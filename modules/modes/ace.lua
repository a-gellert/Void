-- Ace Hunt: elite enemy aces (no respawn, heavy hull) escorted by respawning pirates.
local bots_db = require("data.bots_db")
local audio = require("modules.audio")

local M = {}

function M.setup(match, api)
    api.build_environment()
    api.spawn_player()
    api.spawn_pilots(1, match.cfg.allies or 2)
    local diff = match.cfg.difficulty or 3
    local skill = api.skill(2)
    match.aces = {}
    for i, idx in ipairs(match.cfg.params.aces or { 1 }) do
        local a = bots_db.ACES[idx]
        local spawn = api.spawn_point(2, i)
        local ace = api.spawn_ship({
            team = 2, ship_id = a.ship, tier = math.min(5, (match.cfg.bot_tier or 1) + 1),
            skin = a.skin, trail = a.trail, name = a.name, display_name = a.name, flag = "",
            ai = "pilot", respawn = false, is_ace = true,
            hp_mult = 2.4 + 0.12 * diff, dmg_mult = skill.dmg_mult * 1.2, pos = spawn,
        })
        if ace then
            ace.archetype = "aggressor"
            match.aces[#match.aces + 1] = ace
        end
    end
    api.spawn_pilots(2, match.cfg.params.escorts or 2)
    match.score_kind = "none"
    api.hint("hint_ace", 6.0)
end

function M.update(match, api)
    local total, cur, left = 0, 0, 0
    for _, a in ipairs(match.aces) do
        total = total + a.max_hull + a.max_shield
        if a.alive then
            cur = cur + a.hull + a.shield
            left = left + 1
        end
    end
    match.boss_bar = { key = "aces_bar", pct = total > 0 and cur / total or 0 }
    api.set_objective("obj_ace", left, #match.aces, 1 - left / math.max(1, #match.aces))
end

function M.on_kill(match, api, victim)
    if not victim.is_ace then return end
    local left = 0
    for _, a in ipairs(match.aces) do if a.alive then left = left + 1 end end
    api.banner("ace_down", "gold", victim.name, 2.2)
    audio.play("objective", 0.6)
    if left == 0 then api.finish(true) end
end

return M
