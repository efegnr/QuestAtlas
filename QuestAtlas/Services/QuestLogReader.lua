-- QuestAtlas - Services/QuestLogReader.lua
-- IQuestSource implementation: reads the player's quest log through the API
-- adapter, attaches the game's map markers (IQuestPoiProvider) and turns
-- every entry into a Quest via the factory.
local _, ns = ...

local QuestLogReader = ns.Class("QuestLogReader")

--- poiProvider is optional (defaults to the Null Object: no markers).
function QuestLogReader:init(api, questFactory, poiProvider)
    self.api = api
    self.questFactory = questFactory
    self.poiProvider = ns.Interfaces.IQuestPoiProvider:assert(poiProvider or ns.NullQuestPoiProvider.new(),
        "QuestLogReader")
end

--- Returns a list of Quest objects (quest log order).
function QuestLogReader:readQuests()
    local entries = self.api:getQuestLogEntries()
    local ids = {}
    for i = 1, #entries do
        ids[i] = entries[i].questID
    end
    local pois = self.poiProvider:getQuestPois(ids)
    local quests = {}
    for i = 1, #entries do
        entries[i].poi = pois[entries[i].questID]
        quests[#quests + 1] = self.questFactory:create("log", entries[i])
    end
    return quests
end

ns.QuestLogReader = QuestLogReader
