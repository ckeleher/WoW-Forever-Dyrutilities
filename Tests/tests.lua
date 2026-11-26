-- Tests/tests.lua
--
-- The regression suite. Loads the addon into a real Lua 5.1 interpreter against
-- Tests/wowstub.lua and drives it. See Tests/README.md.
--
-- There are no real features yet, so the modules here are FIXTURES, one per
-- shape the framework must handle: plain, reload-to-disable, reload-to-enable,
-- unavailable, and one whose OnEnable throws.

local root = REPO_ROOT

local function loadFile(path)
	local chunk, err = loadfile(root .. "/" .. path)
	if not chunk then error("could not load " .. path .. ": " .. tostring(err)) end
	return chunk
end

dofile(root .. "/Tests/wowstub.lua")

--------------------------------------------------------------------------------
-- Assertions
--------------------------------------------------------------------------------

local checks, failures = 0, 0
local currentSuite = "?"
local suites = {}

local function suite(name, fn) suites[#suites + 1] = { name = name, fn = fn } end

local function fail(message)
	failures = failures + 1
	print(string.format("  FAIL [%s] %s", currentSuite, message))
end

local function check(condition, message)
	checks = checks + 1
	if not condition then fail(message) end
	return condition
end

local function eq(actual, expected, message)
	checks = checks + 1
	if actual ~= expected then
		fail(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
		return false
	end
	return true
end

--------------------------------------------------------------------------------
-- Fixture modules
--------------------------------------------------------------------------------

local counts = {}
local function bump(key) counts[key] = (counts[key] or 0) + 1 end

local function registerFixtures(_, ns)
	ns:RegisterModule("alpha", {
		title = "Alpha",
		summary = "A plain live-toggle feature.",
		defaults = { size = 3, list = { 1, 2 } },
		OnInitialize = function() bump("alpha:init") end,
		OnEnable = function(self)
			bump("alpha:enable")
			self:RegisterEvent("BAG_UPDATE", function() bump("alpha:bag") end)
		end,
		OnDisable = function() bump("alpha:disable") end,
		BuildSettings = function(self, panel)
			bump("alpha:build")
			panel.box = ns.Widgets:Checkbox(panel, 20, function(checked) self:Set("flag", checked) end)
		end,
		OnSettingChanged = function(_, key, value) counts["alpha:changed"] = key .. "=" .. tostring(value) end,
	})

	ns:RegisterModule("hooky", {
		title = "Hooky",
		reloadToDisable = true,
		OnEnable = function() bump("hooky:enable") end,
		OnDisable = function() bump("hooky:disable") end,
	})

	ns:RegisterModule("latey", {
		title = "Latey",
		reloadToEnable = true,
		OnEnable = function() bump("latey:enable") end,
	})

	ns:RegisterModule("nope", {
		title = "Nope",
		Available = function() return false, "needs a thing this client lacks" end,
		OnEnable = function() bump("nope:enable") end,
	})

	ns:RegisterModule("broken", {
		title = "Broken",
		OnEnable = function() error("boom") end,
	})
end

--------------------------------------------------------------------------------
-- Load the addon in TOC order, fixtures where Modules\ files would go
--------------------------------------------------------------------------------

local CORE = { "Core/Compat.lua", "Core/Errors.lua", "Core/DB.lua", "Core/Module.lua", "Core/Widgets.lua" }
local UI = { "UI/MainWindow.lua", "UI/SettingsStub.lua", "Core/Core.lua" }

local function loadAddon(withFixtures)
	local ns = {}
	for _, path in ipairs(CORE) do loadFile(path)("Dyrutilities", ns) end
	if withFixtures then registerFixtures("Dyrutilities", ns) end
	for _, path in ipairs(UI) do loadFile(path)("Dyrutilities", ns) end
	return ns
end

local ns = loadAddon(true)
local M = ns.modules
local W = ns.MainWindow

--------------------------------------------------------------------------------
-- Suites
--------------------------------------------------------------------------------

suite("load and bootstrap", function()
	check(ns.Compat and ns.Errors and ns.DB and ns.Widgets and ns.MainWindow and ns.SettingsStub,
		"every namespace exists")
	eq(#ns.moduleOrder, 5, "fixtures registered in order")
	eq(ns.moduleOrder[1].name, "alpha", "registration order is menu order")
	check(_G.Dyrutilities == ns, "the namespace is published as a global")

	stub.fire("ADDON_LOADED", "SomeOtherAddon")
	check(ns.DB.db == nil, "another addon's ADDON_LOADED is ignored")

	stub.fire("ADDON_LOADED", "Dyrutilities")
	check(type(_G.DyrutilitiesCharDB) == "table", "the per-character table exists")
	eq(_G.DyrutilitiesCharDB.version, 1, "stamped with the schema version")
	eq(counts["alpha:init"], 1, "OnInitialize ran")
	for _, module in ipairs(ns.moduleOrder) do
		check(module.initialized, module.name .. " initialized")
	end
end)

suite("everything defaults to off", function()
	for _, module in ipairs(ns.moduleOrder) do
		eq(_G.DyrutilitiesCharDB.modules[module.name].enabled, false, module.name .. " saved off")
		check(not module:IsWanted(), module.name .. " not wanted")
	end

	stub.reset()
	stub.fire("PLAYER_LOGIN")
	for _, module in ipairs(ns.moduleOrder) do
		check(not module.running, module.name .. " not started at login")
	end
	eq(counts["alpha:enable"], nil, "no OnEnable ran")
end)

suite("defaults are filled and copied", function()
	local alpha = M.alpha
	eq(alpha.db.size, 3, "scalar default filled")
	check(type(alpha.db.list) == "table" and alpha.db.list[2] == 2, "table default filled")
	check(alpha.db.list ~= alpha.defaults.list, "a table default is copied, not aliased")
	check(_G.DyrutilitiesCharDB.modules.alpha.settings == alpha.db, "self.db is the saved settings table")
	eq(_G.DyrutilitiesCharDB.modules.alpha.settings.enabled, nil, "enabled is not mixed into settings")
end)

suite("first-run message and Options entry", function()
	stub.runTimers()
	check(stub.chatMatches("/dyru"), "the welcome line names the command")
	eq(_G.DyrutilitiesCharDB.firstRun, false, "and is not shown again for this character")
	eq(stub.countCalls("RegisterCanvasLayoutCategory"), 1, "Options page registered once")
	eq(stub.lastCall("RegisterCanvasLayoutCategory")[2], "Dyrutilities", "under our name")
	eq(stub.countCalls("RegisterAddOnCategory"), 1, "and added to the AddOns list")
	eq(ns.Compat.optionsRoute, "settings", "via the modern Settings API")
end)

suite("live toggle", function()
	stub.reset()
	local alpha = M.alpha
	check(alpha:SetWanted(true), "accepted")
	check(alpha.running, "running immediately")
	eq(counts["alpha:enable"], 1, "OnEnable once")
	eq(_G.DyrutilitiesCharDB.modules.alpha.enabled, true, "choice saved")
	eq(alpha:Status(), "on", "status on")

	stub.fire("BAG_UPDATE", 0)
	eq(counts["alpha:bag"], 1, "its event reaches it while running")

	alpha:SetWanted(false)
	check(not alpha.running, "stopped")
	eq(counts["alpha:disable"], 1, "OnDisable once")
	stub.fire("BAG_UPDATE", 0)
	eq(counts["alpha:bag"], 1, "its event no longer reaches it")
	eq(alpha:Status(), "off", "status off")
	check(not ns:AnyPendingReload(), "nothing pending")
end)

suite("reloadToDisable", function()
	local hooky = M.hooky
	hooky:SetWanted(true)
	check(hooky.running, "turning on is live")

	hooky:SetWanted(false)
	check(hooky.running, "turning off does NOT stop it")
	eq(counts["hooky:disable"], nil, "OnDisable not called")
	eq(_G.DyrutilitiesCharDB.modules.hooky.enabled, false, "but the choice is saved")
	eq(hooky:Status(), "pending-off", "status pending-off")
	check(ns:AnyPendingReload(), "a reload is pending")

	hooky:SetWanted(true)
	eq(hooky:Status(), "on", "flipping back clears the pending state")
	check(not ns:AnyPendingReload(), "nothing pending")
end)

suite("reloadToEnable", function()
	local latey = M.latey
	latey:SetWanted(true)
	check(not latey.running, "turning on does NOT start it")
	eq(latey:Status(), "pending-on", "status pending-on")
	check(ns:AnyPendingReload(), "a reload is pending")

	-- What the next login does.
	ns:StartWantedModules()
	check(latey.running, "a login starts it")
	eq(counts["latey:enable"], 1, "OnEnable once")
	check(not ns:AnyPendingReload(), "nothing pending after the reload")

	latey:SetWanted(false)
	check(not latey.running, "turning off is live")
end)

suite("unavailable modules are refused", function()
	local nope = M.nope
	stub.reset()
	check(not nope:SetWanted(true), "refused")
	eq(_G.DyrutilitiesCharDB.modules.nope.enabled, false, "choice not saved")
	eq(counts["nope:enable"], nil, "never started")
	local status, reason = nope:Status()
	eq(status, "unavailable", "status unavailable")
	eq(reason, "needs a thing this client lacks", "with the module's reason")
	check(stub.chatMatches("cannot run"), "and says so")
end)

suite("a module whose OnEnable throws", function()
	local broken = M.broken
	stub.reset()
	broken:SetWanted(true)
	check(not broken.running, "is not left half-started")
	eq(_G.DyrutilitiesCharDB.modules.broken.enabled, true, "the user's choice stands; next login retries")
	local status, reason = broken:Status()
	eq(status, "failed", "status failed")
	check(reason and reason:find("boom"), "with the error")
	check(stub.chatMatches("failed to start"), "and says so")
	broken:SetWanted(false)
end)

suite("settings writes", function()
	local alpha = M.alpha
	counts["alpha:changed"] = nil
	alpha:Set("size", 5)
	eq(alpha.db.size, 5, "written while off")
	eq(counts["alpha:changed"], nil, "OnSettingChanged not called while off")
	alpha:SetWanted(true)
	alpha:Set("size", 6)
	eq(counts["alpha:changed"], "size=6", "called while running")
	alpha:SetWanted(false)
end)

suite("per-character storage", function()
	local DB = ns.DB
	local realDB = _G.DyrutilitiesCharDB

	-- A new character: SavedVariablesPerCharacter starts empty.
	_G.DyrutilitiesCharDB = nil
	DB:Initialize()
	local entry = DB:Module("alpha", M.alpha.defaults)
	eq(entry.enabled, false, "a new character starts with everything off")
	eq(entry.settings.size, 3, "and the module's defaults, not another character's")

	-- Garbage on disk.
	_G.DyrutilitiesCharDB = "corrupt"
	DB:Initialize()
	check(type(_G.DyrutilitiesCharDB) == "table", "a non-table saved value is replaced")

	-- Written by a newer version.
	stub.reset()
	_G.DyrutilitiesCharDB = { version = 99 }
	DB:Initialize()
	check(stub.chatMatches("newer version"), "a newer file is warned about")
	eq(_G.DyrutilitiesCharDB.version, 99, "and its version stamp is left alone")

	_G.DyrutilitiesCharDB = realDB
	DB:Initialize()
end)

suite("circuit breaker", function()
	local Errors = ns.Errors
	stub.reset()
	for _ = 1, 7 do Errors:Safe("test:boom", function() error("x") end) end
	check(Errors:IsDisabled("test:boom"), "switched off after the threshold")
	local lines = 0
	for _, line in ipairs(stub.chat) do
		if line:find("switched off") then lines = lines + 1 end
	end
	eq(lines, 1, "said once, not per failure")

	Errors:Reset()
	check(not Errors:IsDisabled("test:boom"), "reset re-arms it")

	local ok, a, b, c = Errors:Safe("test:returns", function() return 1, nil, 3 end)
	check(ok and a == 1 and b == nil and c == 3, "returns survive, including a nil in the middle")
end)

suite("slash commands", function()
	local handler = SlashCmdList.DYRUTILITIES
	eq(SLASH_DYRUTILITIES1, "/dyru", "short command")
	eq(SLASH_DYRUTILITIES2, "/dyrutilities", "long command")

	handler("")
	check(W:IsShown(), "bare /dyru opens the menu")
	handler("   ")
	check(not W:IsShown(), "and closes it")

	stub.reset()
	handler("frobnicate")
	check(stub.chatMatches("Unknown command 'frobnicate'"), "an unknown word is reported")
	check(stub.chatMatches("Commands:"), "with help")
	check(not W:IsShown(), "and does NOT fall through to opening the menu")

	stub.reset()
	handler("HELP")
	check(stub.chatMatches("/dyru reset"), "help is case-insensitive")

	stub.reset()
	handler("compat")
	check(stub.chatMatches("tocVersion = 16001"), "compat reports the TOC version")

	local before = ns.DB.db.debug
	handler("debug")
	eq(ns.DB.db.debug, not before, "debug toggles")
	handler("debug")

	ns.Errors:Safe("test:once", function() error("y") end)
	stub.reset()
	handler("errors")
	check(stub.chatMatches("test:once"), "errors lists what failed")
	handler("errors reset")
	stub.reset()
	handler("errors")
	check(stub.chatMatches("No errors"), "errors reset clears them")
end)

suite("menu window: rows and checkboxes", function()
	W:Show()
	local frame = W.frame
	check(frame and frame:IsShown(), "shown")
	eq(frame.strata, "DIALOG", "above the game UI")
	check(frame.list.empty == nil, "no empty-state label when modules exist")

	local found = false
	for _, name in ipairs(UISpecialFrames) do
		if name == "DyrutilitiesMainWindow" then found = true end
	end
	check(found, "Escape closes it (UISpecialFrames)")

	-- Rows are found through the checkbox fixture's frame parentage.
	local rowsByName = {}
	for _, f in ipairs(stub.frames) do
		if f.module and f.check then rowsByName[f.module.name] = f end
	end
	eq(rowsByName.alpha and rowsByName.alpha.label:GetText(), "Alpha", "a row per module, titled")
	check(rowsByName.nope ~= nil and rowsByName.broken ~= nil, "every module has a row")

	local alphaRow = rowsByName.alpha
	check(not alphaRow.check:GetChecked(), "checkbox reflects off")
	alphaRow.check:Click()
	check(M.alpha.running, "clicking the checkbox turns the feature on")
	check(alphaRow.check:GetChecked(), "and the box stays checked")
	alphaRow.check:Click()
	check(not M.alpha.running, "clicking again turns it off")

	local nopeRow = rowsByName.nope
	check(not nopeRow.check:IsEnabled(), "an unavailable module's checkbox is disabled")
	nopeRow.check:Click()
	check(not M.nope:IsWanted(), "and cannot be clicked on")

	-- Selection
	rowsByName.hooky:Click()
	eq(ns.DB.db.window.selected, "hooky", "clicking a row selects it, remembered per character")
	eq(frame.detail.title:GetText(), "Hooky", "the detail pane follows")
	-- hooky was left on by the reloadToDisable suite.
	eq(frame.detail.status:GetText(), "On", "with its status")
	check(frame.detail.noSettings:IsShown(), "a module without settings says so")

	rowsByName.nope:Click()
	check(frame.detail.status:GetText():find("needs a thing"), "an unavailable module shows why")
end)

suite("menu window: settings panels", function()
	local frame = W.frame
	-- alpha is first, so it was selected (and built) when the window first opened.
	eq(counts["alpha:build"], 1, "BuildSettings ran when the module was first shown")
	W:Select("alpha")
	check(not frame.detail.noSettings:IsShown(), "and the no-settings label hides")
	W:Select("hooky")
	W:Select("alpha")
	eq(counts["alpha:build"], 1, "and only once")

	-- Its own controls write through Module:Set.
	local panel
	for _, f in ipairs(stub.frames) do
		if f.box and f.parent == frame.detail.host then panel = f end
	end
	check(panel ~= nil, "the panel is parented to the detail pane")
	panel.box:Click()
	eq(M.alpha.db.flag, true, "a settings checkbox writes the setting")
end)

suite("menu window: reload banner", function()
	local frame = W.frame
	W:Refresh()
	check(not frame.banner:IsShown(), "hidden when nothing is pending")

	M.latey:SetWanted(false)
	ns:StartWantedModules()   -- make sure latey is stopped and wanted off
	M.latey:SetWanted(true)
	check(frame.banner:IsShown(), "shown while a change is pending")
	W:Select("latey")
	eq(frame.detail.status:GetText(), "On after reload", "the status says when it applies")

	stub.reset()
	frame.banner.button:Click()
	eq(stub.countCalls("ReloadUI"), 1, "the button reloads")

	M.latey:SetWanted(false)
	check(not frame.banner:IsShown(), "and hides when the change is undone")
end)

suite("menu window: position", function()
	local frame = W.frame
	frame.cx, frame.cy = 620, 380
	frame.titleBar:Fire("OnDragStop")
	local point = ns.DB.db.window.point
	check(point and point[1] == "CENTER" and point[4] == 120 and point[5] == -20,
		"a drag saves the centre offset from UIParent")
	eq(frame.userPlaced, false, "and opts out of the client's own layout cache")

	SlashCmdList.DYRUTILITIES("reset")
	eq(ns.DB.db.window.point, nil, "/dyru reset forgets it")
	local last = frame.points[#frame.points]
	check(last and last[1] == "CENTER" and last[4] == 0, "and recentres the window")

	frame.closeButton:Click()
	check(not W:IsShown(), "the close button closes it")
end)

suite("addon compartment", function()
	check(type(Dyrutilities_OnAddonCompartmentClick) == "function", "the TOC-named global exists")
	Dyrutilities_OnAddonCompartmentClick("Dyrutilities", "LeftButton")
	check(W:IsShown(), "click opens the menu")
	Dyrutilities_OnAddonCompartmentClick("Dyrutilities", "LeftButton")
	check(not W:IsShown(), "click again closes it")

	GameTooltip.lines = nil
	Dyrutilities_OnAddonCompartmentEnter("Dyrutilities", "not a frame")
	eq(GameTooltip.lines, nil, "an unexpected argument shape shows nothing and does not error")
	local button = CreateFrame("Button")
	Dyrutilities_OnAddonCompartmentEnter("Dyrutilities", button)
	eq(GameTooltip.lines and GameTooltip.lines[1], "Dyrutilities", "a frame gets a tooltip")
	eq(GameTooltip.owner, button, "anchored to it")
	Dyrutilities_OnAddonCompartmentLeave()
end)

suite("Options page", function()
	local page = ns.SettingsStub.frame
	check(page ~= nil, "built at login")
	check(type(page.OnCommit) == "function" and type(page.OnRefresh) == "function", "canvas no-ops present")

	local openButton
	for _, f in ipairs(stub.frames) do
		if f.parent == page and f.text == "Open Dyrutilities" then openButton = f end
	end
	check(openButton ~= nil, "has an Open button")
	SettingsPanel:Show()
	stub.reset()
	openButton:Click()
	eq(stub.countCalls("HideUIPanel"), 1, "which closes the Options panel")
	check(W:IsShown(), "and opens the menu")
	W:Hide()

	-- The fallbacks, exercised through Compat directly.
	local Compat = ns.Compat
	local savedCanvas = Compat.hasSettingsCanvas
	Compat.hasSettingsCanvas = false
	Compat.hasLegacyInterfaceOptions = true
	_G.InterfaceOptions_AddCategory = function(f) stub.log("InterfaceOptions_AddCategory", f.name) end
	eq(Compat.RegisterOptionsPage(CreateFrame("Frame"), "X"), "legacy", "falls back to the legacy call")
	Compat.hasLegacyInterfaceOptions = false
	eq(Compat.RegisterOptionsPage(CreateFrame("Frame"), "X"), nil, "and to nothing, without erroring")
	Compat.hasSettingsCanvas = savedCanvas
	_G.InterfaceOptions_AddCategory = nil
end)

suite("template fallbacks", function()
	local Widgets = ns.Widgets
	stub.templates.UICheckButtonTemplate = nil
	stub.templates.UIPanelButtonTemplate = nil
	stub.templates.UIPanelCloseButton = nil

	local got
	local box = Widgets:Checkbox(UIParent, 20, function(checked) got = checked end)
	check(box ~= nil and box.normalTexture ~= nil, "a checkbox is hand-built without the template")
	box:Click()
	eq(got, true, "and still toggles")

	local button = Widgets:Button(UIParent, "Hi", 80, 20)
	check(button:GetFontString() ~= nil and button:GetFontString():GetText() == "Hi",
		"a button is hand-built with its own label")

	local close = Widgets:CloseButton(UIParent, function() end)
	check(close:GetFontString() ~= nil, "so is the close button")

	stub.templates.UICheckButtonTemplate = true
	stub.templates.UIPanelButtonTemplate = true
	stub.templates.UIPanelCloseButton = true
end)

suite("empty state", function()
	-- A second, independent copy of the addon with no modules at all, as v0.1
	-- actually ships.
	local savedDB = _G.DyrutilitiesCharDB
	_G.DyrutilitiesCharDB = nil
	local empty = loadAddon(false)
	stub.fire("ADDON_LOADED", "Dyrutilities")
	empty.MainWindow:Show()
	check(empty.MainWindow.frame.list.empty ~= nil, "the list says there are no features")
	check(empty.MainWindow.frame.detail.nothing:IsShown(), "the detail pane says so too")
	check(not empty.MainWindow.frame.banner:IsShown(), "no banner")
	empty.MainWindow:Hide()
	_G.DyrutilitiesCharDB = savedDB
end)

suite("probe", function()
	stub.reset()
	_G.DyrutilitiesProbeDB = nil
	loadFile("Probe/Dyrutilities_Probe/Probe.lua")("Dyrutilities_Probe")
	local probe = SlashCmdList.DYRUTILITIESPROBE
	check(probe ~= nil, "/dyruprobe registered")

	stub.reset()
	probe("nonsense")
	check(stub.chatMatches("Unknown probe"), "an unknown subcommand is reported")
	check(DyrutilitiesProbeDB.survey == nil, "and does NOT run the survey")

	probe("")
	local survey = DyrutilitiesProbeDB.survey
	check(survey ~= nil, "the survey runs and is saved")
	eq(survey.tocVersion, 16001, "with the TOC version")
	eq(survey.projects.WOW_PROJECT_CAMELOT, 18, "WOW_PROJECT_* globals are enumerated")
	check(stub.chatMatches("WOW_PROJECT_CAMELOT = 18%s+<%- this client"), "and the client's own is marked")
	check(not stub.chatMatches("TOC is not 16001"), "a numeric 16001 is not mistaken for a mismatch")
	eq(survey.templates.UICheckButtonTemplate, true, "templates are tested by building them")
	eq(survey.templates.PortraitFrameTemplate, false, "and a missing one reports false")
	eq(survey.optionsRoute, "settings", "verdict: options route")
	eq(survey.secretPlainNumber, false, "a plain number is recorded as not secret (not as an error)")
	eq(survey.secretPlayerHealth, false, "and so is player health out of combat, here")

	probe("settings")
	eq(DyrutilitiesProbeDB.settings.register, "ok", "settings probe registers a page")
	eq(stub.lastCall("OpenToCategory")[1], 42, "and opens it by id")

	probe("compartment")
	eq(DyrutilitiesProbeDB.compartment.tocFunc, "Dyrutilities_OnAddonCompartmentClick",
		"compartment probe reads the TOC function back")

	probe("globals ^Dyrutilities_On")
	eq(#DyrutilitiesProbeDB.globals.found, 3, "globals finds the three compartment functions")
	stub.reset()
	probe("globals [")
	check(stub.chatMatches("Not a valid Lua pattern"), "a bad pattern is reported, not thrown")

	probe("ns Settings")
	eq(#DyrutilitiesProbeDB.namespaces.Settings, 3, "ns lists a namespace's members")
end)

--------------------------------------------------------------------------------
-- Run
--------------------------------------------------------------------------------

for _, entry in ipairs(suites) do
	currentSuite = entry.name
	local ok, err = pcall(entry.fn)
	if not ok then
		failures = failures + 1
		print(string.format("  ERROR [%s] %s", entry.name, tostring(err)))
	end
end

print(string.format("%d suite(s), %d check(s), %d failure(s)", #suites, checks, failures))

RESULT_FAILURES = failures
