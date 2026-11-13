-- Team Deathmatch: first team to `target_score` pilot kills wins.
local M = {}

function M.setup(match, api)
    api.build_environment()
    api.spawn_player()
    api.spawn_pilots(1, match.cfg.allies or 3)
    api.spawn_pilots(2, match.cfg.enemies or 4)
    match.score_kind = "kills"
    match.score_target = match.cfg.params.target_score or 12
    api.hint("hint_tdm", 5.0)
end

function M.on_kill(match, api, victim)
    if victim.ai ~= "pilot" and not victim.is_player then return end
    local t = (victim.team == 1) and 2 or 1
    match.score[t] = match.score[t] + 1
    if match.score[1] >= match.score_target then
        api.finish(true)
    elseif match.score[2] >= match.score_target then
        api.finish(false)
    end
end

function M.update(match, api)
    api.set_objective("obj_tdm", match.score[1], match.score_target, match.score[1] / math.max(1, match.score_target))
end

function M.on_timeout(match)
    return match.score[1] >= match.score[2]
end

return M
