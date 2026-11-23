-- Steps: world pieces for the step each hunt is on (only this player sees them), plus each hunt's stash target.
Steps = { active = {}, stash = {} }
-- active[huntId] = { info, zone, target, npcKey, sceneKey, prop }
-- stash[huntId]  = { info, target, sceneKey }

---------------------------------------------------------------------------
-- NPCs: local (non-networked) peds, spawned only near the player.
-- Keyed by hunt + NPC step, so the same ped stays when a password step it hosts starts.
---------------------------------------------------------------------------
local Npcs = {} -- [key] = { key, huntId, info, refs, point, ped, spawning, removed, pending }

local function deletePed(n)
    if n.ped then
        if DoesEntityExist(n.ped) then
            exports.ox_target:removeLocalEntity(n.ped)
            DeleteEntity(n.ped)
        end
        n.ped = nil
    end
end

--- Spawn a hunt NPC ped (also used by the builder preview)
function Steps.CreateNpcPed(info)
    local c = info.coords
    local ok, model = pcall(lib.requestModel, info.model or 'a_m_m_business_01', 10000)
    if not ok or not model then
        print(('^3[blaze_hints]^7 could not load NPC model %s'):format(tostring(info.model)))
        return
    end
    -- coords are where the admin stood ("Place here"): feet go 1 m lower
    local ped = CreatePed(4, model, c.x + 0.0, c.y + 0.0, c.z - 1.0, Util.Heading(c), false, true)
    SetModelAsNoLongerNeeded(model)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    if info.scenario and info.scenario ~= '' then
        TaskStartScenarioInPlace(ped, info.scenario, 0, true)
    end
    return ped
end

local function spawnPed(n)
    if n.spawning or (n.ped and DoesEntityExist(n.ped)) then return end
    if type(n.info.coords) ~= 'table' or not n.info.coords.x then return end
    n.spawning = true
    CreateThread(function()
        local ped = Steps.CreateNpcPed(n.info)
        n.spawning = false
        if not ped then return end
        if n.removed or n.ped then DeleteEntity(ped) return end
        n.ped = ped
        exports.ox_target:addLocalEntity(ped, {
            {
                name = 'blaze_hints_talk',
                icon = 'fa-solid fa-comments',
                label = n.info.label or Config.Text.talk,
                distance = 2.5,
                onSelect = function() Dialog.Open(n.huntId, n.info, ped) end,
            },
        })
    end)
end

local function useNpc(huntId, info)
    local n = Npcs[info.key]
    if n then
        n.refs = n.refs + 1
        n.info = info -- newest dialog / settings (e.g. the locked line)
        n.pending = nil
        return info.key
    end
    local c = info.coords
    if type(c) ~= 'table' or not c.x then return end
    n = { key = info.key, huntId = huntId, info = info, refs = 1 }
    Npcs[info.key] = n
    n.point = lib.points.new({
        coords = vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0),
        distance = Config.NpcSpawnDistance,
        onEnter = function() spawnPed(n) end,
        onExit = function()
            if not Dialog.IsOpenFor(n.huntId, n.ped) then deletePed(n) end
        end,
    })
    return info.key
end

local function removeNpc(n)
    n.removed = true
    if n.point then n.point:remove() end
    deletePed(n)
    Npcs[n.key] = nil
end

local function releaseNpc(key, force)
    local n = Npcs[key]
    if not n then return end
    n.refs = n.refs - 1
    if n.refs > 0 then return end
    if not force and n.ped and Dialog.IsOpenFor(n.huntId, n.ped) then
        n.pending = true -- still talking: removed when the dialog closes
        return
    end
    removeNpc(n)
end

--- Dialog closed: remove NPCs whose step ended mid-conversation
function Steps.OnDialogClosed(huntId)
    for _, n in pairs(Npcs) do
        if n.huntId == huntId and n.pending and n.refs <= 0 then removeNpc(n) end
    end
end

---------------------------------------------------------------------------
-- Where-to-look markers (Config.Markers): a floating icon over the spot, a thin ring on the ground.
-- Hidden while a close-up camera or a hunt screen is up.
---------------------------------------------------------------------------
local Markers, markerLoop = {}, false

local function accentColor()
    local c = Config.Markers.color
    if type(c) == 'table' then return c[1] or 242, c[2] or 106, c[3] or 33, c[4] or 210 end
    local hex = tostring(Config.Accent or '#f26a21'):gsub('#', '')
    return tonumber(hex:sub(1, 2), 16) or 242, tonumber(hex:sub(3, 4), 16) or 106, tonumber(hex:sub(5, 6), 16) or 33, 210
