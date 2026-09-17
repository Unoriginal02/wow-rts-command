// dllmain.cpp -- entry point.
//
// DllMain runs under the loader lock, so it does no real work: it only spawns
// a thread. Everything that touches the client happens from there, and
// anything needing the main thread is deferred to the EndScene hook.

#include <windows.h>

#include "Circle.h"
#include "Plates.h"
#include "SelfShow.h"
#include "Log.h"
#include "MainThreadHook.h"
#include "ObjectManager.h"
#include "Offsets.h"

namespace {

HMODULE g_self = nullptr;

// Refuse to run against a client we have not verified offsets for.
bool VerifyClient() {
    HMODULE base = GetModuleHandleW(nullptr);
    if (reinterpret_cast<uint32_t>(base) != off::kImageBase) {
        RTS_LOG("FATAL: image base is %p, expected 0x%08X -- ASLR or wrong binary",
                static_cast<void*>(base), off::kImageBase);
        return false;
    }

    wchar_t path[MAX_PATH] = {0};
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    RTS_LOG("host process: %ls", path);
    RTS_LOG("image base   : %p (expected)", static_cast<void*>(base));
    return true;
}

DWORD WINAPI Main(LPVOID) {
    rtslog::Init();
    RTS_LOG("rts_core starting (built for 3.3.5a build %u, x86)", off::kBuildNumber);

    if (!VerifyClient()) {
        RTS_LOG("aborting: client verification failed, nothing was hooked");
        return 0;
    }

    // Snapshot state at inject time. Usually 'not in world' if injected at the
    // login screen -- that is expected and harmless.
    objmgr::SelfTest();

    if (!mainthread::Install()) {
        RTS_LOG("aborting: main-thread hook not installed");
        return 0;
    }

    RTS_LOG("initialisation complete; waiting for main thread to register Lua");
    return 0;
}

}  // namespace

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
    switch (reason) {
        case DLL_PROCESS_ATTACH: {
            g_self = module;
            DisableThreadLibraryCalls(module);
            HANDLE t = CreateThread(nullptr, 0, &Main, nullptr, 0, nullptr);
            if (t) CloseHandle(t);
            break;
        }
        case DLL_PROCESS_DETACH:
            // Order matters: stop the publish loop before unpatching, so the
            // main thread is not still being poked into code that is about to
            // be rewritten under it.
            mainthread::Remove();
            selfshow::Shutdown();
            plates::Shutdown();
            circle::Remove();
            rtslog::Shutdown();
            break;
        default:
            break;
    }
    return TRUE;
}
