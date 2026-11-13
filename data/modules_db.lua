-- Flight systems shared by all hulls + 9 role modules (3 per role, 2 equipped).
local M = {}

-- Evasive maneuver (Space): short burst + barrel roll, breaks missile locks.
M.DASH = {
    cooldown = 5.0,
    duration = 0.5,
    speed_mult = 2.3,
}

-- Afterburner (Shift / W): consumes energy while held.
M.AFTERBURNER = {
    drain = 30.0,        -- energy per second
    regen = 22.0,        -- energy per second
    regen_delay = 0.8,   -- seconds after release before regen starts
    min_to_start = 12.0, -- energy needed to (re)ignite
}

-- Brake (S): slower, but tighter turns.
M.BRAKE = {
    speed_mult = 0.5,
    turn_mult = 1.35,
}
M.BOOST_TURN_MULT = 0.8

-- Guided missiles (RMB / F): needs a lock, charges recharge one by one.
M.MISSILE = {
    recharge = 8.0,
    damage = 40,
    speed = 150,
    turn_rate = 4.2,
    life = 3.8,
    color = { 1.0, 0.55, 0.20 },
}

-- Role modules. `unlock_level` = pilot level required to equip.
M.MODULES = {
    -- Interceptor
    microwarp = {
        id = "microwarp", role = "interceptor", unlock_level = 1,
        cooldown = 8.0, distance = 45.0, invuln_duration = 0.45,
        color = { 0.0, 0.90, 1.0 },
    },
    emp = {
        id = "emp", role = "interceptor", unlock_level = 1,
        cooldown = 12.0, radius = 34.0, block_regen = 3.5, damage = 12,
        color = { 0.85, 0.30, 1.0 },
    },
    cloak = {
        id = "cloak", role = "interceptor", unlock_level = 5,
        cooldown = 16.0, duration = 5.0, ambush_mult = 1.6,
        color = { 0.55, 0.60, 0.95 },
    },
    -- Fighter
    overdrive = {
        id = "overdrive", role = "fighter", unlock_level = 1,
        cooldown = 11.0, duration = 5.0, rate_mult = 1.5,
        color = { 1.0, 0.78, 0.15 },
    },
    swarm = {
        id = "swarm", role = "fighter", unlock_level = 1,
        cooldown = 10.0, count = 6, damage = 15, speed = 165, turn_rate = 5.5, life = 3.0,
        color = { 1.0, 0.45, 0.15 },
    },
    nanorepair = {
        id = "nanorepair", role = "fighter", unlock_level = 5,
        cooldown = 15.0, duration = 5.0, heal_pct = 0.45,
        color = { 0.40, 0.95, 0.65 },
    },
    -- Frigate
    energydome = {
        id = "energydome", role = "frigate", unlock_level = 1,
        cooldown = 13.0, duration = 3.5, damage_reduction = 0.80,
        color = { 0.25, 0.72, 1.0 },
    },
    repairdrone = {
        id = "repairdrone", role = "frigate", unlock_level = 1,
        cooldown = 14.0, heal_pct = 0.35, radius = 45.0,
        color = { 0.40, 0.95, 0.65 },
    },
    pulse = {
        id = "pulse", role = "frigate", unlock_level = 7,
        cooldown = 16.0, radius = 55.0, shield_restore = 0.6, damage = 30, push = 26.0,
        color = { 0.55, 0.85, 1.0 },
    },
}

M.ROLE_DEFAULTS = {
    interceptor = { "microwarp", "emp" },
    fighter = { "overdrive", "swarm" },
    frigate = { "energydome", "repairdrone" },
}

return M
