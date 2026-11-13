-- Persistent player profile (save v2): pilot level, hangar, campaign stars,
-- contracts, statistics and settings. v1 saves are migrated on first load.
local ships_db = require("data.ships_db")
local modules_db = require("data.modules_db")
local campaign_db = require("data.campaign_db")
local progression_db = require("data.progression_db")
local i18n = require("modules.i18n")

local M = {}

local SAVE_APP = "void_clash_3d"
local SAVE_FILE = "save_v2"
local LEGACY_FILE = "save_v1"

local state = nil

local function default_upgrades()
    return { hull = 1, weapon = 1, shield = 1, engine = 1 }
end

local function default_state()
    return {
        version = 2,
        credits = 300,
        parts = 2,
        xp = 0,
        level = 1,
        owned = { wasp = true },
        selected = "wasp",
        upgrades = {},
        loadouts = {},
        unlocked_skins = { [1] = true, [2] = true, [3] = true },
        unlocked_trails = { [1] = true, [2] = true, [3] = true },
        equipped_skin = 1,
        equipped_trail = 1,
        campaign = { stars = {}, best_time = {} },
        contracts = {},
        stats = {
            matches = 0, wins = 0, kills = 0, deaths = 0, missile_kills = 0, drones = 0,
            rings = 0, beacons = 0, damage = 0, modules = 0, stars = 0, playtime = 0,
        },
        match_count = 0,
        skirmish_round = 0,
        test_drive_active = false,
        settings = {
            language = i18n.detect_default(),
            muted = false,
            autofire = true,
            sensitivity = 1.0,
            invert_y = false,
        },
    }
end

