-- tools/lib/TinyTest.lua
-- A minimal unit test framework (no external dependencies, Lua 5.1).
local T = { tests = {}, currentSuite = "" }

-- Keep the real print: the WoW mock replaces the global one with the chat.
local print = print

function T.suite(name)
    T.currentSuite = name
end

function T.test(name, fn)
    T.tests[#T.tests + 1] = { suite = T.currentSuite, name = name, fn = fn }
end

----------------------------------------------------------------------------
-- Assertions
----------------------------------------------------------------------------

local function fail(message, level)
    error(message, (level or 1) + 2)
end

local function describe(value)
    if type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end

function T.ok(condition, message)
    if not condition then
        fail(message or "expected a truthy value")
    end
end

function T.eq(actual, expected, message)
    if actual ~= expected then
        fail((message and (message .. ": ") or "") .. "expected " .. describe(expected) .. ", got " .. describe(actual))
    end
end

function T.near(actual, expected, epsilon, message)
    if type(actual) ~= "number" or math.abs(actual - expected) > (epsilon or 1e-6) then
        fail((message and (message .. ": ") or "") .. "expected ~" .. describe(expected) .. ", got " .. describe(actual))
    end
end

local function deepEqual(a, b)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not deepEqual(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function serialize(value)
    if type(value) ~= "table" then
        return describe(value)
    end
    local parts = {}
    for i = 1, #value do
        parts[#parts + 1] = serialize(value[i])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function T.deepEq(actual, expected, message)
    if not deepEqual(actual, expected) then
        fail((message and (message .. ": ") or "") .. "expected " .. serialize(expected) .. ", got " .. serialize(actual))
    end
end

function T.contains(text, fragment, message)
    if type(text) ~= "string" or not text:find(fragment, 1, true) then
        fail((message and (message .. ": ") or "") .. "expected text to contain " .. describe(fragment)
            .. "\n--- text ---\n" .. tostring(text))
    end
end

function T.notContains(text, fragment, message)
    if type(text) == "string" and text:find(fragment, 1, true) then
        fail((message and (message .. ": ") or "") .. "text must not contain " .. describe(fragment)
            .. "\n--- text ---\n" .. tostring(text))
    end
end

function T.raises(fn, pattern, message)
    local ok, err = pcall(fn)
    if ok then
        fail(message or "expected an error")
    end
    if pattern and not tostring(err):find(pattern, 1, true) then
        fail((message and (message .. ": ") or "") .. "error " .. describe(tostring(err))
            .. " does not contain " .. describe(pattern))
    end
end

----------------------------------------------------------------------------
-- Runner
----------------------------------------------------------------------------

--- Runs all registered tests (optionally only those whose name contains `filter`).
--- Returns passed, failed.
function T.run(filter)
    local passed, failed, failures = 0, 0, {}
    local lastSuite = nil
    for _, test in ipairs(T.tests) do
        local fullName = test.suite .. " > " .. test.name
        if not filter or fullName:lower():find(filter:lower(), 1, true) then
            if test.suite ~= lastSuite then
                print("\n" .. test.suite)
                lastSuite = test.suite
            end
            local ok, err = xpcall(test.fn, debug.traceback)
            if ok then
                passed = passed + 1
                print("  [OK]   " .. test.name)
            else
                failed = failed + 1
                failures[#failures + 1] = { name = fullName, err = err }
                print("  [FAIL] " .. test.name)
            end
        end
    end
    for _, failure in ipairs(failures) do
        print("\nFAILED: " .. failure.name .. "\n" .. tostring(failure.err))
    end
    print(string.format("\n%d passed, %d failed (%s)", passed, failed, _VERSION))
    return passed, failed
end

return T
