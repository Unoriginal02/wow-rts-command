--[[
	FreeCam.lua -- the RTS camera controller.

	It replaces the possessed creature. The four layers the brief asked for, in
	the order they run once per frame:

	    INPUT     keys -> intentions              (our own buttons, by edge)
	    SOLVER    intentions -> target            (horizontal plane + ground)
	    SMOOTHING target -> current position      (exponential by dt)
	    APPLY     a single write                  (ns.Camera:SpecPlace)

	=== WHY THIS CAN EXIST NOW AND COULD NOT BEFORE =========================

	The old camera was a server creature the player POSSESSES, so the client
	owned its position and the server could only move it with `NearTeleportTo`
	-- which CANCELS the movement the client is applying. Everything this file
	does was blocked by that one fact:

	  * moving forward and rising at the same time was impossible (each
	    teleport cuts the forward motion),
	  * height over terrain was built BOTH possible ways and deleted on
	    2026-08-23, because the server one is a lift and the client one (hover)
	    needs gravity switched on, which is exactly what stops the camera
	    staying where you put it,
	  * and smoothing by dt made no sense: we did not own the transform, so
	    there was nothing to interpolate.

	With `CommentatorSetCamera` the transform is OURS -- six values, one call,
	and it stays put (measured in game: 0.00 drift). So all three stop being
	mechanism problems and become arithmetic.

	=== FORWARD IS FLAT, NEVER THE VIEW VECTOR =============================

	It is the explicit requirement and it is also the lesson of stage 5f, where
	`SetCanFly(true)` was the reason the camera "flew": in flight mode the
	client moves the unit along its VIEW, so looking at the ground and pressing
	W makes you descend.

	Here forward comes from the camera forward vector PROJECTED onto the
	horizontal plane and renormalised, so tilting only changes what you SEE.
	W/S move on the plane the height defines, which is what was asked for.

	And that vector is asked of the DLL (`RTS_CamFwdX/Y`) rather than derived
	from our yaw, which sidesteps the question of what `CommentatorSetCamera`
	angle convention is -- something that cannot be read from the binary. Yaw is
	only used to TURN; the direction of travel never depends on it.

	=== HEIGHT IS MEASURED AGAINST THE GROUND UNDER THE CAMERA ==============

	`targetZ = ground + offset`, with the ground from `RTS_CamGroundZ` -- a
	vertical ray the DLL fires under the camera every tick. The only ground
	published before was under the PLAYER, and that is no use: in an RTS camera
	the camera spends most of its time where the character is not, which is
	exactly when it is needed.

	SPACE and C do not move Z: they move the OFFSET. That is why you can travel
	and rise at once without either cutting the other -- both are inputs to the
	same solver and are integrated in the same frame, which is what the brief
	asked for in its section 7.

	=== "THE GROUND" IS NOT "THE FIRST THING UNDERNEATH" (2026-09-10) =======

	The two are said the same way and are only the same thing in open country.
	The moment there is anything built, the first thing under the camera as it
	nears a house is the ROOF -- so height was corrected against the roof, the
	camera rose by itself and getting inside was impossible. A wooden sign did
	the same in miniature: a six-yard jump and back.

	Since 0.25.0 the DLL publishes BOTH heights -- `RTS_CamGroundZ` (everything)
	and `RTS_CamLandZ` (terrain only, another flag mask on the same client ray)
	-- and `floor` picks. With `floor = 1` a roof stops being ground: the camera
	passes over it unmoved and can descend right INSIDE the house, where the
	client also draws the interior and clips the exterior on its own, which is
	the good version of the cutaway discarded that same morning.

	=== AND A STEP IS NOT A SLOPE =========================================

	Even with no roofs, terrain has edges too. Smoothing over the camera error
	cannot tell them apart, because six yards of error are the same six yards in
	both cases. What DOES tell them apart is HOW FAST THE GROUND MOVES: a slope
	at full speed is ~20 yd/s, the edge of a step is six yards IN ONE FRAME --
	hundreds.

	So there is a filter IN FRONT of the smoothing, on the ground signal, with a
	speed limit whose ceiling drops as the pending step grows (`climb`, `soft`,
	`slow`). A slope is followed closely; a step is barely begun, and if you
	stay on top of it you do end up climbing. The taller the step, the slower --
	which is exactly the opposite of what normal smoothing does, and is what was
	asked for.

	=== AND THE LOCK IS THE FOURTH LAYER SWITCHED OFF (2026-09-13) ==========

	The panel LOCK slot pins the camera to the hero: the distance at that
	instant is captured and held while the hero travels. It is for going along
	with the party without flying the camera by hand.

	AND THAT SLOT IS THE ONLY MOUTH. There is no key and no command: a key was
	considered and the player did not want one (2026-09-13), so the lock takes
	none.

	It is a DETOUR, not another layer: with the lock on, the whole ground SOLVER
	-- ray, step filter, hard floor, push budget -- does not run. Z comes from
	the hero, who already walks the ground on his own, and two owners of the
	same Z is the kind of fight this file has already lost twice.

	AND IT FRAMES NOTHING BY ITSELF: not the angle, not the height, not the
	distance. The player sets that with the mouse and the usual keys -- which,
	with the lock on, move the FRAMING instead of the camera -- and it stays
	until they touch it again.

	=== AND THE HERO VIEW IS THE SAME LOCK WITH A DIFFERENT ENTRANCE ========

	RIGHT-clicking the lock slot puts the camera RIGHT ABOVE the hero -- five
	yards by default -- facing the way he faces, and attaches both: it stays
	there while he walks, fights, or his AI drives him.

	    mouse, Q/E      turn
	    W/A/S/D         nudge the spot, exactly as with the lock
	    SPACE, C        raise and lower the height above him

	WHAT THIS MODE BUYS IS THE ENTRANCE, NOT A RESTRICTION (2026-09-15). It was
	born forbidding W/A/S/D -- "look only" -- and that half is gone at the
	player request: it bought nothing. The expensive, useful part is the other
	one: that in ONE CLICK the camera is over your hero, oriented like him,
	without flying it there.

	AND THE HEIGHT WAS MEASURED TWICE. It started at 2.2 -- a human head,
	literally inside -- and was **far too low**: at head height the slope in
	front hides whatever is behind it and your own model eats the bottom third
	of the screen. Seven felt high. Five is what stuck.

	IT IS NOT A FIFTH MODE. It is the lock, which instead of capturing whatever
	framing is on screen sets it to (0, 0, `eyeH`) and also orients, so it
	inherits the whole smoothed hero follow -- which matters more there than
	anywhere: the DLL publishes the position at 33 Hz and the screen runs at 60,
	so copying it raw is 0.2 yards of jerk thirty-three times a second right
	above the hero. What does not show from a bird eye view makes you seasick
	here.

	=== WITHOUT THE DLL THIS DOES NOT START, AND IT SAYS SO =================

	It needs two things only the DLL gives: the forward vector and the ground
	under the camera. Without `rts_core` injected there is neither, so the
	controller refuses to start rather than draw a camera that is going to sit
	there frozen -- a degraded mode nobody announces is worse than one that
	fails.
]]

local ADDON, ns = ...

local F = {}
ns.FreeCam = F

F.active = false

--- Settings ---------------------------------------------------------------
--
-- All per character, because they are a matter of feel: the right speed
-- depends on your resolution and your habits, same as mouse sensitivity.
local D = {
	speed   = 30.0,   -- yards/second on the plane
	lift    = 14.0,   -- yards/second of offset with SPACE and C
	turn    = 90.0,   -- degrees/second with Q and E
	height  = 30.0,   -- starting offset above the ground
	minH    = 4.0,    -- the lowest `height` may be. NOT a floor on the flight:
	                  -- with C you go through anything
	maxH    = 300.0,  -- ceiling on the offset
	smoothZ = 8.0,    -- k of the height smoothing (1/s); higher is sharper
	-- === THE GROUND IS NOT THE FIRST THING UNDERNEATH =====================
	--
	-- `floor = 1` measures against TERRAIN and nothing else: a roof, a sign or
	-- a treetop stop counting as ground, so the camera neither rises by itself
	-- as it nears a house nor gets locked out of it. `floor = 0` is the old
	-- behaviour -- whatever it hits first -- and is useful for flying over a
	-- village without dropping into anything.
	floor   = 1,      -- 1 = terrain only, 0 = whatever is underneath
	-- === AND THE CAMERA COLLIDES WITH NOTHING =============================
	--
	-- The commentator camera DOES collide out of the box, and with the same
	-- flags as the ground ray -- terrain, buildings and doodads. It is the
	-- second half of "I cannot get into the house": one raised it onto the roof
	-- and the other pushed it out of the wall.
	--
	-- With `noclip = 1` that ray is switched off on entry and back on on exit,
	-- so the only thing stopping the camera is OUR ground. Everything needed to
	-- read that in the binary is in `Camera:SetCollision`.
	noclip  = 1,      -- 1 = passes through everything; 0 = client collision
	-- === AND A STEP IS CHASED SLOWLY, A SLOPE IS NOT ======================
	--
	-- These three are the filter that separates a slope from a jump. The speed
	-- at which the measured ground chases the real one is
	--
	--     v = climb / (1 + (pending/soft)^2),  never below `slow`
	--
	-- so the BIGGER the step left to climb, the SLOWER it is climbed -- exactly
	-- the opposite of what normal smoothing does, and what the player asked
	-- for: passing over a sign does not show, and if you genuinely want to get
	-- on top of it, you wait.
	climb   = 60.0,   -- yd/s when the difference is tiny (a slope)
	soft    = 2.5,    -- yards; the knee. Smaller is fussier
	slow    = 6.0,    -- yd/s; the floor under that speed (without it a real
	                  -- cliff would never be climbed at all)
	-- POSITIVE LOOKS DOWN, and the game says so, not me.
	--
	-- I set it to -45 reasoning "down is negative" and it comes out the other
	-- way: at -45 the camera points at the SKY. It is the
	-- `CommentatorSetCamera` convention, which cannot be read from the binary
	-- -- the disassembly only shows the argument being multiplied by DEG2RAD
	-- and stored.
	--
	-- Another guessed sign constant, which is the mistake this project has been
	-- paying for since the two `SetPosition` signs on the portrait. There the
	-- way out was a table of seven framings to try them; here having seen it
	-- once is enough.
	pitch   = 45.0,   -- degrees; POSITIVE looks down (measured in game 2026-09-07)
	clear   = 2.0,    -- hard margin above the ground
	-- === AND THE HARD FLOOR HAS A SPEED TOO (2026-09-12) ==================
	--
	-- Without this the hard floor was a bare `st.z = ground + clear`: an EIGHTY
	-- yard jump in ONE frame. It was the only path in the file capable of
	-- teleporting the camera, and it is the "plop" when crossing a cave mouth.
	--
	-- And the step filter above did not prevent it, QUITE THE OPPOSITE -- see
	-- the comment on the lag cap. Both skipped the limiter at once and for the
	-- same reason: both read `ground` RAW.
	--
	-- 40 yd/s is generous for real terrain: the camera travels at `speed` (30),
	-- so a 45 degree slope moves the ground 30 yd/s and a 53 degree one 40.
	-- Steeper than that is a cliff, and there having the camera dip into the
	-- rock for an instant and come out the top beats the jump.
	push    = 40.0,   -- yd/s; the fastest the hard floor may PUSH
	yawSign = 1,      -- if Q and E come out backwards, this is -1
	ease    = 9.0,    -- k of the start/stop on the plane (1/s); higher is sharper
	-- === THE ANCHOR IS NOT RIGID, AND CANNOT BE ===========================
	--
	-- The lock (the panel slot) pins the camera at a fixed distance from the
	-- hero, and the obvious thing would be to copy his position verbatim every
	-- frame. It does not come out well, and the cause is not in this file: the
	-- DLL publishes `RTS_PX/PY/PZ` at 33 Hz and the screen runs at 60 or more,
	-- so the hero position is a STAIRCASE with ~30 ms treads while the client
	-- draws the hero interpolated every frame. Copying it pins the camera to
	-- the tread, not to the hero: running at 7 yd/s that is 0.2 yards of jerk,
	-- back and forth, thirty-three times a second.
	--
	-- So the anchor CHASES the hero with the same exponential smoothing the
	-- height uses. The price is a fixed lag of `v / lockSmooth` -- at 25 and
	-- running, 0.28 yards out of thirty -- which is a constant, invisible
	-- offset that only changes while the hero accelerates or brakes. The
	-- staircase, by contrast, shows.
	lockSmooth = 25.0,   -- k of the hero follow with the lock on (1/s)
	-- THE HERO VIEW HEIGHT, AND BY DEFAULT IT IS NOT HIS HEAD (2026-09-15).
	--
	-- It started at 2.2 -- a human head, literally inside -- and the player
	-- measured it in game: **far too low**. And that makes sense, because at
	-- head height the world looks the way it looks to a pedestrian: the slope
	-- in front hides what is behind it, your own model eats the bottom third of
	-- the screen, and what you want from a camera attached to your hero is to
	-- SEE WHERE HE IS GOING, not to check his feet are on the floor.
	--
	-- It settled on FIVE, measured in game over two rounds: 2.2 was inside the
	-- head, 7 felt high, 5 is what he asked for. Above the model and above
	-- almost everything at ground level, and still close enough that it is THAT
	-- character view and not just another RTS camera.
	--
	-- AND IT IS STILL A SETTING, which is what it was before: `SPACE` and `C`
	-- raise and lower it live, and `/rts fc eyeH 4` sets it by hand. Both
	-- mouths write THIS number and not a live copy, which is what makes the
	-- height you climb to the height you get next time.
	eyeH    = 5.0,    -- yards above the hero FEET, with the camera attached
}

