--[[
	Standby.lua -- tus hechizos, en su sitio, mientras la interfaz de verdad no
	puede volver.

	Sale en un caso y solo en uno: sales del modo RTS **en combate**. PlayerFrame,
	MainMenuBar y las barras de accion son frames PROTEGIDOS y `Show()` sobre
	ellos dentro de combate lo bloquea el cliente, asi que la interfaz de Blizzard
	no puede volver hasta que acabe la pelea. Antes eso te dejaba con la camara en
	tu personaje y la pantalla vacia; ahora te deja esto, y al salir de combate se
	va solo y vuelve la de verdad.

	=== ES UN ESPEJO, NO UNA BARRA ==========================================

	No lanza nada. Sus botones no son `SecureActionButtonTemplate` y no tienen
	`type`/`action`: son texturas.

	Y es a proposito, no una limitacion aceptada de mala gana. Una barra que
	lanzase de verdad tendria que ser segura, y un frame seguro no se puede crear
	ni ensenar ni esconder EN COMBATE -- que es exactamente el unico momento en
	que esto existe. Habria que tenerla creada y visible todo el rato, con alfa 0
	durante el modo RTS, y entonces se comeria los clicks del mundo en la franja
	de abajo, que es justo donde esta la consola. Se cambiaria un problema por
	otro peor.

	LAS TECLAS SIGUEN FUNCIONANDO IGUAL, que es lo que hace que esto baste. Una
	barra de accion escondida sigue respondiendo a sus atajos -- es lo mismo que
	pasa con el Alt-Z del propio juego -- asi que se puede pelear con el teclado
	mientras se mira aqui el estado. Lo que faltaba no era poder lanzar: era ver
	QUE tienes y si esta listo.

	=== LA POSICION SE COPIA, NO SE ELIGE ===================================

	Cada boton se dibuja en el rectangulo EXACTO de su boton real, leido del
	propio frame de Blizzard. Un frame escondido conserva su ancla y su tamano,
	asi que `GetLeft()` y compania siguen contestando.

	Eso es lo que cumple "los spells en su sitio, ni que esten volando en el
	aire": no hay una disposicion inventada que se parezca a la tuya, es la tuya.
	Si mueves tus barras o cambias su escala, esto se mueve con ellas y no hay
	nada que mantener al dia.

	El unico detalle es la ESCALA: `GetLeft()` responde en el espacio del propio
	frame, asi que hay que pasarlo al de UIParent con la razon de escalas
	efectivas. Con las barras a escala 1 sale lo mismo, pero no siempre lo estan.
]]

local ADDON, ns = ...

local S = {}
ns.Standby = S

S.active = false

-- Las barras de accion de 3.3.5a, por nombre de boton. Se prueban todas y se
-- usan las que existan Y tengan hueco: preguntar al cliente cuales hay es mas
-- barato que llevar la cuenta de que barras tiene activadas el jugador.
local BARS = {
	"ActionButton",
	"MultiBarBottomLeftButton",
	"MultiBarBottomRightButton",
	"MultiBarRightButton",
	"MultiBarLeftButton",
}

local frame, notice
local slots = {}

--- La rejilla ---------------------------------------------------------------

local function Slot(i)
	if slots[i] then return slots[i] end

	local f = CreateFrame("Frame", "RTSStandbySlot" .. i, frame)
	f:EnableMouse(false)

	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetTexture(0, 0, 0, 0.6)

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetAllPoints()
	f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- El barrido de enfriamiento del propio cliente. Es un widget, no un dibujo
	-- nuestro: asi gira igual que el de la barra de verdad.
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints()

	f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)

	f.key = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
	f.key:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

	slots[i] = f
	return f
end

--- El rectangulo de un boton real ------------------------------------------

-- Devuelve x, y (esquina inferior izquierda) y tamano, ya en el espacio de
-- UIParent. nil si ese boton no esta anclado a nada -- que pasa con las barras
-- que el jugador no tiene puestas.
local function RectOf(button)
	local l, b = button:GetLeft(), button:GetBottom()
	if not l or not b then return nil end

	local k = button:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return l * k, b * k, button:GetWidth() * k, button:GetHeight() * k
end

-- El hueco de accion que ese boton esta ensenando. `ActionButton_GetPagedID`
-- es lo que usa el cliente para la barra principal, que cambia de pagina; para
-- las demas `action` ya es el numero. Se prueba la funcion y se cae al campo.
local function SlotOf(button)
	if ActionButton_GetPagedID then
		local ok, id = pcall(ActionButton_GetPagedID, button)
		if ok and id then return id end
	end
	return button.action
end

--- Rellenar -----------------------------------------------------------------

function S:Refresh()
	if not self.active or not frame then return end

	local n = 0

	for _, prefix in ipairs(BARS) do
		for i = 1, 12 do
			local real = _G[prefix .. i]
			local id = real and SlotOf(real)
			if id and HasAction(id) then
				local x, y, w, h = RectOf(real)
				if x then
					n = n + 1
					local f = Slot(n)
					f:ClearAllPoints()
					f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
					f:SetWidth(w)
					f:SetHeight(h)

					f.icon:SetTexture(GetActionTexture(id))

					local count = GetActionCount(id)
					f.count:SetText((count and count > 1) and count or "")

					local start, dur, enable = GetActionCooldown(id)
					CooldownFrame_SetTimer(f.cd, start, dur, enable)

					-- Gris cuando no se puede usar y azul cuando falta mana:
					-- los dos colores que usa la barra de verdad, para que se
					-- lea igual sin tener que aprender nada nuevo.
					local usable, nomana = IsUsableAction(id)
					if nomana then
						f.icon:SetVertexColor(0.35, 0.35, 1.0)
					elseif not usable then
						f.icon:SetVertexColor(0.4, 0.4, 0.4)
					else
						f.icon:SetVertexColor(1, 1, 1)
					end

					f.key:SetText(real.hotkey and real.hotkey:GetText() or "")
					f:Show()
				end
			end
		end
	end

	for i = n + 1, #slots do slots[i]:Hide() end
	self.shown = n
end

--- Entrar y salir -----------------------------------------------------------

function S:Create()
	if frame then return end

	frame = CreateFrame("Frame", "RTSStandby", UIParent)
	frame:SetAllPoints(UIParent)
	frame:EnableMouse(false)
	-- Por encima de todo: durante esta ventana no hay nada mas en pantalla, y
	-- si algo de Blizzard reaparece solo, esto tiene que seguir viendose.
	frame:SetFrameStrata("HIGH")
	frame:Hide()

	notice = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	notice:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 4)
	notice:SetTextColor(1, 0.82, 0.2)
	notice:SetText("En combate: tu interfaz vuelve entera al acabar. " ..
		"Las teclas de tus hechizos funcionan.")
end

function S:Show()
	self:Create()
	if self.active then return end
	self.active = true
	self:Refresh()
	frame:Show()

	if not self.wired then
		self.wired = true
		ns.W:Every(function() S:Refresh() end)
	end

	if (self.shown or 0) == 0 then
		-- Ni un solo boton con hueco. Es raro y merece decirse: significa que
		-- las barras reales no estan ancladas, y entonces esto no puede copiar
		-- ninguna posicion.
		ns.Print("|cffff8800No he encontrado ninguna barra de accion que copiar.|r")
	end
end

function S:Hide()
	if not self.active then return end
	self.active = false
	if frame then frame:Hide() end
end
