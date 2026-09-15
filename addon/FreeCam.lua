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

	RIGHT-clicking the lock slot puts the camera BEHIND the hero -- four yards
	up, six yards back -- looking the way he looks, and attaches it: it stays at
	his back while he walks, fights, or his AI drives him. If he turns, the
	camera comes round with him and you go on seeing his back.

	    W / S           closer and further away, never past him
	    A / D           pivot around him, with him at the centre
	    SPACE, C        raise and lower the height over his feet
	    right drag      sideways pivots around him; up and down tilts the view

	THE PIVOT IS MEASURED FROM HIS NOSE, NOT FROM THE WORLD, and that single
	decision is the whole mode. The camera does not sit at a compass bearing the
	hero happens to be standing in front of: it sits at `facing + orbit`, and
	`orbit` is the only thing A/D write. So zero is his back and STAYS his back
	through every turn he takes -- and if you pivot round to his flank, you keep
	the flank, turn after turn, instead of the camera drifting back behind him.

	AND THE MOUSE IS SPLIT IN TWO HERE, which is the only trick in the mode.
	Everywhere else in this file the CLIENT owns the orientation and we only carry
	the position (see `AdoptLook`): both live angles are adopted and written
	straight back. Here the YAW cannot be adopted -- it is a consequence of where
	the hero looks -- so adopting it would be letting the mouse fight the follow
	over the same number, and the mouse would win on every frame the hero was not
	turning.

	So of the yaw we take not the angle but the DIFFERENCE between what we wrote
	last frame and what is there now (`DragRead`): whatever the client has added
	on top is the drag, and it is spent on the ORBIT -- the camera goes round him
	instead of looking away from him. THE TILT IS ADOPTED WHOLE, exactly as
	everywhere else: dragging up looks up, and it is the client that decides how
	much, with the player own sensitivity and inversion already in it.

	AND THE TILT IS NOT DERIVED FROM THE HEIGHT, which it was for one round and
	is the reason this paragraph exists. Aiming at his chest every frame meant
	SPACE could not raise the camera without tilting it down -- one gesture doing
	two things, and the second one not asked for. Now the height is a translation
	and the tilt is a rotation, each with its own hand on it; the chest aim
	survives as the ENTRY value only.

	THE FACING ARRIVES AT 33 Hz AND IS CHASED, LIKE THE POSITION. A turn in this
	client is instantaneous -- a bot changing his mind is 180 degrees in one tick
	-- so copying the angle raw is a whip-pan. `eyeTurn` is the k of that chase
	and it is a SEPARATE dial from `lockSmooth`: the position can be chased hard
	because its lag is a constant offset nobody sees, and the angle cannot.

	AND A SPIN IS ABSORBED, NOT FOLLOWED. Clicking the ground behind you spins the
	hero a hundred and eighty degrees in ONE tick, and a camera glued to his
	facing replays that spin as a whip-pan. What was asked for is to WATCH HIM
	TURN -- the camera still, him turning in front of it -- and then, once he is
	walking, to drift back behind him VERY slowly.

	AND THE WAY IT IS DONE IS THE ONE THING WORTH READING HERE: the jump is MOVED
	FROM `hf` TO `orbit`. Both together are the camera (`hf + orbit`), so adding
	to one what is taken from the other does not move it by a single degree, and
	what is left is the same picture described another way -- the facing GLUED
	again from the very next frame, which is what an advance needs, and the whole
	discrepancy parked in the one number the slow return knows how to undo.

	FREEZING THE FACING FOR A MOMENT WAS THE FIRST ATTEMPT AND IT CAME OUT WRONG,
	for a reason worth keeping: when the freeze ended, the chase brought `hf` up
	to date but `orbit` was still whatever the player had pivoted to before
	clicking, so the camera turned the whole spin AGAIN on top of it and ended up
	looking at his flank -- "un giro que la lia". Absorbing costs the same line
	and cannot do that, because the sum is what it preserves.

	A SPIN IS TOLD APART FROM AN ADVANCE BY HOW MUCH THE FACING MOVES BETWEEN TWO
	READINGS, and it is measured there and not on the chase error because the
	error stays large for a whole second AFTER a spin -- that is what chasing
	means -- so it cannot tell the start of one from the middle of one. Between
	two readings, running a curve at full speed is some three degrees and a spin
	is a hundred and eighty.

	AND THE RETURN WAITS FOR HIM TO WALK, at the player request: the point of the
	pause is to see him set off in the new direction, so what starts the drift is
	his position changing and not a stopwatch. Four spins in a row cost four
	absorptions -- the camera does not move through any of them -- and then ONE
	slow return, which is the "do not replay the four turns" of a few rounds ago
	arriving by another door.

	IT IS NOT A FIFTH MODE. It is the lock, which instead of capturing whatever
	framing is on screen recomputes it every frame from the hero facing, so it
	inherits the whole smoothed hero follow -- which matters more here than
	anywhere: the DLL publishes the position at 33 Hz and the screen runs at 60,
	so copying it raw is 0.2 yards of jerk thirty-three times a second right
	behind the hero. What does not show from a bird eye view makes you seasick
	here.

	AND THERE IS NO GROUND UNDER IT, same as the lock: Z is the hero Z plus
	`eyeH` and no ray runs. Over flat country that is right; going DOWNHILL the
	ground behind the camera is higher than the camera, and with `noclip` on you
	see the inside of the hill. It is known and it is not fixed: fixing it means
	bringing a filtered ground into a branch that today has a single owner of Z.

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
	-- THE HERO VIEW: HOW HIGH, HOW FAR BACK, AND HOW FAST IT COMES ROUND.
	--
	-- `eyeH` has been measured in game four times -- 2.2 (a human head, and
	-- literally inside it), 7, 5, and now 4 with the camera BEHIND the hero
	-- rather than on top of him. It is not a number that can be reasoned out
	-- from here: how far you want to be from your own character is a matter of
	-- feel, like mouse sensitivity, and every round of it has moved.
	--
	-- AND BOTH DISTANCES HAVE TWO MOUTHS, which is what makes them settings and
	-- not constants: `SPACE`/`C` write `eyeH` and `W`/`S` write `eyeD` live, and
	-- `/rts fc eyeH 4` / `/rts fc eyeD 8` write the same two numbers by hand.
	-- They are NOT a live copy of the camera, and that is what makes the spot
	-- you back off to the spot you get next time you come in.
	--
	-- `eyeTurn` is the k of the chase of the HERO FACING, and it is separate
	-- from `lockSmooth` on purpose: the position can be chased at 25 because its
	-- lag is a constant offset nobody sees, and the angle cannot -- a turn in
	-- this client is instantaneous, so at 25 a bot changing his mind is a
	-- whip-pan. At 6 that same turn takes about half a second to settle, which
	-- is what a camera on a rail behind someone looks like.
	eyeTurn = 6.0,    -- k of the chase of his facing (1/s); higher is sharper
	-- AND THE SPIN, WHICH IS TWO NUMBERS: what counts as one, and how slowly the
	-- camera comes back behind him afterwards.
	--
	-- `eyeSnap` is generous on purpose. Running a curve at full tilt moves the
	-- facing some three degrees between readings and a click-to-move spins it up
	-- to a hundred and eighty, so anywhere in the middle works; what it must not
	-- do is fire while simply travelling, because the symptom of that would be
	-- the camera drifting off a hero who never did anything sudden.
	--
	-- `eyeBack` IS MEANT TO BE TOO SLOW. It was asked for as "muy MUY lento", and
	-- a constant speed is what delivers that: an exponential would start at
	-- `k * 180` and the first half of the return would be the whip-pan all this
	-- exists to avoid. At twenty degrees a second, coming back from a click
	-- behind you takes nine seconds and reads as the camera settling rather than
	-- as the camera moving. Zero means it never comes back on its own.
	eyeSnap = 40.0,   -- degrees between two readings that count as a SPIN
	eyeBack = 20.0,   -- deg/s of the slow return behind him (0 = it never does)
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

