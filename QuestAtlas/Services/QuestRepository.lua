-- QuestAtlas - Services/QuestRepository.lua
-- Repository pattern: read-only access to the quest database
-- (Data/QuestData.lua). Callers never touch the raw tables directly, so the
-- data source can be replaced (e.g. a bigger generated database) without
-- changing them.
local _, ns = ...

local QuestRepository = ns.Class("QuestRepository")

function QuestRepository:init(questData)
    self.data = questData or ns.QuestData
    assert(self.data and self.data.quests and self.data.npcs, "QuestRepository: invalid quest data")
end

function QuestRepository:getQuest(questID)
    return self.data.quests[questID]
end

function QuestRepository:getNpc(npcKey)
    return npcKey and self.data.npcs[npcKey] or nil
end

--- Location of an NPC (with the NPC's name as label) or nil.
function QuestRepository:getNpcLocation(npcKey)
    local npc = self:getNpc(npcKey)
    if not npc then
        return nil
    end
    return ns.Location.new(npc.map, npc.x, npc.y, npc.name)
end

function QuestRepository:getAllQuestIds()
    return ns.Util.sortedKeys(self.data.quests)
end

--- Quests the player could pick up right now.
---   player      : { level, faction }
---   isCompleted : function(questID) -> bool
---   inLog       : set { [questID] = true }
function QuestRepository:findAvailable(player, isCompleted, inLog)
    local result = {}
    local ids = self:getAllQuestIds()
    for i = 1, #ids do
        local id = ids[i]
        local quest = self.data.quests[id]
        local factionOk = quest.faction == nil or player.faction == nil or quest.faction == player.faction
        local levelOk = (quest.minLevel or 1) <= (player.level or 1)
        local prerequisiteOk = quest.prerequisite == nil or isCompleted(quest.prerequisite)
        if factionOk and levelOk and prerequisiteOk and not inLog[id] and not isCompleted(id) then
            result[#result + 1] = id
        end
    end
    return result
end

ns.QuestRepository = QuestRepository
