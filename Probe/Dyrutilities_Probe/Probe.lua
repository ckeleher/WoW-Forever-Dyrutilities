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
	out("Usage: |cffffcc00/dyruprobe|r [survey | settings | compartment | globals <pattern> | ns <Name> | dump]")
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
