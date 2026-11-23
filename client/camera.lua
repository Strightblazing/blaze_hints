-- Camera + HUD: cinematic close-ups and hiding the HUD while hunt screens are open.
-- Everything here is restored on close, death, logout, step end and resource stop.

---------------------------------------------------------------------------
-- HUD (your HUD resource through Config.Hud, plus the GTA HUD / minimap per frame)
---------------------------------------------------------------------------
Hud = {}

local HUD = Config.Hud or {}
local holds, hidden, wasVisible, showTimer = {}, false, nil, 0
local radarHolds, radarLoop = {}, false

local function setHud(hide)
    TriggerEvent('blaze_hints:client:hud', hide) -- for HUDs that listen instead
    if type(HUD.toggle) == 'function' then
        local ok, err = pcall(HUD.toggle, hide)
        if not ok then print(('^3[blaze_hints]^7 Hud.toggle failed: %s'):format(err)) end
    end
    local e = HUD.export
    if type(e) ~= 'table' or type(e.resource) ~= 'string' or GetResourceState(e.resource) ~= 'started' then return end
    local ok, err = pcall(function()
        local r = exports[e.resource]
        if hide and e.isVisible then wasVisible = r[e.isVisible](r) ~= false end
        if not hide and wasVisible == false then return end -- it was already off before we hid it
        if e.set then
            r[e.set](r, not hide)
        elseif hide and e.hide then
            r[e.hide](r)
        elseif not hide and e.show then
            r[e.show](r)
        end
    end)
    if not ok then print(('^3[blaze_hints]^7 Hud.export (%s) failed: %s'):format(e.resource, err)) end
end

local function update()
    showTimer = showTimer + 1
    if next(holds) then
        if not hidden then hidden = true setHud(true) end
        return
    end
    if not hidden then return end
    -- show again a moment later, so going from the dialog to the keypad doesn't flash the HUD
    local mine = showTimer
    SetTimeout(400, function()
        if mine ~= showTimer or next(holds) or not hidden then return end
        hidden = false
        setHud(false)
    end)
end

--- Hold your HUD hidden for one reason ('dialog', 'keypad', 'camera', ...) or let go
function Hud.Hold(reason, on)
    holds[reason] = on and true or nil
    update()
end

--- Hide the GTA HUD + minimap every frame while any reason holds it
function Hud.Radar(reason, on)
    radarHolds[reason] = on and true or nil
    if radarLoop or not next(radarHolds) then return end
    radarLoop = true
    CreateThread(function()
        while next(radarHolds) do
            HideHudAndRadarThisFrame()
            Wait(0)
        end
        radarLoop = false
    end)
end

--- Let go of everything right now (resource stop / logout: no delayed show)
function Hud.ReleaseAll()
    holds, radarHolds = {}, {}
    showTimer = showTimer + 1
    if hidden then
        hidden = false
        setHud(false)
    end
end

---------------------------------------------------------------------------
-- Camera
---------------------------------------------------------------------------
Camera = { cam = nil }