-- GENERATION STAMP, and it is needed because a setting CHANGED MEANING.
--
-- Generation 1 saved `pitch = -45` believing negative looked down. On this
-- client it is the other way round. And `-45` is still inside the valid range,
-- so `Cfg()` clamping let it through untouched: changing the default to +45 did
-- absolutely nothing on a client that already had it saved, and the camera went
-- on looking at the sky.
--
-- COMPARING THE RANGE IS NOT ENOUGH WHEN WHAT MOVED IS WHAT THE NUMBER MEANS.
-- It is the exact case of stage 5o `railCropGen` -- a valid index whose meaning
-- changed -- and the only coherent way out is to trust none of what was saved:
-- the whole table is thrown away, and it is said out loud.
-- GEN 3: mouse turning becomes NATIVE, so `lookSens` and `lookInv` stop
-- existing -- the addon used to own them and now the client does, with your own
-- mouse settings. A setting nobody reads any more is a dial wired to nothing.
local GEN = 3

-- The caps on the attached height. Below zero you would be looking from under
-- the hero feet; above fifty it is no longer his view, it is the free camera
-- with the lock on -- which exists, and is asked for by dropping the hero view
-- rather than by stretching this one until it means the same thing.
local EYE_MIN, EYE_MAX = 0.0, 50.0

-- === AND RAISING THE DEFAULT DOES NOT REACH ANYONE WHO HAS IT SAVED ======
--
-- This is the third time this project has hit the same rock, and the other two
-- are written a few lines below: the `pitch` that changed sign and went on
-- looking at the sky, and the `yawSign` that was inverted in the default and
-- did absolutely nothing. **What is saved beats the default**, so raising
-- `D.eyeH` from 2.2 to 7.0 would not have moved the camera of anyone who had
-- already entered the hero view once -- that is, of the only person using it --
-- and the symptom would have been "I changed it and it is still just as low".
--
-- A stamp for THIS KEY ALONE, not a new `GEN` for the whole table: a generation
-- throws away `speed`, `height`, `ease` and the other fifteen, and what changed
-- its mind here is one number. That one moves, it is announced, and nothing
-- else is touched.
--
-- 2 -> 3: from seven to five, measured in game. The stamp goes up again because
-- the problem is the same: anyone with 7.0 written down would never see the 5.0.
local EYE_GEN = 3

local function MigrateEye(c)
	if c.eyeGen == EYE_GEN then return end
	local was = c.eyeH
	c.eyeGen = EYE_GEN
	c.eyeH = D.eyeH
	-- It is ALWAYS said when there was a different value, even the old default:
	-- from outside "I changed it myself" and "the addon changed it" look
	-- identical, and keeping quiet turns an announced change into a surprise.
	if type(was) == "number" and math.abs(was - c.eyeH) > 0.01 then
		ns.Print(("|cffffd100RTS camera:|r the hero view height goes from %.1f to " ..
			"|cffffff00%.1f|r yd (the old one was measured in game and was far too " ..
			"low). |cffffff00/rts fc eyeH %.1f|r puts it back."):format(
			was, c.eyeH, was))
	end
end

local function Cfg()
	RTSCommandDB.freeCam = RTSCommandDB.freeCam or {}
	local c = RTSCommandDB.freeCam
	if c.gen ~= GEN then
		-- EVERYTHING is thrown away, not just `pitch`. A generation means "what
		-- was saved no longer means the same thing", so keeping the keys that
		-- "look fine" is deciding by hand all over again the very thing the
		-- generation exists to avoid deciding. The price -- losing the settings
		-- the player HAD tuned -- is paid by saying so, which is what separates
		-- a purge from a loss.
		if c.gen ~= nil or c.pitch ~= nil then
			ns.Print("|cffffd100RTS camera:|r settings reset (the sign of the " ..
				"tilt changed meaning).")
		end
		RTSCommandDB.freeCam = { gen = GEN }
		c = RTSCommandDB.freeCam
	end
	for k, v in pairs(D) do
		if type(c[k]) ~= "number" then c[k] = v end
	end
	-- AFTER the fill and BEFORE the clamping. After, because an `eyeH` that does
	-- not exist yet has to be worth something before it can be compared; before,
	-- because what the migration writes gets clamped too, like everything else.
	MigrateEye(c)
	-- WHAT IS SAVED GETS CLAMPED ON READING, not only on writing. SavedVariables
	-- outlive the version that wrote them, so a setting from an earlier version
	-- can be out of range and the `Set*` paths only run when the player types.
	-- Same lesson as `grow = 688`.
	if c.speed  <= 0 or c.speed  > 300 then c.speed  = D.speed  end
	if c.lift   <= 0 or c.lift   > 200 then c.lift   = D.lift   end
	if c.turn   <= 0 or c.turn   > 720 then c.turn   = D.turn   end
	if c.minH   <  0 or c.minH   > 100 then c.minH   = D.minH   end
	if c.maxH   <= c.minH               then c.maxH   = D.maxH   end
	if c.height < c.minH or c.height > c.maxH then c.height = D.height end
	if c.smoothZ <= 0 or c.smoothZ > 60 then c.smoothZ = D.smoothZ end
	-- `floor` is a choice, not a magnitude: anything else is garbage and goes
	-- back to the default rather than being clipped. And it is compared against
	-- 0/1 rather than `~= 1`, because a `nil` from an earlier version has
	-- already been handled by the loop above and what is left here is some
	-- arbitrary number.
	if c.floor ~= 0 and c.floor ~= 1 then c.floor = D.floor end
	if c.noclip ~= 0 and c.noclip ~= 1 then c.noclip = D.noclip end
	if c.climb <= 0 or c.climb > 500 then c.climb = D.climb end
	if c.soft  <= 0 or c.soft  > 100 then c.soft  = D.soft  end
	if c.slow  <  0 or c.slow  > 200 then c.slow  = D.slow  end
	-- At zero the hard floor stops pushing and the camera stays buried with no
	-- way out, which is worse than the bug this came to fix. An absurd value is
	-- garbage and goes back to the default; it is not clipped.
	if c.push  <= 0 or c.push  > 1000 then c.push  = D.push  end
	-- A speed floor above the ceiling would leave the knee with no effect and
	-- the `soft` setting with nothing to do -- a dial wired to nothing. The
	-- FLOOR is lowered rather than the ceiling raised: lowering `climb` is a
	-- clear intention ("make everything slow") and raising it back behind the
	-- player would be disobeying.
	if c.slow > c.climb then c.slow = c.climb end
	if c.pitch < -89 or c.pitch > 89    then c.pitch  = D.pitch  end
	if c.clear < 0 or c.clear > 50      then c.clear  = D.clear  end
	if c.yawSign ~= 1 and c.yawSign ~= -1 then c.yawSign = 1 end
	if c.ease <= 0 or c.ease > 60 then c.ease = D.ease end
	-- At zero the anchor would never move and the lock would look like it does
	-- nothing; too high it becomes the rigid copy the `D` comment explains is
	-- not wanted. Out of range is garbage and goes back to the default.
	if c.lockSmooth <= 0 or c.lockSmooth > 200 then c.lockSmooth = D.lockSmooth end
	-- THE SAME CAP THE KEYS USE, and it has to be the same number: if `SPACE`
	-- could get past this, this line would call the result garbage and send it
	-- back to the default ON THE NEXT FRAME -- so climbing past the cap would
	-- look like the camera falling out of the sky. Two different caps on the
	-- same number is a cap that gets forgotten; it already happened with the
	-- FOV floor.
	if c.eyeH < EYE_MIN or c.eyeH > EYE_MAX then c.eyeH = D.eyeH end
	return c
end

--- INPUT ------------------------------------------------------------------
--
-- Eight keys, on BOTH edges. Registering only the down edge gives one event per
-- press and no way of knowing it was released, which is exactly what a
-- hold-to-move control needs -- the same reason and the same mechanism SPACE
-- and C already used for the old camera.
--
-- AND THE LOCK IS NOT HERE, at the player request (2026-09-13): it is put on
-- and taken off ONLY from its panel slot. This table keeps the eight movement
-- keys and nothing else -- every key you take is a key you have to give back,
-- and one you never take cannot be given back wrong.
--
-- They are deliberately NOT secure buttons: nothing they do is protected.

local input = { fwd = false, back = false, left = false, right = false,
                up = false, down = false, yawL = false, yawR = false }

local KEYS = {
	{ key = "W",     field = "fwd"   },
	{ key = "S",     field = "back"  },
	{ key = "A",     field = "left"  },
	{ key = "D",     field = "right" },
	{ key = "SPACE", field = "up"    },
	{ key = "C",     field = "down"  },
	{ key = "Q",     field = "yawL"  },
	{ key = "E",     field = "yawR"  },
}

local buttons = {}
local savedBindings = nil

local function MakeButtons()
	if buttons.fwd then return end
	for _, k in ipairs(KEYS) do
		local name = "RTSFreeCam" .. k.field
		local b = _G[name] or CreateFrame("Button", name, UIParent)
		b:Hide()
		b:RegisterForClicks("AnyDown", "AnyUp")
		local field = k.field
		b:SetScript("OnClick", function(_, _, down)
			input[field] = (down == true)
		end)
		buttons[k.field] = b
	end
end

-- THE KEYS ARE RECORDED BEFORE BEING TOUCHED AND COME BACK ON EXIT, which is
-- the hard rule of this project. All eight are taken out of the box -- WASD is
-- movement, SPACE jumps, C opens the character sheet, Q/E strafe -- so giving
-- them back is not courtesy: without it the player is left unable to move in
-- normal play after entering RTS mode once.
--
-- `SaveBindings` is NEVER called: they are restored on the way out and never
-- saved, so a reload, a disconnect or an unexpected crash leaves the player
-- real bindings untouched.
local function GrabKeys()
	if InCombatLockdown() then
		ns.Print("|cffff8800camera:|r the keys cannot be taken in combat.")
		return false
	end
	MakeButtons()
	savedBindings = {}
	for _, k in ipairs(KEYS) do
		savedBindings[k.key] = GetBindingAction(k.key) or ""
		SetBindingClick(k.key, buttons[k.field]:GetName())
	end
	return true
end

local function ReleaseKeys()
	if not savedBindings then return true end
	if InCombatLockdown() then return false end
	for key, action in pairs(savedBindings) do
		if action ~= "" then
			SetBinding(key, action)
		else
			SetBinding(key, nil)
		end
	end
	savedBindings = nil
	for k in pairs(input) do input[k] = false end
	return true
end

--- SOLVER + SMOOTHING ------------------------------------------------------

-- PITCH IS STATE, NOT JUST A SETTING: the mouse changes it (see `AdoptLook`),
-- so the `Cfg().pitch` value is only what you ENTER with.
local st = { x = nil, y = nil, z = nil, yaw = 0, pitch = nil, offset = nil,
             vx = 0, vy = 0,
             -- `gz` is the FILTERED ground: the one the camera believes is
             -- under it, chasing the measured one at a limited speed. It is
             -- state and not a tick-local on purpose -- with no memory between
             -- frames there is no filter, only the ground under a new name.
             gz = nil, gstep = 0,
             -- THE LOCK: `a*` is the anchor (the hero, chased with
             -- smoothing) and `o*` the framing (what separates the camera from
             -- the anchor). With the lock on the camera has NO position of its
             -- own: it is always `anchor + framing`, and the keys move the
             -- FRAMING, not the camera. That is why the framing "stays":
             -- nothing else writes it.
             ax = nil, ay = nil, az = nil,
             ox = 0, oy = 0, oz = 0 }

-- The lock is on. It lives on `F` and not on `st` because it gets asked about
-- from outside -- the report, the command -- and `st` belongs to the solver.
F.lock = false

