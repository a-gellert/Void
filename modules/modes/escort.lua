-- Escort: a slow freighter follows the layout path; pirates attack in waves.
local math3d = require("modules.math3d")
local flight_physics = require("modules.flight_physics")
local audio = require("modules.audio")

local M = {}

function M.setup(match, api)
    local path = match.layout.escort_path
    local keep = {}
    for _, p in ipairs(path) do keep[#keep + 1] = p end
    -- Interpolate extra keepout points so no asteroid sits on the route.
    for i = 1, #path - 1 do
        local a, b = path[i], path[i + 1]
        for k = 1, 3 do
            local t = k / 4
            keep[#keep + 1] = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
        end
    end
    api.build_environment({ keepout = keep, keep_r = 30 })

    match.path = {}
    local total = 0
    for i, p in ipairs(path) do
        match.path[i] = vmath.vector3(p[1], p[2], p[3])
        if i > 1 then total = total + vmath.length(match.path[i] - match.path[i - 1]) end
    end
    match.path_len = total
    match.path_done = 0
    match.wp = 2
    local diff = match.cfg.difficulty or 3
    local start = match.path[1]
    local fwd = math3d.normalize_or_default(match.path[2] - start)
    match.vip = api.spawn_ship({
        team = 1, ship_id = "freighter", tier = 1, ai = "freighter", is_vip = true, respawn = false,
        pos = start, forward = fwd, speed = match.cfg.params.speed or 3.6, hp_mult = 1 + 0.08 * diff,
        name = "FREIGHTER", display_name = "FREIGHTER",
    })
    match.protect = { entity = match.vip, key = "freighter" }
    match.cfg.player_pos = start + vmath.vector3(0, 14, 40)
    match.cfg.player_fwd = fwd
    api.spawn_player()
    api.spawn_pilots(1, match.cfg.allies or 2)
    match.wave_timer = 9.0
    match.wave = 0
    match.queue = {}
    match.spawn_cd = 0
    api.hint("hint_escort", 6.0)
end

local function queue_wave(match)
    local p = match.cfg.params
    local n = (p.wave_drones or 4) + math.floor(match.wave / 2)
    for _ = 1, n do
        match.queue[#match.queue + 1] = (math.random() < (p.kamikaze or 0)) and "kamikaze" or "drone"
    end
    for _ = 1, (p.wave_pilots or 0) do match.queue[#match.queue + 1] = "pilot" end
end

-- Spawn point among the wave spawns closest to the freighter's next waypoints.
local function wave_origin(match)
    local target = match.path[math.min(#match.path, match.wp + 1)]
    local best, best_d = nil, 1e18
    for _, sp in ipairs(match.layout.wave_spawns) do
        local d = math3d.dist_sq(sp[1], sp[2], sp[3], target.x, target.y, target.z) * (0.6 + math.random() * 0.8)
        if d < best_d then best_d = d; best = sp end
    end
    return vmath.vector3(best[1], best[2], best[3])
end

function M.update(match, api, dt)
    local v = match.vip
    if not v.alive then return end
    match.protect_pct = math.floor(100 * v.hull / v.max_hull + 0.5)

    local wp = match.path[match.wp]
    if math3d.vec_dist_sq(v.pos, wp) < 14 * 14 then
        match.wp = match.wp + 1
        if match.wp > #match.path then
            api.banner("escort_done", "green", nil, 2.5)
            api.finish(true)
            return
        end
        wp = match.path[match.wp]
    end
    flight_physics.update_scripted(v, wp - v.pos, dt)
    go.set_position(v.pos, v.pool_slot.id)
    go.set_rotation(v.rot, v.pool_slot.id)

    -- Progress along the path
    local done = 0
    for i = 2, match.wp - 1 do done = done + vmath.length(match.path[i] - match.path[i - 1]) end
    local seg = vmath.length(match.path[match.wp] - match.path[match.wp - 1])
    local left = vmath.length(match.path[match.wp] - v.pos)
    done = done + math.max(0, seg - left)
    match.path_done = done / math.max(1, match.path_len)

    match.wave_timer = match.wave_timer - dt
    if match.wave_timer <= 0 then
        match.wave = match.wave + 1
        match.wave_timer = match.cfg.params.wave_every or 25
        queue_wave(match)
        match.wave_pos = wave_origin(match)
        api.banner("wave_incoming", "coral", match.wave, 2.2)
        audio.play("wave", 0.6)
    end
    if #match.queue > 0 then
        match.spawn_cd = match.spawn_cd - dt
        if match.spawn_cd <= 0 and api.free_slots() > 1 then
            match.spawn_cd = 0.5
            local kind = table.remove(match.queue, 1)
            local o = match.wave_pos or wave_origin(match)
            local pos = o + vmath.vector3(math.random(-14, 14), math.random(-8, 8), math.random(-14, 14))
            if kind == "pilot" then
                api.spawn_pilots(2, 1, { respawn = false, pos = pos })
            else
                api.spawn_drone(kind, pos, 2)
            end
        end
    end
    api.set_objective("obj_escort", math.floor(match.path_done * 100), match.protect_pct, match.path_done)
end

function M.on_kill(match, api, victim)
    if victim == match.vip then
        match.protect_pct = 0
        api.banner("freighter_lost", "coral", nil, 2.5)
        api.finish(false)
    end
end

return M
