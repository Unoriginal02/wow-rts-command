// Publisher.h -- pushes client state to the addon as Lua globals.

#pragma once

namespace publisher {

// Reads client memory and publishes RTS_* Lua globals via FrameScript_Execute.
// MUST run on the client's main thread (called from the WndProc hook).
// Safe to call before the world loads; it publishes RTS_HasPos=0 then.
void Publish();

// A mouse button went down, at this CLIENT-AREA pixel.
//
// Called from the WndProc hook with the coordinates the message itself carried,
// BEFORE the client is given the message -- so the point is published before
// any Lua handler for that click can run, and the addon reads an answer that
// belongs to the press rather than to whatever the 33 Hz tick last saw.
//
// `button` is 1 for the left and 2 for the right. Same main-thread rule as
// Publish(): the WndProc is the main thread by construction.
void PublishClick(int button, int px, int py);

// Publishes ONLY the camera. Cheap enough for every frame, which is the point:
// markers are placed from the camera, so a stale camera slides them across the
// screen while you turn. Same main-thread rule as Publish().
void PublishCamera();

}  // namespace publisher
