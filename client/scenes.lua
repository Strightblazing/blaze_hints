-- World scenes on the client.
-- private: non-networked entities spawned just for this player (only inside Config.SceneSpawnDistance).
-- shared:  the server spawns the entities; here we only add the effects and the search-area blip,
--          and set up shared entities from their 'blazeHintsScene' state bag.
-- Scenes are keyed, so the scene step and the step it hosts (an inspect spot, ...) share one set of entities.
Scenes = {}
local active = {} -- [key] = { key, info, refs, point, ents, fx, blip, removed }

local HOSTILE = joaat('HATES_PLAYER')

local function hash(model) return type(model) == 'number' and model or joaat(model) end

---------------------------------------------------------------------------
-- Entity setup (private entities and shared ones from their state bag)
---------------------------------------------------------------------------

local function setupVehicle(veh, doors)
    SetEntityInvincible(veh, true)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleUndriveable(veh, true)
    SetVehicleDoorsLocked(veh, 2)
    for _, d in ipairs(doors or {}) do
        SetVehicleDoorOpen(veh, d, false, true)
    end
    FreezeEntityPosition(veh, true)
end

local function setupGuard(ped, mode, giveWeapon)
    SetPedFleeAttributes(ped, 0, false)
    SetPedDropsWeaponsWhenDead(ped, false)
    SetPedKeepTask(ped, true)
    if giveWeapon and mode ~= 'dressing' then
        local weapon = mode == 'hostile' and Config.Guards.hostileWeapon or Config.Guards.calmWeapon
        GiveWeaponToPed(ped, hash(weapon), 250, false, mode == 'hostile')
    end
    if mode == 'hostile' then
        SetBlockingOfNonTemporaryEvents(ped, false)
        SetPedRelationshipGroupHash(ped, HOSTILE)
        SetPedCombatAttributes(ped, 46, true) -- always fight
        SetPedCombatAbility(ped, 1)
        SetPedAccuracy(ped, Config.Guards.accuracy or 25)
        TaskGuardCurrentPosition(ped, 15.0, 15.0, true)
    elseif mode == 'calm' then
        SetBlockingOfNonTemporaryEvents(ped, true)
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_GUARD_STAND', 0, true)
    else -- set dressing
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_GUARD_STAND', 0, true)
    end
end

-- shared scene entities: set up from the state bag the server put on them
AddStateBagChangeHandler('blazeHintsScene', nil, function(bagName, _, value)
    if type(value) ~= 'table' then return end
    CreateThread(function()
        local ent, t = 0, GetGameTimer() + 5000
        while GetGameTimer() < t do
            ent = GetEntityFromStateBagName(bagName)
            if ent ~= 0 and DoesEntityExist(ent) then break end
            Wait(100)
        end
        if ent == 0 or not DoesEntityExist(ent) then return end
        if value.kind == 'vehicle' then
            setupVehicle(ent, value.doors)
        elseif value.kind == 'guard' then
            if NetworkGetEntityOwner(ent) == PlayerId() then setupGuard(ent, value.mode, false) end
        elseif value.kind == 'prop' then
            FreezeEntityPosition(ent, true)
        end
    end)
end)

---------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------

