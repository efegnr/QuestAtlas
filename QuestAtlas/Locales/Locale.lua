-- QuestAtlas - Locales/Locale.lua
-- Translation registry. Language files register a table of strings; get()
-- looks up the current language and falls back to English.
-- WoW has no Turkish client, so the language is an add-on setting
-- (/qa lang tr | en) instead of following GetLocale().
local _, ns = ...

local Locale = ns.Class("Locale")

Locale.FALLBACK = "enUS"

function Locale:init()
    self.tables = {}
    self.current = Locale.FALLBACK
end

function Locale:register(code, strings)
    self.tables[code] = strings
end

function Locale:setLanguage(code)
    if self.tables[code] then
        self.current = code
        return true
    end
    return false
end

function Locale:getLanguage()
    return self.current
end

function Locale:has(code, key)
    local strings = self.tables[code]
    return strings ~= nil and strings[key] ~= nil
end

--- Returns the translated text, formatted with string.format when arguments are given.
function Locale:get(key, ...)
    local strings = self.tables[self.current]
    local template = strings and strings[key]
    if template == nil then
        local fallback = self.tables[Locale.FALLBACK]
        template = fallback and fallback[key] or key
    end
    if select("#", ...) > 0 then
        return string.format(template, ...)
    end
    return template
end

-- One shared instance for the add-on (language files register into it).
ns.Locale = Locale.new()
ns.LocaleClass = Locale
