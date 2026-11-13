-- Pilot levels, level-up rewards and contract templates.
local M = {}

M.MAX_LEVEL = 30

-- XP needed to go from level L to L+1.
function M.xp_for_level(level)
    return 200 + 100 * level
end

-- Reward granted on reaching `level`.
function M.level_reward(level)
    return { credits = 100 * level, parts = (level % 2 == 0) and 2 or 1 }
end

-- Match XP / credits outside of mission rewards (skirmish).
M.MATCH = {
    win_credits = 150, loss_credits = 70, kill_credits = 15,
    win_xp = 120, loss_xp = 60, kill_xp = 10,
    win_parts = 2, loss_parts = 1,
}

-- Contracts: 3 active at once, replaced on claim.
-- stat: which counter advances it (see progress.track()).
M.CONTRACTS = {
    { id = "kills", stat = "kills", min = 10, max = 25, credits = 18, xp = 8, parts = 1 },
    { id = "wins", stat = "wins", min = 2, max = 4, credits = 140, xp = 70, parts = 1 },
    { id = "missile_kills", stat = "missile_kills", min = 3, max = 6, credits = 70, xp = 30, parts = 1 },
    { id = "stars", stat = "stars", min = 3, max = 6, credits = 80, xp = 40, parts = 1 },
    { id = "beacons", stat = "beacons", min = 3, max = 6, credits = 60, xp = 30, parts = 1 },
    { id = "drones", stat = "drones", min = 15, max = 30, credits = 12, xp = 6, parts = 1 },
    { id = "rings", stat = "rings", min = 15, max = 30, credits = 10, xp = 5, parts = 1 },
    { id = "damage", stat = "damage", min = 3000, max = 6000, credits = 0.08, xp = 0.03, parts = 2 },
    { id = "modules", stat = "modules", min = 12, max = 25, credits = 12, xp = 6, parts = 1 },
}

return M
