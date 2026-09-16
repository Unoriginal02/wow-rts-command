--[[
	Orders.lua -- the verbs.

	Every order is a mod-playerbots chat command. Commands whispered to a bot
	are handled by that bot alone; commands sent to PARTY/RAID are handled by
	all of them (PlayerbotAI.cpp:582). So:

	  selection == whole roster  ->  one PARTY message  (cheap, atomic)
	  otherwise                  ->  one whisper per selected unit

	Outgoing chat is queued and spaced. Firing four whispers inside one frame
	trips the client's own chat throttle and some just vanish -- which looks
	exactly like "the bots ignored my order".

	Commands used here are all verified against the module source:
	  go <name>       GoAction.cpp        -- walk to a named nearby friendly
	  go X;Y;Z        GoAction.cpp:113    -- walk to world coords (needs DLL)
	  stay/follow/    ChatCommandHandlerStrategy.cpp
	  attack/flee/
	  pull/cast/...
	  formation <n>   Formations.cpp
]]

local ADDON, ns = ...

local O = {}
ns.Orders = O

--- Outgoing chat queue -----------------------------------------------------

local queue = {}
local INTERVAL = 0.15
local elapsed = 0

local pump = CreateFrame("Frame")
pump:Hide()
pump:SetScript("OnUpdate", function(self, e)
	elapsed = elapsed + e
	if elapsed < INTERVAL then return end
	elapsed = 0

	local m = tremove(queue, 1)
	if not m then
		self:Hide()
		return
	end

	SendChatMessage(m.text, m.channel, nil, m.target)
end)

local function Enqueue(text, channel, target)
	tinsert(queue, { text = text, channel = channel, target = target })
	if not pump:IsShown() then
		elapsed = INTERVAL   -- let the first one go out on the next frame
		pump:Show()
	end
end

--- Dispatch ----------------------------------------------------------------

local function GroupChannel()
	if GetNumRaidMembers() > 0 then return "RAID" end
	if GetNumPartyMembers() > 0 then return "PARTY" end
	return nil
end

-- Every order goes out through SendTo / Send / Broadcast, so telling the state
-- machine here covers the command card, the key bindings, the RTS mouse handler
-- and `/rts cmd <anything>` at once -- and covers any order added later without
-- that call site having to remember. See State.lua.

-- Send a raw command to one named unit (used by RTS click orders).
function O:SendTo(name, command)
	ns.UnitState:Note(name, command)
	Enqueue(command, "WHISPER", name)
end

