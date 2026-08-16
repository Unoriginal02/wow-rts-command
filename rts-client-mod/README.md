# rts_core

Native capability layer for the `RTSCommand` addon.

WotLK 3.3.5a Lua cannot read world coordinates, cannot raycast a screen click to
a world position, and cannot project world→screen. Those are the only jobs this
DLL has. Everything else — selection, orders, UI — stays in the addon, where it
cannot crash the client.

## Build

Requires Visual Studio 2022 with the C++ workload. **32-bit only** — `Wow.exe` is
x86, so a 64-bit build cannot be injected. CMake refuses to configure otherwise.

```
cmake -S . -B build -G "Visual Studio 17 2022" -A Win32
cmake --build build --config Release
```

Output lands in `build\bin\`: `rts_core.dll` and `injector.exe`. The injector
looks for the DLL beside itself, so keep them together.

The CRT is linked statically, so the client needs no VC++ redistributable.

## Use

1. Start the client and log in.
2. Run `build\bin\injector.exe`.
3. In game: `/rts native`

Injection can happen at any point, including mid-session — the addon polls for
the DLL every two seconds and reports when it attaches.

## Verifying it worked

`/rts native` prints your live world coordinates and object count. Every step is
also written to `rts_core.log` next to the DLL. A healthy log ends with:

```
selftest: player pos = ..., ..., ...  facing=...  <-- OFFSETS GOOD
registered Lua function RTS_GetPlayerPosition
Lua bridge ready (6 functions), version 0.1.0
```

If the client is at the login screen when you inject, "object manager not
resolvable yet" is expected — registration retries every frame until Lua exists.

## Client offsets

All in `src/Offsets.h`, verified against
`F:\Games\WOW WOTLK\Wow.exe` (MD5 `45892BDEDD0AD70AED4CCD22D9FB5984`,
build 12340, image base `0x00400000`) by static PE analysis: every code address
resolves inside `.text` and starts with a real prologue, and
`FrameScript_RegisterFunction` was disassembled far enough to confirm it loads
the global `lua_State*` from `0x00D3F78C` and therefore takes no state
parameter.

Note `lua_type` is deliberately absent — the commonly cited `0x0084DD60` is
*not* a function entry on this binary, so it is unused rather than guessed at.

**Swapping the client invalidates all of this.** Re-verify before trusting it.

## Design notes

- **No MinHook.** A vtable slot is one pointer; `VirtualProtect` + swap is the
  whole technique.
- **No ImGui yet.** Nothing is drawn until drag-box selection needs it.
- **The `EndScene` hook is a main-thread trampoline, not a renderer.** Lua
  registration has to happen on the client's thread; doing it from the injected
  thread races the interpreter. The dummy-device trick gets the shared vtable
  without needing to locate the client's own device.
- **Every client read is guarded** (`Memory.h`). A wrong offset logs and returns
  nil to Lua; it must never crash the client.

## Antivirus

Remote-thread injection trips heuristics regardless of intent. If Defender
flags it, add `C:\Server\rts-client-mod` as an exclusion rather than disabling
protection.

## Status

Working: world coordinates for the player and for any object by GUID.

Not yet built: cursor→world raycast (next — `CGWorldFrame::Intersect` at
`0x0077F310` is the client's own picking function, already located), free
camera, world→screen projection for drag-box selection.
