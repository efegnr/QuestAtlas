-- QuestAtlas - Domain/Location.lua
-- A point on a WoW map: uiMapID + x/y in map percent (0-100, like the
-- coordinates on Wowhead or in the world map), plus an optional label.
local _, ns = ...

local Location = ns.Class("Location")

function Location:init(mapID, x, y, label)
    assert(type(mapID) == "number", "Location: mapID must be a number")
    assert(type(x) == "number" and type(y) == "number", "Location: x and y must be numbers")
    self.mapID = mapID
    self.x = x
    self.y = y
    self.label = label
end

--- Identity used to merge equal places into one graph node.
function Location:key()
    return string.format("%d:%.1f:%.1f", self.mapID, self.x, self.y)
end

function Location:equals(other)
    return other ~= nil and self:key() == other:key()
end

function Location:withLabel(label)
    return Location.new(self.mapID, self.x, self.y, label)
end

function Location:describe()
    local coords = ns.Util.formatCoord(self.x, self.y)
    if self.label then
        return self.label .. " (" .. coords .. ")"
    end
    return "(" .. coords .. ")"
end

ns.Location = Location
