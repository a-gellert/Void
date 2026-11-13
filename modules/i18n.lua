-- Localization. String tables live in data/lang/<code>.lua (en is the fallback).
-- Font glyphs: ASCII, Cyrillic, PT/TR diacritics and the symbols ° × • → — only.
local M = {}

M.LANGUAGES = { "en", "ru", "pt", "tr" }

local STRINGS = {
    en = require("data.lang.en"),
    ru = require("data.lang.ru"),
    pt = require("data.lang.pt"),
    tr = require("data.lang.tr"),
}

local current_lang = "en"

function M.detect_default()
    local info = sys.get_sys_info()
    local lang = string.lower(string.sub(info.language or "en", 1, 2))
    current_lang = STRINGS[lang] and lang or "en"
    return current_lang
end

function M.set_language(lang)
    if STRINGS[lang] then current_lang = lang end
end

function M.get_language()
    return current_lang
end

function M.cycle_language()
    for i, l in ipairs(M.LANGUAGES) do
        if l == current_lang then
            current_lang = M.LANGUAGES[(i % #M.LANGUAGES) + 1]
            return current_lang
        end
    end
    current_lang = "en"
    return current_lang
end

function M.has(key)
    return STRINGS.en[key] ~= nil
end

function M.t(key)
    local dict = STRINGS[current_lang] or STRINGS.en
    return dict[key] or STRINGS.en[key] or key
end

return M
