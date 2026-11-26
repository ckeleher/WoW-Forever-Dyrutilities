-- Tests/wowstub.lua
--
-- A fake WoW Forever client, big enough to load Dyrutilities and drive it.
--
-- Shallow on purpose: frames record what was done to them and render nothing.
-- What a green run proves is that the LOGIC holds, not that anything appears on
-- screen or that any API exists on the real client. The probe answers that.

local stub = {}
_G.stub = stub

stub.calls = {}     -- a log of the calls the tests care about
stub.chat = {}      -- everything printed to the chat frame
stub.timers = {}    -- pending C_Timer.After callbacks
stub.inCombat = false

local function log(name, ...)
	stub.calls[#stub.calls + 1] = { name = name, n = select("#", ...), ... }
end
stub.log = log

function stub.reset()
	-- Flush pending timers BEFORE clearing them. Module:Schedule latches a key
	-- until its callback runs, so a dropped callback would latch it forever.
	stub.runTimers()
	stub.calls = {}
	stub.chat = {}
	stub.timers = {}
end

function stub.runTimers(rounds)
	for _ = 1, rounds or 40 do
		local pending = stub.timers
		if #pending == 0 then return end
		stub.timers = {}
		for _, entry in ipairs(pending) do entry.fn() end
	end
end

function stub.countCalls(name)
	local n = 0
	for _, call in ipairs(stub.calls) do
		if call.name == name then n = n + 1 end
	end
	return n
end

function stub.lastCall(name)
	for i = #stub.calls, 1, -1 do
		if stub.calls[i].name == name then return stub.calls[i] end
	end
	return nil
end

function stub.chatMatches(pattern)
	for _, line in ipairs(stub.chat) do
		if line:find(pattern) then return line end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Templates
--
-- CreateFrame with a template the stub does not know throws, as the client
-- does. Tests remove entries to exercise the hand-built fallbacks.
--------------------------------------------------------------------------------

stub.templates = {
	UIPanelButtonTemplate = true,
	UIPanelCloseButton = true,
	UICheckButtonTemplate = true,
}

--------------------------------------------------------------------------------
-- Regions and frames
--------------------------------------------------------------------------------

local frames = {}
stub.frames = frames

local function newRegion(kind)
	local region = { kind = kind, points = {}, shown = true }

	function region:SetTexture(path) self.texture = path end
	function region:GetTexture() return self.texture end
	function region:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
	function region:SetTexCoord() end
	function region:SetText(text) self.text = text end
	function region:GetText() return self.text end
	function region:SetTextColor(r, g, b) self.textColor = { r, g, b } end
	function region:SetJustifyH() end
	function region:SetJustifyV() end
	function region:SetWordWrap() end
	function region:SetFont() return true end
	function region:GetStringWidth() return #tostring(self.text or "") * 6 end
	function region:SetAllPoints() end
	function region:SetPoint(...) self.points[#self.points + 1] = { ... } end
	function region:GetPoint(i) return unpack(self.points[i or 1] or {}) end
	function region:ClearAllPoints() self.points = {} end
	function region:SetSize(w, h) self.width, self.height = w, h end
	function region:SetWidth(w) self.width = w end
	function region:SetHeight(h) self.height = h end
	function region:GetWidth() return self.width or 0 end
	function region:GetHeight() return self.height or 0 end
	function region:Show() self.shown = true end
	function region:Hide() self.shown = false end
	function region:SetShown(v) self.shown = v and true or false end
	function region:IsShown() return self.shown end
	return region
end
stub.newRegion = newRegion

local function newFrame(frameType, name, parent, template)
	if template and template ~= "" then
		for part in template:gmatch("[^,%s]+") do
			if not stub.templates[part] then
				error("CreateFrame: unknown template " .. part, 3)
			end
		end
	end

	local frame = newRegion(frameType or "Frame")
	frame.name = name
	frame.parent = parent
	frame.template = template or ""
	frame.scripts = {}
	frame.events = {}
	frame.regions = {}
	frame.enabled = true
	frame.checked = false
	frame.scroll = 0

	function frame:SetScript(which, fn) self.scripts[which] = fn end
	function frame:GetScript(which) return self.scripts[which] end
	function frame:HookScript(which, fn) self.scripts[which] = fn end

	function frame:RegisterEvent(event)
		if not stub.validEvents[event] then
			error("RegisterEvent: unknown event " .. tostring(event), 2)
		end
		self.events[event] = true
	end
	function frame:UnregisterEvent(event) self.events[event] = nil end
	function frame:UnregisterAllEvents() self.events = {} end
	function frame:IsEventRegistered(event) return self.events[event] and true or false end

	function frame:CreateTexture(_, layer)
		local texture = newRegion("Texture")
		texture.layer = layer
		self.regions[#self.regions + 1] = texture
		return texture
	end
	function frame:CreateFontString(_, layer, fontTemplate)
		local fontString = newRegion("FontString")
		fontString.layer = layer
		fontString.template = fontTemplate
		self.regions[#self.regions + 1] = fontString
		return fontString
	end

	-- The template gives a button its own label, as UIPanelButtonTemplate does.
	if (frameType == "Button" or frameType == "CheckButton") and frame.template ~= "" then
		frame.fontString = newRegion("FontString")
	end
	function frame:SetFontString(fs) self.fontString = fs end
	function frame:GetFontString() return self.fontString end
	function frame:SetText(text)
		self.text = text
		if self.fontString then self.fontString:SetText(text) end
	end

	function frame:Enable() self.enabled = true end
	function frame:Disable() self.enabled = false end
	function frame:IsEnabled() return self.enabled end
	function frame:SetChecked(v) self.checked = v and true or false end
	function frame:GetChecked() return self.checked end
	function frame:SetNormalTexture(t) self.normalTexture = t end
	function frame:SetPushedTexture() end
	function frame:SetHighlightTexture() end
	function frame:SetCheckedTexture() end
	function frame:SetDisabledCheckedTexture() end

	--- A user click. A disabled button ignores it; a CheckButton flips its
	-- state before OnClick runs, exactly as the client does.
	function frame:Click(button)
		if not self.enabled then return end
		if self.kind == "CheckButton" then self.checked = not self.checked end
		return self:Fire("OnClick", button or "LeftButton")
	end

	function frame:SetScrollChild(child) self.scrollChild = child end
	function frame:SetVerticalScroll(v) self.scroll = v end
	function frame:GetVerticalScroll() return self.scroll end
	function frame:EnableMouseWheel() end

	function frame:RegisterForClicks() end
	function frame:RegisterForDrag() end
	function frame:SetMovable() end
	function frame:SetClampedToScreen() end
	function frame:SetFrameStrata(s) self.strata = s end
	function frame:SetFrameLevel() end
	function frame:EnableMouse() end
	function frame:StartMoving() log("StartMoving", self.name) end
	function frame:StopMovingOrSizing() end
	function frame:SetUserPlaced(v) self.userPlaced = v end
	function frame:SetParent(p) self.parent = p end
	function frame:GetParent() return self.parent end
	function frame:SetScale(s) self.scale = s end
	function frame:GetEffectiveScale() return 1 end
	function frame:GetCenter() return self.cx or 0, self.cy or 0 end
	function frame:GetObjectType() return frameType end

	--- Run a script the way the game would.
	function frame:Fire(which, ...)
		local script = self.scripts[which]
		if script then return script(self, ...) end
	end

	-- OnShow, as the client fires it on a hidden-to-shown transition.
	function frame:Show()
		local was = self.shown
		self.shown = true
		if not was then self:Fire("OnShow") end
	end
	function frame:SetShown(v) if v then self:Show() else self:Hide() end end

	frames[#frames + 1] = frame
	return frame
end

function _G.CreateFrame(frameType, name, parent, template)
	local frame = newFrame(frameType, name, parent, template)
	if name then _G[name] = frame end
	return frame
end

function stub.fire(event, ...)
	for _, frame in ipairs(frames) do
		if frame.events[event] and frame.scripts.OnEvent then
			frame.scripts.OnEvent(frame, event, ...)
		end
	end
end

--- Every region of `frame` and its descendants whose text matches `pattern`.
function stub.findText(pattern)
	for _, frame in ipairs(frames) do
		for _, region in ipairs(frame.regions) do
			if region.text and tostring(region.text):find(pattern) then return region, frame end
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

stub.validEvents = {}
for _, event in ipairs({
	"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD",
	"PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
	"BAG_UPDATE", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}) do stub.validEvents[event] = true end

_G.C_EventUtils = {
	IsEventValid = function(event) return stub.validEvents[event] and true or false end,
}

_G.UIParent = newFrame("Frame", "UIParent", nil, "")
UIParent.cx, UIParent.cy = 500, 400

_G.DEFAULT_CHAT_FRAME = {
	AddMessage = function(_, text) stub.chat[#stub.chat + 1] = text end,
}

_G.GameTooltip = newFrame("GameTooltip", "GameTooltip", nil, "")
function GameTooltip:SetOwner(owner) self.owner = owner end
function GameTooltip:SetText(text) self.lines = { text } end
function GameTooltip:AddLine(text) self.lines = self.lines or {}; self.lines[#self.lines + 1] = text end
GameTooltip.shown = false

_G.C_Timer = {
	After = function(delay, fn) stub.timers[#stub.timers + 1] = { delay = delay, fn = fn } end,
}

_G.SlashCmdList = {}
_G.UISpecialFrames = {}

-- Shapes as measured on build 71139 (COMPAT_FINDINGS): the TOC version is a
-- NUMBER, and the project is Camelot, Forever's internal name.
function _G.GetBuildInfo() return "1.60.1", "71139", "Nov 24 2026", 16001 end
function _G.GetLocale() return "enUS" end
function _G.date() return "2026-11-25 12:00:00" end
function _G.InCombatLockdown() return stub.inCombat end
function _G.ReloadUI() log("ReloadUI") end
function _G.UnitHealth() return 100 end
function _G.issecretvalue() return false end
_G.WOW_PROJECT_MAINLINE = 1
_G.WOW_PROJECT_CLASSIC = 2
_G.WOW_PROJECT_CAMELOT = 18
_G.WOW_PROJECT_ID = 18

_G.C_AddOns = {
	GetAddOnMetadata = function(_, field)
		if field == "Version" then return "0.1.0" end
		if field == "AddonCompartmentFunc" then return "Dyrutilities_OnAddonCompartmentClick" end
		return nil
	end,
}

-- The modern Options API, recording what it was asked to do.
_G.Settings = {
	RegisterCanvasLayoutCategory = function(frame, name)
		log("RegisterCanvasLayoutCategory", frame, name)
		return { name = name, frame = frame, GetID = function() return 42 end }
	end,
	RegisterAddOnCategory = function(category) log("RegisterAddOnCategory", category) end,
	OpenToCategory = function(id) log("OpenToCategory", id) end,
}

_G.SettingsPanel = newFrame("Frame", "SettingsPanel", nil, "")
SettingsPanel.shown = false
function _G.HideUIPanel(frame) log("HideUIPanel", frame); frame:Hide() end

return stub
