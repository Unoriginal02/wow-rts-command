// injector.cpp -- remote-thread LoadLibrary injection into Wow.exe.
//
// Must itself be x86: CreateRemoteThread across a bitness boundary does not
// work, and Wow.exe 3.3.5a is 32-bit.

#include <windows.h>
#include <tlhelp32.h>

#include <cstdint>
#include <cstdio>
#include <string>

namespace {

const wchar_t* kTargetExe = L"Wow.exe";
const wchar_t* kDllName = L"rts_core.dll";

// Base address of a module already loaded in the target, or 0.
//
// This is the difference between "injected" and "was already in there". A second
// LoadLibraryW on a DLL the process already holds returns the EXISTING handle --
// non-zero, indistinguishable from success -- but DllMain does NOT run again, so
// nothing re-initialises and nothing new reaches the log. Reporting that as a
// fresh injection is how the launcher ended up validating the previous session's
// log and calling it this one's.
uintptr_t FindRemoteModule(DWORD pid, const wchar_t* name) {
    // TH32CS_SNAPMODULE32 so this works whichever way the OS enumerates a 32-bit
    // target. The snapshot fails with ERROR_BAD_LENGTH while the target is still
    // loading modules -- which is exactly when we ask -- so retry briefly.
    for (int attempt = 0; attempt < 10; ++attempt) {
        HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
        if (snap == INVALID_HANDLE_VALUE) {
            if (GetLastError() != ERROR_BAD_LENGTH) return 0;
            Sleep(50);
            continue;
        }

        MODULEENTRY32W me = {};
        me.dwSize = sizeof(me);

        uintptr_t base = 0;
        if (Module32FirstW(snap, &me)) {
            do {
                if (_wcsicmp(me.szModule, name) == 0) {
                    base = reinterpret_cast<uintptr_t>(me.modBaseAddr);
                    break;
                }
            } while (Module32NextW(snap, &me));
        }

        CloseHandle(snap);
        return base;
    }
    return 0;
}

DWORD FindProcess(const wchar_t* exeName) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return 0;

    PROCESSENTRY32W pe = {};
    pe.dwSize = sizeof(pe);

    DWORD pid = 0;
    if (Process32FirstW(snap, &pe)) {
        do {
            if (_wcsicmp(pe.szExeFile, exeName) == 0) {
                pid = pe.th32ProcessID;
                break;
            }
        } while (Process32NextW(snap, &pe));
    }

    CloseHandle(snap);
    return pid;
}

bool IsWow64Process32Bit(HANDLE process, bool* is32) {
    BOOL wow64 = FALSE;
    if (!IsWow64Process(process, &wow64)) return false;
    // On a 64-bit OS, a 32-bit process reports WOW64 = TRUE.
    *is32 = (wow64 == TRUE);
    return true;
}

std::wstring DllPathBesideMe() {
    wchar_t path[MAX_PATH] = {0};
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    wchar_t* slash = wcsrchr(path, L'\\');
    if (slash) *(slash + 1) = L'\0';
    return std::wstring(path) + kDllName;
}

int Fail(const char* msg) {
    fprintf(stderr, "[!] %s (error %lu)\n", msg, GetLastError());
    printf("\nPress Enter to close...");
    (void)getchar();
    return 1;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    printf("rts_core injector\n\n");

    std::wstring dll = (argc > 1) ? argv[1] : DllPathBesideMe();

    if (GetFileAttributesW(dll.c_str()) == INVALID_FILE_ATTRIBUTES) {
        fwprintf(stderr, L"[!] DLL not found: %ls\n", dll.c_str());
        printf("\nPress Enter to close...");
        (void)getchar();
        return 1;
    }
    wprintf(L"[*] DLL    : %ls\n", dll.c_str());

    DWORD pid = FindProcess(kTargetExe);
    if (!pid) {
        fwprintf(stderr, L"[!] %ls is not running. Start the client first.\n", kTargetExe);
        printf("\nPress Enter to close...");
        (void)getchar();
        return 1;
    }
    printf("[*] target : Wow.exe (pid %lu)\n", pid);

    if (uintptr_t already = FindRemoteModule(pid, kDllName)) {
        printf("[=] rts_core.dll is ALREADY loaded at 0x%08zX -- nothing to do.\n", already);
        printf("    DllMain does not run twice, so no new log lines will appear\n");
        printf("    and this is NOT a failed injection.\n");
        printf("    If RTS mode misbehaves, close the client and inject once.\n");
        printf("\nPress Enter to close...");
        (void)getchar();
        return 2;
    }

    HANDLE process = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION |
                                     PROCESS_VM_OPERATION | PROCESS_VM_WRITE | PROCESS_VM_READ,
                                 FALSE, pid);
    if (!process) return Fail("OpenProcess failed - try running as administrator");

    bool is32 = false;
    if (IsWow64Process32Bit(process, &is32) && !is32) {
        fprintf(stderr, "[!] target is not a 32-bit process; this injector is x86-only\n");
        CloseHandle(process);
        printf("\nPress Enter to close...");
        (void)getchar();
        return 1;
    }

    const SIZE_T bytes = (dll.size() + 1) * sizeof(wchar_t);
    void* remote = VirtualAllocEx(process, nullptr, bytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remote) {
        CloseHandle(process);
        return Fail("VirtualAllocEx failed");
    }

    if (!WriteProcessMemory(process, remote, dll.c_str(), bytes, nullptr)) {
        VirtualFreeEx(process, remote, 0, MEM_RELEASE);
        CloseHandle(process);
        return Fail("WriteProcessMemory failed");
    }

    // kernel32 is at the same base in every process of the same bitness, so
    // our LoadLibraryW address is valid in the target.
    HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
    auto loader = reinterpret_cast<LPTHREAD_START_ROUTINE>(GetProcAddress(k32, "LoadLibraryW"));
    if (!loader) {
        VirtualFreeEx(process, remote, 0, MEM_RELEASE);
        CloseHandle(process);
        return Fail("GetProcAddress(LoadLibraryW) failed");
    }

    HANDLE thread = CreateRemoteThread(process, nullptr, 0, loader, remote, 0, nullptr);
    if (!thread) {
        VirtualFreeEx(process, remote, 0, MEM_RELEASE);
        CloseHandle(process);
        return Fail("CreateRemoteThread failed - antivirus may have blocked it");
    }

    WaitForSingleObject(thread, 10000);

    DWORD module = 0;
    GetExitCodeThread(thread, &module);

    CloseHandle(thread);
    VirtualFreeEx(process, remote, 0, MEM_RELEASE);
    CloseHandle(process);

    if (module == 0) {
        fprintf(stderr, "[!] LoadLibraryW returned NULL - the DLL failed to load.\n");
        fprintf(stderr, "    Most likely a missing VC++ runtime in the target.\n");
        printf("\nPress Enter to close...");
        (void)getchar();
        return 1;
    }

    printf("[+] injected, module at 0x%08lX\n", module);
    printf("[+] check rts_core.log next to the DLL for details\n");

    // No pause on success. This runs in the launcher's own console window, and the
    // getchar() that used to be here left the .bat sitting at step [2/3] looking
    // hung until someone pressed a key -- so the check that follows never ran on
    // its own. Failures still pause, because there the text IS the point.
    return 0;
}
