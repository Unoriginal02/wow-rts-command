--[[
	Selection.lua -- who is currently under command.

	Selection is stored as a list of NAMES, not unit tokens. Tokens ("party2")
	shuffle whenever the group changes, and every order we send is addressed by
	name anyway (whisper), so names are the stable identity.

	Anything that changes selection fires ns.Selection:Notify(), which the UI
	layers subscribe to. No UI code reaches into this table directly.
]]

local ADDON, ns = ...

local S = {}
ns.Selection = S

S.selected = {}      -- array of names, ordered
S.listeners = {}

-- EL PRIMARIO: DE QUIEN ES LA BARRA DE HABILIDADES, que NO es lo mismo que a
-- quien van las ordenes.
--
-- Del video: *"if we hit tab, we get the command bar for the next person in the
-- group WITHOUT DESELECTING"*. Son dos conceptos y hasta ahora aqui solo habia
-- uno: la seleccion decidia las dos cosas, asi que ver las habilidades del mago
-- obligaba a dejar de mandar sobre el grupo.
--
-- Separarlos es lo que hace posible el gesto de RTS de verdad: el grupo entero
-- cogido y atacando, y tu hojeando las habilidades de cada uno con Tab para
-- lanzar UNA cosa concreta sin soltar a nadie.
--
-- La regla de coherencia, y es lo unico delicado: **seleccionar a UNO le hace
-- primario**. Si no, pinchar un bot ensenaria las habilidades de otro, que se
-- lee como que la barra esta rota. Seleccionar a VARIOS no toca el primario:
-- ahi el jugador no ha dicho nada sobre quien le interesa.
S.primary = nil

--- Roster ------------------------------------------------------------------

-- Every commandable group member (everyone but you). On a solo/bot server this
-- is exactly the bot party.
function S:GetRoster()
	local roster = {}
	local raid = GetNumRaidMembers()

	if raid > 0 then
		for i = 1, raid do
			local unit = "raid" .. i
			if UnitExists(unit) and not UnitIsUnit(unit, "player") then
				local n = UnitName(unit)
				ns.NoteClass(n, unit)
				tinsert(roster, { name = n, unit = unit })
			end
		end
	else
		for i = 1, GetNumPartyMembers() do
			local unit = "party" .. i
			if UnitExists(unit) then
				-- SE APUNTA LA CLASE DE CADA COMPANERO AL PASAR. Es lo que
				-- permite saber la TUYA despues de un cambio de personaje: el
				-- que ahora eres estaba aqui hace un segundo, y para un
				-- `partyN` el cliente si mira el objeto. Ver `ns.MyClass`.
				local n = UnitName(unit)
				ns.NoteClass(n, unit)
				tinsert(roster, { name = n, unit = unit })
			end
		end
	end

	return roster
end

-- The roster INCLUDING your own character, which in RTS mode is a unit like
-- any other -- selectable, orderable, commandable. You go last so the bots keep
-- the slot numbers your fingers already know.
--
-- Kept separate from GetRoster because that one means "everyone I command by
-- whispering", and whispering yourself is not a thing. The unit bar and the
-- mouse handler want this list; the order dispatcher wants the other.
function S:GetRosterWithPlayer()
	local roster = self:GetRoster()
	tinsert(roster, { name = ns.MyName(), unit = "player", isPlayer = true })
	return roster
end

-- LA MISMA LISTA CON EL HEROE EL PRIMERO, que es lo que pide §3/§6 del brief:
-- *"el heroe activo es siempre el primer item de la lista"*.
--
-- No sustituye a `GetRosterWithPlayer`, que deja al jugador el ULTIMO a
-- proposito -- ahi el orden lo fijan las teclas de control de grupo que los
-- dedos ya tienen aprendidas, y cambiarlo movería los bots un sitio. Esta es
-- para DIBUJAR, donde lo que manda es que el heroe se lea primero.
--
-- Y "el heroe" es quien seas AHORA, no con quien entraste: despues de un cambio
-- de personaje el primero de la lista es el nuevo. `ns.MyName()` es el unico
-- sitio que contesta eso bien -- `UnitName("player")` sale de un buffer que
-- solo rellena la pantalla de seleccion y se queda con el nombre de la sesion
-- para siempre.
function S:GetRosterHeroFirst()
	local out = { { name = ns.MyName(), unit = "player", isPlayer = true } }
	for _, m in ipairs(self:GetRoster()) do
		tinsert(out, m)
	end
	return out
end

