-- Modules/LootFramePositions/LootFramePositions.lua
--
-- Move the loot roll prompts and Blizzard's toasts (including the "you won"
-- loot popup) to where the player wants them. See README.md beside this file,
-- and SPEC §11 (F-1) for the decisions.
--
-- Shape of it: we own two anchor frames. While Edit Mode is open, a small
-- Dyrutilities panel below Edit Mode's window offers a show-checkbox per
-- anchor, and a ticked anchor shows a draggable handle. A saved position is
-- applied through Compat, which is the only code touching Blizzard's frames:
--   * toasts: AlertFrame:SetBaseAnchorFrame(ourAnchor), undone exactly by
--     ResetBaseAnchorFrame (verified 26 Nov 2026), so no reload is needed;
--   * roll prompts: GroupLootFrame1-4 re-anchored to ourAnchor after each
--     GroupLootContainer_Update; the managed container itself is never moved
--     (it would not stick: measured 26 Nov 2026).
-- With no saved position, nothing of Blizzard's is touched at all.

local ADDON, ns = ...

local Compat = ns.Compat
local Widgets = ns.Widgets

local HANDLE_COLOR = { 0.1, 0.5, 1, 0.45 }       -- the color verified visible over Edit Mode
local HANDLE_STRATA = "FULLSCREEN_DIALOG"          -- likewise (COMPAT_FINDINGS "Edit Mode")

-- Sizes of what the handles stand for. A roll prompt is 277x67 (measured);
-- a toast is roughly that size too, and stacks upward from the anchor.
local ROLL_SIZE = { 277, 67 }
local ALERT_ANCHOR_SIZE = { 300, 10 }
local ALERT_HANDLE_HEIGHT = 80

local M = ns:RegisterModule("lootframepositions", {
	title = "Loot Frame Positions",
	summary = "Move the loot roll prompts (Need / Greed / Pass) and Blizzard's toasts, "
		.. "including the \"you won\" loot popup. Open Edit Mode, tick Loot Rolls or Alerts in "
		.. "the Dyrutilities panel under Edit Mode's window, and drag. Moving toasts moves "
		.. "every Blizzard toast (achievements, reputation and so on), not only loot.",
	defaults = {
		-- Positions: nil = Blizzard's default. Shape: { "CENTER", "UIParent", "CENTER", x, y }.
		-- (No entries here: a nil default is simply absence.)
		showAlertHandle = false,
		showRollHandle = false,
	},
})

--------------------------------------------------------------------------------
-- Availability
--------------------------------------------------------------------------------

function M:Available()
	if not Compat.hasEditModeCallbacks then
		return false, "this client does not report when Edit Mode opens"
	end
	if not Compat.hasAlertBaseAnchor and not Compat.hasLootRollHook then
		return false, "neither the toasts nor the roll prompts can be moved on this client"
	end
	return true
end

--------------------------------------------------------------------------------
-- Positions
--------------------------------------------------------------------------------

local function savePoint(frame)
	local cx, cy = frame:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if not (cx and cy and ux and uy) then return nil end
	return { "CENTER", "UIParent", "CENTER", cx - ux, cy - uy }
end

local function restorePoint(frame, point)
	frame:ClearAllPoints()
	local ok = type(point) == "table" and pcall(frame.SetPoint, frame,
		point[1], UIParent, point[3], point[4], point[5])
	return ok and true or false
end

--------------------------------------------------------------------------------
-- Anchors and handles (our own frames only)
--------------------------------------------------------------------------------

--- One anchor kind: its frame, its handle, and how it is applied.
local kinds = {
	alert = {
		label = "Alerts",
		hint = "Toasts appear here",
		pointKey = "alertPoint",
		showKey = "showAlertHandle",
		available = function() return Compat.hasAlertBaseAnchor end,
		placeDefault = function(frame) Compat.AnchorAtAlertFrame(frame) end,
		apply = function(frame) return Compat.SetAlertBaseAnchor(frame) end,
		reset = function() return Compat.ResetAlertBaseAnchor() end,
	},
	roll = {
		label = "Loot Rolls",
		hint = "Need / Greed prompts appear here",
		pointKey = "rollPoint",
		showKey = "showRollHandle",
		-- Checked when asked: Blizzard's loot code can load after us.
		available = function() return Compat.LootRollAnchorAvailable() end,
		placeDefault = function(frame) Compat.AnchorAtLootRollDefault(frame) end,
		apply = function(frame) return Compat.SetLootRollAnchor(frame) end,
		reset = function() return Compat.ResetLootRollAnchor() end,
	},
}
M.kinds = kinds
local KIND_ORDER = { "roll", "alert" }

