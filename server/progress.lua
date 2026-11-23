-- Progress: per character (citizenid) state for every hint, plus the step engine.
-- Players[src] = { citizenid, rows = { [hintId] = row }, scenes = { [hintId] = sceneKey }, pendingReceipt = {...} }
Progress = { players = {} }
local Players = Progress.players

local function now() return os.time() end
local vec = Util.Vec

local function debug(...)
    if Config.Debug then print('[blaze_hints]', ...) end
end

local function notify(src, kind, title, description, duration)
    lib.notify(src, {
        title = title,
        description = description,
        type = kind,
        duration = duration or Config.Notify.duration,
        position = Config.Notify.position,
    })
end
Progress.Notify = notify

local function getCitizenId(src)
    local player = exports.qbx_core:GetPlayer(src)
    return player and player.PlayerData and player.PlayerData.citizenid
end

local function distanceTo(src, coords)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not coords then return math.huge end
    return #(GetEntityCoords(ped) - coords)
end

local function isTrue(v) return v == true or v == 1 or v == '1' end

local function decodeJson(raw)
    if type(raw) ~= 'string' or raw == '' then return end
    local ok, t = pcall(json.decode, raw)
    if ok and type(t) == 'table' then return t end
end

local function newRow(citizenid, hintId)
    return {
        citizenid = citizenid, hint_id = hintId, step_index = 1, code = nil, pieces = {},
        wrong_tries = 0, cooldown_until = 0, completed = false, unlocked_stash = 0,
        step_started = now(), token = 0,
    }
end

