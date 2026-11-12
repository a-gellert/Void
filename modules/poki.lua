local audio = require("modules.audio")

local M = {}

local gameplay_active = false
local last_commercial_time = -999
local COMMERCIAL_COOLDOWN = 140 -- seconds (2-3 minutes strictly between matches)

function M.init()
    if poki_sdk and poki_sdk.init then
        poki_sdk.init()
    end
end

function M.gameplay_start()
    if gameplay_active then return end
    gameplay_active = true
    if poki_sdk and poki_sdk.gameplay_start then
        poki_sdk.gameplay_start()
    end
end

function M.gameplay_stop()
    if not gameplay_active then return end
    gameplay_active = false
    if poki_sdk and poki_sdk.gameplay_stop then
        poki_sdk.gameplay_stop()
    end
end

function M.try_commercial_break(on_done)
    local now = socket.gettime()
    if (now - last_commercial_time) < COMMERCIAL_COOLDOWN then
        if on_done then on_done() end
        return false
    end
    M.gameplay_stop()
    if poki_sdk and poki_sdk.commercial_break then
        audio.set_ad_paused(true)
        poki_sdk.commercial_break(function()
            audio.set_ad_paused(false)
            last_commercial_time = socket.gettime()
            if on_done then on_done() end
        end)
        return true
    end
    if on_done then on_done() end
    return false
end

function M.rewarded_break(on_result)
    M.gameplay_stop()
    if poki_sdk and poki_sdk.rewarded_break then
        audio.set_ad_paused(true)
        poki_sdk.rewarded_break(function(_, rewarded)
            audio.set_ad_paused(false)
            last_commercial_time = socket.gettime()
            if on_result then on_result(rewarded == true) end
        end)
    else
        -- Local dev fallback when Poki SDK is unavailable outside browser
        if on_result then on_result(true) end
    end
end

return M
