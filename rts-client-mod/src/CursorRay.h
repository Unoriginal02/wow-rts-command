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

// Ground/collision point under the mouse cursor. False if the cursor is outside
// the client area, the camera is unreadable, or the ray hit nothing (sky).
bool Get(const camera::Camera& cam, world::Vec3* hit);

}  // namespace cursorray