-- AND THE HERO VIEW IS A SECOND FLAG, NOT A VALUE OF THE FIRST. `eyes` implies
-- `lock` -- the camera hangs off the hero just the same -- and what it adds is
-- that the framing stops being the player. Storing it as "lock = 2" would have
-- forced every `if self.lock` in the file to ask which of the two, which is how
-- branches that only work in one mode get in.
F.eyes = false

-- Ninguna de las funciones de comentarista se habia llamado nunca en este
-- proyecto, asi que todas pasan por aqui: si una no existe, el controlador
-- sigue funcionando en vez de reventar en cada frame.
-- El avance plano y el suelo, las dos lecturas del DLL en las que se apoya todo
-- lo demas. Van JUNTO A `st` y no cerca del giro a proposito: las he borrado
-- por accidente DOS VECES al reescribir el bloque del raton, porque estaban
-- dentro del rango que sustituia. Aqui no hay nada que reescribir.
local function FlatForward()
	if RTS_HasCam ~= 1 then return nil end
	local fx, fy = RTS_CamFwdX, RTS_CamFwdY
	if not fx or not fy then return nil end
	local len = math.sqrt(fx * fx + fy * fy)
	-- Mirando a plomo hacia abajo la proyeccion es casi cero y la direccion deja
	-- de estar definida. No se normaliza una longitud minuscula: no hay
	-- adelante, y ese frame no se avanza -- preferible a salir disparado en una
	-- direccion aleatoria.
	if len < 0.001 then return nil end
	return fx / len, fy / len
end

-- EL SUELO, Y DE CUAL DE LOS DOS RAYOS SALE.
--
-- El DLL publica dos alturas bajo la camara y la diferencia entre ellas es
-- todo el problema del tejado:
--
--   `RTS_CamGroundZ` -- lo PRIMERO que hay debajo. Un tejado, un cartel, la
--                       copa de un arbol. Es la que habia, y es la buena para
--                       sobrevolar un sitio sin meterse en nada.
--   `RTS_CamLandZ`   -- solo el TERRENO. Lo construido deja de ser suelo, asi
--                       que ni un tejado levanta la camara ni le impide bajar
--                       hasta dentro de la casa.
--
-- Devuelve tambien de donde ha salido, porque "la camara sube sola" y "la
-- camara no baja" son el mismo sintoma con las dos fuentes cambiadas, y
-- distinguirlo mirando la pantalla cuesta una ronda.

-- LA CAJA NEGRA DE LA BOCA. Avisa cuando el terreno se queda arriba, porque es
-- el unico instante que importa y dura menos de lo que se tarda en escribir
-- `/rts fc`. Se limita a un aviso cada dos segundos: dentro de una cueva la
-- condicion es cierta en TODOS los frames, y sin el freno serian sesenta lineas
-- por segundo tapando el chat.
local lastBox = 0
local function BlackBox(land, solid)
	local now = GetTime and GetTime() or 0
	if now - lastBox < 2.0 then return end
	lastBox = now
	ns.Print(("|cffff8800techo de roca|r: terreno %.1f ARRIBA, solido %.1f abajo, camara %.1f -- se usa el solido")
		:format(land, solid, st.z or 0))
end

-- EL RAYO QUE DICE QUE CHOCO SIN CHOCAR (2026-09-12).
--
-- Dentro de la cueva, `/rts fc` imprimio esto:
--
--     suelo: terreno 0.0   solido 1345.7   en uso: terreno
--
-- `terreno 0.0` NO es "no ha contestado" -- eso se imprime como `--`. Es que
-- `RTS_CamLandHit` vino a 1 y `RTS_CamLandZ` a cero: el rayo de terreno dijo que
-- SI choco, y no escribio donde. En el DLL, `Cast` arranca `out = {0,0,0}` y lo
-- devuelve tal cual si `CGWorldFrame::Intersect` contesta cierto sin tocarlo,
-- que es lo que hace ahi donde el ADT esta agujereado a proposito -- o sea justo
-- dentro de una cueva.
--
-- Y AHI ESTA EL PLOP, entero, sin bucles ni acantilados: un suelo de 0.0 con la
-- camara a 1345 es un desnivel de mil trescientas yardas hacia abajo, mas grande
-- que `GROUND_SNAP`, asi que el filtro hace lo que tiene mandado con un salto
-- imposible -- se pone al dia DE GOLPE -- y la camara aparece a `0 + offset`, en
-- el fondo del mundo. Por eso no se sabia si iba arriba o abajo: iba abajo, del
-- todo, en un frame.
--
-- La regla es que un choque tiene que caer DENTRO del segmento que se disparo.
-- El DLL lanza desde `cam.z + 5` hasta `cam.z - 1000`; cualquier cosa fuera de
-- ahi no la ha podido tocar ese rayo. No hay constante que inventar: son las dos
-- del publicador. El cero se descarta ademas por su cuenta, porque es el valor
-- que el propio publicador escribe cuando NO hay choque y ningun suelo del mundo
-- cae exactamente en 0.000.
--
-- Esto tapa el sintoma en el lado barato -- un `/reload` en vez de recompilar e
-- inyectar. El arreglo de raiz es que el DLL no publique un choque que no ha
-- escrito.
local RAY_UP, RAY_DOWN = 5.0, 1000.0

local function RayHit(hit, z)
	if hit ~= 1 or type(z) ~= "number" then return nil end
	if z == 0 then return nil, "0.0" end
	if st.z and (z > st.z + RAY_UP + 0.5 or z < st.z - RAY_DOWN) then
		return nil, ("%.1f"):format(z)
	end
	return z
end

-- EL RAYO DEL TECHO (rts_core 0.29.0). Mira las `RAY_UP` yardas de ENCIMA de la
-- camara, y solo terreno. Es lo unico que el adelanto del rayo de abajo compraba
-- -- salir de debajo del suelo cuando el suavizado te ha colado -- separado en un
-- dato con su propio nombre, ahora que el de abajo arranca en la camara y por fin
-- significa "lo que hay DEBAJO".
--
-- Con un rts_core viejo esto es nil y no pasa nada: la franja ciega vuelve, que
-- es exactamente como se venia funcionando.
local function CeilAbove()
	local z = RayHit(RTS_CamCeilHit, RTS_CamCeilZ)
	if z and st.z and z >= st.z and z <= st.z + RAY_UP + 0.5 then return z end
	return nil
end

local function GroundUnderCamera(c)
	local land  = RayHit(RTS_CamLandHit,  RTS_CamLandZ)
	local solid = RayHit(RTS_CamGroundHit, RTS_CamGroundZ)
	if c.floor == 1 then
		-- EL TERRENO DEJA DE SER SUELO CUANDO ESTA POR ENCIMA DE LA CABEZA.
		--
		-- Aqui estaba la causa de las cuevas, y no en la aritmetica de la
		-- altura: la aritmetica hacia exactamente lo que se le pedia con una
		-- MEDIDA QUE NO ERA UN SUELO. Al cruzar la boca, la XY de la camara pasa
		-- por debajo de la silueta de la montana; el ADT solo esta agujereado en
		-- el INTERIOR, asi que el rayo de terreno sigue contestando -- y lo que
		-- devuelve es la ladera de fuera, decenas de yardas POR ENCIMA. El suelo
		-- duro lee eso y hace lo unico que sabe hacer: empujar la camara hasta
		-- `ground + clear`, o sea al tejado de la montana, atravesando la roca
		-- durante todo el camino. Eso es la pantalla lila, y por eso el `/rts fc`
		-- de dentro salia coherente: las cuentas cuadraban con la superficie
		-- equivocada.
		--
		-- Un suelo esta DEBAJO. Si el terreno queda arriba y el solido queda
		-- abajo, el solido es el suelo de la cueva y el terreno es el techo de
		-- roca que tenemos encima: no hay nada que decidir.
		--
		-- Y la regla no toca el acantilado, que es el caso que parece el mismo:
		-- volando contra un risco el terreno tambien queda arriba, pero ahi NO
		-- hay solido debajo -- el risco es terreno pelado -- asi que el `if` no
		-- entra y la camara lo sube como hasta ahora. Hace falta que las DOS
		-- cosas pasen a la vez, y eso solo pasa bajo techo.
		if land and solid and st.z and land > st.z and solid < st.z then
			BlackBox(land, solid)
			return solid, "solido (el terreno queda arriba)"
		end
		if land then return land, "terreno" end
		-- CAER AL SOLIDO NO ES DEGRADARSE AQUI, ES ACERTAR. Dentro de una cueva
		-- el ADT esta agujereado a proposito y el rayo de terreno NO CONTESTA:
		-- el suelo bueno de ese sitio es justamente el solido -- el suelo de la
		-- cueva. Es tambien lo que pasa con un DLL viejo, que no publica
		-- `RTS_CamLandZ` en absoluto, y ahi la camara se porta como antes en vez
		-- de quedarse sin altura.
		if solid then return solid, "solido (sin terreno aqui)" end
		return nil, nil
	end
	if solid then return solid, "solido" end
	return nil, nil
end

-- Un cambio de suelo mas grande que esto NO es un escalon del mundo: es un
-- teleport, un cambio de mapa o el primer frame. Filtrarlo a 6 yd/s dejaria la
-- camara subiendo durante minuto y medio, asi que ahi se salta de golpe.
local GROUND_SNAP = 300.0

local function Try(name, ...)
	local fn = _G[name]
	if type(fn) ~= "function" then return false end
	local ok, a, b, c, d, e, f = pcall(fn, ...)
	if not ok then return false end
	return true, a, b, c, d, e, f
end

-- === EL GIRO ES NATIVO. NOSOTROS SOLO LLEVAMOS LA POSICION ===============
--
-- QUINTO INTENTO, y el que sobra es el cuarto: leer el raton en crudo desde el
-- DLL y girar nosotros. Funcionaba y se sentia mal -- **a trompicones, con
-- latencia y demasiado sensible**, y con el eje horizontal invertido. Y tenia
-- que sentirse mal por construccion: el DLL acumula deltas, los publica a 67 Hz
-- por una cadena de Lua, y el addon los aplica al frame siguiente. Tres etapas
-- de retardo y una cuantizacion, para reimplementar algo que el cliente ya hace
-- perfecto.
--
-- Y LA EVIDENCIA DE QUE EL CLIENTE LO HACE BIEN YA LA TENIAMOS, mal leida. En
-- la 1.17.0 el jugador dijo *"ahora he podido mover la camara con el raton pero
-- no con WASD"*. En esa version el controlador estaba CAIDO -- habia borrado
-- `FlatForward` por accidente -- asi que no escribia la camara en absoluto, y
-- el arrastre nativo del cliente movia la camara que se ve. O sea que el giro
-- nativo SI llega a nuestra camara; lo que lo mataba era que yo sobrescribiera
-- los angulos cada frame. Mi conclusion de entonces ("gira otra camara") era
-- falsa, y la saque de una prueba hecha con el controlador muerto.
--
-- Asi que el reparto queda: **el cliente lleva la ORIENTACION, nosotros la
-- POSICION.** El raton derecho es el mouselook de siempre -- con la
-- sensibilidad y la inversion que el jugador ya tiene configuradas, gratis -- y
-- WASD, ESPACIO/C y la altura sobre el terreno siguen siendo nuestros.
--
-- COMO SE CONVIVE, que es lo unico con truco: `CommentatorSetCamera` toma los
-- seis valores de golpe, asi que no se puede escribir la posicion sin escribir
-- los angulos. Se LEEN los vivos justo antes y se vuelven a escribir tal cual:
-- para la orientacion es un no-op y el giro del cliente se acumula solo.
--
-- Se leen con `CommentatorGetCamera`, que es SINCRONO y lee `cam+0x11C`/`+0x120`
-- de la camara activa en este mismo frame -- no `RTS_CamFwd*`, que viene del DLL
-- con un tick de retraso. Esa eleccion es la que quita la latencia.
local function AdoptLook()
	local ok, _, _, _, yaw, pitch = Try("CommentatorGetCamera")
	if not ok or type(yaw) ~= "number" or type(pitch) ~= "number" then return end
	st.yaw = yaw % 360
	if pitch < -89 then pitch = -89 end
	if pitch > 89 then pitch = 89 end
	st.pitch = pitch
end

