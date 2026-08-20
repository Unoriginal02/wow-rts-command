--[[
	Rails.lua -- los dos railes de botones de los extremos.

	  izquierda   lo del minimapa: mapa, rastreo, zoom, calendario, correo
	  derecha     lo del juego: ficha, talentos, hechizos, misiones, bolsas, menu

	Seis casillas cada uno, que es lo que da el hueco del arte (78 x 452 con
	botones de 68). Son los dos unicos paneles que NO mandan ordenes a nadie:
	abren ventanas del cliente, que es lo que hacen los botones de las esquinas
	en cualquier RTS.

	=== LOS ICONOS SE LE PIDEN AL CLIENTE, NO SE ESCRIBEN ==================

	La regla de este proyecto es comprobar contra el cliente y no contra internet
	(`nameplateMaxDistance`, `gxWindowedResolution`, `SetCamera(1)`), y aqui se
	puede llevar al extremo: el cliente YA esta dibujando estos doce botones
	ahora mismo, asi que en vez de escribir doce rutas de memoria se le pregunta
	a cada frame por la textura que esta usando.

	  MainMenuBarBackpackButton:GetNormalTexture():GetTexture()

	Eso no puede estar mal, porque es literalmente el dibujo que hay en pantalla.
	Escribir "Interface\\Icons\\INV_Misc_Bag_08" es una apuesta, y una ruta que no
	existe NO DA ERROR: dibuja nada, y el fallo aparece como "el rail sale vacio"
	sin decir por que.

	El precio es la FORMA: los micro-botones del cliente son altos y estrechos
	(32x64), no cuadrados. Se dibujan con su proporcion dentro de la casilla en
	vez de estirarlos, porque un icono estirado se ve peor que uno pequeno.

	Si algun frame no estuviera, el boton se queda con el interrogante y
	`/rts rails` dice cual -- en vez de una casilla vacia sin explicacion.

	=== nada de aqui esta protegido ==========================================

	`ToggleCharacter`, `ToggleSpellBook`, `ToggleTalentFrame`, `ToggleQuestLog`,
	`ToggleAllBags`, `ToggleGameMenu`, `ToggleWorldMap`, `ToggleCalendar` y
	`Minimap:SetZoom` son todas llamables por un addon en 3.3.5a. Lo que esta
	protegido son las acciones de COMBATE (`CastSpellByName`, `TargetUnit`), y
	aqui no hay ninguna. Igual se llaman con guarda: un cliente sin calendario
	tiene que dejar el boton apagado, no reventar el rail entero.
]]

local ADDON, ns = ...

local R = {}
ns.Rails = R

R.active = false

local UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"

local hosts, buttons = {}, { ["rail-left"] = {}, ["rail-right"] = {} }

--- La textura que el cliente esta usando ahora mismo ----------------------

-- Se prueban varios nombres porque no todos los frames del minimapa se llaman
-- igual en todos los clientes 3.3.5a parcheados; el primero que exista gana.
local function TextureOf(names)
	for _, name in ipairs(names) do
		local f = _G[name]
		if f then
			if f.GetNormalTexture then
				local t = f:GetNormalTexture()
				local path = t and t.GetTexture and t:GetTexture()
				if path then return path, name end
			end
			if f.GetRegions then
				for _, reg in ipairs({ f:GetRegions() }) do
					if reg.GetTexture then
						local path = reg:GetTexture()
						if path then return path, name end
					end
				end
			end
		end
	end
	return nil
end

--- Acciones --------------------------------------------------------------

local function Call(fn, ...)
	if type(fn) ~= "function" then return false end
	fn(...)
	return true
end

local function Zoom(delta)
	if not Minimap or not Minimap.SetZoom then return end
	local z = (Minimap.GetZoom and Minimap:GetZoom()) or 0
	local max = (Minimap.GetZoomLevels and Minimap:GetZoomLevels()) or 5
	z = z + delta
	if z < 0 then z = 0 end
	if z > max - 1 then z = max - 1 end
	Minimap:SetZoom(z)
end

-- El desplegable de rastreo. Se intenta abrirlo por su nombre y, si no, se
-- pulsa el boton de verdad: esta escondido pero un frame escondido sigue
-- corriendo su OnClick.
local function Tracking()
	if MiniMapTrackingDropDown and ToggleDropDownMenu then
		ToggleDropDownMenu(1, nil, MiniMapTrackingDropDown, "cursor", 0, 0)
		return
	end
	for _, name in ipairs({ "MiniMapTrackingButton", "MiniMapTracking" }) do
		local f = _G[name]
		if f and f.Click then f:Click(); return end
	end
	ns.Print("este cliente no tiene el desplegable de rastreo donde se esperaba.")
end

--- Los dos railes --------------------------------------------------------

