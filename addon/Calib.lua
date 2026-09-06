--[[
	Calib.lua -- measures the projection instead of guessing it.

	The open bug: selection rings land short of the unit, and the miss varies per
	unit, so a single SX/SY scale demonstrably cannot be the whole model. Eyeball
	calibration ("put the cursor on its feet") is one noisy sample, which is how
	we got a fit that worked for one bot and not the next.

	Ground truth is the game's OWN picking: when the client reports a unit as
	"mouseover", that unit's model genuinely covers the cursor pixel. Sweeping the
	mouse across a bot therefore yields many exact (world point -> screen pixel)
	correspondences with no human precision involved.

	=== why the fit is weighted the way it is ===============================

	A sample's error is "how far the cursor sat from the model's true centre",
	which is a WORLD length (half a body width) divided by depth. So the error in
	ndc shrinks with distance: a bot 5 yards away spans ~0.2 ndc, one 40 yards
	away spans ~0.025. Averaging per-sample implied scales therefore mixes wildly
	unequal precisions AND divides by a near-zero denominator for anything close
	to screen centre -- the first version of this file did exactly that and
	reported a 152% spread, which was its own noise, not the projection's.

	Multiplying through by depth fixes it. Writing the two candidate models as

	  A. ndcx = (rc / depth) * S
	  B. ndcx = (rc / (depth + D)) * S

	and multiplying by (depth + D) gives, for both,

	  ndcx * depth = S * rc - D * ndcx

	which is linear in the unknowns S and D with a NOW-CONSTANT error term. That
	is an ordinary least-squares problem, so D comes with a standard error and the
	choice between A and B stops being a judgement call: B is only justified when
	D is bigger than twice its own uncertainty.

	Model B exists because a camera origin displaced along the view axis
	reproduces the exact reported symptom -- everything short, worse up close,
	unfixable by any single scale.

	The vertical axis gets its own regression rather than being assumed. The
	cursor lands anywhere between a model's feet and its head, so ndcy carries an
	unknown body height; but that height is a CONSTANT offset, so

	  ndcy * depth = SY * uc + SY * meanHeight

	is a regression with an intercept, and the intercept absorbs the height. The
	recovered height doubles as a sanity check: it has to come out around a
	yard for a humanoid, and if it does, the whole error model is confirmed.
]]

local ADDON, ns = ...

local C = {}
ns.Calib = C

C.samples = {}
C.active = false

-- A sample is only trustworthy if the unit is standing still (a moving model
-- renders ahead of the last published position). Off-centre samples no longer
-- need a hard filter -- the weighted fit gives them their proper small weight --
-- but a token cut keeps degenerate geometry out.
local STILL_FOR    = 0.30   -- seconds since the unit's position last changed
local MIN_OFFAXIS  = 0.04   -- |ndcx|
local SAMPLE_EVERY = 0.05
local REJECT_AT    = 2.5    -- sigmas; one outlier pass

local function Now() return GetTime() end

function C:Reset()
	self.samples = {}
	RTSCommandDB.calSamples = nil
	self.fitX, self.fitY = nil, nil
	ns.Print("calibration samples cleared.")
end

function C:Record()
	if RTS_HasCam ~= 1 then return end

	local guid = UnitGUID("mouseover")
	if not guid then return end

	local wx, wy, wz = ns.Markers:UnitWorld(guid)
	if not wx then return end   -- not a unit the DLL publishes

	-- Stationary check, using the tracker Markers already maintains.
	local t = ns.Markers.track[string.upper(guid)]
	if not t or (Now() - t.ct) < STILL_FOR then return end

	-- raw depth: the fit has to see the unbiased geometry, not a previous fit's
	local depth, rc, uc = ns.Markers:CamCoords(wx, wy, wz, true)
	if not depth then return end

	local mx, my = GetCursorPosition()
	local s = UIParent:GetEffectiveScale()
	local w, h = GetScreenWidth(), GetScreenHeight()
	local ndcx = ((mx / s) / w) * 2 - 1
	local ndcy = ((my / s) / h) * 2 - 1

	if math.abs(ndcx) < MIN_OFFAXIS then return end

	table.insert(self.samples, {
		guid = guid,
		name = UnitName("mouseover") or "?",
		t = Now(),
		depth = depth, rc = rc, uc = uc,
		ndcx = ndcx, ndcy = ndcy,
	})

	-- Live feedback: hovering a bot looks identical to hovering nothing, so
	-- without a counter there is no way to tell the sweep is landing.
	local n = #self.samples
	if n % 25 == 0 then
		ns.Print(("cal: %d samples (%s at %.0fy)"):format(n, self.samples[n].name, depth))
	end