-- === HACIA DONDE MIRA EL HEROE, EN YAW DE COMENTARISTA =================
--
-- Entrar en primera persona es lo unico de este fichero que necesita PEDIR un
-- yaw concreto -- el del heroe -- y ahi vuelve la pregunta que todo lo demas
-- lleva evitando desde el principio: CUAL ES LA CONVENCION DE ANGULOS DE
-- `CommentatorSetCamera`. No se puede leer del binario (el desensamblado solo
-- ensena que el argumento se multiplica por DEG2RAD y se guarda), y este
-- proyecto ya ha pagado DOS VECES por adivinar un signo: el `pitch` de aqui
-- arriba y los dos `SetPosition` del retrato.
--
-- Asi que no se adivina: se MIDE, con dos datos que ya estan en pantalla.
--
--   * `CommentatorGetCamera` da el yaw VIVO de la camara.
--   * el DLL publica su adelante en coordenadas del MUNDO (`RTS_CamFwdX/Y`),
--     que en angulo es `atan2(fy, fx)` -- la misma convencion que `RTS_PF`.
--
-- Con un solo par no basta: dice el desfase pero NO EL SIGNO -- un yaw que
-- creciera al reves encaja igual de bien en una sola muestra, y el error solo
-- se veria como una entrada espejada. Con dos pares a yaws distintos salen los
-- dos de golpe:
--
--     mundo = signo * yaw + desfase
--
-- Y LAS MUESTRAS SE TOMAN CON LA CAMARA QUIETA. El adelante viene del DLL a 100
-- Hz y el yaw se lee en este mismo frame: mientras se gira son dos instantes
-- distintos, o sea que la medida saldria torcida justo cuando mas se mueve.
-- Parada, los dos son del mismo sitio y la resta es exacta.
--
-- NO HACE FALTA PEDIRLE NADA AL JUGADOR. La segunda muestra llega sola en
-- cuanto gire la camara, que es lo primero que hace cualquiera; hasta entonces
-- se usa el desfase de una sola con el signo supuesto, que es lo que habria
-- habido de todas formas.
local look = { prev = nil, refY = nil, refW = nil, sign = nil, delta = nil }

local function Wrap180(d)
	d = d % 360
	if d > 180 then d = d - 360 end
	return d
end

local function CamWorldAngle()
	if RTS_HasCam ~= 1 then return nil end
	local fx, fy = RTS_CamFwdX, RTS_CamFwdY
	if type(fx) ~= "number" or type(fy) ~= "number" then return nil end
	-- Mirando a plomo la proyeccion es casi cero y el angulo deja de estar
	-- definido; misma criba que `FlatForward` y por la misma razon.
	if (fx * fx + fy * fy) < 0.000001 then return nil end
	return math.deg(math.atan2(fy, fx))
end

local function CalibrateYaw()
	local yaw, prev = st.yaw, look.prev
	look.prev = yaw
	if not yaw or not prev then return end
	if math.abs(Wrap180(yaw - prev)) > 0.02 then return end   -- girando: no vale
	local w = CamWorldAngle()
	if not w then return end
	if not look.refY then
		look.refY, look.refW = yaw, w
		return
	end
	local dy = Wrap180(yaw - look.refY)
	local ady = math.abs(dy)
	-- Por debajo de 20 grados la medida es todo ruido; por encima de 170 el
	-- signo del envoltorio deja de estar claro (a 180 justos, +1 y -1 dan lo
	-- mismo). Fuera de esa ventana no se concluye nada y se sigue esperando.
	if ady < 20 or ady > 170 then return end
	local dw = Wrap180(w - look.refW)
	-- LA COMPROBACION QUE CONVIERTE UNA SUPOSICION EN UNA MEDIDA: si el mundo no
	-- ha girado LO MISMO que el yaw, la relacion no es `signo * yaw + desfase` y
	-- no hay nada que deducir. Sin esto, un modelo equivocado saldria como un
	-- signo con toda la confianza del mundo.
	if math.abs(math.abs(dw) - ady) > 5 then return end
	look.sign = (dw * dy >= 0) and 1 or -1
	look.delta = Wrap180(w - look.sign * yaw)
	look.refY, look.refW = yaw, w
end

-- Una direccion del MUNDO (radianes, la convencion de `RTS_PF`) en yaw.
local function YawForWorld(rad)
	local sign, delta = look.sign, look.delta
	if not sign then
		-- Sin las dos muestras todavia: el desfase de UNA, dando por hecho que
		-- el yaw crece como el angulo del mundo. Si eso fuera falso, esta
		-- entrada sale espejada y la siguiente ya no -- en cuanto el jugador
		-- gire, la medida de verdad esta hecha.
		local w = CamWorldAngle()
		if not w or not st.yaw then return nil end
		sign, delta = 1, Wrap180(w - st.yaw)
	end
	return ((math.deg(rad) - delta) * sign) % 360
end

local function LookReport()
	if look.sign then
		return ("signo %+d, desfase %.1f |cff888888(medido con dos muestras)|r"):format(
			look.sign, look.delta)
	end
	local w = CamWorldAngle()
	if w and st.yaw then
		return ("desfase %.1f |cffff8800(una sola muestra: gira la camara para medir el signo)|r"):format(
			Wrap180(w - st.yaw))
	end
	return "|cffff8800sin medir|r (¿camara publicada?)"
end

-- Los botones, del DLL. `IsMouseButtonDown` devuelve NO mientras el cliente
-- tiene el raton cogido, asi que para saber si estan los DOS pulsados no hay
-- otra fuente. Se queda solo para el gesto de avanzar; el giro ya no lo usa.
local function MouseButtons()
	if RTS_MouseRaw ~= 1 then return false, false end
	local b = tonumber(RTS_MouseB) or 0
	return (b % 2) == 1, (math.floor(b / 2) % 2) == 1
end

--- EL CANDADO -------------------------------------------------------------
--
-- Un interruptor, y hace UNA cosa: mientras esta puesto, la camara se queda a
-- la misma distancia del heroe -- la que tuviera al encenderlo -- y viaja con
-- el. Para seguir al grupo por el camino sin conducir la camara a mano.
--
-- LO QUE NO HACE, que es la mitad que se pidio por escrito: no toca el angulo,
-- no toca la altura, no recoloca nada. El encuadre lo pone el jugador -- con el
-- raton, con W/A/S/D, con ESPACIO y C -- y se queda tal cual hasta que lo
-- vuelva a tocar. Aqui no hay ni una decision de encuadre.
--
-- POR ESO LAS TECLAS MUEVEN EL ENCUADRE Y NO LA CAMARA. Con el candado puesto,
-- la posicion de la camara es SIEMPRE `ancla + encuadre`, asi que escribir en
-- ella directamente -- como hace el modo libre -- seria escribir en un valor
-- que se recalcula entero el frame siguiente: las teclas pareceria que no
-- hacen nada. Sumando al encuadre, retocar el plano mientras se viaja funciona
-- igual que siempre y lo retocado PERSISTE, que es exactamente lo que se
-- pidio.
--
-- Y AQUI NO HAY SUELO. Ni rayo, ni filtro de escalon, ni suelo duro, ni
-- presupuesto de empuje: la Z sale del heroe, que ya va por el suelo por su
-- cuenta. Meter la correccion de altura seria un segundo dueno de la Z
-- discutiendo con el candado cada frame -- la forma de pelea que este fichero
-- ya ha perdido dos veces -- y ademas romperia la promesa de la distancia fija
-- en cuanto el heroe pasara por debajo de un tejado.
local function HeroPos()
	if RTS_HasPos ~= 1 then return nil end
	local x, y, z = RTS_PX, RTS_PY, RTS_PZ
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return nil
	end
	return x, y, z
end

local function Follow(c, dt)
	local hx, hy, hz = HeroPos()
	-- Sin posicion del heroe este tick no se inventa una: la camara se queda
	-- donde esta. Pasa al cambiar de zona y dura lo que tarda el DLL en volver
	-- a publicar.
	if not hx then return end

	if not st.ax then
		st.ax, st.ay, st.az = hx, hy, hz
	else
		-- UN CAMBIO DE MAPA NO ES UN PASO. Igual que `GROUND_SNAP` para el
		-- suelo: por encima de esa distancia el heroe no se ha movido, lo han
		-- movido -- teleport, portal, cambio de personaje -- y perseguirlo con
		-- suavizado seria cruzar el continente a la vista. Ahi se salta.
		local dx, dy, dz = hx - st.ax, hy - st.ay, hz - st.az
		if (dx * dx + dy * dy + dz * dz) > (GROUND_SNAP * GROUND_SNAP) then
			st.ax, st.ay, st.az = hx, hy, hz
		else
			local a = 1 - math.exp(-c.lockSmooth * dt)
			st.ax = st.ax + dx * a
			st.ay = st.ay + dy * a
			st.az = st.az + dz * a
		end
	end

	if F.eyes then
		-- LAS OCHO TECLAS VALEN AQUI TAMBIEN (2026-09-15). Lo que queda de
		-- exclusivo de este modo no es una restriccion, es POR DONDE SE ENTRA:
		-- encima del heroe, mirando a donde mira el, en un clic. Eso era lo
		-- caro; prohibir moverse una vez dentro no compraba nada y se pidio
		-- quitarlo.
		--
		-- EL PLANO ES DEL RATO, LA ALTURA ES TUYA, y la asimetria es a
		-- proposito. `ox`/`oy` se olvidan al salir y por eso volver a entrar
		-- VUELVE A PONER LA CAMARA SOBRE EL HEROE -- que es para lo que se
		-- pulsa el boton; si se guardaran, el segundo clic te dejaria donde ya
		-- estabas y el boton no serviria de nada. La altura no es de este rato:
		-- es a que distancia te gusta ir de tu personaje, la misma en la
		-- siguiente partida.
		st.ox = st.ox + st.vx * dt
		st.oy = st.oy + st.vy * dt

		-- POR ESO LA ALTURA ESCRIBE EN EL AJUSTE Y EL PLANO NO. Un solo numero,
		-- dos bocas: `ESPACIO`/`C` y `/rts fc eyeH`.
		local lift = 0
		if input.up then lift = lift + 1 end
		if input.down then lift = lift - 1 end
		if lift ~= 0 then
			local h = c.eyeH + lift * c.lift * dt
			-- Acotado AQUI con las mismas dos constantes que usa `Cfg`, no con
			-- numeros nuevos: ver el comentario de alla. Se recorta en vez de
			-- rebotar, que es lo que hace que mantener la tecla contra el tope
			-- se sienta como un tope y no como un fallo.
			if h < EYE_MIN then h = EYE_MIN end
			if h > EYE_MAX then h = EYE_MAX end
			c.eyeH = h
		end
		-- La Z se reescribe entera cada frame en vez de ponerla una vez al
		-- entrar, y eso es lo que hace que tanto las teclas como
		-- `/rts fc eyeH 4` se vean AHORA -- un ajuste que solo entra al volver a
		-- entrar en el modo se lee como un ajuste que no funciona.
		st.oz = c.eyeH
	else
		-- Las teclas RETOCAN EL ENCUADRE. Misma velocidad y mismo suavizado que
		-- en el modo libre: `st.vx/vy` ya vienen calculadas del mismo solver de
		-- arriba, asi que el plano se siente igual con el candado puesto.
		st.ox = st.ox + st.vx * dt
		st.oy = st.oy + st.vy * dt
		local lift = 0
		if input.up then lift = lift + 1 end
		if input.down then lift = lift - 1 end
		if lift ~= 0 then st.oz = st.oz + lift * c.lift * dt end
	end

	st.x = st.ax + st.ox
	st.y = st.ay + st.oy
	st.z = st.az + st.oz

	-- El suelo filtrado se olvida MIENTRAS dura el candado, no al soltarlo: asi
	-- el primer tick libre se engancha a lo que haya debajo de donde la camara
	-- haya acabado, en vez de venir arrastrando el suelo de otro continente.
	st.gz, st.gstep, st.buried = nil, 0, 0
end

-- LA CASILLA DEL PANEL TIENE QUE ENTERARSE, y no puede enterarse sola: se
-- repinta en los cambios de SELECCION (`Panel:Refresh`, suscrito a
-- `ns.Selection`), y el candado no es uno. Sin este aviso, poner el candado
-- dejaria el boton apagado hasta el siguiente click en un companero -- o sea un
-- indicador que miente sobre lo que uno acaba de pulsar.
--
-- Va en `SetLock` y no en la casilla porque el estado se cambia AQUI: quien
-- repinta tiene que colgar de quien decide, no de quien pulsa.
local function Repaint()
	-- El candado se dibujaba en una casilla de la rejilla 4x4, que ya no existe;
	-- desde el 2026-09-13 es un macro y no hay ningun boton que repintar.
	if ns.Cast and ns.Cast.Refresh then ns.Cast:Refresh() end
end

