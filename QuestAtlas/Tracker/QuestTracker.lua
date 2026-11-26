-- QuestAtlas - Tracker/QuestTracker.lua
-- Keeps the current state: tracked quests, planned quests, player position and
-- the latest route. After each refresh it publishes "TRACKER_UPDATED" on the
-- event bus (Observer pattern) - it does not know the UI exists.
local _, ns = ...

local QuestTracker = ns.Class("QuestTracker")

QuestTracker.UPDATED_EVENT = "TRACKER_UPDATED"
QuestTracker.MOVE_THRESHOLD_YARDS = 100

-- Game events (QUEST_LOG_UPDATE fires on every kill / loot) may reuse the last
-- route when nothing route-relevant changed. These reasons always re-plan:
QuestTracker.FORCE_REPLAN = {
    LOGIN = true, MANUAL = true, COMMAND = true, BUTTON = true, STRATEGY = true, PLAN = true, MOVED = true,
}

--- deps = { questSource, positionProvider, repository, questFactory, planner,
---          strategyFactory, settings, eventBus, api, distanceCalculator }
function QuestTracker:init(deps)
    local I = ns.Interfaces
    self.questSource = I.IQuestSource:assert(deps.questSource, "QuestTracker")
    self.positionProvider = I.IPositionProvider:assert(deps.positionProvider, "QuestTracker")
    self.repository = I.IQuestRepository:assert(deps.repository, "QuestTracker")
    self.settings = I.ISettingsStore:assert(deps.settings, "QuestTracker")
    self.distanceCalculator = I.IDistanceCalculator:assert(deps.distanceCalculator, "QuestTracker")
    self.questFactory = deps.questFactory
    self.planner = deps.planner
    self.strategyFactory = deps.strategyFactory
    self.eventBus = deps.eventBus
    self.api = deps.api

    self.quests = {}
    self.route = ns.Route.empty(nil, "NOT_REFRESHED")
    self.playerLocation = nil
    self.routeOrigin = nil
end

----------------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------------