-- Send to everyone currently selected.
function O:Send(command, label)
	local sel = ns.Selection:Get()
	if #sel == 0 then
		ns.Print("No units selected.")
		return false
	end

	local roster = ns.Selection:GetRoster()
	local channel = GroupChannel()

	-- Tag every selected unit, whichever way the command actually travels: one
	-- party message and N whispers mean the same thing to the recipients.
	for _, name in ipairs(sel) do ns.UnitState:Note(name, command) end

	if channel and #sel == #roster and #roster > 1 then
		Enqueue(command, channel)
	else
		for _, name in ipairs(sel) do
			Enqueue(command, "WHISPER", name)
		end
	end

	if label then
		ns.Print(("%s (%d unit%s)"):format(label, #sel, #sel == 1 and "" or "s"))
	end
	return true
end

-- Send to the whole group regardless of selection. For orders that are
-- inherently group-wide, like formation.
function O:Broadcast(command, label)
	local channel = GroupChannel()
	if not channel then
		ns.Print("Not in a group.")
		return false
	end

	-- Broadcast ignores the selection, so the whole roster gets the state.
	for _, m in ipairs(ns.Selection:GetRoster()) do
		ns.UnitState:Note(m.name, command)
	end

	Enqueue(command, channel)
	if label then ns.Print(label) end
	return true
end

--- Movement ----------------------------------------------------------------

-- Rally: bots path to your character.
--
-- With the native bridge we send exact world coordinates, which puts bots ON
-- the spot. Without it we fall back to "go <name>", which name-matches
-- server-side but routes through MoveNear -- bots stop a follow-distance short.
-- Good enough to play with, not precise enough to build formations from.
function O:MoveToMe()
	local x, y, z = ns.Bridge:GetPlayerWorldPosition()
	if x then
		return self:MoveTo(x, y, z)
	end
	-- No DLL: name-matched rally, which routes through MoveNear and stops a
	-- follow-distance short. Cannot be anchored, so they will drift home.
	return self:Send("go " .. ns.MyName(), "Move to my position")
end

-- Move order from the command card / hotkey.
--
-- Once the DLL implements cursor->world picking this becomes true click-to-move.
-- Until then it rallies to your position -- with exact coordinates when the
-- native bridge is up, so the bot lands on your spot, not a follow-distance off.
function O:MoveToCursor()
	local x, y, z = ns.Bridge:GetCursorWorldPosition()
	if x then
		return self:MoveTo(x, y, z)
	end
	return self:MoveToMe()
end

--- RTS move: go there AND STAY there ---------------------------------------
--
-- `go X;Y;Z` is a one-shot MoveTo (GoAction.cpp:161). The moment it finishes,
-- the bot's normal strategy resumes and follow drags it straight back to you.
-- That is the "they walk there and then run home" problem, and no amount of
-- re-issuing `go` fixes it -- the bot is doing what it was told, then doing
-- what it always does.
--
-- The bot's OWN stay machinery is the answer. `stay` switches on StayStrategy,
-- which pins the bot to posMap["stay"] and walks it back whenever it drifts
-- (StayStrategy.cpp:15 -> ReturnToStayPositionAction). `position stay X,Y,Z`
-- then moves that pin. So rather than ordering a walk, we move the anchor and
-- let the bot's own "return to stay position" behaviour do the walking. The
-- destination becomes where it WANTS to be, so nothing pulls it home.
--
-- Two limits, both out of MoveToPositionAction::isUseful():
--   * it only walks when further than FollowDistance (1.5y) from the anchor
--   * it will not walk further than ReactDistance (150y), so a longer hop gets
--     an explicit `go` as well to close the gap
-- and `position` parses coordinates with atoi, so the anchor is whole yards.

O.holding = {}   -- unit name -> true once that bot is in stay mode

local REACT_LIMIT = 140   -- under ReactDistance 150, with room for drift

-- World position of a unit by name, via the DLL's published list.
local function UnitPos(name)
	local unit = ns.Selection:UnitFor(name)
	local guid = unit and UnitGUID(unit)
	if not guid or not ns.Markers then return nil end
	return ns.Markers:UnitWorld(guid)
end

-- True when mod-rts is present to take orders directly. Set by the first reply
-- the server sends us; until then everything falls back to chat commands.
--
-- `Link` KNOWS IT, NOT THIS FILE, since 2026-09-02: it is a fact about the
-- channel, not about the orders. The name stays because it is the one thirteen
-- places read, and because "is there a server to give orders to" is the question
-- asked from here.
--
-- And it is still a PROMISE during the first second: anyone who needs to act as
-- soon as there is a server uses `ns.Link:WhenServer(fn)`, not a loop of their
-- own.
function O:HasServer()
	return ns.Link:HasServer()
end

-- Order one named bot to hold a specific spot, the chat way.
--
-- Kept as the fallback for a server without mod-rts. It costs an emote (both
-- `stay` and `position` reply, and PlayerbotAI::TellMaster turns the bot to
-- face you and plays EMOTE_ONESHOT_TALK first), a queue slot per message, and
-- whole-yard precision because `position` parses with atoi.
function O:MoveUnitToViaChat(name, x, y, z)
	if not self.holding[name] then
		self:SendTo(name, "stay")
		self.holding[name] = true
	end

	-- Beyond react distance the anchor alone will not move it, so close the
	-- distance explicitly; the anchor takes over once it arrives.
	local ux, uy = UnitPos(name)
	if ux then
		local d = math.sqrt((ux - x) ^ 2 + (uy - y) ^ 2)
		if d > REACT_LIMIT then
			self:SendTo(name, ("go %.2f;%.2f;%.2f"):format(x, y, z))
		end
	end

	self:SendTo(name, ("position stay %d,%d,%d")
		:format(math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)))
end

function O:MoveUnitTo(name, x, y, z)
	if self:HasServer() then
		-- Batched by MoveTo/MoveSelectionTo; this single-unit path is only for
		-- callers that really do mean one bot.
		ns.SendServer(("MOVE %s %.2f %.2f %.2f"):format(name, x, y, z))
		ns.UnitState:Note(name, "position")
		self.holding[name] = true
		return
	end
	self:MoveUnitToViaChat(name, x, y, z)
end

-- Order a whole list of {name, x, y, z} at once. One packet, so every bot turns
-- on the same frame instead of trickling out of the chat queue over a second.
function O:MoveBatch(list)
	if not self:HasServer() then
		for _, e in ipairs(list) do self:MoveUnitToViaChat(e[1], e[2], e[3], e[4]) end
		return
	end

	-- Addon messages cap at 255 characters, so long groups go in chunks rather
	-- than being silently truncated.
	local parts, len = {}, 0
	local function flush()
		if #parts > 0 then
			ns.SendServer("MOVE " .. table.concat(parts, ";"))
			parts, len = {}, 0
		end
	end

	for _, e in ipairs(list) do
		local s = ("%s %.2f %.2f %.2f"):format(e[1], e[2], e[3], e[4])
		if len + #s + 6 > 240 then flush() end
		tinsert(parts, s)
		len = len + #s + 1
		ns.UnitState:Note(e[1], "position")
		self.holding[e[1]] = true
	end
	flush()
end

-- Fan a group out around the click point so an order does not pile every bot
-- onto one coordinate.
--
-- A ring was the first attempt and it reads badly for small groups: three units
-- on a circle look scattered rather than arranged, and there is no front. A
-- staggered block facing the way they are travelling looks deliberate, keeps
-- whoever is listed first at the front, and grows sensibly.
--
-- `facing` is the direction of travel in radians; without it the block is laid
-- out along the world axes, which is still better than a ring.
O.spacing = 2.4      -- yards between neighbours
O.rowsFirst = 3      -- units per rank before starting another

function O:SpreadOffsets(n, facing)
	if n <= 1 then return { { 0, 0 } } end

	local perRow = math.min(self.rowsFirst, n)
	local rows = math.ceil(n / perRow)

	-- Rotate the block so its front faces the way the group is going.
	local c, s = 1, 0
	if facing then c, s = math.cos(facing), math.sin(facing) end

	local out = {}
	for i = 1, n do
		local row = math.floor((i - 1) / perRow)
		local col = (i - 1) % perRow

		-- Centre each rank, and put later ranks behind the first.
		local inRow = math.min(perRow, n - row * perRow)
		local across = (col - (inRow - 1) * 0.5) * self.spacing
		local back = -(row - (rows - 1) * 0.5) * self.spacing

		out[i] = { back * c - across * s, back * s + across * c }
	end
	return out
end

-- Direction from the selection's current centre to a destination, for orienting
-- the block. Nil when positions are unknown, and the caller falls back to the
-- world axes.
function O:FacingTo(x, y)
	local sx, sy, n = 0, 0, 0
	for _, name in ipairs(ns.Selection:Get()) do
		local ux, uy = UnitPos(name)
		if ux then sx, sy, n = sx + ux, sy + uy, n + 1 end
	end
	if n == 0 then return nil end
	local dx, dy = x - sx / n, y - sy / n
	if (dx * dx + dy * dy) < 1 then return nil end
	return math.atan2(dy, dx)
end

-- Move a NAMED list of units to a point, spread around it.
--
-- Takes the list rather than reading the selection, because two callers need
-- exactly that: the RTS right-click (which is the selection) and Route.lua
-- (which is whoever was selected when the route was drawn, and that is not the
-- same thing a few seconds later).
--
-- YOUR OWN CHARACTER goes in the list too, under its own name, and takes a slot
-- in the spread. It moves by a different route -- the server can only drive
-- your body while the RTS camera holds client control -- but that is exactly
-- when you are giving orders, so the distinction never shows.
function O:MoveGroupTo(names, x, y, z, quiet)
	if not names or #names == 0 then return false end

	local playerName = ns.MyName()
	local offsets = self:SpreadOffsets(#names, self:FacingTo(x, y))
	local batch, movedSelf = {}, false

	for i, name in ipairs(names) do
		local o = offsets[i]
		if name == playerName then
			self:MoveSelfTo(x + o[1], y + o[2], z)
			movedSelf = true
		else
			tinsert(batch, { name, x + o[1], y + o[2], z })
		end
	end

	if #batch > 0 then self:MoveBatch(batch) end
	ns.Flare:Show(x, y, z, "move")

	local total = #batch + (movedSelf and 1 or 0)
	if not quiet and total > 0 then
		ns.Print(("Move order -> %d unit%s"):format(total, total == 1 and "" or "s"))
	end
	return true
end

-- Move the whole selection to a point, spread around it.
function O:MoveTo(x, y, z)
	local sel = ns.Selection:Get()
	if #sel == 0 then
		ns.Print("No units selected.")
		return false
	end
	if ns.Route then ns.Route:ClearFor(sel) end
	return self:MoveGroupTo(sel, x, y, z)
end

-- Anything that hands control back to normal behaviour clears the hold flags,
-- so the next move order re-arms stay mode.
function O:ClearHolding()
	self.holding = {}
end

--- Your own character ------------------------------------------------------
-- Orderable like any other unit, but by a different route: the server can only
-- drive your body while something else holds client control -- the RTS camera.
-- That is precisely when you are giving orders, so in practice it always works
-- when it needs to and refuses with a clear message when it cannot.

function O:MoveSelfTo(x, y, z)
	if not self:HasServer() then
		ns.Print("|cffffff00Your character needs mod-rts to take orders.|r")
		return false
	end
	ns.SendServer(("SELFMOVE %.2f %.2f %.2f"):format(x, y, z))
	return true
end

--- Direct control ----------------------------------------------------------
-- Possession was removed 2026-08-15 in favour of borrowing a bot's action bar
-- without moving the camera or leaving RTS mode. That borrowing was a floating
-- panel and a mode of its own until 2026-08-24; it is now the console's skill
-- row (Skills.lua), driven by whoever is selected, with no mode to enter.
--
-- It came back on 2026-09-06 as `/rts play` and went for good on 2026-09-11:
-- *"your possession is weird, take it out"*. It never could be anything else --
-- possession changes who MOVES you, not who you ARE, so talking to an NPC went
-- through your own character, standing somewhere else, and failed on range.
-- This time the server half went with it, so there is nothing left to reach
-- for; the thing that does what it promised is `SWAP`.

--- Attack-move -------------------------------------------------------------
-- Advance to a point, engaging on the way. There is no attack-move verb in
-- playerbots, so the server approximates it with the destination anchor plus
-- `grind`. It can be distracted onto something off the path; the anchor is
-- what drags it back on.

function O:AttackMoveTo(x, y, z)
	local sel = ns.Selection:Get()
	if #sel == 0 then ns.Print("No units selected.") return false end

	if not self:HasServer() then
		ns.Print("|cffffff00Attack-move needs mod-rts.|r")
		return self:MoveTo(x, y, z)
	end

	local offsets = self:SpreadOffsets(#sel, self:FacingTo(x, y))
	local parts = {}
	for i, name in ipairs(sel) do
		local o = offsets[i]
		tinsert(parts, ("%s %.2f %.2f %.2f"):format(name, x + o[1], y + o[2], z))
		ns.UnitState:Note(name, "attack")
		self.holding[name] = true
	end

	-- The same '@' tail as the right-click: attack-move also comes out of the
	-- cursor, so the server cuts the ray against the real ground and shifts the
	-- destinations as a block. See Orders:Click.
	local ox, oy, oz, dx, dy, dz = ns.Markers:CursorRay()
	if ox then
		tinsert(parts, ("@ 0 %.2f %.2f %.2f %.5f %.5f %.5f %.2f %.2f %.2f")
			:format(ox, oy, oz, dx, dy, dz, x, y, z))
	end

	ns.SendServer("AMOVE " .. table.concat(parts, ";"))
	ns.Flare:Show(x, y, z, "attack")
	ns.Print(("Attack-move (%d unit%s)"):format(#sel, #sel == 1 and "" or "s"))
	return true
end

--- Interact ----------------------------------------------------------------
-- Right-clicking a friendly NPC. `talk` is a real playerbots verb (gossip hello
-- + talk to quest giver), so this one still goes through chat: it is rare, and
-- the talking emote that comes with a chat reply is thematically right here
-- rather than wrong.

function O:Talk()
	return self:Send("talk", "Interact")
end

-- WITH NO SELECTION, TO THE WHOLE GROUP -- and saying so.
--
-- It is what `/rtscmd` already did, which is how these two orders travelled
-- until today: with nobody held, the whisper turned into one line to the group.
-- Moving them onto the direct path meant bringing that rule along, or the key
-- would stop doing anything precisely when there is no selection, which is half
-- the times it gets used.
local function Targets(self)
	local sel = ns.Selection:Get()
	if #sel > 0 then return sel end

	local all = {}
	for _, m in ipairs(ns.Selection:GetRoster()) do tinsert(all, m.name) end
	if #all > 0 then
		ns.Print("|cffffff00no selection|r -> to the whole group:")
	end
	return all
end

-- Everyone still, wherever they are. `stay` pins the bot to the spot, which is
-- exactly hold-position, and it ALSO ends any route: "stay here" and "keep
-- walking the path" are opposite orders, and leaving the path drawn would say
-- the wrong one.
--
-- DIRECT SINCE mod-rts 0.52. It used to be a `stay` over chat: the bot did not
-- see it until its next think cycle, and four in a row got eaten by the client's
-- queue. The chat path stays as the fallback for a server without the module,
-- just as with move.
function O:Hold()
	local names = Targets(self)
	if #names == 0 then
		ns.Print("No units selected.")
		return false
	end

	if ns.Route then ns.Route:ClearFor(names) end
	for _, name in ipairs(names) do
		self.holding[name] = true
		ns.UnitState:Note(name, "stay")
	end

	if self:HasServer() and ns.Link:ServerAtLeast(52) then
		ns.SendServer("HOLD " .. table.concat(names, ";"))
		ns.Print(("Hold position (%d)"):format(#names))
		return true
	end

	return self:Send("stay", "Hold position")
end

-- BRING THEM TO YOUR SIDE. Playerbots' `summon` action, called from the inside.
function O:Summon(names)
	names = names or Targets(self)
	if #names == 0 then
		ns.Print("No units selected.")
		return false
	end

	if self:HasServer() and ns.Link:ServerAtLeast(52) then
		ns.SendServer("SUMMON " .. table.concat(names, ";"))
		return true
	end

	-- Without the module, through group chat: one line for all five.
	return self:Broadcast("summon", nil)
end

function O:SummonAll()
	local all = {}
	for _, m in ipairs(ns.Selection:GetRoster()) do tinsert(all, m.name) end
	if #all == 0 then
		ns.Print("Are you in a group?")
		return false
	end
	return self:Summon(all)
end

function O:Follow()
	-- follow turns StayStrategy back off, so the anchors are gone and the next
	-- move order has to re-arm stay mode. Same reasoning as Hold for the route.
	local names = Targets(self)
	if #names == 0 then
		ns.Print("No units selected.")
		return false
	end

	if ns.Route then ns.Route:ClearFor(names) end
	self:ClearHolding()

	if self:HasServer() then
		for _, n in ipairs(names) do ns.UnitState:Note(n, "follow") end
		ns.SendServer("FOLLOW " .. table.concat(names, ";"))
		ns.Print(("Follow (%d unit%s)"):format(#names, #names == 1 and "" or "s"))
		return true
	end

	return self:Send("follow", "Follow")
end

-- Follow, FOR A SPECIFIC LIST instead of for the selection.
--
-- It exists because the case that uses it does not fit `O:Follow`: when you send
-- a group you are IN walking somewhere, the selected bots switch to following
-- you and you do not -- that is to say the order goes to a subset of what is
-- selected, and `O:Follow` goes to everything selected by definition.
--
-- The rest is the same: the anchors are released, because `follow` turns off the
-- stay strategy and a bot with its anchor set would go back to it.
function O:FollowThese(names)
	if not names or #names == 0 then return false end

	if ns.Route then ns.Route:ClearFor(names) end
	for _, n in ipairs(names) do
		self.holding[n] = nil
		ns.UnitState:Note(n, "follow")
	end

	if self:HasServer() then
		ns.SendServer("FOLLOW " .. table.concat(names, ";"))
		return true
	end

	for _, n in ipairs(names) do self:SendTo(n, "follow") end
	return true
end

-- Follow, FOR THE WHOLE GROUP, whatever the selection says.
--
-- It is not `O:Follow` with everything selected: `O:Follow` refuses if nothing
-- is held ("No units selected"), which is right for an order YOU give with the
-- mouse and the opposite of what is needed here -- summoning the group and
-- having them stick to you is one single thing, and it cannot depend on your
-- having had something selected when you pressed the key.
function O:FollowAll()
	local names = {}
	for _, m in ipairs(ns.Selection:GetRoster()) do tinsert(names, m.name) end
	return self:FollowThese(names)
end

function O:Flee()   return self:Send("flee",   "Flee")          end

--- Combat ------------------------------------------------------------------

-- EL RAYO QUE SE MANDA ES EL DEL CLICK, no uno reconstruido despues.
--
-- Cuando el DLL vio la pulsacion trae el rayo con ella (`Markers:ClickShot`), y
-- ese es el bueno: sale del pixel de verdad y de la camara de aquel fotograma.
-- Reconstruirlo aqui -- que es lo que hacia `Markers:CursorRay` -- lo vuelve a
-- sacar del cursor de AHORA y de la escala derivada del fov, o sea de tres
-- cosas que pueden haber cambiado o no coincidir: entonces el punto que el
-- cliente vio y el que el servidor corta son respuestas a preguntas distintas.
--
-- Con el rayo del click las dos partes cortan LA MISMA recta, y lo que quede de
-- diferencia es terreno -- el cliente y el servidor no tienen exactamente el
-- mismo suelo -- y no proyeccion.
local function RayOf(shot)
	if shot and shot.ox then
		return shot.ox, shot.oy, shot.oz, shot.dx, shot.dy, shot.dz
	end
	return ns.Markers:CursorRay()
end

-- Ask where a ray hits the ground without sending any order. It is the path of
-- shift + right-click, which notes a waypoint and sends nothing yet.
--
-- NO ANSWER DOES NO HARM: the point keeps the plane estimate, which is what
-- there was before any of this.
function O:AskGround(id, shot)
	if not id or id == 0 or not self:HasServer() then return false end
	local ox, oy, oz, dx, dy, dz = RayOf(shot)
	if not ox then return false end
	ns.SendServer(("GROUND %d %.2f %.2f %.2f %.5f %.5f %.5f")
		:format(id, ox, oy, oz, dx, dy, dz))
	return true
end

-- An undecided right-click: a guid (or "0"), a ground point, and who is
-- selected. The server works out whether that means attack, interact or move,
-- because it is the only side that can -- see RtsOrders::ClassifyClick.
function O:Click(guid, x, y, z, rayId, shot)
	local sel = ns.Selection:Get()
	if #sel == 0 then return false end

	-- A destination PER UNIT, not one shared point. The server classifies the
	-- click (attack / interact / move) but it cannot know where each unit should
	-- stand -- and when this verb carried a single point, every bot piled onto
	-- the same coordinate.
	--
	-- YOUR OWN CHARACTER goes in the list too, under its own name. In RTS mode
	-- you are a unit like the others, so a click means the same for you; the
	-- server routes your name to the paths that work on a body the camera is
	-- holding control of.
	--
	-- ONE DECIMAL PLACE AND NOT TWO, and it is not cosmetic: it is what makes it
	-- fit. An addon message is 250 usable characters (see `Link.lua`), and with
	-- five units, a creature guid and the ray behind them, this message measured
	-- 258 and NEVER WENT OUT -- hence *"they do not attack if Kirinah is in"*,
	-- which was not her but her name adding seven characters too many.
	--
	-- The tenth of a yard is not missed anywhere: the destination is then
	-- clipped against the real ground with the ray, and playerbots' `position`
	-- rounds to WHOLE yards anyway.
	local offsets = self:SpreadOffsets(#sel, self:FacingTo(x, y))
	local parts = {}
	for i, n in ipairs(sel) do
		tinsert(parts, ("%s %.1f %.1f %.1f"):format(n, x + offsets[i][1], y + offsets[i][2], z))
	end

	-- THE RAY TRAVELS WITH THE ORDER, in a final tail marked with '@'.
	--
	-- The points above come from cutting the cursor ray against a horizontal
	-- PLANE, which is the only thing Lua can do with no map -- and on a slope
	-- that cut lands behind the slope and underground. The server does have a
	-- map: with the ray and the base point it clips against the real ground and
	-- shifts every destination as a block, so the formation is preserved and
	-- only where it hangs from gets corrected. With no ray (no published camera)
	-- the server uses the points as they are and everything goes on as before.
	local hex = tostring(guid):gsub("^0[xX]", "")
	local body = ("CLICK %s %s"):format(hex, table.concat(parts, ";"))

	-- THE RAY IS THE FIRST THING TO GO IF IT DOES NOT FIT, and that is the right
	-- degradation: without it, the server uses the points as they are -- which
	-- is what there was before the ray existed and is still supported on the
	-- other side. Trimming units instead would leave bots with no order, which
	-- is the very bug this came to fix.
	--
	-- It is measured against the channel limit rather than trusting that it
	-- fits: the length depends on the group's NAMES and on whether the click
	-- carries a guid, so "it fits" is a property of the game in progress, not of
	-- the format.
	local ox, oy, oz, dx, dy, dz = RayOf(shot)
	if ox then
		local tail = ("@ %d %.1f %.1f %.1f %.4f %.4f %.4f %.1f %.1f %.1f")
			:format(rayId or 0, ox, oy, oz, dx, dy, dz, x, y, z)
		if #body + 1 + #tail <= ns.Link.LIMIT then
			body = body .. ";" .. tail
		elseif not self.warnedRay then
			self.warnedRay = true
			ns.Print(("|cffff8800click:|r with %d selected the ray does not fit in the " ..
			          "message; the destination comes from the plane and lands worse on a slope."):format(#sel))
		end
	end

	ns.SendServer(body)

	-- Shown straight away rather than waiting for the server to say what the
	-- click meant: a marker that appears a round trip late does not feel like a
	-- response to your click. Recoloured red if it turns out to be an attack.
	self.lastClick = { x = x, y = y, z = z }
	ns.Flare:Show(x, y, z, "move")
	return true
end

-- Attack ONE named unit, whoever it is.
--
-- The `attack` chat command cannot express this: server-side it resolves as
-- "attack my target" and reads the master's current target
-- (AttackAction.cpp:39), so right-clicking an enemy only ever did anything if
-- that enemy was already your target. With mod-rts the victim travels with the
-- order. Without it, the best we can do is target the unit first and fall back
-- to the old command.
function O:AttackGuid(guid, label)
	local sel = ns.Selection:Get()
	if #sel == 0 then
		ns.Print("No units selected.")
		return false
	end

	if self:HasServer() then
		local names = {}
		for _, n in ipairs(sel) do
			tinsert(names, n)
			ns.UnitState:Note(n, "attack")
			self.holding[n] = nil     -- an attack order releases the anchor
		end
		-- Guids arrive from the DLL as "0x0000000000000ABC"; the server parses
		-- hex, so the prefix has to go.
		local hex = tostring(guid):gsub("^0[xX]", "")
		ns.SendServer(("ATTACK %s %s"):format(hex, table.concat(names, ";")))
		ns.Print("Attack " .. (label or "target"))
		return true
	end

	return self:Attack()
end

-- Both act on YOUR current target, so guard against having none.
--
-- WITH THE MODULE IT GOES THROUGH `ATTACK`, the same path as the right-click on
-- an enemy. The victim travels INSIDE the order, so it does not depend on the
-- server reading your target at exactly the right moment -- and it arrives with
-- no chat queue.
--
-- `AttackGuid` comes back here when there is no module, so the detour has to
-- check `HasServer` and not the other way round: without that guard the two call
-- each other in a circle.
function O:Attack()
	if not UnitExists("target") or not UnitCanAttack("player", "target") then
		ns.Print("No hostile target.")
		return false
	end
	if self:HasServer() then
		return self:AttackGuid(UnitGUID("target"), UnitName("target"))
	end
	return self:Send("attack", "Attack " .. UnitName("target"))
end

function O:Pull()
	if not UnitExists("target") or not UnitCanAttack("player", "target") then
		ns.Print("No hostile target.")
		return false
	end
	return self:Send("pull", "Pull " .. UnitName("target"))
end

function O:TankAttack() return self:Send("tank attack", "Tank attack") end
function O:MaxDPS()     return self:Send("max dps",     "Max DPS")     end
function O:Grind()      return self:Send("grind",       "Grind")       end
function O:Runaway()    return self:Send("runaway",     "Runaway")     end

function O:Cast(spell)
	if not spell or spell == "" then
		ns.Print("Usage: cast <spell name>")
		return false
	end
	return self:Send("cast " .. spell, "Cast " .. spell)
end

--- Formation ---------------------------------------------------------------

O.FORMATIONS = { "near", "far", "melee", "queue", "chaos", "circle", "line", "shield", "arrow" }

-- THE RAID MARK AND THE ORDER, IN THE SAME GESTURE.
--
-- They were two cells of the 4x4 grid (`Panel.lua`, deleted on 2026-09-13) and
-- that is why they lived inside the panel. Now they are macros, so the order
-- comes down here: a macro only knows how to write one command, and this one
-- has two halves that HAVE to go together -- putting the icon on your target
-- and telling the group to go for that icon. Apart, the missing half gives no
-- error: it leaves the group chasing the previous mark.
--
-- `rti` and `rti cc` are playerbots verbs; the skull (8) and the moon (5) are
-- the client's own long-standing indices.
function O:MarkTarget(cc)
	local key   = cc and "moon" or "skull"
	local index = cc and 5 or 8

	local f = SetRaidTarget or SetRaidTargetIcon
	local puesto = false
	if f and UnitExists("target") then
		f("target", index)
		puesto = true
	end

	self:Broadcast((cc and "rti cc " or "rti ") .. key,
		cc and "crowd control: moon" or "target: skull")

	-- IT SAYS SO WHEN IT WAS NOT PUT ON. The order goes out anyway -- the group
	-- follows whatever mark there was -- and without this warning it looks as
	-- though the button did nothing.
	if not puesto then
		ns.Print("no target: the mark was not put on anybody.")
	end
	return puesto
end

-- FACTORY BEHAVIOUR TO THE WHOLE GROUP. This was a grid cell too. It goes
-- through mod-rts' `RESET`, which clears strategies and roles in one go; with no
-- server the closest thing there is is putting them back on follow, which is
-- what the button did.
function O:ResetAll()
	local names = {}
	for _, m in ipairs(ns.Selection:GetRoster()) do
		table.insert(names, m.name)
	end
	if #names == 0 then
		ns.Print("reset: no group.")
		return
	end
	if self:HasServer() then
		ns.SendServer("RESET " .. table.concat(names, ";"))
		ns.Print(("reset: factory behaviour on all %d."):format(#names))
	else
		self:Broadcast("follow", "Back to following you")
	end
end

function O:Formation(name)
	return self:Broadcast("formation " .. name, "Formation: " .. name)
end

--- Escape hatch ------------------------------------------------------------

-- Pass any raw playerbots command through to the selection.
function O:Raw(text)
	if not text or text == "" then return false end
	return self:Send(text, "> " .. text)
end

--- What the server says it did ---------------------------------------------
--
-- `DID <VERB> [n] [label]` is the acknowledgement of every order: what the
-- server decided the click meant, and how many bots it reached. **It is printed
-- whenever the answer is useful**, because a click that silently does nothing
-- is the most confusing failure in this whole system.
--
-- It lived in `Camera.lua` until 2026-09-02 and it is here because it is this
-- file's orders that get acknowledged. Registered at file scope and not in a
-- `Create` because `Orders` has none: its structures are flat tables and it
-- creates no frames.
ns.Link:On("DID", function(rest)
	local did, n, label = rest:match("^(%a+)%s*(%d*)%s*(.*)$")
	if not did then return end

	if did == "ATTACK" then
		local p = O.lastClick
		if p then ns.Flare:Show(p.x, p.y, p.z, "attack") end
		ns.Print(("Attack %s -> %s unit%s"):format(
			label ~= "" and ("|cffff6666" .. label .. "|r") or "target",
			n == "" and "0" or n, n == "1" and "" or "s"))

	elseif did == "INTERACT" then
		-- NO se manda `talk` aqui. El servidor YA ha interactuado -- eso es
		-- justo lo que este mensaje nos esta contando -- y ademas distingue un
		-- PNJ (gossip) de un cadaver (botin).
		--
		-- La llamada que habia aqui era de cuando el servidor no lo hacia y el
		-- addon tenia que pedirlo por chat. Al pasarle esa tarea al servidor,
		-- esta linea se quedo de duplicado: sobre un cadaver susurraba `talk`
		-- -- querer hablar con un muerto -- y encima interrumpia la ventana de
		-- botin recien abierta, que es por lo que solo recogias una cosa y el
		-- resto se quedaba.
		--
		-- Mismo patron que ya costo una ronda entera: un apano en pie despues
		-- de que desapareciera el motivo que lo puso ahi.
		if n ~= "" and tonumber(n) == 0 then
			ns.Print("|cffffff00Nadie pudo interactuar.|r")
		end

	elseif did == "SELFCAST" then
		-- El acuse del lanzamiento sobre tu propio cuerpo. Un lanzamiento del
		-- servidor puede no dar NINGUNA senal en el cliente, asi que sin esto
		-- "no ha pasado nada" y "no llego la orden" se ven igual
		-- (PRUEBAS-18 C10).
		local spell = GetSpellInfo(tonumber(n) or 0)
		ns.Print(("|cff33ccfftu|r: %s"):format(spell or ("hechizo " .. n)))

	elseif did == "GATHER" then
		-- EL UNICO CLICK DEL MODO QUE PUEDE NO MOVER A NADIE, y por eso este
		-- acuse no es opcional: pinchas una hierba, el grupo se queda quieto a
		-- proposito, y sin una linea eso se lee exactamente igual que un click
		-- perdido.
		--
		-- Recoger es del CLIENTE: el mismo click derecho ya ha lanzado tu
		-- hechizo de profesion. Lo que el servidor hace es apartarse -- no
		-- mandarte una orden de movimiento que lo cancele -- y decirlo aqui.
		local what = (label ~= "" and label) or "eso"
		if n == "1" then
			ns.Print(("|cff33ccffrecoges|r %s"):format(what))
		else
			-- Fuera de alcance el cliente no llego a intentarlo, asi que el
			-- servidor te lleva y el que recoge es el siguiente click. Se dice,
			-- o se queda uno esperando una barra que no va a salir.
			ns.Print(("|cffffff00vas hacia|r %s |cff888888(vuelve a pincharlo al llegar)|r"):format(what))
		end

	elseif did == "MOVE" and n == "0" then
		ns.Print("|cffffff00Move order reached no bots.|r")

	elseif (did == "HOLD" or did == "SUMMON") and n == "0" then
		-- Mismo motivo que el de MOVE: sin esta linea, una orden que no alcanza
		-- a nadie se ve igual que una que fue bien -- que es como se pasa un
		-- rato dandole a un boton roto.
		ns.Print(("|cffffff00%s no llego a ningun bot.|r"):format(
			did == "HOLD" and "Quieto" or "Traer"))

	elseif did == "LOOT" and n == "0" then
		-- Cero bots cambiados. Sin esto la estrategia de botin fallaria EN
		-- SILENCIO, que es exactamente el fallo que este verbo vino a arreglar:
		-- el addon dice "botin: TODO" y no ha llegado a nadie.
		ns.Print("|cffffff00El botin no llego a ningun bot.|r " ..
			"Estas en grupo? Son bots de playerbots?")
	end
end)

