-- Body.lua -- THE BODY PROBE. An instrument, not a feature.
--
-- The hero goes invisible the moment his player carries PLAYER_FLAGS_UBER,
-- which is one of the two flags that open the commentator camera. The chain is
-- disassembled from THIS Wow.exe and written up in `rts-client-mod/src/
-- Offsets.h`; the summary is that a per-unit "emit this unit" (0x0073A890)
-- asks 0x006DE980 about THAT player and skips the emission if it says yes. The
-- bots do not carry the flags: that is why yours disappears and they do not,
-- and why forcing the predicate on 2026-09-08 hid everybody.
--
-- This file fixes nothing. It answers two questions, each with its own switch,
-- so the shape of the cure can be decided BEFORE building it:
--
--   /rts body flags on    are the flags enough, with no server and no camera
--                         in between, to make the hero disappear?
--   /rts body skip on     with the flags set, does he come back by cancelling
--                         THAT jump -- two bytes, a single call site?
--
-- The two combinations that matter:
--   1  -> flags set, no patch      => hero expected to be INVISIBLE
--   5  -> flags set, with patch    => if the hero SHOWS, the cure is 2 bytes
--   2  -> flags cleared every tick => the undo, and the test of the other
--                                     possible cure (the flags window)
--
-- It ships off and it is NOT saved to disk ON PURPOSE. A probe with its switch
-- saved is the `camHold` of 2026-08-23: the feature went into hiding, the
-- setting survived, and it re-armed itself every session.

local ADDON, ns = ...

local B = {}
ns.Body = B

local CVAR = "rtsBody"

local FLAGS_ON  = 1
local FLAGS_OFF = 2
local SKIP      = 4
local REPORT    = 8
local INVERT    = 16
local UBER_ONLY = 32    -- just bit 19, without 22
local COMM_ONLY = 64    -- just bit 22, without 19
local NO_FIX    = 8192  -- disarm the automatic fix (to see the bug again)
local BLINK_OFF = 16384 -- turn off the blink. CANDIDATE, not a cure
local ACT_FIX   = 32768 -- give back "I can attack" (bit 19 vetoes it)

-- Created if it is not there. `SetCVar` on a name that does not exist IS NOT AN
-- ERROR: it does nothing. It is how the FOV channel spent three stages failing
-- in silence, so here it is checked and called out.
local function Ensure()
	if GetCVar(CVAR) ~= nil then return true end
	if type(RegisterCVar) == "function" then
		RegisterCVar(CVAR, "0")
	end
	if GetCVar(CVAR) ~= nil then return true end
	ns.Print("|cffff0000body:|r cannot create the CVar |cffffff00" .. CVAR ..
	         "|r; the probe cannot talk to the DLL.")
	return false
end

local function Get()
	local v = tonumber(GetCVar(CVAR) or "0") or 0
	if v < 0 then v = 0 end
	return v
end

local function Set(v)
	if not Ensure() then return end
	SetCVar(CVAR, tostring(v))
	B:Report()
end

local function Bit(v, mask, on)
	if on then
		if v % (mask * 2) >= mask then return v end
		return v + mask
	end
	if v % (mask * 2) >= mask then return v - mask end
	return v
end

local function Has(v, mask)
	return v % (mask * 2) >= mask
end

-- The site code travels in bits 7+ of the CVar. These live up here because
-- `B:Report` uses them and `B:Sites` is two hundred lines further down: the
-- previous version declared them next to `B:Sites` and `check_addon.py` stopped
-- it dead -- one was a call to nil and the other a mute global.
local SITE_SHIFT = 128    -- 2^7
local SITES_ALL  = 63

local function SiteCode(v)
	return math.floor(v / SITE_SHIFT) % 64
end

local function SetSite(v, code)
	local rest = v % SITE_SHIFT
	local high = math.floor(v / SITE_SHIFT / 64) * 64
	return rest + (high + code) * SITE_SHIFT
end