function QuestTracker:refresh(reason)
    local logQuests = self.questSource:readQuests()
    local inLog = {}
    for i = 1, #logQuests do
        inLog[logQuests[i].id] = true
    end

    -- Planned quests that were accepted or completed meanwhile leave the plan.
    local quests = ns.Util.shallowCopy(logQuests)
    local planned = self.settings:get("planned")
    for i = #planned, 1, -1 do
        local id = planned[i]
        if inLog[id] or self.api:isQuestCompleted(id) or not self.repository:getQuest(id) then
            table.remove(planned, i)
        end
    end
    for i = 1, #planned do
        quests[#quests + 1] = self.questFactory:create("planned", planned[i])
    end

    self.quests = quests
    local location = self.positionProvider:getPlayerLocation()
    self.playerLocation = location
    local strategy = self:getStrategyName()
    if not self:canReuseRoute(reason, location, quests, strategy) then
        self.route = self.planner:plan(location, quests, strategy)
        self.routeOrigin = location
    end
    self.lastReason = reason
    if self.eventBus then
        self.eventBus:publish(QuestTracker.UPDATED_EVENT, self, reason)
    end
    return self.route
end

--- True when the previous route is still valid: same tasks, same strategy and
--- the player is still close to where it was planned. Keeps the game smooth -
--- killing a mob only changes "3/10" to "4/10", no need to run ATLAS again.
function QuestTracker:canReuseRoute(reason, location, quests, strategy)
    if QuestTracker.FORCE_REPLAN[reason] or not location or not self.routeOrigin then
        return false
    end
    if self.route.signature ~= self.planner:signature(quests, strategy) then
        return false
    end
    return self.distanceCalculator:distance(self.routeOrigin, location) < QuestTracker.MOVE_THRESHOLD_YARDS
end

--- Called periodically: re-plans only when the player moved noticeably.
function QuestTracker:refreshIfMoved(thresholdYards)
    local location = self.positionProvider:getPlayerLocation()
    if not location then
        return false
    end
    local origin = self.routeOrigin
    local moved = not origin
        or self.distanceCalculator:distance(origin, location) >= (thresholdYards or QuestTracker.MOVE_THRESHOLD_YARDS)
    if moved then
        self:refresh("MOVED")
    end
    return moved
end

----------------------------------------------------------------------------
-- Queries
----------------------------------------------------------------------------

function QuestTracker:getQuests()
    return self.quests
end

function QuestTracker:getRoute()
    return self.route
end

function QuestTracker:getPlayerLocation()
    return self.playerLocation
end

function QuestTracker:getStrategyName()
    return self.settings:get("strategy")
end

function QuestTracker:getPlannedQuestIds()
    return ns.Util.shallowCopy(self.settings:get("planned"))
end

--- list of { id, title } of the planned quests
function QuestTracker:getPlannedQuests()
    local ids = self.settings:get("planned")
    local result = {}
    for i = 1, #ids do
        local record = self.repository:getQuest(ids[i])
        result[#result + 1] = { id = ids[i], title = record and record.title or "?" }
    end
    return result
end

function QuestTracker:inLogSet()
    local set = {}
    for i = 1, #self.quests do
        if not self.quests[i]:isPlanned() then
            set[self.quests[i].id] = true
        end
    end
    return set
end

--- Available quests sorted by distance from the player:
--- list of { id, title, level, giverName, distance }
function QuestTracker:getAvailableQuests()
    local api = self.api
    local ids = self.repository:findAvailable(api:getPlayerInfo(),
        function(id) return api:isQuestCompleted(id) end, self:inLogSet())
    local here = self.positionProvider:getPlayerLocation()
    local result = {}
    for i = 1, #ids do
        local record = self.repository:getQuest(ids[i])
        local giver = self.repository:getNpcLocation(record.giver)
        result[#result + 1] = {
            id = ids[i], title = record.title, level = record.level,
            giverName = giver and giver.label or "?",
            distance = (here and giver) and self.distanceCalculator:distance(here, giver) or math.huge,
            planned = ns.Util.contains(self.settings:get("planned"), ids[i]),
        }
    end
    table.sort(result, function(a, b)
        if a.distance ~= b.distance then
            return a.distance < b.distance
        end
        return a.id < b.id
    end)
    return result
end

----------------------------------------------------------------------------
-- Commands (each returns ok, messageKey)
----------------------------------------------------------------------------

function QuestTracker:setStrategy(name)
    if not self.strategyFactory:has(name) then
        return false, "ERR_UNKNOWN_STRATEGY"
    end
    self.settings:set("strategy", name)
    self:refresh("STRATEGY")
    return true
end

function QuestTracker:cycleStrategy()
    local nextName = self.strategyFactory:nextName(self:getStrategyName())
    return self:setStrategy(nextName)
end

function QuestTracker:planQuest(questID)
    if not self.repository:getQuest(questID) then
        return false, "ERR_UNKNOWN_QUEST"
    end
    if self:inLogSet()[questID] then
        return false, "ERR_ALREADY_IN_LOG"
    end
    if self.api:isQuestCompleted(questID) then
        return false, "ERR_ALREADY_COMPLETED"
    end
    local planned = self.settings:get("planned")
    if ns.Util.contains(planned, questID) then
        return false, "ERR_ALREADY_PLANNED"
    end
    local available = self.repository:findAvailable(self.api:getPlayerInfo(),
        function(id) return self.api:isQuestCompleted(id) end, self:inLogSet())
    if not ns.Util.contains(available, questID) then
        return false, "ERR_NOT_AVAILABLE"
    end
    planned[#planned + 1] = questID
    self:refresh("PLAN")
    return true
end

function QuestTracker:unplanQuest(questID)
    local planned = self.settings:get("planned")
    if not ns.Util.contains(planned, questID) then
        return false, "ERR_NOT_PLANNED"
    end
    ns.Util.removeValue(planned, questID)
    self:refresh("PLAN")
    return true
end

function QuestTracker:clearPlanned()
    self.settings:set("planned", {})
    self:refresh("PLAN")
    return true
end

function QuestTracker:compareStrategies()
    return self.planner:compare(self.positionProvider:getPlayerLocation(), self.quests)
end

ns.QuestTracker = QuestTracker
