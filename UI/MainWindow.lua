-- UI/MainWindow.lua
--
-- The primary menu (SPEC §6.1): every feature in a list on the left with a
-- checkbox, and the selected feature's status, summary and settings on the
-- right. A banner along the bottom offers a reload while any change waits for one.
--
-- Built lazily, on first open, so an addon nobody opens costs one table.

local ADDON, ns = ...

local Compat = ns.Compat
local Errors = ns.Errors
local Widgets = ns.Widgets
local DB = ns.DB

local MainWindow = {}
ns.MainWindow = MainWindow

local WIDTH, HEIGHT = 560, 380
local LIST_WIDTH = 200
local ROW_HEIGHT = 24
local PAD = 8
local BANNER_HEIGHT = 32

MainWindow.FRAME_NAME = "DyrutilitiesMainWindow"

local STATUS_TEXT = {
	["on"]          = { "On", 0.25, 1, 0.25 },
	["off"]         = { "Off", 0.6, 0.6, 0.6 },
	["pending-on"]  = { "On after reload", 1, 0.8, 0 },
	["pending-off"] = { "Off after reload", 1, 0.8, 0 },
	["unavailable"] = { "Unavailable", 1, 0.35, 0.35 },
	["failed"]      = { "Failed to start", 1, 0.35, 0.35 },
}

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local frame          -- the window
local rows = {}      -- module name -> row
local detail         -- right pane widgets
local banner
local settingsPanels = {}   -- module name -> built settings frame

local function windowStore()
	return DB.db and DB.db.window or nil
end

local function selectedName()
	local store = windowStore()
	local name = store and store.selected
	if name and ns.modules[name] then return name end
	local first = ns.moduleOrder[1]
	return first and first.name or nil
end

local function buildRow(parent, module, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
	row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
	row.module = module

	row.selectedBg = Widgets:Fill(row, "BACKGROUND", Widgets.colors.selected)
	row.selectedBg:SetAllPoints(row)
	row.selectedBg:Hide()

	row.hoverBg = Widgets:Fill(row, "HIGHLIGHT", Widgets.colors.hover)
	row.hoverBg:SetAllPoints(row)

	-- The checkbox is its own button, so clicking it toggles without selecting
	-- and clicking the rest of the row selects without toggling.
	row.check = Widgets:Checkbox(row, 20, function(checked)
		module:SetWanted(checked)
		MainWindow:Select(module.name)
	end)
	row.check:SetPoint("LEFT", 4, 0)

	row.label = Widgets:Label(row, module.title, "GameFontHighlight")
	row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
	row.label:SetPoint("RIGHT", -4, 0)
	row.label:SetJustifyH("LEFT")

	row:SetScript("OnClick", function()
		MainWindow:Select(module.name)
	end)
	return row
end

local function buildList(body)
	local pane = CreateFrame("Frame", nil, body)
	pane:SetWidth(LIST_WIDTH)
	Widgets:Box(pane, Widgets.colors.pane)

	local scroll = CreateFrame("ScrollFrame", nil, pane)
	scroll:SetPoint("TOPLEFT", 1, -1)
	scroll:SetPoint("BOTTOMRIGHT", -1, 1)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetWidth(LIST_WIDTH - 2)
	content:SetHeight(math.max(1, #ns.moduleOrder * ROW_HEIGHT))
	scroll:SetScrollChild(content)

	-- Wheel scrolling, hand-rolled: no scroll template is verified on Forever.
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
		local target = (self:GetVerticalScroll() or 0) - delta * ROW_HEIGHT * 2
		self:SetVerticalScroll(math.max(0, math.min(maxScroll, target)))
	end)

	for index, module in ipairs(ns.moduleOrder) do
		rows[module.name] = buildRow(content, module, index)
	end

	if #ns.moduleOrder == 0 then
		local empty = Widgets:Label(pane, "No features yet.", "GameFontDisable")
		empty:SetPoint("TOP", 0, -16)
		pane.empty = empty
	end

	pane.scroll = scroll
	pane.content = content
	return pane
end

local function buildDetail(body)
	local pane = CreateFrame("Frame", nil, body)
	Widgets:Box(pane, Widgets.colors.pane)

	local title = Widgets:Label(pane, "", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 12, -12)
	title:SetPoint("TOPRIGHT", -12, -12)
	title:SetJustifyH("LEFT")

	local status = Widgets:Label(pane, "", "GameFontHighlightSmall")
	status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	status:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -4)
	status:SetJustifyH("LEFT")

	local summary = Widgets:Label(pane, "", "GameFontHighlight")
	summary:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -10)
	summary:SetPoint("TOPRIGHT", status, "BOTTOMRIGHT", 0, -10)
	summary:SetJustifyH("LEFT")
	summary:SetJustifyV("TOP")
	summary:SetWordWrap(true)

	local divider = Widgets:Fill(pane, "ARTWORK", Widgets.colors.border)
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -10)
	divider:SetPoint("TOPRIGHT", summary, "BOTTOMRIGHT", 0, -10)

	local host = CreateFrame("Frame", nil, pane)
	host:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -10)
	host:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -12, 12)

	local noSettings = Widgets:Label(host, "This feature has no settings.", "GameFontDisable")
	noSettings:SetPoint("TOPLEFT")

	local nothing = Widgets:Label(pane, "Features will appear here as they are added.", "GameFontDisable")
	nothing:SetPoint("CENTER")

	return {
		pane = pane, title = title, status = status, summary = summary,
		divider = divider, host = host, noSettings = noSettings, nothing = nothing,
	}
