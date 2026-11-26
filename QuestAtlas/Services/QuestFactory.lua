-- QuestAtlas - Services/QuestFactory.lua
-- Factory Method pattern: the only place where Quest domain objects are built.
-- It merges a source (a quest log entry, or a database record for a planned
-- quest) with the location data from the repository.
-- New kinds of sources are added with registerCreator() - existing code does
-- not change (SOLID - O).
local _, ns = ...

local QuestFactory = ns.Class("QuestFactory")

function QuestFactory:init(repository)
    self.repository = ns.Interfaces.IQuestRepository:assert(repository, "QuestFactory")
    self.creators = {
        log = function(source) return self:createFromLogEntry(source) end,
        planned = function(source) return self:createPlanned(source) end,
    }
end

function QuestFactory:registerCreator(kind, creator)
    self.creators[kind] = creator
end

--- Factory method: create(kind, source) -> Quest
function QuestFactory:create(kind, source)
    local creator = self.creators[kind]
    if not creator then
        error("QuestFactory: unknown quest source kind '" .. tostring(kind) .. "'", 2)
    end
    return creator(source)
end

function QuestFactory:objectiveLocation(record, index)
    local data = record and record.objectives and record.objectives[index]
    if not data or not data.map then
        return nil
    end
    return ns.Location.new(data.map, data.x, data.y, data.text)
end

--- entry: plain table from WowApiAdapter:getQuestLogEntries(), optionally with
--- entry.poi = Location of the game's map marker for this quest.
function QuestFactory:createFromLogEntry(entry)
    local record = self.repository:getQuest(entry.questID)
    local objectives = {}
    for i = 1, #entry.objectives do
        local objective = entry.objectives[i]
        objectives[i] = ns.QuestObjective.new(objective.index, objective.text, objective.finished,
            self:objectiveLocation(record, objective.index))
    end

    local status
    if entry.isFailed then
        status = ns.QuestStatus.FAILED
    elseif entry.isComplete or #objectives == 0 then
        status = ns.QuestStatus.READY
    else
        local allDone = true
        for i = 1, #objectives do
            allDone = allDone and objectives[i].finished
        end
        status = allDone and ns.QuestStatus.READY or ns.QuestStatus.IN_PROGRESS
    end

    local giver = record and self.repository:getNpcLocation(record.giver) or nil
    local turnIn = record and self.repository:getNpcLocation(record.turnIn) or nil
    local locationSource = record and "database" or nil

    -- The database wins; the game's map marker fills what it does not know.
    local poi = entry.poi
    if poi then
        if status == ns.QuestStatus.READY then
            if not turnIn then
                turnIn = poi
                locationSource = locationSource or "game"
            end
        elseif status == ns.QuestStatus.IN_PROGRESS then
            for i = 1, #objectives do
                if not objectives[i].finished and not objectives[i].location then
                    objectives[i].location = poi
                    locationSource = locationSource or "game"
                end
            end
        end
    end

    return ns.Quest.new({
        id = entry.questID,
        title = entry.title or (record and record.title),
        level = entry.level or (record and record.level),
        status = status,
        objectives = objectives,
        giver = giver,
        turnIn = turnIn,
        known = record ~= nil,
        locationSource = locationSource,
    })
end

--- questID of a quest the player wants to pick up (must exist in the database).
function QuestFactory:createPlanned(questID)
    local record = self.repository:getQuest(questID)
    if not record then
        return nil
    end
    local objectives = {}
    for i = 1, #record.objectives do
        objectives[i] = ns.QuestObjective.new(i, record.objectives[i].text, false, self:objectiveLocation(record, i))
    end
    return ns.Quest.new({
        id = questID,
        title = record.title,
        level = record.level,
        status = ns.QuestStatus.PLANNED,
        objectives = objectives,
        giver = self.repository:getNpcLocation(record.giver),
        turnIn = self.repository:getNpcLocation(record.turnIn),
        known = true,
        locationSource = "database",
    })
end

ns.QuestFactory = QuestFactory
