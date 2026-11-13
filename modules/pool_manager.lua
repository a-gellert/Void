local ships_db = require("data.ships_db")
local math3d = require("modules.math3d")

local M = {}

local HIDE_POS = vmath.vector3(0, -5000, 0)
local ZERO_VEC4 = vmath.vector4(0, 0, 0, 0)
local ONE_VEC4 = vmath.vector4(1, 1, 1, 1)
local TRAIL_NORMAL_STRETCH = vmath.vector4(1, 1, 1, 0)
local stretch_vec = vmath.vector4(1, 1, 1, 0)
local trail_tint_vec = vmath.vector4(1, 1, 1, 0.85)
local dust_scale = vmath.vector3(0.24, 0.24, 0.16)
local dust_tint = vmath.vector4(0.72, 0.88, 1.0, 0.42)
local dust_rot = vmath.quat()
local pickup_scale = vmath.vector3(1, 1, 1)
local pickup_tint = vmath.vector4(1, 1, 1, 1)
local last_dust_alpha = -1

local pools = {
    ships = {},
    lasers = {},
    missiles = {},
    vfx = {},
    asteroids = {},
    beacons = {},
    dreadnought = {},
    dust = {},
    pickups = {},
    rings = {},
}

M.SHIP_POOL = 20
M.LASER_POOL = 160
M.MISSILE_POOL = 40
M.VFX_POOL = 56
M.ASTEROID_POOL = 28
M.RING_POOL = 16

local PILOT_MESHES = { interceptor = true, fighter = true, frigate = true }
local ring_tint = vmath.vector4(1, 1, 1, 1)
local ring_scale = vmath.vector3(1, 1, 1)

local function set_comp_enabled(id, comp, enabled)
    msg.post(msg.url(nil, id, comp), enabled and "enable" or "disable")
end

function M.init()
    -- Ships (pilots, drones, freighter)
    for i = 1, M.SHIP_POOL do
        local id = factory.create("/factories#ship", HIDE_POS)
        local entry = {
            id = id,
            in_use = false,
            active_mesh = nil,
            urls = {
                interceptor = msg.url(nil, id, "mesh_interceptor"),
                fighter = msg.url(nil, id, "mesh_fighter"),
                frigate = msg.url(nil, id, "mesh_frigate"),
                drone = msg.url(nil, id, "mesh_drone"),
                freighter = msg.url(nil, id, "mesh_freighter"),
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

    -- Laser pulses
    for i = 1, M.LASER_POOL do
        local id = factory.create("/factories#projectile", HIDE_POS)
        set_comp_enabled(id, "laser", false)
        set_comp_enabled(id, "missile", false)
        pools.lasers[i] = {
            id = id,
            url = msg.url(nil, id, "laser"),
            active = false,
        }
    end

    -- Missiles
    for i = 1, M.MISSILE_POOL do
        local id = factory.create("/factories#projectile", HIDE_POS)
        set_comp_enabled(id, "laser", false)
        set_comp_enabled(id, "missile", false)
        pools.missiles[i] = {
            id = id,
            url = msg.url(nil, id, "missile"),
            active = false,
        }
    end

    -- VFX spheres
    for i = 1, M.VFX_POOL do
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

    -- Asteroid / Station slots
    for i = 1, M.ASTEROID_POOL do
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
                dome = msg.url(nil, id, "dome"),
            },
        }
        for _, u in pairs(entry.urls) do
            msg.post(u, "disable")
        end
        pools.dreadnought[i] = entry
    end

    -- 32 3D Speed Dust particles around camera
    for i = 1, 32 do
        local id = factory.create("/factories#dust", HIDE_POS)
        local url = msg.url(nil, id, "speck")
        msg.post(url, "disable")
        pools.dust[i] = {
            id = id,
            url = url,
            pos = vmath.vector3(0, -5000, 0),
        }
    end

    -- 3 Arena Pickup Spheres
    for i = 1, 3 do
        local id = factory.create("/factories#pickup", HIDE_POS)
        local entry = {
            id = id,
            core = msg.url(nil, id, "core"),
            aura = msg.url(nil, id, "aura"),
            r = 0.28, g = 0.95, b = 0.55,
        }
        msg.post(entry.core, "disable")
        msg.post(entry.aura, "disable")
        pools.pickups[i] = entry
    end

    -- Ring gates (race / tutorial)
    for i = 1, M.RING_POOL do
        local id = factory.create("/factories#ring", HIDE_POS)
        local url = msg.url(nil, id, "mesh")
        msg.post(url, "disable")
        pools.rings[i] = { id = id, url = url, visible = false }
    end
