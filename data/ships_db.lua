local M = {}

M.DAMAGE_MULT = {
    plasma = { shield = 1.25, hull = 0.80 },
    kinetic = { shield = 0.85, hull = 1.25 },
    railgun = { shield = 0.85, hull = 1.25 },
    missile = { shield = 0.85, hull = 1.25 },
}

M.UPGRADE_COSTS = {
    credits = { 0, 150, 350, 700, 1250 },
    parts = { 0, 0, 3, 6, 10 },
}

M.CRAFT_COSTS = {
    random = 2,
    trail = 3,
    skin = 4,
}

M.CLASSES = {
    interceptor = {
        id = "interceptor",
        order = 1,
        model = "ship_interceptor",
        radius = 3.2,
        speed = 68,
        boost_speed = 118,
        turn_rate = 3.6,
        shield = 60,
        hull = 90,
        weapon_type = "plasma",
        weapon_damage = 11,
        weapon_rate = 7.8, -- shots/sec
        weapon_range = 165,
        proj_speed = 245,
        proj_color = { 0.0, 0.90, 1.0 },
        muzzle_offsets = { { -1.4, -0.1, -1.2 }, { 1.4, -0.1, -1.2 } },
        engine_offsets = { { -0.5, 0.0, 2.2 }, { 0.5, 0.0, 2.2 } },
        mod1 = "microwarp",
        mod2 = "emp",
    },
    fighter = {
        id = "fighter",
        order = 2,
        model = "ship_fighter",
        radius = 3.8,
        speed = 50,
        boost_speed = 90,
        turn_rate = 2.8,
        shield = 100,
        hull = 130,
        weapon_type = "kinetic",
        weapon_damage = 18,
        weapon_rate = 5.4,
        weapon_range = 205,
        proj_speed = 285,
        proj_color = { 1.0, 0.84, 0.25 },
        muzzle_offsets = { { -2.2, -0.1, -1.4 }, { 2.2, -0.1, -1.4 } },
        engine_offsets = { { -1.15, 0.0, 2.5 }, { 1.15, 0.0, 2.5 } },
        mod1 = "micromissiles",
        mod2 = "overdrive",
    },
    frigate = {
        id = "frigate",
        order = 3,
        model = "ship_frigate",
        radius = 4.8,
        speed = 36,
        boost_speed = 64,
        turn_rate = 2.0,
        shield = 200,
        hull = 220,
        weapon_type = "railgun",
        weapon_damage = 64,
        weapon_rate = 1.35,
        weapon_range = 295,
        proj_speed = 460,
        proj_color = { 0.40, 0.95, 1.0 },
        muzzle_offsets = { { 0.0, 0.18, -4.4 } },
        engine_offsets = { { -1.4, 0.0, 3.2 }, { 1.4, 0.0, 3.2 } },
        mod1 = "energydome",
        mod2 = "repairdrone",
    },
}

M.CLASS_ORDER = { "interceptor", "fighter", "frigate" }

-- 24 hull skins matching palette_256.png rows 0..5, 4 skins per row
M.SKINS = {}
local skin_colors = {
    { 0.18, 0.55, 1.00 }, { 0.90, 0.22, 0.21 }, { 0.00, 0.75, 0.65 }, { 0.96, 0.65, 0.14 },
    { 0.56, 0.14, 0.67 }, { 0.26, 0.63, 0.28 }, { 0.92, 0.94, 0.95 }, { 0.22, 0.28, 0.31 },
    { 0.96, 0.36, 0.48 }, { 0.85, 0.11, 0.38 }, { 0.83, 0.64, 0.45 }, { 0.12, 0.23, 0.54 },
    { 0.49, 0.70, 0.26 }, { 0.37, 0.21, 0.69 }, { 0.93, 0.25, 0.48 }, { 0.55, 0.43, 0.39 },
    { 0.00, 0.67, 0.76 }, { 0.75, 0.21, 0.05 }, { 0.15, 0.65, 0.60 }, { 0.98, 0.55, 0.00 },
    { 0.22, 0.29, 0.67 }, { 0.33, 0.55, 0.18 }, { 0.99, 0.85, 0.21 }, { 0.73, 0.41, 0.78 },
}
for i = 0, 23 do
    local col = (i % 4) * 4
    local row = math.floor(i / 4)
    M.SKINS[i + 1] = {
        id = i + 1,
        u_offset = col / 16.0,
        v_offset = row / 16.0,
        preview = skin_colors[i + 1],
    }
end

-- 12 engine trail colors
M.TRAILS = {
    { id = 1, color = { 0.00, 0.90, 1.00 } },
    { id = 2, color = { 1.00, 0.35, 0.15 } },
    { id = 3, color = { 0.40, 0.95, 0.68 } },
    { id = 4, color = { 1.00, 0.84, 0.25 } },
    { id = 5, color = { 0.88, 0.25, 0.98 } },
    { id = 6, color = { 0.96, 0.36, 0.48 } },
    { id = 7, color = { 0.20, 0.55, 1.00 } },
    { id = 8, color = { 0.78, 1.00, 0.20 } },
    { id = 9, color = { 1.00, 1.00, 1.00 } },
    { id = 10, color = { 1.00, 0.15, 0.45 } },
    { id = 11, color = { 0.00, 1.00, 0.85 } },
    { id = 12, color = { 1.00, 0.55, 0.00 } },
}

function M.get_effective_stats(class_id, upgrades)
    local base = M.CLASSES[class_id] or M.CLASSES.interceptor
    local u = upgrades or { hull = 1, weapon = 1, shield = 1, engine = 1 }
    local hull_lv = u.hull or 1
    local weap_lv = u.weapon or 1
    local shield_lv = u.shield or 1
    local eng_lv = u.engine or 1
    local avg_tier = math.floor((hull_lv + weap_lv + shield_lv + eng_lv) / 4 + 0.5)
    avg_tier = math.max(1, math.min(5, avg_tier))

    local damage = base.weapon_damage * (1 + 0.15 * (weap_lv - 1))
    return {
        class_id = base.id,
        tier = avg_tier,
        hull_lv = hull_lv,
        weapon_lv = weap_lv,
        shield_lv = shield_lv,
        engine_lv = eng_lv,
        max_hull = math.floor(base.hull * (1 + 0.15 * (hull_lv - 1)) + 0.5),
        max_shield = math.floor(base.shield * (1 + 0.15 * (shield_lv - 1)) + 0.5),
        damage = damage,
        dps = math.floor(damage * base.weapon_rate + 0.5),
        speed = base.speed * (1 + 0.07 * (eng_lv - 1)),
        boost_speed = base.boost_speed * (1 + 0.07 * (eng_lv - 1)),
        turn_rate = base.turn_rate * (1 + 0.05 * (eng_lv - 1)),
        weapon_rate = base.weapon_rate,
        weapon_range = base.weapon_range,
        weapon_type = base.weapon_type,
        proj_speed = base.proj_speed,
        proj_color = base.proj_color,
        radius = base.radius,
        muzzle_offsets = base.muzzle_offsets,
        engine_offsets = base.engine_offsets,
        mod1 = base.mod1,
        mod2 = base.mod2,
    }
end

return M
