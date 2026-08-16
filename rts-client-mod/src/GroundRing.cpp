#include "GroundRing.h"

#include <cmath>

#include "World.h"

namespace ring {
namespace {

// How far above and below the unit's own Z to look for ground. Up covers a bot
// standing at the foot of a step; down covers the outer edge of the ring
// hanging over a drop. Beyond this the "ground" found would not be the surface
// the unit is standing on.
constexpr float kProbeUp   = 3.0f;
constexpr float kProbeDown = 8.0f;

// Re-sample when the unit has moved this far from where its ring was taken.
// Well under the radius, so the ring never visibly lags the model.
constexpr float kMoveEpsilonSq = 0.25f * 0.25f;

// Rings expire anyway, so terrain that changes under a stationary unit -- a
// door, a lift, a bridge spawning -- is picked up within a few ticks.
constexpr uint32_t kMaxAgeTicks = 15;

constexpr int kMaxCached = 12;

struct Entry {
    uint64_t guid;
    float cx, cy, cz;
    uint32_t age;
    bool valid;
    float z[kPoints];
};

Entry g_cache[kMaxCached] = {};
int g_count = 0;

Entry* Find(uint64_t guid) {
    for (int i = 0; i < g_count; ++i) {
        if (g_cache[i].guid == guid) return &g_cache[i];
    }
    return nullptr;
}

Entry* Claim(uint64_t guid) {
    if (Entry* e = Find(guid)) return e;

    if (g_count < kMaxCached) {
        Entry* e = &g_cache[g_count++];
        *e = Entry{};
        e->guid = guid;
        return e;
    }

    // Full: reuse the oldest. The cache is larger than the number of units that
    // can be ringed at once, so this is a safety net rather than a normal path.
    Entry* oldest = &g_cache[0];
    for (int i = 1; i < g_count; ++i) {
        if (g_cache[i].age > oldest->age) oldest = &g_cache[i];
    }
    *oldest = Entry{};
    oldest->guid = guid;
    return oldest;
}

bool SampleInto(float x, float y, float z, float* out) {
    int hits = 0;

    for (int i = 0; i < kPoints; ++i) {
        float const a = (static_cast<float>(i) / kPoints) * 6.28318530718f;
        float const px = x + std::cos(a) * kRadius;
        float const py = y + std::sin(a) * kRadius;

        world::Vec3 const start = {px, py, z + kProbeUp};
        world::Vec3 const end   = {px, py, z - kProbeDown};
        world::Vec3 hit;

        if (world::Raycast(start, end, &hit, nullptr)) {
            out[i] = hit.z;
            ++hits;
        } else {
            // No ground within the probe window -- the unit is over a ledge, or
            // flying. Fall back to its own height so the ring stays a ring
            // instead of tearing open.
            out[i] = z;
        }
    }

    return hits > 0;
}

}  // namespace

const float* Get(uint64_t guid, float x, float y, float z) {
    Entry* e = Claim(guid);

    float const dx = x - e->cx;
    float const dy = y - e->cy;
    bool const moved = (dx * dx + dy * dy) > kMoveEpsilonSq || std::fabs(z - e->cz) > 0.5f;

    if (!e->valid || moved || e->age >= kMaxAgeTicks) {
        e->valid = SampleInto(x, y, z, e->z);
        e->cx = x;
        e->cy = y;
        e->cz = z;
        e->age = 0;
    } else {
        ++e->age;
    }

    return e->valid ? e->z : nullptr;
}

void Forget(const uint64_t* keep, int count) {
    int out = 0;
    for (int i = 0; i < g_count; ++i) {
        bool wanted = false;
        for (int k = 0; k < count; ++k) {
            if (g_cache[i].guid == keep[k]) { wanted = true; break; }
        }
        if (wanted) {
            if (out != i) g_cache[out] = g_cache[i];
            ++out;
        }
    }
    g_count = out;
}

}  // namespace ring
