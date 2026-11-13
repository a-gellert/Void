-- Bot pilots: names, behaviour archetypes and difficulty curve.
local M = {}

M.PILOT_NAMES = {
    { "Kestrel_99", "US" }, { "ValkyrieBR", "BR" }, { "Sokol_77", "RU" }, { "Bozkurt_TR", "TR" },
    { "NovaPulse", "DE" }, { "AegisCore", "GB" }, { "ZeroGravity", "JP" }, { "FuriaEstelar", "BR" },
    { "Grom_204", "RU" }, { "AtesKusu", "TR" }, { "OrionWing", "FR" }, { "IronBastion", "CA" },
    { "Lynx", "SE" }, { "Halcyon", "IT" }, { "Tempest_X", "US" }, { "Raposa", "PT" },
    { "Strizh", "RU" }, { "Kartal", "TR" }, { "Quasar", "ES" }, { "Nightjar", "AU" },
    { "Vortex_3", "PL" }, { "Ember", "NL" }, { "Comet", "KR" }, { "Brisa", "BR" },
}

M.PIRATE_NAMES = {
    "Scrap-Rat", "Rust Fang", "Hexbolt", "Cinder", "Junkjaw", "Gutter", "Snarl", "Blackmark",
    "Razorback", "Spitfire", "Grimlock", "Mongrel",
}

-- Elite enemy aces (ace hunt missions).
M.ACES = {
    { name = "VIPER", ship = "phantom", skin = 10, trail = 10 },
    { name = "WARDEN", ship = "aegis", skin = 18, trail = 12 },
    { name = "MAULER", ship = "raptor", skin = 2, trail = 2 },
    { name = "HEX", ship = "wasp", skin = 14, trail = 5 },
}

M.ARCHETYPES = {
    aggressor = { preferred_range = 70, strafe_amp = 0.8, dash_chance = 0.65, mod_aggression = 0.9 },
    tactician = { preferred_range = 115, strafe_amp = 0.55, dash_chance = 0.45, mod_aggression = 0.7 },
    defender = { preferred_range = 165, strafe_amp = 0.35, dash_chance = 0.30, mod_aggression = 0.75 },
}

M.ROLE_ARCHETYPE = { interceptor = "aggressor", fighter = "tactician", frigate = "defender" }

-- Difficulty 1..10 -> bot skill parameters.
--  aim_error: radians of random lead error; fire_cone: min dot to pull the trigger;
--  reaction: dash/evade probability multiplier; dmg_mult / hp_mult: raw scaling.
function M.skill(difficulty)
    local d = math.max(1, math.min(10, difficulty or 3))
    local t = (d - 1) / 9
    return {
        level = d,
        aim_error = 0.085 - 0.07 * t,
        fire_cone = 0.80 + 0.12 * t,
        reaction = 0.35 + 0.85 * t,
        dmg_mult = 0.42 + 0.40 * t,
        hp_mult = 0.85 + 0.35 * t,
        missile_use = d >= 3,
        module_use = 0.4 + 0.6 * t,
        retreat_hp = (d >= 4) and 0.35 or 0.0,
    }
end

return M
