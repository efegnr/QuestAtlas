-- QuestAtlas - Services/PlayerPositionProvider.lua
-- IPositionProvider implementation: where is the player right now?
local _, ns = ...

local PlayerPositionProvider = ns.Class("PlayerPositionProvider")

function PlayerPositionProvider:init(api)
    self.api = api
end

--- Returns a Location or nil (inside instances the map position is unknown).
function PlayerPositionProvider:getPlayerLocation()
    local mapID, x, y = self.api:getPlayerMapPosition()
    if not mapID then
        return nil
    end
    return ns.Location.new(mapID, x, y)
end

ns.PlayerPositionProvider = PlayerPositionProvider
