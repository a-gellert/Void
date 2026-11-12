local ships_db = require("data.ships_db")
local i18n = require("modules.i18n")

local M = {}

local SAVE_APP = "void_clash_3d"
local SAVE_FILE = "save_v1"

local state = nil

local function default_state()
    return {
        credits = 200,
        parts = 2,
        selected_class = "interceptor",
        upgrades = {
            interceptor = { hull = 1, weapon = 1, shield = 1, engine = 1 },
            fighter = { hull = 1, weapon = 1, shield = 1, engine = 1 },
            frigate = { hull = 1, weapon = 1, shield = 1, engine = 1 },
        },
        unlocked_skins = { [1] = true, [2] = true, [3] = true },
        unlocked_trails = { [1] = true, [2] = true, [3] = true },
        equipped_skin = 1,
        equipped_trail = 1,
        match_count = 0,
        first_battle_done = false,
        test_drive_active = false,
        language = i18n.detect_default(),
        muted = false,
    }
end

function M.load()
    local path = sys.get_save_file(SAVE_APP, SAVE_FILE)
    local loaded = sys.load(path)
    state = default_state()
    if type(loaded) == "table" then
        for k, v in pairs(loaded) do
            if state[k] ~= nil then
                state[k] = v
            end
        end
    end
    i18n.set_language(state.language or "en")
    return state
end

function M.save()
    if not state then return end
    local path = sys.get_save_file(SAVE_APP, SAVE_FILE)
    sys.save(path, state)
end

function M.get()
    if not state then M.load() end
    return state
end

function M.get_player_upgrades(class_id)
    local s = M.get()
    local cid = class_id or s.selected_class
    local u = s.upgrades[cid] or { hull = 1, weapon = 1, shield = 1, engine = 1 }
    if s.test_drive_active and cid == s.selected_class then
        return {
            hull = math.min(5, u.hull + 1),
            weapon = math.min(5, u.weapon + 1),
            shield = math.min(5, u.shield + 1),
            engine = math.min(5, u.engine + 1),
        }
    end
    return u
end

function M.get_average_player_tier()
    local s = M.get()
    local u = s.upgrades[s.selected_class] or { hull = 1, weapon = 1, shield = 1, engine = 1 }
    return math.max(1, math.min(5, math.floor((u.hull + u.weapon + u.shield + u.engine) / 4 + 0.5)))
end

function M.can_upgrade(class_id, node_key)
    local s = M.get()
    local u = s.upgrades[class_id]
    if not u then return false, 0 end
    local lv = u[node_key] or 1
    if lv >= 5 then return false, 0 end
    local cost = ships_db.UPGRADE_COSTS.credits[lv + 1] or 9999
    return s.credits >= cost, cost
end

function M.upgrade_node(class_id, node_key)
    local ok, cost = M.can_upgrade(class_id, node_key)
    if not ok then return false end
    state.credits = state.credits - cost
    state.upgrades[class_id][node_key] = state.upgrades[class_id][node_key] + 1
    M.save()
    return true
end

function M.unlock_random_cosmetic()
    local s = M.get()
    local locked_skins = {}
    for i = 1, #ships_db.SKINS do
        if not s.unlocked_skins[i] then
            locked_skins[#locked_skins + 1] = i
        end
    end
    local locked_trails = {}
    for i = 1, #ships_db.TRAILS do
        if not s.unlocked_trails[i] then
            locked_trails[#locked_trails + 1] = i
        end
    end
    if #locked_skins > 0 and (#locked_trails == 0 or math.random() < 0.65) then
        local pick = locked_skins[math.random(#locked_skins)]
        s.unlocked_skins[pick] = true
        s.equipped_skin = pick
        M.save()
        return "skin", pick
    elseif #locked_trails > 0 then
        local pick = locked_trails[math.random(#locked_trails)]
        s.unlocked_trails[pick] = true
        s.equipped_trail = pick
        M.save()
        return "trail", pick
    else
        -- All unlocked: grant bonus credits
        s.credits = s.credits + 250
        M.save()
        return "credits", 250
    end
end

function M.add_rewards(credits, parts)
    local s = M.get()
    s.credits = s.credits + (credits or 0)
    s.parts = s.parts + (parts or 0)
    M.save()
end

return M
