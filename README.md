# RTS Command

An RTS-style command layer (Warcraft 3 / StarCraft) for a private World of
Warcraft 3.3.5a server running AzerothCore + mod-playerbots.

You take your own alts, bring them in as bots, and the game starts being played
from above: free camera, box selection, mouse orders, and a bottom bar that
commands the whole party. The things WoW simply does not have — seeing a party
member's bags, their quest log, talking to a trainer *as them* — get drawn here.

**This folder is where the work happens.** It is the original of all three
pieces. What lives inside the WoW client and inside AzerothCore are deployed
copies.

| Piece | Version | What it is |
|---|---|---|
| `addon/` | 1.42.0 | Lua addon: UI, selection, orders, camera |
| `mod-rts/` | 0.55.0 | AzerothCore module: orders straight into the AI, quests, bags, NPCs, character swap |
| `rts-client-mod/` | `rts_core.dll` 0.30.0 | Injected into the client: world coordinates, raycast, native effects |

```
WoW client  <->  worldserver (+ mod-rts + mod-playerbots)  <->  MySQL
     ^
     +-- RTSCommand addon   (UI, selection, orders)
     +-- rts_core.dll       (local only: coordinates, raycast, native effects)
```

> The in-game commands and the UI are in Spanish, because that is the language
> this is played in. Command names appear here verbatim — they are what you
> actually type.

---

## Contents

