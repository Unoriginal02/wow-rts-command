// ObjectManager.h -- read-only walk of the client's object list.

#pragma once
#include <cstdint>

namespace objmgr {

// Resolve ClientConnection -> ObjectMgr. False before the world is loaded.
bool Ready();

// GUID of the character you are playing. 0 when unavailable.
uint64_t LocalGuid();

// Locate an object by GUID. Returns its address and type id.
bool FindByGuid(uint64_t guid, uint32_t* outAddr, uint32_t* outType);

// World position of a unit/player object. Any out-param may be null.
bool GetPosition(uint32_t objAddr, float* x, float* y, float* z, float* facing);

// The two underlying reads, exposed for diagnostics.
bool GetPositionVirtual(uint32_t objAddr, float* x, float* y, float* z);  // client GetPosition()
bool GetPositionRaw(uint32_t objAddr, float* x, float* y, float* z);      // field 0x798

// Convenience: position of the local player.
bool GetLocalPlayerPosition(float* x, float* y, float* z, float* facing);

// Count objects, for the self-test. Returns -1 if the list looks corrupt.
int CountObjects();

// Hard ceiling on one enumeration, so the distance-sort scratch array is fixed.
constexpr int kMaxNearby = 32;

struct UnitInfo {
    uint64_t guid;
    float x, y, z;
    uint32_t addr;   // client object address, for calling its methods
    uint32_t type;   // off::kTypePlayer or off::kTypeUnit
};

// Fills `out` with the `maxCount` NEAREST units within `maxDist` of (cx,cy,cz),
// sorted nearest first. Players always count; creatures only if asked, since
// they are far more numerous. Includes the local player. maxCount is clamped to
// kMaxNearby. Returns how many were written.
int EnumerateNearby(UnitInfo* out, int maxCount, float cx, float cy, float cz,
                    float maxDist, bool includeCreatures);

// Players only -- the original behaviour, kept for existing callers.
int EnumeratePlayers(UnitInfo* out, int maxCount, float cx, float cy, float cz, float maxDist);

// Walks the chain and logs what it found. Safe to call any time.
void SelfTest();

// Logs virtual GetPosition vs raw 0x798 for the player and one remote bot, so
// we can see which read is correct and whether the virtual call even works.
void DiagPositions();

}  // namespace objmgr
