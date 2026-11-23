-- blaze_hints server: startup, client events/callbacks, shop hooks, builder events, admin commands

--- Admin check used by every admin command and every builder event / callback
function IsHuntAdmin(src)
    if src == 0 then return true end -- server console
    if IsPlayerAceAllowed(src, ('group.%s'):format(Config.AdminGroup)) then return true end
    local ok, allowed = pcall(function() return exports.qbx_core:HasPermission(src, Config.AdminGroup) end)
    return ok and allowed == true
end

CreateThread(function()
    Hunts.EnsureTables()
    Hunts.Load()
end)

---------------------------------------------------------------------------
-- Player lifecycle (the client says when it is ready, so a restart re-syncs everyone)
---------------------------------------------------------------------------

RegisterNetEvent('blaze_hints:server:ready', function()
    Progress.Load(source)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    Progress.Unload(src or source)
end)

AddEventHandler('playerDropped', function()
    Progress.Unload(source)
end)

---------------------------------------------------------------------------
-- Step events (validated in Progress / Stash)
---------------------------------------------------------------------------

RegisterNetEvent('blaze_hints:server:zoneEnter', function(huntId, index)
    if type(huntId) ~= 'number' or type(index) ~= 'number' then return end
    Progress.ZoneEntered(source, huntId, index)
end)

RegisterNetEvent('blaze_hints:server:inspectDone', function(huntId)
    if type(huntId) ~= 'number' then return end
    Progress.InspectDone(source, huntId)
end)

RegisterNetEvent('blaze_hints:server:openStash', function(huntId)
    if type(huntId) ~= 'number' then return end
    Stash.Open(source, huntId)
end)

lib.callback.register('blaze_hints:openPassword', function(src, huntId)
    if type(huntId) ~= 'number' then return end
    return Progress.OpenPassword(src, huntId)
end)

lib.callback.register('blaze_hints:submitCode', function(src, huntId, input)
    if type(huntId) ~= 'number' or type(input) ~= 'string' then return { ok = false, closed = true } end
    return Progress.SubmitCode(src, huntId, input)
end)

lib.callback.register('blaze_hints:npcReply', function(src, huntId, lineIndex, replyIndex)
    if type(huntId) ~= 'number' or type(lineIndex) ~= 'number' or type(replyIndex) ~= 'number' then return { close = true } end
    return Progress.NpcReply(src, huntId, lineIndex, replyIndex)
end)

lib.callback.register('blaze_hints:inspect', function(src, huntId)
    if type(huntId) ~= 'number' then return end
    return Progress.Inspect(src, huntId)
end)

lib.callback.register('blaze_hints:notes', function(src)
    return Progress.Notes(src)
end)

---------------------------------------------------------------------------
-- Shop purchases (receipt code pieces)
---------------------------------------------------------------------------

-- ox_inventory shops
CreateThread(function()
    while GetResourceState('ox_inventory') ~= 'started' do Wait(1000) end
    exports.ox_inventory:registerHook('buyItem', function(payload)
        local src, shopType = payload.source, payload.shopType
        SetTimeout(0, function() Progress.OnPurchase(src, shopType) end)
        return true
    end, {})
end)

-- Lation Shops: its OnItemPurchased hook (lation_shops/server/utils/hooks.lua) fires this server-only event
-- (AddEventHandler, not RegisterNetEvent: clients cannot trigger it)
AddEventHandler('blaze_hints:shopPurchase', function(src, shopId)
    if type(src) ~= 'number' then return end
    Progress.OnPurchase(src, shopId)
end)

---------------------------------------------------------------------------
-- Builder (every event checks the admin group / ace here)
---------------------------------------------------------------------------

local STEP_TYPES = { hint = true, inspect = true, npc = true, password = true, scene = true, stash = true }

