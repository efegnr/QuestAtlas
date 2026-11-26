-- QuestAtlas - UI/WidgetFactory.lua
-- Factory Method pattern for UI widgets: every frame, label and button of the
-- add-on is created here, with a consistent look. The rest of the UI code
-- never calls CreateFrame directly.
local _, ns = ...

local WidgetFactory = ns.Class("WidgetFactory")

WidgetFactory.TEXT_FONT = "Fonts\\ARIALN.TTF"

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

function WidgetFactory:init(api)
    self.api = api
end

--- A movable window with a dark background.
function WidgetFactory:createPanel(name, width, height)
    local template = self.api:hasBackdropTemplate() and "BackdropTemplate" or nil
    local frame = self.api:createFrame("Frame", name, self.api:getUIParent(), template)
    frame:SetSize(width, height)
    frame:SetPoint("RIGHT", self.api:getUIParent(), "RIGHT", -40, 0)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    if frame.SetBackdrop then
        frame:SetBackdrop(BACKDROP)
        frame:SetBackdropColor(0, 0, 0, 0.75)
        frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
    return frame
end

function WidgetFactory:getUIParent()
    return self.api:getUIParent()
end

function WidgetFactory:createLabel(parent, fontObject, justify)
    local label = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlightSmall")
    label:SetJustifyH(justify or "LEFT")
    return label
end

--- A text line that can show Turkish characters (ş, ğ, ı): WoW's default UI
--- font lacks some of them, Arial Narrow (used by the chat) has them all.
function WidgetFactory:createTextLine(parent, size)
    local label = self:createLabel(parent, "GameFontHighlightSmall", "LEFT")
    label:SetFont(WidgetFactory.TEXT_FONT, size or 12, "")
    return label
end

function WidgetFactory:createButton(parent, text, width, height, onClick)
    local button = self.api:createFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

function WidgetFactory:createCloseButton(parent, onClick)
    local button = self.api:createFrame("Button", nil, parent, "UIPanelCloseButton")
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -2)
    button:SetScript("OnClick", onClick)
    return button
end

ns.WidgetFactory = WidgetFactory