-- name -> unit token, or nil if they left the group.
-- In RTS mode your own character is selectable, so the player matches too.
--
-- EL GRUPO SE MIRA PRIMERO, Y EL ORDEN ES EL ARREGLO. Antes se comparaba con
-- `ns.MyName()` antes que nada, y eso convierte cualquier coincidencia de
-- nombre en "ese eres tu". Despues de un cambio de personaje hay un compañero
-- que se llama como te llamabas -- es literalmente el heroe que acabas de dejar,
-- que vuelve de bot -- asi que pinchar a ESE bot resolvia a `player`.
--
-- El sintoma no se parecia a la causa: seleccionabas al bot y quedabais
-- seleccionados los dos, y el boton de Control decia "selecciona a un compañero
-- primero" sobre alguien que si lo era. Con el grupo delante, un nombre que este
-- en el grupo resuelve a su unidad del grupo, que es lo unico que puede ser.
function S:UnitFor(name)
	for _, m in ipairs(self:GetRoster()) do
		if m.name == name then return m.unit end
	end
	if name == ns.MyName() then return "player" end
	return nil
end

--- Queries -----------------------------------------------------------------

function S:Get()
	return self.selected
end

function S:Count()
	return #self.selected
end

function S:IsEmpty()
	return #self.selected == 0
end

function S:IsSelected(name)
	for _, n in ipairs(self.selected) do
		if n == name then return true end
	end
	return false
end

-- The single selected unit, or nil when 0 or many are selected.
-- The command card uses this to decide whether to show per-unit detail.
function S:Single()
	if #self.selected == 1 then return self.selected[1] end
	return nil
end

--- Mutation ----------------------------------------------------------------

function S:Set(names)
	self.selected = {}
	for _, n in ipairs(names or {}) do
		tinsert(self.selected, n)
	end
	-- Uno solo: ese pasa a ser el primario. Varios o ninguno: el primario se
	-- queda como estaba, salvo que ya no este en el grupo (`Prune` lo revisa).
	if #self.selected == 1 then
		self.primary = self.selected[1]
	end
	self:Notify()
end

--- El primario -------------------------------------------------------------

function S:GetPrimary()
	-- Sin primario elegido, el tuyo. Es lo que hace que la fila de habilidades
	-- nunca este vacia nada mas entrar.
	if self.primary then return self.primary end
	return ns.MyName()
end

-- SIN LLAMANTE DESDE LA 0.77.0, y dicho aqui para que no se busque uno.
--
-- El unico gesto que lo usaba era el click derecho sobre una fila del grupo, y
-- `PRUEBAS-23` A5 lo mando quitar. El primario se pone solo, en `Set`, cuando
-- hay exactamente uno seleccionado.
--
-- Se queda porque es inerte: un `set` que nadie llama no puede armarse a si
-- mismo, que es la diferencia con la retencion de altura de camara -- aquella
-- tenia su interruptor GUARDADO en las SavedVariables y se encendia sola.
function S:SetPrimary(name)
	if not name or self.primary == name then return end
	self.primary = name
	self:Notify()
end


function S:SelectOnly(name)
	self:Set({ name })
end

function S:Add(name)
	if not self:IsSelected(name) then
		tinsert(self.selected, name)
		self:Notify()
	end
end

function S:Remove(name)
	for i, n in ipairs(self.selected) do
		if n == name then
			tremove(self.selected, i)
			self:Notify()
			return
		end
	end
end

function S:Toggle(name)
	if self:IsSelected(name) then self:Remove(name) else self:Add(name) end
end

--- El gesto de seleccionar, en un solo sitio ------------------------------
--
-- Click = solo esa, shift o ctrl = sumar, DOBLE CLICK = todas. Lo usan las
-- filas del grupo, el retrato del heroe y sus barras, o sea todos los sitios de
-- la consola donde se puede pinchar una unidad.
--
-- ESTA AQUI Y NO EN CADA PANEL porque si no la ventana del doble click seria de
-- cada panel por separado: pinchar un bot en su fila y luego el retrato del
-- heroe contaria como doble click en dos sitios distintos a la vez. Con un solo
-- reloj y un solo nombre, dos clicks solo son un doble click si son sobre LA
-- MISMA unidad, que es lo que espera cualquiera.
--
-- WoW no da evento de doble click en estos frames, asi que se mide a mano. La
-- ventana es la misma que usa el mundo en RTSMode.lua, algo por debajo del
-- medio segundo de Windows para que dos ordenes seguidas no se confundan.
local DOUBLE_CLICK = 0.40
local lastName, lastAt

