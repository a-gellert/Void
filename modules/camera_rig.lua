-- Chase camera, death cam, hangar orbit, screen shake and world->GUI projection.
local math3d = require("modules.math3d")

local M = {}

local UP = vmath.vector3(0, 1, 0)
local GUI_W = 1920
local GUI_H = 1080

local cam_pos = vmath.vector3(0, 8, 22)
local cam_look = vmath.vector3(0, 0, -20)
local cam_forward = vmath.vector3(0, 0, -1)
local view_mtx = vmath.matrix4()
local proj_mtx = vmath.matrix4()
local vp_mtx = vmath.matrix4()
local current_fov = 65.0
local shake_trauma = 0.0
local hangar_angle = 0.4
local hangar_offset = vmath.vector3(0, 0, 0)
local hangar_offset_target = vmath.vector3(0, 0, 0)
local hangar_dist = 12.0
local hangar_dist_target = 12.0

function M.get_pos()
    return cam_pos
end

function M.get_forward()
    return cam_forward
end

function M.add_shake(amount)
    shake_trauma = math.min(1.0, shake_trauma + amount)
end

local function push_matrices(eye, look, fov)
    local win_w, win_h = window.get_size()
    local aspect = math.max(0.2, win_w / math.max(1, win_h))
    view_mtx = vmath.matrix4_look_at(eye, look, UP)
    proj_mtx = vmath.matrix4_perspective(math.rad(fov), aspect, 0.5, 1800)
    vp_mtx = proj_mtx * view_mtx
    msg.post("@render:", "set_space_camera", { view = view_mtx, projection = proj_mtx })
end

function M.reset(pos, forward)
    local p = pos or vmath.vector3(0, 0, 0)
    local f = forward or vmath.vector3(0, 0, -1)
    cam_pos = p - f * 17.5 + UP * 4.2
    cam_look = p + f * 35.0
    cam_forward = math3d.normalize_or_default(cam_look - cam_pos, f)
    current_fov = 65.0
    shake_trauma = 0.0
end

local function apply_shake(base, dt)
    local final_pos = vmath.vector3(base.x, base.y, base.z)
    if shake_trauma > 0.001 then
        local mag = shake_trauma * shake_trauma * 1.2
        final_pos.x = final_pos.x + (math.random() * 2 - 1) * mag
        final_pos.y = final_pos.y + (math.random() * 2 - 1) * mag
        shake_trauma = math.max(0.0, shake_trauma - dt * 2.4)
    end
    return final_pos
end

-- Mouse-aim chase cam: sits behind the ship along the AIM direction (not the nose),
-- so the screen centre is always where the player wants to fly and the ship
-- visibly swings towards it.
function M.update_battle(ship, aim_dir, dt)
    if not ship then return end
    local aim = aim_dir or ship.forward
    local spd_ratio = (ship.cur_speed or ship.speed) / math.max(1, ship.speed)
    local target_fov = 64.0 + math3d.clamp((spd_ratio - 1.0) * 14.0, -4.0, 16.0)
    if (ship.warp_flash or 0) > 0 then target_fov = 82.0 end
    current_fov = math3d.lerp(current_fov, target_fov, math.min(1.0, dt * 6.0))

    local aim_h = math3d.normalize_or_default(vmath.vector3(aim.x, aim.y * 0.6, aim.z), ship.forward)
    local back = 17.0 + math3d.clamp((spd_ratio - 1.0) * 3.0, -1.5, 3.5)
    local desired_pos = ship.pos - aim_h * back + UP * 4.6
    local desired_look = ship.pos + aim * 60.0 + UP * 2.0

    local follow_t = math.min(1.0, dt * 12.0)
    cam_pos.x = math3d.lerp(cam_pos.x, desired_pos.x, follow_t)
    cam_pos.y = math3d.lerp(cam_pos.y, desired_pos.y, follow_t)
    cam_pos.z = math3d.lerp(cam_pos.z, desired_pos.z, follow_t)
    local look_t = math.min(1.0, dt * 22.0)
    cam_look.x = math3d.lerp(cam_look.x, desired_look.x, look_t)
    cam_look.y = math3d.lerp(cam_look.y, desired_look.y, look_t)
    cam_look.z = math3d.lerp(cam_look.z, desired_look.z, look_t)
    cam_forward = math3d.normalize_or_default(cam_look - cam_pos, ship.forward)

    push_matrices(apply_shake(cam_pos, dt), cam_look, current_fov)
end

-- Death cam: drift back from the wreck and look at the killer (or the wreck).
function M.update_death(wreck_pos, focus_pos, dt)
    local focus = focus_pos or wreck_pos
    local dir = math3d.normalize_or_default(focus - wreck_pos, cam_forward)
    local desired_pos = wreck_pos - dir * 26.0 + UP * 9.0
    local t = math.min(1.0, dt * 2.5)
    cam_pos.x = math3d.lerp(cam_pos.x, desired_pos.x, t)
    cam_pos.y = math3d.lerp(cam_pos.y, desired_pos.y, t)
    cam_pos.z = math3d.lerp(cam_pos.z, desired_pos.z, t)
    cam_look.x = math3d.lerp(cam_look.x, focus.x, t)
    cam_look.y = math3d.lerp(cam_look.y, focus.y, t)
    cam_look.z = math3d.lerp(cam_look.z, focus.z, t)
    cam_forward = math3d.normalize_or_default(cam_look - cam_pos, cam_forward)
    current_fov = math3d.lerp(current_fov, 60.0, t)
    push_matrices(apply_shake(cam_pos, dt), cam_look, current_fov)
end

-- Hangar orbit. `offset` shifts the framing so side panels do not cover the ship.
function M.set_hangar_framing(offset_x, dist)
    hangar_offset_target.x = offset_x or 0
    hangar_dist_target = dist or 12.0
end

function M.update_hangar(target_pos, dt)
    hangar_angle = hangar_angle + dt * 0.38
    local t = math.min(1.0, dt * 4.0)
    hangar_offset.x = math3d.lerp(hangar_offset.x, hangar_offset_target.x, t)
    hangar_dist = math3d.lerp(hangar_dist, hangar_dist_target, t)
    local cx = target_pos.x + math.sin(hangar_angle) * hangar_dist
    local cy = target_pos.y + 3.2
    local cz = target_pos.z + math.cos(hangar_angle) * hangar_dist
    local eye = vmath.vector3(cx, cy, cz)
    local look = target_pos + vmath.vector3(0, -0.4, 0)
    -- Shift both eye and target along the camera's right vector for off-centre framing.
    local fwd = math3d.normalize_or_default(look - eye)
    local right = math3d.normalize_or_default(vmath.cross(fwd, UP), vmath.vector3(1, 0, 0))
    eye = eye - right * hangar_offset.x
    look = look - right * hangar_offset.x
    cam_pos = eye
    cam_forward = fwd
    push_matrices(eye, look, 52)
end

--- Point the reticle (screen centre) is looking at, `dist` metres from the camera.
function M.get_aim_point(dist)
    local d = math3d.normalize_or_default(cam_look - cam_pos, cam_forward)
    return cam_pos + d * dist
end

--- Project a world point to the 1920x1080 virtual GUI space.
function M.world_to_screen(wx, wy, wz)
    local clip = vp_mtx * vmath.vector4(wx, wy, wz, 1.0)
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
