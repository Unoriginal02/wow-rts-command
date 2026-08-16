// CVarChannel.h -- the addon -> DLL direction.
//
// The DLL pushes state to Lua by executing source that assigns globals. Lua
// cannot call the other way: a C function pointer outside Wow.exe is rejected
// with ERROR #134 and takes the client down with it (verified the hard way).
//
// A CVar is the way back. It is ordinary client memory that Lua is allowed to
// write with SetCVar, and the client parses the value into an int we can read.
// One CVar therefore carries 32 bits per tick, which is enough for a selection
// mask and the generation stamp that keeps it honest. See Offsets.h.

#pragma once
#include <cstdint>

namespace cvar {

// Looks a CVar up by name in the client's own table. Null if it does not exist.
uint32_t Find(const char* name);

// Reads a CVar's integer value (the client's atoi of its string). False if the
// CVar is missing or unreadable; *out is untouched then.
bool ReadInt(const char* name, int32_t* out);

}  // namespace cvar
