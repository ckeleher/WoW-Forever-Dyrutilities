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
-- Edit Mode (COMPAT_FINDINGS "Edit Mode")
--
-- There is no addon-facing way to register with Edit Mode. What IS verified:
-- the EventRegistry callbacks EditMode.Enter / EditMode.Exit fire, and our own
-- frames at FULLSCREEN_DIALOG strata show over it. Features show their own
-- handles while it is open.
--------------------------------------------------------------------------------

Compat.hasEditModeCallbacks = (type(_G.EventRegistry) == "table"
	and type(_G.EventRegistry.RegisterCallback) == "function") and true or false

local editModeListeners = {}
local editModeRegistered = false

local function fireEditMode(entering)
	for key, listener in pairs(editModeListeners) do
		local fn = entering and listener.enter or listener.exit
		if fn then ns.Errors:Safe("editmode:" .. key, fn) end
	end
end

--- Call `onEnter` / `onExit` when Edit Mode opens and closes. One registration
-- with the client serves every listener; `key` replaces an earlier listener.
-- @return boolean whether Edit Mode notifications are available at all
function Compat.OnEditMode(key, onEnter, onExit)
	if not Compat.hasEditModeCallbacks then return false end
	editModeListeners[key] = { enter = onEnter, exit = onExit }
	if not editModeRegistered then
		local okEnter = pcall(_G.EventRegistry.RegisterCallback, _G.EventRegistry, "EditMode.Enter",
			function() fireEditMode(true) end, "Dyrutilities")
		local okExit = pcall(_G.EventRegistry.RegisterCallback, _G.EventRegistry, "EditMode.Exit",
			function() fireEditMode(false) end, "Dyrutilities")
		editModeRegistered = okEnter and okExit
	end
	return editModeRegistered
end

function Compat.IsEditModeActive()
	local manager = _G.EditModeManagerFrame
	if type(manager) ~= "table" or type(manager.IsShown) ~= "function" then return false end
	local ok, shown = pcall(manager.IsShown, manager)
	return ok and shown and true or false
end

--- Anchor one of OUR frames below Edit Mode's window. Reads Blizzard's frame
-- only as an anchor target, which changes nothing on it.
-- @return boolean whether the manager window was there to anchor to
function Compat.AnchorBelowEditMode(frame, yOffset)
	local manager = _G.EditModeManagerFrame
	frame:ClearAllPoints()
	if type(manager) == "table" then
		local ok = pcall(frame.SetPoint, frame, "TOPLEFT", manager, "BOTTOMLEFT", 0, yOffset or -6)
		if ok then return true end
	end
	frame:SetPoint("TOP", _G.UIParent, "TOP", 0, -120)
	return false
end

--------------------------------------------------------------------------------
-- Alerts (toasts) (COMPAT_FINDINGS "Loot roll and alert frames")
--
-- Verified 26 Nov 2026: AlertFrame:SetBaseAnchorFrame(ourFrame) makes every
-- toast anchor to our frame, and ResetBaseAnchorFrame() undoes it exactly.
-- Blizzard's AlertFrame itself is never moved.
--------------------------------------------------------------------------------

Compat.hasAlertBaseAnchor = (type(_G.AlertFrame) == "table"
	and type(_G.AlertFrame.SetBaseAnchorFrame) == "function"
	and type(_G.AlertFrame.ResetBaseAnchorFrame) == "function") and true or false

function Compat.SetAlertBaseAnchor(frame)
	if not Compat.hasAlertBaseAnchor then return false end
	return (pcall(_G.AlertFrame.SetBaseAnchorFrame, _G.AlertFrame, frame))
end

function Compat.ResetAlertBaseAnchor()
	if not Compat.hasAlertBaseAnchor then return false end
	return (pcall(_G.AlertFrame.ResetBaseAnchorFrame, _G.AlertFrame))
end

