// GroundRing.h -- ground heights in a circle around a unit's feet.
//
// A selection ring drawn as a flat circle at one height reads as a sticker on
// the monitor: it cuts through kerbs, floats over dips, and slides across
// stairs. A ring that is SAMPLED from the terrain does not, because every point
// on it is a real point on the ground.
//
// Lua has no raycast in 3.3.5a, so this has to live here. It is the same
// CGWorldFrame::Intersect the cursor ray uses -- the client's own picking --
// fired straight down at points around the unit.
//
// Only the heights are published. The addon knows the unit's position and the
// ring radius, so x and y are derivable and would be a waste of a Lua parse.

#pragma once
#include <cstdint>

namespace ring {

// Points around the circle. Twelve reads as round at the sizes a selection ring
// is drawn at, and costs twelve rays rather than the twenty-four that would be
// needed before the difference is visible.
constexpr int kPoints = 12;

// Yards. Tight enough to sit under a humanoid without swallowing its feet.
constexpr float kRadius = 1.6f;

// Ground heights around (x,y,z), clockwise from world +X. Returns null if the
// terrain could not be sampled at all.
//
// Cached per guid and re-sampled only when the unit has actually moved or the
// entry has gone stale, because a bot standing still has the same ring every
// tick and twelve rays per unit per tick adds up.
const float* Get(uint64_t guid, float x, float y, float z);

// Drop cached rings for units no longer being drawn.
void Forget(const uint64_t* keep, int count);

}  // namespace ring
