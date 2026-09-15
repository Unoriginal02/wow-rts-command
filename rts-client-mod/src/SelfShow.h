// SelfShow.h -- THE BODY PROBE. It is an instrument, not a feature.
//
// The hero turns invisible the moment his player carries PLAYER_FLAGS_UBER, and
// the chain is disassembled in Offsets.h: a per-unit "submit this unit"
// (0x0073A890) asks 0x006DE980 about THAT player and skips the submit if the
// answer is yes. The bots do not carry the flags, so only yours disappears --
// which is the exact symptom -- and forcing the predicate to true hid everyone,
// which is the other half of the proof.
//
// This FIXES nothing by itself and does NOT switch itself on. It answers two
// questions with two independent switches, in a single session:
//
//   1. Are the flags enough, with no commentator mode and no server involved?
//      They are written into the CLIENT's copy. If the hero disappears, yes.
//   2. With the flags set, does he come back by nulling THAT jump and only it?
//      If he does, the cure is two bytes and the 18 callers need no touching.
//
// It ships off and behind a command, which is the rule that cost the afternoon
// of 2026-09-06 (the ring drawn twice shipped armed) and the one of 2026-09-08
// (the 0x006DE980 patch shipped armed and hid everybody).

#pragma once
#include <cstdint>

namespace selfshow {

// Called once per tick from Publisher, on the main thread.
void Tick();

// Undoes the byte patch if it is in place. Called when the DLL is unloaded.
void Shutdown();

}  // namespace selfshow
