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
-- LO SABE `Link`, NO ESTE FICHERO, desde 2026-09-02: es un hecho del canal, no
-- de las ordenes. Se queda el nombre porque es el que leen trece sitios y
-- porque "hay servidor para mandar" es la pregunta que se hace desde aqui.
--
-- Y sigue siendo una PROMESA durante el primer segundo: quien necesite actuar
-- en cuanto haya servidor usa `ns.Link:WhenServer(fn)`, no un bucle propio.
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
-- *"posees raro, eso quitalo"*. It never could be anything else -- possession
-- changes who MOVES you, not who you ARE, so talking to an NPC went through
-- your own character, standing somewhere else, and failed on range. This time
-- the server half went with it, so there is nothing left to reach for; the
-- thing that does what it promised is `SWAP`.

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

	-- El mismo tramo '@' que el click derecho: el avance con ataque tambien
	-- sale del cursor, asi que el servidor le corta el suelo de verdad al rayo
	-- y desplaza los destinos en bloque. Ver Orders:Click.
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

function O:Hold()
	-- stay pins each bot where it stands, which is exactly hold-position.
	-- It also ENDS any route: "hold here" and "keep walking the path" are
	-- contradictory orders, and leaving the path drawn would say the wrong one.
	local sel = ns.Selection:Get()
	if ns.Route then ns.Route:ClearFor(sel) end
	for _, name in ipairs(sel) do self.holding[name] = true end
	return self:Send("stay", "Hold position")
end