local function merge_into(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            merge_into(dst[k], v)
        elseif dst[k] == nil or type(dst[k]) == type(v) then
            dst[k] = v
        end
    end
end

local LEGACY_CLASS = { interceptor = "wasp", fighter = "falcon", frigate = "bastion" }

local function migrate_v1(old, s)
    s.credits = math.max(s.credits, tonumber(old.credits) or 0)
    s.parts = math.max(s.parts, tonumber(old.parts) or 0)
    if type(old.unlocked_skins) == "table" then s.unlocked_skins = old.unlocked_skins end
    if type(old.unlocked_trails) == "table" then s.unlocked_trails = old.unlocked_trails end
    s.equipped_skin = old.equipped_skin or s.equipped_skin
    s.equipped_trail = old.equipped_trail or s.equipped_trail
    s.settings.muted = old.muted and true or false
    if old.language then s.settings.language = old.language end
    if type(old.upgrades) == "table" then
        for cls, u in pairs(old.upgrades) do
            local sid = LEGACY_CLASS[cls]
            if sid and type(u) == "table" then
                s.upgrades[sid] = { hull = u.hull or 1, weapon = u.weapon or 1, shield = u.shield or 1, engine = u.engine or 1 }
                if ships_db.tier_of(s.upgrades[sid]) > 1 or (u.hull or 1) + (u.weapon or 1) + (u.shield or 1) + (u.engine or 1) > 4 then
                    s.owned[sid] = true
                end
            end
        end
    end
    local sel = LEGACY_CLASS[old.selected_class or ""]
    if sel then s.owned[sel] = true; s.selected = sel end
    s.match_count = tonumber(old.match_count) or 0
    -- Veterans start with a little XP so the first unlocks come quickly.
    s.xp = math.min(600, s.match_count * 60)
end

function M.load()
    state = default_state()
    local loaded = sys.load(sys.get_save_file(SAVE_APP, SAVE_FILE))
    if type(loaded) == "table" and loaded.version == 2 then
        merge_into(state, loaded)
    else
        local legacy = sys.load(sys.get_save_file(SAVE_APP, LEGACY_FILE))
        if type(legacy) == "table" and next(legacy) ~= nil then
            migrate_v1(legacy, state)
            -- Level up from migrated XP.
            M.add_xp(0)
        end
    end
    if not ships_db.SHIPS[state.selected] or not state.owned[state.selected] then
        state.selected = "wasp"
    end
    i18n.set_language(state.settings.language or "en")
    M.ensure_contracts()
    return state
end

function M.save()
    if not state then return end
    sys.save(sys.get_save_file(SAVE_APP, SAVE_FILE), state)
end

function M.get()
    if not state then M.load() end
    return state
end

function M.settings()
    return M.get().settings
end

-- =============================================================== HANGAR
function M.get_upgrades(ship_id)
    local s = M.get()
    local sid = ship_id or s.selected
    if not s.upgrades[sid] then s.upgrades[sid] = default_upgrades() end
    return s.upgrades[sid]
end

-- Upgrades used in combat (includes the rewarded +1 tier "test drive").
function M.get_combat_upgrades(ship_id)
    local s = M.get()
    local sid = ship_id or s.selected
    local u = M.get_upgrades(sid)
    if s.test_drive_active and sid == s.selected then
        return {
            hull = math.min(5, u.hull + 1), weapon = math.min(5, u.weapon + 1),
            shield = math.min(5, u.shield + 1), engine = math.min(5, u.engine + 1),
        }
    end
    return u
end

function M.get_player_tier(ship_id)
    return ships_db.tier_of(M.get_upgrades(ship_id))
end

function M.can_upgrade(ship_id, node_key)
    local s = M.get()
    if not s.owned[ship_id] then return false, 0, 0 end
    local u = M.get_upgrades(ship_id)
    local lv = u[node_key] or 1
    if lv >= 5 then return false, 0, 0 end
    local credits_cost = ships_db.UPGRADE_COSTS.credits[lv + 1] or 9999
    local parts_cost = ships_db.UPGRADE_COSTS.parts[lv + 1] or 0
    local ok = (s.credits >= credits_cost) and ((s.parts or 0) >= parts_cost)
    return ok, credits_cost, parts_cost
end

function M.upgrade_node(ship_id, node_key)
    local ok, credits_cost, parts_cost = M.can_upgrade(ship_id, node_key)
    if not ok then return false end
    state.credits = state.credits - credits_cost
    state.parts = state.parts - parts_cost
    local u = M.get_upgrades(ship_id)
    u[node_key] = u[node_key] + 1
    M.save()
    return true
end

function M.ship_status(ship_id)
    local s = M.get()
    local def = ships_db.get(ship_id)
    if s.owned[ship_id] then return "owned", 0, def.unlock_level end
    if s.level < def.unlock_level then return "level", def.price, def.unlock_level end
    return "buy", def.price, def.unlock_level
end

function M.buy_ship(ship_id)
    local st, price = M.ship_status(ship_id)
    if st ~= "buy" or state.credits < price then return false end
    state.credits = state.credits - price
    state.owned[ship_id] = true
    state.selected = ship_id
    M.save()
    return true
end

function M.select_ship(ship_id)
    local s = M.get()
    if not s.owned[ship_id] then return false end
    s.selected = ship_id
    M.save()
    return true
end

function M.module_unlocked(mod_id)
    local cfg = modules_db.MODULES[mod_id]
    return cfg ~= nil and M.get().level >= (cfg.unlock_level or 1)
end

function M.get_loadout(ship_id)
    local s = M.get()
    local sid = ship_id or s.selected
    local def = ships_db.get(sid)
    local lo = s.loadouts[sid]
    if type(lo) ~= "table" or #lo < 2 then
        lo = { def.modules[1], def.modules[2] }
        s.loadouts[sid] = lo
    end
    -- Drop modules that no longer belong to this hull or got locked.
    for i = 1, 2 do
        local ok = false
        for _, m in ipairs(def.modules) do if m == lo[i] then ok = true end end
        if not ok or not M.module_unlocked(lo[i]) then lo[i] = def.modules[i] end
    end
    return lo
end

-- Put `mod_id` into `slot`; if it already sits in the other slot, swap.
function M.set_loadout(ship_id, slot, mod_id)
    if not M.module_unlocked(mod_id) then return false end
    local lo = M.get_loadout(ship_id)
    local other = (slot == 1) and 2 or 1
    if lo[other] == mod_id then lo[other] = lo[slot] end
    lo[slot] = mod_id
    M.save()
    return true
end

-- ============================================================ PILOT LEVEL
-- Adds XP; returns a list of reached levels (possibly empty).
function M.add_xp(amount)
    local s = M.get()
    s.xp = s.xp + math.max(0, math.floor(amount or 0))
    local reached = {}
    while s.level < progression_db.MAX_LEVEL and s.xp >= progression_db.xp_for_level(s.level) do
        s.xp = s.xp - progression_db.xp_for_level(s.level)
        s.level = s.level + 1
        local r = progression_db.level_reward(s.level)
        s.credits = s.credits + r.credits
        s.parts = s.parts + r.parts
        reached[#reached + 1] = s.level
    end
    return reached
end

function M.add_rewards(credits, parts)
    local s = M.get()
    s.credits = s.credits + math.floor(credits or 0)
    s.parts = s.parts + math.floor(parts or 0)
    M.save()
end

-- =============================================================== CAMPAIGN
function M.get_stars(mission_id)
    return M.get().campaign.stars[mission_id] or 0
end

function M.total_stars()
    local n = 0
    for _, v in pairs(M.get().campaign.stars) do n = n + v end
    return n
end

function M.sector_unlocked(sector)
    local sec = campaign_db.SECTORS[sector]
    if not sec then return false end
    if sector == 1 then return true end
    -- Previous sector finale must be cleared and enough stars collected.
    local prev = campaign_db.sector_missions(sector - 1)
    local last = prev[#prev]
    return M.get_stars(last.id) > 0 and M.total_stars() >= sec.stars_required
end

function M.mission_unlocked(mission_id)
    local m = campaign_db.get(mission_id)
    if not m then return false end
    if not M.sector_unlocked(m.sector) then return false end
    if m.order == 1 then return true end
    local prev = campaign_db.MISSIONS[m.order - 1]
    if prev.sector ~= m.sector then return true end
    return M.get_stars(prev.id) > 0
end

-- First campaign mission that is unlocked but not yet cleared (or the last one).
function M.next_mission()
    for _, m in ipairs(campaign_db.MISSIONS) do
        if M.mission_unlocked(m.id) and M.get_stars(m.id) == 0 then return m end
    end
    for i = #campaign_db.MISSIONS, 1, -1 do
        local m = campaign_db.MISSIONS[i]
        if M.mission_unlocked(m.id) then return m end
    end
    return campaign_db.MISSIONS[1]
end

-- Stores a result; returns (new_stars_gained, first_clear).
function M.record_mission(mission_id, stars, time_s)
    local c = M.get().campaign
    local prev = c.stars[mission_id] or 0
    local first = prev == 0 and stars > 0
    if stars > prev then c.stars[mission_id] = stars end
    if stars > 0 and time_s then
        local bt = c.best_time[mission_id]
        if not bt or time_s < bt then c.best_time[mission_id] = time_s end
    end
    return math.max(0, stars - prev), first
end

-- ============================================================== CONTRACTS
local function make_contract(exclude)
    local pool = {}
    for _, t in ipairs(progression_db.CONTRACTS) do
        if not exclude[t.id] then pool[#pool + 1] = t end
    end
    local t = pool[math.random(1, #pool)]
    local target = math.random(t.min, t.max)
    if t.id == "damage" then target = math.floor(target / 500 + 0.5) * 500 end
    return {
        id = t.id,
        stat = t.stat,
        target = target,
        progress = 0,
        credits = math.floor(t.credits * target / 10 + 0.5) * 10,
        xp = math.floor(t.xp * target / 5 + 0.5) * 5,
        parts = t.parts,
    }
end

function M.ensure_contracts()
    local s = M.get()
    local ids = {}
    for _, c in ipairs(s.contracts) do ids[c.id] = true end
    while #s.contracts < 3 do
        local c = make_contract(ids)
        ids[c.id] = true
        s.contracts[#s.contracts + 1] = c
    end
end

-- Advance a statistic + matching contracts.
function M.track(stat, amount)
    local s = M.get()
    local a = amount or 1
    if s.stats[stat] ~= nil then s.stats[stat] = s.stats[stat] + a end
    for _, c in ipairs(s.contracts) do
        if c.stat == stat and c.progress < c.target then
            c.progress = math.min(c.target, c.progress + a)
        end
    end
end

function M.claim_contract(index)
    local s = M.get()
    local c = s.contracts[index]
    if not c or c.progress < c.target then return nil end
    local levels = M.add_xp(c.xp)
    s.credits = s.credits + c.credits
    s.parts = s.parts + c.parts
    local ids = {}
    for i, o in ipairs(s.contracts) do if i ~= index then ids[o.id] = true end end
    ids[c.id] = true
    s.contracts[index] = make_contract(ids)
    M.save()
    return c, levels
end

function M.claimable_contracts()
    local n = 0
    for _, c in ipairs(M.get().contracts) do
        if c.progress >= c.target then n = n + 1 end
    end
    return n
end

-- ============================================================== COSMETICS
local function collect_locked_cosmetics(s)
    local locked_skins = {}
    for i = 1, #ships_db.SKINS do
        if not s.unlocked_skins[i] then locked_skins[#locked_skins + 1] = i end
    end
    local locked_trails = {}
    for i = 1, #ships_db.TRAILS do
        if not s.unlocked_trails[i] then locked_trails[#locked_trails + 1] = i end
    end
    return locked_skins, locked_trails
end

local function unlock_random_from_locked(s, locked_skins, locked_trails)
    if #locked_skins > 0 and (#locked_trails == 0 or math.random() < 0.65) then
        local pick = locked_skins[math.random(#locked_skins)]
        s.unlocked_skins[pick] = true
        s.equipped_skin = pick
        return "skin", pick
    elseif #locked_trails > 0 then
        local pick = locked_trails[math.random(#locked_trails)]
        s.unlocked_trails[pick] = true
        s.equipped_trail = pick
        return "trail", pick
    end
    return nil, 0
end

function M.has_locked_cosmetic()
    local locked_skins, locked_trails = collect_locked_cosmetics(M.get())
    return (#locked_skins > 0) or (#locked_trails > 0)
end

function M.can_craft_random()
    local s = M.get()
    local cost = ships_db.CRAFT_COSTS.random
    local has_locked = M.has_locked_cosmetic()
    return has_locked and (s.parts >= cost), cost, has_locked
end

function M.craft_random_cosmetic()
    local ok, cost = M.can_craft_random()
    if not ok then return nil, 0 end
    local s = M.get()
    local locked_skins, locked_trails = collect_locked_cosmetics(s)
    local kind, pick = unlock_random_from_locked(s, locked_skins, locked_trails)
    if not kind then return nil, 0 end
    s.parts = s.parts - cost
    M.save()
    return kind, pick
end

function M.can_craft_cosmetic(kind, id)
    local s = M.get()
    if kind == "skin" then
        if not id or id < 1 or id > #ships_db.SKINS or s.unlocked_skins[id] then return false, 0 end
    elseif kind == "trail" then
        if not id or id < 1 or id > #ships_db.TRAILS or s.unlocked_trails[id] then return false, 0 end
    else
        return false, 0
    end
    local cost = ships_db.CRAFT_COSTS[kind] or 99
    return s.parts >= cost, cost
end

function M.craft_cosmetic(kind, id)
    local ok, cost = M.can_craft_cosmetic(kind, id)
    if not ok then return false end
    local s = M.get()
    s.parts = s.parts - cost
    if kind == "skin" then
        s.unlocked_skins[id] = true
        s.equipped_skin = id
    else
        s.unlocked_trails[id] = true
        s.equipped_trail = id
    end
    M.save()
    return true
end

function M.unlock_random_cosmetic()
    local s = M.get()
    local locked_skins, locked_trails = collect_locked_cosmetics(s)
    local kind, pick = unlock_random_from_locked(s, locked_skins, locked_trails)
    if kind then
        M.save()
        return kind, pick
    end
    s.credits = s.credits + 250
    M.save()
    return "credits", 250
end

return M