local function spawnPrivate(s)
    local info = s.info
    local preset = Config.ScenePresets[info.preset]
    local c = info.coords
    local h = Util.Heading(c)

    if preset.vehicle then
        local model = lib.requestModel(preset.vehicle, 10000)
        if s.removed or not s.ents then return end
        local veh = CreateVehicle(model, c.x, c.y, c.z, h, false, false)
        SetModelAsNoLongerNeeded(model)
        SetVehicleOnGroundProperly(veh)
        setupVehicle(veh, info.rearDoors and preset.rearDoors or nil)
        s.ents[#s.ents + 1] = veh
        s.main = veh
    end

    for _, p in ipairs(preset.props or {}) do
        local model = lib.requestModel(p.model, 10000)
        if s.removed or not s.ents then return end
        local pos = Util.Offset(c, p.offset[1], p.offset[2], p.offset[3])
        local obj = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)
        SetModelAsNoLongerNeeded(model)
        SetEntityHeading(obj, h)
        FreezeEntityPosition(obj, true)
        s.ents[#s.ents + 1] = obj
        s.main = s.main or obj
    end

    for i = 1, info.guards or 0 do
        local g = preset.guardSpots and preset.guardSpots[i]
        if g then
            local model = lib.requestModel(info.guardModel or Config.Guards.model, 10000)
            if s.removed or not s.ents then return end
            local pos = Util.Offset(c, g[1], g[2], g[3])
            local ped = CreatePed(4, model, pos.x, pos.y, pos.z - 1.0, (h + (g[4] or 0.0)) % 360.0, false, true)
            SetModelAsNoLongerNeeded(model)
            setupGuard(ped, info.guardMode, true)
            s.ents[#s.ents + 1] = ped
        end
    end
end

local function startEffects(s)
    local info = s.info
    local preset = Config.ScenePresets[info.preset]
    local c = info.coords
    for name, on in pairs(info.effects or {}) do
        local fx = Config.SceneEffects[name]
        local o = preset.effects and preset.effects[name]
        if on and fx and o then
            lib.requestNamedPtfxAsset(fx.asset, 5000)
            if s.removed or not s.fx then return end
            local p = Util.Offset(c, o[1], o[2], o[3])
            UseParticleFxAssetNextCall(fx.asset)
            local handle = StartParticleFxLoopedAtCoord(fx.name, p.x, p.y, p.z, 0.0, 0.0, 0.0, fx.scale or 1.0, false, false, false, false)
            s.fx[#s.fx + 1] = handle
        end
    end
end

local function spawn(s)
    if s.ents or s.removed then return end
    s.ents, s.fx = {}, {}
    CreateThread(function()
        if s.info.visibility ~= 'shared' then spawnPrivate(s) end
        startEffects(s)
    end)
end

local function despawn(s)
    for _, ent in ipairs(s.ents or {}) do
        if DoesEntityExist(ent) then
            SetEntityAsMissionEntity(ent, true, true)
            DeleteEntity(ent)
        end
    end
    for _, handle in ipairs(s.fx or {}) do
        StopParticleFxLooped(handle, false)
    end
    s.ents, s.fx, s.main = nil, nil, nil
end

local function remove(s)
    s.removed = true
    if s.point then s.point:remove() end
    despawn(s)
    if s.blip and DoesBlipExist(s.blip) then RemoveBlip(s.blip) end
    active[s.key] = nil
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

--- Show a scene (refcounted by key). Returns the key.
function Scenes.Use(info)
    if type(info) ~= 'table' or not info.key or not Config.ScenePresets[info.preset] or not info.coords then return end
    local s = active[info.key]
    if s then
        s.refs = s.refs + 1
        return info.key
    end
    s = { key = info.key, info = info, refs = 1 }
    active[info.key] = s
    local c = info.coords

    s.point = lib.points.new({
        coords = vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0),
        distance = Config.SceneSpawnDistance,
        onEnter = function() spawn(s) end,
        onExit = function() despawn(s) end,
    })

    if (info.searchRadius or 0) > 0 then
        local blip = AddBlipForRadius(c.x + 0.0, c.y + 0.0, c.z + 0.0, info.searchRadius + 0.0)
        SetBlipColour(blip, 47)
        SetBlipAlpha(blip, 110)
        SetBlipHighDetail(blip, true)
        s.blip = blip
        if (info.searchSeconds or 0) > 0 then
            SetTimeout(info.searchSeconds * 1000, function()
                if s.blip == blip and DoesBlipExist(blip) then RemoveBlip(blip) s.blip = nil end
            end)
        end
    end
    return info.key
end

function Scenes.Release(key)
    local s = key and active[key]
    if not s then return end
    s.refs = s.refs - 1
    if s.refs <= 0 then remove(s) end
end

function Scenes.ClearAll()
    for _, s in pairs(active) do remove(s) end
end

--- The scene's main entity (vehicle or first prop) for the inspect camera
function Scenes.MainEntity(key)
    local s = key and active[key]
    return s and s.main and DoesEntityExist(s.main) and s.main or nil
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Scenes.ClearAll() end
end)
