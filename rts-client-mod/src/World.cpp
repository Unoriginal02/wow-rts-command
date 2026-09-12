#include "World.h"

#include <windows.h>

#include "Offsets.h"

namespace world {

namespace {

bool Cast(const Vec3& start, const Vec3& end, Vec3* hit, float* frac, unsigned flags) {
    using Fn = int(__cdecl*)(const Vec3*, const Vec3*, Vec3*, float*, unsigned, unsigned);

    Vec3 out = {0.f, 0.f, 0.f};
    float distance = 1.0f;  // the caller inits this to 1.0; result comes back as a fraction
    int result = 0;

    __try {
        result = reinterpret_cast<Fn>(off::kCGWorldFrame_Intersect)(
            &start, &end, &out, &distance, flags, 0);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }

    if (!result) return false;

    // A HIT MUST LIE ON THE SEGMENT WE CAST. Measured in game on 2026-09-12:
    // inside a cave, where the ADT is holed on purpose, the terrain-only cast
    // returned true and wrote nothing, so the caller got `out` exactly as it was
    // initialised -- {0,0,0}. The addon published that as a ground height of
    // 0.0, which against a camera at z 1345 is a 1345-yard drop: past its
    // GROUND_SNAP, so the height filter snapped, and the camera appeared at the
    // bottom of the world in a single frame. That was the cave "plop", and the
    // lie came from here.
    //
    // The test is the cheapest one that cannot be fooled: the returned point has
    // to be inside the bounding box of start..end, with a small margin for the
    // float arithmetic. A point that is not on the ray was never touched by it.
    constexpr float kEps = 0.5f;
    auto within = [kEps](float v, float a, float b) {
        if (a > b) { float t = a; a = b; b = t; }
        return v >= a - kEps && v <= b + kEps;
    };
    if (!within(out.x, start.x, end.x) ||
        !within(out.y, start.y, end.y) ||
        !within(out.z, start.z, end.z)) {
        return false;
    }

    if (hit) *hit = out;
    if (frac) *frac = distance;
    return true;
}

}  // namespace

bool Raycast(const Vec3& start, const Vec3& end, Vec3* hit, float* frac) {
    return Cast(start, end, hit, frac, off::kIntersectFlags);
}

bool RaycastTerrain(const Vec3& start, const Vec3& end, Vec3* hit, float* frac) {
    return Cast(start, end, hit, frac, off::kIntersectFlagsTerrain);
}

}  // namespace world
