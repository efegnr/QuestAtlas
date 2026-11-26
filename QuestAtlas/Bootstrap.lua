-- QuestAtlas - Bootstrap.lua
-- Composition root: the ONLY place that knows the concrete classes. It creates
-- every object, injects the dependencies (Dependency Injection, SOLID - D),
-- and connects the add-on to the game (events + slash commands).
local ADDON_NAME, ns = ...

local SAVED_VARIABLES = "QuestAtlasDB"
local REFRESH_DELAY = 0.3          -- seconds; QUEST_LOG_UPDATE fires in bursts
local POSITION_CHECK_INTERVAL = 3  -- seconds between "did the player move?" checks

--- Builds the whole object graph. `env` is the table holding the WoW API
--- (defaults to _G); tests pass the same mock environment.
function ns.CreateApp(env)
    env = env or _G
    local api = ns.WowApiAdapter.new(env)
    local settings = ns.SettingsStore.new(SAVED_VARIABLES, env)
    local eventBus = ns.EventBus.new()
    local locale = ns.Locale

    local repository = ns.QuestRepository.new(ns.QuestData)
    local questFactory = ns.QuestFactory.new(repository)
    local questSource = ns.QuestLogReader.new(api, questFactory, ns.GameQuestPoiProvider.new(api))
    local positionProvider = ns.PlayerPositionProvider.new(api)

    local geometry = ns.ChainedMapGeometry.new({
        ns.ApiMapGeometry.new(api),
        ns.StaticMapGeometry.new(ns.MapData),
    })
    local distanceCalculator = ns.DistanceCalculator.new(geometry)
    local strategyFactory = ns.RouteStrategyFactory.new(distanceCalculator)
    local planner = ns.RoutePlanner.new(ns.RouteTaskBuilder.new(), strategyFactory, function() return api:clockMs() end)

    local tracker = ns.QuestTracker.new({
        questSource = questSource,
        positionProvider = positionProvider,
        repository = repository,
        questFactory = questFactory,
        planner = planner,
        strategyFactory = strategyFactory,
        settings = settings,
        eventBus = eventBus,
        api = api,
        distanceCalculator = distanceCalculator,
    })

    local presenter = ns.TrackerPresenter.new(locale, function(mapID) return api:getMapName(mapID) end)
    local facade = ns.QuestAtlasFacade.new({
        tracker = tracker,
        settings = settings,
        api = api,
        locale = locale,
        strategyFactory = strategyFactory,
        presenter = presenter,
        eventBus = eventBus,
    })
    facade:setCommandChain(ns.CommandChainFactory.build())

    local app = { facade = facade, settings = settings, api = api, tracker = tracker }

    --- Called on ADDON_LOADED: SavedVariables are available from now on.
    function app.loadSettings()
        settings:load()
        if not strategyFactory:has(settings:get("strategy")) then
            settings:set("strategy", "atlas")
        end
        locale:setLanguage(settings:get("language"))
    end

    --- Called on PLAYER_LOGIN: build the UI and compute the first route.
    function app.start()
        local view = ns.TrackerFrame.new({
            widgetFactory = ns.WidgetFactory.new(api),
            settings = settings,
            locale = locale,
            onRefresh = function() facade:refresh("BUTTON") end,
            onCycleStrategy = function() facade:cycleStrategy() end,
        })
        view:build()
        facade:attachView(view)
        facade:refresh("LOGIN")
    end

    return app
end

----------------------------------------------------------------------------
-- Game wiring (runs when WoW loads the file)
----------------------------------------------------------------------------

local app = ns.CreateApp(_G)
ns.app = app
_G.QuestAtlas = app.facade -- public API for macros and other add-ons

local eventFrame = CreateFrame("Frame")
local refreshPending = false

local function scheduleRefresh(reason)
    if refreshPending then
        return
    end
    refreshPending = true
    app.api:after(REFRESH_DELAY, function()
        refreshPending = false
        app.facade:refresh(reason)
    end)
end

--- Registers an event; events that a client version does not know are skipped.
local function safeRegister(event)
    pcall(eventFrame.RegisterEvent, eventFrame, event)
end

local handlers = {}

function handlers.ADDON_LOADED(loadedName)
    if loadedName == ADDON_NAME then
        app.loadSettings()
        eventFrame:UnregisterEvent("ADDON_LOADED")
    end
end

function handlers.PLAYER_LOGIN()
    app.start()
    safeRegister("QUEST_LOG_UPDATE")
    safeRegister("QUEST_ACCEPTED")
    safeRegister("QUEST_TURNED_IN")
    safeRegister("QUEST_REMOVED")
    safeRegister("QUEST_POI_UPDATE")
    safeRegister("ZONE_CHANGED_NEW_AREA")
    safeRegister("PLAYER_ENTERING_WORLD")
    app.api:newTicker(POSITION_CHECK_INTERVAL, function()
        app.facade:refreshIfMoved()
    end)
end

function handlers.QUEST_LOG_UPDATE() scheduleRefresh("QUEST_LOG_UPDATE") end
function handlers.QUEST_ACCEPTED() scheduleRefresh("QUEST_ACCEPTED") end
function handlers.QUEST_TURNED_IN() scheduleRefresh("QUEST_TURNED_IN") end
function handlers.QUEST_REMOVED() scheduleRefresh("QUEST_REMOVED") end
function handlers.QUEST_POI_UPDATE() scheduleRefresh("QUEST_POI_UPDATE") end
function handlers.ZONE_CHANGED_NEW_AREA() scheduleRefresh("ZONE_CHANGED") end
function handlers.PLAYER_ENTERING_WORLD() scheduleRefresh("ENTERING_WORLD") end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then
        handler(...)
    end
end)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

SLASH_QUESTATLAS1 = "/questatlas"
SLASH_QUESTATLAS2 = "/qa"
SlashCmdList["QUESTATLAS"] = function(message)
    app.facade:handleSlashCommand(message)
end
