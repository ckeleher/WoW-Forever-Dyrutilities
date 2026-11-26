-- Core/Module.lua
--
-- The submodule registry. The contract is SPEC §5; read that first.
--
-- Each module has two booleans:
--   wanted  -- what the user chose; saved as entry.enabled; default false
--   running -- OnEnable has run without a matching OnDisable; never saved
-- They differ only while a change is waiting for a reload (reloadToEnable /
-- reloadToDisable), and the menu shows a Reload banner while any module is in
-- that state.

local ADDON, ns = ...

local Errors = ns.Errors
local Compat = ns.Compat
local DB = ns.DB

ns.modules = {}       -- name -> module
ns.moduleOrder = {}   -- registration order, which is TOC order, which is menu order

local Module = {}
Module.__index = Module
ns.ModulePrototype = Module

--------------------------------------------------------------------------------
-- State-change notification (the menu listens)
--------------------------------------------------------------------------------

local listeners = {}

function ns:OnModuleStateChanged(key, fn)
	listeners[key] = fn
end

local function notify(module)
	for key, fn in pairs(listeners) do
		Errors:Safe("listener:" .. key, fn, module)
	end
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

function ns:RegisterModule(name, def)
	assert(type(name) == "string" and name ~= "", "module name must be a non-empty string")
	assert(name:match("^[%w_]+$"), "module name must be alphanumeric: " .. name)
	assert(ns.modules[name] == nil, "module already registered: " .. name)

	local module = setmetatable(def or {}, Module)
	module.name = name
	module.title = module.title or name
	module.running = false
	module.initialized = false
	module._handlers = {}
	module._scheduled = {}

	ns.modules[name] = module
	ns.moduleOrder[#ns.moduleOrder + 1] = module
	return module
end

--------------------------------------------------------------------------------
-- Per-module services
--------------------------------------------------------------------------------

function Module:Print(...)
	Errors:Print("|cffffcc00" .. self.title .. ":|r", ...)
end

function Module:Debug(...)
	Errors:Debug("[" .. self.name .. "]", ...)
end

function Module:Safe(what, fn, ...)
	return Errors:Safe(self.name .. ":" .. what, fn, ...)
end

--- Handle `event` while this module is running.
function Module:RegisterEvent(event, handler)
	self._handlers[event] = handler or self[event]
	if self.running then self:_bindEvents() end
end

function Module:UnregisterEvent(event)
	self._handlers[event] = nil
	if self._eventFrame then pcall(self._eventFrame.UnregisterEvent, self._eventFrame, event) end
end

function Module:_frame()
	if not self._eventFrame then
		local frame = CreateFrame("Frame")
		frame:SetScript("OnEvent", function(_, event, ...)
			local handler = self._handlers[event]
			if handler then self:Safe(event, handler, self, event, ...) end
		end)
		self._eventFrame = frame
	end
	return self._eventFrame
end

function Module:_bindEvents()
	local frame = self:_frame()
	frame:UnregisterAllEvents()
	for event in pairs(self._handlers) do
		if not Compat.RegisterEvent(frame, event) then
			self:Debug("event not available on this client:", event)
		end
	end
end

function Module:_unbindEvents()
	if self._eventFrame then self._eventFrame:UnregisterAllEvents() end
end

--- Run `fn` once after `delay`, coalescing repeat requests under `key`.
-- Dropped if the module stops running before it fires.
function Module:Schedule(key, delay, fn)
	if self._scheduled[key] then return end
	self._scheduled[key] = true
	C_Timer.After(delay, function()
		self._scheduled[key] = nil
		if self.running then self:Safe(key, fn, self) end
	end)
end

--- Write a setting. Fires OnSettingChanged only while running (SPEC D-14:
-- settings stay editable while a feature is off, and apply when it starts).
function Module:Set(key, value)
	self.db[key] = value
	if self.running and self.OnSettingChanged then
		self:Safe("OnSettingChanged", self.OnSettingChanged, self, key, value)
	end
end

function Module:Get(key)
	return self.db[key]
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

--- @return boolean available, string|nil reason
function Module:IsAvailable()
	if self.Available then
		local ok, available, reason = Errors:Safe(self.name .. ":Available", self.Available, self)
		if not ok then return false, "its availability check errored" end
		return available and true or false, reason
	end
	return true, nil
end

function Module:IsWanted()
	return self.entry ~= nil and self.entry.enabled == true
end

function Module:IsRunning()
	return self.running
end

--- A saved choice that will only take effect after a reload.
function Module:IsPendingReload()
	if not self.initialized then return false end
	if self:IsWanted() == self.running then return false end
	if self:IsWanted() then
		-- Wanted on, not running: pending only if a reload would start it.
		return self.reloadToEnable and (self:IsAvailable()) or false
	end
	return self.reloadToDisable and true or false
end

--- One of "on", "off", "pending-on", "pending-off", "unavailable", "failed".
function Module:Status()
	local available, reason = self:IsAvailable()
	if not available and not self.running then return "unavailable", reason end
	if self:IsPendingReload() then
		return self.running and "pending-off" or "pending-on"
	end
	if self.running then return "on" end
	if self:IsWanted() then return "failed", self.lastFailure end
	return "off"
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Module:Initialize()
	if self.initialized then return end
	self.entry = DB:Module(self.name, self.defaults)
	self.db = self.entry.settings
	self.initialized = true
	if self.OnInitialize then
		self:Safe("OnInitialize", self.OnInitialize, self)
	end
end

--- Start the module now. Does not change the saved choice.
function Module:_start()
	if self.running then return true end
	if not (self:IsAvailable()) then return false end

	self.running = true
	self.lastFailure = nil
	self:_bindEvents()
	if self.OnEnable then
		local ok, err = self:Safe("OnEnable", self.OnEnable, self)
		if not ok then
			-- A half-started module is worse than a stopped one.
			self.running = false
			self:_unbindEvents()
			self.lastFailure = err or "OnEnable failed"
			self:Print("|cffff5555failed to start:|r", tostring(self.lastFailure))
			return false
		end
	end
	return true
end

--- Stop the module now. Does not change the saved choice.
function Module:_stop()
	if not self.running then return end
	self.running = false
	self:_unbindEvents()
	if self.OnDisable then
		self:Safe("OnDisable", self.OnDisable, self)
	end
end

--- The user's choice, from the checkbox or a command. SPEC §5.3.
-- @return boolean accepted
function Module:SetWanted(want)
	want = want and true or false
	if not self.initialized then return false end

	if want and not self.running then
		local available, reason = self:IsAvailable()
		if not available then
			self:Print("cannot run on this client" .. (reason and (": " .. reason) or "."))
			notify(self)
			return false
		end
	end

	self.entry.enabled = want

	if want and not self.running and not self.reloadToEnable then
		self:_start()
	elseif not want and self.running and not self.reloadToDisable then
		self:_stop()
	end

	notify(self)
	return true
end

function Module:Toggle()
	return self:SetWanted(not self:IsWanted())
end

--------------------------------------------------------------------------------
-- Bulk lifecycle, driven by Core
--------------------------------------------------------------------------------

function ns:InitializeModules()
	for _, module in ipairs(ns.moduleOrder) do
		module:Initialize()
	end
end

--- At login every wanted module starts, reload flags or not: this IS the reload.
function ns:StartWantedModules()
	for _, module in ipairs(ns.moduleOrder) do
		if module:IsWanted() then module:_start() end
	end
	notify(nil)
end

function ns:AnyPendingReload()
	for _, module in ipairs(ns.moduleOrder) do
		if module:IsPendingReload() then return true end
	end
	return false
end
