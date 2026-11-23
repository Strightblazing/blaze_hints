-- blaze_hints client: NUI helpers, code screens, items, shops, ready signal, cleanup
Hints = { nuiOpen = false }

local resource = GetCurrentResourceName()

function Hints.Debug(...)
    if Config.Debug then print('[blaze_hints]', ...) end
end

Hints.Vec = Util.Vec

---------------------------------------------------------------------------
-- NUI
---------------------------------------------------------------------------

local HUD_HOLD = { keypad = 'hideInKeypad', word = 'hideInKeypad', note = 'hideInReader', builder = 'hideInBuilder' }

function Hints.OpenNui(action, data)
    data = data or {}
    data.action = action
    data.accent = data.accent or Config.Accent
    Hints.nuiOpen = action
    local hold = HUD_HOLD[action]
    if hold and Config.Hud[hold] then Hud.Hold(action, true) end
    SetNuiFocus(true, not data.noCursor) -- inspect: keyboard only
    SendNUIMessage(data)
end

-- a screen went away (closed from Lua or from the page)
local function closed(action)
    if HUD_HOLD[action] then Hud.Hold(action, false) end
    if action == 'dialog' then Dialog.Close() end
    if action == 'inspect' then Inspect.Closed() end
    if action == 'keypad' or action == 'word' then Hints.PasswordClosed() end
    if action == 'builder' then Builder.Closed() end
end

function Hints.CloseNui()
    local action = Hints.nuiOpen
    if not action then return end
    Hints.nuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    closed(action)
end

RegisterNUICallback('close', function(_, cb)
    cb(1)
    local action = Hints.nuiOpen
    if not action then return end
    Hints.nuiOpen = false
    SetNuiFocus(false, false)
    closed(action)
end)

-- close any open screen (and the camera) if the player dies
CreateThread(function()
    while true do
        if Hints.nuiOpen or Dialog.IsOpen() or Camera.Active() then
            if IsEntityDead(PlayerPedId()) or LocalPlayer.state.isDead then
                Dialog.Close()
                Hints.CloseNui()
                Camera.Stop(true)
            end
            Wait(250)
        else
            Wait(1000)
        end
    end
end)

---------------------------------------------------------------------------
-- Password (keypad / word entry)
---------------------------------------------------------------------------

local passwordHunt, passwordPreview

local function openCodeScreen(info)
    Hints.OpenNui(info.inputType == 'word' and 'word' or 'keypad', info)
end

function Hints.OpenPassword(huntId)
    if Hints.nuiOpen then return end
    local info = lib.callback.await('blaze_hints:openPassword', false, huntId)
    if not info then return end -- server already notified why (cooldown / too far / locked / wrong step)
    passwordHunt, passwordPreview = huntId, nil
    openCodeScreen(info)
end

--- Builder preview: any code of the right length opens. onDone runs when the screen closes.
function Hints.PreviewPassword(info, onDone)
    passwordHunt, passwordPreview = nil, { length = info.length, onDone = onDone }
    openCodeScreen(info)
end

function Hints.PasswordClosed()
    local p = passwordPreview
    passwordHunt, passwordPreview = nil, nil
    if p and p.onDone then p.onDone() end
end

RegisterNUICallback('keypadSubmit', function(data, cb)
    if type(data) ~= 'table' or type(data.code) ~= 'string' then return cb({ ok = false, closed = true }) end
    if passwordPreview then
        local ok = #data.code == passwordPreview.length
        return cb({ ok = ok, triesLeft = 3 })
    end
    if not passwordHunt then return cb({ ok = false, closed = true }) end
    local result = lib.callback.await('blaze_hints:submitCode', false, passwordHunt, data.code)
    cb(result or { ok = false, closed = true })
end)

---------------------------------------------------------------------------
-- Items: blaze_note / blaze_receipt open the note reader with their own text
-- ox_inventory: client = { export = 'blaze_hints.readNote' }
---------------------------------------------------------------------------

local function readNote(_, slot)
    if Hints.nuiOpen then return end
    local meta = slot and slot.metadata or {}
    if Config.Hud.hideInReader then Hud.Hold('note', true) end
    Hints.OpenNui('note', {
        title = meta.label or Config.Text.noteTitle,
        text = meta.text or '...',
        kind = meta.kind == 'receipt' and 'receipt' or 'note',
    })
end
exports('readNote', readNote)

---------------------------------------------------------------------------
-- Shops (open_shop replies)
---------------------------------------------------------------------------

function Hints.OpenShop(shopId)
    local system = Config.Shop.system or 'auto'
    if system ~= 'ox' and GetResourceState('lation_shops') == 'started' then
        exports.lation_shops:openShop(shopId)
    elseif system ~= 'lation' then
        exports.ox_inventory:openInventory('shop', { type = shopId })
    else
        lib.notify({ title = Config.Text.shopClosed, description = Config.Text.shopClosedMsg, type = 'warning' })
    end
end

---------------------------------------------------------------------------
-- Notes (/huntnotes): your own found pieces
---------------------------------------------------------------------------

RegisterCommand('huntnotes', function()
    local notes = lib.callback.await('blaze_hints:notes', false) or {}
    local options = {}
    for _, n in ipairs(notes) do
        local parts = {}
        for _, p in ipairs(n.pieces) do parts[#parts + 1] = ('%d/%d: %s'):format(p.n, p.total, p.value) end
        options[#options + 1] = {
            title = n.hunt,
            description = #parts > 0 and table.concat(parts, '   ') or Config.Text.noNotes,
            icon = 'magnifying-glass',
            readOnly = true,
        }
    end
    if #options == 0 then
        lib.notify({ title = Config.Text.notesTitle, description = Config.Text.noNotes, type = 'inform' })
        return
    end
    lib.registerContext({ id = 'blaze_hints_notes', title = Config.Text.notesTitle, options = options })
    lib.showContext('blaze_hints_notes')
end, false)

---------------------------------------------------------------------------
-- Ready / cleanup
---------------------------------------------------------------------------

local function ready()
    TriggerServerEvent('blaze_hints:server:ready')
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(1000)
    ready()
end)

local function cleanupAll()
    Builder.StopPreview()
    Dialog.Close()
    Hints.CloseNui()
    Camera.Stop(true)
    Steps.ClearAll()
    Scenes.ClearAll()
    Hud.ReleaseAll()
end

RegisterNetEvent('QBCore:Client:OnPlayerUnload', cleanupAll)

AddEventHandler('onClientResourceStart', function(res)
    if res ~= resource then return end
    if LocalPlayer.state.isLoggedIn then
        Wait(500)
        ready()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= resource then return end
    cleanupAll()
    SetNuiFocus(false, false)
end)
