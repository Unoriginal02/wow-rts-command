#include "CVarChannel.h"

#include <windows.h>

#include "Log.h"
#include "Memory.h"
#include "Offsets.h"

namespace cvar {
namespace {

// __thiscall(table, name) -> CVar*, the client's own lookup.
using LookupFn = uint32_t(__thiscall*)(void*, const char*);

// The lookup is called every tick, so a HIT is cached per name pointer -- the
// table it walks does not change once a CVar is registered.
//
// A MISS IS NOT CACHED, and the sentence that used to be here is why: *"a CVar
// that does not exist now will not appear later"*. That was written as a fact
// and it is an assumption, and a wrong one. This DLL attaches while the client
// is still on the login screen; the addon's own CVars do not exist until the UI
// loads, several seconds later. Caching that miss meant a name registered by
// Lua could never be found for the rest of the session -- which is a silent,
// permanent failure of whatever channel used it.
//
// The retry is cheap and bounded: one lookup per name per second while it is
// missing, and never again once it resolves.
struct Cached {
    const char* name;
    uint32_t obj;
    uint32_t nextTry;    // GetTickCount() before which a miss is not retried
};
// RAISED FROM 4 TO 8. With the cache full a new name still resolves -- it is
// looked up every time -- so it was not a bug, but it was one lookup per tick at
// 67 Hz for the last channel to arrive. Four fell short as soon as there were
// `enablePVPNotifyAFK`, `rtsFov` and `rtsBody`. It stays at 8 even though the
// section cut -- the fourth channel, the one that motivated it -- has been
// dropped: the spare slot costs nothing and raising it again WOULD cost another
// client cycle.
constexpr int kMaxCached = 8;
constexpr uint32_t kRetryMs = 1000;
Cached g_cache[kMaxCached] = {};
int g_cacheCount = 0;

uint32_t LookupUncached(const char* name) {
    if (!name || !mem::Plausible(off::kCVarTable)) return 0;
    __try {
        LookupFn fn = reinterpret_cast<LookupFn>(off::kCVarLookup);
        uint32_t obj = fn(reinterpret_cast<void*>(off::kCVarTable), name);
        return mem::Plausible(obj) ? obj : 0;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        RTS_LOG("cvar: lookup of '%s' faulted", name);
        return 0;
    }
}

}  // namespace

uint32_t Find(const char* name) {
    uint32_t const now = GetTickCount();

    Cached* slot = nullptr;
    for (int i = 0; i < g_cacheCount; ++i) {
        if (g_cache[i].name == name) {
            slot = &g_cache[i];
            break;
        }
    }

    if (slot) {
        if (slot->obj) return slot->obj;                 // resolved: nothing to do
        if (now < slot->nextTry) return 0;               // missed recently
        slot->obj = LookupUncached(name);
        slot->nextTry = now + kRetryMs;
        if (slot->obj)
            RTS_LOG("cvar: '%s' appeared -- channel up", name);
        return slot->obj;
    }

    uint32_t const obj = LookupUncached(name);
    if (g_cacheCount < kMaxCached) {
        g_cache[g_cacheCount].name = name;
        g_cache[g_cacheCount].obj = obj;
        g_cache[g_cacheCount].nextTry = now + kRetryMs;
        ++g_cacheCount;
    }
    if (obj == 0)
        RTS_LOG("cvar: '%s' not there yet -- retrying once a second", name);
    return obj;
}

bool ReadInt(const char* name, int32_t* out) {
    uint32_t obj = Find(name);
    if (!obj || !out) return false;
    return mem::Read<int32_t>(obj + off::kCVar_IntValue, out);
}

}  // namespace cvar
