-- QuestAtlas - Algorithm/CostPolicies.lua
-- Strategy pattern for the cost that ATLAS maximises while it extends the walk.
-- ICostPolicy:
--   initial()                   cost of the walk's first edge
--   extend(cost, edge, isNew)   cost after appending `edge`
--   isBetter(a, b)              true if cost a is strictly better than b (b may be nil)
--   hasGain(cost)               false once an extension covers nothing new
local _, ns = ...

----------------------------------------------------------------------------
-- UnitCostPolicy: the ORIGINAL ATLAS cost.
-- Java: new_cost = cost[edge] + (path.contains(neighbor) ? 0 : 1)
-- i.e. the number of not-yet-covered edges on the extension.
----------------------------------------------------------------------------
local UnitCostPolicy = ns.Class("UnitCostPolicy")

function UnitCostPolicy:getName()
    return "unit"
end

function UnitCostPolicy:initial()
    return 0
end

function UnitCostPolicy:extend(cost, _, isNew)
    return cost + (isNew and 1 or 0)
end

function UnitCostPolicy:isBetter(a, b)
    return b == nil or a > b
end

function UnitCostPolicy:hasGain(cost)
    return cost > 0
end

----------------------------------------------------------------------------
-- DistanceAwareCostPolicy: same primary goal as ATLAS (cover as many new
-- required edges as possible), but between two extensions that cover the same
-- number of new edges it prefers the one with the smaller total edge weight
-- (distance in yards for quest routes).
--
-- The pair (gain, distance) is compared lexicographically. It is stored as ONE
-- number, gain * SCALE - distance, so the inner loop of ATLAS allocates no
-- tables (important for the plain Lua 5.1 interpreter of the WoW client).
-- This is exact as long as a walk is shorter than SCALE (10^9 yards).
----------------------------------------------------------------------------
local DistanceAwareCostPolicy = ns.Class("DistanceAwareCostPolicy")

DistanceAwareCostPolicy.SCALE = 1e9
local SCALE = DistanceAwareCostPolicy.SCALE
local EPSILON = 1e-6

function DistanceAwareCostPolicy:getName()
    return "distance"
end

function DistanceAwareCostPolicy:initial()
    return 0
end

function DistanceAwareCostPolicy:extend(cost, edge, isNew)
    return cost + (isNew and SCALE or 0) - (edge.weight or 0)
end

function DistanceAwareCostPolicy:isBetter(a, b)
    return b == nil or a > b + EPSILON
end

function DistanceAwareCostPolicy:hasGain(cost)
    return cost > 0
end

--- Splits a packed cost back into (gain, distance) - for tests and debugging.
function DistanceAwareCostPolicy.unpack(cost)
    local gain = math.floor((cost + SCALE / 2) / SCALE)
    return gain, gain * SCALE - cost
end

----------------------------------------------------------------------------
-- Factory method: create a policy by name.
----------------------------------------------------------------------------
local CostPolicyFactory = {
    creators = {
        unit = function() return UnitCostPolicy.new() end,
        distance = function() return DistanceAwareCostPolicy.new() end,
    },
}

function CostPolicyFactory.create(name)
    local creator = CostPolicyFactory.creators[name]
    if not creator then
        error("Unknown cost policy: " .. tostring(name), 2)
    end
    return ns.Interfaces.ICostPolicy:assert(creator(), "CostPolicyFactory")
end

ns.UnitCostPolicy = UnitCostPolicy
ns.DistanceAwareCostPolicy = DistanceAwareCostPolicy
ns.CostPolicyFactory = CostPolicyFactory
