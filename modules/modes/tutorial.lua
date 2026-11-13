-- First Flight: scripted 5-step tutorial.
--  1 steer through 3 gates   2 afterburner through 2 far gates   3 shoot 4 target drones
--  4 lock + missile 2 targets   5 evade/modules vs 3 live pirate drones
local math3d = require("modules.math3d")
local pool_manager = require("modules.pool_manager")
local audio = require("modules.audio")
local race = require("modules.modes.race")

local M = {}

local GATES = {
    { 30, 12, 110 }, { 70, 22, 60 }, { 105, 12, 5 }, -- steering
    { 120, 0, -80 }, { 60, -10, -170 },             -- afterburner
}

local STAGES = {
    { key = "tut_steer" },
    { key = "tut_boost" },
    { key = "tut_fire" },
    { key = "tut_missile" },
    { key = "tut_evade" },
}

local function spawn_targets(match, api, n, kind, center)
    match.targets_left = 0
    for i = 1, n do
        local a = (i / n) * math.pi * 2
        local pos = center + vmath.vector3(math.cos(a) * 30, math.sin(a * 2) * 10, math.sin(a) * 30)
        local d = api.spawn_drone(kind == "dummy" and "drone" or kind, pos, 2)
        if d then
            if kind == "dummy" then
                d.ai = "dummy"
                d.anchor = center
                d.has_weapon = false
                d.max_hull, d.hull = 30, 30
            else
                d.dmg_mult = 0.35
            end
            match.targets_left = match.targets_left + 1
        end
    end
end

local function enter_stage(match, api, n)
    match.stage = n
    local st = STAGES[n]
    if not st then
        api.banner("tut_complete", "gold", nil, 2.5)
        api.finish(true)
        return
    end
    api.hint(st.key, 999)
    if n > 1 then audio.play("objective", 0.6) end
    local p = match.player
    local ahead = p and (p.pos + p.forward * 120) or vmath.vector3(0, 0, 0)
    ahead.y = math3d.clamp(ahead.y, -40, 40)
    if n == 3 then
        spawn_targets(match, api, 4, "dummy", ahead)
    elseif n == 4 then
        spawn_targets(match, api, 2, "dummy", ahead)
        p.missiles = p.missiles_max
    elseif n == 5 then
        spawn_targets(match, api, 3, "drone", ahead)
    end
end

function M.setup(match, api)
    match.gates = {}
    for i, g in ipairs(GATES) do
        local nxt = GATES[math.min(#GATES, i + 1)]
        local prv = GATES[math.max(1, i - 1)]
        local dir = math3d.normalize_or_default(vmath.vector3(nxt[1] - prv[1], nxt[2] - prv[2], nxt[3] - prv[3]))
        match.gates[i] = { pos = vmath.vector3(g[1], g[2], g[3]), dir = dir }
    end
    match.gate_index = 1
    match.gate_limit = 3
    api.build_environment({ keepout = GATES, keep_r = 30, no_hollow = true })
    match.cfg.player_pos = vmath.vector3(0, 8, 175)
    match.cfg.player_fwd = math3d.normalize_or_default(match.gates[1].pos - match.cfg.player_pos)
    api.spawn_player()
    match.score_kind = "none"
    race.refresh_rings(match)
    enter_stage(match, api, 1)
end

function M.update(match, api)
    local s = match.stage
    if s == 1 or s == 2 then
        if race.check_gate(match, api) then
            if match.gate_index > match.gate_limit then
                if s == 1 then
                    match.gate_limit = 5
                    enter_stage(match, api, 2)
                else
                    for k = 1, pool_manager.RING_POOL do pool_manager.hide_ring(pool_manager.get_ring_slot(k)) end
                    enter_stage(match, api, 3)
                end
            end
        end
        -- Only show the gates of the current stage.
        for k = 1, pool_manager.RING_POOL do
            if match.gate_index + (k - 1) > match.gate_limit then pool_manager.hide_ring(pool_manager.get_ring_slot(k)) end
        end
        local g = match.gates[match.gate_index]
        match.waypoints[1] = g and g.pos or nil
        match.waypoint_kind = "ring"
    else
        match.waypoints[1] = nil
        if (match.targets_left or 0) <= 0 then enter_stage(match, api, s + 1) end
    end
    api.set_objective("obj_tutorial", math.min(5, match.stage or 1), 5, ((match.stage or 1) - 1) / 5)
end

function M.on_kill(match, api, victim)
    if victim.team == 2 then
        match.targets_left = (match.targets_left or 1) - 1
    end
end

function M.on_timeout()
    return false
end

function M.on_finish()
    for k = 1, pool_manager.RING_POOL do pool_manager.hide_ring(pool_manager.get_ring_slot(k)) end
end

return M
