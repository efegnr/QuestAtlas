-- QuestAtlas - Core/Util.lua
-- Small pure-Lua helpers. They do not depend on the WoW API, so they behave
-- identically in the game and in the offline test environment.
local _, ns = ...

local Util = {}

function Util.trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Splits "plan add 7" into "plan", "add 7" (command is lower-cased).
function Util.splitCommand(message)
    local text = Util.trim(message)
    local command, rest = text:match("^(%S+)%s*(.*)$")
    if not command then
        return "", ""
    end
    return command:lower(), rest
end

function Util.round(value, decimals)
    local factor = 10 ^ (decimals or 0)
    return math.floor(value * factor + 0.5) / factor
end

function Util.formatCoord(x, y)
    return string.format("%.1f, %.1f", x, y)
end

function Util.formatYards(value)
    if value >= 10000 then
        return string.format("%.1fk", value / 1000)
    end
    return string.format("%d", Util.round(value))
end

function Util.shallowCopy(source)
    local copy = {}
    for k, v in pairs(source) do
        copy[k] = v
    end
    return copy
end

function Util.deepCopy(source)
    if type(source) ~= "table" then
        return source
    end
    local copy = {}
    for k, v in pairs(source) do
        copy[Util.deepCopy(k)] = Util.deepCopy(v)
    end
    return copy
end

function Util.contains(list, value)
    for i = 1, #list do
        if list[i] == value then
            return true
        end
    end
    return false
end

function Util.removeValue(list, value)
    for i = #list, 1, -1 do
        if list[i] == value then
            table.remove(list, i)
        end
    end
end

function Util.map(list, fn)
    local result = {}
    for i = 1, #list do
        result[i] = fn(list[i], i)
    end
    return result
end

function Util.sortedKeys(tbl)
    local keys = {}
    for k in pairs(tbl) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then
            return a < b
        end
        return type(a) < type(b)
    end)
    return keys
end

--- Wraps text in a WoW colour escape sequence (|cffRRGGBB ... |r).
function Util.colorize(text, hexColor)
    if not hexColor then
        return text
    end
    return "|cff" .. hexColor .. text .. "|r"
end

ns.Util = Util
