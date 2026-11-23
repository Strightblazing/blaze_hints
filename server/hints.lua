-- Hints: loaded from blaze_hints on start, kept in memory, saved live (the builder calls Hints.Save)
Hints = { list = {}, loaded = false }

--- Steps saved by 1.0.x: the notification step was type 'hint' (now 'message'), and the code source with it
local function upgradeSteps(steps)
    for _, s in ipairs(steps) do
        if s.type == 'hint' then s.type = 'message' end
        if type(s.sources) == 'table' and s.sources.hint ~= nil then
            if s.sources.message == nil then s.sources.message = s.sources.hint end
            s.sources.hint = nil
        end
    end
    return steps
end

local function decodeData(raw)
    local ok, data = pcall(json.decode, raw or '')
    if not ok or type(data) ~= 'table' then data = {} end
    if type(data.steps) ~= 'table' then data.steps = {} end
    upgradeSteps(data.steps)
    return data
end

local function tableExists(name)
    return tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { name })) > 0
end

local function columnExists(tbl, col)
    return tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        { tbl, col })) > 0
end

--- 1.0.x stored "hunts": blaze_hints_hunts and blaze_hints_progress.hunt_id. Move them to the hint names, keeping everything.
local function migrateFromHunts()
    if tableExists('blaze_hints_hunts') and not tableExists('blaze_hints') then
        MySQL.query.await('RENAME TABLE `blaze_hints_hunts` TO `blaze_hints`')
        print('[blaze_hints] renamed table blaze_hints_hunts -> blaze_hints')
    end
    if tableExists('blaze_hints_progress') and columnExists('blaze_hints_progress', 'hunt_id') then
        local fk = MySQL.scalar.await([[
            SELECT CONSTRAINT_NAME FROM information_schema.KEY_COLUMN_USAGE
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'blaze_hints_progress'
              AND COLUMN_NAME = 'hunt_id' AND REFERENCED_TABLE_NAME IS NOT NULL LIMIT 1
        ]])
        if fk then MySQL.query.await(('ALTER TABLE `blaze_hints_progress` DROP FOREIGN KEY `%s`'):format(fk)) end
        MySQL.query.await('ALTER TABLE `blaze_hints_progress` CHANGE `hunt_id` `hint_id` INT NOT NULL')
        pcall(function() MySQL.query.await('ALTER TABLE `blaze_hints_progress` RENAME INDEX `hunt_id` TO `hint_id`') end)
        MySQL.query.await([[
            ALTER TABLE `blaze_hints_progress` ADD CONSTRAINT `blaze_hints_progress_hint`
            FOREIGN KEY (`hint_id`) REFERENCES `blaze_hints` (`id`) ON DELETE CASCADE
        ]])
        print('[blaze_hints] renamed column blaze_hints_progress.hunt_id -> hint_id')
    end
end

local function isTrue(v)
    return v == true or v == 1 or v == '1'
end

--- Every step keeps a stable uid (stash ids, NPC / scene keys), so reordering steps does not lose a stash
local function ensureUids(steps)
    local used = {}
    for _, s in ipairs(steps) do
        if type(s.uid) == 'string' and s.uid ~= '' and not used[s.uid] then used[s.uid] = true else s.uid = nil end
    end
    for i, s in ipairs(steps) do
        if not s.uid then
            local uid = ('s%d'):format(i)
            while used[uid] do uid = ('s%d%d'):format(i, math.random(100, 999)) end
            s.uid = uid
            used[uid] = true
        end
    end
end

local function build(id, name, enabled, data)
    ensureUids(data.steps)
    return {
        id = id,
        name = name,
        enabled = enabled,
        autoStart = data.autoStart ~= false,
        steps = data.steps,
    }
end

