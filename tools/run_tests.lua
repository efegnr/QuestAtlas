-- tools/run_tests.lua
-- Runs all tests:   luajit tools/run_tests.lua [filter]
-- (any Lua 5.1 compatible interpreter works: luajit, lua5.1)
local scriptDir = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local ROOT = scriptDir .. "/.."

local T = dofile(ROOT .. "/tools/lib/TinyTest.lua")
local ctx = dofile(ROOT .. "/tools/lib/TestContext.lua")(ROOT)

local TEST_FILES = {
    "test_core.lua",
    "test_atlas.lua",
    "test_services.lua",
    "test_routing.lua",
    "test_commands.lua",
    "test_integration.lua",
    "test_retail.lua",
}

for _, file in ipairs(TEST_FILES) do
    dofile(ROOT .. "/tests/" .. file)(T, ctx)
end

local _, failed = T.run(arg and arg[1])
if os.exit and arg then
    os.exit(failed == 0 and 0 or 1)
end
return failed