--- Put one of OUR frames exactly where Blizzard's AlertFrame is, so a toast
-- anchored to it lands where it would by default.
function Compat.AnchorAtAlertFrame(frame)
	frame:ClearAllPoints()
	local alert = _G.AlertFrame
	if type(alert) == "table" and pcall(frame.SetPoint, frame, "BOTTOM", alert, "BOTTOM", 0, 0) then
		return true
	end
	-- Blizzard's measured default (COMPAT_FINDINGS): BOTTOM of UIParent, (0, 128).
	frame:SetPoint("BOTTOM", _G.UIParent, "BOTTOM", 0, 128)
	return false
end

--- Show a sample "you won" toast, so the player can see where toasts land.
function Compat.PreviewLootToast()
	local system = _G.LootAlertSystem
	if type(system) ~= "table" or type(system.AddAlert) ~= "function" then return false end
	local getter = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
	if not getter then return false end
	local okInfo, _, link = pcall(getter, 6948) -- Hearthstone: almost always cached
	if not okInfo or not link then return false end
	return (pcall(system.AddAlert, system, link, 1))
end

--------------------------------------------------------------------------------
-- Loot roll prompts (COMPAT_FINDINGS "Loot roll and alert frames")
--
-- GroupLootContainer is a managed frame: the bottom stack re-anchors it on
-- every relayout (measured 26 Nov 2026), so moving it does not stick, and we
-- never touch it or the stack. Instead (SPEC F-1.8) the roll prompts inside
-- it, GroupLootFrame1-4, are re-anchored to OUR frame each time Blizzard lays
-- them out (a post-hook on GroupLootContainer_Update), and whenever one shows.
-- Nothing anchors to the container, so this disturbs no other frame. The
-- container keeps its slot in the stack while a roll is up.
--
-- hooksecurefunc cannot be undone, so the hooks stay and check `rollAnchor`:
-- with none set they do nothing, and Blizzard's next layout wins.
--
-- Blizzard's loot roll code is present when this file loads (measured
-- 26 Nov 2026, `/dyruprobe lootframes timing`). As a guard against that
-- changing in a patch, presence is still checked
-- when asked, never cached as false, and an anchor set before the code
-- exists is kept and hooked up as soon as it appears (ADDON_LOADED or
-- PLAYER_ENTERING_WORLD).
--------------------------------------------------------------------------------

local ROLL_FRAME_COUNT = 4
local ROLL_SPACING = 4      -- Claude default between stacked prompts; Blizzard's is unmeasured
local ROLL_HEIGHT = 67      -- measured prompt height, used if GetHeight fails

local function rollApiPresent()
	return (type(_G.GroupLootContainer_Update) == "function"
		and type(_G.GroupLootContainer) == "table"
		and type(_G.GroupLootFrame1) == "table") and true or false
end

--- Whether an anchor can be accepted at all, now or once the loot code loads.
Compat.hasLootRollHook = type(_G.hooksecurefunc) == "function"

--- Whether Blizzard's roll prompts are there to follow an anchor right now.
-- Only ever turns true; a false answer is re-checked on the next call.
Compat.hasLootRollAnchor = Compat.hasLootRollHook and rollApiPresent()

function Compat.LootRollAnchorAvailable()
	if not Compat.hasLootRollAnchor and Compat.hasLootRollHook and rollApiPresent() then
		Compat.hasLootRollAnchor = true
	end
	return Compat.hasLootRollAnchor
end

local rollAnchor = nil
local rollHooked = false
local rollWaiter = nil

