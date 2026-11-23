-- Hunts: loaded from blaze_hints_hunts on start, kept in memory, saved live (the builder calls Hunts.Save)
Hunts = { list = {}, loaded = false }

local function decodeData(raw)
    local ok, data = pcall(json.decode, raw or '')
    if not ok or type(data) ~= 'table' then data = {} end
    if type(data.steps) ~= 'table' then data.steps = {} end
    return data
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

function Hunts.EnsureTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `blaze_hints_hunts` (
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
            `hunt_id` INT NOT NULL,
            `step_index` INT NOT NULL DEFAULT 1,
            `code` VARCHAR(255) NULL DEFAULT NULL,
            `pieces_found` TEXT NULL,
            `wrong_tries` INT NOT NULL DEFAULT 0,
            `cooldown_until` INT NOT NULL DEFAULT 0,
            `completed` TINYINT(1) NOT NULL DEFAULT 0,
            `unlocked_stash` TINYINT(4) NOT NULL DEFAULT 0,
            `step_started` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`citizenid`, `hunt_id`),
            KEY `hunt_id` (`hunt_id`),
            CONSTRAINT `blaze_hints_progress_hunt` FOREIGN KEY (`hunt_id`) REFERENCES `blaze_hints_hunts` (`id`) ON DELETE CASCADE
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

function Hunts.Load()
    local rows = MySQL.query.await('SELECT `id`, `name`, `enabled`, `data` FROM `blaze_hints_hunts`') or {}
    local list = {}
    for _, row in ipairs(rows) do
        list[row.id] = build(row.id, row.name, isTrue(row.enabled), decodeData(row.data))
    end
    Hunts.list = list
    Hunts.loaded = true
    for _, hunt in pairs(list) do Stash.RegisterHunt(hunt) end
    print(('[blaze_hints] loaded %d hunt(s)'):format(#rows))
end

function Hunts.Get(id)
    return Hunts.list[tonumber(id)]
end

function Hunts.All()
    return Hunts.list
end

--- Create (id = nil) or update a hunt. Updates players' progress live.
---@return integer id
function Hunts.Save(id, name, enabled, steps, autoStart)
    steps = steps or {}
    ensureUids(steps)
    local data = json.encode({ autoStart = autoStart ~= false, steps = steps })
    enabled = enabled ~= false
    id = tonumber(id)
    if id and Hunts.list[id] then
        MySQL.update.await('UPDATE `blaze_hints_hunts` SET `name` = ?, `enabled` = ?, `data` = ? WHERE `id` = ?',
            { name, enabled and 1 or 0, data, id })
    else
        id = MySQL.insert.await('INSERT INTO `blaze_hints_hunts` (`name`, `enabled`, `data`) VALUES (?, ?, ?)',
            { name, enabled and 1 or 0, data })
    end
    Hunts.list[id] = build(id, name, enabled, { autoStart = autoStart ~= false, steps = steps })
    Stash.RegisterHunt(Hunts.list[id])
    Progress.OnHuntUpdated(id)
    return id
end

function Hunts.SetEnabled(id, enabled)
    local hunt = Hunts.Get(id)
    if not hunt then return false end
    return Hunts.Save(hunt.id, hunt.name, enabled, hunt.steps, hunt.autoStart) ~= nil
end

function Hunts.Delete(id)
    id = tonumber(id)
    if not id or not Hunts.list[id] then return false end
    MySQL.update.await('DELETE FROM `blaze_hints_hunts` WHERE `id` = ?', { id }) -- progress rows go with it (FK cascade)
    Hunts.list[id] = nil
    Progress.OnHuntDeleted(id)
    return true
end
