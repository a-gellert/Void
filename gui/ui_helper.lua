local audio = require("modules.audio")

local M = {}

M.TEX = "ui"
M.FONT = "main"

M.C_BG      = vmath.vector4(0.05, 0.08, 0.14, 0.88)
M.C_BG2     = vmath.vector4(0.03, 0.05, 0.09, 0.94)
M.C_CARD    = vmath.vector4(0.11, 0.16, 0.24, 0.92)
M.C_ELEV    = vmath.vector4(0.17, 0.24, 0.35, 0.96)
M.C_AQUA    = vmath.vector4(0.15, 0.78, 0.85, 1.0)
M.C_CORAL   = vmath.vector4(0.96, 0.36, 0.48, 1.0)
M.C_AMBER   = vmath.vector4(0.96, 0.65, 0.14, 1.0)
M.C_GREEN   = vmath.vector4(0.28, 0.90, 0.55, 1.0)
M.C_GOLD    = vmath.vector4(0.98, 0.75, 0.20, 1.0)
M.C_WHITE   = vmath.vector4(1.0, 1.0, 1.0, 1.0)
M.C_DIM     = vmath.vector4(0.60, 0.68, 0.80, 1.0)
M.C_DARK    = vmath.vector4(0.30, 0.36, 0.46, 1.0)
M.C_SHIELD  = vmath.vector4(0.45, 0.80, 1.0, 1.0)
M.C_ENERGY  = vmath.vector4(0.98, 0.80, 0.30, 1.0)
M.C_PURPLE  = vmath.vector4(0.72, 0.45, 1.0, 1.0)

M.NAMED = {
    gold = M.C_GOLD, aqua = M.C_AQUA, coral = M.C_CORAL, green = M.C_GREEN,
    amber = M.C_AMBER, white = M.C_WHITE, purple = M.C_PURPLE,
}

function M.box(parent, x, y, w, h, color, sprite)
    local n = gui.new_box_node(vmath.vector3(x, y, 0), vmath.vector3(w, h, 0))
    gui.set_texture(n, M.TEX)
    gui.play_flipbook(n, sprite or "white")
    gui.set_color(n, color or M.C_WHITE)
    if sprite == "panel_rounded" then
        gui.set_slice9(n, vmath.vector4(14, 14, 14, 14))
    end
    if parent then gui.set_parent(n, parent, false) end
    return n
end

function M.text(parent, x, y, str, scale, color, pivot)
    local n = gui.new_text_node(vmath.vector3(x, y, 0), str or "")
    gui.set_font(n, M.FONT)
    gui.set_color(n, color or M.C_WHITE)
    local s = scale or 0.65
    gui.set_scale(n, vmath.vector3(s, s, 1))
    gui.set_pivot(n, pivot or gui.PIVOT_CENTER)
    gui.set_outline(n, vmath.vector4(0.03, 0.05, 0.09, 0.9))
    if parent then gui.set_parent(n, parent, false) end
    return n
end

-- Multi-line text that wraps inside `width` (virtual px at scale 1).
function M.para(parent, x, y, str, scale, color, width, pivot)
    local n = M.text(parent, x, y, str, scale, color, pivot or gui.PIVOT_NW)
    gui.set_line_break(n, true)
    gui.set_size(n, vmath.vector3(width / (scale or 0.65), 400, 0))
    return n
end

function M.button(druid_inst, parent, x, y, w, h, label_str, bg_color, sprite, on_click, text_scale)
    local node = M.box(parent, x, y, w, h, bg_color or M.C_ELEV, sprite or "panel_rounded")
    local lbl = M.text(node, 0, 0, label_str, text_scale or 0.58, M.C_WHITE, gui.PIVOT_CENTER)
    local btn = druid_inst:new_button(node, function()
        audio.play("ui_click", 0.5)
        if on_click then on_click() end
    end)
    return btn, node, lbl
end

-- Horizontal bar: returns holder, fill (fill scales on X from the left edge).
-- Background and fill are siblings under a transparent holder: a fill parented to
-- its background rendered underneath it (dim bars), siblings draw in order.
function M.bar(parent, x, y, w, h, color, bg_color)
    local holder = M.box(parent, x, y, 1, 1, vmath.vector4(0, 0, 0, 0))
    M.box(holder, 0, 0, w, h, bg_color or M.C_CARD)
    local fill = M.box(holder, -w * 0.5, 0, w, h, color or M.C_AQUA)
    gui.set_pivot(fill, gui.PIVOT_W)
    return holder, fill
end

local tmp_scale = vmath.vector3(1, 1, 1)
function M.set_bar(fill, pct)
    tmp_scale.x = math.max(0.001, math.min(1, pct or 0))
    tmp_scale.y = 1
    gui.set_scale(fill, tmp_scale)
end

local tmp_col = vmath.vector4()
function M.set_alpha_color(node, c, a)
    tmp_col.x, tmp_col.y, tmp_col.z, tmp_col.w = c.x, c.y, c.z, a
    gui.set_color(node, tmp_col)
end

return M
