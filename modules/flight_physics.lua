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

function M.update_ship(ship, aim_dir, dt)
    if not ship.alive then return end

    local target_dir = math3d.normalize_or_default(aim_dir, ship.forward)
    -- Clamp vertical pitch component to +/- 70 degrees so auto-horizon never flips upside down
    local max_pitch_y = 0.92
    if target_dir.y > max_pitch_y or target_dir.y < -max_pitch_y then
        target_dir.y = math3d.clamp(target_dir.y, -max_pitch_y, max_pitch_y)
        target_dir = math3d.normalize_or_default(target_dir)
    end

    -- Compute lateral turn delta for crisp banking roll
    local right_x = -ship.forward.z
    local right_z = ship.forward.x
    local lateral = right_x * target_dir.x + right_z * target_dir.z
    local target_roll = math3d.clamp(-lateral * 1.15, -0.78, 0.78)
    ship.roll = math3d.lerp(ship.roll or 0, target_roll, math.min(1.0, dt * 7.5))

    -- Smoothly turn ship forward vector
    local turn_alpha = math.min(1.0, ship.turn_rate * dt)
    local new_fwd = vmath.vector3(
        math3d.lerp(ship.forward.x, target_dir.x, turn_alpha),
        math3d.lerp(ship.forward.y, target_dir.y, turn_alpha),
        math3d.lerp(ship.forward.z, target_dir.z, turn_alpha)
    )
    ship.forward = math3d.normalize_or_default(new_fwd, ship.forward)

    -- Compute speed (dash / microwarp / base)
    local spd = ship.speed
    if ship.dash_timer > 0 then
        spd = ship.boost_speed
    end

    ship.vel = ship.forward * spd
    ship.pos.x = ship.pos.x + ship.vel.x * dt
    ship.pos.y = ship.pos.y + ship.vel.y * dt
    ship.pos.z = ship.pos.z + ship.vel.z * dt

    -- Pure Lua sphere-vs-sphere asteroid & station repulsion (no Box2D/Bullet)
    local sr = ship.radius
    for i = 1, #obstacles do
        local obs = obstacles[i]
        local dx = ship.pos.x - obs.x
        local dy = ship.pos.y - obs.y
        local dz = ship.pos.z - obs.z
        local min_r = sr + obs.r
        local d_sq = dx * dx + dy * dy + dz * dz
        if d_sq < min_r * min_r then
            local d = math.sqrt(d_sq)
            if d < 0.001 then
                dx, dy, dz, d = 0, 1, 0, 1
            end
            local nx, ny, nz = dx / d, dy / d, dz / d
            local push = min_r - d
            ship.pos.x = ship.pos.x + nx * push
            ship.pos.y = ship.pos.y + ny * push
            ship.pos.z = ship.pos.z + nz * push
            -- Deflect forward vector slightly away from sphere surface
            local dot_n = ship.forward.x * nx + ship.forward.y * ny + ship.forward.z * nz
            if dot_n < 0 then
                ship.forward = math3d.normalize_or_default(vmath.vector3(
                    ship.forward.x - nx * dot_n * 1.1,
                    ship.forward.y - ny * dot_n * 1.1,
                    ship.forward.z - nz * dot_n * 1.1
                ))
            end
        end
    end

    -- Soft spherical arena boundary
    local max_r = arenas_db.ARENA_RADIUS
    local pos_sq = ship.pos.x * ship.pos.x + ship.pos.y * ship.pos.y + ship.pos.z * ship.pos.z
    if pos_sq > max_r * max_r then
        local d = math.sqrt(pos_sq)
        local scale = max_r / d
        ship.pos.x = ship.pos.x * scale
        ship.pos.y = ship.pos.y * scale
        ship.pos.z = ship.pos.z * scale
    end

    ship.rot = math3d.quat_from_forward(ship.forward, ship.roll)
end

return M
