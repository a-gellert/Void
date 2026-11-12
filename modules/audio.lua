local M = {}

local muted = false
local ad_paused = false
local ambient_wanted = false
local ambient_started = false
local last_play_time = {}

local COOLDOWNS = {
    laser = 0.08,
    kinetic = 0.09,
    railgun = 0.15,
    shield_hit = 0.10,
    explosion = 0.12,
    lock = 0.14,
    victory = 0.50,
    defeat = 0.50,
}

local function sync_master_gain()
    sound.set_group_gain(hash("master"), (muted or ad_paused) and 0.0 or 1.0)
end

function M.start_ambient()
    ambient_wanted = true
    if not ambient_started and not ad_paused then
        ambient_started = true
        sound.play("/audio#ambient", { gain = 0.25 })
    end
    sync_master_gain()
end

function M.set_muted(is_muted)
    muted = is_muted and true or false
    sync_master_gain()
end

function M.is_muted()
    return muted
end

function M.set_ad_paused(paused)
    ad_paused = paused and true or false
    sync_master_gain()
    if ad_paused then
        if ambient_started and sound.pause then
            sound.pause("/audio#ambient", true)
        end
    else
        if ambient_started and sound.pause then
            sound.pause("/audio#ambient", false)
        elseif ambient_wanted and not ambient_started then
            ambient_started = true
            sound.play("/audio#ambient", { gain = 0.25 })
        end
    end
end

function M.play(name, gain)
    if muted or ad_paused then return end
    local now = socket.gettime()
    local cd = COOLDOWNS[name]
    if cd then
        local prev = last_play_time[name] or 0
        if (now - prev) < cd then return end
    end
    last_play_time[name] = now
    sound.play("/audio#" .. name, { gain = gain or 0.7 })
end

return M
