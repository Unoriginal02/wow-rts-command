// Camera.h -- reads the active camera for cursor/look-at raycasting.

#pragma once

namespace camera {

struct Camera {
    float pos[3];        // world position
    float mat[9];        // 3x3 orientation, rows [0..2] at struct +0x14/+0x20/+0x2C
    float fov;           // radians
    float aspect;
};

// Reads the active camera. False if the camera is not available yet.
bool Get(Camera* out);

// Force the camera's field of view, in radians (diagonal, as the client stores
// it). Must be re-applied every tick -- the client rewrites this field.
bool SetFov(float radians);

// Logs the raw camera struct as floats (once) so the real FOV / any stored
// projection matrix can be identified instead of guessed.
void DumpStruct();

}  // namespace camera
