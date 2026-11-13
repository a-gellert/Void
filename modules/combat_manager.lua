-- Weapons, missiles, modules and damage. Pure Lua collision (segment vs sphere).
-- Damageable entities: ships (match.ships) and structures (boss parts, station core).
local ships_db = require("data.ships_db")
local modules_db = require("data.modules_db")
local math3d = require("modules.math3d")
local pool_manager = require("modules.pool_manager")
local flight_physics = require("modules.flight_physics")
local camera_rig = require("modules.camera_rig")
local audio = require("modules.audio")

local M = {}

local active_lasers = {}
local active_missiles = {}
local cb = {}

local LOCK_SCREEN_RADIUS = 175.0
local ZERO = vmath.vector3(0, 0, 0)

-- ctx: { on_hit(target, attacker, dmg, is_kill, weapon), on_kill(victim, attacker, weapon),
--        on_structure_killed(s, attacker), on_module(ship, mod_id) }
function M.reset(ctx)
    for i = #active_lasers, 1, -1 do
        pool_manager.release_laser(active_lasers[i].pool_item)
        active_lasers[i] = nil
    end
    for i = #active_missiles, 1, -1 do
        pool_manager.release_missile(active_missiles[i].pool_item)
        active_missiles[i] = nil
    end
    cb = ctx or {}
end

function M.break_missile_locks(target_entity)
    for i = 1, #active_missiles do
        if active_missiles[i].target == target_entity then
            active_missiles[i].target = nil
        end
    end
end

function M.has_incoming_missile(entity)
    if not entity then return false, 0 end
    local count = 0
    for i = 1, #active_missiles do
        if active_missiles[i].target == entity then count = count + 1 end
    end
    return count > 0, count
end

local function is_hostile(a, b)
    return a.team ~= b.team
end

-- ============================================================ PROJECTILES
local function spawn_laser(owner, pos, dir, speed, damage, weapon_type, range, color)
    local item = pool_manager.acquire_laser()
    if not item then return end
    go.set_position(pos, item.id)
    go.set_rotation(math3d.quat_from_forward(dir, 0), item.id)
    go.set_scale(weapon_type == "railgun" and vmath.vector3(1.7, 1.7, 2.6) or vmath.vector3(1, 1, 1), item.id)
    go.set(item.url, "tint", vmath.vector4(color[1], color[2], color[3], 1.0))
    active_lasers[#active_lasers + 1] = {
        pool_item = item,
        owner = owner,
        team = owner.team,
        pos = vmath.vector3(pos.x, pos.y, pos.z),
        vel = dir * speed,
        damage = damage,
        weapon_type = weapon_type,
        life = range / speed,
    }
end

local function spawn_missile(owner, pos, dir, target, damage, opts)
    local item = pool_manager.acquire_missile()
    if not item then return end
    local cfg = modules_db.MISSILE
    local c = (opts and opts.color) or cfg.color
    go.set_position(pos, item.id)
    go.set_rotation(math3d.quat_from_forward(dir, 0), item.id)
    go.set_scale((opts and opts.scale) or vmath.vector3(1, 1, 1), item.id)
    go.set(item.url, "tint", vmath.vector4(c[1], c[2], c[3], 1.0))
    active_missiles[#active_missiles + 1] = {
        pool_item = item,
        owner = owner,
        team = owner.team,
        pos = vmath.vector3(pos.x, pos.y, pos.z),
        forward = vmath.vector3(dir.x, dir.y, dir.z),
        speed = (opts and opts.speed) or cfg.speed,
        turn_rate = (opts and opts.turn_rate) or cfg.turn_rate,
        target = target,
        damage = damage,
        life = (opts and opts.life) or cfg.life,
        tag = (opts and opts.tag) or "missile",
    }
end

