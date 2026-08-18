--[[
	Core.lua -- init, events, slash commands, binding entry points.
]]

local ADDON, ns = ...

local PREFIX = "|cff33ccffRTS|r "

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

local DEFAULTS = {
	groups = {},
	unitBar = nil,
	commandCard = nil,
	shown = true,
}

--- Event plumbing ----------------------------------------------------------

local f = CreateFrame("Frame", "RTSCommandCore")
f:RegisterEvent("VARIABLES_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PARTY_MEMBERS_CHANGED")
f:RegisterEvent("RAID_ROSTER_UPDATE")

local initialised = false

local function Initialise()
	if initialised then return end
	initialised = true

	-- Scales are derived from the camera's diagonal FOV unless a calibration run
	-- explicitly overrode them; a stale SX from an older eyeball calibration must
	-- NOT silently win over the derived value.
	if RTSCommandDB.SX then ns.Markers.SX = RTSCommandDB.SX end
	if RTSCommandDB.SY then ns.Markers.SY = RTSCommandDB.SY end
	if RTSCommandDB.DEPTH_BIAS then ns.Markers.DEPTH_BIAS = RTSCommandDB.DEPTH_BIAS end
	if RTSCommandDB.forceScale then ns.Markers.autoIntrinsics = false end
	-- Calibration samples survive a reload so refining the fit costs no re-sweep.
	if type(RTSCommandDB.calSamples) == "table" then
		ns.Calib.samples = RTSCommandDB.calSamples
	end

	ns.UnitBar:Create()
	ns.CommandCard:Create()
	ns.Markers:Create()
	ns.SelectionRing:Create()
	ns.Flare:Create()
	ns.Focus:Create()
	ns.CommandMode:Create()
	ns.Targets:Create()
	ns.Channel:Create()
	ns.Camera:Create()
	ns.Chrome:Create()
	ns.HUD:Create()
	if type(RTSCommandDB.selfBotAuto) == "boolean" then
		ns.RTSMode.selfBot.auto = RTSCommandDB.selfBotAuto
	end
	if type(RTSCommandDB.freeLoot) == "boolean" then
		ns.RTSMode.freeLoot = RTSCommandDB.freeLoot
	end
	-- Umbral de "esto ha sido un giro de camara, no un click". Depende del raton
	-- y de la sensibilidad del cliente, asi que se guarda por personaje en vez
	-- de vivir como constante en el codigo.
	if type(RTSCommandDB.turnEps) == "number" and RTSCommandDB.turnEps > 0 then
		ns.RTSMode.turnEps = RTSCommandDB.turnEps
	end
	ns.UnitBar:Refresh()
	ns.CommandCard:Refresh()

	if not RTSCommandDB.shown then
		ns.UnitBar.frame:Hide()
		ns.CommandCard.frame:Hide()
	end

	ns.Print("loaded. |cffffff00/rts|r for commands.")

	-- rts_core.dll may be injected at any point, including mid-session, so
	-- poll for it rather than checking once at load.
	local acc = 0
	local watcher = CreateFrame("Frame")
	watcher:SetScript("OnUpdate", function(self, e)
		acc = acc + e
		if acc < 2 then return end
		acc = 0

		if ns.Bridge:TryAttach() then
			ns.Print(("|cff00ff00native bridge attached|r (rts_core %s) - " ..
				"precise coordinates enabled."):format(ns.Bridge.version or "?"))
			self:SetScript("OnUpdate", nil)
		end
	end)
end

f:SetScript("OnEvent", function(self, event)
	if event == "VARIABLES_LOADED" then
		RTSCommandDB = RTSCommandDB or {}
		for k, v in pairs(DEFAULTS) do
			if RTSCommandDB[k] == nil then RTSCommandDB[k] = v end
		end

	elseif event == "PLAYER_LOGIN" then
		-- VARIABLES_LOADED can arrive after PLAYER_LOGIN on a cold start.
		RTSCommandDB = RTSCommandDB or {}
		for k, v in pairs(DEFAULTS) do
			if RTSCommandDB[k] == nil then RTSCommandDB[k] = v end
		end
		Initialise()

	else -- roster changed
		if initialised then
			ns.Selection:Prune()
			ns.UnitBar:Refresh()
			ns.CommandCard:Refresh()
			-- El metodo de botin es del GRUPO, y el grupo se rehace cada vez
			-- que entra o sale un bot -- asi que hay que volver a ponerlo.
			ns.RTSMode:ApplyFreeLoot(true)
		end
	end
end)

--- Binding labels ----------------------------------------------------------
-- Shown in the Key Bindings UI. Must be globals.

