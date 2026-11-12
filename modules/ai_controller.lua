local bots_db = require("data.bots_db")
local math3d = require("modules.math3d")
local flight_physics = require("modules.flight_physics")
local combat_manager = require("modules.combat_manager")

local M = {}

local function pick_target(bot, all_ships, beacons, boss_parts, mode)
    local best_enemy = nil
    local best_sq = 1e9
    for i = 1, #all_ships do
        local other = all_ships[i]
        if other.alive and other.team ~= bot.team then
            local d_sq = math3d.vec_dist_sq(bot.pos, other.pos)
            -- Aggressor prefers hunting player slightly
            if bot.archetype == "aggressor" and other.is_player then
                d_sq = d_sq * 0.72
            end
            if d_sq < best_sq then
                best_sq = d_sq
                best_enemy = other
            end
        end
    end

    if mode == "boss" and boss_parts then
        local best_bp = nil
        local bp_sq = 1e9
        for i = 1, #boss_parts do
            local bp = boss_parts[i]
            if bp.alive and bp.targetable then
                local d_sq = math3d.vec_dist_sq(bot.pos, bp.pos)
                if d_sq < bp_sq then bp_sq = d_sq; best_bp = bp end
            end
        end
        if best_bp then return best_bp, nil end
    end

    if mode == "domination" and beacons and #beacons > 0 then
        local desired_beacon = nil
        local best_b_sq = 1e9
        for i = 1, #beacons do
            local b = beacons[i]
            if b.owner ~= bot.team then
                local d_sq = math3d.vec_dist_sq(bot.pos, b.pos)
                if d_sq < best_b_sq then best_b_sq = d_sq; desired_beacon = b end
            end
        end
        if bot.archetype == "defender" and desired_beacon then
            return best_enemy, desired_beacon.pos
        elseif desired_beacon and (not best_enemy or best_b_sq < 90 * 90) then
            return best_enemy, desired_beacon.pos
        end
    end

    return best_enemy, nil
end

local function compute_avoidance(pos, obstacles)
    local ax, ay, az = 0, 0, 0
    for i = 1, #obstacles do
        local obs = obstacles[i]
        local dx, dy, dz, d_sq, avoid_r
        if obs.kind == "torus" then
            dx, dy, dz, d_sq = flight_physics.torus_closest_offset(pos.x, pos.y, pos.z, obs)
            avoid_r = obs.minor_r + 14.0
        else
            dx = pos.x - obs.x
            dy = pos.y - obs.y
            dz = pos.z - obs.z
            d_sq = dx * dx + dy * dy + dz * dz
            avoid_r = obs.r + 18.0
        end
        if d_sq < avoid_r * avoid_r and d_sq > 0.001 then
            local d = math.sqrt(d_sq)
            local strength = (avoid_r - d) / avoid_r
            ax = ax + (dx / d) * strength * 2.4
            ay = ay + (dy / d) * strength * 2.4
            az = az + (dz / d) * strength * 2.4
        end
    end
    return ax, ay, az
end

local function has_boss_telegraph(bot, boss_parts, mode)
    if mode ~= "boss" or not boss_parts then return false end
    for i = 1, #boss_parts do
        local bp = boss_parts[i]
        if bp.alive and bp.salvo_telegraph and bp.salvo_telegraph > 0 and bp.salvo_telegraph <= 0.45 and bp.salvo_target == bot then
            return true
        end
    end
    return false
end

