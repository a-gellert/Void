local ships_db = require("data.ships_db")

local M = {}

local HIDE_POS = vmath.vector3(0, -5000, 0)
local ZERO_VEC4 = vmath.vector4(0, 0, 0, 0)
local ONE_VEC4 = vmath.vector4(1, 1, 1, 1)

local pools = {
    ships = {},
    lasers = {},
    missiles = {},
    vfx = {},
    asteroids = {},
    beacons = {},
    dreadnought = {},
}

local function set_comp_enabled(id, comp, enabled)
    msg.post(msg.url(nil, id, comp), enabled and "enable" or "disable")
end

function M.init()
    -- 8 Ships
    for i = 1, 8 do
        local id = factory.create("/factories#ship", HIDE_POS)
        local entry = {
            id = id,
            in_use = false,
            active_mesh = nil,
            urls = {
                interceptor = msg.url(nil, id, "mesh_interceptor"),
                fighter = msg.url(nil, id, "mesh_fighter"),
                frigate = msg.url(nil, id, "mesh_frigate"),
                t2 = msg.url(nil, id, "tier_t2"),
                t3 = msg.url(nil, id, "tier_t3"),
                t4 = msg.url(nil, id, "tier_t4"),
                t5 = msg.url(nil, id, "tier_t5"),
                trail = msg.url(nil, id, "trail"),
                dome = msg.url(nil, id, "dome"),
            },
        }
        for _, u in pairs(entry.urls) do
            msg.post(u, "disable")
        end
        pools.ships[i] = entry
    end

    -- 120 Laser pulses
    for i = 1, 120 do
        local id = factory.create("/factories#projectile", HIDE_POS)
        set_comp_enabled(id, "laser", false)
        set_comp_enabled(id, "missile", false)
        pools.lasers[i] = {
            id = id,
            url = msg.url(nil, id, "laser"),
            active = false,
        }
    end

    -- 24 Missiles
    for i = 1, 24 do
        local id = factory.create("/factories#projectile", HIDE_POS)
        set_comp_enabled(id, "laser", false)
        set_comp_enabled(id, "missile", false)
        pools.missiles[i] = {
            id = id,
            url = msg.url(nil, id, "missile"),
            active = false,
        }
    end

    -- 40 VFX spheres
    for i = 1, 40 do
        local id = factory.create("/factories#vfx", HIDE_POS)
        local url = msg.url(nil, id, "sphere")
        msg.post(url, "disable")
        pools.vfx[i] = {
            id = id,
            url = url,
            active = false,
            timer = 0,
            duration = 0.4,
            max_scale = 5,
            r = 1, g = 0.7, b = 0.2,
        }
    end

    -- 16 Asteroid / Station slots
    for i = 1, 16 do
        local id = factory.create("/factories#asteroid", HIDE_POS)
        local entry = {
            id = id,
            urls = {
                mesh1 = msg.url(nil, id, "mesh1"),
                mesh2 = msg.url(nil, id, "mesh2"),
                hollow = msg.url(nil, id, "mesh_hollow"),
                station = msg.url(nil, id, "mesh_station"),
            },
        }
        for _, u in pairs(entry.urls) do
            msg.post(u, "disable")
        end
        pools.asteroids[i] = entry
    end

    -- 3 Beacons
    for i = 1, 3 do
        local id = factory.create("/factories#beacon", HIDE_POS)
        local entry = {
            id = id,
            mesh = msg.url(nil, id, "mesh"),
            zone = msg.url(nil, id, "zone"),
        }
        msg.post(entry.mesh, "disable")
        msg.post(entry.zone, "disable")
        pools.beacons[i] = entry
    end

    -- 9 Dreadnought pieces (1 hull, 3 generators, 4 turrets, 1 reactor)
    for i = 1, 9 do
        local id = factory.create("/factories#dreadnought", HIDE_POS)
        local entry = {
            id = id,
            urls = {
                hull = msg.url(nil, id, "hull"),
                gen = msg.url(nil, id, "gen"),
                turret = msg.url(nil, id, "turret"),
                reactor = msg.url(nil, id, "reactor"),
            },
        }
        for _, u in pairs(entry.urls) do
            msg.post(u, "disable")
        end
        pools.dreadnought[i] = entry
    end
end

function M.get_ship_slot(index)
    return pools.ships[index]
end

