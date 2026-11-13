-- Ship hulls, weapons, upgrade tiers and cosmetics.
-- Player hulls: 6 (2 per role). Enemy-only hulls: drone, kamikaze, freighter.
local M = {}

M.DAMAGE_MULT = {
    plasma = { shield = 1.25, hull = 0.80 },
    kinetic = { shield = 0.85, hull = 1.25 },
    railgun = { shield = 0.90, hull = 1.20 },
    missile = { shield = 0.85, hull = 1.25 },
    explosion = { shield = 1.0, hull = 1.0 },
}

-- Credits / parts for reaching tier N of an upgrade node (index = target tier).
M.UPGRADE_COSTS = {
    credits = { 0, 150, 350, 700, 1250 },
    parts = { 0, 0, 2, 5, 9 },
}

M.CRAFT_COSTS = {
    random = 2,
    trail = 3,
    skin = 4,
}

M.ROLES = { "interceptor", "fighter", "frigate" }

-- Hull/shield multiplier for every combat hull (not the escort freighter).
M.DURABILITY = 1.5

M.SHIPS = {
    -- ===== Interceptors: fast, fragile, plasma (strong vs shields) =====
    wasp = {
        id = "wasp", role = "interceptor", mesh = "interceptor", order = 1,
        unlock_level = 1, price = 0, default_skin = 1,
        radius = 3.2, speed = 66, boost_mult = 1.75, strafe = 26, turn_rate = 3.5, agility = 9.0,
        shield = 60, hull = 90, energy = 100, missiles = 2,
        weapon = { type = "plasma", damage = 11, rate = 7.5, range = 175, proj_speed = 265,
            color = { 0.0, 0.90, 1.0 }, muzzles = { { -1.4, -0.1, -1.2 }, { 1.4, -0.1, -1.2 } } },
        modules = { "microwarp", "emp", "cloak" },
    },
    phantom = {
        id = "phantom", role = "interceptor", mesh = "interceptor", order = 4,
        unlock_level = 6, price = 1800, default_skin = 8,
        radius = 3.2, speed = 72, boost_mult = 1.8, strafe = 30, turn_rate = 3.8, agility = 10.0,
        shield = 70, hull = 85, energy = 120, missiles = 2,
        weapon = { type = "plasma", damage = 16, rate = 6.4, range = 185, proj_speed = 290,
            color = { 0.88, 0.25, 0.98 }, muzzles = { { -1.4, -0.1, -1.2 }, { 1.4, -0.1, -1.2 } } },
        modules = { "microwarp", "emp", "cloak" },
    },
    -- ===== Fighters: balanced dogfighters, kinetic (strong vs hull) =====
    falcon = {
        id = "falcon", role = "fighter", mesh = "fighter", order = 2,
        unlock_level = 2, price = 400, default_skin = 4,
        radius = 3.8, speed = 54, boost_mult = 1.7, strafe = 22, turn_rate = 2.9, agility = 7.5,
        shield = 100, hull = 135, energy = 100, missiles = 3,
        weapon = { type = "kinetic", damage = 18, rate = 5.4, range = 205, proj_speed = 290,
            color = { 1.0, 0.84, 0.25 }, muzzles = { { -2.2, -0.1, -1.4 }, { 2.2, -0.1, -1.4 } } },
        modules = { "overdrive", "swarm", "nanorepair" },
    },
    raptor = {
        id = "raptor", role = "fighter", mesh = "fighter", order = 5,
        unlock_level = 8, price = 2600, default_skin = 18,
        radius = 3.8, speed = 56, boost_mult = 1.7, strafe = 22, turn_rate = 3.0, agility = 7.5,
        shield = 115, hull = 165, energy = 110, missiles = 4,
        weapon = { type = "kinetic", damage = 23, rate = 4.8, range = 215, proj_speed = 300,
            color = { 1.0, 0.55, 0.15 }, muzzles = { { -2.2, -0.1, -1.4 }, { 2.2, -0.1, -1.4 } } },
        modules = { "overdrive", "swarm", "nanorepair" },
    },
    -- ===== Frigates: heavy, slow, railgun + support =====
    bastion = {
        id = "bastion", role = "frigate", mesh = "frigate", order = 3,
        unlock_level = 4, price = 900, default_skin = 12,
        radius = 4.8, speed = 40, boost_mult = 1.65, strafe = 16, turn_rate = 2.1, agility = 5.5,
        shield = 200, hull = 220, energy = 100, missiles = 2,
        weapon = { type = "railgun", damage = 62, rate = 1.4, range = 300, proj_speed = 480,
            color = { 0.40, 0.95, 1.0 }, muzzles = { { 0.0, 0.18, -4.4 } } },
        modules = { "energydome", "repairdrone", "pulse" },
    },
    aegis = {
        id = "aegis", role = "frigate", mesh = "frigate", order = 6,
        unlock_level = 10, price = 3600, default_skin = 7,
        radius = 4.8, speed = 42, boost_mult = 1.65, strafe = 16, turn_rate = 2.2, agility = 5.5,
        shield = 260, hull = 250, energy = 110, missiles = 3,
        weapon = { type = "railgun", damage = 82, rate = 1.25, range = 330, proj_speed = 520,
            color = { 0.40, 1.0, 0.68 }, muzzles = { { 0.0, 0.18, -4.4 } } },
        modules = { "energydome", "repairdrone", "pulse" },
    },

    -- ===== Enemy-only hulls =====
    drone = {
        id = "drone", role = "drone", mesh = "drone", order = 90, enemy_only = true,
        radius = 2.6, speed = 52, boost_mult = 1.5, strafe = 14, turn_rate = 2.6, agility = 6.0,
        shield = 0, hull = 38, energy = 0, missiles = 0,
        weapon = { type = "plasma", damage = 5, rate = 2.2, range = 130, proj_speed = 210,
            color = { 1.0, 0.25, 0.15 }, muzzles = { { 0.0, 0.0, -1.6 } } },
        modules = {},
    },
    kamikaze = {
        id = "kamikaze", role = "drone", mesh = "drone", order = 91, enemy_only = true,
        radius = 2.6, speed = 64, boost_mult = 1.4, strafe = 0, turn_rate = 2.3, agility = 6.0,
        shield = 0, hull = 30, energy = 0, missiles = 0, blast_damage = 55, blast_radius = 14,
        weapon = nil,
        modules = {},
    },
    freighter = {
        id = "freighter", role = "vip", mesh = "freighter", order = 92, enemy_only = true,
        radius = 11.0, speed = 13, boost_mult = 1.0, strafe = 0, turn_rate = 0.5, agility = 1.5,
        shield = 500, hull = 1300, energy = 0, missiles = 0,
        weapon = nil,
        modules = {},
    },
}

