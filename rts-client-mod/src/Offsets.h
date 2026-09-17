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

// EL SUELO SIN LOS EDIFICIOS -- las banderas que dejan SOLO el terreno.
//
// Sale del cuerpo de la funcion (0x007A3B70), que tiene exactamente DOS
// mitades y cada una se enciende con su propia mascara:
//
//   007A3B8A  test eax, 0x40F300FF   -> call 0x007A30D0   ; objetos
//   007A3C2E  test eax, 0x40F3010F   -> call 0x007A39F0   ; terreno
//
// Cual es cual no se supone, se lee en las dos: 0x007A30D0 mide el largo del
// rayo, carga 6000 como tope y recorre una estructura espacial -- WMO y
// doodads; 0x007A39F0 convierte las dos puntas a indices de casilla con
// `fmul [0x00A3FDA0] / fistp` contra el global 0x009E2ACC, que es la rejilla
// de ADT. Terreno.
//
// El bit 0x100 esta en la segunda mascara Y NO EN LA PRIMERA, asi que
// `flags = 0x100` salta el bloque de objetos ENTERO -- no lo filtra despues,
// no llega a entrar. Es la unica pareja de bits del juego que separa las dos
// mitades limpiamente: 0x01..0x80 solo estan en la de objetos, y 0x0F y
// 0x00F30000 estan en las dos (0x00100000, el que llevan las banderas de
// arriba, es uno de esos: no distingue nada).
//
// Para que sirve: la camara libre medía su altura contra ESTO -- lo primero
// que hay bajo ella -- y lo primero que hay bajo ella al acercarse a una casa
// es el TEJADO, asi que la camara subia sola y no se podia entrar. Con el
// terreno solo, un tejado deja de ser suelo.
constexpr uint32_t kIntersectFlagsTerrain  = 0x00000100;

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

// ================== CAMINO DESCARTADO: EL CORTE SECCIONAL ==================
//
// DESCARTADO EL 2026-09-10 y sin un solo lector en el arbol: mover el plano
// cercano recorta TODA la escena a una distancia, y el tajo se lleva medio
// mundo por delante en vez de un techo. Estas direcciones se quedan porque este
// fichero guarda cada camino descartado CON SU EVIDENCIA -- son horas de
// analisis y ninguna de ellas hace nada por si sola. Si alguien vuelve por
// aqui, que lea antes el porque en `Publisher.cpp` y `Camera.cpp`.
//
// EL PLANO CERCANO ES UN GLOBAL, NO UN CAMPO DE LA CAMARA.
//
// Y ese es todo el fallo de las dos primeras rondas. El struct de camara SI
// tiene un par que parece cerca/lejos -- del volcado en juego:
//
//   +0x30:   0.00000    1.00000    0.20000  791.66669
//   +0x40:   1.57080    1.60000        FOV      aspect
//
// +0x38 = 0.20 y +0x3C = 791.67, pegados al FOV y al aspect. Parecia de manual.
// Es una COPIA: `+0x3C` sigue al CVar `farclip` (medido con el buscador: 300 y
// 700 aparecen ahi y en ningun otro sitio del struct), pero escribirlo no mueve
// el horizonte -- probado en las dos direcciones y con el valor confirmado
// escrito y persistente en el log. Nadie lee esa copia para dibujar.
//
// La proyeccion se construye en 0x00606B30 leyendo DOS GLOBALES:
//
//   00606B41  fld dword ptr [0x00CD7748]   ; lejos
//   00606B4B  fld dword ptr [0x00ADEED4]   ; cerca
//   00606B54  call 0x00607C20              ; construye el frustum
//
// Se leen cada vez que se construye, asi que basta con reescribir el global
// cada tick, igual que el FOV. Nada de banderas ni de invalidar.
//
// Y hay un CVar `nearclip` REGISTRADO -- descripcion "Near clip plane distance",
// por defecto 0.2 -- que **es inerte**: su manejador (0x0077F490) ignora el
// argumento y escribe la constante 0.2 pase lo que pase. `SetCVar("nearclip")`
// no habria hecho nada nunca, y habria parecido que el cliente no lo soporta.
// Es el mismo modo de fallo que `guildMemberNotify`, pero al reves: la cadena
// existe, el CVar existe, y lo que no hace nada es el manejador.
//
//   0077F490  fld  dword ptr [0x009E8D84]   ; 0.2, la constante
//   0077F496  fstp dword ptr [0x00ADEED4]
//   0077F49C  ret
//
// Ojo: el setter de `farclip` (0x00780800) tambien reinicia el cercano a 0.2 al
// acabar. Da igual mientras se reescriba cada tick, pero explica por que un
// cambio de distancia de vision "apagaria" el corte si esto fuera una sola
// escritura.
constexpr uint32_t kNearClipGlobal = 0x00ADEED4;   // float, yardas
constexpr uint32_t kFarClipGlobal  = 0x00CD7748;   // float, yardas (no se toca)

