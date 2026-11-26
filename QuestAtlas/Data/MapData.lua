-- QuestAtlas - Data/MapData.lua
-- Fallback geometry of a few maps, used only when the game API
-- C_Map.GetWorldPosFromMapPos is not available.
--   width/height : size of the map in yards
--   left         : world Y coordinate of the map's left (west) edge
--   top          : world X coordinate of the map's top (north) edge
--   continent    : continent / instance id (0 = Eastern Kingdoms)
-- NOTE: values are APPROXIMATE (classic-era map sizes); with the real API the
-- add-on does not need this table at all.
local _, ns = ...

ns.MapData = {
    [1429] = { name = "Elwynn Forest",  continent = 0, width = 3470.83, height = 2314.58, left = 1535.42,  top = -7939.58 },
    [1453] = { name = "Stormwind City", continent = 0, width = 1737.50, height = 1158.33, left = 1722.92,  top = -7995.83 },
    [1436] = { name = "Westfall",       continent = 0, width = 3500.00, height = 2333.33, left = 3016.67,  top = -9400.00 },
    [1431] = { name = "Duskwood",       continent = 0, width = 2700.00, height = 1800.00, left = 833.33,   top = -9866.67 },
    [1433] = { name = "Redridge Mountains", continent = 0, width = 2170.83, height = 1447.92, left = -1570.83, top = -8575.00 },
}
