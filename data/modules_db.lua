local M = {}

M.DASH = {
    id = "dash",
    cooldown = 4.5,
    duration = 0.45,
    speed_mult = 2.1,
    breaks_lock = true,
}

M.MODULES = {
    microwarp = {
        id = "microwarp",
        cooldown = 8.0,
        distance = 40.0,
        invuln_duration = 0.4,
        color = { 0.0, 0.90, 1.0 },
    },
    emp = {
        id = "emp",
        cooldown = 11.0,
        radius = 25.0,
        block_regen = 3.0,
        color = { 0.85, 0.30, 1.0 },
    },
    micromissiles = {
        id = "micromissiles",
        cooldown = 9.0,
        count = 4,
        damage = 28,
        speed = 165,
        turn_rate = 5.5,
        life = 3.2,
        color = { 1.0, 0.45, 0.15 },
    },
    overdrive = {
        id = "overdrive",
        cooldown = 10.0,
        duration = 4.0,
        rate_mult = 1.5,
        color = { 1.0, 0.78, 0.15 },
    },
    energydome = {
        id = "energydome",
        cooldown = 12.0,
        duration = 3.0,
        damage_reduction = 0.80,
        color = { 0.25, 0.72, 1.0 },
    },
    repairdrone = {
        id = "repairdrone",
        cooldown = 12.0,
        heal_pct = 0.35,
        radius = 38.0,
        color = { 0.40, 0.95, 0.65 },
    },
}

return M
