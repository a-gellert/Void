-- Arena layouts. All coordinates are metres, arena is a soft sphere of ARENA_RADIUS.
-- Each layout provides: obstacles, 3 beacons, pickups, team spawns, a race ring loop,
-- an escort path and wave entry points. Missions pick a layout + a sector theme.
local M = {}

M.ARENA_RADIUS = 250.0

-- Deterministic Park-Miller LCG (products stay < 2^53, exact in doubles) so
-- generated fields are identical on every device and Lua VM.
local function lcg(seed)
    local s = seed
    return function()
        s = (s * 16807) % 2147483647
        return s / 2147483647
    end
end

local function dist3(a, b)
    local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Ring loop: n gates on a wavy ellipse.
local function ring_loop(cx, cy, cz, rx, rz, y_amp, n, phase, weave)
    local list = {}
    for i = 0, n - 1 do
        local a = phase + (i / n) * math.pi * 2
        local w = 1.0 + (weave or 0) * math.sin(a * 3)
        list[#list + 1] = {
            cx + math.cos(a) * rx * w,
            cy + math.sin(a * 2) * y_amp,
            cz + math.sin(a) * rz * w,
        }
    end
    return list
end

local function gen_field(seed, count, rmin, rmax, shell_min, shell_max, keepout, keep_r)
    local rnd = lcg(seed)
    local out = {}
    local guard = 0
    while #out < count and guard < 4000 do
        guard = guard + 1
        local r = rmin + rnd() * (rmax - rmin)
        local u = rnd() * 2 - 1
        local th = rnd() * math.pi * 2
        local d = shell_min + rnd() * (shell_max - shell_min)
        local h = math.sqrt(1 - u * u)
        local p = { math.cos(th) * h * d, u * d * 0.55, math.sin(th) * h * d }
        local ok = true
        for _, k in ipairs(keepout) do
            if dist3(p, k) < r + (k[4] or keep_r) then ok = false; break end
        end
        if ok then
            for _, o in ipairs(out) do
                if dist3(p, { o.x, o.y, o.z }) < r + o.r + 10 then ok = false; break end
            end
        end
        if ok then
            out[#out + 1] = { x = p[1], y = p[2], z = p[3], r = r, model = (#out % 2) + 1 }
        end
    end
    return out
end

local STD_SPAWNS = {
    team1 = { { -24, 6, 175 }, { 24, 6, 175 }, { -56, -8, 160 }, { 56, 10, 160 }, { 0, 22, 190 } },
    team2 = { { -24, 6, -175 }, { 24, 6, -175 }, { -56, 10, -160 }, { 56, -8, -160 }, { 0, -18, -190 } },
}

local WAVE_SPAWNS = {
    { 0, 30, -215 }, { 150, 10, -150 }, { -150, -10, -150 },
    { 205, 40, 20 }, { -205, -30, 20 }, { 0, 90, -190 },
}

-- ===================================================================== RIFT
M.LAYOUTS = {}

M.LAYOUTS.rift = {
    id = "rift",
    station = { x = 0, y = 0, z = 0, core_radius = 16.0 },
    hollow = { x = -95, y = 0, z = 40, scale = 28.0 },
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
        { id = "A", x = 0, y = 52, z = 0, radius = 20 },
        { id = "B", x = -95, y = 0, z = 40, radius = 20 },
        { id = "C", x = 95, y = -40, z = -45, radius = 20 },
    },
    pickups = {
        { kind = "repair", x = 0, y = -36, z = 0, radius = 7.5, respawn = 18.0 },
        { kind = "charge", x = 58, y = 14, z = -12, radius = 7.5, respawn = 18.0 },
        { kind = "repair", x = -52, y = 18, z = -10, radius = 7.5, respawn = 18.0 },
    },
    spawns = STD_SPAWNS,
    rings = ring_loop(0, 10, 0, 120, 140, 26, 12, math.pi * 0.5, 0.18),
    escort_path = { { -140, 10, 130 }, { -130, 60, 40 }, { -40, 45, -60 }, { 70, 20, -110 }, { 150, 10, -130 } },
    wave_spawns = WAVE_SPAWNS,
}