function B:Report()
	if GetCVar(CVAR) == nil then
		ns.Print("|cffff0000body:|r the CVar |cffffff00" .. CVAR ..
		         "|r does not exist yet.")
		return
	end
	local v = Get()
	local dll = (RTS_Ready == 1)
	ns.Print(("body: mode |cffffff00%d|r  flags=%s  patch=%s  report=%s  DLL=%s"):format(
		v,
		Has(v, FLAGS_OFF) and "|cffff8000CLEAR|r"
			or (Has(v, UBER_ONLY) and "|cff00ff00UBER ONLY|r"
			or (Has(v, COMM_ONLY) and "|cff00ff00COMM ONLY|r"
			or (Has(v, FLAGS_ON) and "|cff00ff00SET|r" or "leave alone"))),
		Has(v, SKIP) and "|cff00ff00yes|r" or "no",
		Has(v, REPORT) and "yes" or "no",
		dll and "|cff00ff00injected|r" or "|cffff0000MISSING|r"))
	local code = SiteCode(v)
	if code == SITES_ALL then
		ns.Print("  predicate call sites: |cffff8000ALL EIGHTEEN off|r")
	elseif code > 0 then
		ns.Print(("  predicate call sites: |cffff8000number %d off|r"):format(code - 1))
	end
	if Has(v, ACT_FIX) then
		ns.Print("  sword: |cff00ff00bit 19 verdict overridden|r (you can attack)")
	end
	if not dll then
		ns.Print("  |cffff0000Without the DLL the probe does absolutely nothing.|r " ..
		         "It opens with 2-Jugar.bat.")
	end
end

-- THESE TWO LIVE UP HERE AND NOT NEXT TO `Park`, WHICH IS WHERE THEY WERE.
-- `B:Flags` writes them and the `OnUpdate` reads them; declared further down,
-- what Flags wrote was a GLOBAL with the same name and the loop read the local,
-- which was 0 for ever. Which means: `flags on` NEVER PARKED the camera and the
-- test stayed impossible to look at -- with no error, and no line in any log.
-- It is the local-used-before-it-is-declared bug, but in a variable, which is
-- the mute version: a function that does not exist yet at least blows up.
-- `check_addon.py` now catches it (2026-09-09).
local parkTries = 0
local parkNext  = 0

-- The honest check on the parking: what was ASKED FOR, to compare it a tick
-- later against what the DLL reads off the real camera.
local checkAt
local checkX, checkY, checkZ

function B:Flags(on)
	local v = Get()
	-- The single-bit modes are MUTUALLY EXCLUSIVE with this one: if they were
	-- not cleared, a `flags on` after a `flags uber` would leave both things
	-- asked for and the DLL would have to break the tie. A switch that depends
	-- on the order you typed it in is a switch that lies.
	v = Bit(v, UBER_ONLY, false)
	v = Bit(v, COMM_ONLY, false)
	if on then
		v = Bit(v, FLAGS_OFF, false)
		v = Bit(v, FLAGS_ON, true)
	else
		v = Bit(v, FLAGS_ON, false)
		v = Bit(v, FLAGS_OFF, true)
	end
	Set(v)

	-- The gate is opened by the DLL on its next tick (33 Hz), not here, so
	-- parking on this very line would arrive before the permission does. It
	-- retries for two seconds and keeps quiet until one gets through.
	if on then
		parkTries = 8
		parkNext = 0
	else
		parkTries = 0
	end
end

-- ONE BIT ON ITS OWN, WHICH IS WHAT WAS MISSING FROM THE MEASUREMENT.
--
-- `flags on` sets BOTH at once, so A1 -- "the flags are the cause" -- does not
-- say which of the two. And that difference matters: bit 19 already has a
-- second known consumer (`0x00729740`, the 28-caller predicate that kills the
-- mouseover), while bit 22 is only looked at by the commentator band. They are
-- two different searches.
--
-- THE GOOD THING ABOUT THIS TEST IS THAT IT DOES NOT NEED THE CAMERA. One bit
-- on its own does not open the commentator gate, so the camera stays where it
-- is and you look at yourself in third person as always. No parking, no gate,
-- no retries: either you can see yourself or you cannot.
function B:OneBit(which)
	local v = Get()
	v = Bit(v, FLAGS_ON, false)
	v = Bit(v, FLAGS_OFF, false)
	v = Bit(v, UBER_ONLY, which == "uber")
	v = Bit(v, COMM_ONLY, which == "comm")
	Set(v)
	ns.Print(("|cffff8000body:|r just |cffffff00%s|r. Look at yourself in third person: " ..
	          "do you disappear?"):format(
		which == "uber" and "PLAYER_FLAGS_UBER (bit 19)"
		                or "PLAYER_FLAGS_COMMENTATOR2 (bit 22)"))
	ns.Print("  |cffffff00/rts body flags off|r to come back.")
end

