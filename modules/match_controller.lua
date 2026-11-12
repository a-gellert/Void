local ships_db = require("data.ships_db")
local arenas_db = require("data.arenas_db")
local bots_db = require("data.bots_db")
local math3d = require("modules.math3d")
local pool_manager = require("modules.pool_manager")
local flight_physics = require("modules.flight_physics")
local combat_manager = require("modules.combat_manager")
local ai_controller = require("modules.ai_controller")
local camera_rig = require("modules.camera_rig")
local progress = require("modules.progress")
local poki = require("modules.poki")

local M = {}

local match = {
    active = false,
    finished = false,
    mode = "tdm", -- "tdm", "domination", "boss"
    timer = 90.0,
    score_t1 = 0,
    score_t2 = 0,
    target_score = 12,
    player_kills = 0,
    player_deaths = 0,
    ships = {},
    player = nil,
    beacons = {},
    boss_parts = {},
    boss_phase = 1, -- 1=generators, 2=turrets, 3=reactor
    boss_hull_slot = nil,
    boss_pos = vmath.vector3(0, 10, -65),
    result = nil,
    time_elapsed = 0,
    hint_timer = 0,
}

local function get_spawn_pos(team, idx)
    local arena = (match.mode == "boss") and arenas_db.DREADNOUGHT_ARENA or arenas_db.STANDARD_ARENA
    local list = (team == 1) and arena.spawns.team1 or arena.spawns.team2
    local p = list[((idx - 1) % #list) + 1]
    return vmath.vector3(p[1], p[2], p[3])
end

local function create_ship_entity(slot_idx, team, class_id, upgrades, skin_id, trail_id, is_player, bot_profile)
    local stats = ships_db.get_effective_stats(class_id, upgrades)
    local spawn = get_spawn_pos(team, slot_idx)
    local fwd = (team == 1) and vmath.vector3(0, 0, -1) or vmath.vector3(0, 0, 1)
    local pool_slot = pool_manager.get_ship_slot(slot_idx)
    pool_manager.configure_ship_visual(pool_slot, class_id, stats.tier, skin_id, trail_id, true)

    local ship = {
        slot_idx = slot_idx,
        pool_slot = pool_slot,
        team = team,
        is_player = is_player,
        name = is_player and "YOU" or bot_profile.name,
        flag = is_player and "" or bot_profile.flag,
        archetype = bot_profile and bot_profile.archetype or "tactician",
        class_id = class_id,
        tier = stats.tier,
        skin_id = skin_id,
        trail_id = trail_id,
        alive = true,
        respawn_timer = 0,
        pos = vmath.vector3(spawn.x, spawn.y, spawn.z),
        vel = vmath.vector3(0, 0, 0),
        forward = fwd,
        rot = math3d.quat_from_forward(fwd, 0),
        roll = 0,
        radius = stats.radius,
        speed = stats.speed,
        boost_speed = stats.boost_speed,
        turn_rate = stats.turn_rate,
        max_hull = stats.max_hull,
        hull = stats.max_hull,
        max_shield = stats.max_shield,
        shield = stats.max_shield,
        shield_regen_delay = 0,
        damage = stats.damage,
        weapon_rate = stats.weapon_rate,
        weapon_range = stats.weapon_range,
        weapon_type = stats.weapon_type,
        proj_speed = stats.proj_speed,
        proj_color = stats.proj_color,
        muzzle_offsets = stats.muzzle_offsets,
        mod1 = stats.mod1,
        mod2 = stats.mod2,
        fire_cd = 0,
        dash_cd = 0,
        dash_timer = 0,
        mod1_cd = 0,
        mod2_cd = 0,
        invuln_timer = 0,
        warp_flash = 0,
        overdrive_timer = 0,
        dome_timer = 0,
        hit_flash = 0,
        locked_target = nil,
    }
    go.set_position(ship.pos, pool_slot.id)
    go.set_rotation(ship.rot, pool_slot.id)
    return ship
end

local function setup_environment()
    pool_manager.hide_environment()
    local obstacles = {}
    local ast_idx = 1

    if match.mode == "boss" then
        local arena = arenas_db.DREADNOUGHT_ARENA
        for _, a in ipairs(arena.asteroids) do
            local slot = pool_manager.get_asteroid_slot(ast_idx)
            ast_idx = ast_idx + 1
            local mesh_key = (a.model == 1) and "mesh1" or "mesh2"
            msg.post(slot.urls[mesh_key], "enable")
            go.set_position(vmath.vector3(a.x, a.y, a.z), slot.id)
            go.set_scale(vmath.vector3(a.r, a.r, a.r), slot.id)
            obstacles[#obstacles + 1] = { x = a.x, y = a.y, z = a.z, r = a.r }
        end

        -- Dreadnought Hull + 3 Generators + 4 Turrets + 1 Reactor
        local bcfg = arena.boss
        local bp = vmath.vector3(bcfg.pos[1] or bcfg.pos.x, bcfg.pos[2] or bcfg.pos.y, bcfg.pos[3] or bcfg.pos.z)
        match.boss_pos = bp
        local d_idx = 1
        local hull_slot = pool_manager.get_dreadnought_slot(d_idx)
        d_idx = d_idx + 1
        msg.post(hull_slot.urls.hull, "enable")
        go.set_position(bp, hull_slot.id)
        go.set_rotation(vmath.quat(), hull_slot.id)
        go.set_scale(vmath.vector3(1, 1, 1), hull_slot.id)
        match.boss_hull_slot = hull_slot
        obstacles[#obstacles + 1] = { x = bp.x, y = bp.y, z = bp.z, r = bcfg.hull_radius }

        match.boss_parts = {}
        local tier_scale = 1 + 0.15 * (progress.get_average_player_tier() - 1)
        for _, g in ipairs(bcfg.generators) do
            local s = pool_manager.get_dreadnought_slot(d_idx); d_idx = d_idx + 1
            msg.post(s.urls.gen, "enable")
            local p = bp + vmath.vector3(g.offset[1], g.offset[2], g.offset[3])
            go.set_position(p, s.id)
            go.set_scale(vmath.vector3(1, 1, 1), s.id)
            match.boss_parts[#match.boss_parts + 1] = {
                id = g.id, kind = "generator", is_boss_part = true, team = 2,
                pool_slot = s, mesh_url = s.urls.gen,
                pos = p, radius = g.radius, alive = true, targetable = true, shielded = false,
                hull = g.hp * tier_scale, max_hull = g.hp * tier_scale, shield = 0, hit_flash = 0,
            }
        end
        for _, t in ipairs(bcfg.turrets) do
            local s = pool_manager.get_dreadnought_slot(d_idx); d_idx = d_idx + 1
            msg.post(s.urls.turret, "enable")
            local p = bp + vmath.vector3(t.offset[1], t.offset[2], t.offset[3])
            go.set_position(p, s.id)
            go.set_scale(vmath.vector3(1, 1, 1), s.id)
            match.boss_parts[#match.boss_parts + 1] = {
                id = t.id, kind = "turret", is_boss_part = true, team = 2,
                pool_slot = s, mesh_url = s.urls.turret,
                pos = p, rot = vmath.quat(), radius = t.radius, alive = true,
                targetable = false, shielded = true,
                hull = t.hp * tier_scale, max_hull = t.hp * tier_scale, shield = 0, hit_flash = 0,
                fire_rate = t.fire_rate, damage = t.damage * tier_scale, fire_cd = math.random() * 1.5,
            }
        end
        local r = bcfg.reactor
        local rs = pool_manager.get_dreadnought_slot(d_idx)
        msg.post(rs.urls.reactor, "enable")
        local rp = bp + vmath.vector3(r.offset[1], r.offset[2], r.offset[3])
        go.set_position(rp, rs.id)
        go.set_scale(vmath.vector3(1, 1, 1), rs.id)
        match.boss_parts[#match.boss_parts + 1] = {
            id = r.id, kind = "reactor", is_boss_part = true, team = 2,
            pool_slot = rs, mesh_url = rs.urls.reactor,
            pos = rp, radius = r.radius, alive = true,
            targetable = false, shielded = true,
            hull = r.hp * tier_scale, max_hull = r.hp * tier_scale, shield = 0, hit_flash = 0,
        }
    else
        local arena = arenas_db.STANDARD_ARENA
        -- Central Station
        local st_slot = pool_manager.get_asteroid_slot(ast_idx); ast_idx = ast_idx + 1
        msg.post(st_slot.urls.station, "enable")
        go.set_position(vmath.vector3(0, 0, 0), st_slot.id)
        go.set_scale(vmath.vector3(1, 1, 1), st_slot.id)
        obstacles[#obstacles + 1] = { x = 0, y = 0, z = 0, r = arena.station.core_radius }

        -- Hollow tunnel asteroid
        local ha = arena.hollow_asteroid
        local h_slot = pool_manager.get_asteroid_slot(ast_idx); ast_idx = ast_idx + 1
        msg.post(h_slot.urls.hollow, "enable")
        go.set_position(vmath.vector3(ha.x, ha.y, ha.z), h_slot.id)
        go.set_rotation(vmath.quat_rotation_x(math.rad(90)), h_slot.id)
        go.set_scale(vmath.vector3(ha.scale, ha.scale, ha.scale), h_slot.id)

        -- Scattered asteroids
        for _, a in ipairs(arena.asteroids) do
            local slot = pool_manager.get_asteroid_slot(ast_idx); ast_idx = ast_idx + 1
            if slot then
                local mesh_key = (a.model == 1) and "mesh1" or "mesh2"
                msg.post(slot.urls[mesh_key], "enable")
                go.set_position(vmath.vector3(a.x, a.y, a.z), slot.id)
                go.set_scale(vmath.vector3(a.r, a.r, a.r), slot.id)
                obstacles[#obstacles + 1] = { x = a.x, y = a.y, z = a.z, r = a.r }
            end
        end

        -- 3 Beacons (visible in Domination)
        match.beacons = {}
        if match.mode == "domination" then
            for i, b in ipairs(arena.beacons) do
                local bs = pool_manager.get_beacon_slot(i)
                msg.post(bs.mesh, "enable")
                msg.post(bs.zone, "enable")
                local pos = vmath.vector3(b.x, b.y, b.z)
                go.set_position(pos, bs.id)
                go.set(bs.mesh, "tint", vmath.vector4(1.0, 0.85, 0.25, 1.0))
                go.set(bs.zone, "tint", vmath.vector4(1.0, 0.85, 0.25, 0.16))
                match.beacons[i] = {
                    id = b.id, pos = pos, radius = b.radius,
                    owner = 0, capture = 0, -- -100..100 (+ = team1, - = team2)
                    slot = bs,
                }
            end
        end
    end

    flight_physics.set_obstacles(obstacles)
end

local function update_boss_phases()
    local gens_alive, turrets_alive = 0, 0
    for _, bp in ipairs(match.boss_parts) do
        if bp.alive then
            if bp.kind == "generator" then gens_alive = gens_alive + 1
            elseif bp.kind == "turret" then turrets_alive = turrets_alive + 1 end
        end
    end
    if gens_alive > 0 then
        match.boss_phase = 1
    elseif turrets_alive > 0 then
        match.boss_phase = 2
    else
        match.boss_phase = 3
    end
    for _, bp in ipairs(match.boss_parts) do
        if bp.kind == "generator" then
            bp.targetable = bp.alive
            bp.shielded = false
        elseif bp.kind == "turret" then
            bp.targetable = (gens_alive == 0) and bp.alive
            bp.shielded = (gens_alive > 0)
        elseif bp.kind == "reactor" then
            bp.targetable = (gens_alive == 0 and turrets_alive == 0) and bp.alive
            bp.shielded = (gens_alive > 0 or turrets_alive > 0)
        end
    end
end

local function finish_match(won)
    if match.finished then return end
    match.finished = true
    match.active = false
    poki.gameplay_stop()

    local pstate = progress.get()
    pstate.match_count = pstate.match_count + 1
    pstate.first_battle_done = true
    pstate.test_drive_active = false

    local base_credits = won and 140 or 65
    local kill_bonus = match.player_kills * 18
    local boss_bonus = (match.mode == "boss" and won) and 110 or 0
    local total_credits = base_credits + kill_bonus + boss_bonus
    local total_parts = won and (match.mode == "boss" and 4 or 2) or 1

    progress.add_rewards(total_credits, total_parts)

    match.result = {
        won = won,
        credits = total_credits,
        parts = total_parts,
        kills = match.player_kills,
        deaths = match.player_deaths,
        doubled = false,
    }
end

local function on_ship_killed(victim, attacker)
    if match.finished then return end
    pool_manager.configure_ship_visual(victim.pool_slot, victim.class_id, victim.tier, victim.skin_id, victim.trail_id, false)
    if victim.is_player then
        match.player_deaths = match.player_deaths + 1
    end
    if attacker and attacker.is_player then
        match.player_kills = match.player_kills + 1
    end
    if match.mode == "tdm" then
        if victim.team == 2 then
            match.score_t1 = match.score_t1 + 1
            if match.score_t1 >= match.target_score then finish_match(true) end
        else
            match.score_t2 = match.score_t2 + 1
            if match.score_t2 >= match.target_score then finish_match(false) end
        end
    end
end

local function on_boss_part_killed(part, attacker)
    msg.post(part.mesh_url, "disable")
    if attacker and attacker.is_player then
        match.player_kills = match.player_kills + 1
    end
    update_boss_phases()
    if part.kind == "reactor" then
        pool_manager.spawn_vfx(match.boss_pos, 1.0, 0.7, 0.25, 42.0, 1.0)
        finish_match(true)
    end
end

function M.start_match(forced_mode)
    pool_manager.hide_all()
    local pstate = progress.get()
    local next_num = pstate.match_count + 1

    if forced_mode then
        match.mode = forced_mode
    elseif not pstate.first_battle_done then
        match.mode = "tdm"
    elseif next_num % 5 == 0 then
        match.mode = "boss"
    elseif next_num % 2 == 0 then
        match.mode = "domination"
    else
        match.mode = "tdm"
    end

    match.active = true
    match.finished = false
    match.result = nil
    match.time_elapsed = 0
    match.timer = (match.mode == "boss") and 110.0 or 90.0
    match.score_t1 = 0
    match.score_t2 = 0
    match.target_score = (match.mode == "domination") and 100 or 12
    match.player_kills = 0
    match.player_deaths = 0
    match.boss_parts = {}
    match.beacons = {}
    match.boss_phase = 1
    match.hint_timer = (not pstate.first_battle_done or match.mode == "boss") and 12.0 or 0

    setup_environment()
    combat_manager.reset(on_ship_killed, on_boss_part_killed)

    match.ships = {}
    local p_class = pstate.first_battle_done and pstate.selected_class or "interceptor"
    local p_upg = progress.get_player_upgrades(p_class)
    match.player = create_ship_entity(1, 1, p_class, p_upg, pstate.equipped_skin, pstate.equipped_trail, true, nil)
    match.ships[1] = match.player

    local bot_tier = progress.get_average_player_tier()
    local bot_upg = { hull = bot_tier, weapon = bot_tier, shield = bot_tier, engine = bot_tier }

    -- Shuffle bot pool index offset
    local base_idx = math.random(1, #bots_db.BOT_PROFILES)
    -- 3 Allies (Team 1)
    for i = 2, 4 do
        local prof = bots_db.BOT_PROFILES[((base_idx + i) % #bots_db.BOT_PROFILES) + 1]
        match.ships[i] = create_ship_entity(i, 1, prof.class_id, bot_upg, 3, 3, false, prof)
    end
    -- 4 Enemies (Team 2) for TDM / Domination
    if match.mode ~= "boss" then
        for i = 5, 8 do
            local prof = bots_db.BOT_PROFILES[((base_idx + i + 3) % #bots_db.BOT_PROFILES) + 1]
            match.ships[i] = create_ship_entity(i, 2, prof.class_id, bot_upg, prof.skin, prof.trail, false, prof)
        end
    end

    camera_rig.reset(match.player.pos, match.player.forward)
end

local function update_beacons(dt)
    if match.mode ~= "domination" then return end
    for i = 1, #match.beacons do
        local b = match.beacons[i]
        local t1, t2 = 0, 0
        local r_sq = b.radius * b.radius
        for s = 1, #match.ships do
            local ship = match.ships[s]
            if ship.alive and math3d.vec_dist_sq(ship.pos, b.pos) <= r_sq then
                if ship.team == 1 then t1 = t1 + 1 else t2 = t2 + 1 end
            end
        end
        local diff = t1 - t2
        if diff ~= 0 then
            b.capture = math3d.clamp(b.capture + diff * 28.0 * dt, -100, 100)
            if b.capture >= 75 then b.owner = 1
            elseif b.capture <= -75 then b.owner = 2
            elseif math.abs(b.capture) < 25 then b.owner = 0 end
        end
        if b.owner == 1 then
            match.score_t1 = match.score_t1 + 4.2 * dt
            go.set(b.slot.mesh, "tint", vmath.vector4(0.0, 0.9, 1.0, 1.0))
            go.set(b.slot.zone, "tint", vmath.vector4(0.0, 0.9, 1.0, 0.16))
        elseif b.owner == 2 then
            match.score_t2 = match.score_t2 + 4.2 * dt
            go.set(b.slot.mesh, "tint", vmath.vector4(1.0, 0.25, 0.2, 1.0))
            go.set(b.slot.zone, "tint", vmath.vector4(1.0, 0.25, 0.2, 0.16))
        else
            go.set(b.slot.mesh, "tint", vmath.vector4(1.0, 0.85, 0.25, 1.0))
            go.set(b.slot.zone, "tint", vmath.vector4(1.0, 0.85, 0.25, 0.16))
        end
    end
    if match.score_t1 >= 100 then
        match.score_t1 = 100; finish_match(true)
    elseif match.score_t2 >= 100 then
        match.score_t2 = 100; finish_match(false)
    end
end

local function update_boss_turrets(dt)
    if match.mode ~= "boss" then return end
    for _, bp in ipairs(match.boss_parts) do
        if bp.alive then
            if bp.hit_flash > 0 then
                bp.hit_flash = math.max(0, bp.hit_flash - dt * 12.0)
                local f = 1.0 + bp.hit_flash * 2.0
                go.set(bp.mesh_url, "tint", vmath.vector4(f, f, f, 1.0))
            end
            if bp.kind == "turret" then
                bp.fire_cd = bp.fire_cd - dt
                if bp.fire_cd <= 0 then
                    bp.fire_cd = 1.0 / bp.fire_rate
                    local best_tgt, best_sq = nil, 240 * 240
                    for s = 1, #match.ships do
                        local sh = match.ships[s]
                        if sh.alive then
                            local d_sq = math3d.vec_dist_sq(bp.pos, sh.pos)
                            if d_sq < best_sq then best_sq = d_sq; best_tgt = sh end
                        end
                    end
                    if best_tgt then
                        combat_manager.fire_turret(bp, best_tgt)
                        go.set_rotation(bp.rot, bp.pool_slot.id)
                    end
                end
            end
        end
    end
end

function M.update(input_state, dt)
    if not match.active then return end
    match.time_elapsed = match.time_elapsed + dt
    if match.hint_timer > 0 then match.hint_timer = math.max(0, match.hint_timer - dt) end

    match.timer = match.timer - dt
    if match.timer <= 0 then
        match.timer = 0
        if match.mode == "boss" then
            finish_match(false)
        else
            finish_match(match.score_t1 >= match.score_t2)
        end
        return
    end

    -- Update ship timers, respawns & visuals
    for i = 1, #match.ships do
        local s = match.ships[i]
        if s.alive then
            if s.fire_cd > 0 then s.fire_cd = math.max(0, s.fire_cd - dt) end
            if s.dash_cd > 0 then s.dash_cd = math.max(0, s.dash_cd - dt) end
            if s.dash_timer > 0 then s.dash_timer = math.max(0, s.dash_timer - dt) end
            if s.mod1_cd > 0 then s.mod1_cd = math.max(0, s.mod1_cd - dt) end
            if s.mod2_cd > 0 then s.mod2_cd = math.max(0, s.mod2_cd - dt) end
            if s.invuln_timer > 0 then s.invuln_timer = math.max(0, s.invuln_timer - dt) end
            if s.warp_flash > 0 then s.warp_flash = math.max(0, s.warp_flash - dt) end
            if s.overdrive_timer > 0 then s.overdrive_timer = math.max(0, s.overdrive_timer - dt) end
            if s.dome_timer > 0 then
                s.dome_timer = math.max(0, s.dome_timer - dt)
                if s.dome_timer <= 0 then pool_manager.set_ship_dome(s.pool_slot, false) end
            end
            if s.shield_regen_delay > 0 then
                s.shield_regen_delay = math.max(0, s.shield_regen_delay - dt)
            elseif s.shield < s.max_shield then
                s.shield = math.min(s.max_shield, s.shield + (s.max_shield * 0.25) * dt)
            end
            if s.hit_flash > 0 then
                s.hit_flash = math.max(0, s.hit_flash - dt * 12.0)
                pool_manager.set_ship_hit_flash(s.pool_slot, s.hit_flash)
            end
        else
            s.respawn_timer = s.respawn_timer - dt
            if s.respawn_timer <= 0 then
                local sp = get_spawn_pos(s.team, s.slot_idx)
                s.pos = vmath.vector3(sp.x, sp.y, sp.z)
                s.forward = (s.team == 1) and vmath.vector3(0, 0, -1) or vmath.vector3(0, 0, 1)
                s.rot = math3d.quat_from_forward(s.forward, 0)
                s.hull = s.max_hull
                s.shield = s.max_shield
                s.alive = true
                s.invuln_timer = 1.5
                s.hit_flash = 0
                pool_manager.configure_ship_visual(s.pool_slot, s.class_id, s.tier, s.skin_id, s.trail_id, true)
            end
        end
    end

    -- Player Flight, Lock-On, Auto-Fire & Actions
    local p = match.player
    if p and p.alive then
        local aim_dir = camera_rig.get_aim_ray(input_state.steer_x, input_state.steer_y)
        flight_physics.update_ship(p, aim_dir, dt)
        camera_rig.update_battle(p, input_state.steer_x, input_state.steer_y, dt)

        local locked = combat_manager.acquire_player_lock(p, match.ships, match.boss_parts)
        if locked or input_state.fire_held then
            combat_manager.fire_primary(p, locked, input_state.fire_held)
        end

        if input_state.dash_pressed then combat_manager.activate_dash(p) end
        if input_state.mod1_pressed then combat_manager.activate_module(p, 1, match.ships, match.boss_parts) end
        if input_state.mod2_pressed then combat_manager.activate_module(p, 2, match.ships, match.boss_parts) end
    elseif p then
        camera_rig.update_battle(p, 0, 0, dt)
    end

    -- AI Bots
    for i = 2, #match.ships do
        ai_controller.update_bot(match.ships[i], match.ships, match.beacons, match.boss_parts, match.mode, match.time_elapsed, dt)
    end

    -- Sync ship transforms
    for i = 1, #match.ships do
        local s = match.ships[i]
        if s.alive then
            go.set_position(s.pos, s.pool_slot.id)
            go.set_rotation(s.rot, s.pool_slot.id)
        end
    end

    combat_manager.update(match.ships, match.boss_parts, dt)
    update_beacons(dt)
    update_boss_turrets(dt)
    pool_manager.update_vfx(dt)
end

function M.get_state()
    return match
end

function M.stop_match()
    match.active = false
    pool_manager.hide_all()
    poki.gameplay_stop()
end

return M
