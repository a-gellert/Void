-- Bot brains. Kinds:
--  pilot    full dogfighter: objective-aware targeting, retreat to repairs, strafe weave,
--           missiles, situational modules, reactive dash.
--  drone    pirate drone: harass the nearest target (player preferred), weak lasers.
--  kamikaze rams the target (player / VIP / station) and detonates.
--  dummy    tutorial target: slow orbit around an anchor, never fires.
-- `ctx` (built by match_controller every frame):
--   ships, structures, beacons, pickups, mode, time, vip, station, skill(team) -> table
local bots_db = require("data.bots_db")
local math3d = require("modules.math3d")
local flight_physics = require("modules.flight_physics")
local combat_manager = require("modules.combat_manager")

local M = {}

local ctl = { boost = false, brake = false, strafe = 0 }

local function compute_avoidance(pos, obstacles, extra)
    local ax, ay, az = 0, 0, 0
    for i = 1, #obstacles do
        local obs = obstacles[i]
        local dx, dy, dz, d_sq, avoid_r
        if obs.kind == "torus" then
            dx, dy, dz, d_sq = flight_physics.torus_closest_offset(pos.x, pos.y, pos.z, obs)
            avoid_r = obs.minor_r + 14.0 + extra
        else
            dx = pos.x - obs.x
            dy = pos.y - obs.y
            dz = pos.z - obs.z
            d_sq = dx * dx + dy * dy + dz * dz
            avoid_r = obs.r + 18.0 + extra
        end
        if d_sq < avoid_r * avoid_r and d_sq > 0.001 then
            local d = math.sqrt(d_sq)
            local strength = (avoid_r - d) / avoid_r
            ax = ax + (dx / d) * strength * 2.6
            ay = ay + (dy / d) * strength * 2.6
            az = az + (dz / d) * strength * 2.6
        end
    end
    return ax, ay, az
end

local function targetable(bot, o)
    if not o.alive or o.team == bot.team then return false end
    if (o.cloak_timer or 0) > 0 and math3d.vec_dist_sq(bot.pos, o.pos) > 28 * 28 then return false end
    return true
end

-- Pick an enemy ship, biased by archetype, distance and objective.
local function pick_ship_target(bot, ctx, anchor, anchor_r)
    local best, best_score = nil, 1e18
    local ships = ctx.ships
    for i = 1, #ships do
        local o = ships[i]
        if targetable(bot, o) then
            local d_sq = math3d.vec_dist_sq(bot.pos, o.pos)
            local score = d_sq
            if o.is_player then score = score * (bot.archetype == "aggressor" and 0.6 or 0.85) end
            if o.hull < o.max_hull * 0.4 then score = score * 0.75 end
            if o.is_vip then score = score * (bot.vip_bias or 1.0) end
            if anchor and math3d.vec_dist_sq(o.pos, anchor) > anchor_r * anchor_r then score = score * 3.0 end
            if o == bot.ai_target then score = score * 0.7 end
            if score < best_score then best_score = score; best = o end
        end
    end
    return best
end

local function pick_structure_target(bot, ctx)
    if not ctx.structures then return nil end
    local best, best_sq = nil, 1e18
    for i = 1, #ctx.structures do
        local s = ctx.structures[i]
        if s.alive and s.team ~= bot.team and s.targetable then
            local d_sq = math3d.vec_dist_sq(bot.pos, s.pos)
            if d_sq < best_sq then best_sq = d_sq; best = s end
        end
    end
    return best
end

local function choose_beacon(bot, beacons)
    local desired, best_sq = nil, 1e18
    for i = 1, #beacons do
        local b = beacons[i]
        local want = b.owner ~= bot.team or b.contested
        if bot.archetype == "defender" and b.owner == bot.team then want = true end
        if want then
            local d_sq = math3d.vec_dist_sq(bot.pos, b.pos)
            -- Spread the team across beacons using the slot index.
            d_sq = d_sq * (1 + ((bot.slot_idx + i) % 3) * 0.35)
            if d_sq < best_sq then best_sq = d_sq; desired = b end
        end
    end
    return desired
end