BINDING_HEADER_RTSCOMMAND        = "RTS Command"
BINDING_NAME_RTSCOMMAND_TOGGLE   = "Show/hide RTS panels"
BINDING_NAME_RTSCOMMAND_MODE     = "Toggle RTS mode (mouse control)"
BINDING_NAME_RTSCOMMAND_CAMERA   = "Toggle detached RTS camera"
BINDING_NAME_RTSCOMMAND_CALIBRATE = "Calibrate projection (cursor on a unit)"
BINDING_NAME_RTSCOMMAND_SELECTALL = "Select all units"
BINDING_NAME_RTSCOMMAND_CLEAR    = "Clear selection"

BINDING_HEADER_RTSCOMMAND_ORDERS = "RTS Command: Orders"
BINDING_NAME_RTSCOMMAND_ORDER_MOVE   = "Order: Move"
BINDING_NAME_RTSCOMMAND_ORDER_HOLD   = "Order: Hold position"
BINDING_NAME_RTSCOMMAND_ORDER_FOLLOW = "Order: Follow"
BINDING_NAME_RTSCOMMAND_ORDER_ATTACK = "Order: Attack target"
BINDING_NAME_RTSCOMMAND_ORDER_ATTACKMOVE = "Order: Attack-move to cursor"
BINDING_NAME_RTSCOMMAND_RELEASE = "Leave command mode"
BINDING_NAME_RTSCOMMAND_COMMAND = "Command mode (borrow selected bot's bar)"
BINDING_NAME_RTSCOMMAND_SLOT1 = "Command slot 1"
BINDING_NAME_RTSCOMMAND_SLOT2 = "Command slot 2"
BINDING_NAME_RTSCOMMAND_SLOT3 = "Command slot 3"
BINDING_NAME_RTSCOMMAND_SLOT4 = "Command slot 4"
BINDING_NAME_RTSCOMMAND_SLOT5 = "Command slot 5"
BINDING_NAME_RTSCOMMAND_SLOT6 = "Command slot 6"
BINDING_NAME_RTSCOMMAND_SLOT7 = "Command slot 7"
BINDING_NAME_RTSCOMMAND_SLOT8 = "Command slot 8"
BINDING_NAME_RTSCOMMAND_SLOT9 = "Command slot 9"
BINDING_NAME_RTSCOMMAND_SLOT10 = "Command slot 10"

BINDING_HEADER_RTSCOMMAND_UNITS  = "RTS Command: Select unit"
BINDING_NAME_RTSCOMMAND_UNIT1 = "Select unit 1 (shift: add)"
BINDING_NAME_RTSCOMMAND_UNIT2 = "Select unit 2 (shift: add)"
BINDING_NAME_RTSCOMMAND_UNIT3 = "Select unit 3 (shift: add)"
BINDING_NAME_RTSCOMMAND_UNIT4 = "Select unit 4 (shift: add)"
BINDING_NAME_RTSCOMMAND_UNIT5 = "Select unit 5 (shift: add)"
BINDING_NAME_RTSCOMMAND_UNIT6 = "Select unit 6 (shift: add)"
BINDING_NAME_RTSCOMMAND_UNIT7 = "Select unit 7 (shift: add)"
BINDING_NAME_RTSCOMMAND_UNIT8 = "Select unit 8 (shift: add)"

BINDING_HEADER_RTSCOMMAND_GROUPS = "RTS Command: Control groups"
BINDING_NAME_RTSCOMMAND_GROUP1 = "Control group 1 (alt: store)"
BINDING_NAME_RTSCOMMAND_GROUP2 = "Control group 2 (alt: store)"
BINDING_NAME_RTSCOMMAND_GROUP3 = "Control group 3 (alt: store)"
BINDING_NAME_RTSCOMMAND_GROUP4 = "Control group 4 (alt: store)"

--- Binding entry points ----------------------------------------------------
-- Referenced by Bindings.xml. Must be globals.

function RTSCommand_SelectIndex(i)
	local roster = ns.Selection:GetRosterWithPlayer()
	local m = roster[i]
	if not m then return end

	if IsShiftKeyDown() or IsControlKeyDown() then
		ns.Selection:Toggle(m.name)
	else
		ns.Selection:SelectOnly(m.name)
	end
end

function RTSCommand_SelectAll()
	ns.Selection:SelectAll()
end

function RTSCommand_ClearSelection()
	ns.Selection:Clear()
end

