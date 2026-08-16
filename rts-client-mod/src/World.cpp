#include "World.h"

#include <windows.h>

#include "Offsets.h"

namespace world {

bool Raycast(const Vec3& start, const Vec3& end, Vec3* hit, float* frac) {
    using Fn = int(__cdecl*)(const Vec3*, const Vec3*, Vec3*, float*, unsigned, unsigned);

    Vec3 out = {0.f, 0.f, 0.f};
    float distance = 1.0f;  // the caller inits this to 1.0; result comes back as a fraction
    int result = 0;

    __try {
        result = reinterpret_cast<Fn>(off::kCGWorldFrame_Intersect)(
            &start, &end, &out, &distance, off::kIntersectFlags, 0);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }

    if (result) {
        if (hit) *hit = out;
        if (frac) *frac = distance;
        return true;
    }
    return false;
}

}  // namespace world
