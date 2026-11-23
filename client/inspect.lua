-- Inspect spots: optional close-up camera, letterbox overlay with the caption and the code piece, "[E] Stop inspecting".
-- The server reveals the piece when you inspect, and moves you on when you stop inspecting.
Inspect = {}

local cur -- { huntId, preview }

function Inspect.IsOpen() return cur ~= nil end

--- Show the overlay. focus = entity to frame, or coords (vector3) when there is none.
function Inspect.Show(huntId, data, focus, opts)
    if cur or Hints.nuiOpen then return end
    opts = opts or {}
    cur = { huntId = huntId, preview = opts.preview }
    if opts.camera ~= false then
        if type(focus) == 'number' and DoesEntityExist(focus) then
            Camera.Focus(focus, { distance = 1.0, side = 0.35, height = 0.35, fov = 45.0, hidePlayer = true })
        elseif focus then
            Camera.FocusCoords(focus)
        end
    end
    if Config.Hud.hideInReader then Hud.Hold('reader', true) end
    Hints.OpenNui('inspect', {
        caption = data.caption or '',
        pieceN = data.pieceN,
        pieceTotal = data.pieceTotal,
        pieceText = data.pieceN and Config.Text.pieceOverlay:format(data.pieceN, data.pieceTotal) or nil,
        circle = opts.camera ~= false and focus ~= nil,
        stopText = Config.Text.stopInspect,
        noCursor = true,
    })
end

--- The overlay closed (E / ESC / death / step end)
function Inspect.Closed()
    if not cur then return end
    local c = cur
    cur = nil
    Camera.Stop()
    Hud.Hold('reader', false)
    if c.preview then
        if c.preview ~= true then c.preview() end
    elseif c.huntId then
        TriggerServerEvent('blaze_hints:server:inspectDone', c.huntId)
    end
end

--- ox_target "Inspect" on the current step's spot
function Inspect.Use(huntId, info, focus)
    if cur or Hints.nuiOpen then return end
    if info.locked then
        lib.notify({ title = info.label or Config.Text.inspect, description = info.lockedMessage or Config.Text.nothingHere, type = 'inform' })
        return
    end
    local res = lib.callback.await('blaze_hints:inspect', false, huntId)
    if not res then return end
    Inspect.Show(huntId, res, focus, { camera = info.camera })
end