end

function C:Start()
	if self.active then return end
	if not ns.Bridge:IsNative() then
		ns.Print("|cffff0000cal:|r native bridge not attached - inject rts_core.dll first.")
		return
	end
	self.active = true

	local acc = 0
	local f = self.frame or CreateFrame("Frame")
	self.frame = f
	f:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < SAMPLE_EVERY then return end
		acc = 0
		C:Record()
	end)

	ns.Print("|cff00ff00cal: recording.|r Bots must be standing still (|cffffff00stay|r).")
	ns.Print("Hover a bot and drag the cursor across its body, edge to edge, a few")
	ns.Print("times - only pixels ON the model count. Repeat at several distances,")
	ns.Print("keeping bots off to the side, not dead centre. Then |cffffff00/rts cal stop|r.")
end

function C:Stop()
	self.active = false
	if self.frame then self.frame:SetScript("OnUpdate", nil) end
	-- Persisted so refining the fit never costs another sweep.
	RTSCommandDB.calSamples = self.samples
	ns.Print(("cal: stopped, %d samples (saved)."):format(#self.samples))
end

--- Least squares -----------------------------------------------------------

-- Fit y = a*u + b*v. uf/vf/yf pull the terms out of a sample; pass a vf that
-- returns 1 to make b an intercept. Returns a, b, sigma, se(a), se(b), n.
local function LS2(samples, uf, vf, yf)
	local Suu, Suv, Svv, Suy, Svy, n = 0, 0, 0, 0, 0, 0
	for _, s in ipairs(samples) do
		if not s.reject then
			local u, v, y = uf(s), vf(s), yf(s)
			Suu, Suv, Svv = Suu + u * u, Suv + u * v, Svv + v * v
			Suy, Svy = Suy + u * y, Svy + v * y
			n = n + 1
		end
	end
	local det = Suu * Svv - Suv * Suv
	if n < 5 or math.abs(det) < 1e-12 then return nil end

	local a = (Suy * Svv - Svy * Suv) / det
	local b = (Svy * Suu - Suy * Suv) / det

	local rss = 0
	for _, s in ipairs(samples) do
		if not s.reject then
			local r = yf(s) - a * uf(s) - b * vf(s)
			s.res = r
			rss = rss + r * r
		end
	end
	local sig2 = rss / (n - 2)
	return a, b, math.sqrt(sig2),
	       math.sqrt(sig2 * Svv / det), math.sqrt(sig2 * Suu / det), n
end

-- Fit y = a1*f1 + a2*f2 + a3*f3. Needed because two different defects produce a
-- depth trend and they have to be told apart rather than picked by taste:
--   a displaced eye  -> a term in ndcx      (model B)
--   an off-centre 3D viewport -> a term in depth
-- Fitting both at once lets each one's own error bar decide. Explicit 3x3
-- inverse; there is no matrix library here.
local function LS3(samples, f1, f2, f3, yf)
	local fs = { f1, f2, f3 }
	local A = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
	local B = { 0, 0, 0 }
	local n = 0
	for _, s in ipairs(samples) do
		if not s.reject then
			local v = { fs[1](s), fs[2](s), fs[3](s) }
			local y = yf(s)
			for i = 1, 3 do
				B[i] = B[i] + v[i] * y
				for j = 1, 3 do A[i][j] = A[i][j] + v[i] * v[j] end
			end
			n = n + 1
		end
	end
	if n < 8 then return nil end

	local a, b, c = A[1][1], A[1][2], A[1][3]
	local d, e, f = A[2][1], A[2][2], A[2][3]
	local g, hh, i2 = A[3][1], A[3][2], A[3][3]
	local det = a * (e * i2 - f * hh) - b * (d * i2 - f * g) + c * (d * hh - e * g)
	if math.abs(det) < 1e-18 then return nil end

	local inv = {
		{ (e * i2 - f * hh) / det, (c * hh - b * i2) / det, (b * f - c * e) / det },
		{ (f * g - d * i2) / det,  (a * i2 - c * g) / det,  (c * d - a * f) / det },
		{ (d * hh - e * g) / det,  (b * g - a * hh) / det,  (a * e - b * d) / det },
	}
	local co = {}
	for i = 1, 3 do
		co[i] = inv[i][1] * B[1] + inv[i][2] * B[2] + inv[i][3] * B[3]
	end

	local rss = 0
	for _, s in ipairs(samples) do
		if not s.reject then
			local r = yf(s) - (co[1] * fs[1](s) + co[2] * fs[2](s) + co[3] * fs[3](s))
			rss = rss + r * r
		end
	end
	local sig2 = rss / (n - 3)
	local se = {}
	for i = 1, 3 do se[i] = math.sqrt(math.max(0, sig2 * inv[i][i])) end
	return co, se, math.sqrt(sig2), n
end

-- Fit y = a*u, no intercept.
local function LS1(samples, uf, yf)
	local Suu, Suy, n = 0, 0, 0
	for _, s in ipairs(samples) do
		if not s.reject then
			local u = uf(s)
			Suu, Suy, n = Suu + u * u, Suy + u * yf(s), n + 1
		end
	end
	if n < 2 or Suu < 1e-12 then return nil end
	return Suy / Suu, n
end

-- terms for the horizontal fit: ndcx*depth = S*rc + (-D)*ndcx
local uX = function(s) return s.rc end
local vX = function(s) return s.ndcx end
local yX = function(s) return s.ndcx * s.depth end

--- Independent sweeps ------------------------------------------------------
-- Samples inside one sweep are NOT independent: sweep a bot slightly left of
-- centre and all fifty of its samples carry that same bias. Treating them as
-- independent inflated D's significance to a bogus 5 sigma. One sweep is one
-- measurement, so collapse each to its centroid and fit on those. Fewer points,
-- honest error bars.
local SWEEP_GAP = 0.6   -- seconds of no samples for the same unit = new sweep

function C:Sweeps()
	local out, cur, prev = {}, nil, nil
	for _, s in ipairs(self.samples) do
		if s.reject then
			-- skip
		else
			local gap = (s.t and prev and prev.t) and (s.t - prev.t) or 0
			if not cur or not prev or s.guid ~= prev.guid or gap > SWEEP_GAP then
				cur = { rc = 0, depth = 0, ndcx = 0, uc = 0, ndcy = 0, n = 0, name = s.name }
				table.insert(out, cur)
			end
			cur.rc, cur.depth = cur.rc + s.rc, cur.depth + s.depth
			cur.ndcx, cur.ndcy = cur.ndcx + s.ndcx, cur.ndcy + s.ndcy
			cur.uc, cur.n = cur.uc + s.uc, cur.n + 1
			prev = s
		end
	end
	for _, c in ipairs(out) do
		c.rc, c.depth = c.rc / c.n, c.depth / c.n
		c.ndcx, c.ndcy = c.ndcx / c.n, c.ndcy / c.n
		c.uc = c.uc / c.n
	end
	return out
end

local function ndcResidual(samples, S, D)
	local rss, n = 0, 0
	for _, s in ipairs(samples) do
		if not s.reject then
			local pred = (s.rc / (s.depth + D)) * S
			rss, n = rss + (pred - s.ndcx) ^ 2, n + 1
		end
	end
	if n == 0 then return nil end
	return math.sqrt(rss / n)
end

function C:Report()
	local samples = self.samples
	if #samples < 10 then
		ns.Print(("|cffff0000cal:|r only %d samples - |cffffff00/rts cal start|r and sweep more."):format(#samples))
		return
	end
	for _, s in ipairs(samples) do s.reject = nil end
	self.fitX, self.fitY = nil, nil

	-- Fit once only to size the scatter and find outliers; every reported number
	-- comes from the per-sample or per-sweep fits further down.
	local S, _, sigma, _, _, n = LS2(samples, uX, vX, yX)
	if not S then ns.Print("|cffff0000cal:|r fit failed (degenerate geometry).") return end

	local dropped = 0
	for _, s in ipairs(samples) do
		if s.res and math.abs(s.res) > REJECT_AT * sigma then
			s.reject, dropped = true, dropped + 1
		end
	end
	if dropped > 0 then
		S, _, sigma, _, _, n = LS2(samples, uX, vX, yX)
		if not S then ns.Print("|cffff0000cal:|r fit failed after outlier pass.") return end
	end

	local w, h = GetScreenWidth(), GetScreenHeight()
	ns.Print(("--- calibration: %d samples used, %d dropped ---"):format(n, dropped))
	ns.Print(("screen %.0fx%.0f aspect %.4f | cam aspect %.4f | cam fov %.4f rad")
		:format(w, h, w / h, RTS_CamAspect or 0, RTS_CamFov or 0))
	if RTS_CamAspect and math.abs(w / h - RTS_CamAspect) > 0.01 then
		ns.Print("|cffff0000screen aspect != camera aspect|r - that alone would skew Y.")
	end

	-- sigma is in ndc*yards; divided by the scale it is a world length, namely
	-- how far off centre the cursor typically sat. It must land near a body
	-- half-width. If it does, the error model behind this whole fit is sound.
	ns.Print(("scatter %.3f ndc*y -> cursor sat %.2f y off centre (expect ~0.3-0.8)")
		:format(sigma, sigma / math.abs(S)))

	-- Per-depth scale, each bucket fitted properly rather than averaged.
	local buckets = {
		{ lo = 0, hi = 12 }, { lo = 12, hi = 25 }, { lo = 25, hi = 45 }, { lo = 45, hi = 1e9 },
	}
	ns.Print("scale fitted per depth band (flat = model A, sloped = model B):")
	for _, bk in ipairs(buckets) do
		local sub = {}
		for _, s in ipairs(samples) do
			if not s.reject and s.depth >= bk.lo and s.depth < bk.hi then
				table.insert(sub, s)
			end
		end
		local bs, bn = LS1(sub, uX, yX)
		if bs then
			ns.Print(("  %3d-%3dy  n=%-4d  S=%.4f")
				:format(bk.lo, (bk.hi > 1e8) and 999 or bk.hi, bn, bs))
		end
	end

	-- Model A: the same fit with D pinned to zero. This is the physically honest
	-- form for projecting an arbitrary world point, so it stays the default.
	local SA = LS1(samples, uX, yX)
	ns.Print(("|cffffff00A) pure scale:|r S=%.4f  (all %d samples, ndc residual %.4f)")
		:format(SA, n, ndcResidual(samples, SA, 0)))

	-- The acceptance test: measurement against the value derived from the
	-- camera's own diagonal FOV. Agreement means no calibration is needed at all.
	local dSX, dSY = ns.Markers:Derived()
	if dSX then
		local off = math.abs(SA / dSX - 1) * 100
		ns.Print(("|cffffff00derived|r from diagonal fov: SX=%.4f SY=%.4f -> measured %.1f%% off %s")
			:format(dSX, dSY, off, (off < 3) and "|cff00ff00CONFIRMED|r" or "|cffff0000check|r"))
	end

	-- The D question, decided on independent sweeps only.
	local sw = self:Sweeps()
	local SB, bb, sigW, seSB, seDB, nw = LS2(sw, uX, vX, yX)
	ns.Print(("independent sweeps: %d"):format(#sw))

	local useB, D2 = false, 0
	if not SB then
		ns.Print("|cffffff00D undecidable|r - too few sweeps to fit it. Model A stands.")
	else
		D2 = -bb
		local sig = (seDB > 1e-9) and (math.abs(D2) / seDB) or 0
		ns.Print(("|cffffff00B) scale+origin:|r S=%.4f +-%.4f  D=%+.2f +-%.2f y  (%.1f sigma)")
			:format(SB, seSB, D2, seDB, sig))
		useB = (nw >= 10) and (sig > 2) and (math.abs(D2) > 0.15)
		if useB then
			ns.Print(("|cff00ff00Model B:|r stored camera position is %+.2f y off the real eye."):format(D2))
		elseif nw < 10 then
			ns.Print(("|cffffff00need >=10 sweeps|r for a verdict on D (have %d). Model A stands."):format(nw))
		else
			ns.Print(("|cff00ff00Model A:|r D=%+.2f is within noise. Plain scale it is."):format(D2))
		end
	end

	-- Three-term probe. A depth trend can come from a displaced eye (a term in
	-- ndcx) or from a 3D viewport whose centre is not UIParent's centre (a term
	-- in depth). Fitted together, whichever is real keeps its significance and
	-- the other collapses. Point estimates are unbiased regardless of sweep
	-- clustering; only the error bars here are optimistic.
	local co, cse = LS3(samples, uX, vX, function(s) return s.depth end, yX)
	if co then
		ns.Print("|cffffff00probe|r (both defects at once, all samples):")
		ns.Print(("  S=%.4f +-%.4f   D=%+.2f +-%.2f y   centre off=%+.4f +-%.4f ndc")
			:format(co[1], cse[1], -co[2], cse[2], co[3], cse[3]))
		local sD = (cse[2] > 1e-9) and math.abs(co[2] / cse[2]) or 0
		local sC = (cse[3] > 1e-9) and math.abs(co[3] / cse[3]) or 0
		ns.Print(("  D is %.1f sigma, centre offset is %.1f sigma -> %s"):format(sD, sC,
			(sC > sD * 1.5) and "|cff00ff00off-centre viewport|r"
			or (sD > sC * 1.5) and "|cff00ff00displaced eye|r" or "|cffffff00tangled|r"))
		if math.abs(co[3]) > 0.002 then
			ns.Print(("  that offset is %.0f screen px from centre"):format(math.abs(co[3]) * w / 2))
		end
	end

	-- Vertical, measured rather than assumed. The intercept absorbs the body
	-- height, but the fit goes degenerate when uc barely varies across samples,
	-- so it is only believed when its own error bar is tight and the recovered
	-- height is anatomically possible.
	local Dv = useB and D2 or 0
	local convention = (useB and SB or SA) * (w / h)
	local SY, inter, _, seSY = LS2(sw,
		function(s) return s.uc end,
		function(s) return 1 end,
		function(s) return s.ndcy * (s.depth + Dv) end)

	local goodY = false
	if SY then
		local bodyH = inter / SY
		local rel = math.abs(seSY / SY)
		goodY = rel < 0.15 and bodyH > 0 and bodyH < 3 and SY > 0
		ns.Print(("|cffffff00vertical:|r SY=%.4f +-%.4f (%.0f%%)  cursor %.2f y above feet -> %s")
			:format(SY, seSY, rel * 100, bodyH, goodY and "|cff00ff00usable|r" or "|cffff0000degenerate|r"))
		if goodY then
			self.fitY = { SY = SY }
			ns.Print(("shared-focal-length predicts %.4f -> %s"):format(convention,
				(math.abs(SY - convention) < 3 * seSY) and "|cff00ff00agrees|r" or "|cffff0000disagrees|r"))
		else
			self.fitY = nil
			ns.Print("Vary the camera PITCH (look down, then level) to break the")
			ns.Print("degeneracy. Until then SY falls back to the standard convention.")
		end
	end
	if not goodY then
		ns.Print(("SY will use the convention: %.4f"):format(convention))
	end

	-- Same probe on the vertical axis: SY, body height, and a vertical centre
	-- offset. This axis matters most, since it is the one that disagreed with the
	-- shared-focal-length convention.
	local vco, vse = LS3(samples,
		function(s) return s.uc end,
		function(s) return 1 end,
		function(s) return s.depth end,
		function(s) return s.ndcy * s.depth end)
	if vco then
		ns.Print(("|cffffff00probe Y:|r SY=%.4f +-%.4f  body=%.2f y  centre off=%+.4f +-%.4f")
			:format(vco[1], vse[1], (vco[1] ~= 0) and vco[2] / vco[1] or 0, vco[3], vse[3]))
	end

	self.fitX = { S = useB and SB or SA, D = Dv, useB = useB }
	ns.Print("|cffffff00/rts cal apply|r to write it.")
end

function C:Apply()
	if not self.fitX then
		ns.Print("|cffff0000cal:|r run |cffffff00/rts cal report|r first.")
		return
	end

	local w, h = GetScreenWidth(), GetScreenHeight()
	local S, D = self.fitX.S, self.fitX.D

	-- SY is NOT taken from the vertical regression even when that regression looks
	-- tight. Pixels are square here (render aspect == display aspect), so the
	-- focal length in pixels is the same on both axes and SY is pinned to SX by
	-- geometry. A measured SY that disagrees is a biased measurement -- the
	-- cursor's height above a model's feet is not independent of distance -- and
	-- believing it would put a 16% error into the vertical axis.
	local SY = S * (w / h)

	ns.Markers.SX = S
	ns.Markers.SY = SY
	ns.Markers.DEPTH_BIAS = D
	ns.Markers.autoIntrinsics = false

	RTSCommandDB.SX, RTSCommandDB.SY, RTSCommandDB.DEPTH_BIAS = S, SY, D
	RTSCommandDB.forceScale = true

	ns.Print(("|cff00ff00applied|r SX=%.4f SY=%.4f depthBias=%+.2f (saved, overrides derived)")
		:format(S, SY, D))
	ns.Print("|cffffff00/rts cal auto|r goes back to the derived intrinsics.")
end

-- Drop the override and go back to deriving the scales from the live camera.
function C:Auto()
	-- Por `UseDerived`, que es el unico sitio que sabe todo lo que hay que
	-- olvidar: dejar `RTSCommandDB.SX` puesto hacia que la escala mala volviera
	-- al siguiente arranque, porque `Core.Initialise` la lee sin mirar.
	ns.Markers:UseDerived()
	ns.Markers.overrideChecked = true
	local SX, SY = ns.Markers:Intrinsics()
	ns.Print(("|cff00ff00derived intrinsics|r SX=%.4f SY=%.4f from fov %.4f rad (diagonal)")
		:format(SX, SY, RTS_CamFov or 0))
end

-- Raw dump, for when the summary is not enough.
function C:Dump(limit)
	limit = limit or 20
	local step = math.max(1, math.floor(#self.samples / limit))
	ns.Print("depth   rc      ndcx     ndcy     unit")
	for i = 1, #self.samples, step do
		local s = self.samples[i]
		ns.Print(("%6.1f %7.2f %8.4f %8.4f  %s%s")
			:format(s.depth, s.rc, s.ndcx, s.ndcy, s.name, s.reject and " |cffff0000(out)|r" or ""))
	end
end
