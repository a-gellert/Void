-- Campaign: 4 sectors x 6 missions. Text lives in i18n as m_<id>_name / m_<id>_desc.
-- Star rules: the first star is always "win"; two extra stars from:
--   deaths_max (v), time_max (seconds, v), kills_min (v), protect_min (VIP/station hull %, v)
local M = {}

M.SECTORS = {
    { id = 1, key = "sector_1", theme = "kepler", stars_required = 0 },
    { id = 2, key = "sector_2", theme = "ion", stars_required = 10 },
    { id = 3, key = "sector_3", theme = "crimson", stars_required = 24 },
    { id = 4, key = "sector_4", theme = "void", stars_required = 38 },
}

local function reward(diff)
    return { credits = 120 + 35 * diff, parts = 1 + math.floor(diff / 3), xp = 100 + 25 * diff }
end

local list = {
    -- ===================== SECTOR 1: KEPLER OUTSKIRTS (training & pirates)
    { id = "s1m1", mode = "tutorial", layout = "rift", difficulty = 1, bot_tier = 1,
      time_limit = 300, stars = { { type = "time_max", v = 200 }, { type = "deaths_max", v = 0 } } },
    { id = "s1m2", mode = "hunt", layout = "rift", difficulty = 1, bot_tier = 1, allies = 1,
      params = { drones_total = 12, max_alive = 4 }, time_limit = 240,
      stars = { { type = "deaths_max", v = 1 }, { type = "time_max", v = 150 } } },
    { id = "s1m3", mode = "race", layout = "belt", difficulty = 1, bot_tier = 1,
      params = { rings = 12 }, time_limit = 100,
      stars = { { type = "time_max", v = 80 }, { type = "time_max", v = 64 } } },
    { id = "s1m4", mode = "tdm", layout = "rift", difficulty = 2, bot_tier = 1, allies = 2, enemies = 3,
      params = { target_score = 10 }, time_limit = 180,
      stars = { { type = "kills_min", v = 4 }, { type = "deaths_max", v = 1 } } },
    { id = "s1m5", mode = "survival", layout = "rift", difficulty = 2, bot_tier = 1, allies = 2,
      params = { waves = 3 }, time_limit = 300,
      stars = { { type = "protect_min", v = 50 }, { type = "protect_min", v = 80 } } },
    { id = "s1m6", mode = "ace", layout = "belt", difficulty = 3, bot_tier = 2, allies = 2,
      params = { aces = { 1 }, escorts = 3 }, time_limit = 210,
      stars = { { type = "time_max", v = 140 }, { type = "deaths_max", v = 1 } } },

    -- ===================== SECTOR 2: ION RIFT (the war heats up)
    { id = "s2m1", mode = "domination", layout = "rift", difficulty = 3, bot_tier = 2, allies = 3, enemies = 4,
      params = { target_score = 100 }, time_limit = 210,
      stars = { { type = "kills_min", v = 5 }, { type = "deaths_max", v = 2 } } },
    { id = "s2m2", mode = "escort", layout = "rift", difficulty = 3, bot_tier = 2, allies = 2,
      params = { speed = 3.6, wave_every = 26, wave_drones = 4, wave_pilots = 0 }, time_limit = 260,
      stars = { { type = "protect_min", v = 50 }, { type = "protect_min", v = 80 } } },
    { id = "s2m3", mode = "race", layout = "nebula", difficulty = 3, bot_tier = 2,
      params = { rings = 12, turrets = true }, time_limit = 110,
      stars = { { type = "time_max", v = 90 }, { type = "time_max", v = 74 } } },
    { id = "s2m4", mode = "survival", layout = "nebula", difficulty = 4, bot_tier = 2, allies = 2,
      params = { waves = 5 }, time_limit = 420,
      stars = { { type = "protect_min", v = 40 }, { type = "deaths_max", v = 1 } } },
    { id = "s2m5", mode = "tdm", layout = "belt", difficulty = 4, bot_tier = 2, allies = 3, enemies = 4,
      params = { target_score = 12 }, time_limit = 210,
      stars = { { type = "kills_min", v = 5 }, { type = "deaths_max", v = 1 } } },
    { id = "s2m6", mode = "boss", layout = "wreck", difficulty = 4, bot_tier = 2, allies = 3,
      params = { mk = 1 }, time_limit = 180,
      stars = { { type = "time_max", v = 140 }, { type = "deaths_max", v = 1 } } },

    -- ===================== SECTOR 3: CRIMSON NEBULA (ion storms, elite pirates)
    { id = "s3m1", mode = "escort", layout = "nebula", difficulty = 5, bot_tier = 3, allies = 2,
      params = { speed = 3.4, wave_every = 24, wave_drones = 4, wave_pilots = 1, kamikaze = 0.3 }, time_limit = 280,
      modifiers = { shield_regen = 0.5 },
      stars = { { type = "protect_min", v = 45 }, { type = "protect_min", v = 75 } } },
    { id = "s3m2", mode = "ace", layout = "nebula", difficulty = 5, bot_tier = 3, allies = 2,
      params = { aces = { 1, 3 }, escorts = 2 }, time_limit = 240,
      stars = { { type = "time_max", v = 170 }, { type = "deaths_max", v = 1 } } },
    { id = "s3m3", mode = "domination", layout = "belt", difficulty = 6, bot_tier = 3, allies = 4, enemies = 5,
      params = { target_score = 100 }, time_limit = 240,
      stars = { { type = "kills_min", v = 6 }, { type = "deaths_max", v = 2 } } },
    { id = "s3m4", mode = "survival", layout = "rift", difficulty = 6, bot_tier = 3, allies = 2,
      params = { waves = 6, kamikaze = 0.35 }, time_limit = 480,
      modifiers = { shield_regen = 0.5 },
      stars = { { type = "protect_min", v = 40 }, { type = "protect_min", v = 70 } } },
    { id = "s3m5", mode = "race", layout = "rift", difficulty = 6, bot_tier = 3,
      params = { rings = 16, turrets = true }, time_limit = 130,
      stars = { { type = "time_max", v = 108 }, { type = "time_max", v = 92 } } },
    { id = "s3m6", mode = "boss", layout = "wreck", difficulty = 6, bot_tier = 3, allies = 3,
      params = { mk = 2 }, time_limit = 200,
      stars = { { type = "time_max", v = 160 }, { type = "deaths_max", v = 1 } } },

    -- ===================== SECTOR 4: VOID CORE (endgame)
    { id = "s4m1", mode = "tdm", layout = "nebula", difficulty = 7, bot_tier = 4, allies = 4, enemies = 5,
      params = { target_score = 15 }, time_limit = 240,
      stars = { { type = "kills_min", v = 6 }, { type = "deaths_max", v = 2 } } },
    { id = "s4m2", mode = "escort", layout = "belt", difficulty = 7, bot_tier = 4, allies = 3,
      params = { speed = 3.2, wave_every = 22, wave_drones = 5, wave_pilots = 2, kamikaze = 0.4 }, time_limit = 300,
      stars = { { type = "protect_min", v = 40 }, { type = "protect_min", v = 70 } } },
    { id = "s4m3", mode = "survival", layout = "nebula", difficulty = 8, bot_tier = 4, allies = 3,
      params = { waves = 7, kamikaze = 0.4 }, time_limit = 540,
      stars = { { type = "protect_min", v = 35 }, { type = "deaths_max", v = 2 } } },
    { id = "s4m4", mode = "domination", layout = "rift", difficulty = 8, bot_tier = 4, allies = 4, enemies = 5,
      params = { target_score = 100 }, time_limit = 240,
      modifiers = { shield_regen = 0.6 },
      stars = { { type = "kills_min", v = 6 }, { type = "deaths_max", v = 2 } } },
    { id = "s4m5", mode = "ace", layout = "belt", difficulty = 9, bot_tier = 5, allies = 3,
      params = { aces = { 2, 3, 4 }, escorts = 2 }, time_limit = 300,
      stars = { { type = "time_max", v = 220 }, { type = "deaths_max", v = 2 } } },
    { id = "s4m6", mode = "boss", layout = "wreck", difficulty = 9, bot_tier = 5, allies = 4,
      params = { mk = 3 }, time_limit = 240,
      stars = { { type = "time_max", v = 190 }, { type = "deaths_max", v = 2 } } },
}

