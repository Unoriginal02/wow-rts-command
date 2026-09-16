// CursorRay.h -- where the mouse cursor is pointing, in the world.
//
// This is the one thing WotLK Lua genuinely cannot do: there is no raycast in
// the 3.3.5a API. The addon had been faking it by unprojecting the cursor onto
// a flat plane at the PLAYER's Z, which is exact on flat ground next to your
// character and wrong everywhere else -- hills, stairs, bridges. The detached
// RTS camera made it much worse, because the camera can now be a hundred yards
// from the character whose Z that plane is pinned to.
//
// So we cast the ray ourselves, through CGWorldFrame::Intersect -- the client's
// own picking function, the same one it uses to decide what your mouse is over.

#pragma once

#include "Camera.h"
#include "World.h"

namespace cursorray {

// A cast: the ray that was fired, and what it found.
//
// THE RAY IS WORTH HAVING EVEN WHEN NOTHING WAS HIT. It is what the server is
// asked with -- it has the map and we do not -- so `origin`/`dir` are filled
// whenever the camera is readable, and `hitOk` says separately whether the
// client's own picking found ground along it.
struct Shot {
    world::Vec3 origin;
    world::Vec3 dir;      // unit length
    world::Vec3 hit;
    bool        hitOk;
};

// Cast through a CLIENT-AREA pixel, with the window size that pixel was
// measured in. y counts downward, as every Windows mouse message reports it.
// False if the geometry is unusable (zero-sized window, degenerate fov).
bool At(const camera::Camera& cam, float px, float py, float w, float h, Shot* out);

// Ground/collision point under the Windows cursor. False if the cursor is
// outside the client area, the camera is unreadable, or the ray hit nothing.
bool Get(const camera::Camera& cam, world::Vec3* hit);

}  // namespace cursorray
