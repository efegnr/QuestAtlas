-- QuestAtlas - Services/MapGeometry.lua
-- IMapGeometry: toWorld(location) -> continentID, worldX, worldY (or nil)
-- Two implementations + a chain that tries them in order
-- (Chain of Responsibility): first the game API, then the static table.
local _, ns = ...

----------------------------------------------------------------------------
-- Uses the game's C_Map API through the adapter.
----------------------------------------------------------------------------
local ApiMapGeometry = ns.Class("ApiMapGeometry")

function ApiMapGeometry:init(api)
    self.api = api
end

function ApiMapGeometry:toWorld(location)
    return self.api:getWorldPosition(location.mapID, location.x, location.y)
end

----------------------------------------------------------------------------
-- Uses the approximate table in Data/MapData.lua.
----------------------------------------------------------------------------
local StaticMapGeometry = ns.Class("StaticMapGeometry")

function StaticMapGeometry:init(mapData)
    self.mapData = mapData or ns.MapData or {}
end

function StaticMapGeometry:toWorld(location)
    local map = self.mapData[location.mapID]
    if not map then
        return nil
    end
    local worldY = map.left - (location.x / 100) * map.width
    local worldX = map.top - (location.y / 100) * map.height
    return map.continent, worldX, worldY
end

----------------------------------------------------------------------------
-- Chain: asks each geometry until one knows the answer.
----------------------------------------------------------------------------
local ChainedMapGeometry = ns.Class("ChainedMapGeometry")

function ChainedMapGeometry:init(geometries)
    for i = 1, #geometries do
        ns.Interfaces.IMapGeometry:assert(geometries[i], "ChainedMapGeometry")
    end
    self.geometries = geometries
end

function ChainedMapGeometry:toWorld(location)
    for i = 1, #self.geometries do
        local continent, worldX, worldY = self.geometries[i]:toWorld(location)
        if continent ~= nil then
            return continent, worldX, worldY
        end
    end
    return nil
end

ns.ApiMapGeometry = ApiMapGeometry
ns.StaticMapGeometry = StaticMapGeometry
ns.ChainedMapGeometry = ChainedMapGeometry