-- Alt held = store the current selection, otherwise recall.
function RTSCommand_ControlGroup(i)
	if IsAltKeyDown() then
		ns.Selection:SaveGroup(i)
	else
		ns.Selection:RecallGroup(i)
	end
end

function RTSCommand_OrderMove()   ns.Orders:MoveToCursor() end
function RTSCommand_OrderHold()   ns.Orders:Hold()   end
function RTSCommand_OrderFollow() ns.Orders:Follow() end
function RTSCommand_OrderAttack() ns.Orders:Attack() end
function RTSCommand_OrderAttackMove() ns.RTSMode:AttackMoveToCursor() end
function RTSCommand_ReleasePossession() ns.CommandMode:Leave() end
function RTSCommand_ToggleCommandMode() ns.CommandMode:Toggle() end

function RTSCommand_ToggleUI()
	ns.UnitBar:Toggle()
	ns.CommandCard:Toggle()
	RTSCommandDB.shown = ns.CommandCard.frame:IsShown()
end

function RTSCommand_ToggleRTSMode()
	ns.RTSMode:Toggle()
end

function RTSCommand_Calibrate()
	ns.Markers:Calibrate()
end

function RTSCommand_ToggleCamera()
	ns.Camera:Toggle()
end

--- Slash commands ----------------------------------------------------------

local HELP = {
	"|cffffff00/rts|r - show or hide the RTS panels",
	"|cffffff00/rts all|r - select every bot",
	"|cffffff00/rts clear|r - clear selection",
	"|cffffff00/rts list|r - list the roster",
	"|cffffff00/rts move|r / |cffffff00hold|r / |cffffff00follow|r / |cffffff00attack|r",
	"|cffffff00/rts form <name>|r - " .. table.concat({ "near", "far", "melee", "queue", "chaos", "circle", "line", "shield", "arrow" }, ", "),
	"|cffffff00/rts cmd <text>|r - send any raw playerbots command to the selection",
	"|cffffff00/rts amove|r - attack-move to the cursor; |cffffff00/rts release|r drops direct control",
	"|cffffff00/rts flare|r - order marker settings (time/size/start/hold/alpha/ease/fade)",
	"|cffffff00/rts markers|r - halo that follows the mouse pointer (off by default)",
	"|cffffff00/rts command|r - borrow the selected bot's action bar and cast as them",
	"|cffffff00/rts targets|r - panel with everything the group is engaged with",
	"|cffffff00/rts self|r - your own character fights with the playerbots AI; |cffffff00auto|r / |cffffff00status|r",
	"|cffffff00/rts loot|r - botin libre para todo el grupo (free-for-all)",
	"|cffffff00/rts tri|r - green triangle over heads (parked; |cffffff00/rts tri help|r)",
	"|cffffff00/rts turn|r - por que un click se pierde: mide el giro de camara y lo compara con el umbral",
	"|cffffff00/rts halo <0-2>|r - cursor halo style, |cffffff00/rts halo size <yards>|r",
	"|cffffff00/rts ring|r - native ground circle under selected units; |cffffff00tint|r adds the model glow, |cffffff00test|r proves the hook",
	"|cffffff00/rts cam|r - detached RTS camera (WASD pans flat, Q/E lower/raise, right-drag rotates)",
	"|cffffff00/rts cam save|r - frame it how you want, then save; |cffffff00show|r reprints the values",
	"|cffffff00/rts cam frame|r - re-apply it; |cffffff00tilt|r / |cffffff00zoom|r / |cffffff00fov <deg>|r nudge; |cffffff00clear|r forgets it",
	"|cffffff00/rts cam fly|r / |cffffff00fly 0|r - forward follows your view, or runs flat (RTS)",
	"|cffffff00/rts cam here|r - recentre over your character; |cffffff00mouse|r toggles mouse steering",
	"|cffffff00/rts cam speed <n>|r - how fast it flies",
	"|cffffff00/rts channel|r - what the DLL is being told about your selection",
	"|cffffff00/rts state|r - the tint colour each selected unit is being given",
	"|cffffff00/rts cal|r - measure the projection (fixes rings that sit short)",
	"|cffffff00/rts version|r - versions of all three pieces (addon, server, DLL)",
	"|cffffff00/rts pick|r / |cffffff00pick on|r - what is under the cursor, once or continuously",
	"|cffffff00/rts debug|r - echo every message to and from the server module",
	"|cffffff00/rts native|r - rts_core.dll status + offset self-test",
	"|cffffff00/rts ui|r - que se esconde al entrar en modo RTS, y las medidas de la HUD",
	"|cffffff00/rts art|r - visor de texturas del cliente (para vestir la HUD sin dibujar)",
	"|cffffff00/rts skin|r - aspecto WC3 o plano; |cffffff00/rts skin wall <ruta>|r cambia una pieza",
	"|cffffff00/rts reset|r - move panels back to their default position",
	"Bind keys under Key Bindings -> RTS Command.",
}