local function nearest_pickup(bot, pickups, kind, max_d)
    local best, best_sq = nil, max_d * max_d
    for i = 1, #pickups do
        local p = pickups[i]
        if p.active and p.kind == kind then
            local d_sq = math3d.vec_dist_sq(bot.pos, p.pos)
            if d_sq < best_sq then best_sq = d_sq; best = p end
        end
    end
    return best
end

local function threat_dash(bot, skill, dt)
    if bot.dash_cd > 0 then return end
    local missile_threat = combat_manager.has_incoming_missile(bot) or bot.salvo_threat
    local heavy = (bot.under_fire_timer or 0) > 0 and ((bot.recent_dmg or 0) >= bot.max_hull * 0.18)
    local p = 0
    if missile_threat then p = 3.5 * skill.reaction elseif heavy then p = 1.6 * skill.reaction end
    if p > 0 and math.random() < p * dt then
        if combat_manager.activate_dash(bot, bot.evade_sign) then
            bot.evade_timer = 0.8
            bot.recent_dmg = 0
            bot.evade_sign = -(bot.evade_sign or 1)
        end
    end
end

local function use_modules(bot, ctx, target, d_sq, dot, skill, dt)
    local chance = skill.module_use * dt * 1.6
    for slot = 1, 2 do
        local mod = (slot == 1) and bot.mod1 or bot.mod2
        if mod and combat_manager.module_ready(bot, slot) and math.random() < chance then
            local use = false
            local hp = bot.hull / bot.max_hull
            if mod == "microwarp" then
                use = (target and dot > 0.85 and d_sq > 90 * 90 and d_sq < 200 * 200) or combat_manager.has_incoming_missile(bot)
            elseif mod == "emp" then
                use = target and d_sq < 28 * 28
            elseif mod == "cloak" then
                use = (hp < 0.45) or (target and d_sq > 70 * 70 and d_sq < 160 * 160 and dot > 0.7)
            elseif mod == "overdrive" then
                use = target and dot > 0.85 and d_sq < bot.weapon_range * bot.weapon_range
            elseif mod == "swarm" then
                use = target and d_sq < 200 * 200
            elseif mod == "nanorepair" then
                use = hp < 0.6
            elseif mod == "energydome" then
                use = (bot.under_fire_timer or 0) > 0 and (bot.shield < bot.max_shield * 0.5)
            elseif mod == "repairdrone" then
                use = hp < 0.65
            elseif mod == "pulse" then
                use = (target and d_sq < 45 * 45) or bot.shield < bot.max_shield * 0.3
            end
            if use then combat_manager.activate_module(bot, slot, ctx.ships, ctx.structures) end
        end
    end
end

local function steer_and_fight(bot, ctx, target, goal_pos, skill, dt, opts)
    local desired = math3d.normalize_or_default(goal_pos - bot.pos, bot.forward)
    if bot.evade_timer and bot.evade_timer > 0 then
        bot.evade_timer = math.max(0, bot.evade_timer - dt)
        local sign = bot.evade_sign or 1
        desired.x = desired.x + (-bot.forward.z) * sign * 1.35
        desired.y = desired.y + 0.35 * sign
        desired.z = desired.z + bot.forward.x * sign * 1.35
    end
    local ax, ay, az = compute_avoidance(bot.pos, flight_physics.get_obstacles(), bot.radius)
    desired.x = desired.x + ax
    desired.y = desired.y + ay
    desired.z = desired.z + az
    flight_physics.update_ai(bot, desired, ctl, dt)

    if target and target.alive and bot.has_weapon then
        local to_t = target.pos - bot.pos
        local d_sq = vmath.dot(to_t, to_t)
        local dir_t = math3d.normalize_or_default(to_t)
        local dot = vmath.dot(bot.forward, dir_t)
        local rng = bot.weapon_range * ((opts and opts.range_mult) or 1)
        if d_sq <= rng * rng and dot > skill.fire_cone then
            bot.aim_error = skill.aim_error
            combat_manager.fire_primary(bot, target, nil)
        end
        return d_sq, dot
    end
    return 1e18, 0
end

