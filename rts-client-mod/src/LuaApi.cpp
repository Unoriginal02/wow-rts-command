#include "LuaApi.h"

#include "Memory.h"
#include "Offsets.h"

namespace lua {

bool StateReady() {
    uint32_t state = 0;
    if (!mem::Read<uint32_t>(off::kLuaState, &state)) return false;
    return mem::Plausible(state);
}

}  // namespace lua
