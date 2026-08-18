--[[
	RTSMode.lua -- Warcraft 3 style mouse control.

	Toggling RTS mode shows a full-screen mouse catcher below the HUD frames
	(LOW strata: over the world, under the unit bar / command card, so those
	still work). While it is up:

	  left-click a unit   -> select it            (shift = add/toggle)
	  alt-click a unit    -> take direct control of it
	  left-drag on ground -> box-select units
	  left-click ground   -> deselect
	  right-click ground  -> move selection there
	  right-click an enemy-> attack that unit
	  right-click an NPC  -> interact with it

	RTS mode is ONE switch: it raises the mouse layer and the detached camera
	together, and drops both on the way out.

	Your own character is a unit like any other here -- selectable, orderable and
	possessable. It moves by a different route (the server drives it directly)
	because that is only possible while the camera holds client control, which is
	exactly when you are giving orders.

	Units are located on screen by projecting the world positions rts_core.dll
	publishes (Markers:UnitScreen), so this rides on the same camera math the
	cursor reticle already proved correct.
]]

local ADDON, ns = ...

local R = {}
ns.RTSMode = R

R.active = false

local CLICK_SLOP = 6          -- px; drag beyond this is a box, not a click

-- Deliberately much larger than CLICK_SLOP. Right-drag orbits the camera, and
-- at 6 px an ordinary click -- which almost always twitches a few pixels --
-- was being swallowed as a tiny orbit, so the order never fired. The threshold
-- for "you meant to drag" has to be well clear of hand tremor.
local ORBIT_SLOP = 16
local PICK_RADIUS = 42        -- px; how close a click must be to a unit

-- Ventana del doble click, en segundos. El valor de Windows por defecto es 0,5;
-- se queda algo por debajo para que dos ordenes seguidas a la misma unidad no
-- se confundan con querer seleccionarlas a todas.
local DOUBLE_CLICK = 0.40

--- Selectable roster (party bots + you) ------------------------------------

-- One source of truth, shared with the unit bar and the select-by-index keys.
function R:Roster()
	local list = ns.Selection:GetRosterWithPlayer()
	for _, m in ipairs(list) do m.guid = UnitGUID(m.unit) end
	return list
end

--- Cursor helpers ----------------------------------------------------------

-- Cursor in the same screen space Markers:Project returns (bottom-left origin).
local function CursorXY()
	local mx, my = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	return mx / scale, my / scale
end

--- What the CLIENT says is under the cursor ---------------------------------
--
-- REDESIGNED 2026-08-16. Everything below this used to be a workaround for one
-- self-inflicted problem: a full-screen frame captured the mouse, so the client
-- never set "mouseover", so nothing highlighted on hover and Lua could not tell
-- an enemy from a signpost. Two whole subsystems existed to paper over that --
-- projecting every published unit to screen and measuring pixel distances, and
-- a WHAT/KindOf round trip asking the server to classify a guid we could not
-- identify ourselves.
--
-- Both were reimplementing, worse, something the client already does perfectly:
-- it raycasts the cursor against real model geometry every frame. The fix is to
-- stop taking the mouse away. Then mouseover works, hover highlights come back
-- for free, and picking is exact instead of "within 48 pixels of a projected
-- point".
--
-- The division of labour that falls out of it is the right one, and worth
-- stating because it is the lesson of this whole layer:
--
--     the CLIENT picks, because only it has the mouse
--     the SERVER decides and executes, because only it has exact state
--
-- We send the server a real guid from a real raycast; it works out approach
-- positions, spread and range. Neither side guesses at the other's job.

-- Whatever the client currently has under the cursor, or nil.
function R:HoverUnit()
    if not UnitExists("mouseover") then return nil end

    local guid = UnitGUID("mouseover")
    local name = UnitName("mouseover")
    if not guid then return nil end

    local ours = false
    for _, m in ipairs(self:Roster()) do
        if m.guid == guid or m.name == name then ours = true break end
    end

    return {
        guid     = guid,
        name     = name,
        isPlayer = UnitIsPlayer("mouseover"),
        hostile  = UnitCanAttack("player", "mouseover") and not UnitIsDead("mouseover"),
        ours     = ours,
        dead     = UnitIsDead("mouseover"),
    }
end

-- Nearest roster unit to (sx,sy), or nil.
--
-- Kept as the fallback for the moment the mouse IS captured -- mid drag-box,
-- when the catcher owns it and mouseover is gone. Outside that, HoverUnit is
-- both cheaper and exact.
function R:UnitAt(sx, sy)
	local best, bestD
	for _, m in ipairs(self:Roster()) do
		local ux, uy = ns.Markers:UnitScreen(m.guid)
		if ux then
			local d = (ux - sx) ^ 2 + (uy - sy) ^ 2
			if d <= PICK_RADIUS * PICK_RADIUS and (not bestD or d < bestD) then
				best, bestD = m, d
			end
		end
	end
	return best
end

--- Hostile picking ---------------------------------------------------------
-- Roster picking above only ever looks at your own units, which is why
-- right-clicking an enemy used to fall through to a move order. Creatures are
-- published by rts_core as type 3, so they can be picked the same way -- by
-- projecting their world position and measuring against the cursor.

R.hostilePickRadius = 48   -- px; a little looser than unit picking

