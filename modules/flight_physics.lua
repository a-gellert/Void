-- 3D arcade flight model (pure Lua, no physics engine).
--  * Player: mouse-aim. The ship turns towards a world-space aim direction (see
--    match_controller.update_aim). Auto-horizon keeps the ship upright (no manual roll).
--  * AI: steers towards a desired direction along the shortest arc.
--  * Shared: throttle (cruise / afterburner on energy / brake), lateral strafe,
--    evasive dash with barrel roll, obstacle push-out + bump events, soft arena shell.
local math3d = require("modules.math3d")
local arenas_db = require("data.arenas_db")
local modules_db = require("data.modules_db")

local M = {}

local UP = vmath.vector3(0, 1, 0)
local MAX_PITCH_Y = 0.92
local TWO_PI = math.pi * 2

local obstacles = {}

function M.set_obstacles(list)
    obstacles = list or {}
end

function M.get_obstacles()
    return obstacles
end

--- Shortest vector from a torus centreline circle to point (px, py, pz).
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

-- Push the ship out of an obstacle. Returns impact speed along the normal (0 if none).
local function resolve_repulsion(ship, dx, dy, dz, d_sq, min_r)
    if d_sq >= min_r * min_r then return 0 end
    local d = math.sqrt(d_sq)
    if d < 0.001 then
        dx, dy, dz, d = 0, 1, 0, 1
    end
    local nx, ny, nz = dx / d, dy / d, dz / d
    local push = min_r - d
    ship.pos.x = ship.pos.x + nx * push
    ship.pos.y = ship.pos.y + ny * push
    ship.pos.z = ship.pos.z + nz * push
    local impact = 0
    local v = ship.vel
    if v then
        impact = -(v.x * nx + v.y * ny + v.z * nz)
    end
    local dot_n = ship.forward.x * nx + ship.forward.y * ny + ship.forward.z * nz
    if dot_n < 0 then
        ship.forward = math3d.normalize_or_default(vmath.vector3(
            ship.forward.x - nx * dot_n * 1.1,
            ship.forward.y - ny * dot_n * 1.1,
            ship.forward.z - nz * dot_n * 1.1
        ), ship.forward)
    end
    return math.max(0, impact)
end

-- Throttle + energy. ctl = { boost = bool, brake = bool }
local function update_throttle(ship, ctl, dt)
    local ab = modules_db.AFTERBURNER
    local wants_boost = ctl.boost and (ship.max_energy or 0) > 0 and not ctl.brake
    if wants_boost and ship.energy > 0 and (ship.boosting or ship.energy >= ab.min_to_start) then
        if not ship.boosting then ship.boost_started = true end
        ship.boosting = true
        ship.energy = math.max(0, ship.energy - ab.drain * dt)
        ship.energy_delay = ab.regen_delay
    else
        ship.boosting = false
        if ship.energy_delay > 0 then
            ship.energy_delay = ship.energy_delay - dt
        elseif ship.energy < ship.max_energy then
            ship.energy = math.min(ship.max_energy, ship.energy + ab.regen * dt)
        end
    end
    ship.braking = ctl.brake and not ship.boosting

    local target = ship.speed
    if ship.dash_timer > 0 then
        target = ship.speed * modules_db.DASH.speed_mult
    elseif ship.boosting then
        target = ship.speed * ship.boost_mult
    elseif ship.braking then
        target = ship.speed * modules_db.BRAKE.speed_mult
    end
    if ship.speed_mult then target = target * ship.speed_mult end
    local cur = ship.cur_speed or ship.speed
    local rate = (target > cur) and ship.speed * 2.4 or ship.speed * 1.8
    if ship.dash_timer > 0 then rate = ship.speed * 8.0 end
    if target > cur then
        cur = math.min(target, cur + rate * dt)
    else
        cur = math.max(target, cur - rate * dt)
    end
    ship.cur_speed = cur
end

local function turn_mult(ship)
    if ship.braking then return modules_db.BRAKE.turn_mult end
    if ship.boosting then return modules_db.BOOST_TURN_MULT end
    return 1.0
end

