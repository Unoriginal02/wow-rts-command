#include "Camera.h"

#include "Log.h"
#include "Memory.h"
#include "Offsets.h"

namespace camera {

void DumpStruct() {
    uint32_t wf = 0;
    if (!mem::Read<uint32_t>(off::kWorldFrameBase, &wf) || !mem::Plausible(wf)) return;
    uint32_t cam = 0;
    if (!mem::Deref(wf, off::kCameraPtrOffset, &cam)) return;

    RTS_LOG("camera struct @ 0x%08X, floats 0x00..0xB0:", cam);
    for (uint32_t o = 0x00; o <= 0xB0; o += 0x10) {
        float f0 = 0, f1 = 0, f2 = 0, f3 = 0;
        mem::Read<float>(cam + o + 0x0, &f0);
        mem::Read<float>(cam + o + 0x4, &f1);
        mem::Read<float>(cam + o + 0x8, &f2);
        mem::Read<float>(cam + o + 0xC, &f3);
        RTS_LOG("  +0x%02X: %14.5f %14.5f %14.5f %14.5f", o, f0, f1, f2, f3);
    }
}

// Overwrite the camera's field of view.
//
// This is the isometric knob. WoW ships a DIAGONAL fov of 1.5708 rad (90 deg);
// narrowing it flattens the perspective toward orthographic, which is what makes
// a scene read as an RTS map rather than as a place you are standing in.
//
// Written every camera tick rather than once, because the client owns this field
// and rewrites it -- on zone changes, on some spell effects, and whenever it
// runs its own fov smoothing (see the cameraFoVSmoothSpeed CVar). Setting it once
// would hold until the first of those and then silently revert.
//
// The addon's projection follows automatically: Markers.lua derives its scales
// from RTS_CamFov, which is read back from this same field, so a changed fov
// keeps the ground reticle and every projected marker correct.
bool SetFov(float radians) {
    if (!(radians > 0.05f && radians < 3.0f)) return false;

    uint32_t wf = 0;
    if (!mem::Read<uint32_t>(off::kWorldFrameBase, &wf)) return false;
    if (!mem::Plausible(wf)) return false;

    uint32_t cam = 0;
    if (!mem::Deref(wf, off::kCameraPtrOffset, &cam)) return false;

    return mem::Write<float>(cam + off::kCam_Fov, radians);
}

// THE SECTION CUT LIVED HERE AND LEFT WHOLE ON 2026-09-10, with what was learnt
// written down in `Publisher.cpp`. What is left, in case it is ever needed
// again, so nobody has to go looking for it twice:
//
//   * The real near plane is the GLOBAL `0x00ADEED4`, not the camera struct.
//     The projection (0x00606B30) reads it when it rebuilds the frustum.
//   * `cam+0x38` and `cam+0x3C` are a COPY that nobody reads to draw with: they
//     get written, they stay written and they clip nothing. Tried in both
//     directions before believing it.
//   * `cam+0x3C` follows the client's `farclip` CVar, so it serves as a witness
//     for locating fields: move the knob and search for the number.
//
// `Pointer()`, `ReadClip()`, `SetNearClip()` and `FindValue()` took the last
// reader of those two offsets with them.

bool Get(Camera* out) {
    // *(kWorldFrameBase) -> world frame; +kCameraPtrOffset -> active camera.
    uint32_t wf = 0;
    if (!mem::Read<uint32_t>(off::kWorldFrameBase, &wf)) return false;
    if (!mem::Plausible(wf)) return false;

    uint32_t cam = 0;
    if (!mem::Deref(wf, off::kCameraPtrOffset, &cam)) return false;

    Camera c;
    for (int i = 0; i < 3; ++i)
        if (!mem::ReadFloat(cam + off::kCam_Pos + i * 4, &c.pos[i])) return false;

    for (int i = 0; i < 9; ++i)
        if (!mem::ReadFloat(cam + off::kCam_Mat + i * 4, &c.mat[i])) return false;

    if (!mem::ReadFloat(cam + off::kCam_Fov, &c.fov)) return false;
    if (!mem::ReadFloat(cam + off::kCam_Aspect, &c.aspect)) c.aspect = 0.0f;

    *out = c;
    return true;
}

}  // namespace camera