-- ================================================================ DAMAGE
function M.apply_damage(target, raw_damage, weapon_type, attacker)
    if not target or not target.alive then return 0 end
    if target.invuln_timer and target.invuln_timer > 0 then return 0 end

    if target.is_structure and target.shielded then
        target.shield_hit_flash = 1.0
        pool_manager.spawn_vfx(target.pos, 0.25, 0.72, 1.0, 4.5, 0.25)
        return 0
    end

    local mult = ships_db.DAMAGE_MULT[weapon_type] or ships_db.DAMAGE_MULT.kinetic
    local dmg = raw_damage
    if target.dome_timer and target.dome_timer > 0 then
        dmg = dmg * (1.0 - modules_db.MODULES.energydome.damage_reduction)
    end
    if target.dmg_taken_mult then dmg = dmg * target.dmg_taken_mult end

    target.shield_regen_delay = 3.0
    target.hit_flash = 1.0
    if not target.is_structure then
        target.under_fire_timer = 0.85
        target.recent_dmg = (target.recent_dmg or 0) + dmg
        if attacker then target.last_attacker = attacker end
    end

    local before = (target.shield or 0) + target.hull
    if target.shield and target.shield > 0 then
        local shield_dmg = dmg * mult.shield
        if target.shield >= shield_dmg then
            target.shield = target.shield - shield_dmg
            if target.is_player then audio.play("shield_hit", 0.45) end
        else
            local overflow_ratio = (shield_dmg - target.shield) / shield_dmg
            target.shield = 0
            target.hull = target.hull - dmg * overflow_ratio * mult.hull
        end
    else
        target.hull = target.hull - dmg * mult.hull
    end
    local dealt = before - math.max(0, (target.shield or 0)) - math.max(0, target.hull)

    local is_kill = target.hull <= 0
    if cb.on_hit then cb.on_hit(target, attacker, dealt, is_kill, weapon_type) end

    if is_kill then
        target.hull = 0
        target.alive = false
        M.break_missile_locks(target)
        local big = target.is_structure or target.is_vip
        pool_manager.spawn_vfx(target.pos, 1.0, 0.55, 0.15, (target.radius or 4) * (big and 2.4 or 3.2), big and 0.9 or 0.55)
        pool_manager.spawn_vfx(target.pos, 1.0, 0.9, 0.6, (target.radius or 4) * 1.4, 0.3)
        if target.is_player or (attacker and attacker.is_player) or big then
            camera_rig.add_shake(big and 0.8 or 0.5)
            audio.play("explosion", 0.75)
        end
        if target.is_structure then
            if cb.on_structure_killed then cb.on_structure_killed(target, attacker) end
        elseif cb.on_kill then
            cb.on_kill(target, attacker, weapon_type)
        end
    end
    return dealt
end

-- ================================================================= LOCK-ON
local function lockable(player, c)
    if not c.alive or c.team == player.team then return false end
    if c.is_structure and not c.targetable then return false end
    if (c.cloak_timer or 0) > 0 then return false end
    return true
end

-- Soft lock: enemy closest to the screen centre inside the lock circle.
function M.acquire_player_lock(player, ships, structures, radius_px)
    if not player or not player.alive then return nil end
    local best = nil
    local lock_r = radius_px or LOCK_SCREEN_RADIUS
    local best_score = lock_r * lock_r
    local max_range_sq = (player.weapon_range * 1.2) ^ 2
    local prev = player.locked_target

    local function check(c)
        if not lockable(player, c) then return end
        local d_sq = math3d.vec_dist_sq(player.pos, c.pos)
        if d_sq > max_range_sq then return end
        local sx, sy, in_front = camera_rig.world_to_screen(c.pos.x, c.pos.y, c.pos.z)
        if not in_front then return end
        local dx = sx - 960.0
        local dy = sy - 540.0
        local scr_sq = dx * dx + dy * dy
        if c == prev then scr_sq = scr_sq * 0.55 end -- stickiness
        if scr_sq < best_score then
            best_score = scr_sq
            best = c
        end
    end
    for i = 1, #ships do check(ships[i]) end
    if structures then
        for i = 1, #structures do check(structures[i]) end
    end
    if best and best ~= prev then audio.play("lock", 0.35) end
    player.locked_target = best
    return best
