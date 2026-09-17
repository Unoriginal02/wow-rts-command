#include "Steady.h"

#include <windows.h>
#include <cstring>

#include "Log.h"
#include "Memory.h"
#include "ObjectManager.h"
#include "Offsets.h"

namespace steady {
namespace {

bool g_camForced = false;
uint8_t g_camOrig[5] = {0};
bool g_announced = false;

// PLAYER_FLAGS where the client's own predicate READS them: a second block of
// CGPlayer_C (+0x1008), not the ordinary descriptor array. Written by the
// server on every update of the field, which is the whole problem below.
bool PlayerFlags(uint32_t* out) {
    uint64_t const guid = objmgr::LocalGuid();
    if (!guid) return false;

    uint32_t addr = 0, type = 0;
    if (!objmgr::FindByGuid(guid, &addr, &type)) return false;

    uint32_t fields = 0;
    if (!mem::Deref(addr, off::kPlayer_FieldsPtr, &fields)) return false;

    return mem::Read<uint32_t>(fields + off::kPlayerFields_Flags, out);
}

// "You have just done something." The client's clock is not GetTickCount and
// not timeGetTime: it is a scaled performance counter with an origin of its own
// (0x0086ADC0), so the value has to come from the client or the comparison it
// feeds is meaningless. It takes no arguments and answers in eax.
bool TouchInput() {
    using ClockFn = uint32_t(__cdecl*)();
    __try {
        uint32_t const now = reinterpret_cast<ClockFn>(off::kClientTimeMs)();
        return mem::Write<uint32_t>(off::kIdleInputStamp, now);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

// `call rel32` -> `mov al, 1` + three nops. Five bytes for five bytes, so
// nothing moves, and the signature is checked before anything is written: if
// there is not a call to the spectator predicate at that address, this is a
// client we do not know and the right thing to do is nothing.
void ForceCamSpectator(bool want) {
    if (want == g_camForced) return;

    uint8_t* site = reinterpret_cast<uint8_t*>(off::kCamSpecCall);
    DWORD prot = 0, ignored = 0;
    if (!VirtualProtect(site, 5, PAGE_EXECUTE_READWRITE, &prot)) {
        RTS_LOG("steady: VirtualProtect on %08X failed (%lu)", off::kCamSpecCall,
                GetLastError());
        return;
    }

    if (want) {
        uint32_t const dest = off::kCamSpecCall + 5 +
                              *reinterpret_cast<int32_t*>(site + 1);
        if (site[0] != 0xE8 || dest != off::kIsSpectator) {
            RTS_LOG("steady: %08X is not a call to %08X (%02X, goes to %08X)"
                    " -- NOT patching", off::kCamSpecCall, off::kIsSpectator,
                    site[0], dest);
            VirtualProtect(site, 5, prot, &ignored);
            return;
        }
        memcpy(g_camOrig, site, 5);
        site[0] = 0xB0;  // mov al, 1
        site[1] = 0x01;
        site[2] = 0x90;
        site[3] = 0x90;
        site[4] = 0x90;
        g_camForced = true;
        RTS_LOG("steady: the camera stops asking whether you are a spectator -- "
                "a PLAYER_FLAGS update can no longer pull it back");
    } else {
        memcpy(site, g_camOrig, 5);
        g_camForced = false;
        RTS_LOG("steady: the camera asks the predicate again");
    }

    VirtualProtect(site, 5, prot, &ignored);
    FlushInstructionCache(GetCurrentProcess(), site, 5);
}

}  // namespace

void Tick() {
    uint32_t flags = 0;
    if (!PlayerFlags(&flags)) {
        // No player to read: the world is not up, or it is going down. A patch
        // that stays in because we could not read is a patch that outlives its
        // reason, which is the one thing this project keeps paying for.
        ForceCamSpectator(false);
        return;
    }

    bool const rts = (flags & off::kPlayerFlagCommentator) != 0;
    ForceCamSpectator(rts);
    if (!rts) {
        g_announced = false;
        return;
    }

    // Every tick, and it costs one dword. Writing it only when the five minutes
    // are nearly up would mean knowing the client's clock origin AND trusting
    // our own tick to land inside that window; this cannot be late.
    if (TouchInput() && !g_announced) {
        g_announced = true;
        RTS_LOG("steady: the idle stamp is being kept fresh -- no auto-AFK and "
                "no idle logout while RTS mode is on");
    }
}

void Shutdown() {
    ForceCamSpectator(false);
}

}  // namespace steady
