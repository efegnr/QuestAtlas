-- tools/mock/MockWorldData.lua
-- "Server side" data of the simulated game world.
-- Quests 900001+ are FICTIONAL test quests for the retail flavor (titles start
-- with "Mock:"); they only exercise the retail map-marker API. It is deliberately separate
-- from the add-on's own database (QuestAtlas/Data/QuestData.lua): in the real
-- game the server knows every quest, while the add-on only knows the quests in
-- its database. Quest 90001 exists here but NOT in the add-on database, to
-- show how the tracker handles quests without location data.

return {
    -- uiMapID -> geometry (same meaning as QuestAtlas/Data/MapData.lua), parent = parent map
    -- (values of the retail maps 1409 / 84 / 13 are made up for the simulation)
    maps = {
        [1429] = { name = "Elwynn Forest",  continent = 0, width = 3470.83, height = 2314.58, left = 1535.42, top = -7939.58, parent = 1415 },
        [1453] = { name = "Stormwind City", continent = 0, width = 1737.50, height = 1158.33, left = 1722.92, top = -7995.83, parent = 1415 },
        [1436] = { name = "Westfall",       continent = 0, width = 3500.00, height = 2333.33, left = 3016.67, top = -9400.00, parent = 1415 },
        [1431] = { name = "Duskwood",       continent = 0, width = 2700.00, height = 1800.00, left = 833.33,  top = -9866.67, parent = 1415 },
        [1411] = { name = "Durotar",        continent = 1, width = 5287.50, height = 3525.00, left = -1962.50, top = 1808.33, parent = 1414 },
        -- retail
        [1409] = { name = "Exile's Reach",  continent = 2175, width = 2000.00, height = 1333.33, left = 800.00, top = 1200.00, parent = 0 },
        [84]   = { name = "Stormwind City", continent = 0, width = 1500.00, height = 1000.00, left = 1700.00, top = -8000.00, parent = 13 },
        [13]   = { name = "Eastern Kingdoms", continent = 0, width = 40000.00, height = 26666.67, left = 16000.00, top = 5000.00, parent = 0 },
    },

    -- questID -> what the quest log shows
    quests = {
        [783]  = { title = "A Threat Within", level = 1, zone = "Elwynn Forest", objectives = {} },
        [7]    = { title = "Kobold Camp Cleanup", level = 2, zone = "Elwynn Forest",
                   objectives = { { text = "Kobold Vermin slain", type = "monster", required = 10 } } },
        [33]   = { title = "Wolves Across the Border", level = 2, zone = "Elwynn Forest",
                   objectives = { { text = "Tough Wolf Meat", type = "item", required = 8 } } },
        [15]   = { title = "Investigate Echo Ridge", level = 4, zone = "Elwynn Forest",
                   objectives = { { text = "Kobold Worker slain", type = "monster", required = 10 } } },
        [18]   = { title = "Brotherhood of Thieves", level = 4, zone = "Elwynn Forest",
                   objectives = { { text = "Red Burlap Bandana", type = "item", required = 12 } } },
        [3904] = { title = "Milly's Harvest", level = 3, zone = "Elwynn Forest",
                   objectives = { { text = "Milly's Harvest", type = "item", required = 8 } } },
        [3905] = { title = "Grape Manifest", level = 4, zone = "Elwynn Forest", objectives = {} },
        [21]   = { title = "Skirmish at Echo Ridge", level = 5, zone = "Elwynn Forest",
                   objectives = { { text = "Kobold Laborer slain", type = "monster", required = 12 } } },
        [54]   = { title = "Report to Goldshire", level = 5, zone = "Elwynn Forest", objectives = {} },
        [62]   = { title = "The Fargodeep Mine", level = 7, zone = "Elwynn Forest",
                   objectives = { { text = "Scout through the Fargodeep Mine", type = "event", required = 1 } } },
        [47]   = { title = "Gold Dust Exchange", level = 7, zone = "Elwynn Forest",
                   objectives = { { text = "Gold Dust", type = "item", required = 10 } } },
        [60]   = { title = "Kobold Candles", level = 7, zone = "Elwynn Forest",
                   objectives = { { text = "Large Candle", type = "item", required = 8 } } },
        [76]   = { title = "The Jasperlode Mine", level = 10, zone = "Elwynn Forest",
                   objectives = { { text = "Scout through the Jasperlode Mine", type = "event", required = 1 } } },
        [88]   = { title = "Princess Must Die!", level = 9, zone = "Elwynn Forest",
                   objectives = { { text = "Brass Collar", type = "item", required = 1 } } },
        [106]  = { title = "Young Lovers", level = 9, zone = "Elwynn Forest", objectives = {} },
        [46]   = { title = "Bounty on Murlocs", level = 9, zone = "Elwynn Forest",
                   objectives = { { text = "Torn Murloc Fin", type = "item", required = 8 } } },
        [83]   = { title = "Red Linen Goods", level = 9, zone = "Elwynn Forest",
                   objectives = { { text = "Red Linen Bandana", type = "item", required = 6 } } },
        [90001] = { title = "A Mysterious Note", level = 5, zone = "Elwynn Forest",
                   objectives = { { text = "Find the author of the note", type = "event", required = 1 } } },

        -- Retail flavor (fictional). poi = where the game's map marker is:
        -- objective area while objectives are open, turn-in NPC afterwards.
        -- waypointOnly: not on the current map, only C_QuestLog.GetNextWaypoint knows it.
        [900001] = { title = "Mock: Survivors on the Beach", level = 1, zone = "Exile's Reach",
                     objectives = { { text = "Survivors found", type = "event", required = 3 } },
                     poi = { objective = { map = 1409, x = 60.0, y = 76.0 }, turnIn = { map = 1409, x = 62.0, y = 83.0 } } },
        [900002] = { title = "Mock: Salvage the Supplies", level = 1, zone = "Exile's Reach",
                     objectives = { { text = "Supply crate", type = "item", required = 5 } },
                     poi = { objective = { map = 1409, x = 54.0, y = 70.0 }, turnIn = { map = 1409, x = 62.0, y = 83.0 } } },
        [900003] = { title = "Mock: Harpy Hunt", level = 2, zone = "Exile's Reach",
                     objectives = { { text = "Harpy slain", type = "monster", required = 6 } },
                     poi = { objective = { map = 1409, x = 70.0, y = 62.0 }, turnIn = { map = 1409, x = 66.0, y = 70.0 } } },
        [900004] = { title = "Mock: Report to the Captain", level = 2, zone = "Exile's Reach", objectives = {},
                     poi = { turnIn = { map = 1409, x = 52.0, y = 51.0 } } },
        [900005] = { title = "Mock: Message in a Bottle", level = 2, zone = "Exile's Reach",
                     objectives = { { text = "Read the message", type = "event", required = 1 } } },
        [900006] = { title = "Mock: Sail to Stormwind", level = 3, zone = "Exile's Reach",
                     objectives = { { text = "Arrive in Stormwind", type = "event", required = 1 } },
                     poi = { objective = { map = 84, x = 50.0, y = 50.0 }, turnIn = { map = 84, x = 52.0, y = 60.0 },
                             waypointOnly = true } },
        [900007] = { title = "Mock: Bonus Objective", level = 2, zone = "Exile's Reach", isTask = true,
                     objectives = { { text = "Wildlife slain", type = "monster", required = 8 } },
                     poi = { objective = { map = 1409, x = 40.0, y = 40.0 } } },
    },
}
