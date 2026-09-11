# Historia del proyecto RTS -- el diario completo

Este fichero es el **registro**: cada etapa, cada fallo, y sobre todo el POR QUE
de cada decision, tal y como se escribio el dia que se tomo. Movido aqui desde
`C:\Server\CLAUDE.md` el 2026-09-09, **verbatim y sin resumir**, porque ese
fichero se carga entero en cada sesion y habia llegado a ~99.000 tokens.

## La direccion es estructural, y por eso esto NO es la copia que se borro

El 2026-08-27 se borro `rts-project\docs\CLAUDE.md` porque era **una copia del
mismo fichero**: dos textos con las mismas instrucciones, sin ninguna forma de
saber cual era el bueno salvo la fecha, y uno de los dos envejecio en silencio.

Esto es lo contrario: es un **corte**, no una copia. El reparto es

| fichero | que es | se edita |
|---|---|---|
| `C:\Server\CLAUDE.md` | estado actual, reglas, comandos. **Es la autoridad.** | cada sesion |
| `rts-project\docs\HISTORIA.md` | el registro cerrado de como se llego aqui | solo se le AÑADE |

Ninguna instruccion vive en los dos sitios. Si algo de aqui se contradice con
`CLAUDE.md`, **manda `CLAUDE.md`**: esto describe lo que se penso entonces, no
lo que hay instalado hoy.

Y de paso arregla la exposicion que `CLAUDE.md` se apuntaba a si mismo -- *"este
fichero ya no tiene ninguna copia fuera de este disco"*. Esto esta en el repo, o
sea en GitHub.

## Aviso: gran parte de esto describe codigo que YA NO EXISTE

Las secciones del **2026-09-07** (camara libre de comentarista) y del
**2026-09-08** (heroe invisible) se revirtieron: el repo volvio a `4047b84`.
Se quedan porque son la investigacion -- direcciones desensambladas, candidatos
descartados con su evidencia -- y borrarlas garantizaria repetirla. La receta
reconstruible de la camara esta en `docs/CAMARA-LIBRE.md`.

Lo mismo, a menor escala, con todo lo que se construyo y se borro despues:
retencion de altura de camara, `CommandMode.lua`, los tres paneles flotantes,
los railes, la ventana de misiones, el rastro de puntitos de las rutas.

## Indice, en orden cronologico

1. Stage 6 — mod-rts, the server half (in progress)
2. Stage 5i — la UI del modo RTS, opcion B (built 2026-08-19, not yet run in-game)
3. El lanzador mentia en las dos direcciones, 2026-08-20
4. Stage 5k -- la sala llena, 2026-08-20. Construido, no visto en juego.
5. Stage 5l -- lo que dijo el juego, 2026-08-22. Construido, no visto todavia.
6. Stage 5m -- la segunda pasada, 2026-08-22. Construido, no visto todavia.
7. La retencion de altura de camara, BORRADA 2026-08-23
8. Las teclas de altura cortan el avance, y se queda asi 2026-08-23
9. Los micro-botones de los railes: recortar el glifo 2026-08-23
10. Stage 5n -- la seccion central del panel de control, 2026-08-24. Construido, no visto todavia.
11. Stage 5o -- lo que dijo la ronda 18, 2026-08-27. Construido, no visto todavia.
12. La sala se vacia, 2026-09-02. Addon 0.49.0, mod-rts SIN TOCAR.
13. Revision de arquitectura, 2026-09-02
14. Los tres primeros arreglos de la revision, 2026-09-02. Addon 0.50.0.
15. Stage 7 -- lo del otro desarrollador, 2026-09-03. Construido, no visto todavia.
16. Dibujar en el suelo, 2026-09-03
17. Stage 7b -- lo que dijo la ronda 20, 2026-09-03. Construido, no visto todavia.
18. El swap nativo existe, pero el login lo pulsas tu. 2026-09-03
19. El grupo sobrevive al cambio, y el ABORT que salio por el camino. 2026-09-03
20. Por que el cambio de personaje NO puede evitar la carga. 2026-09-03
21. El cambio de personaje SIN pantalla de seleccion, 2026-09-03 (tarde)
22. La barra que faltaba era la de POSTURA. Addon 0.74.0, 2026-09-04
23. La sala se llena: el panel de control de grupo, 2026-09-04
24. El crash del servidor era una referencia que sobrevivio a su nodo, 2026-09-05
25. La sala contra el boceto retocado, 2026-09-05 (tarde). Addon 0.78.0
26. Un aro por unidad, y el "bug de Kirinah" que era el largo de un mensaje. 2026-09-06
27. El aro nativo, confirmado; y la cura que se curaba sola. 2026-09-06 (tarde)
28. Cero es cierto en Lua, y por eso los hechizos morian con varios cogidos. Addon 0.85.0
29. El libro de hechizos lo dice el DBC, y los marcos duplicados. 2026-09-06
30. El FOV llevaba tres etapas muerto, las cuevas y la tecla que rompio la mira. 2026-09-06
31. El boton Compartir del registro nativo, forzando. 2026-09-07
32. El cliente ya trae una camara libre, 2026-09-07. Sondeo construido, NO corrido.
33. La camara libre del cliente SUSTITUYE al Puppet, 2026-09-07 (tarde)
34. El heroe invisible: SIN RESOLVER, y esto es lo que NO hay que volver a probar
35. VUELTA ATRAS AL COMMIT DEL BOTON COMPARTIR. 2026-09-08
36. La sonda de identidad, 2026-09-08. CODIGO REVERTIDO; los hallazgos se quedan.
37. Ruta A: la sonda del cuerpo, 2026-09-09. Construida, NO corrida.

(La 0 es el bloque de arriba: `Stage 5 -- el estado etapa por etapa (5a .. 5h)`.)

---

## Stage 5 -- el estado etapa por etapa (5a .. 5h), 2026-08-14 .. 2026-08-16

### Status

Stage 5a **done**: addon runs in-game. Selection, control groups, command card,
formations, and all coordinate-free orders confirmed working.

Stage 5b **done, not yet run in-game**: `rts_core.dll` + `injector.exe` build
clean, both confirmed x86. Exposes player and per-object world coordinates.
Verify with `/rts native`, which prints live coordinates and writes an offset
self-test to `rts_core.log`.

Stage 5c **highlight confirmed in-game 2026-08-14**: bots light up using the
client's own per-unit highlight, so the marker is part of model rendering and is
occluded correctly for free — no UI texture floating over terrain. Verified path:
`CGUnit_C::SetHighlight` → render object (vtable+0xD4) → RGB at `+0x18C/+0x190/
+0x194`, intensity at `+0x1B8`. Two findings worth keeping:

- **The colour is the whole gotcha.** The client writes RGB(78,78,95) — a dark
  slate that reads as "nothing happened" on a model. Overwriting those three
  floats after the call makes it unmistakable, and the values persist between
  frames: the client does not fight the write.
- **The ground circle is single-unit and unusable for RTS.** The renderer at
  `0x0079676D` compares each unit's guid against one global (`0x00CD7770`) that
  `SetHighlight` overwrites per call, so at most one unit can wear a circle. The
  model glow is the per-unit marker; the circle is not.

Stage 5d **selection channel + state colours, 2026-08-14**. The DLL was
push-only: `FrameScript_RegisterFunction` is a dead end, because Lua rejects C
function pointers outside `Wow.exe` (ERROR #134, verified the hard way). A
**CVar closes the loop** — ordinary client memory that Lua writes with `SetCVar`
and the DLL reads out of the CVar object (`+0x30`, int; `+0x20`, string). The
borrowed CVar is `enablePVPNotifyAFK`, inert on a PvP-less server and restored
on logout.

**Protocol 2** (`RTS_PROTO=2`), one 30-bit value — the client parses it with a
*signed* `atoi`, so 2^31 is the hard ceiling:

```
value = (seq << 27) | (state[8] << 24) | ... | (state[0] << 0)
```

Three bits of state per **player** slot, nine slots. Creatures take no slot;
they can never be selected. States map to model tints: 1 blue selected, 2 green
moving, 3 red combat, 4 orange interacting. The addon decides them in
`State.lua` from the order text plus live evidence (`UnitAffectingCombat`, and
the DLL's own position stream for "still walking").

Two findings that cost real time:

- **The blinking tint was the generation stamp, not the highlight.** Protocol 1
  sent a selection bitmask stamped with a *hash of the published guid list* and
  the DLL dropped the whole reply on a mismatch. The list is sorted, the reply
  is always a tick old, and any two bots swapping order re-stamped it — so the
  mask was dropped, every unit cleared, and the tint returned a frame later.
  Constantly, because bots move. Protocol 2 stamps with a **sequence number**
  and keeps the last 8 published lists, so a slot resolves to a *guid* and is
  matched by identity against the current list. A late reply is stale, never
  wrong, and nothing is ever dropped. The list is also now sorted by guid rather
  than left nearest-first, so indices stop churning in the first place.
- **Tint on highlight reason 2, not reason 0.** Reason 0 is the client's own
  target highlight, and the highlight reset at `0x00513CF0` re-runs on **any**
  CVar change — including the ones this channel writes 20×/second — clearing
  reasons 0 and 1. Reason 2 is untouched by the client. Its one catch is that
  `SetHighlight` skips the intensity write when *only* bit 26 is set
  (`(flags & 0x7000000) != 0x4000000` guards it), which does not matter because
  `ForceColour` writes intensity itself. Clearing has to zero the intensity by
  hand for the same reason.

Stage 5e **the halo and the life bars, 2026-08-15. Built, not yet run
in-game.** Both had the same root cause and the same fix: *stop projecting, and
let the client place it.*

Everything drawn "in the world" up to here was a UI texture parked at a pixel
Lua computed from the camera the DLL publishes. That can never be smooth. The
camera used is never the camera the frame was rendered with, so markers swim
when you turn; and a UI texture has no depth, so it draws over the hill it
should be behind. The dot ring in `SelectionRing.lua` was the high-water mark of
fighting this, and it lost.

- **The circle is two guid slots and a drain, and the fix is to call the drain
  more often.** The trail is the `ObjectSelectionCircle` CVar object
  (`0x00CA12C8`), which has exactly one consumer: `0x00743EF4`, inside a
  per-unit virtual at `0x00743EC0` that decides whether a unit should wear a
  circle and writes its guid into a slot on the scene context — `ctx+0x380` for
  your target (never yourself), `ctx+0x388` for your mouseover. Those two slots
  are drained once a frame by `0x004F6F90`, `__thiscall(ctx)`, which per slot
  does: read guid → if zero skip → `ClntObjMgrObjectPtr` (`0x004D4DB0`) →
  `obj->vtbl[0x6C]()` → zero the slot. So the client's design is *two* circles,
  and the draw is an ordinary virtual call on the unit.

  `Circle.cpp` therefore reimplements nothing. It hooks the drain (nine
  position-independent bytes at the entry), lets the original run once so the
  native two are drawn unchanged, then writes each of our guids into slot A and
  calls the original again — each call resolving one unit, drawing its circle
  and clearing the slot behind itself. No patched comparison, and no need to
  know what `vtbl+0x6C` actually is.
- **The first attempt at this was wrong, and the diagnostic is what caught it.**
  The guid compare at `0x0079676D` really is a per-unit gate on a per-unit effect
  word (`0x00D1BEFC`, cleared by `0x7A9160` per unit, consumed by `0x7ABF50` on
  the model submit) — all of that held up. What did not hold up was the
  assumption that the effect it arms is the *circle*. Patching it and arming it
  for every unit on screen produced nothing visible; the client's own value there
  is `0xFF1D3C54`, a dark slate blue, which is a model emissive tint. The whole
  walk is documented in `Offsets.h` under the real circle, because it is a
  working per-unit model tint and someone will want it. **Cost: one build. The
  lesson is that the cheap match-everything diagnostic was worth writing before
  the feature, not after.**
- **The life bars work and are PARKED on sight, 2026-08-16.** A health bar, a
  name and a cast bar over every bot is noise in an RTS view. `Plates.lua` stays
  in full — the plate-finding, the region map and the CVars are the expensive
  part. Note that switching the restyling off is not enough to remove the bars:
  `nameplateShowFriends` is what gives a friendly player a plate at all, so the
  parked path puts all three CVars back and the module now captures their
  original values before it ever changes them.
- **The life bars are the client's own nameplates, restyled** (`Plates.lua`).
  A nameplate is placed by the client, in its own render loop, from the unit's
  world position — so it tracks perfectly because nothing is tracked. There is no
  API: a plate is an unnamed `WorldFrame` child whose second region is
  `Interface\Tooltips\Nameplate-Border`, children are `healthBar, castBar`, and
  the eleven regions are in a fixed order. Identity is by name, since a 3.3.5a
  plate carries no GUID — exact for our own bots.
- **`nameplateAllowOverlap` is the setting that decides whether this works.**
  By default WotLK *spreads* plates sideways so they never overlap, which means a
  plate slides off its own unit whenever two units get close — permanently, for a
  party in formation. Set to 1, each plate sits over its unit and nowhere else.
  `nameplateShowFriends` is what gives bots plates at all.
- **`nameplateMaxDistance` does not exist in 3.3.5a** — confirmed by scanning
  this `Wow.exe`, not by trusting the web, which will tell you to use it. Plates
  stop at the client's hardcoded ~41 yards with no CVar to raise it, so a
  detached camera further out than that loses the bars.

Protocol bumped to **3** for a gate bit: states now take eight slots in bits
0–23, seq 24–26, bit 27 the circle, bit 28 the model glow, bit 29 a `circle
under every published unit` diagnostic (`/rts ring test`). Both sides refuse to
decode the other protocol, so a half-updated install goes quiet rather than
misfiring.

**Per-unit circle colour: PAUSED 2026-08-16, after two failed attempts and a
confirmed negative in game.** `0x00ACC3F8`
holds `0xFF7F7F7F`, the draw is handed its address, and the targeting code reads
the same dword beside the reaction colour tables — every sign says colour. It
is not. Writing it before each draw gave grey circles; repointing the draw's
`push imm32` at a per-unit dword, which is immune to *when* the pointer is
dereferenced, also gave grey circles. Since the second test removes the timing
variable, the address is simply not the tint. Both attempts and the next lead
(runtime-probe the seven args at the `0x007E4370` call site, then walk into
`0x007E3E80`) are written up in `Offsets.h`.

The lesson repeats Stage 5e's: a convincing static reading of a colour-shaped
value is worth one cheap in-game test, not two builds of machinery on top of it.

**State-at-a-glance today** is the model glow (`/rts ring tint`, protocol bit
28), which does take arbitrary per-unit RGB and has worked since Stage 5d. The
halo means "selected"; the glow carries the state.

Stage 5f **the RTS camera, working 2026-08-16.** Free camera and drag-box
selection are both done. Five things had to be true, and four of them were bugs
with a single named cause:

- **`SetCanFly(true)` was why it flew.** In flight mode the client moves a unit
  along its *view* vector — tilt down, press forward, descend. Flight now
  defaults **off** (`RTS.Camera.Fly`, live-switchable with `/rts cam fly`) with
  gravity still disabled, so the client moves the camera flat across the map and
  the tilt only changes what you see. WC3 behaviour.
- **`MoveViewUp` moves the CAMERA up, which makes you look DOWN.** The names
  describe where the camera goes, not where you end up looking. Using
  `MoveViewDown` drove it under the unit and pointed it at the sky.
- **`cameraSmoothStyle` is why a tilt would not stick.** It is WoW's "adjust
  camera automatically", and it slides the camera back behind the unit whenever
  it moves — so any angle you set was undone the moment you panned. Set to 0
  while RTS mode is on. No amount of re-applying our own tilt could have won:
  the client re-runs its correction every frame.
- **Backwards was slower because `MOVE_RUN_BACK` is a different move type with a
  lower base speed** (4.5 yards/s against run's 7.0). The same *rate* on both is
  not the same *speed*. `ApplySpeed` now converts to one absolute target and
  gives every direction the rate that reproduces it.
- **Height must come from the server.** The camera is possessed, so the client
  owns its position, and with flight off it has no vertical movement to offer.
  Q/E send key-down/key-up only; `camera::Update` lifts it on the world tick.

**The hard rule, and it was broken twice before it was stated:** RTS mode may
only affect RTS mode. Every CVar this touches — `cameraSmoothStyle`,
`cameraDistanceMaxFactor`, `cameraDistanceMax` — is captured before its first
change and restored on exit. An early version set the zoom cap and never gave it
back, quietly changing how far *normal play* could zoom out.

Framing is saved with `/rts cam save`, which needs both halves: `SaveView` for
the angle and zoom, and the server for where the camera creature stands (a
distance behind the character and a height above). Saving only the view slot is
what gave a correct tilt with the party in the wrong part of the screen. The
measured values are baked into `C.DEFAULTS` in `Camera.lua`, so a fresh
character is framed correctly with no setup; the command stays for changing it.

Stage 5g **camera FOV, 2026-08-16.** The isometric knob, and the last piece of
the RTS look. WoW's diagonal FOV is 90°; narrowing it flattens the perspective
toward orthographic, which is most of what separates "a map" from "a place you
are standing in". Default is now **60°** in RTS mode, `/rts cam fov <deg>` to
taste, 0 to leave the client's alone.

Two things made it more than a one-line write:

- **It must be re-applied every tick.** The client owns `camera+0x40` and
  rewrites it — on zone changes, on some spell effects, and through its own fov
  smoothing (`cameraFoVSmoothSpeed`). Setting it once holds until the first of
  those and then silently reverts. It is written from the 100 Hz camera tick,
  *before* the fov is read back, so what gets published is what the frame was
  actually drawn with and the addon's derived projection scales stay correct.
- **A SECOND borrowed CVar was needed.** The packed selection channel is a
  bitfield with two spare bits — an index at best, and FOV wants tuning by eye
  rather than picking from presets baked into a build. `guildMemberNotify` is a
  guild-roster toast, inert on a solo server, and an integer, which is all this
  needs: the value is FOV in tenths of a degree, 0 meaning "leave it". It is
  captured and restored with the real camera CVars, under the same hard rule.

Stage 5h **the mouse, the taint and the half-walk, 2026-08-16. Built and
installed, not yet run in-game.** Three failures reported from `PRUEBAS-3`,
looking unrelated, and every one of them turned out to be *something already
true being asked for a second time*.

- **The drag box could never have worked, and the cursor is why.** Pressing the
  left button in the world puts the client into **mouselook**, which hides the
  cursor and pins it in place. `GetCursorPosition()` then returns the same two
  numbers however far the mouse physically travels — so `moved > CLICK_SLOP` was
  measuring against a value frozen by definition. Always 0, never a drag, and
  the client did what it always does with a held left button: orbit. Nothing was
  wrong with the box; the threshold in front of it was unreachable.

  The fix is to detect the drag by its **effect**. While mouselook owns the
  mouse, moving it turns the camera, and the DLL already publishes the camera
  forward vector every tick — so a moving mouse shows up there on the first
  frame. Then `MouselookStop()` hands the cursor back, at the point the press
  started, which is exactly the corner the box wants. A hold timer would also
  work, but any timer long enough to be sure is long enough to feel, so it is
  kept only as the fallback for a client with no DLL injected.
- **`TargetUnit` is protected — and it was also redundant.** Every left click on
  something that was not ours threw "blocked from an action only available to
  the Blizzard UI". An addon may not call `TargetUnit` for an arbitrary unit in
  3.3.5a, full stop. The useful half is that deleting it costs nothing: since
  the mouse stopped being captured, the client sees the click itself and targets
  against real model geometry. **The workaround outlived the capture.**
- **The bot never had a chance to talk.** `TalkBot` ordered the walk and fired
  `gossip hello` in the *same tick*, with the bot still standing where it was.
  That action lands in `Player::GetNPCIfCanInteractWith`, whose last test is a
  range check against `INTERACTION_DISTANCE`; it returns null, playerbots reads
  a null there as "nothing to talk to", and returns quietly. So the order
  reported success, the bot walked, and the conversation had already been thrown
  away before it set off. Walking up by hand and re-clicking *did* work, which
  is what made it read as a distance bug. The intent is now parked and completed
  on arrival — which is exactly what the player's own path already did.
- **A stand-off is a MARGIN, not a distance.** `GetContactPoint` adds both
  parties' combat reaches to the point it returns, and `IsWithinDistInMap` adds
  the same two reaches to the 5.5 it allows. They cancel: what is actually left
  is `5.5 - standoff` yards of slack for the path to be imprecise in. At the old
  4.5 that was one yard, which mmap snapping to walkable ground eats without
  trying. Now 2.0, leaving three and a half.

The through-line is worth more than any of the three fixes: **each was a
workaround still standing after the thing it worked around had been removed.**
Giving the mouse back (Stage 5's redesign) silently invalidated a whole layer of
compensation, and the compensation then started reading as new bugs. The cursor
halo's `HostileAt`/`KindOf` pair is the same shape and is still wired in — it
now takes the client's mouseover as its fast path and only falls back to the
server `WHAT` round trip, so it is demoted rather than dead. Worth sweeping for
the rest deliberately instead of waiting for each to surface.

**Distances reverted to stock, on your call.** `Visibility.Distance.Continents`
300→100, `AiPlayerbot.SightDistance` 300→100, `AiPlayerbot.ReactDistance`
450→150. The open question this answers is whether far attack orders were fixed
by raising the distance or by giving the mouse back — `PRUEBAS-4` D1 decides it.
The DLL's 180-yard publish range needs no matching change and got none: the
client only knows what the server sends it, so the server's 100 caps it on its
own.

Next: run `PRUEBAS-4` → single/double-click selection → hiding the default UI in
RTS mode.

### First-person control of a bot -- DISCARDED 2026-08-16

Dropped as a goal. The command card plus command mode covers what it was for,
and a seamless session character-switch is a large server-side job for something
the RTS layer does not need. The relog swap still works if it is ever wanted.

Original note, 2026-08-13: **command card first.** Selecting a bot and clicking abilities
that fire via `cast <spell>` is the RTS-authentic answer and is already in place.
For genuine first-person with real action bars, the stopgap is a **relog swap** —
log out, log in as that character, and the one you left becomes a bot (playerbots'
alt-bot system). A server module doing a seamless session character-switch is the
only way to avoid the loading screen; deferred until the RTS core is solid.

If Windows Defender flags the injector/DLL later, add its folder as an exclusion
rather than disabling AV — remote-thread injection trips heuristics regardless of
intent.

**Checkpoint (not yet reached):** free camera, drag-select the party, right-click
the ground, bots walk there.

## Stage 6 — mod-rts, the server half (in progress)

Started 2026-08-14 after a reference implementation (Yafravan's DRPG/RTS demo)
showed seamless bot possession and RTS orders on a **custom core**. That is the
unlock: this server is local and we compile it, so the features that looked like
they needed deep client hacking are ordinary server code.

### The camera is not a client hack

The client's camera always looks at whatever unit the client is currently
**moving** — its active mover. So a detached camera is just: summon an invisible
creature, hand the client control of it. The camera follows because that is what
the camera does, and WASD flies it because that is what movement keys do.

This is the mechanism behind **Eye of Kilrogg, Mind Control and Far Sight** —
shipped with the game since 2004, and available here as
`Player::SetClientControl(target, allowMove)` (`Player.cpp:13147`), which sends
`SMSG_CLIENT_CONTROL_UPDATE` then does `SetViewpoint` + `SetMover`.

**Working in game 2026-08-14.** WASD flies it, Q/E rotate, character rooted below.

Two things cost a client crash to learn, both from hand-rolling what the core
already does properly:

- **`SetClientControl` alone moves only the VIEW.** The camera detached and then
  would not budge. The client will not *drive* a unit it does not possess. The
  real path is `Unit::SetCharmedBy(charmer, CHARM_TYPE_POSSESS)`
  (`Unit.cpp:14599`; the possess branch at 14754 is marked `// verified` in the
  core's own source). It adds `UNIT_STATE_POSSESSED`,
  `UNIT_STATE_NO_ENVIRONMENT_UPD` (so the camera does not fall),
  `UNIT_FLAG_POSSESSED`, and `UNIT_FLAG_DISABLE_MOVE` on the player — rooting
  your character, which is exactly what an RTS camera wants. Line 14610
  explicitly permits possessing a **Player**, which is what a playerbot is, so
  bot possession is the same call.
- **Releasing with `SetClientControl(player, true)` does NOT clear the
  viewpoint** — it skips `SetViewpoint` when the target is the player itself
  (`Player.cpp:13171`, `if (this != target)`). `PLAYER_FARSIGHT` stayed pointed
  at the camera creature, which was then despawned, and the dangling seer took
  the client down with **ERROR #134** on the next `/reload`.
  `Player::SetViewpoint` carries the warning twice in its own source: *"must
  immediately set seer back otherwise may crash"*. Release through
  `RemoveCharmedBy`, which calls `SetClientControl(camera, false)` **first** —
  target is not the player there, so the viewpoint really is torn down.

Note ERROR #134 is **not** always the Lua/C-function-pointer problem from Stage
5. It is the client's generic fatal condition; `rts_core` was not even injected
for this one. Check the module list in `Errors\*.txt` before blaming the DLL.

The camera creature is entry **15214 "Invisible Stalker"**, an existing world
trigger: invisible model, faction 35, already not-selectable. Borrowed rather
than shipped as a `creature_template` row, because the world DB is re-imported
wholesale on a core update and a module's own rows are the first thing to go.

### The addon → server channel

Addon messages, whispered by the player **to themselves** (keeps it working solo;
party chat is where mod-playerbots reads its own commands, and a character need
not be in a guild):

```
SendAddonMessage("RTS", "CAM ON", "WHISPER", UnitName("player"))
```

**Hook `OnPlayerBeforeSendChatMessage`, not `OnPlayerCanUseChat`.** The
receiver-taking overload of `OnPlayerCanUseChat` looks like the obvious fit and
is **never called for whispers** — the whisper branch runs straight into
`Player::Whisper` (`ChatHandler.cpp:451`) without consulting it. The hook enum
exists; the call site does not. `OnPlayerBeforeSendChatMessage` fires at
`ChatHandler.cpp:367`, *before* the per-type switch, so it sees everything.
`LANG_ADDON` is only legal for PARTY, RAID, GUILD, BATTLEGROUND and WHISPER —
not CHANNEL, so a private channel is not an option.

The server answers on the same channel via `ChatHandler::BuildChatPacket` with
`CHAT_MSG_WHISPER` + `LANG_ADDON`, so the addon learns the *real* state instead
of assuming its request succeeded.

## Stage 5i — la UI del modo RTS, opcion B (built 2026-08-19, not yet run in-game)

`UI-RTS-ESTUDIO.md` es el estudio previo. Leerlo antes de dibujar arte: tres de
sus hallazgos obligan a rehacerlo si se descubren tarde -- las texturas son
potencias de dos hasta **512**, la escala de UI hace que 1 unidad sean 1.61
pixeles en su equipo (arte borroso salvo que la HUD lleve su propia escala), y
`UIParent:Hide()` esconde tambien el botin, el gossip, las bolsas y el menu de
escape.

**La decision de su apartado 8 esta tomada: opcion B, ocultado selectivo.** No
`UIParent:Hide()`. El modo es jugable desde el primer dia y las ventanas siguen
funcionando solas; mover alguna a la HUD queda como mejora suelta, no como
requisito previo. Dos ficheros nuevos, `Chrome.lua` y `HUD.lua`, mas `/rts ui`.

- **`Chrome.lua` esconde lo que estaba rodeado en el boceto** y lo devuelve al
  salir **al estado en que estaba antes**, no con un `Show()` a ciegas -- una
  barra que el jugador tenia apagada en las opciones tiene que seguir apagada.
  Es la misma regla dura que Camera.lua aplica a sus CVars.
- **Un frame protegido no se puede esconder DENTRO de combate.** PlayerFrame,
  MainMenuBar y las barras de accion lo son. Cada entrada lleva su bandera y lo
  protegido se aplaza a `PLAYER_REGEN_ENABLED`, igual que las teclas de la
  camara.
- **Blizzard repone frames por su cuenta** (salir de un vehiculo, cambiar de
  zona, entrar un bot al grupo). Un barrido de medio segundo los vuelve a
  esconder mientras el modo esta activo; perseguir los eventos uno a uno seria
  una lista que se queda corta.
- **El tooltip no se esconde con `Hide()`**: vuelve en cada mouseover, asi que
  se le engancha el `OnShow`. Unico caso especial de la tabla.
- **La linea de mensajes no es un adorno.** El chat esta en la lista, y con el
  se va `ns.Print`, el unico canal de diagnostico del addon. `HUD.lua` envuelve
  `ns.Print` y replica cada linea sobre el mundo, estilo WC3, con desvanecido.
  Sin eso, esconder el chat es quedarse ciego -- el aviso del estudio.
- **La HUD lleva su propia escala de pixel** (`768/altoFisico`), calculada
  contra la escala del padre, de modo que dentro de ella 1 unidad = 1 pixel y
  el arte no se interpola. Cuelga de `UIParent` mientras la opcion sea la B; si
  algun dia se pasa a la A, se cambia la constante `PARENT` y nada mas.
- **`gxWindowedResolution` NO EXISTE en 3.3.5a, y creer que si costo la primera
  pasada por el juego.** La version original leia ese CVar en modo ventana;
  `GetCVar` devolvia nil, el patron no casaba, la escala se quedaba en 1 y toda
  la HUD salia un **45% mas grande** de lo pedido -- se veia como una decision
  de diseno mala, no como un fallo. Este `Config.wtf` solo tiene `gxResolution`,
  `gxWindow` y `gxMaximize`. **Misma leccion que `nameplateMaxDistance`:
  comprobar el CVar contra el cliente, no contra lo que dice internet** -- y
  aqui la comprobacion era abrir un fichero de texto.
- **`gxResolution` guarda la resolucion de PANTALLA COMPLETA**, que en ventana
  maximizada no es el tamano de la ventana (falta la barra de tareas, y el
  escritorio puede tener otra forma). El alto real sale del ancho y de la
  relacion de aspecto de `UIParent`, que si es la de la ventana: su alto en
  unidades es fijo y su ancho cambia con la forma. Se asume ventana a todo lo
  ancho; `/rts ui` ensena los dos numeros para que un mal supuesto se vea.
- **El alto de la barra se CALCA del boton de la barra de acciones**, no se
  elige. Dos intentos a ojo (240 y 210) salieron mal en direcciones opuestas;
  la medida que el jugador tiene calibrada en la retina es el boton de accion
  de siempre, asi que se mide `ActionButton1` en pixeles fisicos y se deriva de
  ahi el alto que hace que la rejilla 4x3 tenga botones iguales. Se recalca
  solo al cambiar la resolucion, salvo que el jugador haya fijado un alto a
  mano. En esta pantalla: boton 62 px, barra 249 px (16% del alto).
- **La caja de texto del chat es HIJA de `ChatFrame1`**, asi que esconder el
  chat dejaba escribiendo a ciegas al pulsar Intro -- ni lo tecleado ni la
  respuesta. No se reparenta la caja (Blizzard la reancla ella sola cada vez
  que la activa, y esa pelea no se gana): se engancha **`ChatFrame_OpenChat`**,
  que es la funcion que llama la tecla, y el chat *asoma* mientras dure la
  conversacion mas 8 segundos. Enganchar la funcion global y no el
  `OnEditFocusGained` de la caja es lo que lo hace funcionar: un frame
  invisible no coge el foco, asi que su propio script podria no dispararse.
- **El chat de verdad se copia a la linea de mensajes de la HUD** (grupo,
  susurros, decir, gritar, criaturas, sistema), con color por tipo. Es lo que
  hace WC3 -- texto sobre el mundo -- y evita tener que devolver la ventana
  solo para enterarse de lo que dicen los bots. `/rts ui chatline` lo apaga.
- **`Skin.lua`: el aspecto en un solo sitio, cambiable en vivo.** Las texturas
  elegidas mirandolas en el visor -- borde `UI-DialogBox-Border`, ranura
  `UI-PaperDoll-Slot-Bag`, fondo `UI-DialogBox-Background-Dark` -- viven en UNA
  tabla, y los frames vestidos se apuntan en una lista para poder revestirlos
  sin recargar. `/rts skin` alterna WC3 y plano; `/rts skin wall <ruta>` acepta
  cualquier ruta, que es justo lo que `/rts art` escribe al hacer click. Los
  dos comandos estan pensados para usarse juntos: mirar, copiar, probar.
- **Nada de TexCoord todavia, y es deliberado.** Las hojas grandes del cliente
  traen varias piezas en una imagen y acertar el recorte a ciegas es adivinar;
  todo lo que se usa hoy se dibuja entero (un marco de nueve trozos y una
  ranura cuadrada no necesitan recorte). El aro de retrato queda guardado en la
  tabla, sin usar, para cuando haya retratos y con que mirarlo.
- **`/rts art` es el visor de texturas del cliente**, y es el paso previo a
  vestir la HUD al estilo WC3. Un addon puede usar cualquier ruta
  `Interface\...` del cliente -- miles de piezas, cero bytes, sin la regla de
  potencias de dos -- pero una ruta que no existe **no da error, dibuja nada**,
  asi que construir sobre una lista escrita de memoria es descubrir los huecos
  tarde y confundidos con fallos de anclaje. El visor las ensena a escala de
  pixel sobre fondo gris (una casilla lisa = no carga) y `/rts art scan`
  responde ademas si `GetTexture()` sirve de oraculo: si una ruta inexistente
  devuelve nil, se pueden comprobar cientos a ciegas; si no, solo queda el ojo.
- **`/rts ui what` nombra lo que siga visible.** Cuando algo no se esconde, la
  pregunta no es por que sino *como se llama el frame*: anadirlo a la lista es
  una linea, adivinar el nombre mirando la pantalla es media tarde.
- **Lo que hay dibujado es a proposito casi nada**: el minimapa de verdad
  reparentado abajo a la izquierda (cuadrado, con `SetMaskTexture`) y la HUELLA
  de la barra de control a su derecha, con una rejilla 4x3 vacia -- la carta de
  comandos de WC3 -- y las medidas escritas encima. La ronda `PRUEBAS-9`
  existe para devolver **un numero**: la altura de la barra de control. Hasta
  tenerlo, cualquier arte es una apuesta sobre medidas que aun pueden cambiar.
  Se ajusta en vivo con `/rts ui height|mini|pad|gap|right <px>`.

Stage 5j **el arte de la barra, segunda exportacion, 2026-08-19. Instalado, no
visto todavia en juego.** Siete piezas TGA, ya con nombre propio en vez de
`Frame N`. `docs/UI-RTS-PLANTILLA.md` §9 lleva la tabla de medidas; aqui solo lo
que cambia de forma:

- **La barra dejo de ser de ancho fijo.** `middle-grow` empalma consigo mismo —
  el gris llega a los dos bordes y las bandas de arriba y abajo cruzan enteras —
  asi que la barra crece repitiendo esa pieza y solo esa, `/rts bar grow <n>`.
  El `bar-centre` de la primera exportacion no empalmaba (borde a un lado, hueco
  al otro) y por eso el ancho estaba clavado en 1344. Ahora son **1232 + 256 por
  copia**.
- **Los dos railes van sueltos, 8 px separados del resto; todo lo del centro se
  toca.** Es la unica separacion que hay, y esta escrita como un `gap` en la
  tabla de piezas, no sumada a mano en las coordenadas.
- **Ninguna posicion se escribe.** Cada hueco dice a que pieza pertenece y con
  que margen; su x sale de donde acabo la anterior. Es lo que hace que `grow` no
  obligue a tocar un solo numero de los demas, y el hueco del grupo se declara
  con `toPiece`/`toDx` porque abarca varias piezas.
- **EL ARTE ES 2x Y SE DIBUJA REDUCIDO, y esa es la decision de fondo.** Las
  piezas de 256 se quedaban cortas al lado de las texturas del propio cliente,
  que son bastante mayores: un borde de WoW metido en un panel de 256 sale
  desproporcionado. Doblado el arte, encajan. La exportacion nueva es
  **exactamente 2x** -- comprobado zona por zona contra las medidas anteriores,
  no supuesto -- y sigue dentro de potencia de dos hasta 512, que es el techo.
  La barra pasa a **2464 x 512** y se dibuja a **x0.83** en 2560. Es la
  direccion buena: reducir sale nitido, ampliar emborrona, y con el 20% de alto
  sobre el arte viejo la barra AMPLIABA a x1.09.
- **EL ALTO ES LA ESCALA Y EL ANCHO SON LOS PANELES.** `share` = 0.20 del alto
  da la escala; con esa escala se elige cuantas copias del panel central hacen
  falta para dejar `side` = 0.10 de margen a cada lado. Dos mandos para dos
  cosas.
- **Un intento intermedio fijo el ancho con `side` y dejo el alto de
  consecuencia, y salio mal de forma instructiva:** la barra quedaba a 426 px,
  el 30% de la pantalla, y crecer la ENCOGIA. El argumento de entonces --
  proporcion fija, fijar un lado fija el otro, dos mandos para un grado de
  libertad -- era cierto **solo mientras `grow` estuviera a mano**. Repetir el
  panel central cambia la proporcion del dibujo, asi que es un grado de libertad
  de verdad y caben dos mandos sin que ninguno mienta. El error no fue tener dos
  knobs, fue pedirle a la escala que hiciera el trabajo del ancho.
- **No hay pez que se muerda la cola** porque la escala sale del ALTO, que no
  depende del ancho del arte: escala -> cuantos paneles -> `BAR_W`. Al reves no
  se resuelve.
- **`grow` es discreto, asi que el margen nunca es el pedido.** Cada copia son
  512 px de dibujo (~280 de pantalla), asi que el margen salta de golpe: se elige
  la cuenta mas cercana al pedido con un suelo de 4.5%, y los empates se rompen
  hacia abajo -- menos paneles dejan mas mundo, y pasarse es el unico de los dos
  errores que se ve como arte cortado. En 2560x1440 a pantalla completa salen
  **3 paneles, 1962 x 288 px, margen 11.7%**; en ventana maximizada (~1392 de
  alto util) salen **4 y 7.5%**. Las dos son correctas: son los escalones que
  rodean al 10%. Por eso el margen se imprime siempre, junto al pedido, y
  `/rts bar status` dice ademas que pasaria con un panel mas y con uno menos.
- **`pad` es solo el suelo.** Antes hacia dos papeles con 22 px: como separacion
  al suelo esta bien, como margen lateral no es nada.

**El retrato 3D del heroe, `Portrait.lua`, 2026-08-19. Construido, no visto en
juego.** `CreateFrame("PlayerModel")` + `SetUnit("player")` en el hueco del
retrato: el mismo widget con el que el cliente dibuja tu personaje en la ficha,
asi que vive -- animaciones, equipo, montura. `SetPortraitTexture` habria sido
una linea pero es un recorte 2D fijo.

- **Los huecos de la barra ahora pueden alojar.** `SLOTS` gana `host = true` y
  esos huecos tienen un `Frame` de verdad, colocado y reescalado con la barra,
  POR ENCIMA del arte porque las piezas son opacas ahi. El minimapa ya lo hacia
  con un frame escrito a mano; ahora son dos y sale de la tabla.
- **NADA del widget `Model` se llama a pelo.** El `Model` de 3.3.5a no tiene la
  misma lista de metodos que el moderno y casi toda la documentacion de fuera es
  de las nuevas versiones. Todo pasa por un `Try` que comprueba que el metodo
  exista y se traga el fallo, y **`/rts portrait status` imprime cuales existen
  de verdad en este cliente**. Misma leccion que `nameplateMaxDistance` y
  `gxWindowedResolution` -- comprobar contra el cliente, no contra internet --
  solo que aqui la comprobacion se queda puesta. La apuesta era `SetCamera(1)`,
  la camara de retrato de los modelos de personaje: **no hace nada en este
  cliente** -- visto en juego, sale el cuerpo entero igual que con la 0.
- **`SetUnit` REHACE el modelo y borra camara, posicion y giro**, asi que va
  siempre PRIMERO. Ponerlo despues es el fallo tipico: se ajusta el encuadre,
  algo refresca el modelo y el encuadre desaparece sin que nada de error.
- **El cliente vacia el modelo y el evento llega antes que el modelo.** Una
  pantalla de carga lo deja en blanco; se rearma con `PLAYER_ENTERING_WORLD` y
  `UNIT_MODEL_CHANGED` mas **dos reintentos con retraso** (0.5 s y 2 s), porque
  justo al acabar de cargar el modelo aun no se puede pedir.
- **DOS SIGNOS QUE NADIE SABE, Y LA TABLA QUE LOS AVERIGUA.** `SetPosition` no
  documenta en 3.3.5a si el primer eje acerca o aleja ni si el tercero sube o
  baja, y `SetModelScale` escala desde los PIES, asi que ampliar manda la cabeza
  fuera del cuadro y hay que compensar sin saber hacia donde. Dos incognitas de
  signo y una de metodo. En vez de razonarlo hay **siete encuadres en una tabla**
  -- las cuatro combinaciones de signo, dos con escala y una mixta -- y
  `/rts portrait try` pasa al siguiente dejandolo aplicado y guardado. La buena
  se reconoce en cuanto sale. Misma decision que el circulo de la etapa 5e: una
  lectura estatica convincente vale UNA prueba barata en juego, no maquinaria
  encima.
- **La escala va ANTES que la posicion.** `SetModelScale` mueve la cabeza, asi
  que posicionar primero hace que escalar deshaga el centrado -- y entonces el
  resultado depende del orden en que se toquen los mandos, que es justo lo que
  impide encuadrar a ojo.
- **Lo guardado se acota AL LEERLO, no solo al escribirlo.** Este cliente traia
  un `grow = 688` de una version anterior: las SavedVariables no olvidan ninguna
  clave y sobreviven a la version que la escribio, asi que acotar dentro de los
  `Set*` no vale -- esos solo corren cuando el jugador teclea. Y no todo se
  acota igual: pasarse en `share` es una intencion exagerada que se recorta, un
  `grow` de 688 es basura y vuelve al valor de fabrica, porque recortarlo al
  maximo daria ocho paneles diminutos que ademas pareceria deliberado. Lo
  descartado se imprime.

**`rts-tools\Convertir_Arte.py` es nuevo** (boton `Convertir_Arte.bat`): lee los
PNG exportados, los guarda en `rts-project\art-src` y escribe el TGA en
`addon\art`, rechazando lo que no sea potencia de dos hasta 512.

- **Guarda el PNG en el repo a proposito.** La carpeta de descargas se vacia y no
  esta en git. Si el unico original vive ahi, dentro de un mes el TGA es lo unico
  que queda y ya no se puede ni reexportar ni comparar. `art-src` es el original,
  `addon\art` el derivado.
- **El nombre del TGA es el del PNG.** La primera exportacion venia como
  `Frame 3`, `Frame 9`… y la correspondencia con `bar-minimap`, `bar-centre` era
  una tabla que habia que mantener a mano en dos sitios. Ya no existe.
- **Se comprueba leyendo el TGA de vuelta**, pixel a pixel contra el PNG, no
  confiando en que la cabecera este bien. Mismo motivo que las rutas de textura
  inexistentes: un TGA que el cliente no entiende **no da error, no dibuja
  nada**, y el fallo aparece como "el arte no carga" sin decir por que.

## El lanzador mentia en las dos direcciones, 2026-08-20

Un "pulsando Jugar.bat el injector no se aplica" que resulto no ser el injector.
La cadena entera estaba viva y probada en el log de esa misma sesion; lo que
fallaba era el juego, por otro sitio. Merece la pena dejar escrito **como se
demuestra eso en un minuto**, porque el sintoma de un DLL ausente y el de un
error de Lua a mitad de la inicializacion son *identicos*: sin seleccion, sin
halos, sin mover ni atacar.

**`rts_core.log` prueba la cadena de cinco lineas, y las cinco importan:**

| Linea | Que descarta |
|---|---|
| `image base 00400000 (expected)` | el DLL esta cargado en Wow.exe |
| `player pos = ... <-- OFFSETS GOOD` | los offsets valen para *este* binario |
| `WndProc subclassed` + `publish loop started` | el hilo principal esta enganchado |
| `first publish ok (hasPos=1 hasCam=1)` | DLL -> addon: los globales `RTS_*` se escriben |
| `circle: [N] guid 0x... colour 0x...` | **addon -> DLL**: el addon escribio el canal CVar y el DLL lo decodifico |

La ultima es la que cierra el circulo y la que mas se pasa por alto: si aparece,
el addon esta vivo y hablando, y el problema esta aguas abajo. Comprobar ademas
que el addon desplegado es identico al repo (`diff -rq`) y que pasa
`check_addon.py` cuesta otros diez segundos y descarta el resto del camino.

**El log en silencio NO es un bucle muerto.** Las lineas `diag player` se cortan
a los ~5 segundos a proposito (`g_heartbeat <= 150` en `Publisher.cpp`), porque
la version sin capar genero un log de 12 MB. Un log que no crece es lo normal.

**Tres defectos del lanzador, los tres arreglados, los tres del mismo tipo:
daban por bueno algo que no habian comprobado.**

- **`LoadLibraryW` sobre un DLL que ya esta dentro devuelve el handle que ya hay
  -- no nulo, indistinguible de un exito -- pero `DllMain` NO se reejecuta**, asi
  que no se inicializa nada y no llega nada nuevo al log. El injector presentaba
  eso como inyeccion nueva. Ahora mira el snapshot de modulos del proceso destino
  *antes* de inyectar (`FindRemoteModule`) y sale con codigo **2**, distinto del
  0 de "inyectado ahora" y del 1 de "fallo". El snapshot devuelve
  `ERROR_BAD_LENGTH` mientras el cliente aun carga modulos, que es justo cuando
  se le pregunta, asi que lleva reintentos.
- **El injector hacia `getchar()` tambien cuando acertaba**, y el `.bat` lo llama
  en primer plano: se quedaba clavado en `[2/3]` con pinta de cuelgue y el paso
  `[3/3]` no llegaba a correr solo. Peor: el proceso sobrevive a la ventana, y
  un `injector.exe` de una sesion anterior esperando su Enter es lo que **impide
  enlazar** en la siguiente compilacion (`LNK1104` sobre `injector.exe`). Si
  aparece ese error, mirar `tasklist` antes que nada. Ahora solo pausa al fallar.
- **`Log.cpp` abria el log sin `FILE_SHARE_DELETE`**, asi que con el cliente vivo
  el `del` del `.bat` fallaba **en silencio** (`>nul 2>&1`) y el paso que venia
  detras validaba el log de la sesion ANTERIOR. Ya lleva el flag, pero el `.bat`
  sigue sin borrar: en Windows un borrado con ese flag solo quita el nombre
  cuando se cierra el ultimo asa, asi que el fichero sigue ahi y creciendo hasta
  que sale el cliente. La comprobacion buena es que el log **CREZCA**, que
  funciona con el cliente abierto o cerrado.

**`scriptErrors` esta ahora a 1 en `Config.wtf`.** No estaba, y por defecto es 0:
WoW se traga los errores de Lua sin decir nada. Es lo que convierte "el modo RTS
no hace nada" en un mensaje con numero de linea. `check_addon.py` cubre el caso
concreto de la local usada antes de declararse, pero no todo lo demas.

**Este `.bat` no se puede probar desde Git Bash.** `find` y `timeout` se
resuelven a las versiones Unix del PATH: la deteccion de "ya esta abierto" falla
y **abre un segundo cliente**. Desde el Explorador, o con `cmd /c` en un entorno
con el PATH de Windows.

## Stage 5k -- la sala llena, 2026-08-20. Construido, no visto en juego.

Tercera exportacion: **cuatro piezas** de arte en vez de siete, y la barra deja
de estar vacia. `docs/UI-RTS-SALA.md` lleva las medidas; aqui lo que cambia de
forma y las lecciones.

- **DOS PIEZAS SE USAN DOS VECES, UNA ESPEJADA.** `left-bar`, `minimap`,
  `middle`, `ramp` dan los siete paneles: rail | minimapa | hombro | sala xN |
  hombro' | ordenes | rail'. El espejo es `SetTexCoord(1,0,0,1)`, cuatro numeros
  en una llamada, y **no puede desincronizarse del original** -- dos ficheros
  dibujados a mano que deberian ser iguales, si. De 7 TGA (4,2 MB) a 4 (2,6 MB),
  y los seis TGA viejos estan borrados del repo. El precio: el hueco util de una
  pieza espejada esta en su reflejo, asi que la tabla `HOLE` de `Bar.lua` lleva
  las dos variantes escritas en vez de recalcularlas a mano cada vez.
- **`Bar.lua` YA NO DIBUJA NADA DE DENTRO.** Tiene el arte, las areas y las
  celdas, y tres funciones: `SlotFrame(key)` el marco, `Cells(key)` las celdas en
  coordenadas del marco, `OnLayout(fn)` el aviso de redistribucion. Siete
  modulos nuevos ponen el contenido -- `Widgets` (barra, texto, boton, color de
  clase y **un solo latido** de 5 Hz compartido), `Vitals`, `Roster`, `Foes`,
  `Card`, `Panel`, `Rails`. `OnLayout` no es un detalle: cambiar `grow` cambia el
  NUMERO de celdas, no solo su tamano.
- **ANCHO FIJO LO QUE NO GANA CON EL SITIO, ESTIRADO LO QUE SI.** Retrato (256) y
  grupo (440) son fijos: un retrato que crece con la resolucion se ve mal, y una
  barra de vida de 900 px no dice mas que una de 440. Enemigos y acciones cuentan
  columnas contra el ancho que sobre (`fill = "cols"`, 14 y 13x2 en 2560), asi
  que nadie escribe cuantos caben.
- **UN AREA QUE NO CABE NO TIENE CELDAS.** Con `grow` a 1 la sala mide 726 y el
  bloque de la derecha empieza en el 757: ancho NEGATIVO. Devolver 0 columnas
  esconde esos botones en vez de dejarlos flotando sobre el hombro. Es el unico
  caso feo del reparto y se cerro antes de verlo.
- **EL HUECO DEL MINIMAPA NO ES CUADRADO (474x452) y el minimapa si.** Escalarlo
  al ANCHO del hueco lo saca 22 px por arriba y por abajo, y un frame hijo no se
  recorta en 3.3.5a, asi que se comeria el borde del arte. Se le pasa el lado de
  la CELDA. Salio de mirar la tabla de medidas, no del juego -- que es el punto
  de tener la tabla.
- **LOS ICONOS DE LOS RAILES SE LE PIDEN AL CLIENTE.** El cliente esta dibujando
  esos doce botones ahora mismo, asi que
  `MainMenuBarBackpackButton:GetNormalTexture():GetTexture()` no puede estar mal:
  es literalmente el dibujo que hay en pantalla. Escribir la ruta de memoria es
  una apuesta, y una ruta que no existe **no da error, dibuja nada**. El precio
  es la forma -- los micro-botones son 32x64 y se dibujan con su proporcion, no
  estirados. Es la regla de `nameplateMaxDistance` y `gxWindowedResolution`
  llevada al extremo: en vez de comprobar la constante, no tener constante.
- **Los iconos de HECHIZO son por CATEGORIA a proposito.** Cincuenta hechizos
  serian cincuenta rutas escritas de memoria, y con ese fallo silencioso la lista
  de rutas es la parte que se rompe -- y encima parece un fallo de anclaje. Diez
  rutas de iconos de toda la vida, cada hechizo dice a que categoria pertenece, y
  la etiqueta debajo de cada boton dice lo que hace aunque la textura fallara.
  Los cinco hechizos por clase son todos de 3.3.5a: nada de poder sagrado ni Hex,
  que serian un `cast` que el bot ignora en silencio.
- **PLAYERBOTS YA TENIA LA MITAD DEL GESTO DE LAS MARCAS.** "Que el mago
  convierta en oveja al de la luna" parecia lo mas raro de la peticion y no
  necesitaba nada nuevo: cada bot tiene DOS marcas (`RtiValue.cpp`) -- `rti`, la
  de matar, que viene en craneo, y `rti cc`, la de controlar, que viene en LUNA -
  y la IA de cada clase ya sabe que el de `rti cc` es el que se deja fuera de
  combate. Los nombres son `star circle diamond triangle moon square cross skull`
  y coinciden uno a uno con los iconos 1..8 del cliente (`RtiTargetValue.h`). Un
  boton de marca hace las dos mitades: click pone el icono en tu objetivo y manda
  `rti`, click derecho manda `rti cc`.
- **`Panel` (ahora 4x3, ver etapa 5l) manda al GRUPO y la carta a la SELECCION.**
  `Broadcast` contra `Send`, y es toda la diferencia entre dos rejillas utiles y
  una repetida. La casilla de abajo a la derecha SALE del modo RTS: es un boton y
  no una tecla mas porque el modo esconde la interfaz de Blizzard, y "donde
  estaba la tecla" es justo lo que no se recuerda cuando algo va mal.
- **`GetComboPoints` tiene dos firmas y este cliente quiere una.** Fuera dicen
  `GetComboPoints()`, aqui es `("player", "target")`. Llamarla mal no da error:
  devuelve nil y los puntos no aparecen nunca. Se prueban las dos una vez y se
  recuerda la que contesta un numero. Igual con `SetRaidTarget` /
  `SetRaidTargetIcon`.
- **Los tres paneles flotantes de antes se APARTAN, no se borran.**
  SUPERADO en la etapa 5l: estan BORRADOS. La regla dura de devolverlos al
  estado en que estaban sigue viva donde importa -- Chrome con los frames de
  Blizzard y Camera con sus CVars.
- **LA GEOMETRIA SE COMPROBO SIMULANDO EL REPARTO FUERA DEL JUEGO** -- areas,
  celdas, solapes y desbordes, a pantalla completa y en ventana. Encontro dos
  fallos antes de compilar nada: el borde de abajo de la sala llevaba un pixel de
  menos (las cuatro filas del grupo salian 1 px mas altas que su hueco) y el
  minimapa no cuadrado de arriba. Cuesta un script de treinta lineas y es la
  version barata de la leccion de la etapa 5e -- salvo que aqui la prueba barata
  no necesita el juego. Lo que queda por ver en `PRUEBAS-10` no son medidas: son
  las llamadas del cliente que no se pueden probar desde fuera.

## Stage 5l -- lo que dijo el juego, 2026-08-22. Construido, no visto todavia.

Primera vez que la sala de la etapa 5k se ve en pantalla. `docs/UI-RTS-SALA.md`
§10 lleva el detalle; `docs/PRUEBAS-11.txt` es la ronda siguiente. Lo que hay que
retener:

- **LA GEOMETRIA AGUANTO ENTERA Y TODO LO QUE FALLO FUE UNA LLAMADA DEL CLIENTE
  O UNA DECISION DE PRODUCTO.** Era exactamente lo que la simulacion prometia, y
  es el argumento para seguir simulando el reparto antes de compilar: el script
  de treinta lineas volvio a correr con las medidas nuevas y volvio a cazar un
  fallo -- ver el ultimo punto.
- **TRES DE LOS DOCE BOTONES DE LOS RAILES ERAN IMPOSIBLES, Y EL FICHERO DECIA
  QUE NO.** `Rails.lua` afirmaba *"nada de aqui esta protegido: lo que esta
  protegido son las acciones de COMBATE"*. Falso: `ToggleWorldMap`,
  `ToggleTalentFrame` y `ToggleGameMenu` estan protegidas en 3.3.5a igual que
  `TargetUnit`, y da igual que el boton sea nuestro. La frase se escribio
  razonando por analogia -- "esto no es combate, luego no estara protegido" --
  que es justo lo que este proyecto lleva tres etapas aprendiendo a no hacer, **y
  encima era comprobable con un `/script ToggleWorldMap()` en cinco segundos**.
  La regla de "comprobar contra el cliente" se aplico a los ICONOS, que era la
  parte visible, y no a las FUNCIONES, que era la parte que decidia si el panel
  servia para algo. Railes borrados; el arte de los extremos se queda como remate
  y ahora TOCA el resto (`GAP` a 0).
- **LA CARTA TENIA DOS FILAS Y UNA NO ERA DE ACCIONES.** Las ocho marcas de banda
  y los cinco hechizos de clase fuera: las marcas eran ocho botones para un gesto
  que solo se usa de dos maneras (ahora son dos, `Matar` = craneo + `rti` y
  `Contro` = luna + `rti cc`), y los hechizos eran cincuenta nombres a mano que
  ademas solo aparecian con UN bot seleccionado, o sea una fila que cambiaba de
  contenido segun cuantas unidades tuvieras cogidas. La fila que se libera se la
  lleva la de enemigos, que pasa a dos. El panel global pasa de 3x3 a **4x3**.
- **EL HEROE ES MAS ANCHO QUE UNA FILA DEL GRUPO, Y ESO ES LA JERARQUIA.** 330
  contra 300; antes era 256 contra 440 y se leia como que el grupo importaba mas
  que tu. Y el aviso de "seleccionado" pasa de enmarcar la barra de vida a
  **iluminar el retrato** -- marco alrededor del hueco MAS luz dorada en el
  modelo, las dos cosas: el marco se ve de reojo, la luz es lo que hace que
  parezca encendido y no rodeado.
- **LAS GUIAS ERAN ILEGIBLES POR LA MISMA RAZON DE SIEMPRE.** Las fuentes de
  `LayoutGuides` eran 10 y 11 -- numeros de PANTALLA en un fichero cuyos numeros
  son todos de DIBUJO. A x0.5625 eso son seis pixeles. Ya van en 22 y 26, que es
  lo que `ns.W.FONT` lleva escrito desde que existe.
- **LOS TRES PANELES FLOTANTES ESTAN BORRADOS, NO APARTADOS.** `UnitBar.lua` y
  `CommandCard.lua` fuera; de `Targets.lua` queda solo la mitad de DATOS, la
  lista `TGTS` que alimenta la fila de enemigos y que no tenia sustituto. Con
  ellos se va la maquinaria de "apartar y devolver al estado en que estaban", que
  era correcta pero ya no tiene a quien aplicarse.
- **"NO CABE" ES QUE NO CABE UNA CELDA, no que el ancho sea negativo.** Con
  `grow` a 1 el bloque de la derecha salia negativo por 18 px *de casualidad*, y
  `w <= 0` bastaba. Al estrechar las filas del grupo paso a medir 48 -- positivo,
  pero menos que una celda -- y el `if cols < 1 then cols = 1` de debajo habria
  puesto un boton de 103 px en un hueco de 48. Lo cazo la simulacion, no el
  juego.

### El click que se perdia: la referencia, no el umbral

"Click derecho sobre el mundo y no registra el movimiento; al siguiente si"
(`PRUEBAS-10` H4). Siempre el primero, nunca el segundo, y esa es la firma
exacta del problema: **la camara RTS la mueve el SERVIDOR y sigue asentandose
unas decimas despues de soltar una panoramica**, asi que un click que cae en esa
ventana mide el resto del movimiento ANTERIOR y `CameraTurned()` lo archiva como
giro. El siguiente ya cae con la camara quieta.

Subir `turnEps` no lo arregla y por eso la ronda anterior no lo cerro: el
asentamiento de una panoramica larga puede ser mayor que un giro corto de
verdad, asi que cualquier umbral que trague lo uno traga tambien lo otro. **Lo
que habia que cambiar era CONTRA QUE se mide**: la referencia del vector de
camara se toma ahora 0,12 s DESPUES de la pulsacion (`TURN_ARM`), no en ella. Un
click corto suelta antes de que exista referencia y no se puede juzgar como
giro; un arrastre de verdad dura mucho mas y cuenta entero; y lo que la camara
traia de antes se descarta por construccion.

Es la tercera vez que este gesto se arregla y las tres han sido la misma clase
de error: **medir la cosa equivocada** (el cursor, que esta congelado), luego
**medirla con el umbral equivocado**, y ahora **medirla desde el instante
equivocado**.

### Rutas con shift, `Route.lua`

El gesto de RTS que faltaba. Click derecho manda; **shift + click derecho
encadena** otro punto, y otro. Los puntos se ven en el suelo unidos por una linea
de puntos y las unidades los recorren en orden. Con UNA unidad seleccionada, la
ruta sale del color de su clase; con varias, en verde.

- **Se dibuja proyectando en la interfaz, y aqui SI vale**, que es lo contrario
  de lo que se decidio para los circulos de seleccion (etapa 5e). La diferencia
  es a que se pega el dibujo: un circulo bajo los pies de un modelo tiene que
  estar exacto porque el ojo lo compara con el modelo cada frame; **un punto en
  el suelo no se compara con nada**. El precio conocido es que no tiene
  profundidad y se dibuja sobre la colina que deberia taparlo.
- **No se le manda la ruta al bot: playerbots no tiene verbo de ruta.** Se manda
  UN destino, se mira la posicion publicada por rts_core, y al llegar se manda el
  siguiente. **Cada tramo lleva su propio plazo** (40 s) porque un bot encallado
  sin plazo congela la ruta entera, y eso se leeria como "las rutas no funcionan".
- **ANOTAR NO ES MANDAR.** El click derecho normal sigue mandando por su camino
  de siempre -- `Orders:Click`, que deja al servidor decidir si era atacar,
  hablar o lootear -- y la ruta solo se queda con el destino para que el
  siguiente shift+click tenga de donde encadenar. El primer borrador mandaba las
  dos, o sea dos ordenes por click.

### El botin: las dos mitades se estorbaban

"Que todos los bots recojan todo, incluso los grises". Son dos cosas y la
primera apagaba la segunda:

- `ll all` pone la estrategia de botin `all` de playerbots
  (`LootStrategyValue.cpp`), o sea recoger todo. La de fabrica es `normal`, que
  pasa por `ItemUsageValue` y deja los grises. Se manda por PARTY al entrar en
  modo RTS y **cada vez que cambia el grupo**, porque la estrategia vive en la
  memoria de cada bot y uno que entra despues nace con la de fabrica.
- **`AiPlayerbot.FreeMethodLoot = 0` -- el valor por defecto -- anula todo lo
  anterior.** `LootAction::isUseful()` es
  `freeMethodLoot || !grupo || metodo != FREE_FOR_ALL || esJugadorReal`, y el
  addon pone el grupo en FREE_FOR_ALL para que TU puedas lootear cualquier
  cadaver sin esperar el turno. O sea que el botin libre **apagaba el loot de
  todos los bots**, en silencio y sin forma de verlo desde el cliente. Puesto a
  **1** en `playerbots.conf`, con el porque escrito al lado.

### El lanzador, otra vez

`2-Jugar.bat` esperaba **15 segundos fijos** antes de inyectar. En un arranque
lento el cliente sigue montando modulos y el hilo remoto falla o entra a medias;
en uno rapido sobran diez segundos. Ninguno de los dos lo arregla un numero
distinto, asi que ahora espera a que el PROCESO exista y **reintenta la
inyeccion hasta ocho veces**, que es lo unico honesto: no hay senal barata y
fiable de "ya se puede inyectar", asi que en vez de adivinar una se prueba y se
vuelve a probar. Ademas mata el `injector.exe` huerfano antes de empezar -- es lo
que provoca el `LNK1104` de la siguiente compilacion.

**Nada de mirar el titulo de ventana con `tasklist /v`**: esa columna dice "N/A"
en ingles y "N/D" en espanol, asi que la deteccion dependeria del idioma de
Windows. Misma familia que `gxWindowedResolution`.

### "No valid realms specified": el flag del realm se atasca en 1

El authserver arrancaba, conectaba con la base de datos, la actualizaba y
entonces se mataba con **"No valid realms specified."**. La `realmlist` tenia su
fila, correcta, con `flag = 0`. No tiene nada que ver con el RTS y merece estar
escrito porque el sintoma no apunta a la causa por ningun lado.

Cuatro sitios escriben ese flag, y el authserver lo lee con
`... FROM realmlist WHERE flag <> 3`:

| momento | escritura | queda |
|---|---|---|
| worldserver empieza a cargar (`Main.cpp:284`) | `(flag & ~2) \| 1` | **1** |
| worldserver ya listo (`Main.cpp:372`) | `flag & ~1` | 0 |
| worldserver sale LIMPIO (`Main.cpp:411`) | `flag \| 2` | 2 |
| authserver arranca (`authserver/Main.cpp:134`) | `flag \| 2` | +2 |

`1 + 2 = 3`, el `WHERE` descarta la fila, `GetRealms()` sale vacio y el
authserver se cierra. **Sin ningun mensaje sobre el realm**: el codigo solo avisa
cuando no puede resolver una direccion, y aqui la consulta simplemente no
devolvio filas.

El bit 1 significa "el worldserver esta cargando" y lo normal es que dure
segundos. **Se queda pegado si el worldserver se cierra con la X o peta MIENTRAS
CARGA** -- entre las lineas 284 y 372 -- y desde ese momento fallan TODOS los
arranques del authserver, incluidos los de dias siguientes. Es un fallo de hoy
causado por como se cerro ayer, y nada en el mensaje lo relaciona.

`1_Iniciar_Servidor.bat` hace ahora `UPDATE realmlist SET flag = flag & ~1`
antes de lanzar el authserver. Solo el bit 1, que antes de arrancar el
worldserver nunca puede ser cierto; el bit 2 (offline) lo gestionan los dos
servidores y es correcto dejarlo.

Y de paso: el aviso de "no cierres esas ventanas con la X" del propio lanzador
no era una manía. Esta es la consecuencia concreta.

## Stage 5m -- la segunda pasada, 2026-08-22. Construido, no visto todavia.

`PRUEBAS-11` en juego. **El click perdido esta cerrado** (E1-E4 limpios, tercer
intento y el bueno), **el botin funciona** (D2/D4) y **las rutas funcionan**
(F1-F9). Lo que sigue es lo que la ronda cambio de sitio.

### El encuadre del retrato no fallaba: no llegaba

"Todos los try se ven igual" (C1). Siete encuadres con escalas de x1.8 a x3.4 no
pueden verse iguales si la escala se aplica -- que se vean iguales significa que
**ninguna** de las llamadas de encuadre estaba llegando al modelo. La tabla de
tanteo estaba buscando el numero correcto de un mando desconectado.

`SetUnit` no termina de trabajar cuando vuelve: pide la carga del modelo, la
carga acaba mas tarde, y al acabar el widget **reinicia camara, posicion y
escala**. Asi que todo lo que se hacia justo despues de `SetUnit` -- que es
literalmente lo que la etapa 5j dejo escrito en mayusculas como la forma
correcta -- lo borraba el cargador un instante despues. El consejo "SetUnit
primero" era cierto y a la vez insuficiente: primero si, pero **no en la misma
vuelta**.

Ahora `Load` pide el modelo y `Frame` lo encuadra, y `Frame` se vuelve a llamar
desde `OnUpdateModel` / `OnModelLoaded`, que es el cliente avisando de que ya
tiene el modelo. Encuadrar de mas no cuesta nada.

**Y se anade `/rts portrait api`**, que vuelca la lista COMPLETA de metodos que
este widget tiene de verdad, sacada de su metatabla. Es la regla de "comprobar
contra el cliente" llevada al final: en vez de comprobar una constante, no tener
constante -- si el encuadre vuelve a no responder, la primera pregunta se
contesta en un comando en vez de en una ronda de pruebas.

### El botin dejo el chat, y el reproche era exacto

D1: *"quiero que sea una orden por defecto, no que tengan que susurrarlo en el
chat cada vez. Incluso hace tiempo que mandamos ordenes a los bots sin pasar por
el chat."*

Tenia razon en las dos mitades. Todas las demas ordenes dejaron el chat en la
etapa 6 y esta se quedo atras -- y el motivo que yo tenia escrito para
justificarlo (*"replicarlo en mod-rts obligaria a enlazar contra las cabeceras de
playerbots"*) **era falso, y bastaba con abrir el fichero para verlo**:
`RtsOrders.cpp` incluye `PlayerbotAI.h` desde que existe y lee y escribe el
contexto de la IA para mover bots. La estrategia de botin es un valor mas de ese
contexto.

Verbo `LOOT 1|0` en mod-rts: `SetGroupLoot` recorre el grupo y hace
`GetValue<LootStrategy*>("loot strategy")->Set(LootStrategyValue::all)`. Sin
chat, sin cola, sin que se vea. El `ll all` por chat se queda **solo** como
respaldo para un servidor sin mod-rts.

**La razon que justifica no hacer algo caduca antes que la decision de no
hacerlo.** Es el mismo patron que la etapa 5h: un apano que sigue en pie despues
de que desapareciera aquello para lo que estaba.

Un detalle que costo pensarlo: `Orders:HasServer()` se pone a true con la
PRIMERA respuesta de mod-rts, que es un viaje de ida y vuelta que todavia no ha
llegado al entrar en modo RTS. Aplicar en ese instante habria elegido el respaldo
de chat teniendo mod-rts delante, y se habria leido como que el arreglo no se
aplico. `ApplyLootAllSoon` espera a que conteste, con tope de 2,5 s.

### Salir en combate: dos mitades, no una a medias

G8. PlayerFrame, MainMenuBar y las barras de accion son frames PROTEGIDOS y
`Show()` sobre ellos en combate lo bloquea el cliente. Chrome ya lo sabia y
aplazaba esa mitad -- pero **el resto de la salida se hacia igual**, asi que te
quedabas con la camara en tu personaje y sin ninguna interfaz hasta que acabara
la pelea. Lo peor de las dos opciones.

La salida se parte por donde esta la costura de verdad:

  * `LeaveWorld` -- camara, raton, selfbot, modo mando, rutas. Nada de eso esta
    protegido, asi que vuelve siempre y al instante.
  * `LeaveChrome` -- la consola y los frames de Blizzard. En combate se aplaza a
    `PLAYER_REGEN_ENABLED`.

Mientras dura el aplazamiento te quedas con la consola RTS, que lleva tu vida,
tu poder, tus puntos de combate, el grupo, los enemigos y la carta de ordenes --
y **las teclas de la barra de accion siguen funcionando con la barra escondida**,
igual que con el Alt-Z del propio juego. Se puede seguir peleando.

Con guarda en las dos direcciones: si vuelves a ENTRAR mientras dura la pelea,
la salida aplazada se cancela. Un temporizador que dispara despues de que su
motivo haya desaparecido es su propio fallo.

### Las rutas: cada unidad a su ritmo

F1. Un solo indice por ruta significaba que el grupo se paraba en cada punto a
esperar al ultimo, y en juego eso se siente como lentitud. Ahora el indice es
**por unidad** y el que llega sigue; el hueco de cada uno en la formacion se
calcula una vez al crear la ruta y no se recalcula (si no, la formacion giraria
sola en cada punto).

Y "llegar" deja de ser tocar el punto: es estar a `arrive` yardas **o haber
hecho el 95% del tramo**, lo que sea mas generoso. Un radio fijo es demasiado
exigente en un tramo largo -- los ultimos metros el bot los pasa frenando,
rodeando una piedra y recolocandose, y eso es tiempo parado que se lee como
desobediencia. Se usa el mayor de los dos umbrales porque cada uno cubre el caso
donde el otro no sirve: en tramo corto manda el radio, en tramo largo el
porcentaje.

El punto de la linea pasa a ser **redondo**: `WHITE8X8` es un pixel blanco
estirado, o sea un cuadrado, y a nueve pixeles se ve como lo que es. Se usa
`halo-01.tga`, que ya estaba en el addon -- ni un fichero mas ni una ruta que
adivinar. Puntos mas pequenos y mas juntos, disco de destino a la mitad.

### Lo demas

- **Se puede seleccionar pinchando el retrato y las barras del heroe** (C2), con
  doble click = todos, igual que en las filas del grupo y en el mundo. El gesto
  entero vive en `Selection:Click`, y esta ahi y no en cada panel porque si no la
  ventana del doble click seria de cada panel por separado: pinchar un bot y
  luego el retrato contaria como doble click sobre dos unidades distintas.
- **El botin sale en la linea de mensajes** (D3). No era cosmetico: con el chat
  escondido, recoger algo no producia NINGUNA senal -- ni que habia caido, ni si
  lo cogiste tu o un bot.

### El comprobador decia que si, y la respuesta era no

`Portrait.lua` tenia una cadena sin cerrar -- un `\n` que se convirtio en un
salto de linea de verdad -- y el addon no cargaba: *"unfinished string near
'Click: seleccionarte.'"*. Lo grave no es el fallo, que es una errata. Lo grave
es que **`check_addon.py` habia dicho "los 28 ficheros del addon estan bien"**
sobre ese mismo fichero, tres veces seguidas.

`luaparser` no es el lexer de Lua. Es mas permisivo, y **acepta un salto de
linea dentro de una cadena corta**, comprobado en dos lineas:

```python
from luaparser import ast
ast.parse('local x = "roto\nsigue"\n')   # pasa. Lua de verdad: error.
```

Un comprobador que dice que si cuando la respuesta es no es **peor que no tener
comprobador**: te quita la costumbre de mirar. Por eso el arreglo no es solo la
errata; `check_addon.py` gana dos comprobaciones propias que corren ANTES de
luaparser -- el orden importa, porque luaparser se traga la cadena rota y sigue
parseando como si nada:

- **cadenas cortas sin cerrar**, que es exactamente lo que se le escapo.
- **escapes desconocidos**, que es peor todavia porque en Lua 5.1 **no son un
  error**: `"a\Ib"` se lee como `"aIb"` y sigue. A una ruta de textura a la que
  se le haya comido una barra le queda `InterfaceIconsX`, que no existe, y una
  ruta que no existe no da error: **dibuja nada**. Es el fallo silencioso que
  este proyecto persigue desde la etapa 5i, y aqui se caza gratis.

Las dos se probaron contra ficheros rotos a proposito antes de darlas por
buenas. Una prueba que pasa con el codigo roto no es una prueba.

### Las herramientas se comen las barras invertidas

La causa de la errata, y merece estar escrita porque volvera a pasar: el
`\n` de una cadena Lua **no sobrevive** a segun que forma de editar el fichero.
Aqui se colo escribiendo el Lua desde un heredoc de shell, que interpreto la
barra antes de que llegara al fichero. La regla practica es no escribir
escapes de Lua a traves de capas que tambien los interpretan -- y, pase lo que
pase, correr el comprobador, que ahora si lo ve.

### `sim/`, las pruebas que no necesitan el juego

Dos guiones de Python que reproducen la parte del addon que es aritmetica pura y
le pasan los casos que en juego cuestan una ronda de pruebas cada uno.
`bar_layout.py` (el reparto de la barra) ya habia cazado tres fallos antes de
compilar; se guarda por fin en el repo en vez de reescribirse cada ronda, junto
al nuevo `route_advance.py`.

Y `route_advance.py` nacio cazando uno de verdad, que estaba en el codigo que
acababa de escribir y que la revision a ojo no vio: **un bot que llega a un
punto mientras otro sigue andando, y entonces anades un punto con shift**. Su
indice pasaba a apuntar al punto nuevo pero nadie se lo habia mandado, asi que
media la llegada contra el punto ANTERIOR -- donde estaba parado --, se daba por
llegado y **se saltaba el punto nuevo entero**. Se arregla con `u.sent`, el
punto que de verdad se le ordeno: solo se comprueba la llegada de un tramo que
se haya mandado.

Los dos guiones llevan un interruptor para volver al comportamiento anterior
(`SENT_GUARD = False`) y comprobar que la prueba tiene dientes. La unica forma
de saber que un test sirve es romper el codigo a proposito una vez y ver que
falla.

## La retencion de altura de camara, BORRADA 2026-08-23

Mantener una separacion constante sobre el terreno mientras panoramizas. Se
construyo por los dos caminos que existen, se vieron los dos en juego, y esta
**borrada de los dos lados** -- no aparcada. Se pidio quitarla y quedarse con la
camara de siempre mas las teclas de subir y bajar, que es lo que hay.

- **Corrigiendola el SERVIDOR (medir el terreno y `NearTeleportTo`) es un
  ascensor.** Baja a escalones, y cada teleport cancela el movimiento que esta
  aplicando el CLIENTE, asi que el avance se para en seco en cada uno.
- **Corrigiendola el CLIENTE (`UNIT_FIELD_HOVERHEIGHT` + `SMSG_MOVE_SET_HOVER`)
  necesita la GRAVEDAD ENCENDIDA**, porque el hover es un modificador del
  seguimiento del suelo del cliente y sin gravedad no hay seguimiento que
  modificar. Y la gravedad apagada es justamente lo que hace que la camara se
  quede donde se la pone. Asi que al armarlo la camara **CAE al suelo y el hover
  la levanta despues**, cada vez. Esa caida es el mecanismo, no un fallo del
  mecanismo -- y es lo que se vio en pantalla.

Si alguna vez se vuelve, lo primero que hay que encontrar es seguimiento del
suelo del lado del cliente SIN gravedad. Sin eso los dos caminos acaban aqui.

**ESCONDER UNA FUNCION NO ES APAGARLA, y ese fue el fallo de verdad.** La ronda
anterior la saco de la ayuda y dejo la maquinaria intacta "para volver a ella".
Lo que no se penso es que **el ajuste que la enciende ya estaba guardado** en las
SavedVariables de ese cliente, de las pruebas del dia anterior: el addon lo
reenviaba en cada entrada en modo RTS, asi que la funcion oculta se armaba sola y
el fallo siguio pasando exactamente igual. Una funcion escondida con su
interruptor puesto no esta escondida. Por eso el borrado incluye
`RTSCommandDB.camHold = nil` al cargar -- las SavedVariables no olvidan ninguna
clave y sobreviven a la version que la escribio, que es la misma leccion que el
`grow = 688` de la etapa 5j.

Y la razon que justificaba dejarla puesta -- *"borrarla obligaria a redescubrir
que el camino del servidor es un ascensor"* -- se cumple escribiendolo aqui, que
cuesta un parrafo, en vez de dejando doscientas lineas armadas en el codigo.
Tercera vez que aparece el patron de la etapa 5h: **un apano que sigue en pie
despues de que desapareciera aquello para lo que estaba.**

## Las teclas de altura cortan el avance, y se queda asi 2026-08-23

Visto en juego (`PRUEBAS-16` C1/C2): ESPACIO y C suben y bajan la camara, pero
**no se puede avanzar y subir a la vez**. Es el MISMO fallo que la retencion de
altura que se borro ese mismo dia, con la misma causa exacta -- y al borrarla
deje puesto lo unico que sobrevivia *de ella*: su defecto.

**La camara la controla el cliente, asi que desde el servidor solo se puede mover
con `NearTeleportTo`, y un teleport CANCELA el movimiento que el cliente esta
aplicando.** Las teclas corren en el tick del mundo: 10-20 teleports por segundo,
cada uno cortando el avance. No hay numero que lo arregle: **o el movimiento
vertical lo hace el cliente, o corta el horizontal.**

Decidido dejarlo asi -- sube y baja bien parado, que es como se usa. Las tres
salidas, escritas para no volver a razonarlas:

- **El DLL escribe la altura de camara cada frame.** Es la respuesta correcta:
  subida de verdad, suave, y el avance sigue plano porque no se toca la criatura.
  `rts_core` ya escribe el FOV en ese struct cada tick y ahi quedo demostrado que
  las escrituras por tick se quedan, asi que el hook y el sitio existen. Falta
  encontrar el campo de la altura, que puede no ser un campo -- el ojo se calcula
  del objetivo mas pitch, yaw y distancia.
- **Zoom en vez de altura.** Lo hace el cliente, es suave, gratis y funciona
  andando; con la camara inclinada, alejar sube el ojo y lo echa atras. Ya se
  rechazo una vez por duplicar la rueda del raton -- pero **ese rechazo se hizo
  sin saber que la Z era imposible**, o sea que la comparacion de entonces no es
  la de ahora.
- **Modo vuelo mientras se pulsa la tecla.** Vertical de verdad, del cliente y
  suave. El precio es el que costo la etapa 5f: con el vuelo puesto, adelante
  sigue a donde miras -- mirando al suelo y pulsando W, desciendes. Solo mientras
  la tecla este pulsada, que es justo cuando pulsarias las dos.

**Y la leccion de proceso: borrar una funcion no borra su defecto si otra cosa
comparte el mecanismo.** Documente en mayusculas que el teleport es un ascensor y
lo escribi en la cabecera del fichero donde las teclas de altura llaman a
`NearTeleportTo` doce lineas mas abajo. Cuando se identifica una causa raiz, la
pregunta siguiente no es "¿arreglo lo que se ha reportado?" sino **"¿quien mas usa
este mecanismo?"** -- y aqui la respuesta estaba en la misma pantalla.

## Los micro-botones de los railes: recortar el glifo 2026-08-23

`PRUEBAS-16` A2: de los seis botones del rail derecho, solo la bolsa salia del
tamano correcto. Los cinco micro-botones salian a la **mitad de ancho**, y no era
el reparto: el arte del micro-boton es 28x58 (1:2) y la celda 78x74 (casi
cuadrada), asi que respetar la proporcion topa con el ALTO y deja 50 unidades de
ancho sin usar. El sim lo da en un numero -- 48% del ancho de la bolsa, que es
exactamente "la mitad" que se vio en pantalla.

Se recorta el glifo del arte y se dibuja cuadrado. **Lo que importa de la
solucion es lo que NO hace:**

- **No toca las texturas del cliente.** Ni un `SetTexCoord` ni un anclaje sobre
  el arte de Blizzard. Recolocar cuatro capas por boton es facil de hacer y
  dificil de DESHACER, y dejar su interfaz un poco rara para siempre es lo que la
  regla dura prohibe. Lo que se devuelve son **cuatro escalares**: tamano, alfa,
  escala y margenes de click.
- **El boton suyo se queda**, invisible (`SetAlpha(0)`) y del tamano de la celda.
  Sigue recibiendo el click en su propio codigo, que es lo unico que hace que
  esto funcione con `ToggleTalentFrame` y compania protegidas (etapa 5l); el alfa
  no afecta al raton, asi que la diana es la celda entera y el tooltip sigue
  siendo el suyo.
- **`HitRectInsets` hay que anularlos**, porque son ABSOLUTOS: 19 abajo sobre un
  boton redimensionado a la celda deja casi la mitad sin responder, y un boton
  que se ve y no se pulsa es peor que uno pequeno.
- **La ruta del arte se le pregunta a el** (`GetNormalTexture():GetTexture()`),
  la regla de la etapa 5k.

**Y el propio cliente da la pista del recorte.** Esos `HitRectInsets` de 19 sobre
58 son el cliente declarando que el tercio de abajo del arte es pedestal y no
boton: queda el cuadrado de arriba, que es donde esta el glifo. No es adivinar
una constante, es **leer una constante que el cliente ya tiene puesta**. Lo que
no se puede leer desde fuera es donde cae el glifo dentro de ese cuadrado, asi
que hay cinco ventanas en una tabla y `/rts rails crop` pasa a la siguiente
dejandola aplicada y guardada -- misma decision que los siete encuadres del
retrato de la etapa 5j.

`sim/bar_layout.py` cubre las cinco: ninguna desborda la celda y la 1 sale de
74x74, igual que la bolsa. **Y la 5 (sin recortar) sale al 48%, o sea que el sim
reproduce el fallo antes de arreglarlo** -- que es la unica forma de saber que la
prueba tiene dientes.

## Stage 5n -- la seccion central del panel de control, 2026-08-24. Construido, no visto todavia.

`brief-panel-control-personajes.md` pedia llenar la mitad derecha de la sala con
objetivos, habilidades del personaje seleccionado y botones de rol. Addon
**0.47.0**, mod-rts **0.14.0** (cuatro verbos nuevos, hay que reiniciar el
servidor). `docs/UI-RTS-SALA.md` §11 lleva el detalle; `docs/PRUEBAS-18.txt` es
la ronda. Lo que hay que retener:

- **LA MITAD DE LO QUE PEDIA EL BRIEF YA ESTABA CONSTRUIDA, EN EL SITIO
  EQUIVOCADO.** `CommandMode.lua` + `RtsCommandMode.cpp` ya tenian
  `ActionBarSpells` (los hechizos de un bot, sacados de SU barra de acciones),
  `CastAs(bot, id, guid)` y `Aim`. Vivian en un panel flotante con `/rts
  command` -- justo la forma que `PRUEBAS-10` H1/H2 mando borrar, y que
  sobrevivio por no estar en la lista de los tres. El trabajo era **mudarlo a la
  sala y colgarlo de la seleccion**, no escribirlo. `CommandMode.lua` esta
  borrado: seleccionar UNA unidad *es* tomar el mando, sin modo que encender.

  Y la consecuencia que mas vale: **"despues el personaje vuelve a su target
  anterior" no hay que implementarlo.** `CastAs` con un guid explicito no escribe
  la seleccion del bot, asi que su siguiente vuelta de IA elige objetivo como
  siempre. Es el comportamiento por defecto, no una funcion.

  La leccion de proceso es la de la etapa 5m al reves: alli una razon caducada
  justificaba no hacer algo; aqui una funcion existente estaba escondida detras
  de un gesto que ya se habia decidido retirar. **Antes de construir lo que pide
  un brief, buscar si ya esta puesto en otro sitio con otro nombre.**

- **"ARRASTRAR DEL LIBRO DE HECHIZOS" NO PUEDE EXISTIR PARA UN BOT, y no es una
  limitacion que se pueda rodear.** Tu libro solo tiene TUS hechizos: la
  Polimorfia del mago no esta en tu cursor porque no la conoces, y `PickupSpell`
  no la inventa. La fuente que si existe es la barra de acciones del propio bot
  -- que ademas es la lista buena, porque son los hechizos que tu pusiste ahi
  jugandolo. El hueco se llena **eligiendo** (click derecho, sale su lista) en
  vez de arrastrando: lo que se pedia -- huecos vacios, configurables, por
  personaje -- se cumple entero; cambia el gesto.

- **LOS ROLES SON ESTRATEGIAS DE PLAYERBOTS Y CUALES TIENE CADA CLASE SE
  PREGUNTA.** `tank`, `dps`, `heal` y `cc` estan registradas por clase en el
  propio mod-playerbots (`DruidAiObjectContext.cpp:34`,
  `PaladinAiObjectContext.cpp:93-95`), y `passive` es la que mod-rts ya usaba
  para dejar un bot quieto. O sea que "el rol condiciona el comportamiento
  automatico" no habia que construirlo: faltaba el boton.

  La version facil es una tabla de clase a roles en el addon -- diez clases por
  cinco roles escritos de memoria -- y es exactamente el fallo que este proyecto
  paga desde `nameplateMaxDistance`: cuando falla no da error, deja un boton que
  no hace nada. Lo contesta el servidor con
  `AiObjectContext::GetSupportedStrategies()`. En `Roles.lua` no hay ninguna
  lista de clases.

  `tank`/`dps`/`heal` son excluyentes y lo aplica el SERVIDOR, asi que **un boton
  no se enciende al pulsarlo**: se manda `ROLE`, el servidor contesta `ROLES` con
  el estado completo y de ahi sale el dibujo. Encender una postura apaga las
  otras dos, y un boton que se ilumina con su propia peticion esconderia justo
  ese efecto.

- **EL FOCO PERSISTENTE TAMPOCO ES CODIGO NUESTRO.** Doble click derecho ->
  `PFOCUS`, y el servidor lo reparte: un hostil es `orders::AttackBot` (la accion
  `attack my target` del propio bot, pegajosa por construccion); un amigo es la
  lista `focus heal targets` de playerbots mas su estrategia del mismo nombre
  (`TargetValue.h:161`, `StrategyContext.h:132`) -- que ya existia porque `focus
  heal` es un comando de chat.

  La alternativa obvia era reafirmar `SetSelection` en cada tick, y habria
  peleado con el targeting del bot en empate. **Es la misma forma de error que la
  retencion de altura de camara: corregir cada tick lo que otro escribe cada
  tick.** Cuando aparezca esa forma, la pregunta es si el sistema de destino ya
  tiene un sitio donde declarar la intencion.

- **LA SALA MIDE 344 Y ESO NO SE NEGOCIA.** Lo fija el arte, asi que subir
  `share` no compra filas: solo las hace mas grandes en pantalla. Dos bandas
  nuevas salen de la fila de enemigos, que pasa de dos filas a una -- de treinta
  objetivos visibles a catorce, pagado a sabiendas. A cambio cada cuadrado lleva
  el nombre, que era la otra mitad de lo que el brief pedia. El reparto
  (130+8+3+8+111+8+76) suma exacto, y `sim/bar_layout.py` lo comprueba con las
  bandas nuevas antes de compilar nada, como todas las rondas desde la 5k.

- **LA FILA DE ROLES NO LLEVA REJILLA, y esa es la unica diferencia estructural
  con la de habilidades.** Las habilidades son "las que quepan" y `Bar.lua` las
  cuenta. Los roles son "los que tenga la clase", entre dos y cinco: una rejilla
  de ancho fijo dejaria dos fuera con `grow` 3 y dos huecos vacios con `grow` 5.
  `Cells` sin `cell` devuelve el area entera y el modulo la parte entre los que
  haya. El sim comprueba que un rol salga siempre mas ancho que alto, que es lo
  unico que la distingue de una barra de botones.

- **LANZAR VA POR EL SERVIDOR EN LAS DOS MITADES.** `CastSpellByName` esta
  protegida, y un boton seguro no sirve: el contenido de la fila cambia con la
  seleccion y cambiar los atributos de un boton seguro esta **bloqueado en
  combate**, que es justo cuando se usa. Bot -> `CAST`; tu personaje ->
  `SELFCAST`, nuevo, para que la fila no este muerta contigo seleccionado.

- **LA CARTA DE ORDENES SE FUE Y EL PANEL 4x4 TIENE DOS ALCANCES.** Con algo
  seleccionado la orden va a lo seleccionado; sin nada, al grupo. Un mismo boton
  con dos alcances es ambiguo, asi que **el alcance se ve**: etiqueta AZUL y "-> N
  seleccionada(s)" en el tooltip cuando respeta la seleccion, blanco cuando va al
  grupo. Siete de las dieciseis son globales por naturaleza y se quedan siempre
  en blanco, que es lo que hace legible la regla del resto.

### Tres trampas de cliente, cazadas antes de compilar

- **`HasServer()` es falso durante el primer segundo**, porque solo se pone a
  true con la PRIMERA respuesta de mod-rts. Pedir la barra de un bot en ese
  instante encontraba el canal cerrado y **no volvia a intentarlo nunca** -- el
  unico disparador era cambiar de seleccion. En juego: un desplegable eternamente
  en "pidiendo su barra..." que se arregla solo al reseleccionar, o sea
  intermitente y con una solucion que oculta la causa. Las dos filas reintentan
  cada 5 s. Es el mismo tropiezo que `ApplyLootAllSoon` (etapa 5m), y ya van dos:
  **`HasServer` es una promesa, no un hecho, hasta que contesta.**
- **Anclar una textura a otra textura** (`SetAllPoints(b.icon)`) no esta
  garantizado en 3.3.5a y si falla **no da error**: deja la ranura de tamano cero
  -- un hueco que parece que no existe, y justo en la pieza cuyo trabajo es decir
  "aqui va algo".
- **Un `FontString` de ancho y alto fijos NO recorta: parte en dos lineas** y
  deja la segunda a medias contra el borde. `SetWordWrap` no existe en 3.3.5a.
  Los nombres de los enemigos se recortan contando letras.

### Y la de siempre, otra vez: el shell se come las barras invertidas

Escribiendo Lua con `\n` dentro de una cadena a traves de un heredoc de shell,
tres veces en esta sesion la barra desaparecio y el `\n` se convirtio en un salto
de linea real -- que es exactamente la errata que rompio `Portrait.lua` en la
etapa 5m. Aqui se vio al momento porque las sustituciones dejaron de casar, pero
la regla practica se confirma: **para tocar Lua con escapes, editor, no
heredoc.** Y `check_addon.py` despues, que desde la 5m si lo ve.

## Stage 5o -- lo que dijo la ronda 18, 2026-08-27. Construido, no visto todavia.

Addon **0.48.0**, mod-rts **0.15.0** (hay que reiniciar el servidor).
`docs/PRUEBAS-19.txt` es la ronda. Ocho arreglos y dos adiciones, y **siete de
los ocho son la misma clase de error: algo que se dedujo del cliente en vez de
preguntarselo.** Vale la pena leerlos juntos por eso.

- **NO HABIA NI UN TOOLTIP EN TODA LA CONSOLA, Y ESTABAN TODOS ESCRITOS.**
  `W:Tip` los pone en cada boton desde la etapa 5k. La causa es que
  **`GameTooltip` es un objeto UNICO**: el mismo que dibuja "Lobo, nivel 8"
  sobre el mundo es el que usa la barra de control. La etapa 5i lo apago
  negandole el `OnShow` -- correctamente, es cromo de Blizzard -- y con el se
  fueron los nuestros. Reportado como "no tooltip", que se lee como "no se
  escribieron" y no como "se estan escondiendo", asi que sobrevivio tres etapas.

  Se arregla mirando `GetOwner()`: si el dueno cuelga de `RTSBar` o `RTSHUD`,
  pasa. `ns.IsOurs` sube por los padres buscando un nombre que empiece por
  "RTS", asi que vale hasta para los botones del CLIENTE que reparentamos en
  los railes -- su tooltip nativo vuelve gratis.

  **La leccion es sobre compartir un singleton con Blizzard.** Apagar un objeto
  global "porque es suyo" apaga tambien el uso que le damos nosotros, y el
  sintoma aparece en el sitio que menos lo relaciona.

- **EL CLICK DERECHO EN UN ENEMIGO SE PERDIA ENTERO, y no era el guid.**
  "Selecciono varios y click derecho en un enemigo y no van a atacarle". La
  orden ni salia: todo el camino estaba detras de `if ... and x`, y
  `CursorGroundPoint` devuelve nil mas de lo que parece -- cuando el rayo del
  DLL no acierta terreno cae a cortar un PLANO horizontal a la altura del
  jugador, y **un rayo que sube no cruza ese plano nunca** (`k <= 0`). Pinchar
  algo cuesta arriba o alto en la pantalla: sin punto, sin orden, sin mensaje.

  El arreglo no es aflojar la estimacion sino notar que **cuando hay un GUID la
  estimacion no hace falta**: el DLL publica la posicion de ese bicho treinta
  veces por segundo, y sirve para atacar, interactuar y lootear. Solo el click
  al SUELO necesita el corte del rayo, que es justo el caso donde existe. Y si
  no hay ni suelo ni objetivo, **ahora lo dice**: un click que no hace nada y no
  imprime nada es indistinguible de un click sobre hierba, y esa confusion ya ha
  costado tres rondas en este mismo gesto.

- **`HitRectInsets` DICE DONDE SE PULSA, NO DONDE ESTA EL DIBUJO.** El recorte
  del glifo de los micro-botones (etapa anterior) salio de deducir, de los 19 de
  margen inferior que declara el cliente, que el tercio de abajo es pedestal y
  el glifo esta arriba. En juego los recortes salieron **transparentes**, que no
  es "salio el pedestal": es que ahi no hay pixeles. Las ventanas van ahora
  ancladas abajo, y las de arriba se quedan al final de la tabla.

  La tabla ademas **lleva sello de generacion**, porque lo guardado era un
  indice valido cuyo SIGNIFICADO cambio -- comprobar el rango no basta cuando lo
  que se mueve es lo que el numero quiere decir. Misma familia que el
  `grow = 688` y que el `camHold` que sobrevivio a la funcion que lo leia.

- **UN BOT EN `passive` OBEDECE LA ORDEN DE ATACAR Y LUEGO NO PELEA.**
  `DoSpecificAction` dispara la accion del bot saltandose las estrategias, asi
  que sale y llega; lo que SOSTIENE la pelea son las estrategias, y `passive`
  las anula. La orden reportaba exito y en pantalla no pasaba nada. **No se
  corrige por nuestra cuenta -- el rol lo puso el jugador -- se DICE**, que es
  la otra mitad de la regla: desobedecer en silencio es el mismo error del otro
  lado.

  Y habia dos fallos de verdad debajo, los dos de asimetria entre poner y
  quitar:

  **Uno.** `SetRole("passive", off)` solo tocaba `BOT_STATE_COMBAT`, mientras
  que `Suppress` -- tomar prestado el bot para lanzar por el -- y `PossessBot`
  lo ponen en **los dos**. Los dos tambien lo quitan de los dos al soltar, asi
  que en el camino feliz cuadra; pero si ese soltar no llega a correr (el bot
  se va del grupo, el maestro se desconecta), el `passive` del estado NO
  combate se queda. Ese bot no reacciona a nada, la fila de roles lee el estado
  de combate, lo ve apagado, y no ofrece nada que pulsar: se lee como “los bots
  ya no atacan” y ningun boton lo explica. Ahora `passive` es simetrico en los
  dos estados y se lee como puesto si lo esta en cualquiera de ellos.

  **Dos, y es el mismo error del otro lado.** `Suppress(ai, false)` hacia
  `-passive` a secas, que no es restaurar sino **suponer** que el bot no estaba
  pasivo antes. Si le habias puesto “Esperar” a mano, usar una de sus
  habilidades te lo quitaba tres segundos despues -- en silencio, con el boton
  de la fila apagandose solo, y sin que nada relacione las dos cosas. Ahora
  captura `HasStrategy` antes del primer cambio y devuelve a lo capturado, que
  es la misma regla dura que `Camera.lua` aplica a sus CVars y `Chrome.lua` a
  los frames de Blizzard.

  **Correccion sobre la primera version de este apartado: `Hold` NO pone
  passive.** Manda el `stay` de playerbots, y el camino de `stay` de este
  modulo (`MoveBot`) hace justo lo contrario -- `-passive` en los dos estados.
  Lo escribi de memoria por parecido de forma con `Suppress` en vez de abrir el
  fichero, que es el error que este documento lleva cinco etapas describiendo.
  El fallo que se arregla es real; el caller que lo dispara no era ese.

  Lo que SI vale la pena retener del mecanismo, verificado en `Engine.cpp`:
  los multiplicadores solo se aplican en `DoNextAction`, sobre lo que se saca
  de la cola (linea ~182). `ExecuteAction` -- por donde entra
  `DoSpecificAction` -- no los mira: comprueba `isUseful`/`isPossible` y
  ejecuta. Por eso la orden explicita sale y lo que la continuaria, que se
  encola en la linea 344 y se saca en el tick siguiente, muere ahi.

- **`GetActionInfo` NO GARANTIZA DEVOLVER UN ID DE HECHIZO.** "Me salen hechizos
  raros" con tu personaje seleccionado, y `SELFCAST` que no lanzaba nada: es un
  solo fallo. El segundo valor puede ser el **indice del libro**, y pasarle un
  indice a `GetSpellInfo` **no da error** -- devuelve otro hechizo cualquiera,
  con nombre e icono. De ahi la lista rara, y de ahi el "no conoces ese hechizo"
  del servidor, que era literalmente cierto.

  No se elige a ciegas cual de las dos lecturas vale: **se contrasta contra el
  icono que la casilla ya esta dibujando** (`GetActionTexture`), que es la unica
  fuente que no puede mentir. `/rts skills status` imprime por que camino se
  resolvio, asi que si vuelve a pasar se contesta en un comando en vez de en una
  ronda. Es el patron de `/rts portrait api` llevado a otra API dudosa.

- **LAS MARCAS DE APUNTADO EXISTIAN EN UN SOLO PANEL DE TRES.** El click derecho
  sobre una fila del grupo y sobre el retrato del heroe apuntaba desde la etapa
  5n -- es como el sanador cuida del tanque -- pero solo `Foes.lua` las
  dibujaba. Una orden que se da y no se ve es indistinguible de una que no se
  dio ("mi avatar no se ilumina en azul ni nada"). Ahora las llevan los tres.

  Y la que SI se dibujaba no se veia: **el puntual era un velo a alfa 0,35** y
  el foco cuatro barras a 0,95. La diferencia no estaba en si la marca se ponia,
  estaba en cuanta tinta llevaba. Las dos siguen siendo distinguibles por COLOR
  y GROSOR, que se leen de reojo, en vez de por "solido contra translucido", que
  hay que mirar de cerca para notarlo.

- **LA CURACION SE CANCELABA PORQUE `passive` PERMITE `follow` A PROPOSITO.**
  Lo unico que corta un lanzamiento sin dano de por medio es el movimiento, y el
  bot se movia por dos motivos: playerbots se rinde solo si el bot anda y el
  hechizo tiene tiempo de lanzamiento (`bot->isMoving() && spell->GetCastTime()`
  en `PlayerbotAI::CastSpell`), y la supresion que ponemos para tomarle el mando
  **no apaga el seguimiento** -- `PassiveMultiplier` lleva "follow" en su lista
  de partes permitidas. Asi que un bot recolocandose se movia durante el
  lanzamiento y lo interrumpia. `CastAs` le para antes de lanzar, igual que ya
  hacia `MoveBot`.

- **SELECCIONARTE DESDE EL MUNDO tenia dos caminos y los dos pueden fallar a la
  vez**: el mouseover del cliente no es fiable sobre uno mismo con la camara
  poseida, y la lista de unidades del DLL se centra en la CAMARA, asi que con la
  camara despegada lejos tu cuerpo se queda fuera de ella. `RTS_PX/PY/PZ` se
  publica siempre y es el tercer camino que no puede faltar.

### Las dos adiciones

- **Fijar bichos del mundo en la fila de enemigos.** Click izquierdo sobre un
  hostil lo mete en la consola; **shift + izquierdo suma**. Se pidio shift +
  DERECHO y no puede ser: ese gesto encadena puntos de ruta desde la etapa 5l, y
  darle un segundo significado segun lo que hubiera bajo el cursor haria que
  encadenar una ruta dependiera de con cuanta punteria pasaste por encima de un
  lobo -- que es exactamente lo que aquella decision descarto por escrito.

  La lista es **aparte de `TGTS`** y tiene que serlo: `TGTS` significa "a esto
  le esta pegando alguien" y se reemplaza entera dos veces por segundo, asi que
  un bicho al que aun no ataca nadie desapareceria en medio segundo -- justo el
  que acabas de pinchar. Caducan a los dos minutos sin verlos, para que la fila
  no se llene de lobos de hace media hora.

- **Sombras bajo los personajes: `shadowLevel`, y esta escrito lo que NO da.**
  Existe en este cliente (comprobado abriendo `Config.wtf`, donde esta a 0) y se
  pone a 2 en modo RTS, capturado y devuelto como todos los CVars de la camara.
  **3.3.5a no expone tamano ni dureza de la sombra** -- es una escala de
  calidad. Si no basta para distinguir unidades, la respuesta buena no es este
  CVar: es el circulo nativo bajo los pies, que ya existe desde la etapa 5e,
  admite color por unidad y hoy solo lo llevan las seleccionadas. Eso son un
  estado mas en el canal empaquetado, o sea recompilar `rts_core`, y se hace si
  la sombra falla.

## La sala se vacia, 2026-09-02. Addon 0.49.0, mod-rts SIN TOCAR.

Se pidio borrar entera la logica del centro de la HUD -- el heroe, las barras
del grupo, las habilidades, los objetivos -- para repensar que va ahi. No es un
arreglo: es una decision de producto, y lo que sigue es lo que costo hacerla
bien. `docs/UI-RTS-SALA.md` §13 lleva el detalle.

**Ocho ficheros borrados, ~1.400 lineas:** `Portrait`, `Vitals`, `Roster`,
`Foes`, `Skills`, `Roles` (los seis paneles), `Targets` (el sondeo `TGTS`, cuyo
unico consumidor era `Foes`) y `Focus`.

- **`Focus.lua` NO ESTABA EN LA PETICION Y TENIA QUE IRSE.** Llevaba dormido
  desde 2026-08-15 por una sola linea -- `if ns.Targets and ns.Targets.enabled
  then return end` -- asi que borrar `Targets` a secas habria hecho esa
  condicion falsa y **habria resucitado un panel flotante**, justo los que
  `PRUEBAS-10` H1/H2 mando borrar.

  Es el patron de la etapa 5h por sexta vez -- un apano en pie despues de que
  desapareciera aquello para lo que estaba -- pero **por una vez se vio antes
  del sintoma**, y la tecnica que lo caza vale mas que el caso: *antes de borrar
  un modulo, grep de su nombre en todo el addon*. No para arreglar las llamadas,
  que son evidentes, sino para encontrar a quien lo usaba como INTERRUPTOR. Una
  dependencia de "existe" no aparece leyendo el fichero que se borra.

- **EL REPARTO INTERIOR SE FUE CON EL CONTENIDO, y eso es lo unico discutible
  del borrado.** `HERO_W`, `PARTY_W`, `ROLES_H`, `SKILLS_Y`, `FOES_H`... eran
  numeros correctos y probados en juego. Se van igual: son decisiones sobre un
  contenido que ya no existe, y dejarlas puestas habria **predecidido el
  rediseno** -- la sala nueva naceria con un bloque de heroe de 330 y cuatro
  filas de grupo porque estaban ahi, no porque se hubieran elegido. Queda UN
  hueco `hall` sin rejilla: 344 de alto por 710..2758 de ancho segun `grow`.

- **LOS VERBOS DE mod-rts SE QUEDAN, Y ESO NO ES INCOHERENCIA.** `CAST`,
  `SELFCAST`, `PFOCUS`, `ROLE`, `ROLES`, `BARS` y `TGTS` siguen compilados. Un
  verbo sin cliente **no falla en silencio: no corre** -- nadie sondea, asi que
  el servidor no dice nada. Es la diferencia con una funcion escondida con su
  interruptor puesto, que si se arma sola (el `camHold` de la retencion de
  altura). Y son la mitad de servidor de lo que se va a redisenar: borrarlos
  garantizaria repetir el descubrimiento de la etapa 5n -- *la mitad del brief
  ya estaba construida en otro sitio* -- pagando ademas una recompilacion.

- **DIEZ TECLAS LLEVABAN COLGANDO DESDE EL 24 DE AGOSTO.** Al quitar
  `RTSCOMMAND_RELEASE` y `RTSCOMMAND_COMMAND` salio que `Bindings.xml` tenia
  diez `RTSCOMMAND_SLOT1..10` apuntando a `RTSCommand_CommandSlot`, **una global
  que no existe** desde que se borro `CommandMode.lua`. Da un error de Lua al
  pulsarla y solo si el jugador la habia asignado: no lo ve el comprobador, no
  lo ve el cargador, no lo ve nadie. Se comprueba con una linea de shell y
  **debe entrar en `check_addon.py`** -- misma familia que las dos
  comprobaciones que se le anadieron en la etapa 5m.

- **Las SavedVariables de la sala se tiran al cargar** (`skills`, `portrait`,
  `targets`, `targetsOn`, `focus`). Tercera vez que hace falta, despues del
  `grow = 688` y el `camHold`.

**Lo que queda dentro del modo RTS:** camara, raton y sus gestos, seleccion,
rutas, marcadores de suelo, botin, selfbot, `Chrome`, la linea de mensajes,
minimapa, los dos railes y la rejilla de ordenes 4x4.

Y una consecuencia que el rediseno hereda: el consuelo escrito en `LeaveChrome`
-- *"mientras dura el aplazamiento te quedas con la consola, que lleva tu vida y
tu poder"* -- **ya no es cierto**. Esta anotado en `RTSMode.lua`, y es un
argumento a favor de que la sala nueva vuelva a llevar el estado del heroe.

## Revision de arquitectura, 2026-09-02

`rts-project\docs\REVISION-ARQUITECTURA.md`, escrita antes de repensar el centro
de la HUD y con esa pregunta delante. Veredicto: **el contrato de `Bar.lua` esta
listo para colgar la sala nueva; la capa de ABAJO no.** Los tres hallazgos que
bloquean, con sus numeros medidos:

- **`Bridge.lua` es una costura que nadie usa.** Se declara la capa de
  capacidades nativas y expone 8 funciones; **98 lineas de codigo en 8 ficheros
  leen los globales `RTS_*` directamente** (`Markers` 37, `Core` 21, `Channel`
  14, `RTSMode` 12...). La prueba mas limpia es su propia documentacion:
  `GetUnitWorldPosition` devuelve nil diciendo *"not available in the push model
  yet"* mientras **cuatro ficheros parsean la lista de unidades a mano** para
  obtener eso mismo. La costura no esta incompleta: se la rodeo y ahora miente.

  Y la degradacion sin DLL la garantizan sus 8 metodos con
  `if RTS_Ready ~= 1 then return nil end`. Los 98 lectores crudos tienen que
  acordarse cada uno -- que es literalmente lo que costo una sesion entera y
  esta escrito en mayusculas en `RTSMode.lua`.

- **`Camera.lua` es la capa de transporte de todo el proyecto.** `ns.SendServer`
  y la cadena de 12 `message:match` que reparte a `RTSMode`, `Orders`, `Flare`,
  `Route` y `Marks` viven ahi, por historia: la camara fue lo primero que hablo
  con mod-rts. La sala nueva sera el mayor consumidor de verbos del addon, y hoy
  cada verbo significa editar `Camera.lua`.

- **`HasServer()` es una promesa y cada quien se escribe su espera.** Cuatro
  copias del mismo `if servidor o han pasado 2,5 s` (dos vivas en `RTSMode`, dos
  borradas hoy con `Skills` y `Roles`). Documentado ya dos veces, la segunda
  diciendo "y ya van dos". La quinta la escribe la sala nueva.

Los tres se arreglan con el patron que **este addon ya tiene bien hecho dos
veces** -- `Selection:Subscribe` y `Bar:OnLayout`, registros con `pcall` -- asi
que no hay nada que inventar.

Detras van cinco hallazgos menores: `Bar:Panels()` es una lista a mano (la otra
mitad de un contrato que por lo demas es el mejor del addon), `RTSMode.lua` hace
ocho cosas, `Core.lua` es una cadena de 39 ramas mas un orden de arranque
implicito, **34 claves planas de SavedVariables sin version** (cuatro purgas ya:
`grow = 688`, `camHold`, `railCropGen` y la de hoy) y el numero de protocolo del
DLL escrito en dos sitios, uno como literal.

**Dos conclusiones que van contra la intuicion y conviene no perder:**

- **El lado C++ esta MEJOR que el Lua.** `mod_rts.cpp` tiene la misma forma de
  despacho largo, pero delega de verdad: cuatro espacios de nombres en sus
  propios ficheros, y anadir un verbo toca el despacho y UN fichero de dominio.
  La separacion que le falta al addon, el modulo de servidor si la tiene. No
  tocarlo.
- **Hay una lista de lo que NO hay que tocar, y pesa igual que la de hallazgos**
  (§12): el contrato de `Bar`, `Selection:Subscribe`, la regla de capturar y
  devolver, la salida en dos mitades, `sim/` y **los comentarios**. Un refactor
  que se lleve por delante el porque documentado destruye mas valor del que
  crea.

## Los tres primeros arreglos de la revision, 2026-09-02. Addon 0.50.0.

Los §2, §3 y §4 de `REVISION-ARQUITECTURA.md`, que son los que cambian como se
escribe la sala nueva. El §14 de ese documento lleva el detalle. **Nada cambia
de comportamiento salvo un fallo que aparecio por el camino**, y ese si.

- **`Link.lua`: el canal ya no vive en la camara.** `ns.SendServer`, el frame de
  `CHAT_MSG_ADDON`, `serverSeen` y `serverVersion` salen de `Camera.lua`, y los
  doce verbos que repartia se van cada uno a su dueno -- `WHAT` a `RTSMode`,
  `DID` a `Orders`, `POS`/`GROUNDAT`/`GROUNDNO` a `Route`, los cuatro `MARK*` a
  `Marks`. Con ellos se va el `PLAYER_LEAVING_WORLD` de `Marks`, que estaba en
  el frame del canal: el unico fichero donde `Marks` no pinta nada.

  **El reparto es POR VERBO, no por expresion regular**, y eso da lo que la
  cadena de doce regex no podia dar: **decir que llego un verbo que no escucha
  nadie**. Importa justo ahora, porque mod-rts sigue contestando siete verbos de
  la sala borrada que se van a volver a usar.

- **SUSURRARSE A UNO MISMO SIGNIFICA QUE OYES TU PROPIA PETICION DE VUELTA, y
  casi lo pago.** Mi primera version marcaba `serverSeen` con cualquier mensaje
  entrante -- o sea que nuestro propio `VERSION` rebotando lo habria puesto a
  cierto **sin mod-rts instalado**, y `Orders` mandaria por un canal que no
  escucha nadie en vez de caer al respaldo por chat. Silencioso y total.

  Y "casa con un manejador" tampoco vale como prueba: **cuatro verbos se dicen
  igual en los dos sentidos** (`CAM`, `POS`, `WHAT`, `MARKQ`), asi que nuestro
  propio `WHAT <guid>` casa con el manejador de `WHAT`. Lo que los distingue es
  el FORMATO -- que es lo que hacian las regex de antes sin que se notara que
  ese era su segundo trabajo. Cada manejador valida el suyo, y `REPLY_ONLY`
  lista los ocho verbos que nosotros no decimos nunca.

- **`Link:WhenServer(fn)` sustituye cuatro copias del mismo bucle.** Dos vivas y
  dos que se fueron con la sala. Reutiliza los frames -- sin mod-rts, cada
  entrada en modo RTS creaba uno que giraba 2,5 s y se quedaba muerto para
  siempre -- y dice si contesto o si vencio el plazo, que es lo que necesita
  quien tiene respaldo. La guarda de `R.active` del botin **se queda en el
  llamante**: es especifica de ese sitio, no de la espera.

- **`Bar:Register(m)`: los paneles se apuntan solos.** `Bar.lua` ya no nombra a
  ninguno, asi que la sala nueva no tiene que tocar el fichero del arte.

- **Y UN FALLO DE VERDAD, DE ANTES DE ESTA SESION.** `Camera:Create()` acababa
  con `self.frame = f` -- el frame de eventos -- machacando `C.frame`, que **es
  la tabla de encuadre** (`tilt`, `zoom`, `fov`, `shadow`, los dos topes de
  zoom) que ese mismo `Create` acababa de rellenar. En silencio: el CVar del FOV
  se escribia a 0, que significa "no lo toques", asi que **la camara isometrica
  de la etapa 5g no se aplicaba nunca**; los topes de zoom no subian; las
  sombras de la etapa 5o no se ponian.

  **Por que sobrevivio cuatro etapas, que es lo que hay que retener:** con un
  encuadre guardado, `C:Frame()` sale por `SetView(VIEW_SLOT)` antes de usar
  tilt y zoom, asi que la camara se veia bien -- y `C:Report()` cae a `DEFAULTS`
  cuando la tabla no contesta, o sea que **IMPRIMIA los valores correctos
  mientras no aplicaba ninguno**. Un lector que miente en la direccion
  tranquilizadora es peor que no tener lector. Misma forma que `check_addon.py`
  diciendo "los 28 ficheros estan bien" sobre una cadena rota (etapa 5m) y que
  `GetActionInfo` devolviendo otro hechizo en vez de un error (etapa 5o).

  El frame pasa a `self.events`. **Es lo unico que cambia en pantalla y hay que
  mirarlo.**

- **`sim/load_order.py`, nuevo, y es el precio del registro de paneles.** Que un
  panel se apunte solo quita un acoplamiento y crea una dependencia de ORDEN:
  `ns.Bar:Register(P)` corre al CARGAR `Panel.lua`. `check_addon.py` no lo puede
  ver -- mira cada fichero por separado y esto es una pregunta sobre los 24 en
  el orden del `.toc`. Tiene dientes, comprobado moviendo `Panel.lua` delante de
  `Bar.lua`.

  Su trampa fina: **el cuerpo de una funcion no cuenta.** La primera version
  daba cinco falsos positivos, todos dentro de un manejador -- que corre cuando
  llega el mensaje, no al cargar. Un falso positivo aqui seria peor que no tener
  guion: se aprende a ignorarlo.

**Sin ver en juego.** Comprobado desde fuera: `check_addon.py` (24 ficheros),
los cuatro `sim/`, cero referencias colgando, `REPLY_ONLY` sin solapes con lo
que el addon manda, y los cuatro verbos de doble sentido validando formato.

## Stage 7 -- lo del otro desarrollador, 2026-09-03. Construido, no visto todavia.

Addon **0.51.0**, mod-rts **0.19.0** (hay que reiniciar el servidor).
`docs/PRUEBAS-20.txt` es la ronda; el plan de ataque, con las cuatro features
del video de `asd.txt`, esta en `~/.claude/plans/`. Cinco piezas nuevas de
servidor y seis de cliente, y **el hallazgo que mas cambia el plan es que casi
nada de esto necesita playerbots**.

### El cortafuegos, primero de todo

`RtsBotApi.h` + `.cpp` es la UNICA unidad de traduccion de mod-rts que incluye
una cabecera de mod-playerbots. Antes eran ~83 llamadas repartidas entre
`RtsOrders.cpp` y `RtsCommandMode.cpp`, mezcladas con logica nuestra.

- **Era la mitad de caro de lo que decia el borrador**: `RtsCamera.*`,
  `RtsMarks.*`, `mod_rts.cpp` y **las cuatro cabeceras `.h`** ya estaban
  limpios, o sea que ningun consumidor arrastraba playerbots por transitividad.
- `ResolveBot` estaba **duplicado palabra por palabra** en los dos ficheros y
  **no usa playerbots para nada** (`FindPlayerByName` + `Group::IsMember`).
- **La comprobacion mira los `#include`, no los nombres de clase**, y esa
  distincion importa: media docena de comentarios del modulo citan
  `PlayerbotAI.cpp:3066` y compania para explicar por que algo esta escrito como
  esta. Una comprobacion que los contara daria un falso positivo permanente, y a
  una comprobacion que siempre falla se le deja de hacer caso.

### **UN `.cpp` NUEVO NO ENTRA SOLO, Y ESO COSTO UNA COMPILACION ENTERA**

`CollectSourceFiles` corre en el paso de **configure**, no en el de build, asi
que la lista de fuentes vive cacheada en `modules.vcxproj`. Un fichero nuevo
**se compila** (MSBuild lo ve) pero **no se enlaza**, y salen `LNK2019` sobre
cada simbolo suyo -- errores que senalan a los ficheros que LLAMAN, no al que
falta, asi que se leen como *"el cortafuegos esta mal escrito"*.

    cmake C:\Server\build      # ~2 s, reconfigura con la cache que ya hay
    cmake --build C:\Server\build --config Release --target worldserver -- -maxcpucount

Y la comprobacion barata, antes de esperar trece minutos:
`Select-String -Path C:\Server\build\modules\modules.vcxproj -Pattern RtsBags`.

### Lo que las features NO necesitaban

De las cinco piezas de servidor nuevas (`RtsBotApi`, `RtsBags`, `RtsQuests`,
`RtsChain`, `RtsNpc`), **cuatro no tocan playerbots en absoluto**. Solo la
cadena de ataque, y a traves de `AttackBot`, que ya existia.

- **Las bolsas son la secuencia del intercambio del propio nucleo**
  (`TradeHandler.cpp:134,150`): `CanStoreItem` -> `MoveItemFromInventory` ->
  `MoveItemToInventory`. Se copia de ahi y **no de `GiveItemAction` de
  playerbots**, que hace lo mismo con `in_characterInventoryDB = false` -- o sea
  `ITEM_NEW`, "crea la fila". La fila YA existe: `RemoveItem` dice de si mismo,
  en el nucleo, *"does not actually change the item, it only takes the item out
  of storage temporarily"*. Lo correcto es `true`/`ITEM_CHANGED`, que es lo que
  hace cada trade que se ha hecho nunca en un servidor.
- **Y el guardado va en UNA transaccion**, porque el nucleo avisa en ese mismo
  sitio de que `SaveInventoryAndGoldToDB()` *"not have own transaction guards"*
  (`TradeHandler.cpp:577`). Guardar los dos por separado es literalmente la
  ventana en la que se duplica o se pierde un objeto.
- **Las misiones no comprueban distancia, y no es un truco.** Verificado linea a
  linea: `CanTakeQuest` (:252), `CanAddQuest` (:266), `AddQuest` (:520),
  `CanRewardQuest` (:387/:471) y `RewardQuest` (:675) validan estado, nivel,
  reputacion y hueco -- nada mas. La unica puerta es
  `CanInteractWithQuestGiver`, y la llaman **solo los manejadores de opcode**
  (`QuestHandler.cpp:134,270,368,492`), comentada por el nucleo como *"some kind
  of WPE protection"*: es una defensa contra un CLIENTE que miente sobre donde
  esta. Y **mod-playerbots ya lo explota igual** -- `QuestAction.cpp:244-248`
  cae a `bot->AddQuest(quest, pObject)` directo.

### **"INTERACTUAR COMO EL BOT" NO ERA EL CAMINO CARO, Y CASI SE DESCARTA POR NO MIRAR**

El borrador del plan lo daba por imposible sin reescribir el cliente, con el
argumento de que *"esas ventanas las abre el cliente cuando el servidor le habla
a TU personaje"*. La primera mitad es cierta. La conclusion **no**, y se cae
abriendo `Trainer.h`:

    trainer->GetSpells()                  // la lista entera
    trainer->CanTeachSpell(bot, &spell)   // PARA EL BOT
    trainer->TeachSpell(npc, bot, id)     // le cobra y se lo ensena

Publicas, tomando un `Player*` cualquiera. Lo unico que anade
`WorldSession::SendTrainerList` es EMPAQUETARLO hacia su propia sesion, y esa
parte no hace falta porque la lista la dibujamos nosotros. Sin falsificar un
paquete, sin tocar `ServerScript::CanPacketReceive`, sin acercarse al ERROR
#134. Igual el vendedor (`BuyItemFromVendorSlot`) y la reparacion
(`DurabilityRepairAll`).

**Y la misma leccion se cobro otra vez, dos horas despues y en el mismo
fichero:** la exploracion previa listo `GetSpellState` como publica, no lo
comprobe, y **esta debajo del `private:`**. Una compilacion entera. Los tres
estados salen de lo que si es publico (`HasSpell` / `CanTeachSpell` / ninguna) y
salen **mejor**, porque `CanTeachSpell` es el estado mas el hueco de profesion
primaria -- que es la pregunta que hace el boton.

O sea: **el error no fue creer a internet, fue creer al informe de una
busqueda.** Misma familia que `nameplateMaxDistance` y `gxWindowedResolution`.

### El cliente: seis ficheros y un concepto nuevo

`Window.lua` (la ventana flotante compartida), `Bags`, `Quests`, `Skills`,
`Chain`, `Npc`.

- **`Window.lua` existe para que las tres ventanas no diverjan.** El nombre del
  frame **tiene** que empezar por `RTS` -- `ns.IsOurs` es lo unico que deja
  pasar un tooltip con el cromo escondido (etapa 5o) -- asi que si no empieza
  asi se corrige y se avisa, en vez de dejar una ventana entera sin tooltips
  cuyo sintoma aparece tres ficheros mas alla.
- **Y un fallo mio, cazado antes de compilar:** guardaba el sitio leyendo
  `GetPoint()` y restaurandolo como ancla CENTER. `StartMoving` **no promete
  conservar el ancla**, asi que la ventana habria aparecido desplazada al
  siguiente arranque, sin error. Ahora se normaliza el centro a mano y el
  "¿se salio de la pantalla?" se mide sobre el rectangulo de verdad, no sobre el
  desplazamiento guardado -- que es la cuenta que se equivoca en cuanto las
  escalas del frame y de `UIParent` no coinciden, y aqui nunca coinciden.
- **EL PRIMARIO, que es de quien son las habilidades, YA NO ES LA SELECCION.**
  Del video: *"if we hit tab, we get the command bar for the next person WITHOUT
  DESELECTING"*. Son dos conceptos y aqui habia uno solo, asi que ver las
  habilidades del mago obligaba a dejar de mandar sobre el grupo. Regla de
  coherencia: seleccionar a UNO le hace primario; seleccionar a VARIOS no lo
  toca.
- **`Skills.lua` NO DIBUJA NADA, y eso es la decision.** La sala se vacio para
  redisenarla; poner ahi seis botones ahora la predecidiria -- naceria con seis
  huecos de tal tamano porque estaban puestos. Viven los DATOS y las ACCIONES
  (`Slots()`, `Use(i)`, `Subscribe`), y se usa con teclas hasta que la sala se
  decida.
- **`bit.band` NO se usa, a proposito.** Existe en 3.3.5a, pero no lo usaba ni
  un fichero de este addon, y las banderas son potencias de dos: `W:Flag` es
  aritmetica y no puede fallar. Cuatro lineas contra una comprobacion pendiente
  cuyo modo de fallo seria "las banderas nunca estan puestas" -- un objeto
  vinculado que se deja coger.
- **`GetItemInfo` devuelve nil y no da error** para un objeto que el cliente no
  ha visto nunca, o sea casi todo lo que hay en la bolsa de un bot. Se cierra
  por los dos lados: el servidor manda cantidad y calidad (una casilla sin cache
  sale como cuadro de color con su numero, no como hueco), y se pide la cache
  con un `GameTooltip` invisible PROPIO -- no el compartido, que es el que esta
  dibujando el tooltip de verdad.
- **El refresco es "vuelve a preguntar".** Tras mover un objeto o aceptar una
  mision, el servidor dice que salio bien y el cliente vuelve a pedir. Aplicar
  el cambio por su cuenta seria simular el almacenamiento del nucleo (pilas que
  se juntan, el hueco que elige `CanStoreItem`) o la cadena de misiones, y en
  cuanto esa simulacion falla una vez la ventana ensena algo que no existe.

### El canal: dos verbos mas de doble sentido, y cada uno con su discriminante

`BAGS` se distingue por el NUMERO DE CAMPOS (peticion `BAGS <nombre>`,
respuesta `BAGS <nombre> <trozo>`); `NPCQ` por una LETRA DE TIPO;
`TRAINER`/`VENDOR` porque el segundo campo de la respuesta lleva comas y el de
la peticion es un guid en hex. **Cada verbo nuevo de doble sentido tiene que
traer el suyo escrito**, porque el generico -- "casa con un manejador" -- vale
para los dos sentidos por construccion. Comprobado que `REPLY_ONLY` no se solapa
con nada de lo que el addon manda.

**El titulo de una mision va SIEMPRE el ultimo de su linea**, y por eso las
recompensas a elegir se metieron DELANTE al anadirlas. Un titulo lleva espacios
y comas; cualquier separador detras acaba apareciendo dentro de un titulo algun
dia, y eso no da error: parte la linea en dos y deja media mision perdida.

### `check_addon.py` mira ya `Bindings.xml`

El §10 de la revision de arquitectura, que costaba quince minutos y ya habia
cazado uno. Comprueba que toda global que llame una tecla exista en algun `.lua`.
**Probado rompiendolo a proposito** antes de darlo por bueno.

### Lo que NO se hizo, y por que

- **El ayudante de misiones** (a donde ir): fuera por decision del jugador.
- **El menu de conversacion siendo el bot**: sigue abierto.
  `PrepareGossipMenu`/`SendPreparedGossip` mandan a la sesion del propio
  `Player`, y la de un bot no va a ninguna parte; **elegir** una opcion entra en
  `creature->AI()->sGossipSelect`, y esos scripts suponen que quien habla es el
  jugador de verdad. Con tope de media sesion si se retoma.
- **Partir pilas al pasar objetos.** Solo pilas enteras: partir es `SplitItem`,
  otra maquina entera, y de las dos formas de equivocarse ahi **una duplica
  objetos**.

## Dibujar en el suelo, 2026-09-03

`docs/SUELO-INFORME.md`. Dos respuestas que conviene no volver a buscar:

- **Los waypoints YA se dibujan en el mundo**, no en la capa de interfaz:
  `Route.lua:852` los sincroniza a `Marks`, que pide un `DynamicObject` por
  punto. Lo que sigue en la capa es solo la LINEA que los une, y mudarla serian
  ~60 objetos por ruta contra 4. **No compensa**, y esta escrito para no volver
  a plantearlo.
- **Para el anillo de seleccion hay tres caminos nuevos**, y el mejor es una
  **criatura invisible con el modelo cambiado siguiendo a la unidad**: es la
  jugada que ya hace la camara RTS, no toca la base de datos del mundo, da
  color y tamano libres, y **el cliente la interpola solo** -- que es donde han
  muerto los intentos anteriores. Medio dia, solo mod-rts.

Pero antes hay **una prueba de cinco minutos** que decide si eso hace falta:
¿sigue un `DynamicObject` cuando el servidor lo reubica? Hereda de
`MovableMapObject`, asi que el servidor puede; lo que no se sabe es si el
cliente lo redibuja. Si sigue, el anillo nuevo son dos horas y **572 estilos ya
navegables** con `/rts mark`. Es la leccion de la etapa 5e otra vez: una lectura
estatica convincente vale UNA prueba barata en juego, no dos compilaciones de
maquinaria encima.

## Stage 7b -- lo que dijo la ronda 20, 2026-09-03. Construido, no visto todavia.

Addon **0.52.0**, mod-rts **0.20.0**. `docs/PRUEBAS-21.txt` es la ronda. Cuatro
bugs con causa encontrada, una correccion de rumbo grande y cuatro mejoras.

### Los cuatro bugs, y tres son de la misma familia

- **EL FOV NO SE APLICABA, Y NO ERA LO QUE LA 0.50.0 ARREGLO.** `C.frame` se
  declara con `tilt`, `zoom`, `shadow` y los dos topes -- y **sin `fov`**.
  `C.DEFAULTS.fov = 60` nunca se copiaba, asi que `cfg.fov` era nil y el CVar
  prestado se escribia a 0, que significa literalmente *"no toques el FOV"*. El
  DLL lo respetaba al pie de la letra.

  La 0.50.0 arreglo que `Camera:Create()` machacara esa tabla entera y su
  informe dijo *"el FOV deberia aplicarse ahora"*. **Era necesario y no
  suficiente**, y lo dije como si lo fuera. La clave nunca estuvo en la tabla.

- **Y EL LECTOR MENTIA POR PARTIDA DOBLE.** `C:Report()` leia
  `tonumber(f.fov) or tonumber(d.fov)`, o sea que **imprimia 60 mientras se
  escribia 0**. Al perseguirlo aparecio ademas que su `format` llevaba **cinco
  huecos y seis argumentos**: imprimia el FOV bajo la etiqueta `pitch` y tiraba
  el pitch. `format` en Lua no se queja de argumentos de mas.

  El comentario de esa misma funcion dice *"a readout that can fail quietly is
  worse than none"*. Lo decia sobre si misma sin saberlo. **Tercera vez en ese
  fichero.** Ahora `Frame()` vuelve a LEER los CVars tras escribirlos y
  `/rts cam` imprime lo que el cliente se quedo -- porque `SetCVar` sobre algo
  recortado o inexistente no da error, y sin eso "el zoom no llega" es un
  sintoma sin numero detras.

- **LA BARRA PROPIA NO SE PEDIA NUNCA.** `Skills` solo pedia la barra al
  CAMBIAR de primario, y al arrancar no ha cambiado nada. Lo que vale de este
  es el mensaje: decia *"un bot sin barra guardada"* cuando el primario era el
  JUGADOR. **Un diagnostico que nombra la causa equivocada cuesta mas que uno
  que calla**, porque manda a mirar al sitio que no es.

- **NARANJAS QUE NO SE PODIAN COGER.** El estado "puede cogerla" se calculaba
  mirando solo al personaje (`CanTakeQuest` responde *"¿podria en algun
  sitio?"*), sin mirar si **ese** PNJ la da. Una mision que el PNJ solo RECIBE
  salia naranja y el boton de aceptar no aparecia -- con razon. El punto tenia
  razon sobre el personaje y mentia sobre el PNJ, que es la peor combinacion:
  parece un boton roto en vez de una mision que no es de ahi.

- **TU PERSONAJE VOLVIA AL ORIGEN DESPUES DE "QUIETO".** El selfbot le engancha
  IA de playerbots a tu propio personaje, asi que el `stay` que mandas al grupo
  **tambien le llega**: se ancla, `SELFMOVE` le lleva al destino y su estrategia
  le trae de vuelta. Las dos ordenes correctas peleandose -- por eso el sintoma
  era "va y vuelve" y no "no se mueve". `MoveBot` ya soltaba el ancla; `MoveSelf`
  no, porque tu personaje no pasa por `MoveBot` (`ResolveBot` rechaza a
  proposito que te ordenes a ti mismo por esa via). **Patron de la etapa 5h:
  dos caminos para la misma cosa y el arreglo aplicado a uno solo.**

### La correccion de rumbo: jugar como un compañero

*"Controlar al bot se refiere a poner la camara a ese bot y controlarlo como si
estuvieramos en modo de juego normal"*. La seccion D de la ronda 20 estaba
entera mal enfocada.

- **LA MAQUINARIA LLEVABA UN ANO ESCRITA SIN LLAMANTE Y ESTA VEZ SALIO A
  CUENTA.** `rts::orders::PossessBot` existe desde la etapa 6 -- es
  `SetCharmedBy(CHARM_TYPE_POSSESS)`, la misma llamada de la camara RTS apuntada
  a un `Player`. El primer plano se descarto el 2026-08-16 y se dejo la
  maquinaria. **Es la unica vez que dejar codigo sin llamante ha salido bien en
  este proyecto, y salio bien porque estaba DOCUMENTADO por que se dejaba** --
  no escondido detras de un interruptor, que es el caso que cuesta caro.

- **POSEER A UN `Player` DA UNA BARRA VACIA.** `CharmInfo::InitPossessCreateSpells`
  (CharmInfo.cpp:79) rellena desde `m_spells` de la CRIATURA y para cualquier
  otra cosa hace `InitEmptyActionBar()`. Sin rellenarla a mano tomas el mando
  del mago y te mueves sin un solo hechizo. Se llena con la barra guardada del
  bot -- la misma fuente que la fila de habilidades -- y hay que volver a llamar
  a `PossessSpellInitialize()`, porque `SetCharmedBy` ya mando la vacia.

- **Y EL COMENTARIO QUE PREDIJO ESTE DIA SE CUMPLIO.** `PossessBot` ponia
  `+passive` a ciegas y `ReleaseBot` lo quitaba a ciegas, con una nota que
  decia: *"se deja asi A PROPOSITO porque POSSESS no lo manda nadie; si vuelve a
  usarse, la version correcta esta escrita en `Suppress`"*. Volvio a usarse y se
  hizo lo que la nota mandaba. **Una deuda documentada con su cura escrita al
  lado se paga en diez minutos; sin la nota habria sido otro fallo de "le quito
  el rol al soltarlo".**

- **LO QUE LA POSESION NO DA, Y ESTA DICHO POR DELANTE:** cambia quien te MUEVE,
  no quien ERES. Los manejadores de interaccion del nucleo trabajan sobre
  `_player`, no sobre `m_mover`, asi que hablar, comprar, entrenar y lootear
  siguen yendo por TU personaje -- que esta parado en otro sitio y falla por
  distancia. Moverse, pelear y lanzar SI van por el mover. Para la otra mitad
  estan `/rts npc` y `/rts quests`, y por eso no se borraron. La unica forma de
  tener las dos es el cambio de personaje de sesion sin pantalla de carga, que
  es un modulo entero.

### Las cuatro mejoras

- **LAS CASILLAS DE BOLSA ERAN MAS GRANDES QUE UN BOTON DE ACCION.** 74 px
  contra 62, porque se copio el numero del boton de bolsa de los railes sin
  notar que esta ventana lleva la escala de pixel de la HUD -- donde **1 unidad
  es 1 pixel fisico**. Ahora 40, que es lo que mide una casilla de mochila del
  cliente. Misma regla que hizo que el alto de la barra se calcara de
  `ActionButton1` en la etapa 5i: la medida buena es la que el jugador ya tiene
  calibrada en la retina.

- **Y EL SCROLL POR PERSONAJE TIENE QUE SER UN `ScrollFrame`.** En 3.3.5a **un
  frame hijo NO se recorta contra su padre** -- escrito desde la etapa 5k, donde
  el minimapa se habria comido el borde del arte por lo mismo. Un panel con las
  casillas desplazadas hacia arriba las ensenaria igual, por encima de la
  cabecera. `ScrollFrame` es el unico tipo que recorta.

- **LAS MISIONES SIGUEN AL HEROE SOLAS**, y las dos mitades no se hacen igual a
  proposito: **aceptar** es reversible y se hace en el acto (`QUEST_ACCEPTED`);
  **entregar** da objetos que no se devuelven, asi que se hace al CERRAR la
  conversacion y solo de lo que este listo. En 3.3.5a **no hay `GetQuestID()`**:
  el id sale del enlace del registro (`GetQuestLink` -> `quest:1234`), y si
  vuelve nil no se manda nada -- mejor que mandar un id inventado.

- **Y EL BOT ELIGE SU RECOMPENSA.** `AUTO_REWARD` (255, porque 0 es un indice
  valido) hace que el servidor elija POR CADA UNO: lo que pueda usar
  (`CanUseItem`), entre esas la de mayor nivel de objeto, y si ninguna le vale
  la de mas valor de venta. Es lo que hace posible entregar en automatico una
  mision con eleccion -- sin esto la unica opcion segura era saltarselas, porque
  elegir el mismo objeto para cuatro clases es acertar en una y regalar basura a
  tres.

  **No se usa `ItemUsageValue` de playerbots aunque puntue mejor**: seria la
  unica llamada suya en ese fichero, y la regla del plan es preferir el nucleo
  siempre que haya eleccion.

- **"HUIR" SE FUE Y EN SU SITIO HAY "RESET".** Las estrategias de playerbots son
  pegajosas -- se guardan con el bot y sobreviven al relogueo -- asi que un rol
  puesto hace tres sesiones sigue puesto y **no hay nada en pantalla que lo
  diga**. Sin un boton de "olvida todo", la salida era adivinar cual de las diez
  estaba de mas. `flee` era el candidato a sustituir porque romper el combate ya
  se consigue con "Quieto", y un grupo que huye a la vez se dispersa.

- **TAB PARA CICLAR EL PRIMARIO: BORRADO**, a peticion. El "no puedo volver
  atras" tenia arreglo -- en WoW, TAB y SHIFT-TAB son dos asignaciones
  distintas, asi que `IsShiftKeyDown()` dentro de la de TAB no se cumple nunca
  -- pero el gesto entero sobra si se pincha el retrato. **El CONCEPTO de
  primario se queda**: es lo que decide de quien es la barra.

### Y la de siempre, por tercera vez en dos dias

El shell se comio los **backticks** de dos comentarios al escribirlos con
`python -c "..."`, dejando frases con huecos. Es la misma familia que las barras
invertidas de la etapa 5m. **Regla practica, ya sin excusa: para texto con
comillas invertidas o escapes, fichero y editor -- nunca una cadena entre
comillas dobles del shell.**

## El swap nativo existe, pero el login lo pulsas tu. 2026-09-03

Addon **0.56.0**, mod-rts **0.22.0** (hay que reiniciar el servidor).

`RtsSwap` nacio como sonda, y su cabecera decia lo que habia que averiguar: *"que
[el cliente] acepte un `SMSG_LOGIN_VERIFY_WORLD` estando [en la pantalla de
seleccion] -- sin que nadie pulse nada -- es comportamiento del cliente, no del
servidor, y no hay forma de saberlo sin probarlo"*.

**Probado. No lo acepta, y lo que es peor, no lo ignora: se lleva el cliente por
delante con un ERROR #132.** La sonda hizo exactamente su trabajo -- costo una
tarde en vez de una semana -- y ademas dejo un volcado con el que la causa se
puede cerrar entera. Merece estar escrita porque **el sintoma no apunta a la
causa por ningun lado**: el jugador ve la pantalla de seleccion de personaje y un
fallo dentro de `Wow.exe`, sin una sola linea de nada nuestro en la pila.

### La cadena, verificada contra ESTE `Wow.exe`, no deducida

| paso | evidencia |
|---|---|
| `LogoutPlayer(true)` manda `SMSG_LOGOUT_COMPLETE` | `RtsSwap.cpp`, fase `WAIT_BOT_OUT` |
| el cliente se va a la pantalla de seleccion y **cambia su tabla de eventos** | `0x004DA757`: `push 0x29` (**41 eventos**) contra `0x0052AB25`: `push 0x2D2` (**722**), los dos a `FrameScript_RegisterEvents` en `0x0081B5F0` |
| ~300 ms despues llega la rafaga de login que pidio `StartLogin` | el retraso es la consulta asincrona de `DelayQueryHolder` |
| el manejador de `SMSG_MOTD` (`0x00551660`, comprueba `opcode == 0x33D`) dispara el evento **492** | `push 0; push 0x1EC; call 0x0081B530` en `0x00551706` |
| `FrameScript_SignalEvent` (`0x0081AC90`) **no comprueba el rango** -- solo que la tabla no sea nula -- y lee 1.800 bytes mas alla de un array de 41 | `mov ecx, [eax + ecx*4]` sin comparar contra `[0xD3F7D4]`, que es la cuenta |
| el puntero basura va a `lua_pushstring` (`0x0084E350`), que se rompe en su strlen inline | crash en `0x0084E380` = `mov cl, byte ptr [eax]`, leyendo `0x0C4A8B0E`, que es el segundo argumento en la pila |

La prueba de que la pila es esa y no otra: el volcado de memoria del informe trae
el texto del MOTD (`|cffFF4A2DThis server runs on AzerothCore|r ...`) justo en
`ebp-0x64` del marco del manejador. No es una reconstruccion, es el buffer.

### Lo que queda, y por que sigue mereciendo la pena

**El login lo pulsa el jugador en la lista de personajes.** Con eso el cliente
entra por su cuenta, instala su tabla de 722, y el login es uno normal y
corriente. Lo que sigue haciendo el servidor son las dos partes que **a mano no
se pueden hacer en el orden correcto**:

- sacar del mundo al personaje de destino si estaba de bot, **antes** del logout
  -- dos sesiones no pueden tener el mismo personaje, y el login fallaria con un
  `duplicate character` que no dice nada;
- meter de bot al que dejas, **despues** del login -- `AddPlayerBot` necesita un
  maestro en el mundo, y durante el cambio no hay ninguno.

O sea que el swap nativo existe: pantalla de carga y un click a cambio de que el
orden lo lleve el servidor. `/rts swap <nombre>` o el click izquierdo de
"Control"; el derecho sigue siendo la posesion.

### Tres cosas que retener

- **NO ES COSA DEL MOTD.** El `SignalEvent` se dispara pase lo que pase -- la
  llamada esta detras del bucle, no dentro, asi que un MOTD vacio tambien lo
  dispara -- y la rafaga de login trae muchos eventos mas. **Cualquier evento del
  mundo en esa ventana hace lo mismo.** Vaciar el MOTD habria "arreglado" la
  primera prueba y dejado el fallo para la siguiente, que es la peor forma de
  arreglar algo.
- **El cliente solo instala la tabla de 722 cuando entra EL.** Un login que
  empieza en el servidor aterriza siempre en la de 41. El unico camino hacia el
  cambio SIN pantalla de carga es que `rts_core` haga que el cliente mande su
  propio `CMSG_PLAYER_LOGIN` desde esa pantalla. Sin explorar, y ya no bloquea
  nada.
- **La espera pasa de 20 s a 120.** Ya no se espera a una consulta de base de
  datos sino A UNA PERSONA: lista, click, carga, mundo. Vencer significa que el
  heroe que dejas NO vuelve de bot -- el peor final posible, porque el cambio se
  ve completo y falta la mitad. Y el aviso de "entra con X" va **antes** del
  logout: detras no hay `Player` ni ventana de chat donde escribirlo.

### Y una carencia del servidor que salio de paso

`WorldSession::KickPlayer` avisa con `LOG_INFO("network.kick", ...)`, pero
`worldserver.conf` no declara `Logger.network`, asi que hereda `Logger.root=2`
(solo errores) y **una desconexion forzada no deja ni una linea**. Si vuelve a
pasar algo asi, `Logger.network=4,Console Server` es la diferencia entre saber
quien te echo y adivinarlo.

## El grupo sobrevive al cambio, y el ABORT que salio por el camino. 2026-09-03

mod-rts **0.23.0** (hay que reiniciar el servidor). El addon no cambia.

### El grupo: no se conserva, se REHACE, y tenia que ser asi

*"Quiero poder hacer el login nativo a otro personaje y que se mantenga mi
grupo."* La version anterior metia de bot **solo al heroe que dejabas**, asi que
entrabas con el compañero y te encontrabas solo con uno.

No es que faltara un bucle: es que **al salir tu del mundo, mod-playerbots saca a
TODOS tus bots** y el grupo se deshace con ellos. No hay nada que "mantener" al
otro lado del logout; hay que fotografiarlo antes y reconstruirlo despues.

- **La foto se hace en `To()`**, que es el ultimo instante en que el grupo
  existe, y guarda **GUIDs, no punteros**: entre la captura y el reintento hay un
  logout, un login y varias vueltas del mundo, y cada `Player*` de esa lista deja
  de existir por el camino.
- **El heroe que dejas va DENTRO de la lista y el primero.** Antes tenia su
  propio camino -- una llamada suelta a `bots::Add` -- y dos caminos para meter
  de bot es como se acaba arreglando la mitad de un fallo.
- **Es un REINTENTO por vuelta, no una espera.** `AddPlayerBot` es asincrono y
  los bots que salieron con tu logout **no vuelven todos a la vez**: mientras uno
  sigue saliendo del mundo su `Add` se descarta en silencio, y un solo intento
  dejaria un grupo a medias sin decir nada. Se puede llamar cada vuelta porque es
  **idempotente** -- se planta si el guid ya esta cargando (`botLoading`) o si el
  bot ya esta en el mundo, `PlayerbotMgr.cpp:87-93`. Eso esta leido, no supuesto,
  y es lo que hace que no haga falta llevar la cuenta de quien va por donde.
- **Al agotarse el plazo se dice CUANTOS faltan**, no "hubo un problema". El
  jugador tiene la lista delante y puede meterlos a mano; lo que no puede es
  adivinar cuantos deberia haber.
- Requisitos que ya estaban puestos y conviene no perder: `AllowAccountBots = 1`
  y `MaxAddedBots = 40` en `playerbots.conf`. Sin el primero, `AddPlayerBot`
  rechaza a tus propios alts.

### Y EL ABORT: la posesion sin aura MATA EL WORLDSERVER

Salio en la misma sesion, con volcado
(`Crashes/unknown_worldserver.exe_[3-9_14-52-52]`):

```
Player Neferite (0x3ff) is not able to uncharm unit (0x401)
Charmed unit has charmer 0x3ff
>> ABORTED   Player.cpp:9556   Player::StopCastingCharm
```

`PossessBot` hace `SetCharmedBy(master, CHARM_TYPE_POSSESS)` **a pelo, sin aura**.
`Player::RemoveFromWorld` llama a `StopCastingCharm`, que deshace un charm
**quitando sus auras** -- y aqui no hay ninguna que quitar. El charm sigue
puesto, cae en el `LOG_FATAL`, ve que el charmado tiene charmer, y hace
`ABORT()`.

**Es EXACTAMENTE el mismo fallo que tuvo la camara**, y estaba escrito en
mayusculas en `mod_rts.cpp`: *"back when the camera was possessed with a bare
SetCharmedBy that Player::StopCastingCharm could not unwind and answered with
ABORT(). That is fixed at the root now -- the camera is a Puppet"*. `PossessBot`
lo reintrodujo entero. **La nota estaba en el fichero donde se anadio el gancho
de logout al que le faltaba la llamada**, doce lineas mas arriba.

La salida de la camara no vale aqui: un Puppet es una criatura invocada y esto es
un `Player` que ya existe. Asi que se suelta por el camino bueno --
`RemoveCharmedBy`, que es lo que `SetCharmedBy` sabe deshacer -- antes de que el
nucleo llegue a `RemoveFromWorld`:

- `OnPlayerLogout` (corre en `WorldSession.cpp:851`, `RemoveFromWorld` en la 866)
  y `OnPlayerBeforeTeleport` (el cambio de mapa pasa por el mismo sitio).
- `ReleaseAnyPossession` mira **`GetCharmGUID()` y no el grupo**: un bot que se
  fue del grupo mientras lo llevabas seguiria charmado y no apareceria en el
  recorrido. Y solo actua si el charm es un `Player`, para no pisarle la camara a
  `camera::Abandon`.
- `PossessBot` ademas se niega si ya estas charmando algo. `Unit::SetCharm` avisa
  y **sigue adelante pisando el anterior**, o sea que el primero -- que puede ser
  la criatura de la camara -- se quedaria charmado para siempre.

**Queda un camino sin cubrir y esta dicho por delante:**
`Player::ActivateTaxiPathTo` (`Player.cpp:10481`) tambien llama a
`StopCastingCharm` y no tiene gancho. Hoy es inalcanzable -- mientras posees,
hablar con un maestro de vuelo va por TU personaje, que esta parado en otro sitio
-- pero si algun dia se puede interactuar siendo el bot, esa puerta se abre. La
cura de raiz seria que la posesion llevara un aura de verdad
(`SPELL_AURA_MOD_POSSESS`), que es lo que `StopCastingCharm` sabe quitar.

## Por que el cambio de personaje NO puede evitar la carga. 2026-09-03

La pregunta era: *"¿se podrian cargar los 5 personajes del grupo y hacer como un
pseudo login que no acabe de finalizarse, y luego al hacer swap completar el
proceso para ese personaje? Dejarlos entre bambalinas, cargar sus tablas y no
usarlas hasta que hagan falta."*

Es la pregunta correcta y ataca el sitio correcto. Contestada con el
desensamblado del cliente, no con opiniones. **Tres hallazgos, y los dos primeros
son buenas noticias que hacen la idea innecesaria antes de que el tercero la
haga imposible.**

### 1. Los personajes YA estan cargados. No hay nada que precargar.

Los cinco del grupo son playerbots: `Player` de verdad, en el mundo, con sus
hechizos, bolsas, barras de accion, talentos y misiones. Eso ES "entre
bambalinas con las tablas cargadas". La carga de base de datos nunca fue el
coste, asi que un pseudo-login no ahorra nada.

### 2. El servidor YA sabe hacer el cambio sin tocar la base de datos.

`HandlePlayerLoginOpcode` (`CharacterHandler.cpp:777-782`, la rama que anadio
mod-playerbots) hace exactamente lo que pedia la idea:

```cpp
sess->SetPlayer(nullptr);
SetPlayer(p);            // p ya esta en el mundo, de bot
p->SetSession(this);
HandlePlayerLoginToCharInWorld(p);
```

Coge un `Player` que ya existe y lo mete en tu sesion. Cero consultas, cero
carga. **La mitad de servidor de la idea esta escrita y probada.**

### 3. Y EL CLIENTE IGNORA EL PAQUETE. Ahi se acaba.

`SMSG_LOGIN_VERIFY_WORLD` (0x236) es lo primero que manda
`HandlePlayerLoginToCharInWorld`, y es el paquete con el que el servidor dice
"entra en el mundo". Su manejador en el cliente es **`0x00403DE0`**, y lo primero
que hace despues de leer los cinco campos es:

```
00403E2C  call 0x4D37E0        ; mapa en el que estoy ahora
00403E31  mov ecx, [ebp-4]     ; mapa que trae el paquete
00403E34  cmp ecx, eax
00403E37  je  0x403EAB         ; -> mov eax,1 ; ret     <-- NO HACE NADA
...                            ; si no: guarda la posicion y arranca la carga
00403EA3  call 0x403B70        ;      del mundo (0x403B70)
```

**Si ya estas en ese mapa, el paquete se descarta.** No falla, no avisa: no hace
nada. Asi que "completar el login estando dentro" no tiene por donde entrar --
lo rechaza el propio cliente, y encima en silencio, que es la firma de fallo que
este proyecto lleva persiguiendo desde la etapa 5i.

Y trae una asimetria fea de regalo: **si el personaje de destino esta en OTRO
mapa, si arranca una carga de mundo.** O sea que el mismo gesto haria cosas
distintas segun donde estuviera el compañero. Una funcion que a veces funciona
segun la zona es peor que una que siempre pide lo mismo.

### 4. Y aunque eso se saltara, faltaria lo de "quien soy"

El cliente guarda su guid activo en el gestor de objetos (`ObjMgr + 0xC0`) y de
ahi cuelga todo lo demas: barras de accion, libro de hechizos, bolsas, talentos,
misiones, reputaciones, logros. Todo eso lo rellena la rafaga de login paquete a
paquete. **En 3.3.5a no hay ningun paquete que diga "ahora eres otro"**; lo mas
parecido es la rafaga entera, y su primera pieza es justo la que se ignora
estando dentro.

### Conclusion, y lo que si queda

**SUPERADO ESA MISMA TARDE -- ver la seccion siguiente.** Lo que decia este apartado, *"con el cliente 3.3.5a sin parchear la pantalla de carga no se puede evitar"*, era una conclusion de mas: los hallazgos 1-3 son correctos y el 4 estaba mal. El cliente SI se re-identifica dentro del mundo, con un `SMSG_UPDATE_OBJECT` marcado `UPDATEFLAG_SELF`, y la pantalla de seleccion se evita escondiendole el `SMSG_LOGOUT_COMPLETE`.
Lo que si puede caer es el paso ANTERIOR: hoy el cambio es *lista de personajes
+ carga*, y si el cliente acepta una carga de mundo forzada podria quedarse en
*solo carga*. Eso es trabajo de `rts_core` y es una PRUEBA, no una certeza. No
bloquea nada: el swap ya funciona.

**Y una nota sobre la referencia.** Lo que el video de Yafravan enseñaba, segun
lo que quedo escrito al abrir la etapa 6, es *"seamless bot possession and RTS
orders on a **custom core**"* -- posesion, no cambio de personaje. Un core
custom ademas puede llevar cliente parcheado, y entonces nada de lo de arriba
aplica. Merece la pena mirar el video otra vez antes de dar por hecho que lo que
se vio era esto.

## El cambio de personaje SIN pantalla de seleccion, 2026-09-03 (tarde)

mod-rts **0.24.0**, addon **0.57.0**. Hay que reiniciar el servidor. Construido,
no visto todavia.

Por la manana quedo escrito que *"el cliente solo instala su tabla del mundo
cuando entra EL"* y que la pantalla de seleccion era inevitable. **Las dos cosas
eran falsas, y la segunda se cayo mirando una instruccion mas.** Vale la pena
dejar por que, porque el error de razonamiento es el que este documento lleva
seis etapas describiendo: *"si A falla en la situacion X, A no se puede hacer"*,
cuando lo cierto era *"A falla EN X"*.

### El diagnostico de la manana era correcto y la conclusion no

El ERROR #132 pasaba porque `LogoutPlayer(true)` manda `SMSG_LOGOUT_COMPLETE`,
**el cliente se va a la pantalla de seleccion y ahi cambia su tabla de eventos**
de 722 entradas a 41 -- y la rafaga de login que llegaba detras disparaba el
evento 492, fuera de rango. Todo eso sigue siendo verdad.

Lo que no se siguio es la pregunta obvia: **¿y si el cliente NO se va a esa
pantalla?** Dentro del mundo la tabla buena esta puesta, el 492 esta en rango, y
no pasa nada. La rafaga de login nunca fue el problema; el problema era donde
aterrizaba.

### Las dos piezas, las dos verificadas

**Una: el cliente cambia de identidad con un paquete corriente.** Parecia lo
imposible -- *"en 3.3.5a no hay ningun paquete que diga ahora eres otro"*, escrito
esta misma manana. Lo hay, y es el de siempre. Desensamblado el manejador de
creacion de objeto del cliente (`0x004D6C00`):

```
004D6CC8  test byte ptr [ebp-0x44], 1     ; UPDATEFLAG_SELF, que vale 0x0001
004D6CCC  je   0x4D6CF6
004D6CCE..CDE                             ; objmgr, por la cadena de TLS
004D6CE7  mov  [objmgr + 0xC0], guid.lo   ; <-- "yo soy este"
004D6CF0  mov  [objmgr + 0xC4], guid.hi
```

Sin ninguna otra condicion: **el cliente adopta como suyo cualquier objeto que
llegue con `UPDATEFLAG_SELF`**, este en el mundo o donde sea. No comprueba si ya
tenia uno. Y del lado del servidor ese flag se pone solo -- `Object.cpp:187`,
`if (target == this) flags |= UPDATEFLAG_SELF` -- cuando `Map::SendInitSelf`
construye el paquete, que es una de las llamadas que ya hace
`HandlePlayerLoginFromDB`. **La rafaga de login siempre supo hacerlo.**

**Dos: el `SMSG_LOGOUT_COMPLETE` se puede esconder sin tocar el nucleo.**
`WorldSession::SendPacket` pregunta a `sScriptMgr->CanPacketSend` por cada
paquete que sale (`WorldSession.cpp:356`). Un `ServerScript` en el modulo
descarta ese paquete **y solo ese, y solo durante la llamada a `LogoutPlayer` del
cambio**: la bandera se pone la linea de antes y se quita la de despues. Un
filtro con su propia idea de cuando actuar es un filtro que algun dia se traga el
logout de alguien que si queria salir.

### El pseudo-login precargado, que es idea del jugador y hacia falta

Entre el logout y el login el cliente esta en el mundo con un personaje que el
servidor ya borro. Esa ventana tiene que ser **cero**, no corta: el cliente sigue
mandando movimiento y no hay a quien aplicarselo.

Asi que la consulta del personaje de destino se lanza ANTES de soltar el heroe y
se guarda el `LoginQueryHolder` resuelto; cuando llega, el logout y el login
pasan **en la misma vuelta del mundo**. Es exactamente *"un pseudo login que no
acabe de finalizarse"*. Con un matiz que cambia donde se aplica: **lo que se
precarga no es el `Player`** -- ese ya existe, es uno de tus bots, y esa mitad de
la idea ya estaba hecha sin saberlo -- **sino la CONSULTA**, que era la unica
parte que tardaba.

Y la ficha se pide **despues** de que el bot salga del mundo, no antes: si se
pidiera con el dentro se leerian sus filas antes de que `LogoutPlayerBot` las
guardara, o sea el personaje de hace un rato, sin lo que hubiera looteado o
gastado.

### Las tres fases

1. `WAIT_BOT_OUT` -- el destino deja de ser bot y sale del mundo.
2. `PRELOAD` -- consulta lanzada; al volver, en la misma vuelta: tragar el
   logout, `LogoutPlayer(true)`, `HandlePlayerLoginFromDB`.
3. `WAIT_REGROUP` -- el heroe que dejas y el resto del grupo vuelven de bot,
   reintentando cada vuelta.

Hay **una segunda comprobacion de combate** justo antes del cambio. La primera se
hace al pedirlo, y entre las dos pasan la salida de un bot y una consulta: sobra
tiempo para que te ataque algo, y soltar el personaje en combate deja auras y
amenaza apuntando a algo que ya no existe.

Y `Update` recorre **una copia de las claves**, no el mapa: `LogoutPlayer`
dispara `OnPlayerLogout` de forma sincrona y con el medio modulo, y un iterador
sobre un `unordered_map` no sobrevive a que alguien inserte.

### Lo que falta por ver, dicho por delante

- **Puede que no haya pantalla de carga en absoluto.**
  `SMSG_LOGIN_VERIFY_WORLD` (manejador `0x00403DE0`) **no hace nada si el mapa
  que trae es el que ya tienes** (`cmp ecx, eax` / `je 0x403EAB`, verificado esta
  manana). Cambiando entre dos personajes del mismo mapa el cliente no recarga
  nada: se limita a cambiar de identidad y a repoblar. Si eso deja restos --
  el modelo del heroe viejo como fantasma hasta que salga de vista, o la camara
  mirando donde no debe -- el plan B esta escrito: forzar la carga mandando ese
  mismo paquete con otro mapa antes, que es la rama que si llama a `0x00403B70`.
- **Cambiar entre personajes de mapas distintos si hara carga**, por la misma
  razon. Los dos casos son correctos pero no son el mismo, y conviene probar los
  dos.

### La primera pasada en juego: el servidor si, el cliente no. Addon 0.58.0, mod-rts 0.25.0

La rafaga de login llego entera -- el MOTD sale dos veces en el chat, una por
cambio -- y el servidor dijo *"listo, eres Avy"*. **Y el cliente seguia siendo
Neferite.** Sin error, sin nada raro en pantalla salvo que no eres quien te
dijeron: exactamente el modo de fallo silencioso que este proyecto persigue.

La causa esta en la misma funcion del cliente que da la solucion, veinte
instrucciones mas arriba de donde mire la primera vez. `0x004D6C00`, lo PRIMERO
que hace despues de leer el guid:

```
004D6C3F  call 0x4D6AE0        ; buscar ese guid entre los que ya tengo
004D6C49  test esi, esi
004D6C4B  je   0x4D6C91        ; NO lo tengo  -> CREAR  (y ahi esta el
                               ;   UPDATEFLAG_SELF que escribe objmgr+0xC0)
004D6C4D  ...                  ; SI lo tengo  -> ACTUALIZAR, y por ese camino
                               ;   el guid activo no se toca
```

**El flag "este eres tu" solo se mira al CREAR.** Si el cliente conserva al bot
que acaba de salir -- porque el aviso de que desaparecio se cruza con el login,
que es cuestion de un tick -- la rafaga se aplica entera como una actualizacion
y la identidad no se mueve.

La cura es una linea: un `SMSG_DESTROY_OBJECT` del personaje de destino justo
antes del login. Uno de mas no cuesta nada -- el cliente lo ignora si no lo
tiene, que es lo que hace con cada bicho que se aleja.

**Lo que NO se hace todavia, y es deliberado:** destruir el objeto del heroe que
dejas. Se queda de fantasma en el cliente hasta que salga de vista, que es feo
pero inofensivo; destruirlo ahora seria destruir **el jugador activo del cliente
mientras siga siendolo**, y si la identidad no llegara a cambiar seria dejarlo
sin jugador. Es la familia de fallo que se llevo el cliente por la manana.
Primero confirmar el cambio, luego limpiar.

**`/rts whoami` existe para confirmarlo con dos testigos independientes**, porque
"el servidor dice una cosa y el cliente otra" no se ve desde fuera:

- `UnitName("player")` sale del guid activo del gestor de objetos, que es
  justo el campo que escribe el `UPDATEFLAG_SELF`.
- El DLL lee **ese mismo campo** por su cuenta, sin pasar por Lua, y de ahi saca
  la posicion que publica. Si Lua dice un nombre y la posicion es la del otro,
  el problema es cache de la interfaz y no del gestor de objetos.
- Y las entradas al mundo dicen si hubo recarga. `SMSG_LOGIN_VERIFY_WORLD` no
  hace nada si el mapa que trae es el que ya tienes, asi que un cambio entre dos
  personajes del mismo mapa **no** dispara `PLAYER_ENTERING_WORLD`. Si el numero
  no sube, no hubo recarga -- que es lo que decide si hay que forzarla.


### La recarga del mundo, que es lo que faltaba. mod-rts 0.26.0

El `SMSG_DESTROY_OBJECT` del destino no basto: `/rts whoami` seguia diciendo
Neferite. Asi que el objeto que estorbaba no era solo ese, y la respuesta es
tirar el mundo entero del cliente y dejar que se reconstruya.

**La herramienta es `SMSG_NEW_WORLD`, y la diferencia con la otra candidata esta
en una comparacion.** Desensamblados los dos manejadores:

| paquete | manejador | que hace |
|---|---|---|
| `SMSG_LOGIN_VERIFY_WORLD` | `0x00403DE0` | lee mapa y posicion, **compara el mapa con el que ya tienes** y si es el mismo se va sin hacer nada (`je 0x403EAB`) |
| `SMSG_NEW_WORLD` | `0x00403D10` | lee mapa y posicion en **los mismos globales**, y va directo a `0x00403B70` -- la carga del mundo -- **sin comparar nada** |

Por eso el mismo mapa era un problema insalvable para el primero y no lo es para
el segundo. Los dos escriben `[0xB2F048]` y compania; lo unico que los separa es
esa comparacion, y es justo la que sobraba.

Se manda con la forma que usa el nucleo en un teleport lejano
(`Player.cpp:1607-1633`): `SMSG_TRANSFER_PENDING` primero -- que es lo que pinta
la pantalla de carga -- y `SMSG_NEW_WORLD` detras.

**Y hay una espera nueva, que no es opcional.** El nucleo lo dice en su propio
comentario: *"move packet sent by client always after far teleport"*. Hasta que
el cliente conteste con `MSG_MOVE_WORLDPORT_ACK` sigue tirando su mundo abajo, y
una rafaga de login que aterrice a mitad de eso se pierde con lo demas -- que es
el mismo fallo que esto viene a arreglar, repetido un tick mas tarde. Asi que el
heroe no se suelta hasta que llega el acuse.

**El acuse se ve con el mismo gancho que esconde el logout, en el otro sentido.**
`ServerScript::CanPacketReceive` (`WorldSession.cpp:466`) deja mirar lo que
entra, y ademas **se lo traga**: `WorldSession::HandleMoveWorldportAck` empieza
con `GetPlayer()->IsBeingTeleportedFar()` **sin comprobar que `GetPlayer()` no
sea nulo** (`MovementHandler.cpp:55`), y en este cambio hay un instante en que la
sesion no tiene jugador. Un acuse tardio o repetido seria una lectura de puntero
nulo en el hilo del mundo. No se pierde nada al descartarlo: aqui nadie se
teletransporta de verdad, asi que el manejador se saldria por ese mismo `if`.

Si el acuse no llega en 30 s **se sigue igual y se dice**. Abortar dejaria al
cliente mirando una pantalla de carga para siempre; lo unico que puede sacarle de
ahi es precisamente la rafaga que viene detras.

Las fases quedan en cuatro: sale el bot -> se precarga su ficha -> se tira el
mundo y se espera al cliente -> logout y login pegados -> se rehace el grupo.


### FUNCIONA. Y los dos fallos que dejo. Addon 0.59.0, mod-rts 0.27.0

`/rts whoami` dijo **Avy**. El cambio de personaje sin pasar por la pantalla de
seleccion esta hecho: eres el otro personaje de verdad, con su equipo, su libro
y sus barras, y sin mas interrupcion que una pantalla de carga.

Quedaron dos cosas, y **una sola causa explica las dos mitades de la segunda.**

#### La seleccion sobrevivia al cambio de identidad

Reportado como dos sintomas que no se parecen entre si:

- *"si selecciono Neferite de nuevo hace como que nos selecciona a ambos"*
- *"y no me deja cambiar a el en ningun momento"*

Es lo mismo. Seleccionas a Avy para saltar a el; al llegar, `selected` sigue
siendo `{Avy}` -- **que ahora eres tu**. Pinchar entonces a Neferite deja dos
seleccionados. Y con dos seleccionados el boton de Control usa el PRIMARIO, que
es Avy, que eres tu: *"selecciona a un compañero primero"*. O sea que **saltar a
un personaje impedia volver a el**, que se lee como que ese personaje esta
prohibido y no como una seleccion vieja.

`Selection:Prune` no lo cazaba **y no podia**: quita lo que ya no esta en el
grupo, y aqui lo seleccionado si esta. La pregunta que hacia falta no es "¿sigue
existiendo?" sino "**¿soy el mismo de antes?**", y esa solo tiene una fuente.
`Selection:IdentityChanged`, llamada desde `PLAYER_ENTERING_WORLD` -- que con el
cambio de personaje ya no significa "acabo de conectarme".

**La leccion de fondo: un evento cambio de significado y el codigo que lo usaba
no se entero.** Todo lo que el addon guarda por nombre asumia que el personaje de
la sesion no cambia nunca. Merece un barrido: `Route`, `Marks` y `Bags` guardan
cosas por nombre tambien.

#### El grupo no volvia, y el mensaje no dejaba saber por que

*"(1 para el grupo)"* no distingue entre *"solo habia uno"* y *"los demas no se
recogieron"* -- dos fallos distintos con dos arreglos distintos, y decidir cual
era costaba una ronda entera. Ahora se dicen **los nombres**, al empezar y al
fallar.

Y hay una causa real que ya se puede descartar en el momento:
`PlayerbotHolder::AddPlayerBot` solo acepta un personaje **de tu cuenta**, de tu
hermandad, o un bot aleatorio del servidor (`PlayerbotMgr.cpp:104-114`). **Un bot
aleatorio que estuviera en tu grupo no vuelve**: se pide con tu cuenta detras, y
con cuenta detras deja de contar como aleatorio. Meterlo en la lista igual seria
prometer algo que no va a pasar Y taparlo treinta segundos; ahora se avisa al
empezar, que es cuando el jugador puede decidir si le importa.


### El nombre viejo, y por que el addon no puede fiarse de el. Addon 0.60.0

Reportado como *"al loguear con otro pj me sigo llamando Neferite"*, con una
captura en la que **el marco de arriba dice Neferite y la lista del grupo TAMBIEN
tiene a Neferite**. Las dos cosas no pueden ser ciertas: nadie sale en su propio
grupo. Y la lista cuadra con el cambio -- los cuatro bots, sin el personaje al
que se salto -- asi que la identidad cambio bien y **lo que esta sin actualizar
es el nombre**.

Eso convierte un detalle cosmetico en la causa de lo de ayer, porque
`Selection:UnitFor` preguntaba **primero** si el nombre es el tuyo:

```lua
if name == UnitName("player") then return "player" end   -- antes
for _, m in ipairs(self:GetRoster()) do ...              -- despues
```

Despues de un cambio hay un compañero **que se llama como te llamabas** -- es
literalmente el heroe que acabas de dejar, que vuelve de bot -- asi que con el
nombre viejo pegado, pinchar a ESE bot resolvia a `player`. De ahi salen los dos
sintomas de la ronda anterior sin necesidad de ninguna otra causa: quedabais
seleccionados los dos, y el boton de Control contestaba *"selecciona a un
compañero primero"* sobre alguien que si lo era.

**El orden es el arreglo**, y es correcto con nombre fresco o rancio: un nombre
que esta en el grupo solo puede ser el del grupo.

Y con el, dos reglas nuevas para este addon:

- **La identidad se compara por GUID, nunca por nombre.** El guid sale del
  gestor de objetos del cliente -- el mismo campo que escribe el
  `UPDATEFLAG_SELF` -- o sea la definicion de a quien estas jugando. El nombre
  es texto que puede ir por detras, y ademas puede repetirse.
- **Al entrar en el mundo se imprime quien eres**, con nombre y guid. Despues de
  un cambio de personaje "¿quien soy?" deja de ser una curiosidad: es el dato del
  que depende todo lo demas, y cuando el cliente lo tiene mal el sintoma aparece
  tres modulos mas alla.

Falta decidir **cual de los dos esta mal**, y la prueba es de una linea: se le
pide a Blizzard que repinte su marco (`PlayerFrame_Update`, que no esta
protegida). Si el nombre se corrige, era el marco. Si sigue siendo el viejo, lo
que esta mal es el nombre que el cliente guarda de si mismo -- y entonces
`Orders`, `Route` y `Skills`, que mandan ordenes **por nombre**, estan mandando
al personaje equivocado y hay que darles el nombre por otra via.

**Lo que queda pendiente:** todo el addon guarda cosas por nombre asumiendo que
el personaje de la sesion no cambia nunca. `Route`, `Marks`, `Bags` y `Skills`
son la misma familia. Merece un barrido dedicado, no un parche por sintoma.


### El aviso que faltaba, y el nombre que no se puede creer. Addon 0.61.0, mod-rts 0.28.0

El chat de la ronda anterior contesto las tres preguntas de golpe, y las tres
respuestas estaban en el ORDEN de las lineas:

```
RTS: cambiando a Avy. Vuelven de bot: Bob, Secretar...
RTS Eres Neferite 0x0000000000000400        <-- entrada al mundo, TODAVIA Neferite
RTS: el cliente no confirmo la recarga; sigo igual.
...
Welcome to an AzerothCore server.           <-- la rafaga de login, 12 s despues
RTS: listo. Eres Avy y tu grupo esta entero (4).
```

#### 1. El acuse del cliente NO SE PUEDE VER, y el cliente si lo mandaba

`MSG_MOVE_WORLDPORT_ACK` es `STATUS_TRANSFER`, y el nucleo procesa esa clase de
paquete **solo cuando el jugador no esta en el mundo**:

```cpp
case STATUS_TRANSFER:
    if (_player && !_player->IsInWorld())      // WorldSession.cpp:497
    {
        if (!sScriptMgr->CanPacketReceive(this, *packet)) break;
        opHandle->Call(this, *packet);
    }
    break;
```

Durante el cambio el heroe sigue dentro -- no se suelta hasta despues -- asi que
el acuse **se tira antes de llegar a ningun gancho**. No era el cliente
callandose: era el servidor tapandose los oidos, y costaba 30 s de espera por
cambio.

Lo dice el ADDON, desde `PLAYER_ENTERING_WORLD`, que es el momento exacto en que
su mundo vuelve a estar en pie. Verbo `PORTED`. El plazo baja a 12 s y pasa a ser
solo el respaldo para un cliente sin addon.

**Y el `NoticeIncoming` que miraba el acuse esta BORRADO, no aparcado.** No podia
dispararse nunca, y una comprobacion que no corre es peor que no tenerla: parece
cubrir un caso que en realidad esta descubierto.

#### 2. NO HAY UN SEGUNDO `PLAYER_ENTERING_WORLD`, y por eso el addon no se entera

La linea *"Eres Neferite"* salio **antes** de la rafaga de login. Correcto y
esperado: la recarga del mundo pasa ANTES de soltar el heroe. Lo que no se penso
es lo que viene detras -- `SMSG_LOGIN_VERIFY_WORLD` con el mismo mapa no hace
nada (verificado en `0x00403DE0`), **asi que despues de cambiar de verdad no hay
ningun evento**. El addon se quedaba con la identidad de antes para siempre.

Ahora lo dice el servidor: `SWAPPED <nombre>`, mandado al terminar. Es autoridad
y no una pista -- es quien acaba de meter ese personaje en la sesion.

#### 3. `UnitName("player")` MIENTE DESPUES DE UN CAMBIO, y no es cosmetico

El marco seguia diciendo Neferite con el grupo de Avy debajo. La identidad si
cambia -- el guid es el nuevo y el grupo es el nuevo -- pero el texto va por
detras.

Y el heroe que dejas **vuelve de bot y se llama como te llamabas**, asi que
media docena de sitios que preguntan *"¿es este mi personaje?"* comparando
nombres contestaban que si sobre el bot equivocado. Peor: **el canal con el
servidor se susurra a uno mismo POR NOMBRE** (`Link.lua`), asi que un nombre
rancio lo deja mudo entero -- el addon habria dejado de hablar con mod-rts sin
un solo error.

`ns.MyName()` en `Bridge.lua` es el unico sitio que contesta esa pregunta, y
guarda el nombre **junto al guid al que se refiere**: sin eso, un cambio seguido
de una reconexion dejaria el nombre de otro pegado. Barridos los 18 usos de
`UnitName("player")` en ocho ficheros. Los dos de `Core.lua` se quedan **a
proposito**: son los diagnosticos, y tienen que ensenar lo que cree el CLIENTE,
no lo que hemos corregido nosotros.

#### Y el comprobador se gano el sueldo otra vez

`ns.MyName` se anadio al final de `Bridge.lua`, que **acaba en `return B`**. En
Lua un `return` tiene que ser la ultima sentencia de su bloque, asi que el
fichero dejo de compilar entero -- y con el, el addon. `check_addon.py` lo canto
en un segundo. Es la tercera vez que ese guion evita una ronda perdida.


### Por que el nombre no cambia: `UnitName("player")` no mira nada. Addon 0.62.0

La pista fue *"cambio de pj y veo sus cosas, pero el nombre Neferite"* -- o sea,
identidad si, nombre no. Con eso la pregunta deja de ser "¿cambio?" y pasa a ser
"¿de donde saca el cliente su propio nombre?". Contestada en el binario, y la
respuesta explica por que ningun evento ni ninguna funcion de Blizzard lo
arreglaba.

`UnitName` esta en `0x0060E740` y lo PRIMERO que hace es comparar el argumento
con la cadena `"player"` (`0x009F6F4C`):

```
0060E78B  call 0x76E780        ; strcmpi(unidad, "player")
0060E792  jne  0x60E7B3        ; no es "player" -> mirar el objeto
0060E794  call 0x6B1060        ; SI lo es    -> el nombre guardado
0060E79B  call 0x84E350        ; lua_pushstring(L, ese nombre)
```

Y `0x006B1060` son cinco instrucciones:

```
006B1060  mov al, byte ptr [0xC79D18]
006B1065  neg al
006B1067  sbb eax, eax
006B1069  and eax, 0xC79D18      ; devuelve el buffer, o 0 si esta vacio
006B106E  ret
```

**Para `"player"` el cliente no mira el objeto, ni el guid, ni el gestor de
objetos: lee un buffer estatico en `0x00C79D18`.** Ese buffer se rellena al
entrar al mundo desde la lista de personajes -- que es exactamente el paso que
este cambio se salta. Nada mas en todo el binario referencia esa direccion (solo
las dos lecturas del getter), asi que se escribe por puntero desde el camino de
la pantalla de seleccion y por ningun otro sitio.

Eso cierra tres preguntas de golpe:

- **Por que `PlayerFrame_Update` no arreglaba nada.** No estaba sin refrescar: lo
  que Blizzard dibuja ES el contenido de ese buffer.
- **Por que la identidad si cambiaba.** Todo lo demas -- grupo, equipo, hechizos,
  bolsas -- sale del objeto y del guid, y esos si son los nuevos.
- **Por que era peligroso y no cosmetico.** El heroe que dejas vuelve de bot y se
  llama como te llamabas, asi que cada comparacion por nombre del addon
  contestaba que si sobre el bot equivocado -- y el canal con mod-rts, que se
  susurra a uno mismo POR NOMBRE, se habria quedado mudo sin dar un solo error.
  Eso ya lo cubre `ns.MyName()` (0.61.0).

**El arreglo de hoy es cosmetico a proposito y esta dicho.** Se le repinta el
nombre al marco de Blizzard, enganchando `PlayerFrame_Update` con
`hooksecurefunc` -- despues de la suya, para tener la ultima palabra -- porque
ellos lo vuelven a poner en cada evento propio y un `SetText` de una vez duraria
hasta el primer cambio de vida.

**La cura de raiz es que `rts_core` escriba `0x00C79D18`**: es memoria normal del
cliente, el DLL ya escribe cosas mas delicadas, y entonces `UnitName("player")`
diria la verdad y sobrarian tanto el repintado como la mitad de `ns.MyName`.
Queda apuntado y NO hecho, con el precio por delante: hace falta un canal nuevo
para pasarle una CADENA al DLL -- el que hay es un entero empaquetado de 30 bits
-- mas una recompilacion, y lo de hoy son ocho lineas. Se hace el dia que
aparezca un segundo consumidor, no antes.


### La interfaz no se enteraba, y por eso los hechizos eran del anterior. Addon 0.63.0, mod-rts 0.29.0

*"Los spells son los del bot anterior, y si clico uno el personaje se buguea."*

**Los datos llegaban bien.** `SendInitialSpells()` y `SendInitialActionButtons()`
van dentro de la rafaga de login (`Player.cpp:11790,11793`) y el cliente los
guarda. Lo que no pasaba es que la INTERFAZ se enterara: los marcos de Blizzard
se redibujan con `PLAYER_ENTERING_WORLD`, y **el cambio no dispara ninguno** --
la recarga del mundo ocurre ANTES de soltar el heroe, asi que ese evento llega
siendo todavia el de antes, y despues de cambiar de verdad no hay evento
ninguno.

Asi que las barras seguian ensenando las del personaje anterior, y pulsar una
lanzaba un hechizo que este ya no conoce: de ahi el "se buguea".

**Es la TERCERA consecuencia del mismo hecho**, y las tres llegaron por separado
sin parecerse entre si: la espera de 12 s (no habia acuse), el nombre viejo (no
habia aviso) y ahora las barras (no hay redibujo). Merece quedar escrito como
una sola frase: **un cambio de personaje no dispara `PLAYER_ENTERING_WORLD`, y
todo lo que en este cliente cuelga de ese evento se queda como estaba.**

`ReloadUI()` al terminar el cambio, con un respiro para leer el mensaje.
Refrescar marco por marco seria una lista que se queda corta -- barras, libro,
talentos, reputaciones, misiones, bolsas, y la siguiente que falte se descubre en
juego. `ReloadUI` reconstruye la interfaz entera a partir de datos que ya son
correctos, **y no toca la conexion**: es lo mismo que teclear `/reload`, no un
relogueo. Apagable con `/rts swapui`.

**Y con la recarga hace falta preguntar el nombre otra vez**, porque el buffer
del cliente (`0x00C79D18`) sigue teniendo el viejo y una interfaz nueva vuelve a
leerlo. Verbo `WHOAMI` -> respuesta `IAM <nombre>`, mandado en cada entrada al
mundo. **Dos verbos y no uno a proposito**: `SWAPPED` significa "acabas de
cambiar" y recarga la interfaz; `IAM` es solo una respuesta. Con un solo verbo,
preguntar quien eres recargaria la interfaz -- y en el arranque eso es un bucle.

#### Los dos anillos, que no son un fallo nuevo

Pendiente de confirmar, pero la explicacion mas probable estaba escrita desde la
etapa 5e: el dibujo nativo del circulo tiene **dos ranuras**, tu objetivo y tu
mouseover (`ctx+0x380` y `ctx+0x388`), y `Circle.cpp` deja correr el original
antes de dibujar los nuestros. Seleccionar una unidad en el mundo **tambien la
pone de objetivo**, asi que se lleva el anillo nativo Y el nuestro. Seria asi
desde siempre y solo ahora se mira de cerca.

Si molesta, la salida barata es no publicar el nuestro para la unidad que ya es
tu objetivo -- una comparacion en `Channel.lua`, sin tocar el DLL.


### Las rutas, tres retoques antes de volver al centro de la HUD. Addon 0.64.0

Solo cliente; mod-rts sigue en 0.29.0.

- **El aro de destino baja de 2.20 a 1.30 yardas.** Pedido asi.

- **Rastro de puntitos entre destinos: construido y BORRADO el mismo dia.** Se
  pidio con una referencia de otro juego, se hizo (puntos separados una distancia
  fija en yardas, arrancando en quien anda) y al verlo en pantalla no gusto.

  **Es la tercera forma de unir los puntos que se descarta MIRANDOLA**, despues
  de la fila de puntitos original y de la linea continua con `DrawRouteLine`. Las
  tres veces el codigo era correcto: lo que falla no es el dibujo, es la idea de
  dibujar el camino. **La ruta son sus destinos** -- escrito ya tres veces, que
  deberian ser suficientes.

  Con el se va `sim/route_trail.py`, que existia para probarlo. Un guion que
  comprueba codigo borrado es la misma clase de resto que este documento lleva
  seis etapas persiguiendo.

- **Si vas TU en la seleccion, la ruta es tuya y los demas te siguen.** Mandar a
  los cuatro por su cuenta al mismo sitio es peor de todas las maneras: se abren
  en formacion alrededor del punto, se enganchan en la geometria cada uno por su
  lado, y el que llega primero se queda parado. La ruta se queda con **una sola
  unidad**, asi que a los demas los waypoints **ni se les mandan** -- no es que
  los ignoren -- y no hay dos sistemas moviendo al mismo bot, que es como se
  llego al "va y vuelve" que ya costo una ronda con el ancla de `stay`.

  A los NO seleccionados no se les toca, textual: *"el pj que no estuviera
  seleccionado, bueno, por algo sera"*.

#### Y el sim encontro algo antes de borrarse

`sim/route_trail.py` vivio media hora y aun asi salio a cuenta: con el tope en 14
puntos, un tramo de 100 yardas los separaba 7,14 yd en vez de 3,5 -- o sea que la
promesa de "separacion constante" era falsa justo en los tramos largos, y en
pantalla se habria visto como que el rastro se estira sin motivo. Se corrigio
antes de que llegara al juego, y el juego contesto otra cosa. **Las dos mitades
cuentan: el sim hizo bien su trabajo, y su trabajo no era decidir si la funcion
gustaba.**

### El aviso estaba atado al grupo, y por eso no se recargaba. Addon 0.66.0, mod-rts 0.30.0

*"Sigo viendo los spells del anterior, pero si hago /reload se arregla"* -- o sea
que la recarga automatica de la ronda anterior no estaba corriendo. Y *"los
compañeros siguen sin aparecer"*.

**Eran el mismo fallo.** El `SWAPPED` -- que es lo que dispara la recarga en el
addon -- se mandaba al terminar el REGRUPAMIENTO, no al terminar el cambio. Asi
que si un compañero tardaba, el aviso llegaba treinta segundos tarde; y si no
volvia nunca, no llegaba. **Con el se quedaba sin recargar la interfaz**, y las
barras seguian con los hechizos del personaje anterior: dos sintomas sin relacion
aparente, pegados por una dependencia que no tenia ningun motivo de existir.

**Quien eres no depende de cuantos bots hayan cargado.** El aviso se manda ahora
justo despues de `HandlePlayerLoginFromDB`, que es el instante en que de verdad
eres otro.

Y la recarga espera con criterio en vez de con un numero: **se recarga en cuanto
entra el primer compañero** (con medio segundo de cortesia) **o a los 5 s**, lo
que pase antes. No se espera A QUE el grupo se complete, porque un compañero que
no vuelve nunca -- un bot aleatorio, uno de otra cuenta -- dejaria la interfaz
rota para siempre por algo que no tiene que ver con ella.

**Y un fallo silencioso menos:** `bots::Add` devuelve false cuando el gestor de
bots del maestro todavia no existe, y eso puede pasar en la primera vuelta
despues del login. Se decia igual que no decir nada -- un grupo que no vuelve y
ningun motivo. Ahora se avisa una vez y se sigue intentando.


### Tres fallos en una captura, y uno se comia a los otros dos. Addon 0.67.0, mod-rts 0.31.0

La captura del cambio Avy -> Kirinah traia las tres pruebas juntas:

```
RTS: tu cliente no confirmo la recarga (¿addon viejo?); sigo igual.
...
RTS: listo. Eres Kirinah y tu grupo esta entero (4).
RTS Ahora eres Kirinah.
RTS Recargando la interfaz...
No hay ningun jugador con el nombre Avy.
No hay ningun jugador con el nombre Avy.
No se ha podido realizar la accion de interfaz debido a un AddOn
```

#### 1. EL CANAL SE CAIA JUSTO EN EL MOMENTO QUE TENIA QUE CUBRIR

Esos dos *"No hay ningun jugador con el nombre Avy"* son `PORTED` y `WHOAMI` --
**los dos mensajes de los que depende el propio cambio**. El canal se susurra a
uno mismo POR NOMBRE, y despues de un cambio el addon no sabe como se llama:
justo el problema que `PORTED` y `WHOAMI` venian a resolver. Por eso el servidor
decia "tu cliente no confirmo la recarga" y esperaba doce segundos.

Con grupo se manda ahora por **PARTY**, que no necesita acertar ningun nombre.
Este fichero decia que PARTY no valia porque *"el chat de grupo es donde
mod-playerbots lee SUS propios comandos"* -- y **eso no aplica a un mensaje de
addon**: `PlayerbotAI.cpp:604` sale con `type == CHAT_MSG_ADDON` y `:610` sale
otra vez con `lang == LANG_ADDON`, cada uno con su comentario diciendo justo eso.
**La objecion era buena para texto plano y se aplico de mas** -- y costo dos
rondas de sintomas que no se parecian a su causa.

#### 2. `ReloadUI()` ESTA PROHIBIDO DESDE UN ADDON

*"No se ha podido realizar la accion de interfaz debido a un AddOn"* es el aviso
de accion prohibida. Teclear `/reload` a mano si funciona -- porque entonces no
hay addon en la pila -- que es exactamente por que el jugador veia que su
`/reload` arreglaba lo que el nuestro no.

Asi que se refresca a mano lo que cuelga de `PLAYER_ENTERING_WORLD`: barras de
accion, marcos del grupo, tu marco y el del objetivo. **Es una lista y las listas
se quedan cortas**, asi que el addon lo dice en voz alta: si algo sigue viejo,
`/reload` lo arregla -- y que lo cuente, para que la siguiente entre en la lista.

#### 3. EL GRUPO ESTABA, PERO EL CLIENTE NO LO VEIA

Los marcos salian con el nombre puesto y las barras vacias, que es como se ve un
compañero del que el cliente no tiene datos -- no como uno que falta. Y el
servidor decia "tu grupo esta entero (4)". Las dos cosas eran ciertas.

Los bots se anaden **despues** del login, asi que la vuelta de visibilidad que
hizo el login no los incluia. Se repite al completar el grupo, igual que hace el
nucleo en su propio camino de entrar en un personaje que ya esta en el mundo
(`CharacterHandler.cpp:1193`): limpiar las referencias y forzar una vuelta, para
que el cliente reciba la lista entera en vez de la diferencia.


### Tres nombres en tres sitios, y cada uno decia la verdad. Addon 0.68.0, mod-rts 0.32.0

Encadenando Avy -> Kirinah -> Bob, y despues de un `/reload`, el jugador veia:

| donde | decia | de donde sale |
|---|---|---|
| el servidor | **Bob** | el `Player` real de la sesion |
| `UnitName("player")` | **Avy** | el buffer estatico `0x00C79D18` |
| las barras de accion | **Kirinah** | la ultima rafaga de login que el cliente aplico |

Las tres eran ciertas, y juntas dan el diagnostico que ninguna daba sola:

- **El buffer del nombre no es prueba de nada sobre el cambio.** Solo lo escribe
  la pantalla de seleccion, asi que se queda con el personaje con el que entraste
  de verdad -- Avy -- pase lo que pase despues. Ya estaba escrito y aun asi
  despisto: mirandolo parecia que el cliente "habia vuelto" a Avy.
- **Las barras si son prueba, y dicen Kirinah**: o sea que la rafaga de login del
  PRIMER cambio se aplico entera y la del SEGUNDO no llego. **El problema no es
  que la interfaz no se refresque -- es que el cliente nunca recibio los datos.**
  Por eso `/reload` habia dejado de arreglarlo: no hay nada correcto que
  redibujar.

Encaja con el *"tu cliente no confirmo la recarga"* de la ronda anterior: sin el
`PORTED`, el servidor espera doce segundos y manda la rafaga cuando el cliente ya
esta en otro punto del proceso, y se pierde entera.

#### Lo que cambia

- **El servidor manda el GUID junto al nombre** (`SWAPPED <nombre> <guid>`,
  `IAM <nombre> <guid>`) y el addon lo contrasta contra `UnitGUID("player")`. Si
  no cuadran, **dice que el cambio no se aplico** en vez de escribir el nombre
  nuevo encima.

  Esto es lo que convertia un fallo entero en "los hechizos salen mal": todo lo
  demas parecia correcto **porque lo estabamos escribiendo nosotros**. Un aviso
  que se cree lo que le dicen no es un aviso, es un decorado -- misma familia que
  `C:Report()` imprimiendo el FOV que no se aplicaba y que `check_addon.py`
  aprobando una cadena rota.
- **`PORTED` se manda cinco veces en 2,5 s.** De ese mensaje depende el cambio
  entero y acababa de sobrevivir a una recarga de mundo; perderlo cuesta la
  rafaga. `ClientPorted` es idempotente y contesta que no cuando no hay ningun
  cambio esperando, asi que repetirlo no cuesta nada.


### LAS BARRAS NO SE VACIAN SOLAS. mod-rts 0.33.0

Lo encontro el jugador con la prueba mas clara posible: **una barra con hechizos
de sacerdote y de paladin a la vez** -- de dos personajes distintos. No es que
falten las nuevas: es que las viejas siguen ahi, y se van **acumulando** cambio
tras cambio.

`SendInitialActionButtons()` manda el paquete con **estado 1**, y el nucleo
documenta lo que significa cada estado en el propio `Player.cpp:5726-5731`:

```
1 - Used in any SMSG_ACTION_BUTTONS packet with button data
2 - Clears the action bars client sided. This is sent during spec swap
    before unlearning and before sending the new buttons
```

Con el 1 el cliente **no vacia** las casillas que llegan a cero. En un login
normal da igual, porque el cliente viene de la pantalla de seleccion y sus barras
ya estan vacias. **Aqui no**, y ese es el resumen de todo el proyecto de esta
tarde: el cambio de personaje reutiliza un camino cuyas suposiciones incluyen
"vienes de fuera del mundo", y cada suposicion que no se cumple sale como un
sintoma distinto.

El cambio de especializacion tiene exactamente el mismo problema y el nucleo ya
lo resuelve asi. Se hace lo mismo: `SendActionButtons(2)` y luego las suyas.

#### Y una lectura anterior que estaba MAL, corregida

La ronda de antes concluyo, de que las barras ensenaran a Kirinah siendo Bob, que
*"la rafaga de login del segundo cambio se perdio"*. **Falso.** La rafaga llego
perfectamente; lo que pasa es que sus botones se mezclaron con los que ya habia,
y los huecos que Bob no usa se quedaron con los de Kirinah. Mirando solo las
barras las dos explicaciones se ven igual -- y la equivocada mandaba a arreglar
el handshake del cambio de mundo, que no tenia nada que ver.

Lo que la distinguia era **de cuantos personajes hay hechizos a la vez**: una
rafaga perdida deja los de UNO (el anterior); una mezcla deja los de VARIOS. Esa
observacion la hizo el jugador y valia mas que las tres deducciones que llevaba
encima.


### El cliente TIRA las barras si todavia no sabe quien es. mod-rts 0.35.0, addon 0.70.0

Descartada la opcion de "los datos guardados no son los que crees" -- el jugador
configuro a mano la barra de cada personaje para comprobarlo. Asi que era
transporte, y el binario del cliente da la respuesta exacta.

Manejador de `SMSG_ACTION_BUTTONS`, `0x006D8750`:

```
006D876D  call 0x4D3790     ; ¿quien es el jugador activo?
006D8780  call 0x4D4DB0     ; su objeto
006D8788  cmp esi, 2        ; estado 2 -> marca +0x1954 y sale
...                         ; estados 0 y 1 -> leer 144 dwords al array 0xAD9F6C
006D87D3  cmp [ebp-0xC], 1  ; ¿estado 1?
006D87D7  jne 0x6D8863      ;   si no, ni valida ni repinta
006D87E0  cmp eax, edi      ; ¿hay objeto de jugador? (edi vale 0 aqui)
006D87E2  je  0x6D8863      ;   si NO -> se salta el repaso entero
```

**La rafaga de login llega antes de que el cliente haya adoptado su identidad
nueva** -- el objeto propio viaja en esa misma rafaga -- asi que en ese instante
no hay objeto de jugador: los datos entran en el array pero **no se validan ni se
repintan**, y un estado 2 ni siquiera llega a marcar nada.

Eso explica de una vez las tres cosas raras: barras que se quedan con lo
anterior, un `/reload` que a veces arregla (repinta desde el array) y a veces no
(cuando el array tampoco se lleno), y un estado 2 que no limpiaba.

**No se puede adivinar cuando el cliente esta listo, asi que lo dice el.** Verbo
`REBARS`, que el addon manda **despues** de comprobar que su `UnitGUID("player")`
coincide con el guid que el servidor le dijo -- o sea en el primer instante en
que pedirlas sirve de algo. El servidor contesta con el par de siempre: vaciar y
mandar.

**Corrige tambien mi lectura de la ronda anterior.** El comentario del nucleo
sobre los estados (`Player.cpp:5726-5731`) llevo a pensar que el estado 1
fusionaba y el 2 limpiaba. El cliente dice otra cosa: los estados 0 y 1
**sobrescriben los 144 huecos siempre**, y lo unico que el 1 anade sobre el 0 es
el repaso y el repintado. La mezcla de sacerdote y paladin no salia de una
fusion: salia de que el repintado no corria y la interfaz seguia ensenando lo
que tenia. **El comentario del nucleo describe una intencion; el binario describe
lo que pasa.**


## La barra que faltaba era la de POSTURA. Addon 0.74.0, 2026-09-04

**Confirmado en juego.** Despues de un cambio de personaje el guerrero sale con
su barra de postura, igual que en un login natural, y el sentido contrario
tambien. Tres versiones: las dos primeras fallaron por mirar el testigo
equivocado, y lo que lo cerro fue leer el FrameXML del cliente en vez de
razonar sobre el.

El jugador hizo el experimento que ninguna ronda de pruebas habia hecho:
**capturas de los cinco personajes, login natural contra cambio, y comparar la
parte de abajo.** Cuatro pares salieron identicos pixel a pixel; uno no. Ese
"cuatro de cinco" es el diagnostico entero, porque lo que tienen en comun los
cuatro que salen bien es que **ninguno tiene barra de postura**.

### Lo que dicen las capturas y la base de datos

| personaje | clase | login natural | tras un cambio |
|---|---|---|---|
| Avy | cazador | 6603, 1494, 2973 | igual |
| Bob | mago | 1459, ..., 59752 | igual |
| Kirinah | sacerdote | 58984, 585, 2050 | igual |
| Secretaria | paladin | 6603, 465, 635 | igual |
| **Neferite** | **guerrero** | 6603, 78, 58984, 6673 | **-, 78, 2764, -** |

Y lo que Neferite tiene guardado (`character_action`, guid 1023):

```
  1: 78 (Golpe heroico)      72: 6603 (Atacar)      84: 6603
  2: 2764 (Lanzar)           73: 78                 96: 6603
 58: macro 1                 74: 58984 (Camuflaje)
 59: macro 2                 75: 6673 (Grito de batalla)
```

**Las dos filas existen y las dos son suyas.** El login natural dibuja las
casillas **72-75**; despues de un cambio dibuja las **0-11**. No falta ningun
dato, no se pierde ninguna rafaga, no hay nada mezclado de otro personaje: el
cliente esta dibujando **otra fila de las 120 que tiene**.

Comprobado ademas contra `playercreateinfo_action` para elfo de la noche
guerrero, que trae exactamente `72, 73, 74, 84, 96` -- o sea que esas casillas
son de fabrica y llevan ahi desde que se creo el personaje. **La base de datos
nunca estuvo corrupta**, que era la otra explicacion posible y la que habria
mandado a mirar al sitio equivocado.

### La causa

Las casillas 0-11 son la pagina 1. Las 72-83 son la **barra de postura**, y un
guerrero esta siempre en una (Neferite tiene el aura 2457, Postura de Batalla,
permanente en `character_aura`). Cual de las dos se dibuja lo decide
`GetBonusBarOffset()`, y quien se lo pregunta es `ActionBarController` -- que
solo lo hace cuando le llega `PLAYER_ENTERING_WORLD`, `ACTIONBAR_PAGE_CHANGED` o
`UPDATE_BONUS_ACTIONBAR`.

**Un cambio de personaje no dispara ninguno de los tres.** Es la CUARTA
consecuencia del mismo hecho, y las cuatro llegaron por separado sin parecerse
entre si:

  * la espera de 12 s (no habia acuse),
  * el nombre viejo (no habia aviso),
  * las barras con los hechizos del anterior (no habia repintado),
  * y ahora **cual de las 120 casillas se dibuja** (no habia reevaluacion).

`ActionButton_Update` -- la lista de refrescos a mano de `RefreshAfterSwap` -- no
podia cazarlo, y por eso sobrevivio: recalcula **lo que hay EN una casilla**, no
**CUAL de las 120 es esa casilla**. Eso sale del atributo `actionpage`, que pone
el controlador y nadie mas.

### Y EL PRIMER ARREGLO APUNTO AL WIDGET EQUIVOCADO

Di por hecho el esquema moderno -- un `ActionBarController` seguro que le cambia
el atributo `actionpage` a los mismos botones -- y di un golpecito a la pagina
para que se reevaluara. En juego no hizo nada, y el volcado lo contesto en una
linea: **`ActionBarController` NO EXISTE en este cliente.**

En 3.3.5 manda el esquema viejo: `BonusActionBarFrame`, un marco APARTE con sus
propios `BonusActionButton1..12`, que se DESLIZA por encima de la barra normal.
Su estado es un `state` que vale `"top"` o `"bottom"`:

```
login  ->  BonusActionBarFrame  VISIBLE  state=top
cambio ->  BonusActionBarFrame  oculto   state=bottom
```

`ActionButton1 lee la casilla 1` en los DOS casos, y eso es correcto: no es el
que se equivoca, es que **esta tapado**. Por eso el golpecito de pagina no podia
funcionar, y por eso la primera version del volcado -- que miraba
`ActionButton1.action` esperando que saltara de 1 a 73 -- dio "no cambia nada"
en las cuatro pruebas. **El testigo equivocado convierte un experimento bueno en
un resultado inutil**, que es la misma forma de error que `C:Report()`
imprimiendo el FOV que no se aplicaba.

Es la regla de siempre de este proyecto -- comprobar contra el cliente y no
contra lo que uno recuerda -- saltada por asumir la version MODERNA de una API
en vez de una constante inventada. Misma familia que `nameplateMaxDistance` y
`gxWindowedResolution`, y cuesta lo mismo: una vuelta.

### EL FRAMEXML DEL CLIENTE SE PUEDE LEER, Y ESO CAMBIA LA FORMA DE TRABAJAR

Despues de DOS arreglos fallidos seguidos, los dos por razonar sobre una API de
interfaz que no habia visto, se acabo la sangria de la unica forma posible:
sacando el codigo del cliente y leyendolo.

```
pip install mpyq
```

```python
import mpyq
a = mpyq.MPQArchive(r"D:\GAMES\WOW WOTLK\Data\esES\patch-esES.MPQ", listfile=False)
open("MainMenuBar.lua","wb").write(a.read_file("Interface\\FrameXML\\MainMenuBar.lua"))
```

**El FrameXML NO esta en los MPQ de `Data\`, esta en los de la LOCALIZACION**
(`Data\esES\`), y ahi `patch-esES.MPQ` gana a `locale-esES.MPQ`. Son 290
ficheros `.lua`/`.xml`: la interfaz entera de Blizzard, en texto. Cuesta dos
minutos y contesta de una vez preguntas que hasta ahora se contestaban con una
ronda de pruebas por intento.

Es la regla de este proyecto -- comprobar contra el cliente, no contra lo que uno
recuerda -- pero llevada un escalon mas: hasta hoy se comprobaba **si** una
funcion existe (`/rts portrait api`); ahora se puede leer **que hace**.

### El arreglo, escrito contra el codigo de verdad

`MainMenuBar_OnEvent`, en `PLAYER_ENTERING_WORLD`, llama a
`MainMenuBar_ToPlayerArt()`, y ahi dentro esta lo que arregla el `/reload`:

```lua
if ( GetBonusBarOffset() > 0 ) then ShowBonusActionBar(true);
else HideBonusActionBar(true); end
```

Tres cosas que no se deducen y que costaron las dos vueltas:

- **El `override` no es decorativo.** Las dos funciones empiezan con
  `if ((not MainMenuBar.busy) and (not UnitHasVehicleUI("player"))) or override`,
  asi que un `MainMenuBar.busy` que se quedo puesto las deja mudas. Blizzard pasa
  `true` en todos los sitios donde de verdad quiere que ocurra.
- **`state` no vale como testigo inmediato.** Solo lo escribe
  `BonusActionBar_OnUpdate` al ACABAR el deslizamiento, 0,15 s despues. La
  version anterior lo miraba en la misma linea, asi que sus tres puertas dijeron
  "no ha abierto" -- **incluida la que si abria**. Segundo testigo equivocado
  seguido en el mismo fallo, despues de `ActionButton1.action`, que no cambia
  nunca. Ahora se comprueba `IsShown()` medio segundo despues.
- **`mode` se atasca.** El deslizamiento vive en el `OnUpdate` del marco, y un
  marco escondido no recibe `OnUpdate` -- y `Chrome.lua` esconde ese marco al
  entrar en modo RTS. Si se queda a medias con `mode = "show"`, la guarda interna
  (`mode ~= "show" and state ~= "top"`) deja a `ShowBonusActionBar` sin hacer nada
  **para siempre**. Por eso `ns.SyncBonusBar` desatasca `mode`/`completed`/`state`
  antes de pedir nada.

**Se toca solo la barra de postura, no `MainMenuBar_ToPlayerArt` entera.** Esa
esconde y ensena `MultiBarLeft` y compania, que SI son marcos seguros;
`BonusActionBarFrame` es un `Frame` normal -- sus botones son seguros, el no --
asi que ensenarlo no puede bloquear una casilla.

**Los dos sentidos, y no es simetria por gusto:** entrar en el guerrero deja la
barra abajo enseñando casillas que no son suyas, y salir de el la deja arriba
enseñando las 73..84 de un mago, que estan vacias.

### Y una linea de diagnostico que mentia con la voz de la autoridad

*"Al hacer /reload me dice **eres Neferite** aun siendo Bob"*. No era el cambio
fallando: la linea imprimia `UnitName("player")`, que sale del buffer estatico
`0x00C79D18` -- el que **solo rellena la pantalla de seleccion de personaje**, o
sea el nombre con el que ARRANCASTE la sesion, para siempre. El guid que iba al
lado (`0x403`) ya era el de Bob, y decia la verdad; nadie lo miraba porque el
nombre estaba delante.

El aviso se dice ahora al contestar `IAM`, que es el servidor diciendo a quien
acaba de meter en la sesion. Es la misma leccion que `C:Report()` imprimiendo el
FOV que no se aplicaba: **un lector que miente en la direccion tranquilizadora es
peor que no tener lector**, y aqui mentia en la direccion alarmante, que cuesta
igual -- manda a arreglar algo que no esta roto.

### Lo que NO se ha hecho, con el precio por delante

**La cura de raiz es que el cambio termine con una entrada al mundo de verdad**,
para que `PLAYER_ENTERING_WORLD` se dispare DESPUES de que cambie la identidad y
la interfaz se rehaga entera, como en un login. Hoy la recarga de mundo pasa
ANTES de soltar el heroe, asi que ese evento llega siendo todavia el de antes --
y de ahi salen las cuatro consecuencias de arriba.

El camino esta leido y es corto de escribir: despues de
`HandlePlayerLoginFromDB`, un `TeleportTo(mismo mapa, su propia posicion, ...,
newInstance = true)`. El `newInstance` es lo que fuerza la rama LEJANA aunque el
mapa sea el mismo (`Player.cpp:1498`, `if (GetMapId() == mapid && !newInstance)`),
y a partir de ahi lo lleva el nucleo: `SMSG_TRANSFER_PENDING` + `SMSG_NEW_WORLD`,
el cliente contesta `MSG_MOVE_WORLDPORT_ACK` -- que **ya no se descarta**, porque
en ese momento el jugador esta fuera del mundo, que es justo lo que pide
`STATUS_TRANSFER` -- y `HandleMoveWorldportAckOpcode` vuelve a llamar a
`SendInitialPacketsBeforeAddToMap` (hechizos, casillas, talentos, reputaciones) y
a `AddPlayerToMap`. Con eso sobrarian `PORTED`, `REBARS`, `RefreshAfterSwap` y la
lista que se queda corta.

**No se hace hoy porque hay una incognita que solo contesta el juego:** en el
cambio actual `PLAYER_ENTERING_WORLD` se dispara con el guid VIEJO todavia puesto
-- se ve en el chat de la ronda 21, *"Eres Neferite 0x400"* antes de la rafaga --
o sea que el cliente da por terminada la carga sin tener su objeto. Si lo mismo
pasa con el teleport, el evento volveria a llegar antes de la identidad y no se
habria ganado nada; si en cambio espera al objeto, se gana todo. Es una
compilacion y una ronda, contra las dos lineas de hoy. La regla de la etapa 5e:
una lectura estatica convincente vale UNA prueba barata, no maquinaria encima.

`/rts whoami` imprime **pagina, postura y forma**, y `/rts bars page` vuelca
quien dibuja: que marcos existen, cual esta visible, las dos filas de casillas
una debajo de otra, y el intento de arreglo con el resultado de cada puerta. Es
el patron de `/rts portrait api` -- en vez de comprobar una constante, no tener
constante -- y es lo que contesto esta vuelta en treinta segundos.

## La sala se llena: el panel de control de grupo, 2026-09-04

Addon **0.75.0**, mod-rts **0.36.0** (hay que reiniciar el servidor). Construido,
no visto todavia. El encargo es `Downloads/brief-barra-control-grupo.md`;
`docs/UI-RTS-SALA.md` §14 lleva el detalle y `docs/HECHIZOS-COLA.md` es el
estudio previo que el propio brief pedia.

La sala llevaba vacia desde el 2 de septiembre para no predecidir lo que iba
dentro. Cinco ficheros nuevos: `Hall.lua` (el reparto y el estado), `Party.lua`
(la columna de cinco), `Frames.lua` (los marcos de unidad), `Cast.lua` (los
huecos y las cuatro acciones) y `sim/hall_layout.py`. `Skills.lua` reescrito.
En el servidor, `RtsQueue.cpp/.h`.

### LA MITAD DEL BRIEF YA ESTABA CONSTRUIDA, Y ESTA VEZ SE MIRO ANTES

Es la leccion de la etapa 5n aplicada a proposito en vez de pagada otra vez.
Cuatro de las nueve cosas que pedia no habia que escribirlas:

- **§7 "generar una version recortada del tramo central que tilee"**:
  `middle.tga` **es** esa pieza y `/rts bar grow <n>` la repite desde el
  2026-08-19. Cero trabajo.
- **§9.1 "¿curar en focus existe o hay que programarlo?"**: existe, `PFOCUS`,
  compilado desde mod-rts 0.15.0. Sobre un amigo pone `focus heal targets` de
  playerbots mas su estrategia. **Faltaba el boton, no la funcion.**
- **§5 el segundo click en el mundo 3D**: `Skills:Aiming()`/`AimAt` mas el
  gancho de `RTSMode:OnLeftClick`, desde la etapa 5n.
- **§4.1 "ya existe una version previa que se puede reaprovechar"**: `Skills.lua`
  entero, y `Roster.lua` recuperado de git para la columna.

### EL SIM CORRIO ANTES DE ESCRIBIR UNA LINEA DE LUA, Y DECIDIO LA FORMA

`sim/hall_layout.py` encontro que **las cuatro acciones no cabian al lado de la
fila de hechizos**: puestas a su derecha competian por el ANCHO, y con `grow` 1
el reparto daba **cero botones** -- justo los cuatro que el brief llama caso de
uso prioritario. Apiladas debajo compiten por el ALTO, que es fijo y sobra, y
ademas se leen mejor.

Comprobado que la prueba tiene dientes: con `FIT_GUARD = False` las cinco
columnas con `grow` 1 salen a 17 px de dibujo en vez de rechazarse.

**§9.2 contestado con numeros**: con `grow` 4 (el que sale solo en 2560x1440 a
pantalla completa) la sala mide 2246 y las cinco columnas salen a 385 con huecos
de 90 -- holgado, y a 6 huecos siguen entrando a 57. Por debajo de `grow` 3 no
caben, y ahi **el panel lo dice y dice que hacer** en vez de esconderlas.

### LOS TIPOS DE HECHIZO LOS CLASIFICA EL SERVIDOR, Y NO PUEDE SER DE OTRA FORMA

`docs/HECHIZOS-COLA.md` es el inventario que pedia §5.1. La decision de fondo es
que **el cliente no puede clasificar un hechizo ajeno**: `IsHarmfulSpell` y
compania toman un nombre o un indice de TU libro, y el bot conoce hechizos que
tu no. Lo unico que el cliente sabe de un id ajeno es lo que `GetSpellInfo` saca
del DBC, que no incluye si necesita objetivo ni si es amistoso.

Asi que `BARS` devuelve `id:letra` y `SpellInfo` decide la letra con siete
predicados que el nucleo ya tiene escritos (`IsPassive`, `Totem[]`,
`IsRequiringDeadTarget`, `TARGET_FLAG_DEST_LOCATION`, `IsSelfCast`,
`NeedsExplicitUnitTarget`, `IsPositive`). **En el addon no hay ninguna tabla de
hechizos.** Es la regla de `nameplateMaxDistance` llevada al extremo: en vez de
comprobar la constante, no tener constante.

Tres hallazgos que habrian costado una ronda cada uno:

- **UN HECHIZO DE MASCOTA NO SE LANZA: ENCIENDE SU AUTOCAST.**
  `PlayerbotAI::CastSpell` empieza con `if (pet && pet->HasSpell(spellId))`, y
  en ese caso alterna el autocast de la mascota, susurra al maestro y
  **devuelve `true`**. Un hueco con uno de esos en un cazador seria un boton que
  no lanza, que reporta exito, y que ademas alterna: en pantalla, "ese boton
  funciona a veces". Se filtran en `ActionBarSpells`, que es donde se sabe que
  mascota tiene el bot ahora mismo.
- **LOS HECHIZOS DE AREA NO NECESITAN UN CLICK EN EL SUELO.** `CastSpell` hace
  `targets.SetDst(*target)` para los de `TARGET_FLAG_DEST_LOCATION`, o sea que
  apuntando a una unidad el hechizo cae DONDE ESTA esa unidad. Lluvia de fuego
  sobre el lobo es "apunta al lobo". Y para un punto pelado existe ya el
  overload `CastSpell(id, x, y, z)` (`PlayerbotAI.h:520`). Simplifica §5.1
  entero.
- **LA SELECCION DEL BOT SOLO SE DEVUELVE SI EL LANZAMIENTO SALE.** `CastSpell`
  guarda `oldSel`, escribe la nuestra, y restaura **solo al final** -- o sea que
  si falla se queda con la nuestra, y si el bot no tenia nada seleccionado no se
  restaura nunca. **Corrige lo que este fichero decia de la etapa 5n**
  (*"`CastAs` no escribe la seleccion del bot"*): si la escribe.

### LA COLA: LO QUE MAS LA JUSTIFICA NO ES EL CASTEO

`RtsQueue.cpp`. El brief pide que pulsar un hechizo con el personaje ocupado lo
deje esperando en vez de fallar, y eso no se puede hacer desde el cliente: quien
sabe si el hueco esta libre es el servidor, y la respuesta cambia varias veces
por segundo.

Pero el caso que de verdad lo justifica es otro: **`PlayerbotAI::CastSpell`
empieza levantando al bot si esta sentado y devuelve `false`**. O sea que el
PRIMER click sobre un bot que esta comiendo SIEMPRE falla. Sin cola eso se lee
como "los botones no funcionan cuando descansan", y funcionando a la segunda,
que es peor de diagnosticar.

**Y UNA COSA QUE LA COLA TIENE QUE NO HACER: ANCLAR AL BOT.** `CastAs` llama a
`StopMoving()` en cada intento -- hace falta, moverse cancela un casteo y
`passive` permite `follow` a proposito. Pero reintentar cada 400 ms sobre un
objetivo lejano lo pararia cada 400 ms y **no podria acercarse nunca**: la cola
convertiria "espera a tenerlo a tiro" en "quedate quieto para siempre". Estando
fuera de alcance no se intenta nada. Es la unica comprobacion que la cola hace
por su cuenta, y existe porque es la unica que cambia lo que la cola HACE en vez
de lo que dice.

Dos plazos: **8 s** para los que piden objetivo (esperan a que vuelva a rango),
**3 s** para los que no (solo pueden estar esperando un enfriamiento). Al vencer
**se dice cual y por que**, porque una orden que desaparece sin mensaje es
indistinguible de una que nunca se dio.

Lo que NO se puede saber, dicho por delante: `PlayerbotAI::CastSpell` devuelve un
bool, asi que no hay forma de separar "el global, vuelve en un segundo" de "le
faltan reagentes". Se dice reintentable y **es el plazo quien descarta**.
Reimplementar `Spell::CheckCast` aqui seria escribir una segunda version de una
regla del juego que ya existe.

### LA LUZ CIRCULAR ES DEL CLIENTE Y SALE GRATIS

El brief pide el efecto de autocast de las mascotas. No hay que dibujarlo, y
esto salio de **leer el FrameXML del cliente**, que desde la etapa de la barra de
postura es una herramienta y no una idea: `AutoCastShineTemplate`
(`UIPanelTemplates.xml:699`) es una plantilla virtual corriente,
`AutoCastShine_AutoCastStart(frame)` la enciende, y **la animacion la mueve
`UIParent` en su propio `OnUpdate`** recorriendo todas las encendidas.

Dos trampas silenciosas: **el frame TIENE que tener nombre** (`OnLoad` busca sus
16 chispas con `_G[name..i]`; sin nombre no da error, no dibuja), y hay que
**redimensionarlo al boton** porque el recorrido de la animacion es
`self:GetWidth()`.

### LAS RUNAS NO SE PUEDEN ENSENAR, Y ESO SE DICE EN VEZ DE FINGIRLO

El brief pide "pet, runas... lo que corresponda a esa clase". La mascota si
(`party1pet`), y el objetivo del bot y el objetivo de su objetivo tambien
(`party1target`, `party1targettarget` son unidades validas en 3.3.5a, asi que los
tres marcos salen del cliente sin un solo mensaje).

Las runas **no**: `GetRuneCooldown(i)` y `GetRuneType(i)` de 3.3.5a no toman
unidad -- son siempre las TUYAS. Dibujar seis rombos con tus runas bajo el marco
de otro seria un dato falso con pinta de bueno, que es el modo de fallo que este
proyecto persigue desde la etapa 5i. Si se quieren de verdad es un verbo de
mod-rts.

### LA REJILLA 4x4 PIERDE SU DOBLE ALCANCE

Del 24 de agosto al 4 de septiembre tuvo dos: a la seleccion si habia algo
cogido, al grupo si no. Estaba pensado y senalizado (etiqueta azul y "-> N
seleccionada(s)" en el tooltip). §6 y §8 del brief lo cierran al reves: **siempre
a todo el grupo**.

Y tiene sentido con la consola nueva delante, que es lo que ha cambiado: **ahora
hay un sitio donde mandar a UNO** -- los cuatro botones de accion de la sala.
Antes no lo habia, y por eso la rejilla hacia las dos cosas. Cinco casillas no
son ordenes y se quedan igual (Formar, Salir, Control y las dos marcas).

### EL BOCETO CAMBIO LA FORMA, Y EL BRIEF ESCRITO SE QUEDO CORTO

Llego un boceto a mano despues del brief, y manda el boceto porque describe la
FORMA y no solo la cuenta. Cuatro cambios:

- **Diez huecos de hechizo** en el estado A, en una sola fila, no cuatro.
- **Los botones de accion son MACROS**: barras anchas con el nombre escrito, no
  iconos cuadrados.
- **Estado B: 2x2 de hechizos y 2 macros** por columna, no una fila.
- Una raya divisoria bajo los marcos, y el tercer marco mas pequeno.

**UN ICONO SE RECONOCE Y UN MACRO SE LEE**, y esa es la razon de que haya dos
widgets y no un `W:Button` mas largo. Un hueco de hechizo lleva el mismo dibujo
que la barra de acciones de siempre; un macro es algo que el jugador ha puesto
ahi y puede cambiar manana, asi que su nombre va delante y el icono queda de
pista.

`W:Wide` **ancla el texto a los dos lados en vez de darle un ancho**, y eso no
es estilo: un `FontString` de ancho fijo en 3.3.5a **no recorta, parte en dos
lineas** y deja la segunda a medias contra el borde (`SetWordWrap` no existe).
Es la misma trampa que ya costo los nombres de la fila de enemigos en la etapa
5n.

**LOS DIEZ Y EL 2x2 SON LA MISMA CONFIGURACION.** El 2x2 son los huecos 1..4 de
esos mismos diez, y los dos macros del estado B son los dos primeros de los
cuatro. Guardar dos listas por personaje habria sido dos sitios donde configurar
lo mismo, y el jugador descubriendo en combate que el hueco 2 no dice lo mismo
segun cuantos lleve cogidos.

**Y EL SIM VOLVIO A CAZAR ALGO AL CAMBIAR LA FORMA**: con diez huecos, la fila
deja de caber con `grow` 1 -- la zona de contenido mide 438 y diez huecos al
minimo necesitan 472. Se esconde y se dice, igual que las columnas. Sin el guion
se habria visto en juego como "los hechizos han desaparecido".

La unica desviacion del boceto, dicha a proposito: **los macros del estado B
ocupan la columna entera** y no el ancho del bloque 2x2. En el papel coinciden;
con las proporciones reales el bloque mide 214 dentro de una columna de 385, o
sea 171 px de hueco muerto por columna, y un macro es una barra de TEXTO que se
lee mejor cuanto mas ancha.

### Lo demas que conviene retener

- **El click derecho sobre una fila hace PRIMARIO sin seleccionar**, que recupera
  el gesto del video (*"the command bar for the next person WITHOUT
  deselecting"*) que vivia en Tab hasta que se pidio quitarlo en 0.52.0. El
  concepto se quedo entonces y el gesto se fue; desde entonces la unica forma de
  ver los hechizos de alguien era seleccionarlo a el solo, o sea soltar al grupo.
- **`Link:ServerAtLeast(minor)` es nuevo** y hace falta: un verbo que el servidor
  no conoce **no da error, no contesta**, o sea un boton que no hace nada. Con un
  mod-rts anterior a 0.36.0 se manda `CAST` en vez de `CASTQ` -- sin cola, pero
  funcionando.
- **Las dos direcciones de `BARS` degradan a lo de antes.** Un addon viejo lee
  `id:letra` con `tonumber` y se queda con el numero; un mod-rts viejo manda solo
  el numero y el addon nuevo lo trata como el tipo seguro. Ninguna de las dos se
  queda muda.
- **`RTSCommandDB.skills` se sigue tirando al cargar**, y que la clave nueva sea
  otra (`RTSCommandDB.hall.who`) es lo que deja hacerlo sin pensarlo:
  reutilizarla habria hecho que el primer arranque tras actualizar leyera huecos
  de un formato que ya no es. Cuarta purga, despues del `grow = 688`, el
  `camHold` y el `railCropGen`.
- **`Bar.lua` sigue sin nombrar a ningun modulo de contenido.** La sala gano
  `host = true` y nada mas; `Hall` se apunta con `B:Register` y `Party`,
  `Frames` y `Cast` con `H:Register`. El contrato que la revision de
  arquitectura §12 marca como intocable se copia, no se inventa.
- **`Un .cpp nuevo no entra solo`**, otra vez: `RtsQueue.cpp` necesito
  `cmake C:\Server\build` antes de compilar. Comprobado con
  `Select-String -Path C:\Server\build\modules\modules.vcxproj -Pattern RtsQueue`
  antes de esperar los trece minutos, que es la comprobacion barata que esa
  leccion dejo escrita.
- **Y el shell se comio las barras invertidas otra vez**, en el primer intento de
  parchear `Panel.lua` desde un heredoc. La regla practica sigue siendo la misma
  y ya sin excusa: **para tocar codigo con escapes, fichero y editor -- nunca una
  cadena del shell.**

## El crash del servidor era una referencia que sobrevivio a su nodo, 2026-09-05

Addon **0.77.0**, mod-rts **0.37.0** (hay que reiniciar el servidor). Lo que dijo
`PRUEBAS-23`: la sala funciona casi entera, y *"si pulso algunos hechizos durante
un rato se cuelga el juego y el servidor se para"*.

### La causa, y por que el sintoma no apuntaba a ella

`CastAs` cogia una referencia al nodo del maestro (`Borrowed& b =
g_borrowed[...]`), llamaba a `Release()` -- que hace `g_borrowed.erase(it)` sobre
**ese mismo nodo** -- y seguia escribiendo en `b`: el guid, `suppressed`, los dos
`wasPassive*` de `Suppress` y `sinceLastCast`. Unos treinta bytes sobre memoria
liberada, **cada vez que lanzabas un hechizo por un bot distinto del anterior**.

Eso es machacar el monton, no caerse. El servidor seguia un rato y moria en otro
sitio. Los dos volcados del dia dicen lo mismo: `ACCESS_VIOLATION` en
`std::string::_Tidy_deallocate` (RVA 0x14B462) con la capacidad a 0x100000000 y
el puntero valiendo texto suelto -- `"log"` en uno, `"guild de"` en el otro.

**SIN SIMBOLOS Y CON SEIS LINEAS BASTO PARA LEER EL VOLCADO.** `worldserver.exe`
se compila sin PDB, asi que la pila del informe son direcciones. Pero el informe
da `seccion:desplazamiento` y `pefile` + `capstone` desensamblan el binario que
YA ESTA en disco:

```python
rva = 0x14A462 + 0x1000            # seccion 1 empieza en 0x1000
```

Las diez instrucciones de alrededor eran el destructor de `std::string` de MSVC
(`_Myres > 15` -> liberar, `> 0xFFF` -> leer la cabecera en `[ptr-8]`), y el
registro que fallaba llevaba texto en vez de un puntero. Con eso la pregunta deja
de ser *"¿donde se cae?"* y pasa a ser *"¿quien escribe en un bloque liberado?"*,
que se contesta leyendo, no probando.

**La regla, que este proyecto ya paga en otros sitios:** una referencia a un nodo
de un contenedor no sobrevive a una llamada que pueda tocar ese contenedor. Se
suelta primero y se coge despues. `queue::Update` y `swap::Update` ya iteraban
sobre una copia de las claves por haberlo pagado; `command::Update` no, y ahora
si -- no porque falle hoy, sino porque es la misma forma.

### El casteo que empezaba y se cortaba: parar de moverse no basta

`PRUEBAS-23` C6, y ya se habia "arreglado" en la etapa 5o. `CastAs` llamaba a
`StopMoving()`, que corta el paso que el bot lleva **en ese instante**. Lo que no
puede es impedir que su IA le mande otro medio segundo despues -- y se lo manda,
porque `passive` lleva "follow" en su lista de partes permitidas a proposito
(`PassiveMultiplier.cpp`). O sea: necesario y no suficiente, exactamente como el
FOV de la etapa 7b.

Ahora, tras un lanzamiento con tiempo de casteo, se le calla la IA ese tiempo mas
300 ms (`SetNextCheckDelay`, publica en `PlayerbotAIBase`, el mismo mando que
playerbots se aplica a si mismo tras un GCD). A un instantaneo no se le calla:
seria quitarle medio segundo de pelea por nada.

**El arreglo anterior se dio por bueno porque el sintoma se movio, no porque
desapareciera.**

### "Neferite no tiene spells": tu heroe tenia su propio camino, y era el malo

`ActionBarSpells` pasaba por `ResolveBot`, que **rechaza a proposito que te
resuelvas a ti mismo** -- correcto para no mandarte ordenes de bot, y equivocado
para una LECTURA. Con tu heroe de primario, `BARS` contestaba vacio y el addon
caia a `MyBar()`, que lee tus casillas con `GetActionInfo`... cuyo segundo valor
puede ser el indice del libro en vez del id. La defensa contra eso (contrastar el
icono dibujado) es correcta y **tira la lista entera** cuando pasa: un personaje
sin un solo hechizo y ningun error.

Dos caminos para la misma pregunta y el propio era el malo. Ahora tu personaje
pasa por el servidor igual que los demas; `MyBar()` se queda solo como respaldo
sin mod-rts.

### De donde salen los hechizos: la pregunta tenia respuesta, y no la supuesta

*"¿son los de mi barra o los de playerbot? me gustaria que fueran los de
playerbot porque va actualizando"*.

**Playerbots NO TIENE una lista de hechizos que consultar.** Su IA elige accion
por accion, en el momento, y no guarda ningun catalogo -- asi que "los de
playerbot" no existe como fuente. Lo que si existe y ademas hace lo que se pedia
(crecer solo segun el personaje sube) es **su libro de hechizos**, que el nucleo
mantiene.

`BARS` manda ahora las dos mitades: su barra de acciones primero, en el orden en
que esta puesta -- es la lista curada y sigue siendo la que llena los huecos por
defecto -- y detras todo lo demas que sepa, por nombre.

**`Active` HACE EL TRABAJO DE FILTRAR RANGOS**, y lo dice el nucleo en su propio
comentario (`Player.h:130`): *"lower rank of a spell are not useable, but
learnt"*. O sea que no hay que recorrer cadenas de hechizos a mano, que seria
escribir una segunda version de una regla que ya existe. Se filtran ademas
pasivos, oficios, idiomas y los de mascota.

**Y la lista pasa de doce a cien, asi que el desplegable va por paginas.** Sin
eso se dibujaria de tres mil pixeles de alto y en juego se leeria como que no
sale -- que es el fallo silencioso de siempre, esta vez previsto en vez de
pagado.

### Las medidas, que las decidio la pantalla

Tres quejas de la ronda, y las tres eran de proporcion:

- **112 de dibujo son 63 px, o sea EXACTAMENTE un boton de accion del cliente.**
  Suena bien y en pantalla no lo era: al lado de unas filas de grupo de 36 px y
  unos marcos de 54, el icono de hechizo era la pieza mas grande de la consola.
  Bajado a 84 (47 px). *"Los iconos son puto enormes"*.
- **12 de dibujo de separacion son SIETE PIXELES**, que no separa nada -- de ahi
  *"la seccion central muy pegada a las barras de los 5 jugadores"*. El `GUTTER`
  pasa a 48 (27 px). La leccion se repite: **un numero en unidades de dibujo hay
  que dividirlo por dos antes de opinar sobre el**, y es el mismo error que dejo
  las guias ilegibles en la etapa 5l.
- **Los marcos de unidad median 84 de alto (47 px)** para meter retrato, nombre,
  vida, poder y mascota. El marco de jugador del propio cliente mide 100 px, que
  es la medida que el jugador tiene calibrada en la retina -- misma regla que
  hizo que el alto de la barra se calcara de `ActionButton1`. Ahora 120.

**Y el hueco que sobra se centra en vez de quedarse a la derecha.** Con los
iconos mas pequenos la fila de diez mide 912 dentro de 1758: pegada a la
izquierda deja 846 vacios, o sea media consola con pinta de descuadre. Las tres
bandas (marcos, hechizos, macros) comparten eje ahora. Es lo que contesta
*"administrar correctamente el espacio"* sin volver a agrandar los iconos, que
es lo que se acababa de quitar.

`sim/hall_layout.py` lleva las medidas nuevas y **dos comprobaciones mas**: que
el bloque este centrado de verdad (con el centrado quitado falla en los cinco
`grow`, comprobado) y que ni el icono ni la separacion pasen de sus limites *en
pixeles de pantalla*, que es la unidad en la que se vio el fallo.

### Los dos gestos que se van

- **El click derecho sobre una fila del grupo ya no hace primario.** `PRUEBAS-23`
  A5, `[!]`: *"¿para que iba a querer yo eso?"*. Se quita el GESTO, no el
  CONCEPTO: el primario sigue decidiendo de quien son los hechizos y ahora lo
  pone unicamente la seleccion. Es la segunda vez que este concepto se queda sin
  gesto propio, despues de Tab en la 0.52.0.
- **Los macros pierden el icono.** *"No quiero los botones con icono, seran
  textos"*. El icono seguia en la tabla de acciones y ahi se queda, porque el
  desplegable de eleccion si lo usa: once opciones en una lista vertical y el
  dibujo ayuda a encontrarlas. Misma pieza, dos sitios, dos respuestas -- y esta
  bien que sean distintas.

## La sala contra el boceto retocado, 2026-09-05 (tarde). Addon 0.78.0

Llegaron dos capturas -- la de la consola tal cual y una version retocada -- con
el encargo de implementar la segunda. Es la primera vez que la referencia de
diseno es una IMAGEN del propio juego y no un dibujo a mano, y eso cambia como se
trabaja: **las medidas no se eligen, se miden**.

### Se mide con un script, y eso es lo que hace que la comparacion valga

`pefile` sirvio para leer un volcado sin simbolos por la manana; `PIL` sirve para
esto. Las dos capturas se cargan, se buscan los bordes por color y salen numeros:
la columna, la separacion, el lado del icono, el paso entre iconos, el ancho del
macro, el alto de la banda, la extension de la raya.

**Lo importante es la CALIBRACION, que es donde se falla.** Las dos imagenes no
estan a la misma escala (1998x359 contra 1995x367), asi que comparar pixeles a
pelo miente. Se calibra cada una contra algo de tamano conocido -- la fila de
huecos, que son `10*84 + 9*8` de dibujo en la original -- y a partir de ahi todo
se convierte a unidades de dibujo, que es en lo que esta escrito el addon.

Con eso hecho, la primera medida ya contesto una pregunta que llevaba abierta:
**la captura "original" es la 0.77.0 tal cual**, porque la columna sale a 437 de
dibujo y ese numero solo existe desde anoche.

### Cuatro cosas que la imagen dice y una que NO dice

Medido, no interpretado:

| | original | retocada |
|---|---|---|
| columna de personajes | 276 px | **168 px** |
| separacion columna/centro | 27 px | **44 px** |
| lado del icono | 53 px | 52 px (igual) |
| separacion entre iconos | 5 px | **9 px** |
| separacion entre macros | 6 px | **18 px** |
| huecos en la fila | 10 | **13** |
| bloque | centrado | **pegado a la izquierda** |
| la raya horizontal | toda la zona | **lo que el bloque** |
| borde en los macros | no | **si, 1 px** |

Y la que NO dice, aunque lo parecia: **el texto de la columna es EXACTAMENTE el
mismo tamano en las dos**. La primera medicion decia que habia encogido un 20% y
era ruido -- la ventana de medida se comia parte de la barra de vida, que es
brillante. Se caza midiendo la altura de las mayusculas en vez del ancho de la
linea: 11 px en las dos.

Merece la pena porque la conclusion equivocada era accionable y mala: habria
bajado la fuente que se acababa de subir por "texto muy pequeno".

### LA COLUMNA SE ESTRECHA Y ESO NO CONTRADICE "LOS PLAYER FRAMES MUY PEQUENOS"

Anoche se subio de 260 a 440 por esa queja. Hoy baja a 272, que es casi el valor
de antes, y hay que decir por que no es dar marcha atras:

**lo que no se leia era el TEXTO, y el texto sube y se queda arriba.** Ensanchar
ademas la columna no hizo la letra mas grande -- dejo `Secretaria  3 134`, que
son 114 px de texto, flotando en una fila de 276 px con la mitad vacia. A 168 px
el mismo texto llena su sitio y se lee igual. Los 168 px que sobran se los queda
el centro, que es donde hacian falta.

**Ensanchar un contenedor no agranda su contenido.** Es un error facil de cometer
porque las dos cosas se sienten como "hacerlo mas grande".

### EL TAMANO ERA FIJO Y LA CUENTA VARIABLE; AHORA ES AL REVES

Es el cambio de fondo del boceto y el unico que no es un numero. Hasta hoy la
fila tenia DIEZ huecos y el lado se calculaba para que cupieran. Ahora **el lado
es fijo (84) y la CUENTA se calcula** hasta llenar el ancho: catorce con la barra
que sale sola, diecinueve con la mas ancha, tres con la mas estrecha.

Se llego ahi por descarte, y las alternativas conviene dejarlas escritas porque
las dos parecen razonables hasta que se les pone el numero:

- **Diez fijos y estirar los huecos** hasta llenar: 124 de dibujo, o sea 76 px.
  Es volver a los "iconos puto enormes" de ayer por otro camino.
- **Diez fijos y estirar la separacion**: 60 de dibujo entre iconos de 84, o sea
  37 px de aire entre botones de 47. Una fila de sellos sueltos.

El precio esta dicho por delante: la cuenta depende del ancho de la barra, asi
que estrechar la barra esconde los ultimos huecos. **Lo guardado no se pierde**
-- la configuracion es por indice y vuelve al ensanchar -- y `K.MAX_SLOTS` sube a
20 porque *un hueco dibujado que no se puede guardar es un boton que acepta un
hechizo y lo olvida al recargar*.

Y `/rts hall slots <n>` cambia de significado: era "cuantos hay", ahora es "como
mucho cuantos". **Un 10 guardado se descarta al leerlo**, porque en rango sigue
siendo valido pero ahora TOPA una fila que podria ensenar catorce -- y eso no da
error, solo deja la fila corta sin motivo visible. Quinta purga de
SavedVariables, despues del `grow = 688`, el `camHold`, el `railCropGen` y la de
la sala.

### CENTRAR ERA CORRECTO AYER Y ES INCORRECTO HOY

La 0.77.0 centro el bloque porque la fila de diez dejaba 846 de dibujo vacios a
un lado. En cuanto la fila llena el ancho no hay nada que repartir, y entonces
centrar solo puede descuadrar: **el borde izquierdo de los marcos, el de la raya,
el del primer hueco y el del primer macro son el mismo**, y esa columna de bordes
alineados es lo que hace que la zona se lea como un bloque.

El centrado de los marcos ademas tenia un defecto propio que la imagen dejo ver:
media el ancho de los TRES marcos aunque dos estuvieran escondidos por no tener
el bot objetivo, asi que el marco visible se movia segun el bot estuviera
peleando o no. Un centrado que depende de un dato de juego no es un centrado.

### Lo demas

- **La raya horizontal mide lo que el bloque**, no toda la zona. Una raya que
  sobresale por la derecha de todo lo que separa se lee como un borde suelto.
- **Los macros recuperan un borde fino** -- dos texturas, no cuatro rayas: la de
  abajo ocupa el boton con el color del borde y la oscura se mete dos dentro. Al
  quitarles el icono ayer, cuatro rectangulos oscuros sobre un panel oscuro se
  leian como huecos; el borde es lo que los devuelve a botones.
- **Se le reservan 88 de dibujo al numero de la fila** en vez de 60. Con la
  columna estrecha, `80 12k` a fuente 22 se comia el final del nombre -- y un
  `FontString` de ancho fijo en 3.3.5a **no recorta, parte en dos lineas**, asi
  que el sintoma habria sido "a veces falta media letra".
- **Una raya vertical entre cada dos seleccionados**, pedida aparte. Va en el
  centro del hueco que ya los separaba y se queda corta arriba y abajo: pegada a
  una columna se lee como su borde, y la asimetria se nota antes que la raya.

### El sim gano cuatro comprobaciones y las cuatro tienen dientes

Probadas rompiendo el codigo a proposito, una por una: centrar en vez de alinear
a la izquierda (8 fallos), pegar la raya vertical a la columna (16), quitar el
minimo de los macros (1) y volver a diez huecos fijos (3).

Y encontro algo antes de compilar: **con `grow` 5 el tope de 20 es el que manda y
sobran 424 de dibujo**. Es correcto y deliberado, no un fallo -- pero la
comprobacion de "llena el ancho" lo daba por malo. Sin distinguir los dos casos,
la unica decision deliberada del reparto salia en rojo, que es como se le deja de
hacer caso a un guion.

### Los tres ajustes de la ronda de la tarde, y el bug que salio de paso. Addon 0.79.0

Vistos en juego los tres retoques que se pidieron mirando la consola:

- **El bloque llegaba al borde del arte.** Con la fila llena, el ultimo hueco y
  el ultimo macro acababan pegados al marco -- se lee como recortado, no como
  ajustado. Se le quita `GUTTER` tambien por la derecha, o sea el mismo aire a
  los dos lados. **Y sale un numero bonito de regalo: la fila pasa a TRECE
  huecos, que es exactamente lo que tenia el boceto retocado.** El margen que
  faltaba era el que hacia que mis catorce no cuadraran con sus trece.
- **Los marcos de unidad iban pegados al borde de arriba.** Bajan 14. No crece
  `TOP_H` para hacerles sitio: la banda ya tenia 20 de sobra sobre los 120 que
  mide el marco, o sea que el aire estaba puesto y solo estaba en el lado que no
  era.
- **La columna del estado B era un bloque solido.** Nombre pegado al borde, 2x2
  pegado a los macros y los dos macros pegados entre si. Bajan 18 y se separan
  26 y 12. **El precio esta en el icono y es donde tenia que estar**: el alto de
  la sala es fijo, asi que los 46 de aire salen del cuadrado, que baja de 84 a
  78.

`sim/hall_layout.py` gana cuatro comprobaciones mas -- el aire a la derecha, que
la columna baje, que el 2x2 no toque los macros y que los macros no se toquen --
y las cuatro se probaron rompiendolas.

### Y EL BUG DE VERDAD: `UnitClass("player")` MIENTE IGUAL QUE `UnitName`

Reportado con la prueba delante: tras saltar a Bob, que es MAGO, su fila salia
con el color del GUERRERO y el marco central decia "Neferite" sobre el retrato,
la vida y los hechizos de Bob.

La mitad del nombre estaba documentada desde la 0.62.0. La otra mitad no, y se
cerro desensamblando en vez de suponiendo. `UnitClass` esta en `0x0060FEC0` y
hace lo mismo que `UnitName` instruccion por instruccion:

```
0060FF05  push 0x9F6F4C        ; "player"
0060FF0B  call 0x76E780        ; strcmpi(unidad, "player")
0060FF12  jne  0x60FF55        ; NO lo es -> mirar el objeto
0060FF14  call 0x6B1080        ; SI lo es  -> la ficha estatica
```

Y `0x006B1080` son dos instrucciones: `mov al, byte ptr [0xC79E89]` / `ret`.

**Los tres getters son vecinos, y eso es el hallazgo:**

| Lua | getter | dato |
|---|---|---|
| `UnitName("player")` | `0x006B1060` | `0x00C79D18` (cadena) |
| `UnitClass("player")` | `0x006B1080` | `0x00C79E89` (byte) |
| `UnitRace("player")` | `0x006B1090` | `0x00C79E8A` (byte) |

O sea que **la regla es mas amplia de lo que decia la 0.62.0**: no es que el
NOMBRE de "player" se quede rancio tras un cambio -- es que **nombre, clase y
raza mienten los tres**, porque son los tres campos que el cliente guarda en una
ficha aparte, rellenada por la pantalla de seleccion de personaje. Todo lo demas
sale del objeto y es correcto.

Esa mezcla es lo que hacia el sintoma ilegible: **retrato de uno y nombre del
otro en el mismo marco**. Un fallo que fuera todo o nada se habria diagnosticado
en un minuto.

**Como se localizaron las funciones, que es reutilizable.** El cliente registra
sus funciones de Lua en una tabla de pares `{const char*, void*}`. Buscando la
cadena `"UnitClass"` en el binario, luego su direccion como dword, y leyendo los
cuatro bytes siguientes, sale el puntero. Se valido contra `UnitName`, que ya
sabiamos que estaba en `0x0060E740` -- **una tecnica nueva se estrena sobre algo
cuya respuesta ya se conoce, o no se sabe si lo que devuelve es verdad.**

#### El arreglo: la clase se aprende del grupo

No hace falta ni un verbo nuevo ni una tabla de ids de clase escrita a mano (que
es justo la clase de constante que este proyecto paga cara). **El personaje al
que saltas era companero tuyo un segundo antes**, y para un `partyN` el cliente
si mira el objeto -- asi que su clase ya se leyo bien. `Selection:GetRoster` la
apunta al pasar, y `ns.MyClass()` la busca por el nombre que da `ns.MyName()`.

Sin entrada aprendida cae a `UnitClass("player")`, que es correcto mientras no
haya habido un cambio, o sea en una sesion normal.

**Se guarda en disco, y eso no es opcional:** lo aprendido vive en memoria, y un
`/reload` lo perderia -- y tu propio personaje no aparece en tu grupo, asi que no
hay de donde reaprenderlo. Peor: un `/reload` es lo primero que se hace cuando
algo se ve raro, o sea exactamente el gesto que reintroduciria el fallo. Se puede
persistir sin pensarlo porque **la clase de un personaje no cambia nunca**: una
entrada vieja no se queda obsoleta, solo sobra. Es lo contrario del `grow = 688`
y del `camHold`.

`ns.IsMe(unit)` y `ns.UnitLabel(unit)` salen de aqui: preguntar "¿este token soy
yo?" por GUID y nunca por nombre es la regla de la 0.60.0, y ahora tiene un solo
sitio donde vive.

`/rts whoami` imprime ahora las DOS respuestas, la del cliente y la nuestra. Si
difieren, hubo un cambio y la correccion esta actuando.

#### La cura de raiz sigue sin hacerse, y ahora es mas barata

`rts_core` escribiendo `0x00C79D18` (nombre) y `0x00C79E89` (clase) haria que
`UnitName`, `UnitClass` y todo lo que cuelgue de ellos dijeran la verdad, y
sobrarian `ns.MyName`, `ns.MyClass` y el repintado del marco de Blizzard. Lo que
frenaba era que el canal DLL es un entero empaquetado y el nombre es una cadena
-- pero **la clase es UN BYTE y cabe de sobra**. Queda apuntado; se hace el dia
que aparezca un tercer sintoma de la misma ficha, que muy probablemente sera la
raza.

## Un aro por unidad, y el "bug de Kirinah" que era el largo de un mensaje. 2026-09-06

Addon **0.82.0**, rts_core **0.12.0**. mod-rts sin tocar.

El DLL hay que reinyectarlo (cerrar el cliente y relanzar con `2-Jugar.bat`) y
**no se puede ni recompilar con el cliente abierto** -- `LNK1104` sobre
`rts_core.dll`, que es la misma familia que el `injector.exe` huerfano y con la
misma pinta de fallo de compilador. Lo unico que hace la 0.12.0 sobre la 0.11.0
es liberar el bit 30; el addon 0.82.0 ya no lo manda, asi que con el DLL viejo
delante el resultado es el mismo.

### Los aros se apilaban, y el jugador lo diagnostico solo

*"¿ves que la seleccion del mundo se ve mas brillante? es porque se apilan la
del RTS y la del mundo."* Exacto, y el codigo lo confirma sin ambiguedad: el
`colour` que `circle::Set` recibe **no se usa** -- el gancho no hace nada de
color -- asi que nuestro aro y el nativo son LA MISMA llamada de dibujo. La
unica diferencia posible entre los dos era **cuantas veces se dibuja**.

De ahi salen los tres sintomas de una sola causa:

- una unidad que era a la vez tu objetivo y seleccion RTS se llevaba dos
  pasadas y salia mas marcada que sus companeros;
- cambiando la seleccion desde la consola, el que era tu objetivo **conservaba
  su aro nativo** y quedaban dos unidades con pinta de seleccionadas;
- y las dos formas de seleccionar -- pinchar en el mundo (que ademas apunta) y
  pinchar en la consola (que no) -- se veian distintas haciendo lo mismo.

**No se arregla apagando lo nuestro sino lo del cliente, y la razon es que
apuntar no se puede tocar desde Lua.** `TargetUnit` y `ClearTarget` estan
protegidas en 3.3.5a -- ya costo una etapa descubrirlo (5h) -- asi que "que la
consola apunte tambien" y "que la consola desapunte" son las dos imposibles. Lo
que si se puede es que el DLL no deje dibujar el aro nativo.

`Circle.cpp` lo hace en tres instrucciones, ANTES de dejar correr el original:
si nuestra tabla no esta vacia y la ranura del objetivo (`ctx+0x380`) tiene un
guid de **jugador**, la pone a cero. Un guid de jugador tiene el dword alto a
cero y el de una criatura vale `0xF130xxxx`, asi que **una comparacion separa
"un amigo, que lo lleva la capa RTS" de "el bicho al que estoy pegando"** -- sin
mirar reacciones y sin recorrer ninguna lista. El aro de un enemigo apuntado se
queda como estaba, que es del juego y no nuestro.

La ranura del **mouseover** (`ctx+0x388`) se deja a proposito: dice donde esta
el puntero, no que hay seleccionado.

**Y LA OTRA MITAD DE LA PETICION SE INTENTO, DURO UNA TARDE Y LA DESMINTIO EL
JUEGO EN EL PRIMER VISTAZO.** El encargo decia *"si tengo que elegir, quiero el
estilo de la seleccion del mundo"*, o sea el aro mas marcado; y como esa marca
salia de dos pasadas apiladas, la respuesta parecia obvia: dibujar el nuestro
dos veces. Se hizo, con su bit 30 y su interruptor.

En pantalla **no da un aro mas marcado: da DOS AROS**, claramente separados.
Las dos pasadas no caen una encima de otra, y ninguna lectura del codigo lo
decia -- porque el codigo solo dice que es la misma llamada, no donde acaba
dibujando.

Es **la leccion de la etapa 5e otra vez, y esta vez me la salte entera**: una
lectura estatica convincente sobre algo VISUAL vale una prueba barata en juego,
no un valor por defecto. Lo caro no fue el codigo -- media hora -- fue que salio
como comportamiento de fabrica, asi que el primer contacto del jugador con la
ronda fue un fallo nuevo puesto por mi encima de un arreglo que si funcionaba.

Quitado **de los dos lados**, no apagado por defecto: el bit 30 vuelve a estar
libre y un DLL que siguiera entendiendolo seria una trampa plantada para quien
gaste ese bit despues. Con el se va `/rts ring bright` y la clave `bright` se
tira al leer las SavedVariables -- sexta purga de este addon, despues de
`grow = 688`, `camHold`, `railCropGen`, las de la sala y `slots`.

**Y el arreglo de verdad no necesitaba el peso para nada.** Apagar el aro nativo
del objetivo cuando es un jugador es lo que quita el apilado Y el segundo
personaje encendido; el peso era decoracion encima.

### EL "BUG DE KIRINAH" NO ERA DE KIRINAH: ERAN 258 CARACTERES

*"Selecciono al grupo entero y mando atacar y no atacan. Si la quito a ella,
atacan. Si la selecciono a ella sola, ataca."*

Un mensaje de addon de 3.3.5a viaja dentro de uno de chat de 255 caracteres:
`prefijo` + tabulador + cuerpo, o sea 251 utiles con "RTS" delante. `Orders:Click`
era el unico emisor largo **sin trocear** -- `MoveBatch` si lo hacia, y su
comentario ya avisaba de esto desde que se escribio.

Las cuentas, que estan en `sim/click_len.py`:

| caso | largo |
|---|---|
| 5 unidades + ataque + rayo | **258** |
| 4 (quitando a cualquiera) + ataque + rayo | 226 |
| 5 unidades + click al SUELO + rayo | 243 |

**Quitar a cualquiera de los cinco lo bajaba de 255**; se probo con ella, asi
que parecio suya la culpa. Y la tercera fila explica por que solo fallaba el
ataque y nunca el movimiento: un click al suelo lleva `0` donde el ataque lleva
**16 digitos hex de guid de criatura**, y esos 15 caracteres son justo los que
cruzan la linea.

Tres cosas cambian:

- **`%.1f` en vez de `%.2f`** para los destinos y `%.4f` para la direccion del
  rayo: 258 -> 234. La decima de yarda no se echa de menos -- el destino se
  recorta luego contra el suelo con el rayo, y el `position` de playerbots
  redondea a yardas ENTERAS de todas formas.
- **El rayo se cae primero si no cabe**, medido contra el limite en vez de
  supuesto. Es la degradacion correcta: sin rayo el servidor usa los puntos tal
  cual, que es lo que habia antes de que el rayo existiera y sigue soportado al
  otro lado. Recortar unidades dejaria bots sin orden, o sea el fallo que esto
  arregla.
- **`Link:Send` mide y lo DICE.** Es lo que mas vale de todo esto: pasarse de
  largo no da error -- el cliente no manda nada, o manda un trozo -- y en juego
  eso se ve como "la orden no llego", que es indistinguible de diez causas
  distintas. Ahora sale el numero en el primer click. Cubre de paso a todos los
  demas emisores, que hoy son cortos y manana no tienen por que serlo.

**El sim tiene dientes**: reproduce el fallo con el formato viejo antes de
comprobar que el nuevo cabe, incluido el peor caso razonable (cinco nombres de
doce letras, que sigue sin caber y por eso suelta el rayo).

### El heroe no era un "bot parcheado": es que el cliente nunca te apunta a ti

*"Es mas dificil de seleccionar, como si tuviera que clicar en sus pies, y no se
ilumina al pasar por encima. Me gustaria que fuera un bot completo y no un bot
parcheado."*

La conversion **ya es la de playerbots**, no un apano nuestro: `/rts self` manda
`.playerbots bot self`, que es su propio comando. Lo que hace distinto al heroe
no es como se convirtio, es que **el cliente no apunta jamas a tu propio
personaje** -- ni en modo RTS ni en juego normal. De ahi salen las dos quejas a
la vez: sin mouseover no hay iluminado al pasar por encima, y sin mouseover el
click cae al tercer camino del addon, que era el mas estrecho.

**Y era estrecho por una razon concreta: se media contra los PIES.** La posicion
que publica el DLL es la del suelo, asi que la diana era un circulo alrededor de
donde pisa. Con los bots no se notaba porque ahi manda el mouseover del cliente,
que es geometria de verdad. Ahora la diana es el **segmento de los pies a la
cabeza** (dos proyecciones en vez de una) con el radio de siempre a los lados:
la forma que tiene el bicho en pantalla.

Lo que sigue sin poder ser, dicho por delante: **un personaje solo es un
playerbot de verdad cuando la sesion no lo tiene cogida**, y para eso ya existe
`/rts swap`. Mientras seas tu, tu cuerpo pasa por caminos de servidor propios
(`MoveSelf`, `SelfAttack`, `SELFCAST`) porque `ResolveBot` rechaza a proposito
que te ordenes a ti mismo por la via de los bots. Si alguna de esas rutas se
comporta distinto de la de un bot, es un fallo concreto de esa ruta y se
arregla; lo que no hay es un interruptor de "bot completo".

**Queda sin hacer y es barato: el iluminado al pasar por encima.** Seria un
codigo de estado mas en el canal empaquetado (hay tres libres de los ocho) que
el DLL pintaria como aro o brillo cuando el cursor este sobre el heroe. Son unas
cuarenta lineas y una recompilacion del DLL; no se hace hoy para no meter un
cuarto cambio visual en la misma ronda.

## El aro nativo, confirmado; y la cura que se curaba sola. 2026-09-06 (tarde)

**Confirmado en juego**: un aro por unidad, el nativo del objetivo apagado
cuando es un jugador, el click al grupo entero sale y el heroe se coge por el
cuerpo. Addon **0.84.0** con lo que dijo esa sesion.

### LO PRIMERO NO ERA UN FALLO NUEVO: ERA EL DLL SIN INYECTAR

Reportado como *"roto: puedo seleccionar varios y solo sale el aro en uno, y
ademas no se mueven"*, justo despues de una recompilacion. **La 0.12.0 no habia
corrido todavia**: `rts_core.log` no tenia ninguna sesion posterior a la hora en
que se compilo el DLL, y eso lo cierra sin discutir nada.

Los tres sintomas son **la firma exacta de rts_core ausente**, y merece la pena
tenerla escrita porque se parece muchisimo a "el addon esta roto":

| lo que se ve | por que |
|---|---|
| seleccionar varios SI funciona | la seleccion es Lua puro, no toca el DLL |
| **un** aro, siempre uno | sin lista de unidades el canal no publica nada, asi que el unico que queda es el del CLIENTE bajo tu objetivo |
| nadie se mueve | `CursorGroundPoint` sale en su primera linea con `RTS_HasCam ~= 1`; sin punto de suelo no hay orden |

Lo que queda en pie es justo lo que vive solo en Lua -- seleccion, consola,
camara -- y eso es lo que hace el cuadro tan enganoso: **la mitad que responde
es la mitad que se toca**.

**El arreglo es que el modo lo diga.** Al entrar en modo RTS sin `RTS_Ready`, el
addon avisa en rojo de que no habra aros ni ordenes al suelo y de que se abre con
`2-Jugar.bat`. Un estado degradado que no se anuncia es peor que uno que falla:
este costo una vuelta entera de mirar codigo que estaba bien.

### LA CURA SE LANZABA SOBRE EL LANZADOR, Y LA CAUSA ERA UN ATAJO CADUCADO

*"Sacerdotisa seleccionada DESDE EL MUNDO: pulso curar y se cura a si misma.
Seleccionada desde la consola: se enciende la luz, elijo objetivo y cura a quien
elijo. Quiero lo segundo."*

Dos comportamientos del mismo boton segun **como** hubieras seleccionado, y la
diferencia invisible. `Skills:Use` tenia esto:

```lua
if UnitExists("target") then ... Fire(name, s.spellId, UnitGUID("target")) ...
```

con su porque al lado: *"con un objetivo ya apuntado se manda ya, porque
preguntar cuando la respuesta esta delante es una pulsacion de mas"*.

**La premisa dejo de ser cierta cuando el raton volvio al jugador (etapa 5h).**
Desde entonces pinchar una unidad en el mundo la APUNTA -- lo hace el cliente,
no nosotros -- asi que en modo RTS el objetivo casi nunca es una intencion: es
**el residuo del gesto de seleccionar**. Y como lo que seleccionas es la
sacerdotisa, "la respuesta que esta delante" era ella misma.

Es el patron de la etapa 5h por septima vez -- *un apano en pie despues de que
desapareciera aquello para lo que estaba* -- pero con una variante que conviene
distinguir: aqui el codigo no sobro, **cambio de significado el dato que leia**.
El atajo seguia funcionando exactamente como se escribio; lo que ya no queria
decir lo mismo era `UnitExists("target")`.

Ahora se pregunta siempre. Alt sigue lanzando sobre uno mismo sin preguntar, que
es la convencion de WoW y la del video.

**Y el aviso de bando bajo con el atajo, en vez de borrarse.** Existia para
proteger un disparo a ciegas; sin disparo a ciegas ya no protege nada ahi, pero
en `AimAt` -- donde el objetivo lo acabas de elegir tu -- si dice algo util. Va
como aviso y no como bloqueo, por lo que decia su propio comentario: la
clasificacion no es infalible y quien decide de verdad es el servidor.

### Y EL CAMBIO ABRIO UN HUECO QUE SE CERRO EN LA MISMA PASADA

Preguntar siempre hace que "que la sacerdotisa me cure A MI" sea el gesto
normal... y **tu heroe no tiene mouseover nunca**, porque el cliente no apunta a
tu propio personaje (la misma causa que le hacia dificil de seleccionar esta
manana). Asi que pincharte en el mundo con un hechizo armado caia en la rama de
*"no hay nada bajo el cursor"* y **cancelaba**.

Un gesto que hace justo lo contrario de lo que pides es peor que uno que no hace
nada. Con algo armado, sin mouseover se tira de la proyeccion -- la misma
`UnitAt` del arreglo de esta manana -- y se hace **arriba, para las dos bocas
del gesto a la vez** (habilidad y boton de Cuidar). Arreglar solo una es como se
acaba con dos gestos que se parecen y no se comportan igual.

### La luz de apuntado, por encima y por fuera

Pedido *"que se vea mejor"*. Dos cosas, y ninguna es subir el brillo:

- **Nivel de frame por encima del boton.** Un frame hijo con nivel mas alto se
  dibuja sobre TODAS las capas de su padre, asi que eso es lo que saca las
  chispas de debajo del icono.
- **Un 18% mas grande que el hueco.** El recorrido de la animacion es el ancho
  del frame, asi que agrandarlo manda las chispas a orbitar por FUERA del dibujo
  -- contra el fondo, que es donde se ven. El 18% no es libre: la separacion
  entre huecos es de 16 sobre 84, o sea un 19%, asi que con un 9% por lado la luz
  no llega a pisar al vecino.

Las dos se aplican **en cada armado y no al crear la luz**: el boton cambia de
tamano con `grow` y de nivel al reparentarse entre el estado A y el B, y un
nivel puesto una sola vez envejece sin dar error -- la luz volveria debajo del
icono y pareceria que no sale.

## Cero es cierto en Lua, y por eso los hechizos morian con varios cogidos. Addon 0.85.0

*"Con seleccion multiple los hechizos de sanacion no funcionan porque tengo
seleccionado a todo dios."* El diagnostico del jugador apuntaba a la seleccion y
la causa era otra, pero **la correlacion era exacta** -- con dos o mas cogidos,
ninguna habilidad de la sala hacia nada.

```lua
n = n or ns.Hall.shown or K.MAX_SLOTS     -- K:Slots
```

`Hall.shown` es "cuantos huecos hay pintados en la fila del estado A". Con dos o
mas personajes la sala esta en el estado **B**, que no tiene fila -- y desde que
la sala se vacio (2026-09-05) `Recompute` deja `shown` en **0**. En Lua **0 es
cierto**, asi que `n` valia 0, el bucle no daba una vuelta, y `Slots(name)[i]`
era nil para todo.

**Los iconos SI salian**, porque los pinta `Cast`, que pasa su propio 4 para el
2x2. Solo estaba muerta la mitad que RESUELVE el hueco al pulsarlo. Un boton
dibujado, con su tooltip, que no hacia nada y no decia nada.

**Lo escribi yo el dia anterior, y el comentario que lo acompanaba se equivocaba
justo en la mitad que importaba.** Al poner `H.shown = 0` en la salida temprana
de `Recompute` deje escrito: *"hoy no lo pinta nadie porque el marco esta
escondido, y ese 'hoy' es justo lo que envejece mal"*. La precaucion era buena y
el sujeto estaba mal: el problema no era quien lo PINTA, era quien lo LEE. Un
`grep` de `Hall.shown` -- cuatro sitios -- lo habria ensenado en diez segundos, y
es el mismo gesto que la etapa anterior habia usado con exito antes de borrar
`Targets.lua` (*"antes de borrar un modulo, grep de su nombre"*). Ahi se hizo
para un borrado y no para un cambio de valor, y **un valor que cambia de
significado se lee tan mal como un modulo que desaparece**.

El arreglo no es poner otro numero: **resolver un hueco no tiene nada que ver
con cuantos se dibujan**, y quien dibuja ya pasa su cuenta. El tope es el unico
valor que no puede envejecer. Misma trampa arreglada en `K:Report`, donde ademas
dolia mas: decia *"0 huecos"* y no listaba ninguno, justo en el caso en que se
abre para averiguar por que un boton no responde.

### Un hechizo sin clasificar PREGUNTA, que no es lo mismo que `N`

`Describe` -- el camino de un hueco configurado cuyo hechizo no esta en el
catalogo de ahora, porque el `BARS` no ha llegado o el bot no esta cargado --
devolvia el tipo por defecto `N`, "sin objetivo". Y `N` **no pregunta**: se manda
tal cual, o sea sobre el propio lanzador. Un bufo puesto en un hueco se lo
aplicaba a si mismo por no saber todavia lo que era.

Ahora hay una letra `?` que pregunta. **Preguntar es la unica de las dos salidas
que es reversible**: el click derecho cancela, y un hechizo lanzado sobre quien
no era no se deshace.

### Y SHIFT PREGUNTA IGUALMENTE, que es la valvula de la clasificacion

*"Los hechizos que uno puede lanzarse a si mismo, como los bufos, deberian poder
lanzarse a otro jugador como si fueran una cura. Los que solo le sirven a el, esos
si se aplican al hacer click."*

Esa distincion es exactamente la que hace `ClassifySpell` con los predicados del
nucleo: `S` (todos sus efectos van al lanzador) se manda ya, `A` (pide objetivo
amistoso) pregunta. **Sin ninguna lista de ids**, que es lo que este proyecto
lleva seis etapas defendiendo, y no se toca.

Lo que se anade es la salida para donde esa regla no llega: *"no pide objetivo
explicito"* no es lo mismo que *"solo vale para quien lo lanza"*, asi que un bufo
que el juego deja echarle a un companero puede caer en `N` y mandarse a ciegas.
Inventar una regla nueva encima de la del nucleo seria adivinar -- y adivinar
aqui se paga en botones que no hacen lo que dicen. Se deja que lo diga el
jugador, que es quien sabe si ese bufo va para otro:

    Alt    sobre si mismo, sin preguntar
    Shift  elijo yo el objetivo, diga lo que diga la letra
    nada   lo que diga la letra

**Y el mensaje dice ahora la letra** cuando un hechizo se manda sin preguntar.
*"¿Por que no me ha preguntado?"* es una pregunta sobre la CLASIFICACION, y sin
el dato delante cuesta una ronda entera distinguir "esta mal clasificado" de
"entendi mal el gesto". Los tres gestos estan ademas escritos en el tooltip de
cada hueco: un modificador que no se cuenta en ningun sitio es un modificador
que no existe.

**Y una sospecha que el jugador puede cerrar en un click:** que un bufo cayera
sobre el propio lanzador *en seleccion simple* es tambien lo que hacia el atajo
del objetivo que se quito unas horas antes en la 0.84.0 -- seleccionar en el
mundo APUNTA, y el atajo lanzaba sobre lo apuntado. Si con la 0.85.0 sigue
pasando, el mensaje trae la letra y eso lo decide.

## El libro de hechizos lo dice el DBC, y los marcos duplicados. 2026-09-06

Addon **0.86.0**, mod-rts **0.38.0** (hay que reiniciar el servidor).

### "LOS HECHIZOS SON RAROS DE COJONES", Y NINGUN FILTRO OBVIO LOS SEPARABA

El desplegable de un sacerdote de nivel 3 ensenaba, junto a Punicion y Sanacion
inferior: *Duelo*, *Objetivo sin honor*, *Cerrando* (tres veces), *Activar
especializacion principal* y *secundaria*, *Atacando* y *Atacar automaticamente*.
Salen de `GetSpellMap()`, que es el mapa de hechizos del personaje -- bastante
mas de lo que el cliente dibuja en el libro.

**Los dos filtros que parecian evidentes NO valen, y se comprobo antes de
compilar nada:**

- **Tener entrada en `SkillLineAbility`**: la tienen los seis, igual que los
  buenos.
- **El bit 0x80 de "no mostrar"**: lo llevan unos si y otros no. *Objetivo sin
  honor* vale `0x09000120` -- sin ese bit. Un filtro asi habria dejado basura
  dentro y se habria descubierto en juego, en la siguiente ronda.

**Lo que si los separa lo dice el DBC con todas las letras.** Los seis cuelgan
de la linea de habilidad **183, "GENERIC (DND)"**, cuya categoria es la **12**,
llamada en `SkillLineCategory.dbc` literalmente **"Not Displayed"**. Los de
verdad cuelgan de una linea de clase (Holy, Discipline, Fury) o de una racial
(Night Elf Racial). La categoria 12 tiene UNA sola linea y ningun hechizo bueno
pasa por ella.

Y la constante no hay ni que inventarla: el nucleo la tiene con nombre,
`SKILL_CATEGORY_GENERIC`. Es la regla de siempre de este proyecto -- no inventar
una constante, leer la que ya existe -- llevada al sitio donde vive el dato.

**LA COMPROBACION SE HIZO CON UN GUION SOBRE `dist\data\dbc`, Y ESO ES LO
REUTILIZABLE.** Un DBC es una cabecera de veinte bytes (`WDBC`, registros,
campos, tamano de registro, bloque de cadenas) y detras registros de ancho fijo;
con `struct.unpack_from` se leen los tres ficheros que hacian falta en treinta
lineas. Es el mismo escalon que abrir el FrameXML de los MPQ (etapa de la barra
de postura): hasta hoy se comprobaba **si** algo existe, ahora se puede
comprobar **como esta clasificado**.

Dos trampas del camino, por si se repite: el `Spell.dbc` de `dist` esta en
**ingles** aunque el cliente lo ensene en espanol -- son ficheros distintos, y
buscar por el nombre de la captura no encuentra nada -- y el nombre esta en el
campo **136** de 234.

El filtro se aplica **solo a la mitad de "todo lo demas que sabe"**, no a la
barra de acciones del bot: esa es la lista curada por el jugador, y si el puso
ahi "Atacar automaticamente" es porque lo quiere. Filtrar lo que uno mismo
coloco seria decidir por el.

### Tu marco y los del grupo: la excepcion se cumplio y se va

`Chrome.lua` los dejaba a la vista desde el 2026-09-02, y su comentario decia
por que: la sala del centro acababa de vaciarse para redisenarla, asi que
esconder ademas los marcos de Blizzard habria dejado el modo RTS **sin ningun
estado en pantalla**. Decia tambien que *"donde acaben viviendo es una decision
del rediseno de la sala, no de este fichero"*.

La sala se lleno el 2026-09-04 -- retrato del heroe con vida y poder, columna de
cinco con la de cada companero -- asi que desde entonces eran **dos dibujos de
lo mismo, uno encima del otro**. La excepcion caduco el dia que se cumplio su
condicion y sobrevivio dos dias porque nadie volvio a leerla.

El del objetivo se queda: la sala ensena el objetivo del BOT seleccionado, que
no es el tuyo, asi que ahi no hay duplicado.

### Y LA PURGA DE GENERACION ESTABA MAL ESCRITA, aunque nunca hubiera fallado

Al subir la generacion, `Chrome` borraba **solo las claves de
`SHOW_BY_DEFAULT`**. Eso funciona mientras esa tabla CREZCA, y se rompe en
silencio en cuanto encoge -- que es exactamente lo que este cambio hace al sacar
de ella `player` y `party`: sus valores guardados bajo el defecto viejo habrian
sobrevivido a la purga escrita para ellos, y los marcos habrian seguido a la
vista sin que nada lo explicara.

Una generacion significa *"lo guardado ya no quiere decir lo mismo"*, asi que lo
unico coherente es no fiarse de nada de lo guardado: se tira la tabla entera. El
precio -- perder los ajustes que el jugador si habia tocado -- **se paga
diciendolo**, que es la diferencia entre una purga y una perdida.

## El FOV llevaba tres etapas muerto, las cuevas y la tecla que rompio la mira. 2026-09-06

Addon **0.88.0**, rts_core **0.13.0**, mod-rts **0.39.0**. Hay que reinyectar el
DLL y reiniciar el servidor.

### EL CANAL DEL FOV NUNCA EXISTIO, Y EL LOG LO DECIA DESDE EL PRIMER DIA

La camara isometrica de la etapa 5g manda el angulo por un segundo CVar
prestado, `guildMemberNotify`, *"un aviso del registro de hermandad, inerte en
un servidor solitario"*. **Ese CVar no existe en este cliente**, y `rts_core.log`
lo lleva escribiendo en cada arranque desde entonces:

    cvar: 'guildMemberNotify' not found -- channel unavailable

O sea que el FOV **no se ha aplicado ni una sola vez** desde que se escribio. Y
encima se dio por arreglado dos veces: la 0.50.0 (el `Create` que machacaba la
tabla de encuadre) y la 0.52.0 (la clave `fov` que faltaba en esa tabla). Los
dos eran fallos reales y los dos hacian falta -- **y ninguno bastaba**, porque
el canal estaba muerto por debajo. Tres rondas arreglando cosas ciertas encima
de una tuberia cortada.

La cadena `guildMemberNotify` **si esta en el `Wow.exe`**, que es lo que hizo
que pareciera buena eleccion: esta en el bloque de registro de CVars, con su
descripcion al lado. Estar la cadena no es estar registrado el CVar.

**La cura es dejar de necesitar que exista un CVar ajeno que nos venga bien:**
`RegisterCVar` crea uno (comprobado en el binario), asi que el canal pasa a ser
`rtsFov`, nuestro. No pisa ningun ajuste de nadie, no hay que devolverlo, y lo
unico que deja es una linea en `Config.wtf` que dice lo que es.

**Y EL DLL CACHEABA EL FALLO PARA SIEMPRE**, con esta frase escrita como si
fuera un hecho: *"a CVar that does not exist now will not appear later"*. Es una
suposicion, y falsa: el DLL se engancha con el cliente en la pantalla de login y
un CVar creado por el addon no existe hasta que carga la interfaz, varios
segundos despues. Con la cache de fallos, **un CVar registrado por Lua no se
podia encontrar jamas** -- que es un fallo silencioso y permanente de cualquier
canal que lo use. Ahora se reintenta una vez por segundo mientras falte, y se
dice en el log cuando aparece.

**El suelo del FOV baja de 20 a 5.** Se pidio 15 para probar y el tope lo habria
convertido en 20 **sin decir nada**: un numero que se acepta y se cambia por
otro es peor que uno que se rechaza.

### LA CAMARA ORTOGRAFICA SE PIDIO Y SE RETIRO EL MISMO DIA

Todo el apartado de abajo -- giro de 45, picado de 50-60, equivalente de 60-70
horizontales -- se encargo y se retiro unas horas despues: *"olvida lo de la
camara RTS y los valores de angulos que te di. Solo quiero poder controlar el
FOV, y la camara como antes"*. Se queda escrito porque el analisis vale (sobre
todo lo de la diagonal), pero **el codigo esta borrado**: fuera `/rts cam pitch`
y `/rts cam hfov`. Lo unico que sobrevive del encargo es el mando del FOV, que
era lo que estaba roto de verdad.

**Y EL VALOR POR DEFECTO DEL FOV VUELVE A 0, "no lo toques".** Estuvo en 60
desde la etapa 5g, pero como el canal nunca funciono **ese 60 no se habia visto
nunca en juego**: la camara que el jugador conoce es la de los 90 del cliente.
El dia que el canal empezo a funcionar la camara cambio de aspecto sola, sin que
nadie tocara nada. Eso no es un valor por defecto, es un cambio de
comportamiento colado por la puerta de atras -- y arreglar un canal no da
derecho a estrenar por el lo que llevaba anos sin salir.

Por lo mismo se tira una vez el `fov` guardado en `camFrame`: se escribio a
ciegas contra un canal muerto, asi que no es una preferencia de nadie. Septima
purga de este addon.

### La camara que se pidio, traducida a lo que este cliente tiene

El encargo era: ortografica, giro ~45, picado 50-60, equivalente perspectivo
60-70 horizontales, y el zoom por altura y no por FOV.

- **Ortografica: NO, y no hay rodeo.** El cliente construye una proyeccion en
  perspectiva a partir de UN campo (`camera+0x40`); no hay bandera de ortografia
  que activar, habria que sustituir la construccion de la matriz. Lo que si
  funciona es lo que el propio encargo propone como equivalente: estrechar el
  angulo y alejar la camara aplana la perspectiva hasta parecer un mapa.
- **60-70 HORIZONTALES NO SON 60-70 DE LOS NUESTROS.** `camera+0x40` guarda la
  **diagonal** -- se ve en el volcado del DLL, 1.5708 rad, los 90 grados de
  siempre. En 16:9, 65 horizontales son **72 diagonales**; escribir 65 seria
  bastante mas estrecho de lo pedido. `/rts cam hfov <deg>` hace la conversion
  con la forma REAL de la pantalla en vez de con un 16:9 escrito a mano.
- **El picado ahora es un angulo.** El comentario de `PitchDegrees` decia *"no
  hay forma de FIJAR un pitch en 3.3.5a"*, y es cierto a medias: no hay llamada
  que ponga un angulo, pero el cliente tiene movimiento de vista continuo y el
  DLL publica hacia donde mira la camara. Con las dos cosas **se cierra el
  lazo**: empujar y parar cuando el angulo publicado cruza el pedido.
  `/rts cam pitch 55`. El `tilt` en segundos sigue debajo, que es lo que el
  cliente entiende y lo que se guarda como angulo de entrada.
- **El giro de 45 no es un ajuste**: es hacia donde miras, y cambia en cuanto
  giras. Fijarlo seria orientar la criatura de la camara desde el servidor en
  cada entrada, y pelearia con tu propio giro. Sin hacer, y dicho.
- **El zoom ya es por altura y distancia** (`back`, `up`, `zoom` y las teclas),
  y el FOV es independiente. Esa mitad ya estaba como se pide.

### Dentro de una cueva, el campo de alturas no significa nada

*"No puedo clicar dentro de cuevas: el punto se imprime en el terreno por encima
y los bots van alli."*

`GroundRay` corta el rayo contra los modelos (interseccion de verdad) y, por
separado, **anda el rayo comparandolo con el campo de alturas del terreno**. El
suelo de una cueva es un modelo; el campo de alturas sigue describiendo la
ladera que tienes ENCIMA. Con la camara dentro, `pz <= g` es cierto **en el
primer paso** -- estas debajo del monte desde el metro uno -- asi que el paseo
cortaba a una yarda de la camara y devolvia la altura del terreno de fuera.

No fallaba el rayo: fallaba pedirle una respuesta a un campo de alturas desde
debajo de el, donde no la tiene. Si el rayo empieza por debajo del terreno, el
paseo no se hace y manda el modelo, que es lo unico valido ahi.

### LA TECLA DE CALIBRAR RESUELVE LA MIRA CON UNA SOLA MUESTRA

*"En algun momento pulse G para calibrar no se que, y algo se fue a la mierda."*

`Markers:Calibrate` -- la tecla -- toma la posicion del cursor en el instante de
pulsarla y **supone que estaba exactamente encima de la unidad seleccionada**.
Con eso resuelve la escala de proyeccion, la guarda y pone `forceScale`. Si el
cursor no estaba justo ahi -- que es lo normal cuando la tecla se pulsa sin
saber lo que hace -- escribe una mira torcida **para siempre**, y a partir de
entonces los clicks caen donde no es. Eso es lo que se rompio.

**Hay un arbitro que no depende de la punteria**: la escala DERIVADA del FOV y de
la forma de la pantalla, que es pura geometria. Una medida buena cae a menos del
1% de ella (1.1404 medido contra 1.1473 derivado, sobre 900 muestras). Asi que:

- una calibracion que salga a mas del **25%** de la derivada se **rechaza al
  escribirla** -- eso no es una medida, es el cursor fuera del modelo;
- y **se comprueba tambien AL LEERLA**, porque la mala ya estaba guardada de
  ayer. Sexta purga de este addon, y la primera que no se puede hacer al cargar:
  la derivada necesita el FOV del DLL, que llega despues, asi que se comprueba
  en cuanto hay con que.

`/rts cal auto` sigue siendo el deshacer manual, y ahora pasa por el mismo sitio
-- antes dejaba `RTSCommandDB.SX` puesto, asi que la escala mala **volvia en el
siguiente arranque**.

## El boton Compartir del registro nativo, forzando. 2026-09-07

Addon **1.4.0**, mod-rts **0.45.0** (hay que reiniciar el servidor). `rts_core`
sin tocar. `docs/PRUEBAS-25.txt` es la ronda.

### LA VENTANA DE MISIONES ESTA BORRADA, Y ES LA SEGUNDA VEZ QUE SE DECIDE

Hubo dos: la de *"lo que ofrece este PNJ"* (etapa 7) y la de *"mis misiones con
una fila de puntos por companero"*. Las dos se vieron en pantalla y las dos
sobraban por el mismo motivo: **el registro de misiones ya existe, ya sabe
dibujar una mision, y el jugador ya sabe usarlo.** Lo unico que le faltaba era
que su boton de Compartir sirviera de algo con un grupo de bots.

Asi que no se dibuja una lista: se le cambia el trabajo a un boton que ya esta
puesto. **Cero pixeles nuevos.**

`QuestLogFramePushQuestButton` es un `Button` corriente que hereda
`UIPanelButtonTemplate` (`QuestLogFrame.xml:181`, **leido del MPQ del cliente**,
no recordado), y ni el ni `QuestLogFrame` llevan `protected`. Quien lo apaga es
`QuestLogControlPanel_UpdateState` (`QuestLogFrame.lua:984`), que exige
`GetQuestLogPushable()` -- justo la condicion que sobra cuando se fuerza -- asi
que se engancha con `hooksecurefunc` y se reenciende DESPUES de que ella decida.
Mismo patron que el repintado del nombre en el marco de Blizzard (0.62.0):
despues de la suya, para tener la ultima palabra. Sin mod-rts o sin companeros
el boton hace lo que hacia (`QuestLogPushQuest()`), que se guarda en vez de
reemplazarse a ciegas.

**`ToggleQuestLog` no se usa, y no por gusto:** es una funcion de C de la misma
familia que `ToggleWorldMap`, que la etapa 5l confirmo PROTEGIDA en juego.
`ShowUIPanel`/`HideUIPanel` son Lua corriente (`UIParent.lua:1922`) y por ahi se
abre. Es la leccion de la 5l aplicada por delante en vez de pagada otra vez.

### LAS TRES MITADES ESPERAN A UN CLICK TUYO, Y LA MITAD DEL FALLO NO ERA NUESTRA

Pedido asi: *"IF I PRESSED THE ACCEPT BUTTON, then it is when other players also
get the quest (...) wait until i press COMPLETE, then bots get their quest
reward"*. Y lo que pasaba era lo contrario: *"any time i opened the npc's quest
window the log said the bots turned the quest"*. **Eran dos causas y solo una era
nuestra.**

- **La nuestra: colgaba de `QUEST_FINISHED`**, que en 3.3.5a significa *"se
  cerro el dialogo"* y nada mas -- no lleva el id de nada y el manejador de
  Blizzard solo hace `HideUIPanel`. Asi que abrir la ventana de un PNJ y
  cerrarla entregaba por el grupo. **Estaba escrito como comportamiento esperado
  en `PRUEBAS-25` J11: no fue un descuido, fue una decision equivocada** -- y una
  ronda de pruebas que confirma lo que el diseno dijo no la caza. Los ganchos son
  ahora `AcceptQuest`/`ConfirmAcceptQuest`, `GetQuestReward` y `AbandonQuest`, o
  sea BOTONES. Ni el "Continuar" del panel de progreso (`CompleteQuest()`, que no
  cobra) ni cerrar la ventana disparan nada.
- **La otra era de playerbots, y su disparador es TU cliente.** La estrategia
  `quest` (`QuestStrategies.cpp:27`) responde al disparador "gossip hello", y ese
  lo arma el `CMSG_GOSSIP_HELLO` que manda tu cliente al abrir la conversacion
  (`PlayerbotAI.cpp:164-165`): con solo abrir la ventana, cada bot ejecuta
  `TalkToQuestGiverAction` contra tu objetivo y entrega ahi mismo todo lo que
  tenga completado, eligiendo recompensa por su cuenta. Y con
  `AiPlayerbot.SyncQuestWithPlayer = 1` esa accion primero COMPLETA la mision del
  bot si la tuya lo esta (`TalkToQuestGiverAction.cpp:39-46`), asi que ni hace
  falta que haya hecho el trabajo.

  **No se pierde nada al quitarla, y por eso es la salida correcta y no un
  parche:** todo lo que daba lo hace ya este modulo y ademas atado a un click --
  `Accept`/`Share` para dar, `TurnIn` para entregar. Lo que se va con ella es
  solo el camino que se disparaba SOLO; el credito de objetivos (matar, recoger)
  es del nucleo y no pasa por la IA.

  Se apaga con el verbo `QAI` al entrar en modo RTS y **cada vez que cambia el
  grupo**. Es el hermano exacto del botin: estado de la IA que vive en la memoria
  de cada bot, asi que el que entra despues nace con el de fabrica.
  `/rts quests ai` lo devuelve -- apagar algo de otro modulo tiene que ser
  reversible y visible.

**Y LA RECOMPENSA DOBLE NO PODIA PASAR, ni antes ni ahora**, que era el otro
miedo del informe: `Player::RewardQuest` solo corre detras de `CanRewardQuest`,
y un `GetQuestRewardStatus` cierto la corta -- la propia
`TalkToQuestGiverAction::TurnInQuest` empieza con esa misma guarda. Cobrar cinco
veces no estaba pasando: cobraban UNA vez, sin que lo pidieras. Merece estar
escrito porque el sintoma reportado (*"entregaron solos"*) es compatible con las
dos cosas, y una de ellas habria mandado a buscar un fallo que no existe.

### IDENTIFICAR "QUE MISION ACABA DE PASAR" SE HIZO MAL TRES VECES

Tres intentos, tres rondas, y los tres leian **algo que el cliente ya habia
cambiado**:

1. por el **INDICE** de `QUEST_ACCEPTED` -- el registro que Lua consulta no esta
   escrito cuando llega ese evento, asi que el indice apunta a lo que hubiera
   antes en ese hueco;
2. por el **TITULO del panel** leido dentro del gancho de `AcceptQuest` --
   `hooksecurefunc` corre DESPUES, con el dialogo ya cerrado;
3. igual, en la entrega, dentro del gancho de `GetQuestReward`.

La version cuatro no lee nada que pueda estar viejo: **mira que mision es NUEVA
(o cual DESAPARECIO) comparando dos fotos del registro**, en
`QUEST_LOG_UPDATE` y no en `QUEST_ACCEPTED`. Sin ventanas de tiempo para acertar
el instante -- el plazo de 10 s que queda solo existe para que un Aceptar que el
servidor rechace no deje armado el reparto de la siguiente mision que entre por
cualquier otro camino.

Es la forma de error de la barra de postura y del FOV: **el testigo equivocado
convierte un mecanismo correcto en un resultado inutil.** Aqui tres veces
seguidas, y las tres veces el testigo estaba disponible un tick mas tarde.

`sim/quest_share.py` reproduce la maquina de estados fuera del juego. Encontro
dos casos antes de compilar: un `QUEST_LOG_UPDATE` que llega ANTES de que el
servidor haya metido la mision (no hay nada nuevo, y no debe mandar nada
todavia) y **la primera foto, donde el registro entero parece nuevo** -- que
habria repartido las 25 misiones que llevaras encima al primer Aceptar de la
sesion. Ninguno de los dos se ve leyendo el codigo.

### EL FORZADO SOLO ALCANZA A LO QUE TU YA ENTREGASTE

`/rts quests force`, encendido de serie: al entregar tu, el grupo completa y
cobra aunque no la llevara hecha. La puerta -- **el maestro tiene que tener esa
mision cobrada** -- nacio de que el disparador de entonces (`QUEST_FINISHED`) no
llevaba id, asi que cerrar la ventana de un PNJ que recibe tres misiones habria
completado las tres, **incluidas las que el jugador aun esta haciendo**.

Con la identificacion por diferencia del registro ya se sabe cual es, y la puerta
**se queda igual, en los dos lados**: el cliente filtra antes de mandar porque
sabe lo que acabas de pulsar, y el servidor la repite porque es el lado con
autoridad. No necesita adivinar nada -- cuando llega la llamada el nucleo ya te
ha recompensado, asi que la que acabas de entregar cumple y las que llevas a
medias no.

Lo que SI sigue alcanzando, y es deliberado: una mision que entregaste hace
tiempo y que a un bot le falta, p.ej. uno que entro al grupo despues. Ponerle al
dia es justo para lo que existe.

### FORZAR EL ESTADO NO BASTA PARA UNA MISION DE RECOGER

El camino de ayudar a un companero tiene TRES escalones porque hay tres formas
distintas de quedarse atras -- no la lleva, le faltan objetos, la lleva a medias
-- y el segundo es el que no se ve venir:

`Player::CompleteQuest` pone el estado y **no inventa los objetos**. Y
`CanRewardQuest` (rama `QUEST_SPECIAL_FLAGS_DELIVER`) vuelve a contar lo que hay
en la bolsa y devuelve false si falta algo. O sea que forzar el estado **no basta
para una mision de entregar objetos**: el nucleo la rechazaria igual, en silencio
y solo en esas -- o sea el peor reparto posible de un fallo. Se le completan las
pilas antes de entregar, y `RewardQuest` las destruye acto seguido, que era la
otra mitad de lo que se pidio.

**Lo que no se salta es `CanRewardQuest` entera**: hueco en la bolsa, diarias, y
el dinero de las misiones que CUESTAN oro. Forzar un estado es una cosa; dejar a
un bot en numeros rojos por saltarse una comprobacion es otra.

**Y MARCAR LA CADENA NO ES UN TRUCO NI HACEN FALTA COMANDOS GM.** El requisito
que el nucleo comprueba es literalmente `IsQuestRewarded(prevId)`
(`PlayerQuest.cpp:1039`), y hay un metodo publico que lo pone:
`Player::SetRewardedQuest(id)`. No se falsifica un paquete, no se toca la base de
datos a mano, y no hay que seleccionar a cada bot para escribirle un
`.quest complete` -- los comandos GM llaman a este mismo nucleo, solo que de uno
en uno y sobre tu seleccion.

**SOLO SE FUERZA LA CADENA.** Nivel, clase, raza, reputacion y registro lleno se
respetan y se DICEN, una linea por companero: son motivos distintos de "no te
siguio", y taparlos convertiria un boton honesto en uno que a veces hace algo que
no entiendes. Los eslabones NEGATIVOS de `prevQuests` piden la mision ACTIVA y no
recompensada (`:1071`), asi que no se pueden arreglar por ahi y se informan en
vez de fingirse.

### `questAuto`: UN INTERRUPTOR QUE NADIE PIDIO, GUARDADO EN OFF

*"I had to activate /rts quests auto. when the fuck did i ask for that?"* -- y es
exacto: nunca se pidio. Lo que se pidio es que al aceptar tu, el grupo coja la
mision. **Un interruptor encima de eso solo puede hacer una cosa mala, y la
hizo:** estaba guardado en OFF de una ronda de pruebas vieja, y desde entonces
bloqueaba el reparto entero con un `return` mudo -- o sea que las tres vueltas
siguientes se fueron buscando el fallo en el sitio equivocado.

Borrado el interruptor y **tirada la clave al cargar**, que es la octava purga de
este addon despues de `grow = 688`, `camHold`, `railCropGen`, las de la sala,
`slots` y `bright`. Dejarla seria dejar el mismo cepo puesto para el dia que
alguien vuelva a leerla.

`/rts quests force` (forzar la entrega) SI se queda como interruptor, y la
diferencia importa: *"que el grupo vaya detras de mi"* es lo que se pidio y no
tiene sentido apagar; *"que lo haga aunque no hayan hecho el trabajo"* es una
decision distinta que se puede querer o no.

### Lo demas

- **UN VERBO QUE EL SERVIDOR NO CONOCE NO DA ERROR: NO CONTESTA**, asi que un
  worldserver sin reiniciar se comporta *exactamente* igual que un fallo en el
  addon -- el gesto sale, no pasa nada, y no hay nada que mirar. Ya se cobro una
  ronda con `QDROP`, que se leyo como "abandonar no funciona". Ahora el addon
  comprueba `Link:ServerAtLeast(45)` y **lo dice a gritos**, con el numero que
  tiene y el que hace falta.
- **`QCATCH` contestaba con la letra `C` y el patron del addon solo aceptaba
  `[AT]`**, asi que su resultado no se imprimia NUNCA. Un mensaje que no sale es
  indistinguible de una orden que no llego. Las cinco letras estan ahora escritas
  con su nombre, y al anadir `QDROP` toco la `D`.
- **Abandonar faltaba entera.** Aceptar y entregar iban juntos desde la etapa 7;
  tirar una mision se quedaba solo en ti y los cuatro bots la conservaban para
  siempre. `QDROP`.
- **`Frames:Refresh` entraba en `Paint` con el marco a nil.** Los tres marcos los
  crea `Layout`, pero `host` existe desde que la sala registra el modulo, asi que
  un refresco que llegue por delante (un evento de unidad, el latido de 5 Hz)
  reventaba en la primera linea que lo indexa. Salia como
  `Frames.lua:235: attempt to index local 'f' (a nil value)` **al aceptar una
  mision**, que es donde menos se parece a lo que es: un orden de arranque.
- **La rejilla 4x4 pierde Botin y Cazar, y gana Bolsas y Misiones.** Botin ponia
  `ll all` al grupo y eso ya se hace solo al entrar en modo RTS -- una casilla
  gastada en repetir algo que ya paso. Cazar (`grind`) era la unica de las
  dieciseis que dejaba al grupo con un comportamiento propio que luego hay que
  deshacer, y en una consola cuyo asunto es dirigirlos, "id a vuestro aire" es lo
  mas lejos de lo que la rejilla significa.

  **Y las dos ventanas son las que mas falta hacian ahi, no porque fueran
  dificiles de abrir sino porque el modo RTS ESCONDE EL CHAT:** una funcion que
  solo se alcanza escribiendo un comando esta a un gesto de no existir, por muy
  construida que este. `/rts npc` sigue en ese estado y es la siguiente candidata
  el dia que se libere una casilla.
- **Los dos iconos nuevos salen del FrameXML del cliente**, no de memoria: la
  mochila es la del boton de bolsas (`MainMenuBarBagButtons.xml`) y la
  exclamacion la que Blizzard pone sobre un PNJ con mision (`GossipFrame.lua`).
  Una ruta de textura que no existe no da error, dibuja nada.

## El cliente ya trae una camara libre, 2026-09-07. Sondeo construido, NO corrido.

Addon **1.5.0**, mod-rts **0.46.0** (hay que reiniciar el servidor). `rts_core`
sin tocar, no hay que reinyectar. Sale de
`Downloads/Brief_Tecnico_Rediseno_Camara_RTS_WoW.docx`, que pide rehacer la
camara en cuatro capas con altura sobre terreno, suavizado por `dt`, seguimiento
de unidad y un corte seccional para interiores.

### EL BRIEF ACIERTA EL DIAGNOSTICO Y SE EQUIVOCA EN LA PREMISA

Su §15 lista como cosa *a comprobar* lo que resulta ser la causa raiz de todo lo
que intenta arreglar: *"comprobar si la camara vive exclusivamente en cliente"*.
**No vive.** Es una criatura del servidor (`Puppet`, entry 15214) que el jugador
posee, asi que el CLIENTE es dueño de su posicion y desde el servidor solo se la
puede mover con `NearTeleportTo` -- que cancela el movimiento que el cliente esta
aplicando.

Una sola causa explica los cuatro requisitos que el brief pide y que hoy no se
cumplen: avanzar y subir a la vez (§2/§7/§17), la altura sobre el terreno
(§5/§8, construida y borrada el 2026-08-23 por los dos caminos), el suavizado
por `dt` (§6, no somos dueños de la transformada: no hay nada que interpolar) y
un pitch que se quede (§4).

**Construir cuatro capas encima de la criatura poseida hereda la causa.** Lo que
habia que cambiar es quien es dueño de la camara -- y el cliente ya trae la
pieza.

### LA CAMARA DE COMENTARISTA: 6-DOF DESDE LUA CORRIENTE

Desensamblado de **este** `Wow.exe` (MD5 `45892BDEDD0AD70AED4CCD22D9FB5984`):

```
CommentatorSetCamera(x, y, z, yaw, pitch, fov)   0x0056A0F0
CommentatorGetCamera()                           0x0056A2A0
CommentatorSetCameraCollision(bool)              0x0056AB70
CommentatorFollowPlayer(faction, index)          0x00569B50
CommentatorSetTargetHeightOffset(float)
CommentatorSetMoveSpeed(speed)
CommentatorZoomIn / ZoomOut
```

Colocacion de camara por coordenadas de mundo, interruptor de colision de
camara, y seguimiento de unidad con offset de altura. Es §12, §9A y media §14
del brief **ya escritos por Blizzard**.

**COMO SE LOCALIZA UNA FUNCION DE LUA DEL CLIENTE, que es reutilizable.** El
cliente registra sus funciones en una tabla de pares `{const char*, void*}`: se
busca la cadena del nombre, luego su direccion como dword, y los cuatro bytes
siguientes son el puntero. **La tecnica se estreno contra `UnitClass`**, que ya
estaba documentada aqui en `0x0060FEC0`, y dio esa misma direccion -- una
tecnica nueva se prueba sobre algo cuya respuesta ya se conoce, o no se sabe si
lo que devuelve es verdad. Es la misma decision que la etapa de la clase que
mentia.

### LA PUERTA SON DOS FLAGS Y LOS PONE NUESTRO SERVIDOR

El predicado en `0x006DE980`, al que llaman `SetCamera`, `GetCamera` y el
manejador del paquete:

```
mov ecx, [player + 0x1008]
mov ecx, [ecx + 8]
shr edx, 0x13 ; test bit 19  -> APAGADO: return false
shr ecx, 0x16 ; test bit 22  -> ENCENDIDO: return true, y ya
                             ; si no: hace falta un mapa de tipo 4 (arena)
```

Bits comprobados **contra el enum del propio nucleo** y no de memoria
(`Player.h:478,481`): bit 19 es `PLAYER_FLAGS_UBER` (0x00080000) y bit 22 es
`PLAYER_FLAGS_COMMENTATOR2` (0x00400000). El 19 es obligatorio; **el 22 es lo
unico que salta el requisito de la arena**, que es lo que hace esto viable en
mundo abierto. Y el nucleo ya trae el setter del 22 hecho:
`Player::SetCommentator(bool)` (`Player.h:1169`).

### EL MODO LO ARBITRA EL SERVIDOR, QUE SOMOS NOSOTROS

`CommentatorToggleMode` (`0x00569180`) manda `CMSG_COMMENTATOR_ENABLE` (0x3B5) y
espera `SMSG_COMMENTATOR_STATE_CHANGED` (0x3B6). El manejador del cliente esta en
**`0x0056B8A0`** y su carga es exactamente `uint64 playerGuid` + `uint8 enable`,
con el guid obligado a ser el del receptor. Si cuadra y el predicado pasa, mete
la camara activa en modo comentarista (`0x00603330(cam, 6, 2, 0)`).

Dos cosas del nucleo que hacen falta y estan comprobadas:

- **No hace falta que el cliente lo pida, y ademas no se puede escuchar.**
  `CMSG_COMMENTATOR_ENABLE` es `STATUS_NEVER` + `Handle_NULL`
  (`Opcodes.cpp:1080`), y `STATUS_NEVER` **ni llega a `CanPacketReceive`**: su
  `case` en `WorldSession.cpp` solo hace `LOG_ERROR` y `break`. Asi que mod-rts
  no puede observar la peticion -- da igual, el addon la hace por su canal y el
  0x3B6 lo manda el servidor por su cuenta.
- **`SendPacket` no valida opcodes de servidor.** Solo rechaza `NULL_OPCODE`. Que
  0x3B6 este declarado `STATUS_NEVER` en la tabla no impide MANDARLO, que era el
  riesgo obvio a descartar antes de construir nada.

### EL TESTIGO OBVIO NO SIRVE, Y ESA ES LA TRAMPA DE ESTE SONDEO

`CommentatorGetCamera()` **no vale para saber si la camara se movio**: lee la
posicion de los globales del estado de comentarista (`0x00ACE4B4/B8/BC`), o sea
**lo que le pediste**, no donde esta la camara de verdad. Un lector que devuelve
tu propia peticion es exactamente el modo de fallo que este documento lleva
persiguiendo desde el `C:Report()` que imprimia el FOV que no se aplicaba, y
desde el `check_addon.py` que aprobaba una cadena rota.

El testigo honesto es **`RTS_CamX/Y/Z`**, que el DLL saca del campo de posicion
de la camara ACTIVA (`cam+0x08`) sin pasar por Lua.

Para lo que **si** vale `GetCamera` es para saber si la puerta esta abierta:
devuelve **seis numeros** si lo esta y **nada** si no (la rama de gate cerrado
sale sin apilar). Es una lectura pura, cero riesgo, y por eso es el paso 1.

**Y EL SILENCIO ES EL DIAGNOSTICO EN `SetCamera`.** La rama de gate cerrado es
`xor eax,eax; ret` sin decir nada (`0x0056A298`); un error de argumentos SI
imprime (`0x0056A283`). O sea: *sin mensaje y sin efecto* = los flags no
llegaron; *mensaje de uso* = la puerta esta abierta.

### DE PASO: LOS ANGULOS DE LA CAMARA, QUE EL DLL NO TIENE

Desensamblar `GetCamera` dio algo que `Offsets.h` dice hoy que no conoce -- su
tabla tiene posicion (`+0x08`), matriz (`+0x14`), FOV (`+0x40`) y aspect
(`+0x44`), y **ningun campo de pitch ni de yaw**. `GetCamera` los lee de la
camara activa:

```
fld dword ptr [edi + 0x11C]   ; yaw, radianes  (x RAD2DEG al devolverlo)
fld dword ptr [edi + 0x120]   ; pitch, radianes
```

Hace falta si algun dia se va por el camino B (el DLL escribiendo la camara cada
tick, como ya hace con el FOV), porque hasta ahora la orientacion solo se sabia
leer como matriz y no habia forma de ESCRIBIR un angulo.

### LO QUE NO ES ALCANZABLE, DICHO POR DELANTE

**§9C / §10 / §11, el corte seccional por shader: no.** `Wow.exe` es binario
cerrado sin fuentes de shader; "shader discard basado en world position"
significaria enganchar D3D9 y sustituir shaders, que es otra categoria de
proyecto. Lo que **si** hay dentro del binario, y por eso el sondeo lo
inventaria en vez de darlo por perdido:

- la clase `CClipVolume` (string RTTI presente), `M2UseClipPlanes`, `glClipPlane`,
- `farClipOverride` (*"must be 0 or 1"*), `horizonFarclipScale`,
- interruptores de categorias enteras: *"Terrain culling enabled/disabled"*,
  *"Detail doodads disabled"*, *"Doodad batching"*, *"Simple doodads"* -- todos
  de `World.cpp` del cliente, o sea **comandos de consola**,
- `antiportal`, `TogglePortals`.

**Y la consola de desarrollo esta encendida en este cliente**: `Config.wtf`
tiene `showToolsUI "1"`. `/rts cam geo` dice cuales de esos nombres son CVars
(lo unico que Lua alcanza) y el resto se prueba alli. **Es un inventario, no una
funcion**: sirve para diseñar §10/§11, no para usarlo.

La respuesta barata para interiores es §9A -- `CommentatorSetCameraCollision(false)`,
una llamada, `/rts cam cut`.

### ESTADO: SONDEO, NO FUNCION

`/rts cam probe` corre seis pasos parando en el primero que no contesta, y cada
uno dice **lo que significaria que fallara** -- si el paso 4 dice que la camara
no se movio, el modo no se arma fuera de una arena y el camino A esta muerto.
`/rts cam spec 0` sale, y los flags se quitan tambien en el logout y en
`Abandon`, sin condicion y antes de mirar si habia camara: `PLAYER_FLAGS_UBER`
puesto y olvidado es estado del jugador que sobrevive a la sesion.

**No se ha construido ni una de las cuatro capas**, ni la altura sobre terreno,
ni el suavizado, ni el follow. Nada de eso se escribe hasta que el paso 4
conteste, porque el hallazgo es una lectura estatica de algo **visual** y la
regla de la etapa 5e dice que eso vale *una* prueba barata en juego, no
maquinaria encima. La ultima vez que me la salte -- el aro dibujado dos veces,
2026-09-06 -- costo una tarde y encima salio como comportamiento de fabrica.

**Nada del camino del Puppet se toca**: la camara de siempre sigue funcionando
igual mientras esto se prueba.

## La camara libre del cliente SUSTITUYE al Puppet, 2026-09-07 (tarde)

Addon **1.23.0**, `rts_core` **0.23.0**, mod-rts **0.49.0**. La camara **funciona
y esta confirmada en juego**; el heroe invisible sigue abierto y su apartado va
al final con todo lo descartado.

Sale del sondeo de la seccion anterior, que contesto que si. Lo que hay ahora:

  * **WASD mueve en el PLANO**, no volando: adelante es el vector de avance de
    la camara PROYECTADO al plano horizontal y renormalizado, asi que la
    inclinacion solo cambia lo que ves. Es la leccion de la etapa 5f aplicada
    con la transformada en nuestras manos.
  * **La altura se mantiene sobre el terreno.** `targetZ = suelo + offset`, con
    el suelo de un rayo vertical que el DLL lanza **bajo la camara** cada tick
    (`RTS_CamGroundZ`). El unico suelo que se publicaba antes estaba bajo el
    JUGADOR y no sirve: la camara RTS pasa la mayor parte del tiempo donde el
    personaje no esta, que es justo cuando hace falta. **Esto es lo que se
    construyo por los dos caminos y se borro el 2026-08-23 por imposible.**
  * **ESPACIO y C mueven el OFFSET, no la Z**, asi que avanzar y subir a la vez
    deja de ser un problema en vez de arreglarse: son dos entradas del mismo
    solver, integradas en el mismo frame.
  * **Suavizado por `dt`** en la altura y en el plano, `1 - exp(-k*dt)`,
    independiente del frame rate. `/rts fc ease` es el mando.
  * **El giro con el raton es NATIVO.** El cliente lleva la ORIENTACION,
    nosotros la POSICION.

`FreeCam.lua` es el controlador -- las cuatro capas del brief -- y `RTSMode` ya
no invoca la camara como vista, solo como *mover* (ver el ultimo apartado).

### EL GIRO CON EL RATON: CINCO INTENTOS Y LA LECCION ES UNA

Los tres primeros fueron en Lua y **los tres estaban descartados POR ESCRITO en
`RTSMode.lua` antes de que los escribiera**, por la misma frase:

    "MouselookStop only stops a mouselook an ADDON started, and
     IsMouselooking is FALSE for the client's own button-drag."

  1. disparar por `IsMouseButtonDown("RightButton")` -- devuelve **NO** mientras
     el cliente tiene el raton cogido;
  2. disparar por `IsMouselooking()` y soltar el cursor -- es false para el
     arrastre del cliente, y `MouselookStop` no suelta lo que no empezamos;
  3. dejar girar al cliente y leer el resultado -- correcto, y lo descarte con
     una prueba **hecha con el controlador muerto** (ver el apartado del borrado
     accidental), asi que la conclusion *"gira otra camara"* era falsa.

El cuarto -- el DLL leyendo el raton en crudo por `WM_INPUT` y girando nosotros
-- funcionaba y **se sentia mal por construccion**: el DLL acumula deltas, los
publica a 67 Hz por una cadena de Lua, y el addon los aplica al frame siguiente.
Tres etapas de retardo y una cuantizacion. En pantalla: a trompicones, con
latencia y demasiado sensible.

**El quinto es el bueno y es el que el jugador propuso: que el giro sea NATIVO.**
El cliente ya lo hace perfecto, con la sensibilidad y la inversion que el jugador
tiene configuradas. El truco de convivencia es que `CommentatorSetCamera` toma
los seis valores de golpe, asi que no se puede escribir la posicion sin escribir
los angulos: **se leen los vivos justo antes y se reescriben tal cual**, que para
la orientacion es un no-op y deja que el giro del cliente se acumule solo.

Y se leen con `CommentatorGetCamera`, que es **SINCRONO** -- lee `cam+0x11C`
(yaw) y `cam+0x120` (pitch) en este mismo frame -- y no con `RTS_CamFwd*`, que
llega con un tick de retraso. **Esa eleccion es la que quita la latencia.**

La leccion, que es la de todo el dia: **cuando el cliente ya hace algo bien, el
trabajo es convivir con el, no reimplementarlo.** Reimplementarlo mete una
cadena de retardos que no se puede compensar con ajustes.

### EL SIGNO DEL PITCH, Y POR QUE EL VALOR POR DEFECTO NO LLEGABA

`CommentatorSetCamera` mira hacia ABAJO con pitch **POSITIVO**. Lo puse a -45
razonando "abajo es negativo" y la camara apuntaba al cielo.

Y cambiar el valor por defecto a +45 **no hizo absolutamente nada**, porque
`Cfg()` solo rellena las claves que FALTAN y el cliente ya tenia `-45` guardado.
`-45` esta dentro del rango valido, asi que el acotado lo dejo pasar tal cual.

**COMPARAR EL RANGO NO BASTA CUANDO LO QUE CAMBIA ES LO QUE EL NUMERO
SIGNIFICA.** Es el caso exacto del `railCropGen` de la etapa 5o. `FreeCam` lleva
sello de generacion (`GEN`) y al subirlo se tira la tabla entera y se dice --
salvar las claves que "parecen bien" es volver a decidir a mano lo que el sello
existe para no tener que decidir. Novena purga de este addon.

### EL FOV DE `SetCamera` NO ADMITE 0, Y ESO ES UNA CONVENCION IMPORTADA

Una pantalla morada, ilegible, "como el FOV mas estrecho posible" -- y era
exactamente eso: **un grado**. El sexto argumento va en grados y se acota entre
`[0x009E2B40]` y `[0x00A0FF40]`, que leidos del binario son **1 y 120**. Y el
suelo no es un valor cualquiera: `0.01745329` **es** `DEG2RAD`, la misma
constante con la que convierte. Pasar 0 da `0 <= DEG2RAD`, gana el suelo.

El fallo de fondo no fue el numero: **me traje una convencion de otro canal.** En
`rtsFov` -- el CVar que lee el DLL -- 0 significa *"no toques el FOV"*, y lo
escribi aqui como si fuera una propiedad del FOV y no de ese canal. Dos caminos
al mismo campo (`cam+0x40`) con dos significados para el mismo valor.

Y por eso `/rts cam fov` no hacia nada con la camara libre puesta: en modo 6 el
FOV lo tiene el estado de esa camara y lo repone el cliente, asi que el CVar
pierde. Ahora va por `CommentatorSetCamera`, que es su dueño mientras el modo
este armado.

### `/rts fc poke`: EL CANAL QUE DEBIA EXISTIR TRES INTENTOS ANTES

Cada candidato probado a pulso costaba **una compilacion y una sesion del
jugador**, y este fichero lleva media docena de vueltas asi. `rtsPoke` es un CVar
entero propio -- el canal empaquetado no tiene bits libres y esto necesita un
NUMERO -- codificado en decimal para poder teclearlo:

    accion * 1000000 + indiceDword * 100 + bit
    1 = apagar el bit, 2 = encenderlo, 3 = poner a cero un dword de la CAMARA

`/rts fc poke 216 17 0`. **Cero recompilaciones para descartar un candidato.**
Si vuelve a aparecer una investigacion de este tipo, esto es lo primero que hay
que montar, no lo ultimo.

### DOS VECES BORRE LA MISMA FUNCION AL REESCRIBIR EL BLOQUE DE AL LADO

`FlatForward` y `GroundUnderCamera` cayeron dentro del rango que sustitui, dos
veces seguidas. `Step` las llama, asi que pasaban a ser **llamadas a un GLOBAL
inexistente -- que en Lua es legal**: no lo vio el cargador, no lo vio
`check_addon.py`, y reventaba en el primer frame. El `pcall` del latido apagaba
el controlador.

Y el sintoma no se parecia a la causa: **"el raton va pero WASD no"**. El giro
del raton lo hace el CLIENTE, asi que no depende de ese fichero; todo lo que
hacia el controlador murio de golpe. Peor: con el controlador muerto se probo el
intento 3 del raton y su conclusion salio falseada.

Ahora estan **ancladas junto al estado**, lejos del codigo que se reescribe, y se
comprueba que no quede ninguna llamada sin definir en el fichero. La version
ingenua de esa comprobacion da **65 falsos positivos** (APIs de WoW usadas en un
solo fichero), asi que no vale para `check_addon.py`; la precisa es comparar
contra git -- *"esto estaba definido en HEAD, ya no, y se sigue llamando"* -- y
esta **sin hacer**.

### Y UNA REGRESION QUE SE ARREGLO EN EL SITIO EQUIVOCADO

Al jubilar el Puppet, `orders::MoveSelf` empezo a contestar *"the RTS camera is
not holding control"* y las rutas propias salian con "reached no bots". Su guarda
exige que alguien le haya quitado el control del personaje al cliente, y su
comentario dice por que: *"si el cliente sigue conduciendo este personaje, un
movimiento del servidor lo cancela el siguiente paquete que manda"*. Eso lo
cumplia la POSESION.

La razon de la guarda sigue siendo verdad; lo que estaba mal era suponer que la
unica forma de cumplirla es poseer algo. `SetClientControl(player, false)` lo
hace, y con el propio jugador como objetivo **no toca el viewpoint**
(`Player.cpp:13171`), asi que no deja ningun seer colgando.

**Pero manda `SMSG_CLIENT_CONTROL_UPDATE` con el guid del jugador, y eso
significa "tu unidad activa es esta".** Cuando se volvio a poner el Puppet para
el heroe invisible, esa linea lo deshacia un instante despues -- ver el apartado
siguiente. Ahora solo se manda si no hay nada poseido.

## El heroe invisible: SIN RESOLVER, y esto es lo que NO hay que volver a probar

En modo comentarista el cliente **no dibuja tu propio personaje**. Los bots si.
Se ve el aro de seleccion en el suelo sin modelo encima.

### EL FILTRO QUE DESCARTA CASI TODO, Y LO DIO EL JUGADOR

*"Lo que me parece la mar de curioso es que en modo primera persona lo arreglaste
en un plis."*

Con la camara Puppet el heroe **SE VEIA** -- `CLAUDE.md` de la etapa 6: *"WASD
flies it, Q/E rotate, **character rooted below**"*. Y `PRUEBAS-5` D2 dice por
que: *"tu personaje **no es el active mover**, asi que el cliente calcula las
interacciones contra la camara y no contra ti"*.

O sea que **nunca se arreglo: salia gratis.** La camara estaba pegada a la
criatura invisible, asi que tu cuerpo era una unidad mas.

**De ahi sale la pregunta que cualquier explicacion tiene que contestar: ¿por que
con el Puppet SI se veia?** Con ese filtro, los seis candidatos que probe estaban
descartados de entrada -- ninguno lo explicaba. **Es el filtro, no los
candidatos, lo que hay que retener.**

### LOS SEIS CANDIDATOS DESCARTADOS, con la evidencia

1. **El bit `0x800` de `render+0x7C`.** El cliente lo apaga al entrar en modo
   comentarista (`0x7801C0(*(player+0xB8), 2, 2)`, con un NOT en la aritmetica).
   Descartado por dos vias: se devuelve y se queda puesto (log:
   `00008000 -> 00008800`), y **anulando la llamada del cliente con cinco NOPs**
   -- `0x0056B92D`, firma de trece bytes comprobada, restaurada al descargar --
   el bit no se apaga nunca y el modelo sigue invisible.
2. **Las otras dos llamadas a `0x7801C0`.** Son las TRES que existen en todo el
   binario (`0x0056B851`, `0x0056B92D`, `0x0056B96F`) y ninguna limpia el bit en
   nuestro camino.
3. **La distancia de camara** (la teoria de "te esconde como en primera
   persona"). No hay campo que falsear: el "zoom" de comentarista escribe
   `0xACE4E4`, que es el **FOV**.
4. **El modo de camara como criterio.** Vive en `camera+0xB4`; solo hay 8 modos
   (`FIRST_PERSON`, cinco de tercera persona, `VIEW_COMMENTATOR`,
   `VIEW_BARBER_SHOP`), el 6 es el unico libre -- no hay alternativa -- y **no
   hay ni una comparacion con 6** en sus 107 accesos.
5. **Los bits 17 de `+0x0D8` y `+0x1A8`**, que la comparacion contra un bot
   visible senalo (`yo 00020221` contra `bot 00000221`). Apagados con `poke`, el
   log confirma la escritura (`00020221 -> 00000221`), y sigue invisible.
6. **Un objetivo de camara.** `FindSelfRef` busca en 1 KB de la camara el
   puntero al objeto, al objeto de render y las dos mitades del guid: **la camara
   no referencia al jugador**.

### Y EL SEPTIMO, QUE ES EL QUE MERECE LA PROXIMA VUELTA

**Volver a poner el Puppet como *active mover*, no como vista.** Es lo que el
filtro senala, y ya no choca con la camara libre: el conflicto era por WASD, y
desde que `FreeCam` coge las teclas con botones propios **el cliente no ve WASD
en absoluto**. La criatura solo tiene que existir y ser el mover.

Se intento y **fallo por una razon que ya esta arreglada**: `Spectate` mandaba
`SetClientControl(player, false)` DESPUES de la posesion, y ese paquete vuelve a
declararte mover. Corregido en mod-rts 0.49.0 (solo se manda si no hay nada
poseido). **La prueba con la correccion puesta no se ha hecho todavia** -- eso es
lo primero de la proxima sesion.

Si tampoco funciona, quedan dos:

  * **El gancho dentro del frame.** `Circle.cpp` ya engancha `0x004F6F90`, una
    funcion del recorrido de render que corre DENTRO del frame del cliente.
    Escribir ahi gana cualquier carrera contra una decision por frame, que es lo
    unico que `poke` (33 Hz, asincrono) no puede descartar.
  * **El doble que te sigue.** Una criatura con tu `DisplayId` siguiendo al
    heroe. Es la tecnica que `docs/SUELO-INFORME.md` ya eligio como la mejor de
    tres, y funciona seguro porque no es el jugador activo. El precio, dicho por
    delante: **sin equipo** -- se ve el modelo de raza y genero, sin armadura.

    **CORREGIDO 2026-09-08: LO DE "SIN EQUIPO" ES FALSO.** Es cierto para una
    criatura con el `DisplayId` prestado y nada mas, que es lo unico que se
    penso aqui. El nucleo trae el camino bueno hecho -- es el de la Imagen
    Especular del mago -- y con el, el doble lleva armadura, tabardo y armas.
    Ver la seccion del 2026-09-08.

### DOS INSTRUMENTOS, Y UNO NACIO MAL

`RenderVsBot` compara **tu objeto de render (invisible) contra el de un bot
(visible) EN EL MISMO FRAME**, y es el bueno: los dos son unidades del mismo tipo
en el mismo instante, asi que la animacion deja de ser ruido.

`RenderDiff` -- comparar contra una foto de un segundo antes -- **no sirve, y sus
propias tomas lo demostraron**: la primera dio 14 cambios y la segunda 2, sin que
nada relevante cambiara. El "antes" es un objeto VIVO (animaciones,
temporizadores, colores), asi que medía la deriva del segundo con la causa
enterrada dentro. **Un instrumento cuyo resultado no se repite no mide lo que
dice medir.**

Y peor: mi propio arreglo de los bits 17 **cego el diagnostico**, porque los
apagaba antes de que el diff los mirara. Un arreglo que no arregla y encima tapa
el instrumento es peor que no tener arreglo.

## VUELTA ATRAS AL COMMIT DEL BOTON COMPARTIR. 2026-09-08

**El repositorio esta en `4047b84` ("El boton Compartir del registro nativo,
forzando"), identico a GitHub.** Todo lo posterior -- la camara libre de
comentarista del 2026-09-07 y el trabajo del heroe invisible del 2026-09-08 --
nunca llego a estar commiteado y **se ha deshecho a peticion del jugador**.

Estado real, para que este fichero no mienta:

- **La camara RTS vuelve a ser el Puppet poseido.** `FreeCam.lua` no existe.
- **`rts_core` vuelve a 0.14.0** y **mod-rts a 0.45.0**. Recompilados y
  redesplegados desde este commit.
- Las secciones de mas arriba fechadas **2026-09-07** describen codigo que ya no
  esta. Se dejan porque son el registro de la investigacion, pero **no describen
  lo instalado**.

### LO QUE FUNCIONABA ESTA GUARDADO, Y ES LO IMPORTANTE

`docs/CAMARA-LIBRE.md` (sin commitear, en el repo) es la receta completa de la
camara libre que SI funcionaba: las ocho funciones de comentarista con sus
direcciones, los dos flags y su puerta, la secuencia de dos verbos y por que va
partida, el giro nativo con `AdoptLook`, **la altura sobre el terreno con el rayo
bajo la CAMARA**, el suavizado por `dt`, el adelante plano, y los once ajustes
medidos en juego. Con eso se reconstruye sin volver a investigar nada.

Copia de seguridad del arbol completo antes de deshacer:
`C:\Server\_backup-2026-09-08-freecam` (134 ficheros, incluida una copia de
este CLAUDE.md).

### LO QUE SI HAY QUE RETENER DE LA SESION DEL 2026-09-08

Tres hechos verificados que siguen siendo ciertos y ahorran trabajo futuro:

- **El selfbot no tiene nada que ver con el heroe invisible.**
  `.playerbots bot self` (`PlayerbotMgr.cpp:1059-1079`) mete un puntero en un
  mapa y **no escribe nada en el `Player`**; mod-playerbots no tiene ninguna
  llamada de visibilidad ni de display en todo su arbol, y registra solo
  `SERVERHOOK_CAN_PACKET_RECEIVE`. Ademas ocurre tres viajes de red DESPUES del
  paquete que esconde el modelo. Descartado, no hay que volver.

- **El doble del heroe SI puede llevar el equipo**, y este fichero decia lo
  contrario. El camino es el de la Imagen Especular del mago: aplicar
  `SPELL_AURA_CLONE_CASTER` pone `UNIT_FLAG2_MIRROR_IMAGE`
  (`SpellAuraEffects.cpp:2918`), el cliente pide `CMSG_GET_MIRRORIMAGE_DATA`, y
  `HandleMirrorImageDataRequest` (`SpellHandler.cpp:739-808`) contesta con raza,
  genero, clase, piel, cara, pelo, vello facial **y los once display id de
  equipo visible**, respetando `HIDE_HELM` y `HIDE_CLOAK`. El aspecto sale del
  LANZADOR del aura. Hechizo **45204 "Clone Me!"**, comprobado en el DBC de este
  servidor: `Effect[0]=6`, `ApplyAuraName[0]=247`, duracion permanente. Las
  armas no van en esos once: `UNIT_VIRTUAL_ITEM_SLOT_ID`, que toma un ENTRY.

- **`PLAYER_FLAGS_UBER` mata el mouseover.** `0x00729740` es un predicado con 28
  llamantes que devuelve false en cuanto el jugador local tiene el bit 19, y uno
  de sus llamantes es el filtro de hit-test del mundo (`0x004F7350`). Por eso
  con la camara de comentarista nada se ilumina al pasar por encima. **No es la
  causa de la invisibilidad**: un barrido de `mov r32,[reg+0x1008]` sobre todo
  `.text` da un solo hit en el rango del render, y sin prologo.

### Y LA LECCION DE PROCESO, QUE ES LA CARA

Parchee `0x006DE980` a `mov eax,1 / ret` creyendo que era la puerta del modo
comentarista. **No lo es: es un predicado general de "¿soy espectador?" con
dieciocho llamantes** repartidos por la escena, la interfaz y el codigo de
unidad. Forzarlo a true le dijo al cliente entero que el jugador era un
espectador, y el resultado en pantalla fue **que no se veia NADIE** -- ni el
heroe ni los bots -- ademas de entrar en camara de espectador en juego normal.

Dos errores, los dos evitables y los dos ya escritos en este fichero:

1. **Desensamble el CUERPO de la funcion y no enumere sus LLAMANTES.** Media
   hora antes, para `0x00729740`, SI los habia enumerado -- 28 -- y por eso
   aquella conclusion era correcta. La misma comprobacion, disponible, de un
   minuto, ya usada ese mismo dia, saltada en la segunda funcion. Es la regla de
   *"cuando se identifica una causa raiz, la pregunta siguiente es quien mas usa
   este mecanismo"*, que este fichero lleva escrita desde el 2026-08-23.

2. **Entregue un experimento ENCENDIDO DE SERIE.** Identico al aro dibujado dos
   veces del 2026-09-06: las dos veces el primer contacto del jugador con la
   ronda fue un fallo nuevo puesto encima de lo que venia a arreglar. **Regla:
   ningun parche de bytes sobre el cliente entra activo sin una prueba en juego
   detras. Va apagado y detras de un comando.**

## La sonda de identidad, 2026-09-08. CODIGO REVERTIDO; los hallazgos se quedan.

**ESTADO: el codigo de esta sonda NO esta instalado.** Se construyo, se corrio
en juego, contesto la pregunta, y se deshizo a peticion del jugador -- el repo
esta otra vez en `4047b84`, identico a GitHub, `rts_core` en 0.14.0 y el addon
en 1.4.0. Copia completa de lo revertido en
`C:\Server\_backup-2026-09-08-sonda` (incluido el `.patch` de los ficheros
trackeados), asi que reconstruirla es aplicar un parche, no reinvestigar.

Lo que sigue se queda porque **el resultado y las medidas son conocimiento, no
codigo**: la cuenta de llamantes es una propiedad del binario, y el veredicto
descarta un camino entero. Borrarlo garantizaria volver a desensamblar lo mismo.
Mismo trato que `docs/CAMARA-LIBRE.md`: es una receta, no un diario.

**No es una funcion, es un instrumento**, y
existe porque el heroe invisible lleva seis candidatos fallidos y ninguno
explicaba el filtro que dio el jugador: con la camara Puppet el heroe SI SE
VEIA. Ese filtro señala que el escondite se decide por IDENTIDAD -- el cliente
esconde lo que cree que es EL -- y esa pregunta tiene una funcion con nombre.

### La funcion, desensamblada de este `Wow.exe`

`ClntObjMgrGetActivePlayer`, **`0x004D3790`**, devuelve el guid del jugador
activo en edx:eax leyendo `objmgr+0xC0/+0xC4`. **Va por TLS** (`fs:[0x2C]` ->
indice en `0x00D439BC` -> `+8`), o sea que `objmgr+0xC0` **no es una direccion
fija y es por hilo**: cualquiera que lo lea o lo escriba tiene que andar la
cadena desde el hilo principal. Es la misma cadena del `UPDATEFLAG_SELF`.

### LO QUE MATO LA IDEA DE ESCRIBIRLO: 1296 LLAMANTES

La propuesta era apuntar la identidad a otro personaje escribiendo ese campo, y
la frase que la acompañaba era *"todo lo demas mantenerlo igual"*. Contados los
`call rel32` sobre `.text`: **1296 sitios**. Dos dias antes se forzo
`0x006DE980` creyendo que era la puerta del modo comentarista, resulto ser un
predicado general con **18** llamantes, y en pantalla **no se veia nadie**.
Setenta y dos veces ese alcance no puede ser quirurgico por definicion.

**Y un coste que no depende del radio:** `Group::SendUpdateToPlayer` manda
`GetMembersCount() - 1` y se salta al receptor (`Group.cpp:1836-1840`), asi que
la lista de grupo **nunca te contiene a ti**. Con la identidad apuntando a un
personaje fuera del grupo, el heroe se queda **sin token de unidad en Lua** --
ni `player` ni `partyN` -- y el bloque del heroe de la sala leeria a otro. El
canal si sobrevive: `Link.lua:153` va por PARTY con grupo, sin nombre que
acertar.

### La forma buena: mentirle a UN llamante, no a los 1296

Si el escondite es `si (unidad == jugadorActivo) saltar`, basta con que ESE
llamante reciba un guid que no case con nada. Radio 1 en vez de 1296, y **no
hace falta ningun personaje extra, ni swap, ni raid**. Asi que el trabajo pasa a
ser encontrar cual de los 1296 es, y para eso esta la sonda.

### El reparto de los llamantes, que acota la busqueda y da una prediccion

| banda | llamantes |
|---|---|
| `004F6000-004FA000` recorrido de escena / hit-test | **13** |
| `00743000-00745000` circulo por unidad | **2** |
| **`00790000-007B0000` submit de modelo de unidad** | **0** |
| `00569000-0056C000` comentarista | 34 |

**El cero es un hallazgo, no la ausencia de uno.** El submit del modelo no
pregunta el guid por esta funcion, y tampoco hay un thunk comun guid->objeto
(el cliente lo inlinea en 21 sitios). Asi que si la sonda vuelve vacia de las
bandas de render, **la respuesta es que el escondite compara PUNTEROS de
objeto** -- y el sitio donde mirar es el paseo por `*(player+0xB8)` del
candidato 1, no esta funcion. Un negativo tambien cierra.

### El instrumento: `SelfProbe.cpp`, y las cuatro decisiones que lo hacen usable

- **DOS VENTANAS Y UNA RESTA, no un volcado.** Ventana A con el heroe visible,
  B con el heroe escondido, y el llamante que decide sale en la diferencia. Dos
  listas de cientos de direcciones habria que compararlas a ojo, y eso no es un
  instrumento: es una tarea. La resta la hace el DLL, con las bandas puestas al
  lado de cada direccion y normalizada por el total de cada ventana -- sin
  normalizar, el orden lo decidiria el frame rate.
- **EL DETOUR TERMINA EN `jmp`, NO EN `call`.** La original devuelve 64 bits en
  edx:eax; saltando a ella, su propio `ret` vuelve al llamante y el valor de
  retorno nunca pasa por nuestras manos. Con un `call` habria que preservar
  edx:eax a mano, y eso es la clase de error que no da sintoma: devolveria una
  identidad corrupta a uno de 1296 sitios y el fallo saldria en cualquier otra
  parte. **Comprobado desensamblando el DLL compilado**, no confiando en que
  MSVC hiciera lo escrito.
- **SE INSTALA UNA VEZ Y NO SE QUITA, y el interruptor es un byte.** Parchear
  siete bytes no es atomico y no sabemos si el cliente llama a esta funcion
  desde otros hilos -- devuelve cero sin gestor, o sea que esta escrita para
  tolerarlo. Instalar y quitar por ventana multiplicaria esa carrera por cada
  uso. Apagado cuesta `cmp`+`je`+`jmp`.
- **LA TABLA ES UN HASH, Y NO ES PREMATURO.** La funcion se llama miles de veces
  por frame; un barrido lineal por llamada daria un tiron justo mientras se
  sostiene la pose que se esta midiendo, y **una medida que altera lo que mide
  no vale**. Solo se anota el hilo principal, que ademas quita la carrera sobre
  la tabla.

### Lo que se puede medir HOY, y por que se hace asi

El modo comentarista se fue con la vuelta atras, asi que la condicion que
interesa no se puede reproducir. Lo que si, sin tocar el servidor, es la
**primera persona**, donde el cliente tambien esconde tu modelo:
`/rts probe fp` hace la pareja entera sola.

**Automatica y no a mano por una razon concreta:** la ventana dura 400 ms y hay
que sostener la pose mientras corre. Pedir teclear, girar la rueda y teclear
otra vez dentro de ese tiempo es pedirle al jugador que sea el cronometro, y
entonces lo que se mide es su punteria.

**Y vale sobre todo porque estrena el instrumento contra una respuesta que ya
se conoce** -- ahi el modelo se esconde, seguro -- que es la regla con la que se
estreno la tecnica de localizar funciones de Lua contra `UnitClass`. Dicho por
delante: pueden ser caminos distintos, asi que un acierto es una pista y no una
prueba.

### Y LA MENTIRA NO ESTA ESCRITA, NI APAGADA

Es deliberado y es la leccion del `camHold` del 2026-08-23: aquella funcion se
quito de la ayuda dejando la maquinaria puesta, y **su ajuste guardado la volvio
a armar sola**, asi que el fallo siguio pasando igual. Cuando la resta señale
una direccion, la mentira se escribe entonces, para ESA direccion, detras de un
comando y con una prueba en juego detras -- que es tambien la regla que se
incumplio con el aro dibujado dos veces del 2026-09-06.

**El canal es un CVar PROPIO, `rtsProbe`**, creado con `RegisterCVar`. Prestar
uno ajeno es lo que costo tres etapas de FOV que no se aplicaba porque
`guildMemberNotify` no existe en este cliente. Y el DLL actua **por cambio de
valor, no por valor**, con un nonce en los bits altos: sin eso, el CVar que se
queda puesto reabriria la misma ventana treinta veces por segundo, y una ventana
que se reabre sola nunca se cierra.


### EL PRIMER ARRANQUE CON LA SONDA PUESTA DESTAPO UN FALLO QUE NO ERA DE LA SONDA

*"Al entrar en el juego estoy en primera persona como si mi pj no estuviera y
puedo mover la camara, incluso clipear en el suelo."* Antes de ejecutar nada.

**`Neferite` tenia `playerFlags = 4718592` = `0x480000` = bit 19
(`PLAYER_FLAGS_UBER`) + bit 22 (`PLAYER_FLAGS_COMMENTATOR2`), guardados en
`characters.playerFlags`.** Con esos dos bits puestos, `0x006DE980` -- el
predicado general de "¿soy espectador?" con dieciocho llamantes -- contesta que
si **sin necesidad de ningun parche**, y el cliente entero se comporta como
espectador en juego normal. Es el mismo cuadro que el parche de bytes del
2026-09-08 produjo a mano, y estaba escrito con esas palabras: *"ademas de
entrar en camara de espectador en juego normal"*.

**LOS ESCRIBIO LA CAMARA LIBRE Y LOS DEJO LA VUELTA ATRAS.** El revert a
`4047b84` se llevo `Spectate`, `Abandon` y el gancho de logout -- todo el codigo
que quitaba esos bits -- **pero no el estado que ese codigo existia para
limpiar**. Resultado: un personaje roto y **ni una linea de codigo en el arbol
capaz de explicarlo**, porque toda la que mencionaba esos flags se habia
borrado. Se leyo, con toda la razon, como un fallo de lo ultimo instalado.

Es el `camHold` del 2026-08-23 con el mecanismo al reves: alli la maquinaria
seguia puesta y el ajuste guardado la armaba sola; aqui la maquinaria se borro y
el estado guardado se quedo huerfano. **Antes de revertir codigo que escribe
estado persistente -- flags de jugador, SavedVariables, filas de base de datos
-- hay que limpiar el estado, no solo el codigo.** Anotado tambien en
`docs/CAMARA-LIBRE.md`, que es donde lo leera quien reconstruya la camara.

Cura, con el personaje **fuera del mundo** (si no, el `Player` en memoria lo
reescribe al guardar y el arreglo parece no funcionar):

```sql
UPDATE characters SET playerFlags = playerFlags & ~0x00480000 WHERE online = 0;
```

### Y LA SONDA TENIA UN DEFECTO DE VERDAD QUE ESTO SACO A LA LUZ

`/rts probe fp` **suponia** que la ventana A tiene el heroe visible, y lo decia
por el chat (*"alejando la camara (heroe VISIBLE)"*) sin comprobarlo. En un
cliente en modo espectador tu modelo no se dibuja **nunca, ni en tercera
persona**, asi que A y B miden la MISMA condicion y la resta sale vacia -- vacia
**por el motivo equivocado**, y eso se leeria como *"el escondite no usa el
guid"*, que es literalmente una de las tres conclusiones que la sonda existe
para poder sacar. Un instrumento que puede dar un falso negativo tranquilizador
es de la familia de `C:Report()` imprimiendo el FOV que no se aplicaba.

**El detector era gratis y ya estaba documentado:** `CommentatorGetCamera`
devuelve seis numeros si la puerta esta abierta y nada si no. `/rts probe` lo
imprime siempre y `fp` se niega a correr con la puerta abierta, diciendo por
que. Cero coste, cero riesgo, y cierra el unico modo de fallo silencioso que le
quedaba a la sonda.


### EL RESULTADO: RESPUESTA (c), Y REPRODUCIDA DOS VECES

`/rts probe fp` corrido dos veces seguidas. La sonda funciono exactamente como
se diseño -- ~3.000 llamadas por ventana, 50 sitios distintos, sin cuelgue, sin
tope alcanzado y sin llenar la tabla -- y contesta que **NO**:

| | corrida 1 | corrida 2 |
|---|---|---|
| llamadas A / B | 2943 / 2756 | 3178 / 3044 |
| **SOLO EN B** | **ninguno** | **ninguno** |
| **SOLO EN A** | **ninguno** | **ninguno** |
| banda recorrido de escena | 5 sitios, A=182 B=168 | 6 sitios, A=208 B=200 |
| banda submit de modelo | 0 | 0 |

**Ni un llamante aparece ni desaparece al esconderse el modelo.** Y el unico
candidato con volumen que parecia moverse -- `0x00730F05`, x1.14 -- **cambia de
signo entre las dos corridas** (A=234/B=192, luego A=182/B=200), o sea ruido.
Es justo para lo que valia correrlo dos veces.

**El escondite NO saca su identidad de `ClntObjMgrGetActivePlayer`.** Es
exactamente lo que la lectura estatica predecia con los cero llamantes en la
banda del submit de modelo, asi que las dos evidencias -- una estatica sobre el
binario, otra dinamica en juego -- apuntan al mismo sitio.

Los dos llamantes de mas peso, desensamblados para etiquetar su banda, confirman
de paso que el patron existe y que no es el nuestro:

```
0073E2F8  call 0x4D3790        ; ¿quien soy yo?
0073E2FD  cmp  edi, eax        ; ¿es esta unidad yo?
0073E301  cmp  ebx, edx
```

~10 visitas por frame cada uno, o sea un recorrido por unidad -- **y con la
misma cuenta esté el modelo dibujado o no**. El cliente pregunta "¿es este yo?"
ahi para otra cosa, y la decision de dibujar se toma en otro sitio.

### LO QUE ESTE NEGATIVO MATA, Y LO QUE NO -- LA DISTINCION IMPORTA

**MATA el atajo del DLL:** escribir `objmgr+0xC0` para apuntar la identidad a
otro personaje **no puede curar el heroe invisible**, porque el camino que
decide no dibujarlo no consulta ese campo. Habria sido una escritura con 1296
llamantes de alcance a cambio de nada, y eso es lo que costaba descubrir tarde.

**NO mata la idea del cambio de personaje**, y conviene tenerlo claro porque es
lo contrario de lo que parece: un swap de verdad cambia la identidad **por la
maquinaria del propio cliente** (`UPDATEFLAG_SELF` -> `objmgr+0xC0` -> y con el,
todo lo que el cliente derive y cachee de ahi, incluido el puntero al objeto del
jugador local). Una escritura cruda solo cambia lo que contesta UN getter. Asi
que de los dos caminos que habia, la sonda elimina el barato y deja el otro
intacto -- **el swap pasa de ser una de dos opciones a ser la unica**.

### DONDE MIRAR AHORA

Si no es el guid, el escondite compara **el objeto**. Y hay una pista de la
misma sesion: `0x0056B830` -- el que apaga el bit 0x800 al entrar en modo
comentarista -- **recibe el `player` como ARGUMENTO** (`mov esi, [ebp+8]`), no
lo busca:

```
0056B834  mov  esi, [ebp + 8]     ; el player, de su llamante
0056B83D  call 0x006DE980         ; __thiscall(player) -> ¿soy espectador?
0056B846  mov  eax, [esi + 0xB8]  ; su objeto de render
0056B851  call 0x007801C0         ; apagar el bit
```

Asi que el codigo de esa zona tampoco se pregunta quien es: la identidad le
llega de arriba. **El siguiente paso es el que la sesion del 2026-09-08 ya dejo
apuntado y sigue siendo el bueno: un gancho DENTRO del frame** -- `Circle.cpp`
ya engancha `0x004F6F90`, que corre en el recorrido de render -- para ver que le
pasa al objeto de render del heroe en el momento del submit. La sonda de guid
descarta una rama entera y deja esa.

**Y la sonda se queda puesta y validada para la pregunta de verdad.** Cuando el
modo comentarista vuelva, `/rts probe a` con el heroe visible y `/rts probe b`
con el modo armado se contestan con el mismo instrumento, sin cambiar una linea.
Lo medido hoy es primera persona; con los cero llamantes del submit de por
medio la conclusion se generaliza bien, pero **eso sigue siendo una inferencia y
no la medida**, y la medida cuesta dos comandos el dia que se pueda hacer.

### Dos defectos del instrumento que la primera medida saco

- **La banda que faltaba.** Los dos llamantes con mas datos caian en
  `0x00700000-0x00790000`, sin etiquetar, y salian como `[-]`: la parte con mas
  informacion era la que menos decia. Añadida, y **etiquetada despues de
  desensamblar los dos**, no por su rango -- una banda mal nombrada es peor que
  ninguna, porque manda a mirar al sitio equivocado con la confianza de una
  etiqueta.
- **`/rts probe` informaba "el CVar no existe todavia"** de un CVar que el mismo
  podia crear en una linea. No es un dato del cliente, es la pereza del informe,
  y se leia como que el canal esta roto justo en el comando al que se acude para
  saber si el canal esta roto.

### De paso: dos comprobaciones de servidor que zanjan la objecion del raid

Verificadas al valorar la idea del personaje "Comentator", y valen aunque esa
idea no se construya:

- **En un raid, el nucleo bloquea el CREDITO de objetivos de misiones no-raid**
  en cuatro sitios (`PlayerQuest.cpp:2012/2072/2344`, `Player.cpp:12665`), y los
  cuatro pasan por `Quest::IsAllowedInRaid` (`QuestDef.cpp:297`), que es
  `IsRaidQuest() || CONFIG_QUEST_IGNORE_RAID`. O sea que **es una linea de
  configuracion**: `Quests.IgnoreRaid` (hoy a 0, `worldserver.conf:2937`).
  Aceptar mision no esta bloqueado en ningun sitio.
- **Un raid NO cuesta XP en mundo abierto**: `KillRewarder.cpp:260` exige que
  **el mapa** sea de raid, y un continente no lo es. Y un miembro extra solo
  diluye XP si esta **dentro de la distancia de recompensa** (`_count`, :96).
- Y el limite de 5 no bloquea nada: playerbots **convierte la party a raid solo**
  al necesitar el sexto (`PlayerbotMgr.cpp:557-566`), y `Selection.lua:44` ya
  lee `raidN` antes que `partyN`.

## Ruta A: la sonda del cuerpo, 2026-09-09. Construida, NO corrida.

Addon **1.5.0**, `rts_core` **0.15.0**. mod-rts sin tocar, no hay que reiniciar
el servidor; el DLL SI hay que reinyectarlo. `docs/PRUEBAS-26.txt` es la ronda.

Se descarto de entrada la pregunta que abrio la sesion -- *"¿un modulo de
servidor puede secuestrar la peticion que esconde el personaje?"*. **No hay
peticion en el cable**: `CMSG_COMMENTATOR_ENABLE` es `STATUS_NEVER` y ni llega
a `CanPacketReceive`, y el escondite lo decide el cliente en su propio proceso
mucho despues de que el paquete haya pasado. La unica palanca que entra ahi es
`rts_core`, que ya existe. Y `Wow.exe` no se puede recompilar porque no hay
fuentes: para el cliente solo hay MPQ (datos), parcheo en proceso (el DLL) y
nada mas.

### EL ESCONDITE SALE DE ENUMERAR LOS LLAMANTES, QUE ES LO QUE NO SE HIZO

`0x006DE980` es *"¿este jugador es espectador?"*, `__thiscall(player)`, y mira
el bit 19 (`PLAYER_FLAGS_UBER`) y el bit 22 (`PLAYER_FLAGS_COMMENTATOR2`). Los
dieciocho llamantes estan ahora **enumerados**, no contados:

| banda | llamantes |
|---|---|
| `0x004FA69D` recorrido de escena | 1 |
| `0x00519039`, `0x005245B3`, `0x006E085C` | 3 |
| `0x00569B7B`..`0x0056B919` comentarista | 7 |
| `0x005FA6F5`..`0x005FBEBA` API de interfaz | 6 |
| **`0x0073AAA9` emision por unidad** | **1** |

El ultimo es el que importa. Vive en `0x0073A890`, un *"prepara y emite esta
unidad"*, y su cola es:

```
0073AA9F  shr edx,4 ; test dl,1   ; TYPEMASK_PLAYER
0073AAA7  mov ecx, edi            ; ESTE jugador
0073AAA9  call 0x006DE980         ; ¿es espectador?
0073AAAE  test al, al
0073AAB0  jne 0x0073AB17          ; SI -> no lo emite
0073AAB5  lea ecx, [edi+0x788]
0073AABB  call 0x006EF230         ; NO -> lo emite
```

**Se pregunta POR JUGADOR.** Solo el nuestro lleva los flags, asi que solo el
nuestro se salta -- que es el sintoma exacto, heroe no y bots si. Y explica de
paso el desastre del 2026-09-08: forzar el predicado a `mov eax,1 / ret` lo hizo
cierto para TODOS, y por eso no se veia nadie. **Aquel resultado no era ruido:
era la prueba de que este es el sitio, leida al reves.**

La leccion de proceso es la misma de aquel dia, cumplida esta vez: *cuando se
identifica una causa raiz, la pregunta siguiente es quien mas usa este
mecanismo.* Cuesta un minuto de script y convierte "un parche con dieciocho
consumidores" en "dos bytes en un sitio".

### La sonda: dos interruptores independientes, apagados de fabrica

`SelfShow.cpp` + `Body.lua`, canal por un CVar **propio** (`rtsBody`, creado con
`RegisterCVar`) -- prestar uno ajeno es lo que dejo el FOV muerto tres etapas.

- **`/rts body flags on`** escribe los dos bits **en la copia del CLIENTE**,
  donde el predicado los lee (`*(player+0x1008)+8`), sin servidor y sin camara.
  Si el heroe desaparece, los flags bastan y el diagnostico esta cerrado.
- **`/rts body skip on`** anula ese `jne` -- dos bytes, un solo sitio, firma
  comprobada antes de escribir y devueltos al descargar el DLL.

Con los dos a la vez se contesta la pregunta que decide la forma de la cura:
*con los flags puestos, ¿reaparece anulando solo ese salto?*

Tres reglas de este documento aplicadas por delante en vez de pagadas otra vez:

- **No sale de serie.** Va detras de un comando y arranca en 0. El aro dibujado
  dos veces (2026-09-06) y el parche del predicado (2026-09-08) salieron los dos
  encendidos, y las dos veces el primer contacto del jugador con la ronda fue un
  fallo nuevo puesto encima de lo que venia a arreglar.
- **No se guarda en disco.** Un instrumento con su interruptor guardado es el
  `camHold` del 2026-08-23: la funcion se escondio, el ajuste sobrevivio, y se
  rearmaba sola.
- **La mentira no esta escrita.** No hay ni una linea de camara libre en este
  cambio. Se reconstruye desde `docs/CAMARA-LIBRE.md` cuando la sonda conteste,
  no antes.

**Y la sonda es ademas el detector de la basura de aquel dia:** `/rts body log
on` imprime los flags vivos, asi que un `uber=1` antes de tocar nada dice que el
personaje todavia arrastra el `playerFlags = 0x480000` en la base de datos.


## Los macros de mando y las dos barras de la derecha. 2026-09-11

El encargo tenia dos mitades que resultaron ser la misma: *"esconde tambien el
marco del objetivo y el del objetivo del objetivo, pero DEJA las dos barras
verticales de la derecha, que ahi pondre cosas"*, y *"hazme macros con los
comandos de los bots -- el `assist` sobre todo -- para poder activarlos y
desactivarlos desde ahi"*. Sin las barras los macros no tienen donde vivir; sin
los macros las barras no tienen para que quedarse.

**Esconder el objetivo es una linea; el conjunto nuevo no.** Las cuatro barras
de accion vivian juntas en el conjunto `bars`, asi que las dos verticales salen
a un conjunto propio, `side`, que de fabrica NO se esconde. Eso cambia lo que
significa `bars` para quien lo tuviera guardado, o sea sello `uiHideGen` a 4 y
la tabla entera a la basura diciendolo -- la novena purga, por la misma razon de
siempre: comparar el rango no basta cuando lo que cambia es lo que la clave
SIGNIFICA.

**Dejarlas visibles no era dejarlas usables.** `MultiActionBars.xml` del cliente
(sacado de `locale-esES.MPQ`, que es donde vive el XML de FrameXML -- el
`patch-esES.MPQ` solo trae los ficheros que cambiaron) dice dos cosas: que
`MultiBarRight` cuelga de **UIParent** y no de `MainMenuBar` -- asi que esconder
la barra de abajo no se las lleva -- y que esta anclada a **98 pixeles** del
borde inferior. La consola ocupa el 20% del alto de pantalla. Los tres botones
de abajo de cada columna quedaban detras de ella: visibles a medias y sin poder
pulsarlos, que es la version cara de "esta puesto pero no funciona". Se levanta
el ancla mientras dura el modo y se devuelve al salir, con la regla de capturar
y devolver de siempre; `MultiBarLeft` cuelga de `MultiBarRight`, asi que mover
una mueve las dos.

**Y el icono de un macro NO es una ruta.** Esto se leyo en
`Blizzard_MacroUI.lua` de este cliente antes de escribir una linea, y es la
diferencia entre 24 macros con icono y 24 con interrogacion:

```lua
index = CreateMacro(MacroPopupEditBox:GetText(), MacroPopupFrame.selectedIcon, ...)
...
MacroFrameSelectedMacroButtonIcon:SetTexture(GetMacroIconInfo(MacroPopupFrame.selectedIcon));
```

`selectedIcon` es el **indice** dentro de la lista de iconos de macro del
cliente. Pasar `Interface\Icons\Loquesea` no da error -- dibuja nada, que es el
modo de fallo por defecto de este cliente. Asi que `Macros.lua` recorre
`GetMacroIconInfo` una vez, guarda nombre -> indice, y **canta por pantalla** lo
que no encuentre. Del mismo fichero salen los topes que no hay que recordar de
memoria: 36 macros de cuenta, 18 de personaje, 16 letras de nombre
(`letters="16"`) y 255 de cuerpo.

Dos decisiones mas, las dos por un fallo ya pagado:

- **Se actualiza, no se borra y se crea.** Una barra de accion guarda el INDICE
  del macro. Borrar y recrear recoloca los indices, asi que el boton que el
  jugador habia colocado acabaria apuntando a otro macro. Volver a dar a `/rts
  macros` tiene que ser gratis.
- **No se cachea una lista de iconos vacia.** Si la lista aun no esta, cachear
  el fallo lo deja fallando para siempre -- que es exactamente lo que tuvo al
  FOV tres etapas muerto por un CVar que no existia todavia.

Los macros salen por `/rtscmd`, que manda **a los seleccionados** y, si no hay
nadie, a todo el grupo DICIENDOLO; `/rtsall` va siempre al grupo. Pasan por
`Orders`, o sea que heredan la cola de envio: cuatro susurros en el mismo frame
se los come el limite de ritmo del chat sin un solo error.

El catalogo se comprueba en `sim/macro_catalog.py`, que lee el propio
`Macros.lua` y lo contrasta contra el CLIENTE (los iconos, por
`SpellIcon.dbc` + `ItemDisplayInfo.dbc`) y contra el MODULO (los comandos, por
`ChatCommandHandlerStrategy.cpp`, y las estrategias de `co`/`nc`, por
`StrategyContext.h`). Con `--break` se le mete un nombre largo, un icono que no
existe y un comando inventado, y caza los cuatro fallos. Si alguna de las dos
fuentes no esta en la maquina, lo dice en vez de dar por bueno lo que no ha
mirado.

**La leccion cara de la ronda no fue de WoW:** editar Lua con escapes desde una
cadena del shell se comio los `\\1` de un `re.sub` y dejo bytes `\x01` dentro del
fichero. Es la regla que ya estaba escrita -- *"para tocar codigo con escapes,
fichero y editor, nunca una cadena del shell"* -- y la cuarta vez que se paga.
`check_addon.py` lo cazo en un segundo, que es justo para lo que esta.

## La posesion, borrada entera. 2026-09-11 (tarde)

Empezo como un detalle: *"el boton de poseer, si le haces click derecho posees
raro. Eso quitalo, es una mierda"*. Era el click derecho del boton **Control**
de la rejilla 4x4. Se quito el gesto, se dijo que la posesion seguia viva por
otras dos puertas -- `/rts play` y su tecla -- y la respuesta fue *"quitala del
todo"*.

**Y tenia razon desde el principio, que es lo incomodo:** el precio estaba
escrito en la cabecera de `Possess.lua` **el dia que se escribio**, en un bloque
titulado "LO QUE ESTO NO DA, DICHO POR DELANTE". La posesion cambia quien te
MUEVE, no quien ERES; los manejadores de interaccion del nucleo
(`HandleGossipHelloOpcode`, vendedor, entrenador, botin, misiones) trabajan
sobre `_player`, no sobre el `m_mover`. Asi que hablar con un PNJ mientras
posees va por TU personaje, parado en otro sitio, y falla por distancia. Se
construyo sabiendolo, y lo que se entrego fue media funcion. Escribir el precio
por delante funciona; lo que falla es leerlo **antes de construir**, no despues.

Lo borrado, de las dos mitades a la vez:

| Addon (1.14.0) | mod-rts (0.49.0) |
|---|---|
| `Possess.lua` entero y su linea del `.toc` | el verbo `POSSESS` |
| `RTSCommand_TogglePossess`, su `Binding` y su `BINDING_NAME` | `PossessBot`, `ReleaseBot` |
| `/rts play` y su linea de ayuda | `ReleaseAnyPossession`, `ReleaseAll` |
| el click derecho de **Control** y la bandera `rmb` | `FillPossessBar` y `g_possessed` |

**La parte que habia que pensar era quitar los dos seguros del `ABORT()`.**
`ReleaseAnyPossession` se llamaba en el logout y en el cambio de mapa, y existe
por un worldserver muerto con volcado el 2026-09-03: un `Player` charmado sin
aura llega a `Player::RemoveFromWorld` -> `StopCastingCharm`, que solo sabe
quitar auras, no encuentra ninguna y responde con `ABORT()`. Borrar una guarda
que costo eso da respeto.

Se borran igualmente, y el razonamiento es el que manda el propio documento:
`PossessBot` era **lo unico de este modulo que charmaba a un `Player`**, asi que
sin el la guarda no puede dispararse nunca -- *"una comprobacion que no puede
dispararse es peor que no tenerla, porque parece cubrir un caso que en realidad
esta descubierto"*. Y hay una razon mas fuerte: el unico charm de `Player` que
queda en el juego es el **Control Mental de un sacerdote**, que lleva aura de
verdad y el nucleo deshace solo; la guarda del logout se la habria comido por
delante. La camara no entra en nada de esto -- es un Puppet y se suelta por
`camera::Abandon`, que ademas devuelve la criatura a su mapa.

Un comentario en `RtsCommandMode.cpp` decia *"dos sitios ponen `+passive` en los
dos estados: `Suppress` y `PossessBot`"*. Ahora es uno, y se ha corregido:
**un comentario que cita un simbolo borrado es una pista falsa**, y este
proyecto ya perdio vueltas siguiendo pistas falsas escritas por el mismo.

Epilogo para una linea vieja de `CLAUDE.md`. Decia que la unica vez que dejar
codigo sin llamante salio bien fue `PossessBot`, porque estaba documentado por
que se dejaba. Se sostiene a medias: volvio a usarse, y al volver reintrodujo
entero el `ABORT()` que la camara ya habia sufrido. Guardar un año de codigo no
salvo ni una hora de las que costo. Esta vez se borra de verdad -- git lo tiene,
y la cura de raiz esta escrita en el hueco que dejo: que la posesion lleve un
aura de verdad (`SPELL_AURA_MOD_POSSESS`), que es lo que `StopCastingCharm` sabe
deshacer.

---

# Apendice -- el texto original de las etapas 1-4 y de `rts-tools`

Recuperado aqui el 2026-09-09 al cortar `CLAUDE.md`: son las instrucciones de
instalacion tal y como se escribieron. La version operativa y actualizada esta
en `CLAUDE.md` ("Instalar desde cero"); esto es el original, con el detalle de
las lecciones del instalador y la historia de `sync.ps1`.

## Stage 1 — toolchain and first build

Prerequisites: Visual Studio 2022 Community with the "Desktop development with C++"
workload, Git for Windows, CMake (on PATH), Boost (prebuilt MSVC 14.3 x64, 1.81+),
OpenSSL 3.x (Win64, DLLs to the OpenSSL binaries dir), MySQL 8.0, 7-Zip.

Set `BOOST_ROOT` as a system environment variable, then reboot.
Add `C:\Server` as a Windows Defender exclusion — this can roughly halve build time.

Verify Boost and OpenSSL version pins against the AzerothCore Windows wiki before
building. Version mismatch is the most common cause of a failed first build.

```
mkdir C:\Server
cd C:\Server
git clone --branch Playerbot --single-branch https://github.com/mod-playerbots/azerothcore-wotlk.git azerothcore

cd C:\Server\azerothcore\modules
git clone https://github.com/mod-playerbots/mod-playerbots.git
git clone https://github.com/azerothcore/mod-autobalance.git
git clone https://github.com/azerothcore/mod-ah-bot.git
git clone https://github.com/azerothcore/mod-learn-spells.git
```

CMake settings:
- Generator: Visual Studio 17 2022, platform x64
- `CMAKE_INSTALL_PREFIX` = `C:/Server/dist`
- `TOOLS_BUILD` = `all`
- `WITH_WARNINGS` = OFF (playerbots is not warning-clean; this speeds up rebuilds)

Build in **Release**, then build the `INSTALL` project.

**Checkpoint:** `worldserver.exe` and `authserver.exe` exist in `C:\Server\dist`.

## Stage 2 — database

Create `acore_auth`, `acore_characters`, `acore_world` plus a MySQL user.
Copy the `.conf.dist` files in `dist/etc` to `.conf` and set DB credentials.
First worldserver launch auto-imports the world database.

**Checkpoint:** worldserver starts and reaches its console prompt.

## Stage 3 — client data

Needs a WoW 3.3.5a client, build 12340. Produce `maps`, `vmaps`, `mmaps`, `dbc`
into `C:\Server\dist\data`.

`mmaps` are mandatory for bots — without them bots cannot pathfind and will stand
still. Generating mmaps locally takes hours; prebuilt client data packs exist and
are the recommended shortcut.

**Checkpoint:** log in, create a character, stand in the world.

## Stage 4 — bots

- `playerbots.conf` — configure bot counts. `AiPlayerbot.RandomBotTalk = 1` (default)
  so bots use their own built-in chat lines — nothing else to configure here.
- Summon a companion into your party with `.playerbots bot add <name>`, control it
  with chat commands (`stay`, `follow`, `attack`, etc.) — no addon needed.

**Checkpoint:** a bot follows and responds to chat commands in-game.

## Where the source lives — one original, one direction

Adopted 2026-08-17, replacing a backup-mirror arrangement that had both
directions and cost a day.

**`C:\Server\rts-project` is the source of truth.** It is the git repo
(`Unoriginal02/wow-rts-command`), and all three pieces are edited there:

| Source | Deployed to | Button |
|---|---|---|
| `rts-project\addon` | `D:\GAMES\WOW WOTLK\Interface\AddOns\RTSCommand` | `rts-tools\Deploy_Addon.bat` |
| `rts-project\mod-rts` | `azerothcore\modules\mod-rts` | `rts-tools\Deploy_Mod.bat` |
| `rts-project\rts-client-mod` | nowhere — compiled in place | — |

Deploy is `robocopy /MIR`, out only. There is no way back in, deliberately.

### La copia de este fichero dentro del repo, BORRADA 2026-08-27

`rts-project\docs\CLAUDE.md` era una copia de este mismo fichero. Se quedo
congelada en la etapa 5i — decia *“Latest is `PRUEBAS-9.txt`”* cuando la ronda
real iba por la 18 — y describia como comprobado un `check_addon.py` que desde
la 5m hace dos comprobaciones mas.

**Es exactamente el fallo que el apartado de arriba documenta, aplicado a la
documentacion en vez de al codigo:** dos copias sin direccion estructural, y
“cual es la buena” contestado solo por una marca de tiempo. Con el addon eso
costo un dia y 247 lineas perdidas. Aqui el precio habria sido peor de detectar,
porque una copia vieja del plan no da error — se lee igual de bien que la nueva
y manda a arreglar cosas que ya estan arregladas.

**El precio de borrarla, dicho por delante:** este fichero ya no tiene ninguna
copia fuera de este disco. Es la misma exposicion que `rts-tools`, y se paga con
la misma moneda — una linea en `MUDANZA.md` §1, donde ahora esta listado como el
fichero mas caro de perder de toda la mudanza: lo demas se recompila o se
descarga, esto no. Un fichero que envejece en silencio es peor respaldo que una
linea en una lista que si se lee.

### `C:\Server\rts-tools` — the buttons, 2026-08-17

Everything we wrote that is *run* rather than *built* lives there and nowhere
else: the launchers (`Iniciar_Servidor`, `Detener_Servidor`, `Jugar`,
`Actualizar_Mundo`), the two deploy buttons, `srp6_account.ps1` and
`check_addon.py`. `C:\Server` root now holds only `CLAUDE.md` plus folders.

It was briefly duplicated into `rts-project\scripts` as well. That copy is
**deleted**, on the same reasoning as `sync.ps1` below — two copies with no
structural direction is a bug waiting for a timestamp to trigger it.

**The mudanza scripts are gone, and the split is the point.** The old pair tried
to do two jobs at once. *Copying* your data is judgement — which folders, which
drive, what fits — and it is now a manual checklist in
`rts-project\docs\MUDANZA.md`. *Installing prerequisites* is mechanical and
verifiable, so it survives as `rts-tools\Instalar_Requisitos.ps1` (+ a `.bat`
that only elevates). It installs nothing of yours and copies nothing — it just
gets a bare PC to the point where the core compiles.

**It verifies against the disk, not the installer's exit code.** The silent-install
flags for Boost and OpenSSL are guesses at Inno Setup convention, so each step
finishes by testing for `boost\version.hpp` / `bin\openssl.exe` and, if missing,
prints the exact file to fetch and where to put it. Same for downloads:
SourceForge will happily serve an HTML interstitial under the requested
filename, so the download is rejected unless it starts with `MZ`. slproweb
retires old OpenSSL builds, so that URL is the first thing here that will rot.

**Detection is the part that was actually wrong.** The first version tested
hardcoded `Program Files` paths and would have reinstalled over working
software: on this machine winget had put Git and Python under
`%LOCALAPPDATA%\Programs` (per-user) and left `7z.exe` off `PATH` entirely —
three different shapes among four packages. It now checks `PATH` *and* a
candidate list. Caught by running the detection against this PC before shipping
it, which took one command.

**The tradeoff, stated so it is not a surprise:** `rts-tools` is outside the git
repo, so it is *not* on GitHub and a disk failure loses it. With the mudanza
scripts gone, nothing carries it automatically either — it has to be copied by
hand on a move, which `MUDANZA.md` §1 lists. Every path inside these scripts is
absolute and none of them call each other, so they run from anywhere.

**What the old arrangement cost.** `sync.ps1` pulled the three pieces *in* from
where they lived, making this folder a backup. Both directions existed, so
"which copy is newer" was a question with no structural answer — only a
timestamp. On 2026-08-16 the addon was edited until 22:06, the last sync had run
at 19:04, and moving the server to a second machine installed the 19:04 copy.
`RTSMode.lua` was short by 247 lines including `CameraTurned()` — the drag
detection that Stage 5h had just added — so box-select silently did nothing on
the new machine, with no Lua error to point at it. The addon was the only piece
that could go stale this way, because it is the only one living outside
`C:\Server` and therefore the only one not carried by copying that folder.

`rts-tools\2-Jugar.bat` deliberately does **not** deploy: it launches the client and
injects, nothing else. Deploying is a decision, not a side effect of pressing
play.

## Comprobar el addon antes de darlo por bueno

```
python C:\Server\rts-tools\check_addon.py
```

Sintaxis, **cadenas sin cerrar**, **escapes desconocidos** y **locales usadas
antes de declararse**. Lo segundo es el fallo que ya
ha costado dos rondas de pruebas, las dos veces igual: una `local function`
definida por debajo del sitio donde se llama compila como una busqueda de
GLOBAL, encuentra nil, y revienta al ejecutarse -- dejando la secuencia a
medias. La primera vez dejo la camara sin soltar; la segunda impidio salir del
modo RTS. El parser no lo ve, porque el fichero es sintacticamente valido, y WoW
esconde los errores de Lua salvo que `scriptErrors` este a 1. Correrlo cuesta un
segundo.
