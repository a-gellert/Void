-- Match core: spawning, simulation loop, player control, scoring hooks, results.
-- Game modes live in modules/modes/<mode>.lua and implement:
--   setup(match, api)                    build environment + spawn ships
--   update(match, api, dt)               per-frame rules (score, waves, objectives)
--   on_kill(match, api, victim, killer)  optional
--   on_structure_killed(match, api, s, killer) optional
--   on_timeout(match, api) -> won        optional (default: lose)
local ships_db = require("data.ships_db")
local arenas_db = require("data.arenas_db")
local bots_db = require("data.bots_db")
local campaign_db = require("data.campaign_db")
local progression_db = require("data.progression_db")
local modules_db = require("data.modules_db")
local math3d = require("modules.math3d")
local pool_manager = require("modules.pool_manager")
local flight_physics = require("modules.flight_physics")
local combat_manager = require("modules.combat_manager")
local ai_controller = require("modules.ai_controller")
local camera_rig = require("modules.camera_rig")
local input_state = require("modules.input_state")
local progress = require("modules.progress")
local audio = require("modules.audio")
local poki = require("modules.poki")

local MODES = {
    tdm = require("modules.modes.tdm"),
    domination = require("modules.modes.domination"),
    survival = require("modules.modes.survival"),
    escort = require("modules.modes.escort"),
    race = require("modules.modes.race"),
    hunt = require("modules.modes.hunt"),
    ace = require("modules.modes.ace"),
    boss = require("modules.modes.boss"),
    tutorial = require("modules.modes.tutorial"),
}

local M = {}

local RESPAWN_DELAY = 3.0
local FEED_SIZE = 5
local DMG_NUMBERS = 12

local match = {
    active = false,
    finished = false,
    paused = false,
    ships = {},
    structures = {},
    beacons = {},
    pickups = {},
    feed = {},
    dmg_numbers = {},
    waypoints = {},
    score = { 0, 0 },
}

for i = 1, FEED_SIZE do
    match.feed[i] = { active = false, timer = 0, killer = "", killer_team = 1, killer_me = false, victim = "", victim_team = 2, victim_me = false }
end
for i = 1, DMG_NUMBERS do
    match.dmg_numbers[i] = { active = false, pos = vmath.vector3(), value = 0, timer = 0, kill = false }
end
local dmg_cursor = 1

local api = {}
local mode_impl = nil
local skills = {}
local ai_ctx = { ships = nil, structures = nil, beacons = nil, pickups = nil, mode = "tdm", time = 0 }

function M.get_state()
    return match
end

-- ============================================================ HUD EVENTS
function api.banner(key, color, arg, duration)
    match.banner = { key = key, color = color or "gold", arg = arg, timer = duration or 2.4, duration = duration or 2.4 }
end

function api.hint(key, duration)
    match.hint = { key = key, timer = duration or 6.0 }
end

function api.set_objective(key, a, b, progress_pct)
    local o = match.objective
    o.key, o.a, o.b, o.pct = key, a, b, progress_pct
end

local function push_feed(killer, victim)
    local f = match.feed
    for i = #f, 2, -1 do
        local d, s = f[i], f[i - 1]
        d.active, d.timer, d.killer, d.killer_team, d.killer_me = s.active, s.timer, s.killer, s.killer_team, s.killer_me
        d.victim, d.victim_team, d.victim_me = s.victim, s.victim_team, s.victim_me
    end
    local t = f[1]
    t.active = true
    t.timer = 5.0
    t.killer = killer and (killer.display_name or killer.name) or ""
    t.killer_team = killer and killer.team or 0
    t.killer_me = killer and killer.is_player or false
    t.victim = victim.display_name or victim.name or ""
    t.victim_team = victim.team
    t.victim_me = victim.is_player or false
end

local function push_dmg_number(pos, value, is_kill)
    local d = match.dmg_numbers[dmg_cursor]
    dmg_cursor = (dmg_cursor % DMG_NUMBERS) + 1
    d.active = true
    d.pos.x, d.pos.y, d.pos.z = pos.x, pos.y + 2.5, pos.z
    d.value = math.floor(value + 0.5)
    d.timer = 0.9
    d.kill = is_kill
end

-- ============================================================ SPAWNING
local function free_pool_slot()
    for i = 1, pool_manager.SHIP_POOL do
        local slot = pool_manager.get_ship_slot(i)
        if not slot.in_use then return i, slot end
    end
    return nil, nil
end

function api.alive_count(team, filter_ai)
    local n = 0
    for _, s in ipairs(match.ships) do
        if s.team == team and (s.alive or s.can_respawn) and (not filter_ai or s.ai == filter_ai) then n = n + 1 end
    end
    return n
end

function api.free_slots()
    local n = 0
    for i = 1, pool_manager.SHIP_POOL do
        if not pool_manager.get_ship_slot(i).in_use then n = n + 1 end
    end
    return n
end

