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
local on_kill_callback = nil
local on_boss_part_killed = nil
local on_hit_callback = nil

local LOCK_SCREEN_RADIUS = 175.0

function M.reset(kill_cb, boss_part_cb, hit_cb)
    for i = #active_lasers, 1, -1 do
        pool_manager.release_laser(active_lasers[i].pool_item)
        active_lasers[i] = nil
    end
    for i = #active_missiles, 1, -1 do
        pool_manager.release_missile(active_missiles[i].pool_item)
        active_missiles[i] = nil
    end
    on_kill_callback = kill_cb
    on_boss_part_killed = boss_part_cb
    on_hit_callback = hit_cb
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
        if active_missiles[i].target == entity then
            count = count + 1
        end
    end
    return count > 0, count
end

local function spawn_laser(owner, pos, dir, speed, damage, weapon_type, range, color)
    local item = pool_manager.acquire_laser()
    if not item then return end
    local rot = math3d.quat_from_forward(dir, 0)
    go.set_position(pos, item.id)
    go.set_rotation(rot, item.id)
    go.set_scale(weapon_type == "railgun" and vmath.vector3(1.6, 1.6, 2.2) or vmath.vector3(1, 1, 1), item.id)
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
    local mod = modules_db.MODULES.micromissiles
    local rot = math3d.quat_from_forward(dir, 0)
    local c = (opts and opts.color) or { 1.0, 0.55, 0.20 }
    go.set_position(pos, item.id)
    go.set_rotation(rot, item.id)
    go.set(item.url, "tint", vmath.vector4(c[1], c[2], c[3], 1.0))
    active_missiles[#active_missiles + 1] = {
        pool_item = item,
        owner = owner,
        team = owner.team,
        pos = vmath.vector3(pos.x, pos.y, pos.z),
        forward = vmath.vector3(dir.x, dir.y, dir.z),
        speed = (opts and opts.speed) or mod.speed,
        turn_rate = (opts and opts.turn_rate) or mod.turn_rate,
        target = target,
        damage = damage,
        life = (opts and opts.life) or mod.life,
    }
end

function M.apply_damage(target, raw_damage, weapon_type, attacker)
    if not target or not target.alive then return end
    if target.invuln_timer and target.invuln_timer > 0 then return end

    -- Boss shield protection check
    if target.is_boss_part and target.shielded then
        target.shield_hit_flash = 1.0
        pool_manager.spawn_vfx(target.pos, 0.25, 0.72, 1.0, 4.5, 0.25)
        return
    end

    local mult = ships_db.DAMAGE_MULT[weapon_type] or ships_db.DAMAGE_MULT.kinetic
    local dmg = raw_damage
    if target.dome_timer and target.dome_timer > 0 then
        dmg = dmg * (1.0 - modules_db.MODULES.energydome.damage_reduction)
    end

    target.shield_regen_delay = 3.0
    target.hit_flash = 1.0
    if not target.is_boss_part then
        target.under_fire_timer = 0.85
        target.recent_dmg = (target.recent_dmg or 0) + dmg
    end

    if target.shield and target.shield > 0 then
        local shield_dmg = dmg * mult.shield
        if target.shield >= shield_dmg then
            target.shield = target.shield - shield_dmg
            if target.is_player or (attacker and attacker.is_player) then
                audio.play("shield_hit", 0.45)
            end
        else
            local overflow_ratio = (shield_dmg - target.shield) / shield_dmg
            target.shield = 0
            target.hull = target.hull - dmg * overflow_ratio * mult.hull
        end
    else
        target.hull = target.hull - dmg * mult.hull
    end

    local is_kill = target.hull <= 0
    if attacker and attacker.is_player and target.team ~= attacker.team and on_hit_callback then
        on_hit_callback(target, attacker, is_kill)
    end

    if is_kill then
        target.hull = 0
        target.alive = false
        target.respawn_timer = 2.0
        M.break_missile_locks(target)
        pool_manager.spawn_vfx(target.pos, 1.0, 0.55, 0.15, (target.radius or 4) * 3.2, 0.55)
        if target.is_player or (attacker and attacker.is_player) then
            camera_rig.add_shake(target.is_boss_part and 0.85 or 0.55)
            audio.play("explosion", 0.75)
        end
        if target.is_boss_part then
            if on_boss_part_killed then on_boss_part_killed(target, attacker) end
        elseif on_kill_callback then
            on_kill_callback(target, attacker)
        end
    end
end

