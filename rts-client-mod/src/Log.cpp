#include "Log.h"

#include <windows.h>
#include <cstdarg>
#include <cstdio>

namespace {
HANDLE g_file = INVALID_HANDLE_VALUE;
CRITICAL_SECTION g_lock;
bool g_ready = false;
}  // namespace

namespace rtslog {

void Init() {
    if (g_ready) return;
    InitializeCriticalSection(&g_lock);

    // Sit next to the DLL rather than the client, so the game folder stays clean.
    wchar_t path[MAX_PATH] = {0};
    HMODULE self = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                           GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&Init), &self);
    if (self && GetModuleFileNameW(self, path, MAX_PATH)) {
        wchar_t* slash = wcsrchr(path, L'\\');
        if (slash) *(slash + 1) = L'\0';
        wcsncat_s(path, L"rts_core.log", _TRUNCATE);
    } else {
        wcscpy_s(path, L"rts_core.log");
    }

    g_file = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                         OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    g_ready = true;

    SYSTEMTIME st;
    GetLocalTime(&st);
    Write("=== rts_core attached %04d-%02d-%02d %02d:%02d:%02d ===",
          st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
}

void Write(const char* fmt, ...) {
    if (!g_ready || g_file == INVALID_HANDLE_VALUE) return;

    char body[1024];
    va_list ap;
    va_start(ap, fmt);
    _vsnprintf_s(body, sizeof(body), _TRUNCATE, fmt, ap);
    va_end(ap);

    SYSTEMTIME st;
    GetLocalTime(&st);

    char line[1152];
    int n = _snprintf_s(line, sizeof(line), _TRUNCATE, "[%02d:%02d:%02d.%03d] %s\r\n",
                        st.wHour, st.wMinute, st.wSecond, st.wMilliseconds, body);
    if (n <= 0) return;

    EnterCriticalSection(&g_lock);
    DWORD written = 0;
    WriteFile(g_file, line, static_cast<DWORD>(n), &written, nullptr);
    FlushFileBuffers(g_file);  // the client may crash; never buffer
    LeaveCriticalSection(&g_lock);
}

void Shutdown() {
    if (!g_ready) return;
    Write("=== rts_core detaching ===");
    if (g_file != INVALID_HANDLE_VALUE) CloseHandle(g_file);
    g_file = INVALID_HANDLE_VALUE;
    g_ready = false;
    DeleteCriticalSection(&g_lock);
}

}  // namespace rtslog