-- Nearest attackable creature to (sx,sy), as { guid = ... }, or nil.
function R:HostileAt(sx, sy)
	-- The client's own mouseover is better than anything we can compute, when
	-- it is available: it is the game's real picking, against actual model
	-- geometry rather than a point. It is not always available here, because a
	-- frame that captures the mouse can stop the world seeing it.
	if UnitExists("mouseover") and UnitCanAttack("player", "mouseover")
	   and not UnitIsDead("mouseover") then
		local guid = UnitGUID("mouseover")
		if guid then return { guid = guid, name = UnitName("mouseover") } end
	end

	local best, bestD = self:NearestCreature(sx, sy)
	local r = self.hostilePickRadius
	if best and bestD <= r * r then return best end
	return nil
end

-- Nearest published creature to (sx,sy) with NO radius limit, plus its squared
-- pixel distance. Split out so the diagnostic can report how far the nearest
-- one actually was: "nothing within radius" is useless on its own, because it
-- reads the same whether the projection is broken or you were hovering grass.
function R:NearestCreature(sx, sy)
	local best, bestD
	local count = math.min(RTS_UN or 0, ns.MAX_UNITS)
	for i = 1, count do
		if _G["RTS_U" .. i .. "T"] == 3 then      -- 3 = creature
			local ux, uy = ns.Markers:Project(_G["RTS_U" .. i .. "X"],
			                                  _G["RTS_U" .. i .. "Y"],
			                                  _G["RTS_U" .. i .. "Z"] + 1.0)
			if ux then
				local d = (ux - sx) ^ 2 + (uy - sy) ^ 2
				if not bestD or d < bestD then
					best, bestD = { guid = _G["RTS_U" .. i .. "G"], sx = ux, sy = uy }, d
				end
			end
		end
	end
	return best, bestD
end

--- What is under the cursor ------------------------------------------------
-- The cursor halo used to colour itself from the client's own mouseover, which
-- does not exist in RTS mode -- the catcher frame eats it -- so the halo stayed
-- green over everything. Same answer as the click: ask the server, which is the
-- only side that can tell a boar from an innkeeper.
--
-- Cached per guid, so a cursor resting on something costs one round trip rather
-- than one per frame. Entries are short-lived because a creature can die or
-- change faction, and a stale "attackable" is worse than a moment of green.

local KIND_TTL = 6
local kinds = {}          -- guid -> { kind = 0|1|2, at = time }
local asked = {}          -- guid -> time we last asked, to avoid spamming

-- 0 scenery/neutral, 1 attackable, 2 talkable. Nil until the server answers.
function R:KindOf(guid)
	if not guid then return nil end
	local now = GetTime()
	local e = kinds[guid]
	if e and (now - e.at) < KIND_TTL then return e.kind end

	if ns.Orders:HasServer() and (not asked[guid] or (now - asked[guid]) > 1) then
		asked[guid] = now
		ns.SendServer("WHAT " .. tostring(guid):gsub("^0[xX]", ""))
	end
	return e and e.kind or nil
end

function R:OnKind(hex, kind)
	-- The server answers with the bare hex; our keys carry the 0x the DLL
	-- publishes, so normalise before storing.
	kinds["0x" .. hex] = { kind = kind, at = GetTime() }
end

--- Box selection -----------------------------------------------------------

function R:UnitsInBox(x1, y1, x2, y2)
	local lo_x, hi_x = math.min(x1, x2), math.max(x1, x2)
	local lo_y, hi_y = math.min(y1, y2), math.max(y1, y2)

	local names = {}
	for _, m in ipairs(self:Roster()) do
		local ux, uy = ns.Markers:UnitScreen(m.guid)
		if ux and ux >= lo_x and ux <= hi_x and uy >= lo_y and uy <= hi_y then
			tinsert(names, m.name)
		end
	end
	return names
end

--- Order dispatch ----------------------------------------------------------

