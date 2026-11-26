-- Core/Core.lua
--
-- Bootstrap, slash commands and the addon-compartment entry. Loaded last, so
-- every module and UI file has registered by the time anything here runs.

local ADDON, ns = ...

local Compat = ns.Compat
local Errors = ns.Errors
local DB = ns.DB

ns.version = Compat.GetAddOnMetadata(ADDON, "Version") or "0.0.0"

_G.Dyrutilities = ns

--------------------------------------------------------------------------------
-- Bootstrap (SPEC §4.1)
--------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")

loader:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		self:UnregisterEvent("ADDON_LOADED")
		DB:Initialize()
		ns:InitializeModules()

	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		ns:StartWantedModules()
		Errors:Safe("SettingsStub", ns.SettingsStub.Register, ns.SettingsStub)

		if DB.db.firstRun then
			DB.db.firstRun = false
			C_Timer.After(4, function()
				Errors:Print(string.format(
					"v%s loaded. Every feature starts off; |cffffcc00/dyru|r opens the menu.", ns.version))
			end)
		end
	end
end)

--------------------------------------------------------------------------------
-- Addon compartment (named in the TOC; must be globals)
--
-- Registered, but Forever's minimap shows no compartment button (COMPAT_FINDINGS,
-- SPEC D-8), so nothing user-facing mentions it. Kept because it is free and
-- starts working if a patch or another addon ever shows the button.
--------------------------------------------------------------------------------

function _G.Dyrutilities_OnAddonCompartmentClick()
	ns.MainWindow:Toggle()
end

--- The second argument is assumed to be the menu button; unverified, so it is
-- only used if it looks like a frame.
function _G.Dyrutilities_OnAddonCompartmentEnter(_, button)
	if type(button) ~= "table" or type(button.GetObjectType) ~= "function" then return end
	ns.Widgets:ShowTooltip(button, { "Dyrutilities", "Click to open or close the menu." })
end

function _G.Dyrutilities_OnAddonCompartmentLeave()
	if _G.GameTooltip then GameTooltip:Hide() end
end

--------------------------------------------------------------------------------
-- Slash commands (SPEC §6.3)
--------------------------------------------------------------------------------

local function help()
	Errors:Print("Commands:")
	Errors:Print("  |cffffcc00/dyru|r - open or close the menu")
	Errors:Print("  |cffffcc00/dyru reset|r - move the menu back to the centre")
	Errors:Print("  |cffffcc00/dyru compat|r - what this client supports")
	Errors:Print("  |cffffcc00/dyru errors [reset]|r - errors recorded this session")
	Errors:Print("  |cffffcc00/dyru debug|r - verbose logging")
end

local function compatReport()
	Errors:Print("Client capabilities:")
	local info = Compat.Describe()
	local keys = {}
	for key in pairs(info) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do
		Errors:Print(string.format("  %s = %s", key, tostring(info[key])))
	end
end

local commands = {
	help = help,
	compat = compatReport,
	reset = function()
		ns.MainWindow:ResetPosition()
		Errors:Print("Menu moved back to the centre.")
	end,
	debug = function()
		DB.db.debug = not DB.db.debug
		Errors.debug = DB.db.debug
		Errors:Print(DB.db.debug and "Debug logging on." or "Debug logging off.")
	end,
	errors = function(rest)
		if rest:lower():match("^%s*reset") then
			Errors:Reset()
			Errors:Print("Error counts cleared. Anything that was switched off will be tried again.")
		else
			Errors:Report()
		end
	end,
}
ns.commands = commands

function ns:HandleSlash(input)
	local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()

	if cmd == "" then
		ns.MainWindow:Toggle()
		return
	end

	local handler = commands[cmd]
	if handler then
		Errors:Safe("slash:" .. cmd, handler, rest or "")
		return
	end

	-- Never fall through to a default action (SPEC §6.3).
	Errors:Print("|cffff5555Unknown command '" .. cmd .. "'.|r")
	help()
end

SLASH_DYRUTILITIES1 = "/dyru"
SLASH_DYRUTILITIES2 = "/dyrutilities"
SlashCmdList["DYRUTILITIES"] = function(input) ns:HandleSlash(input) end
