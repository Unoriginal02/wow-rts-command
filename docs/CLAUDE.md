# AzerothCore + Playerbots — build plan

Place this file at `C:\Server\CLAUDE.md`.

## Goal

A private WotLK 3.3.5a server for solo/small-group play with 1–4 AI companion bots.
The bots are mechanically driven by the playerbots engine only. There is no LLM/chat
layer and no client-side bot-management addon — companions are controlled entirely
through playerbots' own chat commands (`stay`, `follow`, `rti skull`, etc.) and the
`.playerbots` GM commands.

## Architecture

```
WoW client 3.3.5a  <->  worldserver.exe (+ mod-rts)  <->  MySQL 8
      ^
      +-- RTSCommand addon   (UI, selection, input, command card)
      +-- rts_core.dll       (client-local only: world coords, tints)
```

No external bridge process, no LLM API calls — worldserver and the client are the
whole system.

**Layer rule, adopted 2026-08-14.** Anything needing authority goes in the server
module. Anything that is purely client-local *and* invisible to Lua goes in the
DLL — world coordinates, cursor raycast, model tints, and nothing else. Anything
else is addon Lua. The DLL stops growing; the risky work moves to ordinary
server code with a documented API. A plain client-side addon (pure Lua, no bridge, no external API/LLM)
is fine; it just fires the same playerbots chat commands you'd type by hand.

## Decisions already made

- **Fork, not upstream.** `mod-playerbots/azerothcore-wotlk`, branch `Playerbot`.
  mod-playerbots requires core patches and will NOT build against stock AzerothCore.
  This is required for playerbots' bot mechanics themselves — nothing to do with chat
  or addons, so it stays regardless of what else is or isn't installed.
- **No LLM chat layer, no server-bridge addon.** Tried and removed 2026-08-07:
  `mod-llm-chatter` (Claude-driven dialogue, needed a Python bridge) and
  `mod-multibot-bridge` (server-side support for the "MultiBot-Chatless" client
  addon). Both required an external bridge process and/or an LLM call — that's what
  got removed, not addons in general. A plain client-side addon (pure Lua, no
  bridge, no external API/LLM) that just fires the same playerbots chat commands is
  fine — e.g. the quick-command-bar addon in `Interface\AddOns` on the client at
  `D:\GAMES\WOW WOTLK`.
- **Native Windows build** (Visual Studio + CMake), not Docker. Docker playerbots
  installs are experimental with limited support.
- **NOT installing mod-individual-progression.** Normal WotLK rules, everything
  unlocked from level 1.
- **NOT installing mod-eluna.** It forces the server onto a single core, which is
  documented as bad for playerbot performance.
- **AHBot, not Auctionator.** Auctionator is reported to crash alongside playerbots.
- **RTS mod is layered: Lua addon first, DLL only for what Lua cannot do.**
  Re-planned 2026-08-13, replacing an earlier DLL-first plan that was discarded.
  WotLK 3.3.5a Lua cannot control the camera, raycast a screen click to a world
  position, or project world→screen — those three, and only those, need an
  injected DLL. Everything else (selection model, orders, command card, control
  groups) is a plain Lua addon, because it iterates fast and cannot crash the
  client. Orders route through mod-playerbots' existing chat commands; no server
  module is needed. See Stage 5.

## Paths

| What | Where |
|---|---|
| Source | `C:\Server\azerothcore` |
| Build dir | `C:\Server\build` |
| Install output | `C:\Server\dist` |
| Boost | `BOOST_ROOT` env var, e.g. `C:\local\boost_1_81_0` |

Do not move the project into OneDrive, Documents or Desktop. Keep the path short.

## Modules

Active, in `modules/`:
- `mod-playerbots` — https://github.com/mod-playerbots/mod-playerbots
- `mod-ah-bot` — populates the auction house
- `mod-autobalance` — scales instances to real group size
- `mod-learn-spells` — auto-learn on level up
- `mod-rts` — **ours**, not a clone. Server half of the RTS layer: detached
  camera, and later bot possession and real order dispatch. See Stage 6.

Not installed, still just an idea if ever revisited: solo LFG/RDF (queue for
dungeons with a bot group).

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

## Stage 5 — RTS-style control (in progress)

Goal: play the party like Warcraft 3 — free camera, select units, order them to
positions, attack — plus a way to act as an individual unit.

### Order channel (verified, no server changes needed)

An earlier plan claimed playerbots supports only preset formations and no
free-form per-bot placement. **That is wrong.** Verified in
`modules/mod-playerbots/src`:

| Command | Source | Effect |
|---|---|---|
| `go X;Y;Z` | `Ai/Base/Actions/GoAction.cpp:113` | move to exact world coords, float precision |
| `go <playerName>` | `Ai/Base/Actions/GoAction.cpp:100` | move to a named nearby friendly — **needs no coordinates** |
| `position guard X,Y,Z` | `Ai/Base/Actions/PositionAction.cpp` | set a hold point (int precision) |
| `formation <name>` | `Ai/Base/Value/Formations.cpp:530` | `melee queue chaos circle line shield arrow near far` |
| `stay` `follow` `attack` `pull` `flee` `cast` `grind` `max dps` `tank attack` | `Ai/Base/Strategy/ChatCommandHandlerStrategy.cpp` | as named |

