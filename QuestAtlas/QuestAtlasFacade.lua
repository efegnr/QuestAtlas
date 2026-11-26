-- QuestAtlas - QuestAtlasFacade.lua
-- Facade pattern: ONE simple entry point to the whole add-on. Slash commands,
-- UI buttons, game events (and other add-ons via the global `QuestAtlas`)
-- only call these methods; they never see the tracker, planner, repository or
-- API adapter behind them.
local _, ns = ...

local QuestAtlasFacade = ns.Class("QuestAtlasFacade")

--- deps = { tracker, settings, api, locale, strategyFactory, presenter, eventBus }
function QuestAtlasFacade:init(deps)
    self.tracker = deps.tracker
    self.settings = deps.settings
    self.api = deps.api
    self.locale = deps.locale
    self.strategyFactory = deps.strategyFactory
    self.presenter = deps.presenter
    self.eventBus = deps.eventBus
    self.view = nil
    self.commandChain = nil
    self.commandHandlers = {}
end

----------------------------------------------------------------------------
-- Wiring (called once by Bootstrap)
----------------------------------------------------------------------------

function QuestAtlasFacade:attachView(view)
    self.view = ns.Interfaces.ITrackerView:assert(view, "QuestAtlasFacade:attachView")
    self.eventBus:subscribe(ns.QuestTracker.UPDATED_EVENT, function()
        self:renderView()
    end)
end

function QuestAtlasFacade:setCommandChain(head, handlers)
    self.commandChain = ns.Interfaces.ICommandHandler:assert(head, "QuestAtlasFacade:setCommandChain")
    self.commandHandlers = handlers or {}
end

----------------------------------------------------------------------------
-- Text helpers
----------------------------------------------------------------------------

function QuestAtlasFacade:t(key, ...)
    return self.locale:get(key, ...)
end

function QuestAtlasFacade:print(text)
    self.api:printMessage(ns.Util.colorize("QuestAtlas:", "33ccff") .. " " .. text)
end

function QuestAtlasFacade:printLine(text)
    self.api:printMessage(text)
end

