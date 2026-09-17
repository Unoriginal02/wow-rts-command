--[[
	RTSMode.lua -- Warcraft 3 style mouse control.

	Toggling RTS mode shows a full-screen mouse catcher below the addon frames
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
R.held = {}

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

-- SE MIDE CONTRA EL CUERPO, NO CONTRA LOS PIES, y eso es lo que arregla al
-- heroe.
--
-- La posicion que publica el DLL son los PIES. Medir la distancia del cursor a
-- ESE punto hace que la diana sea un circulo en el suelo, asi que para coger a
-- alguien hay que pinchar donde pisa -- literalmente *"es como si tuviera que
-- clicar en sus pies"*.
--
-- Con los bots no se notaba porque ahi manda el mouseover del cliente, que es
-- geometria de verdad. **El heroe no tiene mouseover: el cliente nunca apunta a
-- tu propio personaje**, ni dentro ni fuera del modo RTS. Asi que el unico
-- camino que le quedaba era tambien el mas estrecho de los tres, y por eso el
-- sintoma parecia cosa de "estar convertido en bot" cuando no tiene nada que
-- ver con eso.
--
-- Un modelo ocupa una FRANJA vertical en pantalla, asi que la diana es el
-- segmento de los pies a la cabeza con el radio de siempre a los lados. Es la
-- forma que tiene el bicho, y sale de dos proyecciones en vez de una.
local BODY_TOP = 2.2      -- yardas de los pies a la coronilla

local function BodyDist2(sx, sy, wx, wy, wz)
	local fx, fy = ns.Markers:Project(wx, wy, wz + 0.2)
	local hx, hy = ns.Markers:Project(wx, wy, wz + BODY_TOP)
	if not fx then fx, fy = hx, hy end
	if not hx then hx, hy = fx, fy end
	if not fx then return nil end

	local dx, dy = hx - fx, hy - fy
	local len2 = dx * dx + dy * dy
	local t = 0
	if len2 > 0 then
		t = ((sx - fx) * dx + (sy - fy) * dy) / len2
		if t < 0 then t = 0 elseif t > 1 then t = 1 end
	end
	local px, py = fx + dx * t, fy + dy * t
	return (sx - px) ^ 2 + (sy - py) ^ 2
end

-- Nearest roster unit to (sx,sy), or nil.
--
-- Kept as the fallback for the moment the mouse IS captured -- mid drag-box,
-- when the catcher owns it and mouseover is gone. Outside that, HoverUnit is
-- both cheaper and exact -- salvo para el heroe, que no tiene mouseover nunca y
-- para el que este es el unico camino.
function R:UnitAt(sx, sy)
	local best, bestD
	for _, m in ipairs(self:Roster()) do
		local wx, wy, wz = ns.Markers:UnitWorld(m.guid)

		-- TU PROPIO PERSONAJE TIENE UNA SEGUNDA FUENTE, y hace falta.
		--
		-- La lista del DLL se centra en la CAMARA: con la camara despegada lejos
		-- de tu cuerpo, tu cuerpo puede quedarse fuera de ella. `RTS_PX/PY/PZ`
		-- es tu posicion y se publica SIEMPRE, este la camara donde este.
		if not wx and m.isPlayer and RTS_HasPos == 1 then
			wx, wy, wz = RTS_PX, RTS_PY, RTS_PZ
		end

		if wx then
			local d = BodyDist2(sx, sy, wx, wy, wz)
			if d and d <= PICK_RADIUS * PICK_RADIUS and (not bestD or d < bestD) then
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
	ns.Orders:MoveGroupTo(sel, x, y, z)
end

--- Click handling ----------------------------------------------------------

-- `hover` is what the client had under the cursor at MOUSE-DOWN, captured
-- before any capture could steal it. Falls back to projected picking only if
-- there was none.
function R:OnLeftClick(sx, sy, shift, alt, hover)
	-- SIN MOUSEOVER, LA PROYECCION -- y solo con algo armado.
	--
	-- Hace falta justo desde que se pregunta SIEMPRE (2026-09-06): **tu heroe no
	-- tiene mouseover nunca**, porque el cliente no apunta a tu propio
	-- personaje. Asi que "que la sacerdotisa me cure a mi" pinchandote en el
	-- mundo caia en la rama de "no hay nada bajo el cursor" y CANCELABA el
	-- hechizo -- un gesto que hace lo contrario de lo que pides.
	--
	-- Se hace aqui arriba y no dentro de cada rama porque las dos bocas del
	-- mismo gesto -- una habilidad y el boton de Cuidar -- tienen el hueco
	-- identico, y arreglar solo una es como se acaba con dos gestos que se
	-- parecen y no se comportan igual.
	--
	-- Solo cuando hay algo armado: fuera de eso el camino de siempre ya cae a
	-- `UnitAt` mas abajo, y adelantarlo cambiaria comportamiento que funciona.
	if not hover and (ns.Skills:Aiming() or ns.Cast.pendingFocus) then
		local m = self:UnitAt(sx, sy)
		if m then
			-- `ours`/`hostile` son ciertos por construccion: `UnitAt` solo mira
			-- tu propio grupo.
			hover = { guid = m.guid, name = m.name, ours = true, hostile = false }
		end
	end

	-- UNA HABILIDAD ARMADA SE COME EL CLICK, y va lo primero de todo.
	--
	-- Pulsar una habilidad sin Alt y sin objetivo la deja esperando a que elijas
	-- sobre quien (la convencion del video). Mientras espera, el click siguiente
	-- SIGNIFICA ese objetivo y nada mas -- si ademas cambiara la seleccion,
	-- curar al tanque te dejaria con el tanque cogido y el grupo suelto.
	--
	-- Sobre suelo vacio se cancela, que es lo que quiere decir pinchar la nada.
	if ns.Skills:Aiming() then
		if hover then
			-- El bando viaja con el click: aqui es donde de verdad se sabe, y
			-- es lo que deja que `AimAt` avise de una cura sobre un lobo.
			ns.Skills:AimAt(hover.guid, hover.name, hover.hostile)
		else
			ns.Skills:AimAt(nil)
		end
		return
	end

	-- Y UN FOCO PENDIENTE, IGUAL. El boton de "Focus" de la consola usa el mismo
	-- armado que un hechizo -- el jugador ya sabe que un icono dando vueltas
	-- significa "elige a quien", y dos gestos para lo mismo seria peor que uno.
	if ns.Cast:AimAt(hover and hover.guid, hover and hover.name) then
		return
	end

	local m = hover and hover.ours and { name = hover.name, guid = hover.guid,
	                                     isPlayer = hover.name == ns.MyName() }
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
			-- Seleccionar una unidad ES tomar el mando desde 2026-08-24: sus
			-- habilidades salen en la consola sin ningun modo que encender.
			-- Antes esto abria el panel flotante de `CommandMode.lua`.
			ns.Print(("|cff33ccff%s|r: sus habilidades, en la consola."):format(m.name))
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
	--
	-- FIJAR UN BICHO DEL MUNDO EN LA CONSOLA SE FUE CON LA FILA DE ENEMIGOS,
	-- borrada en 2026-09-02. El gesto era click izquierdo sobre un hostil (shift
	-- suma) y esta escrito aqui porque, si la sala vuelve a tener una fila de
	-- objetivos, esta es la linea donde se enganchaba -- y la razon de que fuera
	-- shift + IZQUIERDO y no derecho sigue en pie: shift + derecho encadena un
	-- punto de ruta desde la etapa 5l, y darle un segundo significado segun lo
	-- que hubiera bajo el cursor haria que encadenar una ruta dependiera de con
	-- cuanta punteria pasaste por encima de un lobo.
	--
	-- Hoy un click izquierdo sobre algo que no es tuyo no hace nada nuestro: el
	-- cliente lo apunta por su cuenta, como fuera del modo RTS.
	if hover and not hover.ours then
		-- SHIFT sobre un HOSTIL lo encadena (1, 2, 3...). Es el gesto que la
		-- fila de enemigos borrada usaba para fijar bichos, y esta linea es la
		-- que su comentario decia que era la suya. El icono se pone AQUI y no
		-- despues porque solo se puede poner sobre `mouseover`, que es lo que
		-- el cliente tiene ahora mismo y en un instante ya no.
		if shift and hover.hostile then
			ns.Chain:Add(hover.guid, hover.name, "mouseover")
			return
		end

		-- Sin shift: nada nuestro. La ventana de misiones dejo de ser "lo que
		-- ofrece este PNJ" para ser "lo que llevo YO y quien lo lleva conmigo",
		-- asi que ya no tiene nada que ver con lo que haya bajo el cursor y se
		-- abre con `/rts quests`. Lo que el PNJ ofrece se sigue leyendo -- es lo
		-- que alimenta la entrega automatica -- pero en silencio y al cerrar la
		-- conversacion, no al pinchar.
		return
	end

	-- SIN MOUSEOVER NO SE FIJA NADA, aunque el DLL este publicando bichos ahi
	-- mismo. La proyeccion sabe DONDE esta una criatura pero no si es hostil --
	-- publica el tipo 3, que incluye al tabernero -- asi que fijar por
	-- proyeccion meteria PNJs amistosos en una fila que se llama "enemigos" y
	-- cuyo click izquierdo es una orden de ataque. El click derecho si tira de
	-- la proyeccion, y puede: alli la clasificacion la hace el SERVIDOR.
	--
	-- Y aqui no hace falta: desde la etapa 5h el raton esta libre, asi que el
	-- cliente marca mouseover en cada click del mundo.
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
function R:OnRightClick(sx, sy, hover, shift, shot)
	-- El derecho cancela una habilidad armada y NO da la orden. Es la salida del
	-- gesto, y tiene que existir: sin ella la unica forma de deshacer un "elige
	-- objetivo" pulsado por error es lanzarlo sobre algo.
	if ns.Skills:CancelAim() then
		ns.Print("|cff888888habilidad cancelada.|r")
		return
	end
	if ns.Cast:CancelAim() then
		ns.Print("|cff888888foco cancelado.|r")
		return
	end

	if ns.Selection:IsEmpty() then return end

	-- DONDE SE PINCHO. UNA SOLA RESPUESTA, Y LA DEL DLL MANDA.
	--
	-- `shot` es el rayo que el DLL casco en el mensaje de ESTA pulsacion: el
	-- pixel de verdad, la camara de ese fotograma, y la funcion de picking del
	-- propio cliente contra el terreno, los edificios y los modelos. No hay nada
	-- que estimar ni con que arbitrar.
	--
	-- `CursorGroundPoint` se queda de suplente para un cliente sin DLL, y esa es
	-- toda su vida ahora. Sigue cortando un PLANO horizontal -- lo unico que Lua
	-- puede hacer sin mapa -- y en cuesta eso falla mas cuanto mas lejos y mas
	-- rasante mires. Por eso el rayo viaja con la orden: el servidor lo corta
	-- contra su suelo y corrige.
	local x, y, z
	local exact = false
	if shot and shot.x then
		x, y, z = shot.x, shot.y, shot.z
		exact = true
	else
		x, y, z = ns.Markers:CursorGroundPoint()
	end

	-- SHIFT ENCADENA UN PUNTO DE RUTA, y no llega a preguntar que hay debajo.
	-- Es deliberado: shift + click derecho sobre un bicho en un RTS sigue
	-- siendo "y luego ve ahi", no "y luego atacale" -- y mezclar las dos cosas
	-- en un gesto haria que la ruta dependiera de con cuanta punteria pasaste
	-- por encima de un lobo.
	if shift and x then
		-- El punto se apunta con la estimacion y se le pregunta al servidor
		-- donde esta el suelo de verdad de ese rayo. Aqui NO hay orden que
		-- mandar -- el punto encadenado se manda cuando le toque -- asi que la
		-- pregunta va sola, con el numero del punto para que la respuesta
		-- corrija el que se pregunto y no el que este de moda al llegar.
		local id = ns.Route:Add(x, y, z, exact)
		ns.Orders:AskGround(tonumber(id), shot)
		return
	end

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

	-- SIN PUNTO DE SUELO PERO CON OBJETIVO, EL PUNTO ES EL OBJETIVO.
	--
	-- `CursorGroundPoint` puede devolver nil, y no es raro: cuando el rayo del
	-- DLL no acierta terreno se cae a cortar un PLANO horizontal a la altura del
	-- jugador, y un rayo que sube -- pinchar algo cuesta arriba, o alto en la
	-- pantalla -- no cruza ese plano nunca (`k <= 0`). Devuelve nil, y hasta hoy
	-- todo lo de abajo estaba guardado tras `and x`: la orden no salia, no se
	-- imprimia nada, y el click se perdia ENTERO. Reportado en PRUEBAS-18 como
	-- "selecciono varios y click derecho en un enemigo y no van a atacarle".
	--
	-- El arreglo no es aflojar la estimacion: es que cuando hay un GUID la
	-- estimacion no hace falta. La posicion de ese objetivo la publica el DLL
	-- treinta veces por segundo, es su sitio de verdad, y sirve para las tres
	-- lecturas -- atacar (los destinos se reparten a su alrededor), interactuar
	-- y lootear. Solo el click al SUELO necesita el corte del rayo, que es
	-- justo el caso donde el corte existe.
	if not x and guid ~= "0" then
		x, y, z = ns.Markers:UnitWorld(guid)
	end

	-- Y si sigue sin haber nada, se DICE. Un click que no hace nada y no imprime
	-- nada es indistinguible de un click sobre hierba, y esa confusion es la que
	-- ha costado tres rondas de pruebas en este mismo gesto.
	if not x then
		ns.Print("|cffff8800No se donde has pinchado|r " ..
			"(el rayo no corta el suelo y ahi no hay nada). Prueba mas cerca del horizonte.")
		return
	end

	-- Un click derecho sin shift EMPIEZA DE NUEVO: la ruta anterior se tira, y
	-- si esto fue un click al suelo se anota como ruta de un punto.
	--
	-- ANOTAR NO ES MANDAR. La orden de este primer tramo la manda igualmente el
	-- camino de siempre (`Orders:Click`, que ademas deja al servidor decidir si
	-- era atacar, hablar o lootear); la ruta solo se queda con el destino para
	-- que el SIGUIENTE shift+click tenga de donde encadenar. Mandarlo dos veces
	-- seria dos ordenes por click, que es lo que pasaba en el primer borrador.
	local rayId
	if x and guid == "0" then
		rayId = tonumber(ns.Route:Set(x, y, z, exact))
	else
		ns.Route:ClearFor(ns.Selection:Get())
	end

	-- El rayo viaja DENTRO de la orden, no en una pregunta aparte: el servidor
	-- corta el suelo antes de repartir los destinos, asi que la orden sale ya
	-- corregida y no hay que esperar a nada. Lo que si llega despues es la
	-- respuesta para el dibujo (`GROUNDAT`), y por eso va el numero del punto.
	if ns.Orders:HasServer() then
		ns.Orders:Click(guid, x, y, z, rayId, shot)
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

-- CUANDO SE TOMA LA REFERENCIA DEL GIRO, que es la otra mitad del problema y la
-- que seguia rota despues de subir `turnEps`.
--
-- PRUEBAS-10 H4: "los comandos de click en el mundo a veces no se registran a
-- la primera, al siguiente click si". Siempre el primero, nunca el segundo, y
-- eso es la firma exacta de lo que pasa: la camara RTS la mueve el SERVIDOR, y
-- despues de soltar una panoramica sigue asentandose unas decimas. Un click que
-- cae en esa ventana mide el resto del movimiento ANTERIOR y se archiva como
-- "giro de camara". El siguiente click ya cae con la camara quieta y funciona.
--
-- Subir el umbral no lo arregla: el asentamiento de una panoramica larga puede
-- ser mayor que un giro corto de verdad, asi que cualquier umbral que trague lo
-- uno traga tambien lo otro. Lo que hay que arreglar es CONTRA QUE se mide.
--
-- La referencia se vuelve a tomar `TURN_ARM` despues de la pulsacion, no en la
-- pulsacion. Con eso:
--
--   * un click corto suelta antes de que haya referencia -- no se puede juzgar
--     como giro, asi que nunca se traga. La deriva se mide desde cero.
--   * un arrastre de verdad dura mucho mas que esto, y todo lo que mueva la
--     camara despues del rearme cuenta entero.
--   * lo que la camara traia de antes se descarta por construccion, que es
--     justo lo que sobraba.
local TURN_ARM = 0.12

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
    -- Sin referencia todavia: la toma `ArmTurn` pasado TURN_ARM. Hasta entonces
    -- CamDrift devuelve nil y nada se puede archivar como giro.
    down.fx, down.fy, down.fz = nil, nil, nil
    down.armed = false
    down.drift = 0
    -- Snapshot now, while the client still owns the mouse.
    down.hover = R:HoverUnit()

    -- Y EL PUNTO DEL SUELO, TAMBIEN EN LA PULSACION.
    --
    -- Por lo mismo que el mouseover: lo que el jugador apunto es lo que hay
    -- cuando aprieta, no lo que quede cuando suelte. La diferencia entre las dos
    -- cosas es un cursor que el cliente congela y mueve por su cuenta durante el
    -- boton, y una camara que sigue paneando -- o sea, exactamente los casos en
    -- los que el punto acababa donde nadie pincho.
    --
    -- Lo contesta el DLL en el mensaje del boton (`Markers:ClickShot`), asi que
    -- ya esta puesto cuando esto corre. Nil si no hay DLL: entonces manda el
    -- camino de siempre y nada cambia.
    down.shot = ns.Markers:ClickShot(button)
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

-- Tomar la referencia, una vez, TURN_ARM despues de la pulsacion. Llamada desde
-- el OnUpdate, que es el unico sitio que corre mientras el boton esta abajo.
local function ArmTurn()
    if down.armed or not down.at then return end
    if (GetTime() - down.at) < TURN_ARM then return end
    down.armed = true
    down.fx, down.fy, down.fz = CamFwd()
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
    -- Con Ctrl el raton lo tiene el catcher, asi que el cursor NO esta
    -- congelado: es la medida honesta y ademas la inmediata. Antes esto caia
    -- en el temporizador de abajo y la caja tardaba 150 ms en aparecer.
    if down.captured then
        local sx, sy = CursorXY()
        if math.abs(sx - down.x) + math.abs(sy - down.y) > CLICK_SLOP then
            return true
        end
    end
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
    local shot  = down.shot

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
            R:OnRightClick(sx, sy, hover, shift, shot)
        else
            ReportGesture(button, "|cffff0000TRAGADO|r (giro de camara)")
        end
    end

    down.button, down.hover, down.dragging, down.turned = nil, nil, false, false
    down.shot = nil
    down.armed, down.fx, down.fy, down.fz = false, nil, nil, nil
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
    -- LOS DOS BOTONES, PARA EL GESTO DE AVANZAR. `down` solo guarda UNO -- el
    -- que abrio el gesto -- y izquierdo+derecho necesita saber de los dos a la
    -- vez. Se apuntan aqui, que es donde el cliente los entrega, y no
    -- preguntando a `IsMouseButtonDown`: ese devuelve NO mientras el cliente
    -- tiene el raton cogido en su propio arrastre (medido con `/rts fc mouse`).
    WorldFrame:HookScript("OnMouseDown", function(_, button)
        if R.active then R.held[button] = true end
    end)

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

        -- La referencia se toma aqui, no en la pulsacion: ver TURN_ARM. Hasta
        -- que se toma, CameraTurned no puede decir que si, y un click corto
        -- suelta antes -- que es exactamente lo que arregla los clicks que se
        -- perdian justo despues de mover la camara.
        ArmTurn()

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

--- Que los bots recojan TODO, grises incluidos ------------------------------
--
-- Botin libre (arriba) es de quien PUEDE lootear; esto es de que RECOGEN los
-- bots. Son dos cosas distintas y las dos hacian falta:
--
--   * `ll all` pone la estrategia de botin "all" (`LootStrategyValue.cpp`:
--     `AllLootStrategy::CanLoot` devuelve true a secas). La de fabrica es
--     "normal", que pasa por `ItemUsageValue` y deja los grises en el suelo.
--   * Y hay una TRAMPA en la conf del servidor que anula esto entero:
--     `LootAction::isUseful()` es
--         freeMethodLoot || !grupo || metodo != FREE_FOR_ALL || esJugadorReal
--     asi que con `AiPlayerbot.FreeMethodLoot = 0` -- el valor por defecto --
--     poner el grupo en botin libre, que es justo lo que hace ApplyFreeLoot,
--     APAGA el loot de todos los bots. Las dos mitades de la peticion se
--     estorbaban. Se arregla en `playerbots.conf` con FreeMethodLoot = 1; sin
--     eso, esto no hace nada y no hay forma de notarlo desde el cliente.
--
-- SIN PASAR POR EL CHAT, desde 2026-08-22 (PRUEBAS-11 D1: "quiero que sea una
-- orden por defecto, no que tengan que susurrarlo en el chat cada vez").
--
-- Tenia razon y ademas el reproche era exacto: todas las demas ordenes dejaron
-- el chat hace tres etapas, y esta se quedo atras sin ningun motivo. El motivo
-- que YO creia -- que mod-rts no puede hablar con playerbots -- resulto ser
-- falso al mirarlo: `RtsOrders.cpp` ya incluye `PlayerbotAI.h` y lee y escribe
-- el contexto de la IA para mover bots. La estrategia de botin es un valor mas
-- de ese contexto, asi que se pone directamente (verbo `LOOT`), sin chat, sin
-- retardo de cola y sin que se vea.
--
-- El chat se queda SOLO como respaldo para un servidor sin mod-rts. Ahi no hay
-- otra forma, y es mejor una linea fea que un botin que no funciona.
--
-- Se repite al cambiar el grupo en los dos caminos, porque la estrategia vive
-- en la memoria de cada bot y uno que entra despues nace con la de fabrica.
-- Eso no es un apano: es lo mismo que hace el metodo de botin del grupo.
R.lootAll = true

function R:CameraOn()
	-- EL PUPPET YA NO SE ENCIENDE, y aqui esta por que estuvo encendido.

	-- Se prendia como *active mover*, no como camara: **el cliente esconde a
	-- quien es su active mover**, asi que con la criatura invisible haciendo de
	-- mover tu cuerpo era una unidad mas y se dibujaba. Era el tercero de los
	-- tres apaños del heroe invisible, y el unico que llego a estar puesto.

	-- Sobra desde que el problema esta resuelto de raiz: `SelfShow.cpp` parchea
	-- los cinco bytes de `0x006E085C` y se arma solo con los flags, o sea que te
	-- ve dibujado sin necesidad de que otro sea el mover. Quitarlo se dejo para
	-- un paso propio (2026-09-10) en vez de hacerlo a la vez que la restauracion:
	-- un fallo con dos causas posibles no se diagnostica, se adivina.

	-- Lo que sostiene que se pueda quitar es la TERCERA CONDICION de
	-- `rts::orders::MoveSelf`. Las dos primeras preguntan por una posesion, que
	-- es como el Puppet cumplia el requisito; la camara de comentarista no posee
	-- nada y quita el control por el otro camino, asi que sin
	-- `camera::IsSpectating` en esa guarda tu propio heroe se queda inordenable.
	-- Esa linea entro con la restauracion y por eso esto es seguro hoy y no antes.

	-- `CameraOff` SI sigue llamando a `ns.Camera:Off()`: el Puppet se puede haber
	-- encendido a mano con `/rts cam on`, y la salida tiene que devolverlo igual.

	-- Los flags primero: tardan un tick de mundo en llegar al cliente, y hasta
	-- que llegan la API de la camara libre no responde. Se espera a que el
	-- CLIENTE lo confirme en vez de adivinar un retraso -- `WaitGate` sondea
	-- `CommentatorGetCamera`, que contesta en cuanto la puerta se abre.
	--
	-- EL GATE VA ANTES DE PEDIR NADA, y no es prudencia: `CAM SPEC` contra un
	-- mod-rts viejo **no da error, no contesta**, asi que la secuencia se queda
	-- colgada en `WaitGate` y acaba diciendo "el cliente no abrio la camara
	-- libre" -- culpando al cliente de que el worldserver no se ha reiniciado.
	-- Un diagnostico que apunta al sitio equivocado cuesta la ronda entera.
	if not ns.Link:ServerAtLeast(46) then
		ns.Print(("|cffff0000camara:|r la camara libre necesita mod-rts 0.46.0 y hay %s.")
			:format(tostring(ns.Link.serverVersion or "ninguno")))
		-- Y SE CAE AL PUPPET, que desde hoy no se enciende solo. Sin esta linea
		-- el modo RTS con un servidor viejo se quedaria **sin camara ninguna**:
		-- la libre no puede armarse y la de siempre ya no viene puesta de antes.
		ns.Print("  Reinicia el worldserver. Mientras, la camara de siempre.")
		ns.Camera:On()
		return
	end

	ns.Camera:Spectate(true, function()
		ns.Camera:WaitGate(12,
			function()
				-- Coloca ANTES de armar. El estado de esa camara empieza sin
				-- inicializar, asi que armar el modo sin haberla colocado
				-- dibuja desde memoria vieja: la primera vez salio en otro
				-- continente y por debajo del suelo.
				if not ns.FreeCam:Start() then
					-- SE DESHACE LO PEDIDO Y SE CAE AL PUPPET. Los flags ya estan
					-- puestos a estas alturas, y dejarlos con la camara sin armar es
					-- quedarse en tierra de nadie: sin camara libre y con el estado de
					-- espectador encendido. Desde que el Puppet no viene puesto de
					-- antes, este camino tiene que traerselo el.
					ns.Print("|cffff8800camara:|r no pude arrancar la camara libre; " ..
						"me quedo con la de siempre.")
					ns.Camera:Spectate(false)
					ns.Camera:On()
					return
				end
				-- El modelo lo pide `FreeCam:Start` por su cuenta: colgarlo de
				-- esta respuesta lo dejaba invisible para siempre con un
				-- mod-rts que no conociera `SPECARM`, sin decir nada.
				ns.Camera:Arm(true)
			end,
			function()
				ns.Print("|cffff0000camara:|r el cliente no abrio la camara libre.")
				-- Y LA PRIMERA SOSPECHA ES EL DLL, desde mod-rts 0.48.0. El bit 19
				-- que abre esa puerta ya no lo manda el servidor -- el nucleo prohibe
				-- atacar a quien lo lleve (`Unit.cpp:10762`) -- asi que lo escribe
				-- `rts_core` en la memoria del cliente. Sin inyectar, ese bit no
				-- existe en ninguna parte y la puerta no abre nunca. Se dice aqui
				-- porque el sintoma (una espera de doce intentos que se agota) no se
				-- parece en nada a "falta el DLL".
				if RTS_Ready ~= 1 then
					ns.Print("  |cffff0000El DLL no esta inyectado|r, y desde 0.48.0 la " ..
						"camara libre lo necesita. Abre el juego con |cffffff002-Jugar.bat|r.")
				end
				ns.Print("  |cffffff00/rts cam probe|r dice en que paso se queda.")
				-- Igual que arriba: quitar los flags y traerse el Puppet. Antes esta
				-- rama se podia permitir solo quejarse porque la camara de siempre ya
				-- estaba encendida desde el principio de `CameraOn`.
				ns.Camera:Spectate(false)
				ns.Camera:On()
			end)
	end)
end

function R:CameraOff()
	ns.FreeCam:Stop()
	-- `Spectate(false)` quita los flags Y manda el paquete de modo normal, asi
	-- que es la salida completa aunque el armado se hubiera quedado a medias.
	ns.Camera:Spectate(false)
	-- Y la camara de siempre, por si estaba puesta a mano con `/rts cam on`.
	ns.Camera:Off()
end

function R:ApplyLootAll(quiet)
    if not self.lootAll then return end
    if GetNumPartyMembers() == 0 and GetNumRaidMembers() == 0 then return end

    if ns.Orders:HasServer() then
        ns.SendServer("LOOT 1")
        if not quiet then
            ns.Print("botin de los bots: |cff00ff00TODO|r, grises incluidos")
        end
        return
    end

    ns.Orders:Broadcast("ll all", quiet and nil
        or "botin de los bots: |cff00ff00TODO|r, grises incluidos (por chat: " ..
           "mod-rts no responde)")
end

-- ESPERAR A QUE EL SERVIDOR CONTESTE ANTES DE DECIDIR POR DONDE MANDARLO.
--
-- `HasServer()` se pone a true con la PRIMERA respuesta de mod-rts, y esa
-- respuesta es un viaje de ida y vuelta que todavia no ha llegado cuando se
-- entra en modo RTS. Aplicar en ese instante en la primera entrada de la sesion
-- elegiria el respaldo de chat teniendo mod-rts delante -- y se veria como que
-- el arreglo no se aplico.
--
-- EL BUCLE QUE HABIA AQUI ES AHORA `Link:WhenServer`. Era una de cuatro copias
-- del mismo `si contesta o han pasado 2,5 s`; las otras tres estaban en el
-- recordatorio de `Marks` y en las filas de habilidades y roles de la sala.
--
-- LA GUARDA DE `R.active` SE QUEDA, y es lo unico que no podia irse a la
-- funcion comun: si sales del modo mientras se espera, la estrategia de botin
-- ya no se quiere. Un temporizador que dispara despues de que su motivo haya
-- desaparecido es su propio fallo -- la misma regla que cancela la salida
-- aplazada de `Chrome` si vuelves a entrar.
function R:ApplyLootAllSoon()
    if not self.lootAll then return end
    ns.Link:WhenServer(function()
        if R.active and R.lootAll then R:ApplyLootAll(true) end
    end)
end

--- QUE LA IA NO TOQUE LAS MISIONES ------------------------------------------
--
-- Hermano del botin, y por la misma razon exacta: es estado de la IA de cada
-- bot, vive en su memoria, y hay que reponerlo cuando el grupo cambia porque el
-- que entra nace con la de fabrica.
--
-- Lo que apaga y por que -- la estrategia `quest` de mod-playerbots entrega
-- sola al ABRIR la ventana de un PNJ, sin que pulses nada -- esta escrito
-- entero en `mod-rts/src/RtsQuests.h`, con las lineas de playerbots delante.
--
-- NO HAY RESPALDO POR CHAT Y ES DELIBERADO. Seria `nc -quest` susurrado a cada
-- bot, o sea cuatro lineas de chat cada vez que cambia el grupo, para tapar un
-- defecto que solo se nota cuando hay servidor. Sin mod-rts esto no se aplica y
-- la entrega automatica de playerbots vuelve -- que es exactamente lo que
-- habia antes, no una regresion nueva.
R.questAI = false

function R:ApplyQuestAI()
    if GetNumPartyMembers() == 0 and GetNumRaidMembers() == 0 then return end
    if not ns.Orders:HasServer() then return end

    -- SE AVISA AL ENTRAR Y NO SOLO AL FALLAR UN GESTO. Un verbo que el servidor
    -- no conoce no da error: no contesta. Asi que un worldserver sin reiniciar
    -- se ve igual que un addon roto, y eso ya costo una ronda entera.
    if not ns.Link:ServerAtLeast(45) then
        ns.Print(("|cffff0000RTS: mod-rts es %s; las misiones necesitan 0.45.0.|r"):format(
            tostring(ns.Link.serverVersion)))
        ns.Print("Reinicia el worldserver: hasta entonces los bots entregan solos.")
        return
    end

    ns.SendServer(self.questAI and "QAI 1" or "QAI 0")
end

function R:ApplyQuestAISoon()
    ns.Link:WhenServer(function()
        if R.active then R:ApplyQuestAI() end
    end)
end

function R:ToggleLootAll()
    self.lootAll = not self.lootAll
    RTSCommandDB.lootAll = self.lootAll

    if self.lootAll then
        self:ApplyLootAll()
        return
    end

    if ns.Orders:HasServer() then
        ns.SendServer("LOOT 0")
    else
        ns.Orders:Broadcast("ll normal")
    end
    ns.Print("botin de los bots: |cffffff00solo lo util|r")
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
-- Va por comando de chat y no por mod-rts porque el comando ya existe y lo
-- mantiene playerbots: replicarlo seria trabajo por un interruptor.
--
-- OJO, LA RAZON QUE AQUI PONIA ANTES ERA FALSA. Decia que hacerlo en mod-rts
-- "obligaria a enlazar contra las cabeceras de playerbots y ataria dos modulos
-- que hoy no se conocen". Ya se conocen, y ya se conocian cuando se escribio:
-- `RtsOrders.cpp` incluye `PlayerbotAI.h` y lee y escribe el contexto de la IA
-- para mover bots. Creerse esa frase costo que la estrategia de botin siguiera
-- saliendo por el chat una etapa entera de mas (PRUEBAS-11 D1). Si alguna vez
-- hace falta mover ESTO al servidor, no hay ningun impedimento tecnico -- solo
-- que no compensa.
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
-- Y QUE TAMPOCO TOQUE TUS MISIONES, por lo mismo y con el mismo susurro.
--
-- "al hablar con el npc, me ha cogido la quest tal cual". La estrategia `quest`
-- es la que responde al "gossip hello" que manda TU cliente al hablar con un
-- PNJ, y con el selfbot puesto eso llega a tu propia IA. Lo que hace ahi es
-- `TalkToQuestGiverAction`, que ENTREGA sola lo que tengas completado -- y elige
-- la recompensa por ti cuando hay una sola -- sin que veas la ventana. O sea el
-- mismo defecto que el loot, en la otra mitad del dialogo.
--
-- QUE ADEMAS SEA LA QUE ACEPTA NO ESTA DEMOSTRADO, y esta dicho asi en
-- `Quests.lua`: leyendo, esa accion no acepta nada. Es el sospechoso con mas
-- papeletas -- es la unica maquinaria de misiones que el modo RTS le engancha a
-- tu personaje -- y quitarla es una palabra en un susurro que ya se manda. Si
-- despues de esto la mision sigue entrando sola, el aviso de `Quests.lua` lo
-- dira y el culpable esta en otro sitio.
--
-- EL SUSURRO SE QUEDA AUNQUE `QAI` HAGA LO MISMO, y no es duplicado por
-- descuido: `QAI` necesita mod-rts, y este camino no. Lo que si hace falta es
-- que los dos digan lo mismo, asi que respeta el interruptor de `/rts quests
-- ai` en vez de apagarlo siempre -- si no, volver a encender la IA de misiones
-- se la devolveria a los bots y no a ti, que es la clase de discrepancia que
-- luego se lee como "a mi personaje le pasa otra cosa".
-- Y LA TERCERA, QUE ES LA QUE CERRABA LA VENTANA DE BOTIN (2026-09-12).
--
-- Sintoma: *"cuando voy a lootear a un bicho me sale un frame el loot del bicho
-- y al instante se esconde"*. Medido con la sonda de `Loot.lua`: la ventana se
-- abre y entre 80 y 130 ms despues llega `LOOT_CLOSED`, sin recoger un solo
-- hueco y con el cliente viendote a menos de cinco metros del cuerpo. O sea que
-- el botin se SUELTA, y lo suelta tu propia IA:
--
--     SMSG_LOOT_RESPONSE
--       -> disparador "loot response"      (PlayerbotAI.cpp:189)
--       -> accion "store loot"             (WorldPacketHandlerStrategy.cpp:40)
--       -> StoreLootAction::Execute, que mira objeto por objeto, se queda con
--          lo que su estrategia permita... y ACABE COMO ACABE termina mandando
--          CMSG_LOOT_RELEASE (LootAction.cpp:459).
--
-- Los 100 ms son su tick de reaccion. Y el `-loot` de arriba NO lo tapa, que es
-- lo que despistaba: `store loot` no cuelga de la estrategia `loot` -- esa es la
-- que hace que un bot vaya andando hasta el cadaver -- sino de `default`, que es
-- el manejador de paquetes y lo lleva todo el mundo que tenga IA.
--
-- QUE SE PIERDE AL QUITARLA, dicho entero porque no es gratis: `default` es
-- tambien quien acepta solo las invitaciones de grupo, los intercambios y las
-- hermandades, quien entrega misiones al abrir el dialogo, quien te levanta del
-- suelo al morir y quien hace el mantenimiento al subir de nivel. Todo eso son
-- cosas que un jugador de verdad hace por su cuenta con su interfaz -- y varias
-- de ellas son quejas viejas de este mismo fichero ("me ha cogido la quest tal
-- cual"). Los BOTS no se enteran: esto va por susurro y el susurro llega solo a
-- tu IA.
--
-- Va en los dos motores. El botin casi siempre se abre fuera de combate, pero
-- con cinco bots peleando alrededor "fuera de combate" no es donde uno cree, y
-- si el motor de combate es el activo el disparador sale igual por ahi.
local function SelfSoloStrategies(on)
    local quest = (on or R.questAI) and "+quest" or "-quest"
    SendChatMessage((on and "nc +loot,+gather," or "nc -loot,-gather,") .. quest,
                    "WHISPER", nil, ns.MyName())
    SendChatMessage(on and "nc +default" or "nc -default", "WHISPER", nil, ns.MyName())
    SendChatMessage(on and "co +default" or "co -default", "WHISPER", nil, ns.MyName())
end

function R:SelfBotSet(want, quiet)
    -- CON mod-rts NO SE LLEVA LA CUENTA: SE DICE EL ESTADO.
    --
    -- `AUTO <0|1>` pide el estado que quieres, no "lo contrario de lo que
    -- haya", y contesta con el que ha quedado. Eso mata el fallo que el
    -- comentario de arriba describe y que la cuenta a mano no podia evitar:
    -- despues de un `/reload` `on` vuelve a false con la IA TODAVIA enganchada,
    -- asi que el siguiente encendido mandaba el toggle y la QUITABA -- tu heroe
    -- dejaba de pelear solo justo al entrar en el modo que lo pide.
    --
    -- El susurro sigue de respaldo para cuando no hay mod-rts delante, que es
    -- donde era la unica forma.
    if ns.Link:HasServer() then
        self.selfBot.quiet = quiet and true or false
        ns.SendServer("AUTO " .. (want and "1" or "0"))
        return
    end

    if self.selfBot.on == want then return end
    SelfBotCommand()
    self.selfBot.on = want

    -- Despues de encender: la IA acaba de nacer con sus estrategias por
    -- defecto puestas, asi que hay que quitarle el loot y las misiones ahora, no antes.
    SelfSoloStrategies(not want)
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
    if ns.Link:HasServer() then
        ns.Print("Lo dice el servidor (|cffffff00AUTO|r), no una cuenta nuestra.")
    else
        ns.Print("Sin mod-rts se lleva la cuenta a mano: el comando no devuelve estado.")
        ns.Print("Si no cuadra con lo que ves, |cffffff00/rts self|r lo realinea.")
    end
end

--- Toggle ------------------------------------------------------------------

-- RTS mode is ONE switch, not a set of things to remember to turn on.
-- Toggling it brings up the mouse layer AND the detached camera, and drops both
-- again on the way out. Anything else the mode needs belongs here too.
function R:Toggle()
	EnsureFrames()
	self.active = not self.active

	if self.active then
		-- Vuelves a entrar: si quedaba una salida aplazada por combate, se
		-- cancela, y el espejo de hechizos sobra -- la consola vuelve a estar.
		self.pendingLeave = false
		ns.Standby:Hide()
		catcher:Show()
		catcher:EnableMouse(false)
		self:CameraOn()
		ns.Print("|cff00ff00Modo RTS ON|r - el raton va normal: pasar por encima ilumina,")
		ns.Print("click selecciona, |cffffff00doble click|r selecciona a todos, click derecho ordena.")
		ns.Print("|cffffff00Ctrl + arrastrar|r = caja de seleccion.")

		-- SIN rts_core EL MODO ENTRA IGUAL Y HACE LA MITAD, Y ESO NO SE VEIA.
		--
		-- Sin DLL no hay aros (el canal no publica nada porque no hay lista de
		-- unidades) y **no hay ordenes al suelo**: `CursorGroundPoint` sale por
		-- `RTS_HasCam ~= 1` en su primera linea. Lo que queda en pie es
		-- justamente lo que vive solo en Lua -- seleccionar, la consola, la
		-- camara -- asi que la pantalla ensena: seleccion multiple que funciona,
		-- UN aro (el del cliente, bajo tu objetivo) y unidades que no se mueven.
		--
		-- Ese cuadro es indistinguible de "el addon esta roto", y costo una
		-- ronda entera confundirlo con un fallo del arreglo del dia. Un estado
		-- degradado que no se anuncia es peor que uno que falla.
		if RTS_Ready ~= 1 then
			ns.Print("|cffff0000rts_core NO esta inyectado.|r Sin el no hay aros de " ..
			         "seleccion ni ordenes al suelo: los bots no se moveran.")
			ns.Print("Cierra el juego y abrelo con |cffffff00rts-tools\\2-Jugar.bat|r, " ..
			         "o comprueba con |cffffff00/rts native|r.")
		end

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
		if self.selfBot.auto then
			self:SelfBotSet(true, true)
			-- Y LOS SUSURROS DE ESTRATEGIA SIEMPRE, aunque `SelfBotSet` crea
			-- que no hay nada que cambiar. Despues de un `/reload` la cuenta
			-- de `on` vuelve a false mientras la IA de verdad sigue
			-- enganchada, y ahi el early-return se come justo lo que hace
			-- falta -- que es como el cierre de la ventana de botin podia
			-- volver sin que nada hubiera cambiado. Mandarlos de mas no
			-- cuesta nada: quitar una estrategia que ya no esta es no hacer
			-- nada, y sin IA el susurro no lo lee nadie.
			SelfSoloStrategies(false)
		end
		self:ApplyFreeLoot(true)
		self:ApplyLootAllSoon()
		self:ApplyQuestAISoon()
		-- El aspecto de los marcadores de ruta vive en el servidor y se pierde
		-- al desconectar, asi que el addon -- que es donde persisten los
		-- ajustes -- se lo recuerda. Con la misma espera que el botin y por el
		-- mismo motivo, que ahora esta escrito una sola vez en `Link`.
		if ns.Marks then
			ns.Link:WhenServer(function() ns.Marks:Apply() end)
		end

		-- LA BARRA VA ANTES QUE CHROME, y ahora importa mas que antes: `Tray`
		-- reparenta los micro-botones del cliente a su fila, y si Chrome
		-- escondiera `MainMenuBar` primero se los llevaria por delante siendo
		-- todavia hijos suyos.
		ns.Dock:Enter()
		ns.Chrome:Enter()
	else
		-- SALIR EN COMBATE NO PUEDE DEVOLVER LA INTERFAZ, y por eso se sale en
		-- dos mitades. Ver LeaveChrome mas abajo.
		self:LeaveWorld()
		self:LeaveChrome()
	end
end

--- Salir, en dos mitades ---------------------------------------------------
--
-- PRUEBAS-11 G8: "salir en combate no me devuelve mi UI en primera persona".
-- Correcto, y no es un fallo que se pueda arreglar: PlayerFrame, MainMenuBar y
-- las barras de accion son frames PROTEGIDOS, y `Show()` sobre un frame
-- protegido dentro de combate lo bloquea el cliente. Chrome ya lo sabia y
-- aplazaba esa mitad a PLAYER_REGEN_ENABLED -- pero el resto de la salida se
-- hacia igual, asi que te quedabas con la camara en tu personaje y SIN NINGUNA
-- interfaz hasta que acabara la pelea. Lo peor de las dos opciones.
--
-- Asi que la salida se parte por donde de verdad esta la costura:
--
--   LeaveWorld    la camara, el raton, el selfbot, el modo mando. Nada de esto
--                 esta protegido, asi que vuelve SIEMPRE y al instante: en
--                 cuanto pulsas Salir estas otra vez detras de tu personaje.
--   LeaveChrome   la consola y los frames de Blizzard. En combate se aplaza.
--
-- Mientras dura el aplazamiento te quedas con LA CONSOLA RTS puesta. Desde
-- 2026-09-02 eso es el minimapa, los railes y la rejilla de ordenes: la sala
-- del medio -- vida, poder, grupo, enemigos, habilidades -- esta vacia mientras
-- se redisena, asi que este consuelo es hoy mas pequeno de lo que era. Y las
-- teclas de la barra de accion siguen
-- funcionando con la barra escondida -- es lo mismo que pasa con el Alt-Z del
-- propio juego -- asi que puedes seguir peleando con el teclado. Al acabar el
-- combate la interfaz de Blizzard vuelve sola.

function R:LeaveWorld()
	catcher:Hide()
	ReleaseCapture()
	down.button = nil
	-- Leaving mid-drag would strand the client outside mouselook with the
	-- button still held. Same rule as the CVars: RTS mode only affects RTS
	-- mode, and that includes how it ends.
	if IsMouselooking() then MouselookStop() end
	-- Las rutas dibujadas no tienen sentido fuera del modo, y ademas seguirian
	-- mandando tramos a los bots desde una interfaz que ya no se ve.
	if ns.Route then ns.Route:ClearAll() end
	-- Devolver el personaje ANTES de soltar la camara, para que no quede un
	-- instante en el que la IA lo lleva y tu ya has vuelto a el.
	self:SelfBotSet(false, true)
	self:CameraOff()
end

local regen

function R:LeaveChrome()
	-- LA BARRA SE VA SIEMPRE, y este es el cambio de 2026-08-23. Es NUESTRA:
	-- frames corrientes, sin proteger, asi que esconderla en combate es legal y
	-- no hay ningun motivo para dejarla puesta. La primera version la mantenia
	-- de sustituta durante la pelea y no era lo que se pedia -- se pedia salir.
	--
	-- CON UNA EXCEPCION QUE SE RESUELVE SOLA: los micro-botones del cliente que
	-- `Tray` tiene prestados SI estan protegidos, asi que en combate no se
	-- pueden devolver. `Tray:Leave` lo aplaza a PLAYER_REGEN_ENABLED igual que
	-- hace el resto de este fichero.
	ns.Dock:Leave()

	if InCombatLockdown() then
		self.pendingLeave = true
		-- Y en su lugar, tus hechizos en su sitio: un espejo de tus barras de
		-- accion, dibujado en el rectangulo exacto de cada boton real. No lanza
		-- -- para eso tendria que ser un frame seguro, y un frame seguro no se
		-- puede ensenar en combate, que es el unico momento en que esto existe.
		-- Las teclas si funcionan, con las barras escondidas, igual que con el
		-- Alt-Z del juego.
		ns.Standby:Show()
		if not regen then
			regen = CreateFrame("Frame", "RTSModeRegen")
			regen:RegisterEvent("PLAYER_REGEN_ENABLED")
			regen:SetScript("OnEvent", function()
				if not R.pendingLeave then return end
				R.pendingLeave = false
				-- Si has vuelto a ENTRAR en modo RTS mientras duraba la pelea,
				-- la salida aplazada ya no toca: completarla ahora desmontaria
				-- la consola que acabas de encender. Es la misma clase de fallo
				-- que un temporizador que dispara despues de que su motivo haya
				-- desaparecido.
				if R.active then return end
				R:LeaveChrome()
			end)
		end
		ns.Print("|cffffff00Estas en combate.|r La camara ya es tuya y la consola " ..
			"se ha ido; las barras de Blizzard son frames protegidos y el " ..
			"cliente no deja devolverlas hasta que acabe la pelea.")
		ns.Print("Te dejo tus hechizos en su sitio para poder verlos. " ..
			"|cffffff00Las teclas funcionan|r. La interfaz normal vuelve sola " ..
			"al salir de combate.")
		return
	end

	self.pendingLeave = false
	ns.Standby:Hide()
	ns.Chrome:Leave()
	ns.Print("|cffff0000Modo RTS OFF|r - controles normales.")
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

--- Que hay bajo el cursor, segun el servidor ------------------------------
--
-- La respuesta a `WHAT <guid>`: la clasificacion que hace el SERVIDOR de lo que
-- se pincho -- hostil, amistoso, cadaver. Es el camino lento; el rapido es el
-- mouseover del cliente, y este solo entra cuando aquel no sabe.
--
-- EL FORMATO SE VALIDA, y aqui hace falta de verdad: `WHAT` se dice en los dos
-- sentidos. Nuestra propia peticion es `WHAT <hex>` y vuelve a nosotros por el
-- mismo canal; la respuesta trae ademas el digito del tipo, y ese `(%d)` es lo
-- unico que las distingue.
ns.Link:On("WHAT", function(rest)
	local guid, kind = rest:match("^(%S+) (%d)$")
	if guid then R:OnKind(guid, tonumber(kind)) end
end)

-- EL SELFBOT, DICHO POR EL SERVIDOR. Otro verbo de doble sentido: la peticion
-- es `AUTO <0|1>` y la respuesta `AUTO <0|1> ok`, o sea que el discriminante es
-- el numero de campos -- mismo truco que `BAGS` y por el mismo motivo, que nos
-- oimos a nosotros mismos.
--
-- Y MANDA LO QUE CONTESTA, NO LO QUE PEDIMOS: el servidor puede negarse (su
-- `SelfBotLevel` decide), y en ese caso la cuenta tiene que quedarse en lo que
-- de verdad hay, no en lo que quisimos.
ns.Link:On("AUTO", function(rest)
	local state = rest:match("^([01])%s+%S+$")
	if not state then return end

	local on = (state == "1")
	local changed = (R.selfBot.on ~= on)
	R.selfBot.on = on

	-- LAS ESTRATEGIAS, DESPUES Y NO ANTES: la IA acaba de nacer con las suyas
	-- por defecto puestas, y lo que hay que quitarle (botin, misiones, el
	-- manejador de paquetes) solo existe una vez esta enganchada.
	SelfSoloStrategies(not on)

	if changed and not R.selfBot.quiet then
		ns.Print("selfbot " .. (on and "|cff00ff00ON|r - tu personaje pelea solo"
		                          or "|cffff0000OFF|r - vuelves a llevarlo tu"))
	end
	R.selfBot.quiet = nil

	-- Y LA FILA DE ROL CAMBIA DE CAMINO CON ESTO: con IA el rol es el de su
	-- motor de combate y con ella fuera vuelve a ser la postura. Lo que
	-- supieramos de tu heroe ya no vale.
	if ns.Roles then ns.Roles:Recheck() end
end)