end

local function drawMarkers()
    if markerLoop then return end
    markerLoop = true
    CreateThread(function()
        local M = Config.Markers
        local r, g, b, a = accentColor()
        local icon = M.icon or 32
        local flip = icon == 2 or icon == 3 or (icon >= 20 and icon <= 22) -- chevrons point down at the spot
        local s, rs = M.iconScale or 0.35, M.ringScale or 0.9
        while next(Markers) do
            local sleep = 500
            if not Camera.Active() and not Hints.nuiOpen then
                local me = GetEntityCoords(PlayerPedId())
                for _, m in pairs(Markers) do
                    if #(me - m.coords) < (M.distance or 25.0) then
                        sleep = 0
                        local c = m.coords
                        DrawMarker(icon, c.x, c.y, c.z + (m.height or M.height or 0.75), 0.0, 0.0, 0.0,
                            flip and 180.0 or 0.0, 0.0, 0.0, s, s, s, r, g, b, a, M.bob ~= false, true, 2, false, nil, nil, false)
                        if M.ring ~= false and not m.noRing then
                            DrawMarker(25, c.x, c.y, c.z - 0.97, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, rs, rs, rs, r, g, b, 120,
                                false, false, 2, false, nil, nil, false)
                        end
                    end
                end
            end
            Wait(sleep)
        end
        markerLoop = false
    end)
end

local markerSeq = 0
local function addMarker(coords, height, noRing)
    if not coords or not Config.Markers or Config.Markers.enabled == false then return end
    markerSeq = markerSeq + 1
    Markers[markerSeq] = { coords = coords, height = height, noRing = noRing }
    drawMarkers()
    return markerSeq
end

local function removeMarker(id)
    if id then Markers[id] = nil end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function addTarget(coords, name, icon, label, onSelect, radius)
    return exports.ox_target:addSphereZone({
        coords = coords,
        radius = radius or 0.8,
        debug = Config.Debug,
        options = { { name = name, icon = icon, label = label, distance = 2.0, onSelect = onSelect } },
    })
end

local function lockedNotice(info, title)
    lib.notify({ title = title, description = info.lockedMessage or Config.Text.nothingHere, type = 'inform' })
end

