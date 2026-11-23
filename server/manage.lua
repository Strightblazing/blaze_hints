-- Manage hints (admins, /hintmanage): overview with player counts, each player's progress, set step / reset,
-- enable, duplicate, reset everyone, delete, and clean-up. Every callback checks the admin group / ace here.

local function json_copy(t) return json.decode(json.encode(t)) end

local function overview()
    local counts = MySQL.query.await([[
        SELECT `hint_id`, COUNT(*) AS started, SUM(`completed`) AS done
        FROM `blaze_hints_progress` GROUP BY `hint_id`
    ]]) or {}
    local by = {}
    for _, r in ipairs(counts) do by[r.hint_id] = r end
    local online = Progress.OnlineCounts()
    local list = {}
    for id, h in pairs(Hints.All()) do
        local c = by[id] or {}
        list[#list + 1] = {
            id = id, name = h.name, enabled = h.enabled, autoStart = h.autoStart, steps = #h.steps,
            started = tonumber(c.started) or 0, done = tonumber(c.done) or 0, online = online[id] or 0,
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function charName(charinfo)
    local ok, c = pcall(json.decode, charinfo or '')
    if ok and type(c) == 'table' and c.firstname then return ('%s %s'):format(c.firstname, c.lastname or '') end
end

local function players(id)
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT p.`citizenid`, p.`step_index`, p.`completed`, p.`unlocked_stash`, pl.`charinfo`
        FROM `blaze_hints_progress` p LEFT JOIN `players` pl ON pl.`citizenid` = p.`citizenid`
        WHERE p.`hint_id` = ? ORDER BY p.`completed` ASC, p.`step_index` DESC LIMIT 100
    ]], { id })
    if not ok then -- no qbx players table: ids only
        rows = MySQL.query.await([[
            SELECT `citizenid`, `step_index`, `completed`, `unlocked_stash` FROM `blaze_hints_progress`
            WHERE `hint_id` = ? ORDER BY `completed` ASC, `step_index` DESC LIMIT 100
        ]], { id }) or {}
    end
    local list = {}
    for _, r in ipairs(rows or {}) do
        list[#list + 1] = {
            citizenid = r.citizenid,
            name = charName(r.charinfo),
            step = r.step_index,
            completed = r.completed == true or r.completed == 1,
            stash = tonumber(r.unlocked_stash) or 0,
            online = Progress.FindSrc(r.citizenid) ~= nil,
        }
    end
    return list
end

local function log(src, text)
    print(('[blaze_hints] %s %s'):format(GetPlayerName(src) or ('id ' .. src), text))
end

local function register(name, fn)
    lib.callback.register('blaze_hints:manage:' .. name, function(src, ...)
        if not IsHintAdmin(src) then return end
        return fn(src, ...)
    end)
end

register('overview', function() return overview() end)

register('players', function(_, id)
    local hint = Hints.Get(id)
    if not hint then return end
    return { steps = #hint.steps, list = players(hint.id) }
end)

register('setStep', function(src, id, citizenid, step)
    local hint = Hints.Get(id)
    step = math.floor(tonumber(step) or 0)
    if not hint or type(citizenid) ~= 'string' or step < 1 or step > #hint.steps then return false end
    local target = Progress.FindSrc(citizenid)
    if target then
        Progress.SetStep(target, hint.id, step)
    else
        MySQL.query.await([[
            INSERT INTO `blaze_hints_progress` (`citizenid`, `hint_id`, `step_index`, `pieces_found`, `step_started`)
            VALUES (?, ?, ?, '[]', UNIX_TIMESTAMP())
            ON DUPLICATE KEY UPDATE `step_index` = VALUES(`step_index`), `completed` = 0, `code` = NULL,
                `pieces_found` = '[]', `wrong_tries` = 0, `cooldown_until` = 0, `step_started` = UNIX_TIMESTAMP()
        ]], { citizenid, hint.id, step })
    end
    log(src, ('put %s on step %d of hint #%d'):format(citizenid, step, hint.id))
    return true
end)

register('resetPlayer', function(src, id, citizenid)
    local hint = Hints.Get(id)
    if not hint or type(citizenid) ~= 'string' then return false end
    local target = Progress.FindSrc(citizenid)
    if target then
        Progress.Reset(target, hint.id)
    else
        MySQL.update.await('DELETE FROM `blaze_hints_progress` WHERE `citizenid` = ? AND `hint_id` = ?', { citizenid, hint.id })
    end
    log(src, ('reset %s on hint #%d'):format(citizenid, hint.id))
    return true
end)

register('resetAll', function(src, id)
    local hint = Hints.Get(id)
    if not hint then return false end
    local n = MySQL.update.await('DELETE FROM `blaze_hints_progress` WHERE `hint_id` = ?', { hint.id }) or 0
    Progress.ForgetHint(hint.id)
    log(src, ('reset everyone (%d) on hint #%d'):format(n, hint.id))
    return n
end)

register('toggle', function(src, id)
    local hint = Hints.Get(id)
    if not hint then return end
    Hints.SetEnabled(hint.id, not hint.enabled)
    log(src, ('%s hint #%d'):format(Hints.Get(hint.id).enabled and 'enabled' or 'disabled', hint.id))
    return Hints.Get(hint.id).enabled
end)

register('duplicate', function(src, id)
    local hint = Hints.Get(id)
    if not hint then return end
    local steps = json_copy(hint.steps)
    for _, s in ipairs(steps) do s.uid = nil end -- new stash ids for the copy
    local newId = Hints.Save(nil, (hint.name .. ' (copy)'):sub(1, 100), false, steps, hint.autoStart)
    log(src, ('duplicated hint #%d as #%d (disabled)'):format(hint.id, newId))
    return newId
end)

register('delete', function(src, id)
    local hint = Hints.Get(id)
    if not hint or not Hints.Delete(hint.id) then return false end
    log(src, ('deleted hint #%d "%s"'):format(hint.id, hint.name))
    return true
end)

-- Clean-up: every hint whose name starts with "Demo " (made by /hintdemo, /hintdemonpc, /hintdemofull)
register('cleanDemos', function(src)
    local ids = {}
    for id, h in pairs(Hints.All()) do
        if type(h.name) == 'string' and h.name:match('^Demo ') then ids[#ids + 1] = id end
    end
    for _, id in ipairs(ids) do Hints.Delete(id) end
    log(src, ('deleted %d demo hint(s)'):format(#ids))
    return #ids
end)

-- Clean-up: progress of characters that no longer exist (deleted in multichar)
register('cleanOrphans', function(src)
    local ok, n = pcall(MySQL.update.await, [[
        DELETE p FROM `blaze_hints_progress` p
        LEFT JOIN `players` pl ON pl.`citizenid` = p.`citizenid`
        WHERE pl.`citizenid` IS NULL
    ]])
    if not ok then return -1 end
    log(src, ('removed %d progress row(s) of deleted characters'):format(n or 0))
    return n or 0
end)
