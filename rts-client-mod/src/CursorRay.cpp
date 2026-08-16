#include "CursorRay.h"

#include <windows.h>
#include <cmath>

#include "MainThreadHook.h"

namespace cursorray {
namespace {

// How far to cast. A camera parked high above the ground looking out toward the
// horizon needs real length; beyond this the answer stops being useful anyway.
constexpr float kRange = 600.0f;

// The projection convention, kept deliberately identical to Markers.lua so the
// DLL's answer and the addon's own projection agree to the pixel.
//
// RTS_CamFov (camera struct +0x40) is the DIAGONAL field of view -- not
// horizontal, not vertical. That single fact is what made two earlier attempts
// miss by 13% and by half. With the diagonal half-angle d/2:
//     tan(vfov/2) = tan(d/2) / sqrt(1 + aspect^2)
//     sy = 1/tan(vfov/2)      sx = sy / aspect
//
// The client's camera "right" row is the geometric LEFT (forward x up = -right,
// verified from the logged matrix), hence the negated sideways axis.
constexpr float kRightSign = -1.0f;
constexpr float kUpSign    =  1.0f;

}  // namespace

bool Get(const camera::Camera& cam, world::Vec3* hit) {
    if (!hit) return false;

    HWND hwnd = static_cast<HWND>(mainthread::Window());
    if (!hwnd) return false;

    POINT pt;
    if (!GetCursorPos(&pt)) return false;
    if (!ScreenToClient(hwnd, &pt)) return false;

    RECT rc;
    if (!GetClientRect(hwnd, &rc)) return false;

    float const w = static_cast<float>(rc.right - rc.left);
    float const h = static_cast<float>(rc.bottom - rc.top);
    if (w < 1.0f || h < 1.0f) return false;

    // Cursor outside the client area (alt-tabbed, or over another window) would
    // otherwise produce a confident answer for a ray nobody aimed.
    if (pt.x < 0 || pt.y < 0 || pt.x > rc.right || pt.y > rc.bottom) return false;

    // Normalised device coords. Windows counts y downward and the projection
    // counts it upward, so y is flipped here and nowhere else.
    float const ndcx = (static_cast<float>(pt.x) / w) * 2.0f - 1.0f;
    float const ndcy = 1.0f - (static_cast<float>(pt.y) / h) * 2.0f;

    float const aspect = w / h;
    float const tv = std::tan(cam.fov * 0.5f) / std::sqrt(1.0f + aspect * aspect);
    if (tv <= 1e-6f) return false;

    float const sy = 1.0f / tv;
    float const sx = sy / aspect;

    // Ray coefficients along the camera's right/up axes, per unit of depth.
    float const a = ndcx / (sx * kRightSign);
    float const b = ndcy / (sy * kUpSign);

    // Rows: 0 = forward, 1 = right, 2 = up (confirmed from the logged matrix).
    float dir[3];
    for (int i = 0; i < 3; ++i)
        dir[i] = cam.mat[i] + cam.mat[3 + i] * a + cam.mat[6 + i] * b;

    world::Vec3 const start = {cam.pos[0], cam.pos[1], cam.pos[2]};
    world::Vec3 const end   = {cam.pos[0] + dir[0] * kRange,
                               cam.pos[1] + dir[1] * kRange,
                               cam.pos[2] + dir[2] * kRange};

    return world::Raycast(start, end, hit, nullptr);
}

}  // namespace cursorray