--- Every frame while this camera is up:
---   hidePlayer: hide your own ped on your screen (others still see you)
---   orbit:      your controls are locked; the mouse turns the camera around the target (limited range)
---               and the shot slowly pushes in and sways by itself
local function runCam(cam, target, pos, opts)
    if not opts.hidePlayer and not opts.orbit then return end
    local rel = pos - target
    local baseYaw = math.atan(rel.y, rel.x)
    local baseDist = math.max(0.3, #vector3(rel.x, rel.y, 0.0))
    local baseHeight = rel.z
    local maxYaw, maxUp, maxDown = math.rad(opts.maxYaw or 45.0), opts.maxUp or 0.45, opts.maxDown or 0.25
    local yaw, lift = 0.0, 0.0
    local started = GetGameTimer()

    CreateThread(function()
        while Camera.cam == cam do
            if opts.hidePlayer then SetEntityLocallyInvisible(PlayerPedId()) end
            if opts.orbit then
                DisableAllControlActions(0)
                EnableControlAction(0, 249, true) -- push to talk
                -- mouse / right stick look
                local mx = GetDisabledControlNormal(0, 1)
                local my = GetDisabledControlNormal(0, 2)
                yaw = math.max(-maxYaw, math.min(maxYaw, yaw - mx * math.rad(opts.sensitivity or 10.0)))
                lift = math.max(-maxDown, math.min(maxUp, lift + my * 0.12))
                -- drift: slow push-in over ~10 s, then a gentle sway
                local t = (GetGameTimer() - started) / 1000.0
                local push = math.min(t / 10.0, 1.0)
                push = push * push * (3 - 2 * push)
                local dist = baseDist * (1.0 - 0.18 * push)
                local a = baseYaw + yaw + math.sin(t * 0.45) * math.rad(2.5)
                local z = baseHeight + lift + math.sin(t * 0.7) * 0.015
                SetCamCoord(cam, target.x + math.cos(a) * dist, target.y + math.sin(a) * dist, target.z + z)
                PointCamAtCoord(cam, target.x, target.y, target.z)
            end
            Wait(0)
        end
    end)
end

--- Frame an entity: a ped's face (head bone) or an object's centre
---@param entity number
---@param opts? { distance?: number, fov?: number, side?: number, height?: number }
function Camera.Focus(entity, opts)
    if not entity or not DoesEntityExist(entity) then return end
    opts = opts or {}
    Camera.Stop(true)

    local isPed = IsEntityAPed(entity)
    local target = isPed and GetPedBoneCoords(entity, 31086, 0.0, 0.0, 0.0) or GetEntityCoords(entity)
    local fwd = GetEntityForwardVector(entity)
    local right = vector3(fwd.y, -fwd.x, 0.0)
    local pos = target
        + fwd * (opts.distance or (isPed and 0.95 or 1.2))
        + right * (opts.side or 0.22)
        + vector3(0.0, 0.0, opts.height or 0.04)

    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, opts.fov or 38.0, false, 0)
    PointCamAtCoord(cam, target.x, target.y, target.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 700, true, true)
    Camera.cam = cam
    runCam(cam, target, pos, opts)
    Hud.Radar('camera', true)
    Hud.Hold('camera', true)
end

--- Frame a point in the world (an inspect spot without an entity): close in, from your side at an angle,
--- with your own ped hidden so it never blocks the clue
function Camera.FocusCoords(target, opts)
    if not target then return end
    opts = opts or {}
    Camera.Stop(true)
    local from = GetEntityCoords(PlayerPedId())
    local dir = vector3(from.x - target.x, from.y - target.y, 0.0)
    local len = #dir
    dir = len > 0.01 and dir / len or vector3(0.0, -1.0, 0.0)
    -- turn ~35 degrees off your line of sight so the shot is not straight over your shoulder
    local a = math.rad(opts.angle or 35.0)
    local ca, sa = math.cos(a), math.sin(a)
    dir = vector3(dir.x * ca - dir.y * sa, dir.x * sa + dir.y * ca, 0.0)
    local pos = target + dir * (opts.distance or 0.75) + vector3(0.0, 0.0, opts.height or 0.3)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, opts.fov or 50.0, false, 0)
    PointCamAtCoord(cam, target.x, target.y, target.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 700, true, true)
    Camera.cam = cam
    if opts.hidePlayer == nil then opts.hidePlayer = true end
    runCam(cam, target, pos, opts)
    Hud.Radar('camera', true)
    Hud.Hold('camera', true)
end

function Camera.Stop(instant)
    local cam = Camera.cam
    if not cam then return end
    Camera.cam = nil
    RenderScriptCams(false, not instant, instant and 0 or 600, true, true)
    DestroyCam(cam, false)
    Hud.Radar('camera', false)
    Hud.Hold('camera', false)
end

function Camera.Active()
    return Camera.cam ~= nil
end