local function clean(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == 'string' then return v:sub(1, 2000) end
    if t == 'number' then return (v == v and v ~= math.huge and v ~= -math.huge) and v or 0 end
    if t == 'boolean' then return v end
    if t == 'table' and depth < 8 then
        local out, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 300 then break end
            if type(k) == 'string' or type(k) == 'number' then out[k] = clean(val, depth + 1) end
        end
        return out
    end
end

local function sanitizeHunt(data)
    if type(data) ~= 'table' then return end
    local name = type(data.name) == 'string' and data.name:sub(1, 100) or ''
    if name == '' then name = 'Unnamed hunt' end
    local steps = {}
    for _, s in ipairs(type(data.steps) == 'table' and data.steps or {}) do
        if #steps >= 100 then break end
        if type(s) == 'table' and STEP_TYPES[s.type] then
            steps[#steps + 1] = clean(s)
        end
    end
    return {
        id = tonumber(data.id),
        name = name,
        enabled = data.enabled ~= false,
        autoStart = data.autoStart ~= false,
        steps = steps,
    }
end

local function huntList()
    local list = {}
    for id, hunt in pairs(Hunts.All()) do
        list[#list + 1] = { id = id, name = hunt.name, enabled = hunt.enabled, autoStart = hunt.autoStart, steps = hunt.steps }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

lib.callback.register('blaze_hints:builder:hunts', function(src)
    if not IsHuntAdmin(src) then return end
    return huntList()
end)

lib.callback.register('blaze_hints:builder:save', function(src, data)
    if not IsHuntAdmin(src) then return end
    local hunt = sanitizeHunt(data)
    if not hunt then return end
    if hunt.id and not Hunts.Get(hunt.id) then hunt.id = nil end
    local id = Hunts.Save(hunt.id, hunt.name, hunt.enabled, hunt.steps, hunt.autoStart)
    print(('[blaze_hints] %s saved hunt #%d "%s" (%d steps)'):format(GetPlayerName(src) or src, id, hunt.name, #hunt.steps))
    return { id = id, hunts = huntList() }
end)

lib.callback.register('blaze_hints:builder:delete', function(src, id)
    if not IsHuntAdmin(src) then return end
    id = tonumber(id)
    if not id or not Hunts.Delete(id) then return end
    print(('[blaze_hints] %s deleted hunt #%d'):format(GetPlayerName(src) or src, id))
    return { hunts = huntList() }
end)

lib.callback.register('blaze_hints:builder:resetMe', function(src, id)
    if not IsHuntAdmin(src) then return end
    id = tonumber(id)
    return id and Hunts.Get(id) and Progress.Reset(src, id) or false
end)

---------------------------------------------------------------------------
-- Admin commands (permission checked here, not only by ace)
---------------------------------------------------------------------------

local function reply(src, kind, text)
    if src == 0 then print('[blaze_hints] ' .. text) return end
    Progress.Notify(src, kind, 'Hunts', text)
end

local function adminCommand(name, handler)
    RegisterCommand(name, function(src, args)
        if not IsHuntAdmin(src) then
            if src ~= 0 then reply(src, 'error', 'You are not allowed to use this.') end
            return
        end
        handler(src, args)
    end, false)
end

-- /huntbuilder [menu|nui]
adminCommand(Config.BuilderCommand, function(src, args)
    if src == 0 then return reply(src, 'error', 'Run this in game') end
    local style = (args[1] == 'menu' or args[1] == 'nui') and args[1] or Config.BuilderStyle
    TriggerClientEvent('blaze_hints:client:openBuilder', src, style)
end)

adminCommand('huntlist', function(src)
    local any = false
    for id, hunt in pairs(Hunts.All()) do
        any = true
        reply(src, 'inform', ('#%d %s (%d steps, %s)'):format(id, hunt.name, #hunt.steps, hunt.enabled and 'enabled' or 'disabled'))
    end
    if not any then reply(src, 'inform', ('No hunts yet. Try /%s or /huntdemofull'):format(Config.BuilderCommand)) end
end)

-- /huntreset <huntId> [serverId]
adminCommand('huntreset', function(src, args)
    local huntId, target = tonumber(args[1]), tonumber(args[2]) or src
    if not huntId or not Hunts.Get(huntId) then return reply(src, 'error', 'Usage: /huntreset <huntId> [serverId]') end
    if target == 0 then return reply(src, 'error', 'Give a server id from the console') end
    if Progress.Reset(target, huntId) then
        reply(src, 'success', ('Hunt #%d reset for %d'):format(huntId, target))
    else
        reply(src, 'error', 'That player is not loaded')
    end
end)

-- /hunttoggle <huntId>
adminCommand('hunttoggle', function(src, args)
    local hunt = Hunts.Get(args[1])
    if not hunt then return reply(src, 'error', 'Usage: /hunttoggle <huntId>') end
    Hunts.SetEnabled(hunt.id, not hunt.enabled)
    reply(src, 'success', ('Hunt #%d is now %s'):format(hunt.id, Hunts.Get(hunt.id).enabled and 'enabled' or 'disabled'))
end)

-- /huntdelete <huntId>
adminCommand('huntdelete', function(src, args)
    local id = tonumber(args[1])
    if not id or not Hunts.Delete(id) then return reply(src, 'error', 'Usage: /huntdelete <huntId>') end
    reply(src, 'success', ('Hunt #%d deleted'):format(id))
end)

---------------------------------------------------------------------------
-- Demo hunts (quick tests around the admin)
---------------------------------------------------------------------------

local function around(src)
    local ped = GetPlayerPed(src)
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local base = { x = c.x, y = c.y, z = c.z, w = h }
    --- right / forward metres from where the admin stands; face = heading offset
    return function(right, forward, face)
        local p = Util.Offset(base, right, forward, 0.0)
        return { x = p.x, y = p.y, z = p.z, w = (h + (face or 0.0)) % 360.0 }
    end, base
end

-- /huntdemo: hints with pieces + a keypad 1.5 m in front of you
adminCommand('huntdemo', function(src)
    if src == 0 then return reply(src, 'error', 'Run this in game') end
    local at, base = around(src)
    local id = Hunts.Save(nil, 'Demo hunt', true, {
        { type = 'hint', trigger = 'after_previous', piece = true,
          text = 'Someone slipped a note in your pocket: "It starts with {piece}."' },
        { type = 'hint', trigger = 'delay', delay = 20, piece = true,
          text = 'A text from an unknown number: "...and ends with {piece}."' },
        { type = 'hint', trigger = 'zone', radius = 6.0, coords = base,
          text = 'You are close. There is a keypad around here.' },
        { type = 'password', inputType = 'keypad', codeMode = 'random', length = 4,
          wrongTries = 3, cooldown = 30, coords = at(0.0, 1.5), label = 'Use keypad' },
    }, true)
    reply(src, 'success', ('Demo hunt #%d created. Keypad is 1.5 m in front of you.'):format(id))
end)

-- /huntdemonpc [classic]: an NPC 2 m in front of you takes the code
adminCommand('huntdemonpc', function(src, args)
    if src == 0 then return reply(src, 'error', 'Run this in game') end
    local at = around(src)
    local id = Hunts.Save(nil, 'Demo NPC hunt', true, {
        { type = 'hint', trigger = 'after_previous', piece = true,
          text = 'A voicemail: "Vinnie wants the code. First half: {piece}."' },
        { type = 'hint', trigger = 'delay', delay = 10, piece = true,
          text = 'A second voicemail: "Second half: {piece}. Don\'t keep him waiting."' },
        { type = 'npc', name = 'Vinnie', model = 'a_m_m_business_01', coords = at(0.0, 2.0, 180.0),
          scenario = 'WORLD_HUMAN_SMOKING', cinematic = args[1] ~= 'classic',
          dialog = {
              { id = 'start', text = 'You got something for me, or are you just here for the view?',
                replies = {
                    { label = 'Who are you?', action = 'next_line', next = 'who' },
                    { label = 'I have the code.', action = 'open_password' },
                    { label = 'Got any work?', action = 'give_clue', complete = false,
                      clue = 'Work? Find the code first. Two halves, two messages.' },
                    { label = 'Never mind.', action = 'end' },
                } },
              { id = 'who', text = 'Someone who pays well for four little numbers.',
                replies = {
                    { label = 'I have the code.', action = 'open_password' },
                    { label = 'Later.', action = 'end' },
                } },
          } },
        { type = 'password', inputType = 'keypad', codeMode = 'random', length = 4,
          wrongTries = 3, cooldown = 30, label = 'Give Vinnie the code' },
    }, true)
    reply(src, 'success', ('Demo NPC hunt #%d created. Vinnie is 2 m in front of you.'):format(id))
end)

-- /huntdemofull: note item, armored van scene with an inspect spot, NPC riddle, scrambled word, reward stash
adminCommand('huntdemofull', function(src)
    if src == 0 then return reply(src, 'error', 'Run this in game') end
    local at, base = around(src)
    local id = Hunts.Save(nil, 'Demo full hunt', true, {
        { type = 'hint', trigger = 'after_previous', piece = true, deliver = 'note', title = 'A crumpled note',
          text = 'They hit the van just up the road. The first letters are {piece}. Burn this.' },
        { type = 'scene', radius = 12.0, title = 'The van',
          text = 'The armored van. The guards look bored. Check the back.',
          scene = { preset = 'armored_van', coords = at(0.0, 14.0, 0.0), rearDoors = true, guards = 2,
                    guardMode = 'calm', visibility = 'private', effects = { smoke = true, sparks = true },
                    searchRadius = 40.0 } },
        { type = 'inspect', piece = true, camera = true, label = 'Search the van',
          text = 'Scratched inside the rear door: {piece}' },
        { type = 'npc', name = 'Marla', model = 'a_f_y_business_02', coords = at(3.0, 0.0, 270.0),
          scenario = 'WORLD_HUMAN_STAND_MOBILE',
          dialog = {
              { id = 'start', text = 'You were at the van? Then you want the rest of the word.',
                replies = {
                    { label = 'Tell me.', action = 'give_clue', piece = true, complete = false,
                      clue = 'What ends the word sits behind your ear: {piece}.' },
                    { label = 'I know the word.', action = 'open_password' },
                    { label = 'Bye.', action = 'end' },
                } },
          } },
        { type = 'password', inputType = 'word', codeMode = 'random', length = 6, wrongTries = 3, cooldown = 30,
          label = 'Tell Marla the word', sources = { note = true, inspect = true, npc = true, scramble = true } },
        { type = 'stash', label = 'Marla\'s lockbox', mode = 'reward', coords = base,
          rewards = { { name = 'money', count = 500 } } },
    }, true)
    reply(src, 'success', ('Demo full hunt #%d created: van 14 m ahead, Marla 3 m right, lockbox where you stand.'):format(id))
end)
