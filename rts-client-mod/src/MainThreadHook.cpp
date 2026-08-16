#include "MainThreadHook.h"

#include <windows.h>

#include "Log.h"
#include "Publisher.h"

namespace {

HWND g_wnd = nullptr;
WNDPROC g_originalProc = nullptr;
bool g_unicode = false;
UINT g_pokeMsg = 0;        // private message that drives a publish tick
HANDLE g_pokeThread = nullptr;
volatile bool g_stop = false;

struct FindCtx {
    DWORD pid;
    HWND result;
};

BOOL CALLBACK EnumProc(HWND hwnd, LPARAM param) {
    auto* ctx = reinterpret_cast<FindCtx*>(param);

    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid != ctx->pid) return TRUE;               // different process
    if (GetWindow(hwnd, GW_OWNER) != nullptr) return TRUE;  // not top-level
    if (!IsWindowVisible(hwnd)) return TRUE;

    ctx->result = hwnd;
    return FALSE;  // stop
}

HWND FindClientWindow() {
    FindCtx ctx = {GetCurrentProcessId(), nullptr};
    EnumWindows(&EnumProc, reinterpret_cast<LPARAM>(&ctx));
    return ctx.result;
}

LRESULT CALLBACK HookedProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    // Runs on the client's main thread -- the only place Lua may be touched.
    // Publish only on our own message, so ordinary window traffic is untouched.
    if (msg == g_pokeMsg) {
        // wParam 0 = the full tick, 1 = the camera-only tick.
        if (wParam == 0) {
            publisher::Publish();
        } else {
            publisher::PublishCamera();
        }
    }

    if (g_originalProc) {
        return g_unicode ? CallWindowProcW(g_originalProc, hwnd, msg, wParam, lParam)
                         : CallWindowProcA(g_originalProc, hwnd, msg, wParam, lParam);
    }
    return g_unicode ? DefWindowProcW(hwnd, msg, wParam, lParam)
                     : DefWindowProcA(hwnd, msg, wParam, lParam);
}

// Drives a publish tick ~30x/second. PostMessage enqueues; the client's own
// message pump dispatches it to HookedProc on the main thread, so we never
// depend on the game generating input on its own.
//
// 30 Hz (was 10) so markers track moving units smoothly -- at 10 Hz a running
// bot's marker visibly trailed, since the model renders at 60 fps but the
// published position only stepped 10x/second.
//
// The camera then gets its own 100 Hz tick, because the two have very different
// error budgets. A unit moves at ~7 yards/s, so 33 ms of staleness is a couple
// of pixels; the camera can swing 180 deg/s, and 33 ms of that is over a hundred
// pixels of sideways slide on every marker at once. The full tick is far too
// expensive to run at 100 Hz -- it walks the whole object list and fires two
// raycasts -- so only the cheap half speeds up.
DWORD WINAPI PokeThread(LPVOID) {
    int n = 0;
    while (!g_stop) {
        if (g_wnd) {
            bool full = (n % 3) == 0;   // 100 Hz / 3 ~= the old 30 Hz
            PostMessageW(g_wnd, g_pokeMsg, full ? 0 : 1, 0);
        }
        ++n;
        Sleep(10);
    }
    return 0;
}

}  // namespace

namespace mainthread {

void* Window() {
    return g_wnd;
}

bool Install() {
    for (int i = 0; i < 100 && !g_wnd; ++i) {
        g_wnd = FindClientWindow();
        if (!g_wnd) Sleep(50);
    }
    if (!g_wnd) {
        RTS_LOG("could not find the client window -- publishing cannot proceed");
        return false;
    }

    g_unicode = IsWindowUnicode(g_wnd) != FALSE;
    RTS_LOG("client window %p (%s)", static_cast<void*>(g_wnd), g_unicode ? "unicode" : "ansi");

    g_pokeMsg = RegisterWindowMessageW(L"RtsCorePublish");
    if (g_pokeMsg == 0) g_pokeMsg = WM_APP + 0x51;

    LONG_PTR prev = g_unicode
        ? SetWindowLongPtrW(g_wnd, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&HookedProc))
        : SetWindowLongPtrA(g_wnd, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&HookedProc));

    if (prev == 0) {
        RTS_LOG("SetWindowLongPtr failed (%lu)", GetLastError());
        return false;
    }
    g_originalProc = reinterpret_cast<WNDPROC>(prev);
    RTS_LOG("WndProc subclassed (original %p)", reinterpret_cast<void*>(prev));

    g_stop = false;
    g_pokeThread = CreateThread(nullptr, 0, &PokeThread, nullptr, 0, nullptr);
    RTS_LOG("publish loop started (~10 Hz)");
    return true;
}

void Remove() {
    g_stop = true;

    if (g_pokeThread) {
        WaitForSingleObject(g_pokeThread, 500);
        CloseHandle(g_pokeThread);
        g_pokeThread = nullptr;
    }

    if (g_wnd && g_originalProc) {
        if (g_unicode)
            SetWindowLongPtrW(g_wnd, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(g_originalProc));
        else
            SetWindowLongPtrA(g_wnd, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(g_originalProc));
        RTS_LOG("WndProc restored");
    }

    g_originalProc = nullptr;
    g_wnd = nullptr;
}

}  // namespace mainthread
