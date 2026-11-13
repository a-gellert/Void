-- Dreadnought Raid. Phase 1: 3 shield generators (energy dome up). Phase 2: 4 turrets
-- with telegraphed missile salvos. Phase 3: reactor core.
-- params.mk 1..3 scales hull, salvo pace and adds pirate drone waves (mk >= 2).
local math3d = require("modules.math3d")
local pool_manager = require("modules.pool_manager")
local combat_manager = require("modules.combat_manager")
local audio = require("modules.audio")

local M = {}

local NEUTRAL = vmath.vector4(1, 1, 1, 1)
local MK = {
    { hp = 1.0, salvo = 1.0, count = 0, drones = 0 },
    { hp = 1.45, salvo = 0.82, count = 0, drones = 3 },
    { hp = 2.0, salvo = 0.68, count = 1, drones = 4 },
}

function M.setup(match, api)
    local L = match.layout
    local bcfg = L.boss
    local bp = vmath.vector3(bcfg.pos[1], bcfg.pos[2], bcfg.pos[3])
    match.boss_pos = bp
    match.mk = MK[match.cfg.params.mk or 1] or MK[1]
    api.build_environment({ extra_obstacles = {
        { x = bp.x, y = bp.y, z = bp.z, r = bcfg.hull_radius, no_projectile_block = true },
    } })

    local d_idx = 1
    local hull_slot = pool_manager.get_dreadnought_slot(d_idx); d_idx = d_idx + 1
    msg.post(hull_slot.urls.hull, "enable")
    msg.post(hull_slot.urls.dome, "enable")
    go.set_position(bp, hull_slot.id)
    go.set_rotation(vmath.quat(), hull_slot.id)
    go.set_scale(vmath.vector3(1, 1, 1), hull_slot.id)
    go.set(hull_slot.urls.dome, "tint", vmath.vector4(0.22, 0.72, 1.0, 0.24))
    match.boss_hull_slot = hull_slot
    match.boss_dome_active = true
    match.boss_dome_flash = 0
    match.boss_phase = 1
    match.boss_salvo_cd = 4.5
    match.drone_timer = 25.0

    local tier_scale = 1.5 * (1 + 0.15 * ((match.cfg.bot_tier or 1) - 1)) * match.mk.hp
    local dmg_scale = api.skill(2).dmg_mult
    local id_rot = vmath.quat()
    local function add_part(kind, def, url_key, extra)
        local s = pool_manager.get_dreadnought_slot(d_idx); d_idx = d_idx + 1
        msg.post(s.urls[url_key], "enable")
        go.set(s.urls[url_key], "tint", NEUTRAL)
        local p = bp + vmath.vector3(def.offset[1], def.offset[2], def.offset[3])
        go.set_position(p, s.id)
        go.set_rotation(id_rot, s.id)
        go.set_scale(vmath.vector3(1, 1, 1), s.id)
        local part = {
            id = def.id, kind = kind, team = 2, pool_slot = s, mesh_url = s.urls[url_key],
            pos = p, rot = vmath.quat(), radius = def.radius,
            hull = def.hp * tier_scale, max_hull = def.hp * tier_scale, shield = 0, max_shield = 0,
            targetable = kind == "generator", shielded = kind ~= "generator",
            name = kind, display_name = string.upper(kind),
        }
        if extra then for k, v in pairs(extra) do part[k] = v end end
        return api.add_structure(part)
    end
    for _, g in ipairs(bcfg.generators) do add_part("generator", g, "gen") end
    for _, t in ipairs(bcfg.turrets) do
        add_part("turret", t, "turret", {
            fire_rate = t.fire_rate, damage = t.damage * dmg_scale, fire_cd = math.random() * 1.5,
            salvo_telegraph = 0, salvo_target = nil, salvo_vfx_cd = 0, salvo_count = 2,
        })
    end
    add_part("reactor", bcfg.reactor, "reactor")

    api.spawn_player()
    api.spawn_pilots(1, match.cfg.allies or 3)
    match.score_kind = "none"
    api.hint("hint_boss", 7.0)
