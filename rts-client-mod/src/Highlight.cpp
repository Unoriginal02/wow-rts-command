#include "Highlight.h"

#include <windows.h>

#include "Log.h"
#include "Memory.h"
#include "Offsets.h"

namespace highlight {
namespace {

using HighlightFn = void(__thiscall*)(void*, uint32_t);
using Virtual0Fn = uint32_t(__thiscall*)(void*);

// Units we asserted the reason on last time, so we can take it back off when a
// unit stops being selected. Small fixed array -- the party is at most 5.
constexpr int kMaxTracked = 16;
uint32_t g_lit[kMaxTracked] = {};
int g_litCount = 0;

bool CallHighlight(uint32_t fnAddr, uint32_t objAddr, uint32_t reason) {
    if (!mem::Plausible(objAddr)) return false;

    // The call reads the object's vtable, so a bad object would fault inside the
    // client. Verify the vtable pointer before handing control over.
    uint32_t vtable = 0;
    if (!mem::Read<uint32_t>(objAddr, &vtable) || !mem::Plausible(vtable)) return false;

    __try {
        HighlightFn fn = reinterpret_cast<HighlightFn>(fnAddr);
        fn(reinterpret_cast<void*>(objAddr), reason);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        RTS_LOG("highlight: call 0x%08X on obj 0x%08X faulted", fnAddr, objAddr);
        return false;
    }
}

// Calls a no-argument __thiscall virtual and reports whether it returned at all.
bool CallVirtual0(uint32_t objAddr, uint32_t slot, uint32_t* out) {
    uint32_t vtable = 0;
    if (!mem::Read<uint32_t>(objAddr, &vtable) || !mem::Plausible(vtable)) return false;
    uint32_t fn = 0;
    if (!mem::Read<uint32_t>(vtable + slot, &fn) || !mem::Plausible(fn)) return false;
    __try {
        *out = reinterpret_cast<Virtual0Fn>(fn)(reinterpret_cast<void*>(objAddr));
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        RTS_LOG("highlight: vtbl+0x%X on obj 0x%08X faulted", slot, objAddr);
        return false;
    }
}

// Log the first few applications after injection and then stay silent. The
// mechanism is confirmed working now, so a periodic sample would only grow the
// log; re-raise this if the render object ever needs watching again.
int g_diagTick = 0;
bool DiagDue() { return g_diagTick++ < 3; }

}  // namespace

void Diag(uint32_t objAddr, uint32_t reason) {
    if (!DiagDue()) return;

    uint32_t gate = mem::ReadOr<uint32_t>(off::kHighlightGateFlag, 0xFFFFFFFF);
    uint32_t cvarObj = mem::ReadOr<uint32_t>(off::kCVar_UnitHighlights, 0);
    uint32_t cvarVal = cvarObj ? mem::ReadOr<uint32_t>(cvarObj + off::kCVar_IntValue, 0xFFFFFFFF)
                               : 0xFFFFFFFF;
    RTS_LOG("diag hl: gate=%u cvar unitHighlights=%d circleGuid=0x%08X%08X",
            gate, static_cast<int>(cvarVal),
            mem::ReadOr<uint32_t>(off::kHighlightedGuid + 4, 0),
            mem::ReadOr<uint32_t>(off::kHighlightedGuid, 0));

    uint32_t vtable = mem::ReadOr<uint32_t>(objAddr, 0);
    uint32_t flags = mem::ReadOr<uint32_t>(objAddr + off::kUnit_HighlightFlags, 0);

    // The two branches SetHighlight takes. Nonzero from +0xB4 means it painted
    // nothing at all -- that is the failure mode we cannot see from Lua.
    uint32_t suppressed = 0;
    bool okB4 = CallVirtual0(objAddr, off::kVtbl_HighlightSuppressed, &suppressed);
    uint32_t render = 0;
    bool okD4 = CallVirtual0(objAddr, off::kVtbl_GetRenderObject, &render);

    RTS_LOG("diag hl: obj=0x%08X vtbl=0x%08X flags=0x%08X reason=%u "
            "suppressed=%s render=%s",
            objAddr, vtable, flags, reason,
            okB4 ? (suppressed ? "YES(bails)" : "no") : "call failed",
            okD4 ? (render ? "ok" : "NULL(bails)") : "call failed");

    if (okD4 && mem::Plausible(render)) {
        RTS_LOG("diag hl: render=0x%08X rgb=%.3f,%.3f,%.3f amount=%.3f",
                render,
                mem::ReadOr<float>(render + off::kRender_HighlightR, -1.0f),
                mem::ReadOr<float>(render + off::kRender_HighlightR + 4, -1.0f),
                mem::ReadOr<float>(render + off::kRender_HighlightR + 8, -1.0f),
                mem::ReadOr<float>(render + off::kRender_HighlightAmount, -1.0f));
    }
}

bool ForceColour(uint32_t objAddr, float r, float g, float b, float amount) {
    uint32_t render = 0;
    if (!CallVirtual0(objAddr, off::kVtbl_GetRenderObject, &render)) return false;
    if (!mem::Plausible(render)) return false;
    return mem::Write<float>(render + off::kRender_HighlightR, r)
        && mem::Write<float>(render + off::kRender_HighlightR + 4, g)
        && mem::Write<float>(render + off::kRender_HighlightR + 8, b)
        && mem::Write<float>(render + off::kRender_HighlightAmount, amount);
}

bool Set(uint32_t objAddr, uint32_t reason) {
    return CallHighlight(off::kCGUnit_SetHighlight, objAddr, reason);
}

bool Clear(uint32_t objAddr, uint32_t reason) {
    return CallHighlight(off::kCGUnit_ClearHighlight, objAddr, reason);
}

bool Has(uint32_t objAddr, uint32_t reason) {
    uint32_t flags = 0;
    if (!mem::Read<uint32_t>(objAddr + off::kUnit_HighlightFlags, &flags)) return false;
    return (flags & (1u << (reason + 0x18))) != 0;
}

// Drop a reason and, if nothing else wants the unit lit, put the intensity back
// to zero ourselves. Necessary because reason 2 is ours alone: the client never
// repaints a unit it does not think is highlighted, so without this a
// deselected bot keeps glowing until its model is rebuilt.
void ClearAndDarken(uint32_t objAddr, uint32_t reason) {
    Clear(objAddr, reason);

    uint32_t flags = 0;
    if (!mem::Read<uint32_t>(objAddr + off::kUnit_HighlightFlags, &flags)) return;
    if ((flags & 0x07000000u) != 0) return;   // still the client's target/mouseover

    uint32_t render = 0;
    if (!CallVirtual0(objAddr, off::kVtbl_GetRenderObject, &render)) return;
    if (!mem::Plausible(render)) return;
    mem::Write<float>(render + off::kRender_HighlightAmount, 0.0f);
}

int Apply(const Tint* tints, int count, uint32_t reason) {
    if (count > kMaxTracked) count = kMaxTracked;

    // Take the highlight off anything that dropped out of the list. Doing this
    // first keeps a unit that is still listed from being cleared and re-set in
    // the same tick, which would flicker.
    for (int i = 0; i < g_litCount; ++i) {
        bool still = false;
        for (int j = 0; j < count; ++j) {
            if (tints[j].addr == g_lit[i]) { still = true; break; }
        }
        if (!still) ClearAndDarken(g_lit[i], reason);
    }

    if (count > 0 && tints[0].addr) Diag(tints[0].addr, reason);

    int lit = 0;
    for (int i = 0; i < count; ++i) {
        uint32_t addr = tints[i].addr;
        if (!addr) continue;

        // Only flip the flag when it is not already set. SetHighlight repaints
        // the client's own colour -- RGB(78,78,95) -- and calling it every tick
        // meant every tick wrote a colour we then had to overwrite. With reason
        // 2 nothing else clears the bit, so this settles into a single call per
        // unit per selection.
        if (!Has(addr, reason) && !Set(addr, reason)) continue;

        // The COLOUR is re-asserted every tick regardless. A unit that walks out
        // of view and back gets a fresh render object with default colours, and
        // the flag bit -- which lives on the unit, not the render object -- does
        // not tell us that happened. Rewriting is cheap; detecting it is not.
        ForceColour(addr, tints[i].r, tints[i].g, tints[i].b, 1.0f);
        g_lit[lit++] = addr;
    }
    g_litCount = lit;

    return lit;
}

}  // namespace highlight
