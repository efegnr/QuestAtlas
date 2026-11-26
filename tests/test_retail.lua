-- tests/test_retail.lua - retail client (12.1.5): quest map markers, map pins, /qa debug
return function(T, ctx)
    T.suite("Retail client (map markers from the game)")

    local Mock = ctx.Mock

    local function acceptAll(ids)
        for _, id in ipairs(ids) do
            Mock.acceptQuest(id)
        end
    end

    T.test("adapter: client info and API detection per flavor", function()
        local ns = ctx.loadAddon({ apiFlavor = "retail" })
        local api = ns.WowApiAdapter.new(_G)
        T.eq(api:getClientInfo().interface, 120105)
        T.eq(api:getClientInfo().version, "12.1.5")
        T.eq(api:getQuestApiFlavor(), "modern")
        T.eq(api:hasQuestPoiApi(), true)
        T.eq(api:hasWaypointApi(), true)
        ns = ctx.loadAddon({ apiFlavor = "classic" })
        api = ns.WowApiAdapter.new(_G)
        T.eq(api:getClientInfo().interface, 16001)
        T.eq(api:hasQuestPoiApi(), false)
        T.eq(api:hasWaypointApi(), false)
    end)

    T.test("adapter: markers from GetQuestsOnMap, GetNextWaypoint as fallback", function()
        local ns = ctx.loadAddon({ apiFlavor = "retail" })
        acceptAll({ 900001, 900005, 900006 })
        local api = ns.WowApiAdapter.new(_G)
        local pois = api:getQuestPoiLocations({ 900001, 900005, 900006 })
        T.deepEq(pois[900001], { mapID = 1409, x = 60, y = 76 }, "objective area on the current map")
        T.eq(pois[900005], nil, "quest without a marker")
        T.deepEq(pois[900006], { mapID = 84, x = 50, y = 50 }, "other zone: from GetNextWaypoint")
        Mock.completeObjectives(900001)
        T.deepEq(api:getQuestPoiLocations({ 900001 })[900001], { mapID = 1409, x = 62, y = 83 },
            "objectives done: the marker moves to the turn-in NPC")
    end)

    T.test("adapter: parent maps are searched (zone -> continent)", function()
        local ns = ctx.loadAddon({ apiFlavor = "retail", mapID = 84, x = 50, y = 50 })
        Mock.world().catalog[900099] = { title = "Mock: Continent marker", level = 3, zone = "Eastern Kingdoms",
            objectives = { { text = "Somewhere", type = "event", required = 1 } },
            poi = { objective = { map = 13, x = 40, y = 30 } } }
        Mock.acceptQuest(900099)
        _G.C_QuestLog.GetNextWaypoint = nil -- only the map search may find it
        local pois = ns.WowApiAdapter.new(_G):getQuestPoiLocations({ 900099 })
        T.deepEq(pois[900099], { mapID = 13, x = 40, y = 30 })
    end)

    T.test("adapter: a failing or changed marker API never breaks the add-on", function()
        local ns = ctx.loadAddon({ apiFlavor = "retail" })
        Mock.acceptQuest(900001)
        _G.C_QuestLog.GetQuestsOnMap = function() error("API changed") end
        _G.C_QuestLog.GetNextWaypoint = function() return "nonsense" end
        local pois = ns.WowApiAdapter.new(_G):getQuestPoiLocations({ 900001 })
        T.eq(next(pois), nil, "no markers, no error")
    end)

    T.test("adapter: bonus objectives (isTask) are not quests", function()
        local ns = ctx.loadAddon({ apiFlavor = "retail" })
        acceptAll({ 900001, 900007 })
        local entries = ns.WowApiAdapter.new(_G):getQuestLogEntries()
        T.eq(#entries, 1)
        T.eq(entries[1].questID, 900001)
    end)

    T.test("QuestFactory: the game's marker fills what the database does not know", function()
        local ns = ctx.loadAddon()
        local factory = ns.QuestFactory.new(ns.QuestRepository.new(ns.QuestData))
        local marker = ns.Location.new(1409, 60, 76)
        local open = factory:create("log", { questID = 900001, title = "T", level = 1, isComplete = false,
            objectives = { { index = 1, text = "o", finished = false } }, poi = marker })
        T.ok(open.objectives[1].location == marker, "objective at the marker")
        T.eq(open.turnIn, nil, "turn-in unknown until the objectives are done")
        T.eq(open.locationSource, "game")
        T.ok(open:isRoutable())
        local done = factory:create("log", { questID = 900001, title = "T", level = 1, isComplete = true,
            objectives = { { index = 1, text = "o", finished = true } }, poi = marker })
        T.ok(done.turnIn == marker, "ready: the marker is the turn-in NPC")
        local known = factory:create("log", { questID = 7, title = "Kobold Camp Cleanup", level = 2,
            isComplete = false, objectives = { { index = 1, text = "o", finished = false } }, poi = marker })
        T.eq(known.objectives[1].location.mapID, 1429, "database location wins over the marker")
        T.eq(known.turnIn.label, "Marshal McBride")
        T.eq(known.locationSource, "database")
    end)

    T.test("NullQuestPoiProvider is the default (Null Object)", function()
        local ns = ctx.loadAddon()
        T.ok(ns.Interfaces.IQuestPoiProvider:isImplementedBy(ns.NullQuestPoiProvider.new()))
        T.ok(ns.Interfaces.IQuestPoiProvider:isImplementedBy(ns.GameQuestPoiProvider.new(ns.WowApiAdapter.new(_G))))
        T.eq(next(ns.NullQuestPoiProvider.new():getQuestPois({ 1, 2 })), nil)
    end)

    T.test("Exile's Reach: quests unknown to the database are routed by the game's markers", function()
        ctx.startGame({ apiFlavor = "retail" })
        acceptAll({ 900001, 900002, 900003, 900004, 900005, 900006 })
        Mock.advanceTime(1)
        local box = Mock.renderFrame("QuestAtlasFrame", 100)
        T.contains(box, "Görevler (6)")
        T.contains(box, "Mock: Report to the Captain  (teslime hazır)")
        T.contains(box, "Konum verisi yok: Mock: Message in a Bottle")
        local route = _G.QuestAtlas:getRoute()
        T.eq(#route.taskOrder, 5, "every quest with a marker is on the route")
        local last = route.steps[#route.steps]
        T.eq(last.quests[1].id, 900006, "the other-continent quest comes last")
        T.contains(box, "Stormwind City: (50.0, 50.0) - başka kıta", "other map is named, no fake yards")
        T.contains(box, "(+1 uzak yolculuk)", "header counts the long trip separately")
        T.notContains(box, "k yd", "penalty distance never shown as yards")
        for _, step in ipairs(route.steps) do
            if step.quests[1].id ~= 900004 then
                T.eq(step.kind, "OBJECTIVE", "open quests: only their objective area is known")
            end
        end
    end)

    T.test("finishing objectives moves the quest to its turn-in NPC", function()
        ctx.startGame({ apiFlavor = "retail" })
        acceptAll({ 900001, 900003 })
        Mock.advanceTime(1)
        Mock.completeObjectives(900001)
        Mock.advanceTime(1)
        local found = false
        for _, step in ipairs(_G.QuestAtlas:getRoute().steps) do
            if step.quests[1].id == 900001 then
                T.eq(step.kind, "TURN_IN")
                T.near(step.location.x, 62, 1e-9)
                T.near(step.location.y, 83, 1e-9)
                found = true
            end
        end
        T.ok(found, "turn-in step present")
    end)

    T.test("progress only (3/10 -> 4/10) does not run ATLAS again", function()
        ctx.startGame({ apiFlavor = "retail" })
        acceptAll({ 900001, 900002, 900003 })
        Mock.advanceTime(1)
        local before = _G.QuestAtlas:getRoute()
        Mock.setObjectiveProgress(900002, 1, 2)
        Mock.advanceTime(1)
        T.ok(_G.QuestAtlas:getRoute() == before, "same route object")
        T.contains(Mock.renderFrame("QuestAtlasFrame", 100), "Mock: Salvage the Supplies  0/1 hedef", "window still refreshed")
        Mock.completeObjectives(900002)
        Mock.advanceTime(1)
        T.ok(_G.QuestAtlas:getRoute() ~= before, "a finished objective changes the route")
        local after = _G.QuestAtlas:getRoute()
        Mock.slash("/qa refresh")
        T.ok(_G.QuestAtlas:getRoute() ~= after, "a manual refresh always re-plans")
    end)

    T.test("/qa next puts a map pin on retail", function()
        ctx.startGame({ apiFlavor = "retail" })
        Mock.acceptQuest(900004)
        Mock.advanceTime(1)
        Mock.clearChat()
        Mock.slash("/qa next")
        T.contains(Mock.chatText(), "haritaya işaretlendi")
        T.eq(Mock.waypoint().uiMapID, 1409)
        T.near(Mock.waypoint().position.x, 0.52, 1e-9)
    end)

    T.test("/qa debug shows client, APIs, position and data sources", function()
        ctx.startGame({ apiFlavor = "retail" })
        acceptAll({ 900001, 900002, 900003, 900004, 900005, 900006 })
        Mock.advanceTime(1)
        Mock.clearChat()
        Mock.slash("/qa debug")
        local text = Mock.chatText()
        T.contains(text, "Tanılama")
        T.contains(text, "İstemci: 12.1.5 (build 70961), arayüz 120105")
        T.contains(text, "Görev API'si: modern, harita işaretleri: var, harita iğnesi: var")
        T.contains(text, "Konum: harita 1409 (Exile's Reach), 62.0, 84.0")
        T.contains(text, "Görevler: 6 (veritabanı: 0, oyun işareti: 5, konumsuz: 1)")
        T.contains(text, "Rota: atlas, ")

        ctx.startGame({ apiFlavor = "classic" })
        Mock.clearChat()
        Mock.slash("/qa debug")
        text = Mock.chatText()
        T.contains(text, "arayüz 16001")
        T.contains(text, "Görev API'si: classic, harita işaretleri: yok, harita iğnesi: yok")
    end)

    T.test("whole add-on in the retail client creates no unexpected globals", function()
        Mock.reset({ apiFlavor = "retail" })
        local before = Mock.globalsSnapshot()
        Mock.loadAddon(ctx.addonDir)
        Mock.login()
        Mock.acceptQuest(900001)
        Mock.advanceTime(5)
        T.deepEq(Mock.newGlobalsSince(before),
            { "QuestAtlas", "QuestAtlasDB", "QuestAtlasFrame", "SLASH_QUESTATLAS1", "SLASH_QUESTATLAS2" })
    end)
end