end

local function update_phases(match)
    local gens, turrets = 0, 0
    for _, s in ipairs(match.structures) do
        if s.alive then
            if s.kind == "generator" then gens = gens + 1 elseif s.kind == "turret" then turrets = turrets + 1 end
        end
    end
    local phase = (gens > 0) and 1 or ((turrets > 0) and 2 or 3)
    if match.boss_dome_active and gens == 0 then
        match.boss_dome_active = false
        msg.post(match.boss_hull_slot.urls.dome, "disable")
        pool_manager.spawn_vfx(match.boss_pos, 0.25, 0.78, 1.0, 48.0, 0.75)
        audio.play("emp", 0.75)
    end
    for _, s in ipairs(match.structures) do
        if s.kind == "generator" then
            s.targetable, s.shielded = s.alive, false
        elseif s.kind == "turret" then
            s.targetable, s.shielded = (gens == 0) and s.alive, gens > 0
        elseif s.kind == "reactor" then
            s.targetable, s.shielded = (gens == 0 and turrets == 0) and s.alive, (gens > 0 or turrets > 0)
        end
    end
    return phase
end

local function pick_salvo_target(match, pos)
    local max_sq = 265 * 265
    local p = match.player
    if p and p.alive and math3d.vec_dist_sq(pos, p.pos) <= max_sq and math.random() < 0.6 then return p end
    local best, best_sq = nil, max_sq
    for _, sh in ipairs(match.ships) do
        if sh.alive and sh.team == 1 then
            local d = math3d.vec_dist_sq(pos, sh.pos)
            if d < best_sq then best_sq = d; best = sh end
        end
    end
    return best
end