SLASH_RTSCOMMAND1 = "/rts"
SlashCmdList["RTSCOMMAND"] = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()

	if cmd == "" then
		RTSCommand_ToggleUI()

	elseif cmd == "help" then
		for _, line in ipairs(HELP) do ns.Print(line) end

	elseif cmd == "all" then
		ns.Selection:SelectAll()

	elseif cmd == "clear" then
		ns.Selection:Clear()

	elseif cmd == "list" then
		local roster = ns.Selection:GetRosterWithPlayer()
		if #roster == 0 then
			ns.Print("Roster is empty - no group members.")
		end
		for i, m in ipairs(roster) do
			ns.Print(("%d. %s%s"):format(i, m.name,
				ns.Selection:IsSelected(m.name) and " |cff00ff00[selected]|r" or ""))
		end

	elseif cmd == "move"   then ns.Orders:MoveToCursor()
	elseif cmd == "hold"   then ns.Orders:Hold()
	elseif cmd == "follow" then ns.Orders:Follow()
	elseif cmd == "attack" then ns.Orders:Attack()
	elseif cmd == "amove" then ns.RTSMode:AttackMoveToCursor()
	elseif cmd == "release" then ns.CommandMode:Leave()

	elseif cmd == "form" or cmd == "formation" then
		if rest == "" then
			ns.Print("Usage: /rts form <" .. table.concat(ns.Orders.FORMATIONS, "|") .. ">")
		else
			ns.Orders:Formation(rest:lower())
		end

	elseif cmd == "cmd" or cmd == "raw" then
		ns.Orders:Raw(rest)

	elseif cmd == "mode" or cmd == "rts" then
		ns.RTSMode:Toggle()

	elseif cmd == "cal" or cmd == "calibrate" then
		local sub = (rest or ""):lower()
		if sub == "start" or sub == "on" then
			ns.Calib:Start()
		elseif sub == "stop" or sub == "off" then
			ns.Calib:Stop()
		elseif sub == "report" or sub == "fit" then
			ns.Calib:Report()
		elseif sub == "apply" then
			ns.Calib:Apply()
		elseif sub == "auto" then
			ns.Calib:Auto()
		elseif sub == "dump" then
			ns.Calib:Dump()
		elseif sub == "clear" or sub == "reset" then
			ns.Calib:Reset()
		else
			ns.Print("Projection calibration - measures the projection from the")
			ns.Print("game's own mouseover picking, so no eyeballing is involved.")
			ns.Print("|cffffff00/rts cal start|r - begin recording")
			ns.Print("  then hover each bot, sweeping side to side, at several")
			ns.Print("  distances. Bots must be standing still.")
			ns.Print("|cffffff00/rts cal stop|r / |cffffff00report|r / |cffffff00apply|r / |cffffff00auto|r / |cffffff00dump|r / |cffffff00clear|r")
			ns.Print("Scales are derived from the camera's diagonal FOV by default;")
			ns.Print("|cffffff00auto|r restores that, |cffffff00apply|r overrides it with a measurement.")
		end

	elseif cmd == "markers" then
		ns.Markers:Toggle()

	elseif cmd == "loot" then
		ns.RTSMode:ToggleFreeLoot()

	elseif cmd == "self" or cmd == "selfbot" then
		local sub = (rest or ""):match("^(%S*)"):lower()
		if sub == "auto" then
			ns.RTSMode:SelfBotAuto()
		elseif sub == "status" or sub == "?" then
			ns.RTSMode:SelfBotStatus()
		else
			ns.RTSMode:SelfBotToggle()
		end

	elseif cmd == "targets" then
		ns.Targets:Toggle()

	elseif cmd == "flare" then
		local sub, a1 = rest:match("^(%S*)%s*(%S*)$")
		sub = (sub or ""):lower()
		if sub == "" or sub == "status" or sub == "?" then
			ns.Flare:Status()
		elseif sub == "on" or sub == "off" or sub == "toggle" then
			ns.Flare:Toggle()
		elseif sub == "reset" then
			ns.Flare:Reset()
		else
			ns.Flare:Set(sub, a1)
		end

	elseif cmd == "ring" or cmd == "rings" or cmd == "circle" then
		local sub = (rest or ""):match("^(%S*)"):lower()
		local cfg = ns.SelectionRing
		if sub == "tint" then
			cfg:ToggleTint()
		elseif sub == "test" then
			cfg:ToggleTest()
		elseif sub == "status" or sub == "?" then
			cfg:Status()
		else
			cfg:Toggle()
		end


	elseif cmd == "cam" or cmd == "camera" then
		local sub, arg = rest:match("^(%S*)%s*(%S*)$")
		sub = (sub or ""):lower()
		if sub == "speed" then
			ns.Camera:SetSpeed(arg)
		elseif sub == "fly" then
			ns.Camera:SetFly(arg ~= "0" and arg ~= "off")
		elseif sub == "frame" then
			ns.Camera:Frame()
		elseif sub == "save" then
			ns.Camera:SavePreset()
		elseif sub == "show" or sub == "values" then
			ns.Camera:Report()
		elseif sub == "clear" then
			ns.Camera:ClearPreset()
		elseif sub == "tilt" or sub == "zoom" or sub == "fov" then
			ns.Camera:SetFrame(sub, arg)
		elseif sub == "mouse" or sub == "mouselook" then
			ns.Camera:ToggleMouselook()
		elseif sub == "here" or sub == "recenter" then
			ns.Camera:Recenter()
		elseif sub == "on" then
			ns.Camera:On()
		elseif sub == "off" then
			ns.Camera:Off()
		else
			ns.Camera:Toggle()
		end

	elseif cmd == "ui" then
		-- El interruptor de la opcion B del estudio: ocultado selectivo, mas
		-- las medidas del prototipo de HUD. Todo por el mismo comando porque
		-- son la misma pregunta -- que se ve en pantalla en modo RTS.
		local sub, arg = rest:match("^(%S*)%s*(%S*)$")
		sub = (sub or ""):lower()

		if sub == "" or sub == "status" or sub == "?" then
			ns.Chrome:Status()
			ns.HUD:Report()

		elseif sub == "hud" then
			ns.HUD:Toggle()

		elseif sub == "what" or sub == "que" then
			ns.Chrome:What()

		elseif sub == "chatline" or sub == "chatlinea" then
			ns.HUD:MirrorChat()

		elseif sub == "fit" then
			-- El alto que hace que los botones midan lo mismo que los de la
			-- barra de acciones del juego.
			ns.HUD:Fit()

		elseif sub == "default" or sub == "defaults" then
			ns.HUD:Reset()
			ns.Print("medidas de la HUD devueltas a las de fabrica.")

		elseif ns.HUD.cfg[sub] ~= nil then
			if ns.HUD:Set(sub, arg) then
				ns.HUD:Report()
			else
				ns.Print(("|cffffff00/rts ui %s <px>|r - ahora %d"):format(sub, ns.HUD.cfg[sub]))
			end

		elseif ns.Chrome.hide[sub] ~= nil then
			ns.Chrome:SetHidden(sub)
			ns.Print(("%s: %s"):format(sub,
				ns.Chrome.hide[sub] and "|cffff4040se oculta en modo RTS|r"
				or "|cff40ff40se deja como esta|r"))

		else
			ns.Print("|cffffff00/rts ui|r - estado y medidas")
			local names = {}
			for _, sset in ipairs(ns.Chrome.SETS) do names[#names + 1] = sset.k end
			ns.Print("|cffffff00/rts ui <conjunto>|r - " .. table.concat(names, ", "))
			ns.Print("|cffffff00/rts ui hud|r - encender o apagar el prototipo de HUD")
			ns.Print("|cffffff00/rts ui what|r - nombrar lo que sigue visible en pantalla")
			ns.Print("|cffffff00/rts ui fit|r - botones del tamano de la barra de acciones")
			ns.Print("|cffffff00/rts ui chatline|r - copiar el chat a la linea de mensajes")
			ns.Print("|cffffff00/rts ui height / mini / pad / gap / right <px>|r - medidas")
			ns.Print("|cffffff00/rts ui default|r - devolver las medidas")
		end

	elseif cmd == "skin" or cmd == "piel" then
		-- El aspecto de la HUD. Pensado para usarse con /rts art al lado:
		-- se mira una textura, se copia su ruta con un click, se pega aqui.
		local sub, arg = rest:match("^(%S*)%s*(.-)$")
		sub = (sub or ""):lower()
		if sub == "" then
			ns.Skin:Toggle()
		elseif sub == "status" or sub == "?" then
			ns.Skin:Status()
		elseif sub == "default" or sub == "reset" then
			ns.Skin:Reset()
		elseif ns.Skin.tex[sub] ~= nil then
			if not ns.Skin:Set(sub, strtrim(arg or "")) then
				ns.Print(("|cffffff00/rts skin %s <ruta>|r - ahora %s")
					:format(sub, ns.Skin.tex[sub]))
			end
		else
			ns.Skin:Status()
		end

	elseif cmd == "art" then
		-- Que texturas del cliente existen de verdad, mirandolas. Es el paso
		-- previo a vestir la HUD: una ruta que no carga no da error, dibuja
		-- nada, y construir encima de eso se descubre tarde.
		local sub = (rest or ""):lower()
		if sub == "" then
			ns.Art:Toggle()
		elseif sub == "next" or sub == "+" then
			ns.Art:Page(1)
		elseif sub == "prev" or sub == "-" then
			ns.Art:Page(-1)
		elseif sub == "scan" then
			ns.Art:Scan()
		elseif sub == "all" or sub == "todo" then
			ns.Art:Filter("")
		else
			ns.Art:Filter(sub)
		end

	elseif cmd == "channel" then
		ns.Channel:Dump()

	elseif cmd == "state" then
		-- Why each unit is the colour it is: the order still standing, and the
		-- two live signals that decide how long that order keeps its colour.
		local COLOUR = {
			[ns.UnitState.SELECTED] = "|cff2a72ffblue|r   selected",
			[ns.UnitState.MOVING]   = "|cff1aff40green|r  moving",
			[ns.UnitState.COMBAT]   = "|cffff1a1ared|r    combat",
			[ns.UnitState.INTERACT] = "|cffff8c1aorange|r interact",
		}
		local sel = ns.Selection:Get()
		if #sel == 0 then ns.Print("Nothing selected.") end
		for _, name in ipairs(sel) do
			local unit = ns.Selection:UnitFor(name)
			local guid = unit and UnitGUID(unit)
			-- Read the order BEFORE Code(), which drops it once it has expired.
			local o = ns.UnitState.orders[name]
			local code = ns.UnitState:Code(name, unit, guid)
			local track = guid and ns.Markers.track[string.upper(guid)]
			ns.Print(("%s -> %s"):format(name, COLOUR[code] or tostring(code)))
			ns.Print(("    order=%s%s  incombat=%s  lastmoved=%s")
				:format(o and o.kind or "none",
				        o and (" %.1fs ago"):format(GetTime() - o.at) or "",
				        unit and tostring(UnitAffectingCombat(unit) and true or false) or "?",
				        track and ("%.2fs"):format(GetTime() - track.ct) or "not published"))
		end

	elseif cmd == "turn" then
		local M = ns.RTSMode
		local eps = tonumber(rest:match("^eps%s+([%d%.]+)$"))
		if eps and eps > 0 then
			M.turnEps = eps
			RTSCommandDB.turnEps = eps
			ns.Print(("umbral de giro = %.4f"):format(eps))
		elseif rest == "reset" then
			M.turnEps = 0.05
			RTSCommandDB.turnEps = nil
			ns.Print("umbral de giro devuelto a 0.0500")
		elseif rest == "" then
			M.turnDebug = not M.turnDebug
			ns.Print("informe de clicks " ..
				(M.turnDebug and "|cff00ff00ON|r" or "|cffff0000OFF|r")
				.. (" - umbral actual %.4f"):format(M.turnEps))
			if M.turnDebug then
				ns.Print("Cada click dira cuanto giro la camara mientras lo hacias.")
				ns.Print("Un click quieto deberia dar un numero PEQUENO; un arrastre")
				ns.Print("para girar, uno GRANDE. El umbral va entre los dos.")
				ns.Print("Si sale |cffff0000TRAGADO|r en clicks que querias dar, subelo:")
				ns.Print("|cffffff00/rts turn eps <n>|r")
			end
		else
			ns.Print("|cffffff00/rts turn|r - informe por click (giro medido vs umbral)")
			ns.Print("|cffffff00/rts turn eps <n>|r - cambiar el umbral; |cffffff00reset|r lo devuelve")
			ns.Print(("umbral actual %.4f"):format(M.turnEps))
		end

	elseif cmd == "halo" then
		local h = ns.Markers.halo
		local n = tonumber(rest)
		local size = tonumber(rest:match("^size%s+([%d%.]+)$"))
		if size then
			h.size = size
			RTSCommandDB.haloSize = size
			ns.Print(("halo size = %.1f yards across"):format(size))
		elseif n and h.styles[n] then
			h.style = n
			RTSCommandDB.halo = n
			ns.Print(("halo style %d - %s"):format(n, h.styles[n].name))
		else
			ns.Print("|cffffff00/rts halo <n>|r - switch the cursor halo:")
			for i = 0, 2 do
				ns.Print(("  %d %s%s"):format(i, h.styles[i].name,
					h.style == i and " |cff00ff00<-- current|r" or ""))
			end
			ns.Print("|cffffff00/rts halo size <yards>|r - " ..
				("currently %.1f"):format(h.size))
		end

	elseif cmd == "tri" or cmd == "triangle" then
		local sub, a1, a2 = rest:match("^(%S*)%s*(%S*)%s*(%S*)$")
		sub = (sub or ""):lower()
		local cfg = ns.Markers.tri
		local n1, n2 = tonumber(a1), tonumber(a2)

		if sub == "" then
			ns.Markers:ToggleTriangles()
		elseif sub == "mobs" then
			cfg.mobs = not cfg.mobs
			ns.Print("triangles over mobs " .. (cfg.mobs and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		elseif sub == "sel" or sub == "selection" then
			cfg.sel = not cfg.sel
			ns.Print("triangles over selection " .. (cfg.sel and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		elseif sub == "height" and n1 then
			cfg.height = n1
			ns.Print(("triangle height = %.1f yards above the feet"):format(n1))
		elseif sub == "scale" and n1 then
			cfg.scale = n1
			ns.Print(("triangle scale = %d (pixel size at 1 yard)"):format(n1))
		elseif sub == "size" and n1 then
			cfg.min = n1
			if n2 then cfg.max = n2 end
			ns.Print(("triangle size clamped to %d..%d px"):format(cfg.min, cfg.max))
		else
			ns.Print("|cffffff00/rts tri|r - toggle the head triangles")
			ns.Print("|cffffff00/rts tri mobs|r / |cffffff00sel|r - which units get one")
			ns.Print("|cffffff00/rts tri height <yards>|r - raise or lower it over the head")
			ns.Print("|cffffff00/rts tri scale <n>|r - how fast it shrinks with distance")
			ns.Print("|cffffff00/rts tri size <min> [max]|r - pixel clamp")
			ns.Print(("now: %s  mobs=%s sel=%s height=%.1f scale=%d size=%d..%d")
				:format(cfg.enabled and "ON" or "OFF", tostring(cfg.mobs), tostring(cfg.sel),
				        cfg.height, cfg.scale, cfg.min, cfg.max))
		end
		RTSCommandDB.tri = cfg

	elseif cmd == "units" then
		-- Diagnostic: dump every unit position the DLL publishes, vs the player.
		local pn = RTS_UN or 0
		ns.Print(("player: %.2f, %.2f, %.2f  (facing %.2f)"):format(RTS_PX or 0, RTS_PY or 0, RTS_PZ or 0, RTS_PF or 0))
		ns.Print(("published units: %d"):format(pn))
		for i = 1, pn do
			local g = _G["RTS_U" .. i .. "G"]
			local ux = _G["RTS_U" .. i .. "X"]
			local uy = _G["RTS_U" .. i .. "Y"]
			local uz = _G["RTS_U" .. i .. "Z"]
			local dist = math.sqrt((ux - RTS_PX)^2 + (uy - RTS_PY)^2)
			ns.Print(("  %d %s  %.2f, %.2f, %.2f  (%.1fy away)"):format(i, tostring(g), ux, uy, uz, dist))
		end
		-- Compare to what the client's own API says about a party member.
		if GetNumPartyMembers() > 0 then
			ns.Print(("party1 guid = %s"):format(tostring(UnitGUID("party1"))))
		end

		-- Resolve each SELECTED unit exactly as the ring code does.
		ns.Print("--- selection resolution ---")
		for _, name in ipairs(ns.Selection:Get()) do
			local unit = ns.Selection:UnitFor(name)
			local guid = unit and UnitGUID(unit)
			local x, y, z = ns.Markers:UnitWorld(guid)
			if x then
				local d = math.sqrt((x - RTS_PX)^2 + (y - RTS_PY)^2)
				ns.Print(("%s -> token=%s guid=%s -> pos %.2f,%.2f (%.1fy from you)")
					:format(name, tostring(unit), tostring(guid), x, y, d))
			else
				ns.Print(("%s -> token=%s guid=%s -> |cffff0000NO MATCH in map|r")
					:format(name, tostring(unit), tostring(guid)))
			end
		end

	elseif cmd == "pick" then
		-- `/rts pick` samples once, wherever the cursor happens to be when you
		-- press Enter -- which is rarely where you were hovering. `/rts pick on`
		-- prints continuously so you can hover a wolf and watch.
		local sub = (rest or ""):lower()
		if sub == "on" or sub == "off" then
			ns.RTSMode:LivePick(sub == "on")
		else
			ns.RTSMode:PickReport()
		end

	elseif cmd == "command" or cmd == "cmdmode" then
		ns.CommandMode:Toggle()

	elseif cmd == "debug" then
		ns.Camera.debug = not ns.Camera.debug
		ns.Print("channel debug " .. (ns.Camera.debug and "|cff00ff00ON|r" or "|cffff0000OFF|r")
			.. " - shows every message to and from mod-rts.")

	elseif cmd == "pickradius" then
		local n = tonumber(rest)
		if n then
			ns.RTSMode.hostilePickRadius = n
			ns.Print(("hostile pick radius = %d px"):format(n))
		else
			ns.Print(("hostile pick radius is %d px - |cffffff00/rts pickradius <px>|r")
				:format(ns.RTSMode.hostilePickRadius))
		end

	elseif cmd == "version" or cmd == "ver" then
		ns.Print(("addon      |cffffff00%s|r"):format(GetAddOnMetadata(ADDON, "Version") or "?"))
		ns.Print(("mod-rts    %s"):format(ns.Camera.serverVersion
			and ("|cff00ff00" .. ns.Camera.serverVersion .. "|r")
			or "|cffff0000not answering|r"))
		ns.Print(("rts_core   %s"):format(RTS_Ready == 1
			and ("|cff00ff00" .. tostring(RTS_Version) .. "|r")
			or "|cffff0000not injected|r"))

	elseif cmd == "native" then
		ns.Bridge:TryAttach()
		if not ns.Bridge:IsNative() then
			ns.Print("native bridge |cffff0000not attached|r - rts_core.dll is not injected.")
			ns.Print("Orders still work; coordinates and click-to-move do not.")
		else
			ns.Print(("native bridge |cff00ff00attached|r, rts_core %s (heartbeat %s)")
				:format(ns.Bridge.version or "?", tostring(ns.Bridge:Heartbeat())))
			local x, y, z, f = ns.Bridge:GetPlayerWorldPosition()
			if x then
				ns.Print(("player world pos: %.2f, %.2f, %.2f (facing %.2f)"):format(x, y, z, f or 0))
			else
				ns.Print("|cffff0000no position yet|r - are you in the world?")
			end
			local n = ns.Bridge:ObjectCount()
			if n then ns.Print(("objects tracked: %d"):format(n)) end

			-- Raycast self-test: ground Z under the player should match player Z.
			if RTS_GroundHit == 1 and x then
				local dz = RTS_GroundZ - z
				local ok = (math.abs(dz) < 2.0) and "|cff00ff00OK|r" or "|cffffff00check|r"
				ns.Print(("raycast: ground Z %.2f vs player Z %.2f (%.2f diff) %s")
					:format(RTS_GroundZ, z, dz, ok))
			elseif RTS_GroundHit == 0 then
				ns.Print("|cffff0000raycast: no ground hit|r (offset may be wrong)")
			end

			-- Cursor terrain raycast -- what a click-to-move order will use.
			if RTS_CurHit == 1 then
				ns.Print(("|cff00ff00cursor ground:|r %.1f, %.1f, %.1f"):format(RTS_CurX, RTS_CurY, RTS_CurZ))
			elseif RTS_CurHit == 0 then
				ns.Print("|cffffff00cursor ray: no hit|r (pointing at sky, or cursor off-window)")
			else
				ns.Print("|cffffff00cursor ray: absent|r - rts_core older than 0.8.0")
			end

			-- Camera + screen-centre look-at point.
			if RTS_HasCam == 1 then
				ns.Print(("camera pos: %.1f, %.1f, %.1f"):format(RTS_CamX, RTS_CamY, RTS_CamZ))
				if RTS_LookHit == 1 then
					ns.Print(("|cff00ff00look-at ground:|r %.1f, %.1f, %.1f"):format(RTS_LookX, RTS_LookY, RTS_LookZ))
				else
					ns.Print("|cffffff00look-at: no hit|r (aim at ground, not sky)")
				end
			else
				ns.Print("|cffff0000camera not read|r - see rts_core.log")
			end
		end

	elseif cmd == "reset" then
		RTSCommandDB.unitBar, RTSCommandDB.commandCard = nil, nil
		ns.Print("Panel positions reset - reload the UI (|cffffff00/console reloadui|r) to apply.")

	else
		ns.Print("Unknown command. Try |cffffff00/rts help|r.")
	end
end
