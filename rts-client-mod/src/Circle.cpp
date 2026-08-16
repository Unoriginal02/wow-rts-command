#include "Circle.h"

#include <windows.h>
#include <cstring>

#include "Log.h"
#include "Memory.h"
#include "Offsets.h"

namespace circle {
namespace {

constexpr int kMaxEntries = 16;

// Twelve bytes, and the detour strides `add ebx, 12`. If this ever stops being
// true the scan walks through garbage, so pin it.
struct Slot {
    uint32_t lo;
    uint32_t hi;
    uint32_t colour;   // reserved -- see the note on colour in Install()
};
static_assert(sizeof(Slot) == 12, "the detour strides 12 bytes per entry");

// One spare slot on the end that is never filled, so the table is always
// zero-terminated. A guid of zero is not a unit, and is exactly what the
// client's own drain loop treats as "empty slot".
Slot g_table[kMaxEntries + 1] = {};

// Copy of the nine stolen bytes plus a jmp back, so the detour can run the
// client's own function as many times as it likes.
using DrawFn = void(__thiscall*)(void*);
void* g_trampoline = nullptr;

uint8_t g_original[off::kCircleStolen] = {};
bool    g_installed = false;

// Written as literals because MSVC inline asm cannot take a constexpr's value.
static_assert(off::kCircleSlotA == 0x380, "asm literal out of sync");

// The detour.
//
// Entered with ecx = the scene context whose two guid slots the original
// function drains. We let it drain them as usual -- that draws the circles under
// your target and your mouseover, unchanged -- and then feed it our own units
// one at a time. Each call resolves one guid, draws that unit's circle and zeros
// the slot behind itself, so the loop needs no cleanup of its own.
//
// Nothing here reimplements any part of the drawing. That is the whole point:
// the earlier attempt tried to out-think the renderer and armed the wrong
// effect. This one only ever asks the client to do the thing it already does.
__declspec(naked) void DrawHook() {
    __asm {
        push    ebp
        mov     ebp, esp
        push    ebx
        push    esi
        push    edi
        mov     esi, ecx                    // the scene context

        // 1. the client's own two circles, exactly as before.
        mov     ecx, esi
        call    dword ptr [g_trampoline]

        // 2. ours, one call each. NO colour work: see Offsets.h for the two
        //    ways that was tried and the in-game result of each.
        lea     ebx, g_table
    next:
        mov     eax, dword ptr [ebx]
        mov     edx, dword ptr [ebx + 4]
        mov     ecx, eax
        or      ecx, edx
        jz      done                        // all-zero guid: end of table

        mov     dword ptr [esi + 0x380], eax
        mov     dword ptr [esi + 0x384], edx
        mov     ecx, esi
        call    dword ptr [g_trampoline]

        add     ebx, 12
        jmp     next

    done:
        pop     edi
        pop     esi
        pop     ebx
        mov     esp, ebp
        pop     ebp
        ret
    }
}

}  // namespace

namespace {
uint8_t Clamp8(float v) {
    if (v <= 0.0f) return 0;
    if (v >= 1.0f) return 255;
    return static_cast<uint8_t>(v * 255.0f + 0.5f);
}
}  // namespace

// 0xAARRGGBB -- the layout the client's own 0xFF7F7F7F sits in.
//
// Note that the client's grey is 127, not 255: it draws its circle at half
// intensity. Ours go out at full on purpose. A state colour that has to be read
// at a glance across a battlefield should be vivid, and being unmistakable is
// the entire job of the marker.
uint32_t Pack(float r, float g, float b, float a) {
    return (static_cast<uint32_t>(Clamp8(a)) << 24)
         | (static_cast<uint32_t>(Clamp8(r)) << 16)
         | (static_cast<uint32_t>(Clamp8(g)) << 8)
         |  static_cast<uint32_t>(Clamp8(b));
}

bool Installed() { return g_installed; }

bool Install() {
    if (g_installed) return true;

    uint8_t* site = reinterpret_cast<uint8_t*>(off::kCircleDraw);

    if (memcmp(site, off::kCircleDrawBytes, off::kCircleStolen) != 0) {
        RTS_LOG("circle: entry at 0x%08X is not the expected %u bytes -- NOT hooked",
                off::kCircleDraw, off::kCircleStolen);
        return false;
    }


    // Trampoline: the stolen bytes verbatim (all position-independent -- a push,
    // a register move and an absolute-displacement load) then a jump back.
    uint8_t* tramp = static_cast<uint8_t*>(
        VirtualAlloc(nullptr, 64, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    if (!tramp) {
        RTS_LOG("circle: VirtualAlloc failed (%lu) -- NOT hooked", GetLastError());
        return false;
    }

    memcpy(tramp, off::kCircleDrawBytes, off::kCircleStolen);
    int32_t const back = static_cast<int32_t>(off::kCircleDrawResume)
                       - static_cast<int32_t>(reinterpret_cast<uintptr_t>(tramp)
                                              + off::kCircleStolen + 5);
    tramp[off::kCircleStolen] = 0xE9;
    memcpy(tramp + off::kCircleStolen + 1, &back, 4);
    g_trampoline = tramp;

    DWORD prot = 0;
    if (!VirtualProtect(site, off::kCircleStolen, PAGE_EXECUTE_READWRITE, &prot)) {
        RTS_LOG("circle: VirtualProtect failed (%lu) -- NOT hooked", GetLastError());
        VirtualFree(tramp, 0, MEM_RELEASE);
        g_trampoline = nullptr;
        return false;
    }

    memcpy(g_original, site, off::kCircleStolen);

    int32_t const rel = static_cast<int32_t>(reinterpret_cast<uintptr_t>(&DrawHook))
                      - static_cast<int32_t>(off::kCircleDraw + 5);
    site[0] = 0xE9;
    memcpy(site + 1, &rel, 4);
    memset(site + 5, 0x90, off::kCircleStolen - 5);

    DWORD ignored = 0;
    VirtualProtect(site, off::kCircleStolen, prot, &ignored);
    FlushInstructionCache(GetCurrentProcess(), site, off::kCircleStolen);

    g_installed = true;
    RTS_LOG("circle: draw hooked at 0x%08X -> %p (trampoline %p)",
            off::kCircleDraw, reinterpret_cast<void*>(&DrawHook), tramp);

    uint32_t const cvarObj = mem::ReadOr<uint32_t>(off::kCVar_ObjectSelectionCircle, 0);
    int32_t const cvarVal = cvarObj ? mem::ReadOr<int32_t>(cvarObj + off::kCVar_IntValue, -1) : -1;
    RTS_LOG("circle: ObjectSelectionCircle = %d (0 means the client draws no circle at all)",
            cvarVal);
    return true;
}

void Remove() {
    if (!g_installed) return;

    uint8_t* site = reinterpret_cast<uint8_t*>(off::kCircleDraw);
    DWORD prot = 0;
    if (VirtualProtect(site, off::kCircleStolen, PAGE_EXECUTE_READWRITE, &prot)) {
        memcpy(site, g_original, off::kCircleStolen);
        DWORD ignored = 0;
        VirtualProtect(site, off::kCircleStolen, prot, &ignored);
        FlushInstructionCache(GetCurrentProcess(), site, off::kCircleStolen);
        RTS_LOG("circle: draw hook removed");
    }

    // The trampoline is deliberately NOT freed. A frame already in flight can be
    // inside it, and 64 bytes leaked once per session is a far better trade than
    // a race on unload.
    g_installed = false;
}

void Set(const Entry* entries, int count) {
    if (count > kMaxEntries) count = kMaxEntries;

    int out = 0;
    for (int i = 0; i < count && entries; ++i) {
        // A zero guid would terminate the table early and silently drop
        // everything after it.
        if (entries[i].guid == 0) continue;
        g_table[out].lo     = static_cast<uint32_t>(entries[i].guid & 0xFFFFFFFFu);
        g_table[out].hi     = static_cast<uint32_t>(entries[i].guid >> 32);
        g_table[out].colour = entries[i].colour;
        ++out;
    }

    // Terminate. Only the first unused slot needs clearing -- the scan stops
    // there and never sees the stale entries beyond it.
    g_table[out].lo = 0;
    g_table[out].hi = 0;
    g_table[out].colour = 0;

    // Log the table whenever it CHANGES, never per tick. This exists because
    // "the circles are all one colour" has two completely different causes --
    // colours not being sent, or colours being sent and not rendering -- and
    // they look identical in game. One line here separates them for good.
    // Capped as well as change-gated. "On change" sounds cheap and is not: a
    // unit's state flips as it walks and fights, so a moving party rewrites this
    // table constantly. Enough lines to see the colours going in, then silence.
    static int s_logged = 0;
    if (s_logged >= 40) return;

    static uint32_t s_lastSig = 0;
    static int s_lastCount = -1;
    uint32_t sig = 0;
    for (int i = 0; i < out; ++i) sig ^= g_table[i].lo * 31u + g_table[i].colour;
    if (sig != s_lastSig || out != s_lastCount) {
        ++s_logged;
        s_lastSig = sig;
        s_lastCount = out;
        if (out == 0) {
            RTS_LOG("circle: table empty");
        } else {
            for (int i = 0; i < out; ++i) {
                RTS_LOG("circle: [%d] guid 0x%08X%08X colour 0x%08X%s",
                        i, g_table[i].hi, g_table[i].lo, g_table[i].colour,
                        g_table[i].colour == 0 ? "  <- 0 = keep the client's grey" : "");
            }
        }
    }
}

}  // namespace circle
