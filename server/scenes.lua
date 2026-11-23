-- World scenes.
-- step.scene = { preset = 'armored_van' | 'crate_drop' | 'briefcase', coords = {x,y,z,w} (default: the step's),
--   rearDoors = true, guards = 0-4, guardMode = 'calm' | 'hostile' | 'dressing', visibility = 'private' | 'shared',
--   effects = { smoke = true, sparks = true, flare = true }, searchRadius = 0 (temporary blip), searchSeconds = 0 (0 = while on the step) }
-- private (default): the client spawns non-networked entities just for that player.
-- shared: the server spawns networked entities once per scene (everyone sees them) while anyone is on that step.
--         The entity owner applies doors / guard behaviour from the 'blazeHintsScene' state bag. Effects and the
--         search blip stay on the screens of players on that step.
Scenes = { shared = {} } -- [key] = { refs = { [src] = true }, entities = { handles }, netIds = { ... } }

local function hash(model) return type(model) == 'number' and model or joaat(model) end

local function waitFor(entity)
    local t = GetGameTimer() + 3000
    while not DoesEntityExist(entity) and GetGameTimer() < t do Wait(0) end
    return DoesEntityExist(entity)
end

local function spawnShared(scene, step)
    local preset = Config.ScenePresets[scene.preset]
    local c = Util.SceneCoords(scene, step)
    if not preset or not c then return {}, {} end
    local h = Util.Heading(c)
    local entities, netIds = {}, {}

    local function track(ent, state)
        if not waitFor(ent) then return end
        entities[#entities + 1] = ent
        Entity(ent).state:set('blazeHintsScene', state, true)
        netIds[#netIds + 1] = NetworkGetNetworkIdFromEntity(ent)
    end

    if preset.vehicle then
        local veh = CreateVehicleServerSetter(hash(preset.vehicle), 'automobile', c.x + 0.0, c.y + 0.0, c.z + 0.0, h)
        if waitFor(veh) then
            FreezeEntityPosition(veh, true)
            SetVehicleDoorsLocked(veh, 2)
            track(veh, { kind = 'vehicle', doors = scene.rearDoors ~= false and preset.rearDoors or nil })
        end
    end

    for _, p in ipairs(preset.props or {}) do
        local pos = Util.Offset(c, p.offset[1], p.offset[2], p.offset[3])
        local obj = CreateObjectNoOffset(hash(p.model), pos.x, pos.y, pos.z, true, true, false)
        if waitFor(obj) then
            SetEntityHeading(obj, h)
            FreezeEntityPosition(obj, true)
            track(obj, { kind = 'prop' })
        end
    end

    local count = math.max(0, math.min(4, math.floor(tonumber(scene.guards) or 0)))
    local mode = scene.guardMode or 'calm'
    for i = 1, count do
        local g = preset.guardSpots and preset.guardSpots[i]
        if g then
            local pos = Util.Offset(c, g[1], g[2], g[3])
            local ped = CreatePed(4, hash(scene.guardModel or Config.Guards.model), pos.x, pos.y, pos.z, (h + (g[4] or 0.0)) % 360.0, true, true)
            if waitFor(ped) then
                local weapon = mode == 'hostile' and Config.Guards.hostileWeapon or Config.Guards.calmWeapon
                if mode ~= 'dressing' then GiveWeaponToPed(ped, hash(weapon), 250, false, mode == 'hostile') end
                if mode ~= 'hostile' then FreezeEntityPosition(ped, true) end
                track(ped, { kind = 'guard', mode = mode })
            end
        end
    end

    return entities, netIds
end

--- Player `src` needs shared scene `key` (spawned on first use). Returns its net ids.
function Scenes.Acquire(src, key, scene, step)
    local s = Scenes.shared[key]
    if not s then
        s = { refs = {}, entities = {}, netIds = {}, spawning = true }
        Scenes.shared[key] = s
        s.entities, s.netIds = spawnShared(scene, step)
        s.spawning = false
        if not next(s.refs) and s.released then -- everyone left while it spawned
            Scenes.Destroy(key)
            return {}
        end
    end
    s.refs[src] = true
    return s.netIds
end

function Scenes.Release(src, key)
    local s = key and Scenes.shared[key]
    if not s then return end
    s.refs[src] = nil
    if next(s.refs) then return end
    if s.spawning then s.released = true return end
    Scenes.Destroy(key)
end

function Scenes.ReleaseAll(src)
    for key in pairs(Scenes.shared) do Scenes.Release(src, key) end
end

function Scenes.Destroy(key)
    local s = Scenes.shared[key]
    if not s then return end
    for _, ent in ipairs(s.entities) do
        if DoesEntityExist(ent) then DeleteEntity(ent) end
    end
    Scenes.shared[key] = nil
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for key in pairs(Scenes.shared) do Scenes.Destroy(key) end
end)
