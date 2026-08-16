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

}  // namespace world