end

local function buildBanner(body)
	local bar = CreateFrame("Frame", nil, body)
	bar:SetHeight(BANNER_HEIGHT)
	bar:SetPoint("BOTTOMLEFT", PAD, PAD)
	bar:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	Widgets:Box(bar, Widgets.colors.banner)

	local text = Widgets:Label(bar, "Some changes take effect after a reload.", "GameFontHighlight")
	text:SetPoint("LEFT", 10, 0)

	local button = Widgets:Button(bar, "Reload UI", 100, 22, function()
		if not Compat.ReloadUI() then
			Errors:Print("Could not reload from here. Type |cffffcc00/reload|r.")
		end
	end)
	button:SetPoint("RIGHT", -6, 0)
	bar.button = button
	bar:Hide()
	return bar
end

--- Anchor both panes to the bottom of the body, or to the banner when it shows.
local function layout(list, showBanner)
	local bottom = showBanner and (PAD + BANNER_HEIGHT + PAD) or PAD
	list:ClearAllPoints()
	list:SetPoint("TOPLEFT", frame.body, "TOPLEFT", PAD, -PAD)
	list:SetPoint("BOTTOMLEFT", frame.body, "BOTTOMLEFT", PAD, bottom)

	detail.pane:ClearAllPoints()
	detail.pane:SetPoint("TOPLEFT", list, "TOPRIGHT", PAD, 0)
	detail.pane:SetPoint("BOTTOMRIGHT", frame.body, "BOTTOMRIGHT", -PAD, bottom)
end

function MainWindow:Build()
	if frame then return frame end

	frame = Widgets:Window({
		name = MainWindow.FRAME_NAME,
		title = "Dyrutilities |cff808080v" .. tostring(ns.version) .. "|r",
		width = WIDTH,
		height = HEIGHT,
		store = windowStore(),
	})
	Compat.AddSpecialFrame(MainWindow.FRAME_NAME)

	frame.list = buildList(frame.body)
	detail = buildDetail(frame.body)
	banner = buildBanner(frame.body)
	frame.banner = banner
	frame.detail = detail
	layout(frame.list, false)

	frame:SetScript("OnShow", function() MainWindow:Refresh() end)

	ns:OnModuleStateChanged("mainwindow", function()
		if frame:IsShown() then MainWindow:Refresh() end
	end)

	MainWindow.frame = frame
	return frame
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

local function settingsPanelFor(module)
	if not module.BuildSettings then return nil end
	local panel = settingsPanels[module.name]
	if panel then return panel end

	panel = CreateFrame("Frame", nil, detail.host)
	panel:SetAllPoints(detail.host)
	local ok = module:Safe("BuildSettings", module.BuildSettings, module, panel)
	if not ok then
		local failed = Widgets:Label(panel, "|cffff5555This feature's settings failed to build.|r "
			.. "See /dyru errors.", "GameFontHighlightSmall")
		failed:SetPoint("TOPLEFT")
	end
	settingsPanels[module.name] = panel
	return panel
end

local function refreshRow(row)
	local module = row.module
	local available = module:IsAvailable()
	row.check:SetChecked(module:IsWanted())
	if available then
		row.check:Enable()
		row.label:SetTextColor(1, 1, 1)
	else
		row.check:Disable()
		row.label:SetTextColor(0.5, 0.5, 0.5)
	end
end

local function refreshDetail(name)
	local module = name and ns.modules[name]
	local hasModule = module ~= nil

	detail.nothing:SetShown(not hasModule)
	detail.title:SetShown(hasModule)
	detail.status:SetShown(hasModule)
	detail.summary:SetShown(hasModule)
	detail.divider:SetShown(hasModule)
	detail.host:SetShown(hasModule)

	for panelName, panel in pairs(settingsPanels) do
		panel:SetShown(panelName == name)
	end
	if not hasModule then return end

	detail.title:SetText(module.title)

	local status, reason = module:Status()
	local spec = STATUS_TEXT[status] or { status, 1, 1, 1 }
	local text = spec[1]
	if reason then text = text .. ": " .. tostring(reason) end
	if status == "failed" then text = text .. "  (/dyru errors)" end
	detail.status:SetText(text)
	detail.status:SetTextColor(spec[2], spec[3], spec[4])

	detail.summary:SetText(module.summary or "")

	local panel = settingsPanelFor(module)
	detail.noSettings:SetShown(panel == nil)
	if panel then panel:Show() end
end

function MainWindow:Refresh()
	if not frame then return end
	local name = selectedName()
	for rowName, row in pairs(rows) do
		refreshRow(row)
		row.selectedBg:SetShown(rowName == name)
	end
	refreshDetail(name)

	local pending = ns:AnyPendingReload()
	banner:SetShown(pending)
	layout(frame.list, pending)
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

function MainWindow:Select(name)
	if not ns.modules[name] then return end
	local store = windowStore()
	if store then store.selected = name end
	self:Refresh()
end

function MainWindow:Show()
	self:Build()
	frame:Show()
	self:Refresh()
end

function MainWindow:Hide()
	if frame then frame:Hide() end
end

function MainWindow:IsShown()
	return frame ~= nil and frame:IsShown() and true or false
end

function MainWindow:Toggle()
	if self:IsShown() then self:Hide() else self:Show() end
end

function MainWindow:ResetPosition()
	local store = windowStore()
	if store then store.point = nil end
	if frame then frame:ResetPosition() end
end
