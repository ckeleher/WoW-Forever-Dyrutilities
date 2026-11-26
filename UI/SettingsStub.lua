-- UI/SettingsStub.lua
--
-- The entry under Esc > Options > AddOns (SPEC D-5). It does not duplicate the
-- menu: it is one line of text and a button that opens the real window.
--
-- Which registration route exists on Forever is unverified (COMPAT_FINDINGS);
-- Compat tries the modern Settings canvas, then the legacy InterfaceOptions call.

local ADDON, ns = ...

local Compat = ns.Compat
local Widgets = ns.Widgets

local SettingsStub = {}
ns.SettingsStub = SettingsStub

SettingsStub.TITLE = "Dyrutilities"

function SettingsStub:Register()
	if self.frame then return Compat.optionsRoute end

	local page = CreateFrame("Frame")
	page:Hide()

	-- Canvas pages are asked to commit/default/refresh by the Settings panel on
	-- some builds. There is nothing to commit here; no-ops keep it from erroring.
	page.OnCommit = function() end
	page.OnDefault = function() end
	page.OnRefresh = function() end

	local title = Widgets:Label(page, SettingsStub.TITLE, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)

	local text = Widgets:Label(page,
		"Dyrutilities has its own window. Every feature and its settings are there.",
		"GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetJustifyH("LEFT")

	local open = Widgets:Button(page, "Open Dyrutilities", 160, 24, function()
		Compat.HideOptionsPanel()
		ns.MainWindow:Show()
	end)
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)

	local hint = Widgets:Label(page, "Also: /dyru or /dyrutilities.", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)

	self.frame = page
	Compat.optionsRoute = Compat.RegisterOptionsPage(page, SettingsStub.TITLE)
	if not Compat.optionsRoute then
		ns.Errors:Debug("no Options panel API found; the AddOns entry is skipped")
	end
	return Compat.optionsRoute
end
