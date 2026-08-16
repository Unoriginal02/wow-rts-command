// Highlight.h -- drives the client's own per-unit highlight, so selection
// markers are drawn by the game in the 3D world instead of by us in the UI.
//
// Why this matters: a UI texture cannot be depth-tested. Anything we draw
// ourselves floats on top of trees and hills. The client's highlight is part of
// model rendering, so it is occluded correctly for free. See Offsets.h for the
// reverse-engineering notes.

#pragma once
#include <cstdint>

namespace highlight {

// One unit and the colour it should wear this tick.
struct Tint {
    uint32_t addr;
    float r, g, b;
};

// Set or clear one highlight reason on a unit object. False if the object or the
// call looks unsafe; never throws into the client.
bool Set(uint32_t objAddr, uint32_t reason);
bool Clear(uint32_t objAddr, uint32_t reason);

// True if the unit currently holds this reason.
bool Has(uint32_t objAddr, uint32_t reason);

// Overwrite the highlight colour and amount the client just wrote, on the unit's
// own render object. Returns false if the render object could not be reached.
bool ForceColour(uint32_t objAddr, float r, float g, float b, float amount);

// Logs the branches SetHighlight takes on this unit -- the suppression virtual,
// the render object, the colour actually written, and the unitHighlights CVar.
// Self-limiting: the first few calls after injection log, the rest are silent.
void Diag(uint32_t objAddr, uint32_t reason);

// Paint exactly `tints`, in that unit's own colour, and take the highlight off
// anything we lit previously that is no longer listed. Returns how many are lit.
int Apply(const Tint* tints, int count, uint32_t reason);

}  // namespace highlight