function QuestAtlasFacade:getHelpLines()
    local lines = {}
    for i = 1, #self.commandHandlers do
        local key = self.commandHandlers[i]:getHelpKey()
        if key then
            lines[#lines + 1] = "  " .. self:t(key)
        end
    end
    return lines
end

function QuestAtlasFacade:describeStep(step, index)
    local here = self.tracker:getPlayerLocation()
    return self.presenter:formatStep(step, index, here and here.mapID)
end

function QuestAtlasFacade:describeRouteHeader(route)
    return self.presenter:routeHeader(route)
end

function QuestAtlasFacade:describeEmptyRoute(route)
    return self.presenter:emptyRouteText(route)
end

----------------------------------------------------------------------------
-- Tracker
----------------------------------------------------------------------------

function QuestAtlasFacade:refresh(reason)
    return self.tracker:refresh(reason or "MANUAL")
end

function QuestAtlasFacade:refreshIfMoved(thresholdYards)
    return self.tracker:refreshIfMoved(thresholdYards)
end

function QuestAtlasFacade:getQuests()
    return self.tracker:getQuests()
end

function QuestAtlasFacade:getRoute()
    return self.tracker:getRoute()
end

function QuestAtlasFacade:getStrategyName()
    return self.tracker:getStrategyName()
end

function QuestAtlasFacade:getStrategyNames()
    return self.strategyFactory:getNames()
end

function QuestAtlasFacade:setStrategy(name)
    return self.tracker:setStrategy(name)
end

function QuestAtlasFacade:cycleStrategy()
    return self.tracker:cycleStrategy()
end

function QuestAtlasFacade:compareStrategies()
    return self.tracker:compareStrategies()
end

function QuestAtlasFacade:getAvailableQuests()
    return self.tracker:getAvailableQuests()
end

function QuestAtlasFacade:planQuest(questID)
    return self.tracker:planQuest(questID)
end

function QuestAtlasFacade:unplanQuest(questID)
    return self.tracker:unplanQuest(questID)
end

function QuestAtlasFacade:clearPlanned()
    return self.tracker:clearPlanned()
end

--- list of { id, title }
function QuestAtlasFacade:getPlannedQuests()
    return self.tracker:getPlannedQuests()
end

--- Returns the next route step and whether a map waypoint could be placed.
function QuestAtlasFacade:goToNextStep()
    local step = self.tracker:getRoute():getNextStep()
    if not step then
        return nil, false
    end
    local location = step.location
    return step, self.api:setWaypoint(location.mapID, location.x, location.y)
end

--- Lines for /qa debug: everything needed to report a problem from the game.
function QuestAtlasFacade:getDiagnostics()
    local api, Util = self.api, ns.Util
    local function yesNo(value)
        return self:t(value and "DEBUG_YES" or "DEBUG_NO")
    end
    local lines = {}
    local client = api:getClientInfo()
    lines[#lines + 1] = self:t("DEBUG_CLIENT", tostring(client.version or "?"), tostring(client.build or "?"),
        tostring(client.interface or "?"))
    lines[#lines + 1] = self:t("DEBUG_API", api:getQuestApiFlavor(), yesNo(api:hasQuestPoiApi()),
        yesNo(api:hasWaypointApi()))
    local here = self.tracker:getPlayerLocation()
    if here then
        lines[#lines + 1] = self:t("DEBUG_POSITION", tostring(here.mapID), api:getMapName(here.mapID),
            Util.formatCoord(here.x, here.y))
    else
        local mapID = api.getPlayerMapID and api:getPlayerMapID() or nil
        lines[#lines + 1] = self:t("DEBUG_NO_POSITION",
            mapID and (tostring(mapID) .. " " .. api:getMapName(mapID)) or "-")
    end
    local quests = self.tracker:getQuests()
    local fromDatabase, fromGame, without = 0, 0, 0
    for i = 1, #quests do
        local source = quests[i].locationSource
        if source == "database" then
            fromDatabase = fromDatabase + 1
        elseif source == "game" then
            fromGame = fromGame + 1
        else
            without = without + 1
        end
    end
    lines[#lines + 1] = self:t("DEBUG_QUESTS", #quests, fromDatabase, fromGame, without)
    local route = self.tracker:getRoute()
    lines[#lines + 1] = self:t("DEBUG_ROUTE", tostring(route.strategyName or self:getStrategyName()), #route.steps,
        Util.formatYards(route.totalDistance or 0), string.format("%.1f", route.computeTimeMs or 0))
    return lines
end

----------------------------------------------------------------------------
-- Language
----------------------------------------------------------------------------

function QuestAtlasFacade:setLanguage(code)
    self.locale:setLanguage(code)
    self.settings:set("language", code)
    self:renderView()
end

function QuestAtlasFacade:getLanguage()
    return self.locale:getLanguage()
end

----------------------------------------------------------------------------
-- UI
----------------------------------------------------------------------------

function QuestAtlasFacade:renderView()
    if not self.view then
        return
    end
    local route = self.tracker:getRoute()
    local lines = self.presenter:buildLines({
        quests = self.tracker:getQuests(),
        route = route,
        playerLocation = self.tracker:getPlayerLocation(),
        maxRouteLines = self.settings:get("maxRouteLines"),
    })
    local subtitle = self:t("SUBTITLE", self:getStrategyName(), string.format("%.1f", route.computeTimeMs or 0))
    self.view:render(lines, subtitle)
end

function QuestAtlasFacade:showUI()
    if self.view then
        self.view:show()
        self:renderView()
    end
end

function QuestAtlasFacade:hideUI()
    if self.view then
        self.view:hide()
    end
end

function QuestAtlasFacade:toggleUI()
    if self.view then
        self.view:toggle()
        self:renderView()
    end
end

----------------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------------

function QuestAtlasFacade:handleSlashCommand(message)
    local command, args = ns.Util.splitCommand(message)
    if not self.commandChain then
        return false
    end
    return self.commandChain:handle(self, command, args)
end

ns.QuestAtlasFacade = QuestAtlasFacade