-- Shared integration: strafe, position, obstacles, arena shell, orientation.
local function integrate(ship, strafe_in, bank, dt)
    -- Lateral strafe (horizontal right axis)
    local rx, rz = -ship.forward.z, ship.forward.x
    local rl = math.sqrt(rx * rx + rz * rz)
    if rl < 1e-4 then rx, rz, rl = 1, 0, 1 end
    rx, rz = rx / rl, rz / rl
    local target_strafe = (strafe_in or 0) * (ship.strafe_speed or 0)
    ship.strafe_vel = math3d.lerp(ship.strafe_vel or 0, target_strafe, math.min(1.0, dt * 6.0))

    local spd = ship.cur_speed or ship.speed
    local v = ship.vel
    v.x = ship.forward.x * spd + rx * ship.strafe_vel
    v.y = ship.forward.y * spd
    v.z = ship.forward.z * spd + rz * ship.strafe_vel
    ship.pos.x = ship.pos.x + v.x * dt
    ship.pos.y = ship.pos.y + v.y * dt
    ship.pos.z = ship.pos.z + v.z * dt

    -- Obstacles (spheres and tori)
    local sr = ship.radius
    local impact = 0
    for i = 1, #obstacles do
        local obs = obstacles[i]
        local imp
        if obs.kind == "torus" then
            local ox, oy, oz, d_sq = M.torus_closest_offset(ship.pos.x, ship.pos.y, ship.pos.z, obs)
            imp = resolve_repulsion(ship, ox, oy, oz, d_sq, sr + obs.minor_r)
        else
            local dx = ship.pos.x - obs.x
            local dy = ship.pos.y - obs.y
            local dz = ship.pos.z - obs.z
            imp = resolve_repulsion(ship, dx, dy, dz, dx * dx + dy * dy + dz * dz, sr + obs.r)
        end
        if imp > impact then impact = imp end
    end
    if impact > 0 then
        ship.bump_impact = math.max(ship.bump_impact or 0, impact)
    end

    -- Soft spherical arena boundary: turn the nose back in before the hard shell.
    local max_r = arenas_db.ARENA_RADIUS
    local soft_r = max_r * 0.90
    local pos_sq = ship.pos.x * ship.pos.x + ship.pos.y * ship.pos.y + ship.pos.z * ship.pos.z
    ship.near_boundary = pos_sq > soft_r * soft_r
    if ship.near_boundary then
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
            math.min(1.0, dt * 6.0 * t + dt * 2.0)
        )
        if d > max_r then
            local scale = max_r * inv
            ship.pos.x = ship.pos.x * scale
            ship.pos.y = ship.pos.y * scale
            ship.pos.z = ship.pos.z * scale
            local dot_n = ship.forward.x * nx + ship.forward.y * ny + ship.forward.z * nz
            if dot_n > 0 then
                local tx = ship.forward.x - nx * dot_n
                local ty = ship.forward.y - ny * dot_n
                local tz = ship.forward.z - nz * dot_n
                if tx * tx + ty * ty + tz * tz > 1e-6 then
                    ship.forward = math3d.normalize_or_default(vmath.vector3(tx, ty, tz), ship.forward)
                else
                    ship.forward = vmath.vector3(-nx, -ny, -nz)
                end
            end
        end
    end
    ship.forward = math3d.clamp_pitch(ship.forward, MAX_PITCH_Y, ship.forward)

    -- Visual roll: banking + strafe lean + evasive barrel roll.
    local strafe_lean = 0
    if ship.strafe_speed and ship.strafe_speed > 0 then
        strafe_lean = -(ship.strafe_vel / ship.strafe_speed) * 0.35
    end
    local target_roll = math3d.clamp(bank + strafe_lean, -0.95, 0.95)
    ship.roll = math3d.lerp(ship.roll or 0, target_roll, math.min(1.0, dt * 7.5))
    local roll = ship.roll
    if ship.dash_timer > 0 and ship.dash_duration and ship.dash_duration > 0 then
        local p = 1.0 - ship.dash_timer / ship.dash_duration
        roll = roll + (ship.dash_roll_sign or 1) * TWO_PI * (p * p * (3 - 2 * p))
    end
    ship.rot = math3d.quat_from_forward(ship.forward, roll)
end

--- Player mouse-aim flight: the ship turns towards the world-space aim direction.
--- Angular speed is proportional to the remaining angle (no overshoot), capped by the
--- hull turn rate and smoothed by agility, so the nose settles exactly on the aim.
function M.update_player_aim(ship, aim_dir, inp, dt)
    if not ship.alive then return end
    update_throttle(ship, inp, dt)
    local f = ship.forward
    local d = math3d.clamp(f.x * aim_dir.x + f.y * aim_dir.y + f.z * aim_dir.z, -1, 1)
    local angle = math.acos(d)
    local max_rate = ship.turn_rate * 0.8 * turn_mult(ship)
    local target_w = math.min(max_rate, angle * 5.0)
    ship.ang_vel = math3d.lerp(ship.ang_vel or 0, target_w, math.min(1.0, (ship.agility or 7) * 1.4 * dt))
    if angle > 1e-4 then
        local frac = math.min(1.0, ship.ang_vel * dt / angle)
        ship.forward = math3d.rotate_towards(f, aim_dir, frac)
    end
    ship.forward = math3d.clamp_pitch(ship.forward, MAX_PITCH_Y, ship.forward)
    local rx, rz = -ship.forward.z, ship.forward.x
    local lateral = rx * aim_dir.x + rz * aim_dir.z
    local bank = math3d.clamp(-lateral * 1.6, -0.9, 0.9)
    integrate(ship, inp.strafe, bank, dt)
end

--- AI flight towards a desired direction. ctl = { boost, brake, strafe }
function M.update_ai(ship, aim_dir, ctl, dt)
    if not ship.alive then return end
    update_throttle(ship, ctl, dt)
    local target_dir = math3d.normalize_or_default(aim_dir, ship.forward)
    if target_dir.y > MAX_PITCH_Y or target_dir.y < -MAX_PITCH_Y then
        target_dir = math3d.clamp_pitch(target_dir, MAX_PITCH_Y, ship.forward)
    end
    local rx, rz = -ship.forward.z, ship.forward.x
    local lateral = rx * target_dir.x + rz * target_dir.z
    local bank = math3d.clamp(-lateral * 1.15, -0.78, 0.78)
    local turn_alpha = math.min(1.0, ship.turn_rate * turn_mult(ship) * dt)
    ship.forward = math3d.rotate_towards(ship.forward, target_dir, turn_alpha)
    integrate(ship, ctl.strafe or 0, bank, dt)
end

--- Kinematic path follower (freighter). Moves along forward at cur_speed.
function M.update_scripted(ship, aim_dir, dt)
    if not ship.alive then return end
    ship.boosting = false
    ship.braking = false
    ship.cur_speed = ship.speed * (ship.speed_mult or 1)
    local turn_alpha = math.min(1.0, ship.turn_rate * dt)
    ship.forward = math3d.rotate_towards(ship.forward, math3d.normalize_or_default(aim_dir, ship.forward), turn_alpha)
    integrate(ship, 0, 0, dt)
end

return M
