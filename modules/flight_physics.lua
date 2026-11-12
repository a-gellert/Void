local math3d = require("modules.math3d")
local arenas_db = require("data.arenas_db")

local M = {}

local obstacles = {}

function M.set_obstacles(list)
    obstacles = list or {}
end

function M.get_obstacles()
    return obstacles
end

--- Compute shortest vector from a torus centerline circle to point (px, py, pz).
function M.torus_closest_offset(px, py, pz, obs)
    local dx = px - obs.x
    local dy = py - obs.y
    local dz = pz - obs.z
    local ax, ay, az = obs.ax or 0, obs.ay or 0, obs.az or 1
    local d_axial = dx * ax + dy * ay + dz * az
    local rx = dx - d_axial * ax
    local ry = dy - d_axial * ay
    local rz = dz - d_axial * az
    local rad_sq = rx * rx + ry * ry + rz * rz
    local major_r = obs.major_r
    local cx, cy, cz
    if rad_sq > 1e-8 then
        local inv_r = major_r / math.sqrt(rad_sq)
        cx, cy, cz = rx * inv_r, ry * inv_r, rz * inv_r
    elseif math.abs(ax) < 0.9 then
        local ly, lz = -az, ay
        local inv = major_r / math.sqrt(ly * ly + lz * lz)
        cx, cy, cz = 0, ly * inv, lz * inv
    else
        local lx, lz = az, -ax
        local inv = major_r / math.sqrt(lx * lx + lz * lz)
        cx, cy, cz = lx * inv, 0, lz * inv
    end
    local ox = dx - cx
    local oy = dy - cy
    local oz = dz - cz
    return ox, oy, oz, ox * ox + oy * oy + oz * oz
end

local function resolve_repulsion(ship, dx, dy, dz, d_sq, min_r)
    if d_sq >= min_r * min_r then return end
    local d = math.sqrt(d_sq)
    if d < 0.001 then
        dx, dy, dz, d = 0, 1, 0, 1
    end
    local nx, ny, nz = dx / d, dy / d, dz / d
    local push = min_r - d
    ship.pos.x = ship.pos.x + nx * push
    ship.pos.y = ship.pos.y + ny * push
    ship.pos.z = ship.pos.z + nz * push
    local dot_n = ship.forward.x * nx + ship.forward.y * ny + ship.forward.z * nz
    if dot_n < 0 then
        ship.forward = math3d.normalize_or_default(vmath.vector3(
            ship.forward.x - nx * dot_n * 1.1,
            ship.forward.y - ny * dot_n * 1.1,
            ship.forward.z - nz * dot_n * 1.1
        ))
    end
end

function M.update_ship(ship, aim_dir, dt)
    if not ship.alive then return end

    local target_dir = math3d.normalize_or_default(aim_dir, ship.forward)
    -- Clamp vertical pitch component to +/- 70 degrees so auto-horizon never flips upside down
    local max_pitch_y = 0.92
    if target_dir.y > max_pitch_y or target_dir.y < -max_pitch_y then
        target_dir = math3d.clamp_pitch(target_dir, max_pitch_y, ship.forward)
    end

    -- Compute lateral turn delta for crisp banking roll
    local right_x = -ship.forward.z
    local right_z = ship.forward.x
    local lateral = right_x * target_dir.x + right_z * target_dir.z
    local target_roll = math3d.clamp(-lateral * 1.15, -0.78, 0.78)
    ship.roll = math3d.lerp(ship.roll or 0, target_roll, math.min(1.0, dt * 7.5))

    -- Smoothly turn ship forward vector along the shortest arc (slerp-like),
    -- then enforce the pitch limit on the result as well: component-wise lerp
    -- near the pole could amplify |y| past the target limit, let the nose reach
    -- vertical and make the orientation basis flip/spin.
    local turn_alpha = math.min(1.0, ship.turn_rate * dt)
    ship.forward = math3d.rotate_towards(ship.forward, target_dir, turn_alpha)
    ship.forward = math3d.clamp_pitch(ship.forward, max_pitch_y, ship.forward)

    -- Compute speed (dash / microwarp / base)
    local spd = ship.speed
    if ship.dash_timer > 0 then
        spd = ship.boost_speed
    end

    ship.vel = ship.forward * spd
    ship.pos.x = ship.pos.x + ship.vel.x * dt
    ship.pos.y = ship.pos.y + ship.vel.y * dt
    ship.pos.z = ship.pos.z + ship.vel.z * dt

    -- Pure Lua sphere & torus asteroid/station repulsion (no Box2D/Bullet)
    local sr = ship.radius
    for i = 1, #obstacles do
        local obs = obstacles[i]
        if obs.kind == "torus" then
            local ox, oy, oz, d_sq = M.torus_closest_offset(ship.pos.x, ship.pos.y, ship.pos.z, obs)
            resolve_repulsion(ship, ox, oy, oz, d_sq, sr + obs.minor_r)
        else
            local dx = ship.pos.x - obs.x
            local dy = ship.pos.y - obs.y
            local dz = ship.pos.z - obs.z
            resolve_repulsion(ship, dx, dy, dz, dx * dx + dy * dy + dz * dz, sr + obs.r)
        end
    end

    -- Soft spherical arena boundary. Start turning the nose back inside a bit
    -- before the hard shell, otherwise a ship with neutral steering slides
    -- along it and ends up circling the arena forever.
    local max_r = arenas_db.ARENA_RADIUS
    local soft_r = max_r * 0.90
    local pos_sq = ship.pos.x * ship.pos.x + ship.pos.y * ship.pos.y + ship.pos.z * ship.pos.z
    if pos_sq > soft_r * soft_r then
        local d = math.sqrt(pos_sq)
        local inv = 1.0 / d
        local nx, ny, nz = ship.pos.x * inv, ship.pos.y * inv, ship.pos.z * inv
        local t = math3d.clamp((d - soft_r) / (max_r - soft_r), 0.0, 1.0)
        local pull = 4.0 * t
        ship.forward = math3d.rotate_towards(
            ship.forward,
            math3d.normalize_or_default(vmath.vector3(
                ship.forward.x - nx * pull,
                ship.forward.y - ny * pull,
                ship.forward.z - nz * pull
            ), ship.forward),
            math.min(1.0, dt * 14.0)
        )

        if d > max_r then
            local scale = max_r * inv
            ship.pos.x = ship.pos.x * scale
            ship.pos.y = ship.pos.y * scale
            ship.pos.z = ship.pos.z * scale
            -- Hard fallback: never keep the nose pointing outside the shell.
            local dot_n = ship.forward.x * nx + ship.forward.y * ny + ship.forward.z * nz
            if dot_n > 0 then
                local tx = ship.forward.x - nx * dot_n
                local ty = ship.forward.y - ny * dot_n
                local tz = ship.forward.z - nz * dot_n
                local t_sq = tx * tx + ty * ty + tz * tz
                if t_sq > 1e-6 then
                    ship.forward = math3d.normalize_or_default(vmath.vector3(tx, ty, tz), ship.forward)
                else
                    ship.forward = vmath.vector3(-nx, -ny, -nz)
                end
            end
        end
    end

    -- Repulsion or the boundary turn may have nudged the pitch; keep the
    -- auto-horizon basis away from the pole.
    ship.forward = math3d.clamp_pitch(ship.forward, max_pitch_y, ship.forward)

    ship.rot = math3d.quat_from_forward(ship.forward, ship.roll)
end

return M
