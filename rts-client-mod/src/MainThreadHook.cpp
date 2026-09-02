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

// Publish ticks that actually reached HookedProc. This is the ONLY honest
// measure of "are we still hooked": see Watch() below.
volatile LONG g_served = 0;
int g_reattaches = 0;

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
        InterlockedIncrement(&g_served);
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

// Subclass `wnd`, and be safe to call twice.
//
// IDEMPOTENT ON PURPOSE, and that is not tidiness: if the proc already IS ours
// and we subclass again, `prev` comes back as HookedProc and every message then
// calls HookedProc from inside HookedProc -- an unbounded recursion that takes
// the client down. So the current proc is read first and a second install is
// declined.
//
// Read and write with the SAME width (W or A) as the window: for a unicode
// window the ANSI accessors hand back a translation stub rather than the real
// procedure, so mixing them compares two things that are not comparable.
bool Attach(HWND wnd) {
    if (!wnd) return false;

    bool const uni = IsWindowUnicode(wnd) != FALSE;
    LONG_PTR const cur = uni ? GetWindowLongPtrW(wnd, GWLP_WNDPROC)
                             : GetWindowLongPtrA(wnd, GWLP_WNDPROC);
    if (reinterpret_cast<WNDPROC>(cur) == &HookedProc) {
        g_wnd = wnd;
        g_unicode = uni;
        return true;                      // already hooked; leave the chain alone
    }

    LONG_PTR const prev = uni
        ? SetWindowLongPtrW(wnd, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&HookedProc))
        : SetWindowLongPtrA(wnd, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&HookedProc));
    if (prev == 0) {
        RTS_LOG("SetWindowLongPtr failed (%lu)", GetLastError());
        return false;
    }

    g_wnd = wnd;
    g_unicode = uni;
    g_originalProc = reinterpret_cast<WNDPROC>(prev);
    RTS_LOG("WndProc subclassed on window %p (%s, original %p)",
            static_cast<void*>(wnd), uni ? "unicode" : "ansi",
            reinterpret_cast<void*>(prev));
    return true;
}

// THE WINDOW DOES NOT LIVE AS LONG AS THE PROCESS, and that is what broke the
// DLL every time the video mode changed.
//
// Switching windowed/fullscreen (or resolution) makes the client tear its
// top-level window down and build a new one. The handle found at inject time is
// then dead: `PostMessage` fails, no publish tick ever reaches the main thread
// again, and the subclass went with the old window. In game that looks EXACTLY
// like a client with no DLL injected -- no selection, no halos, no orders -- so
// it reads as "the injector broke" when in fact everything is still loaded and
// merely talking to a window that no longer exists.
//
// The watchdog does not try to guess which mechanism broke it. It measures the
// only thing that matters -- whether publish ticks are still ARRIVING -- and
// re-attaches when they are not. That covers a destroyed window, a window whose
// proc the client replaced in place, and anything else with the same effect.
//
// TWO SECONDS OF SILENCE, not one tick: a loading screen can stop the client
// pumping messages for a while, and that is not a broken hook. When the window
// turns out to be the same one and still ours, nothing is touched -- the
// posted messages are simply queued and will be served late.
void Watch() {
    static LONG lastServed = -1;
    static int quiet = 0;
    static bool complained = false;

    LONG const now = g_served;
    if (now != lastServed) {
        lastServed = now;
        quiet = 0;
        return;
    }

    if (++quiet < 2) return;              // Watch() runs ~1 Hz
    quiet = 0;

    HWND const found = FindClientWindow();
    if (!found) {
        if (!complained) {
            RTS_LOG("publish stalled and no client window found -- "
                    "mid mode-change, will keep looking");
            complained = true;
        }
        return;
    }
    complained = false;

    if (found == g_wnd && IsWindow(g_wnd)) {
        bool const ours = (g_unicode ? GetWindowLongPtrW(g_wnd, GWLP_WNDPROC)
                                     : GetWindowLongPtrA(g_wnd, GWLP_WNDPROC))
                          == reinterpret_cast<LONG_PTR>(&HookedProc);
        if (ours) return;                 // just not pumping: nothing to fix
    }

    ++g_reattaches;
    RTS_LOG("publish stalled -- window was %p, now %p (re-attach #%d)",
            static_cast<void*>(g_wnd), static_cast<void*>(found), g_reattaches);

    // Only forget the old procedure when we are really moving to a DIFFERENT
    // window. Clearing it unconditionally was a way to lose it for good: if
    // Attach then declines (the proc is already ours), nothing puts it back, and
    // from that moment HookedProc sends every message to DefWindowProc instead
    // of to the client -- which is the game's own input handling, gone.
    if (found != g_wnd)
        g_originalProc = nullptr;
    Attach(found);
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
        // The watchdog, once a second. It is on THIS thread and not on the
        // main one deliberately: when the hook is gone there is no main-thread
        // code of ours left to run, so the check has to live outside it.
        if ((n % 100) == 0) Watch();
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

    g_pokeMsg = RegisterWindowMessageW(L"RtsCorePublish");
    if (g_pokeMsg == 0) g_pokeMsg = WM_APP + 0x51;

    if (!Attach(g_wnd)) return false;

    g_stop = false;
    g_pokeThread = CreateThread(nullptr, 0, &PokeThread, nullptr, 0, nullptr);
    RTS_LOG("publish loop started (100 Hz camera / 33 Hz full, watchdog 1 Hz)");
    return true;
}

void Remove() {
    g_stop = true;

    if (g_pokeThread) {
        WaitForSingleObject(g_pokeThread, 500);
        CloseHandle(g_pokeThread);
        g_pokeThread = nullptr;
    }

    // IsWindow, because the client may have thrown this window away since --
    // putting a proc back on a dead handle is a silent no-op at best.
    if (g_wnd && g_originalProc && IsWindow(g_wnd)) {
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