function Progress.SaveRow(row)
    MySQL.query([[
        INSERT INTO `blaze_hints_progress`
            (`citizenid`, `hint_id`, `step_index`, `code`, `pieces_found`, `wrong_tries`, `cooldown_until`, `completed`, `unlocked_stash`, `step_started`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            `step_index` = VALUES(`step_index`), `code` = VALUES(`code`), `pieces_found` = VALUES(`pieces_found`),
            `wrong_tries` = VALUES(`wrong_tries`), `cooldown_until` = VALUES(`cooldown_until`),
            `completed` = VALUES(`completed`), `unlocked_stash` = VALUES(`unlocked_stash`), `step_started` = VALUES(`step_started`)
    ]], {
        row.citizenid, row.hint_id, row.step_index,
        row.code and json.encode(row.code) or nil,
        json.encode(row.pieces or {}),
        row.wrong_tries, row.cooldown_until,
        row.completed and 1 or 0, row.unlocked_stash or 0, row.step_started or 0,
    })
end

---------------------------------------------------------------------------
-- Where things are
---------------------------------------------------------------------------

--- The NPC step that hosts password step `index` (a password step with no spot of its own right after an NPC step)
local function hostNpc(steps, index)
    local step, prev = steps[index], steps[index - 1]
    if step and step.type == 'password' and not vec(step.coords) and not Util.HasScene(step)
        and prev and prev.type == 'npc' then
        return prev, index - 1
    end
end
Progress.HostNpc = hostNpc

--- The step whose scene step `index` shows: its own, or the scene step right before it (when it has no coords of its own)
local function sceneOwner(steps, index)
    local step = steps[index]
    if not step then return end
    if Util.HasScene(step) then return step, index end
    if step.type == 'stash' then return end -- a stash shows its own scene through Stash.Info
    local prev = steps[index - 1]
    if not vec(step.coords) and prev and prev.type == 'scene' and Util.HasScene(prev) then return prev, index - 1 end
end

--- Where step `index` happens (inspect point, password spot, stash, NPC, scene)
function Progress.SpotFor(steps, index)
    local step = steps[index]
    if not step then return end
    local c = vec(step.coords)
    if c and step.type ~= 'scene' then return c end
    if Util.HasScene(step) then
        if step.type == 'scene' then return vec(Util.SceneCoords(step.scene, step)) end
        return Util.SceneSpot(step.scene, step)
    end
    if c then return c end
    local npc = hostNpc(steps, index)
    if npc then return vec(npc.coords) end
    local prev = steps[index - 1]
    if prev and prev.type == 'scene' and Util.HasScene(prev) then return Util.SceneSpot(prev.scene, prev) end
end

--- The scene a stash sits on: its own, or the scene step right before it. Returns scene step, index.
function Progress.StashSceneOwner(steps, index)
    local step = steps[index]
    if Util.HasScene(step) then return step, index end
    local prev = steps[index - 1]
    if not vec(step.coords) and prev and prev.type == 'scene' and Util.HasScene(prev) then return prev, index - 1 end
end

function Progress.SceneInfo(scene, step)
    local c = Util.SceneCoords(scene, step)
    if not c then return end
    local effects = type(scene.effects) == 'table' and scene.effects or {}
    return {
        preset = scene.preset,
        coords = { x = c.x, y = c.y, z = c.z, w = Util.Heading(c) },
        rearDoors = scene.rearDoors ~= false,
        guards = math.max(0, math.min(4, math.floor(tonumber(scene.guards) or 0))),
        guardMode = scene.guardMode or 'calm',
        guardModel = scene.guardModel,
        visibility = scene.visibility == 'shared' and 'shared' or 'private',
        effects = { smoke = effects.smoke == true, sparks = effects.sparks == true, flare = effects.flare == true },
        searchRadius = tonumber(scene.searchRadius) or 0,
        searchSeconds = tonumber(scene.searchSeconds) or 0,
    }
end

---------------------------------------------------------------------------
-- Client sync (never includes the code)
---------------------------------------------------------------------------

local function sendStep(src, hintId, info)
    TriggerClientEvent('blaze_hints:client:step', src, hintId, info)
end

local function lockedText(step)
    local lock = step.timeLock
    return type(lock) == 'table' and lock.lockedMessage and lock.lockedMessage ~= '' and lock.lockedMessage or Config.Text.nothingHere
end

local function hideWhileLocked(step)
    return type(step.timeLock) == 'table' and step.timeLock.hideWhileLocked == true
end

--- What the client needs to show an NPC: no clue texts (they can carry code pieces)
local function npcInfo(hintId, step, locked)
    local lines = {}
    if locked then
        lines[1] = { text = lockedText(step), replies = {} }
    else
        for i, line in ipairs(type(step.dialog) == 'table' and step.dialog or {}) do
            local replies = {}
            for r, reply in ipairs(type(line.replies) == 'table' and line.replies or {}) do
                replies[r] = { label = tostring(reply.label or ''), action = reply.action or 'end', next = reply.next }
            end
            lines[i] = { id = line.id, text = tostring(line.text or ''), replies = replies }
        end
    end
    local cinematic = step.cinematic
    if cinematic == nil then cinematic = Config.CinematicDialog end
    return {
        key = ('%d:%s'):format(hintId, tostring(step.uid)), -- same key = same ped (kept when the hosted password step starts)
        name = step.name or 'Stranger',
        model = step.model or 'a_m_m_business_01',
        coords = step.coords,
        scenario = step.scenario,
        label = step.label or Config.Text.talk,
        cinematic = cinematic == true,
        locked = locked or nil,
        lines = lines,
    }
end

--- Does this step show a where-to-look marker? (step.marker = true / false, nil = Config.Markers.steps[kind])
function Progress.MarkerOn(step, kind)
    local m = Config.Markers or {}
    if m.enabled == false then return false end
    if step.marker ~= nil then return step.marker == true end
    return (m.steps or {})[kind or step.type] == true
end

local function spotTable(v)
    return v and { x = v.x, y = v.y, z = v.z } or nil
end

local function clientInfo(src, hint, index, step, locked)
    local info = { index = index, total = #hint.steps, type = step.type, hintName = hint.name }
    local hide = locked and hideWhileLocked(step)

    if locked then
        info.locked = true
        info.lockedMessage = lockedText(step)
    end

    if step.type == 'message' then
        info.trigger = step.trigger or 'after_previous'
        info.coords = step.coords
        info.radius = tonumber(step.radius) or 5.0
    elseif step.type == 'password' then
        local host = hostNpc(hint.steps, index)
        if host then
            if not hide then info.npc = npcInfo(hint.id, host, locked) end
        elseif not hide then
            info.coords = spotTable(Progress.SpotFor(hint.steps, index))
        end
        info.label = step.label
        info.inputType = step.inputType or 'keypad'
    elseif step.type == 'npc' then
        if not hide then info.npc = npcInfo(hint.id, step, locked) end
    elseif step.type == 'inspect' then
        if not hide then
            info.coords = spotTable(Progress.SpotFor(hint.steps, index))
            info.label = step.label or Config.Text.inspect
            info.camera = step.camera ~= false
            info.prop = step.prop ~= '' and step.prop or nil
        end
    elseif step.type == 'scene' then
        info.coords = spotTable(Progress.SpotFor(hint.steps, index))
        info.radius = tonumber(step.radius) or 15.0
    end

    -- where-to-look marker: the step's own choice, else the config default for its type (never while locked)
    if not locked then
        local markerType = (step.type == 'password' and hostNpc(hint.steps, index)) and 'npc' or step.type
        info.marker = Progress.MarkerOn(step, markerType)
    end

    -- world scene (not while locked)
    if not locked then
        local owner, ownerIndex = sceneOwner(hint.steps, index)
        if owner then
            local scene = Progress.SceneInfo(owner.scene, owner)
            if scene then
                scene.key = ('scene:%d:%s'):format(hint.id, tostring(owner.uid))
                if scene.visibility == 'shared' then
                    scene.netIds = Scenes.Acquire(src, scene.key, owner.scene, owner)
                end
                info.scene = scene
                info.sceneStep = ownerIndex
            end
        end
    end
    return info
end

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------

--- Returns row, step, hint if the player is still on step `index` (and `token`, when given)
local function current(src, hintId, index, token)
    local state = Players[src]
    local row = state and state.rows[hintId]
    local hint = Hints.Get(hintId)
    if not row or not hint or not hint.enabled or row.completed then return end
    if index and row.step_index ~= index then return end
    if token and row.token ~= token then return end
    local step = hint.steps[row.step_index]
    if not step then return end
    return row, step, hint
end
Progress.Current = current

local function maxTries(step) return math.max(1, math.floor(tonumber(step.wrongTries) or Config.MaxWrongTries)) end
local function cooldownFor(step) return math.max(0, math.floor(tonumber(step.cooldown) or Config.DefaultCooldown)) end
local function resetOnFail(step)
    if step.resetOnFail == nil then return Config.ResetOnFail end
    return step.resetOnFail == true
end

--- Make sure the row holds a code for the upcoming password step (and that it still matches the step's settings)
local function ensureCode(row, steps)
    local p = Codes.NextPassword(steps, row.step_index)
    if not p then
        if row.code then row.code, row.pieces = nil, {} return true end
        return false
    end
    local step, code = steps[p], row.code
    local fixed = Codes.IsFixed(step)
    local inputType = step.inputType or 'keypad'
    local stale = not code or code.step ~= p or (code.input or 'keypad') ~= inputType
        or (fixed and code.value ~= Codes.Normalize(step.code, inputType))
        or (not fixed and code.fixed)
        or (not fixed and inputType == 'keypad' and #code.value ~= Codes.Length(step))
    if not stale then return false end
    row.code = { step = p, value = Codes.ForStep(step), fixed = fixed or nil, input = inputType }
    row.pieces = {}
    debug(('new code for %s hint %s step %d'):format(row.citizenid, row.hint_id, p))
    return true
end

local function piecesFound(row, steps)
    if not row.code then return 0, 0 end
    local slots = Codes.Slots(steps, row.code.step)
    local total = math.min(#slots, #row.code.value)
    local found = {}
    for _, key in ipairs(row.pieces) do found[key] = true end
    local count = 0
    for k = 1, total do
        if found[slots[k].key] then count = count + 1 end
    end
    return count, total
end

--- Reveal the piece step `index` carries as `kind`. Marks it found and sends the "Code piece found X/Y" notify.
---@return string? piece, integer? position, integer? total
local function revealPiece(src, row, hint, index, kind)
    if not row.code then return end
    local piece, k, total, key = Codes.PieceFor(hint.steps, row.code.value, index, kind)
    if not piece then return end
    local known = false
    for _, existing in ipairs(row.pieces) do if existing == key then known = true break end end
    if not known then
        row.pieces[#row.pieces + 1] = key
        Progress.SaveRow(row)
    end
    local found, all = piecesFound(row, hint.steps)
    notify(src, 'success', Config.Text.pieceFound, Config.Text.pieceCount:format(found, all))
    return piece, k, total
end

--- Give a note / receipt item. Falls back to a notify if it does not fit.
local function giveItem(src, item, title, text, hintName)
    local metadata = {
        label = title,
        text = text,
        description = title .. (hintName and (' · ' .. hintName) or ''),
        kind = item == Config.Items.receipt and 'receipt' or 'note',
    }
    local ok = exports.ox_inventory:AddItem(src, item, 1, metadata)
    if not ok then
        notify(src, 'inform', title, text)
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- Step engine
---------------------------------------------------------------------------

local function releaseScene(src, hintId, keep)
    local state = Players[src]
    if not state then return end
    local old = state.scenes[hintId]
    if old and old ~= keep then Scenes.Release(src, old) end
    state.scenes[hintId] = keep
end

--- Back to the start of this stretch (the step after the previous password step) with a new code
local function resetSegment(row, steps)
    row.step_index = Codes.PrevPassword(steps, row.step_index) + 1
    row.code, row.pieces, row.wrong_tries = nil, {}, 0
    row.step_started = now()
    row.comeBackFor = nil
    Progress.SaveRow(row)
end

function Progress.StartStep(src, hintId)
    local state = Players[src]
    local row = state and state.rows[hintId]
    local hint = Hints.Get(hintId)
    if row then row.token = row.token + 1 end

    if not row or not hint or not hint.enabled or row.completed then
        sendStep(src, hintId, nil)
        releaseScene(src, hintId, nil)
        Stash.Sync(src, hintId)
        return
    end

    local steps = hint.steps
    if row.step_index < 1 then row.step_index = 1 end
    if row.step_index > #steps then
        return Progress.Complete(src, hintId)
    end

    if ensureCode(row, steps) then Progress.SaveRow(row) end

    local index, token = row.step_index, row.token
    local step = steps[index]

    -- time lock
    local open, comeBack, expired = TimeLock.Check(step.timeLock, row)
    if expired then
        notify(src, 'error', Config.Text.tooLate, Config.Text.tooLateMsg)
        resetSegment(row, steps)
        return Progress.StartStep(src, hintId)
    end
    row.lockOpen = open
    if not open and comeBack and step.timeLock.comeBack and row.comeBackFor ~= index then
        row.comeBackFor = index
        notify(src, 'inform', Config.Text.comeBack, comeBack)
    end

    debug(('src %d hint %d -> step %d (%s)%s'):format(src, hintId, index, tostring(step.type), open and '' or ' [locked]'))

    if step.type == 'message' then
        releaseScene(src, hintId, nil)
        if not open then sendStep(src, hintId, nil) return Stash.Sync(src, hintId) end -- queued until it opens
        local trigger = step.trigger or 'after_previous'
        if trigger == 'zone' and vec(step.coords) then
            local info = clientInfo(src, hint, index, step, false)
            releaseScene(src, hintId, info.scene and info.scene.visibility == 'shared' and info.scene.key or nil)
            sendStep(src, hintId, info)
        else
            sendStep(src, hintId, nil)
            local delay = trigger == 'delay' and math.max(0, tonumber(step.delay) or 0) * 1000 or 0
            SetTimeout(delay + Config.MessageGap, function()
                if current(src, hintId, index, token) then Progress.DeliverMessage(src, hintId, index) end
            end)
        end
    elseif step.type == 'stash' then
        releaseScene(src, hintId, nil)
        sendStep(src, hintId, nil)
        if open then
            Stash.Unlock(src, row, hint, step)
            return Progress.Advance(src, hintId)
        end
    elseif step.type == 'scene' and not open then
        releaseScene(src, hintId, nil)
        sendStep(src, hintId, nil)
    else
        local info = clientInfo(src, hint, index, step, not open)
        releaseScene(src, hintId, info.scene and info.scene.visibility == 'shared' and info.scene.key or nil)
        if not current(src, hintId, index, token) then return end -- moved on while a shared scene spawned
        sendStep(src, hintId, info)
    end

    Stash.Sync(src, hintId)
end

function Progress.Advance(src, hintId)
    local state = Players[src]
    local row = state and state.rows[hintId]
    if not row then return end
    row.step_index = row.step_index + 1
    row.wrong_tries = 0
    row.step_started = now()
    row.comeBackFor = nil
    Progress.SaveRow(row)
    Progress.StartStep(src, hintId)
end

function Progress.Complete(src, hintId)
    local state = Players[src]
    local row = state and state.rows[hintId]
    if not row then return end
    local hint = Hints.Get(hintId)
    if not row.completed then
        row.completed = true
        row.code, row.pieces = nil, {}
        Progress.SaveRow(row)
        notify(src, 'success', Config.Text.hintComplete, hint and hint.name or nil)
    end
    sendStep(src, hintId, nil)
    releaseScene(src, hintId, nil)
    Stash.Sync(src, hintId)
end

function Progress.DeliverMessage(src, hintId, index)
    local row, step, hint = current(src, hintId, index)
    if not row or step.type ~= 'message' or row.lockOpen == false then return end

    local text = tostring(step.text or '')
    local asNote = step.deliver == 'note'
    if step.piece then
        local piece = revealPiece(src, row, hint, index, asNote and 'note' or 'message')
        if piece then text = Codes.Insert(text, piece) end
    end

    if asNote then
        if giveItem(src, Config.Items.note, step.title or Config.Text.noteTitle, text, hint.name) then
            notify(src, 'inform', step.title or Config.Text.newHint, Config.Text.noteFound, tonumber(step.duration))
        end
    else
        notify(src, 'inform', step.title or Config.Text.newHint, text, tonumber(step.duration))
    end

    Progress.Advance(src, hintId)
end

--- Client says it walked into a hint zone or reached a scene: verify the position, then go on
function Progress.ZoneEntered(src, hintId, index)
    local row, step, hint = current(src, hintId, index)
    if not row or row.lockOpen == false then return end
    if step.type == 'message' and step.trigger == 'zone' then
        local coords = vec(step.coords)
        if not coords or distanceTo(src, coords) > (tonumber(step.radius) or 5.0) + Config.ZoneSlack then return end
        Progress.DeliverMessage(src, hintId, index)
    elseif step.type == 'scene' then
        local coords = Progress.SpotFor(hint.steps, index)
        if not coords or distanceTo(src, coords) > (tonumber(step.radius) or 15.0) + Config.ZoneSlack then return end
        if step.text and step.text ~= '' then notify(src, 'inform', step.title or Config.Text.newHint, step.text) end
        Progress.Advance(src, hintId)
    end
end

---------------------------------------------------------------------------
-- Inspect
---------------------------------------------------------------------------

--- Player inspects the spot: returns what the overlay shows
function Progress.Inspect(src, hintId)
    local row, step, hint = current(src, hintId)
    if not row or step.type ~= 'inspect' then return end
    if row.lockOpen == false then
        notify(src, 'inform', step.label or Config.Text.inspect, lockedText(step))
        return
    end
    local spot = Progress.SpotFor(hint.steps, row.step_index)
    if not spot or distanceTo(src, spot) > Config.InspectDistance then return end

    local caption = tostring(step.text or '')
    local result = {}
    if step.piece then
        local asNote = step.deliver == 'note'
        local piece, k, total = revealPiece(src, row, hint, row.step_index, asNote and 'note' or 'inspect')
        if piece then
            result.pieceN, result.pieceTotal = k, total
            if asNote then
                giveItem(src, Config.Items.note, step.title or Config.Text.noteTitle, Codes.Insert(caption, piece), hint.name)
                caption = (caption ~= '' and (caption:gsub('{piece}', '...') .. '\n') or '') .. Config.Text.noteFound
            else
                caption = Codes.Insert(caption, piece)
            end
        end
    end
    result.caption = caption
    row.inspected = row.token
    return result
end

function Progress.InspectDone(src, hintId)
    local row, step = current(src, hintId)
    if not row or step.type ~= 'inspect' or row.inspected ~= row.token then return end
    Progress.Advance(src, hintId)
end

---------------------------------------------------------------------------
-- Password
---------------------------------------------------------------------------

local function passwordStep(src, hintId)
    local row, step, hint = current(src, hintId)
    if not row or step.type ~= 'password' or not row.code or row.lockOpen == false then return end
    local spot = Progress.SpotFor(hint.steps, row.step_index)
    if spot and distanceTo(src, spot) > Config.PasswordDistance then return end
    return row, step, hint
end

function Progress.OpenPassword(src, hintId)
    local row, step = passwordStep(src, hintId)
    if not row then
        local r2, s2 = current(src, hintId)
        if r2 and s2.type == 'password' and r2.lockOpen == false then
            notify(src, 'inform', s2.label or Config.Text.enterCode, lockedText(s2))
        end
        return
    end
    local left = row.cooldown_until - now()
    if left > 0 then
        notify(src, 'error', Config.Text.wrongCode, Config.Text.cooldown:format(left))
        return
    end
    local inputType = step.inputType or 'keypad'
    return {
        length = #row.code.value,
        triesLeft = maxTries(step) - row.wrong_tries,
        title = step.label or Config.Text.enterCode,
        inputType = inputType,
        tiles = Codes.UsesSource(step, 'scramble') and Codes.Scramble(row.code.value) or nil,
        accent = Config.Accent,
    }
end

function Progress.SubmitCode(src, hintId, input)
    local row, step, hint = passwordStep(src, hintId)
    if not row then return { ok = false, closed = true } end

    local left = row.cooldown_until - now()
    if left > 0 then
        notify(src, 'error', Config.Text.wrongCode, Config.Text.cooldown:format(left))
        return { ok = false, locked = true, triesLeft = 0 }
    end

    if Codes.Match(input, row.code.value, step.inputType) then
        local index, token = row.step_index, row.token
        row.code, row.pieces, row.wrong_tries = nil, {}, 0
        Progress.SaveRow(row)
        -- let the keypad show OPEN before the step changes
        SetTimeout(1200, function()
            if current(src, hintId, index, token) then Progress.Advance(src, hintId) end
        end)
        return { ok = true }
    end

    row.wrong_tries = row.wrong_tries + 1
    local max = maxTries(step)

    if row.wrong_tries < max then
        Progress.SaveRow(row)
        notify(src, 'error', Config.Text.wrongCode, Config.Text.triesLeft:format(max - row.wrong_tries))
        return { ok = false, triesLeft = max - row.wrong_tries }
    end

    local cd = cooldownFor(step)
    row.wrong_tries = 0
    row.cooldown_until = now() + cd

    if resetOnFail(step) then
        resetSegment(row, hint.steps)
        notify(src, 'error', Config.Text.wrongCode, Config.Text.lockedReset)
        SetTimeout(1500, function()
            if Players[src] and Players[src].rows[hintId] == row then Progress.StartStep(src, hintId) end
        end)
        return { ok = false, locked = true, reset = true, triesLeft = 0 }
    end

    Progress.SaveRow(row)
    notify(src, 'error', Config.Text.wrongCode, Config.Text.lockedOut:format(cd))
    return { ok = false, locked = true, triesLeft = 0 }
end

---------------------------------------------------------------------------
-- NPC replies (next_line is handled on the client; everything else comes here)
---------------------------------------------------------------------------

--- Returns what the client should do: { line = text } (keep talking), { close = true },
--- { openPassword = true } or { shop = id }
function Progress.NpcReply(src, hintId, lineIndex, replyIndex)
    local row, step, hint = current(src, hintId)
    if not row or row.lockOpen == false then return { close = true } end

    local npc, npcIndex, hosted = step, row.step_index, false
    if step.type ~= 'npc' then
        npc, npcIndex = hostNpc(hint.steps, row.step_index)
        hosted = true
        if not npc then return { close = true } end
    end

    local coords = vec(npc.coords)
    if coords and distanceTo(src, coords) > Config.NpcDistance then return { close = true } end

    local line = type(npc.dialog) == 'table' and npc.dialog[lineIndex]
    local reply = line and type(line.replies) == 'table' and line.replies[replyIndex]
    if not reply then return { close = true } end

    local action = reply.action or 'end'
    local finishes = reply.complete == true and not hosted

    if action == 'give_clue' then
        local clue = tostring(reply.clue or '')
        if reply.piece then
            local piece = revealPiece(src, row, hint, npcIndex, 'npc')
            if piece then clue = Codes.Insert(clue, piece) end
        end
        if clue ~= '' then notify(src, 'inform', Config.Text.newHint, clue) end
        if not hosted and reply.complete ~= false then Progress.Advance(src, hintId) end
        return { line = clue ~= '' and clue or nil, close = clue == '' }
    elseif action == 'open_password' then
        if hosted then return { openPassword = true } end
        local nextStep = hint.steps[row.step_index + 1]
        if not nextStep or nextStep.type ~= 'password' then
            print(('[blaze_hints] hint %d step %d: open_password but the next step is not a password step'):format(hintId, row.step_index))
            return { close = true }
        end
        Progress.Advance(src, hintId) -- the password step is now current (hosted by this NPC when it has no spot)
        return { openPassword = true }
    elseif action == 'open_shop' then
        local shop = reply.shop ~= '' and reply.shop or npc.shop or Config.Shop.defaultId
        if not shop or shop == '' then
            notify(src, 'warning', Config.Text.shopClosed, Config.Text.shopClosedMsg)
            return { close = true }
        end
        if reply.receipt and row.code then
            Players[src].pendingReceipt = {
                hintId = hintId, index = npcIndex, shop = tostring(shop),
                expires = now() + (Config.Shop.receiptMinutes or 10) * 60,
                complete = finishes,
            }
        elseif finishes then
            Progress.Advance(src, hintId)
        end
        return { shop = shop }
    end

    -- 'end' (and anything unknown)
    if finishes then Progress.Advance(src, hintId) end
    return { close = true }
end

--- A purchase happened (ox_inventory buyItem hook or the lation_shops hook): hand out a waiting receipt piece
function Progress.OnPurchase(src, shopId)
    local state = Players[src]
    local p = state and state.pendingReceipt
    if not p or tostring(shopId) ~= p.shop then return end
    state.pendingReceipt = nil
    if now() > p.expires then return end
    local row = state.rows[p.hintId]
    local hint = Hints.Get(p.hintId)
    if not row or not hint or row.completed or not row.code then return end
    local piece = revealPiece(src, row, hint, p.index, 'receipt')
    if piece then
        local text = Codes.Insert('Thank you for your purchase!\nScribbled on the back:', piece)
        giveItem(src, Config.Items.receipt, Config.Text.receiptTitle, text, hint.name)
        notify(src, 'inform', Config.Text.newHint, Config.Text.receiptFound)
    end
    if p.complete and row.step_index == p.index then Progress.Advance(src, p.hintId) end
end

---------------------------------------------------------------------------
-- Load / unload / sync
---------------------------------------------------------------------------

--- Start any enabled auto-start hints this character has no row for, then (re)send every step
function Progress.SyncAll(src)
    local state = Players[src]
    if not state then return end
    for id, hint in pairs(Hints.All()) do
        if hint.enabled and hint.autoStart and not state.rows[id] then
            local row = newRow(state.citizenid, id)
            state.rows[id] = row
            Progress.SaveRow(row)
        end
    end
    for id in pairs(state.rows) do
        Progress.StartStep(src, id)
    end
end

local function normalizePieces(list)
    local out = {}
    for _, v in ipairs(type(list) == 'table' and list or {}) do
        out[#out + 1] = type(v) == 'number' and ('%d:message'):format(v) or (tostring(v):gsub(':hint$', ':message')) -- 1.0.x keys
    end
    return out
end

function Progress.Load(src)
    local citizenid = getCitizenId(src)
    if not citizenid then return end
    while not Hints.loaded do Wait(200) end

    local existing = Players[src]
    if existing and existing.citizenid == citizenid then
        return Progress.SyncAll(src)
    end
    if existing then Progress.Unload(src) end

    local state = { citizenid = citizenid, rows = {}, scenes = {} }
    Players[src] = state

    local rows = MySQL.query.await('SELECT * FROM `blaze_hints_progress` WHERE `citizenid` = ?', { citizenid }) or {}
    if Players[src] ~= state then return end -- dropped or switched while loading

    for _, r in ipairs(rows) do
        state.rows[r.hint_id] = {
            citizenid = citizenid,
            hint_id = r.hint_id,
            step_index = r.step_index,
            code = decodeJson(r.code),
            pieces = normalizePieces(decodeJson(r.pieces_found)),
            wrong_tries = r.wrong_tries or 0,
            cooldown_until = r.cooldown_until or 0,
            completed = isTrue(r.completed),
            unlocked_stash = tonumber(r.unlocked_stash) or (isTrue(r.unlocked_stash) and 1 or 0),
            step_started = tonumber(r.step_started) or 0,
            token = 0,
        }
    end
    debug(('loaded %d progress row(s) for %s'):format(#rows, citizenid))
    Progress.SyncAll(src)
end

function Progress.Unload(src)
    Scenes.ReleaseAll(src)
    Players[src] = nil -- pending timers check Players[src] / row tokens and stop on their own
end

function Progress.OnHintUpdated(hintId)
    for src, state in pairs(Players) do
        local hint = Hints.Get(hintId)
        if hint and hint.enabled and hint.autoStart and not state.rows[hintId] then
            state.rows[hintId] = newRow(state.citizenid, hintId)
            Progress.SaveRow(state.rows[hintId])
        end
        if state.rows[hintId] then Progress.StartStep(src, hintId) end
    end
end

function Progress.OnHintDeleted(hintId)
    for src, state in pairs(Players) do
        if state.rows[hintId] then
            state.rows[hintId] = nil
            sendStep(src, hintId, nil)
            releaseScene(src, hintId, nil)
            TriggerClientEvent('blaze_hints:client:stash', src, hintId, nil)
        end
    end
end

--- Admin reset of one character's progress (online player by server id)
function Progress.Reset(src, hintId)
    local state = Players[src]
    if not state then return false end
    MySQL.update.await('DELETE FROM `blaze_hints_progress` WHERE `citizenid` = ? AND `hint_id` = ?', { state.citizenid, hintId })
    if state.rows[hintId] then state.rows[hintId].token = state.rows[hintId].token + 1 end
    state.rows[hintId] = nil
    sendStep(src, hintId, nil)
    releaseScene(src, hintId, nil)
    TriggerClientEvent('blaze_hints:client:stash', src, hintId, nil)
    Progress.SyncAll(src)
    return true
end

--- Server id of an online character (nil if offline)
function Progress.FindSrc(citizenid)
    for src, state in pairs(Players) do
        if state.citizenid == citizenid then return src end
    end
end

--- Put an online character on step `step` of a hint (new code for that stretch)
function Progress.SetStep(src, hintId, step)
    local state = Players[src]
    local hint = Hints.Get(hintId)
    if not state or not hint then return false end
    local row = state.rows[hintId] or newRow(state.citizenid, hintId)
    state.rows[hintId] = row
    row.token = row.token + 1
    row.step_index = math.max(1, math.min(step, #hint.steps))
    row.completed = false
    row.code, row.pieces, row.wrong_tries, row.cooldown_until = nil, {}, 0, 0
    row.step_started = now()
    row.comeBackFor = nil
    Progress.SaveRow(row)
    Progress.StartStep(src, hintId)
    return true
end

--- Everyone's progress on a hint was wiped: online players start it again (if it auto-starts)
function Progress.ForgetHint(hintId)
    for src, state in pairs(Players) do
        if state.rows[hintId] then
            state.rows[hintId].token = state.rows[hintId].token + 1
            state.rows[hintId] = nil
            sendStep(src, hintId, nil)
            releaseScene(src, hintId, nil)
            TriggerClientEvent('blaze_hints:client:stash', src, hintId, nil)
            Progress.SyncAll(src)
        end
    end
end

--- How many online characters are on each hint (not finished)
function Progress.OnlineCounts()
    local counts = {}
    for _, state in pairs(Players) do
        for hintId, row in pairs(state.rows) do
            if not row.completed then counts[hintId] = (counts[hintId] or 0) + 1 end
        end
    end
    return counts
end

--- Code pieces this character has found (only their own pieces, never the full code unless they found them all)
function Progress.Notes(src)
    local state = Players[src]
    if not state then return {} end
    local notes = {}
    for hintId, row in pairs(state.rows) do
        local hint = Hints.Get(hintId)
        if hint and hint.enabled and not row.completed then
            local entry = { hint = hint.name, step = row.step_index, steps = #hint.steps, pieces = {} }
            if row.code then
                local found = {}
                for _, key in ipairs(row.pieces) do found[key] = true end
                local slots = Codes.Slots(hint.steps, row.code.step)
                local pieces = Codes.Split(row.code.value, #slots)
                for k, slot in ipairs(slots) do
                    if pieces[k] and found[slot.key] then
                        entry.pieces[#entry.pieces + 1] = { n = k, total = #pieces, value = pieces[k] }
                    end
                end
            end
            notes[#notes + 1] = entry
        end
    end
    return notes
end

---------------------------------------------------------------------------
-- Time lock watcher: re-starts steps whose lock opened, closed or ran out
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(math.max(5, Config.TimeLockCheck or 20) * 1000)
        for src, state in pairs(Players) do
            for hintId, row in pairs(state.rows) do
                local hint = Hints.Get(hintId)
                local step = hint and hint.enabled and not row.completed and hint.steps[row.step_index]
                if step and TimeLock.Mode(step.timeLock) ~= 'off' then
                    local open, _, expired = TimeLock.Check(step.timeLock, row)
                    if expired or open ~= row.lockOpen then
                        Progress.StartStep(src, hintId)
                    end
                end
            end
        end
    end
end)