local function buildAnchor(self, key, kind)
	local anchor = CreateFrame("Frame", key == "alert" and "DyrutilitiesAlertAnchor"
		or "DyrutilitiesLootRollAnchor", UIParent)
	if key == "alert" then
		anchor:SetSize(ALERT_ANCHOR_SIZE[1], ALERT_ANCHOR_SIZE[2])
	else
		anchor:SetSize(ROLL_SIZE[1], ROLL_SIZE[2])
	end
	anchor:SetMovable(true)
	anchor:SetClampedToScreen(true)

	-- The handle is what the player sees and drags; the anchor is what Blizzard's
	-- frames follow. For toasts they differ: toasts stack UP from the anchor.
	local handle = CreateFrame("Button", nil, anchor)
	handle:SetFrameStrata(HANDLE_STRATA)
	if key == "alert" then
		handle:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT")
		handle:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT")
		handle:SetHeight(ALERT_HANDLE_HEIGHT)
	else
		handle:SetAllPoints(anchor)
	end
	Widgets:Box(handle, HANDLE_COLOR, { 0.3, 0.7, 1, 1 })

	local title = Widgets:Label(handle, kind.label, "GameFontHighlightLarge")
	title:SetPoint("CENTER", 0, 8)
	local hint = Widgets:Label(handle, kind.hint, "GameFontHighlightSmall")
	hint:SetPoint("TOP", title, "BOTTOM", 0, -4)

	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function() anchor:StartMoving() end)
	handle:SetScript("OnDragStop", function()
		anchor:StopMovingOrSizing()
		if anchor.SetUserPlaced then pcall(anchor.SetUserPlaced, anchor, false) end
		self:Safe("drag", self.OnHandleMoved, self, key)
	end)
	handle:Hide()

	kind.anchor = anchor
	kind.handle = handle
end

--- Apply the saved position for one kind, or stand back to Blizzard's default.
function M:ApplyKind(key)
	local kind = kinds[key]
	-- Not gated on available(): Compat keeps a roll anchor set before
	-- Blizzard's loot code loads, and hooks it up when that code appears.
	if not kind.anchor then return end
	local point = self.db[kind.pointKey]
	if point and restorePoint(kind.anchor, point) then
		kind.applied = kind.apply(kind.anchor) and true or false
	else
		kind.placeDefault(kind.anchor)
		if kind.applied then kind.reset() end
		kind.applied = false
	end
end

function M:OnHandleMoved(key)
	local kind = kinds[key]
	self.db[kind.pointKey] = savePoint(kind.anchor)
	if self.running then self:ApplyKind(key) end
	self:RefreshSettings()
end

--------------------------------------------------------------------------------
-- The Edit Mode panel (SPEC F-1.5: our own show-checkboxes)
--------------------------------------------------------------------------------