Whispering a bot runs the command on **that bot alone**; PARTY/RAID chat runs it
on all of them (`Bot/PlayerbotAI.cpp:582`). That is the whole RTS order channel —
**no server module required.**

Note Lua has no access to server world coordinates (only normalized 0–1 map
coords), so `go X;Y;Z` is unusable until the DLL lands. `go <playerName>` covers
"rally to me" in the meantime.

### Layers

1. **Lua addon `RTSCommand`** — edited in `C:\Server\rts-project\addon`, deployed
   to `D:\GAMES\WOW WOTLK\Interface\AddOns\RTSCommand` (see *Where the source
   lives* below).
   Selection model, control groups, command card, order dispatch (throttled —
   unthrottled whispers get silently eaten by the client's chat rate limit).
   Separate from Jairo's existing `PlayerbotCommander` addon; both can coexist.
2. **`rts_core.dll`** — `C:\Server\rts-project\rts-client-mod`, separate CMake project, **not**
   part of the AzerothCore build. Only three jobs: world coordinates, cursor→world
   raycast, world→screen projection. Builds `-A Win32` (`Wow.exe` is x86; CMake
   hard-fails otherwise), static CRT, no third-party deps. Registers `RTS_*`
   globals into the client's Lua; `Bridge.lua` polls for them and wraps them into
   `Bridge.impl`. See that project's README.
3. **mod-playerbots** — unmodified, executes the orders.

### Client offsets

In `rts-client-mod/src/Offsets.h`, verified against this exact `Wow.exe`
(MD5 `45892BDEDD0AD70AED4CCD22D9FB5984`) by static PE analysis rather than
trusted from memory. `FrameScript_RegisterFunction` (`0x00817FD0`) was
disassembled to confirm it loads the global `lua_State*` from `0x00D3F78C`, so it
takes **no** state parameter. `lua_type` at the commonly cited `0x0084DD60` is
**not** a function entry on this binary and is deliberately unused.
Re-verify if the client is ever swapped.

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

### Build note

Adding a module does **not** force a playerbots rebuild — its objects are cached
and only the new module compiles and relinks. Do not try to slim playerbots down
for build speed: its class AI *is* those files, removing them breaks the loader,
and it would wreck the periodic upstream pull. Test-loop speed comes from cutting
random-bot counts in `playerbots.conf` (startup), and from building the
`worldserver` target with `/m` rather than `ALL_BUILD` → `INSTALL`.

## Siguiente capitulo: la UI del modo RTS

`UI-RTS-ESTUDIO.md` es el estudio previo para sustituir toda la interfaz por una
HUD estilo WC3/SC2 en modo RTS. Leerlo antes de dibujar arte: tres de sus
hallazgos obligan a rehacerlo si se descubren tarde -- las texturas son
potencias de dos hasta **512**, la escala de UI hace que 1 unidad sean 1.61
pixeles en su equipo (arte borroso salvo que la HUD lleve su propia escala), y
`UIParent:Hide()` esconde tambien el botin, el gossip, las bolsas y el menu de
escape.

La decision que bloquea todo lo demas esta en su apartado 8: ocultar todo y
reparentar ventanas, u ocultado selectivo.

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

`rts-tools\Jugar.bat` deliberately does **not** deploy: it launches the client and
injects, nothing else. Deploying is a decision, not a side effect of pressing
play.

## Comprobar el addon antes de darlo por bueno

```
python C:\Server\rts-tools\check_addon.py
```

Sintaxis, y **locales usadas antes de declararse**. Lo segundo es el fallo que ya
ha costado dos rondas de pruebas, las dos veces igual: una `local function`
definida por debajo del sitio donde se llama compila como una busqueda de
GLOBAL, encuentra nil, y revienta al ejecutarse -- dejando la secuencia a
medias. La primera vez dejo la camara sin soltar; la segunda impidio salir del
modo RTS. El parser no lo ve, porque el fichero es sintacticamente valido, y WoW
esconde los errores de Lua salvo que `scriptErrors` este a 1. Correrlo cuesta un
segundo.

## Unverified work

`PRUEBAS-N.txt` in `rts-project\docs` is the running test list, in Spanish, one
file per round — everything built and installed but not yet seen working. Marked
`[x]` works, `[!]` fails, `[?]` unclear, with a `notas:` line under each. Each
entry says what a failure would actually *mean*, so a bad result narrows the
problem rather than just reporting it. Latest is `PRUEBAS-8.txt`.

## Update policy

Keep git remotes intact and keep `C:\Server\build`. Incremental rebuilds skip CMake
entirely and take minutes. mod-playerbots is actively developed and ships real bug
fixes, so pulling it periodically is worthwhile.