function O:Follow()
	-- follow turns StayStrategy back off, so the anchors are gone and the next
	-- move order has to re-arm stay mode. Same reasoning as Hold for the route.
	if ns.Route then ns.Route:ClearFor(ns.Selection:Get()) end
	self:ClearHolding()

	if self:HasServer() then
		local names = {}
		for _, n in ipairs(ns.Selection:Get()) do
			tinsert(names, n)
			ns.UnitState:Note(n, "follow")
		end
		if #names == 0 then ns.Print("No units selected.") return false end
		ns.SendServer("FOLLOW " .. table.concat(names, ";"))
		ns.Print(("Follow (%d unit%s)"):format(#names, #names == 1 and "" or "s"))
		return true
	end

	return self:Send("follow", "Follow")
end

-- Seguir, PARA UNA LISTA CONCRETA en vez de para la seleccion.
--
-- Existe porque el caso que la usa no cuadra con `O:Follow`: cuando mandas
-- caminar a un grupo en el que vas TU, los bots seleccionados pasan a seguirte
-- y tu no -- o sea que la orden va a un subconjunto de lo seleccionado, y
-- `O:Follow` manda a todo lo seleccionado por definicion.
--
-- Lo demas es igual: se sueltan las anclas, porque `follow` apaga la estrategia
-- de quedarse quieto y un bot con ancla puesta volveria a ella.
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

function O:Flee()   return self:Send("flee",   "Flee")          end

--- Combat ------------------------------------------------------------------

-- An undecided right-click: a guid (or "0"), a ground point, and who is
-- selected. The server works out whether that means attack, interact or move,
-- because it is the only side that can -- see RtsOrders::ClassifyClick.
-- Preguntar por el suelo de un rayo sin mandar ninguna orden. Es el camino del
-- shift + click derecho, que anota un punto de ruta y no manda nada todavia.
--
-- SIN RESPUESTA NO PASA NADA MALO: el punto se queda con la estimacion del
-- plano, que es lo que habia antes de todo esto.
function O:AskGround(id)
	if not id or id == 0 or not self:HasServer() then return false end
	local ox, oy, oz, dx, dy, dz = ns.Markers:CursorRay()
	if not ox then return false end
	ns.SendServer(("GROUND %d %.2f %.2f %.2f %.5f %.5f %.5f")
		:format(id, ox, oy, oz, dx, dy, dz))
	return true
end

function O:Click(guid, x, y, z, rayId)
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
	-- UNA CIFRA DECIMAL Y NO DOS, y no es cosmetico: es lo que hace que quepa.
	-- Un mensaje de addon son 250 caracteres utiles (ver `Link.lua`), y con
	-- cinco unidades, un guid de criatura y el rayo detras, este mensaje media
	-- 258 y NO SALIA -- de ahi *"no atacan si esta Kirinah"*, que no era ella
	-- sino su nombre sumando siete caracteres de mas.
	--
	-- La decima de yarda no se echa de menos por ningun lado: el destino se
	-- recorta luego contra el suelo de verdad con el rayo, y el `position` de
	-- playerbots redondea a yardas ENTERAS de todas formas.
	local offsets = self:SpreadOffsets(#sel, self:FacingTo(x, y))
	local parts = {}
	for i, n in ipairs(sel) do
		tinsert(parts, ("%s %.1f %.1f %.1f"):format(n, x + offsets[i][1], y + offsets[i][2], z))
	end

	-- EL RAYO VIAJA CON LA ORDEN, en un tramo final marcado con '@'.
	--
	-- Los puntos de arriba salen de cortar el rayo del cursor contra un PLANO
	-- horizontal, que es lo unico que Lua puede hacer sin mapa -- y en una
	-- cuesta ese corte cae detras de la cuesta y bajo tierra. El servidor si
	-- tiene mapa: con el rayo y el punto base recorta el suelo de verdad y
	-- desplaza todos los destinos en bloque, asi que la formacion se conserva y
	-- solo se corrige de donde cuelga. Sin rayo (sin camara publicada) el
	-- servidor usa los puntos tal cual y todo sigue como antes.
	local hex = tostring(guid):gsub("^0[xX]", "")
	local body = ("CLICK %s %s"):format(hex, table.concat(parts, ";"))

	-- EL RAYO ES LO PRIMERO QUE SE CAE SI NO CABE, y esa es la degradacion
	-- correcta: sin el, el servidor usa los puntos tal cual -- que es lo que
	-- habia antes de que el rayo existiera y sigue estando soportado al otro
	-- lado. Recortar unidades en cambio dejaria bots sin orden, o sea el fallo
	-- que esto viene a arreglar.
	--
	-- Se mide contra el limite del canal en vez de confiar en que quepa: el
	-- largo depende de los NOMBRES del grupo y de si el click lleva guid, asi
	-- que "cabe" es una propiedad de la partida, no del formato.
	local ox, oy, oz, dx, dy, dz = ns.Markers:CursorRay()
	if ox then
		local tail = ("@ %d %.1f %.1f %.1f %.4f %.4f %.4f %.1f %.1f %.1f")
			:format(rayId or 0, ox, oy, oz, dx, dy, dz, x, y, z)
		if #body + 1 + #tail <= ns.Link.LIMIT then
			body = body .. ";" .. tail
		elseif not self.warnedRay then
			self.warnedRay = true
			ns.Print(("|cffff8800click:|r con %d seleccionados el rayo no cabe en el " ..
			          "mensaje; el destino sale del plano y en cuesta cae peor."):format(#sel))
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
function O:Attack()
	if not UnitExists("target") or not UnitCanAttack("player", "target") then
		ns.Print("No hostile target.")
		return false
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

function O:Formation(name)
	return self:Broadcast("formation " .. name, "Formation: " .. name)
end

--- Escape hatch ------------------------------------------------------------

-- Pass any raw playerbots command through to the selection.
function O:Raw(text)
	if not text or text == "" then return false end
	return self:Send(text, "> " .. text)
end

--- Lo que el servidor dice que hizo ---------------------------------------
--
-- `DID <VERBO> [n] [etiqueta]` es el acuse de cada orden: que decidio el
-- servidor que significaba el click, y a cuantos bots llego. **Se imprime
-- siempre que la respuesta sea util**, porque un click que en silencio no hace
-- nada es el fallo mas confuso de todo este sistema.
--
-- Vivia en `Camera.lua` hasta 2026-09-02 y esta aqui porque son las ordenes de
-- este fichero las que se acusan. Registrado en el ambito del fichero y no en
-- un `Create` porque `Orders` no tiene: sus estructuras son tablas planas y no
-- crea ningun frame.
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

	elseif did == "MOVE" and n == "0" then
		ns.Print("|cffffff00Move order reached no bots.|r")

	elseif did == "LOOT" and n == "0" then
		-- Cero bots cambiados. Sin esto la estrategia de botin fallaria EN
		-- SILENCIO, que es exactamente el fallo que este verbo vino a arreglar:
		-- el addon dice "botin: TODO" y no ha llegado a nadie.
		ns.Print("|cffffff00El botin no llego a ningun bot.|r " ..
			"Estas en grupo? Son bots de playerbots?")
	end
end)

