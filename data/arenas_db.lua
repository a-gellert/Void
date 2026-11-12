local M = {}

M.ARENA_RADIUS = 250.0

M.STANDARD_ARENA = {
    id = "orbital_rift",
    station = { x = 0, y = 0, z = 0, core_radius = 16.0 },
    -- Hollow asteroid sits around Beacon B so players fly through or around it
    hollow_asteroid = { x = -95, y = 0, z = 40, scale = 28.0, collider_radius = 12.0 },
    asteroids = {
        { x = 68, y = 22, z = 58, r = 14, model = 1 },
        { x = -56, y = -28, z = -64, r = 16, model = 2 },
        { x = 112, y = -18, z = 20, r = 13, model = 1 },
        { x = -120, y = 34, z = -32, r = 15, model = 2 },
        { x = 28, y = -48, z = 95, r = 12, model = 1 },
        { x = -35, y = 52, z = -98, r = 13, model = 2 },
        { x = 82, y = 44, z = -72, r = 15, model = 1 },
        { x = -72, y = -40, z = 108, r = 12, model = 2 },
        { x = 148, y = 10, z = -42, r = 14, model = 1 },
        { x = -152, y = -12, z = 14, r = 14, model = 2 },
        { x = 14, y = 68, z = 25, r = 11, model = 1 },
        { x = -18, y = -68, z = -22, r = 11, model = 2 },
    },
    beacons = {
        { id = "A", x = 0, y = 48, z = 0, radius = 20 },
        { id = "B", x = -95, y = 0, z = 40, radius = 20 },
        { id = "C", x = 95, y = -40, z = -45, radius = 20 },
    },
    spawns = {
        team1 = {
            { -24, 6, 170 }, { 24, 6, 170 }, { -54, -8, 155 }, { 54, 10, 155 },
        },
        team2 = {
            { -24, 6, -170 }, { 24, 6, -170 }, { -54, 10, -155 }, { 54, -8, -155 },
        },
    },
}

M.DREADNOUGHT_ARENA = {
    id = "dreadnought_ambush",
    asteroids = {
        { x = 75, y = 18, z = 65, r = 14, model = 1 },
        { x = -75, y = -14, z = 65, r = 15, model = 2 },
        { x = 95, y = -22, z = -15, r = 13, model = 1 },
        { x = -95, y = 24, z = -15, r = 14, model = 2 },
        { x = 48, y = 42, z = 115, r = 11, model = 1 },
        { x = -48, y = -36, z = 115, r = 11, model = 2 },
        { x = 125, y = 12, z = -85, r = 15, model = 1 },
        { x = -125, y = -16, z = -85, r = 15, model = 2 },
    },
    boss = {
        pos = { x = 0, y = 10, z = -65 },
        hull_radius = 28.0,
        generators = {
            { id = "gen_port", offset = { -22, 4, 5 }, radius = 7.0, hp = 320 },
            { id = "gen_stbd", offset = { 22, 4, 5 }, radius = 7.0, hp = 320 },
            { id = "gen_dorsal", offset = { 0, 18, 22 }, radius = 7.0, hp = 360 },
        },
        turrets = {
            { id = "turret_fl", offset = { -14, 8, -32 }, radius = 6.5, hp = 260, fire_rate = 1.1, damage = 18 },
            { id = "turret_fr", offset = { 14, 8, -32 }, radius = 6.5, hp = 260, fire_rate = 1.1, damage = 18 },
            { id = "turret_rl", offset = { -16, 8, 18 }, radius = 6.5, hp = 260, fire_rate = 0.9, damage = 22 },
            { id = "turret_rr", offset = { 16, 8, 18 }, radius = 6.5, hp = 260, fire_rate = 0.9, damage = 22 },
        },
        reactor = {
            id = "reactor",
            offset = { 0, 2, -2 },
            radius = 10.0,
            hp = 950,
        },
    },
    spawns = {
        team1 = {
            { -28, 4, 165 }, { 28, 4, 165 }, { -65, 14, 150 }, { 65, -8, 150 },
        },
    },
}

return M