M.MISSIONS = {}
M.BY_ID = {}
for i, m in ipairs(list) do
    m.order = i
    m.sector = tonumber(string.sub(m.id, 2, 2))
    m.index = tonumber(string.sub(m.id, 4, 4))
    m.allies = m.allies or 0
    m.enemies = m.enemies or 0
    m.params = m.params or {}
    m.modifiers = m.modifiers or {}
    m.reward = reward(m.difficulty)
    M.MISSIONS[i] = m
    M.BY_ID[m.id] = m
end

function M.get(id)
    return M.BY_ID[id]
end

function M.sector_missions(sector)
    local out = {}
    for _, m in ipairs(M.MISSIONS) do
        if m.sector == sector then out[#out + 1] = m end
    end
    return out
end

M.TOTAL_STARS = #list * 3

-- Skirmish (quick battle) presets. Difficulty and bot tier are scaled by pilot level.
M.SKIRMISH = {
    { id = "sk_tdm", mode = "tdm", layout_cycle = { "rift", "belt", "nebula" }, allies = 3, enemies = 4,
      params = { target_score = 12 }, time_limit = 210, unlock_level = 1 },
    { id = "sk_dom", mode = "domination", layout_cycle = { "rift", "belt", "nebula" }, allies = 3, enemies = 4,
      params = { target_score = 100 }, time_limit = 210, unlock_level = 2 },
    { id = "sk_survival", mode = "survival", layout_cycle = { "rift", "nebula" }, allies = 2, enemies = 0,
      params = { waves = 99, endless = true, kamikaze = 0.3 }, time_limit = 900, unlock_level = 3 },
    { id = "sk_boss", mode = "boss", layout_cycle = { "wreck" }, allies = 3, enemies = 0,
      params = { mk = 1 }, time_limit = 200, unlock_level = 5 },
}

return M
