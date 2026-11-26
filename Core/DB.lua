-- Core/DB.lua
--
-- The saved variables. Per-character only (SPEC D-4); there is no account-wide
-- table until a module needs one (D-15).
--
--   DyrutilitiesCharDB = {
--       version  = 1,
--       debug    = false,
--       firstRun = true,
--       window   = { point = {...}, selected = "name" },
--       modules  = {
--           name = { enabled = false, settings = { ... } },
--       },
--   }
--
-- Defaults are filled in explicitly rather than through metatables. `enabled`
-- sits beside `settings`, never inside it, so no module setting can collide
-- with the framework's own key.

local ADDON, ns = ...

local DB = {}
ns.DB = DB

DB.SCHEMA_VERSION = 1

local function ensure(parent, key, default)
	if parent[key] == nil then parent[key] = default end
	return parent[key]
end

--- A default that is safe to hand out. Shallow copy for tables, so saved data
-- never aliases the module's defaults table.
local function copyDefault(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = v end
	return copy
end
DB.copyDefault = copyDefault

--- Bring the saved table up to the current shape. Idempotent.
function DB:Initialize()
	if type(_G.DyrutilitiesCharDB) ~= "table" then
		_G.DyrutilitiesCharDB = {}
	end
	local db = _G.DyrutilitiesCharDB

	ensure(db, "version", DB.SCHEMA_VERSION)
	ensure(db, "debug", false)
	ensure(db, "firstRun", true)
	ensure(db, "window", {})
	ensure(db, "modules", {})

	-- Written by a newer version, then downgraded. Say so once and leave the
	-- version stamp alone, so the newer code still recognises its own file.
	if type(db.version) == "number" and db.version > DB.SCHEMA_VERSION then
		ns.Errors:Print("|cffffcc00Saved settings were written by a newer version ("
			.. tostring(db.version) .. " > " .. DB.SCHEMA_VERSION
			.. ").|r Anything this version does not recognise is left alone.")
	else
		-- Future migrations go here, gated on db.version, BEFORE this stamp.
		db.version = DB.SCHEMA_VERSION
	end

	ns.Errors.debug = db.debug and true or false
	DB.db = db
	return db
end

--- The saved entry for one module: `{ enabled = bool, settings = table }`,
-- created on demand, with `defaults` filled into `settings`.
function DB:Module(name, defaults)
	local db = DB.db or DB:Initialize()
	local entry = ensure(db.modules, name, {})
	if type(entry.enabled) ~= "boolean" then entry.enabled = false end   -- SPEC §1: everything off
	local settings = ensure(entry, "settings", {})

	if defaults then
		for key, value in pairs(defaults) do
			if settings[key] == nil then
				settings[key] = copyDefault(value)
			end
		end
	end
	return entry
end