-- TURNING OFF THE PREDICATE CALL SITES, ONE AT A TIME.
--
-- `0x006DE980` answers "this player is a spectator" and has EIGHTEEN call
-- sites. Forcing the whole predicate was already tried on 2026-09-08 and left
-- the screen with nobody on it: it was telling the client that every player was
-- a spectator. Turning off ONE site is five bytes, it is local, and the other
-- seventeen go on telling the truth.
--
-- With both flags set the hero DOES disappear -- measured, not assumed -- which
-- means the mechanism is alive in front of us and can be cornered:
--
--   sites all  -> do you come back?  no -> the predicate is NOT the mechanism
--                            and we go looking for a test of the two bits
--                            written by hand somewhere else. yes -> it is among
--                            the eighteen, and we halve it.
--   site <n>   -> the one that gives you back is THE caller.
--
-- The code travels in bits 7+ of the same CVar. A single channel: with two, a
-- test can end up half done with one set and the other not, and nothing says so.
function B:Sites(code)
	local v = SetSite(Get(), code)
	Set(v)

	-- WITHOUT THE FLAGS SET THIS TEST MEASURES NOTHING, AND THE WORST OF IT IS
	-- THAT IT COMES OUT FINE. The predicate answers `false` everywhere when the
	-- two bits are not there, so you are visible anyway and ANY site looks like
	-- it gave you your model back: eighteen false positives in a row, every one
	-- of them convincing.
	--
	-- It happened on 2026-09-09: a `reset` in between left the flags neutral and
	-- the whole round of sites 11..18 was run on a hero who had never been
	-- hidden. The command obeyed and measured nothing, which is the worst way of
	-- failing. Now it says so.
	if code ~= 0 and not Has(v, FLAGS_ON) then
		ns.Print("|cffff0000body: THE FLAGS ARE NOT SET.|r Without them you are " ..
		         "visible anyway and this measures nothing.")
		ns.Print("  |cffffff00/rts body flags on|r first, and then the sites: " ..
		         "the site code does not touch the flags, so they are set ONCE.")
		return
	end
	if code == 0 then
		ns.Print("body: all eighteen call sites given back.")
	elseif code == SITES_ALL then
		ns.Print("|cffff8000body:|r all EIGHTEEN off. With the flags set, " ..
		         "does your model come back?")
		ns.Print("  |cff00ff00yes|r -> the hiding place is among them and we halve it.")
		ns.Print("  |cffff0000no|r -> the predicate is not the mechanism. Something else reads the two bits.")
	else
		ns.Print(("|cffff8000body:|r turned off ONLY site |cffffff00%d|r of 18. " ..
		          "does your model come back?"):format(code - 1))
	end
	ns.Print("  the log says the exact address that was touched.")
end

-- THE FIX ARMS ITSELF, SO THIS IS FOR DISARMING IT.
--
-- The DLL turns off 0x006E085C as soon as the player CARRIES both flags,
-- whether the probe or the server set them. This switch exists so the bug can
-- be seen again: a cure with no way to turn it off cannot be measured again the
-- day the symptom moves, and then all that is left is recompiling blind.
function B:NoFix(on)
	Set(Bit(Get(), NO_FIX, on and true or false))
	ns.Print(on and "|cffff8000body:|r fix DISARMED -- you go back to being invisible with the flags."
	             or "|cff00ff00body:|r fix armed (this is the normal state).")
end

-- THE BLINK, AND IT STARTS OFF BECAUSE IT IS A CANDIDATE.
--
-- With the flags set, the mouse highlight and the destination circle blink at
-- the same time, and the circle alternates between two positions. 0x0073DAB0
-- has exactly that shape: a 500 ms toggle behind the OTHER predicate
-- (0x00729740), with its `sete` and its `sub edx, 0x1f4`.
--
-- The rhythm fits and the mechanism fits, and that is not the same as being the
-- cause. That is why it is a switch and not a fix: turn it off, look, and the
-- game answers. If it was not it, it is ruled out in ten seconds instead of in
-- a whole round.
function B:Blink(on)
	Set(Bit(Get(), BLINK_OFF, on and true or false))
	if on then
		ns.Print("|cffff8000body:|r blink off (0x0073DB42). " ..
		         "Is the destination circle still shaking?")
		ns.Print("  |cff00ff00no|r -> that was it. |cffff0000yes|r -> it is somewhere else and we keep looking.")
	else
		ns.Print("body: blink put back the way it was.")
	end
end