-- The caps on the DISTANCE, and the low one is the "do not go past him" this
-- mode was asked for: W brings the camera in and stops a yard short instead of
-- crossing over the hero and coming out looking at his face. Zero is not a
-- distance either -- the tilt is `atan(dz / eyeD)`, which at zero is the camera
-- looking straight down its own axis.
local EYE_DMIN, EYE_DMAX = 1.0, 50.0

-- WHERE ON THE HERO THE CAMERA AIMS ON THE WAY IN -- and only on the way in,
-- the tilt is the drag's from the next frame: a yard and a half over his feet,
-- roughly the chest. Aiming at the feet with the camera four yards up would put
-- him at the top of the screen with the floor filling the rest of it.
local EYE_AIM = 1.5

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
-- 3 -> 4: from five to four, with the camera moving from over the hero to behind
-- him. The stamp goes up for the same reason every time: anyone with 5.0 written
-- down would never see the 4.0.
local EYE_GEN = 4

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
			"|cffffff00%.1f|r yd (the camera now rides BEHIND your hero, not over " ..
			"him). |cffffff00/rts fc eyeH %.1f|r puts it back."):format(
			was, c.eyeH, was))
	end
end

-- Settings that USED TO EXIST and no longer do. They are wiped from the saved
-- variables on every read: a number saved under a name nothing reads is a dial
-- wired to nothing, and the next person to grep for it finds a value that has
-- not moved anything for months.
--
--   eyeFast/eyeSoft/eyeSlow -- the ground filter in degrees, tried on
--   2026-09-15 for the hero view turning and taken straight back out: the
--   brief behind it was not the one the player had in mind.
--   eyeHold -- the freeze after a spin, replaced on 2026-09-16 by absorbing
--   the spin into `orbit`, which does the same job without the second turn
--   that gave it away.
local DEAD = { "eyeFast", "eyeSoft", "eyeSlow", "eyeHold" }

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
	-- THE SAME TWO CONSTANTS W AND S USE, and for the same reason as `eyeH`.
	if c.eyeD < EYE_DMIN or c.eyeD > EYE_DMAX then c.eyeD = D.eyeD end
	-- At zero the camera would never come round and the mode would look broken
	-- exactly when the hero turns; above 200 it is the raw 33 Hz staircase back
	-- again. Out of range is garbage and goes back to the default.
	if c.eyeTurn <= 0 or c.eyeTurn > 200 then c.eyeTurn = D.eyeTurn end
	-- Under ten degrees a hard curve would count as a spin and the camera would
	-- let go of a hero who is only running; over 180 nothing can ever reach it
	-- and the pause would never happen at all.
	if c.eyeSnap < 10 or c.eyeSnap > 180 then c.eyeSnap = D.eyeSnap end
	-- Zero is allowed here (see `D`): it is "it never comes back by itself", the
	-- sticky framing of the very first version, and not a broken value.
	if c.eyeBack < 0 or c.eyeBack > 360 then c.eyeBack = D.eyeBack end
	-- AND THE KEYS THAT STOPPED EXISTING ARE THROWN AWAY, not left lying in the
	-- SavedVariables. They are cleared here, one line for all of them, rather
	-- than with a generation: a generation means "what was saved no longer means
	-- the same thing" and would take `speed`, `height` and the other twenty with
	-- it, and what happened to these is simpler -- nobody reads them any more.
	for _, dead in ipairs(DEAD) do c[dead] = nil end
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
             ox = 0, oy = 0, oz = 0,
             -- THE HERO VIEW, and neither of these is a position: `orbit` is
             -- the angle FROM THE HERO NOSE (0 = his back) that A/D write, and
             -- `hf` is his facing chased with smoothing. The framing `o*` above
             -- is recomputed from those two every frame, which is why the
             -- camera keeps the side you chose through every turn he makes.
             orbit = 0, hf = nil,
             -- THE SPIN: `rawf` is his facing AS PUBLISHED (not chased), which
             -- is the only place a spin can be measured, and `back` says there
             -- is a return pending. `px/py` and `moving` are how "he is
             -- walking" is answered -- the trigger of that return.
             rawf = nil, back = false,
             px = nil, py = nil, moving = 0,
             -- THE YAW WE WROTE INTO THE CAMERA LAST FRAME, which is how the
             -- drag is told apart from our own writing (`DragRead`).
             wroteYaw = nil }

-- The lock is on. It lives on `F` and not on `st` because it gets asked about
-- from outside -- the report, the command -- and `st` belongs to the solver.
F.lock = false

-- AND THE HERO VIEW IS A SECOND FLAG, NOT A VALUE OF THE FIRST. `eyes` implies
-- `lock` -- the camera hangs off the hero just the same -- and what it adds is
-- that the framing stops being the player. Storing it as "lock = 2" would have
-- forced every `if self.lock` in the file to ask which of the two, which is how
-- branches that only work in one mode get in.
F.eyes = false

-- None of the commentator functions had ever been called in this project, so
-- every one of them goes through here: if one does not exist, the controller
-- carries on working instead of blowing up on every frame.
-- The flat forward and the ground, the two DLL readings everything else leans
-- on. They live NEXT TO `st` and not near the turning on purpose: I have
-- deleted them by accident TWICE while rewriting the mouse block, because they
-- were inside the range I was replacing. Here there is nothing to rewrite.
local function FlatForward()
	if RTS_HasCam ~= 1 then return nil end
	local fx, fy = RTS_CamFwdX, RTS_CamFwdY
	if not fx or not fy then return nil end
	local len = math.sqrt(fx * fx + fy * fy)
	-- Looking straight down the projection is almost zero and the direction
	-- stops being defined. A minuscule length is not normalised: there is no
	-- forward, and that frame does not move -- better than being fired off in a
	-- random direction.
	if len < 0.001 then return nil end
	return fx / len, fy / len
