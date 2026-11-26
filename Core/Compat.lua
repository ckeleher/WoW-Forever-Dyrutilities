-- Core/Compat.lua
--
-- The only file in this addon permitted to:
--   * call an API whose existence or shape on WoW Forever is not certain,
--   * touch a Blizzard-owned frame or global.
--
-- Everything else goes through the accessors below. FEATURE-PROBE, NEVER
-- VERSION-CHECK: every call here is guarded, so a missing API degrades to "not
-- available" instead of a load error. What each guard assumes is listed in
-- Documents/COMPAT_FINDINGS.md, and Probe/Dyrutilities_Probe measures it.
--
-- Forever is Mainline-family code (12.1.x) with Midnight's secret values
-- active. Do not carry over Classic-client knowledge from the sibling addons.

local ADDON, ns = ...

local Compat = {}
ns.Compat = Compat

local _G = _G
local pcall, type, tonumber = pcall, type, tonumber

--------------------------------------------------------------------------------
-- Build identification (informational; never used to gate a feature)
--------------------------------------------------------------------------------

local version, build, buildDate, tocVersion = GetBuildInfo()

Compat.gameVersion = version
Compat.gameBuild = build
Compat.buildDate = buildDate
Compat.tocVersion = tonumber(tocVersion) or 0

--------------------------------------------------------------------------------
-- Events
--
-- Modern clients throw on RegisterEvent for an unknown event. Never register
-- one without knowing it exists.
--------------------------------------------------------------------------------

local probeFrame = CreateFrame("Frame")
local eventValidCache = {}

function Compat.HasEvent(event)
	local cached = eventValidCache[event]
	if cached ~= nil then return cached end

	local valid
	if _G.C_EventUtils and _G.C_EventUtils.IsEventValid then
		local ok, result = pcall(_G.C_EventUtils.IsEventValid, event)
		if ok then valid = result and true or false end
	end
	if valid == nil then
		local ok = pcall(probeFrame.RegisterEvent, probeFrame, event)
		if ok then pcall(probeFrame.UnregisterEvent, probeFrame, event) end
		valid = ok and true or false
	end

	eventValidCache[event] = valid
	return valid
end

--- Register an event, skipping ones this client does not have.
-- @return boolean whether the registration happened
function Compat.RegisterEvent(frame, event)
	if not Compat.HasEvent(event) then return false end
	local ok = pcall(frame.RegisterEvent, frame, event)
	return ok and true or false
end

--------------------------------------------------------------------------------
-- Addon metadata
--------------------------------------------------------------------------------

function Compat.GetAddOnMetadata(name, field)
	if _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata then
		local ok, value = pcall(_G.C_AddOns.GetAddOnMetadata, name, field)
		if ok then return value end
	end
	if _G.GetAddOnMetadata then
		local ok, value = pcall(_G.GetAddOnMetadata, name, field)
		if ok then return value end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Combat and secrets
--------------------------------------------------------------------------------

function Compat.InCombatLockdown()
	if _G.InCombatLockdown then
		local ok, locked = pcall(_G.InCombatLockdown)
		if ok then return locked and true or false end
	end
	return false
end

Compat.hasSecretValues = type(_G.issecretvalue) == "function"

--- Is `value` a Midnight-style secret? Always false where the API is absent.
-- No caller yet: this exists so the first feature that reads unit or combat
-- data has one place to ask.
function Compat.IsSecret(value)
	if not Compat.hasSecretValues then return false end
	local ok, secret = pcall(_G.issecretvalue, value)
	return ok and secret and true or false
end

--------------------------------------------------------------------------------
-- Reload
--------------------------------------------------------------------------------

function Compat.ReloadUI()
	local reload = _G.ReloadUI or (_G.C_UI and _G.C_UI.Reload)
	if not reload then return false end
	return (pcall(reload))
end

--------------------------------------------------------------------------------
-- Escape-to-close
--------------------------------------------------------------------------------

--- Let Escape close a named frame, the way Blizzard's own panels close.
function Compat.AddSpecialFrame(frameName)
	local list = _G.UISpecialFrames
	if type(list) ~= "table" or type(frameName) ~= "string" then return false end
	for _, existing in ipairs(list) do
		if existing == frameName then return true end
	end
	list[#list + 1] = frameName
	return true
end

--------------------------------------------------------------------------------
-- Blizzard Options panel (SPEC D-5: a stub entry that opens our window)
--------------------------------------------------------------------------------

Compat.hasSettingsCanvas = (_G.Settings
	and type(_G.Settings.RegisterCanvasLayoutCategory) == "function"
	and type(_G.Settings.RegisterAddOnCategory) == "function") and true or false

Compat.hasLegacyInterfaceOptions = type(_G.InterfaceOptions_AddCategory) == "function"

--- Register `frame` as a page under Options › AddOns.
-- @return string|nil which route worked: "settings", "legacy" or nil
function Compat.RegisterOptionsPage(frame, title)
	if Compat.hasSettingsCanvas then
		local ok, category = pcall(_G.Settings.RegisterCanvasLayoutCategory, frame, title)
		if ok and category then
			local added = pcall(_G.Settings.RegisterAddOnCategory, category)
			if added then
				Compat.optionsCategory = category
				return "settings"
			end
		end
	end
	if Compat.hasLegacyInterfaceOptions then
		frame.name = title
		if pcall(_G.InterfaceOptions_AddCategory, frame) then
			return "legacy"
		end
	end
	return nil
end

--- Close Blizzard's Options window if it is open.
function Compat.HideOptionsPanel()
	local panel = _G.SettingsPanel or _G.InterfaceOptionsFrame
	if not panel or not panel.IsShown then return false end
	local okShown, shown = pcall(panel.IsShown, panel)
	if not okShown or not shown then return false end
	if _G.HideUIPanel and pcall(_G.HideUIPanel, panel) then return true end
	return (pcall(panel.Hide, panel))
end

--------------------------------------------------------------------------------
-- Report
--------------------------------------------------------------------------------

--- What this client supports, for /dyru compat.
function Compat.Describe()
	return {
		gameVersion = Compat.gameVersion,
		gameBuild = Compat.gameBuild,
		tocVersion = Compat.tocVersion,
		projectId = _G.WOW_PROJECT_ID,
		locale = GetLocale(),
		settingsCanvas = Compat.hasSettingsCanvas,
		legacyInterfaceOptions = Compat.hasLegacyInterfaceOptions,
		optionsRoute = Compat.optionsRoute or "none",
		secretValues = Compat.hasSecretValues,
		addonCompartment = _G.AddonCompartmentFrame ~= nil,
		specialFrames = type(_G.UISpecialFrames) == "table",
	}
end
