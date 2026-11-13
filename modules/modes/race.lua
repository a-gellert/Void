-- Ring Run: fly through the gates in order before the timer ends.
-- Each gate refills 35 energy so chaining afterburner pays off.
-- params.turrets: pirate drones harass the course.
local math3d = require("modules.math3d")
local pool_manager = require("modules.pool_manager")
local audio = require("modules.audio")

local M = {}

local SHOW_AHEAD = 4
local PASS_R = 10.5

local function ring_dir(list, i)
    local n = #list
    local a = list[((i - 2) % n) + 1]
    local b = list[(i % n) + 1]
    return math3d.normalize_or_default(vmath.vector3(b[1] - a[1], b[2] - a[2], b[3] - a[3]))
end

--- Build an ordered gate list from a loop (wrapping) or an explicit point list.
function M.build_gates(points, count)
    local gates = {}
    for i = 1, count do
        local idx = ((i - 1) % #points) + 1
        local p = points[idx]
        gates[i] = { pos = vmath.vector3(p[1], p[2], p[3]), dir = ring_dir(points, idx) }
    end
    return gates
end

function M.refresh_rings(match)
    for k = 1, pool_manager.RING_POOL do
        local slot = pool_manager.get_ring_slot(k)
        local gi = match.gate_index + (k - 1)
        local g = match.gates[gi]
        if g and k <= SHOW_AHEAD then
            if k == 1 then
                pool_manager.show_ring(slot, g.pos, g.dir, 1.0, 0.85, 0.25, 1.0, 1.0)
            else
                local a = 0.75 - 0.15 * (k - 2)
                pool_manager.show_ring(slot, g.pos, g.dir, 0.15 * a + 0.1, 0.78 * a, 0.85 * a, 1.0, 0.9)
            end
        else
            pool_manager.hide_ring(slot)
        end
    end
end

-- Returns true when the player passes the current gate.
function M.check_gate(match, api)
    local p = match.player
    local g = match.gates[match.gate_index]
    if not g or not p or not p.alive then return false end
    if math3d.vec_dist_sq(p.pos, g.pos) < PASS_R * PASS_R then
        match.gate_index = match.gate_index + 1
        api.track("rings", 1)
        p.energy = math.min(p.max_energy, p.energy + 35)
        pool_manager.spawn_vfx(g.pos, 1.0, 0.85, 0.3, 12.0, 0.4)
        audio.play("ring", 0.7)
        M.refresh_rings(match)
        return true
    end
    return false
end

function M.setup(match, api)
    local pts = match.layout.rings
    local count = match.cfg.params.rings or 12
    match.gates = M.build_gates(pts, count)
    match.gate_index = 1
    local keep = {}
    for _, p in ipairs(pts) do keep[#keep + 1] = p end
    api.build_environment({ keepout = keep, keep_r = 26, no_hollow = true })

    local g1 = match.gates[1]
    match.cfg.player_pos = g1.pos - g1.dir * 70 + vmath.vector3(0, 4, 0)
    match.cfg.player_fwd = g1.dir
    api.spawn_player()
    if match.cfg.params.turrets then
        for i = 1, 4 do
            local g = match.gates[math.min(#match.gates, i * 3)]
            local side = vmath.vector3(math.cos(i * 1.7) * 30, 18, math.sin(i * 1.7) * 30)
            local d = api.spawn_drone("drone", g.pos + side, 2)
            if d then d.anchor = g.pos end
        end
    end
    match.score_kind = "none"
    M.refresh_rings(match)
    api.hint("hint_race", 5.0)
end

function M.update(match, api)
    if M.check_gate(match, api) and match.gate_index > #match.gates then
        api.banner("race_done", "gold", nil, 2.0)
        api.finish(true)
        return
    end
    local g = match.gates[match.gate_index]
    match.waypoints[1] = g and g.pos or nil
    match.waypoint_kind = "ring"
    api.set_objective("obj_race", match.gate_index - 1, #match.gates, (match.gate_index - 1) / #match.gates)
end

function M.on_finish()
    for k = 1, pool_manager.RING_POOL do pool_manager.hide_ring(pool_manager.get_ring_slot(k)) end
end

return M