-- Encender y apagar. Devuelve si el candado ha quedado como se pedia.
function F:SetLock(on)
	if not self.active then
		ns.Print("|cffff8800camara RTS:|r la camara libre no esta activa.")
		return false
	end

	if not on then
		if self.lock then
			self.lock = false
			-- SOLTAR EL CANDADO SUELTA TAMBIEN LA PRIMERA PERSONA, porque la
			-- primera persona ES el candado: dejar `eyes` puesto con `lock`
			-- quitado seria una bandera encendida que ya no manda sobre nada,
			-- y la casilla diria "primera persona" con la camara suelta.
			self.eyes = false
			-- `offset` se recalcula solo en el primer tick libre (el bloque del
			-- anclaje): con `gz` a nil, la altura que tenga la camara AHORA
			-- pasa a medirse contra el suelo de donde este. Sin esto la camara
			-- volveria de golpe a la altura con la que se encendio el candado.
			st.gz, st.gstep, st.buried = nil, 0, 0
			Repaint()
			ns.Print("|cff33ccffcamara RTS:|r candado |cffff8800SUELTO|r.")
		end
		return true
	end

	local hx, hy, hz = HeroPos()
	if not hx then
		ns.Print("|cffff0000camara RTS:|r el DLL no publica la posicion de tu heroe.")
		return false
	end
	if not st.x then
		ns.Print("|cffff0000camara RTS:|r la camara no tiene sitio todavia.")
		return false
	end

	-- EL ENCUADRE SE CAPTURA, NO SE ELIGE. La distancia y la direccion son las
	-- que haya en pantalla en este instante: encender el candado no debe mover
	-- ni un pixel, solo dejar de soltar.
	st.ax, st.ay, st.az = hx, hy, hz
	st.ox, st.oy, st.oz = st.x - hx, st.y - hy, st.z - hz
	self.lock = true
	Repaint()
	ns.Print(("|cff33ccffcamara RTS:|r candado |cff00ff00PUESTO|r a %.1f yd del heroe."):format(
		math.sqrt(st.ox * st.ox + st.oy * st.oy + st.oz * st.oz)))
	return true
end

function F:ToggleLock()
	return self:SetLock(not self.lock)
end

--- LA PRIMERA PERSONA -----------------------------------------------------
--
-- La camara se mete en la cabeza del heroe y se queda ahi. Lo unico que hace
-- falta decidir aqui es POR DONDE SE ENTRA -- el sitio y hacia donde se mira --
-- porque a partir del frame siguiente lo lleva todo `Follow`.
--
-- ENTRAR TIENE QUE SER INSTANTANEO, no un viaje. Si esto se limitara a poner
-- las banderas, la camara viajaria desde donde estuviera hasta la cabeza
-- arrastrada por el suavizado del ancla -- cien yardas de vuelo desde la vista
-- de pajaro -- que se ve como que el modo tarda en arrancar. Se escribe la
-- posicion entera aqui mismo y se aplica en el acto.
function F:SetEyes(on)
	if not self.active then
		ns.Print("|cffff8800camara RTS:|r la camara libre no esta activa.")
		return false
	end

	if not on then
		if self.eyes then
			self.eyes = false
			self.lock = false
			-- Con `gz` a nil el primer tick libre mide el suelo de DONDE ESTA la
			-- camara (la cabeza del heroe) en vez de traerse el de antes de
			-- entrar: si no, salir de primera persona seria un salto de altura.
			st.gz, st.gstep, st.buried = nil, 0, 0
			Repaint()
			ns.Print("|cff33ccffcamara RTS:|r primera persona |cffff8800FUERA|r " ..
				"|cff888888(la camara se queda donde estaba la cabeza)|r.")
		end
		return true
	end

	local hx, hy, hz = HeroPos()
	if not hx then
		ns.Print("|cffff0000camara RTS:|r el DLL no publica la posicion de tu heroe.")
		return false
	end

	local c = Cfg()
	st.ax, st.ay, st.az = hx, hy, hz
	st.ox, st.oy, st.oz = 0, 0, c.eyeH
	st.x, st.y, st.z = hx, hy, hz + c.eyeH
	-- La velocidad del plano se tira a la basura: con las teclas desconectadas
	-- no hay quien la frene, asi que un W a medio soltar al entrar se quedaria
	-- guardado y saldria de golpe al salir.
	st.vx, st.vy = 0, 0
	st.gz, st.gstep, st.buried = nil, 0, 0

	-- HACIA DONDE MIRA EL HEROE, Y SOLO AL ENTRAR. Despues es del jugador: no
	-- se vuelve a tocar el yaw ni un frame mas, que es la mitad de lo que se
	-- pidio -- "que despues se pueda reorientar".
	local yaw = (type(RTS_PF) == "number") and YawForWorld(RTS_PF) or nil
	if yaw then st.yaw = yaw end
	-- Al horizonte. Un heroe no entra mirandose los pies, y la inclinacion de
	-- la camara RTS (45 grados hacia abajo de fabrica) ahi dentro es el suelo.
	st.pitch = 0

	self.lock = true
	self.eyes = true
	Repaint()
	ns.Camera:SpecPlace(st.x, st.y, st.z, st.yaw, st.pitch, nil)
	ns.Print(("|cff33ccffcamara RTS:|r |cff00ff00vista del heroe|r, %.1f yd sobre sus pies."):format(c.eyeH))
	if not yaw then
		ns.Print("  |cffff8800No se hacia donde mira|r: gira la camara un momento " ..
			"y vuelve a entrar (|cffffff00/rts fc|r lo explica).")
	end
	ns.Print("  |cff888888El raton y Q/E giran, W/A/S/D retocan el sitio y " ..
		"ESPACIO/C la altura. Te lleva el heroe.|r")
	return true
end

function F:ToggleEyes()
	return self:SetEyes(not self.eyes)
end