-- Move the current selection to a ground point.
--
-- Bots are anchored rather than merely walked -- see Orders:MoveUnitTo for why
-- a plain `go` makes them run home again -- and fanned out around the click so
-- a group does not stack on one coordinate. The player (if selected) is
-- deferred to the ClickToMove step.
function R:MoveSelectionTo(x, y, z)
	local sel = ns.Selection:Get()
	if #sel == 0 then return end

	local playerName = UnitName("player")

	-- Your own character is a unit like any other here: it takes a slot in the
	-- spread and gets ordered with everyone else. It moves by a different route
	-- (see Orders:MoveSelfTo) because the server can only drive your body while
	-- the RTS camera holds client control -- but that is exactly when you are
	-- giving orders, so the distinction never shows.
	local offsets = ns.Orders:SpreadOffsets(#sel, ns.Orders:FacingTo(x, y))
	local batch = {}
	local movedSelf = false

	for i, name in ipairs(sel) do
		local o = offsets[i]
		if name == playerName then
			ns.Orders:MoveSelfTo(x + o[1], y + o[2], z)
			movedSelf = true
		else
			tinsert(batch, { name, x + o[1], y + o[2], z })
		end
	end

	if #batch > 0 then ns.Orders:MoveBatch(batch) end
	ns.Flare:Show(x, y, z, "move")

	local total = #batch + (movedSelf and 1 or 0)
	if total > 0 then
		ns.Print(("Move order -> %d unit%s"):format(total, total == 1 and "" or "s"))
	end
end

--- Click handling ----------------------------------------------------------

-- `hover` is what the client had under the cursor at MOUSE-DOWN, captured
-- before any capture could steal it. Falls back to projected picking only if
-- there was none.
function R:OnLeftClick(sx, sy, shift, alt, hover)
	local m = hover and hover.ours and { name = hover.name, guid = hover.guid,
	                                     isPlayer = hover.name == UnitName("player") }
	          or self:UnitAt(sx, sy)

	-- Alt-click takes command of the unit: its action bar appears and you cast
	-- through it, without the camera moving or leaving RTS mode.
	--
	-- This REPLACED possession, which used to live on this gesture. Possession
	-- swung the camera to the unit and put you in third person, which is the
	-- wrong shape for the thing you actually want a bot for -- three seconds of
	-- healing without ceasing to be the director.
	if alt and m then
		if m.isPlayer then
			ns.Print("That is your own character - you already have its bars.")
		else
			ns.Selection:SelectOnly(m.name)
			ns.CommandMode:Enter(m.name)
		end
		return
	end

	if m then
		-- DOBLE CLICK sobre una unidad tuya = seleccionar todas.
		--
		-- WoW no da un evento de doble click en un frame del mundo, asi que se
		-- mide a mano: dos clicks sobre EL MISMO nombre dentro de la ventana.
		-- Exigir el mismo nombre importa -- si no, un click rapido sobre un bot
		-- y luego sobre otro se leeria como doble click y te seleccionaria a
		-- todos justo cuando querias cambiar de unidad.
		local now = GetTime()
		if shift then
			ns.Selection:Toggle(m.name)
		elseif self.lastClickName == m.name
		   and self.lastClickAt and (now - self.lastClickAt) < DOUBLE_CLICK then
			ns.Selection:SelectAll()
			self.lastClickName, self.lastClickAt = nil, nil   -- que un triple no reabra
			return
		else
			ns.Selection:SelectOnly(m.name)
		end
		self.lastClickName, self.lastClickAt = m.name, now
		return
	end

	-- Un click en cualquier otro sitio rompe la cadena del doble click.
	self.lastClickName, self.lastClickAt = nil, nil

	-- Clicking something that is NOT ours -- an enemy, an NPC -- leaves the
	-- selection alone rather than clearing it. Only bare ground clears.
	--
	-- Nothing else happens here, and the nothing is the point. This used to call
	-- TargetUnit(hover.name), which threw "blocked from an action only available
	-- to the Blizzard UI" on every click: TargetUnit is protected in 3.3.5a and
	-- an addon may not call it for an arbitrary unit, ever.
	--
	-- It was also redundant, which is the more useful half of the lesson. Once
	-- the mouse stopped being captured (see below), the client sees this click
	-- itself and does its own targeting -- against real model geometry, exactly
	-- as it does outside RTS mode. We were asking for something that had already
	-- happened. The workaround for a captured mouse outlived the capture.
	if hover then return end

	if not shift then ns.Selection:Clear() end
end

function R:OnLeftDrag(x1, y1, x2, y2, shift)
	local names = self:UnitsInBox(x1, y1, x2, y2)
	if #names == 0 and not shift then
		ns.Selection:Clear()
		return
	end
	if shift then
		for _, n in ipairs(names) do ns.Selection:Add(n) end
	else
		ns.Selection:Set(names)
	end
end

-- Right-click means three different things depending on what is under it:
-- an enemy is an attack order, a friendly NPC is an interaction, and bare
-- ground is a move.
function R:OnRightClick(sx, sy, hover)
	if ns.Selection:IsEmpty() then return end

	local x, y, z = ns.Markers:CursorGroundPoint()

	-- The guid now comes from the client's own raycast rather than from
	-- projecting published positions and hoping something lands within 48
	-- pixels. It is exact, it costs nothing, and it works on anything the
	-- client can see -- not just the 32 units the DLL happens to be forwarding.
	--
	-- It is still sent UNDECIDED. Knowing WHAT is under the cursor is a client
	-- job; deciding what an order against it means -- and where each bot has to
	-- stand to carry it out -- is a server job, and the server is the only side
	-- with the positions to do it exactly.
	-- Dead units are sent too. They used to be filtered out here, on the
	-- assumption that a corpse could only ever be a failed attack -- which is
	-- exactly why looting did nothing in RTS mode: the guid never left the
	-- client, so the server never got the chance to say "that is a corpse you
	-- may loot". Classifying is the server's job; withholding the guid took
	-- that job away from it.
	local guid = (hover and not hover.ours and hover.guid) or "0"

	-- Sin mouseover, tirar de la proyeccion. Hace falta para los CADAVERES:
	-- con la camara poseida el cliente calcula sus interacciones contra la
	-- camara y no contra ti, asi que a veces no llega a marcar mouseover sobre
	-- un muerto -- y sin guid el servidor no puede decir "eso es un cadaver que
	-- puedes lootear". La proyeccion es menos precisa pero no depende de la
	-- posesion, asi que cubre justo el hueco.
	if guid == "0" then
		local near = self:NearestCreature(sx, sy)
		local r = self.hostilePickRadius
		if near then
			local _, d = self:NearestCreature(sx, sy)
			if d and d <= r * r then guid = near.guid end
		end
	end

	if ns.Orders:HasServer() and x then
		ns.Orders:Click(guid, x, y, z)
		return
	end

	-- No server module: fall back to what the client alone can manage.
	if hover and hover.hostile then
		ns.Orders:AttackGuid(hover.guid, hover.name)
		return
	end
	if x then self:MoveSelectionTo(x, y, z) end
end

-- Attack-move: advance on a point, engaging what you meet.
function R:AttackMoveToCursor()
	local x, y, z = ns.Markers:CursorGroundPoint()
	if x then ns.Orders:AttackMoveTo(x, y, z) end
end

--- Mouse: free, always ------------------------------------------------------
--
-- The old model was a full-screen frame with EnableMouse(true) held on for the
-- whole of RTS mode. It got the two gestures WoW gives addons no hook for -- a
-- drag rectangle, and right-click-on-ground as an order -- and paid for them by
-- confiscating the mouse for everything else. No hover, no highlight, no
-- mouseover, no native picking.
--
-- Now the mouse is FREE, and stays free -- including during a drag. The world
-- gets every event, so hovering highlights units exactly as it does in normal
-- play, and the client's own click targeting works because it is the client
-- doing it.
--
-- Two consequences worth naming:
--   * right-drag needs no special handling any more. The client turns the
--     camera itself, because we are no longer intercepting it. The old
--     MouselookStart dance is gone.
--   * mouseover is still snapshotted at MOUSE-DOWN and carried through to the
--     release. It is cheap, and a cursor that has travelled across the screen
--     during a drag is no longer over what the press was aimed at.

--
-- === why the box never appeared ==========================================
--
-- The drag rectangle was written, wired up and correct, and it did not draw a
-- single pixel in game -- the camera just orbited instead. The threshold it
-- waited on could never be crossed, for a reason that has nothing to do with
-- the box:
--
--     pressing the left button in the world puts the client into MOUSELOOK,
--     which hides the cursor and PINS IT IN PLACE.
--
-- GetCursorPosition() then returns the same two numbers no matter how far the
-- mouse physically travels. So `moved > CLICK_SLOP` was being measured against
-- a value frozen by definition: always 0, never a drag, and the client did what
-- it always does with a held left button -- turn the camera.
--
-- The fix is to detect the drag by its EFFECT rather than by the cursor. While
-- mouselook owns the mouse, moving it turns the camera, and rts_core publishes
-- the camera's forward vector every tick. A moving mouse shows up there on the
-- first frame; a press going nowhere never disturbs it. Once we know it is a
-- drag we call MouselookStop(), the cursor comes back at the point the press
-- started -- exactly the corner the box wants -- and tracks normally from there.
--
-- Detection has to be by effect and not by a timer, because a timer long enough
-- to be sure would be long enough to feel. The timer is kept only as the
-- fallback for a client with no DLL injected, where there is no camera vector
-- to watch.
--
-- Note what is NOT done: the mouse is never captured, not even mid-drag. The
-- old code escalated to EnableMouse(true) once a drag started, to be sure of
-- receiving the release. That is unnecessary -- the release is polled for
-- below -- and capturing would cost the hover highlight for the duration.

local catcher, box
local down = {}

-- How far the camera's forward vector may drift before this counts as a drag.
--
-- RAISED 2026-08-18, from 0.0015 -- about a twelfth of a degree. That number was
-- picked so it would "trip immediately on a drag", and it did. It also tripped
-- on everything else, because the RTS camera is driven by the SERVER and keeps
-- settling for a moment after you stop panning. Any click landing in that
-- settling window was filed as a camera turn and thrown away, and three separate
-- bug reports came out of it:
--
--   * a right click on the ground fired no order at all -- and always the FIRST
--     one, because the first click is the one that follows a camera move
--   * a left click on bare ground never reached Clear(), so the selection
--     circles looked as though they would not switch off
--   * and a swallowed click never reaches OnLeftClick, so it never resets the
--     double-click chain either: click a bot, have the ground click after it
--     swallowed, click the same bot again, and the two SURVIVING clicks read as
--     a double click and selected everyone
--
-- One bug wearing three faces. It is also the lesson ORBIT_SLOP already carries
-- for the cursor a few lines up: a threshold for "you meant to drag" has to sit
-- well clear of hand tremor, not merely above zero. The cursor got that lesson
-- in an earlier round; the camera never did.
--
-- Tunable live, because it CANNOT honestly be a constant: the camera swing a
-- given hand movement produces scales with mouse DPI and with the client's look
-- sensitivity, so the right value is not the same on two machines. `/rts turn`
-- prints what each click actually measured -- set it from that rather than from
-- anybody's estimate, this default included.
local FWD_EPS_DEFAULT = 0.05      -- ~3 degrees of camera swing

R.turnEps = FWD_EPS_DEFAULT
R.turnDebug = false

-- Fallback only, for when rts_core is not injected and there is no camera to
-- watch: a press held longer than this is a drag whatever the mouse did.
local HOLD_TO_DRAG = 0.15

local function CamFwd()
    if not RTS_CamFwdX then return nil end
    return RTS_CamFwdX, RTS_CamFwdY, RTS_CamFwdZ
end

local function ReleaseCapture()
    if catcher and catcher:IsMouseEnabled() then catcher:EnableMouse(false) end
    if box then box:Hide() end
end

local function BeginGesture(button)
    local sx, sy = CursorXY()
    down.x, down.y, down.button = sx, sy, button
    down.dragging = false
    down.turned = false
    down.at = GetTime()
    -- Did WE get this press, or did the client? Decides how the drag is
    -- measured further down: our own capture leaves the cursor alone, the
    -- client's freezes it.
    down.captured = catcher and catcher:IsMouseEnabled() or false
    down.fx, down.fy, down.fz = CamFwd()
    down.drift = 0
    -- Snapshot now, while the client still owns the mouse.
    down.hover = R:HoverUnit()
end

-- Has the CAMERA moved since the button went down?
--
-- This is the question that replaced "has the cursor moved", and it is the only
-- one that can be answered while a button is held: the client freezes the cursor
-- for the whole of a camera drag, so the cursor says "no" no matter what the
-- hand does. The camera vector, which rts_core publishes every tick, says yes on
-- the first frame of real movement.
-- How far it has drifted since the press, or nil when there is no camera to
-- compare against. Split out from the decision below so the number can be shown
-- as well as judged: the threshold is machine-dependent, and the only honest way
-- to choose it is to look at what real clicks and real drags actually produce.
local function CamDrift()
    local fx, fy, fz = CamFwd()
    if not fx or not down.fx then return nil end
    return math.abs(fx - down.fx) + math.abs(fy - down.fy)
         + math.abs(fz - down.fz)
end

local function CameraTurned()
    local d = CamDrift()
    if not d then return false end
    -- Latch the peak for the report. It has to be the peak and not the value at
    -- release: by the time the button comes up the camera has usually settled
    -- back, so reading it then would under-report every drag.
    if d > (down.drift or 0) then down.drift = d end
    return d > R.turnEps
end

-- Has this press turned into a drag? The hold timer is the fallback for a
-- client with no DLL injected, where CameraTurned can never answer.
local function BecameDrag()
    if CameraTurned() then return true end
    return down.at ~= nil and (GetTime() - down.at) > HOLD_TO_DRAG
end

-- What this click measured, and what that got it. Off by default; `/rts turn`
-- switches it on.
--
-- This exists because the threshold above is the kind of number that cannot be
-- reasoned to, only measured -- and because the failure it guards is SILENT.
-- A swallowed click looks exactly like a click on nothing: no order, no error,
-- no message. That is precisely why it took three separate bug reports to
-- notice it was one bug, so the diagnostic prints the swallowed case loudest.
local function ReportGesture(button, verdict)
    if not R.turnDebug then return end
    local d = down.drift or 0
    ns.Print(("|cff88ccff%s|r  giro=%.4f  umbral=%.4f  -> %s"):format(
        button == "LeftButton" and "izq" or "der", d, R.turnEps, verdict))
end

local function EndGesture(button)
    if down.button ~= button then return end

    local sx, sy = CursorXY()
    local moved = math.abs(sx - down.x) + math.abs(sy - down.y)
    local shift = IsShiftKeyDown()
    local hover = down.hover

    if button == "LeftButton" then
        -- Two ways to tell a drag, because there are two ways the press can
        -- arrive.
        --
        -- CAPTURED (Ctrl held): the catcher ate the press, the client never
        -- started a camera turn, the cursor moves normally -- so the cursor is
        -- the honest measure and the box is exact.
        --
        -- NOT CAPTURED: the client owns the button and has frozen the cursor,
        -- so only the camera can say anything moved. That path can no longer
        -- draw a box at all (see the note on Ctrl above); it is kept so a drag
        -- is still recognised as "not a click" and does not fire an order.
        local isDrag
        if down.captured then
            isDrag = moved > CLICK_SLOP
        else
            isDrag = down.dragging and moved > CLICK_SLOP
        end

        if isDrag then
            ReportGesture(button, "CAJA")
            R:OnLeftDrag(down.x, down.y, sx, sy, shift)
        elseif down.captured or not down.turned then
            ReportGesture(button, "click")
            R:OnLeftClick(sx, sy, shift, IsAltKeyDown(), hover)
        else
            ReportGesture(button, "|cffff0000TRAGADO|r (giro de camara)")
        end
        -- Si no, fue un GIRO DE CAMARA con el izquierdo (sin Ctrl) y no es ni
        -- arrastre ni click. Antes caia en el else y se leia como "click en
        -- suelo vacio", que borra la seleccion: girabas la camara y perdias a
        -- los bots. Es el mismo fallo que tenia el boton derecho, y se arregla
        -- igual: preguntando si se movio la CAMARA, no el cursor.
    elseif button == "RightButton" then
        -- Was the camera turned, or was this a click?
        --
        -- NOT `moved <= ORBIT_SLOP`. That measured the CURSOR, and while the
        -- client is turning the camera the cursor is frozen -- so `moved` was
        -- always 0, always under the threshold, and every camera orbit fired a
        -- move order at whatever the cursor happened to be over when the button
        -- went down. Reported as "giro la camara y al soltar los bots se van".
        --
        -- Same mistake the left button had, and the same fix: ask whether the
        -- CAMERA moved, which is the thing that actually changes during a drag.
        if not down.turned then
            ReportGesture(button, "orden")
            R:OnRightClick(sx, sy, hover)
        else
            ReportGesture(button, "|cffff0000TRAGADO|r (giro de camara)")
        end
    end

    down.button, down.hover, down.dragging, down.turned = nil, nil, false, false
    ReleaseCapture()
end

local function EnsureFrames()
    if catcher then return end

    catcher = CreateFrame("Frame", "RTSModeCatcher", UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("LOW")
    catcher:EnableMouse(false)          -- free unless a box is being drawn
    catcher:Hide()

    box = CreateFrame("Frame", nil, catcher)
    box:SetFrameStrata("MEDIUM")
    box:Hide()
    box.tex = box:CreateTexture(nil, "OVERLAY")
    box.tex:SetAllPoints()
    box.tex:SetTexture(0.2, 1, 0.3, 0.12)

    -- A safety net, nothing more. The catcher is never given the mouse now, so
    -- in practice this does not fire -- the release arrives either through
    -- WorldFrame below or through the poll in OnUpdate. It costs nothing and it
    -- covers the case where some other frame ends up owning the button.
    -- With Ctrl held the catcher owns the mouse, so the press lands here
    -- rather than on WorldFrame. This is the path that makes the box possible.
    catcher:SetScript("OnMouseDown", function(_, button) BeginGesture(button) end)
    catcher:SetScript("OnMouseUp", function(_, button) EndGesture(button) end)

    -- HookScript, not SetScript: WorldFrame's own mouse handling is what drives
    -- camera look and the client's unit clicks, and replacing it would break
    -- both. We only want to observe.
    WorldFrame:HookScript("OnMouseDown", function(_, button)
        if R.active then BeginGesture(button) end
    end)
    WorldFrame:HookScript("OnMouseUp", function(_, button)
        if R.active then EndGesture(button) end
    end)

    catcher:SetScript("OnUpdate", function()
        -- CTRL ARMS THE BOX.
        --
        -- The client takes the mouse the instant the left button goes down in
        -- the world and turns the camera with it, freezing the cursor. Nothing
        -- in Lua can take that back afterwards: MouselookStop only stops a
        -- mouselook an ADDON started, and IsMouselooking is false for the
        -- client's own button-drag, which is why the previous attempt at this
        -- changed nothing at all.
        --
        -- The only way to have the box is to own the mouse BEFORE the press.
        -- Holding Ctrl does that, and only for as long as it is held -- so
        -- hover, highlight, native picking and looting are untouched the rest
        -- of the time, which was the whole point of freeing the mouse.
        if not down.button then
            local want = IsControlKeyDown() and R.active
            if want ~= catcher:IsMouseEnabled() then catcher:EnableMouse(want) end
        end

        if not down.button then
            if box:IsShown() then box:Hide() end
            return
        end

        -- Tracked for BOTH buttons, before the left-only work below. The right
        -- button needs it to tell an orbit from an order, and it has to be
        -- latched while the button is still down -- by the time the release
        -- arrives, the camera has stopped moving and the evidence is gone.
        if not down.turned and CameraTurned() then down.turned = true end

        if down.button ~= "LeftButton" then return end

        -- Poll for the release instead of waiting on a handler. During
        -- mouselook the button is held by the client rather than by any frame,
        -- so there is no guarantee an OnMouseUp reaches us at all -- and a
        -- missed release would leave a box on screen forever.
        if not IsMouseButtonDown("LeftButton") then
            EndGesture("LeftButton")
            return
        end

        if not down.dragging then
            if not BecameDrag() then return end
            down.dragging = true
        end

        -- Give the mouse back, and keep giving it back: the client re-arms
        -- mouselook while the button is still down, and checking every frame is
        -- cheaper than working out exactly when it decides to.
        if IsMouselooking() then MouselookStop() end

        local sx, sy = CursorXY()
        if math.abs(sx - down.x) + math.abs(sy - down.y) <= CLICK_SLOP then
            box:Hide()
            return
        end

        box:ClearAllPoints()
        box:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
            math.min(down.x, sx), math.min(down.y, sy))
        box:SetWidth(math.abs(sx - down.x))
        box:SetHeight(math.abs(sy - down.y))
        box:Show()
    end)
end



--- Botin libre --------------------------------------------------------------
--
-- "Que pueda lootear siempre" es, literalmente, el metodo de botin FREE_FOR_ALL
-- del grupo. En Player::isAllowedToLoot (PlayerStorage.cpp:5762) el switch por
-- metodo de botin tiene esta linea:
--
--     case MASTER_LOOT: case FREE_FOR_ALL: return true;
--
-- y con GROUP_LOOT, que es el de por defecto, solo puedes lootear si eres el
-- del turno rotatorio o el objeto pasa del umbral. Con bots matando cosas, ese
-- turno rara vez te toca -- de ahi que el cadaver estuviera ahi y no se dejara
-- abrir.
--
-- Se pone desde el cliente porque es una propiedad del GRUPO y ya existe la
-- llamada; no hace falta tocar el servidor para nada. Requiere ser lider.
R.freeLoot = true

function R:ApplyFreeLoot(quiet)
    if not self.freeLoot then return end
    if GetNumPartyMembers() == 0 then return end          -- solo, no hay metodo
    if not IsPartyLeader() then
        if not quiet then
            ns.Print("|cffffff00Botin libre:|r hay que ser lider del grupo.")
        end
        return
    end
    if GetLootMethod() == "freeforall" then return end
    SetLootMethod("freeforall")
    if not quiet then ns.Print("botin |cff00ff00libre|r - puedes lootear todo.") end
end

function R:ToggleFreeLoot()
    self.freeLoot = not self.freeLoot
    RTSCommandDB.freeLoot = self.freeLoot
    if self.freeLoot then
        self:ApplyFreeLoot()
    elseif IsPartyLeader() and GetNumPartyMembers() > 0 then
        SetLootMethod("group")
        ns.Print("botin de vuelta a |cffff0000grupo|r (el normal).")
    end
    ns.Print("botin libre automatico: " ..
        (self.freeLoot and "|cff00ff00SI|r" or "|cffff0000NO|r"))
end

--- Selfbot: que tu propio personaje pelee como uno mas ----------------------
--
-- mod-playerbots puede engancharle a TU personaje el mismo PlayerbotAI que
-- lleva cualquier bot (PlayerbotMgr.cpp:1071). No es una imitacion: es el mismo
-- objeto, asi que pasa por el mismo ResetStrategies y AiFactory elige la
-- rotacion segun tu arbol de talentos, igual que con los demas.
--
-- El comando es ".playerbots BOT self". El "bot" de en medio no es opcional:
-- self es un subcomando de HandlePlayerbotCommand, que cuelga de "bot" en la
-- tabla de comandos (PlayerbotCommandScript.cpp:36). Sin el salia la lista de
-- ayuda amarilla y no pasaba nada.
--
-- Va por comando de chat y no por mod-rts a proposito. El comando ya existe y
-- lo mantiene playerbots; replicarlo en nuestro modulo obligaria a enlazar
-- mod-rts contra las cabeceras de playerbots, y ataria dos modulos que hoy no
-- se conocen -- por un interruptor.
--
-- LA PEGA, y conviene saberla: el comando es un TOGGLE y no devuelve el estado,
-- asi que aqui se lleva la cuenta a mano. Si se desincroniza (por ejemplo si lo
-- lanzas tu por tu cuenta), /rts self lo vuelve a alinear.
R.selfBot = { auto = true, on = false }

local function SelfBotCommand()
    SendChatMessage(".playerbots bot self", "SAY")
end

-- want = true encender, false apagar. No hace nada si ya cree estar asi.
-- Que TU personaje no recoja solo, aunque los bots si.
--
-- "el mio recoge sin la UI, cosa que no me gusta". Es la estrategia "loot" que
-- playerbots le pone por defecto a todo el que lleve su IA -- y con el selfbot
-- puesto, eso te incluye. Recoge en silencio y nunca ves la ventana.
--
-- Se le quita SOLO A TI, por susurro. Un susurro a un bot ejecuta el comando en
-- ESE bot nada mas (PlayerbotAI.cpp:582), y susurrarte a ti mismo llega a tu
-- propia IA -- asi que los bots siguen recogiendo, que es como elegiste
-- dejarlo, y tu looteas a mano y con ventana.
--
-- No estorba al loot manual: el click derecho va por mod-rts y acaba en
-- SendLoot del servidor, que no sabe nada de estrategias.
local function SelfLootStrategy(on)
    SendChatMessage(on and "nc +loot,+gather" or "nc -loot,-gather",
                    "WHISPER", nil, UnitName("player"))
end

function R:SelfBotSet(want, quiet)
    if self.selfBot.on == want then return end
    SelfBotCommand()
    self.selfBot.on = want

    -- Despues de encender: la IA acaba de nacer con sus estrategias por
    -- defecto puestas, asi que hay que quitarle el loot ahora, no antes.
    SelfLootStrategy(not want)
    if not quiet then
        ns.Print("selfbot " .. (want and "|cff00ff00ON|r - tu personaje pelea solo"
                                     or "|cffff0000OFF|r - vuelves a llevarlo tu"))
    end
end

function R:SelfBotToggle()
    self:SelfBotSet(not self.selfBot.on)
end

function R:SelfBotAuto()
    self.selfBot.auto = not self.selfBot.auto
    RTSCommandDB.selfBotAuto = self.selfBot.auto
    ns.Print("selfbot automatico al entrar en modo RTS: " ..
        (self.selfBot.auto and "|cff00ff00SI|r" or "|cffff0000NO|r"))
end

function R:SelfBotStatus()
    ns.Print(("selfbot: %s   automatico: %s"):format(
        self.selfBot.on and "|cff00ff00encendido|r" or "|cffff0000apagado|r",
        self.selfBot.auto and "si" or "no"))
    ns.Print("Se lleva la cuenta a mano porque el comando no devuelve estado.")
    ns.Print("Si no cuadra con lo que ves, |cffffff00/rts self|r lo realinea.")
end

--- Toggle ------------------------------------------------------------------

-- RTS mode is ONE switch, not a set of things to remember to turn on.
-- Toggling it brings up the mouse layer AND the detached camera, and drops both
-- again on the way out. Anything else the mode needs belongs here too.
function R:Toggle()
	EnsureFrames()
	self.active = not self.active

	if self.active then
		catcher:Show()
		catcher:EnableMouse(false)
		ns.Camera:On()
		ns.Print("|cff00ff00Modo RTS ON|r - el raton va normal: pasar por encima ilumina,")
		ns.Print("click selecciona, |cffffff00doble click|r selecciona a todos, click derecho ordena.")
		ns.Print("|cffffff00Ctrl + arrastrar|r = caja de seleccion.")

		-- SIN DLL EL MODO RTS SE DEGRADA EN SILENCIO, Y ESO COSTO UNA SESION
		-- ENTERA. Un rts_core que no entra no da ningun error: la caja se
		-- dibuja (es Lua pura) pero no coge nada, porque decidir que unidad cae
		-- dentro necesita proyectar mundo->pantalla; los halos no salen; y
		-- mover/atacar se quedan sin coordenadas. Se lee como tres fallos
		-- distintos y no lo es. Asi que el modo RTS ya no arranca callado.
		ns.Bridge:TryAttach()
		if not ns.Bridge:IsNative() then
			ns.Print("|cffff0000rts_core.dll NO esta inyectado.|r Sin el:")
			ns.Print("  - la caja se dibuja pero |cffff0000no selecciona nada|r")
			ns.Print("  - |cffff0000no hay halos|r")
			ns.Print("  - |cffff0000mover y atacar al suelo no funcionan|r (siguen valiendo follow/stay/attack)")
			ns.Print("  Arreglo: cierra el WoW y abrelo con |cffffff00C:\\Server\\rts-tools\\Jugar.bat|r")
		end
		if self.selfBot.auto then self:SelfBotSet(true, true) end
		self:ApplyFreeLoot(true)
	else
		catcher:Hide()
		ReleaseCapture()
		down.button = nil
		-- Leaving mid-drag would strand the client outside mouselook with the
		-- button still held. Same rule as the CVars: RTS mode only affects RTS
		-- mode, and that includes how it ends.
		if IsMouselooking() then MouselookStop() end
		-- Drop any borrowed bar before the camera goes.
		ns.CommandMode:Leave()
		-- Devolver el personaje ANTES de soltar la camara, para que no quede un
		-- instante en el que la IA lo lleva y tu ya has vuelto a el.
		self:SelfBotSet(false, true)
		ns.Camera:Off()
		ns.Print("|cffff0000RTS mode OFF|r - normal controls.")
	end
end

function R:IsActive()
	return self.active
end

--- Picking diagnostics -----------------------------------------------------
-- Added after "right-click does nothing" turned out to have four possible
-- causes and guessing between them cost several test cycles.

function R:PickReport()
	local mx, my = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	local sx, sy = mx / scale, my / scale

	ns.Print(("cursor %.0f,%.0f   screen %.0fx%.0f   RTS mode %s"):format(
		sx, sy, GetScreenWidth(), GetScreenHeight(),
		self.active and "|cff00ff00ON|r" or "OFF"))

	ns.Print(("mouseover: %s"):format(UnitExists("mouseover")
		and (UnitName("mouseover") .. "  hostile=" .. tostring(UnitCanAttack("player", "mouseover")))
		or "|cffff0000none|r (the catcher frame hides it in RTS mode)"))

	local n = 0
	for i = 1, math.min(RTS_UN or 0, ns.MAX_UNITS) do
		if _G["RTS_U" .. i .. "T"] == 3 then n = n + 1 end
	end

	-- The important number: how far the NEAREST creature projected, whether or
	-- not it was inside the pick radius.
	local best, bestD = self:NearestCreature(sx, sy)
	if best then
		local d = math.sqrt(bestD)
		ns.Print(("nearest creature: %s at screen %.0f,%.0f -- |cffffff00%.0f px|r away (radius %d)")
			:format(tostring(best.guid), best.sx, best.sy, d, self.hostilePickRadius))
		ns.Print(d <= self.hostilePickRadius
			and "  |cff00ff00inside the radius: this click would pick it|r"
			or  "  |cffff0000outside the radius|r - widen with /rts pickradius <px>, or the projection is off")
	else
		ns.Print(("nearest creature: |cffff0000none projected|r (%d creatures published)"):format(n))
	end

	local gx, gy, gz = ns.Markers:CursorGroundPoint()
	ns.Print(("ground point: %s   creatures published: %d"):format(
		gx and ("%.1f, %.1f, %.1f"):format(gx, gy, gz) or "|cffff0000none|r", n))
end

local liveFrame
function R:LivePick(on)
	if on then
		if not liveFrame then
			liveFrame = CreateFrame("Frame")
			local acc = 0
			liveFrame:SetScript("OnUpdate", function(_, e)
				acc = acc + e
				if acc < 0.7 then return end
				acc = 0
				R:PickReport()
			end)
		end
		liveFrame:Show()
		ns.Print("|cff00ff00live pick ON|r - hover something. |cffffff00/rts pick off|r to stop.")
	elseif liveFrame then
		liveFrame:Hide()
		ns.Print("|cffff0000live pick OFF|r")
	end
end