-- THE SWORD: GIVING BACK "I CAN ATTACK".
--
-- `PLAYER_FLAGS_UBER` -- bit 19, the one the free camera CANNOT leave unset --
-- cuts the predicate 0x00729740 dead, which is the one behind `UnitCanAttack`.
-- With the camera on, `UnitCanAttack("player", whatever)` is false, so the
-- client does not draw the sword when you pass over a mob and right-click does
-- not attack. The quest icon and the loot bag do show up because they go
-- through another predicate, and that asymmetry is exactly the signature of
-- bit 19.
--
-- The fix is one byte in the verdict (`je` -> `jmp`), and it is described in
-- full in `rts-client-mod/src/Offsets.h`. Only the switch is here.
--
-- IT STARTS OFF. It is a byte patch on the client and it has not been seen
-- working in game yet: that is the rule, and both times it was broken the
-- player's first contact with the round was a new bug laid on top of the one it
-- came to fix.
function B:Attack(on)
	Set(Bit(Get(), ACT_FIX, on and true or false))
	if on then
		ns.Print("|cff00ff00body:|r bit 19 verdict overridden (0x00729762).")
		ns.Print("  Move the mouse over a mob: |cffffff00does the sword appear?|r")
		ns.Print("  |cff00ff00yes|r -> that was it, and the fix moves to arming itself.")
		ns.Print("  |cffff0000no|r -> it is not the only site; the predicate has 37 callers.")
	else
		ns.Print("body: bit 19 verdict given back (no sword, the way it has been until today).")
	end
end

function B:FlagsAuto()
	-- Neither set nor clear: leave the flags as they are. It is the neutral
	-- state, and it is needed to test the window cure without the probe
	-- fighting it.
	local v = Get()
	v = Bit(v, FLAGS_ON, false)
	v = Bit(v, FLAGS_OFF, false)
	v = Bit(v, UBER_ONLY, false)
	v = Bit(v, COMM_ONLY, false)
	Set(v)
end

function B:Skip(on)
	Set(Bit(Get(), SKIP, on and true or false))
end

function B:Log(on)
	Set(Bit(Get(), REPORT, on and true or false))
end

-- The "let it swallow everything" diagnostic. It forces the jump for EVERY
-- unit, and what you watch is THE BOTS, not the hero:
--
--   they vanish  -> 0x0073A890 is the model emission and the jump is its gate.
--                   Then something MORE is hiding the hero, as well.
--   nothing      -> that function does not draw the model and the whole static
--                   reading is wrong. We start somewhere else.
--
-- Cancelling the jump is not enough to see the hero (tried in game), and from
-- the hero those two explanations look the same. This tells them apart.
function B:Invert(on)
	Set(Bit(Get(), INVERT, on and true or false))
	if on then
		ns.Print("|cffff8000body:|r watch the BOTS, not yourself. Do their models disappear?")
	end
end

-- TURNING IT OFF IS NOT THE SAME AS STOPPING ASKING, AND THAT WAS THE BUG IN
-- THE FIRST VERSION. Mode 0 means "do not touch the flags", so `reset` left
-- them SET: the client went on believing it was a spectator -- detached camera
-- included -- and the only real undo was `flags off` or relogging. And on top
-- of that, step 3 of the help said reset left everything as it was.
--
-- Now reset ASKS TO CLEAR and only afterwards goes neutral, giving the DLL
-- plenty of time for its tick (33 Hz). It is the same shape as the hard rule
-- about capturing and giving back: the undo has to undo, not stop insisting.
local clearUntil

-- PARKING THE CAMERA OVER YOUR BODY, AND THIS IS NOT A CONVENIENCE: WITHOUT IT
-- THE PROBE CANNOT ANSWER ITSELF.
--
-- With the flags set the client believes it is a spectator and the camera goes
-- off to the commentator state's position, which nobody has ever written --
-- that is, ~(0,0,0). Measured in game: camera at (35, -15, 32) with the hero at
-- (10326, 830, 1326), 10,300 yards. Flying out there is not an option, so the
-- question "has my model disappeared?" was literally impossible to look at. The
-- probe could say yes and say no without anybody seeing it.
--
-- The flags the probe sets are precisely the ones that OPEN the
-- `CommentatorSetCamera` gate, so placing it is ordinary Lua: no recompiling
-- the DLL and no reinjecting.
--
-- It goes ABOVE, looking down, on purpose. The yaw of that function has a
-- convention that cannot be read off the binary (`docs/CAMARA-LIBRE.md` §6), so
-- whatever is there is kept and not relied on: from above, your body comes out
-- in the middle of the screen wherever the yaw happens to point. A POSITIVE
-- `pitch` looks down -- with a negative one it points at the sky.
local HEIGHT = 12.0
local PITCH  = 70.0
local FOV    = 70.0     -- the legal range is 1..120; a 0 clamps to ~1 and
                        -- leaves the screen purple

