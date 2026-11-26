-- QuestAtlas - UI/TrackerPresenter.lua
-- Presenter (MVP): converts the tracker state into plain text lines.
-- It contains all formatting logic but never touches a frame, so it can be
-- tested without the game; TrackerFrame only draws the lines (SOLID - S).
local _, ns = ...

local Util = ns.Util

local COLORS = {
    header = "ffd100",   -- WoW yellow
    ready = "40ff40",
    failed = "ff4040",
    planned = "a0a0a0",
    dim = "a0a0a0",
    step = "ffffff",
}

local TrackerPresenter = ns.Class("TrackerPresenter")

--- locale: ns.Locale instance; mapNameResolver: function(mapID) -> name
function TrackerPresenter:init(locale, mapNameResolver)
    self.locale = locale
    self.mapNameResolver = mapNameResolver or function(mapID) return "Map " .. tostring(mapID) end
end

function TrackerPresenter:t(key, ...)
    return self.locale:get(key, ...)
end

function TrackerPresenter:questStatusText(quest)
    if quest:isFailed() then
        return Util.colorize(self:t("STATUS_FAILED"), COLORS.failed)
    elseif quest:isReady() then
        return Util.colorize(self:t("STATUS_READY"), COLORS.ready)
    elseif quest:isPlanned() then
        return Util.colorize(self:t("STATUS_PLANNED"), COLORS.planned)
    end
    return self:t("STATUS_PROGRESS", quest:finishedObjectiveCount(), #quest.objectives)
end

function TrackerPresenter:formatQuest(quest)
    return string.format("[%d] %s  %s", quest.level or 0, quest.title, self:questStatusText(quest))
end

function TrackerPresenter:stepKindText(kind)
    if kind == ns.StepKind.ACCEPT then
        return self:t("STEP_ACCEPT")
    elseif kind == ns.StepKind.TURN_IN then
        return self:t("STEP_TURN_IN")
    end
    return self:t("STEP_OBJECTIVE")
end

--- Legs to another continent (or with unknown geometry) carry a penalty
--- distance in the routing; they are shown as words, not as fake yards.
local function isPenaltyDistance(distance)
    return distance >= ns.DistanceCalculator.UNKNOWN_PENALTY
end

function TrackerPresenter:distanceText(distance)
    if distance >= ns.DistanceCalculator.CROSS_CONTINENT_PENALTY then
        return self:t("FAR_AWAY")
    elseif isPenaltyDistance(distance) then
        return self:t("DISTANCE_UNKNOWN")
    end
    return Util.formatYards(distance) .. " " .. self:t("YARDS")
end

--- "1. Turn in: A Threat Within @ Marshal McBride (48.9, 41.6) - 35 yd"
function TrackerPresenter:formatStep(step, index, playerMapID)
    local titles = Util.map(step.quests, function(q) return q.title end)
    local location = step.location
    local where = location:describe()
    if playerMapID and location.mapID ~= playerMapID then
        where = self.mapNameResolver(location.mapID) .. ": " .. where
    end
    return string.format("%d. %s: %s @ %s - %s", index, self:stepKindText(step.kind),
        table.concat(titles, ", "), where, self:distanceText(step.legDistance))
end

--- "Route (atlas) - total 1607 yd", plus "(+1 long trip)" for penalty legs.
function TrackerPresenter:routeHeader(route)
    local walked, farLegs = 0, 0
    for i = 1, #route.steps do
        local leg = route.steps[i].legDistance
        if isPenaltyDistance(leg) then
            farLegs = farLegs + 1
        else
            walked = walked + leg
        end
    end
    local text = self:t("ROUTE_HEADER", route.strategyName or "?", Util.formatYards(walked), self:t("YARDS"))
    if farLegs > 0 then
        text = text .. " " .. self:t("ROUTE_FAR_LEGS", farLegs)
    end
    return text
end

function TrackerPresenter:emptyRouteText(route)
    if route.reason == "NO_POSITION" then
        return self:t("ROUTE_NO_POSITION")
    elseif route.reason == "NOT_REFRESHED" then
        return self:t("ROUTE_NOT_READY")
    end
    return self:t("ROUTE_NO_TASKS")
end

--- state: { quests, route, playerLocation, maxRouteLines }
--- Returns a list of { text = string, color = hex or nil }.
function TrackerPresenter:buildLines(state)
    local lines = {}
    local function add(text, color)
        lines[#lines + 1] = { text = text, color = color }
    end

    local quests = state.quests or {}
    add(self:t("QUESTS_HEADER", #quests), COLORS.header)
    if #quests == 0 then
        add(self:t("NO_QUESTS"), COLORS.dim)
    end
    for i = 1, #quests do
        add(self:formatQuest(quests[i]), quests[i]:isPlanned() and COLORS.planned or nil)
    end

    local route = state.route
    add(" ")
    if route and not route:isEmpty() then
        add(self:routeHeader(route), COLORS.header)
        local playerMapID = state.playerLocation and state.playerLocation.mapID
        local limit = math.min(#route.steps, state.maxRouteLines or #route.steps)
        for i = 1, limit do
            add(self:formatStep(route.steps[i], i, playerMapID), i == 1 and COLORS.step or COLORS.dim)
        end
        if #route.steps > limit then
            add(self:t("MORE_STEPS", #route.steps - limit), COLORS.dim)
        end
    else
        add(self:t("ROUTE_TITLE"), COLORS.header)
        add(route and self:emptyRouteText(route) or self:t("ROUTE_NOT_READY"), COLORS.dim)
    end

    if route and route.unroutable and #route.unroutable > 0 then
        local titles = Util.map(route.unroutable, function(q) return q.title end)
        add(self:t("UNROUTABLE", table.concat(titles, ", ")), COLORS.failed)
    end
    return lines
end

ns.TrackerPresenter = TrackerPresenter
ns.TrackerPresenter.COLORS = COLORS