// Los dos de la camara se quedan SOLO para leerlos: son la copia que sigue al
// CVar y sirven de diagnostico, no de mando.
constexpr uint32_t kCam_NearClip = 0x38;  // float, yardas
constexpr uint32_t kCam_FarClip  = 0x3C;  // float, yardas (no se toca)


// ---------------------------------------------------------------------------
// "Am I a spectator?" -- the gate that hides YOUR OWN model.  (sonda del cuerpo)
//
// 0x006DE980 es __thiscall(player) y contesta "este jugador es espectador":
//
//   006DE9A6  mov ecx, [player + 0x1008]   ; bloque de campos PLAYER
//   006DE9AC  mov ecx, [ecx + 8]           ; PLAYER_FLAGS
//   006DE9B1  shr edx, 0x13 ; test dl,1    ; bit 19 APAGADO -> false
//   006DE9B9  shr ecx, 0x16 ; test cl,1    ; bit 22 ENCENDIDO -> true, y ya
//   006DE9C5  cmp [eax + 8], 4             ; si no, hace falta un mapa de arena
//
// Tiene DIECIOCHO llamantes -- enumerados, no supuestos -- y por eso forzarlo a
// `mov eax,1 / ret` el 2026-09-08 no dejo ver a NADIE: se le estaba diciendo al
// cliente entero que todo jugador era espectador. Lo que hay que tocar es UN
// llamante, o los flags que lee.
//
// El llamante que esconde el modelo esta en 0x0073A890, un "prepara/emite esta
// unidad" por unidad, y su cola es:
//
//   0073AA99  mov ecx, [edi + 8]     ; descriptores
//   0073AA9C  mov edx, [ecx + 8]     ; OBJECT_FIELD_TYPE
//   0073AA9F  shr edx, 4 ; test dl,1 ; TYPEMASK_PLAYER (0x10)
//   0073AAA7  mov ecx, edi
//   0073AAA9  call 0x006DE980        ; ¿este jugador es espectador?
//   0073AAAE  test al, al
//   0073AAB0  jne 0x0073AB17         ; SI -> se salta la emision   <-- AQUI
//   0073AAB5  lea ecx, [edi + 0x788]
//   0073AABB  call 0x006EF230        ; NO -> la emite
//
// Se le pregunta POR JUGADOR, asi que solo se salta el que tenga los flags --
// que es exactamente el sintoma: tu heroe no, los bots si.
constexpr uint32_t kIsSpectator      = 0x006DE980;
constexpr uint32_t kSelfSubmitFn     = 0x0073A890;  // por unidad, para contexto
constexpr uint32_t kSelfSkipJne      = 0x0073AAB0;  // los dos bytes del salto
constexpr uint8_t  kSelfSkipBytes[2] = {0x75, 0x65};  // jne +0x65, verificado

// LOS DIECIOCHO SITIOS DE LLAMADA DEL PREDICADO, PARA APAGARLOS DE UNO EN UNO.
//
// Medido, no supuesto: barrido de `call rel32` (0xE8) sobre todo el .text
// quedandose con los que apuntan a 0x006DE980. Salen 18 en 17 funciones --
// 0x005FBA60 llama dos veces.
//
// Por que de uno en uno y no forzando el predicado: forzarlo el 2026-09-08 le
// dijo al cliente que TODO jugador era espectador y dejo la pantalla sin nadie.
// Un sitio de llamada es cinco bytes, es local, y los otros diecisiete siguen
// contestando la verdad. `call rel32` (5) -> `xor eax,eax` + 3 nop (2+3): mismo
// tamano, y ESE llamante ve "no es espectador".
//
// Es el diagnostico por eliminacion, que aqui vale mas que seguir leyendo: con
// los dos flags puestos el heroe SI desaparece (medido 2026-09-09 20:29), o sea
// que el mecanismo esta vivo y se puede acorralar apagando mitades.
constexpr uint32_t kSpecCallSites[] = {
    0x004FA69D,  // [ 0]
    0x00519039,  // [ 1]
    0x005245B3,  // [ 2]
    0x00569B7B,  // [ 3]  banda del comentarista: son las propias funciones de
    0x00569CFB,  // [ 4]  la API (Follow, SetCamera, GetCamera, Collision...),
    0x0056A11B,  // [ 5]  o sea sus porteros. Apagarlos CIERRA la camara libre.
    0x0056A2C8,  // [ 6]
    0x0056AB14,  // [ 7]
    0x0056B83D,  // [ 8]
    0x0056B919,  // [ 9]
    0x005FA6F5,  // [10]  banda que ademas toquetea una palabra de flags de
    0x005FA7D1,  // [11]  OBJETO (`or [esi+4], 0x80000` en 0x005FB1E9), asi que
    0x005FB2AE,  // [12]  de "interfaz" tiene poco. Candidata de verdad.
    0x005FBAC7,  // [13]
    0x005FBC02,  // [14]
    0x005FBEBA,  // [15]
    0x006E085C,  // [16]
    0x0073AAA9,  // [17]  el de la emision por unidad, ya descartado por B1
};
constexpr int kSpecCallSiteCount = 18;