M.PLAYER_SHIPS = { "wasp", "falcon", "bastion", "phantom", "raptor", "aegis" }

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

function M.get(ship_id)
    return M.SHIPS[ship_id] or M.SHIPS.wasp
end

function M.tier_of(u)
    local t = math.floor(((u.hull or 1) + (u.weapon or 1) + (u.shield or 1) + (u.engine or 1)) / 4 + 0.5)
    return math.max(1, math.min(5, t))
end

function M.uniform_upgrades(tier)
    local t = math.max(1, math.min(5, tier or 1))
    return { hull = t, weapon = t, shield = t, engine = t }
end

-- Flattened combat stats for a hull with upgrade levels { hull, weapon, shield, engine } (1..5).
function M.get_effective_stats(ship_id, upgrades)
    local base = M.get(ship_id)
    local u = upgrades or { hull = 1, weapon = 1, shield = 1, engine = 1 }
    local hull_lv = u.hull or 1
    local weap_lv = u.weapon or 1
    local shield_lv = u.shield or 1
    local eng_lv = u.engine or 1
    local w = base.weapon
    local damage = w and (w.damage * (1 + 0.15 * (weap_lv - 1))) or 0
    local eng = 1 + 0.06 * (eng_lv - 1)
    -- Global durability so fights last long enough to read and react (casual TTK ~5-10 s).
    local dur = (base.role == "vip") and 1.0 or M.DURABILITY
    return {
        ship_id = base.id,
        role = base.role,
        mesh = base.mesh,
        tier = M.tier_of(u),
        hull_lv = hull_lv,
        weapon_lv = weap_lv,
        shield_lv = shield_lv,
        engine_lv = eng_lv,
        max_hull = math.floor(base.hull * dur * (1 + 0.15 * (hull_lv - 1)) + 0.5),
        max_shield = math.floor(base.shield * dur * (1 + 0.15 * (shield_lv - 1)) + 0.5),
        damage = damage,
        dps = w and math.floor(damage * w.rate + 0.5) or 0,
        speed = base.speed * eng,
        boost_mult = base.boost_mult,
        strafe = base.strafe * eng,
        turn_rate = base.turn_rate * (1 + 0.05 * (eng_lv - 1)),
        agility = base.agility,
        max_energy = math.floor(base.energy * (1 + 0.10 * (eng_lv - 1)) + 0.5),
        missiles = base.missiles,
        weapon_rate = w and w.rate or 0,
        weapon_range = w and w.range or 0,
        weapon_type = w and w.type or "plasma",
        proj_speed = w and w.proj_speed or 200,
        proj_color = w and w.color or { 1, 1, 1 },
        muzzle_offsets = w and w.muzzles or { { 0, 0, -1 } },
        has_weapon = w ~= nil,
        radius = base.radius,
        blast_damage = base.blast_damage,
        blast_radius = base.blast_radius,
        modules = base.modules,
    }
end

return M
