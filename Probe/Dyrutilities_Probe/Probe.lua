-- Dyrutilities_Probe
--
-- Every assumption Dyrutilities rests on, checked against the running WoW
-- Forever client. Results go into Documents/COMPAT_FINDINGS.md. On a patch day,
-- re-run it and diff the output against that file before trusting the addon.
--
-- It has no dependency on the addon, not even its Compat layer, because one
-- of the failures it diagnoses is "the addon no longer loads".
--
-- Usage:
--   /dyruprobe                 static survey: build, project IDs, API paths,
--                              events, templates, secret values. Saved to
--                              DyrutilitiesProbeDB.survey
--   /dyruprobe settings        register a throwaway Options canvas page and
--                              report each call, then try to open it
--   /dyruprobe compartment     is the addon compartment there, and is
--                              Dyrutilities registered in it?
--   /dyruprobe globals <pat>   every global whose name matches a Lua pattern,
--                              e.g. /dyruprobe globals ^C_Secret
--   /dyruprobe ns <Name>       every member of a namespace, e.g. C_AddOns
--   /dyruprobe lootframes      the loot roll and alert frames: names, anchors,
--                              parents, protection, layout-manager flags
--   /dyruprobe lootframes move moves them for 10 seconds, shows a test toast,
--                              reports whether Blizzard re-anchors them, then
--                              restores them. Out of combat only
--   /dyruprobe lootframes managed     the bottom managed stack: its children,
--                              their order and anchors, what anchors to the rolls
--   /dyruprobe lootframes simulate    show the empty roll container as a roll
--                              would; see where the stack puts it and whether a
--                              moved container survives a relayout. /reload after
--   /dyruprobe lootframes alertanchor point toasts at a frame of ours via
--                              AlertFrame:SetBaseAnchorFrame, preview, then reset
--   /dyruprobe lootframes watch       record where real roll frames appear on
--                              START_LOOT_ROLL, until /reload
--   /dyruprobe lootframes timing      when Blizzard's loot roll code appeared
--                              during this load (recorded on every load)
--   /dyruprobe editmode        what Edit Mode exposes: systems, C_EditMode,
--                              the manager frame's API, registered frames
--   /dyruprobe editmode watch  report Edit Mode enter/exit and show a draggable
--                              test box while it is open (hooks last until /reload)
--   /dyruprobe dump            re-print the last survey's verdicts
--
-- Adding a probe: a local function, a line in the dispatcher at the bottom, a
-- line in this header and in SPEC §8, and a row in COMPAT_FINDINGS.

DyrutilitiesProbeDB = DyrutilitiesProbeDB or {}

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