// EL ESCONDITE. Sitio [16] = 0x006E085C, dentro de 0x006E0840.
//
// Encontrado el 2026-09-09 POR ELIMINACION, no leyendo: con los dos flags
// puestos se apagaron los dieciocho a la vez (vuelve el modelo -> el predicado
// ES el mecanismo) y luego de uno en uno hasta que uno solo lo devolvio.
//
//   006E0855  call 0x730F30              ; calcula el valor
//   006E085A  mov  ecx, esi
//   006E085C  call 0x006DE980            ; ¿este jugador es espectador?
//   006E0861  test al, al
//   006E0863  je   0x006E0871            ; NO -> sigue evaluando
//   006E0866  mov  dword ptr [ebx], 1    ; SI -> fuerza el resultado a 1
//   006E086E  ret  0xc
//
//   006E0871  test dword ptr [esi+0xa30], 0x400000   ; la rama normal tiene
//   006E087D  cmp  dword ptr [esi+0x18b8], 0         ; sus propias razones
//   006E0884  jne  0x006E0865                        ; para el mismo *out = 1
//
// `ebx` es el tercer argumento, un int* de salida. Ser espectador entra por la
// puerta de atras en un calculo que ya existia -- por eso no aparecia buscando
// "quien esconde un modelo": aqui no se esconde nada, se contesta 1.
//
// 0x006E0840 no tiene NI UN `call rel32` que le apunte: es virtual, y se llama
// por vtable. Por eso el camino estatico no llegaba, y por eso la enumeracion
// por eliminacion valia mas que seguir desensamblando.
//
// El predicado pregunta por `esi`, o sea POR ESA UNIDAD, asi que apagar este
// sitio solo cambia el resultado de quien lleve los flags -- que somos nosotros
// y nadie mas.
constexpr uint32_t kSelfHideCall = 0x006E085C;  // = kSpecCallSites[16]
constexpr int      kSelfHideSite = 16;

// EL PARPADEO, que es OTRA COSA y llega por el OTRO predicado.
//
// Con los flags puestos, el resalte del raton sobre otros jugadores y el
// circulo de destino en el suelo parpadean, y el circulo ademas ALTERNA entre
// dos posiciones. Visto en juego 2026-09-09 con el heroe ya visible.
//
// 0x0073DAB0 tiene exactamente esa forma -- un conmutador de 500 ms detras del
// segundo predicado, 0x00729740:
//
//   0073DB42  call 0x00729740          ; el OTRO predicado (37 sitios)
//   0073DB47  test al, al
//   0073DB49  je   0x0073DBCA          ; false -> se salta todo el bloque
//   0073DB50  or   dword ptr [esi+0xa30], 0x10
//   0073DB5B  sub  edx, 0x1f4          ; 500 ms
//   0073DB65  cmp  dword ptr [0xca12bc], eax
//   0073DB6B  sete al
//   0073DB6E  mov  dword ptr [0xca12bc], eax   ; conmuta 0/1 cada 500 ms
//
// Es un CANDIDATO medido en forma, no una conclusion: el ritmo cuadra y el
// mecanismo cuadra. Se apaga con su interruptor y el juego contesta.
constexpr uint32_t kBlinkPredicate = 0x00729740;
constexpr uint32_t kBlinkCall      = 0x0073DB42;