local function Park(quiet)
	if type(CommentatorSetCamera) ~= "function" then
		ns.Print("|cffff0000body:|r this client has no CommentatorSetCamera.")
		return false
	end
	if RTS_HasPos ~= 1 or not RTS_PX then
		if not quiet then
			ns.Print("|cffff0000body:|r the DLL is not publishing your position yet.")
		end
		return false
	end

	-- THE GATE IS CHECKED, NOT ASSUMED, AND THIS WAS THE BUG.
	--
	-- `pcall(CommentatorSetCamera, ...)` returns true WITH THE GATE CLOSED TOO:
	-- the function exists, it gets called, it looks at the flags, does nothing
	-- and comes back without an error. Which means the first attempt -- the one
	-- on the frame after writing the CVar, when the DLL has not yet set the
	-- flags on its 33 Hz tick -- said "parked" and TURNED OFF THE RETRIES. The
	-- camera stayed where the client leaves it when it believes it is a
	-- spectator and the probe still could not look at itself. Another reader
	-- that lies in the reassuring direction.
	--
	-- The good test is given by `CommentatorGetCamera`: it returns the six
	-- numbers with the gate open and NOTHING with the gate closed. And on the
	-- way it brings the live yaw, which is the one that gets kept.
	local ok, cx, _, _, y = pcall(CommentatorGetCamera)
	if not ok or type(cx) ~= "number" or type(y) ~= "number" then
		if not quiet then
			ns.Print("|cffff0000body:|r the gate is still closed " ..
			         "(CommentatorGetCamera does not answer). Are the flags set?")
		end
		return false
	end

	local tx, ty, tz = RTS_PX, RTS_PY, RTS_PZ + HEIGHT
	local ok2 = pcall(CommentatorSetCamera, tx, ty, tz, y, PITCH, FOV)
	if not ok2 then
		if not quiet then
			ns.Print("|cffff0000body:|r CommentatorSetCamera failed.")
		end
		return false
	end

	-- AND THE PROOF THAT IT MOVED IS NOT WHAT GetCamera RETURNS -- that reads
	-- the commentator state globals, that is, WHAT YOU JUST ASKED FOR
	-- (`CAMARA-LIBRE.md` §11). The honest witness is `RTS_Cam*`, which the DLL
	-- takes off the active camera by itself and which arrives a tick later. It
	-- checks itself and IT CALLS OUT THE DISTANCE, which is what turns "I show
	-- up somewhere else" into a number.
	checkAt = GetTime() + 0.4
	checkX, checkY, checkZ = tx, ty, tz

	ns.Print(("body: camera asked for at (%.0f, %.0f, %.0f). Checking..."):format(tx, ty, tz))
	return true
end

function B:Look()
	-- Retries just like `flags on`: if the gate is closed because you have only
	-- just written the CVar, a single attempt is lost by 30 ms.
	parkTries = 0
	if Park(false) then return end
	parkTries = 8
	parkNext = GetTime() + 0.25
end

function B:Off()
	if not Ensure() then return end
	SetCVar(CVAR, tostring(FLAGS_OFF))
	clearUntil = GetTime() + 1.5
	ns.Print("body: clearing the flags... (neutral in 1.5 s)")
end

