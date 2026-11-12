local math3d = require("modules.math3d")

local M = {}

local UP = vmath.vector3(0, 1, 0)
local GUI_W = 1920
local GUI_H = 1080

local cam_pos = vmath.vector3(0, 8, 22)
local cam_look = vmath.vector3(0, 0, -20)
local view_mtx = vmath.matrix4()
local proj_mtx = vmath.matrix4()
local current_fov = 65.0
local shake_trauma = 0.0
local hangar_angle = 0.4

function M.add_shake(amount)
    shake_trauma = math.min(1.0, shake_trauma + amount)
end

function M.reset(pos, forward)
    local p = pos or vmath.vector3(0, 0, 0)
    local f = forward or vmath.vector3(0, 0, -1)
    cam_pos = p - f * 17.5 + UP * 4.2
    cam_look = p + f * 35.0
    current_fov = 65.0
    shake_trauma = 0.0
end

function M.update_battle(ship, steer_x, steer_y, dt)
    if not ship then return end
    local target_fov = (ship.dash_timer > 0 or ship.warp_flash > 0) and 78.0 or 65.0
    current_fov = math3d.lerp(current_fov, target_fov, math.min(1.0, dt * 8.0))

    -- Auto-horizon chase rig behind ship
    local horiz_fwd = math3d.normalize_or_default(vmath.vector3(ship.forward.x, ship.forward.y * 0.55, ship.forward.z))
    local right = math3d.normalize_or_default(vmath.cross(horiz_fwd, UP), vmath.vector3(1, 0, 0))
    local desired_pos = ship.pos - horiz_fwd * 17.0 + UP * 4.4 - right * (steer_x * 2.2)
    local desired_look = ship.pos + ship.forward * 42.0 + right * (steer_x * 6.0) + UP * (steer_y * 4.0)

    local follow_t = math.min(1.0, dt * 10.5)
    cam_pos.x = math3d.lerp(cam_pos.x, desired_pos.x, follow_t)
    cam_pos.y = math3d.lerp(cam_pos.y, desired_pos.y, follow_t)
    cam_pos.z = math3d.lerp(cam_pos.z, desired_pos.z, follow_t)

    cam_look.x = math3d.lerp(cam_look.x, desired_look.x, follow_t * 1.2)
    cam_look.y = math3d.lerp(cam_look.y, desired_look.y, follow_t * 1.2)
    cam_look.z = math3d.lerp(cam_look.z, desired_look.z, follow_t * 1.2)

    local final_pos = vmath.vector3(cam_pos.x, cam_pos.y, cam_pos.z)
    if shake_trauma > 0.001 then
        local mag = shake_trauma * shake_trauma * 1.15
        final_pos.x = final_pos.x + (math.random() * 2 - 1) * mag
        final_pos.y = final_pos.y + (math.random() * 2 - 1) * mag
        shake_trauma = math.max(0.0, shake_trauma - dt * 2.4)
    end

    local win_w, win_h = window.get_size()
    local aspect = math.max(0.2, win_w / math.max(1, win_h))
    view_mtx = vmath.matrix4_look_at(final_pos, cam_look, UP)
    proj_mtx = vmath.matrix4_perspective(math.rad(current_fov), aspect, 0.5, 1800)

    msg.post("@render:", "set_view_projection", { view = view_mtx, projection = proj_mtx })
end

function M.update_hangar(target_pos, dt)
    hangar_angle = hangar_angle + dt * 0.42
    local dist = 12.0
    local cx = target_pos.x + math.sin(hangar_angle) * dist
    local cy = target_pos.y + 3.4
    local cz = target_pos.z + math.cos(hangar_angle) * dist
    local win_w, win_h = window.get_size()
    local aspect = math.max(0.2, win_w / math.max(1, win_h))

    view_mtx = vmath.matrix4_look_at(vmath.vector3(cx, cy, cz), target_pos + vmath.vector3(0, -0.4, 0), UP)
    proj_mtx = vmath.matrix4_perspective(math.rad(55), aspect, 0.5, 1800)
    msg.post("@render:", "set_view_projection", { view = view_mtx, projection = proj_mtx })
end

function M.get_aim_ray(steer_x, steer_y)
    -- Convert normalized screen cursor (-1..1) into a world forward direction
    local fwd = math3d.normalize_or_default(cam_look - cam_pos)
    local right = math3d.normalize_or_default(vmath.cross(fwd, UP), vmath.vector3(1, 0, 0))
    local up = vmath.cross(right, fwd)
    return math3d.normalize_or_default(fwd + right * (steer_x * 0.55) + up * (steer_y * 0.42))
end

-- Project 3D world point to virtual GUI space (1920x1080)
function M.world_to_screen(wx, wy, wz)
    local vp = proj_mtx * view_mtx
    local clip = vp * vmath.vector4(wx, wy, wz, 1.0)
    local in_front = clip.w > 0.05
    local inv_w = 1.0 / math.max(0.05, math.abs(clip.w))
    local ndc_x = clip.x * inv_w
    local ndc_y = clip.y * inv_w
    if not in_front then
        ndc_x = -ndc_x
        ndc_y = -ndc_y
    end
    local sx = (ndc_x * 0.5 + 0.5) * GUI_W
    local sy = (ndc_y * 0.5 + 0.5) * GUI_H
    return sx, sy, in_front, ndc_x, ndc_y
end

return M