// Y EL BIT 19 APAGA ADEMAS "PUEDO ATACAR", QUE ES DE DONDE SALIO LA ESPADA.
//
// 0x00729740 -- el mismo predicado del parpadeo, 37 llamantes -- empieza asi:
//
//   00729746  mov  eax, [ebx + 8]        ; ebx = el SUJETO (ecx a la entrada)
//   00729749  mov  ecx, [eax + 8]        ; OBJECT_FIELD_TYPE
//   0072974C  shr  ecx, 4 ; test cl, 1   ; ¿es un JUGADOR?
//   00729752  je   0x0072976B            ; no -> sigue evaluando de verdad
//   00729754  mov  edx, [ebx + 0x1008]   ; si -> sus PLAYER_FIELDS
//   0072975A  mov  eax, [edx + 8]        ; PLAYER_FLAGS
//   0072975D  shr  eax, 0x13 ; test al,1 ; bit 19 = PLAYER_FLAGS_UBER
//   00729762  je   0x0072976B            ; APAGADO -> sigue        <-- AQUI
//   00729764  xor  al, al                ; ENCENDIDO -> FALSO, y ya
//   00729766  pop ebx / pop ebp / ret 4
//
// O sea: **un jugador con el bit 19 puesto no puede con nada.** Y ese predicado
// es literalmente el de `UnitCanAttack`: la funcion Lua (0x0060D730, resuelta
// por la tabla de pares nombre/puntero) lo llama en 0x0060D786 y devuelve lo
// que conteste. Con la camara libre encendida `UnitCanAttack("player", X)` es
// falso para TODO -- de ahi que no salga la espada al pasar por encima de un
// bicho, que el boton derecho no ataque, y que `HoverUnit().hostile` del addon
// sea siempre falso.
//
// POR QUE EL ICONO DE MISION Y LA BOLSA DE BOTIN SI SALEN: no pasan por aqui.
// `UnitCanCooperate` usa otro predicado (0x00729B30) y el botin mira si el
// cadaver es saqueable. Esa asimetria -- unas cosas si y atacar no -- es la
// firma del bit 19 y es lo que llevo hasta esta linea.
//
// EL BIT 19 NO SE PUEDE QUITAR: `0x006DE980` lo exige para abrir la camara de
// comentarista (`shr edx,0x13 / test dl,1` -> apagado, no eres espectador), y
// sin camara no hay modo RTS. Asi que lo que se toca es ESTE veredicto, un
// byte: `je rel8` (0x74) -> `jmp rel8` (0xEB), mismo destino y misma longitud,
// o sea que el bit 19 deja de significar "no puedes con nada" y el predicado
// sigue contestando lo que de verdad toque (faccion, muerto, fuera de rango).
//
// El radio de la explosion esta ACOTADO, no supuesto: el corto solo dispara
// cuando el SUJETO es un jugador con el bit 19, y el unico que lo lleva somos
// nosotros. Los bots no. Los 37 llamantes siguen viendo la verdad para todos
// los demas. Es lo contrario del parche del 2026-09-08, que reescribio un
// predicado compartido y le dijo al cliente que todo jugador era espectador.
constexpr uint32_t kCanActUberJe      = 0x00729762;
constexpr uint8_t  kCanActUberBytes[2] = {0x74, 0x07};  // je +7, verificado

// PLAYER_FLAGS tal y como lo lee el predicado. NO es el array de descriptores
// corriente (ese cuelga de +0x08); es un segundo bloque propio de CGPlayer_C.
// Se escribe donde el predicado LEE, que es la unica direccion que garantiza
// que lo vea.
constexpr uint32_t kPlayer_FieldsPtr   = 0x1008;
constexpr uint32_t kPlayerFields_Flags = 0x08;
constexpr uint32_t kPlayerFlagUber        = 0x00080000;  // bit 19, obligatorio
constexpr uint32_t kPlayerFlagCommentator = 0x00400000;  // bit 22, salta la arena

