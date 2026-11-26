-- Core/Widgets.lua
--
-- Shared UI primitives: a flat box, labels, buttons, checkboxes, tooltips and a
-- movable window that remembers where it was.
--
-- Look (SPEC D-13): flat, hand-drawn from textures, not Blizzard frame
-- templates. Where a Blizzard template is used at all (button, close button,
-- checkbox) it is created under pcall with a hand-built fallback, because none
-- of those templates is verified on Forever yet. See COMPAT_FINDINGS.md.

local ADDON, ns = ...

local Errors = ns.Errors

local Widgets = {}
ns.Widgets = Widgets

Widgets.colors = {
	background = { 0.06, 0.06, 0.07, 0.94 },
	border     = { 0.35, 0.35, 0.38, 1 },
	title      = { 0.15, 0.15, 0.18, 1 },
	pane       = { 0.10, 0.10, 0.11, 1 },
	selected   = { 0.25, 0.45, 0.70, 0.35 },
	hover      = { 1, 1, 1, 0.06 },
	banner     = { 0.35, 0.25, 0.05, 0.95 },
}

local WHITE = "Interface\\Buttons\\WHITE8X8"

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

function Widgets:Fill(frame, layer, color)
	local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
	texture:SetTexture(WHITE)
	texture:SetVertexColor(color[1], color[2], color[3], color[4])
	return texture
end

--- A flat background with a one-pixel border.
function Widgets:Box(frame, bg, border)
	bg = bg or Widgets.colors.background
	border = border or Widgets.colors.border

	local background = Widgets:Fill(frame, "BACKGROUND", bg)
	background:SetAllPoints(frame)
	frame.bg = background

	frame.edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local edge = Widgets:Fill(frame, "BORDER", border)
		if side == "TOP" or side == "BOTTOM" then
			edge:SetPoint(side .. "LEFT")
			edge:SetPoint(side .. "RIGHT")
			edge:SetHeight(1)
		else
			edge:SetPoint("TOP" .. side)
			edge:SetPoint("BOTTOM" .. side)
			edge:SetWidth(1)
		end
		frame.edges[#frame.edges + 1] = edge
	end
	return frame
end

function Widgets:Label(parent, text, template)
	local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
	if text then label:SetText(text) end
	return label
end

--------------------------------------------------------------------------------
-- Tooltips
--------------------------------------------------------------------------------

--- Show lines as a tooltip anchored to `owner`. First line is the title.
function Widgets:ShowTooltip(owner, lines)
	if type(lines) ~= "table" or #lines == 0 or not _G.GameTooltip then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(lines[1], 1, 1, 1)
	for i = 2, #lines do
		GameTooltip:AddLine(lines[i], 0.8, 0.8, 0.8, true)
	end
	GameTooltip:Show()
end

function Widgets:AttachTooltip(frame, getLines)
	frame:SetScript("OnEnter", function(self)
		Widgets:ShowTooltip(self, getLines())
	end)
	frame:SetScript("OnLeave", function()
		if _G.GameTooltip then GameTooltip:Hide() end
	end)
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

local function tryTemplate(frameType, parent, template)
	local ok, frame = pcall(CreateFrame, frameType, nil, parent, template)
	if ok and frame then return frame end
	return nil
end

function Widgets:Button(parent, text, width, height, onClick)
	local button = tryTemplate("Button", parent, "UIPanelButtonTemplate")
	if not button then
		button = CreateFrame("Button", nil, parent)
		Widgets:Box(button, { 0.16, 0.16, 0.18, 1 }, { 0.4, 0.4, 0.44, 1 })
		local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("CENTER")
		button:SetFontString(label)
	end
	button:SetSize(width or 100, height or 22)
	button:SetText(text)
	if onClick then
		button:SetScript("OnClick", function(self, ...)
			Errors:Safe("button:" .. tostring(text), onClick, self, ...)
		end)
	end
	return button
end

function Widgets:CloseButton(parent, onClick)
	local button = tryTemplate("Button", parent, "UIPanelCloseButton")
	if not button then
		button = CreateFrame("Button", nil, parent)
		local x = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		x:SetPoint("CENTER")
		x:SetText("x")
		button:SetFontString(x)
	end
	button:SetSize(20, 20)
	button:SetScript("OnClick", function(self)
		Errors:Safe("close", onClick, self)
	end)
	return button
end

--- A checkbox. `onToggle(checked)` runs on a user click only, never on
-- SetChecked, so code that refreshes the box cannot feed back into it.
function Widgets:Checkbox(parent, size, onToggle)
	local box = tryTemplate("CheckButton", parent, "UICheckButtonTemplate")
	if not box then
		box = CreateFrame("CheckButton", nil, parent)
		box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
		box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
		box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
		box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
		box:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disable")
	end
	box:SetSize(size or 22, size or 22)
	box:SetScript("OnClick", function(self)
		local checked = self:GetChecked() and true or false
		if onToggle then Errors:Safe("checkbox", onToggle, checked, self) end
	end)
	return box
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

--- A movable window that remembers its position.
--
-- @param opts table
--   name      global frame name (needed for Escape-to-close)
--   title     title bar text
--   width, height
--   store     table; `point` is saved here
--   onClose   optional; after the close button hides the window
function Widgets:Window(opts)
	local frame = CreateFrame("Frame", opts.name, UIParent)
	frame:SetSize(opts.width or 400, opts.height or 300)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)   -- clicks on the body must not fall through to the world
	Widgets:Box(frame)

	local bar = CreateFrame("Frame", nil, frame)
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("TOPRIGHT", -1, -1)
	bar:SetHeight(22)
	Widgets:Box(bar, Widgets.colors.title, { 0, 0, 0, 0 })
	frame.titleBar = bar

	local title = Widgets:Label(bar, opts.title, "GameFontNormal")
	title:SetPoint("LEFT", 8, 0)
	title:SetPoint("RIGHT", -26, 0)
	title:SetJustifyH("LEFT")
	frame.title = title

	local close = Widgets:CloseButton(bar, function()
		frame:Hide()
		if opts.onClose then opts.onClose() end
	end)
	close:SetPoint("RIGHT", -1, 0)
	frame.closeButton = close

	local body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
	body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
	frame.body = body

	-- Dragged by the title bar only, so the body's controls stay clickable.
	frame:SetMovable(true)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() frame:StartMoving() end)
	bar:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		-- We save the position ourselves; stop the client's layout cache from
		-- also restoring it and fighting over it.
		if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
		Widgets:SavePosition(frame, opts.store)
	end)

	function frame:ResetPosition()
		if opts.store then opts.store.point = nil end
		Widgets:RestorePosition(frame, opts.store)
	end

	Widgets:RestorePosition(frame, opts.store)
	frame:Hide()
	return frame
end

--- Save the window's centre as an offset from UIParent's centre.
--
-- Not GetPoint(): after a drag that can name another frame as the anchor, and a
-- saved reference to a frame that may not exist next session fails on load.
-- The window is a direct child of UIParent at scale 1, so both centres are in
-- the same coordinate space.
function Widgets:SavePosition(frame, store)
	if not store then return end
	local cx, cy = frame:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if not (cx and cy and ux and uy) then return end
	store.point = { "CENTER", "UIParent", "CENTER", cx - ux, cy - uy }
end

function Widgets:RestorePosition(frame, store)
	local point = store and store.point
	frame:ClearAllPoints()
	local ok = type(point) == "table" and pcall(frame.SetPoint, frame,
		point[1], UIParent, point[3], point[4], point[5])
	if not ok then
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end
