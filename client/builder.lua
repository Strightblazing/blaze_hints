-- Builder: build hunts in game (admins). Two styles (Config.BuilderStyle, or '/huntbuilder menu|nui'):
--   nui  = the full builder screen (web/), with Place here / Preview / Save
--   menu = ox_lib context menus + input dialogs, Lation UI look when lation_ui is running (Config.UseLationUI)
-- Every save / delete is checked against the admin group on the server; this file only edits a draft.
Builder = {}

local previewing  -- { ped, sceneKey, token }
local previewToken = 0
local resumeNui = false

local function round(n, d) local m = 10 ^ (d or 2) return math.floor(n * m + 0.5) / m end

--- Where the admin stands (the "Place here" coords)
local function here()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    return { x = round(c.x), y = round(c.y), z = round(c.z), w = round(GetEntityHeading(ped), 1) }
end

local function fetchHunts()
    return lib.callback.await('blaze_hints:builder:hunts', false) or {}
end

local function notify(kind, title, text)
    lib.notify({ title = title, description = text, type = kind })
end

local function presetList()
    local list = {}
    for id, p in pairs(Config.ScenePresets) do list[#list + 1] = { value = id, label = p.label or id } end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

---------------------------------------------------------------------------
-- Preview (both styles): plays one step locally, nothing goes to the server
---------------------------------------------------------------------------

local function previewScene(step)
    local scene = step.scene
    if type(scene) ~= 'table' or not Config.ScenePresets[scene.preset] then return end
    local c = Util.SceneCoords(scene, step) or here()
    local fx = type(scene.effects) == 'table' and scene.effects or {}
    return Scenes.Use({
        key = 'preview:' .. previewToken,
        preset = scene.preset,
        coords = { x = c.x, y = c.y, z = c.z, w = Util.Heading(c) },
        rearDoors = scene.rearDoors ~= false,
        guards = math.max(0, math.min(4, math.floor(tonumber(scene.guards) or 0))),
        guardMode = scene.guardMode == 'hostile' and 'calm' or (scene.guardMode or 'calm'), -- no shooting the admin in a preview
        guardModel = scene.guardModel,
        visibility = 'private',
        effects = { smoke = fx.smoke == true, sparks = fx.sparks == true, flare = fx.flare == true },
        searchRadius = tonumber(scene.searchRadius) or 0,
        searchSeconds = 0,
    })
end

function Builder.StopPreview()
    local p = previewing
    previewing = nil
    previewToken = previewToken + 1
    if not p then return end
    if p.ped and DoesEntityExist(p.ped) then DeleteEntity(p.ped) end
    if p.sceneKey then Scenes.Release(p.sceneKey) end
end

--- Preview one step. onDone runs when it ends (reopens the builder).
function Builder.Preview(step, onDone)
    Builder.StopPreview()
    local p = {}
    previewing = p
    local token = previewToken
    local function finish()
        if previewing ~= p then return end
        Builder.StopPreview()
        if onDone then onDone() end
    end
    local function finishIn(seconds)
        SetTimeout(seconds * 1000, function() if previewToken == token then finish() end end)
    end

    p.sceneKey = previewScene(step)
    local t = step.type
    local text = tostring(step.text or ''):gsub('{piece}', '??')

    if t == 'hint' then
        notify('inform', step.title or Config.Text.newHint, text ~= '' and text or '(no text)')
        finishIn(p.sceneKey and 20 or 3)
    elseif t == 'npc' then
        local info = {
            name = step.name or 'Stranger', model = step.model or 'a_m_m_business_01', scenario = step.scenario,
            coords = Util.Vec(step.coords) and step.coords or here(),
            cinematic = step.cinematic == nil and Config.CinematicDialog or step.cinematic == true,
            shop = step.shop,
            lines = {},
        }
        for i, line in ipairs(type(step.dialog) == 'table' and step.dialog or {}) do
            info.lines[i] = { id = line.id, text = tostring(line.text or ''), replies = type(line.replies) == 'table' and line.replies or {} }
        end
        if #info.lines == 0 then
            notify('error', 'Preview', 'This NPC has no dialog lines yet.')
            return finish()
        end
        CreateThread(function()
            local ped = Steps.CreateNpcPed(info)
            if previewing ~= p or not ped then if ped then DeleteEntity(ped) end return finish() end
            p.ped = ped
            Wait(300)
            Dialog.Open(-1, info, ped, { onClose = function(after)
                if after == 'password' then notify('inform', 'Preview', 'This reply opens the next password step.') end
                finish()
            end })
        end)
    elseif t == 'password' then
        local length = tonumber(step.length) or 4
        if step.codeMode == 'fixed' and step.code and step.code ~= '' then length = #tostring(step.code) end
        local tiles
        if type(step.sources) == 'table' and step.sources.scramble then
            tiles = {}
            for i = 1, length do tiles[i] = step.inputType == 'word' and string.char(64 + math.random(1, 26)) or tostring(math.random(0, 9)) end
        end
        Hints.PreviewPassword({
            length = length, triesLeft = tonumber(step.wrongTries) or Config.MaxWrongTries,
            title = (step.label or Config.Text.enterCode) .. ' (preview: any code that long opens)',
            inputType = step.inputType or 'keypad', tiles = tiles,
        }, finish)
    elseif t == 'inspect' then
        local spot = Util.Vec(step.coords) or (Util.HasScene(step) and Util.SceneSpot(step.scene, step)) or GetEntityCoords(PlayerPedId())
        Inspect.Show(nil, {
            caption = text ~= '' and text or '(no caption)',
            pieceN = step.piece and 1 or nil, pieceTotal = step.piece and 3 or nil,
        }, spot, { preview = finish, camera = step.camera ~= false })
    elseif t == 'scene' then
        if not p.sceneKey then notify('error', 'Preview', 'Pick a scene preset first.') return finish() end
        notify('inform', 'Preview', 'Showing the scene for 30 seconds.')
        finishIn(30)
    elseif t == 'stash' then
        local rewards = {}
        for _, r in ipairs(type(step.rewards) == 'table' and step.rewards or {}) do rewards[#rewards + 1] = ('%s x%s'):format(r.name, r.count or 1) end
        notify('inform', step.label or Config.Stash.label, ('%s · %s slots · rewards: %s'):format(
            step.mode == 'reward' and 'One-time reward box' or 'Permanent storage', step.slots or Config.Stash.slots,
            #rewards > 0 and table.concat(rewards, ', ') or 'none'))
        finishIn(p.sceneKey and 20 or 3)
    else
        finish()
    end
end

---------------------------------------------------------------------------
-- NUI builder
---------------------------------------------------------------------------

local function openNui(resume)
    if Hints.nuiOpen and Hints.nuiOpen ~= 'builder' then return end
    Hints.OpenNui('builder', {
        hunts = fetchHunts(),
        resume = resume,
        presets = presetList(),
        cinematicDefault = Config.CinematicDialog,
        defaults = {
            wrongTries = Config.MaxWrongTries, cooldown = Config.DefaultCooldown,
            slots = Config.Stash.slots, maxWeight = Config.Stash.maxWeight,
        },
    })
end

function Builder.Closed()
    -- the page keeps its draft: /huntbuilder brings it back as it was
end

RegisterNUICallback('builderPlace', function(_, cb) cb(here()) end)

RegisterNUICallback('builderSave', function(data, cb)
    local res = lib.callback.await('blaze_hints:builder:save', false, data and data.hunt)
    if res then notify('success', 'Hunt saved', ('#%d is live now.'):format(res.id)) else notify('error', 'Hunt not saved', 'Not allowed or invalid data.') end
    cb(res or false)
end)

RegisterNUICallback('builderDelete', function(data, cb)
    local res = lib.callback.await('blaze_hints:builder:delete', false, data and data.id)
    if res then notify('success', 'Hunt deleted', '') end
    cb(res or false)
end)

RegisterNUICallback('builderResetMe', function(data, cb)
    local ok = lib.callback.await('blaze_hints:builder:resetMe', false, data and data.id)
    notify(ok and 'success' or 'error', 'Your progress', ok and 'Reset. The hunt starts again for you.' or 'Save the hunt first.')
    cb(ok or false)
end)

RegisterNUICallback('builderHide', function(_, cb)
    cb(1)
    Hints.CloseNui()
    notify('inform', 'Builder hidden', ('Walk around, then /%s to bring it back as it was.'):format(Config.BuilderCommand))
end)

RegisterNUICallback('builderPreview', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or type(data.step) ~= 'table' then return end
    Hints.CloseNui()
    Wait(100)
    Builder.Preview(data.step, function() Wait(300) openNui(true) end)
end)

---------------------------------------------------------------------------
-- Menu builder (ox_lib, or Lation UI when it is running)
---------------------------------------------------------------------------

local UI = {}
local useLation = false

local function detectLation()
    useLation = Config.UseLationUI and GetResourceState('lation_ui') == 'started'
end

function UI.menu(data)
    if useLation then
        exports.lation_ui:registerMenu(data)
        return exports.lation_ui:showMenu(data.id)
    end
    local menu = { id = data.id, title = data.title, menu = data.menu, onBack = data.onBack, options = {} }
    for i, o in ipairs(data.options) do
        menu.options[i] = { title = o.title, description = o.description, icon = o.icon, disabled = o.disabled,
            readOnly = o.readOnly, arrow = o.arrow, onSelect = o.onSelect }
    end
    lib.registerContext(menu)
    lib.showContext(data.id)
end

--- fields: { type, label, description, default, checked, options = { {value,label} }, min, max }
function UI.input(title, fields)
    local rows = {}
    for i, f in ipairs(fields) do
        local r = { type = f.type, label = f.label, description = f.description, default = f.default, options = f.options, min = f.min, max = f.max }
        if f.type == 'checkbox' then
            r.checked = f.checked == true
            r.default = useLation and r.checked or nil
        elseif f.type == 'textarea' and not useLation then
            r.autosize = true
        end
        if useLation and f.type == 'select' then r.searchable = false end
        rows[i] = r
    end
    local values
    if useLation then
        values = exports.lation_ui:input({ title = title, options = rows, cancel = true })
    else
        values = lib.inputDialog(title, rows, { allowCancel = true })
    end
    return values
end

function UI.confirm(header, content)
    if useLation then
        return exports.lation_ui:alert({ header = header, content = content, type = 'warning', cancel = true }) == 'confirm'
    end
    return lib.alertDialog({ header = header, content = content, centered = true, cancel = true }) == 'confirm'
end

local Menu = {}

local function opt(list) local o = {} for _, v in ipairs(list) do o[#o + 1] = { value = v[1], label = v[2] } end return o end

local TYPE_LABEL = { hint = 'Hint', inspect = 'Inspect spot', npc = 'NPC', password = 'Password', scene = 'World scene', stash = 'Personal stash' }
local TYPES = opt({ { 'hint', 'Hint' }, { 'inspect', 'Inspect spot' }, { 'npc', 'NPC' }, { 'password', 'Password' }, { 'scene', 'World scene' }, { 'stash', 'Personal stash' } })
local TYPE_ICON = { hint = 'lightbulb', inspect = 'magnifying-glass', npc = 'user', password = 'keyboard', scene = 'truck', stash = 'box-open' }

local function cinematicShow(v) return v == true and 'cinematic' or (v == false and 'classic' or 'default') end
local function cinematicParse(v) if v == 'cinematic' then return true elseif v == 'classic' then return false end end
local function numOrText(v) if v == nil or v == '' then return nil end return tonumber(v) or v end
local function daysShow(v) return type(v) == 'table' and table.concat(v, ',') or '' end
local function daysParse(v)
    local out = {}
    for d in tostring(v or ''):gmatch('%d') do out[#out + 1] = tonumber(d) end
    return out
end

local MARKER = { key = 'marker', type = 'select', label = 'Where-to-look marker',
    description = 'A floating ? over the spot, only for the hunter on this step',
    show = function(v) return v == true and 'on' or (v == false and 'off' or 'default') end,
    parse = function(v) if v == 'on' then return true elseif v == 'off' then return false end end,
    options = opt({ { 'default', 'Config default' }, { 'on', 'Show a marker' }, { 'off', 'No marker' } }) }

local FIELDS = {
    hint = {
        { key = 'title', type = 'input', label = 'Title', description = 'Empty = "New hint"' },
        { key = 'text', type = 'textarea', label = 'Text', description = '{piece} = where the code piece goes' },
        { key = 'trigger', type = 'select', label = 'Trigger', default = 'after_previous',
          options = opt({ { 'after_previous', 'After the previous step' }, { 'delay', 'After a delay' }, { 'zone', 'On entering a zone (Place here)' } }) },
        { key = 'delay', type = 'number', label = 'Delay (seconds)', min = 0 },
        { key = 'radius', type = 'number', label = 'Zone radius (m)', min = 1 },
        { key = 'piece', type = 'checkbox', label = 'Carries a code piece' },
        { key = 'deliver', type = 'select', label = 'Deliver as', default = 'notify',
          options = opt({ { 'notify', 'Notification' }, { 'note', 'Note item (blaze_note)' } }) },
        { key = 'duration', type = 'number', label = 'Notification time (ms)', min = 1000 },
    },
    inspect = {
        { key = 'label', type = 'input', label = 'Target label', description = 'Empty = "Inspect"' },
        { key = 'text', type = 'textarea', label = 'Caption', description = '{piece} = where the code piece goes' },
        { key = 'piece', type = 'checkbox', label = 'Carries a code piece' },
        { key = 'deliver', type = 'select', label = 'Deliver as', default = 'overlay',
          options = opt({ { 'overlay', 'Inspect overlay' }, { 'note', 'Note item (blaze_note)' } }) },
        { key = 'camera', type = 'checkbox', label = 'Cinematic close-up camera', default = true },
        { key = 'prop', type = 'input', label = 'Prop model (optional)', description = 'e.g. prop_cs_envelope_01' },
        MARKER,
    },
    npc = {
        { key = 'name', type = 'input', label = 'Name' },
        { key = 'model', type = 'input', label = 'Ped model', default = 'a_m_m_business_01' },
        { key = 'scenario', type = 'input', label = 'Scenario (optional)', description = 'e.g. WORLD_HUMAN_SMOKING' },
        { key = 'label', type = 'input', label = 'Target label', description = 'Empty = "Talk"' },
        { key = 'cinematic', type = 'select', label = 'Dialog style', show = cinematicShow, parse = cinematicParse,
          options = opt({ { 'default', 'Config default' }, { 'cinematic', 'Cinematic' }, { 'classic', 'Classic panel' } }) },
        { key = 'shop', type = 'input', label = 'Shop id (open_shop replies)' },
        MARKER,
    },
    password = {
        { key = 'label', type = 'input', label = 'Target / screen title', description = 'Empty = "Enter code"' },
        { key = 'inputType', type = 'select', label = 'Input', default = 'keypad',
          options = opt({ { 'keypad', 'Keypad (digits)' }, { 'word', 'Word (letter tiles)' } }) },
        MARKER,
    },
    scene = {
        { key = 'title', type = 'input', label = 'Arrival title' },
        { key = 'text', type = 'textarea', label = 'Arrival text (optional)' },
        { key = 'radius', type = 'number', label = 'Arrival radius (m)', min = 2, default = 15 },
    },
    stash = {
        { key = 'label', type = 'input', label = 'Label', default = Config.Stash.label },
        { key = 'slots', type = 'number', label = 'Slots', min = 1, default = Config.Stash.slots },
        { key = 'maxWeight', type = 'number', label = 'Max weight (g)', min = 1000, default = Config.Stash.maxWeight },
        { key = 'mode', type = 'select', label = 'Mode', default = 'permanent',
          options = opt({ { 'permanent', 'Permanent personal storage' }, { 'reward', 'One-time reward box' } }) },
        { key = 'showWhileLocked', type = 'checkbox', label = 'Show it (locked) during the hunt', default = true },
        { key = 'unlockText', type = 'input', label = 'Unlock message (optional)' },
        MARKER,
    },
    code = {
        { key = 'codeMode', type = 'select', label = 'Code', default = 'random',
          options = opt({ { 'random', 'Random per player' }, { 'fixed', 'Fixed' } }) },
        { key = 'code', type = 'input', label = 'Fixed code / word' },
        { key = 'length', type = 'number', label = 'Length', min = 1, max = 12, default = 4 },
        { key = 'wrongTries', type = 'number', label = 'Wrong tries', min = 1, default = Config.MaxWrongTries },
        { key = 'cooldown', type = 'number', label = 'Cooldown (seconds)', min = 0, default = Config.DefaultCooldown },
        { key = 'resetOnFail', type = 'checkbox', label = 'Reset the hunt with a new code after the lockout', default = Config.ResetOnFail },
    },
    timeLock = {
        { key = 'mode', type = 'select', label = 'Mode', default = 'off',
          options = opt({ { 'off', 'Off' }, { 'ingame_hours', 'In-game hours' }, { 'real_time', 'Real time (days + hours)' },
                          { 'date_window', 'Date window' }, { 'timer_after_last_step', 'Timer after the last step' } }) },
        { key = 'opens', type = 'input', label = 'Opens', description = 'Hours: 22 or 22.5 · Date window: 2026-12-24 18:00', parse = numOrText },
        { key = 'closes', type = 'input', label = 'Closes', description = 'Hours: 4 (wraps past midnight) · Date window: 2026-12-26 00:00', parse = numOrText },
        { key = 'days', type = 'input', label = 'Days (real time)', description = '1 = Mon ... 7 = Sun, e.g. 5,6,7. Empty = every day', show = daysShow, parse = daysParse },
        { key = 'seconds', type = 'number', label = 'Timer (seconds)', min = 0 },
        { key = 'timerMode', type = 'select', label = 'Timer', default = 'wait',
          options = opt({ { 'wait', 'Wait: opens after the timer' }, { 'expire', 'Expire: too late after the timer (hunt goes back)' } }) },
        { key = 'lockedMessage', type = 'input', label = 'Locked message', description = 'NPC line / inspect text while locked' },
        { key = 'hideWhileLocked', type = 'checkbox', label = 'Hide NPC / spot while locked' },
        { key = 'comeBack', type = 'checkbox', label = 'Send a "come back at X" hint' },
    },
    scene_settings = {
        { key = 'preset', type = 'select', label = 'Preset', default = '' },
        { key = 'rearDoors', type = 'checkbox', label = 'Rear doors open (armored van)', default = true },
        { key = 'guards', type = 'number', label = 'Guards (0-4)', min = 0, max = 4, default = 0 },
        { key = 'guardMode', type = 'select', label = 'Guards', default = 'calm',
          options = opt({ { 'calm', 'Calm' }, { 'hostile', 'Hostile' }, { 'dressing', 'Set dressing' } }) },
        { key = 'visibility', type = 'select', label = 'Who sees it', default = 'private',
          options = opt({ { 'private', 'Only the hunter (private)' }, { 'shared', 'Everyone (shared)' } }) },
        { key = 'searchRadius', type = 'number', label = 'Search area blip radius (0 = none)', min = 0, default = 0 },
        { key = 'searchSeconds', type = 'number', label = 'Search blip time (s, 0 = while on the step)', min = 0, default = 0 },
    },
}

local SOURCES = { { 'hint', 'Hint pieces' }, { 'note', 'Note item' }, { 'inspect', 'Inspect spot' }, { 'npc', 'NPC riddle' }, { 'receipt', 'Shop receipt' }, { 'scramble', 'Scramble (shows the letters)' } }
local EFFECTS = { { 'smoke', 'Smoke' }, { 'sparks', 'Sparks' }, { 'flare', 'Flare' } }

--- Edit fields of obj with one input dialog. Returns true when saved.
local function editFields(title, obj, fields)
    local rows = {}
    for i, f in ipairs(fields) do
        local v = obj[f.key]
        if f.show then v = f.show(v) end
        local r = { type = f.type, label = f.label, description = f.description, options = f.options, min = f.min, max = f.max }
        if f.type == 'checkbox' then
            r.checked = v == true or (v == nil and f.default == true)
        elseif f.type == 'number' then
            r.default = tonumber(v) or f.default
        else
            if v ~= nil and v ~= '' then r.default = tostring(v) else r.default = f.default end
        end
        rows[i] = r
    end
    local values = UI.input(title, rows)
    if not values then return false end
    for i, f in ipairs(fields) do
        local v = values[i]
        if f.type == 'checkbox' then v = v == true
        elseif f.type == 'number' then v = tonumber(v)
        elseif f.parse then v = f.parse(v)
        elseif v == '' then v = nil end
        obj[f.key] = v
    end
    return true
end

local function checkboxes(title, tbl, list)
    local rows = {}
    for i, s in ipairs(list) do rows[i] = { type = 'checkbox', label = s[2], checked = tbl[s[1]] == true } end
    local values = UI.input(title, rows)
    if not values then return false end
    for i, s in ipairs(list) do tbl[s[1]] = values[i] == true end
    return true
end

local function summary(step)
    if step.type == 'hint' then return (step.trigger or 'after_previous') .. (step.piece and ' · piece' or '') end
    if step.type == 'npc' then return (step.name or 'Stranger') .. (Util.Vec(step.coords) and '' or ' · not placed') end
    if step.type == 'password' then return (step.inputType or 'keypad') .. ' · ' .. (step.codeMode or 'random') end
    if step.type == 'scene' then return type(step.scene) == 'table' and step.scene.preset or 'no preset' end
    if step.type == 'stash' then return step.mode or 'permanent' end
    return step.label or ''
end

function Menu.Open()
    detectLation()
    local hunts = fetchHunts()
    local options = {}
    for _, h in ipairs(hunts) do
        options[#options + 1] = {
            title = ('#%d %s'):format(h.id, h.name), icon = 'map',
            description = ('%d steps · %s'):format(#h.steps, h.enabled and 'enabled' or 'disabled'),
            arrow = true, onSelect = function() Menu.Hunt(h) end,
        }
    end
    options[#options + 1] = { title = 'New hunt', icon = 'plus', onSelect = function()
        Menu.Hunt({ name = 'New hunt', enabled = true, autoStart = true, steps = {} })
    end }
    options[#options + 1] = { title = 'Open the builder screen', icon = 'table-columns', onSelect = function() openNui(false) end }
    UI.menu({ id = 'bh_main', title = 'Hunt builder', options = options })
end

function Menu.Hunt(h)
    UI.menu({
        id = 'bh_hunt', title = h.id and ('#%d %s'):format(h.id, h.name) or h.name, menu = 'bh_main',
        onBack = function() Menu.Open() end,
        options = {
            { title = 'Name and settings', icon = 'pen', description = ('%s · %s'):format(h.enabled and 'enabled' or 'disabled', h.autoStart and 'auto start' or 'no auto start'),
              onSelect = function()
                  editFields('Hunt', h, {
                      { key = 'name', type = 'input', label = 'Name' },
                      { key = 'enabled', type = 'checkbox', label = 'Enabled' },
                      { key = 'autoStart', type = 'checkbox', label = 'Starts for every character' },
                  })
                  Menu.Hunt(h)
              end },
            { title = ('Steps (%d)'):format(#h.steps), icon = 'list-ol', arrow = true, onSelect = function() Menu.Steps(h) end },
            { title = 'Add step', icon = 'plus', onSelect = function()
                local v = UI.input('Add step', { { type = 'select', label = 'Type', options = TYPES, default = 'hint' } })
                if v and v[1] then
                    h.steps[#h.steps + 1] = { type = v[1], uid = ('b%d%d'):format(GetGameTimer() % 100000, math.random(10, 99)) }
                    return Menu.Step(h, #h.steps)
                end
                Menu.Hunt(h)
            end },
            { title = 'Save hunt', icon = 'floppy-disk', description = 'Goes live for everyone right away', onSelect = function()
                local res = lib.callback.await('blaze_hints:builder:save', false, h)
                if res then
                    h.id = res.id
                    notify('success', 'Hunt saved', ('#%d is live now.'):format(res.id))
                else
                    notify('error', 'Hunt not saved', 'Not allowed or invalid data.')
                end
                Menu.Hunt(h)
            end },
            { title = 'Reset my progress', icon = 'rotate-left', disabled = not h.id, onSelect = function()
                local ok = lib.callback.await('blaze_hints:builder:resetMe', false, h.id)
                notify(ok and 'success' or 'error', 'Your progress', ok and 'Reset.' or 'Could not reset.')
                Menu.Hunt(h)
            end },
            { title = 'Delete hunt', icon = 'trash', disabled = not h.id, onSelect = function()
                if UI.confirm('Delete hunt', ('Delete "%s" and everyone\'s progress on it?'):format(h.name)) then
                    lib.callback.await('blaze_hints:builder:delete', false, h.id)
                    return Menu.Open()
                end
                Menu.Hunt(h)
            end },
        },
    })
end

function Menu.Steps(h)
    local options = {}
    for i, s in ipairs(h.steps) do
        options[#options + 1] = {
            title = ('%d. %s'):format(i, TYPE_LABEL[s.type] or s.type), icon = TYPE_ICON[s.type],
            description = summary(s), arrow = true, onSelect = function() Menu.Step(h, i) end,
        }
    end
    if #options == 0 then options[1] = { title = 'No steps yet', readOnly = true } end
    UI.menu({ id = 'bh_steps', title = 'Steps', menu = 'bh_hunt', onBack = function() Menu.Hunt(h) end, options = options })
end

function Menu.Step(h, i)
    local s = h.steps[i]
    if not s then return Menu.Steps(h) end
    local back = function() Menu.Step(h, i) end
    local options = {
        { title = 'Settings', icon = 'sliders', onSelect = function()
            editFields(('%d. %s'):format(i, TYPE_LABEL[s.type]), s, FIELDS[s.type])
            back()
        end },
        { title = 'Place here', icon = 'location-crosshairs',
          description = Util.Vec(s.coords) and ('%.1f, %.1f, %.1f'):format(s.coords.x, s.coords.y, s.coords.z) or 'Not placed',
          onSelect = function() s.coords = here() notify('success', 'Placed', 'Uses your position and heading.') back() end },
    }
    if s.type == 'password' then
        options[#options + 1] = { title = 'Code', icon = 'hashtag', onSelect = function()
            editFields('Code', s, FIELDS.code)
            back()
        end }
        options[#options + 1] = { title = 'Code sources', icon = 'puzzle-piece', onSelect = function()
            s.sources = type(s.sources) == 'table' and s.sources or {}
            checkboxes('Code sources', s.sources, SOURCES)
            back()
        end }
    elseif s.type == 'npc' then
        options[#options + 1] = { title = 'Dialog', icon = 'comments', arrow = true, onSelect = function() Menu.Dialog(h, i) end }
    elseif s.type == 'stash' then
        options[#options + 1] = { title = 'Rewards', icon = 'gift', onSelect = function()
            local lines = {}
            for _, r in ipairs(type(s.rewards) == 'table' and s.rewards or {}) do lines[#lines + 1] = ('%s:%s'):format(r.name, r.count or 1) end
            local v = UI.input('Rewards', { { type = 'textarea', label = 'One per line: item:count', default = table.concat(lines, '\n') } })
            if v then
                s.rewards = {}
                for line in tostring(v[1] or ''):gmatch('[^\r\n]+') do
                    local name, count = line:match('^%s*([%w_%-]+)%s*:?%s*(%d*)')
                    if name then s.rewards[#s.rewards + 1] = { name = name, count = tonumber(count) or 1 } end
                end
            end
            back()
        end }
    end
    options[#options + 1] = { title = 'Time lock', icon = 'clock', description = type(s.timeLock) == 'table' and s.timeLock.mode or 'off',
        onSelect = function()
            s.timeLock = type(s.timeLock) == 'table' and s.timeLock or {}
            editFields('Time lock', s.timeLock, FIELDS.timeLock)
            back()
        end }
    options[#options + 1] = { title = 'World scene', icon = 'truck', description = type(s.scene) == 'table' and s.scene.preset or 'none',
        onSelect = function()
            s.scene = type(s.scene) == 'table' and s.scene or {}
            local fields = {}
            for k, f in ipairs(FIELDS.scene_settings) do fields[k] = f end
            local presets = { { value = '', label = 'None' } }
            for _, p in ipairs(presetList()) do presets[#presets + 1] = p end
            fields[1] = { key = 'preset', type = 'select', label = 'Preset', options = presets, default = '' }
            editFields('World scene', s.scene, fields)
            if not s.scene.preset or s.scene.preset == '' then s.scene = nil return back() end
            s.scene.effects = type(s.scene.effects) == 'table' and s.scene.effects or {}
            checkboxes('Scene effects', s.scene.effects, EFFECTS)
            back()
        end }
    if type(s.scene) == 'table' then
        options[#options + 1] = { title = 'Place scene here', icon = 'location-dot', onSelect = function()
            s.scene.coords = here() notify('success', 'Scene placed', 'Uses your position and heading.') back()
        end }
    end
    options[#options + 1] = { title = 'Preview', icon = 'eye', onSelect = function() Builder.Preview(s, back) end }
    options[#options + 1] = { title = 'Move up', icon = 'arrow-up', disabled = i == 1, onSelect = function()
        h.steps[i], h.steps[i - 1] = h.steps[i - 1], h.steps[i] Menu.Step(h, i - 1) end }
    options[#options + 1] = { title = 'Move down', icon = 'arrow-down', disabled = i == #h.steps, onSelect = function()
        h.steps[i], h.steps[i + 1] = h.steps[i + 1], h.steps[i] Menu.Step(h, i + 1) end }
    options[#options + 1] = { title = 'Delete step', icon = 'trash', onSelect = function()
        if UI.confirm('Delete step', ('Delete step %d (%s)?'):format(i, TYPE_LABEL[s.type])) then
            table.remove(h.steps, i)
            return Menu.Steps(h)
        end
        back()
    end }
    UI.menu({ id = 'bh_step', title = ('%d. %s'):format(i, TYPE_LABEL[s.type] or s.type), menu = 'bh_steps',
        onBack = function() Menu.Steps(h) end, options = options })
end

local REPLY_ACTIONS = opt({ { 'next_line', 'Next line' }, { 'give_clue', 'Give clue' }, { 'open_password', 'Open password' }, { 'open_shop', 'Open shop' }, { 'end', 'End' } })

function Menu.Dialog(h, i)
    local s = h.steps[i]
    s.dialog = type(s.dialog) == 'table' and s.dialog or {}
    local options = {}
    for l, line in ipairs(s.dialog) do
        options[#options + 1] = {
            title = ('Line %d%s'):format(l, line.id and (' · ' .. line.id) or ''), icon = 'comment',
            description = tostring(line.text or ''):sub(1, 80), arrow = true, onSelect = function() Menu.Line(h, i, l) end,
        }
    end
    options[#options + 1] = { title = 'Add line', icon = 'plus', onSelect = function()
        s.dialog[#s.dialog + 1] = { id = ('line%d'):format(#s.dialog + 1), text = '', replies = {} }
        Menu.Line(h, i, #s.dialog)
    end }
    UI.menu({ id = 'bh_dialog', title = 'Dialog', menu = 'bh_step', onBack = function() Menu.Step(h, i) end, options = options })
end

function Menu.Line(h, i, l)
    local line = h.steps[i].dialog[l]
    if not line then return Menu.Dialog(h, i) end
    line.replies = type(line.replies) == 'table' and line.replies or {}
    local back = function() Menu.Line(h, i, l) end
    local options = {
        { title = 'Edit line', icon = 'pen', description = tostring(line.text or ''):sub(1, 80), onSelect = function()
            editFields('Line', line, {
                { key = 'id', type = 'input', label = 'Line id', description = 'Used by "next line" replies' },
                { key = 'text', type = 'textarea', label = 'What the NPC says' },
            })
            back()
        end },
    }
    for r, reply in ipairs(line.replies) do
        options[#options + 1] = { title = ('%d. %s'):format(r, reply.label or '...'), icon = 'reply',
            description = reply.action or 'end', onSelect = function()
                editFields('Reply', reply, {
                    { key = 'label', type = 'input', label = 'Reply text' },
                    { key = 'action', type = 'select', label = 'Action', options = REPLY_ACTIONS, default = 'end' },
                    { key = 'next', type = 'input', label = 'Next line id (next line)' },
                    { key = 'clue', type = 'textarea', label = 'Clue text (give clue)', description = '{piece} = code piece (NPC riddle)' },
                    { key = 'piece', type = 'checkbox', label = 'Clue carries a code piece (NPC riddle)' },
                    { key = 'shop', type = 'input', label = 'Shop id (open shop)' },
                    { key = 'receipt', type = 'checkbox', label = 'Purchase gives a receipt with a code piece' },
                    { key = 'complete', type = 'checkbox', label = 'Finishes this step', description = 'give clue finishes unless off' },
                    { key = '_delete', type = 'checkbox', label = 'Delete this reply' },
                })
                if reply._delete then table.remove(line.replies, r) else reply._delete = nil end
                back()
            end }
    end
    options[#options + 1] = { title = 'Add reply', icon = 'plus', disabled = #line.replies >= 4, onSelect = function()
        line.replies[#line.replies + 1] = { label = 'Reply', action = 'end' }
        back()
    end }
    options[#options + 1] = { title = 'Remove last reply', icon = 'minus', disabled = #line.replies == 0, onSelect = function()
        table.remove(line.replies)
        back()
    end }
    options[#options + 1] = { title = 'Delete line', icon = 'trash', onSelect = function()
        table.remove(h.steps[i].dialog, l)
        Menu.Dialog(h, i)
    end }
    UI.menu({ id = 'bh_line', title = ('Line %d'):format(l), menu = 'bh_dialog', onBack = function() Menu.Dialog(h, i) end, options = options })
end

---------------------------------------------------------------------------
-- Open (the server checks the admin group before sending this)
---------------------------------------------------------------------------

RegisterNetEvent('blaze_hints:client:openBuilder', function(style)
    if style == 'menu' then return Menu.Open() end
    openNui(true)
end)