function M.update_bot(bot, all_ships, beacons, boss_parts, mode, time_now, dt)
    if not bot.alive then return end

    local arch = bots_db.ARCHETYPES[bot.archetype] or bots_db.ARCHETYPES.tactician
    local target, nav_point = pick_target(bot, all_ships, beacons, boss_parts, mode)
    bot.locked_target = target

    -- Reactive Dash & evasive maneuver on incoming missiles or heavy fire
    local missile_threat = combat_manager.has_incoming_missile(bot) or has_boss_telegraph(bot, boss_parts, mode)
    local heavy_fire = (bot.under_fire_timer or 0) > 0 and ((bot.recent_dmg or 0) >= bot.max_hull * 0.16 or (bot.shield <= 0 and bot.hull < bot.max_hull * 0.65))
    if bot.dash_cd <= 0 then
        local trigger = false
        if missile_threat and math.random() < (3.2 + arch.dash_chance * 3.0) * dt then
            trigger = true
        elseif heavy_fire and math.random() < (1.4 + arch.dash_chance * 2.2) * dt then
            trigger = true
        end
        if trigger and combat_manager.activate_dash(bot) then
            bot.evade_timer = 0.8
            bot.recent_dmg = 0
            if math.random() < 0.5 then
                bot.evade_sign = -(bot.evade_sign or 1)
            end
        end
    end

    local goal_pos = nav_point
    if not goal_pos and target then
        local d_sq = math3d.vec_dist_sq(bot.pos, target.pos)
        local pref = arch.preferred_range
        if d_sq < (pref * 0.55) ^ 2 then
            -- Peel off / orbit so bots don't collide head-on
            local side = vmath.vector3(math.sin(time_now * 0.9 + bot.slot_idx), 0.25, math.cos(time_now * 0.9 + bot.slot_idx))
            goal_pos = target.pos + side * pref
        else
            goal_pos = target.pos
        end
    elseif not goal_pos then
        goal_pos = vmath.vector3(math.sin(time_now * 0.4 + bot.slot_idx) * 80, 12, math.cos(time_now * 0.4 + bot.slot_idx) * 80)
    end

    local desired = math3d.normalize_or_default(goal_pos - bot.pos, bot.forward)
    if bot.evade_timer and bot.evade_timer > 0 then
        bot.evade_timer = math.max(0, bot.evade_timer - dt)
        local sign = bot.evade_sign or 1
        desired.x = desired.x + (-bot.forward.z) * sign * 1.35
        desired.y = desired.y + 0.35 * sign
        desired.z = desired.z + bot.forward.x * sign * 1.35
    end
    local ax, ay, az = compute_avoidance(bot.pos, flight_physics.get_obstacles())
    desired.x = desired.x + ax
    desired.y = desired.y + ay
    desired.z = desired.z + az

    flight_physics.update_ship(bot, desired, dt)

    -- Combat firing & module usage
    if target and target.alive then
        local to_t = target.pos - bot.pos
        local d_sq = to_t.x * to_t.x + to_t.y * to_t.y + to_t.z * to_t.z
        local range_sq = bot.weapon_range * bot.weapon_range
        local dir_t = math3d.normalize_or_default(to_t)
        local dot = bot.forward.x * dir_t.x + bot.forward.y * dir_t.y + bot.forward.z * dir_t.z

        if d_sq <= range_sq and dot > 0.86 then
            combat_manager.fire_primary(bot, target, false)
        end

        -- Smart active modules
        if bot.mod1_cd <= 0 and dot > 0.75 and math.random() < arch.mod_aggression * dt * 1.4 then
            if bot.class_id == "interceptor" and d_sq > 45 * 45 then
                combat_manager.activate_module(bot, 1, all_ships, boss_parts)
            elseif bot.class_id == "fighter" and d_sq < 185 * 185 then
                combat_manager.activate_module(bot, 1, all_ships, boss_parts)
            elseif bot.class_id == "frigate" and (bot.shield < bot.max_shield * 0.5 or bot.hull < bot.max_hull * 0.8) then
                combat_manager.activate_module(bot, 1, all_ships, boss_parts)
            end
        end

        if bot.mod2_cd <= 0 and math.random() < arch.mod_aggression * dt * 1.2 then
            if bot.class_id == "interceptor" and d_sq <= 24 * 24 then
                combat_manager.activate_module(bot, 2, all_ships, boss_parts)
            elseif bot.class_id == "fighter" and dot > 0.85 and d_sq <= range_sq then
                combat_manager.activate_module(bot, 2, all_ships, boss_parts)
            elseif bot.class_id == "frigate" and bot.hull < bot.max_hull * 0.65 then
                combat_manager.activate_module(bot, 2, all_ships, boss_parts)
            end
        end

        if bot.dash_cd <= 0 and d_sq > 130 * 130 and math.random() < arch.dash_chance * dt then
            combat_manager.activate_dash(bot)
        end
    end
end

return M