-- Find Soft Lock-On target for player inside center reticle circle
function M.acquire_player_lock(player, enemies, boss_parts)
    if not player or not player.alive then return nil end
    local best = nil
    local best_dist_sq = LOCK_SCREEN_RADIUS * LOCK_SCREEN_RADIUS
    local max_range_sq = (player.weapon_range * 1.15) ^ 2

    local function check_candidate(c)
        if not c.alive or c.team == player.team then return end
        if c.is_boss_part and not c.targetable then return end
        local d_sq = math3d.vec_dist_sq(player.pos, c.pos)
        if d_sq > max_range_sq then return end
        local sx, sy, in_front = camera_rig.world_to_screen(c.pos.x, c.pos.y, c.pos.z)
        if not in_front then return end
        local dx = sx - 960.0
        local dy = sy - 540.0
        local scr_sq = dx * dx + dy * dy
        if scr_sq < best_dist_sq then
            best_dist_sq = scr_sq
            best = c
        end
    end

    for i = 1, #enemies do check_candidate(enemies[i]) end
    if boss_parts then
        for i = 1, #boss_parts do check_candidate(boss_parts[i]) end
    end
    local prev = player.locked_target
    if best and best ~= prev then
        audio.play("lock", 0.40)
    end
    player.locked_target = best
    return best
end

function M.fire_primary(ship, aim_target, manual_fire)
    if not ship.alive or ship.fire_cd > 0 then return false end
    local rate = ship.weapon_rate * (ship.overdrive_timer > 0 and 1.5 or 1.0)
    ship.fire_cd = 1.0 / rate

    local target_pos
    if aim_target and aim_target.alive then
        target_pos = math3d.compute_lead_point(ship.pos, aim_target.pos, aim_target.vel or vmath.vector3(), ship.proj_speed)
    elseif manual_fire then
        target_pos = ship.pos + ship.forward * 120.0
    else
        return false
    end

    local muzzles = ship.muzzle_offsets
    local dmg_per_bolt = ship.damage / #muzzles
    for i = 1, #muzzles do
        local off = muzzles[i]
        local world_muzzle = ship.pos + vmath.rotate(ship.rot, vmath.vector3(off[1], off[2], off[3]))
        local dir = math3d.normalize_or_default(target_pos - world_muzzle, ship.forward)
        spawn_laser(ship, world_muzzle, dir, ship.proj_speed, dmg_per_bolt, ship.weapon_type, ship.weapon_range, ship.proj_color)
    end

    if ship.is_player then
        local sfx = (ship.weapon_type == "plasma" and "laser") or ship.weapon_type
        audio.play(sfx, 0.45)
    end
    return true
end

function M.fire_turret(turret, target_ship)
    if not turret.alive or not target_ship or not target_ship.alive then return end
    local aim = math3d.compute_lead_point(turret.pos, target_ship.pos, target_ship.vel or vmath.vector3(), 210)
    local dir = math3d.normalize_or_default(aim - turret.pos)
    turret.rot = math3d.quat_from_forward(dir, 0)
    spawn_laser(turret, turret.pos + dir * 4.5, dir, 210, turret.damage, "plasma", 260, { 1.0, 0.25, 0.15 })
end

function M.fire_turret_salvo(turret, target_ship, count)
    if not turret.alive or not target_ship or not target_ship.alive then return end
    local dir = math3d.normalize_or_default(target_ship.pos - turret.pos)
    turret.rot = math3d.quat_from_forward(dir, 0)
    local n = count or 2
    local dmg = (turret.damage or 18) * 1.35
    local opts = {
        speed = 118,
        turn_rate = 3.8,
        life = 4.2,
        color = { 1.0, 0.22, 0.12 },
    }
    local right = math3d.normalize_or_default(vmath.cross(dir, vmath.vector3(0, 1, 0)), vmath.vector3(1, 0, 0))
    for i = 1, n do
        local spread = (i - (n + 1) * 0.5) * 2.4
        local spawn_pos = turret.pos + dir * 5.0 + right * spread + vmath.vector3(0, 1.5, 0)
        local launch_dir = math3d.normalize_or_default(dir + right * (spread * 0.08) + vmath.vector3(0, 0.14, 0), dir)
        spawn_missile(turret, spawn_pos, launch_dir, target_ship, dmg, opts)
    end
    pool_manager.spawn_vfx(turret.pos + dir * 4.5, 1.0, 0.32, 0.12, 6.0, 0.35)
    audio.play("missile", 0.65)
end

