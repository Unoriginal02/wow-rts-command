#include "Publisher.h"

#include <windows.h>
#include <cstdint>
#include <cstdio>

#include "CVarChannel.h"
#include "Camera.h"
#include "Circle.h"
#include "SelfShow.h"
#include "CursorRay.h"
#include "Highlight.h"
#include "Log.h"
#include "LuaApi.h"
#include "ObjectManager.h"
#include "Offsets.h"
#include "World.h"

namespace {

// 0.24.0 = sin corte seccional. La version SUBE al quitarlo, no baja: un
// numero que retrocede haria que un addon que pregunta "¿tienes al menos
// 0.23?" creyera que habla con un DLL viejo, cuando lo que pasa es que la
// funcion ya no existe. Hacia atras no se vuelve, se avanza quitando.
constexpr const char* kVersion = "0.24.0";
constexpr int kProtocol = 3;

// Every published unit costs ~110 bytes of Lua source that the client parses on
// every tick, so this is a real budget rather than an arbitrary cap.
//
// RAISED 2026-08-16 from 16 units at 60 yards, which was the reason a distant
// enemy could not be ordered attacked: RTSMode picks hostiles out of THIS list,
// so anything unpublished is unclickable no matter how plainly it is on screen.
// 60 yards was simply too short -- this server runs Visibility.Distance
// Continents = 100 and Instances = 170, so the client knows about units far
// beyond what was being forwarded.
//
// 180 yards covers the instance case with room to spare; nothing past the
// server's visibility distance is in the object manager to find, so a generous
// range costs only the walk, not the payload. The COUNT is what costs: 32 units
// at ~105 bytes is ~3.4 KB of the 8 KB buffer, which leaves comfortable headroom
// for the header, and the emit loop guards the buffer end anyway.
constexpr int   kPublishedUnits = 32;
constexpr float kPublishRange   = 180.0f;

// The CVar the addon answers through. Hijacking an existing one avoids having to
// register our own; this is a PvP AFK-notification toggle, which is meaningless
// on a private server with no PvP, and the addon restores it on logout.
constexpr const char* kSelectionCVar = "enablePVPNotifyAFK";

// A SECOND borrowed CVar, for the one thing the packed selection channel cannot
// carry: a number. That channel is a bitfield with two spare bits, which is an
// index at best, and field of view wants tuning by eye rather than choosing from
// four presets baked into a build.
//
// guildMemberNotify is a guild-roster login toast -- inert on a solo server, and
// an integer, which is all this needs. Value is FOV in TENTHS OF A DEGREE
// (600 = 60.0 deg) so it stays a whole number; 0 means "leave the client's".
constexpr const char* kFovCVar = "rtsFov";
// EL SUELO BAJA A 5, Y HABIA DOS. El addon ya acotaba a 20 y este acotaba otra
// vez a 20 por su cuenta, asi que bajar solo el del addon habria dejado un
// `/rts cam fov 15` convertido en 20 **sin decir nada** -- que es exactamente el
// modo de fallo que ese cambio venia a quitar. Dos topes para el mismo numero es
// un tope que se olvida.
constexpr float kFovMinDeg = 5.0f;
constexpr float kFovMaxDeg = 140.0f;

// EL CORTE SECCIONAL ESTUVO AQUI Y SE FUE ENTERO EL 2026-09-10.
//
// Movia el plano cercano (el global `0x00ADEED4`) para que la camara se comiera
// techos y tejados. FUNCIONABA -- recorto en juego -- y aun asi se descarta: lo
// que un plano cercano hace es cortar TODA la escena a una distancia, y el tajo
// resultante se lleva por delante medio mundo (mira la captura del 09-10: la
// mitad de abajo de la pantalla es el vacio). No es un corte de arquitecto, es
// un frustum mas corto.
//
// Y DEJO UNA DEUDA QUE ES LA LECCION DE VERDAD: `0 = no tocar` NO ES APAGAR.
// Con el CVar a 0 el DLL simplemente dejaba de escribir, asi que las 15 yardas
// se quedaban puestas en el global y NADIE las devolvia -- el addon decia
// "corte apagado" mientras el cliente seguia cortando. Un valor que dice "no
// toques" tiene que venir con quien devuelva lo que ya se toco, y aqui la regla
// de capturar y devolver no se aplico al global porque no parecia un CVar.
// Mismo modo de fallo que los PLAYER_FLAGS_UBER: el codigo se revierte y el
// estado se queda puesto.
//
// Si algun dia vuelve la idea, lo que hace falta NO es esto: es esconder objeto
// por objeto en el recorrido de render, o un plano de recorte propio -- y el
// cliente no usa ninguno (cero llamadas a SetClipPlane en todo el .text,
// comprobado por bytes).

void ApplyFovOverride() {
    int32_t tenths = 0;
    if (!cvar::ReadInt(kFovCVar, &tenths) || tenths <= 0) return;

    float deg = static_cast<float>(tenths) / 10.0f;
    if (deg < kFovMinDeg) deg = kFovMinDeg;
    if (deg > kFovMaxDeg) deg = kFovMaxDeg;

    camera::SetFov(deg * 3.14159265358979f / 180.0f);
}

// --- the selection-state channel (protocol 2) ----------------------------
//
// The addon packs one CVar as:
//     value = (seq << 27) | (state[8] << 24) | ... | (state[0] << 0)
// three bits per PLAYER slot, nine slots, plus a three-bit sequence number --
// 30 bits, which is the budget: the client parses the CVar with a SIGNED atoi,
// so the whole value has to stay under 2^31.
//
// Slot k is the k-th PLAYER in the published list. Creatures do not take a slot;
// they can never be selected, and spending three bits on each of them would have
// cost exactly the states we need.
//
// WHY A SEQUENCE NUMBER RATHER THAN A HASH OF THE LIST. Protocol 1 stamped each
// published list with a hash of its guids and threw the entire reply away when
// the stamp did not match. That is what made the tint blink. The list is sorted
// nearest-first, so any two bots swapping distance re-stamped it; the addon's
// reply -- always a tick old -- no longer matched, the mask was dropped, every
// unit was cleared, and the tint reappeared a frame or two later. Constantly,
// because bots move.
//
// Now the DLL remembers the last eight lists it published and the reply names
// which one it was computed against. Slot k resolves to a GUID from THAT list,
// and the guid is matched by identity against the list being published now. A
// late reply is no longer wrong, just slightly stale, so nothing is ever
// dropped and the tint never blinks.
// PROTOCOL 3 (2026-08-15). The native ground circle needed a gate bit of its
// own and protocol 2 had none free: states filled bits 0..26, the sequence
// number took 27..29, and bit 30 was already the model glow. Dropping one state
// slot -- nine to eight, when the party this was built for is at most five --
// buys three bits at the top and costs nothing real:
//
//     bits  0..23  eight slots x three bits of state
//     bits 24..26  sequence number (ring of 8, unchanged tolerance)
//     bit  27      draw the native ground circle
//     bit  28      also glow the unit models
//     bits 29,30   free
//     bit  31      unusable -- the client parses the CVar with a SIGNED atoi
//
// Both sides check kProtocol before decoding, so a half-updated install answers
// with nothing rather than with garbage.
constexpr int kStateSlots = 8;
constexpr int kStateBits  = 3;
constexpr int kSeqRing    = 8;
constexpr int kSeqShift   = kStateSlots * kStateBits;   // 24

constexpr uint32_t kBitCircle = 1u << 27;
constexpr uint32_t kBitTint   = 1u << 28;
constexpr uint32_t kBitAll    = 1u << 29;   // diagnostic: circle on EVERY unit

// Bit 30 is FREE. It briefly meant "draw each of our circles twice"; that gives
// two rings, not one heavier one, so it is gone from both sides -- see Circle.h.
// Bit 31 is unusable: the client parses the CVar with a signed atoi.

enum TintState : uint32_t {
    kStateNone     = 0,
    kStateSelected = 1,   // blue   -- selected, standing by
    kStateMoving   = 2,   // green  -- walking to an ordered point
    kStateCombat   = 3,   // red    -- sent to fight, or fighting
    kStateInteract = 4,   // orange -- interacting
    kStateMax      = 4,
};

// Indexed by TintState. The client's own highlight colour is RGB(78,78,95),
// dark enough to pass for nothing at all, so every one of these is written over
// it after the call -- see Highlight.cpp.
struct StateColour { float r, g, b; };
constexpr StateColour kStateColours[kStateMax + 1] = {
    {0.00f, 0.00f, 0.00f},   // none -- never painted
    {0.15f, 0.45f, 1.00f},   // selected
    {0.10f, 1.00f, 0.25f},   // moving
    {1.00f, 0.10f, 0.10f},   // combat
    {1.00f, 0.55f, 0.05f},   // interact
};

// Reason 2, which the client itself never uses. Reason 0 is the client's OWN
// target highlight, and the highlight reset at 0x00513CF0 -- which re-runs on
// any CVar change, including the twenty-a-second this very channel writes --
// clears reasons 0 and 1. Sitting on reason 2 takes the tint out of that fight
// completely. The client declines to write the intensity for a reason-2-only
// unit (see Offsets.h); ForceColour writes it for us, so nothing is lost.
constexpr uint32_t kTintReason = off::kHighlightReasonFree;

// The player guids published under each sequence number, so a reply that lands
// one or two ticks late still resolves to the units the addon meant.
struct PublishedPlayers {
    int count;
    uint64_t guid[kStateSlots];
};
PublishedPlayers g_ring[kSeqRing] = {};
uint32_t g_seq = 0;

// Nearest-first is the right rule for deciding WHICH units to publish and the
// wrong one for numbering them: two bots swapping distance renumbered the whole
// list, so the addon's reply changed every time anyone moved and the channel
// never went quiet. Sorted by guid, the indices only move when the SET changes.
// Insertion sort -- the list is at most sixteen long.
void SortByGuid(objmgr::UnitInfo* units, int count) {
    for (int i = 1; i < count; ++i) {
        objmgr::UnitInfo key = units[i];
        int j = i - 1;
        while (j >= 0 && units[j].guid > key.guid) {
            units[j + 1] = units[j];
            --j;
        }
        units[j + 1] = key;
    }
}

uint32_t g_heartbeat = 0;
bool g_announced = false;
bool g_loggedCamera = false;

struct Snapshot {
    bool hasPos = false;
    float x = 0, y = 0, z = 0, f = 0;
    int count = 0;