end

-- ================================================================== FIRING
local function break_cloak(ship)
    if (ship.cloak_timer or 0) > 0 then
        ship.cloak_timer = 0
        pool_manager.set_ship_cloak(ship.pool_slot, 0)
    end
end

--- Fire primary weapon. target: entity for lead aim (optional); aim_point: fallback point.
function M.fire_primary(ship, target, aim_point)
    if not ship.alive or not ship.has_weapon or ship.fire_cd > 0 then return false end
    local rate = ship.weapon_rate * ((ship.overdrive_timer or 0) > 0 and modules_db.MODULES.overdrive.rate_mult or 1.0)
    ship.fire_cd = 1.0 / rate

    local target_pos
    if target and target.alive then
        target_pos = math3d.compute_lead_point(ship.pos, target.pos, target.vel or ZERO, ship.proj_speed)
        if ship.aim_error and ship.aim_error > 0 then
            local d = math.sqrt(math3d.vec_dist_sq(ship.pos, target_pos))
            local e = ship.aim_error * d
            target_pos = target_pos + vmath.vector3((math.random() * 2 - 1) * e, (math.random() * 2 - 1) * e, (math.random() * 2 - 1) * e)
        end
    elseif aim_point then
        target_pos = aim_point
    else
        target_pos = ship.pos + ship.forward * ship.weapon_range
    end

    local dmg_mult = ship.dmg_mult or 1.0
    if (ship.cloak_timer or 0) > 0 then
        dmg_mult = dmg_mult * modules_db.MODULES.cloak.ambush_mult
        break_cloak(ship)
    end
    local muzzles = ship.muzzle_offsets
    local dmg_per_bolt = ship.damage * dmg_mult / #muzzles
    for i = 1, #muzzles do
        local off = muzzles[i]
        local world_muzzle = ship.pos + vmath.rotate(ship.rot, vmath.vector3(off[1], off[2], off[3]))
        local dir = math3d.normalize_or_default(target_pos - world_muzzle, ship.forward)
        -- Never shoot backwards through the own hull.
        if vmath.dot(dir, ship.forward) < 0.2 then dir = ship.forward end
        spawn_laser(ship, world_muzzle, dir, ship.proj_speed, dmg_per_bolt, ship.weapon_type, ship.weapon_range, ship.proj_color)
    end

    if ship.is_player then
        local sfx = (ship.weapon_type == "plasma" and "laser") or ship.weapon_type
        audio.play(sfx, 0.42)
    end
    return true
end

function M.fire_missile(ship, target)
    if not ship.alive or (ship.missiles or 0) <= 0 then return false end
    if not target or not target.alive then return false end
    ship.missiles = ship.missiles - 1
    if ship.missile_cd <= 0 then ship.missile_cd = modules_db.MISSILE.recharge end
    break_cloak(ship)
    local side = (ship.missiles % 2 == 0) and 1 or -1
    local p = ship.pos + vmath.rotate(ship.rot, vmath.vector3(side * 1.6, -0.6, -0.5))
    local dmg = modules_db.MISSILE.damage * (1 + 0.15 * ((ship.tier or 1) - 1)) * (ship.dmg_mult or 1)
    spawn_missile(ship, p, ship.forward, target, dmg, { tag = "missile" })
    audio.play("missile", ship.is_player and 0.6 or 0.3)
    return true
end

function M.fire_turret(turret, target_ship, dmg_mult)
    if not turret.alive or not target_ship or not target_ship.alive then return end
    local aim = math3d.compute_lead_point(turret.pos, target_ship.pos, target_ship.vel or ZERO, 210)
    local dir = math3d.normalize_or_default(aim - turret.pos)
    turret.rot = math3d.quat_from_forward(dir, 0)
    spawn_laser(turret, turret.pos + dir * 4.5, dir, 210, turret.damage * (dmg_mult or 1), "plasma", 270, { 1.0, 0.25, 0.15 })
