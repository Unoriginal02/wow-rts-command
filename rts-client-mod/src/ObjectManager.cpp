#include "ObjectManager.h"

#include "Log.h"
#include "Memory.h"
#include "Offsets.h"

namespace {

// A corrupt or mid-update list must not spin forever.
constexpr int kMaxObjects = 8192;

bool GetManager(uint32_t* out) {
    uint32_t conn = 0;
    if (!mem::Read<uint32_t>(off::kClientConnection, &conn)) return false;
    if (!mem::Plausible(conn)) return false;

    uint32_t mgr = 0;
    if (!mem::Deref(conn, off::kCurMgrOffset, &mgr)) return false;

    *out = mgr;
    return true;
}

}  // namespace

namespace objmgr {

bool Ready() {
    uint32_t mgr = 0;
    return GetManager(&mgr);
}

uint64_t LocalGuid() {
    uint32_t mgr = 0;
    if (!GetManager(&mgr)) return 0;

    uint64_t guid = 0;
    if (!mem::Read<uint64_t>(mgr + off::kObjMgr_LocalGuid, &guid)) return 0;
    return guid;
}

bool FindByGuid(uint64_t guid, uint32_t* outAddr, uint32_t* outType) {
    if (guid == 0) return false;

    uint32_t mgr = 0;
    if (!GetManager(&mgr)) return false;

    uint32_t obj = 0;
    if (!mem::Read<uint32_t>(mgr + off::kObjMgr_FirstObject, &obj)) return false;

    int guard = 0;
    while (mem::Plausible(obj) && (obj & 1) == 0 && guard++ < kMaxObjects) {
        uint64_t g = 0;
        if (mem::Read<uint64_t>(obj + off::kObj_Guid, &g) && g == guid) {
            if (outAddr) *outAddr = obj;
            if (outType) *outType = mem::ReadOr<uint32_t>(obj + off::kObj_Type, 0);
            return true;
        }

        uint32_t next = 0;
        if (!mem::Read<uint32_t>(obj + off::kObj_Next, &next)) return false;
        if (next == obj) return false;  // self-link: corrupt
        obj = next;
    }

    return false;
}

// C3Vector, as the client's GetPosition fills it.
struct C3Vector { float x, y, z; };

// Calls the unit's own GetPosition (vtable index 11 = +0x2C). This is how the
// GAME reads a unit's position -- verified by disassembly at 0x00519ECA, which
// calls obj->vtable[0x2C](&out) and reads out.{x,y,z} for a distance check.
//
// The raw field at 0x798 is only correct for the local player (its own client
// keeps it live); for remote units (bots), only GetPosition returns the
// rendered/interpolated position. MUST run on the client's main thread, which
// the publish loop does.
bool GetPositionVirtual(uint32_t objAddr, float* x, float* y, float* z) {
    using GetPosFn = C3Vector*(__thiscall*)(void*, C3Vector*);

    __try {
        uint32_t vtable = 0;
        if (!mem::Read<uint32_t>(objAddr, &vtable)) return false;
        if (!mem::Plausible(vtable)) return false;

        uint32_t fnptr = 0;
        if (!mem::Read<uint32_t>(vtable + 0x2C, &fnptr)) return false;
        if (!mem::Plausible(fnptr)) return false;

        C3Vector out = {0.f, 0.f, 0.f};
        GetPosFn fn = reinterpret_cast<GetPosFn>(fnptr);
        C3Vector* r = fn(reinterpret_cast<void*>(objAddr), &out);

        float px = out.x, py = out.y, pz = out.z;
        if (px == 0.f && py == 0.f && pz == 0.f && r) {
            px = r->x; py = r->y; pz = r->z;
        }
        if (px == 0.f && py == 0.f && pz == 0.f) return false;

        if (x) *x = px;
        if (y) *y = py;
        if (z) *z = pz;
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

bool GetPositionRaw(uint32_t objAddr, float* x, float* y, float* z) {
    if (!mem::Plausible(objAddr)) return false;
    float px = 0.f, py = 0.f, pz = 0.f;
    if (!mem::ReadFloat(objAddr + off::kUnit_PosX, &px)) return false;
    if (!mem::ReadFloat(objAddr + off::kUnit_PosY, &py)) return false;
    if (!mem::ReadFloat(objAddr + off::kUnit_PosZ, &pz)) return false;
    if (px == 0.f && py == 0.f && pz == 0.f) return false;
    if (x) *x = px;
    if (y) *y = py;
    if (z) *z = pz;
    return true;
}

bool GetPosition(uint32_t objAddr, float* x, float* y, float* z, float* facing) {
    if (!mem::Plausible(objAddr)) return false;

    // Preferred: the client's own GetPosition (correct for all units).
    float vx, vy, vz;
    if (GetPositionVirtual(objAddr, &vx, &vy, &vz)) {
        if (x) *x = vx;
        if (y) *y = vy;
        if (z) *z = vz;
        if (facing) mem::ReadFloat(objAddr + off::kUnit_Facing, facing);
        return true;
    }

    // Fallback: the raw field (accurate for the local player at least).
    float px = 0.f, py = 0.f, pz = 0.f, pf = 0.f;
    if (!mem::ReadFloat(objAddr + off::kUnit_PosX, &px)) return false;
    if (!mem::ReadFloat(objAddr + off::kUnit_PosY, &py)) return false;
    if (!mem::ReadFloat(objAddr + off::kUnit_PosZ, &pz)) return false;
    mem::ReadFloat(objAddr + off::kUnit_Facing, &pf);

    if (px == 0.f && py == 0.f && pz == 0.f) return false;

    if (x) *x = px;
    if (y) *y = py;
    if (z) *z = pz;
    if (facing) *facing = pf;
    return true;
}

bool GetLocalPlayerPosition(float* x, float* y, float* z, float* facing) {
    uint64_t guid = LocalGuid();
    if (guid == 0) return false;

    uint32_t addr = 0, type = 0;
    if (!FindByGuid(guid, &addr, &type)) return false;
    if (type != off::kTypePlayer) return false;

    return GetPosition(addr, x, y, z, facing);
}

int CountObjects() {
    uint32_t mgr = 0;
    if (!GetManager(&mgr)) return -1;

    uint32_t obj = 0;
    if (!mem::Read<uint32_t>(mgr + off::kObjMgr_FirstObject, &obj)) return -1;

    int n = 0;
    while (mem::Plausible(obj) && (obj & 1) == 0 && n < kMaxObjects) {
        ++n;
        uint32_t next = 0;
        if (!mem::Read<uint32_t>(obj + off::kObj_Next, &next)) return -1;
        if (next == obj) return -1;
        obj = next;
    }
    return n;
}

int EnumerateNearby(UnitInfo* out, int maxCount, float cx, float cy, float cz,
                    float maxDist, bool includeCreatures) {
    if (!out || maxCount <= 0) return 0;
    if (maxCount > kMaxNearby) maxCount = kMaxNearby;   // bounds the sort scratch

    uint32_t mgr = 0;
    if (!GetManager(&mgr)) return 0;

    uint32_t obj = 0;
    if (!mem::Read<uint32_t>(mgr + off::kObjMgr_FirstObject, &obj)) return 0;

    const float maxSq = maxDist * maxDist;
    int written = 0;
    int guard = 0;

    // Once creatures are in scope a crowded camp can far exceed maxCount, and
    // publishing "whichever came first in the object list" would drop the units
    // under the player's nose in favour of ones behind a hill. So the list is
    // kept sorted by distance and a full list evicts its farthest entry.
    float distSq[kMaxNearby];

    while (mem::Plausible(obj) && (obj & 1) == 0 && guard++ < kMaxObjects) {
        uint32_t type = mem::ReadOr<uint32_t>(obj + off::kObj_Type, 0);
        bool wanted = type == off::kTypePlayer ||
                      (includeCreatures && type == off::kTypeUnit);
        if (wanted) {
            float x, y, z;
            if (GetPosition(obj, &x, &y, &z, nullptr)) {
                float dx = x - cx, dy = y - cy, dz = z - cz;
                float d2 = dx * dx + dy * dy + dz * dz;
                if (d2 <= maxSq && (written < maxCount || d2 < distSq[written - 1])) {
                    uint64_t g = 0;
                    if (mem::Read<uint64_t>(obj + off::kObj_Guid, &g) && g != 0) {
                        int i = (written < maxCount) ? written++ : maxCount - 1;
                        for (; i > 0 && distSq[i - 1] > d2; --i) {
                            distSq[i] = distSq[i - 1];
                            out[i] = out[i - 1];
                        }
                        distSq[i] = d2;
                        out[i].guid = g;
                        out[i].x = x;
                        out[i].y = y;
                        out[i].z = z;
                        out[i].addr = obj;
                        out[i].type = type;
                    }
                }
            }
        }

        uint32_t next = 0;
        if (!mem::Read<uint32_t>(obj + off::kObj_Next, &next)) break;
        if (next == obj) break;
        obj = next;
    }

    // Distance decided WHICH units make the cut; guid decides the ORDER they are
    // published in. The addon addresses units by their published index when it
    // answers back through the CVar channel, and a distance-ordered list
    // reshuffles every time two units pass each other -- the answer would then
    // land on the wrong unit. Guid order only changes when the set itself does,
    // which the generation stamp already catches.
    for (int i = 1; i < written; ++i) {
        UnitInfo key = out[i];
        int j = i - 1;
        for (; j >= 0 && out[j].guid > key.guid; --j) out[j + 1] = out[j];
        out[j + 1] = key;
    }

    return written;
}

int EnumeratePlayers(UnitInfo* out, int maxCount, float cx, float cy, float cz, float maxDist) {
    return EnumerateNearby(out, maxCount, cx, cy, cz, maxDist, false);
}

static void LogBoth(const char* tag, uint32_t objAddr) {
    float vx = 0, vy = 0, vz = 0, rx = 0, ry = 0, rz = 0;
    bool v = GetPositionVirtual(objAddr, &vx, &vy, &vz);
    bool r = GetPositionRaw(objAddr, &rx, &ry, &rz);
    RTS_LOG("diag %-8s obj=0x%08X  virtual[%s]=%.2f,%.2f,%.2f  raw0x798[%s]=%.2f,%.2f,%.2f",
            tag, objAddr,
            v ? "ok" : "FAIL", vx, vy, vz,
            r ? "ok" : "FAIL", rx, ry, rz);
}

void DiagPositions() {
    uint32_t mgr = 0;
    if (!GetManager(&mgr)) return;

    uint64_t localGuid = LocalGuid();
    uint32_t addr = 0, type = 0;
    if (FindByGuid(localGuid, &addr, &type)) LogBoth("player", addr);

    // First remote player-type unit (a bot).
    uint32_t obj = 0;
    if (!mem::Read<uint32_t>(mgr + off::kObjMgr_FirstObject, &obj)) return;
    int guard = 0;
    while (mem::Plausible(obj) && (obj & 1) == 0 && guard++ < 8192) {
        uint32_t t = mem::ReadOr<uint32_t>(obj + off::kObj_Type, 0);
        if (t == off::kTypePlayer) {
            uint64_t g = 0;
            if (mem::Read<uint64_t>(obj + off::kObj_Guid, &g) && g != localGuid) {
                RTS_LOG("diag bot guid=0x%016llX", static_cast<unsigned long long>(g));
                LogBoth("bot", obj);
                return;
            }
        }
        uint32_t next = 0;
        if (!mem::Read<uint32_t>(obj + off::kObj_Next, &next) || next == obj) return;
        obj = next;
    }
}

void SelfTest() {
    uint32_t conn = mem::ReadOr<uint32_t>(off::kClientConnection, 0);
    RTS_LOG("selftest: ClientConnection=0x%08X", conn);

    uint32_t mgr = 0;
    if (!GetManager(&mgr)) {
        RTS_LOG("selftest: object manager not resolvable yet (not in world?)");
        return;
    }
    RTS_LOG("selftest: ObjectMgr=0x%08X", mgr);

    uint64_t guid = LocalGuid();
    RTS_LOG("selftest: local GUID=0x%016llX", static_cast<unsigned long long>(guid));

    int n = CountObjects();
    RTS_LOG("selftest: object count=%d", n);

    float x = 0, y = 0, z = 0, f = 0;
    if (GetLocalPlayerPosition(&x, &y, &z, &f)) {
        RTS_LOG("selftest: player pos = %.3f, %.3f, %.3f  facing=%.3f  <-- OFFSETS GOOD", x, y, z, f);
    } else {
        RTS_LOG("selftest: player position unavailable (not in world, or offsets wrong)");
    }
}

}  // namespace objmgr