function B:Help()
	ns.Print("|cffffff00Body probe|r -- why the hero disappears with the free camera.")
	ns.Print("  |cff00ff00/rts body|r                 status")
	ns.Print("  |cff00ff00/rts body flags on|off|r    writes or clears the two flags every tick")
	ns.Print("  |cff00ff00/rts body flags auto|r      does not touch them (neutral state)")
	ns.Print("  |cff00ff00/rts body flags uber|r      JUST bit 19, no camera")
	ns.Print("  |cff00ff00/rts body flags comm|r      JUST bit 22, no camera")
	ns.Print("  |cff00ff00/rts body skip on|off|r     cancels the jump that skips your model")
	ns.Print("  |cff00ff00/rts body look|r           parks the camera over your body")
	ns.Print("  |cff00ff00/rts body log on|off|r      one line per second to rts_core.log")
	ns.Print("  |cff00ff00/rts body blink on|off|r    turns off the blink (candidate)")
	ns.Print("  |cff00ff00/rts body attack on|off|r   gives back the sword and right-click")
	ns.Print("  |cff00ff00/rts body nofix on|off|r    disarms the fix, to see the bug")
	ns.Print("  |cff00ff00/rts body sites all|off|r   turns off the 18 predicate callers")
	ns.Print("  |cff00ff00/rts body site 0..17|r     turns off JUST that caller")
	ns.Print("  |cff00ff00/rts body reset|r           everything off")
	ns.Print(" ")
	ns.Print("The test sequence, in this order:")
	ns.Print("  1. |cffffff00/rts body log on|r  and then |cffffff00flags on|r")
	ns.Print("     -> YOUR MODEL IS EXPECTED TO DISAPPEAR. If it does not, the")
	ns.Print("        flags are not the cause and the rest of this probe is spare.")
	ns.Print("  2. |cffffff00/rts body skip on|r  (with the flags still set)")
	ns.Print("     -> if you COME BACK, the cure is two bytes and it is found.")
	ns.Print("  3. |cffffff00/rts body reset|r  to leave everything as it was.")
	ns.Print(" ")
	ns.Print("|cffff8000With the flags set the CAMERA COMES LOOSE|r and can be moved:")
	ns.Print("  the whole client believes it is a spectator, not just the piece that")
	ns.Print("  draws your model. It is expected. |cffffff00reset|r gives it back, and")
	ns.Print("  so does a relog -- the flags live only in the client's memory.")
end

-- A `/reload` DOES NOT CLEAR THE CLIENT'S MEMORY, so the flags survive an
-- interface reload -- only a logout gives them back, because then the field is
-- sent again by the server. That is why on load it ASKS TO CLEAR instead of
-- going neutral: neutral on top of flags stuck there from the previous session
-- is exactly the `camHold` of 2026-08-23, an instrument that re-arms itself.
--
-- That the probe starts off is still the rule; what changes is that "off" now
-- means clearing, not keeping quiet.
-- MIENTRAS DURA ESE BORRADO NO SE PUEDE ARMAR LA CAMARA LIBRE, y por eso se
-- puede preguntar desde fuera.
--
-- La camara libre necesita los flags PUESTOS (bit 19 y bit 22), y esto acaba de
-- pedir que se quiten. Quien arme en esta ventana y medio de segundo ve como
-- sus flags se evaporan detras de el: la puerta del cliente no abre, la espera
-- se agota y el diagnostico culpa al cliente de algo que hizo el addon. Le paso
-- a `FreeCam:Regain` al cruzar un portal, que corre con este mismo evento.
function B:Clearing()
	return clearUntil ~= nil
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
	if not Ensure() then return end
	SetCVar(CVAR, tostring(FLAGS_OFF))
	clearUntil = GetTime() + 1.5
end)

f:SetScript("OnUpdate", function()
	if clearUntil and GetTime() >= clearUntil then
		clearUntil = nil
		if GetCVar(CVAR) ~= nil then SetCVar(CVAR, "0") end
	end

	if parkTries > 0 and GetTime() >= parkNext then
		parkNext = GetTime() + 0.25
		parkTries = parkTries - 1
		if Park(parkTries > 0) then parkTries = 0 end
	end

	if checkAt and GetTime() >= checkAt then
		checkAt = nil
		if RTS_HasCam ~= 1 or not RTS_CamX then
			ns.Print("|cffff0000body:|r the DLL is not reading the camera, " ..
			         "I cannot check where it ended up. Look at rts_core.log.")
		else
			local dx = RTS_CamX - checkX
			local dy = RTS_CamY - checkY
			local dz = RTS_CamZ - checkZ
			local d = math.sqrt(dx * dx + dy * dy + dz * dz)
			if d < 5 then
				ns.Print(("|cff00ff00body: camera parked over your body|r " ..
				          "(%.1f yards off what was asked)."):format(d))
			else
				ns.Print(("|cffff0000body: THE CAMERA IS NOT WHERE IT WAS ASKED FOR|r -- " ..
				          "%.0f yards out."):format(d))
				ns.Print(("  asked (%.0f, %.0f, %.0f)  real (%.0f, %.0f, %.0f)"):format(
					checkX, checkY, checkZ, RTS_CamX, RTS_CamY, RTS_CamZ))
				ns.Print("  |cffffff00/rts body look|r tries again.")
			end
		end
	end
end)
