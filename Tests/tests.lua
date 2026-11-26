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

suite("probe: loot frames", function()
	local probe = SlashCmdList.DYRUTILITIESPROBE
	stub.reset()
	probe("lootframes")
	local record = DyrutilitiesProbeDB.lootframes
	check(record.frames.GroupLootContainer.exists, "GroupLootContainer described")
	check(record.frames.GroupLootContainer.points:find("BOTTOM %-> UIParent:BOTTOM"), "with its anchor")
	eq(record.frames.BonusRollFrame.exists, false, "an absent frame is reported absent, not an error")
	eq(record.move, nil, "without 'move', nothing is moved")

	-- Move test where nothing fights back.
	stub.layoutReanchors = false
	probe("lootframes move")
	local move = DyrutilitiesProbeDB.lootframes.move
	eq(move.GroupLootContainer.set, "ok", "SetPoint is attempted")
	eq(move.preview, "ok", "a preview toast is raised")
	eq(stub.lastCall("LootAlertSystem:AddAlert")[1], "|Hitem:6948|h[Hearthstone]|h", "with a real item link")
	stub.runTimers()
	eq(move.GroupLootContainer.after1s, "held", "an unchallenged move is reported as held")
	eq(move.AlertFrame.afterRelayout, "held", "including after a relayout")
	local p = { GroupLootContainer:GetPoint(1) }
	check(p[1] == "BOTTOM" and p[5] == 152, "and the frame is restored afterwards")

	-- Move test where Blizzard's layout code puts it back.
	stub.layoutReanchors = true
	probe("lootframes move")
	move = DyrutilitiesProbeDB.lootframes.move
	stub.runTimers()
	check(move.GroupLootContainer.afterRelayout ~= "held", "a re-anchor by the layout code is detected")
	check(stub.chatMatches("RE%-ANCHORED"), "and reported")
	stub.layoutReanchors = false

	-- Refuses in combat.
	stub.inCombat = true
	stub.reset()
	probe("lootframes move")
	check(stub.chatMatches("In combat"), "the move test refuses in combat")
	stub.inCombat = false
end)

