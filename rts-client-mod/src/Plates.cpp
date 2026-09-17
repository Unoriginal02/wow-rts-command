#include "Plates.h"

#include <windows.h>
#include <cstring>

#include "CVarChannel.h"
#include "Log.h"
#include "Memory.h"
#include "ObjectManager.h"
#include "Offsets.h"

namespace plates {
namespace {

// How far a nameplate may be from the reference unit, in yards. Our own CVar,
// created by the addon with RegisterCVar -- never a borrowed one, which is the
// lesson `rtsFov` paid for over three stages. 0 means "leave it to the default
// below", so an addon that never writes it still gets the good value.
constexpr const char* kRangeCVar = "rtsPlates";

// 260 yards, and the number is not a taste: the client only ever holds objects
// the server has sent, and the server sends what is near the PLAYER. That
// distance is `Visibility.Distance.Continents`, raised on 2026-09-17 to 250 --
// the core's own ceiling (`MAX_VISIBILITY_DISTANCE`, 250.0f, anything above is
// clamped at startup with an error line). So this covers everything the client
// can possibly know about, and the plate count stays bounded by the same list
// the addon already walks -- widening it further would change nothing.
//
// The stock 41 yards is not wrong, it is just measured for a camera sitting on
// the hero's shoulder. From an RTS camera it covers the middle of the screen
// and leaves the top half bare, which reads as "it is still broken".
constexpr float kDefaultYards = 260.0f;
constexpr float kMinYards = 10.0f;
constexpr float kMaxYards = 1000.0f;

// The slot the patched gate reads its GUID out of. Two instructions in Wow.exe
// point here once the patch is in; nothing else does.
uint64_t g_ref = 0;

bool g_on = false;
uint8_t g_origHi[6] = {0};
uint8_t g_origLo[6] = {0};
float g_origRange = 0.0f;
float g_range = 0.0f;   // what we last wrote, to avoid writing every tick
uint32_t g_lastProbe = 0;
bool g_walked = false;   // the door walk runs once per probe, not once a second

// Rewrites a handful of bytes, after checking that the ones that are there are
// the ones we disassembled. A different client has something else at that
// address, and overwriting bytes of the render walk is not a patch, it is a
// crash. `orig` only holds anything once a `put` has returned true, so the way
// back is never a copy of zeros.
bool WriteBytes(uint32_t addr, const uint8_t* expect, const uint8_t* want,
                uint8_t* orig, size_t len, bool put, const char* what) {
    uint8_t* site = reinterpret_cast<uint8_t*>(addr);
    DWORD prot = 0, ignored = 0;
    if (!VirtualProtect(site, len, PAGE_EXECUTE_READWRITE, &prot)) {
        RTS_LOG("plates: %s (%08X): VirtualProtect failed (%lu)", what, addr,
                GetLastError());
        return false;
    }

    bool ok = false;
    if (put) {
        if (memcmp(site, expect, len) != 0) {
            RTS_LOG("plates: %s (%08X): found %02X %02X ... and expected "
                    "%02X %02X ... -- NOT patching", what, addr, site[0], site[1],
                    expect[0], expect[1]);
        } else {
            memcpy(orig, site, len);
            memcpy(site, want, len);
            ok = true;
        }
    } else {
        memcpy(site, orig, len);
        ok = true;
    }

    VirtualProtect(site, len, prot, &ignored);
    FlushInstructionCache(GetCurrentProcess(), site, len);
    return ok;
}

// mov ecx, [abs32]  /  mov edx, [abs32]. Six bytes each, same length as the two
// `mov reg, [eax+disp32]` they replace, so nothing after them moves.
void BuildLoad(uint8_t* out, uint8_t modrm, const void* addr) {
    out[0] = 0x8B;
    out[1] = modrm;
    uint32_t const a = reinterpret_cast<uint32_t>(addr);
    memcpy(out + 2, &a, 4);
}

void Arm(bool want) {
    if (want == g_on) return;

    if (want) {
        uint8_t hi[6], lo[6];
        BuildLoad(hi, 0x0D, reinterpret_cast<const uint8_t*>(&g_ref) + 4);  // ecx
        BuildLoad(lo, 0x15, &g_ref);                                        // edx

        // ALL THREE OR NONE. A half-applied patch is worse than none at all:
        // the gate would read our high dword and the camera's low one, which is
        // a GUID that belongs to nobody.
        if (!WriteBytes(off::kPlateRefHi, off::kPlateRefHiBytes, hi, g_origHi,
                        6, true, "reference (high)")) {
            return;
        }
        if (!WriteBytes(off::kPlateRefLo, off::kPlateRefLoBytes, lo, g_origLo,
                        6, true, "reference (low)")) {
            WriteBytes(off::kPlateRefHi, nullptr, nullptr, g_origHi, 6, false,
                       "reference (high)");
            return;
        }
        // The ceiling is captured BEFORE it is changed and given back on the way
        // out, same as every CVar the camera touches. An earlier version of that
        // rule was broken once and quietly changed how far normal play could
        // zoom; this is the same shape of mistake one level down.
        float stock = 0.0f;
        if (mem::ReadFloat(off::kPlateRangeSq, &stock)) {
            if (stock != off::kPlateRangeSqStock) {
                RTS_LOG("plates: %08X holds %.1f and 1681.0 was expected -- "
                        "the range stays as it is", off::kPlateRangeSq, stock);
                g_origRange = 0.0f;
            } else {
                g_origRange = stock;
            }
        }

        g_on = true;
        g_range = 0.0f;
        RTS_LOG("plates: gate patched -- the camera has no target, so the "
                "nameplates get the hero as their reference");
        return;
    }

    WriteBytes(off::kPlateRefHi, nullptr, nullptr, g_origHi, 6, false, "reference (high)");
    WriteBytes(off::kPlateRefLo, nullptr, nullptr, g_origLo, 6, false, "reference (low)");
    if (g_origRange > 0.0f) mem::Write<float>(off::kPlateRangeSq, g_origRange);
    g_origRange = 0.0f;
    g_range = 0.0f;
    g_on = false;
    RTS_LOG("plates: gate returned -- the client is measuring from the camera "
            "target again");
}

// Is the camera free? *(kWorldFrameBase) -> +kCameraPtrOffset -> +0x88/0x8C.
// Empty means the client cleared it because we are a spectator, which is the
// one and only state in which the gate refuses every unit.
bool CameraHasNoTarget() {
    uint32_t wf = 0;
    if (!mem::Read<uint32_t>(off::kWorldFrameBase, &wf) || !mem::Plausible(wf)) {
        return false;
    }
    uint32_t cam = 0;
    if (!mem::Deref(wf, off::kCameraPtrOffset, &cam)) return false;

    uint32_t lo = 0, hi = 0;
    if (!mem::Read<uint32_t>(cam + off::kCam_TargetGuid, &lo)) return false;
    if (!mem::Read<uint32_t>(cam + off::kCam_TargetGuid + 4, &hi)) return false;
    return (lo | hi) == 0;
}

// --- THE PROBE -------------------------------------------------------------
//
// The hero still had no bar with the three patches in (seen in game, and the
// log had not one "NOT patching"), and the first probe answered the first half:
// the GATE ITSELF says no for him -- so it is not the drawing, and it is not
// the enumeration. What it could not say is WHICH of its twelve refusals fires,
// and guessing costs one session per guess.
//
// So it does not guess: it asks the gate. Each refusal is a conditional jump to
// the same "return 0", and they are nulled ONE MORE AT A TIME -- first one,
// then the first two -- calling the gate after each. The first time the answer
// turns into a yes, the one just nulled is the door that was shut. Nothing is
// called that the client does not call itself, so there is no calling
// convention to get wrong, and every byte goes back before the function returns.
//
// `rtsPlates = -1` turns it on (`/rts plates probe`), anything else off.
struct Door {
    uint32_t addr;
    uint8_t len;
    const char* what;
};

// In the order the gate asks them. Addresses and lengths read from Wow.exe.
constexpr Door kDoors[] = {
    {0x0072B07A, 2, "state+0x48 <= 0"},
    {0x0072B087, 2, "state+0xD4 bit 25"},
    {0x0072B091, 2, "+0xB8 null"},
    {0x0072B09E, 2, "0x77F0B0: +0xB8 is hidden"},
    {0x0072B0A7, 2, "global 0xAC80A8"},
    {0x0072B0B0, 2, "no camera"},
    {0x0072B127, 6, "state+0x112 bit 1 (enemy path)"},
    {0x0072B13E, 6, "owner flags 0x100000"},
    {0x0072B152, 6, "nameplateShowEnemies off"},
    {0x0072B166, 6, "nameplateShowFriends off"},
    {0x0072B176, 6, "creature type 8"},
    {0x0072B186, 6, "creature type 0xC"},
    {0x0072B1B8, 6, "position test (0x512A30)"},
    {0x0072B21E, 2, "pet/guardian bit 9"},
    {0x0072B2AC, 2, "predicate 0x729740 on a player"},
    {0x0072B2BF, 2, "0x77F0B0 on +0xB8"},
    {0x0072B2D5, 6, "anchor projection (0x715720)"},
    {0x0072B33C, 6, "distance"},
};
constexpr int kDoorCount = sizeof(kDoors) / sizeof(kDoors[0]);

uint8_t g_doorOrig[kDoorCount][6];
bool g_doorOpen[kDoorCount];

bool OpenDoor(int i, bool open) {
    uint8_t* site = reinterpret_cast<uint8_t*>(kDoors[i].addr);
    DWORD prot = 0, ignored = 0;
    if (!VirtualProtect(site, kDoors[i].len, PAGE_EXECUTE_READWRITE, &prot)) return false;
    if (open) {
        memcpy(g_doorOrig[i], site, kDoors[i].len);
        memset(site, 0x90, kDoors[i].len);
    } else {
        memcpy(site, g_doorOrig[i], kDoors[i].len);
    }
    VirtualProtect(site, kDoors[i].len, prot, &ignored);
    FlushInstructionCache(GetCurrentProcess(), site, kDoors[i].len);
    g_doorOpen[i] = open;
    return true;
}

// THE GATE TAKES THREE, AND GETTING THAT WRONG COST A HUNG CLIENT.
//
// It ends in `ret 8`, so it eats TWO stack arguments, and its caller
// (0x0072B350) pushes exactly two: the world frame it was handed and a Vec3 to
// fill. Calling it with one left the stack four bytes short on EVERY call --
// and because the compiler evaluates the call while it is building the
// argument list of the log line, the numbers printed came out shifted and the
// locals underneath were eaten. Two wrong answers and a crash from one missing
// argument, which is why the convention is now written down here:
//
//     bool __thiscall Gate(CGUnit* unit, void* worldFrame, Vec3* outAnchor)
//
// It is also never called from inside an argument list again.
int CallGate(uint32_t addr) {
    uint32_t wf = 0;
    if (!mem::Read<uint32_t>(off::kWorldFrameBase, &wf) || !mem::Plausible(wf)) {
        return -3;
    }
    __try {
        using GateFn = int(__thiscall*)(uint32_t, uint32_t, float*);
        float out[3] = {0.0f, 0.0f, 0.0f};
        return reinterpret_cast<GateFn>(off::kPlateGateFn)(addr, wf, out) ? 1 : 0;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return -2;
    }
}

void ProbeOne(const char* who, uint32_t addr, uint64_t guid) {
    if (!addr) { RTS_LOG("plates: %s -- no object", who); return; }

    uint32_t state = 0, a = 0, b = 0, c = 0, fields = 0, type = 0, owner = 0;
    uint8_t s110 = 0, s112 = 0;
    mem::Read<uint32_t>(addr + 0xD0, &state);
    if (state) {
        mem::Read<uint32_t>(state + 0x48, &a);
        mem::Read<uint32_t>(state + 0xD4, &b);
        mem::Read<uint8_t>(state + 0x110, &s110);
        mem::Read<uint8_t>(state + 0x112, &s112);
    }
    mem::Read<uint32_t>(addr + 0xB8, &c);
    uint8_t hidden = 0;
    if (c) mem::Read<uint8_t>(c + 0x25, &hidden);
    mem::Read<uint32_t>(addr + 0x964, &owner);
    mem::Read<uint32_t>(addr + 0x08, &fields);
    if (fields) mem::Read<uint32_t>(fields + 0x08, &type);

    int const gate = CallGate(addr);
    RTS_LOG("plates: %-4s guid=%08X%08X obj=%08X +0x48=%d +0xD4=%08X +0x110=%02X "
            "+0x112=%02X +0xB8=%08X(hid=%02X) +0x964=%08X type=%08X GATE=%d",
            who, static_cast<uint32_t>(guid >> 32), static_cast<uint32_t>(guid),
            addr, static_cast<int>(a), b, s110, s112, c, hidden, owner, type,
            gate);
}

// One more door at a time until the gate says yes. Everything goes back.
void DoorWalk(uint32_t addr) {
    int opened = -1;
    for (int i = 0; i < kDoorCount; ++i) {
        if (!OpenDoor(i, true)) {
            RTS_LOG("plates: door %d (%08X) could not be opened", i, kDoors[i].addr);
            continue;
        }
        int const r = CallGate(addr);
        RTS_LOG("plates:   ... +%-32s -> GATE=%d", kDoors[i].what, r);
        if (r == 1) { opened = i; break; }
    }

    for (int i = 0; i < kDoorCount; ++i) {
        if (g_doorOpen[i]) OpenDoor(i, false);
    }

    if (opened >= 0) {
        RTS_LOG("plates: THE DOOR IS %08X -- %s", kDoors[opened].addr,
                kDoors[opened].what);
    } else {
        RTS_LOG("plates: none of them -- the refusal is somewhere not listed");
    }
}

void Probe() {
    uint64_t const me = objmgr::LocalGuid();
    if (!me) return;

    uint32_t mine = 0, type = 0;
    if (!objmgr::FindByGuid(me, &mine, &type)) return;

    float x = 0, y = 0, z = 0;
    if (!objmgr::GetPosition(mine, &x, &y, &z, nullptr)) return;

    objmgr::UnitInfo others[8];
    int const n = objmgr::EnumerateNearby(others, 8, x, y, z, 80.0f, false);

    RTS_LOG("plates: --- probe (ref %08X%08X, %d players within 80y) ---",
            static_cast<uint32_t>(g_ref >> 32), static_cast<uint32_t>(g_ref), n);
    ProbeOne("hero", mine, me);

    uint32_t bot = 0;
    for (int i = 0; i < n; ++i) {
        if (others[i].addr == mine || others[i].guid == me) continue;
        bot = others[i].addr;
        ProbeOne("bot", bot, others[i].guid);
        break;
    }
    if (!bot) RTS_LOG("plates: no bot to compare with -- stand next to one");

    // Once per probe. Nineteen gate calls a second would drown the log and the
    // answer does not change while you stand still.
    if (!g_walked) {
        g_walked = true;
        DoorWalk(mine);
    }
}

float WantedRange() {
    int32_t yards = 0;
    if (!cvar::ReadInt(kRangeCVar, &yards) || yards <= 0) {
        return kDefaultYards * kDefaultYards;
    }
    float y = static_cast<float>(yards);
    if (y < kMinYards) y = kMinYards;
    if (y > kMaxYards) y = kMaxYards;
    return y * y;
}

}  // namespace

void Tick() {
    uint64_t const guid = objmgr::LocalGuid();

    // The GUID goes in BEFORE the patch and is refreshed every tick. Patching
    // first would give the gate one frame reading an empty slot, and the slot is
    // what the whole thing hangs off.
    g_ref = guid;

    Arm(guid != 0 && CameraHasNoTarget());
    if (!g_on) return;

    // The probe, off unless someone asks for it by hand. One line a second, and
    // it costs two object lookups -- it is a diagnostic, not a feature.
    int32_t ask = 0;
    if (!cvar::ReadInt(kRangeCVar, &ask) || ask >= 0) g_walked = false;
    if (ask < 0) {
        uint32_t const now = GetTickCount();
        if (now - g_lastProbe > 1000) {
            g_lastProbe = now;
            __try { Probe(); } __except (EXCEPTION_EXECUTE_HANDLER) {
                RTS_LOG("plates: probe faulted");
            }
        }
    }

    // NOT WIDENED UNLESS THE ORIGINAL IS IN HAND. Capturing is what makes
    // giving it back possible, so a capture that failed has to mean "leave the
    // ceiling alone" -- otherwise normal play would keep a 200-yard nameplate
    // range for the rest of the session and nothing would say why.
    if (g_origRange <= 0.0f) return;

    float const want = WantedRange();
    if (want != g_range && mem::Write<float>(off::kPlateRangeSq, want)) {
        g_range = want;
    }
}

void Shutdown() {
    Arm(false);
}

}  // namespace plates
