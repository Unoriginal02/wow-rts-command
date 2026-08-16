// MainThreadHook.h -- runs Lua registration on the client's main thread by
// subclassing the WoW window's WndProc.
//
// Replaces the earlier D3D9 EndScene trampoline, which hooked a throwaway
// device's vtable that (under Windows 11's d3d9on12 layer) was not the vtable
// the client actually calls through -- so the hook never fired.
//
// A window's WndProc is always dispatched on the thread that created the window
// (WoW's main thread), so anything done inside it is main-thread-safe. To make
// it fire even when the game is idle and generating no input, the inject thread
// posts a private message until registration succeeds.

#pragma once

namespace mainthread {

bool Install();
void Remove();

// The client's top-level window, as an opaque handle so windows.h stays out of
// this header. Null before Install() succeeds. Needed by the cursor raycast,
// which has to turn a screen-space mouse position into client-space.
void* Window();

}  // namespace mainthread
