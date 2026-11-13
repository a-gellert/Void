-- Survival: protect the station core against escalating pirate waves.
-- Campaign: clear `waves` waves. Skirmish (`endless`): survive as long as possible.
local audio = require("modules.audio")

local M = {}

local function build_wave(match, n)
    local params = match.cfg.params
    local q = {}
    local drones = math.min(12, 3 + 2 * n)
    local kamikaze_ratio = (n >= 2) and (params.kamikaze or 0.25) or 0
    for i = 1, drones do
        q[#q + 1] = (math.random() < kamikaze_ratio) and "kamikaze" or "drone"
    end
    local pilots = math.min(4, math.floor((n - 1) / 2))
    for _ = 1, pilots do q[#q + 1] = "pilot" end
    return q
end

function M.setup(match, api)
    api.build_environment()
    local st = match.layout.station or { x = 0, y = 0, z = 0 }
    local diff = match.cfg.difficulty or 3
    local hp = 2600 * (1 + 0.1 * diff)
    match.station = api.add_structure({
        kind = "station", team = 1, pos = vmath.vector3(st.x, st.y, st.z), radius = 18,
        hull = hp, max_hull = hp, shield = 900, max_shield = 900, regen = 0.03,
        targetable = true, name = "STATION", display_name = "STATION",
    })
    match.protect = { entity = match.station, key = "station" }
    api.spawn_player()
    api.spawn_pilots(1, match.cfg.allies or 2)
    match.wave = 0
    match.wave_total = match.cfg.params.waves or 3
    match.wave_reached = 0
    match.break_timer = 5.0
    match.queue = {}
    match.spawn_cd = 0
    match.score_kind = "waves"
    api.hint("hint_survival", 6.0)
end

local function enemies_alive(match)
    for _, s in ipairs(match.ships) do
        if s.team == 2 and s.alive then return true end
    end
    return false
end

function M.update(match, api, dt)
    local st = match.station
    match.protect_pct = math.floor(100 * st.hull / st.max_hull + 0.5)
    if #match.queue == 0 and not enemies_alive(match) then
        if match.wave > match.wave_reached then
            match.wave_reached = match.wave
            if match.wave > 0 then
                api.banner("wave_cleared", "green", match.wave, 2.0)
                audio.play("objective", 0.6)
            end
        end
        if match.wave >= match.wave_total and not match.cfg.params.endless then
            api.finish(true)
            return
        end
        match.break_timer = match.break_timer - dt
        if match.break_timer <= 0 then
            match.wave = match.wave + 1
            match.queue = build_wave(match, match.wave)
            match.break_timer = 7.0
            api.banner("wave_incoming", "coral", match.wave, 2.4)
            audio.play("wave", 0.7)
        end
    end
    if #match.queue > 0 then
        match.spawn_cd = match.spawn_cd - dt
        if match.spawn_cd <= 0 and api.free_slots() > 1 then
            match.spawn_cd = 0.55
            local kind = table.remove(match.queue, 1)
            local sp = match.layout.wave_spawns[math.random(1, #match.layout.wave_spawns)]
            local pos = vmath.vector3(sp[1] + math.random(-15, 15), sp[2] + math.random(-10, 10), sp[3] + math.random(-15, 15))
            if kind == "pilot" then
                api.spawn_pilots(2, 1, { respawn = false, pos = pos })
            else
                api.spawn_drone(kind, pos, 2)
            end
        end
    end
    local total = match.cfg.params.endless and 0 or match.wave_total
    api.set_objective(match.cfg.params.endless and "obj_survival_endless" or "obj_survival",
        math.max(1, match.wave), total, st.hull / st.max_hull)
end

function M.on_structure_killed(match, api, s)
    if s == match.station then
        match.protect_pct = 0
        api.finish(match.cfg.params.endless and match.wave_reached >= 5 or false)
    end
end

function M.on_timeout(match)
    return match.station.alive
end

return M