1. [Getting started](#1-getting-started)
2. [Where everything is](#2-where-everything-is)
3. [Features, by area](#3-features-by-area)
4. [What we touch in the client and the core](#4-what-we-touch-in-the-client-and-the-core)
5. [Deploying and building](#5-deploying-and-building)
6. [Repository rules](#6-repository-rules)

---

## 1. Getting started

1. `C:\Server\rts-tools\1_Iniciar_Servidor.bat` — brings up the worldserver.
2. `C:\Server\rts-tools\2-Jugar.bat` — launches WoW **and injects
   `rts_core.dll`**. Without it there is no free camera and no click-to-ground:
   the addon refuses to start the camera rather than pretend it works.
3. In game, on any character: put the **Traer bots** order in a tray slot (or
   type `/rts invitar`), then enter RTS mode with `/rts mode`.
4. `/rts` on its own prints the full help — about sixty lines.

The bot roster `invitar` uses is changed with
`/rts invitar lista Neferite,Kirinah,Avy`.

---

## 2. Where everything is

### The mouse, in RTS mode

| Gesture | What it does |
|---|---|
| Left-click a unit | select it (**shift** adds or removes) |
| Left-drag on the ground | box selection |
| Left-click empty ground | deselect |
| **Alt** + click a unit | take direct control of it |
| Right-click the ground | send the selection there |
| Right-click an enemy | attack it |
| Right-click an NPC | interact |
| **Shift** + right-click | chain another waypoint |
| **Shift** + left-click a hostile | give it an attack-chain number (1..8) |
| Right-drag | turn the camera (the client's own mouselook). In the **hero view** it pivots around him and tilts instead |
| Left + right together | move forward, the usual gesture — **it does nothing today**: it reads `RTS_MouseRaw`, and no version of the DLL in this repo publishes it |
| Click a Blizzard party frame | select that unit, same rules |

### The keyboard

The free camera borrows eight keys for as long as RTS mode lasts, and **gives
them back on the way out** — they are recorded before being touched and never
saved, so a disconnect cannot leave you without WASD.

| Key | Free camera | Lock | Hero view |
|---|---|---|---|
| `W` / `S` | forward and back on the plane | nudge the offset from the hero | closer and further away, never past him |
| `A` / `D` | left and right on the plane | nudge the offset from the hero | pivot around him, with him in the centre |
| `SPACE` / `C` | up and down | up and down relative to him | raise and lower the height over his feet, without tilting |
| `Q` / `E` | turn | turn | pivot, the same as `A`/`D` |

Everything else is bound under **Options → Key Bindings → RTS Command**: enter
and leave the mode, camera, select all, clear selection, the five orders
(move/hold/follow/attack/attack-move), select unit 1..8, the ten spell slots,
the party bags, and four control groups (**Alt + key** saves the group, the key
alone recalls it).

### The bottom bar

```
+---------------------------------------------------------------+
|              Bob  (dps)                                       |
|        [1][2][3][4][5][6][7][8][9][0]    [M][M][M][M][M]      |
|        [ ][ ][ ][ ][ ][ ][ ][ ][ ][ ]                         |
|                                          [M][M][M][M][M]      |
|                                          [ the game's bags ]  |
|                                          [char][talents]...   |
+---------------------------------------------------------------+
```

- **Centre: the unit.** With one selected (or none, and then it is you): their
  name and **twenty spell slots, in two rows of ten**. The top row is bound to
  **1234567890**, and the number is drawn on the slot that owns it; the bottom
  row has no key, because there are no numbers left and Shift is already the
  "choose a target" modifier on the same button. With two or more: one column
  per head with a 2x2 of **four** — and those are *a different list*, the things
  you cast on the group, not the first four of the ten. **The same ten keys
  follow**, split two per head: 1-2 the first column, 3-4 the second, up to 9-0
  with five picked. Again only the top row of each 2x2; the bottom one is for
  the mouse.
- **Right: your own stuff,** and it never moves: ten slots, the bags and the
  game menu.

### The ten tray slots

A slot takes two different things:

| Gesture | What it does |
|---|---|
| Right-click | the dropdown with the addon's order catalogue |
| Drag a macro onto it | puts that macro there (needed for `/cast`, `/use`, `/target`) |
| Left-click | fires whatever it holds |

The catalogue (`/rts ordenes`) ships: **Traer bots** (summon your bots into the
party), **Sígueme** (follow), **Quieto** (hold), **Reunir** (teleport the party
to you), **Cráneo** / **Luna** (skull / moon mark plus the matching order),
**Reset grupo**, **Control** (swap into the selected character), **Bolsas**,
**Misiones**, **Candado** (camera lock), **Cámara** and **Modo RTS**. The custom
icons are our own art, not from the client's closed macro-icon list.

> **The exception:** an order can carry a **second order** on right-click. Today
> only **Candado** does: left-click pins the camera at whatever distance it is
> at right now, **right-click puts it behind the hero and keeps it at his back**.
> On those slots the dropdown moves to **Shift + right-click**, and the tooltip
> says so.

---

## 3. Features, by area

Every row says **where it lives**. The reasoning behind each decision — dead
ends included — is in the header of the file that implements it.

### 3.1 The camera

| Feature | How you use it | Where it lives |
|---|---|---|
| **RTS free camera** — flies on the plane, rises and falls, follows the ground | `/rts mode`, `/rts cam` | `addon/FreeCam.lua` |
| **Lock** — pins the camera at a fixed distance from the hero and travels with him | Candado slot, `/rts fc lock` | `addon/FreeCam.lua` |
| **Hero view** — one click puts the camera behind him and keeps it at his back | **right-click** Candado, `/rts fc ojos` | `addon/FreeCam.lua` |
| **Escape hatch** — brings the camera back over your hero | `/rts fc home` | `addon/FreeCam.lua` |
| **Entering backs the camera off the hero**, instead of parking on his head | `/rts fc back <yd>` (15 by default, 0 = on top) | `addon/FreeCam.lua` |
| **"Ground" is not "the first thing underneath"** — a roof stops counting, so you can get inside buildings | `/rts fc floor 1` | `addon/FreeCam.lua` |
| **Step filter** — a slope is followed closely, a step is climbed slowly | `/rts fc climb/soft/slow` | `addon/FreeCam.lua` |
| **No collision** — the camera passes through geometry (caves) | `/rts fc noclip 1` | `addon/Camera.lua` |
| **Dot on the map** — where the camera is looking, on the world map | `/rts punto` | `addon/Radar.lua` |
| **Saved framing** — tilt, zoom, FOV, shadows | `/rts cam save/frame/fov/shadow` | `addon/Camera.lua` |
| **Possessed camera** (the old path, still there) | `/rts cam` without the DLL | `mod-rts/src/RtsCamera.cpp` |

The feel settings (`speed`, `lift`, `turn`, `height`, `smoothZ`, `ease`,
`pitch`, `clear`, `push`, `lockSmooth`, and the hero view's `eyeH`, `eyeD`,
`eyeTurn`, `eyeSnap`, `eyeBack`) are **per character** and are listed by
`/rts fc`.

#### The hero view, in detail

**Right-click** the Candado slot and the camera appears **behind your hero** —
four yards up, six yards back — looking the way he looks, and stays at his back
while he walks, fights, or his AI drives him. If he turns, it comes round with
him.

| | |
|---|---|
| `W` / `S` | closer and further away. It stops a yard short of him instead of crossing over |
| `A` / `D`, `Q` / `E` | pivot around him, with him in the centre |
| `SPACE` / `C` | raise and lower the height over his feet. A straight translation: it does **not** tilt as it goes |
| Right-drag sideways | the same pivot |
| Right-drag up and down | tilt the view up and down |

**The pivot is measured from his nose, not from the world**, and that one
decision is the whole mode. The camera sits at `his facing + orbit`, and the
pivot is the only thing that writes `orbit` — so zero is his back and **stays**
his back through every turn he takes, and if you pivot round to his flank you
keep the flank, turn after turn.

**A spin is absorbed, not followed.** Clicking the ground behind you spins the
hero 180° in a single tick, and a camera glued to his facing replays that as a
whip-pan. Instead the jump is *moved* from his facing to the orbit — both
together are the camera, so it does not shift by one degree — and then, **once
he starts walking**, the camera drifts back behind him at a deliberately slow
20°/s. A hand on `A`/`D` or on the mouse cancels that return.

**The mouse is split in two.** The yaw cannot simply be adopted the way it is in
every other mode — it is a consequence of where the hero looks — so what is read
is the *difference* the client has added since the last frame, and that is spent
on the orbit. The tilt **is** adopted whole, so dragging up looks up, at your own
sensitivity and with your own inversion.

- **The default height is 4 yards** over his feet, measured in game four times:
  2.2 (a human's head, literally inside), 7, 5, and 4 once the camera moved
  behind him instead of over him.
- **The height and the distance are saved, the side you were watching from is
  not.** `SPACE`/`C` and `/rts fc eyeH <n>` write the same number, `W`/`S` and
  `/rts fc eyeD <n>` the same again — so the spot you back off to is the spot you
  get next time. The orbit resets to zero on the way in, **and that is what makes
  the button worth pressing**: one click always puts you at his back.
- **`/rts fc eyeSnap <deg>`** is what counts as a spin (12° between two readings)
  and **`/rts fc eyeBack <deg/s>`** how slowly it comes home. `eyeBack 0` never
  comes home on its own, which is the sticky framing of the first version.
  The line is low because what it has to catch is **an order, not a big
  angle**: a waypoint clicked slightly off to one side turns him twenty
  degrees in one tick, and following that round is what read as the camera
  turning with him too directly. What is left under it — a hero leaning into a
  curve — is trailed at `eyeTurn`, and that trails lazily too (2.5, was 6).

Known and not fixed: **there is no ground under this camera**, the same as the
lock. Going downhill the terrain behind it sits higher than it does and, with
`noclip` on, you see the inside of the hill.

You leave with another right-click, with a left-click (which releases the whole
lock), or with `/rts fc home`.

### 3.2 Selection

| Feature | How you use it | Where it lives |
|---|---|---|
| Selection stored by name, not by unit token | — | `addon/Selection.lua` |
| Box selection | left-drag | `addon/RTSMode.lua` |
| Control groups (4) | Alt+key saves, key recalls | `addon/Selection.lua` |
| **Native ground ring under the selection** — the client's own circle, correctly depth-tested | `/rts ring` | `addon/SelectionRing.lua` + `rts-client-mod/src/Circle.cpp` |
| **Model glow by state** — blue standing by, green walking, red fighting, orange interacting | `/rts state`, `/rts ring tint` | `addon/State.lua` + `rts-client-mod/src/Highlight.cpp` |
| **Health bars over heads** — the client's own nameplates, for enemies and for your bots, kept working under the free camera | `V`, `/rts plates friends` | `addon/Plates.lua` + `rts-client-mod/src/Plates.cpp` |
| The game's own unit frames select when clicked | click the frame | `addon/Portraits.lua` |

### 3.3 Orders and movement

| Feature | How you use it | Where it lives |
|---|---|---|
| Move / hold / follow / attack / attack-move | mouse, keys, `/rts move`, `hold`, `follow`, `attack`, `amove` | `addon/Orders.lua` |
| **Orders straight into the AI**, never through chat | automatic | `mod-rts/src/RtsOrders.cpp` |
| **Multi-point routes** | Shift + right-click | `addon/Route.lua` |
| **A long trip is cut into legs on the navmesh** | automatic | `mod-rts/src/RtsOrders.cpp` (`NextLeg`) |
| **A ground marker on every waypoint**, drawn by the client | `/rts mark next/prev/find/size` | `addon/Marks.lua` + `mod-rts/src/RtsMarks.cpp` |
| **"Go here" flare** | automatic on every order | `addon/Flare.lua` |
| **Attack chain** — mark 1, 2, 3, 4 and they go in that order | Shift + left-click a hostile, `/rts chain` | `addon/Chain.lua` + `mod-rts/src/RtsChain.cpp` |
| Formations | `/rts form near/far/melee/queue/chaos/circle/line/shield/arrow` | `addon/Orders.lua` |
| Gather (on foot) and Summon (teleport) | `/rts reunir`, `/rts traer` | `addon/Actions.lua` |
| Skull and moon marks with the order attached | `/rts craneo`, `/rts luna` | `addon/Core.lua` |
| Any raw playerbots verb | `/rtscmd <cmd>` (selection), `/rtsall` (whole party) | `addon/Orders.lua` |
| **Your own character fights with the playerbots AI** | `/rts self`, `/rts self auto` | `addon/RTSMode.lua` |

### 3.4 Spells

| Feature | How you use it | Where it lives |
|---|---|---|
| Twenty configurable slots per character (2 x 10), plus four group ones | right-click a slot, `/rts skills` | `addon/Skills.lua` (data) + `addon/Cast.lua` (drawing) |
| **1234567890 on the top row** — all ten on one head, or two per head with several picked. Borrowed while the console is open and handed back on close | automatic | `addon/Cast.lua` |
| **Cooldown swirls** — the client's own, on your hero for free and asked of the server for a bot | automatic | `addon/Cast.lua` + `mod-rts/src/RtsCommandMode.cpp` |
| **Spell queue** — pressing while the bot is busy leaves it waiting instead of failing | automatic | `mod-rts/src/RtsQueue.cpp` |
| **Focus** — the selected unit looks after whoever you click | `/rts focus` / `/rts unfocus` | `addon/Cast.lua` |
| **Casting a spell AS the bot** — the server casts it for him, with his queue and his checks | click a slot | `mod-rts/src/RtsCommandMode.cpp` |
| **His real action bar** — the one you built playing that character, read from `character_action` | on selecting him | `mod-rts/src/RtsCommandMode.cpp` |
| **Spell mirror** when leaving RTS mode in combat | automatic | `addon/Standby.lua` |
| **The server classifies every spell** — friendly, hostile, ground, dead, self — and the slot behaves accordingly | automatic | `mod-rts/src/RtsCommandMode.cpp` + `addon/Skills.lua` |

#### What a spell slot does when you press it

Nothing in the addon decides what a spell *is*. The server classifies each one
with the core's own predicates when it sends the bar, and sends a letter along
with the id — **there is no list of spell ids anywhere in this project**. That
letter is internal: it is never typed and never shown.

| Letter | What the core says it is | Pressing the slot |
|---|---|---|
| `S` | only on the caster | casts |
| `N` | no target (shouts, auras, stances) | casts |
| `T` | totem | casts |
| `A` | needs a friendly target | arms: the next left-click picks who |
| `H` | needs a hostile target | **casts on whatever you have targeted** |
| `G` | ground or area | arms: the next left-click picks where |
| `D` | on a dead unit (resurrect) | arms |
| `?` | not classified yet (the server has not answered) | arms |

Armed, the icon runs the pet-style circling light and the next **left-click**
chooses — in the party list or out in the 3D world, indifferently. **Right-click
cancels.**

- **`H` does not ask**, because attacking is the only thing done in bursts: one
  question per cast is fine for a heal and one keypress too many on the third hit
  against the same mob. The target has to **exist, be alive and be attackable** —
  and that third test is what makes the shortcut safe, because the usual reason
  for asking is that the client's target is normally just the residue of having
  clicked someone to select them, and that residue is always one of *yours*.
  With nothing hostile targeted it arms, exactly as before.
- **Alt** casts on the character himself without asking, the usual WoW
  convention.
- **Shift** asks anyway, whatever the letter says. It is the valve on the
  classification, and it is how you throw an `H` at something that is not your
  current target.

> `RtsCommandMode.cpp` also holds verbs **nobody calls today** — `AIM`, `ROLES`,
> `TGTS` — left over from when the single-piece console existed. They are alive
> on the server with no mouth in the addon: if that UI ever comes back, the
> backend is already there. They are not listed as features because today they
> are not.

### 3.5 The whole party — the things WoW never shows you

| Feature | How you use it | Where it lives |
|---|---|---|
| **Every party member's bags**, and moving items without a trade window | `/rts bags`, Bolsas slot | `addon/Bags.lua` + `mod-rts/src/RtsBags.cpp` |
| **The whole party's quest log** | `/rts quests`, Misiones slot | `addon/QuestBook.lua` + `mod-rts/src/RtsQuests.cpp` |
| **Quest sharing that actually works** — the server *gives* it to them rather than offering | the native quest log's Share button | `addon/Quests.lua` |
| **When you turn in, the party completes and gets paid too** | `/rts quests force` | `mod-rts/src/RtsQuests.cpp` |
| **Trainer and vendor, acting as the bot** | `/rts npc` | `addon/Npc.lua` + `mod-rts/src/RtsNpc.cpp` |
| Learn everything the trainer would sell him | button in the NPC window | `mod-rts/src/RtsTrain.cpp` |
| Sell the grey junk, repair | buttons in the NPC window | `mod-rts/src/RtsNpc.cpp` |
| **Swap characters without logging out** — the one you leave stays behind as a bot | `/rts swap <name>` | `mod-rts/src/RtsSwap.cpp` |
| Free-for-all party loot / make the bots pick up everything | `/rts loot`, `/rts lootall` | `addon/RTSMode.lua`, `addon/Loot.lua` |
| **Hide the bots' gossip dump** (and keep it) | `/rts chat`, `/rts chat ver` | `addon/Chatter.lua` |

### 3.6 The UI

| Feature | How you use it | Where it lives |
|---|---|---|
| Layout of the bottom bar | `/rts dock` | `addon/Dock.lua` |
| Ten-slot tray + bags + game menu | `/rts tray`, `/rts tray vaciar` | `addon/Tray.lua` |
| Order catalogue with custom icons | `/rts ordenes` | `addon/Actions.lua` |
| Export the catalogue as **real game macros** (for bars and key binds) | `/rts macros` | `addon/Macros.lua` |
| Selective hiding on entering RTS mode (by default, only the action bars) | `/rts ui` | `addon/Chrome.lua` |
| Floating windows (one implementation, three tenants) | `/rts win`, `/rts win reset` | `addon/Window.lua` |
| WC3 or flat skin, built from the client's own textures | `/rts skin`, `/rts skin wall <path>` | `addon/Skin.lua` |
| **Client texture browser** | `/rts art` | `addon/Art.lua` |
| Pixel scale | — | `addon/Pixels.lua` |
| Brightness of the portrait selection mark | `/rts marcos brillo 0.9` | `addon/Portraits.lua` |

### 3.7 Diagnostics

Almost every one of these exists because a specific bug cost an afternoon. Each
answers **one** question.

| Command | What it answers |
|---|---|
| `/rts native` | is the DLL injected, and are its offsets the right ones? |
| `/rts version` | versions of all three pieces |
| `/rts cam probe` | is the client's free camera usable here? step by step |
| `/rts fc` | free camera state: ground, rays, collision, the measured yaw mapping |
| `/rts fc mouse` | is the native turning reaching us, or are we overwriting it? |
| `/rts aim` | why the ground point lands where it lands (cursor vs. the DLL's ray) |
| `/rts cal` | measures the projection (fixes rings that sit short) |
| `/rts turn` | why a click got eaten: measures camera turn against the threshold |
| `/rts channel` | what the DLL is being told about your selection |
| `/rts pick` | what is under the cursor |
| `/rts debug` | echo of everything to and from the server module |
| `/rts bars` | what the SERVER has in your first twelve action slots |
| `/rts body` | **the body probe**: why your hero turns invisible |

---

## 4. What we touch in the client and the core

This is the part you do not see. Almost nothing here is a replacement: in nearly
every case **the game already knew how to do it** and what was missing was the
door.

### 4.1 The commentator camera (the "spectator cam")

This client ships a complete free camera, with a Lua API, that Blizzard put
there to broadcast arenas. It has been the RTS mode camera since 2026-09-07.

**What exists out of the box:** `CommentatorSetCamera`, `CommentatorGetCamera`,
`CommentatorSetCameraCollision`, `CommentatorSetMoveSpeed`,
`CommentatorFollowPlayer`, `CommentatorSetTargetHeightOffset`,
`CommentatorZoomIn`, `CommentatorZoomOut`.

**The door is two `PLAYER_FLAGS` bits.** The client's predicate at `0x006DE980`
answers "is this player a spectator" by reading bit 19 (`PLAYER_FLAGS_UBER`,
0x00080000) and bit 22 (`PLAYER_FLAGS_COMMENTATOR2`, 0x00400000). With 19 off it
returns `false` and there is no camera.

| Who sets what | Why |
|---|---|
| The **server** sets bit 22 | `Player::SetCommentator`, which already exists in the core. That is the one that skips the "must be on an arena map" requirement |
| **`rts_core`** writes bit 19 into the client's own copy | the core **refuses to let anyone carrying `UBER` attack** (`Unit.cpp:10762`), so setting it server-side left you unable to swing |

**Arming the mode is the server's job.** The client asks for the mode with
`CMSG_COMMENTATOR_ENABLE` (0x3B5) and waits for
`SMSG_COMMENTATOR_STATE_CHANGED` (0x3B6). That incoming opcode is `STATUS_NEVER`
in AzerothCore — it never even reaches a handler — so the addon asks over its
own channel and **mod-rts sends the 0x3B6** itself. The client's handler
(`0x0056B8A0`) requires the GUID to be its own, runs the predicate again, and
puts the active camera into commentator mode.

**And it goes in two halves, which is what the first attempt cost.** `Spectate`
sets the flags; `Arm` sends the packet. Doing both at once is a race:
`SetPlayerFlag` only marks the field dirty (it goes out on the next flush,
~100 ms later) while `SendPacket` leaves immediately. The packet arrived first,
the predicate read the old flags, and the closed-door branch **is not a no-op**:
it puts the camera into mode 1 with whatever state was lying around. On screen:
the camera flew off into the distance and under the floor. Now the addon polls
`CommentatorGetCamera()` — which returns six numbers only once the door is open
— and **only then** asks to arm.

**How control is divided:**

- **We own POSITION.** One write per frame,
  `CommentatorSetCamera(x, y, z, yaw, pitch, fov)`.
- **The client owns ORIENTATION.** Right-drag is the usual mouselook, with the
  sensitivity and inversion the player already has configured, for free. Since
  `SetCamera` takes all six values at once, every frame we **read** the live
  angles and **write them straight back**: for orientation it is a no-op, and
  the client's turning accumulates on its own.
- `CommentatorSetMoveSpeed(0)` shuts off the client's own WASD camera motor, so
  there are never two owners of the movement.

**Details that cost one pass each:**

| Thing | What was measured |
|---|---|
| FOV | sixth argument, in **degrees**, clamped 1..120. Passing 0 gives you **one degree** — a purple screen |
| *Pitch* | **positive looks down**. It is the opposite of what it looks like, and it cannot be read from the binary |
| Collision | `CommentatorSetCameraCollision` takes a **number**, not a bool, even though its own usage string says `bool`. It is restored to 1 on the way out: that is what the client writes at startup |
| Live yaw and pitch | `cam+0x11C` and `cam+0x120`, in radians, on the active camera |
| The yaw convention | **cannot be read from the binary.** So the hero view does not guess it: it measures it live, comparing `CommentatorGetCamera`'s yaw against the world-space forward vector the DLL publishes |

**The side effect: your own model disappears.** The flags that open the camera
also make the client stop submitting your character. The `0x006DE980` predicate
has **eighteen** call sites (measured with a `call rel32` sweep over `.text`,
not assumed), so forcing the predicate hid *everyone*. The culprit was found
**by elimination**: it is site `[16]`, `0x006E085C`, inside a virtual function
with no static references at all. `SelfShow.cpp` patches those five bytes
(`call rel32` → `xor eax,eax` + 3 `nop`, same length) so that *that one* caller
sees "not a spectator", and the other seventeen keep telling the truth.

> `addon/Body.lua` is the probe that cornered it, and it is still there, off by
> default.

**The old path still exists:** an invisible creature the player possesses, which
is the Eye of Kilrogg / Mind Control mechanism (`Player::SetClientControl` →
`SetViewpoint` + `SetMover`). It lives in `mod-rts/src/RtsCamera.cpp` and was
abandoned because, while possessing, **the client owns the position** and the
server can only move it with `NearTeleportTo`, which cancels whatever movement
is in progress.

### 4.2 Native client effects, reused

Anything drawn as a UI texture parked at a projected pixel **floats**: no depth,
drawn on top of the hill that should hide it, and swimming sideways whenever the
camera turns. So the markers that matter are not drawn by us — we ask the client
for them.

| What | How | Where |
|---|---|---|
| **Selection ring** | the client keeps **two** GUID slots on the scene context and drains them once a frame. We hook that drain (`0x004F6F90`), let it run once as usual, then hand it our units **one at a time**: each call draws one more ring, through its own code | `rts-client-mod/src/Circle.cpp` |
| **Model glow** | `CGUnit_SetHighlight` / `ClearHighlight` with its three "reasons", plus colour and intensity written into the render object (`+0x18C`, `+0x1B8`) | `rts-client-mod/src/Highlight.cpp` |
| **Attack chain numbers** | they are the client's **raid target icons**. It places them in its own loop from the world position, exactly like nameplates: they track perfectly because nothing is being tracked. The price is that there are eight | `addon/Chain.lua` |
| **Nameplates** | the client draws them, but its gate measures everything from the unit the **camera** is attached to — and the free camera is free precisely because that field is empty, so in RTS mode it refused every unit. Two instructions in the gate are rewritten to read the GUID from a slot in the DLL (the hero) instead of from the camera, the camera is left alone, and the 41-yard ceiling is widened while the free camera is up. Your own hero wears no bar, on purpose: the two further doors that would give him one were found (`/rts plates probe` nulls the gate's refusals one at a time until it says yes) and deliberately left unpatched — the reading is in `Offsets.h` | `rts-client-mod/src/Plates.cpp` |
| **Waypoint ground marker** | a `DynamicObject` carrying a spell's persistent-area visual — the same thing a Consecration patch is — placed in the world and drawn by the client with correct depth. The candidate list is **built from the loaded spell store** (every spell with a persistent-area-aura effect), not from IDs written from memory | `mod-rts/src/RtsMarks.cpp` |

A ring drawn by us did exist once, firing twelve rays down per unit to sample
the terrain, and it was parked: it never read as a ring lying on the ground, and
it never could have. The ray code is still in `GroundRing.cpp`.

### 4.3 The raycast: the one thing 3.3.5a Lua genuinely cannot do

There is no raycast in the API until Cataclysm. The addon used to fake it by
unprojecting the cursor onto a flat plane at the **player's** Z, which is exact
right next to your character and wrong everywhere else — hills, stairs, bridges
— and the free camera made it far worse, because the camera can now be a hundred
yards from the Z that plane is pinned to.

So we call `CGWorldFrame::Intersect` (`0x0077F310`), **the client's own picking
function**, the same one it uses to decide what your mouse is over. With two
flag masks:

- `0x00100171` — everything: terrain, buildings, doodads.
- `0x00000100` — **terrain only**. A roof stops being ground, which is what lets
  the camera get inside a house instead of climbing on top of it.

It is used for the point under the cursor, for the ring heights, and for the
free camera's three rays (ground, terrain and ceiling).

**And for the click itself, cast in the mouse message.** An order does not ask
"where is the cursor now", it asks "where was I aiming when I pressed", and the
two answers come apart in exactly the cases that matter: the continuous ray is
fired from the **Windows** cursor, which the client moves about on its own while
it owns the mouse — which is what a held button does — and it is up to a tick
old, which with a panning camera is a long way on the ground. In game that read
as *"only a patch in the middle of the screen works, further out the mark comes
back toward the centre"*.

`WM_LBUTTONDOWN` / `WM_RBUTTONDOWN` have neither problem, and the `WndProc` hook
already sees them. The pixel comes out of the message itself, the ray is cast
there and then with the camera of the frame the player was looking at, and the
result is published **before** the client is handed the message — so by the time
the addon's `OnMouseDown` runs, the answer to its own press is already a global.
No projection, no calibration, no tolerance, no plane. The ray is published with
the point, so the server's `GroundRay` clips the **same** straight line the
client saw rather than one Lua rebuilds from its own FOV and scale.

A sequence number says whether the press was seen. If it does not advance — no
DLL, or a client that does not deliver the mouse through the window queue — the
addon falls back to the plane estimate it used before, so the worst case is the
old behaviour rather than a broken one.

### 4.4 The Lua ↔ DLL bridge

**DLL to addon:** `FrameScript_Execute` (`0x00819210`) runs a Lua source string
in the client's global state, and what it runs is assignments to `RTS_*` globals
the addon reads: player position and facing, camera (position, 3x3 basis, FOV,
aspect), the three rays under the camera, the cursor point, the click
ray (`RTS_Clk*`, published from the button's own message), and the list of
nearby units.

Cadence: **100 Hz for the camera alone**, 33 Hz for the full state. The camera
runs faster because markers are placed from it, and a stale camera drags them
sideways while you turn.

**Addon to DLL: a CVar.** There is no other way. WoW 3.3.5a rejects C function
pointers living outside `Wow.exe`: calling one throws `ERROR #134` and takes the
client down with it (verified the hard way). A CVar is ordinary client memory,
Lua is allowed to write it with `SetCVar`, and the client parses it into an int
at `CVar+0x30`.

Protocol 3, 32 bits per tick:

```
bits  0..23   eight slots x three bits of state
bits 24..26   sequence number
bit  27       draw the native ground ring
bit  28       also glow the model
bit  29       diagnostic: a ring under EVERY published unit
bit  30       free
bit  31       unusable -- the client parses the value with a SIGNED atoi
```

CVars used: `enablePVPNotifyAFK` (the selection channel, **borrowed**, with its
original value saved and restored), `rtsFov` and `rtsBody` (**created** with
`RegisterCVar`, which exists in this client). Owning them is not cosmetic:
`SetCVar` on a name that does not exist **raises no error** — it does nothing,
which is exactly how an earlier channel stayed dead for three stages without
anyone noticing.

**The main thread:** `MainThreadHook` subclasses the WoW window's `WndProc`. A
`WndProc` is always dispatched on the thread that created the window, which is
the only thread where Lua may be touched. It replaced a D3D9 `EndScene`
trampoline that, under Windows 11's `d3d9on12` layer, hooked a vtable the client
does not actually call through — so it never fired.

### 4.4b Walking there: who decides the route, and where it went wrong

We do no pathfinding of our own, and should not: the server has Detour and the
mmaps. What we decide is **how much of a trip to ask for at once**, and that is
what was wrong.

A move order sets playerbots' `stay`/`return` anchor and wakes the AI. The bot's
own `MovementAction::MoveTo` then calls AzerothCore's `PathGenerator`, and so
does `PointMovementGenerator` underneath it. Two limits shape everything:

- `MoveToPositionAction::isUseful()` is `distance > followDistance && distance <
  reactDistance`. With `AiPlayerbot.ReactDistance = 150`, an anchor further than
  that **is not useful to the AI and the bot never starts**.
- `PathGenerator` gives up past `MAX_POINT_PATH_LENGTH` (74 points at a 4-yard
  step, so ~296 yards of path) and replaces the whole path with
  `BuildShortcut()` — **two points, start and end**.

So a long trip has to be cut into legs, and the addon used to cut it by
**geometry**: take the straight line to the waypoint, stop at a hundred yards,
interpolate the height. That cut knows nothing about a mountain in the way, so
the intermediate point landed on the mountainside — and a steep slope is not on
the navmesh. What the core does then is the whole bug:

```cpp
if (startPoly == INVALID_POLYREF || endPoly == INVALID_POLYREF)
{
    BuildShortcut();
    bool path = creature ? creature->CanFly() : true;
    if (path || ...) { _type = PATHFIND_NORMAL | PATHFIND_NOT_USING_PATH; return; }
```

A bot is a `Player`, not a `Creature`, so `creature` is null and `path` comes out
**true**: any off-mesh destination returns a straight line labelled
`PATHFIND_NORMAL`. playerbots accepts it — its filter is `PATHFIND_NORMAL |
PATHFIND_INCOMPLETE`. And `BuildShortcut` only grounds its **two** endpoints, so
the spline interpolates Z in a straight line between them: the bot goes through
the mountain, floating.

`orders::NextLeg` cuts the leg on the **navmesh polyline** instead
(`PathGenerator::GetPath()`), walking it until the budget runs out — so the
intermediate point is on the mesh by construction. Four path types are treated as
"the core is about to go straight" and refused: `NOPATH`, `SHORTCUT`,
`NOT_USING_PATH` and `SHORT`. `INCOMPLETE` is kept, because a real path that
falls short is exactly what a leg wants.

When the whole path cannot be seen — `SHORT` means "there is a path and it is
over 74 points" — it probes a nearer point and paths to **that**, and uses it
only if the mesh routes there. That is the addon's old guess, with the one step
that was missing: checking it. If even the probe is unreachable, nobody is sent
and the order says so, which beats watching a bot fly.

The budget is two thirds of `ReactDistance`, read from playerbots rather than
copied, because a number written down here would be contradicted by the `.conf`
in silence. The server answers each move with `MOVEAT <name> <x> <y> <z> <kind>`:
the addon measures arrival, draws the route and detects stalls against where the
bot is **actually** going, not against what was asked for.

### 4.5 Blizzard frames: borrowed, not reimplemented

`Rails.lua` tried it with our own buttons calling `ToggleWorldMap`,
`ToggleTalentFrame`, `ToggleGameMenu`… and in game the map would not open, the
talents would not open, and the menu threw *"blocked from an action only
available to the Blizzard UI"*. Those functions are protected and **it makes no
difference that the button is ours**.

| What gets borrowed | How |
|---|---|
| The four bags, the backpack and the keyring | reparented into a row of ours and returned on exit. They are children of `MainMenuBarArtFrame`, so hiding the main bar took them with it |
| The ten micro buttons (character, spellbook, talents, quests…) | same. And `MoveMicroButtons` is hooked, because the client repositions them on its own when you enter a vehicle |
| The player, target and party frames | we hook their **`PostClick`**, never `OnClick`: hooking a secure frame's `OnClick` puts its `TargetUnit` inside a tainted execution and **blocks in combat** |
| The quest log | left entirely alone; only what the Share button does changes |
| The portrait selection mark | it is the client's own highlight in additive mode |

Hard rule throughout: **whether each frame was visible BEFORE we touched it gets
recorded**, and that same state is given back. No blind `Show()`, which would
turn on bars the player had deliberately switched off. And anything protected is
not touched in combat: it is deferred to `PLAYER_REGEN_ENABLED`.

### 4.6 AzerothCore's own API, called with a bot's `Player*`

There is no trick here, and it was nearly discarded for not looking. A
playerbots bot **is a normal `Player`** as far as the core is concerned, and the
domain functions take any `Player*`:

| What is used | What it gives |
|---|---|
| `Trainer::GetSpells / CanTeachSpell / TeachSpell / IsTrainerValidForPlayer` | the entire trainer window, computed **for the bot**. All `WorldSession::SendTrainerList` adds on top is packing it towards its own session, and that is not needed because we draw the window ourselves |
| `CanTakeQuest`, `CanAddQuest`, `AddQuest`, `CanRewardQuest`, `RewardQuest` | accepting and turning in quests for several at once. **None of them checks distance** — verified line by line in `PlayerQuest.cpp` — so the *"you don't have to actually be next to it"* part comes free |
| `CanStoreItem` → `MoveItemFromInventory` → `MoveItemToInventory` | moving an item from one bag to another with no trade window |
| `LoginQueryHolder` + `HandlePlayerLoginFromDB` | **swapping characters without logging out.** It is the same public sequence mod-playerbots uses to bring a bot into the world. The server swallows the `SMSG_LOGOUT_COMPLETE` (the only thing that was sending the client to the character screen) and the client adopts the new object because it arrives with `UPDATEFLAG_SELF` |

**`mod-playerbots` is somebody else's and is not touched.** Every bit of its
surface we need sits behind a single file, `mod-rts/src/RtsBotApi.cpp`, the only
translation unit that includes a header of theirs — so an update on their side
breaks **one** file instead of two thousand-line ones. There used to be about
eighty of their calls scattered around and tangled with our own logic.

What we do add from outside: orders you give with the mouse call
`SetNextCheckDelay(0)` so the bot's AI wakes up **immediately** instead of
waiting for its next think cycle (`nextAICheckDelay`). It is the same lever
playerbots uses on itself, and it is applied **only** to orders you give
personally: everywhere else that wait exists for a reason.

### 4.7 What is deliberately NOT touched

- **The AzerothCore core.** Everything goes in `modules/mod-rts`.
- **`mod-playerbots`.** Read, never edited. See `RtsBotApi`.
- **A bot's role and stance.** Playerbots decides the role; a stance is a spell
  and fits in one of its ten slots. There is no role UI, and that is not an
  oversight.
- **Chat, loot, gossip, popups and the escape menu.** RTS mode hides a
  hand-written list and nothing else.
- **The player's key bindings.** They are recorded before being taken, given
  back on exit, and `SaveBindings` is **never called**: a reload, a disconnect
  or an unexpected crash leaves the real ones untouched.

---

## 5. Deploying and building

One direction, always: out of here. Never the other way.

| Button | What it does | Afterwards you need to |
|---|---|---|
| `C:\Server\rts-tools\Deploy_Addon.bat` | `addon/` → the WoW folder | `/reload` in game |
| `C:\Server\rts-tools\Deploy_Mod.bat` | `mod-rts/` → AzerothCore | rebuild `worldserver` |

The DLL has no button because it never moves:

```powershell
cmake --build C:\Server\rts-project\rts-client-mod\build --config Release
```

and it is injected by `C:\Server\rts-tools\2-Jugar.bat`.

Before calling the addon done: `python C:\Server\rts-tools\check_addon.py`. It
checks four things, and the last three exist because the first one misses them —
unterminated short strings, unknown escapes (`"Interface\Icons\X"` is read as
`InterfaceIconsX`, and **a texture path that does not exist raises no error: it
draws nothing**) and locals used before they are declared.

Custom art is converted with `C:\Server\rts-tools\Convertir_Arte.bat`:
`art-src/` holds the original and `addon/art/` the TGA the client reads.

### On another machine

```
git pull
```

then both deploy buttons, plus building the DLL and the `worldserver`.

---

## 6. Repository rules

### Why one direction only

There used to be a `sync.ps1` that pulled the three pieces in from wherever each
of them lived, and this folder was just a backup. Both directions existed, and
that meant at any given moment it was unclear which copy was the good one.

16/08/2026 cost an afternoon: the addon was edited until 22:06, the last `sync`
had been at 19:04, and when the server was moved to another machine the 19:04
copy got installed. 247 lines of `RTSMode.lua` were missing, among them
`CameraTurned()` — precisely the function that makes box selection work. The
symptom was "the new stuff doesn't work on the new machine", and there was not a
single error to give it away.

With one original and one direction, that failure cannot happen: if the game is
running something old, it means a deploy is missing, and a button fixes it.

### What is NOT committed, and why

- **`worldserver.conf`, `authserver.conf`, `dbimport.conf`** — they carry the
  MySQL user and password in plain text. They never come in here. The module's
  own conf template (`mod-rts/conf/mod_rts.conf.dist`) does, because it ships
  nothing but camera settings.
- **`build/`, binaries, logs** — rebuildable.
- **The AzerothCore fork** — it has its own remote
  (`mod-playerbots/azerothcore-wotlk`, branch `Playerbot`). Only our module
  lives here.
- **`mysql-data/`** — those are the databases, not code.

### Where the reasoning lives

**In the header of the file that implements it**, dead ends included. `docs/`
existed and was deleted on purpose (`4c2b163`): notes that no longer match the
binary are a comfortable place to confirm a wrong idea without opening the code.

The disassembled addresses for **this** `Wow.exe` (MD5
`45892BDEDD0AD70AED4CCD22D9FB5984`, build 12340) are in
`rts-client-mod/src/Offsets.h`, each one next to the dump that justifies it.

## 7. License

GPL-2.0-or-later. Full text in [`LICENSE`](LICENSE).

Copyright (C) 2026 Jairo.

This is not a free choice. `mod-rts/` is an AzerothCore module: it includes
`ScriptMgr.h`, `Player.h`, `PlayerbotAI.h` and links into `worldserver`.
AzerothCore and mod-playerbots are both *"version 2 of the License, or (at your
option) any later version"*, so anything that links into them inherits that.
The addon and the DLL are covered by the same license simply so the repository
speaks with one voice.

What this means in practice: use it, change it, run your own server with it.
If you distribute it — or a fork of it — it goes out under the GPL too, with
sources. `rts_core.dll` is injected into a copy of `Wow.exe` you already own;
nothing from Blizzard is redistributed here, and none of this touches retail.