function F:Step(dt)
	if not self.active then return end
	-- Un frame perdido (carga de zona, alt-tab) puede traer un dt enorme, y
	-- con el la camara pega un salto. Se acota: mas vale ir un poco lento un
	-- frame que teletransportarse.
	if dt <= 0 then return end
	if dt > 0.1 then dt = 0.1 end

	local c = Cfg()

	-- PRIMERO los angulos vivos, DESPUES nuestras teclas. Al reves, el giro de
	-- Q/E de este frame se perderia: la adopcion sobreescribe el yaw entero.
	AdoptLook()
	-- JUSTO DESPUES DE ADOPTAR y antes de que Q/E toquen nada: aqui `st.yaw` es
	-- todavia el yaw VIVO de la camara, que es el unico que se puede comparar
	-- con el adelante que publica el DLL. Un frame mas tarde ya seria el yaw que
	-- vamos a pedir, y la medida compararia dos instantes distintos.
	CalibrateYaw()
	local mouseLeft, mouseRight = MouseButtons()

	-- --- giro ---------------------------------------------------------
	-- Q y E VAN AL REVES QUE ANTES, a peticion del jugador (2026-09-10).
	--
	-- Se invierte AQUI y no cambiando el defecto de `yawSign`, que era lo obvio
	-- y no habria hecho nada: ese ajuste ya esta guardado a 1 en las
	-- SavedVariables, y lo guardado gana al defecto. Cambiar un valor por
	-- defecto solo alcanza a quien todavia no lo tiene escrito -- la misma
	-- trampa que dejo el `pitch` sin efecto cuando cambio de significado.
	--
	-- `yawSign` sigue significando lo mismo (**-1 si te sale al reves**), asi
	-- que el mando no cambia de sentido bajo los pies de nadie: lo que cambia es
	-- hacia donde gira el sentido "normal".
	local turn = 0
	if input.yawL then turn = turn + 1 end
	if input.yawR then turn = turn - 1 end
	if turn ~= 0 then
		st.yaw = (st.yaw + turn * c.yawSign * c.turn * dt) % 360
	end

	-- --- desplazamiento en el plano -----------------------------------
	local wantX, wantY = 0, 0
	local mx, my = 0, 0
	if input.fwd then my = my + 1 end
	if input.back then my = my - 1 end
	-- IZQUIERDO + DERECHO AVANZA, el gesto de siempre. Los botones vienen del
	-- DLL y no de `IsMouseButtonDown`, que miente durante el arrastre. Va aqui
	-- y no en un sitio aparte porque es una entrada mas del mismo solver: asi
	-- avanzar con el raton y girar a la vez sale gratis, en el mismo frame.
	if mouseLeft and mouseRight then my = my + 1 end
	if input.right then mx = mx + 1 end
	if input.left then mx = mx - 1 end

	if mx ~= 0 or my ~= 0 then
		local fx, fy = FlatForward()
		if fx then
			-- El lateral es el avance girado 90 grados en el plano. NO se usa
			-- `RTS_CamRight*`: el DLL documenta que la fila "right" de la
			-- matriz del cliente es la IZQUIERDA geometrica, y depender de ese
			-- signo aqui seria heredar una trampa que ya esta resuelta en otro
			-- sitio. Un giro de 90 grados no puede tener el signo mal sin que
			-- se vea al instante.
			local rx, ry = fy, -fx
			local dx = fx * my + rx * mx
			local dy = fy * my + ry * mx
			local len = math.sqrt(dx * dx + dy * dy)
			if len > 0.001 then
				-- Se normaliza para que en diagonal no se vaya un 41% mas
				-- rapido, que es el fallo clasico de sumar dos ejes.
				wantX, wantY = dx / len * c.speed, dy / len * c.speed
			end
		end
	end

	-- LA VELOCIDAD SE PERSIGUE, NO SE FIJA, y eso es el easing.
	--
	-- Antes la posicion se movia directamente con la tecla, asi que arrancar y
	-- parar eran escalones -- el "va a trompicones" del informe. Ahora la tecla
	-- pide una velocidad y la de verdad la persigue con el mismo suavizado
	-- exponencial que la altura: `1 - exp(-k*dt)`, independiente del frame rate.
	-- `/rts fc ease` es el mando; mas alto es mas seco.
	local ea = 1 - math.exp(-c.ease * dt)
	st.vx = (st.vx or 0) + (wantX - (st.vx or 0)) * ea
	st.vy = (st.vy or 0) + (wantY - (st.vy or 0)) * ea
	-- Por debajo de un pelo se para del todo: si no, la velocidad tiende a cero
	-- sin llegar nunca y la camara sigue arrastrandose despues de soltar.
	if math.abs(st.vx) < 0.01 then st.vx = 0 end
	if math.abs(st.vy) < 0.01 then st.vy = 0 end

	-- EL CANDADO SE BIFURCA AQUI, y no antes: el giro y el solver del plano son
	-- comunes -- con el candado puesto tambien se gira y tambien se retoca el
	-- encuadre -- y todo lo que viene DESPUES es el suelo, que con el candado no
	-- pinta nada (ver `Follow`). Un `if` en el sitio donde las dos ramas dejan
	-- de parecerse, y no dos copias del tick.
	if self.lock then
		Follow(c, dt)
		ns.Camera:SpecPlace(st.x, st.y, st.z, st.yaw, st.pitch or c.pitch, nil)
		return
	end

	st.x = st.x + st.vx * dt
	st.y = st.y + st.vy * dt

	-- --- el objetivo y el suavizado -----------------------------------
	--
	-- EL SUELO SE MIDE ANTES QUE LA ALTURA, y el orden no es cosmetico: sin
	-- suelo, ESPACIO y C tienen que mover otra cosa (ver abajo), asi que hay que
	-- saber si lo hay antes de leer las teclas.
	local ground = GroundUnderCamera(c)

	-- EL EMPUJE SE CANSA (2026-09-12). "Puedo asomarme un poco en la montana y
	-- me echa fuera al momento" -- y el que echa es este fichero, no la colision
	-- del cliente, que esta apagada.
	--
	-- La causa es el arranque del rayo. El DLL dispara desde `cam.z + 5`, asi
	-- que estando DENTRO de la roca el rayo sale por encima de la camara y
	-- devuelve una superficie que esta ARRIBA. El suelo duro hace lo suyo --
	-- subir a `ground + clear` -- y al frame siguiente el rayo arranca cinco
	-- yardas mas alto todavia, encuentra otra vez roca por encima, y vuelve a
	-- subir. Es una escalera que se construye sola: la camara sale disparada
	-- hasta que se acaba la montana. El limite `push` no la para, solo le pone
	-- velocidad.
	--
	-- Y no hay forma de distinguir "estoy metido en un monte" de "el suavizado
	-- me ha dejado una yarda por debajo del suelo" mirando un solo rayo hacia
	-- abajo: los dos casos son lo mismo, una superficie por encima. Lo que si
	-- los separa es CUANTO HAY QUE SUBIR. Una yarda de suavizado se arregla en
	-- dos frames; una montana no se arregla nunca.
	--
	-- Asi que el empuje tiene presupuesto: `offset + clear`, que es lo que mide
	-- la camara de suelo a cabeza y ni una constante nueva. Mientras el suelo
	-- este por encima se va gastando; en cuanto vuelve a estar debajo -- o sea
	-- al asomar a cielo abierto -- se repone entero. Gastado, el suelo deja de
	-- contar como suelo y la camara MANTIENE la altura, que es lo que se pidio:
	-- "que no siga al suelo y simplemente clipee".
	if ground and st.z and ground > st.z then
		st.buried = (st.buried or 0) + c.push * dt
		if st.buried > (st.offset or 0) + c.clear then ground = nil end
	else
		st.buried = 0
	end

	-- --- altura: ESPACIO y C MUEVEN LA CAMARA ------------------------
	--
	-- TERCER MODELO Y EL BUENO (2026-09-12). Los dos anteriores movian el
	-- OFFSET, y los dos se estrellaron contra lo mismo: un offset es una altura
	-- SOBRE algo, asi que mientras se pulsa una tecla el suelo esta discutiendo
	-- con el jugador. Primero el offset se paraba en `minH` y cualquier
	-- superficie era un techo infranqueable. Luego se le dejo bajar a -7 y se
	-- podia uno incrustar un poco, pero no atravesar: en cuanto el rayo
	-- encontraba otro suelo debajo, el offset se recalculaba en positivo y habia
	-- que volver a bajarlo entero. Cada piso costaba un segundo de tecla.
	--
	-- Mientras la tecla esta pulsada, la camara se mueve EN EL MUNDO y punto. No
	-- hay suelo, no hay filtro, no hay suelo duro: hay una camara bajando a
	-- `lift` yardas por segundo, que es lo que se pidio -- "poder colarme por
	-- donde sea". Atraviesa terreno, tejados, pisos y el tubo de la cueva sin
	-- notar ninguno, porque durante ese rato ninguno significa nada.
	--
	-- AL SOLTAR es cuando vuelve a haber suelo, y se engancha a lo que haya
	-- debajo desde la altura en la que se ha quedado. Eso esta unas lineas mas
	-- abajo y vale ademas para salir del vacio: es la misma pregunta.
	local lift = 0
	if input.up then lift = lift + 1 end
	if input.down then lift = lift - 1 end
	if lift ~= 0 then
		st.z = st.z + lift * c.lift * dt
		st.free = true
		-- Se olvida el suelo filtrado y el presupuesto, no por limpieza: si se
		-- quedara puesto, al soltar la tecla el filtro creeria que el suelo de
		-- hace medio segundo sigue siendo el suyo y daria el escalon entero de
		-- golpe. Y `ground` a nil aqui mismo apaga, en una linea, todo lo que
		-- viene detras y empuja.
		st.gz, st.gstep, st.buried = nil, 0, 0
		ground = nil
	else
		st.free = false
	end

	-- EL ANCLAJE: al aparecer un suelo donde no habia ninguno -- soltando la
	-- tecla, o saliendo del vacio volando de lado -- se toma la altura a la que
	-- la camara YA esta como offset. Asi no hay ni un salto: estaba donde
	-- estaba y sigue estando ahi, solo que ahora se mide contra otra cosa. Es la
	-- idea del jugador ("ese sera el nuevo suelo") escrita una sola vez, y
	-- sustituye al relevo que antes dependia de que el offset fuera negativo.
	--
	-- Y EL VACIO ABISAL, la otra mitad: si lo que aparece debajo esta mas lejos
	-- que `maxH` -- el techo del propio offset, o sea mas de lo que esta camara
	-- llama "volar sobre algo" -- no es un suelo, es el fondo del mundo. No se
	-- engancha y se sigue flotando; engancharse a algo a trescientas yardas
	-- seria caerse.
	if ground and not st.gz then
		local h = st.z - ground
		if h < 0 or h > c.maxH then
			ground = nil
		else
			st.offset = h
		end
	end

	local targetZ
	if ground then
		-- EL ESCALON SE FILTRA EN EL SUELO, NO EN LA CAMARA, y esa es la unica
		-- razon de que esto sepa distinguir un cartel de una cuesta.
		--
		-- El suavizado de abajo trabaja sobre el ERROR de la camara, y un error
		-- no dice de donde viene: seis yardas de error son las mismas subiendo
		-- una loma que cruzando por encima de un poste. Lo que si los separa es
		-- CUANTO CORRE EL SUELO: una cuesta a toda velocidad mueve el suelo unas
		-- 20 yd/s, y el borde de un cartel lo mueve seis yardas EN UN FRAME --
		-- cientos de yd/s. Dos ordenes de magnitud, no un matiz.
		--
		-- Asi que el suelo medido persigue al suelo real con una velocidad
		-- limitada, y el limite BAJA con lo que quede por subir:
		--
		--     v = climb / (1 + (pendiente/soft)^2)
		--
		-- Una cuesta se queda a un par de yardas del suelo real y se sigue de
		-- cerca; un escalon de seis apenas se empieza, y cuando el cartel ya ha
		-- pasado el suelo real vuelve a bajar y la diferencia -- ahora minuscula
		-- -- se cierra deprisa. Quedarse quieto encima del cartel si sube: la
		-- velocidad nunca es cero, solo pequena. Eso es literalmente lo que se
		-- pidio -- "si de verdad quiero subirme, solo tengo que esperar".
		--
		-- `slow` es el suelo de esa velocidad y no es cosmetico: sin el, un
		-- acantilado de 60 yardas se subiria a 0.1 yd/s, o sea nunca.
		local gz, pend = st.gz, st.gstep or 0
		local d = gz and (ground - gz) or nil
		if not d or d > GROUND_SNAP or d < -GROUND_SNAP then
			gz, pend = ground, 0
		else
			local ad = (d >= 0) and d or -d
			-- EL FRENO LO DECIDE EL TAMANO DEL ESCALON, NO LO QUE QUEDE DE EL.
			--
			-- Aqui iba `ad` directamente y el simulador lo tumbo en la primera
			-- corrida: con la velocidad atada a lo que FALTA, cada subida se
			-- acelera segun se acerca -- las ultimas dos yardas de un escalon de
			-- quince se hacian a 25 yd/s, casi el doble de lo que sube el
			-- jugador a mano con ESPACIO. O sea el latigazo que veniamos a
			-- quitar, movido al final del recorrido, donde ademas se ve peor
			-- porque llega despues de un tramo lento.
			--
			-- "Esto es un escalon" es una propiedad del SUCESO, no de la
			-- distancia que queda ahora, asi que se recuerda: `pend` es el mayor
			-- desnivel visto desde la ultima vez que el filtro se puso al dia, y
			-- se borra justo al ponerse al dia. Una cuesta no lo levanta -- el
			-- suelo se mueve unas yardas por SEGUNDO y el filtro va sobrado, asi
			-- que el retraso se queda en la fraccion de yarda de un frame.
			if ad > pend then pend = ad end
			local q = pend / c.soft
			local v = c.climb / (1 + q * q)
			if v < c.slow then v = c.slow end
			local step = v * dt
			if ad <= step then
				gz, pend = ground, 0
			elseif d > 0 then
				gz = gz + step
			else
				gz = gz - step
			end
			-- TOPE DE RETRASO HACIA ARRIBA, y no es un ajuste nuevo: SALE DEL
			-- OFFSET. Si el suelo de verdad no debe acercarse a la camara mas de
			-- `clear`, y la camara vuela a `offset` sobre el suelo filtrado,
			-- entonces el filtrado no puede quedarse mas de `offset - clear` por
			-- debajo del real. Ni una constante que inventar ni un mando que
			-- explicar.
			--
			-- Es ademas lo que impide el unico caso feo que quedaba: un escalon
			-- seguido de una cuesta larga deja el freno puesto -- `pend` sigue
			-- alto -- y sin tope la camara se hundiria en la loma hasta que el
			-- suelo duro la rescatara de un tiron. Con el tope no llega a pasar:
			-- el limite se alcanza poco a poco y a partir de ahi el filtro sigue
			-- al suelo a su misma velocidad.
			--
			-- SOLO HACIA ARRIBA. Hacia abajo el retraso no es peligroso, es la
			-- vista: cuando el suelo se acaba, la camara baja despacio y el
			-- terreno se abre debajo. Capar ese lado seria obligarla a caer.
			--
			-- Y EL TOPE SE ALCANZA A UNA VELOCIDAD, NO DE UN SALTO (2026-09-12).
			--
			-- Aqui ponia `gz = ground - cap` a secas, y eso convertia el tope --
			-- que se escribio para que el suelo duro NO tuviera que rescatar a
			-- la camara -- en el atajo que se salta el limitador entero. Con el
			-- offset por defecto (30) el tope son 28 yardas, asi que cualquier
			-- escalon de mas de 28 pasaba de golpe; con el offset bajado a 6.4,
			-- medido en juego el 2026-09-12, son CUATRO YARDAS Y MEDIA, o sea
			-- que el filtro de escalon no filtraba absolutamente nada.
			--
			-- `climb`, `soft` y `slow` quedaban de adorno justo en el caso que
			-- los justifica. Es el modo de fallo de siempre: dos caminos para lo
			-- mismo y el malo manda.
			if d > 0 then
				local cap = st.offset - c.clear
				if cap < 1 then cap = 1 end
				local want = ground - cap
				if want > gz then
					local lim = c.push * dt
					gz = (want - gz > lim) and (gz + lim) or want
				end
			end
		end
		st.gz, st.gstep = gz, pend
		targetZ = gz + st.offset
	else
		-- SIN SUELO NO SE INVENTA UNO. El rayo puede no contestar dentro de una
		-- cueva o sobre agua profunda; mantener la Z es lo unico que no pega un
		-- salto. Lo que NO se hace es caer al terreno bajo el jugador, que fue
		-- la tentacion obvia: en una camara RTS ese punto puede estar a
		-- cientos de yardas y en otra altura.
		targetZ = st.z
		-- Y el suelo filtrado se olvida: cuando el rayo vuelva a contestar sera
		-- en otro sitio, y arrastrar el de antes lo haria parecer un escalon
		-- gigante justo en el frame de la reaparicion.
		--
		-- EL PRESUPUESTO DE EMPUJE NO SE REPONE AQUI, y esa linea de mas habria
		-- deshecho el arreglo entero sin cambiarlo de sitio: cuando el empuje se
		-- agota, `ground` se pone a nil y la ejecucion cae JUSTO EN ESTA RAMA.
		-- Reponerlo aqui seria rellenar el deposito en el mismo frame en que se
		-- vacia -- la escalera otra vez, un peldano por frame. Se repone solo
		-- donde toca: con suelo debajo, o al entrar y salir del modo.
		st.gz, st.gstep = nil, 0
	end

	-- Suavizado exponencial independiente del frame rate. `1 - exp(-k*dt)` y no
	-- una fraccion fija por frame: con una fraccion fija, a 144 fps la camara
	-- llega tres veces mas rapido que a 45, o sea que el tacto cambiaria con el
	-- rendimiento. Es la formula del §6 del brief.
	--
	-- Sigue estando DESPUES del filtro de suelo y no en su lugar: el limitador
	-- de velocidad deja esquinas -- el frame en que deja de correr al tope se ve
	-- como un tiron -- y esto las redondea. Cada uno hace una cosa: el de arriba
	-- decide CUANTO se sube, este decide como se entra y se sale.
	local alpha = 1 - math.exp(-c.smoothZ * dt)
	st.z = st.z + (targetZ - st.z) * alpha

	-- SUELO DURO, aparte del suavizado. El suavizado es estetica; esto impide
	-- que la camara se meta dentro del terreno mientras persigue una subida
	-- brusca -- que es el caso que el brief describe en su §8 y el unico en el
	-- que el suavizado, por definicion, va por detras.
	--
	-- Y SE MIDE CONTRA EL SUELO DE VERDAD, no contra el filtrado: lo que no
	-- puede pasar es que la camara se meta dentro de una loma REAL.
	--
	-- Que esto no sea el tiron de siempre otra vez lo garantiza el tope de
	-- retraso de arriba, no la suerte: con el tope puesto, el suelo real nunca
	-- puede acercarse a la camara mas de `clear`, asi que este `if` no llega a
	-- dispararse mientras el filtro manda. Sin el tope los dos se pelearian cada
	-- frame -- uno frenando y el otro empujando -- que es la forma exacta de
	-- discusion que este proyecto ya ha perdido dos veces.
	--
	-- Y EMPUJA A UNA VELOCIDAD (2026-09-12). El parrafo de arriba daba por hecho
	-- que este `if` no llega a dispararse mientras el filtro manda, y era falso:
	-- el tope de retraso lo llamaba en cuanto el escalon pasaba de `offset -
	-- clear`, y entonces esta linea movia la camara OCHENTA YARDAS EN UN FRAME.
	-- Enumerados todos los escritores de `st.z`, era el unico teletransporte del
	-- fichero -- lo demas va limitado o suavizado -- asi que es el "plop".
	--
	-- Sigue siendo duro: no negocia con el suavizado, gana siempre. Lo unico que
	-- cambia es que tarda lo que tiene que tardar, y eso convierte un salto que
	-- no se puede ver en una subida que se ve venir y de la que se puede salir
	-- marcha atras.
	--
	-- Y NUNCA POR ENCIMA DE LO QUE SE HA PEDIDO (2026-09-12). `clear` a secas
	-- era el suelo duro discutiendo con el buceo: el jugador baja el offset a
	-- -7 para colarse por un tejado y esta linea lo devuelve a +2 del tejado,
	-- cada frame, para siempre. Un margen de seguridad que anula la orden que
	-- viene de las teclas no es un margen, es un veto. Con el `min`, mientras el
	-- offset sea mayor que `clear` esto se comporta exactamente igual que antes,
	-- y en cuanto se pide bajar mas, deja de empujar.
	if ground and st.offset then
		local want = ground + math.min(c.clear, st.offset)
		if st.z < want then
			local lim = c.push * dt
			st.z = (want - st.z > lim) and (st.z + lim) or want
		end
	end

	-- SALIR DE DEBAJO DEL SUELO, que es lo unico para lo que existe el rayo del
	-- techo. Sin suelo debajo y con TERRENO justo encima, la camara se ha colado
	-- por debajo del mundo -- normalmente porque el suavizado fue por detras de
	-- una bajada brusca -- y ahi no hay nada que seguir, solo de donde salir.
	--
	-- Dos frenos, y los dos hacen falta. No se hace si se esta buceando a
	-- proposito (`offset` negativo), o seria el veto de siempre con otro nombre.
	-- Y gasta el MISMO presupuesto que el resto del empuje, asi que en el peor
	-- caso -- que el techo sea de verdad el interior de una montana -- sube unas
	-- yardas y se rinde, en vez de convertirse otra vez en un eyector.
	if not ground and not st.free and st.offset and st.offset >= 0 then
		local ceil = CeilAbove()
		if ceil then
			st.buried = (st.buried or 0) + c.push * dt
			if st.buried <= st.offset + c.clear then
				local lim = c.push * dt
				local want = ceil + c.clear
				st.z = (want - st.z > lim) and (st.z + lim) or want
			end
		end
	end

	ns.Camera:SpecPlace(st.x, st.y, st.z, st.yaw, st.pitch or c.pitch, nil)
