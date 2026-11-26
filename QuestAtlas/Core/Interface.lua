-- QuestAtlas - Core/Interface.lua
-- Lua has no `interface` keyword. An Interface here is a named list of method
-- names; `assert` checks at wiring time that an object really implements it.
-- This makes the abstractions used for Dependency Inversion explicit
-- (SOLID - D) and keeps every interface small (SOLID - I).
local _, ns = ...

local Interface = {}
Interface.__index = Interface

local function newInterface(name, methods)
    return setmetatable({ name = name, methods = methods }, Interface)
end

--- Returns the list of missing methods (empty when `obj` implements the interface).
function Interface:missingMethods(obj)
    local missing = {}
    for i = 1, #self.methods do
        local method = self.methods[i]
        if type(obj) ~= "table" or type(obj[method]) ~= "function" then
            missing[#missing + 1] = method
        end
    end
    return missing
end

function Interface:isImplementedBy(obj)
    return #self:missingMethods(obj) == 0
end

--- Raises an error naming the missing methods; returns `obj` so it can be chained.
function Interface:assert(obj, context)
    local missing = self:missingMethods(obj)
    if #missing > 0 then
        error(string.format("%s: object does not implement %s (missing: %s)",
            context or "QuestAtlas", self.name, table.concat(missing, ", ")), 2)
    end
    return obj
end

ns.Interface = newInterface

-- All abstractions of the add-on in one place (handy for the class diagram).
ns.Interfaces = {
    -- Algorithm
    ICostPolicy         = newInterface("ICostPolicy", { "initial", "extend", "isBetter", "hasGain" }),
    -- Data access / game access
    IQuestRepository    = newInterface("IQuestRepository", { "getQuest", "getNpc", "getAllQuestIds", "findAvailable" }),
    IQuestSource        = newInterface("IQuestSource", { "readQuests" }),
    IQuestPoiProvider   = newInterface("IQuestPoiProvider", { "getQuestPois" }),
    IPositionProvider   = newInterface("IPositionProvider", { "getPlayerLocation" }),
    IMapGeometry        = newInterface("IMapGeometry", { "toWorld" }),
    IDistanceCalculator = newInterface("IDistanceCalculator", { "distance" }),
    ISettingsStore      = newInterface("ISettingsStore", { "get", "set" }),
    -- Routing
    IRouteStrategy      = newInterface("IRouteStrategy", { "getName", "plan" }),
    -- Commands (Chain of Responsibility)
    ICommandHandler     = newInterface("ICommandHandler", { "setNext", "handle" }),
    -- UI
    ITrackerView        = newInterface("ITrackerView", { "render", "show", "hide", "toggle", "isShown" }),
}