function M.activate_dash(ship)
    if not ship.alive or ship.dash_cd > 0 then return false end
    local cfg = modules_db.DASH
    ship.dash_cd = cfg.cooldown
    ship.dash_timer = cfg.duration
    M.break_missile_locks(ship)
    if ship.is_player then audio.play("dash", 0.65) end
    return true
end

function M.activate_module(ship, slot_idx, all_ships, boss_parts)
    if not ship.alive then return false end
    local mod_id = (slot_idx == 1) and ship.mod1 or ship.mod2
    local cd_key = (slot_idx == 1) and "mod1_cd" or "mod2_cd"
    if ship[cd_key] > 0 then return false end

    local cfg = modules_db.MODULES[mod_id]
    if not cfg then return false end
    ship[cd_key] = cfg.cooldown

    if mod_id == "microwarp" then
        ship.pos = ship.pos + ship.forward * cfg.distance
        ship.invuln_timer = cfg.invuln_duration
        ship.warp_flash = cfg.invuln_duration
        M.break_missile_locks(ship)
        pool_manager.spawn_vfx(ship.pos, 0.0, 0.9, 1.0, 7.0, 0.35)
        if ship.is_player then audio.play("dash", 0.7) end
    elseif mod_id == "emp" then
        local r_sq = cfg.radius * cfg.radius
        pool_manager.spawn_vfx(ship.pos, 0.85, 0.3, 1.0, cfg.radius, 0.45)
        for i = 1, #all_ships do
            local other = all_ships[i]
            if other.alive and other.team ~= ship.team then
                if math3d.vec_dist_sq(ship.pos, other.pos) <= r_sq then
                    other.shield = 0
                    other.shield_regen_delay = cfg.block_regen
                    other.hit_flash = 1.0
                    if ship.is_player and on_hit_callback then
                        on_hit_callback(other, ship, false)
                    end
                end
            end
        end
        if ship.is_player then audio.play("emp", 0.7) end
    elseif mod_id == "micromissiles" then
        local tgt = ship.locked_target
        if not tgt or not tgt.alive then
            -- Find nearest alive enemy
            local best_sq = 240 * 240
            for i = 1, #all_ships do
                local other = all_ships[i]
                if other.alive and other.team ~= ship.team then
                    local d_sq = math3d.vec_dist_sq(ship.pos, other.pos)
                    if d_sq < best_sq then best_sq = d_sq; tgt = other end
                end
            end
            if not tgt and boss_parts then
                for i = 1, #boss_parts do
                    local bp = boss_parts[i]
                    if bp.alive and bp.targetable then tgt = bp; break end
                end
            end
        end
        local dmg = cfg.damage * (1 + 0.15 * (ship.tier - 1))
        for m = 1, cfg.count do
            local spread = vmath.vector3((m - 2.5) * 1.4, (m % 2 == 0 and 0.8 or -0.8), 0)
            local p = ship.pos + vmath.rotate(ship.rot, spread)
            local dir = math3d.normalize_or_default(ship.forward + vmath.rotate(ship.rot, spread * 0.08))
            spawn_missile(ship, p, dir, tgt, dmg)
        end
        if ship.is_player then audio.play("missile", 0.6) end
    elseif mod_id == "overdrive" then
        ship.overdrive_timer = cfg.duration
        pool_manager.spawn_vfx(ship.pos, 1.0, 0.8, 0.15, 5.5, 0.35)
        if ship.is_player then audio.play("dash", 0.5) end
    elseif mod_id == "energydome" then
        ship.dome_timer = cfg.duration
        pool_manager.set_ship_dome(ship.pool_slot, true, 0.25, 0.72, 1.0, 0.35)
        if ship.is_player then audio.play("shield_hit", 0.65) end
    elseif mod_id == "repairdrone" then
        local heal = ship.max_hull * cfg.heal_pct
        ship.hull = math.min(ship.max_hull, ship.hull + heal)
        pool_manager.spawn_vfx(ship.pos, 0.35, 0.95, 0.65, 6.5, 0.45)
        -- Heal nearest ally within radius
        local best_ally = nil
        local best_sq = cfg.radius * cfg.radius
        for i = 1, #all_ships do
            local other = all_ships[i]
            if other ~= ship and other.alive and other.team == ship.team then
                local d_sq = math3d.vec_dist_sq(ship.pos, other.pos)
                if d_sq <= best_sq then best_sq = d_sq; best_ally = other end
            end
        end
        if best_ally then
            best_ally.hull = math.min(best_ally.max_hull, best_ally.hull + best_ally.max_hull * cfg.heal_pct)
            pool_manager.spawn_vfx(best_ally.pos, 0.35, 0.95, 0.65, 6.5, 0.45)
        end
        if ship.is_player then audio.play("heal", 0.7) end
    end
    return true