// ---------------------------------------------------------------------------
// NAMEPLATES -- why the V bar disappears the moment the RTS camera comes up.
//
// Read out of Wow.exe, not guessed. The gate that decides whether a unit gets a
// nameplate is 0x0072B060, __thiscall(unit, out Vec3), and it OPENS like this:
//
//   0072B0A9  call 0x004F5960          ; cam = *(0x00B7436C) -> [+0x7E20]
//   0072B0AE  test eax, eax / je       ; no camera -> no plate
//   0072B0B2  mov  ecx, [eax + 0x8C]   ; \ the GUID of the unit the camera
//   0072B0B8  mov  edx, [eax + 0x88]   ; / is ATTACHED to
//   0072B0CC  call 0x004D4DB0          ; look it up (typemask 8 = unit)
//   0072B0D9  jne  ...                 ; NOT FOUND -> returns 0 FOR EVERY UNIT
//
// and it CLOSES with a squared distance from that same unit:
//
//   0072B331  fcomp dword ptr [0x00ADAA7C]   ; 1681.0 = 41 yards, squared
//
// Now the other half. `CGWorldFrame::UpdateCamera` (0x004FA5F0) asks
// 0x006DE980 "am I a spectator?" -- call site [0] of the eighteen listed above,
// 0x004FA69D -- and when the answer is yes it CLEARS the camera's target:
//
//   004FA6B8  je 0x4FA6C3              ; already empty, nothing to do
//   004FA6BA  push 0 / push 0
//   004FA6BE  call 0x006066E0          ; cam->targetGuid = 0
//   004FA6C3  ...                      ; then the commentator camera update
//
// That clearing is not a bug and must NOT be undone: `CGCamera::Update`
// (0x00607B00) follows cam+0x88 every frame when it is set (0x00607B47), so
// putting the hero's GUID back there would drag the free camera onto him.
// The commentator camera is free precisely BECAUSE that field is empty.
//
// So the camera is left alone and the NAMEPLATE GATE is given a reference of
// its own: two instructions, six bytes each, rewritten to read the GUID from a
// slot inside this DLL instead of from the camera. Same length, same registers,
// one call site, and nothing else in the client reads those two instructions.
//
//   8B 88 8C 00 00 00   mov ecx, [eax+0x8C]  ->  8B 0D <addr>   mov ecx, [addr]
//   8B 90 88 00 00 00   mov edx, [eax+0x88]  ->  8B 15 <addr>   mov edx, [addr]
//
// The 41 yards go with it: measured from the hero they cover the middle of the
// screen and nothing else, and the client only ever holds objects the server
// sent (visibility range), so widening this cannot conjure plates for units
// that are not there.
constexpr uint32_t kPlateGateFn  = 0x0072B060;   // for context, never written
constexpr uint32_t kPlateRefHi   = 0x0072B0B2;   // mov ecx, [eax+0x8C]
constexpr uint32_t kPlateRefLo   = 0x0072B0B8;   // mov edx, [eax+0x88]
constexpr uint8_t  kPlateRefHiBytes[6] = {0x8B, 0x88, 0x8C, 0x00, 0x00, 0x00};
constexpr uint8_t  kPlateRefLoBytes[6] = {0x8B, 0x90, 0x88, 0x00, 0x00, 0x00};

// THE HERO'S OWN BAR IS NOT WANTED, AND THE TWO ADDRESSES BELOW ARE NOT
// PATCHED. They were, for one round, and they worked; the player then said he
// does not need a bar over his own head, so they came out again -- fewer bytes
// of someone else's client rewritten for something nobody uses. What is kept is
// the READING, because it cost a session and the next person to wonder "why is
// the hero the only one without a bar" deserves the answer and not the hunt.
//
// FIRST: the unit the reference points at gets no plate of its own.
//
//   0072B0E5  cmp eax, esi             ; the reference IS this unit?
//   0072B0E7  je  0x0072B0DB           ; -> no plate
//
// In ordinary play that is "no nameplate over your own head", and it is right:
// the reference is you. With the reference handed to the gate above it is still
// you -- so the hero was the ONE unit on screen without a bar, name showing and
// nothing under it (seen in game, 2026-09-17). Two bytes, armed and given back
// with the other two: `je rel8` (74 F2) -> two nops.
constexpr uint32_t kPlateSelfJe       = 0x0072B0E7;   // NOT patched, on purpose
constexpr uint8_t  kPlateSelfJeBytes[2] = {0x74, 0xF2};  // je -14, verified

