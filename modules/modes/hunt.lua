-- Drone Sweep: destroy `drones_total` pirate drones (at most `max_alive` at once).
local M = {}

function M.setup(match, api)
    api.build_environment()
    api.spawn_player()
    api.spawn_pilots(1, match.cfg.allies or 1)
    match.drones_total = match.cfg.params.drones_total or 12
    match.drones_max = match.cfg.params.max_alive or 4
    match.drones_spawned = 0
    match.drones_killed = 0
    match.spawn_cd = 2.0
    match.score_kind = "none"
    api.hint("hint_hunt", 6.0)
end

local function alive_drones(match)
    local n = 0
    for _, s in ipairs(match.ships) do
        if s.team == 2 and s.alive then n = n + 1 end
    end
    return n
end

function M.update(match, api, dt)
    match.spawn_cd = match.spawn_cd - dt
    if match.spawn_cd <= 0 and match.drones_spawned < match.drones_total and alive_drones(match) < match.drones_max then
        match.spawn_cd = 1.2
        local sp = match.layout.wave_spawns[math.random(1, #match.layout.wave_spawns)]
        local pos = vmath.vector3(sp[1] * 0.75, sp[2] * 0.75, sp[3] * 0.75)
        local kind = (match.cfg.params.kamikaze and math.random() < match.cfg.params.kamikaze) and "kamikaze" or "drone"
        if api.spawn_drone(kind, pos, 2) then match.drones_spawned = match.drones_spawned + 1 end
    end
    api.set_objective("obj_hunt", match.drones_killed, match.drones_total, match.drones_killed / match.drones_total)
end

function M.on_kill(match, api, victim)
    if victim.team == 2 and (victim.ai == "drone" or victim.ai == "kamikaze") then
        match.drones_killed = match.drones_killed + 1
        if match.drones_killed >= match.drones_total then api.finish(true) end
    end
end

return M
