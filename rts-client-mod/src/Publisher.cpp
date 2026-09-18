#include "Publisher.h"

#include <windows.h>
#include <cstdint>
#include <cstdio>

#include "CVarChannel.h"
#include "Camera.h"
#include "MainThreadHook.h"
#include "Circle.h"
#include "Plates.h"
#include "Steady.h"
#include "SelfShow.h"
#include "CursorRay.h"
#include "Highlight.h"
#include "Log.h"
#include "LuaApi.h"
#include "ObjectManager.h"
#include "Offsets.h"
#include "World.h"

namespace {

// 0.24.0 = no section cut. The version goes UP when something is removed, not
// down: a number that goes backwards would make an addon asking "do you have
// at least 0.23?" believe it is talking to an old DLL, when what has happened
// is that the function no longer exists. You do not go back, you go forward by
// removing.
//
// 0.32.0 = the AFK loop is cut at the client, and the camera stops blinking.
// 0.31.0 = nameplates under the free camera: the gate gets its own reference.
// 0.30.0 = the click ray: cast from the mouse MESSAGE's pixel, at the press.
// 0.28.0 = the DLL writes bit 19: the server cannot carry it set.
// 0.27.0 = "I can attack" comes back armed with the flags: one of the two gates.
// 0.26.0 = the switch that gives "I can attack" back (the bit 19 veto).
// 0.25.0 = the camera's ground is published TWICE, with and without buildings.
constexpr const char* kVersion = "0.32.0";
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
// THE FLOOR DROPS TO 5, AND THERE WERE TWO. The addon already clamped to 20 and
// this one clamped to 20 again on its own, so lowering only the addon's would
// have turned a `/rts cam fov 15` into 20 **without saying a word** -- which is
// exactly the failure mode that change came to remove. Two limits on the same
// number is a limit that gets forgotten.
constexpr float kFovMinDeg = 5.0f;
constexpr float kFovMaxDeg = 140.0f;

// THE SECTION CUT WAS HERE AND LEFT WHOLE ON 2026-09-10.
//
// It moved the near plane (the global `0x00ADEED4`) so the camera would eat
// ceilings and roofs. IT WORKED -- it clipped in game -- and it is dropped all
// the same: what a near plane does is cut THE WHOLE SCENE at a distance, and
// the resulting slice takes half the world with it (look at the 09-10 capture:
// the bottom half of the screen is the void). It is not an architect's section,
// it is a shorter frustum.
//
// AND IT LEFT A DEBT THAT IS THE REAL LESSON: `0 = do not touch` IS NOT OFF.
// With the CVar at 0 the DLL simply stopped writing, so the 15 yards stayed put
// in the global and NOBODY gave them back -- the addon said "cut off" while the
// client went on cutting. A value that says "do not touch" has to come with
// somebody who gives back what was already touched, and here the capture-and-
// restore rule was not applied to the global because it did not look like a
// CVar. Same failure mode as the PLAYER_FLAGS_UBER: the code gets reverted and
// the state stays put.
//
// If the idea ever comes back, what is needed is NOT this: it is hiding object
// by object in the render walk, or a clip plane of our own -- and the client
// uses neither (zero calls to SetClipPlane in the whole .text, checked by
// bytes).

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
//
// ALL FOUR ARE WHITE since 2026-09-18, asked for in game twice -- first *"the
// highlight color for selected heroes be white, not green"* and then, once the
// resting ones were white, *"todo blanco ya sea moviendo, atacando o en
// espera"*. So the glow answers ONE question, WHICH ONES ARE MINE, and answers
// it the same way always.
//
// THE FOUR CODES STAY APART ON PURPOSE. What is the same is the paint, not the
// state: the addon still classifies every order, the wire still carries three
// bits per unit, and `/rts state` still reports them. Collapsing the states
// themselves would be throwing away the machinery that tells them apart, and
// getting it back would mean writing it again -- while giving a state its own
// colour again is this table and nothing else.
struct StateColour { float r, g, b; };
constexpr StateColour kStateColours[kStateMax + 1] = {
    {0.00f, 0.00f, 0.00f},   // none -- never painted
    {1.00f, 1.00f, 1.00f},   // selected
    {1.00f, 1.00f, 1.00f},   // moving
    {1.00f, 1.00f, 1.00f},   // combat
    {1.00f, 1.00f, 1.00f},   // interact
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
bool g_announcedClick = false;
uint32_t g_clickSeq = 0;
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

    // THE GROUND UNDER THE CAMERA, and it goes in the CAMERA tick on purpose.
    //
    // The only ground that was being published (`RTS_GroundZ`) is the one under
    // the CHARACTER, and in an RTS camera the camera spends most of its time
    // where the character is not -- which is exactly when it is needed. The
    // controller consumes it per frame: the height is corrected against the
    // ground of WHERE THE CAMERA IS now, not of where it was 30 ms ago.
    //
    // It starts 5 yd UP because the camera can be below the terrain for an
    // instant while the smoothing lifts it, and a ray that starts inside the
    // ground does not find it. And it goes 1000 down because the height ceiling
    // is set by the player: a short ray stops answering the moment you climb,
    // which reads as the height correction "switching itself off up high".
    //
    // Nobody reads it yet: it is step 2 of `docs/CAMARA-LIBRE.md` §10 and what
    // spends it is FreeCam, which comes next. It goes in now so as not to pay
    // another close-the-client cycle, and it is said here so it does not look
    // like orphan code.
    // THE RAY STARTS AT THE CAMERA (2026-09-12), and before it started five
    // yards higher up. That head start was put in so that a ray beginning INSIDE
    // the ground would still find it, and it cost far more than it was worth:
    // for the five yards after crossing a surface downwards, the ray went on
    // returning THE ONE ABOVE. A blind strip, and precisely the strip you have
    // to go through to get into a cave from the roof: the camera saw the roof of
    // the tube from inside and the addon lifted it back on top of it.
    //
    // Worse still, with the addon's hard floor that was a staircase that builds
    // itself -- it climbs to `ground + clear`, the next frame's ray starts five
    // yards higher, finds rock overhead again -- and it threw the camera out of
    // the mountain in a fraction of a second.
    //
    // Starting at the camera, what gets published is what its name means: the
    // ground that is UNDERNEATH. Never a surface above it.
    constexpr float kCamGroundUp   = 5.0f;
    constexpr float kCamGroundDown = 1000.0f;
    world::Vec3 const gs = {cam.pos[0], cam.pos[1], cam.pos[2]};
    world::Vec3 const ge = {cam.pos[0], cam.pos[1], cam.pos[2] - kCamGroundDown};
    world::Vec3 ghit = {0, 0, 0};
    bool const camGroundHit = world::Raycast(gs, ge, &ghit, nullptr);

    // AND THE SAME RAY AGAIN, WITHOUT THE BUILDINGS.
    //
    // "The first thing underneath" stops being "the ground" as soon as there is
    // something built: bringing the camera up to a house, the first hit is the
    // ROOF, so the height was corrected against the roof and the camera rose by
    // itself -- impossible to get in. A wooden sign did the same on a small
    // scale.
    //
    // BOTH are published and the addon chooses (`/rts fc floor`), instead of
    // changing the one that was already there: the old one is still the right
    // one for flying over without going into anything, and replacing it in
    // silence would have moved the camera's feel without anyone asking for it.
    // It costs one more ray per camera frame, which is the cheap half of the
    // tick.
    world::Vec3 lhit = {0, 0, 0};
    bool const camLandHit = world::RaycastTerrain(gs, ge, &lhit, nullptr);

    // Y LO QUE EL ADELANTO SI COMPRABA, AHORA APARTE: un rayo corto que mira las
    // cinco yardas de ENCIMA de la camara. Sirve para el unico caso que
    // justificaba el adelanto -- el suavizado deja la camara un instante por
    // debajo del terreno, y desde ahi el rayo de abajo ya no encuentra el suelo
    // del que se ha colado -- y ahora es un dato con su propio nombre en vez de
    // una contaminacion del otro. "Tengo suelo debajo" y "tengo roca encima" son
    // dos preguntas distintas y cada una tiene su rayo.
    //
    // Terreno solo a proposito: el tejado de una casa NO debe levantar la camara
    // -- eso era el fallo que `floor 1` vino a arreglar -- pero estar por debajo
    // del terreno del mundo si es una situacion de la que hay que salir.
    world::Vec3 const cs = {cam.pos[0], cam.pos[1], cam.pos[2] + kCamGroundUp};
    world::Vec3 chit = {0, 0, 0};
    bool const camCeilHit = world::RaycastTerrain(cs, gs, &chit, nullptr);

    // 768 se quedo corto al anadir el rayo del techo: con _TRUNCATE, pasarse
    // devuelve -1 y el `if (n <= 0) return;` de abajo tira la publicacion ENTERA
    // en silencio -- la camara dejaria de tener suelo sin decir por que.
    char code[1024];
    int n = _snprintf_s(code, sizeof(code), _TRUNCATE,
        "RTS_HasCam=1;RTS_CamX=%.3f;RTS_CamY=%.3f;RTS_CamZ=%.3f;"
        "RTS_CamFwdX=%.4f;RTS_CamFwdY=%.4f;RTS_CamFwdZ=%.4f;"
        "RTS_CamRightX=%.4f;RTS_CamRightY=%.4f;RTS_CamRightZ=%.4f;"
        "RTS_CamUpX=%.4f;RTS_CamUpY=%.4f;RTS_CamUpZ=%.4f;"
        "RTS_CamFov=%.5f;RTS_CamAspect=%.5f;"
        "RTS_CamGroundHit=%d;RTS_CamGroundZ=%.3f;"
        "RTS_CamLandHit=%d;RTS_CamLandZ=%.3f;"
        "RTS_CamCeilHit=%d;RTS_CamCeilZ=%.3f",
        cam.pos[0], cam.pos[1], cam.pos[2],
        cam.mat[0], cam.mat[1], cam.mat[2],
        cam.mat[3], cam.mat[4], cam.mat[5],
        cam.mat[6], cam.mat[7], cam.mat[8],
        cam.fov, cam.aspect,
        camGroundHit ? 1 : 0, camGroundHit ? ghit.z : 0.0f,
        camLandHit ? 1 : 0, camLandHit ? lhit.z : 0.0f,
        camCeilHit ? 1 : 0, camCeilHit ? chit.z : 0.0f);
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

// WHERE THE PLAYER CLICKED, ANSWERED AT THE CLICK.
//
// The 33 Hz `RTS_Cur*` ray is the wrong tool for an order, for two reasons that
// are both about WHICH cursor and WHICH instant:
//
//   * it is cast from `GetCursorPos`, the WINDOWS cursor. While the client owns
//     the mouse -- which is what a held button does -- the client moves that
//     cursor itself, so the ray goes somewhere nobody aimed. In game that reads
//     as "only a small patch in the middle of the screen works, and clicking
//     further out brings the mark back toward the centre".
//   * it is up to a tick old, and a tick of a panning camera is a long way on
//     the ground.
//
// The mouse MESSAGE has neither problem. It carries the client-area pixel the
// click actually happened at, and it arrives here -- on the main thread, before
// the client has even been handed it -- with the camera still showing the frame
// the player was looking at when they pressed. So the ray is cast from that
// pixel, then and there, and published under a sequence number. The addon's
// OnMouseDown runs afterwards by construction and reads the answer to its own
// press.
//
// THE RAY IS PUBLISHED TOO, not only the point. The server has the map and is
// the authority on the ground; asking it with THIS ray -- rather than with one
// Lua rebuilds from its own fov, aspect and calibration -- makes the two sides
// answer the same question. Where they then differ is real terrain
// disagreement, not a projection mismatch.
void PublishClick(int button, int px, int py) {
    if (!lua::StateReady()) return;

    HWND hwnd = static_cast<HWND>(mainthread::Window());
    if (!hwnd) return;

    RECT rc;
    if (!GetClientRect(hwnd, &rc)) return;

    cursorray::Shot shot;
    bool ok = false;
    __try {
        camera::Camera cam;
        if (camera::Get(&cam)) {
            ok = cursorray::At(cam, static_cast<float>(px), static_cast<float>(py),
                               static_cast<float>(rc.right - rc.left),
                               static_cast<float>(rc.bottom - rc.top), &shot);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        ok = false;
    }
    if (!ok) return;

    // The sequence is what lets the addon tell "this press was seen" from "this
    // press was not". A client that does not deliver mouse input through the
    // window procedure simply never advances it, and the addon falls back to the
    // path it had before -- so the worst case is today's behaviour, not a
    // broken one.
    ++g_clickSeq;

    char code[512];
    int n = _snprintf_s(code, sizeof(code), _TRUNCATE,
        "RTS_ClkSeq=%u;RTS_ClkBtn=%d;RTS_ClkPx=%d;RTS_ClkPy=%d;RTS_ClkHit=%d;"
        "RTS_ClkX=%.3f;RTS_ClkY=%.3f;RTS_ClkZ=%.3f;"
        "RTS_ClkOX=%.3f;RTS_ClkOY=%.3f;RTS_ClkOZ=%.3f;"
        "RTS_ClkDX=%.5f;RTS_ClkDY=%.5f;RTS_ClkDZ=%.5f",
        g_clickSeq, button, px, py, shot.hitOk ? 1 : 0,
        shot.hit.x, shot.hit.y, shot.hit.z,
        shot.origin.x, shot.origin.y, shot.origin.z,
        shot.dir.x, shot.dir.y, shot.dir.z);
    if (n <= 0) return;

    __try {
        lua::Execute(code);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return;
    }

    if (!g_announcedClick) {
        g_announcedClick = true;
        RTS_LOG("first click published (btn=%d at %d,%d hit=%d) -- "
                "mouse messages do reach the WndProc", button, px, py,
                shot.hitOk ? 1 : 0);
    }
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

    // Los rotulos del cliente: la barra de la V y la de los amigos. Se arma
    // solo cuando la camara se queda sin unidad -- o sea, en modo RTS -- y se
    // devuelve solo al salir. Ver Plates.h.
    __try {
        plates::Tick();
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        RTS_LOG("plates: tick faulted -- rotulos sin tocar este tick");
    }

    // El AFK en bucle y la camara que lo acompañaba. Se arma con el bit 22 y se
    // devuelve al salir del modo RTS. Ver Steady.h.
    __try {
        steady::Tick();
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        RTS_LOG("steady: tick faulted -- sin tocar nada este tick");
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
