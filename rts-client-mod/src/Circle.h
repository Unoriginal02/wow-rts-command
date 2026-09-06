// Circle.h -- a native ground selection circle under every selected unit.
//
// The client already draws these -- under your target, and under whatever you
// are hovering. They are exactly the marker an RTS wants: part of the scene, so
// occluded by terrain and draped over slopes with nobody sampling anything. The
// only limitation is that the client has room for two.
//
// It keeps those two as guid slots on the scene context and drains them once a
// frame: read a guid, resolve the unit, call the virtual that draws its circle,
// zero the slot. So this does not reimplement any of it. It hooks the drain,
// lets it run once as usual, and then hands it our units one at a time -- each
// call drawing one more circle through the client's own code. See Offsets.h
// (kCircleDraw) for the disassembly this rests on.
//
// An earlier version of this file patched a guid comparison at 0x0079676D
// instead. That gate is real and per-unit, but the effect it arms is a model
// tint, not the circle -- proved in game, and written up in Offsets.h so nobody
// walks back into it.
//
// Everything here runs on the client's main thread -- the render walk and our
// publish tick are the same thread, so the table can be rewritten between
// frames without a lock and never be read half-updated.

#pragma once
#include <cstdint>

namespace circle {

// One unit that should wear a circle this frame. `colour` is carried but not
// yet used: reusing the client's draw path also means taking the colour it
// chooses. Per-unit colour is a separate, smaller problem.
struct Entry {
    uint64_t guid;
    uint32_t colour;
};

uint32_t Pack(float r, float g, float b, float a = 1.0f);

// Hook the drain. Safe to call repeatedly; only the first call does anything.
// MUST be called from the client's main thread: the nine bytes being rewritten
// are the entry of a function the render loop calls, and patching them from a
// worker thread could land while the main thread is inside them.
bool Install();

// Put the client's own nine bytes back. The trampoline is intentionally leaked.
void Remove();

bool Installed();

// Replace the whole table. Anything not listed stops wearing a circle on the
// next frame.
//
// WHILE THIS TABLE HAS ANYTHING IN IT, the client's own circle under YOUR
// TARGET is suppressed for player targets. Two reasons, both seen in game:
//
//   * a unit that is both your target and RTS-selected got TWO draws of the
//     same circle and came out visibly brighter than the others -- "the world
//     selection is brighter, because both stack";
//   * and a friendly you had targeted earlier kept its circle after you moved
//     the RTS selection somewhere else, so two units looked selected at once.
//
// Only PLAYER guids (high dword zero) are suppressed. A creature you target is
// the game's own business and keeps its ring.
void Set(const Entry* entries, int count);

// ONE DRAW PER UNIT, and the knob that used to be here is gone.
//
// It drew each entry twice for a few hours on 2026-09-06, on the theory that
// two passes of the same ring would read as one heavier ring -- which is what
// a targeted-and-selected unit looked like back when the client's ring and ours
// stacked. In game it does not: it draws TWO RINGS, plainly separate. The two
// passes do not land on top of each other.
//
// Removed from both sides rather than defaulted off, because bit 30 of the
// packed channel is free again and a DLL that still understood it would be a
// trap for whoever spends that bit next.

}  // namespace circle