// SECOND, and this is the one that actually decides it, found by walking the
// doors (2026-09-17). With the patches above in place the hero STILL had no
// bar, so the doors were not guessed at: `Plates.cpp` nulls the gate's refusals one more at a time and
// calls the gate after each. The answer turned to yes at 0x0072B2AC -- the
// predicate 0x00729740 -- and the chain behind it is this:
//
//   0072B107  call 0x00729B30      ; "is this unit friendly?", for players
//   0072B11A  test bl,bl           ; the answer decides friend or foe below
//   ...
//   0072B29F  jne 0x0072B2AE       ; friendly -> straight through
//   0072B2A5  call 0x00729740      ; NOT friendly -> ask if you may touch it
//   0072B2AC  je  0x0072B247       ; no -> no plate
//
// and 0x00729B30 OPENS with:
//
//   00729B36  cmp edx, ecx         ; the subject and the object are the same?
//   00729B38  jne 0x00729B40
//   00729B3A  xor al, al / ret 4   ; YES -> "not friendly"
//
// The subject is your own character (0x004038F0 looks up the active player), so
// asked about himself the client answers **you are not friendly to yourself**,
// your hero goes down the hostile path, and there the bit-19 predicate refuses
// him. Every bot is friendly, skips that branch, and wears its bar -- which is
// exactly the picture: everyone but the hero.
//
// So the cure is that degenerate case and nothing else: `xor al,al` -> `mov al,1`,
// two bytes, same length. A unit IS friendly to itself; the client just never
// had to answer it before, because you never see your own nameplate. The other
// twelve callers of that predicate only reach this line with subject == object,
// which is to say only ever about you.
constexpr uint32_t kFriendSelfRet         = 0x00729B3A;   // NOT patched either
constexpr uint8_t  kFriendSelfRetBytes[2] = {0x32, 0xC0};  // xor al,al, verified

// The distance ceiling, squared, in .data -- writable, and read from exactly
// one instruction (0x0072B331), which is what makes it safe to move.
constexpr uint32_t kPlateRangeSq      = 0x00ADAA7C;
constexpr float    kPlateRangeSqStock = 1681.0f;   // 41 yards

// The camera's attached-unit GUID, read to tell "the camera is free" from
// "ordinary play". Same camera chain as kWorldFrameBase/kCameraPtrOffset.
constexpr uint32_t kCam_TargetGuid = 0x88;

// ---------------------------------------------------------------------------
// THE AFK PING-PONG, and why it shook the camera. (2026-09-17)
//
// Symptom: after a while idle in RTS mode, "now you are away" spams the chat
// and the camera jumps in and out of the mode many times a second.
//
// It is ONE loop with two halves, and neither half is in this addon:
//
//   1. THE CLIENT. After five minutes with no input it calls its auto-AFK
//      EVERY FRAME (0x0052B24C reads the last-input stamp and compares it with
//      0x493E0 = 300000 ms; 0x1B7740 = 30 min is the idle logout further on).
//      The only thing stopping it from firing every frame is a latch,
//      0x00BCEFEC, which `MarkAFK` (0x006DC640) sets when it prints the message
//      and sends CHAT_MSG_AFK, and which `ClearAFK` (0x006D52D0) clears from
//      every input handler.
//
//   2. PLAYERBOTS. `PlayerbotAI::DoNextAction` ends with
//      `else if (bot->isAFK()) bot->ToggleAFK();` -- with the selfbot on, your
//      own hero has the flag taken off him on every AI pass. The client, moved
//      by the bot, clears its latch too; still idle, it marks AFK again on the
//      next frame. Round and round.
//
// AND THE CAMERA RIDES ON IT. `Player::ToggleAFK` is `ToggleFlag(PLAYER_FLAGS)`,
// so every turn of the loop sends a PLAYER_FLAGS update -- which overwrites the
// client's copy, and with it BIT 19, which exists ONLY in the client's memory
// (see the block above; the core forbids attacking to whoever carries it, so
// the server cannot send it). For the frames between the update and the DLL's
// next tick, `0x006DE980` answers "not a spectator", and
// `CGWorldFrame::UpdateCamera` re-attaches the camera to the hero -- the free
// camera collapses and comes back. That is the "battle of titans".
//
// Two cures, both in `Steady.cpp`, both armed by BIT 22 (which the server does
// send, so no update can wipe it) and both given back on the way out:
//
//   * the last-input stamp is kept fresh, so the client never thinks it is
//     idle and the loop never starts. It is the truth, too: commanding an army
//     is not being away from the keyboard.
//   * call site [0] of the spectator predicate -- the camera's own, and only
//     that one -- is made to answer "yes" without asking, so a PLAYER_FLAGS
//     update landing between two ticks can no longer pull the camera back.
//     `call rel32` (5 bytes) -> `mov al,1` + three nops: same length, and the
//     other seventeen callers keep asking the real question.
constexpr uint32_t kIdleInputStamp = 0x00B499A4;  // ms, the client's own clock
constexpr uint32_t kClientTimeMs   = 0x0086AE20;  // uint32 __cdecl(void), ms
constexpr uint32_t kCamSpecCall    = 0x004FA69D;  // == kSpecCallSites[0]

}  // namespace off