end

local function point_hits_obstacle(pos, obstacles)
    for o = 1, #obstacles do
        local obs = obstacles[o]
        if obs.kind == "torus" then
            local _, _, _, d_sq = flight_physics.torus_closest_offset(pos.x, pos.y, pos.z, obs)
            if d_sq <= obs.minor_r * obs.minor_r then
                return true
            end
        elseif not obs.is_boss_hull and math3d.dist_sq(pos.x, pos.y, pos.z, obs.x, obs.y, obs.z) <= obs.r * obs.r then
            return true
        end
    end
    return false
end

function M.update(all_ships, boss_parts, dt)
    local obstacles = flight_physics.get_obstacles()

    -- Update lasers
    for i = #active_lasers, 1, -1 do
        local l = active_lasers[i]
        l.life = l.life - dt
        l.pos.x = l.pos.x + l.vel.x * dt
        l.pos.y = l.pos.y + l.vel.y * dt
        l.pos.z = l.pos.z + l.vel.z * dt

        local hit = false
        -- Check ships
        for s = 1, #all_ships do
            local target = all_ships[s]
            if target.alive and target.team ~= l.team then
                local r = target.radius + 0.9
                if math3d.vec_dist_sq(l.pos, target.pos) <= r * r then
                    M.apply_damage(target, l.damage, l.weapon_type, l.owner)
                    pool_manager.spawn_vfx(l.pos, 0.9, 0.95, 1.0, 2.2, 0.16)
                    hit = true
                    break
                end
            end
        end

        -- Check boss parts
        if not hit and boss_parts and l.team == 1 then
            for b = 1, #boss_parts do
                local bp = boss_parts[b]
                if bp.alive then
                    local r = bp.radius + 1.2
                    if math3d.vec_dist_sq(l.pos, bp.pos) <= r * r then
                        M.apply_damage(bp, l.damage, l.weapon_type, l.owner)
                        pool_manager.spawn_vfx(l.pos, 1.0, 0.6, 0.2, 3.0, 0.22)
                        hit = true
                        break
                    end
                end
            end
        end

        -- Check asteroids
        if not hit and point_hits_obstacle(l.pos, obstacles) then
            hit = true
        end

        if hit or l.life <= 0 then
            pool_manager.release_laser(l.pool_item)
            table.remove(active_lasers, i)
        else
            go.set_position(l.pos, l.pool_item.id)
        end
    end

    -- Update homing missiles
    for i = #active_missiles, 1, -1 do
        local m = active_missiles[i]
        m.life = m.life - dt
        if m.target and m.target.alive then
            local to_t = math3d.normalize_or_default(m.target.pos - m.pos, m.forward)
            local alpha = math.min(1.0, m.turn_rate * dt)
            m.forward = math3d.normalize_or_default(vmath.vector3(
                math3d.lerp(m.forward.x, to_t.x, alpha),
                math3d.lerp(m.forward.y, to_t.y, alpha),
                math3d.lerp(m.forward.z, to_t.z, alpha)
            ), m.forward)
        end
        m.pos = m.pos + m.forward * (m.speed * dt)

        local hit = false
        for s = 1, #all_ships do
            local target = all_ships[s]
            if target.alive and target.team ~= m.team then
                local r = target.radius + 1.5
                if math3d.vec_dist_sq(m.pos, target.pos) <= r * r then
                    M.apply_damage(target, m.damage, "missile", m.owner)
                    pool_manager.spawn_vfx(m.pos, 1.0, 0.45, 0.1, 4.5, 0.3)
                    if target.is_player then camera_rig.add_shake(0.35) end
                    hit = true
                    break
                end
            end
        end
        if not hit and boss_parts and m.team == 1 then
            for b = 1, #boss_parts do
                local bp = boss_parts[b]
                if bp.alive then
                    local r = bp.radius + 1.8
                    if math3d.vec_dist_sq(m.pos, bp.pos) <= r * r then
                        M.apply_damage(bp, m.damage, "missile", m.owner)
                        pool_manager.spawn_vfx(m.pos, 1.0, 0.45, 0.1, 5.0, 0.32)
                        hit = true
                        break
                    end
                end
            end
        end

        if not hit and point_hits_obstacle(m.pos, obstacles) then
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