end

function M.fire_turret_salvo(turret, target_ship, count, dmg_mult)
    if not turret.alive or not target_ship or not target_ship.alive then return end
    local dir = math3d.normalize_or_default(target_ship.pos - turret.pos)
    turret.rot = math3d.quat_from_forward(dir, 0)
    local n = count or 2
    local dmg = (turret.damage or 18) * 1.35 * (dmg_mult or 1)
    local opts = { speed = 118, turn_rate = 3.8, life = 4.2, color = { 1.0, 0.22, 0.12 }, tag = "salvo" }
    local right = math3d.normalize_or_default(vmath.cross(dir, vmath.vector3(0, 1, 0)), vmath.vector3(1, 0, 0))
    for i = 1, n do
        local spread = (i - (n + 1) * 0.5) * 2.4
        local spawn_pos = turret.pos + dir * 5.0 + right * spread + vmath.vector3(0, 1.5, 0)
        local launch_dir = math3d.normalize_or_default(dir + right * (spread * 0.08) + vmath.vector3(0, 0.14, 0), dir)
        spawn_missile(turret, spawn_pos, launch_dir, target_ship, dmg, opts)
    end
    pool_manager.spawn_vfx(turret.pos + dir * 4.5, 1.0, 0.32, 0.12, 6.0, 0.35)
    audio.play("missile", 0.6)
end

-- ======================================================== DASH & MODULES
function M.activate_dash(ship, sign)
    if not ship.alive or ship.dash_cd > 0 then return false end
    local cfg = modules_db.DASH
    ship.dash_cd = cfg.cooldown
    ship.dash_timer = cfg.duration
    ship.dash_duration = cfg.duration
    ship.dash_roll_sign = sign or ((math.random() < 0.5) and 1 or -1)
    M.break_missile_locks(ship)
    if ship.is_player then audio.play("dash", 0.65) end
    return true
end

local function nearest_enemy(ship, ships, max_dist, exclude)
    local best, best_sq = nil, max_dist * max_dist
    for i = 1, #ships do
        local o = ships[i]
        if o.alive and o.team ~= ship.team and o ~= exclude and (o.cloak_timer or 0) <= 0 then
            local d_sq = math3d.vec_dist_sq(ship.pos, o.pos)
            if d_sq < best_sq then best_sq = d_sq; best = o end
        end
    end
    return best
end

function M.module_ready(ship, slot_idx)
    local cd = (slot_idx == 1) and ship.mod1_cd or ship.mod2_cd
    return ship.alive and cd <= 0
end