end

-- THE GROUND, AND WHICH OF THE TWO RAYS IT COMES OUT OF.
--
-- The DLL publishes two heights under the camera, and the difference between
-- them is the whole roof problem:
--
--   `RTS_CamGroundZ` -- the FIRST thing underneath. A roof, a sign, the top of
--                       a tree. It is the one there was, and it is the good one
--                       for flying over a place without dropping into anything.
--   `RTS_CamLandZ`   -- the TERRAIN only. Anything built stops being ground, so
--                       a roof neither lifts the camera nor stops it coming
--                       down right inside the house.
--
-- It also returns where it came from, because "the camera rises by itself" and
-- "the camera will not come down" are the same symptom with the two sources
-- swapped, and telling them apart by looking at the screen costs a round.

-- THE BLACK BOX OF THE CAVE MOUTH. It speaks up when the terrain ends up above,
-- because that is the only instant that matters and it lasts less than it takes
-- to type `/rts fc`. It is limited to one warning every two seconds: inside a
-- cave the condition is true on EVERY frame, and without the brake it would be
-- sixty lines a second burying the chat.
local lastBox = 0
local function BlackBox(land, solid)
	local now = GetTime and GetTime() or 0
	if now - lastBox < 2.0 then return end
	lastBox = now
	ns.Print(("|cffff8800rock ceiling|r: terrain %.1f ABOVE, solid %.1f below, camera %.1f -- the solid one is used")
		:format(land, solid, st.z or 0))
end

-- THE RAY THAT SAYS IT HIT WITHOUT HITTING (2026-09-12).
--
-- Inside the cave, `/rts fc` printed this:
--
--     ground: terrain 0.0   solid 1345.7   in use: terrain
--
-- `terrain 0.0` is NOT "it did not answer" -- that prints as `--`. It is that
-- `RTS_CamLandHit` came in at 1 and `RTS_CamLandZ` at zero: the terrain ray said
-- it DID hit, and did not write where. In the DLL, `Cast` starts `out = {0,0,0}`
-- and returns it just like that if `CGWorldFrame::Intersect` answers true
-- without touching it, which is what it does where the ADT is deliberately
-- holed -- that is, right inside a cave.
--
-- AND THERE IS THE PLOP, whole, with no loops and no cliffs: a ground of 0.0
-- with the camera at 1345 is a thirteen-hundred-yard drop, bigger than
-- `GROUND_SNAP`, so the filter does what it is told to do with an impossible
-- jump -- it catches up ALL AT ONCE -- and the camera turns up at `0 + offset`,
-- at the bottom of the world. That is why it was not clear whether it went up
-- or down: it went down, all the way, in one frame.
--
-- The rule is that a hit has to land INSIDE the segment that was fired. The DLL
-- casts from `cam.z + 5` down to `cam.z - 1000`; anything outside that cannot
-- have been touched by that ray. There is no constant to invent: they are the
-- publisher's own two. Zero is discarded on its own account as well, because it
-- is the value the publisher itself writes when there is NO hit, and no ground
-- in the world falls exactly on 0.000.
--
-- This covers the symptom on the cheap side -- a `/reload` instead of
-- recompiling and injecting. The root fix is for the DLL not to publish a hit
-- it has not written.
local RAY_UP, RAY_DOWN = 5.0, 1000.0

local function RayHit(hit, z)
	if hit ~= 1 or type(z) ~= "number" then return nil end
	if z == 0 then return nil, "0.0" end
	if st.z and (z > st.z + RAY_UP + 0.5 or z < st.z - RAY_DOWN) then
		return nil, ("%.1f"):format(z)
	end
	return z
end

-- THE CEILING RAY (rts_core 0.29.0). It looks at the `RAY_UP` yards ABOVE the
-- camera, and terrain only. It is the one thing the head start on the downward
-- ray bought -- getting out from under the ground when the smoothing has slipped
-- you through -- split out into a reading with its own name, now that the
-- downward one starts at the camera and at last means "what is UNDERNEATH".
--
-- With an old rts_core this is nil and nothing happens: the blind band comes
-- back, which is exactly how it had been working all along.
local function CeilAbove()
	local z = RayHit(RTS_CamCeilHit, RTS_CamCeilZ)
	if z and st.z and z >= st.z and z <= st.z + RAY_UP + 0.5 then return z end
	return nil
end

local function GroundUnderCamera(c)
	local land  = RayHit(RTS_CamLandHit,  RTS_CamLandZ)
	local solid = RayHit(RTS_CamGroundHit, RTS_CamGroundZ)
	if c.floor == 1 then
		-- TERRAIN STOPS BEING GROUND WHEN IT IS ABOVE YOUR HEAD.
		--
		-- Here was the cause of the caves, and not in the height arithmetic: the
		-- arithmetic did exactly what it was asked to do with a MEASUREMENT THAT
		-- WAS NOT A GROUND. Crossing the mouth, the camera XY passes under the
		-- outline of the mountain; the ADT is only holed on the INSIDE, so the
		-- terrain ray goes on answering -- and what it returns is the slope
		-- outside, tens of yards ABOVE. The hard floor reads that and does the
		-- only thing it knows how to do: push the camera up to `ground + clear`,
		-- that is, to the roof of the mountain, going through the rock the whole
		-- way. That is the purple screen, and that is why the `/rts fc` from
		-- inside came out coherent: the sums added up against the wrong surface.
		--
		-- A ground is UNDERNEATH. If the terrain is above and the solid is
		-- below, the solid is the floor of the cave and the terrain is the rock
		-- ceiling over our heads: there is nothing to decide.
		--
		-- And the rule does not touch the cliff, which is the case that looks
		-- the same: flying into a crag the terrain is above as well, but there
		-- there is NO solid underneath -- the crag is bare terrain -- so the `if`
		-- is not entered and the camera climbs it as it always has. BOTH things
		-- have to happen at once, and that only happens under a roof.
		if land and solid and st.z and land > st.z and solid < st.z then
			BlackBox(land, solid)
			return solid, "solid (the terrain is above)"
		end
		if land then return land, "terrain" end
		-- FALLING BACK TO THE SOLID IS NOT DEGRADING HERE, IT IS GETTING IT
		-- RIGHT. Inside a cave the ADT is deliberately holed and the terrain ray
		-- DOES NOT ANSWER: the good ground for that place is precisely the solid
		-- one -- the floor of the cave. It is also what happens with an old DLL,
		-- which does not publish `RTS_CamLandZ` at all, and there the camera
		-- behaves as it did before instead of being left with no height.
		if solid then return solid, "solid (no terrain here)" end
		return nil, nil
	end
	if solid then return solid, "solid" end
	return nil, nil