end

function M.get_ring_slot(i) return pools.rings[i] end

function M.show_ring(slot, pos, dir, r, g, b, a, scale)
    if not slot then return end
    if not slot.visible then
        msg.post(slot.url, "enable")
        slot.visible = true
    end
    go.set_position(pos, slot.id)
    go.set_rotation(vmath.quat_from_to(vmath.vector3(0, 1, 0), dir), slot.id)
    local s = scale or 1
    ring_scale.x, ring_scale.y, ring_scale.z = s, s, s
    go.set_scale(ring_scale, slot.id)
    ring_tint.x, ring_tint.y, ring_tint.z, ring_tint.w = r, g, b, a
    go.set(slot.url, "tint", ring_tint)
end

function M.hide_ring(slot)
    if not slot or not slot.visible then return end
    msg.post(slot.url, "disable")
    slot.visible = false
    go.set_position(HIDE_POS, slot.id)
end

function M.set_dust_color(r, g, b)
    dust_tint.x, dust_tint.y, dust_tint.z = r, g, b
    last_dust_alpha = -1
end

function M.get_ship_slot(index)
    return pools.ships[index]
end

-- mesh: "interceptor" | "fighter" | "frigate" | "drone" | "freighter"
function M.configure_ship_visual(slot, mesh, tier, skin_id, trail_id, visible)
    if not slot then return end
    local u = slot.urls
    for _, key in ipairs({ "interceptor", "fighter", "frigate", "drone", "freighter" }) do
        msg.post(u[key], (visible and mesh == key) and "enable" or "disable")
    end
    local pilot = PILOT_MESHES[mesh] and visible
    msg.post(u.t2, (pilot and tier >= 2) and "enable" or "disable")
    msg.post(u.t3, (pilot and tier >= 3) and "enable" or "disable")
    msg.post(u.t4, (pilot and tier >= 4) and "enable" or "disable")
    msg.post(u.t5, (pilot and tier >= 5) and "enable" or "disable")
    msg.post(u.trail, (visible and mesh ~= "freighter") and "enable" or "disable")
    msg.post(u.dome, "disable")
    slot.cloak = 0
    slot.trail_scale = (mesh == "drone") and 0.6 or 1.0

    slot.active_mesh = u[mesh]
    if visible and slot.active_mesh then
        if PILOT_MESHES[mesh] then
            local skin = ships_db.SKINS[skin_id] or ships_db.SKINS[1]
            go.set(slot.active_mesh, "skin_offset", vmath.vector4(skin.u_offset, skin.v_offset, 0, 0))
        else
            go.set(slot.active_mesh, "skin_offset", ZERO_VEC4)
        end
        go.set(slot.active_mesh, "tint", ONE_VEC4)
        for _, k in ipairs({ "t2", "t3", "t4" }) do
            go.set(u[k], "skin_offset", ZERO_VEC4)
            go.set(u[k], "tint", ONE_VEC4)
        end
        local trail = ships_db.TRAILS[trail_id] or ships_db.TRAILS[1]
        slot.trail_color = { trail.color[1], trail.color[2], trail.color[3] }
        slot.last_dash_factor = 0
        go.set(u.trail, "tint", vmath.vector4(trail.color[1], trail.color[2], trail.color[3], 0.85))
        go.set(u.trail, "stretch", TRAIL_NORMAL_STRETCH)
    end
end

function M.set_ship_trail_dash(slot, dash_factor)
    if not slot then return end
    local df = math3d.clamp(dash_factor or 0, 0, 1)
    if math.abs(df - (slot.last_dash_factor or 0)) < 0.005 then return end
    slot.last_dash_factor = df
    local base = slot.trail_scale or 1.0
    local z_scale = (1.0 + 1.8 * df) * base
    local xy_scale = (1.0 + 0.4 * df) * base
    local z_offset = 2.25 * (z_scale - 1.0)
    stretch_vec.x, stretch_vec.y, stretch_vec.z, stretch_vec.w = xy_scale, xy_scale, z_scale, z_offset
    go.set(slot.urls.trail, "stretch", stretch_vec)
    local c = slot.trail_color or { 1, 1, 1 }
    local boost = 1.0 + 0.45 * df
    trail_tint_vec.x = c[1] * boost
    trail_tint_vec.y = c[2] * boost
    trail_tint_vec.z = c[3] * boost
    trail_tint_vec.w = (0.85 + 0.15 * df) * (1.0 - 0.9 * (slot.cloak or 0))
    go.set(slot.urls.trail, "tint", trail_tint_vec)