function api.spawn_point(team, idx)
    local list = (team == 1) and match.layout.spawns.team1 or match.layout.spawns.team2
    local p = list[((idx - 1) % #list) + 1]
    return vmath.vector3(p[1], p[2], p[3])
end

--- Spawn a ship. opts: team, ship_id, tier, upgrades, skin, trail, is_player, name, flag,
--- archetype, ai, pos, forward, respawn, loadout, hp_mult, dmg_mult, is_ace, is_vip, anchor
function api.spawn_ship(opts)
    local slot_idx, slot = free_pool_slot()
    if not slot then return nil end
    slot.in_use = true
    local upg = opts.upgrades or ships_db.uniform_upgrades(opts.tier or 1)
    local st = ships_db.get_effective_stats(opts.ship_id, upg)
    local pos = opts.pos or api.spawn_point(opts.team, slot_idx)
    local fwd = opts.forward or math3d.normalize_or_default(vmath.vector3(-pos.x, 0, -pos.z), vmath.vector3(0, 0, -1))
    local hp_mult = opts.hp_mult or 1.0
    local loadout = opts.loadout or { st.modules[1], st.modules[2] }
    pool_manager.configure_ship_visual(slot, st.mesh, st.tier, opts.skin or 1, opts.trail or 1, true)

    local ship = {
        slot_idx = slot_idx,
        pool_slot = slot,
        team = opts.team,
        is_player = opts.is_player or false,
        ai = opts.ai or (opts.is_player and "player" or "pilot"),
        name = opts.name or "---",
        flag = opts.flag or "",
        archetype = opts.archetype or bots_db.ROLE_ARCHETYPE[st.role] or "tactician",
        ship_id = st.ship_id,
        mesh = st.mesh,
        role = st.role,
        tier = st.tier,
        skin_id = opts.skin or 1,
        trail_id = opts.trail or 1,
        alive = true,
        can_respawn = opts.respawn ~= false,
        respawn_timer = 0,
        pos = vmath.vector3(pos.x, pos.y, pos.z),
        spawn_pos = vmath.vector3(pos.x, pos.y, pos.z),
        vel = vmath.vector3(0, 0, 0),
        forward = fwd,
        spawn_fwd = fwd,
        rot = math3d.quat_from_forward(fwd, 0),
        roll = 0,
        radius = st.radius,
        speed = st.speed,
        cur_speed = st.speed,
        boost_mult = st.boost_mult,
        strafe_speed = st.strafe,
        strafe_vel = 0,
        turn_rate = st.turn_rate,
        agility = st.agility,
        max_hull = st.max_hull * hp_mult,
        hull = st.max_hull * hp_mult,
        max_shield = st.max_shield * hp_mult,
        shield = st.max_shield * hp_mult,
        shield_regen_delay = 0,
        max_energy = st.max_energy,
        energy = st.max_energy,
        energy_delay = 0,
        boosting = false,
        braking = false,
        damage = st.damage,
        dmg_mult = opts.dmg_mult or 1.0,
        has_weapon = st.has_weapon,
        weapon_rate = st.weapon_rate,
        weapon_range = st.weapon_range,
        weapon_type = st.weapon_type,
        proj_speed = st.proj_speed,
        proj_color = st.proj_color,
        muzzle_offsets = st.muzzle_offsets,
        missiles_max = st.missiles,
        missiles = st.missiles,
        missile_cd = 0,
        mod1 = loadout[1],
        mod2 = loadout[2],
        mod1_cd = 0,
        mod2_cd = 0,
        fire_cd = 0,
        dash_cd = 0,
        dash_timer = 0,
        dash_visual = 0,
        invuln_timer = opts.is_player and 1.0 or 0,
        warp_flash = 0,
        overdrive_timer = 0,
        dome_timer = 0,
        cloak_timer = 0,
        nano_timer = 0,
        hit_flash = 0,
        under_fire_timer = 0,
        recent_dmg = 0,
        evade_timer = 0,
        evade_sign = (slot_idx % 2 == 0) and 1 or -1,
        bump_cd = 0,
        kills = 0,
        deaths = 0,
        is_ace = opts.is_ace or false,
        is_vip = opts.is_vip or false,
        anchor = opts.anchor,
        blast_damage = st.blast_damage,
        blast_radius = st.blast_radius,
        display_name = opts.display_name,
    }
    if opts.speed then ship.speed = opts.speed; ship.cur_speed = opts.speed end
    go.set_position(ship.pos, slot.id)
    go.set_rotation(ship.rot, slot.id)
    match.ships[#match.ships + 1] = ship
    return ship
end

local function release_ship(ship)
    pool_manager.hide_ship(ship.pool_slot)
    ship.pool_slot.in_use = false
    ship.removed = true
end

-- Random bot pilot profile for a team (team 2 in pirate sectors uses pirate names).
local name_cursor = 0
function api.pilot_profile()
    name_cursor = name_cursor + 1
    local list = bots_db.PILOT_NAMES
    local e = list[((name_cursor + match.name_seed) % #list) + 1]
    return e[1], e[2]
end

function api.random_ship_id(max_order)
    local pool = { "wasp", "falcon", "bastion" }
    if (max_order or 3) >= 4 then pool[#pool + 1] = "phantom" end
    if (max_order or 3) >= 5 then pool[#pool + 1] = "raptor" end
    if (max_order or 3) >= 6 then pool[#pool + 1] = "aegis" end
    return pool[math.random(1, #pool)]
end

--- Spawn `count` bot pilots for a team at the team spawns.
function api.spawn_pilots(team, count, opts)
    opts = opts or {}
    local tier = match.cfg.bot_tier or 1
    local max_order = 3 + math.max(0, tier - 2)
    local skill = skills[team]
    for i = 1, count do
        local name, flag = api.pilot_profile()
        local sid = api.random_ship_id(max_order)
        local def = ships_db.get(sid)
        local skin = (team == 1) and ((i % 3) + 1) or (((i * 5) % 24) + 1)
        local trail = (team == 1) and 1 or 2
        api.spawn_ship({
            team = team, ship_id = sid, tier = tier, skin = skin, trail = trail,
            name = name, flag = flag, ai = "pilot", respawn = opts.respawn ~= false,
            archetype = bots_db.ROLE_ARCHETYPE[def.role],
            hp_mult = (team == 2) and skill.hp_mult or 1.0,
            dmg_mult = (team == 2) and skill.dmg_mult or 0.7,
            pos = opts.pos,
        })
    end
end

function api.spawn_drone(kind, pos, team)
    local skill = skills[team or 2]
    local name = bots_db.PIRATE_NAMES[math.random(1, #bots_db.PIRATE_NAMES)]
    return api.spawn_ship({
        team = team or 2, ship_id = kind, tier = 1, skin = 1, trail = 2,
        name = name, ai = (kind == "kamikaze") and "kamikaze" or "drone", respawn = false,
        hp_mult = skill.hp_mult, dmg_mult = skill.dmg_mult, pos = pos,
        display_name = (kind == "kamikaze") and "KAMIKAZE" or "DRONE",
    })
end

function api.spawn_player()
    local s = progress.get()
    local sid = match.cfg.force_ship or s.selected
    local p = api.spawn_ship({
        team = 1, ship_id = sid, upgrades = progress.get_combat_upgrades(sid),
        skin = s.equipped_skin, trail = s.equipped_trail, is_player = true,
        name = "YOU", ai = "player", respawn = true, loadout = progress.get_loadout(sid),
        pos = match.cfg.player_pos, forward = match.cfg.player_fwd,
    })
    match.player = p
    if p then p.aim_dir = vmath.vector3(p.forward.x, p.forward.y, p.forward.z) end
    return p
end

-- ========================================================== ENVIRONMENT
local function near_any(x, y, z, pts, r)
    for _, p in ipairs(pts) do
        local dx, dy, dz = x - p[1], y - p[2], z - p[3]
        if dx * dx + dy * dy + dz * dz < r * r then return true end
    end
    return false
end

--- Build station / hollow / asteroids / pickups of the layout. keepout: { {x,y,z}... } clears asteroids.
function api.build_environment(opts)
    opts = opts or {}
    local L = match.layout
    local obstacles = {}
    local ast_idx = 1
    local keep = opts.keepout or {}
    local keep_r = opts.keep_r or 26

    if L.station and not opts.no_station then
        local st = L.station
        local slot = pool_manager.get_asteroid_slot(ast_idx); ast_idx = ast_idx + 1
        msg.post(slot.urls.station, "enable")
        go.set_position(vmath.vector3(st.x, st.y, st.z), slot.id)
        go.set_rotation(vmath.quat(), slot.id)
        go.set_scale(vmath.vector3(1, 1, 1), slot.id)
        obstacles[#obstacles + 1] = { x = st.x, y = st.y, z = st.z, r = st.core_radius }
        obstacles[#obstacles + 1] = { kind = "torus", x = st.x, y = st.y, z = st.z, ax = 0, ay = 1, az = 0, major_r = 26, minor_r = 3.5 }
    end
    if L.hollow and not opts.no_hollow then
        local ha = L.hollow
        local slot = pool_manager.get_asteroid_slot(ast_idx); ast_idx = ast_idx + 1
        msg.post(slot.urls.hollow, "enable")
        go.set_position(vmath.vector3(ha.x, ha.y, ha.z), slot.id)
        go.set_rotation(vmath.quat_rotation_x(math.rad(90)), slot.id)
        go.set_scale(vmath.vector3(ha.scale, ha.scale, ha.scale), slot.id)
        obstacles[#obstacles + 1] = {
            kind = "torus", x = ha.x, y = ha.y, z = ha.z, ax = 0, ay = 0, az = 1,
            major_r = ha.scale * 1.0, minor_r = ha.scale * 0.36,
        }
    end
    for _, a in ipairs(L.asteroids or {}) do
        if not near_any(a.x, a.y, a.z, keep, keep_r + a.r) then
            local slot = pool_manager.get_asteroid_slot(ast_idx)
            if slot then
                ast_idx = ast_idx + 1
                local mesh_key = (a.model == 1) and "mesh1" or "mesh2"
                msg.post(slot.urls[mesh_key], "enable")
                go.set_position(vmath.vector3(a.x, a.y, a.z), slot.id)
                go.set_rotation(vmath.quat_rotation_y(a.x * 0.37 + a.z * 0.11), slot.id)
                go.set_scale(vmath.vector3(a.r, a.r, a.r), slot.id)
                obstacles[#obstacles + 1] = { x = a.x, y = a.y, z = a.z, r = a.r }
            end
        end
    end
    if opts.extra_obstacles then
        for _, o in ipairs(opts.extra_obstacles) do obstacles[#obstacles + 1] = o end
    end

    match.pickups = {}
    if not opts.no_pickups then
        for i, pk in ipairs(L.pickups or {}) do
            local slot = pool_manager.get_pickup_slot(i)
            if slot then
                local pos = vmath.vector3(pk.x, pk.y, pk.z)
                go.set_position(pos, slot.id)
                pool_manager.configure_pickup_visual(slot, pk.kind, true)
                match.pickups[#match.pickups + 1] = {
                    kind = pk.kind, pos = pos, radius = pk.radius, respawn = pk.respawn or 18.0,
                    active = true, respawn_timer = 0, slot = slot,
                }
            end
        end
    end
    flight_physics.set_obstacles(obstacles)
    return obstacles
end

function api.add_structure(s)
    s.is_structure = true
    s.alive = true
    s.hit_flash = 0
    s.shield = s.shield or 0
    s.max_shield = s.max_shield or s.shield
    match.structures[#match.structures + 1] = s
    return s
end

function api.skill(team) return skills[team] end
function api.finish(won) M.finish(won) end
function api.track(stat, n) match.stats[stat] = (match.stats[stat] or 0) + (n or 1) end

-- ============================================================= CALLBACKS
local function streak_banner()
    local st = match.stats
    if st.multi >= 4 then api.banner("multi_kill", "gold")
    elseif st.multi == 3 then api.banner("triple_kill", "gold")
    elseif st.multi == 2 then api.banner("double_kill", "gold")
    end
    if st.streak == 5 then api.banner("rampage", "coral", nil, 2.8) end
end

local function on_hit(target, attacker, dealt, is_kill)
    if match.finished then return end
    if attacker and attacker.is_player and target.team ~= attacker.team then
        match.hit_marker_timer = is_kill and 0.3 or 0.14
        match.hit_marker_kill = is_kill
        match.stats.damage = match.stats.damage + dealt
        if dealt > 0.5 then push_dmg_number(target.pos, dealt, is_kill) end
        if not is_kill then audio.play("hit", 0.35) end
    end
    if target.is_player and attacker and attacker.pos then
        match.hurt_timer = 0.6
        match.hurt_from = attacker
    end
end

local function on_kill(victim, killer, weapon)
    if match.finished then return end
    pool_manager.configure_ship_visual(victim.pool_slot, victim.mesh, victim.tier, victim.skin_id, victim.trail_id, false)
    victim.deaths = victim.deaths + 1
    victim.respawn_timer = victim.is_player and RESPAWN_DELAY or (RESPAWN_DELAY + 1.5)
    victim.death_pos = vmath.vector3(victim.pos.x, victim.pos.y, victim.pos.z)
    victim.killer = killer
    pool_manager.set_ship_dome(victim.pool_slot, false)
    victim.dome_timer, victim.cloak_timer, victim.nano_timer, victim.overdrive_timer = 0, 0, 0, 0
    if killer and killer ~= victim then killer.kills = (killer.kills or 0) + 1 end

    if victim.is_player then
        match.stats.deaths = match.stats.deaths + 1
        match.stats.streak = 0
        victim.locked_target = nil
    end
    if killer and killer.is_player then
        match.stats.kills = match.stats.kills + 1
        match.stats.streak = match.stats.streak + 1
        if match.stats.multi_timer > 0 then match.stats.multi = match.stats.multi + 1 else match.stats.multi = 1 end
        match.stats.multi_timer = 4.0
        if victim.ai == "drone" or victim.ai == "kamikaze" then match.stats.drones = match.stats.drones + 1 end
        match.kill_banner_timer = 1.3
        audio.play("kill", 0.6)
        streak_banner()
    end
    local is_drone = victim.ai == "drone" or victim.ai == "kamikaze"
    if not is_drone or (killer and killer.is_player) or victim.is_vip then
        push_feed(killer, victim)
    end
    if mode_impl.on_kill then mode_impl.on_kill(match, api, victim, killer) end
end

local function on_structure_killed(s, killer)
    if match.finished then return end
    if s.mesh_url then msg.post(s.mesh_url, "disable") end
    if killer and killer.is_player then
        match.stats.kills = match.stats.kills + 1
        match.kill_banner_timer = 1.3
        audio.play("kill", 0.6)
    end
    push_feed(killer, s)
    if mode_impl.on_structure_killed then mode_impl.on_structure_killed(match, api, s, killer) end
end

local function on_module(ship)
    if ship.is_player then match.stats.modules = match.stats.modules + 1 end
end

local function on_missile_kill()
    match.stats.missile_kills = match.stats.missile_kills + 1
end

-- ============================================================== THEMES
local function apply_theme(theme_id)
    local th = arenas_db.THEMES[theme_id] or arenas_db.THEMES.ion
    msg.post("@render:", "clear_color", { color = vmath.vector4(th.clear[1], th.clear[2], th.clear[3], 1) })
    go.set("/star_dome#mesh", "tint", vmath.vector4(th.stars[1], th.stars[2], th.stars[3], th.stars[4]))
    pool_manager.set_dust_color(th.dust[1], th.dust[2], th.dust[3])
end

-- ================================================================ START
--- cfg: { kind, mission_id?, mode, layout, theme, difficulty, bot_tier, allies, enemies,
---        params, time_limit, modifiers, stars }
function M.start(cfg)
    pool_manager.hide_all()
    for i = 1, pool_manager.SHIP_POOL do pool_manager.get_ship_slot(i).in_use = false end
    input_state.reset()

    match.cfg = cfg
    match.mode = cfg.mode
    match.layout = arenas_db.get_layout(cfg.layout)
    match.active = true
    match.finished = false
    match.paused = false
    match.result = nil
    match.time_elapsed = 0
    match.time_limit = cfg.time_limit or 180
    match.timer = match.time_limit
    match.ships = {}
    match.structures = {}
    match.beacons = {}
    match.pickups = {}
    match.waypoints = {}
    match.player = nil
    match.score = { 0, 0 }
    match.score_target = cfg.params and cfg.params.target_score or 0
    match.score_kind = "none"
    match.objective = { key = nil, a = nil, b = nil, pct = nil }
    match.boss_bar = nil
    match.protect = nil
    match.banner = nil
    match.hint = nil
    match.hit_marker_timer = 0
    match.hit_marker_kill = false
    match.kill_banner_timer = 0
    match.hurt_timer = 0
    match.hurt_from = nil
    match.missile_warning = false
    match.name_seed = math.random(0, 23)
    match.stats = {
        kills = 0, deaths = 0, damage = 0, missile_kills = 0, drones = 0, rings = 0,
        beacons = 0, modules = 0, streak = 0, best_streak = 0, multi = 0, multi_timer = 0,
    }
    for i = 1, FEED_SIZE do match.feed[i].active = false end
    for i = 1, DMG_NUMBERS do match.dmg_numbers[i].active = false end

    local diff = cfg.difficulty or 3
    skills[2] = bots_db.skill(diff)
    skills[1] = bots_db.skill(math.max(2, diff - 1))
    match.shield_regen_mult = (cfg.modifiers and cfg.modifiers.shield_regen) or 1.0

    combat_manager.reset({
        on_hit = on_hit, on_kill = on_kill, on_structure_killed = on_structure_killed,
        on_module = on_module, on_missile_kill = on_missile_kill,
    })
    mode_impl = MODES[cfg.mode] or MODES.tdm
    apply_theme(cfg.theme)
    mode_impl.setup(match, api)
    if not match.player then api.spawn_player() end

    ai_ctx.ships = match.ships
    ai_ctx.structures = match.structures
    ai_ctx.beacons = match.beacons
    ai_ctx.pickups = match.pickups
    ai_ctx.mode = match.mode
    ai_ctx.skill = api.skill

    camera_rig.reset(match.player.pos, match.player.forward)
    pool_manager.init_dust(camera_rig.get_pos(), camera_rig.get_forward())
end

-- ============================================================== FINISH
local function eval_star(rule)
    local st = match.stats
    if rule.type == "deaths_max" then return st.deaths <= rule.v end
    if rule.type == "time_max" then return match.time_elapsed <= rule.v end
    if rule.type == "kills_min" then return st.kills >= rule.v end
    if rule.type == "protect_min" then return (match.protect_pct or 100) >= rule.v end
    return false
end

function M.finish(won)
    if match.finished then return end
    match.finished = true
    match.active = false
    match.missile_warning = false
    if match.player then match.player.locked_target = nil end
    poki.gameplay_stop()
    if mode_impl.on_finish then mode_impl.on_finish(match, api, won) end

    local cfg = match.cfg
    local st = match.stats
    local s = progress.get()
    s.match_count = s.match_count + 1
    s.test_drive_active = false
    s.stats.matches = s.stats.matches + 1
    s.stats.deaths = s.stats.deaths + st.deaths
    s.stats.playtime = s.stats.playtime + math.floor(match.time_elapsed)
    progress.track("kills", st.kills)
    progress.track("missile_kills", st.missile_kills)
    progress.track("drones", st.drones)
    progress.track("rings", st.rings)
    progress.track("beacons", st.beacons)
    progress.track("damage", math.floor(st.damage))
    progress.track("modules", st.modules)
    if won then progress.track("wins", 1) end

    local res = {
        won = won, kills = st.kills, deaths = st.deaths, time = match.time_elapsed,
        damage = math.floor(st.damage), stars = 0, star_flags = { false, false, false },
        star_rules = {}, credits = 0, parts = 0, xp = 0, levels = {}, first_clear = false,
        mission_id = cfg.mission_id, doubled = false, kind = cfg.kind, wave = match.wave_reached,
    }
    if cfg.kind == "campaign" and cfg.mission_id then
        local m = campaign_db.get(cfg.mission_id)
        local flags = { won, false, false }
        if won then
            for i = 1, 2 do flags[i + 1] = eval_star(m.stars[i]) end
        end
        res.star_flags = flags
        res.star_rules = { { type = "win" }, m.stars[1], m.stars[2] }
        local n = 0
        for i = 1, 3 do if flags[i] then n = n + 1 end end
        res.stars = n
        local gained, first = progress.record_mission(cfg.mission_id, n, match.time_elapsed)
        res.first_clear = first
        res.new_stars = gained
        if gained > 0 then progress.track("stars", gained) end
        local rw = m.reward
        if won then
            res.credits = rw.credits + st.kills * 10 + gained * 50
            res.parts = rw.parts + (first and 1 or 0)
            res.xp = rw.xp + st.kills * 8
            if first then res.credits = res.credits + rw.credits end
        else
            res.credits = math.floor(rw.credits * 0.35) + st.kills * 8
            res.parts = 0
            res.xp = math.floor(rw.xp * 0.4) + st.kills * 6
        end
    else
        local mm = progression_db.MATCH
        res.credits = (won and mm.win_credits or mm.loss_credits) + st.kills * mm.kill_credits
        res.parts = won and mm.win_parts or mm.loss_parts
        res.xp = (won and mm.win_xp or mm.loss_xp) + st.kills * mm.kill_xp
        if match.wave_reached then
            res.credits = res.credits + match.wave_reached * 25
            res.xp = res.xp + match.wave_reached * 15
        end
    end
    res.xp_before = s.xp
    res.level_before = s.level
    res.levels = progress.add_xp(res.xp)
    progress.add_rewards(res.credits, res.parts)
    match.result = res
    audio.play(won and "victory" or "defeat", 0.75)
end

-- ============================================================== UPDATE
local function update_ship_timers(s, dt)
    if s.fire_cd > 0 then s.fire_cd = math.max(0, s.fire_cd - dt) end
    if s.dash_cd > 0 then s.dash_cd = math.max(0, s.dash_cd - dt) end
    if s.dash_timer > 0 then s.dash_timer = math.max(0, s.dash_timer - dt) end
    local target_dv = (s.dash_timer > 0) and 1.0 or (s.boosting and 0.55 or 0.0)
    s.dash_visual = math3d.lerp(s.dash_visual or 0, target_dv, math.min(1.0, dt * (target_dv > (s.dash_visual or 0) and 14.0 or 6.0)))
    pool_manager.set_ship_trail_dash(s.pool_slot, s.dash_visual)
    if s.mod1_cd > 0 then s.mod1_cd = math.max(0, s.mod1_cd - dt) end
    if s.mod2_cd > 0 then s.mod2_cd = math.max(0, s.mod2_cd - dt) end
    if s.invuln_timer > 0 then s.invuln_timer = math.max(0, s.invuln_timer - dt) end
    if s.warp_flash > 0 then s.warp_flash = math.max(0, s.warp_flash - dt) end
    if s.overdrive_timer > 0 then s.overdrive_timer = math.max(0, s.overdrive_timer - dt) end
    if s.bump_cd > 0 then s.bump_cd = s.bump_cd - dt end
    if s.dome_timer > 0 then
        s.dome_timer = math.max(0, s.dome_timer - dt)
        if s.dome_timer <= 0 then pool_manager.set_ship_dome(s.pool_slot, false) end
    end
    if s.cloak_timer > 0 then
        s.cloak_timer = math.max(0, s.cloak_timer - dt)
        if s.cloak_timer <= 0 then pool_manager.set_ship_cloak(s.pool_slot, 0) end
    end
    if s.nano_timer > 0 then
        s.nano_timer = math.max(0, s.nano_timer - dt)
        local cfgm = modules_db.MODULES.nanorepair
        s.hull = math.min(s.max_hull, s.hull + s.max_hull * cfgm.heal_pct / cfgm.duration * dt)
    end
    if s.shield_regen_delay > 0 then
        s.shield_regen_delay = math.max(0, s.shield_regen_delay - dt)
    elseif s.shield < s.max_shield then
        s.shield = math.min(s.max_shield, s.shield + s.max_shield * 0.25 * match.shield_regen_mult * dt)
    end
    if s.missiles < s.missiles_max then
        s.missile_cd = s.missile_cd - dt
        if s.missile_cd <= 0 then
            s.missiles = s.missiles + 1
            s.missile_cd = (s.missiles < s.missiles_max) and modules_db.MISSILE.recharge or 0
        end
    end
    if s.hit_flash > 0 then
        s.hit_flash = math.max(0, s.hit_flash - dt * 12.0)
        pool_manager.set_ship_hit_flash(s.pool_slot, s.hit_flash)
    end
    if s.under_fire_timer > 0 then s.under_fire_timer = math.max(0, s.under_fire_timer - dt) end
    if s.recent_dmg > 0 then s.recent_dmg = math.max(0, s.recent_dmg - (s.max_hull * 0.25) * dt) end
end

local function respawn(s)
    local list = (s.team == 1) and match.layout.spawns.team1 or match.layout.spawns.team2
    local p = list[math.random(1, #list)]
    local sp = vmath.vector3(p[1] + math.random(-6, 6), p[2] + math.random(-4, 4), p[3])
    s.pos = vmath.vector3(sp.x, sp.y, sp.z)
    s.forward = math3d.normalize_or_default(vmath.vector3(-sp.x, 0, -sp.z), s.spawn_fwd)
    s.rot = math3d.quat_from_forward(s.forward, 0)
    s.hull, s.shield = s.max_hull, s.max_shield
    s.energy = s.max_energy
    s.missiles = s.missiles_max
    s.alive = true
    s.invuln_timer = 2.0
    s.hit_flash, s.dash_timer, s.dash_visual, s.under_fire_timer, s.recent_dmg, s.evade_timer = 0, 0, 0, 0, 0, 0
    s.cur_speed = s.speed
    s.yaw_vel, s.pitch_vel, s.strafe_vel = 0, 0, 0
    s.locked_target = nil
    s.ai_target = nil
    pool_manager.configure_ship_visual(s.pool_slot, s.mesh, s.tier, s.skin_id, s.trail_id, true)
    go.set_position(s.pos, s.pool_slot.id)
    s.ang_vel = 0
    if s.is_player then
        s.aim_dir = vmath.vector3(s.forward.x, s.forward.y, s.forward.z)
        camera_rig.reset(s.pos, s.forward)
    end
end

local function update_pickups(dt)
    for i = 1, #match.pickups do
        local pk = match.pickups[i]
        if pk.active then
            local pulse = 0.5 + 0.5 * math.sin(match.time_elapsed * 3.2 + pk.pos.x * 0.1)
            pool_manager.update_pickup_visual(pk.slot, pulse)
            for s = 1, #match.ships do
                local ship = match.ships[s]
                if ship.alive and ship.ai ~= "drone" and ship.ai ~= "kamikaze" and not ship.is_vip then
                    local r = ship.radius + pk.radius
                    if math3d.vec_dist_sq(ship.pos, pk.pos) <= r * r then
                        local collected = false
                        if pk.kind == "repair" and ship.hull < ship.max_hull * 0.99 then
                            ship.hull = math.min(ship.max_hull, ship.hull + ship.max_hull * 0.40)
                            collected = true
                        elseif pk.kind == "charge" and (ship.shield < ship.max_shield * 0.99 or ship.dash_cd > 0 or ship.mod1_cd > 0 or ship.mod2_cd > 0 or ship.energy < ship.max_energy) then
                            ship.shield = ship.max_shield
                            ship.shield_regen_delay = 0
                            ship.dash_cd, ship.mod1_cd, ship.mod2_cd = 0, 0, 0
                            ship.energy = ship.max_energy
                            ship.missiles = ship.missiles_max
                            collected = true
                        end
                        if collected then
                            pk.active = false
                            pk.respawn_timer = pk.respawn
                            pool_manager.configure_pickup_visual(pk.slot, pk.kind, false)
                            if pk.kind == "repair" then
                                pool_manager.spawn_vfx(pk.pos, 0.28, 0.95, 0.55, 8.5, 0.45)
                            else
                                pool_manager.spawn_vfx(pk.pos, 0.15, 0.88, 1.0, 8.5, 0.45)
                            end
                            if ship.is_player then
                                audio.play("heal", 0.75)
                                api.banner(pk.kind == "repair" and "pickup_repair" or "pickup_charge", pk.kind == "repair" and "green" or "aqua", nil, 1.8)
                            end
                            break
                        end
                    end
                end
            end
        else
            pk.respawn_timer = pk.respawn_timer - dt
            if pk.respawn_timer <= 0 then
                pk.active = true
                go.set_position(pk.pos, pk.slot.id)
                pool_manager.configure_pickup_visual(pk.slot, pk.kind, true)
            end
        end
    end
end

local function update_structures(dt)
    for i = 1, #match.structures do
        local s = match.structures[i]
        if s.alive and s.hit_flash > 0 and s.mesh_url then
            s.hit_flash = math.max(0, s.hit_flash - dt * 12.0)
            local f = 1.0 + s.hit_flash * 2.0
            go.set(s.mesh_url, "tint", vmath.vector4(f, f, f, 1.0))
        end
        if s.alive and s.max_shield > 0 and s.shield < s.max_shield and (s.shield_regen_delay or 0) <= 0 and s.regen then
            s.shield = math.min(s.max_shield, s.shield + s.max_shield * s.regen * dt)
        end
        if s.shield_regen_delay and s.shield_regen_delay > 0 then s.shield_regen_delay = s.shield_regen_delay - dt end
    end
end

local STICK_AIM_RATE = 2.3     -- rad/s of aim rotation at full stick deflection
local AIM_LEASH = math.rad(70) -- the aim may lead the nose by at most this angle
local AIM_MAX_Y = 0.85         -- aim pitch limit (sin of ~58 degrees)
local ASSIST_CONE = math.cos(math.rad(7))

-- Mouse-aim: the aim direction lives in world space. Mouse deltas rotate it directly,
-- stick / gamepad rotate it at a rate; the ship then turns towards it on its own.
local function update_aim(p, inp, set, locked, dt)
    local aim = p.aim_dir or p.forward
    local sens = set.sensitivity or 1.0
    local inv = set.invert_y and -1 or 1
    local sx, sy = inp.steer_x, inp.steer_y
    local yaw = -inp.aim_dx * sens - sx * (0.35 + 0.65 * math.abs(sx)) * STICK_AIM_RATE * sens * dt
    local pitch = (inp.aim_dy * sens + sy * (0.35 + 0.65 * math.abs(sy)) * STICK_AIM_RATE * sens * dt) * inv
    local active = math.abs(yaw) + math.abs(pitch) > 1e-5
    if active then
        aim = math3d.rotate_about(aim, 0, 1, 0, yaw)
        local r = vmath.cross(aim, vmath.vector3(0, 1, 0))
        local rl = vmath.length(r)
        if rl > 1e-4 then
            r = r * (1 / rl)
            aim = math3d.rotate_about(aim, r.x, r.y, r.z, pitch)
        end
    end
    aim = math3d.clamp_pitch(math3d.normalize_or_default(aim, p.forward), AIM_MAX_Y, p.forward)
    -- Leash to the nose so the camera never swings away from the ship.
    local ang = math.acos(math3d.clamp(vmath.dot(aim, p.forward), -1, 1))
    if ang > AIM_LEASH then
        aim = math3d.rotate_towards(aim, p.forward, (ang - AIM_LEASH) / ang)
    end
    -- Arena shell push-back: let the aim follow the nose back inside.
    if p.near_boundary then
        aim = math3d.rotate_towards(aim, p.forward, math.min(1, dt * 4.0))
    end
    -- Gentle aim assist while the player is not actively steering.
    if locked and locked.alive and not active then
        local lead = math3d.compute_lead_point(p.pos, locked.pos, locked.vel or vmath.vector3(), p.proj_speed)
        local to = math3d.normalize_or_default(lead - p.pos, aim)
        if vmath.dot(aim, to) > ASSIST_CONE then
            aim = math3d.rotate_towards(aim, to, math.min(1, dt * 1.6))
        end
    end
    p.aim_dir = aim
    return aim
end

local function control_player(p, dt)
    local inp = input_state
    local set = progress.settings()
    if p.alive then
        local aim = update_aim(p, inp, set, p.locked_target, dt)
        flight_physics.update_player_aim(p, aim, inp, dt)
        if p.boost_started then
            p.boost_started = false
            audio.play("boost", 0.4)
        end
        camera_rig.update_battle(p, aim, dt)

        local lock_r = (inp.device == "touch") and 215 or 175
        local locked = combat_manager.acquire_player_lock(p, match.ships, match.structures, lock_r)
        local want_fire = inp.fire or (set.autofire and locked ~= nil)
        if want_fire then
            local dist = p.weapon_range * 0.85
            if locked then dist = math.sqrt(math3d.vec_dist_sq(camera_rig.get_pos(), locked.pos)) end
            combat_manager.fire_primary(p, locked, camera_rig.get_aim_point(dist))
        end
        if inp.dash then
            local sign = (inp.strafe ~= 0) and -inp.strafe or ((inp.steer_x >= 0) and -1 or 1)
            if not combat_manager.activate_dash(p, sign) then audio.play("error", 0.3) end
        end
        if inp.missile then
            if locked and p.missiles > 0 then
                combat_manager.fire_missile(p, locked)
            else
                audio.play("error", 0.35)
                if not locked then api.hint("hint_need_lock", 1.6) end
            end
        end
        if inp.mod1 and not combat_manager.activate_module(p, 1, match.ships, match.structures) then audio.play("error", 0.3) end
        if inp.mod2 and not combat_manager.activate_module(p, 2, match.ships, match.structures) then audio.play("error", 0.3) end
        match.missile_warning = combat_manager.has_incoming_missile(p) or (match.salvo_on_player or false)
    else
        match.missile_warning = false
        local focus = p.killer and p.killer.alive and p.killer.pos or nil
        camera_rig.update_death(p.death_pos or p.pos, focus, dt)
    end
end

local function apply_bumps(s)
    local imp = s.bump_impact or 0
    if imp > 0 then
        s.bump_impact = 0
        if imp > 22 and s.bump_cd <= 0 and s.alive and not s.is_vip then
            s.bump_cd = 0.6
            s.cur_speed = (s.cur_speed or s.speed) * 0.55
            local dmg = s.max_hull * 0.025 * math.min(2.0, imp / 30)
            s.hull = s.hull - dmg
            s.hit_flash = 1.0
            if s.is_player then
                camera_rig.add_shake(0.45)
                audio.play("shield_hit", 0.6)
                match.hurt_timer = 0.4
            end
            if s.hull <= 0 then
                s.hull = 1
                combat_manager.apply_damage(s, 5, "explosion", nil)
            end
        end
    end
end

function M.update(dt)
    if not match.active or match.paused then return end
    match.time_elapsed = match.time_elapsed + dt
    ai_ctx.time = match.time_elapsed
    ai_ctx.vip = match.vip
    ai_ctx.station = match.station

    -- HUD timers
    if match.hit_marker_timer > 0 then match.hit_marker_timer = math.max(0, match.hit_marker_timer - dt) end
    if match.kill_banner_timer > 0 then match.kill_banner_timer = math.max(0, match.kill_banner_timer - dt) end
    if match.hurt_timer > 0 then match.hurt_timer = math.max(0, match.hurt_timer - dt) end
    if match.banner then
        match.banner.timer = match.banner.timer - dt
        if match.banner.timer <= 0 then match.banner = nil end
    end
    if match.hint then
        match.hint.timer = match.hint.timer - dt
        if match.hint.timer <= 0 then match.hint = nil end
    end
    for i = 1, FEED_SIZE do
        local f = match.feed[i]
        if f.active then
            f.timer = f.timer - dt
            if f.timer <= 0 then f.active = false end
        end
    end
    for i = 1, DMG_NUMBERS do
        local d = match.dmg_numbers[i]
        if d.active then
            d.timer = d.timer - dt
            if d.timer <= 0 then d.active = false end
        end
    end
    local st = match.stats
    if st.multi_timer > 0 then st.multi_timer = st.multi_timer - dt end
    if st.streak > st.best_streak then st.best_streak = st.streak end

    match.timer = match.timer - dt
    if match.timer <= 0 then
        match.timer = 0
        local won = mode_impl.on_timeout and mode_impl.on_timeout(match, api) or false
        M.finish(won)
        return
    end

    -- Timers / respawns
    for i = 1, #match.ships do
        local s = match.ships[i]
        if s.alive then
            update_ship_timers(s, dt)
        elseif not s.removed then
            if s.can_respawn then
                s.respawn_timer = s.respawn_timer - dt
                if s.respawn_timer <= 0 then respawn(s) end
            else
                release_ship(s)
            end
        end
    end

    local p = match.player
    if p then control_player(p, dt) end
    local sr = (p and p.alive) and math3d.clamp((p.cur_speed or p.speed) / (p.speed * 1.8), 0, 1) or 0.2
    pool_manager.update_dust(camera_rig.get_pos(), camera_rig.get_forward(), sr, (p and p.alive) and (p.dash_visual or 0) or 0)

    for i = 1, #match.ships do
        local s = match.ships[i]
        if not s.is_player and s.alive and s.ai ~= "freighter" then
            ai_controller.update_bot(s, ai_ctx, dt)
        end
    end

    if mode_impl.update then mode_impl.update(match, api, dt) end
    if match.finished then return end

    for i = 1, #match.ships do
        local s = match.ships[i]
        if s.alive then
            apply_bumps(s)
            go.set_position(s.pos, s.pool_slot.id)
            go.set_rotation(s.rot, s.pool_slot.id)
        end
    end

    combat_manager.update(match.ships, match.structures, dt)
    update_pickups(dt)
    update_structures(dt)
    pool_manager.update_vfx(dt)

    -- Compact removed ships
    local n = #match.ships
    local w = 1
    for r = 1, n do
        local s = match.ships[r]
        if not s.removed then
            match.ships[w] = s
            w = w + 1
        end
    end
    for k = w, n do match.ships[k] = nil end
end

function M.set_paused(paused)
    if not match.active or match.finished then
        match.paused = false
        return
    end
    match.paused = paused and true or false
    if match.paused then poki.gameplay_stop() else poki.gameplay_start() end
end

function M.stop_match()
    match.active = false
    match.paused = false
    match.banner = nil
    match.hint = nil
    match.missile_warning = false
    pool_manager.hide_all()
    for i = 1, pool_manager.SHIP_POOL do pool_manager.get_ship_slot(i).in_use = false end
    match.ships = {}
    match.structures = {}
    poki.gameplay_stop()
end

-- ===================================================== CONFIG BUILDERS
function M.campaign_config(mission_id)
    local m = campaign_db.get(mission_id)
    local sector = campaign_db.SECTORS[m.sector]
    return {
        kind = "campaign", mission_id = m.id, mode = m.mode, layout = m.layout, theme = sector.theme,
        difficulty = m.difficulty, bot_tier = m.bot_tier, allies = m.allies, enemies = m.enemies,
        params = m.params, time_limit = m.time_limit, modifiers = m.modifiers,
    }
end

function M.skirmish_config(preset_id)
    local s = progress.get()
    local preset = campaign_db.SKIRMISH[1]
    for _, p in ipairs(campaign_db.SKIRMISH) do if p.id == preset_id then preset = p end end
    s.skirmish_round = (s.skirmish_round or 0) + 1
    local layouts = preset.layout_cycle
    local layout = layouts[((s.skirmish_round - 1) % #layouts) + 1]
    local themes = { "kepler", "ion", "crimson", "void" }
    local diff = math.max(1, math.min(9, 1 + math.floor(s.level / 2)))
    local tier = math.max(1, math.min(5, progress.get_player_tier(s.selected)))
    local params = {}
    for k, v in pairs(preset.params) do params[k] = v end
    if preset.mode == "boss" then params.mk = math.min(3, 1 + math.floor(s.level / 8)) end
    return {
        kind = "skirmish", preset_id = preset.id, mode = preset.mode, layout = layout,
        theme = themes[(s.skirmish_round % #themes) + 1], difficulty = diff, bot_tier = tier,
        allies = preset.allies, enemies = preset.enemies, params = params,
        time_limit = preset.time_limit, modifiers = {},
    }
end

return M
