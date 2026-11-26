-- tools/mock/WowMock.lua
-- A small simulation of the World of Warcraft client, so the REAL add-on code
-- (QuestAtlas/*.lua, loaded through QuestAtlas.toc exactly like the game does)
-- can run on a normal computer without the game.
--
-- What it provides
--   * The WoW API the add-on uses: CreateFrame (frames, buttons, font strings),
--     events, slash commands, SavedVariables, C_Timer, C_Map, quest log
--     functions (classic GetQuestLogTitle API *and* the newer C_QuestLog API),
--     UnitLevel / UnitFactionGroup, DEFAULT_CHAT_FRAME, ...
--   * Three client flavors (Mock.reset{ apiFlavor = ... }):
--       "classic" - WoW: Forever / Classic style API (default)
--       "modern"  - C_QuestLog API, no quest map markers
--       "retail"  - C_QuestLog API + quest map markers (GetQuestsOnMap,
--                   GetNextWaypoint) + map pins, client 12.1.5, player
--                   starts on Exile's Reach
--   * A simulated world: the player's position, the quest log, completed
--     quests. Helper functions change it and fire the same events the game
--     would fire (Mock.acceptQuest, Mock.turnInQuest, Mock.movePlayer, ...).
--   * Inspection: Mock.renderFrame() draws a window as text, Mock.chatLines()
--     returns what was printed to the chat.
--
-- It is strict where mistakes would also break the real client: unknown
-- events, frame templates, fonts, anchor points or script handlers raise
-- errors, and calling a method a frame does not have fails like in the game.
local Mock = {}

local MOCK_DIR = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
local WorldData = dofile(MOCK_DIR .. "MockWorldData.lua")

Mock.KNOWN_EVENTS = {
    ADDON_LOADED = true, PLAYER_LOGIN = true, PLAYER_LOGOUT = true, PLAYER_ENTERING_WORLD = true,
    QUEST_LOG_UPDATE = true, QUEST_ACCEPTED = true, QUEST_TURNED_IN = true, QUEST_REMOVED = true,
    QUEST_COMPLETE = true, UNIT_QUEST_LOG_CHANGED = true, PLAYER_LEVEL_UP = true, QUEST_POI_UPDATE = true,
    ZONE_CHANGED = true, ZONE_CHANGED_NEW_AREA = true, ZONE_CHANGED_INDOORS = true,
}
local KNOWN_SCRIPTS = {
    OnEvent = true, OnClick = true, OnDragStart = true, OnDragStop = true, OnShow = true, OnHide = true,
    OnUpdate = true, OnEnter = true, OnLeave = true, OnMouseDown = true, OnMouseUp = true,
}
local KNOWN_FONTS = {
    GameFontNormal = true, GameFontNormalSmall = true, GameFontNormalLarge = true, GameFontHighlight = true,
    GameFontHighlightSmall = true, GameFontHighlightLarge = true, GameFontDisable = true, GameFontDisableSmall = true,
}
local KNOWN_TEMPLATES = { BackdropTemplate = true, UIPanelButtonTemplate = true, UIPanelCloseButton = true }
local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local world, client -- world survives /reload, client does not
local baselineGlobals = nil

----------------------------------------------------------------------------
-- Utilities
----------------------------------------------------------------------------

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[deepCopy(k)] = deepCopy(v)
    end
    return copy
end

function Mock.stripColors(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function utf8len(text)
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end

local function vector2D(x, y)
    return setmetatable({ x = x, y = y }, { __index = { GetXY = function(self) return self.x, self.y end } })
end

----------------------------------------------------------------------------
-- Widgets: Region -> FontString / Texture, Region -> Frame -> Button
----------------------------------------------------------------------------

local Region = {}

function Region:GetName() return self._name end
function Region:GetParent() return self._parent end
function Region:SetParent(parent) self._parent = parent end
function Region:SetSize(width, height) self._width, self._height = width, height end
function Region:SetWidth(width) self._width = width end
function Region:SetHeight(height) self._height = height end
function Region:GetWidth() return self._width or 0 end
function Region:GetHeight() return self._height or 0 end
function Region:SetAlpha(alpha) self._alpha = alpha end
function Region:GetAlpha() return self._alpha or 1 end

function Region:SetPoint(point, relativeTo, relativePoint, x, y)
    if not ANCHORS[point] then
        error("WoW mock: invalid anchor point '" .. tostring(point) .. "'", 2)
    end
    if type(relativeTo) == "number" then -- SetPoint("TOPLEFT", 10, -10)
        relativeTo, relativePoint, x, y = nil, point, relativeTo, relativePoint
    end
    if relativePoint ~= nil and not ANCHORS[relativePoint] then
        error("WoW mock: invalid relative point '" .. tostring(relativePoint) .. "'", 2)
    end
    self._points[#self._points + 1] = { point, relativeTo or self._parent, relativePoint or point, x or 0, y or 0 }
end

function Region:ClearAllPoints() self._points = {} end
function Region:SetAllPoints(target) self._points = { { "TOPLEFT", target or self._parent, "TOPLEFT", 0, 0 } } end

function Region:GetPoint(index)
    local p = self._points[index or 1]
    if p then
        return p[1], p[2], p[3], p[4], p[5]
    end
end

function Region:Show()
    local was = self._shown
    self._shown = true
    if not was and self._scripts and self._scripts.OnShow then
        self._scripts.OnShow(self)
    end
end

function Region:Hide()
    local was = self._shown
    self._shown = false
    if was and self._scripts and self._scripts.OnHide then
        self._scripts.OnHide(self)
    end
end

function Region:SetShown(shown)
    if shown then self:Show() else self:Hide() end
end

function Region:IsShown() return self._shown end

function Region:IsVisible()
    if not self._shown then
        return false
    end
    local parent = self._parent
    if parent and parent.IsVisible then
        return parent:IsVisible()
    end
    return true
end

local function extend(base, extra)
    local methods = {}
    for k, v in pairs(base) do methods[k] = v end
    for k, v in pairs(extra or {}) do methods[k] = v end
    return methods
end

-- FontString -------------------------------------------------------------
local FontStringMethods = extend(Region, {
    SetText = function(self, text) self._text = text and tostring(text) or "" end,
    GetText = function(self) return self._text end,
    SetJustifyH = function(self, value) self._justifyH = value end,
    SetJustifyV = function(self, value) self._justifyV = value end,
    SetTextColor = function(self, r, g, b, a) self._color = { r, g, b, a } end,
    SetFont = function(self, path, size, flags)
        assert(type(path) == "string" and type(size) == "number", "WoW mock: SetFont(path, size, flags)")
        self._font = { path, size, flags }
        return true
    end,
    GetFont = function(self) local f = self._font or {} return f[1], f[2], f[3] end,
    SetFontObject = function(self, font) self._fontObject = font end,
    SetWordWrap = function(self, wrap) self._wordWrap = wrap end,
    SetNonSpaceWrap = function(self, wrap) self._nonSpaceWrap = wrap end,
    GetStringWidth = function(self) return utf8len(Mock.stripColors(self._text or "")) * 6 end,
})
local FontStringMeta = { __index = FontStringMethods }

-- Texture ----------------------------------------------------------------
local TextureMethods = extend(Region, {
    SetTexture = function(self, texture) self._texture = texture end,
    SetColorTexture = function(self, r, g, b, a) self._texture = { r, g, b, a } end,
    SetVertexColor = function(self, r, g, b, a) self._vertexColor = { r, g, b, a } end,
    SetTexCoord = function() end,
})
local TextureMeta = { __index = TextureMethods }

-- Frame ------------------------------------------------------------------
local FrameMethods = extend(Region, {})

function FrameMethods:SetScript(scriptName, handler)
    if not KNOWN_SCRIPTS[scriptName] then
        error("WoW mock: unknown script handler '" .. tostring(scriptName) .. "'", 2)
    end
    self._scripts[scriptName] = handler
end

function FrameMethods:GetScript(scriptName) return self._scripts[scriptName] end

function FrameMethods:HookScript(scriptName, handler)
    local previous = self._scripts[scriptName]
    self._scripts[scriptName] = function(...)
        if previous then previous(...) end
        handler(...)
    end
end

function FrameMethods:RegisterEvent(event)
    if not Mock.KNOWN_EVENTS[event] then
        error("Attempt to register unknown event \"" .. tostring(event) .. "\"", 2)
    end
    self._events[event] = true
end

function FrameMethods:UnregisterEvent(event) self._events[event] = nil end
function FrameMethods:UnregisterAllEvents() self._events = {} end
function FrameMethods:IsEventRegistered(event) return self._events[event] == true end

function FrameMethods:CreateFontString(name, layer, inherits)
    if inherits ~= nil and not KNOWN_FONTS[inherits] then
        error("WoW mock: unknown font object '" .. tostring(inherits) .. "'", 2)
    end
    local fontString = setmetatable({
        _name = name, _parent = self, _shown = true, _points = {}, _text = nil, _layer = layer, _fontObject = inherits,
    }, FontStringMeta)
    self._regions[#self._regions + 1] = fontString
    if name then
        _G[name] = fontString
    end
    return fontString
end

function FrameMethods:CreateTexture(name, layer)
    local texture = setmetatable({ _name = name, _parent = self, _shown = true, _points = {}, _layer = layer }, TextureMeta)
    self._regions[#self._regions + 1] = texture
    return texture
end

function FrameMethods:SetMovable(value) self._movable = value end
function FrameMethods:EnableMouse(value) self._mouse = value end
function FrameMethods:RegisterForDrag(...) self._dragButtons = { ... } end
function FrameMethods:SetClampedToScreen(value) self._clamped = value end
function FrameMethods:SetFrameStrata(value) self._strata = value end
function FrameMethods:SetFrameLevel(value) self._level = value end
function FrameMethods:SetUserPlaced(value) self._userPlaced = value end
function FrameMethods:SetToplevel(value) self._toplevel = value end

function FrameMethods:StartMoving()
    assert(self._movable, "WoW mock: StartMoving on a frame that is not movable")
    self._moving = true
end

function FrameMethods:StopMovingOrSizing()
    if self._moving then
        self._moving = false
        local target = client.dropPosition or { 100, 600 }
        self._points = { { "TOPLEFT", _G.UIParent, "BOTTOMLEFT", target[1], target[2] } }
    end
end

local BackdropMethods = {
    SetBackdrop = function(self, backdrop) self._backdrop = backdrop end,
    SetBackdropColor = function(self, ...) self._backdropColor = { ... } end,
    SetBackdropBorderColor = function(self, ...) self._backdropBorderColor = { ... } end,
}

local ButtonMethods = {
    SetText = function(self, text) self._text = text end,
    GetText = function(self) return self._text end,
    Enable = function(self) self._enabled = true end,
    Disable = function(self) self._enabled = false end,
    IsEnabled = function(self) return self._enabled ~= false end,
    RegisterForClicks = function() end,
    Click = function(self, button)
        if self._enabled ~= false and self._scripts.OnClick then
            self._scripts.OnClick(self, button or "LeftButton", false)
        end
    end,
}

local metaCache = {}
local function frameMeta(frameType, templates)
    local key = frameType .. "|" .. table.concat(templates, ",")
    if not metaCache[key] then
        local methods = extend(FrameMethods, frameType == "Button" and ButtonMethods or nil)
        for i = 1, #templates do
            if templates[i] == "BackdropTemplate" then
                methods = extend(methods, BackdropMethods)
            end
        end
        metaCache[key] = { __index = methods }
    end
    return metaCache[key]
end

local function createFrame(frameType, name, parent, template)
    if frameType ~= "Frame" and frameType ~= "Button" then
        error("WoW mock: unsupported frame type '" .. tostring(frameType) .. "'", 2)
    end
    local templates = {}
    if template then
        for t in tostring(template):gmatch("[^,%s]+") do
            if not KNOWN_TEMPLATES[t] then
                error("WoW mock: unknown template '" .. t .. "'", 2)
            end
            templates[#templates + 1] = t
        end
    end
    local frame = setmetatable({
        _type = frameType, _name = name, _parent = parent, _templates = templates, _shown = true,
        _points = {}, _scripts = {}, _events = {}, _regions = {}, _children = {},
    }, frameMeta(frameType, templates))
    if parent and parent._children then
        parent._children[#parent._children + 1] = frame
    end
    if client then
        client.frames[#client.frames + 1] = frame
    end
    if name then
        _G[name] = frame
    end
    for i = 1, #templates do
        if templates[i] == "UIPanelCloseButton" then
            frame._text = "X"
            frame._scripts.OnClick = function(self) if self._parent then self._parent:Hide() end end
        end
    end
    return frame
end

----------------------------------------------------------------------------
-- Quest log view (headers + quests, like the in-game quest log)
----------------------------------------------------------------------------

local function questDefinition(questID)
    local definition = world.catalog[questID]
    if not definition then
        error("WoW mock: quest " .. tostring(questID) .. " does not exist in MockWorldData", 3)
    end
    return definition
end

local function findLogEntry(questID)
    for i = 1, #world.questLog do
        if world.questLog[i].questID == questID then
            return world.questLog[i], i
        end
    end
end

local function logView()
    local view, zones, byZone = {}, {}, {}
    for i = 1, #world.questLog do
        local entry = world.questLog[i]
        local zone = questDefinition(entry.questID).zone or "Misc"
        if not byZone[zone] then
            byZone[zone] = {}
            zones[#zones + 1] = zone
        end
        local list = byZone[zone]
        list[#list + 1] = entry
    end
    for _, zone in ipairs(zones) do
        view[#view + 1] = { header = zone }
        for _, entry in ipairs(byZone[zone]) do
            view[#view + 1] = { entry = entry }
        end
    end
    return view
end

local function objectiveState(entry, index)
    local definition = questDefinition(entry.questID).objectives[index]
    local current = entry.progress[index] or 0
    local text = string.format("%s: %d/%d", definition.text, current, definition.required)
    return text, definition.type, current >= definition.required, current, definition.required
end

local function isEntryComplete(entry)
    local objectives = questDefinition(entry.questID).objectives
    if #objectives == 0 then
        return false -- "talk to" quests: the client does not flag them complete
    end
    for i = 1, #objectives do
        local _, _, finished = objectiveState(entry, i)
        if not finished then
            return false
        end
    end
    return true
end

--- Where the game draws the quest's marker right now (retail): the objective
--- area while objectives are open, the turn-in NPC afterwards.
--- Returns position {map, x, y}, waypointOnly
local function currentPoi(entry)
    local definition = questDefinition(entry.questID)
    local poi = definition.poi
    if not poi then
        return nil
    end
    local done = #definition.objectives == 0 or isEntryComplete(entry)
    return done and poi.turnIn or poi.objective, poi.waypointOnly == true
end

----------------------------------------------------------------------------
-- API installation
----------------------------------------------------------------------------

local function installApi()
    local G = _G

    G.UIParent = createFrame("Frame", "UIParent")
    G.UIParent._width, G.UIParent._height = 1920, 1080
    G.BackdropTemplateMixin = {}
    G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, text) client.chat[#client.chat + 1] = tostring(text) end,
    }
    G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring((select(i, ...)))
        end
        client.chat[#client.chat + 1] = table.concat(parts, " ")
    end
    G.CreateFrame = createFrame
    G.SlashCmdList = {}
    G.CreateVector2D = vector2D

    -- WoW's Lua helpers (not used by QuestAtlas, provided for completeness)
    G.tinsert, G.tremove, G.format = table.insert, table.remove, string.format
    G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

    -- Time
    G.GetTime = function() return world.time end
    G.debugprofilestop = function() return os.clock() * 1000 end
    G.C_Timer = {
        After = function(seconds, callback)
            client.timers[#client.timers + 1] = { due = world.time + seconds, callback = callback }
        end,
        NewTicker = function(seconds, callback, iterations)
            local ticker = { due = world.time + seconds, interval = seconds, callback = callback, remaining = iterations }
            ticker.Cancel = function(self) self.cancelled = true end
            ticker.IsCancelled = function(self) return self.cancelled == true end
            client.timers[#client.timers + 1] = ticker
            return ticker
        end,
    }

    -- Client / unit info
    G.GetLocale = function() return world.locale end
    G.GetBuildInfo = function()
        if world.options.apiFlavor == "retail" then
            return "12.1.5", "70961", "Nov 2026", 120105
        end
        return "1.60.1", "99999", "Nov 4 2026", 16001
    end
    G.UnitName = function(unit) if unit == "player" then return world.player.name end end
    G.UnitLevel = function(unit) if unit == "player" then return world.player.level end return 0 end
    G.UnitFactionGroup = function(unit)
        if unit == "player" then return world.player.faction, world.player.faction end
    end

    -- Map
    G.C_Map = {
        GetBestMapForUnit = function(unit)
            if unit == "player" and not world.player.inInstance then
                return world.player.mapID
            end
        end,
        GetPlayerMapPosition = function(mapID, unit)
            local p = world.player
            if unit == "player" and not p.inInstance and mapID == p.mapID then
                return vector2D(p.x / 100, p.y / 100)
            end
        end,
        GetWorldPosFromMapPos = function(mapID, position)
            local map = world.maps[mapID]
            if not map then
                return nil
            end
            local x, y = position:GetXY()
            return map.continent, vector2D(map.top - y * map.height, map.left - x * map.width)
        end,
        GetMapInfo = function(mapID)
            local map = world.maps[mapID]
            if map then
                return { mapID = mapID, name = map.name, mapType = 3, parentMapID = map.parent or 0 }
            end
        end,
    }
    if world.options.waypoints then
        G.UiMapPoint = {
            CreateFromCoordinates = function(mapID, x, y) return { uiMapID = mapID, position = vector2D(x, y) } end,
        }
        G.C_Map.SetUserWaypoint = function(point) client.waypoint = point end
        G.C_SuperTrack = { SetSuperTrackedUserWaypoint = function(value) client.superTracked = value end }
    end

    -- Quest log ------------------------------------------------------------
    local function numQuests()
        return #world.questLog
    end

    if world.options.apiFlavor == "modern" or world.options.apiFlavor == "retail" then
        G.C_QuestLog = {
            GetNumQuestLogEntries = function() return #logView(), numQuests() end,
            GetInfo = function(index)
                local row = logView()[index]
                if not row then return nil end
                if row.header then
                    return { title = row.header, isHeader = true, isHidden = false, isCollapsed = false }
                end
                local definition = questDefinition(row.entry.questID)
                return { title = definition.title, level = definition.level, isHeader = false, isHidden = false,
                    questID = row.entry.questID, isCollapsed = false, frequency = 0, isTask = definition.isTask == true }
            end,
            IsComplete = function(questID)
                local entry = findLogEntry(questID)
                return entry ~= nil and isEntryComplete(entry)
            end,
            IsFailed = function(questID)
                local entry = findLogEntry(questID)
                return entry ~= nil and entry.failed == true
            end,
            GetQuestObjectives = function(questID)
                local entry = findLogEntry(questID)
                if not entry then return {} end
                local list = {}
                for i = 1, #questDefinition(questID).objectives do
                    local text, objectiveType, finished, current, required = objectiveState(entry, i)
                    list[i] = { text = text, type = objectiveType, finished = finished,
                        numFulfilled = current, numRequired = required }
                end
                return list
            end,
            IsQuestFlaggedCompleted = function(questID) return world.completed[questID] == true end,
        }
        if world.options.apiFlavor == "retail" then
            -- Quest markers on the world map (objective area, or turn-in NPC when done).
            G.C_QuestLog.GetQuestsOnMap = function(mapID)
                local list = {}
                for _, entry in ipairs(world.questLog) do
                    local position, waypointOnly = currentPoi(entry)
                    if position and not waypointOnly and position.map == mapID then
                        list[#list + 1] = { questID = entry.questID, x = position.x / 100, y = position.y / 100,
                            type = 0, isMapIndicatorQuest = false }
                    end
                end
                return list
            end
            G.C_QuestLog.GetNextWaypoint = function(questID)
                local entry = findLogEntry(questID)
                local position = entry and currentPoi(entry)
                if position then
                    return position.map, position.x / 100, position.y / 100
                end
            end
        end
    else
        G.GetNumQuestLogEntries = function() return #logView(), numQuests() end
        G.GetQuestLogTitle = function(index)
            local row = logView()[index]
            if not row then return nil end
            if row.header then
                return row.header, nil, nil, true, false, nil, nil, nil
            end
            local entry = row.entry
            local definition = questDefinition(entry.questID)
            local isComplete = nil
            if entry.failed then
                isComplete = -1
            elseif isEntryComplete(entry) then
                isComplete = 1
            end
            return definition.title, definition.level, 0, false, false, isComplete, 1, entry.questID
        end
        G.GetNumQuestLeaderBoards = function(index)
            local row = logView()[index]
            if not row or row.header then return 0 end
            return #questDefinition(row.entry.questID).objectives
        end
        G.GetQuestLogLeaderBoard = function(objectiveIndex, index)
            local row = logView()[index]
            if not row or row.header then return nil end
            local text, objectiveType, finished = objectiveState(row.entry, objectiveIndex)
            return text, objectiveType, finished
        end
        G.C_QuestLog = {
            IsQuestFlaggedCompleted = function(questID) return world.completed[questID] == true end,
        }
    end
end

----------------------------------------------------------------------------
-- Life cycle
----------------------------------------------------------------------------

--- Removes everything the mock or the add-on put into _G and restores the
--- standard Lua globals the mock overrides (e.g. print).
local function clearGlobals()
    if not baselineGlobals then
        baselineGlobals = {}
        for k, v in pairs(_G) do
            baselineGlobals[k] = v
        end
    end
    for k in pairs(_G) do
        if baselineGlobals[k] == nil then
            _G[k] = nil
        end
    end
    for k, v in pairs(baselineGlobals) do
        if _G[k] ~= v then
            _G[k] = v
        end
    end
end

local function newClient()
    client = { frames = {}, timers = {}, chat = {}, waypoint = nil, addon = nil, dropPosition = nil }
end

--- Starts a fresh simulated game.
--- options: apiFlavor ("classic" | "modern" | "retail"), waypoints (bool; retail: on),
---          level, faction, locale, mapID / x / y (start position)
function Mock.reset(options)
    options = options or {}
    clearGlobals()
    local flavor = options.apiFlavor or "classic"
    local retail = flavor == "retail"
    local waypoints = options.waypoints
    if waypoints == nil then
        waypoints = retail
    end
    world = {
        options = { apiFlavor = flavor, waypoints = waypoints == true },
        player = { name = "Mockadin", level = options.level or 1, faction = options.faction or "Alliance",
            mapID = options.mapID or (retail and 1409 or 1429),
            x = options.x or (retail and 62.0 or 48.0),
            y = options.y or (retail and 84.0 or 43.0),
            inInstance = false },
        questLog = {},
        completed = {},
        time = 0,
        locale = options.locale or "enUS",
        maps = deepCopy(WorldData.maps),       -- copies: tests may change them
        catalog = deepCopy(WorldData.quests),
        savedVariables = {},
    }
    newClient()
    installApi()
end

--- Returns a set of the current global names (to detect leaked globals).
function Mock.globalsSnapshot()
    local set = {}
    for k in pairs(_G) do
        set[k] = true
    end
    return set
end

function Mock.newGlobalsSince(snapshot)
    local list = {}
    for k in pairs(_G) do
        if not snapshot[k] then
            list[#list + 1] = tostring(k)
        end
    end
    table.sort(list)
    return list
end

----------------------------------------------------------------------------
-- Add-on loading
----------------------------------------------------------------------------

--- Parses a .toc file. Returns metadata, files (paths with '/').
function Mock.parseToc(tocPath)
    local metadata, files = {}, {}
    local handle = assert(io.open(tocPath, "r"), "cannot open " .. tocPath)
    for line in handle:lines() do
        line = line:gsub("\r$", "")
        local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
        if key then
            metadata[key] = value
        elseif not line:match("^%s*#") and line:match("%S") then
            files[#files + 1] = (line:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\\", "/"))
        end
    end
    handle:close()
    return metadata, files
end

--- Loads an add-on folder like the client: every file of the .toc in order,
--- each called with (addonName, privateNamespace). Then restores
--- SavedVariables and fires ADDON_LOADED.
function Mock.loadAddon(addonDir)
    addonDir = addonDir:gsub("[/\\]$", "")
    local addonName = addonDir:match("([^/\\]+)$")
    local metadata, files = Mock.parseToc(addonDir .. "/" .. addonName .. ".toc")
    local namespace = {}
    for i = 1, #files do
        local chunk, err = loadfile(addonDir .. "/" .. files[i])
        if not chunk then
            error("WoW mock: failed to load " .. files[i] .. ": " .. tostring(err), 2)
        end
        chunk(addonName, namespace)
    end
    local savedNames = {}
    for name in (metadata.SavedVariables or ""):gmatch("[^,%s]+") do
        savedNames[#savedNames + 1] = name
        _G[name] = deepCopy(world.savedVariables[name]) -- nil on the first login
    end
    client.addon = { dir = addonDir, name = addonName, savedVariables = savedNames, namespace = namespace,
        metadata = metadata, files = files }
    Mock.fireEvent("ADDON_LOADED", addonName, false)
    return namespace, metadata, files
end

function Mock.login()
    Mock.fireEvent("PLAYER_LOGIN")
    Mock.fireEvent("PLAYER_ENTERING_WORLD", true, false)
end

--- Like logging out: the client writes SavedVariables to disk.
function Mock.logout()
    Mock.fireEvent("PLAYER_LOGOUT")
    if client.addon then
        for _, name in ipairs(client.addon.savedVariables) do
            world.savedVariables[name] = deepCopy(_G[name])
        end
    end
end

--- /reload: SavedVariables are saved, the UI is torn down and the add-on is
--- loaded again. The world (quest log, position) stays the same.
function Mock.reloadUI()
    assert(client.addon, "WoW mock: no add-on loaded")
    local dir = client.addon.dir
    Mock.logout()
    clearGlobals()
    newClient()
    installApi()
    local namespace = Mock.loadAddon(dir)
    Mock.login()
    return namespace
end

----------------------------------------------------------------------------
-- Events, time, slash commands
----------------------------------------------------------------------------

function Mock.fireEvent(event, ...)
    assert(Mock.KNOWN_EVENTS[event], "WoW mock: unknown event " .. tostring(event))
    local frames = {}
    for i = 1, #client.frames do
        frames[i] = client.frames[i]
    end
    for i = 1, #frames do
        local frame = frames[i]
        if frame._events[event] and frame._scripts.OnEvent then
            frame._scripts.OnEvent(frame, event, ...)
        end
    end
end

--- Advances the clock and runs due C_Timer callbacks / tickers in order.
function Mock.advanceTime(seconds)
    local target = world.time + seconds
    while true do
        local nextIndex, nextTimer = nil, nil
        for i = 1, #client.timers do
            local timer = client.timers[i]
            if not timer.cancelled and timer.due <= target and (not nextTimer or timer.due < nextTimer.due) then
                nextIndex, nextTimer = i, timer
            end
        end
        if not nextTimer then
            break
        end
        world.time = nextTimer.due
        if nextTimer.interval then
            nextTimer.due = nextTimer.due + nextTimer.interval
            if nextTimer.remaining then
                nextTimer.remaining = nextTimer.remaining - 1
                if nextTimer.remaining <= 0 then
                    nextTimer.cancelled = true
                end
            end
        else
            table.remove(client.timers, nextIndex)
        end
        nextTimer.callback(nextTimer)
    end
    world.time = target
end

--- Runs a slash command line such as "/qa route". Returns true if found.
function Mock.slash(line)
    local command, rest = line:match("^(/%S+)%s*(.-)%s*$")
    assert(command, "WoW mock: not a slash command: " .. tostring(line))
    for key, handler in pairs(_G.SlashCmdList) do
        local i = 1
        while _G["SLASH_" .. key .. i] do
            if _G["SLASH_" .. key .. i]:lower() == command:lower() then
                handler(rest, nil)
                return true
            end
            i = i + 1
        end
    end
    client.chat[#client.chat + 1] = "Type '/help' for a listing of a few commands."
    return false
end

----------------------------------------------------------------------------
-- World simulation (fires the events the real game would fire)
----------------------------------------------------------------------------

function Mock.acceptQuest(questID)
    local definition = questDefinition(questID)
    assert(not findLogEntry(questID), "WoW mock: quest already in the log")
    local progress = {}
    for i = 1, #definition.objectives do
        progress[i] = 0
    end
    world.questLog[#world.questLog + 1] = { questID = questID, progress = progress, failed = false }
    Mock.fireEvent("QUEST_ACCEPTED", #world.questLog, questID)
    Mock.fireEvent("QUEST_LOG_UPDATE")
end

function Mock.setObjectiveProgress(questID, objectiveIndex, value)
    local entry = assert(findLogEntry(questID), "WoW mock: quest not in the log")
    local definition = questDefinition(questID).objectives[objectiveIndex]
    assert(definition, "WoW mock: no such objective")
    entry.progress[objectiveIndex] = math.max(0, math.min(value, definition.required))
    Mock.fireEvent("QUEST_LOG_UPDATE")
end

function Mock.completeObjectives(questID)
    local entry = assert(findLogEntry(questID), "WoW mock: quest not in the log")
    local objectives = questDefinition(questID).objectives
    for i = 1, #objectives do
        entry.progress[i] = objectives[i].required
    end
    Mock.fireEvent("QUEST_LOG_UPDATE")
end

function Mock.failQuest(questID)
    local entry = assert(findLogEntry(questID), "WoW mock: quest not in the log")
    entry.failed = true
    Mock.fireEvent("QUEST_LOG_UPDATE")
end

function Mock.turnInQuest(questID)
    local entry, index = findLogEntry(questID)
    assert(entry, "WoW mock: quest not in the log")
    local objectives = questDefinition(questID).objectives
    assert(#objectives == 0 or isEntryComplete(entry), "WoW mock: objectives of quest " .. questID .. " not done")
    table.remove(world.questLog, index)
    world.completed[questID] = true
    Mock.fireEvent("QUEST_TURNED_IN", questID, 100, 0)
    Mock.fireEvent("QUEST_REMOVED", questID)
    Mock.fireEvent("QUEST_LOG_UPDATE")
end

function Mock.abandonQuest(questID)
    local _, index = findLogEntry(questID)
    assert(index, "WoW mock: quest not in the log")
    table.remove(world.questLog, index)
    Mock.fireEvent("QUEST_REMOVED", questID)
    Mock.fireEvent("QUEST_LOG_UPDATE")
end

--- Marks a quest as completed in the past (no events, like a fresh login).
function Mock.setQuestCompleted(questID)
    world.completed[questID] = true
end

function Mock.movePlayer(mapID, x, y)
    local changed = mapID ~= world.player.mapID
    world.player.mapID, world.player.x, world.player.y = mapID, x, y
    if changed then
        Mock.fireEvent("ZONE_CHANGED_NEW_AREA")
    end
end

function Mock.setInInstance(value)
    world.player.inInstance = value and true or false
    Mock.fireEvent("ZONE_CHANGED_NEW_AREA")
end

function Mock.setPlayerLevel(level)
    world.player.level = level
    Mock.fireEvent("PLAYER_LEVEL_UP", level)
end

----------------------------------------------------------------------------
-- Inspection
----------------------------------------------------------------------------

function Mock.world() return world end
function Mock.client() return client end
function Mock.chatLines() return client.chat end
function Mock.clearChat() client.chat = {} end

function Mock.chatText()
    local lines = {}
    for i = 1, #client.chat do
        lines[i] = Mock.stripColors(client.chat[i])
    end
    return table.concat(lines, "\n")
end

function Mock.waypoint() return client.waypoint end

--- Clicks the button with the given text inside `frame`.
function Mock.clickButton(frame, text)
    for _, child in ipairs(frame._children) do
        if child._type == "Button" and child._text == text and child:IsVisible() then
            child:Click("LeftButton")
            return true
        end
    end
    error("WoW mock: no visible button '" .. tostring(text) .. "'")
end

--- Simulates dragging a frame and dropping it at (x, y).
function Mock.dragFrame(frame, x, y)
    client.dropPosition = { x, y }
    frame._scripts.OnDragStart(frame, "LeftButton")
    frame._scripts.OnDragStop(frame)
end

--- Visible text of a frame (font strings in creation order + buttons).
function Mock.frameTexts(frame)
    local texts = {}
    if not frame:IsVisible() then
        return texts
    end
    for _, region in ipairs(frame._regions) do
        if region._text ~= nil and region:IsShown() and region._text ~= "" then
            texts[#texts + 1] = Mock.stripColors(region._text)
        end
    end
    return texts
end

--- Draws a frame as an ASCII box (for the demo and for debugging).
function Mock.renderFrame(frame, width)
    width = width or 78
    if type(frame) == "string" then
        frame = _G[frame]
    end
    if not frame then
        return "(frame does not exist)"
    end
    if not frame:IsVisible() then
        return "(window hidden)"
    end
    local out = { "+" .. string.rep("-", width - 2) .. "+" }
    local function row(text)
        local length = utf8len(text)
        if length > width - 4 then
            -- cut on a character boundary
            local cut, count = 0, 0
            for position = 1, #text do
                local byte = text:byte(position)
                if byte < 128 or byte >= 192 then
                    count = count + 1
                    if count > width - 7 then break end
                end
                cut = position
            end
            text = text:sub(1, cut) .. "..."
            length = utf8len(text)
        end
        out[#out + 1] = "| " .. text .. string.rep(" ", width - 4 - length) .. " |"
    end
    for _, text in ipairs(Mock.frameTexts(frame)) do
        row(text)
    end
    local buttons = {}
    for _, child in ipairs(frame._children) do
        if child._type == "Button" and child:IsShown() then
            buttons[#buttons + 1] = "[" .. tostring(child._text) .. "]"
        end
    end
    if #buttons > 0 then
        row(table.concat(buttons, " "))
    end
    out[#out + 1] = "+" .. string.rep("-", width - 2) .. "+"
    return table.concat(out, "\n")
end

return Mock
