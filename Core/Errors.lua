-- Core/Errors.lua
--
-- Chat output and a circuit breaker.
--
-- A module that errors once inside a bursty event errors hundreds of times a
-- minute and buries its own message. After `threshold` failures in one context
-- that context is switched off and reported once. `/dyru errors reset` re-arms it.
--
-- pcall, not xpcall: in Lua 5.1, which WoW runs, xpcall passes no arguments to
-- the called function, so `xpcall(fn, handler, arg)` silently calls `fn()`.

local ADDON, ns = ...

local Errors = {}
ns.Errors = Errors

Errors.debug = false
Errors.threshold = 5

local counts = {}
local disabled = {}
local lastError = {}

local PREFIX = "|cff66ccffDyrutilities|r "

function Errors:Print(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	local frame = _G.DEFAULT_CHAT_FRAME
	if frame then
		frame:AddMessage(PREFIX .. table.concat(parts, " "))
	end
end

function Errors:Debug(...)
	if not Errors.debug then return end
	Errors:Print("|cff808080debug|r", ...)
end

--- Run `fn` with its arguments, catching errors and counting them per context.
-- @return ok, ... the function's own returns on success
function Errors:Safe(context, fn, ...)
	if disabled[context] then return false end

	-- Counted with select("#"), not #, so a nil among the returns does not
	-- truncate the ones after it.
	local results = { n = 0 }
	local function capture(...)
		results.n = select("#", ...)
		for i = 1, results.n do results[i] = (select(i, ...)) end
	end
	capture(pcall(fn, ...))
	if results[1] then
		return true, unpack(results, 2, results.n)
	end

	local message = tostring(results[2])
	counts[context] = (counts[context] or 0) + 1
	lastError[context] = message

	if Errors.debug then
		Errors:Print("|cffff5555" .. context .. "|r " .. message)
	end

	if counts[context] >= Errors.threshold and not disabled[context] then
		disabled[context] = true
		Errors:Print("|cffff5555" .. context .. " failed " .. counts[context]
			.. " times and has been switched off.|r Last error:")
		Errors:Print("  " .. message)
		Errors:Print("|cffffcc00/dyru errors reset|r turns it back on.")
	end

	return false, message
end

function Errors:IsDisabled(context)
	return disabled[context] and true or false
end

function Errors:Reset()
	counts = {}
	disabled = {}
	lastError = {}
end

function Errors:Report()
	local any = false
	for context, n in pairs(counts) do
		any = true
		Errors:Print(string.format("|cffff5555%s|r x%d%s", context, n,
			disabled[context] and " (disabled)" or ""))
		if lastError[context] then
			Errors:Print("    " .. lastError[context])
		end
	end
	if not any then
		Errors:Print("No errors recorded this session.")
	else
		Errors:Print("|cffffcc00/dyru errors reset|r clears these and retries anything disabled.")
	end
end
