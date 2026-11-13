-- Unified pilot input. The HUD gui_script writes it (mouse, keyboard, touch,
-- gamepad); main.script feeds it to match_controller and clears the one-shot
-- flags after every simulation step.
-- Steering:
--  * mouse: aim_dx / aim_dy accumulate the aim rotation (radians) since the last frame
--    (mouse-aim: the aim point lives in the world, the ship follows it);
--  * touch stick / gamepad: steer_x / steer_y (-1..1) rotate the aim at a rate.
local M = {
    aim_dx = 0,
    aim_dy = 0,
    -- Continuous axes (-1..1)
    steer_x = 0,
    steer_y = 0,
    strafe = 0,
    -- Held buttons
    fire = false,
    boost = false,
    brake = false,
    -- One-shot presses (cleared each frame)
    dash = false,
    missile = false,
    mod1 = false,
    mod2 = false,
    -- Last active device: "mouse", "touch", "gamepad"
    device = "mouse",
    any_input = false,
}

function M.clear_edges()
    M.aim_dx = 0
    M.aim_dy = 0
    M.dash = false
    M.missile = false
    M.mod1 = false
    M.mod2 = false
end

function M.reset()
    M.steer_x = 0
    M.steer_y = 0
    M.strafe = 0
    M.fire = false
    M.boost = false
    M.brake = false
    M.any_input = false
    M.clear_edges()
end

return M
