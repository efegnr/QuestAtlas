-- QuestAtlas - Data/QuestData.lua
-- The quest database (like Questie's, but tiny). The game API tells the add-on
-- WHICH quests are in the log and how far they are; it does not tell WHERE
-- the objectives and quest NPCs are. That information lives here.
--
-- SAMPLE DATA: Alliance quests of Elwynn Forest (uiMapID 1429), based on the
-- original 2004 game. Quest IDs follow the classic client; coordinates are
-- APPROXIMATE map percentages. WoW: Forever may differ - add or correct
-- entries in the same format.
--
-- quests[questID] = {
--     title, level, minLevel, faction ("Alliance" / "Horde" / nil = both),
--     prerequisite = questID or nil,
--     giver = npcKey, turnIn = npcKey,
--     objectives = { { text, map, x, y }, ... }   -- same order as in the quest log
-- }
local _, ns = ...

local ELWYNN = 1429

ns.QuestData = {
    npcs = {
        DEPUTY_WILLEM        = { name = "Deputy Willem",        map = ELWYNN, x = 48.2, y = 42.9 },
        MARSHAL_MCBRIDE      = { name = "Marshal McBride",      map = ELWYNN, x = 48.9, y = 41.6 },
        EAGAN_PELTSKINNER    = { name = "Eagan Peltskinner",    map = ELWYNN, x = 48.9, y = 40.2 },
        MILLY_OSWORTH        = { name = "Milly Osworth",        map = ELWYNN, x = 50.7, y = 39.2 },
        BROTHER_NEALS        = { name = "Brother Neals",        map = ELWYNN, x = 49.5, y = 41.6 },
        MARSHAL_DUGHAN       = { name = "Marshal Dughan",       map = ELWYNN, x = 42.1, y = 65.9 },
        REMY_TWO_TIMES       = { name = "Remy \"Two Times\"",   map = ELWYNN, x = 42.1, y = 67.3 },
        WILLIAM_PESTLE       = { name = "William Pestle",       map = ELWYNN, x = 43.3, y = 65.7 },
        MA_STONEFIELD        = { name = "Ma Stonefield",        map = ELWYNN, x = 34.5, y = 84.3 },
        TOMMY_JOE_STONEFIELD = { name = "Tommy Joe Stonefield", map = ELWYNN, x = 29.8, y = 86.0 },
        MAYBELL_MACLURE      = { name = "Maybell Maclure",      map = ELWYNN, x = 43.1, y = 89.6 },
        GUARD_THOMAS         = { name = "Guard Thomas",         map = ELWYNN, x = 74.0, y = 72.2 },
        SARA_TIMBERLAIN      = { name = "Sara Timberlain",      map = ELWYNN, x = 79.5, y = 68.7 },
    },

    quests = {
        -- Northshire Valley ---------------------------------------------------
        [783] = { title = "A Threat Within", level = 1, minLevel = 1, faction = "Alliance",
            giver = "DEPUTY_WILLEM", turnIn = "MARSHAL_MCBRIDE", objectives = {} },
        [7] = { title = "Kobold Camp Cleanup", level = 2, minLevel = 1, faction = "Alliance", prerequisite = 783,
            giver = "MARSHAL_MCBRIDE", turnIn = "MARSHAL_MCBRIDE",
            objectives = { { text = "Kobold Vermin", map = ELWYNN, x = 47.4, y = 34.6 } } },
        [33] = { title = "Wolves Across the Border", level = 2, minLevel = 1, faction = "Alliance",
            giver = "EAGAN_PELTSKINNER", turnIn = "EAGAN_PELTSKINNER",
            objectives = { { text = "Tough Wolf Meat", map = ELWYNN, x = 45.6, y = 37.8 } } },
        [15] = { title = "Investigate Echo Ridge", level = 4, minLevel = 2, faction = "Alliance", prerequisite = 7,
            giver = "MARSHAL_MCBRIDE", turnIn = "MARSHAL_MCBRIDE",
            objectives = { { text = "Kobold Worker", map = ELWYNN, x = 48.0, y = 30.9 } } },
        [18] = { title = "Brotherhood of Thieves", level = 4, minLevel = 2, faction = "Alliance",
            giver = "DEPUTY_WILLEM", turnIn = "DEPUTY_WILLEM",
            objectives = { { text = "Red Burlap Bandana", map = ELWYNN, x = 54.7, y = 46.3 } } },
        [3904] = { title = "Milly's Harvest", level = 3, minLevel = 2, faction = "Alliance",
            giver = "MILLY_OSWORTH", turnIn = "MILLY_OSWORTH",
            objectives = { { text = "Milly's Harvest", map = ELWYNN, x = 55.6, y = 48.2 } } },
        [3905] = { title = "Grape Manifest", level = 4, minLevel = 2, faction = "Alliance", prerequisite = 3904,
            giver = "MILLY_OSWORTH", turnIn = "BROTHER_NEALS", objectives = {} },
        [21] = { title = "Skirmish at Echo Ridge", level = 5, minLevel = 3, faction = "Alliance", prerequisite = 15,
            giver = "MARSHAL_MCBRIDE", turnIn = "MARSHAL_MCBRIDE",
            objectives = { { text = "Kobold Laborer", map = ELWYNN, x = 47.9, y = 27.4 } } },
        [54] = { title = "Report to Goldshire", level = 5, minLevel = 4, faction = "Alliance",
            giver = "MARSHAL_MCBRIDE", turnIn = "MARSHAL_DUGHAN", objectives = {} },

        -- Goldshire and the south ----------------------------------------------
        [62] = { title = "The Fargodeep Mine", level = 7, minLevel = 5, faction = "Alliance",
            giver = "MARSHAL_DUGHAN", turnIn = "MARSHAL_DUGHAN",
            objectives = { { text = "Scout through the Fargodeep Mine", map = ELWYNN, x = 39.5, y = 81.3 } } },
        [47] = { title = "Gold Dust Exchange", level = 7, minLevel = 4, faction = "Alliance",
            giver = "REMY_TWO_TIMES", turnIn = "REMY_TWO_TIMES",
            objectives = { { text = "Gold Dust", map = ELWYNN, x = 39.6, y = 80.6 } } },
        [60] = { title = "Kobold Candles", level = 7, minLevel = 4, faction = "Alliance",
            giver = "WILLIAM_PESTLE", turnIn = "WILLIAM_PESTLE",
            objectives = { { text = "Large Candle", map = ELWYNN, x = 40.6, y = 79.4 } } },
        [76] = { title = "The Jasperlode Mine", level = 10, minLevel = 6, faction = "Alliance",
            giver = "MARSHAL_DUGHAN", turnIn = "MARSHAL_DUGHAN",
            objectives = { { text = "Scout through the Jasperlode Mine", map = ELWYNN, x = 61.0, y = 53.8 } } },
        [88] = { title = "Princess Must Die!", level = 9, minLevel = 7, faction = "Alliance",
            giver = "MA_STONEFIELD", turnIn = "MA_STONEFIELD",
            objectives = { { text = "Brass Collar", map = ELWYNN, x = 69.5, y = 79.3 } } },
        [106] = { title = "Young Lovers", level = 9, minLevel = 7, faction = "Alliance",
            giver = "MAYBELL_MACLURE", turnIn = "TOMMY_JOE_STONEFIELD", objectives = {} },
        [46] = { title = "Bounty on Murlocs", level = 9, minLevel = 6, faction = "Alliance",
            giver = "GUARD_THOMAS", turnIn = "GUARD_THOMAS",
            objectives = { { text = "Torn Murloc Fin", map = ELWYNN, x = 76.0, y = 60.6 } } },
        [83] = { title = "Red Linen Goods", level = 9, minLevel = 6, faction = "Alliance",
            giver = "SARA_TIMBERLAIN", turnIn = "SARA_TIMBERLAIN",
            objectives = { { text = "Red Linen Bandana", map = ELWYNN, x = 71.0, y = 79.0 } } },
    },
}
