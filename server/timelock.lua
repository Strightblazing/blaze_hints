-- Time locks: server-side checks only.
-- step.timeLock = {
--   mode = 'off' | 'ingame_hours' | 'real_time' | 'date_window' | 'timer_after_last_step',
--   opens, closes,          -- hours 0-24 (decimals ok, 22.5 = 22:30) for ingame_hours / real_time,
--                           -- 'YYYY-MM-DD HH:MM' for date_window (either one can be empty)
--   days = { 1..7 },        -- real_time: 1 = Monday ... 7 = Sunday (empty = every day)
--   seconds, timerMode,     -- timer_after_last_step: 'wait' (opens after) | 'expire' (closes after, then the hunt goes back)
--   lockedMessage,          -- NPC line / inspect text while locked
--   hideWhileLocked,        -- NPC / inspect / password spot hidden while locked (else they show the locked message)
--   comeBack,               -- send a "come back at X" hint when the step is locked
-- }
TimeLock = {}

local DAY_NAMES = { 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun' }
local source, warned

local function detect()
    local want = Config.TimeSync or 'auto'
    if want == 'real' then return 'real' end
    if (want == 'auto' or want == 'renewed') and GetResourceState('Renewed-Weathersync') == 'started' then return 'renewed' end
    if (want == 'auto' or want == 'qb') and GetResourceState('qb-weathersync') == 'started' then return 'qb' end
    return nil
end

--- In-game hour as a decimal (14.5 = 14:30), read from the weather/time sync resource
function TimeLock.GameHour()
    source = source or detect()
    if source == 'renewed' then
        local t = GlobalState.currentTime
        if type(t) == 'table' and t.hour then return t.hour + (t.minute or 0) / 60 end
    elseif source == 'qb' then
        local ok, h, m = pcall(function() return exports['qb-weathersync']:getTime() end)
        if ok and tonumber(h) then return tonumber(h) + (tonumber(m) or 0) / 60 end
    end
    if not warned and source ~= 'real' then
        warned = true
        print('^3[blaze_hints]^7 no weather/time sync resource found (Renewed-Weathersync or qb-weathersync): in-game time locks use the real clock')
    end
    local t = TimeLock.RealDate()
    return t.hour + t.min / 60
end

--- Real date table (server clock, or Config.TimeZone as a UTC offset)
function TimeLock.RealDate()
    if type(Config.TimeZone) == 'number' then
        return os.date('!*t', os.time() + math.floor(Config.TimeZone * 3600))
    end
    return os.date('*t')
end

local function weekday(t) -- 1 = Monday ... 7 = Sunday
    return (t.wday + 5) % 7 + 1
end

local function within(cur, opens, closes)
    opens, closes = tonumber(opens), tonumber(closes)
    if not opens or not closes or opens == closes then return true end
    if opens < closes then return cur >= opens and cur < closes end
    return cur >= opens or cur < closes -- wraps past midnight
end

local function hhmm(h)
    h = tonumber(h) or 0
    return ('%02d:%02d'):format(math.floor(h) % 24, math.floor((h % 1) * 60 + 0.5))
end

local function dateString(t)
    return ('%04d-%02d-%02d %02d:%02d'):format(t.year, t.month, t.day, t.hour, t.min)
end

function TimeLock.Mode(lock)
    if type(lock) ~= 'table' then return 'off' end
    return lock.mode or 'off'
end

--- Is a step open right now?
---@return boolean open
---@return string? comeBack text for a "come back" hint
---@return boolean? expired (timer_after_last_step in expire mode ran out)
function TimeLock.Check(lock, row)
    local mode = TimeLock.Mode(lock)
    if mode == 'off' then return true end

    if mode == 'ingame_hours' then
        local open = within(TimeLock.GameHour(), lock.opens, lock.closes)
        return open, ('Come back between %s and %s (in-game time).'):format(hhmm(lock.opens), hhmm(lock.closes))
    end

    if mode == 'real_time' then
        local t = TimeLock.RealDate()
        local dayOk = true
        local names = {}
        if type(lock.days) == 'table' and #lock.days > 0 then
            dayOk = false
            local today = weekday(t)
            for _, d in ipairs(lock.days) do
                d = tonumber(d)
                if d == today then dayOk = true end
                if DAY_NAMES[d] then names[#names + 1] = DAY_NAMES[d] end
            end
        end
        local open = dayOk and within(t.hour + t.min / 60, lock.opens, lock.closes)
        local text = 'Come back'
        if #names > 0 then text = text .. ' on ' .. table.concat(names, ', ') end
        if tonumber(lock.opens) and tonumber(lock.closes) and tonumber(lock.opens) ~= tonumber(lock.closes) then
            text = ('%s between %s and %s'):format(text, hhmm(lock.opens), hhmm(lock.closes))
        end
        return open, text .. '.'
    end

    if mode == 'date_window' then
        local now = dateString(TimeLock.RealDate())
        local opens = type(lock.opens) == 'string' and lock.opens ~= '' and lock.opens or nil
        local closes = type(lock.closes) == 'string' and lock.closes ~= '' and lock.closes or nil
        if opens and now < opens then return false, ('Come back after %s.'):format(opens) end
        if closes and now >= closes then return false, 'This closed for good.' end
        return true
    end

    if mode == 'timer_after_last_step' then
        local seconds = math.max(0, tonumber(lock.seconds) or 0)
        local elapsed = os.time() - (row and row.step_started or os.time())
        if lock.timerMode == 'expire' then
            if elapsed < seconds then return true end
            return false, nil, true
        end
        if elapsed >= seconds then return true end
        local left = seconds - elapsed
        return false, left >= 120 and ('Come back in %d minutes.'):format(math.ceil(left / 60))
            or ('Come back in %d seconds.'):format(left)
    end

    return true
end
