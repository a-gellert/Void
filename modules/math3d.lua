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

-- Build orientation quaternion where ship forward (-Z) points along dir,
-- with auto-horizon up alignment and optional banking roll (radians).
function M.quat_from_forward(forward, roll_rad)
    local fwd = M.normalize_or_default(forward, vmath.vector3(0, 0, -1))
    -- Clamp pitch slightly away from exact +/-90 deg to keep auto-horizon stable
    local max_y = 0.94
    if fwd.y > max_y or fwd.y < -max_y then
        fwd.y = M.clamp(fwd.y, -max_y, max_y)
        fwd = M.normalize_or_default(fwd)
    end
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
