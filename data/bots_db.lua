local M = {}

M.BOT_PROFILES = {
    { name = "Kestrel_99", flag = "US", archetype = "aggressor", class_id = "interceptor", skin = 2, trail = 2 },
    { name = "ValkyrieBR", flag = "BR", archetype = "tactician", class_id = "fighter", skin = 4, trail = 4 },
    { name = "Sokol_77", flag = "RU", archetype = "aggressor", class_id = "interceptor", skin = 10, trail = 10 },
    { name = "Bozkurt_TR", flag = "TR", archetype = "defender", class_id = "frigate", skin = 8, trail = 5 },
    { name = "NovaPulse", flag = "DE", archetype = "tactician", class_id = "fighter", skin = 6, trail = 3 },
    { name = "AegisCore", flag = "GB", archetype = "defender", class_id = "frigate", skin = 12, trail = 7 },
    { name = "ZeroGravity", flag = "JP", archetype = "aggressor", class_id = "interceptor", skin = 17, trail = 11 },
    { name = "FuriaEstelar", flag = "BR", archetype = "tactician", class_id = "fighter", skin = 9, trail = 6 },
    { name = "Grom_204", flag = "RU", archetype = "defender", class_id = "frigate", skin = 18, trail = 12 },
    { name = "AtesKusu", flag = "TR", archetype = "aggressor", class_id = "interceptor", skin = 20, trail = 2 },
    { name = "OrionWing", flag = "FR", archetype = "tactician", class_id = "fighter", skin = 14, trail = 5 },
    { name = "IronBastion", flag = "CA", archetype = "defender", class_id = "frigate", skin = 16, trail = 4 },
}

M.ARCHETYPES = {
    aggressor = {
        preferred_range = 65,
        strafe_amp = 0.75,
        dash_chance = 0.65,
        mod_aggression = 0.85,
        aim_jitter = 0.04,
    },
    tactician = {
        preferred_range = 115,
        strafe_amp = 0.55,
        dash_chance = 0.40,
        mod_aggression = 0.70,
        aim_jitter = 0.03,
    },
    defender = {
        preferred_range = 165,
        strafe_amp = 0.30,
        dash_chance = 0.25,
        mod_aggression = 0.75,
        aim_jitter = 0.025,
    },
}

return M
