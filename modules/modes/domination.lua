-- Domination: hold beacons A/B/C, each owned beacon ticks score; first to 100 wins.
local math3d = require("modules.math3d")
local pool_manager = require("modules.pool_manager")
local audio = require("modules.audio")

local M = {}

local C_NEUTRAL = vmath.vector4(1.0, 0.85, 0.25, 1.0)
local C_T1 = vmath.vector4(0.0, 0.9, 1.0, 1.0)
local C_T2 = vmath.vector4(1.0, 0.25, 0.2, 1.0)
local tmp = vmath.vector4()
local SCORE_RATE = 0.5 -- points per second per held beacon (all 3 held: ~67 s to 100, 2 held: 100 s)

local function tint(b, c, a)
    go.set(b.slot.mesh, "tint", c)
    tmp.x, tmp.y, tmp.z, tmp.w = c.x, c.y, c.z, a
    go.set(b.slot.zone, "tint", tmp)
end

function M.setup(match, api)
    api.build_environment()
    match.beacons = {}
    for i, b in ipairs(match.layout.beacons) do
        local bs = pool_manager.get_beacon_slot(i)
        msg.post(bs.mesh, "enable")
        msg.post(bs.zone, "enable")
        local pos = vmath.vector3(b.x, b.y, b.z)
        go.set_position(pos, bs.id)
        go.set_scale(vmath.vector3(1, 1, 1), bs.id)
        local beacon = { id = b.id, pos = pos, radius = b.radius, owner = 0, capture = 0, slot = bs, contested = false }
        tint(beacon, C_NEUTRAL, 0.16)
        match.beacons[i] = beacon
    end
    api.spawn_player()
    api.spawn_pilots(1, match.cfg.allies or 3)
    api.spawn_pilots(2, match.cfg.enemies or 4)
    match.score_kind = "percent"
    match.score_target = match.cfg.params.target_score or 100
    api.hint("hint_dom", 5.0)
end

function M.update(match, api, dt)
    local p = match.player
    for i = 1, #match.beacons do
        local b = match.beacons[i]
        local t1, t2 = 0, 0
        local r_sq = b.radius * b.radius
        for s = 1, #match.ships do
            local ship = match.ships[s]
            if ship.alive and (ship.ai == "pilot" or ship.is_player) and math3d.vec_dist_sq(ship.pos, b.pos) <= r_sq then
                if ship.team == 1 then t1 = t1 + (ship.is_player and 1.5 or 1) else t2 = t2 + 1 end
            end
        end
        b.contested = t1 > 0 and t2 > 0
        b.player_inside = p and p.alive and math3d.vec_dist_sq(p.pos, b.pos) <= r_sq
        local diff = t1 - t2
        local prev_owner = b.owner
        if diff ~= 0 then
            b.capture = math3d.clamp(b.capture + diff * 16.0 * dt, -100, 100)
            if b.capture >= 75 then b.owner = 1
            elseif b.capture <= -75 then b.owner = 2
            elseif math.abs(b.capture) < 25 then b.owner = 0 end
        end
        if b.owner ~= prev_owner then
            if b.owner == 1 then
                api.banner("beacon_captured", "aqua", b.id, 1.8)
                audio.play("objective", 0.55)
                if b.player_inside then api.track("beacons", 1) end
            elseif b.owner == 2 then
                api.banner("beacon_lost", "coral", b.id, 1.8)
                audio.play("alarm", 0.4)
            end
        end
        local pulse = 0.12 + (b.contested and 0.1 * math.abs(math.sin(match.time_elapsed * 8)) or 0)
        if b.owner == 1 then
            match.score[1] = match.score[1] + SCORE_RATE * dt
            tint(b, C_T1, pulse + 0.04)
        elseif b.owner == 2 then
            match.score[2] = match.score[2] + SCORE_RATE * dt
            tint(b, C_T2, pulse + 0.04)
        else
            tint(b, C_NEUTRAL, pulse + 0.04)
        end
    end
    local owned = 0
    for i = 1, #match.beacons do if match.beacons[i].owner == 1 then owned = owned + 1 end end
    api.set_objective("obj_dom", owned, #match.beacons, match.score[1] / 100)
    if match.score[1] >= 100 then
        match.score[1] = 100; api.finish(true)
    elseif match.score[2] >= 100 then
        match.score[2] = 100; api.finish(false)
    end
end

function M.on_timeout(match)
    return match.score[1] >= match.score[2]
end

return M