end

local flash_vec = vmath.vector4(1, 1, 1, 1)
function M.set_ship_hit_flash(slot, flash_amount)
    if not slot or not slot.active_mesh then return end
    local f = 1.0 + flash_amount * 2.0
    local c = 1.0 - 0.82 * (slot.cloak or 0)
    flash_vec.x, flash_vec.y, flash_vec.z, flash_vec.w = f * c, f * c, f * c * (1 + 0.3 * (slot.cloak or 0)), 1.0
    go.set(slot.active_mesh, "tint", flash_vec)
end

-- Cloak amount 0..1 darkens the hull and fades the trail (enemies cannot lock it).
function M.set_ship_cloak(slot, amount)
    if not slot then return end
    local a = math3d.clamp(amount or 0, 0, 1)
    if math.abs(a - (slot.cloak or 0)) < 0.01 then return end
    slot.cloak = a
    slot.last_dash_factor = -1
    M.set_ship_hit_flash(slot, 0)
    M.set_ship_trail_dash(slot, 0)
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
function M.get_pickup_slot(i) return pools.pickups[i] end

function M.configure_pickup_visual(slot, kind, active)
    if not slot then return end
    msg.post(slot.core, active and "enable" or "disable")
    msg.post(slot.aura, active and "enable" or "disable")
    if active then
        if kind == "repair" then
            slot.r, slot.g, slot.b = 0.28, 0.95, 0.55
        else
            slot.r, slot.g, slot.b = 0.15, 0.88, 1.0
        end
        pickup_tint.x, pickup_tint.y, pickup_tint.z, pickup_tint.w = slot.r, slot.g, slot.b, 0.95
        go.set(slot.core, "tint", pickup_tint)
        pickup_tint.w = 0.22
        go.set(slot.aura, "tint", pickup_tint)
    else
        go.set_position(HIDE_POS, slot.id)
    end
end

function M.update_pickup_visual(slot, pulse)
    if not slot then return end
    local sc = 0.92 + 0.14 * pulse
    pickup_scale.x, pickup_scale.y, pickup_scale.z = sc, sc, sc
    go.set_scale(pickup_scale, slot.id)
    pickup_tint.x, pickup_tint.y, pickup_tint.z, pickup_tint.w = slot.r, slot.g, slot.b, 0.16 + 0.12 * pulse
    go.set(slot.aura, "tint", pickup_tint)
end

local function compute_dust_basis(cam_fwd)
    local fx, fy, fz = cam_fwd.x, cam_fwd.y, cam_fwd.z
    local len_sq = fx * fx + fy * fy + fz * fz
    if len_sq < 1e-8 then
        fx, fy, fz = 0, 0, -1
    else
        local inv = 1.0 / math.sqrt(len_sq)
        fx, fy, fz = fx * inv, fy * inv, fz * inv
    end
    -- Clamp pitch for stable horizon basis
    if fy > 0.94 or fy < -0.94 then
        fy = math3d.clamp(fy, -0.94, 0.94)
        local inv = 1.0 / math.sqrt(fx * fx + fy * fy + fz * fz)
        fx, fy, fz = fx * inv, fy * inv, fz * inv
    end
    local zx, zy, zz = -fx, -fy, -fz
    local xz_sq = fx * fx + fz * fz
    local xx, xy, xz = 1, 0, 0
    if xz_sq > 1e-8 then
        local inv_x = 1.0 / math.sqrt(xz_sq)
        xx, xz = -fz * inv_x, fx * inv_x
    end
    local yx = zy * xz
    local yy = zz * xx - zx * xz
    local yz = -zy * xx

    local trace = xx + yy + zz
    if trace > 0 then
        local s = math.sqrt(trace + 1.0) * 2.0
        dust_rot.w = 0.25 * s
        dust_rot.x = (yz - zy) / s
        dust_rot.y = (zx - xz) / s
        dust_rot.z = (xy - yx) / s
    elseif xx > yy and xx > zz then
        local s = math.sqrt(1.0 + xx - yy - zz) * 2.0
        dust_rot.w = (yz - zy) / s
        dust_rot.x = 0.25 * s
        dust_rot.y = (yx + xy) / s
        dust_rot.z = (zx + xz) / s
    elseif yy > zz then
        local s = math.sqrt(1.0 + yy - xx - zz) * 2.0
        dust_rot.w = (zx - xz) / s
        dust_rot.x = (yx + xy) / s
        dust_rot.y = 0.25 * s
        dust_rot.z = (zy + yz) / s
    else
        local s = math.sqrt(1.0 + zz - xx - yy) * 2.0
        dust_rot.w = (xy - yx) / s
        dust_rot.x = (zx + xz) / s
        dust_rot.y = (zy + yz) / s
        dust_rot.z = 0.25 * s
    end
    -- Right is -x_axis (since fwd = -z_axis), Up is y_axis
    return fx, fy, fz, -xx, -xy, -xz, yx, yy, yz
