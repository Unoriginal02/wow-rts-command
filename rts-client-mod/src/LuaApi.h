// LuaApi.h -- thin binding to the client's own Lua.
//
// We do NOT register C functions into the client's Lua. WoW 3.3.5a patched its
// Lua to reject C function pointers that live outside Wow.exe -- calling one
// throws ERROR #134 "Invalid function pointer" and crashes the client (verified
// the hard way). So instead we PUSH data: FrameScript_Execute runs a Lua source
// string in the client's own state, and we use it to set plain Lua globals
// (RTS_PX, ...) that the addon reads. No C function pointers cross the boundary.
//
// FrameScript_Execute(const char* code, const char* source, int context),
// __cdecl. Disassembly of 0x00819210 shows luaL_loadbuffer + lua_pcall on the
// global state read from off::kLuaState. context 0 = no owning frame (a plain
// global DoString), which is what we want.

#pragma once
#include "Offsets.h"

namespace lua {

using FnExecute = void(__cdecl*)(const char* code, const char* source, int context);

// Runs a Lua source string in the client's global state. Main thread only.
inline void Execute(const char* code) {
    reinterpret_cast<FnExecute>(off::kFrameScript_Execute)(code, "rts_core", 0);
}

// True once the client has built its Lua state. Executing before this faults.
bool StateReady();

}  // namespace lua