end

-- A change of ground bigger than this is NOT a step in the world: it is a
-- teleport, a change of map or the first frame. Filtering it at 6 yd/s would
-- leave the camera climbing for a minute and a half, so there it snaps.
local GROUND_SNAP = 300.0

local function Try(name, ...)
	local fn = _G[name]
	if type(fn) ~= "function" then return false end
	local ok, a, b, c, d, e, f = pcall(fn, ...)
	if not ok then return false end
	return true, a, b, c, d, e, f
end

-- === THE TURNING IS NATIVE. WE ONLY CARRY THE POSITION ==================
--
-- FIFTH ATTEMPT, and the one that is surplus is the fourth: reading the mouse
-- raw from the DLL and turning ourselves. It worked and it felt wrong -- **jerky,
-- laggy and far too sensitive**, and with the horizontal axis inverted. And it
-- had to feel wrong by construction: the DLL accumulates deltas, publishes them
-- at 67 Hz through a chain of Lua, and the addon applies them on the next frame.
-- Three stages of delay and a quantisation, to reimplement something the client
-- already does perfectly.
--
-- AND THE EVIDENCE THAT THE CLIENT DOES IT RIGHT WAS ALREADY IN OUR HANDS, read
-- wrong. In 1.17.0 the player said *"now I have been able to move the camera
-- with the mouse but not with WASD"*. In that version the controller was DOWN --
-- I had deleted `FlatForward` by accident -- so it was not writing the camera at
-- all, and the client native drag was moving the camera you see. Which means the
-- native turning DOES reach our camera; what was killing it was me overwriting
-- the angles every frame. My conclusion at the time ("it turns some other
-- camera") was false, and I drew it from a test run with the controller dead.
--
-- So the division of labour is: **the client carries the ORIENTATION, we carry
-- the POSITION.** The right mouse button is the same old mouselook -- with the
-- sensitivity and the inversion the player already has configured, for free --
-- and WASD, SPACE/C and the height over the terrain stay ours.
--
-- HOW THEY LIVE TOGETHER, which is the only part with a trick to it:
-- `CommentatorSetCamera` takes the six values at once, so the position cannot be
-- written without writing the angles. The live ones are READ just before and
-- written straight back: for the orientation it is a no-op and the client
-- turning accumulates on its own.
--
-- They are read with `CommentatorGetCamera`, which is SYNCHRONOUS and reads
-- `cam+0x11C`/`+0x120` of the active camera on this very frame -- not
-- `RTS_CamFwd*`, which comes from the DLL a tick late. That choice is what takes
-- the latency out.
local function AdoptLook()
	local ok, _, _, _, yaw, pitch = Try("CommentatorGetCamera")
	if not ok or type(yaw) ~= "number" or type(pitch) ~= "number" then return end
	st.yaw = yaw % 360
	if pitch < -89 then pitch = -89 end
	if pitch > 89 then pitch = 89 end
	st.pitch = pitch
end

-- === WHICH WAY THE HERO IS FACING, IN COMMENTATOR YAW ==================
--
-- Entering the hero view is the only thing in this file that needs to ASK for a
-- particular yaw -- the hero's -- and there the question everything else has
-- been dodging from the start comes back: WHAT IS THE ANGLE CONVENTION OF
-- `CommentatorSetCamera`. It cannot be read from the binary (the disassembly
-- only shows the argument being multiplied by DEG2RAD and stored), and this
-- project has already paid TWICE for guessing a sign: the `pitch` up above and
-- the two `SetPosition` calls on the portrait.
--
-- So it is not guessed: it is MEASURED, with two figures already on screen.
--
--   * `CommentatorGetCamera` gives the LIVE yaw of the camera.
--   * the DLL publishes its forward in WORLD coordinates (`RTS_CamFwdX/Y`),
--     which as an angle is `atan2(fy, fx)` -- the same convention as `RTS_PF`.
--
-- One pair alone is not enough: it gives the offset but NOT THE SIGN -- a yaw
-- that grew the other way fits a single sample just as well, and the error would
-- only show as a mirrored entrance. With two pairs at different yaws both come
-- out at once:
--
--     world = sign * yaw + offset
--
-- AND THE SAMPLES ARE TAKEN WITH THE CAMERA STILL. The forward comes from the
-- DLL at 100 Hz and the yaw is read on this very frame: while turning they are
-- two different instants, which means the measurement would come out crooked
-- exactly when it moves most. At rest, both are from the same place and the
-- subtraction is exact.
--
-- NOTHING HAS TO BE ASKED OF THE PLAYER. The second sample arrives on its own as
-- soon as they turn the camera, which is the first thing anybody does; until
-- then the offset from a single one is used with the assumed sign, which is what
-- there would have been anyway.
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
	-- Looking straight down the projection is almost zero and the angle stops
	-- being defined; same sieve as `FlatForward` and for the same reason.
	if (fx * fx + fy * fy) < 0.000001 then return nil end
	return math.deg(math.atan2(fy, fx))
end

local function CalibrateYaw()
	local yaw, prev = st.yaw, look.prev
	look.prev = yaw
	if not yaw or not prev then return end
	if math.abs(Wrap180(yaw - prev)) > 0.02 then return end   -- turning: no good
	local w = CamWorldAngle()
	if not w then return end
	if not look.refY then
		look.refY, look.refW = yaw, w
		return
	end
	local dy = Wrap180(yaw - look.refY)
	local ady = math.abs(dy)
	-- Below 20 degrees the measurement is all noise; above 170 the sign of the
	-- wrap stops being clear (at exactly 180, +1 and -1 give the same thing).
	-- Outside that window nothing is concluded and it goes on waiting.
	if ady < 20 or ady > 170 then return end
	local dw = Wrap180(w - look.refW)
	-- THE CHECK THAT TURNS AN ASSUMPTION INTO A MEASUREMENT: if the world has not
	-- turned THE SAME as the yaw, the relation is not `sign * yaw + offset` and
	-- there is nothing to deduce. Without this, a wrong model would come out as a
	-- sign with all the confidence in the world.
	if math.abs(math.abs(dw) - ady) > 5 then return end
	look.sign = (dw * dy >= 0) and 1 or -1
	look.delta = Wrap180(w - look.sign * yaw)
	look.refY, look.refW = yaw, w
end

-- A WORLD direction (radians, the `RTS_PF` convention) in yaw.
local function YawForWorld(rad)
	local sign, delta = look.sign, look.delta
	if not sign then
		-- Without both samples yet: the offset from ONE, taking it as given that
		-- the yaw grows like the world angle. If that were false, this entrance
		-- comes out mirrored and the next one does not -- as soon as the player
		-- turns, the real measurement is done.
		local w = CamWorldAngle()
		if not w or not st.yaw then return nil end
		sign, delta = 1, Wrap180(w - st.yaw)
	end
	return ((math.deg(rad) - delta) * sign) % 360
end

local function LookReport()
	if look.sign then
		return ("sign %+d, offset %.1f |cff888888(measured with two samples)|r"):format(
			look.sign, look.delta)
	end
	local w = CamWorldAngle()
	if w and st.yaw then
		return ("offset %.1f |cffff8800(a single sample: turn the camera to measure the sign)|r"):format(
			Wrap180(w - st.yaw))
	end
	return "|cffff8800not measured|r (is the camera published?)"
end

-- === THE MOUSE IN THE HERO VIEW: HALF A DIFFERENCE, HALF AN ANGLE ========
--
-- The two axes of the same drag end up in different places, and they have to:
--
--   THE TILT is adopted whole, like `AdoptLook` does everywhere else. Nobody
--   else writes it in this mode, so whatever the client has is the player's and
--   is handed straight back -- dragging up looks up, at their own sensitivity
--   and with their own inversion.
--
--   THE YAW cannot be adopted, because it is a consequence of where the hero
--   looks. What is taken from it is WHAT THE CLIENT HAS ADDED since we wrote it
--   last frame, and that difference is spent on the orbit. `st.wroteYaw` is the
--   other half: with no previous write there is no difference to measure and it
--   says zero, because the alternative -- reading the whole live angle as a
--   drag -- is a jump of whatever the camera happened to be pointing at.
--
-- Both are read with `CommentatorGetCamera`, which is SYNCHRONOUS -- this frame,
-- not the DLL a tick late -- for the same reason `AdoptLook` uses it: anything
-- else puts back the delay all of this exists to remove.
local function DragRead()
	local ok, _, _, _, yaw, pitch = Try("CommentatorGetCamera")
	if not ok or type(yaw) ~= "number" or type(pitch) ~= "number" then
		return 0, nil
	end
	local dy = st.wroteYaw and Wrap180(yaw - st.wroteYaw) or 0
	-- Under a hundredth of a degree it is the round trip through the client
	-- float and not a hand on the mouse. Without this the orbit creeps.
	if math.abs(dy) < 0.01 then dy = 0 end
	-- The same two stops `AdoptLook` uses: past them the camera is upside down
	-- and the client is the one that says so.
	if pitch < -89 then pitch = -89 end
	if pitch > 89 then pitch = 89 end
	return dy, pitch
end

-- The buttons, from the DLL. `IsMouseButtonDown` returns NO while the client has
-- the mouse grabbed, so to know whether BOTH are held there is no other source.
--
-- AND NOBODY PUBLISHES `RTS_MouseRaw` TODAY, so this answers "neither button" on
-- every frame and the one gesture left hanging off it -- left + right to move
-- forward -- does nothing. It reads as implemented and is not: the producer went
-- with the fourth attempt at mouse turning (raw deltas from the DLL, measured to
-- feel jerky) and the consumer stayed.
--
-- IT IS KEPT ON PURPOSE, pending a decision on publishing the two buttons from
-- `Publisher.cpp`, which is where the missing half is. What HAS gone is the line
-- in `/rts fc mouse` that reported them: a diagnostic that prints "right button:
-- NO" while you hold the right button does not report a fault, it invents one.
local function MouseButtons()
	if RTS_MouseRaw ~= 1 then return false, false end
	local b = tonumber(RTS_MouseB) or 0
	return (b % 2) == 1, (math.floor(b / 2) % 2) == 1
end

--- THE LOCK ---------------------------------------------------------------
--
-- A switch, and it does ONE thing: while it is on, the camera stays at the same
-- distance from the hero -- whatever it was when it was switched on -- and
-- travels with him. For following the party along the road without driving the
-- camera by hand.
--
-- WHAT IT DOES NOT DO, which is the half that was asked for in writing: it does
-- not touch the angle, it does not touch the height, it repositions nothing. The
-- framing is set by the player -- with the mouse, with W/A/S/D, with SPACE and C
-- -- and it stays exactly as it is until they touch it again. There is not one
-- framing decision here.
--
-- THAT IS WHY THE KEYS MOVE THE FRAMING AND NOT THE CAMERA. With the lock on,
-- the camera position is ALWAYS `anchor + framing`, so writing into it directly
-- -- as the free mode does -- would be writing into a value that gets recomputed
-- from scratch on the next frame: the keys would look as if they did nothing.
-- Adding to the framing, adjusting the plane while travelling works just as it
-- always did and what was adjusted PERSISTS, which is exactly what was asked
-- for.
--
-- AND THERE IS NO GROUND HERE. No ray, no step filter, no hard floor, no push
-- budget: Z comes from the hero, who already walks the ground on his own.
-- Bringing the height correction in would be a second owner of Z arguing with
-- the lock every frame -- the kind of fight this file has already lost twice --
-- and it would also break the promise of the fixed distance the moment the hero
-- walked under a roof.
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
	-- With no hero position this tick one is not invented: the camera stays
	-- where it is. It happens when changing zone and lasts as long as the DLL
	-- takes to publish again.
	if not hx then return end

	if not st.ax then
		st.ax, st.ay, st.az = hx, hy, hz
	else
		-- A CHANGE OF MAP IS NOT A STEP. Same as `GROUND_SNAP` for the ground:
		-- beyond that distance the hero has not moved, he HAS BEEN moved --
		-- teleport, portal, change of character -- and chasing him with
		-- smoothing would be crossing the continent in plain sight. There it
		-- snaps.
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
		-- THE CAMERA IS A POLAR COORDINATE AROUND THE HERO, and every key in this
		-- branch moves one of its three numbers: `orbit` (A/D), `eyeD` (W/S) and
		-- `eyeH` (SPACE/C). NOTHING HERE WRITES A POSITION, and that is what makes
		-- the framing survive the hero turning: `st.ox/oy/oz` are recomputed from
		-- the three of them every single frame.

		-- A/D PIVOT, AND Q/E DO THE SAME rather than nothing: they are the turn
		-- pair everywhere else in this file, and a key that does nothing in one
		-- mode reads as a key that is broken. `yawSign` is the same dial that
		-- flips Q/E in free flight -- if the pivot comes out backwards it is
		-- backwards in both places, and there is one number to change.
		-- IS HE WALKING? Not his speed: whether the published position has moved
		-- AT ALL since the last reading, with a grace of a few hundredths after it
		-- last did. The DLL publishes at 33 Hz and the screen runs at 60 or more,
		-- so on half the frames the position is the same one twice and a speed
		-- computed from it would read zero in the middle of a run.
		if st.px and ((hx - st.px) ^ 2 + (hy - st.py) ^ 2) > 0.0004 then
			st.moving = 0.15
		else
			st.moving = math.max(0, (st.moving or 0) - dt)
		end
		st.px, st.py = hx, hy

		-- THE DRAG: SIDEWAYS IT PIVOTS AND UP AND DOWN IT TILTS, and it cannot do
		-- anything else -- there is no gesture here that takes the view off the
		-- hero, because that is what the mode is.
		local dYaw, lookPitch = DragRead()
		if dYaw ~= 0 then
			-- The client yaw is not the world angle: `look.sign` is the measured
			-- relation between the two (`CalibrateYaw`).
			--
			-- AND THE MOUSE GOES THE OTHER WAY ROUND THAN A/D, which reads as an
			-- inconsistency and is the opposite of one: the hand means a different
			-- thing by each gesture. A KEY MOVES THE CAMERA -- D is strafe right,
			-- the same as in free flight -- and A DRAG POINTS THE VIEW, so dragging
			-- left must turn left, which is the camera going round him the other
			-- way. It was built the consistent way first and tried in game, and
			-- the consistent way is the one that feels backwards.
			st.orbit = ((st.orbit or 0) + (look.sign or 1) * dYaw * c.yawSign) % 360
			-- AND THE HAND ON THE MOUSE CANCELS THE RETURN. A camera drifting back
			-- behind him while the player is deliberately moving it somewhere else
			-- is the camera arguing with the person holding it.
			st.back = false
		end

		local pivot = 0
		if input.right or input.yawR then pivot = pivot + 1 end
		if input.left  or input.yawL then pivot = pivot - 1 end
		if pivot ~= 0 then
			st.orbit = ((st.orbit or 0) + pivot * c.yawSign * c.turn * dt) % 360
			st.back = false   -- same as the drag: the keys win over the return
		end

		-- W/S ARE A DOLLY, NOT A WALK: they move the distance and nothing else, so
		-- coming in does not drag the camera down towards the ground and W does
		-- not fly you over the hero and out the far side -- it stops at
		-- `EYE_DMIN`, which is the "without going past him" that was asked for.
		-- The speed is `lift`, the same one SPACE and C use: it is the nudge speed
		-- of this whole mode, and two dials for one gesture is one dial forgotten.
		local dolly = 0
		if input.fwd  then dolly = dolly - 1 end
		if input.back then dolly = dolly + 1 end
		if dolly ~= 0 then
			local d = c.eyeD + dolly * c.lift * dt
			if d < EYE_DMIN then d = EYE_DMIN end
			if d > EYE_DMAX then d = EYE_DMAX end
			c.eyeD = d
		end

		-- SPACE/C: the height over his feet, and it writes the SETTING for the
		-- same reason the dolly does -- one number, two mouths, `/rts fc eyeH`
		-- being the other one. The drag adds a second hand to the same number.
		local lift = 0
		if input.up then lift = lift + 1 end
		if input.down then lift = lift - 1 end
		-- AND IT IS A TRANSLATION AND NOTHING ELSE. It used to aim at his chest
		-- as it went, which meant SPACE could not raise the camera without tilting
		-- it down -- one key doing two things, and the second one not asked for.
		-- The tilt is the drag's now, and it stays where the player left it while
		-- the camera goes up and down past it.
		if lift ~= 0 then
			local h = c.eyeH + lift * c.lift * dt
			-- Clamped HERE with the same two constants `Cfg` uses, not with new
			-- numbers: see the comment over there. It is clipped rather than
			-- bounced, which is what makes holding the key against the cap feel
			-- like a cap and not like a bug.
			if h < EYE_MIN then h = EYE_MIN end
			if h > EYE_MAX then h = EYE_MAX end
			c.eyeH = h
		end

		-- THE HERO FACING, CHASED AND NOT COPIED, and by the SHORT way round:
		-- without the `Wrap180` a hero crossing from 359 to 1 degree would send the
		-- camera all the way round the circle the other way, at the one moment it
		-- shows most.
		local face = (type(RTS_PF) == "number") and math.deg(RTS_PF) or nil
		if face then
			if not st.hf then
				st.hf, st.rawf = face, face
			else
				-- A SPIN, MEASURED BETWEEN TWO READINGS OF THE RAW FACING. On the
				-- chase error it could not be measured: the error is large for a
				-- whole second after every spin, so the start of one and the middle
				-- of one look identical. Here they do not -- an advance moves this
				-- by about three degrees and a click-to-move by a hundred and
				-- eighty.
				local jump = st.rawf and math.abs(Wrap180(face - st.rawf)) or 0
				st.rawf = face
				if jump >= c.eyeSnap then
					-- THE SPIN IS ABSORBED: what is added to `orbit` is exactly what
					-- is taken off `hf`, and the camera is their SUM, so it does not
					-- move by one degree. From the next frame the facing is glued
					-- again (they are equal) and the whole discrepancy is parked in
					-- `orbit`, where the slow return can undo it -- instead of in the
					-- chase, where it came out as a second turn on top of the first.
					st.orbit = ((st.orbit or 0) + st.hf - face) % 360
					st.hf = face
					st.back = true
				else
					-- BY THE SHORT WAY ROUND: without the `Wrap180` a hero crossing
					-- from 359 to 1 degree would send the camera all the way round
					-- the other side, at the one moment it shows most.
					st.hf = (st.hf + Wrap180(face - st.hf) *
						(1 - math.exp(-c.eyeTurn * dt))) % 360
				end
			end
		end

		-- AND HERE IS THE WHOLE MODE, in four lines: the camera sits on the far
		-- side of `facing + orbit` at `eyeD`, and looks back down it.
		-- THE SLOW RETURN, AND IT WAITS FOR HIM TO WALK. That is the gesture as it
		-- was asked for: click, watch him turn, watch him set off, and only then
		-- does the camera settle in behind him.
		--
		-- AT A CONSTANT SPEED, not a chase. A chase is proportional, so it would
		-- start at `k * 180` and spend the first half of the return doing exactly
		-- the whip-pan this was built to remove. Constant is what "muy MUY lento"
		-- means, and it ends at a twentieth of a degree a frame -- a stop nobody
		-- can see.
		if st.back and (st.moving or 0) > 0 then
			local o = Wrap180(st.orbit or 0)
			local step = c.eyeBack * dt
			if math.abs(o) <= step then
				st.orbit, st.back = 0, false
			else
				st.orbit = (st.orbit - (o > 0 and step or -step)) % 360
			end
		end

		local world = (st.hf or 0) + (st.orbit or 0)
		local rad = math.rad(world)
		st.ox = -math.cos(rad) * c.eyeD
		st.oy = -math.sin(rad) * c.eyeD
		st.oz = c.eyeH

		-- THE ONLY THING THAT NEEDS THE MEASURED CONVENTION IS THE LOOK. The
		-- position above is world coordinates and cannot come out mirrored; the
		-- yaw goes through `YawForWorld`, and while there is no measurement yet it
		-- keeps the previous one instead of snapping to zero -- a camera pointing
		-- slightly wrong beats a camera pointing east.
		local yaw = YawForWorld(rad)
		if yaw then st.yaw = yaw end
		-- AND THE TILT IS NOT COMPUTED, IT IS THE PLAYER'S: whatever the client
		-- has, which is where their last drag left it. Nothing else in this mode
		-- writes it, so it survives the height, the distance and every turn the
		-- hero takes. POSITIVE LOOKS DOWN (see `pitch` in `D`).
		if lookPitch then st.pitch = lookPitch end
		-- WHAT WE WROTE, KEPT, and `Step` writes exactly this a few lines later.
		-- It is the other half of `DragRead`: without it there is nothing to
		-- subtract the client yaw from, and the drag cannot be told apart from our
		-- own writing.
		st.wroteYaw = st.yaw
	else
		-- The keys ADJUST THE FRAMING. Same speed and same smoothing as in the
		-- free mode: `st.vx/vy` already come computed from the same solver up
		-- above, so the plane feels the same with the lock on.
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

	-- The filtered ground is forgotten WHILE the lock lasts, not when it is
	-- released: that way the first free tick latches onto whatever is under
	-- wherever the camera ended up, instead of dragging in the ground of
	-- another continent.
	st.gz, st.gstep, st.buried = nil, 0, 0
end

-- THE PANEL SLOT HAS TO FIND OUT, and it cannot find out on its own: it
-- repaints on SELECTION changes (`Panel:Refresh`, subscribed to
-- `ns.Selection`), and the lock is not one. Without this notice, putting the
-- lock on would leave the button dark until the next click on a party member --
-- that is, an indicator that lies about what you have just pressed.
--
-- It goes in `SetLock` and not in the slot because the state is changed HERE:
-- whoever repaints has to hang off whoever decides, not off whoever presses.
local function Repaint()
	-- The lock used to be drawn in a slot of the 4x4 grid, which no longer
	-- exists; since 2026-09-13 it is a macro and there is no button to repaint.
	if ns.Cast and ns.Cast.Refresh then ns.Cast:Refresh() end
end

-- Switching on and off. Returns whether the lock ended up as asked.
function F:SetLock(on)
	if not self.active then
		ns.Print("|cffff8800RTS camera:|r the free camera is not active.")
		return false
	end

	if not on then
		if self.lock then
			self.lock = false
			-- RELEASING THE LOCK RELEASES FIRST PERSON TOO, because first
			-- person IS the lock: leaving `eyes` set with `lock` cleared would
			-- be a flag switched on that no longer commands anything, and the
			-- slot would say "first person" with the camera loose.
			self.eyes = false
			-- `offset` recomputes itself on the first free tick (the anchoring
			-- block): with `gz` at nil, whatever height the camera has NOW
			-- starts being measured against the ground of wherever it is.
			-- Without this the camera would jump straight back to the height it
			-- had when the lock was switched on.
			st.gz, st.gstep, st.buried = nil, 0, 0
			Repaint()
			ns.Print("|cff33ccffRTS camera:|r lock |cffff8800OFF|r.")
		end
		return true
	end

	local hx, hy, hz = HeroPos()
	if not hx then
		ns.Print("|cffff0000RTS camera:|r the DLL is not publishing your hero position.")
		return false
	end
	if not st.x then
		ns.Print("|cffff0000RTS camera:|r the camera has no place yet.")
		return false
	end

	-- THE FRAMING IS CAPTURED, NOT CHOSEN. The distance and the direction are
	-- whatever is on screen at this instant: switching the lock on must not move
	-- a single pixel, only stop letting go.
	st.ax, st.ay, st.az = hx, hy, hz
	st.ox, st.oy, st.oz = st.x - hx, st.y - hy, st.z - hz
	self.lock = true
	Repaint()
	ns.Print(("|cff33ccffRTS camera:|r lock |cff00ff00ON|r at %.1f yd from the hero."):format(
		math.sqrt(st.ox * st.ox + st.oy * st.oy + st.oz * st.oz)))
	return true
end

function F:ToggleLock()
	return self:SetLock(not self.lock)
end

--- THE HERO VIEW ---------------------------------------------------------
--
-- The camera goes behind the hero and stays there. The only thing that has to
-- be decided here is WHERE YOU COME IN -- at his back, at `eyeD` and `eyeH` --
-- because from the next frame onwards `Follow` carries the whole thing.
--
-- COMING IN HAS TO BE INSTANT, not a journey. If this did no more than set the
-- flags, the camera would travel from wherever it was to his back dragged along
-- by the anchor smoothing -- a hundred yards of flight from the bird eye view --
-- which reads as the mode being slow to start. The whole position is written
-- right here and applied on the spot.
function F:SetEyes(on)
	if not self.active then
		ns.Print("|cffff8800RTS camera:|r the free camera is not active.")
		return false
	end

	if not on then
		if self.eyes then
			self.eyes = false
			self.lock = false
			-- The drag reference goes with the mode: on the way back in, the first
			-- frame would otherwise read everything the client has turned in the
			-- meantime as one enormous drag.
			st.wroteYaw = nil
			-- With `gz` at nil the first free tick measures the ground of WHERE
			-- THE CAMERA IS (the hero head) instead of bringing along the one
			-- from before coming in: otherwise, leaving first person would be a
			-- jump in height.
			st.gz, st.gstep, st.buried = nil, 0, 0
			Repaint()
			ns.Print("|cff33ccffRTS camera:|r hero view |cffff8800OUT|r " ..
				"|cff888888(the camera stays where it was)|r.")
		end
		return true
	end

	local hx, hy, hz = HeroPos()
	if not hx then
		ns.Print("|cffff0000camara RTS:|r el DLL no publica la posicion de tu heroe.")
		return false
	end

	local c = Cfg()
	-- COMING IN IS ALWAYS FROM BEHIND, and that is the whole reason the slot is
	-- worth a click: `orbit` is RESET rather than remembered, so one press puts
	-- the camera at his back however you left it last time. The distance and the
	-- height are not reset -- those are how far from your character you like to
	-- be, the same next session -- and the side you were watching from is
	-- something you chose for one sitting.
	st.orbit = 0
	st.hf = (type(RTS_PF) == "number") and math.deg(RTS_PF) or nil
	-- COMING IN IS NOT A SPIN. Without this the first reading would be compared
	-- against whatever was left from the last time the mode was used -- another
	-- character, another continent -- and the mode would open with the pause
	-- already running.
	st.rawf, st.back = st.hf, false
	st.px, st.py, st.moving = hx, hy, 0
	local rad = math.rad(st.hf or 0)
	st.ax, st.ay, st.az = hx, hy, hz
	st.ox = -math.cos(rad) * c.eyeD
	st.oy = -math.sin(rad) * c.eyeD
	st.oz = c.eyeH
	st.x, st.y, st.z = hx + st.ox, hy + st.oy, hz + st.oz
	-- The plane velocity is thrown away: in this mode nobody brakes it, so a
	-- half-released W on the way in would be kept and would come out all at once
	-- on the way back.
	st.vx, st.vy = 0, 0
	st.gz, st.gstep, st.buried = nil, 0, 0

	-- WHICH WAY THE HERO IS FACING, and from here on EVERY frame. This is the
	-- one line that changed meaning when the camera moved from over him to
	-- behind him: the orientation is no longer handed over to the player after
	-- the first frame, it is what keeps the camera at his back when he turns.
	local yaw = st.hf and YawForWorld(rad) or nil
	if yaw then st.yaw = yaw end
	-- THE CHEST AIM SURVIVES AS THE ENTRY TILT AND NOTHING MORE. From the next
	-- frame it belongs to the drag: coming in looking at him is worth a line,
	-- correcting him back into the middle of the screen behind the player's back
	-- is the thing that was taken out.
	st.pitch = math.deg(math.atan2(c.eyeH - EYE_AIM, c.eyeD))
	st.wroteYaw = st.yaw

	self.lock = true
	self.eyes = true
	Repaint()
	ns.Camera:SpecPlace(st.x, st.y, st.z, st.yaw, st.pitch, nil)
	ns.Print(("|cff33ccffRTS camera:|r |cff00ff00hero view|r, %.1f yd up and %.1f yd behind him."):format(
		c.eyeH, c.eyeD))
	if not yaw then
		ns.Print("  |cffff8800I do not know which way he faces|r: turn the camera " ..
			"for a moment and come back in (|cffffff00/rts fc|r explains it).")
	end
	ns.Print("  |cff888888W/S closer and further away, A/D pivot around him, " ..
		"SPACE/C the height. The right drag pivots and tilts.|r")
	return true
end

function F:ToggleEyes()
	return self:SetEyes(not self.eyes)
end

function F:Step(dt)
	if not self.active then return end
	-- A lost frame (zone load, alt-tab) can bring in a huge dt, and with it the
	-- camera jumps. It is clamped: better to run a little slow for one frame
	-- than to teleport.
	if dt <= 0 then return end
	if dt > 0.1 then dt = 0.1 end

	local c = Cfg()

	-- FIRST the live angles, THEN our keys. The other way round, this frame Q/E
	-- turning would be lost: the adoption overwrites the whole yaw.
	-- AND NOT IN THE HERO VIEW, the one mode that owns its own angles: there the
	-- yaw is a CONSEQUENCE of where the hero looks, so adopting the live one
	-- would be letting the right drag fight the follow over the same number --
	-- and the drag would win on every frame the hero did not turn.
	if not self.eyes then AdoptLook() end
	-- RIGHT AFTER ADOPTING and before Q/E touch anything: here `st.yaw` is still
	-- the LIVE yaw of the camera, which is the only one that can be compared with
	-- the forward the DLL publishes. One frame later it would already be the yaw
	-- we are about to ask for, and the measurement would be comparing two
	-- different instants.
	CalibrateYaw()
	local mouseLeft, mouseRight = MouseButtons()

	-- --- turning ------------------------------------------------------
	-- Q AND E GO THE OTHER WAY THAN BEFORE, at the player request (2026-09-10).
	--
	-- It is inverted HERE and not by changing the `yawSign` default, which was
	-- the obvious thing and would have done nothing: that setting is already
	-- saved as 1 in the SavedVariables, and what is saved beats the default.
	-- Changing a default value only reaches whoever does not have it written
	-- down yet -- the same trap that left `pitch` with no effect when it changed
	-- meaning.
	--
	-- `yawSign` still means the same thing (**-1 if it comes out backwards**), so
	-- the dial does not change direction under anybody feet: what changes is
	-- which way the "normal" direction turns.
	local turn = 0
	if input.yawL then turn = turn + 1 end
	if input.yawR then turn = turn - 1 end
	-- Q/E DO NOT TURN IN THE HERO VIEW: there they pivot, like A/D, and they do
	-- it in `Follow`, where the orbit lives. Writing `st.yaw` here as well would
	-- be writing a number that gets recomputed a few lines further down.
	if turn ~= 0 and not self.eyes then
		st.yaw = (st.yaw + turn * c.yawSign * c.turn * dt) % 360
	end

	-- --- movement on the plane ----------------------------------------
	local wantX, wantY = 0, 0
	local mx, my = 0, 0
	if input.fwd then my = my + 1 end
	if input.back then my = my - 1 end
	-- LEFT + RIGHT MOVES FORWARD, the same old gesture. The buttons come from the
	-- DLL and not from `IsMouseButtonDown`, which lies during the drag. It goes
	-- here and not somewhere separate because it is one more input to the same
	-- solver: that way moving with the mouse and turning at once comes free, on
	-- the same frame.
	if mouseLeft and mouseRight and not self.eyes then my = my + 1 end
	if input.right then mx = mx + 1 end
	if input.left then mx = mx - 1 end

	-- AND THE PLANE IS DEAD IN THE HERO VIEW, which is what makes it all
	-- keyboard: the same four keys mean something else there (dolly and pivot,
	-- in `Follow`) and `wantX/wantY` stay at zero, so `st.vx/vy` ease down to
	-- nothing and there is no velocity left over waiting for the way out.
	if (mx ~= 0 or my ~= 0) and not self.eyes then
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
		ns.Print("|cffff8800RTS camera:|r the free camera is not active.")
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
	eyeD = "distancia POR DETRAS del heroe con la camara enganchada (yd); W y S la mueven",
	eyeTurn = "con que fuerza la camara persigue el giro del heroe (k)",
	eyeSnap = "grados de golpe que cuentan como giro brusco y sueltan la camara",
	eyeBack = "velocidad del regreso lento a su espalda tras uno (grados/s; 0 = nunca)",
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
		ns.Print(("  |cff00ff00VISTA DEL HEROE|r: %.1f yd de alto (ESPACIO/C), " ..
			"%.1f yd por detras (W/S), giro %+.0f grados (A/D)%s"):format(
			c.eyeH, c.eyeD, Wrap180(st.orbit or 0),
			hx and "" or "   |cffff8800sin heroe publicado|r"))
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
		if t < 2.0 then return end
		self2:SetScript("OnUpdate", nil)
		ns.Print(("  lecturas de angulo: %d   giro acumulado: yaw %.1f, pitch %.1f"):format(
			n, dyaw, dpitch))
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
