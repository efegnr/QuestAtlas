-- QuestAtlas - Routing/RouteStrategyFactory.lua
-- Factory Method pattern: creates route strategies by name. A new algorithm is
-- added with register() - no existing class has to change (SOLID - O).
local _, ns = ...

local RouteStrategyFactory = ns.Class("RouteStrategyFactory")

function RouteStrategyFactory:init(distanceCalculator)
    self.distanceCalculator = distanceCalculator
    self.creators = {}
    self.order = {}
    self:register("atlas", function(calc) return ns.AtlasRouteStrategy.new(calc) end)
    self:register("nearest", function(calc) return ns.NearestNeighborRouteStrategy.new(calc) end)
    self:register("bruteforce", function(calc) return ns.BruteForceRouteStrategy.new(calc) end)
end

function RouteStrategyFactory:register(name, creator)
    if not self.creators[name] then
        self.order[#self.order + 1] = name
    end
    self.creators[name] = creator
end

function RouteStrategyFactory:has(name)
    return self.creators[name] ~= nil
end

--- Factory method: returns a new IRouteStrategy.
function RouteStrategyFactory:create(name)
    local creator = self.creators[name]
    if not creator then
        error("RouteStrategyFactory: unknown strategy '" .. tostring(name) .. "'", 2)
    end
    return ns.Interfaces.IRouteStrategy:assert(creator(self.distanceCalculator), "RouteStrategyFactory")
end

--- Names in registration order (used to cycle through strategies in the UI).
function RouteStrategyFactory:getNames()
    return ns.Util.shallowCopy(self.order)
end

function RouteStrategyFactory:nextName(current)
    for i = 1, #self.order do
        if self.order[i] == current then
            return self.order[i % #self.order + 1]
        end
    end
    return self.order[1]
end

ns.RouteStrategyFactory = RouteStrategyFactory