-- ================================================================== PILOT
local function update_pilot(bot, ctx, dt)
    local arch = bots_db.ARCHETYPES[bot.archetype] or bots_db.ARCHETYPES.tactician
    local skill = ctx.skill(bot.team)
    threat_dash(bot, skill, dt)

    -- Retarget periodically
    bot.ai_retarget = (bot.ai_retarget or 0) - dt
    local target = bot.ai_target
    if bot.ai_retarget <= 0 or not target or not target.alive or ((target.cloak_timer or 0) > 0) then
        bot.ai_retarget = 0.7 + math.random() * 0.6
        target = nil
        local anchor, anchor_r = nil, nil
        if ctx.mode == "survival" and ctx.station and ctx.station.alive then
            if bot.team == 1 then anchor, anchor_r = ctx.station.pos, 130 end
        elseif ctx.mode == "escort" and ctx.vip and ctx.vip.alive then
            if bot.team == 1 then anchor, anchor_r = ctx.vip.pos, 120 end
        end
        if ctx.mode == "boss" and bot.team == 1 and math.random() < 0.75 then
            target = pick_structure_target(bot, ctx)
        elseif bot.team == 2 and ctx.station and ctx.station.alive and ctx.mode == "survival" and math.random() < 0.45 then
            target = ctx.station
        end
        if not target then target = pick_ship_target(bot, ctx, anchor, anchor_r) end
        if not target and ctx.structures then target = pick_structure_target(bot, ctx) end
        bot.ai_target = target
        bot.locked_target = target
    end

    -- Goal position
    local goal = nil
    local hp = bot.hull / bot.max_hull
    ctl.boost, ctl.brake, ctl.strafe = false, false, 0
    if skill.retreat_hp > 0 and hp < skill.retreat_hp and ctx.pickups then
        local pk = nearest_pickup(bot, ctx.pickups, "repair", 220)
        if pk then
            goal = pk.pos
            ctl.boost = bot.energy > bot.max_energy * 0.3
        end
    end
    if not goal and ctx.mode == "domination" and ctx.beacons and #ctx.beacons > 0 then
        local b = choose_beacon(bot, ctx.beacons)
        if b then
            local d_b = math3d.vec_dist_sq(bot.pos, b.pos)
            local engage = target and target.alive and math3d.vec_dist_sq(bot.pos, target.pos) < 90 * 90
            if not engage or d_b > 160 * 160 then
                if d_b > (b.radius * 0.6) ^ 2 then
                    goal = b.pos
                else
                    local a = ctx.time * 0.9 + bot.slot_idx
                    goal = b.pos + vmath.vector3(math.sin(a) * b.radius * 0.5, math.cos(a * 0.7) * 4, math.cos(a) * b.radius * 0.5)
                end
                if d_b > 120 * 120 then ctl.boost = bot.energy > bot.max_energy * 0.5 end
            end
        end
    end
    if not goal and target and target.alive then
        local d_sq = math3d.vec_dist_sq(bot.pos, target.pos)
        local pref = arch.preferred_range
        if target.is_structure then pref = math.min(pref, 120) end
        if d_sq < (pref * 0.55) ^ 2 then
            local a = ctx.time * 0.9 + bot.slot_idx
            local side = vmath.vector3(math.sin(a), 0.25 * math.sin(a * 1.7), math.cos(a))
            goal = target.pos + side * pref
            local to_t = math3d.normalize_or_default(target.pos - bot.pos)
            if vmath.dot(bot.forward, to_t) < 0.2 then ctl.brake = true end
        else
            goal = target.pos
            if d_sq > 170 * 170 then ctl.boost = bot.energy > bot.max_energy * 0.45 end
        end
        if d_sq < bot.weapon_range * bot.weapon_range then
            ctl.strafe = math.sin(ctx.time * 1.4 + bot.slot_idx * 1.7) * arch.strafe_amp
        end
    end
    if not goal then
        local a = ctx.time * 0.35 + bot.slot_idx
        goal = vmath.vector3(math.sin(a) * 80, 12, math.cos(a) * 80)
    end

    local d_sq, dot = steer_and_fight(bot, ctx, target, goal, skill, dt)

    if target and target.alive then
        if skill.missile_use and (bot.missiles or 0) > 0 and d_sq < 220 * 220 and dot > 0.6
            and math.random() < 0.35 * dt * skill.reaction and not target.is_structure then
            combat_manager.fire_missile(bot, target)
        end
        use_modules(bot, ctx, target, d_sq, dot, skill, dt)
    elseif hp < 0.6 then
        use_modules(bot, ctx, nil, 1e18, 0, skill, dt)
    end
