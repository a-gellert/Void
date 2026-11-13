local M = {}

local UP = vmath.vector3(0, 1, 0)

function M.clamp(v, mn, mx)
    if v < mn then return mn end
    if v > mx then return mx end
    return v
end

function M.lerp(a, b, t)
    return a + (b - a) * t
end

function M.dist_sq(ax, ay, az, bx, by, bz)
    local dx = ax - bx
    local dy = ay - by
    local dz = az - bz
    return dx * dx + dy * dy + dz * dz
end

function M.vec_dist_sq(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

function M.normalize_or_default(v, fallback)
    local len_sq = v.x * v.x + v.y * v.y + v.z * v.z
    if len_sq < 1e-8 then
        return fallback or vmath.vector3(0, 0, -1)
    end
    local inv = 1.0 / math.sqrt(len_sq)
    return vmath.vector3(v.x * inv, v.y * inv, v.z * inv)
end

-- Rotate `current` towards `target` by a fraction (0..1) of the angle between
-- them along the shortest arc. Unlike component-wise lerp + normalize this
-- cannot creep through the pole (which made the auto-horizon basis flip and
-- the ship appear to spin around its own axis) and it handles a 180-degree
-- turn instead of stalling.
function M.rotate_towards(current, target, fraction)
    local c = M.normalize_or_default(current)
    local t = M.normalize_or_default(target, c)
    local d = M.clamp(c.x * t.x + c.y * t.y + c.z * t.z, -1.0, 1.0)
    if d > 0.999999 then
        return t
    end
    local ax, ay, az
    if d < -0.999999 then
        -- Opposite directions: any perpendicular axis gives a valid arc.
        if math.abs(c.y) < 0.9 then
            ax, ay, az = -c.z, 0.0, c.x
        else
            ax, ay, az = 0.0, c.z, -c.y
        end
    else
        ax = c.y * t.z - c.z * t.y
        ay = c.z * t.x - c.x * t.z
        az = c.x * t.y - c.y * t.x
    end
    local al = math.sqrt(ax * ax + ay * ay + az * az)
    if al < 1e-6 then
        return c
    end
    local inv = 1.0 / al
    ax, ay, az = ax * inv, ay * inv, az * inv
    local angle = math.acos(d) * M.clamp(fraction, 0.0, 1.0)
    local cs, sn = math.cos(angle), math.sin(angle)
    -- Rodrigues rotation of c around the axis (axis is perpendicular to c).
    local kx = ay * c.z - az * c.y
    local ky = az * c.x - ax * c.z
    local kz = ax * c.y - ay * c.x
    return M.normalize_or_default(vmath.vector3(
        c.x * cs + kx * sn,
        c.y * cs + ky * sn,
        c.z * cs + kz * sn
    ), c)
end

-- Rodrigues rotation of vector v around the unit axis (ax, ay, az) by `angle` radians.
function M.rotate_about(v, ax, ay, az, angle)
    local c, s = math.cos(angle), math.sin(angle)
    local dot = v.x * ax + v.y * ay + v.z * az
    local cx = ay * v.z - az * v.y
    local cy = az * v.x - ax * v.z
    local cz = ax * v.y - ay * v.x
    return vmath.vector3(
        v.x * c + cx * s + ax * dot * (1 - c),
        v.y * c + cy * s + ay * dot * (1 - c),
        v.z * c + cz * s + az * dot * (1 - c)
    )
end

-- Clamp a direction's vertical component to +/- max_y while preserving its
-- horizontal heading and unit length. A plain clamp followed by normalize does
-- not work: for an almost vertical vector normalization scales the clamped Y
-- component straight back above the limit, which lets the ship pass through the
-- pole and makes the auto-horizon basis flip (the ship appears to spin/flip).
function M.clamp_pitch(dir, max_y, fallback)
    local mx = max_y or 0.92
    local y = M.clamp(dir.y, -mx, mx)
    local h_sq = dir.x * dir.x + dir.z * dir.z
    local h
    if h_sq < 1e-10 then
        -- Vertical input: keep a stable heading from the fallback direction.
        local fb = fallback
        local fx, fz = 0, -1
        if fb then
            fx, fz = fb.x, fb.z
        end
        local fl = math.sqrt(fx * fx + fz * fz)
        if fl < 1e-6 then
            fx, fz, fl = 0, -1, 1
        end
        h = math.sqrt(math.max(0, 1 - y * y))
        return vmath.vector3((fx / fl) * h, y, (fz / fl) * h)
    end
    h = math.sqrt(math.max(0, 1 - y * y) / h_sq)
    return vmath.vector3(dir.x * h, y, dir.z * h)
end

-- Build orientation quaternion where ship forward (-Z) points along dir,
-- with auto-horizon up alignment and optional banking roll (radians).
function M.quat_from_forward(forward, roll_rad)
    local fwd = M.normalize_or_default(forward, vmath.vector3(0, 0, -1))
    -- Clamp pitch slightly away from exact +/-90 deg to keep auto-horizon stable
    fwd = M.clamp_pitch(fwd, 0.94)
    -- Forward is -Z in local ship space, so local +Z is -fwd
    local z_axis = -fwd
    local x_axis = M.normalize_or_default(vmath.cross(UP, z_axis), vmath.vector3(1, 0, 0))
    local y_axis = vmath.cross(z_axis, x_axis)

    local m = vmath.matrix4()
    m.m00, m.m10, m.m20 = x_axis.x, x_axis.y, x_axis.z
    m.m01, m.m11, m.m21 = y_axis.x, y_axis.y, y_axis.z
    m.m02, m.m12, m.m22 = z_axis.x, z_axis.y, z_axis.z

    local q = vmath.quat_matrix4(m)
    if roll_rad and math.abs(roll_rad) > 0.0001 then
        q = q * vmath.quat_rotation_z(roll_rad)
    end
    return q
end

-- Compute intercept point for Soft Lock-On lead aiming
function M.compute_lead_point(shooter_pos, target_pos, target_vel, proj_speed)
    local dx = target_pos.x - shooter_pos.x
    local dy = target_pos.y - shooter_pos.y
    local dz = target_pos.z - shooter_pos.z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    local t = dist / math.max(1.0, proj_speed)
    if t > 1.5 then t = 1.5 end
    return vmath.vector3(
        target_pos.x + (target_vel.x or 0) * t,
        target_pos.y + (target_vel.y or 0) * t,
        target_pos.z + (target_vel.z or 0) * t
    )
end

return M
