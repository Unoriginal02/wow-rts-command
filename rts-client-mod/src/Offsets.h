// Offsets.h -- every client-specific constant lives here and nowhere else.
//
// Target: World of Warcraft 3.3.5a build 12340, x86, image base 0x00400000.
//
// VERIFIED against F:\Games\WOW WOTLK\Wow.exe (MD5 45892BDEDD0AD70AED4CCD22D9FB5984)
// by static PE analysis:
//   - every code address below resolves inside .text
//   - every function address begins with a real prologue (55 8B EC)
//   - FrameScript_RegisterFunction was disassembled far enough to confirm it
//     reads the global lua_State* from 0x00D3F78C and therefore takes no
//     lua_State parameter
//
// If the client is ever swapped, re-run the probe scripts before trusting these.
// Nothing here is dereferenced without going through Memory.h's guarded reads.

#pragma once
#include <cstdint>

namespace off {

// --- expected image ------------------------------------------------------
constexpr uint32_t kImageBase   = 0x00400000;
constexpr uint32_t kBuildNumber = 12340;

// --- object manager ------------------------------------------------------
constexpr uint32_t kClientConnection = 0x00C79CE0;  // static; runtime pointer
constexpr uint32_t kCurMgrOffset     = 0x2ED0;      // ClientConnection -> ObjectMgr

constexpr uint32_t kObjMgr_LocalGuid   = 0xC0;
constexpr uint32_t kObjMgr_FirstObject = 0xAC;

constexpr uint32_t kObj_Type = 0x14;
constexpr uint32_t kObj_Guid = 0x30;
constexpr uint32_t kObj_Next = 0x3C;

// CGUnit_C world position (players and units share this layout)
constexpr uint32_t kUnit_PosX   = 0x798;
constexpr uint32_t kUnit_PosY   = 0x79C;
constexpr uint32_t kUnit_PosZ   = 0x7A0;
constexpr uint32_t kUnit_Facing = 0x7A8;

// WoWObject type ids
enum ObjectType : uint32_t {
    kTypeObject    = 0,
    kTypeItem      = 1,
    kTypeContainer = 2,
    kTypeUnit      = 3,
    kTypePlayer    = 4,
    kTypeGameObj   = 5,
    kTypeDynObj    = 6,
    kTypeCorpse    = 7,
};

// --- Lua glue ------------------------------------------------------------
// Disassembly-confirmed. See header comment.
constexpr uint32_t kLuaState               = 0x00D3F78C;  // lua_State**

// FrameScript_RegisterFunction(const char* name, lua_CFunction fn), __cdecl,
// reads the global lua_State* from kLuaState itself.
//
// CORRECTED 2026-08-13: was 0x00817FD0, which is an adjacent GETTER that takes
// only a name and does a LUA_GLOBALSINDEX lookup -- it ignored the fn argument,
// so registration silently did nothing (globals came back nil in-game).
// Full disassembly of 0x00817F90 confirms the real register body:
//   lua_pushcclosure(L, fn, 0) -> lua_pushstring(L, name)
//   -> lua_setfield(L, LUA_GLOBALSINDEX=-10002, name)
constexpr uint32_t kFrameScript_Register   = 0x00817F90;  // (const char*, lua_CFunction)
constexpr uint32_t kFrameScript_Execute    = 0x00819210;

constexpr uint32_t kLua_GetTop      = 0x0084DBD0;
constexpr uint32_t kLua_SetTop      = 0x0084DBF0;
constexpr uint32_t kLua_IsNumber    = 0x0084DEB0;
constexpr uint32_t kLua_ToNumber    = 0x0084E030;
constexpr uint32_t kLua_ToLString   = 0x0084E0E0;
constexpr uint32_t kLua_PushNil     = 0x0084E280;
constexpr uint32_t kLua_PushNumber  = 0x0084E2A0;
constexpr uint32_t kLua_PushString  = 0x0084E350;

// Deliberately absent: lua_type. The commonly cited 0x0084DD60 is NOT a
// function entry on this binary (bytes are mid-function), so it is unused
// rather than guessed at. Argument checks use gettop + isnumber + tolstring.

// --- world / movement ------------------------------------------------
// CGWorldFrame::Intersect -- the client's own terrain/collision raycast.
// 0x0077F310 is a thunk to the body at 0x007A3B70; call the thunk.
//
// Signature confirmed from the in-game caller at 0x00568C8E (capstone):
//   bool __cdecl Intersect(const Vec3* start, const Vec3* end,
//                          Vec3* hitOut, float* distInOut,
//                          uint32 flags, uint32 zero)
// The caller inits distInOut = 1.0 and passes flags 0x00100171 (terrain + WMO +
// M2 collision). Returns true on hit; hitOut = start + dist*(end-start).
constexpr uint32_t kCGWorldFrame_Intersect = 0x0077F310;
constexpr uint32_t kIntersectFlags         = 0x00100171;

// CGPlayer_C::ClickToMove(uint32 clickType, uint64* guid, Vec3* pos, float prec)
// __thiscall (ecx = local player object). clickType 4 = "move to point",
// confirmed from the in-game type-4 caller at 0x0072B71D. NOT CALLED YET --
// player mouse-move is the last, riskiest step; recorded here once verified.
constexpr uint32_t kCGPlayer_ClickToMove = 0x00727400;
constexpr uint32_t kClickToMove_Move     = 0x4;

// --- unit highlight (native selection marker) ------------------------
// CGUnit_C::SetHighlight(int reason) / ClearHighlight(int reason), __thiscall,
// one stack arg (ret 4). Sets or clears bit (1 << (reason + 0x18)) in the unit's
// flags at +0xBC, then writes the highlight RGB into the unit's model render
// object (virtual call vtable+0xD4) at +0x18C/+0x190/+0x194, intensity at +0x1B8.
//
// Both functions re-disassembled 2026-08-14 and they do exactly this:
//   SetHighlight:   flags |= 1 << (reason + 0x18)
//                   if (this->vtbl[0xB4]() != 0) return;        <-- SILENT BAIL
//                   *(uint64*)kHighlightedGuid = this->guid     <-- ONE unit only
//                   render = this->vtbl[0xD4]()
//                   if (render) { render[0x18C..0x194] = colour from Fn7ECEF0()
//                                 if ((flags & 0x7000000) != 0x4000000)
//                                     render[0x1B8] = 1.0f }
// The bail at vtbl+0xB4 leaves the flag bit set but paints nothing, so a unit can
// read as "lit" (Has() true) while staying visually untouched. Diag() logs it.
//
// CORRECTED 2026-08-15. An earlier note here said the ground circle "IS NOT"
// per-unit and that an RTS marker under every bot could not come from this path.
// That was wrong, and it cost the dot-ring detour. The renderer really does
// compare each unit's guid against the single global below -- but the compare is
// the ONLY thing that is global. See the kCircleGate* block for the walk.
constexpr uint32_t kCGUnit_SetHighlight   = 0x00743C70;
constexpr uint32_t kCGUnit_ClearHighlight = 0x00743BC0;
constexpr uint32_t kUnit_HighlightFlags   = 0xBC;   // bits 24..26
constexpr uint32_t kHighlightReasonTarget = 0;      // ground circle + glow
constexpr uint32_t kHighlightReasonHover  = 1;      // glow only
constexpr uint32_t kHighlightReasonFree   = 2;      // unused by the client

// Virtual slots used by SetHighlight, so Diag() can take the same two branches.
constexpr uint32_t kVtbl_HighlightSuppressed = 0xB4;   // nonzero => paint nothing
constexpr uint32_t kVtbl_GetRenderObject     = 0xD4;
constexpr uint32_t kRender_HighlightR        = 0x18C;  // then G 0x190, B 0x194
constexpr uint32_t kRender_HighlightAmount   = 0x1B8;  // float, 1.0 = fully lit

// Guid of the one unit currently wearing the ground circle (see above).
constexpr uint32_t kHighlightedGuid = 0x00CD7770;   // 8 bytes

// --- native ground circle, per unit ----------------------------------------
//
// THE REAL ONE. Found 2026-08-16 after the gate below turned out to drive
// something else entirely (see kCircleGate*, kept as a warning).
//
// The trail starts at the ObjectSelectionCircle CVar object, which has exactly
// one consumer: 0x00743EF4, inside a per-unit virtual at 0x00743EC0. That
// function decides whether a unit should wear a circle and, if so, writes its
// guid into a slot on the scene context it is handed:
//
//   0x00743ECF  cmp against [0x00BD07B0]  ; the current TARGET guid
//   0x00743EF2  je  ...                   ; ...but never on yourself
//   0x00743EF9  cmp [ObjectSelectionCircle + 0x30], 0
//   0x00743F02  ctx[0x380] = guid.lo      ; slot A
//   0x00743F08  ctx[0x384] = guid.hi
//   0x00743F3C  ctx[0x388] = guid.lo      ; slot B, fed from 0x005D33C0
//
// The slots are drained once per frame by 0x004F6F90, __thiscall(ctx), which
// for each of the two slots does exactly this:
//
//   read guid -> if zero, skip
//   obj = ClntObjMgrObjectPtr(guid, 1, file, line)   (0x004D4DB0)
//   if obj: obj->vtbl[0x6C]()                        <-- draws the circle
//   zero the slot
//
// So the client's design is TWO circles -- your target and your mouseover --
// and the draw is an ordinary virtual call on the unit.
//
// That makes the RTS version almost free, and needs no patched comparison and
// no knowledge of what vtbl+0x6C actually is: hook 0x004F6F90, let the original
// run to draw the client's own two, then for each of our units write its guid
// into slot A and call the original again. Every call resolves one unit, draws
// its circle and clears the slot behind itself. We reuse the client's own draw
// path verbatim, N times, instead of reimplementing any part of it.
//
// Nine bytes at the entry, all position-independent, which is room enough for a
// five-byte jmp and a relocatable trampoline:
//     56              push esi
//     8B F1           mov  esi, ecx
//     8B 86 80030000  mov  eax, [esi+0x380]
constexpr uint32_t kCircleDraw       = 0x004F6F90;  // __thiscall(ctx), drains slots
constexpr uint32_t kCircleDrawResume = 0x004F6F99;  // entry + 9
constexpr uint32_t kCircleStolen     = 9;
constexpr uint32_t kCircleSlotA      = 0x380;       // ctx + this = guid lo/hi
constexpr uint8_t kCircleDrawBytes[kCircleStolen] = {
    0x56, 0x8B, 0xF1, 0x8B, 0x86, 0x80, 0x03, 0x00, 0x00,
};

// THE CIRCLE'S COLOUR. Found 2026-08-16, after the circles came up in game all
// the same shade no matter what state a unit was in.
//
// The drawing class is the one at vtable 0x00A331C8 -- confirmed by its own
// constructor at 0x00706462 (`mov [esi], 0xA331C8`) -- and it is the ONLY one of
// the six classes carrying 0x00743EC0 at vtable+0x88 whose vtable+0x6C is a real
// function rather than the inherited `ret`. That function is 0x007062F0: it
// builds the quad from the unit's position and radius, then calls the textured
// draw at 0x007E4370 passing the ADDRESS of this dword:
//
//   0x0070640D  push 0x00ACC3F8      ; &colour
//   0x00706413  call 0x007E4370
//
// It holds 0xFF7F7F7F -- opaque mid-grey -- and is a plain constant, which is
// the whole reason every circle looked identical. 0x00521F95 reads the same
// dword by value next to lookups in the reaction colour tables at 0x00BD0C8C /
// 0x00BD0C94, which is what identifies it as a colour rather than a handle.
//
// Since our hook calls the draw once per unit, writing this immediately before
// each call gives genuine per-unit colour. The original value is saved on entry
// and put back on the way out, so the client's own target and mouseover circles
// keep their normal look.
constexpr uint32_t kCircleColour     = 0x00ACC3F8;   // 0xAARRGGBB
constexpr uint32_t kCircleColourGrey = 0xFF7F7F7F;   // the client's own value

// *** 0x00ACC3F8 IS NOT THE CIRCLE'S TINT. TWO IN-GAME TESTS SAY SO. DO NOT
// *** SPEND A THIRD BUILD ON IT WITHOUT NEW EVIDENCE.
//
// Attempt 1: write the dword immediately before each per-unit draw call, and
// restore it afterwards. Result: every circle grey.
// Attempt 2: repoint the draw's `push imm32` at a per-unit dword of our own, so
// that the colour is correct whether the pointer is dereferenced at call time or
// at frame flush. Result: every circle grey.
//
// Attempt 2 is immune to the read-timing question that killed attempt 1, so the
// negative is not about WHEN the value is read -- this address is simply not
// what tints the circle. Everything below about how it was identified still
// reads convincingly, which is the point of writing it down: it is a plausible
// wrong answer and someone will find it again.
//
// Where to look next, when this is picked back up: probe at runtime rather than
// statically. Log the seven arguments at the 0x007E4370 call site for a live
// unit, and walk into 0x007E3E80 (which receives the pointer) to find where the
// vertex colour is actually set. The colour may not be a parameter at all -- it
// may be render state bound before the draw, or baked into the circle texture.
//
// The state colours already reach the MODEL GLOW (Highlight.cpp, protocol bit
// 28, `/rts ring tint`), which does per-unit RGB and has worked since Stage 5d.
// That is the working answer for state-at-a-glance in the meantime.
//
// WRITING THAT GLOBAL IS NOT ENOUGH -- proved in game 2026-08-16. The table
// diagnostic showed correct, varied, per-unit colours going in (0xFFFF1A1A red,
// 0xFF2673FF blue) while every circle still rendered grey. So the draw does not
// read the dword when it is called: it keeps the POINTER and dereferences it
// later, when the frame's batch is flushed -- by which time our hook has
// restored the client's grey and every circle reads the same restored value.
//
// The fix is to stop sharing one address. `push 0xACC3F8` is a plain push imm32
// at 0x0070640D (68 F8 C3 AC 00), so the operand can be repointed at a DIFFERENT
// dword per call -- each unit's own colour, in our own table, which stays alive
// long past the flush. A late read then still finds the right colour, and this
// works whether the dereference is immediate or deferred.
constexpr uint32_t kCirclePushImm = 0x0070640E;   // the imm32 inside the push
constexpr uint8_t  kCirclePushOp  = 0x68;         // verified at 0x0070640D

// --- the dead end, kept deliberately ----------------------------------------
// TESTED IN GAME 2026-08-16: this is NOT the ground circle. The hook installed,
// ObjectSelectionCircle was 1, and the match-all diagnostic armed the effect for
// every unit on screen -- and no circle appeared. Everything below about the
// walk being per-unit is correct; the conclusion that the effect it arms is the
// CIRCLE was not. The client's own value at 0x00D38CAC is 0xFF1D3C54 -- a dark
// slate blue, which is a model emissive tint, not a circle.
//
// Left here in full because the mechanism is real and someone will want it: this
// is how you get a per-unit model tint that the batch renderer applies, as
// opposed to the per-render-object one Highlight.cpp writes. The circle lives at
// kCircleDraw above.
//
// Disassembled 2026-08-15 from the per-unit render walk at 0x007964A0. One pass
// of that loop, for one unit, does this:
//
//   0x00796753  call 0x7A9160     ; per-unit setup -- ENDS with [0xD1BEFC] = 0
//   0x00796758  mov  eax,[edi+0x148]   ; this unit's guid, low
//   0x0079675E  mov  ecx,[edi+0x14C]   ;                   high
//   0x0079676D  cmp  eax,[0xCD7770]    ; <-- the entire gate
//   0x00796773  jne  0x796792
//   0x00796775  cmp  ecx,[0xCD7774]
//   0x0079677B  jne  0x796792
//   0x0079677D  mov  eax,[ebp-0x90]    ; = 0xD38B00, the client's config struct
//   0x00796783  mov  ecx,[eax+0x1AC]   ; its stored circle colour
//   0x00796789  push ecx
//   0x0079678A  call 0x7A8430          ; [0xD1BEFC] = ecx
//   0x00796792  ...
//   0x007967AA  call 0x7ABF50          ; model submit -- consumes 0xD1BEFC
//
// The effect word at 0xD1BEFC is CLEARED per unit, ARMED per unit and CONSUMED
// per unit, so the renderer is already fully per-unit; only the SELECTOR is a
// single global. Replacing the compare with a table lookup gives one circle per
// selected bot, drawn by the client, occluded and terrain-draped for free.
//
// 0xD1BEFC is not a boolean either. Its consumers at 0x007A9547 and 0x007AC8BC
// do byte-wise averaging (`and 0x01010100`, the classic SWAR mean), so it is a
// packed colour -- which means per-unit COLOUR comes free with per-unit
// selection. Byte order is taken to be 0xAARRGGBB, from the sibling path at
// 0x007A8483 building a colour as bytes 00 00 00 FF with alpha last.
constexpr uint32_t kCircleGateSite   = 0x0079676D;  // patch here
constexpr uint32_t kCircleGateTake   = 0x0079677D;  // "draw it" continuation
constexpr uint32_t kCircleGateSkip   = 0x00796792;  // "no circle" continuation
constexpr uint32_t kCircleEffect     = 0x00D1BEFC;  // packed colour, per unit
constexpr uint32_t kCircleColourSrc  = 0x00D38CAC;  // the client's own colour

// The 16 bytes at kCircleGateSite are nothing but the two compares and their
// jumps, which is ample room for a 5-byte jmp rel32 plus padding. They are
// checked byte-for-byte before anything is written, so a different client can
// never be patched by accident.
constexpr uint32_t kCircleGateLen = 16;
constexpr uint8_t kCircleGateBytes[kCircleGateLen] = {
    0x3B, 0x05, 0x70, 0x77, 0xCD, 0x00,   // cmp eax, [0x00CD7770]
    0x75, 0x1D,                           // jne 0x00796792
    0x3B, 0x0D, 0x74, 0x77, 0xCD, 0x00,   // cmp ecx, [0x00CD7774]
    0x75, 0x15,                           // jne 0x00796792
};

// "ObjectSelectionCircle" -- the CVar that lets the circle be drawn at all.
// Registered at 0x007460D9; the resulting CVar object is cached here, int at
// +0x30 like every other CVar.
constexpr uint32_t kCVar_ObjectSelectionCircle = 0x00CA12C8;

// The client's own gate on highlighting, read at 0x00513CF0 and 0x0051F84A:
//     highlightsOn = *kHighlightGateFlag != 0 || cvar("unitHighlights") != 0
// The CVar object for "unitHighlights" ("Whether the highlight circle around
// units should be displayed") is registered at 0x0051ED08 and stored here; its
// int value sits at +0x30. We call SetHighlight directly so the gate does not
// block us, but 0x00513CF0 re-runs on cvar change and will clear reasons 0/1.
constexpr uint32_t kHighlightGateFlag = 0x00AC80A8;
constexpr uint32_t kCVar_UnitHighlights = 0x00BD09DC;

// --- CVars as the addon -> DLL channel --------------------------------
// The DLL can push data to Lua (FrameScript_Execute) but Lua cannot call back:
// registering a C function whose pointer lives outside Wow.exe throws ERROR #134
// and kills the client. A CVar closes the loop, because it is memory BOTH sides
// can reach -- Lua writes it with SetCVar, we read it out of the object.
//
// CVar object layout, from the setter at 0x007667B0:
//     lea ecx,[obj+0x20]; call strAssign   -> value as a string
//     push v; call atoi; mov [obj+0x30],eax -> value as an int
//     call atof; fstp [obj+0x2C]            -> value as a float
// so an addon can hand us a full 32-bit integer through any writable CVar.
//
// Lookup is the client's own hash table: __thiscall with ecx = the table.
//     mov ecx, 0x00CA19FC; push name; call 0x0055F4D0  (seen at 0x00767FE9)
constexpr uint32_t kCVarTable    = 0x00CA19FC;
constexpr uint32_t kCVarLookup   = 0x0055F4D0;
constexpr uint32_t kCVar_StringValue = 0x20;
constexpr uint32_t kCVar_FloatValue  = 0x2C;
constexpr uint32_t kCVar_IntValue    = 0x30;

// --- camera ----------------------------------------------------------
// Active camera = *( *(kWorldFrameBase) + kCameraPtrOffset ). This chain
// appears verbatim dozens of times, e.g. 0x004F6653 / 0x007E52A3.
constexpr uint32_t kWorldFrameBase  = 0x00B7436C;
constexpr uint32_t kCameraPtrOffset = 0x7E20;

// Camera struct offsets.
// pos CONFIRMED at +0x08 by disassembly of GetCameraPosition (0x004F6650):
//   mov edx,[cam+8]; ...[cam+0xC]; ...[cam+0x10]  -> x,y,z
// matrix/fov are the standard 3.3.5a layout, validated live before use.
constexpr uint32_t kCam_Pos    = 0x08;   // 3 floats (CONFIRMED)
constexpr uint32_t kCam_Mat    = 0x14;   // 3x3, rows at +0x14/+0x20/+0x2C
constexpr uint32_t kCam_Fov    = 0x40;   // float, radians
constexpr uint32_t kCam_Aspect = 0x44;   // float

}  // namespace off
