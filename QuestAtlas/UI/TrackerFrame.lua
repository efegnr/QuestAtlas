-- QuestAtlas - UI/TrackerFrame.lua
-- The view (ITrackerView): a movable window that shows the lines produced by
-- TrackerPresenter. It has no logic of its own; buttons call the facade.
local _, ns = ...

local TrackerFrame = ns.Class("TrackerFrame")

TrackerFrame.FRAME_NAME = "QuestAtlasFrame"
TrackerFrame.WIDTH = 420
TrackerFrame.LINE_HEIGHT = 14
TrackerFrame.MAX_LINES = 30
TrackerFrame.TOP_OFFSET = 48
TrackerFrame.BOTTOM_PADDING = 40

--- deps = { widgetFactory, settings, locale, onRefresh, onCycleStrategy }
function TrackerFrame:init(deps)
    self.widgetFactory = deps.widgetFactory
    self.settings = deps.settings
    self.locale = deps.locale
    self.onRefresh = deps.onRefresh
    self.onCycleStrategy = deps.onCycleStrategy
    self.lines = {}
    self.frame = nil
end

function TrackerFrame:build()
    if self.frame then
        return self.frame
    end
    local factory = self.widgetFactory
    local frame = factory:createPanel(TrackerFrame.FRAME_NAME, TrackerFrame.WIDTH, 200)
    self.frame = frame

    frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local point, _, relativePoint, x, y = f:GetPoint(1)
        self.settings:set("framePoint", { point, relativePoint, x, y })
    end)
    self:restorePosition()

    self.title = factory:createLabel(frame, "GameFontNormalLarge", "LEFT")
    self.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
    self.title:SetText(self.locale:get("TITLE"))

    self.subtitle = factory:createTextLine(frame, 11)
    self.subtitle:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)

    factory:createCloseButton(frame, function() self:hide() end)

    for i = 1, TrackerFrame.MAX_LINES do
        local line = factory:createTextLine(frame, 12)
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -(TrackerFrame.TOP_OFFSET + (i - 1) * TrackerFrame.LINE_HEIGHT))
        line:SetWidth(TrackerFrame.WIDTH - 24)
        line:SetWordWrap(false)
        line:Hide()
        self.lines[i] = line
    end

    self.refreshButton = factory:createButton(frame, self.locale:get("BTN_REFRESH"), 100, 22,
        function() self.onRefresh() end)
    self.refreshButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)

    self.strategyButton = factory:createButton(frame, self.locale:get("BTN_STRATEGY"), 120, 22,
        function() self.onCycleStrategy() end)
    self.strategyButton:SetPoint("LEFT", self.refreshButton, "RIGHT", 6, 0)

    if self.settings:get("shown") then
        frame:Show()
    else
        frame:Hide()
    end
    return frame
end

function TrackerFrame:restorePosition()
    local saved = self.settings:get("framePoint")
    if type(saved) == "table" and saved[1] then
        self.frame:ClearAllPoints()
        self.frame:SetPoint(saved[1], self.widgetFactory:getUIParent(), saved[2], saved[3], saved[4])
    end
end

--- lines: from TrackerPresenter:buildLines; subtitle: short status text
function TrackerFrame:render(lines, subtitle)
    self:build()
    -- Texts that depend on the language are refreshed too (/qa lang).
    self.title:SetText(self.locale:get("TITLE"))
    self.refreshButton:SetText(self.locale:get("BTN_REFRESH"))
    self.strategyButton:SetText(self.locale:get("BTN_STRATEGY"))
    self.subtitle:SetText(subtitle or "")

    local count = math.min(#lines, TrackerFrame.MAX_LINES)
    for i = 1, TrackerFrame.MAX_LINES do
        local widget = self.lines[i]
        if i <= count then
            widget:SetText(ns.Util.colorize(lines[i].text, lines[i].color))
            widget:Show()
        else
            widget:SetText("")
            widget:Hide()
        end
    end
    self.frame:SetHeight(TrackerFrame.TOP_OFFSET + count * TrackerFrame.LINE_HEIGHT + TrackerFrame.BOTTOM_PADDING)
end

function TrackerFrame:show()
    self:build()
    self.frame:Show()
    self.settings:set("shown", true)
end

function TrackerFrame:hide()
    self:build()
    self.frame:Hide()
    self.settings:set("shown", false)
end

function TrackerFrame:toggle()
    if self:isShown() then
        self:hide()
    else
        self:show()
    end
end

function TrackerFrame:isShown()
    return self.frame ~= nil and self.frame:IsShown() and true or false
end

ns.TrackerFrame = TrackerFrame
