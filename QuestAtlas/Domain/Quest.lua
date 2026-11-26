-- QuestAtlas - Domain/Quest.lua
-- Domain model of a quest as the tracker sees it: game state (status,
-- objective progress) merged with location data from the quest database.
local _, ns = ...

local QuestStatus = {
    PLANNED = "PLANNED",         -- not accepted yet; the player plans to pick it up
    IN_PROGRESS = "IN_PROGRESS", -- in the quest log, objectives left
    READY = "READY",             -- objectives done, only the turn-in is left
    FAILED = "FAILED",           -- failed (e.g. escort died); cannot be routed
}

----------------------------------------------------------------------------
local QuestObjective = ns.Class("QuestObjective")

function QuestObjective:init(index, text, finished, location)
    self.index = index
    self.text = text or ""
    self.finished = finished and true or false
    self.location = location -- Location or nil when the database has no data
end

----------------------------------------------------------------------------
local Quest = ns.Class("Quest")

--- fields: id, title, level, status, objectives, giver, turnIn, known, locationSource
---   giver / turnIn: Location (with NPC name as label) or nil
---   known: true when the quest exists in the add-on's quest database
---   locationSource: "database", "game" (map marker of the client) or nil
function Quest:init(fields)
    assert(fields.id, "Quest: id is required")
    self.id = fields.id
    self.title = fields.title or ("Quest #" .. tostring(fields.id))
    self.level = fields.level or 0
    self.status = fields.status or QuestStatus.IN_PROGRESS
    self.objectives = fields.objectives or {}
    self.giver = fields.giver
    self.turnIn = fields.turnIn
    self.known = fields.known and true or false
    self.locationSource = fields.locationSource
end

function Quest:isPlanned()
    return self.status == QuestStatus.PLANNED
end

function Quest:isReady()
    return self.status == QuestStatus.READY
end

function Quest:isFailed()
    return self.status == QuestStatus.FAILED
end

function Quest:remainingObjectives()
    local result = {}
    for i = 1, #self.objectives do
        if not self.objectives[i].finished then
            result[#result + 1] = self.objectives[i]
        end
    end
    return result
end

function Quest:finishedObjectiveCount()
    return #self.objectives - #self:remainingObjectives()
end

--- True when the tracker knows enough to put the quest on a route.
--- Without a known turn-in NPC (the game only marks the objective area until
--- the objectives are done) the quest is still routable through its objectives.
function Quest:isRoutable()
    if self:isFailed() then
        return false
    end
    if self:isPlanned() then
        return self.giver ~= nil and self.turnIn ~= nil
    end
    if self.turnIn then
        return true
    end
    if self:isReady() then
        return false
    end
    local remaining = self:remainingObjectives()
    for i = 1, #remaining do
        if remaining[i].location then
            return true
        end
    end
    return false
end

ns.QuestStatus = QuestStatus
ns.QuestObjective = QuestObjective
ns.Quest = Quest
