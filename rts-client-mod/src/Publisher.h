// Publisher.h -- pushes client state to the addon as Lua globals.

#pragma once

namespace publisher {

// Reads client memory and publishes RTS_* Lua globals via FrameScript_Execute.
// MUST run on the client's main thread (called from the WndProc hook).
// Safe to call before the world loads; it publishes RTS_HasPos=0 then.
void Publish();

// Publishes ONLY the camera. Cheap enough for every frame, which is the point:
// markers are placed from the camera, so a stale camera slides them across the
// screen while you turn. Same main-thread rule as Publish().
void PublishCamera();

}  // namespace publisher