end

local function respawn_dust_speck(d, cam_pos, fx, fy, fz, rx, ry, rz, ux, uy, uz, min_along, max_along)
    local along = min_along + math.random() * (max_along - min_along)
    local rad = 6.0 + math.random() * 36.0
    local ang = math.random() * math.pi * 2.0
    local ox = math.cos(ang) * rad
    local oy = math.sin(ang) * rad
    d.pos.x = cam_pos.x + fx * along + rx * ox + ux * oy
    d.pos.y = cam_pos.y + fy * along + ry * ox + uy * oy
    d.pos.z = cam_pos.z + fz * along + rz * ox + uz * oy
    go.set_position(d.pos, d.id)
end

function M.init_dust(cam_pos, cam_fwd)
    local fx, fy, fz, rx, ry, rz, ux, uy, uz = compute_dust_basis(cam_fwd)
    dust_tint.w = 0.42
    last_dust_alpha = 0.42
    dust_scale.x, dust_scale.y, dust_scale.z = 0.24, 0.24, 0.16
    for i = 1, #pools.dust do
        local d = pools.dust[i]
        msg.post(d.url, "enable")
        go.set(d.url, "tint", dust_tint)
        go.set_rotation(dust_rot, d.id)
        go.set_scale(dust_scale, d.id)
        respawn_dust_speck(d, cam_pos, fx, fy, fz, rx, ry, rz, ux, uy, uz, 2.0, 72.0)
    end
end

function M.update_dust(cam_pos, cam_fwd, speed_ratio, dash_factor)
    local fx, fy, fz, rx, ry, rz, ux, uy, uz = compute_dust_basis(cam_fwd)
    local df = math3d.clamp(dash_factor or 0, 0, 1)
    local sr = math3d.clamp(speed_ratio or 0, 0, 1)
    dust_scale.x = 0.24 - 0.05 * df
    dust_scale.y = dust_scale.x
    dust_scale.z = 0.14 + 0.16 * sr + 1.15 * df
    local alpha = 0.36 + 0.44 * df
    local update_tint = math.abs(alpha - last_dust_alpha) > 0.02
    if update_tint then
        dust_tint.w = alpha
        last_dust_alpha = alpha
    end
    for i = 1, #pools.dust do
        local d = pools.dust[i]
        local dx = d.pos.x - cam_pos.x
        local dy = d.pos.y - cam_pos.y
        local dz = d.pos.z - cam_pos.z
        local along = dx * fx + dy * fy + dz * fz
        local dist_sq = dx * dx + dy * dy + dz * dz
        local lat_sq = dist_sq - along * along
        if along < -4.0 or along > 74.0 or lat_sq > 52.0 * 52.0 then
            respawn_dust_speck(d, cam_pos, fx, fy, fz, rx, ry, rz, ux, uy, uz, 44.0, 72.0)
        end
        go.set_rotation(dust_rot, d.id)
        go.set_scale(dust_scale, d.id)
        if update_tint then
            go.set(d.url, "tint", dust_tint)
        end
    end
end

function M.hide_environment()
    local id_rot = vmath.quat()
    for i = 1, #pools.asteroids do
        local a = pools.asteroids[i]
        for _, u in pairs(a.urls) do msg.post(u, "disable") end
        go.set_position(HIDE_POS, a.id)
        go.set_rotation(id_rot, a.id)
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
        go.set_rotation(id_rot, d.id)
    end
    for i = 1, #pools.pickups do
        local pk = pools.pickups[i]
        msg.post(pk.core, "disable")
        msg.post(pk.aura, "disable")
        go.set_position(HIDE_POS, pk.id)
    end
    for i = 1, #pools.rings do
        local r = pools.rings[i]
        msg.post(r.url, "disable")
        r.visible = false
        go.set_position(HIDE_POS, r.id)
    end
end

function M.hide_ship(slot)
    if not slot then return end
    M.configure_ship_visual(slot, "interceptor", 1, 1, 1, false)
    go.set_position(HIDE_POS, slot.id)
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
    for i = 1, #pools.dust do
        msg.post(pools.dust[i].url, "disable")
        go.set_position(HIDE_POS, pools.dust[i].id)
    end
    M.hide_environment()
end

return M