function M.configure_ship_visual(slot, class_id, tier, skin_id, trail_id, visible)
    if not slot then return end
    local u = slot.urls
    msg.post(u.interceptor, (visible and class_id == "interceptor") and "enable" or "disable")
    msg.post(u.fighter, (visible and class_id == "fighter") and "enable" or "disable")
    msg.post(u.frigate, (visible and class_id == "frigate") and "enable" or "disable")

    msg.post(u.t2, (visible and tier >= 2) and "enable" or "disable")
    msg.post(u.t3, (visible and tier >= 3) and "enable" or "disable")
    msg.post(u.t4, (visible and tier >= 4) and "enable" or "disable")
    msg.post(u.t5, (visible and tier >= 5) and "enable" or "disable")
    msg.post(u.trail, visible and "enable" or "disable")
    msg.post(u.dome, "disable")

    slot.active_mesh = u[class_id]
    if visible and slot.active_mesh then
        local skin = ships_db.SKINS[skin_id] or ships_db.SKINS[1]
        go.set(slot.active_mesh, "skin_offset", vmath.vector4(skin.u_offset, skin.v_offset, 0, 0))
        go.set(slot.active_mesh, "tint", ONE_VEC4)
        for _, k in ipairs({ "t2", "t3", "t4" }) do
            go.set(u[k], "skin_offset", ZERO_VEC4)
            go.set(u[k], "tint", ONE_VEC4)
        end
        local trail = ships_db.TRAILS[trail_id] or ships_db.TRAILS[1]
        go.set(u.trail, "tint", vmath.vector4(trail.color[1], trail.color[2], trail.color[3], 0.85))
    end
end

function M.set_ship_hit_flash(slot, flash_amount)
    if not slot or not slot.active_mesh then return end
    local f = 1.0 + flash_amount * 2.0
    go.set(slot.active_mesh, "tint", vmath.vector4(f, f, f, 1.0))
end

function M.set_ship_dome(slot, enabled, r, g, b, a)
    if not slot then return end
    msg.post(slot.urls.dome, enabled and "enable" or "disable")
    if enabled then
        go.set(slot.urls.dome, "tint", vmath.vector4(r or 0.25, g or 0.72, b or 1.0, a or 0.35))
    end
end

function M.acquire_laser()
    for i = 1, #pools.lasers do
        local p = pools.lasers[i]
        if not p.active then
            p.active = true
            msg.post(p.url, "enable")
            return p
        end
    end
    return nil
end

function M.release_laser(p)
    p.active = false
    msg.post(p.url, "disable")
    go.set_position(HIDE_POS, p.id)
end

function M.acquire_missile()
    for i = 1, #pools.missiles do
        local p = pools.missiles[i]
        if not p.active then
            p.active = true
            msg.post(p.url, "enable")
            return p
        end
    end
    return nil
end

function M.release_missile(p)
    p.active = false
    msg.post(p.url, "disable")
    go.set_position(HIDE_POS, p.id)
end

function M.spawn_vfx(pos, r, g, b, max_scale, duration)
    for i = 1, #pools.vfx do
        local v = pools.vfx[i]
        if not v.active then
            v.active = true
            v.timer = 0
            v.duration = duration or 0.45
            v.max_scale = max_scale or 6.5
            v.r, v.g, v.b = r or 1.0, g or 0.65, b or 0.2
            go.set_position(pos, v.id)
            go.set_scale(vmath.vector3(0.5, 0.5, 0.5), v.id)
            go.set(v.url, "tint", vmath.vector4(v.r, v.g, v.b, 0.9))
            msg.post(v.url, "enable")
            return v
        end
    end
    return nil
end

function M.update_vfx(dt)
    for i = 1, #pools.vfx do
        local v = pools.vfx[i]
        if v.active then
            v.timer = v.timer + dt
            local p = v.timer / v.duration
            if p >= 1.0 then
                v.active = false
                msg.post(v.url, "disable")
                go.set_position(HIDE_POS, v.id)
            else
                local s = 0.6 + v.max_scale * p
                go.set_scale(vmath.vector3(s, s, s), v.id)
                go.set(v.url, "tint", vmath.vector4(v.r, v.g, v.b, (1.0 - p) * 0.85))
            end
        end
    end
end

function M.get_asteroid_slot(i) return pools.asteroids[i] end
function M.get_beacon_slot(i) return pools.beacons[i] end
function M.get_dreadnought_slot(i) return pools.dreadnought[i] end

function M.hide_environment()
    for i = 1, #pools.asteroids do
        local a = pools.asteroids[i]
        for _, u in pairs(a.urls) do msg.post(u, "disable") end
        go.set_position(HIDE_POS, a.id)
    end
    for i = 1, #pools.beacons do
        local b = pools.beacons[i]
        msg.post(b.mesh, "disable")
        msg.post(b.zone, "disable")
        go.set_position(HIDE_POS, b.id)
    end
    for i = 1, #pools.dreadnought do
        local d = pools.dreadnought[i]
        for _, u in pairs(d.urls) do msg.post(u, "disable") end
        go.set_position(HIDE_POS, d.id)
    end
end

function M.hide_all()
    for i = 1, #pools.ships do
        M.configure_ship_visual(pools.ships[i], "interceptor", 1, 1, 1, false)
        go.set_position(HIDE_POS, pools.ships[i].id)
    end
    for i = 1, #pools.lasers do
        if pools.lasers[i].active then M.release_laser(pools.lasers[i]) end
    end
    for i = 1, #pools.missiles do
        if pools.missiles[i].active then M.release_missile(pools.missiles[i]) end
    end
    for i = 1, #pools.vfx do
        pools.vfx[i].active = false
        msg.post(pools.vfx[i].url, "disable")
        go.set_position(HIDE_POS, pools.vfx[i].id)
    end
    M.hide_environment()
end

return M
