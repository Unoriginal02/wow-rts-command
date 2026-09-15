// World.h -- the client's terrain/collision raycast.

#pragma once

namespace world {

struct Vec3 {
    float x, y, z;
};

// Casts a ray from `start` to `end` against terrain/WMO/M2. On a hit, returns
// true and fills `hit` (and `frac` in [0,1], the fraction along the ray).
// SEH-guarded: a bad read returns false, never crashes.
bool Raycast(const Vec3& start, const Vec3& end, Vec3* hit, float* frac);

// The same, but ONLY AGAINST TERRAIN: no buildings, no doodads, nothing placed
// on top. The same client function with a different flag mask -- the evidence
// for why 0x100 switches off the object half is in `Offsets.h`, next to
// `kIntersectFlagsTerrain`.
//
// It exists because "the first thing underneath" and "the ground" stop being
// the same thing the moment there is a house: the free camera needs the second.
bool RaycastTerrain(const Vec3& start, const Vec3& end, Vec3* hit, float* frac);

}  // namespace world