function S:Click(name)
	if not name then return end

	if IsShiftKeyDown() or IsControlKeyDown() then
		self:Toggle(name)
		lastName, lastAt = name, GetTime()
		return
	end

	local now = GetTime()
	if lastName == name and lastAt and (now - lastAt) < DOUBLE_CLICK then
		self:SelectAll()
		lastName, lastAt = nil, nil     -- que un triple click no reabra la cuenta
		return
	end

	self:SelectOnly(name)
	lastName, lastAt = name, now
end

function S:Clear()
	if #self.selected > 0 then
		self.selected = {}
		self:Notify()
	end
end

function S:SelectAll()
	local names = {}
	for _, m in ipairs(self:GetRosterWithPlayer()) do
		tinsert(names, m.name)
	end
	self:Set(names)
end

-- Drop anyone who has left the group. Called on roster events.
-- ERES OTRO. Se llama al entrar en el mundo, que con el cambio de personaje ya
-- no significa solo "acabo de conectarme".
--
-- `Prune` no sirve para esto y por eso hace falta esta: `Prune` quita lo que ya
-- no esta en el grupo, y despues de un cambio **lo seleccionado si esta** -- es
-- justo el compañero al que acabas de saltar, que ahora eres tu. La seleccion
-- sobrevivia entera y el sintoma no se parecia a la causa:
--
--   * seleccionabas a Avy para saltar a el; al llegar, `selected` seguia siendo
--     {Avy}, o sea TU MISMO. Pinchar entonces a Neferite dejaba dos
--     seleccionados -- "nos selecciona a ambos" -- sin que nada lo explicara.
--   * y con dos seleccionados el boton de Control usa el PRIMARIO, que era Avy,
--     que ahora eres tu: "selecciona a un compañero primero". O sea que
--     **saltar a un personaje impedia volver a el**, que se lee como que ese
--     personaje esta prohibido y no como una seleccion vieja.
--
-- Un nombre no basta para identificar nada aqui: la unica pregunta segura es si
-- el personaje que la sesion tiene ahora es el mismo de antes.
function S:IdentityChanged()
	-- POR GUID Y NO POR NOMBRE. El nombre es lo primero que hay que dejar de
	-- creerse aqui: es lo que puede estar contando la version vieja de la
	-- historia, y ademas puede repetirse con un compañero. El guid sale del
	-- gestor de objetos del cliente, que es el mismo campo que escribe el
	-- `UPDATEFLAG_SELF` -- o sea la definicion de a quien estas jugando.
	local me = UnitGUID("player")
	if not me or self.owner == me then return end

	self.owner = me
	self.selected = {}
	self.primary = nil
	self:Notify()
end

function S:Prune()
	local roster, keep, changed = self:GetRosterWithPlayer(), {}, false
	local present = {}
	for _, m in ipairs(roster) do present[m.name] = true end

	for _, n in ipairs(self.selected) do
		if present[n] then tinsert(keep, n) else changed = true end
	end

	-- El primario tambien se va si se fue del grupo. Sin esto, la fila de
	-- habilidades se quedaria ensenando las de un bot que ya no esta, y sus
	-- botones mandarian ordenes que el servidor rechaza en silencio.
	if self.primary and not present[self.primary] then
		self.primary = nil
		changed = true
	end

	if changed then
		self.selected = keep
		self:Notify()
	end
end

--- Control groups ----------------------------------------------------------
-- Persisted per character in RTSCommandDB.groups.

function S:SaveGroup(index)
	if not RTSCommandDB then return end
	RTSCommandDB.groups = RTSCommandDB.groups or {}

	local copy = {}
	for _, n in ipairs(self.selected) do tinsert(copy, n) end
	RTSCommandDB.groups[index] = copy

	ns.Print(("Control group %d set (%d unit%s)."):format(index, #copy, #copy == 1 and "" or "s"))
end

function S:RecallGroup(index)
	if not RTSCommandDB or not RTSCommandDB.groups then return end
	local g = RTSCommandDB.groups[index]
	if not g or #g == 0 then
		ns.Print(("Control group %d is empty."):format(index))
		return
	end

	-- Only recall members still present. Your own character counts, so a group
	-- saved with you in it comes back with you in it.
	local present, names = {}, {}
	for _, m in ipairs(self:GetRosterWithPlayer()) do present[m.name] = true end
	for _, n in ipairs(g) do
		if present[n] then tinsert(names, n) end
	end

	self:Set(names)
end

--- Change notification -----------------------------------------------------

function S:Subscribe(fn)
	tinsert(self.listeners, fn)
end

function S:Notify()
	for _, fn in ipairs(self.listeners) do
		local ok, err = pcall(fn)
		if not ok then ns.Print("UI error: " .. tostring(err)) end
	end
end
