-- Inspect spots: optional close-up camera, letterbox overlay with the caption and the code piece, "[E] Stop inspecting".
-- The server reveals the piece when you inspect, and moves you on when you stop inspecting.
Inspect = {}

local cur -- { huntId, preview }

function Inspect.IsOpen() return cur ~= nil end

--- Show the overlay. focus = entity to frame, or coords (vector3) when there is none.
function Inspect.Show(huntId, data, focus, opts)
    if cur or Hints.nuiOpen then return end
    opts = opts or {}
    local c = { huntId = huntId, preview = opts.preview }
    cur = c
    local camOn = opts.camera ~= false and focus ~= nil
    if camOn then
        -- orbit: mouse looks around the clue, the shot drifts by itself, your controls are locked
        if type(focus) == 'number' and DoesEntityExist(focus) then
            Camera.Focus(focus, { distance = 1.0, side = 0.35, height = 0.35, fov = 45.0, orbit = true })
        else
            Camera.FocusCoords(focus, { orbit = true })
        end
    end

    -- The overlay takes no NUI focus, so the game keeps the mouse for the camera. E / ESC / Backspace stop.
    CreateThread(function()
        local readyAt = GetGameTimer() + 350 -- ignore the key press that opened it
        while cur == c do
            DisableControlAction(0, 200, true) -- ESC: no pause menu
            DisableControlAction(0, 322, true)
            DisableControlAction(0, 177, true) -- Backspace
            if GetGameTimer() > readyAt then
                for _, key in ipairs({ 38, 200, 322, 177 }) do -- E, ESC, ESC, Backspace
                    if IsControlJustPressed(0, key) or IsDisabledControlJustPressed(0, key) then
                        Hints.CloseNui()
                        break
                    end
                end
            end
            Wait(0)
        end
    end)
    if Config.Hud.hideInReader then Hud.Hold('reader', true) end
    Hints.OpenNui('inspect', {
        caption = data.caption or '',
        pieceN = data.pieceN,
        pieceTotal = data.pieceTotal,
        pieceText = data.pieceN and Config.Text.pieceOverlay:format(data.pieceN, data.pieceTotal) or nil,
        circle = camOn,
        stopText = camOn and Config.Text.stopInspectLook or Config.Text.stopInspect,
        noFocus = true,
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