-- ===================================================================== BELT
do
    local rings = ring_loop(0, 0, 0, 150, 120, 34, 14, math.pi * 0.5, 0.25)
    local path = { { -150, 0, 120 }, { -80, -30, 60 }, { -10, -60, -20 }, { 70, -20, -90 }, { 150, 0, -130 } }
    local beacons = {
        { id = "A", x = 0, y = 0, z = 0, radius = 22 },
        { id = "B", x = -110, y = 20, z = -40, radius = 20 },
        { id = "C", x = 110, y = -20, z = 40, radius = 20 },
    }
    local keep = {}
    for _, r in ipairs(rings) do keep[#keep + 1] = { r[1], r[2], r[3], 26 } end
    for _, p in ipairs(path) do keep[#keep + 1] = { p[1], p[2], p[3], 34 } end
    for _, b in ipairs(beacons) do keep[#keep + 1] = { b.x, b.y, b.z, 34 } end
    for _, s in ipairs(STD_SPAWNS.team1) do keep[#keep + 1] = { s[1], s[2], s[3], 30 } end
    for _, s in ipairs(STD_SPAWNS.team2) do keep[#keep + 1] = { s[1], s[2], s[3], 30 } end
    keep[#keep + 1] = { 0, -40, 60, 16 }
    keep[#keep + 1] = { 40, 30, -50, 16 }
    keep[#keep + 1] = { -60, 30, 30, 16 }
    M.LAYOUTS.belt = {
        id = "belt",
        station = nil,
        hollow = { x = 0, y = 0, z = 0, scale = 30.0 },
        asteroids = gen_field(1337, 22, 7, 17, 45, 215, keep, 20),
        beacons = beacons,
        pickups = {
            { kind = "repair", x = 0, y = -40, z = 60, radius = 7.5, respawn = 18.0 },
            { kind = "charge", x = 40, y = 30, z = -50, radius = 7.5, respawn = 18.0 },
            { kind = "repair", x = -60, y = 30, z = 30, radius = 7.5, respawn = 18.0 },
        },
        spawns = STD_SPAWNS,
        rings = rings,
        escort_path = path,
        wave_spawns = WAVE_SPAWNS,
    }
end

-- =================================================================== NEBULA
do
    local rings = ring_loop(0, 20, 0, 135, 135, 40, 12, 0.0, 0.3)
    local path = { { -140, -20, 130 }, { -150, 10, 20 }, { -90, 40, -80 }, { 20, 30, -140 }, { 140, 0, -120 } }
    local beacons = {
        { id = "A", x = 0, y = 50, z = 0, radius = 20 },
        { id = "B", x = 110, y = 30, z = 60, radius = 20 },
        { id = "C", x = -100, y = -30, z = -60, radius = 20 },
    }
    local keep = { { 0, -10, 0, 50 }, { 110, 30, 60, 46 } }
    for _, r in ipairs(rings) do keep[#keep + 1] = { r[1], r[2], r[3], 28 } end
    for _, p in ipairs(path) do keep[#keep + 1] = { p[1], p[2], p[3], 36 } end
    for _, b in ipairs(beacons) do keep[#keep + 1] = { b.x, b.y, b.z, 34 } end
    for _, s in ipairs(STD_SPAWNS.team1) do keep[#keep + 1] = { s[1], s[2], s[3], 32 } end
    for _, s in ipairs(STD_SPAWNS.team2) do keep[#keep + 1] = { s[1], s[2], s[3], 32 } end
    keep[#keep + 1] = { 60, -50, 0, 16 }
    keep[#keep + 1] = { -60, 20, 70, 16 }
    M.LAYOUTS.nebula = {
        id = "nebula",
        station = { x = 0, y = -10, z = 0, core_radius = 16.0 },
        hollow = { x = 110, y = 30, z = 60, scale = 26.0 },
        asteroids = gen_field(4242, 12, 12, 24, 60, 210, keep, 20),
        beacons = beacons,
        pickups = {
            { kind = "repair", x = 60, y = -50, z = 0, radius = 7.5, respawn = 18.0 },
            { kind = "charge", x = -60, y = 20, z = 70, radius = 7.5, respawn = 18.0 },
        },
        spawns = STD_SPAWNS,
        rings = rings,
        escort_path = path,
        wave_spawns = WAVE_SPAWNS,
    }
end

-- ============================================================ DREADNOUGHT WRECKFIELD
M.LAYOUTS.wreck = {
    id = "wreck",
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
        pos = { 0, 10, -65 },
        hull_radius = 28.0,
        generators = {
            { id = "gen_port", offset = { -22, 4, 5 }, radius = 7.0, hp = 320 },
            { id = "gen_stbd", offset = { 22, 4, 5 }, radius = 7.0, hp = 320 },
            { id = "gen_dorsal", offset = { 0, 18, 22 }, radius = 7.0, hp = 360 },
        },
        turrets = {
            { id = "turret_fl", offset = { -14, 8, -32 }, radius = 6.5, hp = 260, fire_rate = 1.1, damage = 16 },
            { id = "turret_fr", offset = { 14, 8, -32 }, radius = 6.5, hp = 260, fire_rate = 1.1, damage = 16 },
            { id = "turret_rl", offset = { -16, 8, 18 }, radius = 6.5, hp = 260, fire_rate = 0.9, damage = 20 },
            { id = "turret_rr", offset = { 16, 8, 18 }, radius = 6.5, hp = 260, fire_rate = 0.9, damage = 20 },
        },
        reactor = { id = "reactor", offset = { 0, 2, -2 }, radius = 10.0, hp = 950 },
    },
    beacons = {},
    pickups = {
        { kind = "repair", x = -55, y = 12, z = 35, radius = 7.5, respawn = 16.0 },
        { kind = "charge", x = 55, y = 12, z = 35, radius = 7.5, respawn = 16.0 },
        { kind = "repair", x = 0, y = -30, z = 60, radius = 7.5, respawn = 16.0 },
    },
    spawns = {
        team1 = { { -28, 4, 165 }, { 28, 4, 165 }, { -65, 14, 150 }, { 65, -8, 150 }, { 0, 20, 180 } },
        team2 = { { -60, 30, -150 }, { 60, 30, -150 }, { 0, 50, -170 }, { -90, 0, -120 }, { 90, 0, -120 } },
    },
    rings = {},
    escort_path = {},
    wave_spawns = WAVE_SPAWNS,
}

-- Visual themes per campaign sector (clear colour, star dome tint, dust tint).
M.THEMES = {
    kepler = { clear = { 0.020, 0.045, 0.060 }, stars = { 0.85, 1.0, 0.95, 1.0 }, dust = { 0.70, 1.0, 0.90 } },
    ion = { clear = { 0.025, 0.035, 0.075 }, stars = { 0.85, 0.92, 1.0, 1.0 }, dust = { 0.72, 0.88, 1.0 } },
    crimson = { clear = { 0.075, 0.022, 0.045 }, stars = { 1.0, 0.78, 0.82, 1.0 }, dust = { 1.0, 0.70, 0.75 } },
    void = { clear = { 0.030, 0.012, 0.050 }, stars = { 0.86, 0.72, 1.0, 1.0 }, dust = { 0.85, 0.70, 1.0 } },
}

function M.get_layout(id)
    return M.LAYOUTS[id] or M.LAYOUTS.rift
end

return M