end

--- Arranque y parada -------------------------------------------------------

function F:Start()
	if self.active then return true end

	-- Las dos cosas que solo da el DLL: el avance y el suelo bajo la camara.
	if RTS_Ready ~= 1 then
		ns.Print("|cffff0000camara RTS:|r hace falta rts_core inyectado.")
		ns.Print("  Abre el juego con |cffffff002-Jugar.bat|r.")
		return false
	end

	local px, py, pz
	if RTS_HasPos == 1 then
		px, py, pz = RTS_PX, RTS_PY, RTS_PZ
	end
	if not px then
		ns.Print("|cffff0000camara RTS:|r el DLL no publica tu posicion todavia.")
		return false
	end

	if not GrabKeys() then return false end

	-- UN SOLO DUEÑO DEL MOVIMIENTO. Con el modo libre armado el cliente tambien
	-- conduce la camara con WASD, y aunque nuestros bindings se quedan las
	-- teclas antes de que el las vea, dejarle la velocidad puesta es dejar un
	-- segundo motor encendido esperando a que una tecla se escape. Su unidad
	-- ademas no son yardas/segundo: 20 manda la camara a otro continente.
	Try("CommentatorSetMoveSpeed", 0)

	-- QUE SE VEA MI HEROE, Y SIN ESPERAR A NADIE.
	--
	-- AQUI PEDIA `Channel:SetShowSelf(true)`, el apaño para el heroe invisible
	-- por el canal de publicacion. Se ha ido el 2026-09-10 por dos razones, y
	-- la segunda sola ya bastaba:
	--
	--   * El problema esta resuelto de verdad: `SelfShow.cpp` parchea los cinco
	--     bytes de `0x006E085C` y **se arma solo** con los flags puestos, que es
	--     justo lo que hace `Spectate`. No hay nada que pedir.
	--   * El bit 30 NUNCA tuvo lector. Ningun DLL lo decodifica -- el layout del
	--     protocolo 3 lo lista como libre -- asi que esta llamada no hacia nada
	--     y lo parecia todo.

	local c = Cfg()
	st.offset = c.height
	st.x, st.y = px, py
	st.z = pz + c.height
	-- El suelo filtrado de la ULTIMA vez que se entro no vale: puede ser de
	-- otro continente. A nil, que es lo que hace que el primer tick lo siembre
	-- con la medida de aqui en vez de venir subiendo desde donde estuvieramos.
	st.gz, st.gstep, st.buried = nil, 0, 0
	-- El yaw arranca en 0 y NO se deriva del que tenga la camara: la convencion
	-- de angulos de `CommentatorSetCamera` no se puede leer del binario, asi que
	-- sembrarlo seria adivinar. El precio es un giro brusco al entrar; el
	-- beneficio es que a partir de ahi todo es consistente, y el avance no
	-- depende del yaw para nada (sale del vector que publica el DLL).
	st.yaw = 0
	st.pitch = c.pitch
	-- EL CANDADO NO SOBREVIVE A UNA SALIDA. Entrar al modo recoloca la camara
	-- sobre el heroe, asi que un candado heredado traeria el encuadre de la
	-- sesion anterior -- de otro continente, o de antes de un cambio de
	-- personaje -- y lo aplicaria encima. Se entra siempre suelto.
	self.lock = false
	self.eyes = false
	st.ax, st.ay, st.az = nil, nil, nil
	st.ox, st.oy, st.oz = 0, 0, 0

	-- QUE NO CHOQUE CON NADA QUE NO SEA NUESTRO SUELO.
	--
	-- Va AQUI y no antes por una razon que no se ve: el manejador del cliente
	-- exige los dos flags de jugador y, si faltan, retorna sin escribir y sin
	-- error. A estas alturas la puerta ya esta abierta -- `WaitGate` ha dejado
	-- pasar -- asi que los flags estan puestos. Llamarlo en `CameraOn`, antes de
	-- `Spectate`, habria sido una llamada que parece funcionar y no hace nada.
	--
	-- Una vez basta: quien lo enciende es el init del objeto de comentarista, y
	-- ese corre UNA VEZ en el arranque del cliente. Nadie lo reescribe por
	-- detras, asi que no hay que refrescarlo cada tick -- que es la forma de
	-- pelea que este proyecto ya ha perdido dos veces.
	if c.noclip == 1 then ns.Camera:SetCollision(false) end

	self.active = true
	ns.Camera:SpecPlace(st.x, st.y, st.z, st.yaw, st.pitch, nil)
	return true
end

function F:Stop()
	if not self.active then return true end
	self.active = false
	self.lock = false
	self.eyes = false
	-- CAPTURAR Y DEVOLVER, con la unica pega de que aqui no hay de donde
	-- capturar: el cliente no publica un getter de esto. Asi que se devuelve al
	-- valor MEDIDO, no supuesto -- `0x0056BC80` escribe 1 en ese campo al
	-- arrancar el juego, o sea que 1 es como estaba antes de que lo tocaramos.
	--
	-- Y va antes de que nadie quite los flags: `R:CameraOff` llama a esto y solo
	-- despues a `Spectate(false)`. Al reves, esta linea no escribiria nada y la
	-- colision se quedaria apagada para el resto de la sesion.
	ns.Camera:SetCollision(true)
	-- Las teclas pueden no volver en combate; se avisa al llamante para que
	-- pueda reintentarlo al salir de la pelea, igual que hace `Chrome`.
	return ReleaseKeys()
end

-- Para el reintento tras combate.
function F:KeysPending()
	return savedBindings ~= nil
end

function F:ReleaseKeysNow()
	return ReleaseKeys()
end

--- La salida de emergencia ------------------------------------------------
--
-- `/rts fc home` devuelve la camara sobre el heroe.
--
-- Existe porque el fallo de las cuevas tenia DOS mitades y solo una es la
-- aritmetica: la otra es que una vez la camara acaba en un sitio malo **no hay
-- ninguna tecla que la saque**. C solo bajaba el `offset` (suelo `minH`), y el
-- suelo duro gana; W/A/S/D mueven a ciegas dentro de la roca, donde no hay
-- ninguna referencia para saber hacia donde esta la salida. Literalmente sin
-- vuelta: *"me lleva a un sitio del que no puedo volver"*.
--
-- Va aparte del arreglo del salto a proposito. El arreglo puede estar
-- incompleto -- quedan causas por enumerar -- y esto vale igual sea cual sea la
-- causa, porque no diagnostica nada: solo deshace. Lo mismo que el macro
-- "Reset IA" para las estrategias de los bots.
--
-- Se recolocan las MISMAS cosas que `Start`, ni una mas ni una menos, y ahi
-- entran las dos que se olvidan solas: el suelo filtrado (`gz`) hay que
-- borrarlo o el primer frame en el destino ve un escalon gigante, y la
-- velocidad del plano (`vx`,`vy`) o la camara sale disparada al llegar.
function F:Home()
	if not self.active then
		ns.Print("|cffff8800camara RTS:|r la camara libre no esta activa.")
		return false
	end
	if RTS_HasPos ~= 1 or not RTS_PX then
		ns.Print("|cffff0000camara RTS:|r el DLL no publica tu posicion.")
		return false
	end
	local c = Cfg()
	-- LA SALIDA DE EMERGENCIA SACA TAMBIEN DE LA CABEZA, y tiene que hacerlo
	-- antes de nada: en primera persona el encuadre se reescribe entero cada
	-- frame, asi que dejar `eyes` puesto convertiria este rescate en un no-op
	-- -- la camara volveria a la cabeza en el tick siguiente. El candado se
	-- queda (ver abajo): lo que estorba es el encuadre clavado, no el ancla.
	if self.eyes then
		self.eyes = false
		ns.Print("|cff33ccffcamara RTS:|r fuera de primera persona.")
	end
	st.x, st.y = RTS_PX, RTS_PY
	st.offset = c.height
	st.z = RTS_PZ + c.height
	st.gz, st.gstep, st.buried = nil, 0, 0
	st.vx, st.vy = 0, 0
	-- Y CON EL CANDADO PUESTO HAY QUE REHACER EL ENCUADRE, o esto no haria
	-- nada: con el candado, la posicion de la camara se recalcula entera cada
	-- frame desde el ancla, asi que las tres lineas de arriba se perderian en
	-- el tick siguiente. La salida de emergencia dejaria de salvar justo en el
	-- modo en el que uno se puede quedar colgado de un heroe que se ha ido.
	if self.lock then
		st.ax, st.ay, st.az = RTS_PX, RTS_PY, RTS_PZ
		st.ox, st.oy, st.oz = 0, 0, c.height
	end
	ns.Print(("|cff33ccffcamara RTS:|r camara devuelta sobre tu heroe (%.0f %.0f %.0f)."):format(
		st.x, st.y, st.z))
	return true
end

--- Ajustes por comando -----------------------------------------------------

local LABEL = {
	speed = "velocidad en el plano (yd/s)",
	lift = "velocidad de subida (yd/s)",
	turn = "giro (grados/s)",
	height = "altura sobre el suelo (yd)",
	minH = "altura minima de `height` (yd); el vuelo ya no tiene suelo",
	maxH = "altura maxima (yd)",
	smoothZ = "suavizado de altura (k)",
	floor = "que cuenta como suelo: 1 = solo terreno, 0 = lo primero que haya",
	noclip = "1 = la camara atraviesa todo; 0 = colision del cliente",
	climb = "velocidad de seguimiento del suelo con poca diferencia (yd/s)",
	soft = "el codo: a partir de estas yardas de escalon, se frena (yd)",
	slow = "velocidad minima de seguimiento del suelo (yd/s)",
	pitch = "inclinacion de entrada (grados, POSITIVO mira abajo)",
	clear = "margen duro sobre el suelo (yd)",
	push = "lo mas deprisa que el suelo duro puede empujar la camara (yd/s)",
	yawSign = "signo del giro con Q/E (1 o -1)",
	ease = "suavizado del arranque/parada en el plano (k)",
	lockSmooth = "con que fuerza el candado persigue al heroe (k)",
	eyeH = "altura sobre los PIES del heroe con la camara enganchada (yd); ESPACIO y C la mueven",
}

