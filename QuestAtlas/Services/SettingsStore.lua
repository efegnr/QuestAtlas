-- QuestAtlas - Services/SettingsStore.lua
-- Wraps the SavedVariables table (QuestAtlasDB, declared in the .toc). WoW
-- writes it to disk on logout and restores it on the next login.
local _, ns = ...

local SettingsStore = ns.Class("SettingsStore")

SettingsStore.DEFAULTS = {
    version = 1,
    strategy = "atlas",   -- route strategy name (see RouteStrategyFactory)
    language = "trTR",    -- UI language: "trTR" or "enUS"
    shown = true,         -- tracker window visible
    planned = {},         -- quest IDs the player wants to pick up
    framePoint = nil,     -- { point, relativePoint, x, y }
    maxRouteLines = 10,   -- route steps shown in the window
}

--- env: table holding the SavedVariables global (defaults to _G)
function SettingsStore:init(savedVariableName, env)
    self.savedVariableName = savedVariableName
    self.env = env or _G
    self.data = nil
end

--- Must be called after ADDON_LOADED (that is when WoW restores the table).
function SettingsStore:load()
    local data = self.env[self.savedVariableName]
    if type(data) ~= "table" then
        data = {}
        self.env[self.savedVariableName] = data
    end
    for key, value in pairs(SettingsStore.DEFAULTS) do
        if data[key] == nil then
            data[key] = ns.Util.deepCopy(value)
        end
    end
    self.data = data
    return data
end

function SettingsStore:ensureLoaded()
    if not self.data then
        self:load()
    end
end

function SettingsStore:get(key)
    self:ensureLoaded()
    return self.data[key]
end

function SettingsStore:set(key, value)
    self:ensureLoaded()
    self.data[key] = value
end

ns.SettingsStore = SettingsStore