function M.activate_module(ship, slot_idx, ships, structures)
    if not ship.alive then return false end
    local mod_id = (slot_idx == 1) and ship.mod1 or ship.mod2
    local cd_key = (slot_idx == 1) and "mod1_cd" or "mod2_cd"
    if not mod_id or ship[cd_key] > 0 then return false end
    local cfg = modules_db.MODULES[mod_id]
    if not cfg then return false end
    ship[cd_key] = cfg.cooldown
    ship[cd_key .. "_max"] = cfg.cooldown
    local loud = ship.is_player

    if mod_id == "microwarp" then
        pool_manager.spawn_vfx(ship.pos, 0.0, 0.9, 1.0, 6.0, 0.3)
        ship.pos = ship.pos + ship.forward * cfg.distance
        ship.invuln_timer = cfg.invuln_duration
        ship.warp_flash = cfg.invuln_duration
        M.break_missile_locks(ship)
        pool_manager.spawn_vfx(ship.pos, 0.0, 0.9, 1.0, 7.0, 0.35)
        if loud then audio.play("dash", 0.7) end
    elseif mod_id == "emp" then
        local r_sq = cfg.radius * cfg.radius
        pool_manager.spawn_vfx(ship.pos, 0.85, 0.3, 1.0, cfg.radius, 0.45)
        for i = 1, #ships do
            local o = ships[i]
            if o.alive and o.team ~= ship.team and math3d.vec_dist_sq(ship.pos, o.pos) <= r_sq then
                if o.shield and o.shield > 0 then o.shield = 0 end
                o.shield_regen_delay = cfg.block_regen
                M.apply_damage(o, cfg.damage, "explosion", ship)
            end
        end
        audio.play("emp", loud and 0.7 or 0.3)
    elseif mod_id == "cloak" then
        ship.cloak_timer = cfg.duration
        pool_manager.set_ship_cloak(ship.pool_slot, 1.0)
        M.break_missile_locks(ship)
        -- Enemies lose their lock on a cloaked ship.
        for i = 1, #ships do
            if ships[i].locked_target == ship then ships[i].locked_target = nil end
            if ships[i].ai_target == ship then ships[i].ai_target = nil end
        end
        if loud then audio.play("emp", 0.45) end
    elseif mod_id == "overdrive" then
        ship.overdrive_timer = cfg.duration
        pool_manager.spawn_vfx(ship.pos, 1.0, 0.8, 0.15, 5.5, 0.35)
        if loud then audio.play("boost", 0.5) end
    elseif mod_id == "swarm" then
        -- Up to 3 targets: the lock first, then nearest enemies.
        local targets = {}
        local lt = ship.locked_target or ship.ai_target
        if lt and lt.alive and lt.team ~= ship.team then targets[1] = lt end
        local ex = targets[1]
        local t2 = nearest_enemy(ship, ships, 230, ex)
        if t2 then targets[#targets + 1] = t2 end
        if #targets < 3 then
            local t3 = nearest_enemy(ship, ships, 230, t2)
            if t3 and t3 ~= ex then targets[#targets + 1] = t3 end
        end
        if #targets == 0 and structures then
            for i = 1, #structures do
                local s = structures[i]
                if s.alive and s.targetable and s.team ~= ship.team then targets[1] = s; break end
            end
        end
        local dmg = cfg.damage * (1 + 0.15 * ((ship.tier or 1) - 1)) * (ship.dmg_mult or 1)
        local scale = vmath.vector3(0.7, 0.7, 0.7)
        for m = 1, cfg.count do
            local tgt = targets[((m - 1) % math.max(1, #targets)) + 1]
            local spread = vmath.vector3((m - 3.5) * 1.1, (m % 2 == 0 and 0.8 or -0.8), 0)
            local p = ship.pos + vmath.rotate(ship.rot, spread)
            local dir = math3d.normalize_or_default(ship.forward + vmath.rotate(ship.rot, spread * 0.12))
            spawn_missile(ship, p, dir, tgt, dmg, { speed = cfg.speed, turn_rate = cfg.turn_rate, life = cfg.life,
                color = cfg.color, scale = scale, tag = "swarm" })
        end
        audio.play("missile", loud and 0.6 or 0.25)
    elseif mod_id == "nanorepair" then
        ship.nano_timer = cfg.duration
        pool_manager.spawn_vfx(ship.pos, 0.35, 0.95, 0.65, 6.0, 0.4)
        if loud then audio.play("heal", 0.7) end
    elseif mod_id == "energydome" then
        ship.dome_timer = cfg.duration
        pool_manager.set_ship_dome(ship.pool_slot, true, 0.25, 0.72, 1.0, 0.35)
        if loud then audio.play("shield_hit", 0.65) end
    elseif mod_id == "repairdrone" then
        ship.hull = math.min(ship.max_hull, ship.hull + ship.max_hull * cfg.heal_pct)
        pool_manager.spawn_vfx(ship.pos, 0.35, 0.95, 0.65, 6.5, 0.45)
        local best_ally, best_sq = nil, cfg.radius * cfg.radius
        local best_ratio = 2
        for i = 1, #ships do
            local o = ships[i]
            if o ~= ship and o.alive and o.team == ship.team then
                local d_sq = math3d.vec_dist_sq(ship.pos, o.pos)
                local ratio = o.hull / math.max(1, o.max_hull)
                if d_sq <= best_sq and ratio < best_ratio then best_ratio = ratio; best_ally = o end
            end
        end
        if best_ally then
            best_ally.hull = math.min(best_ally.max_hull, best_ally.hull + best_ally.max_hull * cfg.heal_pct)
            pool_manager.spawn_vfx(best_ally.pos, 0.35, 0.95, 0.65, 6.5, 0.45)
        end
        if loud then audio.play("heal", 0.7) end
    elseif mod_id == "pulse" then
        local r_sq = cfg.radius * cfg.radius
        pool_manager.spawn_vfx(ship.pos, 0.55, 0.85, 1.0, cfg.radius, 0.5)
        for i = 1, #ships do
            local o = ships[i]
            if o.alive and math3d.vec_dist_sq(ship.pos, o.pos) <= r_sq then
                if o.team == ship.team then
                    o.shield = math.min(o.max_shield, o.shield + o.max_shield * cfg.shield_restore)
                    o.shield_regen_delay = 0
                elseif not o.is_vip then
                    local away = math3d.normalize_or_default(o.pos - ship.pos, o.forward)
                    o.pos = o.pos + away * cfg.push
                    M.apply_damage(o, cfg.damage, "explosion", ship)
                end
            end
        end
        audio.play("emp", loud and 0.7 or 0.3)
    end
    if cb.on_module then cb.on_module(ship, mod_id) end
    return true
end

--- Kamikaze drone detonation (damages everything hostile around it).
function M.detonate(ship, ships, structures)
    if not ship.alive then return end
    local r = ship.blast_radius or 14
    local dmg = (ship.blast_damage or 50) * (ship.dmg_mult or 1)
    pool_manager.spawn_vfx(ship.pos, 1.0, 0.45, 0.1, r * 1.1, 0.5)
    audio.play("explosion", 0.6)

    for i = 1, #ships do
        local o = ships[i]
        if o.alive and o.team ~= ship.team and math3d.vec_dist_sq(ship.pos, o.pos) <= (r + o.radius) ^ 2 then
            M.apply_damage(o, dmg, "explosion", ship)
            if o.is_player then camera_rig.add_shake(0.5) end
        end
    end
    if structures then
        for i = 1, #structures do
            local s = structures[i]
            if s.alive and s.team ~= ship.team and math3d.vec_dist_sq(ship.pos, s.pos) <= (r + s.radius) ^ 2 then
                M.apply_damage(s, dmg, "explosion", ship)
            end
        end
    end
    ship.self_destruct = true
    M.apply_damage(ship, 99999, "explosion", nil)
    ship.self_destruct = nil
end

-- ================================================================ UPDATE
-- Closest distance^2 from sphere centre c to segment p0 + t*(d), t in [0,1].
local function seg_dist_sq(p0x, p0y, p0z, dx, dy, dz, c)
    local wx, wy, wz = c.x - p0x, c.y - p0y, c.z - p0z
    local dd = dx * dx + dy * dy + dz * dz
    local t = 0
    if dd > 1e-9 then
        t = (wx * dx + wy * dy + wz * dz) / dd
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    local qx = p0x + dx * t - c.x
    local qy = p0y + dy * t - c.y
    local qz = p0z + dz * t - c.z
    return qx * qx + qy * qy + qz * qz
end

local function point_hits_obstacle(pos, obstacles)
    for o = 1, #obstacles do
        local obs = obstacles[o]
        if obs.kind == "torus" then
            local _, _, _, d_sq = flight_physics.torus_closest_offset(pos.x, pos.y, pos.z, obs)
            if d_sq <= obs.minor_r * obs.minor_r then return true end
        elseif not obs.no_projectile_block and math3d.dist_sq(pos.x, pos.y, pos.z, obs.x, obs.y, obs.z) <= obs.r * obs.r then
            return true
        end
    end
    return false
end

local function find_hit(p0x, p0y, p0z, dx, dy, dz, team, pad, ships, structures)
    for s = 1, #ships do
        local t = ships[s]
        if t.alive and t.team ~= team then
            local r = t.radius + pad
            if seg_dist_sq(p0x, p0y, p0z, dx, dy, dz, t.pos) <= r * r then return t end
        end
    end
    if structures then
        for b = 1, #structures do
            local t = structures[b]
            if t.alive and t.team ~= team then
                local r = t.radius + pad
                if seg_dist_sq(p0x, p0y, p0z, dx, dy, dz, t.pos) <= r * r then return t end
            end
        end
    end
    return nil
end

function M.update(ships, structures, dt)
    local obstacles = flight_physics.get_obstacles()

    for i = #active_lasers, 1, -1 do
        local l = active_lasers[i]
        l.life = l.life - dt
        local dx, dy, dz = l.vel.x * dt, l.vel.y * dt, l.vel.z * dt
        local hit_t = find_hit(l.pos.x, l.pos.y, l.pos.z, dx, dy, dz, l.team, 0.9, ships, structures)
        l.pos.x = l.pos.x + dx
        l.pos.y = l.pos.y + dy
        l.pos.z = l.pos.z + dz
        local hit = false
        if hit_t then
            M.apply_damage(hit_t, l.damage, l.weapon_type, l.owner)
            if hit_t.is_structure then
                pool_manager.spawn_vfx(l.pos, 1.0, 0.6, 0.2, 3.0, 0.2)
            else
                pool_manager.spawn_vfx(l.pos, 0.9, 0.95, 1.0, 2.2, 0.14)
            end
            hit = true
        elseif point_hits_obstacle(l.pos, obstacles) then
            hit = true
        end
        if hit or l.life <= 0 then
            pool_manager.release_laser(l.pool_item)
            table.remove(active_lasers, i)
        else
            go.set_position(l.pos, l.pool_item.id)
        end
    end

    for i = #active_missiles, 1, -1 do
        local m = active_missiles[i]
        m.life = m.life - dt
        local tgt = m.target
        if tgt and (not tgt.alive or (tgt.cloak_timer or 0) > 0) then
            m.target = nil
            tgt = nil
        end
        if tgt then
            local to_t = math3d.normalize_or_default(tgt.pos - m.pos, m.forward)
            m.forward = math3d.rotate_towards(m.forward, to_t, math.min(1.0, m.turn_rate * dt))
        end
        local dx = m.forward.x * m.speed * dt
        local dy = m.forward.y * m.speed * dt
        local dz = m.forward.z * m.speed * dt
        local hit_t = find_hit(m.pos.x, m.pos.y, m.pos.z, dx, dy, dz, m.team, 1.5, ships, structures)
        m.pos.x = m.pos.x + dx
        m.pos.y = m.pos.y + dy
        m.pos.z = m.pos.z + dz
        local hit = false
        if hit_t then
            M.apply_damage(hit_t, m.damage, m.tag == "salvo" and "missile" or "missile", m.owner)
            if m.owner and m.owner.is_player and not hit_t.alive and m.tag == "missile" and cb.on_missile_kill then
                cb.on_missile_kill(hit_t)
            end
            pool_manager.spawn_vfx(m.pos, 1.0, 0.45, 0.1, 4.8, 0.3)
            if hit_t.is_player then camera_rig.add_shake(0.35) end
            hit = true
        elseif point_hits_obstacle(m.pos, obstacles) then
            pool_manager.spawn_vfx(m.pos, 1.0, 0.55, 0.2, 3.8, 0.25)
            hit = true
        end
        if hit or m.life <= 0 then
            pool_manager.release_missile(m.pool_item)
            table.remove(active_missiles, i)
        else
            go.set_position(m.pos, m.pool_item.id)
            go.set_rotation(math3d.quat_from_forward(m.forward, 0), m.pool_item.id)
        end
    end
end

return M