local RAILS = {
	["rail-left"] = {
		{ short = "Mapa", tip = "Abrir el mapa del mundo.",
		  from = { "MiniMapWorldMapButton" },
		  fn = function() Call(ToggleWorldMap) end },

		{ short = "Rastro", tip = "Que rastrear en el minimapa.",
		  from = { "MiniMapTrackingIcon", "MiniMapTrackingButton", "MiniMapTracking" },
		  fn = Tracking },

		{ short = "+", tip = "Acercar el minimapa.",
		  from = { "MinimapZoomIn" },
		  fn = function() Zoom(1) end },

		{ short = "-", tip = "Alejar el minimapa.",
		  from = { "MinimapZoomOut" },
		  fn = function() Zoom(-1) end },

		{ short = "Dias", tip = "Abrir el calendario.",
		  from = { "GameTimeFrame" },
		  fn = function() Call(ToggleCalendar) end },

		-- El correo es un AVISO, no un boton: no se puede abrir un buzon de
		-- lejos. Se enciende cuando hay carta y se apaga cuando no, que es la
		-- unica cosa util que puede hacer.
		{ short = "Correo", tip = "Se enciende cuando tienes correo sin leer.",
		  from = { "MiniMapMailIcon", "MiniMapMailFrame" },
		  indicator = function()
			  return HasNewMail and HasNewMail() and true or false
		  end,
		  fn = function()
			  if HasNewMail and HasNewMail() then
				  ns.Print("tienes correo esperando en un buzon.")
			  else
				  ns.Print("no tienes correo.")
			  end
		  end },
	},

	["rail-right"] = {
		{ short = "Ficha", tip = "Hoja de personaje y equipo.",
		  from = { "CharacterMicroButton" },
		  fn = function() Call(ToggleCharacter, "PaperDollFrame") end },

		{ short = "Talent", tip = "Arbol de talentos.",
		  from = { "TalentMicroButton" },
		  fn = function() Call(ToggleTalentFrame) end },

		{ short = "Libro", tip = "Libro de hechizos.",
		  from = { "SpellbookMicroButton" },
		  fn = function() Call(ToggleSpellBook, BOOKTYPE_SPELL or "spell") end },

		{ short = "Mision", tip = "Diario de misiones.",
		  from = { "QuestLogMicroButton" },
		  fn = function() Call(ToggleQuestLog) end },

		{ short = "Bolsas", tip = "Abrir y cerrar todas las bolsas.",
		  from = { "MainMenuBarBackpackButton" },
		  fn = function()
			  if not Call(ToggleAllBags) then Call(OpenAllBags) end
		  end },

		{ short = "Menu", tip = "Menu del juego (lo mismo que Escape).",
		  from = { "MainMenuMicroButton" },
		  fn = function() Call(ToggleGameMenu) end },
	},
}

--- Construccion ---------------------------------------------------------

local function GetButton(key, i, size)
	local list = buttons[key]
	local b = list[i]
	if not b then
		b = ns.W:Button(hosts[key], size)
		b:SetScript("OnClick", function(self)
			if self.act and self.act.fn then self.act.fn() end
		end)
		list[i] = b
	end
	return b
end

R.missing = {}

function R:LayoutRail(key)
	local host = hosts[key]
	if not host then return end

	local cells = ns.Bar:Cells(key)
	local specs = RAILS[key]

	for i, c in ipairs(cells) do
		local spec = specs[i]
		local b = GetButton(key, i, c.w)

		b:SetWidth(c.w)
		b:SetHeight(c.h)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", host, "TOPLEFT", c.x, -c.y)

		b.act = spec
		if not spec then
			b:Hide()
		else
			b:Show()

			local path, from = TextureOf(spec.from)
			if not path then
				path = UNKNOWN
				table.insert(self.missing, spec.short)
			end
			spec.found = from

			-- Con su proporcion, no estirado. Los micro-botones del cliente son
			-- el doble de altos que de anchos, asi que se centran.
			b.icon:ClearAllPoints()
			b.icon:SetTexture(path)
			b.icon:SetTexCoord(0, 1, 0, 1)
			if from and string.find(from, "MicroButton") then
				b.icon:SetHeight(c.h - 6)
				b.icon:SetWidth(math.floor((c.h - 6) / 2))
				b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
			else
				b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
				b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
			end

			b.label:SetText(spec.short)
			ns.W:Tip(b, spec.short, spec.tip)
		end
	end

	for i = #cells + 1, #buttons[key] do buttons[key][i]:Hide() end
end

function R:Layout()
	self.missing = {}
	self:LayoutRail("rail-left")
	self:LayoutRail("rail-right")
	self:Refresh()

	if #self.missing > 0 and not self.warned then
		self.warned = true
		ns.Print(("|cffff8800railes:|r sin icono del cliente para %s - " ..
			"llevan interrogante."):format(table.concat(self.missing, ", ")))
	end
end

-- Lo unico que cambia en vivo: el aviso de correo.
function R:Refresh()
	if not self.active then return end
	for key, specs in pairs(RAILS) do
		for i, spec in ipairs(specs) do
			local b = buttons[key][i]
			if b and spec.indicator then
				local on = spec.indicator()
				b.icon:SetAlpha(on and 1 or 0.35)
				b.icon:SetVertexColor(1, 1, on and 0.4 or 1)
			end
		end
	end
end

--- Informe ---------------------------------------------------------------

function R:Report()
	ns.Print("|cffffff00railes|r  izquierda = minimapa, derecha = juego")
	for _, key in ipairs({ "rail-left", "rail-right" }) do
		local out = {}
		for _, spec in ipairs(RAILS[key]) do
			table.insert(out, ("%s(%s)"):format(spec.short, spec.found or "|cffff0000?|r"))
		end
		ns.Print(("  %s: %s"):format(key, table.concat(out, " ")))
	end
	ns.Print("entre parentesis, el frame del cliente del que salio el icono.")
end

--- Entrar y salir -------------------------------------------------------

function R:Enter()
	hosts["rail-left"] = ns.Bar:SlotFrame("rail-left")
	hosts["rail-right"] = ns.Bar:SlotFrame("rail-right")
	if not hosts["rail-left"] then return end

	self.active = true
	self:Layout()
	hosts["rail-left"]:Show()
	hosts["rail-right"]:Show()

	if not self.wired then
		self.wired = true
		ns.Bar:OnLayout(function() R:Layout() end)
		ns.W:Every(function() R:Refresh() end)
	end
end

function R:Leave()
	self.active = false
	for _, f in pairs(hosts) do
		if f then f:Hide() end
	end
end