function Hints.EnsureTables()
    migrateFromHunts() -- before CREATE, so the old tables are renamed instead of new empty ones being made
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `blaze_hints` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(100) NOT NULL,
            `enabled` TINYINT(1) NOT NULL DEFAULT 1,
            `data` LONGTEXT NOT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `blaze_hints_progress` (
            `citizenid` VARCHAR(50) NOT NULL,
            `hint_id` INT NOT NULL,
            `step_index` INT NOT NULL DEFAULT 1,
            `code` VARCHAR(255) NULL DEFAULT NULL,
            `pieces_found` TEXT NULL,
            `wrong_tries` INT NOT NULL DEFAULT 0,
            `cooldown_until` INT NOT NULL DEFAULT 0,
            `completed` TINYINT(1) NOT NULL DEFAULT 0,
            `unlocked_stash` TINYINT(4) NOT NULL DEFAULT 0,
            `step_started` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`citizenid`, `hint_id`),
            KEY `hint_id` (`hint_id`),
            CONSTRAINT `blaze_hints_progress_hint` FOREIGN KEY (`hint_id`) REFERENCES `blaze_hints` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    -- tables made by 0.1.x: add step_started (timer_after_last_step locks)
    local has = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'blaze_hints_progress' AND COLUMN_NAME = 'step_started'
    ]])
    if tonumber(has) == 0 then
        MySQL.query.await('ALTER TABLE `blaze_hints_progress` ADD COLUMN `step_started` INT NOT NULL DEFAULT 0')
        print('[blaze_hints] added column blaze_hints_progress.step_started')
    end
    -- unlocked_stash holds 0/1/2 now: TINYINT(1) would come back from oxmysql as a boolean
    local colType = MySQL.scalar.await([[
        SELECT COLUMN_TYPE FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'blaze_hints_progress' AND COLUMN_NAME = 'unlocked_stash'
    ]])
    if colType == 'tinyint(1)' then
        MySQL.query.await('ALTER TABLE `blaze_hints_progress` MODIFY `unlocked_stash` TINYINT(4) NOT NULL DEFAULT 0')
    end
end

function Hints.Load()
    local rows = MySQL.query.await('SELECT `id`, `name`, `enabled`, `data` FROM `blaze_hints`') or {}
    local list = {}
    for _, row in ipairs(rows) do
        list[row.id] = build(row.id, row.name, isTrue(row.enabled), decodeData(row.data))
    end
    Hints.list = list
    Hints.loaded = true
    for _, hint in pairs(list) do Stash.RegisterHint(hint) end
    print(('[blaze_hints] loaded %d hint(s)'):format(#rows))
end

function Hints.Get(id)
    return Hints.list[tonumber(id)]
end

function Hints.All()
    return Hints.list
end

--- Create (id = nil) or update a hint. Updates players' progress live.
---@return integer id
function Hints.Save(id, name, enabled, steps, autoStart)
    steps = upgradeSteps(steps or {})
    ensureUids(steps)
    local data = json.encode({ autoStart = autoStart ~= false, steps = steps })
    enabled = enabled ~= false
    id = tonumber(id)
    if id and Hints.list[id] then
        MySQL.update.await('UPDATE `blaze_hints` SET `name` = ?, `enabled` = ?, `data` = ? WHERE `id` = ?',
            { name, enabled and 1 or 0, data, id })
    else
        id = MySQL.insert.await('INSERT INTO `blaze_hints` (`name`, `enabled`, `data`) VALUES (?, ?, ?)',
            { name, enabled and 1 or 0, data })
    end
    Hints.list[id] = build(id, name, enabled, { autoStart = autoStart ~= false, steps = steps })
    Stash.RegisterHint(Hints.list[id])
    Progress.OnHintUpdated(id)
    return id
end

function Hints.SetEnabled(id, enabled)
    local hint = Hints.Get(id)
    if not hint then return false end
    return Hints.Save(hint.id, hint.name, enabled, hint.steps, hint.autoStart) ~= nil
end

function Hints.Delete(id)
    id = tonumber(id)
    if not id or not Hints.list[id] then return false end
    MySQL.update.await('DELETE FROM `blaze_hints` WHERE `id` = ?', { id }) -- progress rows go with it (FK cascade)
    Hints.list[id] = nil
    Progress.OnHintDeleted(id)
    return true
end