function M.update(match, api, dt)
    local new_phase = update_phases(match)
    if new_phase ~= match.boss_phase then
        match.boss_phase = new_phase
        api.banner(new_phase == 2 and "boss_phase2" or "boss_phase3", "gold", nil, 2.4)
        audio.play("objective", 0.6)
    end

    -- Dome pulse + impact flash
    if match.boss_dome_active then
        for _, s in ipairs(match.structures) do
            if s.shield_hit_flash and s.shield_hit_flash > 0 then
                s.shield_hit_flash = 0
                match.boss_dome_flash = 1.0
            end
        end
        match.boss_dome_flash = math.max(0, match.boss_dome_flash - dt * 5.0)
        local pulse = 0.19 + 0.04 * math.sin(match.time_elapsed * 4.2) + match.boss_dome_flash * 0.22
        local boost = match.boss_dome_flash * 0.55
        go.set(match.boss_hull_slot.urls.dome, "tint", vmath.vector4(0.22 + boost, 0.72 + boost * 0.35, 1.0, pulse))
    end

    -- Coordinated telegraphed missile salvos
    if match.boss_phase <= 2 then
        match.boss_salvo_cd = match.boss_salvo_cd - dt
        if match.boss_salvo_cd <= 0 then
            local ready = {}
            for _, s in ipairs(match.structures) do
                if s.alive and s.kind == "turret" and s.salvo_telegraph <= 0 then ready[#ready + 1] = s end
            end
            if #ready > 0 then
                local chosen = ready[math.random(1, #ready)]
                local tgt = pick_salvo_target(match, chosen.pos)
                if tgt then
                    chosen.salvo_telegraph = (match.boss_phase == 1) and 1.5 or 1.35
                    chosen.salvo_count = ((match.boss_phase == 1) and 2 or 3) + match.mk.count
                    chosen.salvo_target = tgt
                    chosen.salvo_vfx_cd = 0
                    match.boss_salvo_cd = ((match.boss_phase == 1) and 7.5 or 5.5) * match.mk.salvo
                    if tgt.is_player then audio.play("alarm", 0.6) end
                else
                    match.boss_salvo_cd = 1.5
                end
            else
                match.boss_salvo_cd = 2.0
            end
        end
    end

    local salvo_on_player = false
    for _, s in ipairs(match.structures) do
        if s.alive and s.kind == "turret" then
            if s.salvo_telegraph > 0 then
                local tgt = s.salvo_target
                if not tgt or not tgt.alive then
                    s.salvo_telegraph = 0
                    s.salvo_target = nil
                    go.set(s.mesh_url, "tint", NEUTRAL)
                else
                    s.salvo_telegraph = s.salvo_telegraph - dt
                    tgt.salvo_threat = s.salvo_telegraph < 0.5
                    local dir = math3d.normalize_or_default(tgt.pos - s.pos)
                    s.rot = math3d.quat_from_forward(dir, 0)
                    go.set_rotation(s.rot, s.pool_slot.id)
                    if tgt.is_player then salvo_on_player = true end
                    local glow = 0.5 + 0.5 * math.sin(match.time_elapsed * 22.0)
                    go.set(s.mesh_url, "tint", vmath.vector4(1.4 + glow * 1.6, 0.35 + glow * 0.45, 0.15, 1.0))
                    s.salvo_vfx_cd = s.salvo_vfx_cd - dt
                    if s.salvo_vfx_cd <= 0 then
                        s.salvo_vfx_cd = 0.45
                        pool_manager.spawn_vfx(s.pos + dir * 4.5, 1.0, 0.35, 0.10, 7.5, 0.38)
                    end
                    if s.salvo_telegraph <= 0 then
                        s.salvo_telegraph = 0
                        s.salvo_target = nil
                        tgt.salvo_threat = false
                        go.set(s.mesh_url, "tint", NEUTRAL)
                        combat_manager.fire_turret_salvo(s, tgt, s.salvo_count, 1.0)
                    end
                end
            else
                s.fire_cd = s.fire_cd - dt
                if s.fire_cd <= 0 then
                    s.fire_cd = 1.0 / s.fire_rate
                    local best, best_sq = nil, 240 * 240
                    for _, sh in ipairs(match.ships) do
                        if sh.alive and sh.team == 1 then
                            local d = math3d.vec_dist_sq(s.pos, sh.pos)
                            if d < best_sq then best_sq = d; best = sh end
                        end
                    end
                    if best then
                        combat_manager.fire_turret(s, best, 1.0)
                        go.set_rotation(s.rot, s.pool_slot.id)
                    end
                end
            end
        end
    end
    match.salvo_on_player = salvo_on_player

    -- Mk II / III: pirate drone escorts
    if match.mk.drones > 0 then
        match.drone_timer = match.drone_timer - dt
        if match.drone_timer <= 0 then
            match.drone_timer = 30.0
            for i = 1, match.mk.drones do
                if api.free_slots() > 1 then
                    local kind = (match.mk.count > 0 and i % 2 == 0) and "kamikaze" or "drone"
                    api.spawn_drone(kind, match.boss_pos + vmath.vector3(math.random(-40, 40), 30, -40), 2)
                end
            end
            api.banner("drones_launched", "coral", nil, 2.0)
        end
    end

    -- Boss bar
    local total, cur = 0, 0
    for _, s in ipairs(match.structures) do
        total = total + s.max_hull
        if s.alive then cur = cur + s.hull end
    end
    local keys = { "boss_gen", "boss_turret", "boss_reactor" }
    match.boss_bar = { key = keys[match.boss_phase], pct = total > 0 and cur / total or 0 }
    api.set_objective("obj_boss", match.boss_phase, 3, 1 - (total > 0 and cur / total or 0))
end

function M.on_structure_killed(match, api, s)
    s.salvo_telegraph = 0
    s.salvo_target = nil
    update_phases(match)
    if s.kind == "reactor" then
        pool_manager.spawn_vfx(match.boss_pos, 1.0, 0.7, 0.25, 60.0, 1.2)
        api.finish(true)
    end
end

function M.on_finish(match)
    match.salvo_on_player = false
    if match.boss_hull_slot then msg.post(match.boss_hull_slot.urls.dome, "disable") end
    for _, s in ipairs(match.structures) do
        if s.alive and s.mesh_url then go.set(s.mesh_url, "tint", NEUTRAL) end
    end
end

return M