--- The shown roll prompts, in Blizzard's order where it exposes one.
local function shownRollFrames()
	local list, seen = {}, {}
	local ordered = _G.GroupLootContainer and _G.GroupLootContainer.rollFrames
	if type(ordered) == "table" then
		for i = 1, ROLL_FRAME_COUNT * 2 do
			local frame = ordered[i]
			if type(frame) == "table" and not seen[frame] then
				seen[frame] = true
				local ok, shown = pcall(frame.IsShown, frame)
				if ok and shown then list[#list + 1] = frame end
			end
		end
	end
	for i = 1, ROLL_FRAME_COUNT do
		local frame = _G["GroupLootFrame" .. i]
		if type(frame) == "table" and not seen[frame] then
			seen[frame] = true
			local ok, shown = pcall(frame.IsShown, frame)
			if ok and shown then list[#list + 1] = frame end
		end
	end
	return list
end

--- Stack the shown prompts upward from the bottom of our anchor.
local function placeRollFrames()
	local anchor = rollAnchor
	if not anchor then return end
	local offset = 0
	for _, frame in ipairs(shownRollFrames()) do
		pcall(frame.ClearAllPoints, frame)
		pcall(frame.SetPoint, frame, "BOTTOM", anchor, "BOTTOM", 0, offset)
		local ok, height = pcall(frame.GetHeight, frame)
		if not ok or type(height) ~= "number" or height <= 0 then height = ROLL_HEIGHT end
		offset = offset + height + ROLL_SPACING
	end
end

local function hookRolls()
	if rollHooked then return true end
	local ok = pcall(_G.hooksecurefunc, "GroupLootContainer_Update", function()
		if rollAnchor then ns.Errors:Safe("lootroll:update", placeRollFrames) end
	end)
	if not ok then return false end
	for i = 1, ROLL_FRAME_COUNT do
		local frame = _G["GroupLootFrame" .. i]
		if type(frame) == "table" and type(frame.HookScript) == "function" then
			pcall(frame.HookScript, frame, "OnShow", function()
				if rollAnchor then ns.Errors:Safe("lootroll:show", placeRollFrames) end
			end)
		end
	end
	rollHooked = true
	return true
end

--- Hook up as soon as Blizzard's loot roll code exists.
local function tryHookRolls()
	if rollHooked then return true end
	if not Compat.LootRollAnchorAvailable() or not hookRolls() then return false end
	if rollWaiter then rollWaiter:UnregisterAllEvents() end
	return true
end

local function waitForRolls()
	if rollWaiter then return end
	rollWaiter = CreateFrame("Frame")
	Compat.RegisterEvent(rollWaiter, "ADDON_LOADED")
	Compat.RegisterEvent(rollWaiter, "PLAYER_ENTERING_WORLD")
	rollWaiter:SetScript("OnEvent", function()
		if rollAnchor and not rollHooked and tryHookRolls() then
			ns.Errors:Safe("lootroll:wait", placeRollFrames)
		end
	end)
end

--- Make the roll prompts follow one of OUR frames. Applies at once to any
-- prompt already showing. If Blizzard's loot roll code hasn't loaded yet, the
-- anchor is kept and applied when it does.
-- @return boolean whether the anchor was accepted
function Compat.SetLootRollAnchor(frame)
	if not Compat.hasLootRollHook then return false end
	rollAnchor = frame
	if tryHookRolls() then placeRollFrames() else waitForRolls() end
	return true
end

--- Whether a set anchor is actually hooked up yet (for status display).
function Compat.IsLootRollAnchorActive()
	return rollAnchor ~= nil and rollHooked
end

--- Stop following. Prompts already showing stay put until Blizzard next lays
-- them out (the next roll added or removed); with none showing, which is the
-- usual case, the next roll appears in Blizzard's place.
function Compat.ResetLootRollAnchor()
	rollAnchor = nil
	return Compat.hasLootRollHook
end

--- Put one of OUR frames where the roll prompts appear by default: the roll
-- container's slot at the top of the bottom stack (measured: TOP of
-- BottomManagedFrameContainer). The stack's own position moves with what it
-- holds, so this is approximate.
function Compat.AnchorAtLootRollDefault(frame)
	frame:ClearAllPoints()
	local stack = _G.GroupLootContainer and _G.GroupLootContainer.layoutParent
		or _G.BottomManagedFrameContainer
	if type(stack) == "table" and pcall(frame.SetPoint, frame, "TOP", stack, "TOP", 0, 0) then
		return true
	end
	frame:SetPoint("BOTTOM", _G.UIParent, "BOTTOM", 0, 200)
	return false
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
		editModeCallbacks = Compat.hasEditModeCallbacks,
		alertBaseAnchor = Compat.hasAlertBaseAnchor,
		lootRollAnchor = Compat.LootRollAnchorAvailable(),
	}
end
