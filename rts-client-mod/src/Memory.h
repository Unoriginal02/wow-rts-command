// Memory.h -- guarded reads.
//
// A wrong offset must produce a logged failure, never a client crash. Every
// dereference of a client address goes through here. T is always POD, so SEH
// is safe (no object unwinding involved).

#pragma once
#include <windows.h>
#include <cstdint>

namespace mem {

inline bool Plausible(uint32_t addr) {
    // Null page and obvious garbage. Real client pointers are far above this.
    return addr >= 0x00010000 && addr < 0xFFFF0000;
}

template <typename T>
inline bool Read(uint32_t addr, T* out) {
    if (!Plausible(addr)) return false;
    __try {
        *out = *reinterpret_cast<const T*>(addr);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

// Writing into the client is only ever done to fields the client itself writes,
// and only after the address came from one of its own accessors.
template <typename T>
inline bool Write(uint32_t addr, T value) {
    if (!Plausible(addr)) return false;
    __try {
        *reinterpret_cast<T*>(addr) = value;
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

template <typename T>
inline T ReadOr(uint32_t addr, T fallback) {
    T v;
    return Read<T>(addr, &v) ? v : fallback;
}

// Follow a pointer: *(uint32_t*)(base + offset)
inline bool Deref(uint32_t base, uint32_t offset, uint32_t* out) {
    if (!Plausible(base)) return false;
    uint32_t v = 0;
    if (!Read<uint32_t>(base + offset, &v)) return false;
    if (!Plausible(v)) return false;
    *out = v;
    return true;
}

inline bool ReadFloat(uint32_t addr, float* out) {
    float v = 0.0f;
    if (!Read<float>(addr, &v)) return false;
    // Reject NaN/inf: a bad offset usually shows up as garbage floats, and
    // this is the cheapest way to notice before shipping it to the server.
    if (!(v == v) || v > 1.0e9f || v < -1.0e9f) return false;
    *out = v;
    return true;
}

}  // namespace mem