function M:BuildPanel()
	if self.panel then return self.panel end
	local panel = CreateFrame("Frame", "DyrutilitiesEditModePanel", UIParent)
	panel:SetSize(230, 30 + #KIND_ORDER * 26)
	panel:SetFrameStrata(HANDLE_STRATA)
	panel:EnableMouse(true)
	Widgets:Box(panel)

	local title = Widgets:Label(panel, "Dyrutilities", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -8)

	panel.boxes = {}
	for index, key in ipairs(KIND_ORDER) do
		local kind = kinds[key]
		local box = Widgets:Checkbox(panel, 22, function(checked)
			self:Set(kind.showKey, checked)
			self:RefreshHandles()
		end)
		box:SetPoint("TOPLEFT", 8, -24 - (index - 1) * 26)
		local label = Widgets:Label(box, kind.label, "GameFontHighlight")
		label:SetPoint("LEFT", box, "RIGHT", 4, 0)
		box.label = label
		box.kindKey = key
		panel.boxes[key] = box
	end
	panel:Hide()
	self.panel = panel
	return panel
end

--- Show what should be showing, given Edit Mode's state and the checkboxes.
function M:RefreshHandles()
	local editing = self.running and self.editing
	if self.panel then
		if editing then
			Compat.AnchorBelowEditMode(self.panel)
			self.panel:Show()
			for key, box in pairs(self.panel.boxes) do
				local kind = kinds[key]
				if kind.available() then
					box:Enable()
					box:SetChecked(self.db[kind.showKey] and true or false)
					box.label:SetTextColor(1, 1, 1)
					box.label:SetText(kind.label)
				else
					box:Disable()
					box:SetChecked(false)
					box.label:SetTextColor(0.5, 0.5, 0.5)
					box.label:SetText(kind.label .. " (not available yet)")
				end
			end
		else
			self.panel:Hide()
		end
	end
	for _, kind in pairs(kinds) do
		if kind.handle then
			kind.handle:SetShown(editing and kind.available() and self.db[kind.showKey] and true or false)
		end
	end
end

function M:OnEditModeEnter()
	self.editing = true
	if self.running then self:RefreshHandles() end
end

function M:OnEditModeExit()
	self.editing = false
	self:RefreshHandles()
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:OnEnable()
	for _, key in ipairs(KIND_ORDER) do
		if not kinds[key].anchor then buildAnchor(self, key, kinds[key]) end
		self:ApplyKind(key)
	end
	self:BuildPanel()

	-- Registered once; the callbacks check `running`, so disabling needs no
	-- unregistering (and EventRegistry's unregister is unverified on Forever).
	if not self.editModeHooked then
		self.editModeHooked = Compat.OnEditMode(self.name,
			function() self:OnEditModeEnter() end,
			function() self:OnEditModeExit() end)
	end
	self.editing = Compat.IsEditModeActive()
	self:RefreshHandles()
	self:RefreshSettings()
end

function M:OnDisable()
	for _, kind in pairs(kinds) do
		if kind.applied then kind.reset() end
		kind.applied = false
	end
	self:RefreshHandles()
	self:RefreshSettings()
end

--------------------------------------------------------------------------------
-- Reset (SPEC F-1.6: a button in the feature's settings)
--------------------------------------------------------------------------------

function M:ResetPositions()
	for _, key in ipairs(KIND_ORDER) do
		self.db[kinds[key].pointKey] = nil
		if self.running then self:ApplyKind(key) end
	end
	self:RefreshSettings()
	self:Print("positions reset to Blizzard's defaults.")
end

--------------------------------------------------------------------------------
-- Settings pane in /dyru
--------------------------------------------------------------------------------

local function describe(self, key)
	local kind = kinds[key]
	if not kind.available() then return kind.label .. ": |cff808080not available yet|r" end
	if self.db[kind.pointKey] then return kind.label .. ": |cff40ff40moved|r" end
	return kind.label .. ": Blizzard's default"
end

function M:BuildSettings(panel)
	local how = Widgets:Label(panel,
		"To move them: turn this feature on, open Edit Mode (Esc > Edit Mode), tick "
		.. "Loot Rolls or Alerts in the Dyrutilities panel under Edit Mode's window, then "
		.. "drag the blue box. Positions are saved for this character.", "GameFontHighlightSmall")
	how:SetPoint("TOPLEFT")
	how:SetPoint("TOPRIGHT")
	how:SetJustifyH("LEFT")
	how:SetWordWrap(true)

	self.statusLabels = {}
	local previous = how
	for _, key in ipairs(KIND_ORDER) do
		local label = Widgets:Label(panel, "", "GameFontHighlight")
		label:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, previous == how and -12 or -4)
		self.statusLabels[key] = label
		previous = label
	end

	local reset = Widgets:Button(panel, "Reset positions", 140, 22, function()
		self:ResetPositions()
	end)
	reset:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -12)
	self.resetButton = reset

	self:RefreshSettings()
end

function M:RefreshSettings()
	if not self.statusLabels then return end
	for key, label in pairs(self.statusLabels) do
		label:SetText(describe(self, key))
	end
end