function F:Set(key, value)
	local c = Cfg()
	if key == nil or LABEL[key] == nil then
		ns.Print("|cff33ccffcamara RTS:|r ajustes")
		for k in pairs(LABEL) do
			ns.Print(("  |cffffff00%s|r = %s   |cff888888%s|r"):format(
				k, tostring(c[k]), LABEL[k]))
		end
		ns.Print("  |cffffff00/rts fc <ajuste> <valor>|r")
		return
	end
	local n = tonumber(value)
	if not n then
		ns.Print(("|cffff0000camara RTS:|r %s quiere un numero."):format(key))
		return
	end
	c[key] = n
	Cfg()   -- reacota y descarta lo imposible
	-- SOLO EL TECHO. `minH` dejo de ser un suelo del vuelo cuando las teclas
	-- pasaron a mover la camara: la altura viva puede estar por debajo a
	-- proposito -- dentro de una cueva, bajo un piso -- y subirla aqui seria
	-- echar al jugador de donde acaba de colarse por tocar un ajuste que no
	-- tiene nada que ver.
	if st.offset and (key == "height" or key == "minH" or key == "maxH") then
		st.offset = math.min(c.maxH, st.offset)
	end
	-- El pitch es estado vivo, asi que tocarlo tiene que verse AHORA. Sin esto
	-- `/rts fc pitch 60` no haria nada hasta la siguiente entrada al modo, que
	-- se lee como que el ajuste no funciona.
	if key == "pitch" then st.pitch = Cfg().pitch end
	-- Igual que el pitch: es estado vivo. Sin esto `/rts fc noclip 0` no haria
	-- nada hasta la siguiente entrada al modo, que se lee como que el ajuste no
	-- funciona -- y aqui ademas el sintoma tardaria en verse, porque hay que ir
	-- a buscar una pared.
	if key == "noclip" and self.active then
		ns.Camera:SetCollision(Cfg().noclip == 0)
	end
	ns.Print(("|cff33ccffcamara RTS:|r %s = %s"):format(key, tostring(Cfg()[key])))
end

function F:Report()
	local c = Cfg()
	ns.Print("|cff33ccffcamara RTS:|r " .. (self.active and "|cff00ff00ON|r" or "OFF"))
	if st.x then
		ns.Print(("  pos %.1f %.1f %.1f   yaw %.0f   pitch %.0f   offset %.1f"):format(
			st.x, st.y, st.z, st.yaw, st.pitch or 0, st.offset or 0))
	end
	-- EL CANDADO, CON LA DISTANCIA MEDIDA Y NO LA PEDIDA. "No me sigue" y "me
	-- sigue mal" son dos averias distintas: la primera se ve en el ON/OFF, la
	-- segunda en que la distancia de ahora no sea la que se capturo.
	if self.eyes then
		local hx = HeroPos()
		ns.Print(("  |cff00ff00VISTA DEL HEROE|r: %.1f yd sobre sus pies (ESPACIO/C)%s"):format(
			c.eyeH, hx and "" or "   |cffff8800sin heroe publicado|r"))
	elseif self.lock then
		local hx, hy, hz = HeroPos()
		local d = hx and math.sqrt((st.x - hx) ^ 2 + (st.y - hy) ^ 2 + (st.z - hz) ^ 2)
		ns.Print(("  candado |cff00ff00PUESTO|r: encuadre %.1f %.1f %.1f (%.1f yd)   ahora %s"):format(
			st.ox, st.oy, st.oz,
			math.sqrt(st.ox * st.ox + st.oy * st.oy + st.oz * st.oz),
			d and ("%.1f yd"):format(d) or "|cffff8800sin heroe publicado|r"))
	else
		ns.Print("  candado suelto |cff888888(izquierdo en la casilla Candado; derecho, primera persona)|r")
	end
	-- LA MEDIDA DEL YAW, SIEMPRE, y no solo en primera persona: es lo unico de
	-- este fichero que depende de una convencion que no se puede leer del
	-- binario, asi que "se entra mirando al reves" se contesta aqui en vez de
	-- costar una ronda de pruebas. Con el signo medido, no hay nada supuesto.
	ns.Print("  yaw -> mundo: " .. LookReport())
	-- LOS DOS RAYOS, SIEMPRE LOS DOS, y no solo el que este en uso.
	--
	-- La pregunta que se hace delante de una casa es "¿por que sube la camara?",
	-- y se contesta sola en cuanto se ven los dos numeros juntos: si `solido`
	-- esta quince yardas por encima de `terreno`, eso de debajo es un tejado.
	-- Con un solo numero hay que adivinar cual de los dos se esta mirando.
	-- Y PASADOS POR LA MISMA CRIBA QUE USA EL CONTROLADOR, o el informe diria
	-- que hay suelo justo donde la camara ha decidido que no lo hay. Un rayo
	-- descartado se ensena con su valor entre parentesis: "no contesta" y
	-- "contesta una mentira" son dos averias distintas y se arreglan en sitios
	-- distintos.
	local land,  landBad  = RayHit(RTS_CamLandHit,  RTS_CamLandZ)
	local solid, solidBad = RayHit(RTS_CamGroundHit, RTS_CamGroundZ)
	-- Una sola llamada para todo el informe: `GroundUnderCamera` avisa por chat
	-- cuando descarta un techo, y llamarla dos veces por un `/rts fc` seria el
	-- instrumento generando la lectura que va a imprimir.
	local g, src = GroundUnderCamera(c)
	ns.Print(("  suelo: terreno %s   solido %s   |cffffff00en uso: %s|r"):format(
		land and ("%.1f"):format(land)
			or (landBad and ("|cffff0000descartado (%s)|r"):format(landBad) or "|cffff8800--|r"),
		solid and ("%.1f"):format(solid)
			or (solidBad and ("|cffff0000descartado (%s)|r"):format(solidBad) or "|cffff8800--|r"),
		src or (c.floor == 1 and "terreno" or "solido")))
	if land == nil and RTS_CamLandHit == nil then
		-- Un DLL viejo no publica la variable EN ABSOLUTO, y eso no se parece en
		-- nada a "el rayo no ha chocado". Sin esta linea, `floor 1` se comporta
		-- exactamente como `floor 0` y parece que el ajuste no hace nada.
		ns.Print("  |cffff8800Este rts_core no publica el terreno|r: hace falta " ..
			"0.25.0 o mas nuevo (recompila e inyecta de nuevo).")
	end
	-- Y LA OTRA MITAD DE "NO PUEDO ENTRAR". Son dos causas distintas con el
	-- mismo sintoma -- el suelo la sube al tejado, la colision la empuja fuera
	-- de la pared -- y arreglada una sola, la pantalla se ve igual.
	ns.Print(("  colision del cliente: %s"):format(
		c.noclip == 1 and "|cff00ff00APAGADA|r (atraviesa todo)"
		              or "|cffff8800encendida|r (choca con paredes y tejados)"))
	if g then
		ns.Print(("  suelo en uso %.1f (%s)   filtrado %s   separacion %.1f yd"):format(
			g, src,
			st.gz and ("%.1f"):format(st.gz) or "--",
			(st.z or g) - (st.gz or g)))
	else
		ns.Print("  |cffff8800sin suelo|r: el rayo no contesta aqui (¿cueva, agua?).")
	end
	local ceil = CeilAbove()
	if ceil then
		ns.Print(("  |cffff8800techo|r a %.1f (%.1f yd por encima)"):format(ceil, ceil - (st.z or ceil)))
	elseif RTS_CamCeilHit == nil then
		ns.Print("  |cff888888sin rayo de techo|r: rts_core anterior a 0.29.0 (la franja ciega de 5 yd sigue ahi).")
	end
	if (st.buried or 0) > 0 then
		ns.Print(("  |cffff8800empuje gastado|r %.1f de %.1f yd (suelo por encima: se deja de seguir al agotarse)")
			:format(st.buried, (st.offset or 0) + c.clear))
	end
	local fx, fy = FlatForward()
	if fx then
		ns.Print(("  adelante plano %.2f %.2f"):format(fx, fy))
	else
		ns.Print("  |cffff8800sin adelante|r: ¿mirando a plomo, o sin camara publicada?")
	end

	-- EL BIT DEL MODELO, PARTIDO EN DOS MITADES.
	--
	-- "No se ve mi heroe" puede fallar en el addon (el bit no se manda) o en el
	-- DLL (llega y el bit de dibujo no es ese). Son dos arreglos distintos en
	-- dos lenguajes distintos, y distinguirlos mirando la pantalla cuesta una
	-- ronda. Esto lo contesta en un comando: si el bit sale puesto y el modelo
	-- sigue invisible, el problema esta aguas abajo.
	local v = ns.Channel.last
	if v then
		local bit30 = (math.floor(v / 2 ^ 30) % 2) == 1
		ns.Print(("  canal = %d, bit30 (verme) = %s"):format(
			v, bit30 and "|cff00ff00SI|r" or "|cffff0000NO|r"))
		if not bit30 then
			ns.Print("  |cffff8800El addon no lo esta pidiendo|r: el fallo es de este lado.")
		else
			ns.Print("  |cff888888Se esta pidiendo. Si no te ves, es el DLL: o el bit")
			ns.Print("  0x800 de +0x7C no es el dibujo, o +0xB8 no es ese objeto.|r")
		end
	else
		ns.Print("  |cffff8800canal sin escribir todavia|r (¿RTS_UGEN, protocolo?).")
	end

end

--- EL INSTRUMENTO DE LA CAMARA ---------------------------------------------
--
-- Existe porque el giro costo CINCO intentos y cada causa estaba en un eslabon
-- distinto, ninguno visible desde la pantalla. Ahora mide las dos cosas que
-- importan del reparto nuevo: que el cliente GIRE (nosotros solo leemos) y que
-- nuestra escritura de posicion no le este pisando el giro.
function F:Mouse()
	ns.Print("|cff33ccffcamara:|r gira con el DERECHO durante 2 segundos...")
	local t, dyaw, dpitch, n = 0, 0, 0, 0
	local y0, p0 = nil, nil
	local sawL, sawR = false, false
	local f = CreateFrame("Frame")
	f:SetScript("OnUpdate", function(self2, e)
		t = t + e
		local ok, _, _, _, yaw, pitch = Try("CommentatorGetCamera")
		if ok and type(yaw) == "number" then
			n = n + 1
			if y0 then
				local d = yaw - y0
				if d > 180 then d = d - 360 elseif d < -180 then d = d + 360 end
				dyaw = dyaw + math.abs(d)
				dpitch = dpitch + math.abs(pitch - p0)
			end
			y0, p0 = yaw, pitch
		end
		local l, r = MouseButtons()
		if l then sawL = true end
		if r then sawR = true end
		if t < 2.0 then return end
		self2:SetScript("OnUpdate", nil)
		ns.Print(("  lecturas de angulo: %d   giro acumulado: yaw %.1f, pitch %.1f"):format(
			n, dyaw, dpitch))
		ns.Print(("  botones (del DLL): derecho %s   izquierdo %s"):format(
			sawR and "|cff00ff00SI|r" or "|cffff0000NO|r", sawL and "SI" or "no"))
		if n == 0 then
			ns.Print("  |cffff0000CommentatorGetCamera no contesta|r: la puerta esta")
			ns.Print("  cerrada. |cffffff00/rts cam probe|r dice en que paso.")
		elseif dyaw < 1 and dpitch < 1 then
			ns.Print("  |cffff8800El cliente no gira esta camara|r, o la estamos")
			ns.Print("  pisando. Mira si `ease` o el escritor de posicion tocan")
			ns.Print("  los angulos en vez de reescribir los leidos.")
		else
			ns.Print("  |cff00ff00El giro nativo llega|r. La sensibilidad es la de")
			ns.Print("  tus ajustes de raton de WoW, no la del addon.")
		end
	end)
end

---- El latido ---------------------------------------------------------------

function F:Create()
	local f = CreateFrame("Frame")
	-- Cada frame, y tiene que ser cada frame: el suavizado y la correccion de
	-- altura son por dt y un temporizador mas lento se ve como escalones.
	-- LAS TECLAS TIENEN QUE VOLVER AUNQUE LA SALIDA FUERA EN COMBATE.
	--
	-- `SetBinding` esta bloqueado en combate, asi que un `Stop()` a mitad de
	-- pelea deja WASD apuntando a nuestros botones -- y entonces el jugador
	-- **no puede moverse** en juego normal hasta el siguiente toggle. Es mucho
	-- peor que el caso que lo provoca, y no da ningun error.
	--
	-- Es la misma guarda que `Camera.lua` tiene para Q/E desde que existe, y la
	-- misma costura que `Chrome` usa para los frames protegidos: lo que no se
	-- puede hacer ahora se aplaza al momento en que se puede.
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:RegisterEvent("PLAYER_LEAVING_WORLD")
	f:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LEAVING_WORLD" then
			F.active = false
			return
		end
		if not F.active and F:KeysPending() then
			if F:ReleaseKeysNow() then
				ns.Print("|cff33ccffcamara:|r teclas devueltas al salir del combate.")
			end
		end
	end)

	f:SetScript("OnUpdate", function(_, e)
		if F.active then
			local ok, err = pcall(F.Step, F, e)
			if not ok then
				-- Un error aqui correria en CADA frame y llenaria la pantalla,
				-- asi que el controlador se apaga solo y lo dice una vez.
				F.active = false
				ns.Print("|cffff0000camara RTS:|r " .. tostring(err))
				ns.Print("  controlador detenido para no repetir el error.")
			end
		end
	end)
	self.events = f
end