local function out(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffDyru probe|r " .. table.concat(parts, " "))
end

local function header(text)
	out("|cffffcc00== " .. text .. " ==|r")
end

local function yn(value)
	if value == nil then return "|cff808080nil|r" end
	if value then return "|cff40ff40yes|r" end
	return "|cffff5555no|r"
end

local function resolve(path)
	local current = _G
	for part in path:gmatch("[^%.]+") do
		if type(current) ~= "table" then return nil end
		current = current[part]
		if current == nil then return nil end
	end
	return current
end

local function exists(path)
	return resolve(path) ~= nil
end

--------------------------------------------------------------------------------
-- What the framework relies on
--------------------------------------------------------------------------------

local API_PATHS = {
	-- Core plumbing
	"C_Timer.After",
	"C_EventUtils.IsEventValid",
	"C_AddOns.GetAddOnMetadata",
	"C_AddOns.IsAddOnLoaded",
	"GetAddOnMetadata",
	"InCombatLockdown",
	"hooksecurefunc",
	"ReloadUI",
	"C_UI.Reload",
	"UISpecialFrames",
	"StaticPopup_Show",
	"StaticPopupDialogs",
	"GameTooltip",
	-- Options panel (UI/SettingsStub.lua)
	"Settings",
	"Settings.RegisterCanvasLayoutCategory",
	"Settings.RegisterVerticalLayoutCategory",
	"Settings.RegisterAddOnCategory",
	"Settings.OpenToCategory",
	"SettingsPanel",
	"HideUIPanel",
	"InterfaceOptions_AddCategory",
	"InterfaceOptionsFrame",
	-- Addon compartment
	"AddonCompartmentFrame",
	"AddonCompartmentFrame.RegisterAddon",
	-- Modern menus, for future settings widgets
	"MenuUtil",
	"MenuUtil.CreateContextMenu",
	-- Secret values (Midnight addon disarmament)
	"issecretvalue",
	"canaccessvalue",
	"issecrettable",
	"C_Secrets",
}

-- Templates are XML, not Lua globals, so the only honest test is to build a
-- frame with one. Each is built as the frame type it is meant for.
local TEMPLATES = {
	{ "Button", "UIPanelButtonTemplate" },
	{ "Button", "UIPanelCloseButton" },
	{ "CheckButton", "UICheckButtonTemplate" },
	{ "CheckButton", "InterfaceOptionsCheckButtonTemplate" },
	{ "Frame", "BackdropTemplate" },
	{ "Frame", "BasicFrameTemplateWithInset" },
	{ "Frame", "PortraitFrameTemplate" },
	{ "Frame", "ButtonFrameTemplate" },
	{ "ScrollFrame", "UIPanelScrollFrameTemplate" },
	{ "ScrollFrame", "ScrollFrameTemplate" },
	{ "Slider", "OptionsSliderTemplate" },
	{ "Slider", "MinimalSliderTemplate" },
	{ "EditBox", "InputBoxTemplate" },
	{ "Button", "SecureActionButtonTemplate" },
}

local EVENTS = {
	"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD",
	"PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
	"ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}

local eventProbeFrame = CreateFrame("Frame")

local function eventExists(event)
	if C_EventUtils and C_EventUtils.IsEventValid then
		local ok, valid = pcall(C_EventUtils.IsEventValid, event)
		if ok then return valid and true or false end
	end
	local ok = pcall(eventProbeFrame.RegisterEvent, eventProbeFrame, event)
	if ok then pcall(eventProbeFrame.UnregisterEvent, eventProbeFrame, event) end
	return ok and true or false
end

local function templateWorks(frameType, template)
	local ok, frame = pcall(CreateFrame, frameType, nil, UIParent, template)
	if ok and frame then
		pcall(frame.Hide, frame)
		return true
	end
	return false, (not ok) and tostring(frame) or nil
end

--------------------------------------------------------------------------------
-- Survey
--------------------------------------------------------------------------------

local function projectIds()
	local found = {}
	for key, value in pairs(_G) do
		if type(key) == "string" and key:find("^WOW_PROJECT_") then
			found[#found + 1] = { key = key, value = value }
		end
	end
	table.sort(found, function(a, b) return a.key < b.key end)
	return found
end

local function survey()
	local version, build, buildDate, tocVersion = GetBuildInfo()
	local record = {
		timestamp = date("%Y-%m-%d %H:%M:%S"),
		version = version, build = build, buildDate = buildDate, tocVersion = tocVersion,
		locale = GetLocale(),
		projects = {}, api = {}, events = {}, templates = {},
	}

	header("Build")
	out("version", version, "build", build, "date", buildDate, "toc", tocVersion, "locale", GetLocale())
	if tostring(tocVersion) ~= "16001" then
		out("|cffffcc00TOC is not 16001.|r Update ## Interface in both TOC files and SPEC §3.")
	end

	header("Project IDs")
	for _, entry in ipairs(projectIds()) do
		record.projects[entry.key] = entry.value
		local marker = (entry.value == WOW_PROJECT_ID and entry.key ~= "WOW_PROJECT_ID") and "  <- this client" or ""
		out(" ", entry.key, "=", tostring(entry.value), marker)
	end

	header("API")
	for _, path in ipairs(API_PATHS) do
		local value = resolve(path)
		record.api[path] = value ~= nil and type(value) or false
		out(" ", path, value ~= nil and ("|cff40ff40" .. type(value) .. "|r") or yn(false))
	end

	header("Events")
	for _, event in ipairs(EVENTS) do
		local present = eventExists(event)
		record.events[event] = present
		out(" ", event, yn(present))
	end

	header("Templates")
	for _, entry in ipairs(TEMPLATES) do
		local works, err = templateWorks(entry[1], entry[2])
		record.templates[entry[2]] = works
		out(" ", entry[2], "(" .. entry[1] .. ")", yn(works), err and ("|cff808080" .. err .. "|r") or "")
	end

	header("Secret values")
	if type(issecretvalue) == "function" then
		-- Not `ok and value or "error"`: that turns a legitimate false into "error".
		local okPlain, plain = pcall(issecretvalue, 1)
		if okPlain then record.secretPlainNumber = plain and true or false
		else record.secretPlainNumber = "error: " .. tostring(plain) end
		out("  issecretvalue(1) =", tostring(record.secretPlainNumber), "(expect false)")
		local okHealth, health = pcall(UnitHealth, "player")
		if okHealth then
			local okSecret, secret = pcall(issecretvalue, health)
			if okSecret then record.secretPlayerHealth = secret and true or false
			else record.secretPlayerHealth = "error: " .. tostring(secret) end
			out("  UnitHealth('player') secret, out of combat:", tostring(record.secretPlayerHealth))
		end
		out("  Re-run in combat to see what changes; secrecy is often combat-gated.")
	else
		record.secretPlainNumber = "absent"
		out("  issecretvalue absent. The secret-value system is not exposed under that name.")
		out("  Try |cffffcc00/dyruprobe globals [Ss]ecret|r.")
	end

	header("Verdicts")
	local canvas = exists("Settings.RegisterCanvasLayoutCategory") and exists("Settings.RegisterAddOnCategory")
	record.optionsRoute = canvas and "settings" or (exists("InterfaceOptions_AddCategory") and "legacy" or "none")
	out("Options page route:", record.optionsRoute, record.optionsRoute == "none"
		and "|cffff5555- no Options entry possible; window still works|r" or "")
	out("Addon compartment:", yn(exists("AddonCompartmentFrame")))
	out("Escape-to-close (UISpecialFrames):", yn(type(UISpecialFrames) == "table"))
	out("Native checkbox:", yn(record.templates.UICheckButtonTemplate),
		record.templates.UICheckButtonTemplate and "" or "- the hand-built fallback is in use")

	DyrutilitiesProbeDB.survey = record
	out("Saved to DyrutilitiesProbeDB.survey (written to disk on logout or /reload).")
	return record
end

--------------------------------------------------------------------------------
-- Options panel
--------------------------------------------------------------------------------

local probeCategory

local function settingsProbe()
	header("Options panel")
	local record = {}
	DyrutilitiesProbeDB.settings = record

	if not (Settings and Settings.RegisterCanvasLayoutCategory) then
		record.canvas = false
		out("Settings.RegisterCanvasLayoutCategory absent.")
		out("InterfaceOptions_AddCategory:", yn(type(InterfaceOptions_AddCategory) == "function"))
		return
	end

	if not probeCategory then
		local page = CreateFrame("Frame")
		page.OnCommit, page.OnDefault, page.OnRefresh = function() end, function() end, function() end
		local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		label:SetPoint("TOPLEFT", 16, -16)
		label:SetText("Dyrutilities probe page. If you can read this, canvas pages render.")

		local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, page, "Dyrutilities Probe")
		record.register = ok and "ok" or tostring(category)
		out("RegisterCanvasLayoutCategory:", ok and "|cff40ff40ok|r" or ("|cffff5555" .. tostring(category) .. "|r"))
		if not ok or not category then return end

		local added, err = pcall(Settings.RegisterAddOnCategory, category)
		record.addOnCategory = added and "ok" or tostring(err)
		out("RegisterAddOnCategory:", added and "|cff40ff40ok|r" or ("|cffff5555" .. tostring(err) .. "|r"))
		probeCategory = category
	else
		out("Probe page already registered this session.")
	end

	local id = probeCategory.GetID and probeCategory:GetID() or probeCategory.ID
	record.categoryId = tostring(id)
	out("category id:", tostring(id), "type", type(id))

	if Settings.OpenToCategory then
		local ok, err = pcall(Settings.OpenToCategory, id)
		record.open = ok and "ok" or tostring(err)
		out("OpenToCategory:", ok and "|cff40ff40called|r - did the panel open on the probe page?"
			or ("|cffff5555" .. tostring(err) .. "|r"))
	else
		out("Settings.OpenToCategory absent. Open Esc > Options > AddOns by hand.")
	end
	out("Also check: does |cffffcc00Dyrutilities|r appear in that list with an Open button?")
end

--------------------------------------------------------------------------------
-- Addon compartment
--------------------------------------------------------------------------------

local function compartmentProbe()
	header("Addon compartment")
	local record = {}
	DyrutilitiesProbeDB.compartment = record

	local frame = AddonCompartmentFrame
	record.frame = frame ~= nil
	out("AddonCompartmentFrame:", yn(frame ~= nil), frame and type(frame) or "")

	local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	if getMeta then
		local ok, func = pcall(getMeta, "Dyrutilities", "AddonCompartmentFunc")
		record.tocFunc = ok and tostring(func) or "error"
		out("TOC AddonCompartmentFunc read back:", tostring(record.tocFunc))
		out("Global of that name exists:", yn(ok and func and type(_G[func]) == "function"))
	end

	if type(frame) ~= "table" then return end

	-- Field names inside the compartment are not documented, so look for any
	-- list whose entries mention us, rather than assume one.
	local hits = {}
	for key, value in pairs(frame) do
		if type(value) == "table" then
			for _, entry in pairs(value) do
				if type(entry) == "table" then
					local text = entry.text or entry.addonName or entry.name
					if type(text) == "string" and text:find("Dyrutilities") then
						hits[#hits + 1] = tostring(key)
					end
				end
			end
		end
	end
	record.registeredIn = hits
	if #hits > 0 then
		out("Dyrutilities found in field(s):", table.concat(hits, ", "), "|cff40ff40- registered|r")
	else
		out("|cffffcc00Not found in any field.|r Is Dyrutilities enabled? Check the minimap addon list by eye.")
	end
end

--------------------------------------------------------------------------------
-- Discovery
--------------------------------------------------------------------------------

local MAX_LINES = 150

local function globalsProbe(pattern)
	if pattern == "" then
		out("Usage: /dyruprobe globals <lua pattern>, e.g. ^C_Secret or [Ss]ecret")
		return
	end
	local okPattern = pcall(string.find, "", pattern)
	if not okPattern then
		out("|cffff5555Not a valid Lua pattern:|r", pattern)
		return
	end

	local found = {}
	for key, value in pairs(_G) do
		if type(key) == "string" and key:find(pattern) then
			found[#found + 1] = key .. " (" .. type(value) .. ")"
		end
	end
	table.sort(found)
	header("Globals matching " .. pattern .. ": " .. #found)
	for i = 1, math.min(#found, MAX_LINES) do out(" ", found[i]) end
	if #found > MAX_LINES then out("...", #found - MAX_LINES, "more; all saved to DyrutilitiesProbeDB.globals") end
	DyrutilitiesProbeDB.globals = { pattern = pattern, found = found }
end

local function namespaceProbe(path)
	if path == "" then
		out("Usage: /dyruprobe ns <Namespace>, e.g. C_AddOns or Settings")
		return
	end
	local target = resolve(path)
	if type(target) ~= "table" then
		out(path, "is", target == nil and "|cffff5555absent|r" or ("a " .. type(target) .. ", not a table"))
		return
	end
	local found = {}
	for key, value in pairs(target) do
		found[#found + 1] = tostring(key) .. " (" .. type(value) .. ")"
	end
	table.sort(found)
	header(path .. ": " .. #found .. " member(s)")
	for i = 1, math.min(#found, MAX_LINES) do out(" ", found[i]) end
	if #found > MAX_LINES then out("...", #found - MAX_LINES, "more; all saved to DyrutilitiesProbeDB.namespaces") end
	DyrutilitiesProbeDB.namespaces = DyrutilitiesProbeDB.namespaces or {}
	DyrutilitiesProbeDB.namespaces[path] = found
end

--------------------------------------------------------------------------------
-- Frame inspection helpers
--
-- Forever has a FrameStrata secret aspect (1.60.1 notes), and other frame
-- reads may be secret too, so every value is checked before it is printed.
--------------------------------------------------------------------------------

local function isSecret(value)
	if type(issecretvalue) ~= "function" then return false end
	local ok, secret = pcall(issecretvalue, value)
	return ok and secret and true or false
end

local function frameName(frame)
	if frame == nil then return "nil" end
	if type(frame) ~= "table" then return tostring(frame) end
	if type(frame.GetName) == "function" then
		local ok, name = pcall(frame.GetName, frame)
		if ok and name and not isSecret(name) then return name end
	end
	return "<anonymous " .. tostring(frame) .. ">"
end

local function show(value)
	if isSecret(value) then return "|cffff5555<secret>|r" end
	if type(value) == "table" then return frameName(value) end
	if type(value) == "number" then return string.format("%.1f", value) end
	return tostring(value)
end

--- Call a method on a frame, returning its first two results as display
-- strings, or the reason it could not be called.
local function ask(frame, method, ...)
	local fn = frame[method]
	if type(fn) ~= "function" then return "|cff808080(no " .. method .. ")|r" end
	local ok, a, b = pcall(fn, frame, ...)
	if not ok then return "|cffff5555error: " .. tostring(a) .. "|r" end
	if b ~= nil then return show(a) .. ", " .. show(b) end
	return show(a)
end

local function readPoints(frame)
	local points = {}
	if type(frame.GetNumPoints) ~= "function" then return points end
	local okN, n = pcall(frame.GetNumPoints, frame)
	if not okN or type(n) ~= "number" or isSecret(n) then return points end
	for i = 1, n do
		local ok, point, relativeTo, relativePoint, x, y = pcall(frame.GetPoint, frame, i)
		if ok then
			points[#points + 1] = { point, relativeTo, relativePoint, x, y }
		end
	end
	return points
end

local function pointsText(points)
	if #points == 0 then return "(no points)" end
	local parts = {}
	for _, p in ipairs(points) do
		parts[#parts + 1] = string.format("%s -> %s:%s (%s, %s)",
			show(p[1]), show(p[2]), show(p[3]), show(p[4]), show(p[5]))
	end
	return table.concat(parts, " | ")
end

local function restorePoints(frame, points)
	pcall(frame.ClearAllPoints, frame)
	for _, p in ipairs(points) do
		pcall(frame.SetPoint, frame, p[1], p[2], p[3], p[4], p[5])
	end
end

local function describeFrame(name)
	local frame = _G[name]
	if frame == nil then
		out(" ", name, "|cffff5555absent|r")
		return { exists = false }
	end
	if type(frame) ~= "table" or type(frame.GetObjectType) ~= "function" then
		out(" ", name, "is a", type(frame), "but not a frame")
		return { exists = true, frame = false }
	end

	local points = readPoints(frame)
	local record = {
		exists = true,
		objectType = ask(frame, "GetObjectType"),
		protected = ask(frame, "IsProtected"),
		forbidden = ask(frame, "IsForbidden"),
		parent = ask(frame, "GetParent"),
		shown = ask(frame, "IsShown"),
		size = ask(frame, "GetSize"),
		scale = ask(frame, "GetScale"),
		strata = ask(frame, "GetFrameStrata"),
		movable = ask(frame, "IsMovable"),
		points = pointsText(points),
		-- Plain fields Blizzard's layout code uses to decide who positions a frame.
		ignoreFramePositionManager = show(frame.ignoreFramePositionManager),
		isManagedFrame = show(frame.isManagedFrame),
		layoutParent = show(frame.layoutParent),
		layoutIndex = show(frame.layoutIndex),
		systemId = show(frame.system),
	}
	out("|cffffcc00" .. name .. "|r", record.objectType, "protected:", record.protected,
		"parent:", record.parent, "shown:", record.shown)
	out("    points:", record.points)
	out("    size:", record.size, "scale:", record.scale, "strata:", record.strata, "movable:", record.movable)
	out("    managed:", record.isManagedFrame, "ignoreFPM:", record.ignoreFramePositionManager,
		"layoutParent:", record.layoutParent, "edit-mode system:", record.systemId)
	return record
end

local function functionMembers(target, pattern)
	local found = {}
	if type(target) ~= "table" then return found end
	for key, value in pairs(target) do
		if type(key) == "string" and type(value) == "function" and (not pattern or key:find(pattern)) then
			found[#found + 1] = key
		end
	end
	table.sort(found)
	return found
end

local function globalNames(pattern)
	local found = {}
	for key in pairs(_G) do
		if type(key) == "string" and key:find(pattern) then found[#found + 1] = key end
	end
	table.sort(found)
	return found
end

--------------------------------------------------------------------------------
-- Blocked actions: if moving a Blizzard frame taints something, the client
-- reports it here. Recorded only for this addon and the probe.
--------------------------------------------------------------------------------

local blocked = {}
local blockedFrame = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
	if eventExists(event) then blockedFrame:RegisterEvent(event) end
end
blockedFrame:SetScript("OnEvent", function(_, event, addon, func)
	if type(addon) == "string" and addon:find("^Dyrutilities") then
		local entry = date("%H:%M:%S") .. " " .. event .. " " .. addon .. " " .. tostring(func)
		blocked[#blocked + 1] = entry
		DyrutilitiesProbeDB.blocked = blocked
		out("|cffff5555BLOCKED|r", entry)
	end
end)

--------------------------------------------------------------------------------
-- Load timing: when does Blizzard's loot roll code exist? Recorded on every
-- load, silently. The probe loads right after Dyrutilities (alphabetical), so
-- "at probe load" is what Dyrutilities' own files see.
--------------------------------------------------------------------------------

local function lootRollApiState()
	return string.format("Update:%s Container:%s Frame1:%s",
		type(_G.GroupLootContainer_Update) == "function" and "yes" or "no",
		type(_G.GroupLootContainer) == "table" and "yes" or "no",
		type(_G.GroupLootFrame1) == "table" and "yes" or "no")
end

local loadTiming = { atProbeLoad = lootRollApiState(), events = {} }
local timingFrame = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" }) do
	if eventExists(event) then timingFrame:RegisterEvent(event) end
end
timingFrame:SetScript("OnEvent", function(_, event, addon)
	if #loadTiming.events < 60 then
		loadTiming.events[#loadTiming.events + 1] = event
			.. (type(addon) == "string" and (" " .. addon) or "") .. ": " .. lootRollApiState()
	end
	-- Our saved table replaces the file-load one at our own ADDON_LOADED.
	if type(DyrutilitiesProbeDB) == "table" then DyrutilitiesProbeDB.loadTiming = loadTiming end
	if event == "PLAYER_ENTERING_WORLD" then timingFrame:UnregisterAllEvents() end
end)

local function timingProbe()
	header("Loot roll code load timing (this session)")
	out("  at Dyrutilities' load:", loadTiming.atProbeLoad)
	for _, line in ipairs(loadTiming.events) do out("   ", line) end
	out("  now:", lootRollApiState())
	DyrutilitiesProbeDB.loadTiming = loadTiming
end

--------------------------------------------------------------------------------
-- Loot frames (SPEC §11, F-1)
--------------------------------------------------------------------------------

local LOOT_FRAMES = {
	"GroupLootContainer",
	"GroupLootFrame1", "GroupLootFrame2", "GroupLootFrame3", "GroupLootFrame4",
	"AlertFrame",
	"BonusRollFrame",
	"LootFrame",
}

-- What a move is tested against: the two anchors F-1 would move.
local MOVE_TARGETS = {
	{ name = "GroupLootContainer", x = 0, y = 150 },
	{ name = "AlertFrame", x = 0, y = -150 },
}

local function itemLink(itemID)
	local getter = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not getter then return nil end
	local ok, _, link = pcall(getter, itemID)
	return ok and link or nil
end

--- Show a "you won" toast, so the player can see where alerts appear.
local function previewLootAlert()
	local system = LootAlertSystem
	if type(system) ~= "table" or type(system.AddAlert) ~= "function" then
		out("  preview: LootAlertSystem:AddAlert absent; no preview")
		return "absent"
	end
	local link = itemLink(6948) -- Hearthstone: almost always in the item cache
	if not link then
		out("  preview: Hearthstone link not cached yet; run it again in a moment")
		return "uncached"
	end
	local ok, err = pcall(system.AddAlert, system, link, 1)
	out("  preview: LootAlertSystem:AddAlert", ok and "|cff40ff40called|r - do you see a Hearthstone toast?"
		or ("|cffff5555" .. tostring(err) .. "|r"))
	return ok and "ok" or tostring(err)
end

local moveInProgress = false

local function lootMoveTest(record)
	if moveInProgress then
		out("A move test is already running.")
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		out("|cffffcc00In combat.|r Run the move test out of combat.")
		return
	end
	moveInProgress = true
	record.move = {}

	header("Move test (restores in 10s)")
	local originals = {}
	for _, target in ipairs(MOVE_TARGETS) do
		local frame = _G[target.name]
		local result = {}
		record.move[target.name] = result
		if type(frame) == "table" and type(frame.SetPoint) == "function" then
			originals[target.name] = readPoints(frame)
			pcall(frame.ClearAllPoints, frame)
			local ok, err = pcall(frame.SetPoint, frame, "CENTER", UIParent, "CENTER", target.x, target.y)
			result.set = ok and "ok" or tostring(err)
			result.immediately = pointsText(readPoints(frame))
			out(" ", target.name, "SetPoint:", ok and "|cff40ff40ok|r" or ("|cffff5555" .. tostring(err) .. "|r"),
				"now:", result.immediately)
		else
			result.set = "absent"
			out(" ", target.name, "absent; skipped")
		end
	end

	record.move.preview = previewLootAlert()

	local function check(label, key)
		for _, target in ipairs(MOVE_TARGETS) do
			local frame = _G[target.name]
			if originals[target.name] then
				local now = readPoints(frame)
				local p = now[1]
				-- pcall: comparing a secret value throws.
				local okCmp, held = pcall(function()
					return p and p[1] == "CENTER" and p[2] == UIParent and p[4] == target.x and p[5] == target.y
				end)
				held = okCmp and held and true or false
				record.move[target.name][key] = held and "held" or pointsText(now)
				out(" ", label, target.name, held and "|cff40ff40held|r"
					or ("|cffffcc00RE-ANCHORED|r to " .. pointsText(now)))
			end
		end
	end

	C_Timer.After(1, function() check("after 1s:", "after1s") end)
	C_Timer.After(3, function()
		-- Ask Blizzard's own layout code to run, as it would on many UI events.
		if type(UIParent_ManageFramePositions) == "function" then
			local ok = pcall(UIParent_ManageFramePositions)
			out("  called UIParent_ManageFramePositions:", ok and "ok" or "error")
		end
		if type(AlertFrame) == "table" and type(AlertFrame.UpdateAnchors) == "function" then
			local ok = pcall(AlertFrame.UpdateAnchors, AlertFrame)
			out("  called AlertFrame:UpdateAnchors:", ok and "ok" or "error")
		end
		check("after relayout:", "afterRelayout")
	end)
	C_Timer.After(10, function()
		for name, points in pairs(originals) do restorePoints(_G[name], points) end
		moveInProgress = false
		out("Move test over; frames restored to", "their original anchors.",
			#blocked > 0 and "|cffff5555Blocked actions were recorded: see above.|r" or "No blocked actions.")
	end)
end

--- Frames among UIParent's children (and `extra`) with a point relative to `target`.
local function framesAnchoredTo(target, extra)
	local found = {}
	local candidates = {}
	local ok, children = pcall(function() return { UIParent:GetChildren() } end)
	if ok then for _, child in ipairs(children) do candidates[#candidates + 1] = child end end
	for _, frame in ipairs(extra or {}) do candidates[#candidates + 1] = frame end
	for _, frame in ipairs(candidates) do
		if frame ~= target then
			for _, p in ipairs(readPoints(frame)) do
				if p[2] == target then
					found[#found + 1] = frameName(frame) .. " (" .. show(p[1]) .. " to its " .. show(p[3]) .. ")"
					break
				end
			end
		end
	end
	return found
end

local function managedContainer()
	local fromLoot = type(GroupLootContainer) == "table" and GroupLootContainer.layoutParent
	return fromLoot or _G.BottomManagedFrameContainer or _G.UIParentBottomManagedFrameContainer
end

--- Frames the managed container keeps in its own tables (field names unknown).
local function managedChildren(container)
	local frames, fields = {}, {}
	for key, value in pairs(container) do
		if type(value) == "table" and type(value.GetObjectType) ~= "function" then
			local count = 0
			for k, v in pairs(value) do
				local frame = (type(k) == "table" and type(k.GetObjectType) == "function" and k)
					or (type(v) == "table" and type(v.GetObjectType) == "function" and v) or nil
				if frame and not frames[frame] then
					frames[frame] = true
					count = count + 1
				end
			end
			if count > 0 then fields[#fields + 1] = tostring(key) .. "(" .. count .. ")" end
		end
	end
	local list = {}
	for frame in pairs(frames) do list[#list + 1] = frame end
	table.sort(list, function(a, b)
		local ia, ib = tonumber(a.layoutIndex) or 999, tonumber(b.layoutIndex) or 999
		if ia ~= ib then return ia < ib end
		return frameName(a) < frameName(b)
	end)
	return list, fields
end

local function managedProbe(record)
	header("Bottom managed stack")
	local container = managedContainer()
	record.managed = {}
	if type(container) ~= "table" then
		out("|cffff5555No managed container found.|r")
		return
	end
	record.managed.name = frameName(container)
	record.managed.points = pointsText(readPoints(container))
	record.managed.methods = functionMembers(container)
	out("container:", record.managed.name, "at", record.managed.points)
	out("  methods:", table.concat(record.managed.methods, ", "))

	local children, fields = managedChildren(container)
	record.managed.fields = fields
	out("  frame tables:", #fields > 0 and table.concat(fields, ", ") or "none found")
	record.managed.children = {}
	for _, frame in ipairs(children) do
		local line = string.format("#%s %s shown:%s at %s", show(frame.layoutIndex), frameName(frame),
			ask(frame, "IsShown"), pointsText(readPoints(frame)))
		record.managed.children[#record.managed.children + 1] = line
		out("   ", line)
	end
	record.managed.anchoredToLoot = framesAnchoredTo(GroupLootContainer, children)
	out("  anchored to GroupLootContainer now:", #record.managed.anchoredToLoot > 0
		and table.concat(record.managed.anchoredToLoot, ", ") or "nothing")
end

--- Show the roll container empty, as a roll would, and watch the stack lay it out.
local function simulateProbe(record)
	if moveInProgress then out("A test is already running.") return end
	if InCombatLockdown and InCombatLockdown() then out("|cffffcc00In combat.|r Run it out of combat.") return end
	local frame = GroupLootContainer
	local container = managedContainer()
	if type(frame) ~= "table" then out("GroupLootContainer absent.") return end
	moveInProgress = true
	record.simulate = {}
	local sim = record.simulate
	local _, children = pcall(managedChildren, container or {})

	header("Simulated roll (about 3s)")
	local okH, originalHeight = pcall(frame.GetHeight, frame)
	pcall(frame.SetHeight, frame, 67)
	local okShow, errShow = pcall(frame.Show, frame)
	sim.show = okShow and "ok" or tostring(errShow)
	out("  container shown at height 67:", sim.show)

	C_Timer.After(0.3, function()
		sim.laidOutAt = pointsText(readPoints(frame))
		sim.anchoredToIt = framesAnchoredTo(frame, type(children) == "table" and children or nil)
		out("  the stack put it at:", sim.laidOutAt)
		out("  anchored to it while shown:", #sim.anchoredToIt > 0
			and ("|cffffcc00" .. table.concat(sim.anchoredToIt, ", ") .. "|r") or "|cff40ff40nothing|r")

		-- Now move it while shown, and ask the stack to lay out again.
		pcall(frame.ClearAllPoints, frame)
		pcall(frame.SetPoint, frame, "CENTER", UIParent, "CENTER", 0, 150)
		if type(container) == "table" and type(container.Layout) == "function" then
			sim.layoutCall = (pcall(container.Layout, container)) and "ok" or "error"
		else
			sim.layoutCall = "no Layout method"
		end
		out("  moved it, then called the stack's Layout:", sim.layoutCall)

		C_Timer.After(0.3, function()
			local p = readPoints(frame)[1]
			local okCmp, held = pcall(function() return p and p[1] == "CENTER" and p[5] == 150 end)
			sim.afterLayout = (okCmp and held) and "held" or pointsText(readPoints(frame))
			out("  after Layout:", sim.afterLayout == "held" and "|cff40ff40held|r"
				or ("|cffffcc00RE-ANCHORED|r to " .. sim.afterLayout))

			C_Timer.After(1, function()
				pcall(frame.Hide, frame)
				if okH then pcall(frame.SetHeight, frame, originalHeight) end
				pcall(frame.ClearAllPoints, frame)
				if type(container) == "table" and type(container.Layout) == "function" then
					pcall(container.Layout, container)
				end
				moveInProgress = false
				out("Simulation over; container hidden again.",
					"|cffffcc00/reload|r before your next real roll, to clear any taint from this test.")
			end)
		end)
	end)
end

--- Point AlertFrame's base anchor at a frame of ours, preview, then reset.
local function alertAnchorProbe(record)
	if moveInProgress then out("A test is already running.") return end
	record.alertAnchor = {}
	local result = record.alertAnchor
	if type(AlertFrame) ~= "table" or type(AlertFrame.SetBaseAnchorFrame) ~= "function" then
		result.available = false
		out("AlertFrame:SetBaseAnchorFrame |cffff5555absent|r.")
		return
	end
	moveInProgress = true
	header("Alert base anchor (about 12s)")
	local anchor = _G.DyrutilitiesProbeAlertAnchor or CreateFrame("Frame", "DyrutilitiesProbeAlertAnchor", UIParent)
	anchor:SetSize(40, 40)
	anchor:ClearAllPoints()
	anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 250)
	if not anchor.marker then
		anchor.marker = anchor:CreateTexture(nil, "OVERLAY")
		anchor.marker:SetAllPoints(anchor)
		anchor.marker:SetColorTexture(1, 0.2, 0.2, 0.6)
	end
	anchor:Show()

	local ok, err = pcall(AlertFrame.SetBaseAnchorFrame, AlertFrame, anchor)
	result.set = ok and "ok" or tostring(err)
	out("  SetBaseAnchorFrame(red square, high on screen):", ok and "|cff40ff40ok|r" or ("|cffff5555" .. tostring(err) .. "|r"))
	result.preview = previewLootAlert()
	out("  |cffffcc00Look:|r the toast should appear next to the red square.")

	C_Timer.After(6, function()
		local okReset, errReset = pcall(AlertFrame.ResetBaseAnchorFrame, AlertFrame)
		result.reset = okReset and "ok" or tostring(errReset)
		anchor:Hide()
		out("  ResetBaseAnchorFrame:", okReset and "|cff40ff40ok|r" or ("|cffff5555" .. tostring(errReset) .. "|r"))
		C_Timer.After(1, function()
			result.previewAfterReset = previewLootAlert()
			out("  |cffffcc00Look:|r this second toast should be back in the usual place.")
			moveInProgress = false
		end)
	end)
end

local watchingRolls = false

--- Record where the roll frames really end up when a group loot roll starts.
local function rollWatchProbe(record)
	if watchingRolls then out("Already watching for loot rolls.") return end
	if not eventExists("START_LOOT_ROLL") then
		out("START_LOOT_ROLL |cffff5555is not an event|r on this client.")
		return
	end
	watchingRolls = true
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("START_LOOT_ROLL")
	watcher:SetScript("OnEvent", function()
		C_Timer.After(0.3, function()
			local entry = { time = date("%H:%M:%S") }
			entry.container = pointsText(readPoints(GroupLootContainer))
			entry.containerShown = ask(GroupLootContainer, "IsShown")
			entry.frames = {}
			for i = 1, 4 do
				local f = _G["GroupLootFrame" .. i]
				if f and f:IsShown() then
					entry.frames[#entry.frames + 1] = "GroupLootFrame" .. i .. " at " .. pointsText(readPoints(f))
				end
			end
			entry.anchoredToContainer = framesAnchoredTo(GroupLootContainer)
			record.rolls = record.rolls or {}
			record.rolls[#record.rolls + 1] = entry
			out("|cffffcc00Loot roll seen.|r container:", entry.container)
			for _, line in ipairs(entry.frames) do out("   ", line) end
			out("   anchored to container:", #entry.anchoredToContainer > 0
				and table.concat(entry.anchoredToContainer, ", ") or "nothing")
		end)
	end)
	out("Watching for group loot rolls until /reload. Results are saved; /reload afterwards to write them.")
end

local LOOT_USAGE = "Usage: /dyruprobe lootframes [move | managed | simulate | alertanchor | watch | timing]"

local function lootFramesProbe(arg)
	local sub = ((arg or ""):match("^(%S*)") or ""):lower()
	-- One record across subcommands, so a later survey never erases watched rolls.
	DyrutilitiesProbeDB.lootframes = DyrutilitiesProbeDB.lootframes or {}
	local record = DyrutilitiesProbeDB.lootframes

	if sub == "managed" then managedProbe(record) return end
	if sub == "simulate" then simulateProbe(record) return end
	if sub == "alertanchor" then alertAnchorProbe(record) return end
	if sub == "watch" then rollWatchProbe(record) return end
	if sub == "timing" then timingProbe() return end
	if sub ~= "" and sub ~= "move" then
		out("|cffff5555Unknown lootframes probe '" .. sub .. "'.|r")
		out(LOOT_USAGE)
		return
	end

	header("Loot frames")
	record.frames = {}
	for _, name in ipairs(LOOT_FRAMES) do
		record.frames[name] = describeFrame(name)
	end

	header("Related globals")
	record.globals = {}
	for _, pattern in ipairs({ "^GroupLoot", "LootWon", "AlertSystem$", "^AlertFrame" }) do
		local names = globalNames(pattern)
		record.globals[pattern] = names
		out(" ", pattern, "->", #names > 0 and table.concat(names, ", ") or "|cff808080none|r")
	end

	record.alertFrameMethods = functionMembers(AlertFrame, "[Aa]nchor")
	out("  AlertFrame anchor methods:", #record.alertFrameMethods > 0
		and table.concat(record.alertFrameMethods, ", ") or "none")
	record.manageFramePositions = type(UIParent_ManageFramePositions) == "function"
	out("  UIParent_ManageFramePositions:", yn(record.manageFramePositions))

	if sub == "move" then
		lootMoveTest(record)
	else
		out(LOOT_USAGE)
	end
end

--------------------------------------------------------------------------------
-- Edit Mode (SPEC §11, F-1.3)
--------------------------------------------------------------------------------

local editModeWatching = false
local editModeOverlay

local function buildOverlay()
	if editModeOverlay then return editModeOverlay end
	-- A stand-in for a draggable handle, to see whether our own frame can sit
	-- on top of Edit Mode and be dragged while it is open.
	local f = CreateFrame("Frame", "DyrutilitiesProbeEditModeOverlay", UIParent)
	f:SetSize(220, 60)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		out("overlay dragged to", pointsText(readPoints(self)))
	end)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(f)
	bg:SetColorTexture(0.1, 0.5, 1, 0.45)
	local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("CENTER")
	label:SetText("Dyrutilities probe\ndrag me")
	f:Hide()
	editModeOverlay = f
	return f
end

local function onEditMode(source, entering)
	local record = DyrutilitiesProbeDB.editmode or {}
	DyrutilitiesProbeDB.editmode = record
	record.seen = record.seen or {}
	record.seen[source .. (entering and ":enter" or ":exit")] = true
	out("Edit Mode", entering and "|cff40ff40ENTER|r" or "|cffffcc00EXIT|r", "via", source)
	local overlay = buildOverlay()
	if entering then overlay:Show() else overlay:Hide() end
end

local function editModeWatch()
	if editModeWatching then
		out("Already watching. Open and close Edit Mode (Esc > Edit Mode).")
		return
	end
	editModeWatching = true
	local hooked = {}

	if type(EventRegistry) == "table" and type(EventRegistry.RegisterCallback) == "function" then
		local okEnter = pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Enter",
			function() onEditMode("EventRegistry", true) end, "DyrutilitiesProbe")
		local okExit = pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit",
			function() onEditMode("EventRegistry", false) end, "DyrutilitiesProbe")
		hooked[#hooked + 1] = "EventRegistry EditMode.Enter/Exit: " .. tostring(okEnter and okExit)
	else
		hooked[#hooked + 1] = "EventRegistry: absent"
	end

	local manager = EditModeManagerFrame
	if type(manager) == "table" then
		for _, method in ipairs({ "EnterEditMode", "ExitEditMode" }) do
			if type(manager[method]) == "function" then
				hooksecurefunc(manager, method, function() onEditMode(method, method == "EnterEditMode") end)
				hooked[#hooked + 1] = "hooked EditModeManagerFrame:" .. method
			end
		end
		if type(manager.HookScript) == "function" then
			manager:HookScript("OnShow", function() onEditMode("OnShow", true) end)
			manager:HookScript("OnHide", function() onEditMode("OnHide", false) end)
			hooked[#hooked + 1] = "hooked EditModeManagerFrame OnShow/OnHide"
		end
	end

	for _, line in ipairs(hooked) do out(" ", line) end
	out("Now open Edit Mode (Esc > Edit Mode) and close it again. Each route that")
	out("fires is reported. While it is open a blue test box should appear: try dragging it.")
	out("|cffffcc00/reload|r afterwards: the hooks cannot be removed.")
end

local function editModeProbe(arg)
	local sub = ((arg or ""):match("^(%S*)") or ""):lower()
	if sub ~= "" and sub ~= "watch" then
		out("|cffff5555Unknown editmode probe '" .. sub .. "'.|r Usage: /dyruprobe editmode [watch]")
		return
	end
	header("Edit Mode")
	local record = DyrutilitiesProbeDB.editmode or {}
	DyrutilitiesProbeDB.editmode = record

	local manager = EditModeManagerFrame
	record.manager = manager ~= nil
	out("EditModeManagerFrame:", yn(manager ~= nil), manager and ("protected: " .. ask(manager, "IsProtected")) or "")
	record.eventRegistry = type(EventRegistry) == "table" and type(EventRegistry.RegisterCallback) == "function"
	out("EventRegistry:RegisterCallback:", yn(record.eventRegistry))

	record.systems = {}
	local systems = Enum and Enum.EditModeSystem
	if type(systems) == "table" then
		local names = {}
		for key, value in pairs(systems) do names[#names + 1] = tostring(key) .. "=" .. tostring(value) end
		table.sort(names)
		record.systems = names
		out("Enum.EditModeSystem (" .. #names .. "):", table.concat(names, ", "))
		local hits = {}
		for _, entry in ipairs(names) do
			if entry:find("[Ll]oot") or entry:find("[Aa]lert") then hits[#hits + 1] = entry end
		end
		record.lootSystems = hits
		out("  loot/alert systems:", #hits > 0 and ("|cff40ff40" .. table.concat(hits, ", ") .. "|r")
			or "|cffffcc00none|r - Edit Mode has no native loot or alert system")
	else
		out("Enum.EditModeSystem: |cffff5555absent|r")
	end

	record.cEditMode = functionMembers(C_EditMode)
	out("C_EditMode:", #record.cEditMode > 0 and table.concat(record.cEditMode, ", ") or "absent or empty")

	if type(manager) == "table" then
		record.managerMethods = functionMembers(manager, "[Rr]egister")
		for _, m in ipairs(functionMembers(manager, "[Ss]ystem")) do record.managerMethods[#record.managerMethods + 1] = m end
		out("Manager register/system methods:", #record.managerMethods > 0
			and table.concat(record.managerMethods, ", ") or "none")

		local registered = {}
		if type(manager.registeredSystemFrames) == "table" then
			for _, frame in pairs(manager.registeredSystemFrames) do
				registered[#registered + 1] = frameName(frame)
			end
			table.sort(registered)
		end
		record.registered = registered
		out("Registered system frames (" .. #registered .. "):", table.concat(registered, ", "))
		record.accountSettings = type(manager.AccountSettings) == "table"
		out("AccountSettings panel (the 'show' checkboxes):", yn(record.accountSettings))
	end

	if sub == "watch" then
		editModeWatch()
	else
		out("Next: |cffffcc00/dyruprobe editmode watch|r, then open and close Edit Mode.")
	end
end

local function dump()
	local record = DyrutilitiesProbeDB.survey
	if not record then
		out("No survey stored. Run |cffffcc00/dyruprobe|r first.")
		return
	end
	out("Survey from", record.timestamp, "version", record.version, "build", record.build, "toc", record.tocVersion)
	out("Options route:", tostring(record.optionsRoute), " secret(1):", tostring(record.secretPlainNumber))
end

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

local function usage()
	out("Usage: |cffffcc00/dyruprobe|r [survey | settings | compartment | globals <pattern> | ns <Name> | "
		.. "lootframes [move] | editmode [watch] | dump]")
end

SLASH_DYRUTILITIESPROBE1 = "/dyruprobe"

SlashCmdList["DYRUTILITIESPROBE"] = function(input)
	local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	rest = rest or ""

	if cmd == "" or cmd == "survey" then
		survey()
	elseif cmd == "settings" then
		settingsProbe()
	elseif cmd == "compartment" then
		compartmentProbe()
	elseif cmd == "globals" then
		globalsProbe(rest)
	elseif cmd == "ns" then
		namespaceProbe(rest)
	elseif cmd == "lootframes" then
		lootFramesProbe(rest)
	elseif cmd == "editmode" then
		editModeProbe(rest)
	elseif cmd == "dump" then
		dump()
	else
		-- Never run a default probe for an unrecognised word: on DyrueWoWTools
		-- that once made a missing subcommand look exactly like a success.
		out("|cffff5555Unknown probe '" .. cmd .. "'.|r /reload if it was added since you logged in.")
		usage()
	end
end

DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffDyru probe|r loaded. |cffffcc00/dyruprobe|r runs the survey.")