local function spawnProp(model, coords)
    local ok, hash = pcall(lib.requestModel, model, 5000)
    if not ok or not hash then return end
    local obj = CreateObject(hash, coords.x, coords.y, coords.z - 0.95, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    return obj
end

---------------------------------------------------------------------------
-- Step setup / clear
---------------------------------------------------------------------------

local function clear(a, force)
    if not a then return end
    if a.zone then a.zone:remove() end
    if a.target then exports.ox_target:removeZone(a.target) end
    if a.npcKey then releaseNpc(a.npcKey, force) end
    if a.sceneKey then Scenes.Release(a.sceneKey) end
    if a.prop and DoesEntityExist(a.prop) then DeleteEntity(a.prop) end
    removeMarker(a.marker)
    a.cleared = true
end

local setup = {}

-- hint with trigger 'zone': tell the server once when we walk in (the server checks our position)
function setup.hint(huntId, info, a)
    if info.trigger ~= 'zone' then return end
    local coords = Hints.Vec(info.coords)
    if not coords then return end
    local sent = false
    a.zone = lib.zones.sphere({
        coords = coords,
        radius = info.radius or 5.0,
        debug = Config.Debug,
        onEnter = function()
            if sent then return end
            sent = true
            TriggerServerEvent('blaze_hints:server:zoneEnter', huntId, info.index)
        end,
    })
end

-- scene: reach it (same as a hint zone, the server checks the distance)
function setup.scene(huntId, info, a)
    local coords = Hints.Vec(info.coords)
    if not coords then return end
    local sent = false
    a.zone = lib.zones.sphere({
        coords = coords,
        radius = info.radius or 15.0,
        debug = Config.Debug,
        onEnter = function()
            if sent then return end
            sent = true
            TriggerServerEvent('blaze_hints:server:zoneEnter', huntId, info.index)
        end,
    })
end

-- password: an ox_target spot that opens the keypad / word entry, and/or the NPC that hosts it
function setup.password(huntId, info, a)
    if info.npc then a.npcKey = useNpc(huntId, info.npc) end
    local coords = Hints.Vec(info.coords)
    if info.marker then
        if coords then
            a.marker = addMarker(coords)
        elseif info.npc then
            a.marker = addMarker(Hints.Vec(info.npc.coords), 1.25, true) -- over the NPC's head
        end
    end
    if not coords then return end
    local label = info.label or Config.Text.enterCode
    a.target = addTarget(coords, ('blaze_hints_password_%d'):format(huntId), 'fa-solid fa-keyboard', label, function()
        if info.locked then return lockedNotice(info, label) end
        Hints.OpenPassword(huntId)
    end)
end

-- npc: a ped with "Talk"
function setup.npc(huntId, info, a)
    if not info.npc then return end
    a.npcKey = useNpc(huntId, info.npc)
    if info.marker then a.marker = addMarker(Hints.Vec(info.npc.coords), 1.25, true) end -- over the NPC's head
end

-- inspect: a spot (optionally a prop) with "Inspect"
function setup.inspect(huntId, info, a)
    local coords = Hints.Vec(info.coords)
    if not coords then return end
    if info.marker then a.marker = addMarker(coords) end
    if info.prop then
        CreateThread(function()
            local obj = spawnProp(info.prop, coords)
            if a.cleared then if obj then DeleteEntity(obj) end return end
            a.prop = obj
        end)
    end
    a.target = addTarget(coords, ('blaze_hints_inspect_%d'):format(huntId), 'fa-solid fa-magnifying-glass', info.label or Config.Text.inspect, function()
        -- a prop of its own is framed; otherwise the spot itself (on a scene: behind the van, on the crate, ...)
        Inspect.Use(huntId, info, a.prop or coords)
    end)
end

RegisterNetEvent('blaze_hints:client:step', function(huntId, info)
    local old = Steps.active[huntId]
    Steps.active[huntId] = nil

    if (Hints.nuiOpen == 'keypad' or Hints.nuiOpen == 'word') and (not info or info.type ~= 'password') then
        -- step moved on (or was reset) while the code screen was open: let the OPEN/locked animation finish
        SetTimeout(600, function()
            if Hints.nuiOpen == 'keypad' or Hints.nuiOpen == 'word' then Hints.CloseNui() end
        end)
    end

    -- set up the new step before clearing the old one, so a shared NPC / scene is kept instead of respawned
    if info then
        Hints.Debug(('hunt %d step %d (%s)%s'):format(huntId, info.index, info.type, info.locked and ' locked' or ''))
        local a = { info = info }
        Steps.active[huntId] = a
        if info.scene then a.sceneKey = Scenes.Use(info.scene) end
        local fn = setup[info.type]
        if fn then fn(huntId, info, a) end
    end
    clear(old)
end)

---------------------------------------------------------------------------
-- Stash target (stays after the hunt is complete for permanent storage)
---------------------------------------------------------------------------

local function clearStash(s)
    if not s then return end
    if s.target then exports.ox_target:removeZone(s.target) end
    if s.sceneKey then Scenes.Release(s.sceneKey) end
    removeMarker(s.marker)
end

RegisterNetEvent('blaze_hints:client:stash', function(huntId, info)
    local old = Steps.stash[huntId]
    Steps.stash[huntId] = nil
    if info then
        local s = { info = info }
        Steps.stash[huntId] = s
        if info.scene then s.sceneKey = Scenes.Use(info.scene) end
        local coords = Hints.Vec(info.coords)
        if coords and info.marker then s.marker = addMarker(coords) end
        if coords then
            s.target = addTarget(coords, ('blaze_hints_stash_%d'):format(huntId),
                info.unlocked and 'fa-solid fa-box-open' or 'fa-solid fa-lock',
                info.unlocked and info.label or ('%s (%s)'):format(info.label, Config.Text.stashLocked),
                function() TriggerServerEvent('blaze_hints:server:openStash', huntId) end, 1.0)
        end
    end
    clearStash(old)
end)

function Steps.ClearAll()
    for huntId, a in pairs(Steps.active) do
        clear(a, true)
        Steps.active[huntId] = nil
    end
    for huntId, s in pairs(Steps.stash) do
        clearStash(s)
        Steps.stash[huntId] = nil
    end
    for _, n in pairs(Npcs) do removeNpc(n) end
    for id in pairs(Markers) do Markers[id] = nil end
end
