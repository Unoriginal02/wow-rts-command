// Steady.h -- keeps RTS mode from being knocked over by the client itself.
//
// Two small things that are not features and are not probes: they stop a state
// we already own from being taken away from us. Both are read out of the binary
// in Offsets.h under "THE AFK PING-PONG", and both arm themselves on bit 22 --
// the commentator flag, which is the server's and therefore survives every
// field update -- and undo themselves when it goes.
//
//   THE AFK LOOP. Five minutes idle and the client marks you away every frame
//   it is allowed to; playerbots takes the flag off your hero on every AI pass
//   with the selfbot on; round and round, one chat line per turn. The last-input
//   stamp is kept fresh instead, so the client never believes it is idle.
//
//   THE CAMERA. Every turn of that loop (and every other PLAYER_FLAGS update:
//   rested, group leader, PvP) overwrites the client's copy of the flags and
//   takes bit 19 with it -- the bit only WE write. For the frames until the
//   next tick puts it back, the client decides you are not a spectator and
//   re-attaches the camera to the hero. The camera's own call to that predicate
//   is made to answer "yes" while RTS mode is on, so the answer can no longer
//   blink.
//
// WHAT THIS CHANGES THAT YOU MIGHT NOTICE: while RTS mode is on there is no
// auto-AFK and no idle logout. Outside it, both work exactly as before.

#pragma once

namespace steady {

// Once per tick from Publisher, on the main thread -- which is also the thread
// that runs the five bytes being rewritten.
void Tick();

// Gives the bytes back. Called when the DLL is unloaded.
void Shutdown();

}  // namespace steady
