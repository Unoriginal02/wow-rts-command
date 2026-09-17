// Plates.h -- the client's own nameplates, kept alive under the free camera.
//
// The V bar (and the friendly one) is drawn by the client, not by the addon,
// and in RTS mode it was never drawn at all. The chain is disassembled in
// Offsets.h; the short version is that the nameplate gate measures everything
// from the unit the CAMERA is attached to, and the free camera is free
// precisely because that field is empty.
//
// So this hands the gate a reference of its own -- the hero -- without touching
// the camera, and widens the 41-yard ceiling that only ever made sense for a
// camera sitting on the player's shoulder.
//
// YOUR HERO GETS NO BAR OF HIS OWN, AND THAT IS ON PURPOSE. The gate refuses a
// plate to the unit its reference points at, and behind that the client answers
// "you are not friendly to yourself", which sends him down the hostile path
// where the bit-19 predicate refuses him. Both were found (`/rts plates probe`
// walks the gate's refusals one at a time) and both were patched for one round;
// they came out again when the player said he does not need it. The reading is
// kept in Offsets.h, the two bytes are not written. Everyone else -- bots,
// enemies, anything the client can see -- wears a bar.
//
// IT ARMS ITSELF AND IT DISARMS ITSELF, and the condition is the cause, not a
// switch someone has to remember: the patch goes in only while the camera has
// no target, which is exactly when the gate would otherwise refuse every unit.
// Come out of RTS mode and the client re-attaches the camera, the condition
// goes false, and every byte and the 1681.0 go back. No channel to leave
// half-set, and nothing to forget on the way out.

#pragma once
#include <cstdint>

namespace plates {

// Called once per tick from Publisher, on the main thread -- the same thread
// that executes the bytes being rewritten, so a write cannot land mid-instruction.
void Tick();

// Puts the client back exactly as it was. Called when the DLL is unloaded.
void Shutdown();

}  // namespace plates
