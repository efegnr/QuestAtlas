-- QuestAtlas - Services/QuestPoiProvider.lua
-- IQuestPoiProvider: getQuestPois(questIDs) -> { [questID] = Location }
-- "POI" = point of interest: the quest marker the game draws on the map
-- (objective area of an unfinished quest, turn-in NPC of a finished one).
--
--   GameQuestPoiProvider : asks the client (retail API) through the adapter.
--   NullQuestPoiProvider : Null Object - "no markers". Used where the client
--                          has no such API (classic / Forever without it), so
--                          callers never need an `if provider then` check.
local _, ns = ...

----------------------------------------------------------------------------
local GameQuestPoiProvider = ns.Class("GameQuestPoiProvider")

function GameQuestPoiProvider:init(api)
    self.api = api
end

function GameQuestPoiProvider:getQuestPois(questIDs)
    local raw = self.api:getQuestPoiLocations(questIDs)
    local result = {}
    for questID, poi in pairs(raw) do
        result[questID] = ns.Location.new(poi.mapID, poi.x, poi.y)
    end
    return result
end

----------------------------------------------------------------------------
local NullQuestPoiProvider = ns.Class("NullQuestPoiProvider")

function NullQuestPoiProvider:getQuestPois()
    return {}
end

ns.GameQuestPoiProvider = GameQuestPoiProvider
ns.NullQuestPoiProvider = NullQuestPoiProvider