end

-- ================================================================== DRONE
local function update_drone(bot, ctx, dt)
    local skill = ctx.skill(bot.team)
    bot.ai_retarget = (bot.ai_retarget or 0) - dt
    local target = bot.ai_target
    if bot.ai_retarget <= 0 or not target or not target.alive then
        bot.ai_retarget = 1.0 + math.random() * 0.8
        target = nil
        if ctx.mode == "survival" and ctx.station and ctx.station.alive and (bot.slot_idx % 3 == 0) then
            target = ctx.station
        elseif ctx.mode == "escort" and ctx.vip and ctx.vip.alive and (bot.slot_idx % 2 == 0) then
            target = ctx.vip
        end
        target = target or pick_ship_target(bot, ctx, nil, nil)
        bot.ai_target = target
    end
    ctl.boost, ctl.brake, ctl.strafe = false, false, 0
    local goal
    if target and target.alive then
        local d_sq = math3d.vec_dist_sq(bot.pos, target.pos)
        local keep = target.is_structure and 45 or (target.is_vip and 40 or 55)
        if d_sq < keep * keep then
            local a = ctx.time * 1.1 + bot.slot_idx * 2.1
            goal = target.pos + vmath.vector3(math.sin(a) * keep * 1.2, math.cos(a * 0.8) * 12, math.cos(a) * keep * 1.2)
        else
            goal = target.pos
        end
        ctl.strafe = math.sin(ctx.time * 2.0 + bot.slot_idx) * 0.6
    else
        goal = vmath.vector3(0, 0, 0)
    end
    steer_and_fight(bot, ctx, target, goal, skill, dt, { range_mult = 1.0 })
end

-- =============================================================== KAMIKAZE
local function update_kamikaze(bot, ctx, dt)
    bot.ai_retarget = (bot.ai_retarget or 0) - dt
    local target = bot.ai_target
    if bot.ai_retarget <= 0 or not target or not target.alive then
        bot.ai_retarget = 1.5
        target = nil
        if ctx.vip and ctx.vip.alive and bot.slot_idx % 2 == 0 then target = ctx.vip end
        if not target and ctx.station and ctx.station.alive and bot.slot_idx % 2 == 0 then target = ctx.station end
        target = target or pick_ship_target(bot, ctx, nil, nil)
        bot.ai_target = target
    end
    ctl.boost, ctl.brake, ctl.strafe = false, false, 0
    local goal = (target and target.alive) and target.pos or vmath.vector3(0, 0, 0)
    local desired = math3d.normalize_or_default(goal - bot.pos, bot.forward)
    local ax, ay, az = compute_avoidance(bot.pos, flight_physics.get_obstacles(), 0)
    desired.x, desired.y, desired.z = desired.x + ax, desired.y + ay, desired.z + az
    flight_physics.update_ai(bot, desired, ctl, dt)
    if target and target.alive then
        local r = (target.radius or 4) + (bot.blast_radius or 14) * 0.55
        if math3d.vec_dist_sq(bot.pos, target.pos) < r * r then
            combat_manager.detonate(bot, ctx.ships, ctx.structures)
        end
    end
end

-- ================================================================== DUMMY
local function update_dummy(bot, ctx, dt)
    ctl.boost, ctl.brake, ctl.strafe = false, false, 0
    local a = ctx.time * 0.45 + bot.slot_idx * 1.3
    local anchor = bot.anchor or vmath.vector3(0, 0, 0)
    local goal = anchor + vmath.vector3(math.sin(a) * 26, math.sin(a * 1.3) * 8, math.cos(a) * 26)
    flight_physics.update_ai(bot, math3d.normalize_or_default(goal - bot.pos, bot.forward), ctl, dt)
end

function M.update_bot(bot, ctx, dt)
    if not bot.alive then return end
    local k = bot.ai
    if k == "pilot" then update_pilot(bot, ctx, dt)
    elseif k == "drone" then update_drone(bot, ctx, dt)
    elseif k == "kamikaze" then update_kamikaze(bot, ctx, dt)
    elseif k == "dummy" then update_dummy(bot, ctx, dt)
    end
end

return M
