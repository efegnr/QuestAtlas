-- QuestAtlas - Services/DistanceCalculator.lua
-- IDistanceCalculator: distance(locationA, locationB) -> yards.
-- Straight-line distance in world coordinates. Places on different continents
-- (or with unknown geometry) get a large penalty so routes stay on one
-- continent where possible.
local _, ns = ...

local DistanceCalculator = ns.Class("DistanceCalculator")

DistanceCalculator.CROSS_CONTINENT_PENALTY = 100000
DistanceCalculator.UNKNOWN_PENALTY = 50000

function DistanceCalculator:init(geometry)
    self.geometry = ns.Interfaces.IMapGeometry:assert(geometry, "DistanceCalculator")
    self.cache = {}
end

function DistanceCalculator:worldPosition(location)
    local key = location:key()
    local cached = self.cache[key]
    if cached == nil then
        local continent, worldX, worldY = self.geometry:toWorld(location)
        cached = continent ~= nil and { continent = continent, x = worldX, y = worldY } or false
        self.cache[key] = cached
    end
    return cached or nil
end

function DistanceCalculator:distance(a, b)
    if a:key() == b:key() then
        return 0
    end
    local pa, pb = self:worldPosition(a), self:worldPosition(b)
    if not pa or not pb then
        return DistanceCalculator.UNKNOWN_PENALTY
    end
    if pa.continent ~= pb.continent then
        return DistanceCalculator.CROSS_CONTINENT_PENALTY
    end
    local dx, dy = pa.x - pb.x, pa.y - pb.y
    return math.sqrt(dx * dx + dy * dy)
end

function DistanceCalculator:clearCache()
    self.cache = {}
end

ns.DistanceCalculator = DistanceCalculator