    bool groundHit = false;
    float groundZ = 0.f;

    bool hasCam = false;
    float camX = 0, camY = 0, camZ = 0;
    float fwd[3] = {0, 0, 0};
    float right[3] = {0, 0, 0};
    float up[3] = {0, 0, 0};
    float fov = 0, aspect = 0;

    bool lookHit = false;
    float lookX = 0, lookY = 0, lookZ = 0;

    bool curHit = false;
    float curX = 0, curY = 0, curZ = 0;
};

int BuildCode(char* buf, size_t cap, const Snapshot& s) {
    if (!s.hasPos && !s.hasCam) {
        return _snprintf_s(buf, cap, _TRUNCATE,
            "RTS_Ready=1;RTS_Version='%s';RTS_HB=%u;RTS_HasPos=0",
            kVersion, g_heartbeat);
    }
    return _snprintf_s(buf, cap, _TRUNCATE,
        "RTS_Ready=1;RTS_Version='%s';RTS_HB=%u;"
        "RTS_HasPos=%d;RTS_PX=%.3f;RTS_PY=%.3f;RTS_PZ=%.3f;RTS_PF=%.3f;RTS_N=%d;"
        "RTS_GroundHit=%d;RTS_GroundZ=%.3f;"
        "RTS_HasCam=%d;RTS_CamX=%.3f;RTS_CamY=%.3f;RTS_CamZ=%.3f;"
        "RTS_CamFwdX=%.4f;RTS_CamFwdY=%.4f;RTS_CamFwdZ=%.4f;"
        "RTS_CamRightX=%.4f;RTS_CamRightY=%.4f;RTS_CamRightZ=%.4f;"
        "RTS_CamUpX=%.4f;RTS_CamUpY=%.4f;RTS_CamUpZ=%.4f;"
        "RTS_CamFov=%.5f;RTS_CamAspect=%.5f;"
        "RTS_LookHit=%d;RTS_LookX=%.3f;RTS_LookY=%.3f;RTS_LookZ=%.3f;"
        "RTS_CurHit=%d;RTS_CurX=%.3f;RTS_CurY=%.3f;RTS_CurZ=%.3f",
        kVersion, g_heartbeat,
        s.hasPos ? 1 : 0, s.x, s.y, s.z, s.f, s.count,
        s.groundHit ? 1 : 0, s.groundZ,
        s.hasCam ? 1 : 0, s.camX, s.camY, s.camZ,
        s.fwd[0], s.fwd[1], s.fwd[2],
        s.right[0], s.right[1], s.right[2],
        s.up[0], s.up[1], s.up[2],
        s.fov, s.aspect,
        s.lookHit ? 1 : 0, s.lookX, s.lookY, s.lookZ,
        s.curHit ? 1 : 0, s.curX, s.curY, s.curZ);
}

// Camera only, and nothing else: no object walk, no raycasts, no unit list. A
// marker is drawn at a screen pixel derived from the camera, so a camera that is
// one 33 ms tick stale drags every marker sideways while you turn -- at a normal
// turn rate that is over a hundred pixels, which reads as "the icons lag behind
// the world". This path is cheap enough to run every frame, which is what fixes
// it; the expensive half stays at 30 Hz because unit positions do not need more.
void PublishCameraOnly() {
    camera::Camera cam;
    __try {
        // BEFORE reading it back, so what gets published is the fov actually in
        // effect this frame and the addon's derived projection scales match what
        // the GPU drew with.
        ApplyFovOverride();
        if (!camera::Get(&cam)) return;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return;
    }

    // EL SUELO BAJO LA CAMARA, y va en el tick de CAMARA a proposito.
    //
    // El unico suelo que se publicaba (`RTS_GroundZ`) esta bajo el PERSONAJE, y
    // en una camara RTS la camara pasa la mayor parte del tiempo donde el
    // personaje no esta -- que es justo cuando hace falta. El controlador lo
    // consume por frame: la altura se corrige contra el suelo de DONDE ESTA la
    // camara ahora, no de donde estaba hace 30 ms.
    //
    // Empieza 5 yd ARRIBA porque la camara puede estar por debajo del terreno un
    // instante mientras el suavizado la sube, y un rayo que arranca dentro del
    // suelo no lo encuentra. Y baja 1000 porque el techo de altura lo pone el
    // jugador: un rayo corto deja de contestar justo al subir, lo que se ve como
    // que la correccion de altura "se apaga sola a cierta altura".
    //
    // Todavia no lo lee nadie: es el paso 2 de `docs/CAMARA-LIBRE.md` §10 y lo
    // gasta FreeCam, que viene detras. Va ahora para no pagar otro ciclo de
    // cerrar el cliente, y se dice aqui para que no parezca codigo huerfano.
    constexpr float kCamGroundUp   = 5.0f;
    constexpr float kCamGroundDown = 1000.0f;
    world::Vec3 const gs = {cam.pos[0], cam.pos[1], cam.pos[2] + kCamGroundUp};
    world::Vec3 const ge = {cam.pos[0], cam.pos[1], cam.pos[2] - kCamGroundDown};
    world::Vec3 ghit = {0, 0, 0};
    bool const camGroundHit = world::Raycast(gs, ge, &ghit, nullptr);

    char code[640];
    int n = _snprintf_s(code, sizeof(code), _TRUNCATE,
        "RTS_HasCam=1;RTS_CamX=%.3f;RTS_CamY=%.3f;RTS_CamZ=%.3f;"
        "RTS_CamFwdX=%.4f;RTS_CamFwdY=%.4f;RTS_CamFwdZ=%.4f;"
        "RTS_CamRightX=%.4f;RTS_CamRightY=%.4f;RTS_CamRightZ=%.4f;"
        "RTS_CamUpX=%.4f;RTS_CamUpY=%.4f;RTS_CamUpZ=%.4f;"
        "RTS_CamFov=%.5f;RTS_CamAspect=%.5f;"
        "RTS_CamGroundHit=%d;RTS_CamGroundZ=%.3f",
        cam.pos[0], cam.pos[1], cam.pos[2],
        cam.mat[0], cam.mat[1], cam.mat[2],
        cam.mat[3], cam.mat[4], cam.mat[5],
        cam.mat[6], cam.mat[7], cam.mat[8],
        cam.fov, cam.aspect,
        camGroundHit ? 1 : 0, camGroundHit ? ghit.z : 0.0f);
    if (n <= 0) return;

    __try {
        lua::Execute(code);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
    }
}

}  // namespace

