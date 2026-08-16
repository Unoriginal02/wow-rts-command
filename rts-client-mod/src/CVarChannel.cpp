#include "CVarChannel.h"

#include <windows.h>

#include "Log.h"
#include "Memory.h"
#include "Offsets.h"

namespace cvar {
namespace {

// __thiscall(table, name) -> CVar*, the client's own lookup.
using LookupFn = uint32_t(__thiscall*)(void*, const char*);

// The lookup is called every tick, and the table it walks does not change once
// the CVars are registered, so the result is cached per name pointer. A miss is
// cached too: a CVar that does not exist now will not appear later.
struct Cached {
    const char* name;
    uint32_t obj;
    bool resolved;
};
constexpr int kMaxCached = 4;
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
    for (int i = 0; i < g_cacheCount; ++i) {
        if (g_cache[i].name == name) return g_cache[i].obj;
    }

    uint32_t obj = LookupUncached(name);
    if (g_cacheCount < kMaxCached) {
        g_cache[g_cacheCount].name = name;
        g_cache[g_cacheCount].obj = obj;
        g_cache[g_cacheCount].resolved = true;
        ++g_cacheCount;
    }
    if (obj == 0) RTS_LOG("cvar: '%s' not found -- channel unavailable", name);
    return obj;
}

bool ReadInt(const char* name, int32_t* out) {
    uint32_t obj = Find(name);
    if (!obj || !out) return false;
    return mem::Read<int32_t>(obj + off::kCVar_IntValue, out);
}

}  // namespace cvar