suite("probe: managed stack, simulation, alert anchor, roll watch", function()
	local probe = SlashCmdList.DYRUTILITIESPROBE
	local record = DyrutilitiesProbeDB.lootframes

	stub.reset()
	probe("lootframes frobnicate")
	check(stub.chatMatches("Unknown lootframes probe"), "an unknown lootframes subcommand is reported")
	check(not stub.chatMatches("== Loot frames =="), "and does not run the survey")

	-- Something anchored to the roll container must be noticed.
	local leaner = CreateFrame("Frame", "LeansOnLoot", UIParent)
	leaner:SetPoint("BOTTOM", GroupLootContainer, "TOP", 0, 4)
	BottomManagedFrameContainer.showingFrames[leaner] = true
	leaner.layoutIndex = 4

	probe("lootframes managed")
	eq(record.managed.name, "BottomManagedFrameContainer", "the stack is found through layoutParent")
	check(record.managed.children[1]:find("#3.0 GroupLootContainer"), "its children are listed in layout order")
	check(record.managed.anchoredToLoot[1] and record.managed.anchoredToLoot[1]:find("LeansOnLoot"),
		"a frame anchored to the roll container is found")
	BottomManagedFrameContainer.showingFrames[leaner] = nil
	leaner:ClearAllPoints()

	stub.layoutReanchors = false
	probe("lootframes simulate")
	stub.runTimers()
	eq(record.simulate.show, "ok", "simulate shows the container")
	eq(record.simulate.afterLayout, "held", "a move that the stack leaves alone is reported held")
	check(not GroupLootContainer:IsShown(), "and the container is hidden again afterwards")

	stub.layoutReanchors = true
	GroupLootContainer:ClearAllPoints()
	probe("lootframes simulate")
	stub.runTimers()
	check(record.simulate.afterLayout:find("BottomManagedFrameContainer:TOP"),
		"a stack that re-anchors it is caught, naming where it went")
	stub.layoutReanchors = false

	stub.reset()
	probe("lootframes alertanchor")
	eq(record.alertAnchor.set, "ok", "SetBaseAnchorFrame is called")
	check(AlertFrame.baseAnchor == DyrutilitiesProbeAlertAnchor, "with our anchor frame")
	stub.runTimers()
	eq(record.alertAnchor.reset, "ok", "and ResetBaseAnchorFrame afterwards")
	eq(AlertFrame.baseAnchor, nil, "leaving AlertFrame as it was")
	eq(stub.countCalls("LootAlertSystem:AddAlert"), 2, "with a preview before and after")

	probe("lootframes watch")
	GroupLootContainer:Show()
	GroupLootFrame1:SetPoint("BOTTOM", GroupLootContainer, "BOTTOM", 0, 0)
	GroupLootFrame1:Show()
	stub.fire("START_LOOT_ROLL", 7, 60)
	stub.runTimers()
	eq(#record.rolls, 1, "a real roll is recorded")
	check(record.rolls[1].frames[1]:find("GroupLootFrame1 at BOTTOM %-> GroupLootContainer"),
		"with where its frame was put")
	GroupLootFrame1:Hide()
	GroupLootContainer:Hide()

	probe("lootframes")
	eq(#record.rolls, 1, "re-running the survey keeps the recorded rolls")
end)

suite("probe: edit mode and blocked actions", function()
	local probe = SlashCmdList.DYRUTILITIESPROBE
	stub.reset()
	probe("editmode")
	local record = DyrutilitiesProbeDB.editmode
	eq(#record.systems, 3, "Edit Mode systems listed")
	eq(#record.lootSystems, 0, "no native loot system found in this stub")
	check(stub.chatMatches("no native loot or alert system"), "and that is said plainly")
	eq(record.registered[1], "MinimapCluster", "registered system frames listed by name")
	check(record.accountSettings, "AccountSettings panel detected")

	probe("editmode watch")
	EventRegistry:TriggerEvent("EditMode.Enter")
	check(record.seen["EventRegistry:enter"], "EventRegistry enter is seen")
	check(DyrutilitiesProbeDB.editmode.seen and _G.DyrutilitiesProbeEditModeOverlay:IsShown(),
		"the test overlay shows while Edit Mode is open")
	EditModeManagerFrame:ExitEditMode()
	check(DyrutilitiesProbeDB.editmode.seen["ExitEditMode:exit"], "the ExitEditMode hook is seen")
	check(not DyrutilitiesProbeEditModeOverlay:IsShown(), "and the overlay hides")

	stub.reset()
	stub.fire("ADDON_ACTION_BLOCKED", "SomeoneElse", "CastSpell()")
	check(not stub.chatMatches("BLOCKED"), "other addons' blocked actions are ignored")
	stub.fire("ADDON_ACTION_BLOCKED", "Dyrutilities", "Frame:SetPoint()")
	check(stub.chatMatches("BLOCKED.*Dyrutilities"), "ours are reported")
end)

suite("module: loot frame positions", function()
	-- A separate copy of the addon carrying the real module, as the TOC loads it.
	local savedDB = _G.DyrutilitiesCharDB
	_G.DyrutilitiesCharDB = nil
	stub.reset()
	AlertFrame.baseAnchor = nil
	EditModeManagerFrame:Hide()

	local real = {}
	for _, path in ipairs(CORE) do loadFile(path)("Dyrutilities", real) end
	loadFile("Modules/LootFramePositions/LootFramePositions.lua")("Dyrutilities", real)
	for _, path in ipairs(UI) do loadFile(path)("Dyrutilities", real) end
	stub.fire("ADDON_LOADED", "Dyrutilities")

	local mod = real.modules.lootframepositions
	check(mod ~= nil, "the module registers under its key")
	eq(mod:IsWanted(), false, "and defaults to off")
	eq(mod.db.showAlertHandle, false, "the Alerts handle defaults to hidden")
	eq(mod.db.showRollHandle, false, "the Loot Rolls handle defaults to hidden")
	eq(mod.db.alertPoint, nil, "no saved toast position")
	check((mod:IsAvailable()), "available: Edit Mode callbacks and the alert anchor exist")

	check(mod:SetWanted(true), "turning it on is accepted")
	check(mod:IsRunning(), "and starts it live, no reload")
	eq(AlertFrame.baseAnchor, nil, "with no saved position, toasts are left alone")
	local alert, roll = mod.kinds.alert, mod.kinds.roll
	check(not mod.panel:IsShown(), "the panel is hidden outside Edit Mode")

	EditModeManagerFrame:EnterEditMode()
	EventRegistry:TriggerEvent("EditMode.Enter")
	check(mod.panel:IsShown(), "the panel shows when Edit Mode opens")
	eq(mod.panel:GetFrameStrata(), "FULLSCREEN_DIALOG", "above Edit Mode")
	check(not alert.handle:IsShown(), "no handle until its box is ticked")
	local rollBox, alertBox = mod.panel.boxes.roll, mod.panel.boxes.alert
	check(real.Compat.hasLootRollAnchor, "the roll anchor is available where GroupLootContainer_Update exists")
	eq(rollBox:IsEnabled(), true, "so Loot Rolls can be ticked")

	alertBox:Click()
	eq(mod.db.showAlertHandle, true, "ticking Alerts is saved")
	check(alert.handle:IsShown(), "and shows its handle")
	rollBox:Click()
	check(roll.handle:IsShown(), "ticking Loot Rolls shows its handle")

	-- A roll before the prompts are moved: Blizzard's layout is left alone.
	GroupLootFrame1:Show()
	GroupLootContainer_Update(GroupLootContainer)
	eq(select(2, GroupLootFrame1:GetPoint()), GroupLootContainer, "unmoved, prompts stay in Blizzard's container")

	-- Drag the Loot Rolls handle: a showing prompt follows at once.
	roll.anchor.cx, roll.anchor.cy = UIParent.cx - 300, UIParent.cy + 10
	roll.handle:Fire("OnDragStop")
	check(mod.db.rollPoint and mod.db.rollPoint[4] == -300, "the roll position is saved")
	eq(select(2, GroupLootFrame1:GetPoint()), roll.anchor, "a showing prompt moves to our anchor")
	-- Blizzard lays the prompts out again with a second roll: ours wins, stacked.
	GroupLootFrame2:Show()
	GroupLootContainer_Update(GroupLootContainer)
	eq(select(2, GroupLootFrame1:GetPoint()), roll.anchor, "after Blizzard's relayout the first prompt is ours")
	eq(select(2, GroupLootFrame2:GetPoint()), roll.anchor, "and so is the second")
	eq(select(5, GroupLootFrame2:GetPoint()), 71, "stacked above the first (67 + 4)")
	check(not GroupLootContainer.points[1] or GroupLootContainer.points[1][2] ~= roll.anchor,
		"the container itself is never moved")
	GroupLootFrame3:Hide(); GroupLootFrame3:Fire("OnShow")
	check(true, "an OnShow with nothing new is harmless")

	-- Drag the Alerts handle.
	alert.handle:Fire("OnDragStart")
	eq(stub.countCalls("StartMoving"), 1, "dragging moves our anchor")
	alert.anchor.cx, alert.anchor.cy = UIParent.cx + 120, UIParent.cy - 40
	alert.handle:Fire("OnDragStop")
	local point = mod.db.alertPoint
	check(point and point[4] == 120 and point[5] == -40, "the drop is saved as a centre offset")
	check(AlertFrame.baseAnchor == alert.anchor, "and toasts now follow our anchor")

	EventRegistry:TriggerEvent("EditMode.Exit")
	check(not mod.panel:IsShown(), "the panel hides when Edit Mode closes")
	check(not alert.handle:IsShown(), "and so does the handle")

	-- Turning it off undoes the toast change at once; on again re-applies it.
	mod:SetWanted(false)
	eq(AlertFrame.baseAnchor, nil, "turning it off resets the toast anchor")
	GroupLootContainer_Update(GroupLootContainer)
	eq(select(2, GroupLootFrame1:GetPoint()), GroupLootContainer, "and the prompts go back to Blizzard's layout")
	EventRegistry:TriggerEvent("EditMode.Enter")
	check(not mod.panel:IsShown(), "a stopped module ignores Edit Mode")
	EventRegistry:TriggerEvent("EditMode.Exit")
	mod:SetWanted(true)
	check(AlertFrame.baseAnchor == alert.anchor, "turning it on again re-applies the saved position")
	eq(select(2, GroupLootFrame1:GetPoint()), roll.anchor, "for the prompts too")
	eq(#(stub.callbacks["EditMode.Enter"] or {}) >= 1, true, "Edit Mode is hooked")
	local hooks = #stub.callbacks["EditMode.Enter"]
	mod:SetWanted(false); mod:SetWanted(true)
	eq(#stub.callbacks["EditMode.Enter"], hooks, "and hooked only once across toggles")

	-- Settings pane and reset.
	local panel = CreateFrame("Frame", nil, UIParent)
	mod:BuildSettings(panel)
	check(mod.statusLabels.alert:GetText():find("moved"), "settings show the toasts as moved")
	check(mod.statusLabels.roll:GetText():find("moved"), "and the roll prompts as moved")
	mod.resetButton:Click()
	eq(mod.db.alertPoint, nil, "Reset positions forgets the toast position")
	eq(mod.db.rollPoint, nil, "and the roll position")
	GroupLootContainer_Update(GroupLootContainer)
	eq(select(2, GroupLootFrame1:GetPoint()), GroupLootContainer, "Blizzard's next layout of the prompts stands")
	GroupLootFrame1:Hide(); GroupLootFrame2:Hide()
	eq(AlertFrame.baseAnchor, nil, "and gives toasts back to Blizzard")
	check(mod.statusLabels.alert:GetText():find("default"), "and the settings say so")

	mod:SetWanted(false)
	EditModeManagerFrame:Hide()
	_G.DyrutilitiesCharDB = savedDB
end)

suite("module: loot frame positions, Blizzard's loot code loading late", function()
	-- Not the case on Forever today (measured), but guarded against: the loot code arriving after us.
	local savedDB = _G.DyrutilitiesCharDB
	local update, container, frame1 = GroupLootContainer_Update, GroupLootContainer, GroupLootFrame1
	_G.GroupLootContainer_Update, _G.GroupLootContainer, _G.GroupLootFrame1 = nil, nil, nil
	_G.DyrutilitiesCharDB = { version = 1, modules = { lootframepositions = { enabled = true,
		settings = { rollPoint = { "CENTER", "UIParent", "CENTER", -200, 0 } } } } }
	stub.reset()
	EditModeManagerFrame:Hide()

	local late = {}
	for _, path in ipairs(CORE) do loadFile(path)("Dyrutilities", late) end
	loadFile("Modules/LootFramePositions/LootFramePositions.lua")("Dyrutilities", late)
	for _, path in ipairs(UI) do loadFile(path)("Dyrutilities", late) end
	stub.fire("ADDON_LOADED", "Dyrutilities")
	eq(late.Compat.hasLootRollAnchor, false, "absent at load is seen as absent")
	late:StartWantedModules()
	local mod = late.modules.lootframepositions
	check(mod:IsRunning(), "the module still starts")

	EditModeManagerFrame:EnterEditMode()
	EventRegistry:TriggerEvent("EditMode.Enter")
	eq(mod.panel.boxes.roll:IsEnabled(), false, "Loot Rolls is unavailable while the code is missing")
	EventRegistry:TriggerEvent("EditMode.Exit")
	EditModeManagerFrame:Hide()

	-- Blizzard's loot code arrives.
	_G.GroupLootContainer_Update, _G.GroupLootContainer, _G.GroupLootFrame1 = update, container, frame1
	EditModeManagerFrame:EnterEditMode()
	EventRegistry:TriggerEvent("EditMode.Enter")
	eq(mod.panel.boxes.roll:IsEnabled(), true, "once it exists, Loot Rolls is offered without a reload")
	EventRegistry:TriggerEvent("EditMode.Exit")
	EditModeManagerFrame:Hide()

	stub.fire("ADDON_LOADED", "Blizzard_SomethingLoot")
	GroupLootFrame1:Show()
	GroupLootContainer_Update(GroupLootContainer)
	eq(select(2, GroupLootFrame1:GetPoint()), mod.kinds.roll.anchor,
		"the position saved earlier is hooked up when the code appears")

	mod:SetWanted(false)
	GroupLootFrame1:Hide()
	_G.DyrutilitiesCharDB = savedDB
end)

suite("probe: load timing", function()
	local probe = SlashCmdList.DYRUTILITIESPROBE
	stub.reset()
	probe("lootframes timing")
	local timing = DyrutilitiesProbeDB.loadTiming
	check(timing and timing.atProbeLoad:find("Update:yes"), "presence at load is recorded")
	check(#timing.events > 0 and timing.events[1]:find("ADDON_LOADED"), "and each load event after it")
	check(stub.chatMatches("load timing"), "and printed")
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