namespace publisher {

void PublishCamera() {
    if (!lua::StateReady()) return;
    PublishCameraOnly();
}

void Publish() {
    if (!lua::StateReady()) return;
    ++g_heartbeat;

    // Patched from HERE and not from the inject thread, on purpose. The sixteen
    // bytes being rewritten sit inside the client's render walk; this runs on
    // the client's main thread, which is the thread that executes them, so it
    // cannot land mid-instruction. Install() is a no-op after the first call.
    __try {
        circle::Install();
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        RTS_LOG("circle: install faulted -- ground circles unavailable");
    }

    // La sonda del cuerpo. Inerte mientras su CVar valga 0, que es de fabrica.
    __try {
        selfshow::Tick();
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        RTS_LOG("body: tick faulted -- sonda desactivada este tick");
    }

    // Virtual-vs-raw position check. This used to run once a SECOND, forever,
    // and was single-handedly responsible for a 12 MB log -- 135,000 lines of a
    // question that was answered months ago and has been quietly re-answered
    // 30 times a minute ever since. It still runs a few times after injection,
    // because "positions are sane" is worth confirming on a client that might
    // have been patched or swapped, and then it stops.
    if (g_heartbeat <= 150 && g_heartbeat % 30 == 0) {
        __try { objmgr::DiagPositions(); } __except (EXCEPTION_EXECUTE_HANDLER) {}
    }

    Snapshot s;
    __try {
        s.hasPos = objmgr::GetLocalPlayerPosition(&s.x, &s.y, &s.z, &s.f);
        if (s.hasPos) {
            s.count = objmgr::CountObjects();

            // Downward raycast self-test (ground under our feet ~= player Z).
            world::Vec3 ds = {s.x, s.y, s.z + 5.0f};
            world::Vec3 de = {s.x, s.y, s.z - 15.0f};
            world::Vec3 dhit;
            s.groundHit = world::Raycast(ds, de, &dhit, nullptr);
            if (s.groundHit) s.groundZ = dhit.z;
        }

        // Camera + look-at ground point (screen-centre raycast).
        camera::Camera cam;
        if (camera::Get(&cam)) {
            s.hasCam = true;
            s.camX = cam.pos[0];
            s.camY = cam.pos[1];
            s.camZ = cam.pos[2];
            // Rows confirmed from the log: row0=forward, row1=right, row2=up.
            for (int i = 0; i < 3; ++i) {
                s.fwd[i]   = cam.mat[0 + i];
                s.right[i] = cam.mat[3 + i];
                s.up[i]    = cam.mat[6 + i];
            }
            s.fov = cam.fov;
            s.aspect = cam.aspect;

            // Row 0 assumed forward; validated against the log dump below.
            world::Vec3 ls = {cam.pos[0], cam.pos[1], cam.pos[2]};
            world::Vec3 le = {cam.pos[0] + cam.mat[0] * 300.0f,
                              cam.pos[1] + cam.mat[1] * 300.0f,
                              cam.pos[2] + cam.mat[2] * 300.0f};
            world::Vec3 lhit;
            s.lookHit = world::Raycast(ls, le, &lhit, nullptr);
            if (s.lookHit) {
                s.lookX = lhit.x;
                s.lookY = lhit.y;
                s.lookZ = lhit.z;
            }

            // Where the MOUSE is pointing, which is what an order actually
            // needs. The addon's flat-plane fallback is pinned to the player's
            // Z, and the detached camera can now be a long way from the player.
            world::Vec3 chit;
            s.curHit = cursorray::Get(cam, &chit);
            if (s.curHit) {
                s.curX = chit.x;
                s.curY = chit.y;
                s.curZ = chit.z;
            }

            // One-time dump so the matrix convention can be nailed from a single
            // in-game test instead of guess-and-rebuild.
            if (!g_loggedCamera) {
                g_loggedCamera = true;
                RTS_LOG("camera pos = %.3f, %.3f, %.3f  fov=%.4f aspect=%.4f",
                        cam.pos[0], cam.pos[1], cam.pos[2], cam.fov, cam.aspect);
                RTS_LOG("camera mat row0 = %.4f, %.4f, %.4f", cam.mat[0], cam.mat[1], cam.mat[2]);
                RTS_LOG("camera mat row1 = %.4f, %.4f, %.4f", cam.mat[3], cam.mat[4], cam.mat[5]);
                RTS_LOG("camera mat row2 = %.4f, %.4f, %.4f", cam.mat[6], cam.mat[7], cam.mat[8]);
                camera::DumpStruct();
            }
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        // leave whatever was gathered before the fault
    }

    // Rings add roughly 100 bytes per selected unit on top of the unit list, so
    // 4096 no longer leaves comfortable headroom.
    char code[8192];
    int n = BuildCode(code, sizeof(code), s);
    if (n <= 0) return;

    // Append nearby units -- bots, you, and creatures -- so the addon can put a
    // marker over each one. Nearest first, so a crowded camp drops the far ones.
    if (s.hasPos) {
        objmgr::UnitInfo units[kPublishedUnits];
        int uc = 0;

        // Centred on the CAMERA, not on the player. In normal play the camera
        // sits just behind your character and the two give the same list. With
        // the detached RTS camera they do not: flying away from your character
        // silently stopped publishing the very units you had flown over to look
        // at, so their markers and tints vanished. What is on screen is what
        // the addon needs to know about.
        float ex = s.x, ey = s.y, ez = s.z;
        if (s.hasCam) {
            ex = s.camX;
            ey = s.camY;
            ez = s.camZ;
        }

        __try {
            uc = objmgr::EnumerateNearby(units, kPublishedUnits, ex, ey, ez,
                                         kPublishRange, true);
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            uc = 0;
        }

        SortByGuid(units, uc);

        // Record the players of THIS list under a fresh sequence number, so the
        // reply the addon computes from it can be resolved even a few ticks
        // later. Same walk the addon does: published order, players only.
        g_seq = (g_seq + 1) % kSeqRing;
        PublishedPlayers& cur = g_ring[g_seq];
        cur.count = 0;
        for (int i = 0; i < uc && cur.count < kStateSlots; ++i) {
            if (units[i].type == off::kTypePlayer) cur.guid[cur.count++] = units[i].guid;
        }

        // Decode the addon's answer and turn it into one colour per unit.
        int32_t reply = 0;
        highlight::Tint tints[kStateSlots];
        int tintCount = 0;

        // The same units again as guid + packed colour, for the native ground
        // circle. Selection is already known at this point, so the circle costs
        // one more array and no extra round trip.
        circle::Entry circles[kStateSlots];
        int circleCount = 0;

        bool const haveReply = cvar::ReadInt(kSelectionCVar, &reply) && reply > 0;
        uint32_t const v = haveReply ? static_cast<uint32_t>(reply) : 0u;

        bool const wantTint   = (v & kBitTint) != 0;
        bool const wantCircle = (v & kBitCircle) != 0;

        // Bit 29 puts a circle under EVERY published unit rather than only the
        // selected ones, which answers "is the hook drawing at all?" without
        // needing a selection to exist. Read OUTSIDE the haveReply guard,
        // because zero is a legitimate packed value -- nothing selected, all
        // flags off, sequence zero -- and treating it as "no answer" would latch
        // the diagnostic on with no way to switch it off.
        bool const showAll = (v & kBitAll) != 0;
        if (showAll) {
            for (int i = 0; i < uc && circleCount < kStateSlots; ++i) {
                circles[circleCount].guid = units[i].guid;
                circles[circleCount].colour = 0;
                ++circleCount;
            }
        }

        if (haveReply && !showAll) {
            const PublishedPlayers& src = g_ring[(v >> kSeqShift) & (kSeqRing - 1)];

            for (int k = 0; k < src.count; ++k) {
                uint32_t st = (v >> (k * kStateBits)) & 0x7u;
                if (st == kStateNone || st > kStateMax) continue;

                // Slot -> guid against the list the ADDON saw; guid -> address
                // against the list being published NOW. This is the whole fix:
                // identity survives reordering, an index does not.
                for (int i = 0; i < uc; ++i) {
                    if (units[i].guid != src.guid[k]) continue;
                    if (units[i].type != off::kTypePlayer) break;
                    tints[tintCount].addr = units[i].addr;
                    tints[tintCount].r = kStateColours[st].r;
                    tints[tintCount].g = kStateColours[st].g;
                    tints[tintCount].b = kStateColours[st].b;
                    ++tintCount;

                    circles[circleCount].guid = units[i].guid;
                    circles[circleCount].colour = circle::Pack(kStateColours[st].r,
                                                               kStateColours[st].g,
                                                               kStateColours[st].b);
                    ++circleCount;
                    break;
                }
            }
        }

        // The selection is decoded either way; only the painting is skipped.
        // Passing zero also CLEARS anything lit by a previous tick, so switching
        // the glow off takes effect at once.
        __try {
            highlight::Apply(tints, wantTint ? tintCount : 0, kTintReason);
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            RTS_LOG("highlight pass faulted -- tinting disabled for this tick");
        }

        // Same for the circle: an empty table is read by the very next frame the
        // client draws, so turning it off is immediate. Nothing here touches the
        // client -- the table is ours, and the renderer only reads it.
        circle::Set(circles, (wantCircle || showAll) ? circleCount : 0);

        {
            int w2 = _snprintf_s(code + n, sizeof(code) - n, _TRUNCATE,
                                 ";RTS_PROTO=%d;RTS_UGEN=%u", kProtocol, g_seq);
            if (w2 > 0) n += w2;
        }

        for (int i = 0; i < uc && n < static_cast<int>(sizeof(code)) - 128; ++i) {
            int w = _snprintf_s(code + n, sizeof(code) - n, _TRUNCATE,
                ";RTS_U%dG='0x%016llX';RTS_U%dX=%.2f;RTS_U%dY=%.2f;RTS_U%dZ=%.2f;RTS_U%dT=%u",
                i + 1, static_cast<unsigned long long>(units[i].guid),
                i + 1, units[i].x, i + 1, units[i].y, i + 1, units[i].z,
                i + 1, units[i].type);
            if (w <= 0) break;
            n += w;
        }
        int w = _snprintf_s(code + n, sizeof(code) - n, _TRUNCATE, ";RTS_UN=%d", uc);
        if (w > 0) n += w;

        // The terrain-sampled ring in GroundRing.cpp stays uncalled, and is now
        // unlikely ever to be called again: the native circle drapes itself over
        // terrain because the client draws it as part of the scene, which is the
        // whole problem those twelve downward raycasts per unit per tick existed
        // to solve by hand.

    } else {
        // No player position means no unit list, so nothing can be resolved --
        // drop every tint and every circle rather than leaving the last
        // selection marked through a zone change or a logout.
        __try {
            highlight::Apply(nullptr, 0, kTintReason);
        } __except (EXCEPTION_EXECUTE_HANDLER) {
        }
        circle::Set(nullptr, 0);
        int w = _snprintf_s(code + n, sizeof(code) - n, _TRUNCATE,
                            ";RTS_PROTO=%d;RTS_UN=0", kProtocol);
        if (w > 0) n += w;
    }

    __try {
        lua::Execute(code);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        RTS_LOG("FrameScript_Execute faulted -- stopping further publishes");
        return;
    }

    if (!g_announced) {
        g_announced = true;
        RTS_LOG("first publish ok (hasPos=%d hasCam=%d)", s.hasPos ? 1 : 0, s.hasCam ? 1 : 0);
    }
}

}  // namespace publisher
