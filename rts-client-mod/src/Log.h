// Log.h -- file logging. There is no console in an injected DLL, and a crashed
// client tells you nothing, so the log is the only diagnostic channel.
//
// Namespace is rtslog, not log: <cmath> declares ::log (the logarithm) and a
// namespace of the same name makes every math header fail to compile.

#pragma once

namespace rtslog {

void Init();
void Write(const char* fmt, ...);
void Shutdown();

}  // namespace rtslog

#define RTS_LOG(...) ::rtslog::Write(__VA_ARGS__)
