-- Dialog: NPC conversations in two styles.
-- cinematic = letterbox + camera on the NPC's face + HUD hidden; classic = small panel bottom-right over gameplay.
Dialog = {}

local cur -- { huntId, npc, ped, line, busy, cinematic }

function Dialog.IsOpen() return cur ~= nil end
function Dialog.IsOpenFor(huntId, ped)
    return cur ~= nil and cur.huntId == huntId and (not ped or cur.ped == ped)
end

local function lineIndexById(id)
    if id == nil then return end
    for i, line in ipairs(cur.npc.lines) do
        if line.id == id then return i end
    end
    return tonumber(id)
end

local function send(text, replies)
    SendNUIMessage({ action = 'dialogLine', text = text, replies = replies })
end

function Dialog.ShowLine(index)
    if not cur then return end
    local line = cur.npc.lines[index]
    if not line then return Dialog.Close() end
    cur.line = index
    local labels = {}
    for i, r in ipairs(line.replies) do labels[i] = r.label end
    if #labels == 0 then labels[1] = Config.Text.leave end
    send(line.text, labels)
end

--- A line from the server (a clue): only "Leave" after it
function Dialog.ShowText(text)
    if not cur then return end
    cur.line = nil
    send(text, { Config.Text.leave })
end

--- preview = { onClose = fn } for the builder: replies are played locally, nothing goes to the server
function Dialog.Open(huntId, npc, ped, preview)
    if cur or Hints.nuiOpen then return end
    if not ped or not DoesEntityExist(ped) or not npc.lines or #npc.lines == 0 then return end
    local me = PlayerPedId()
    if IsEntityDead(me) or LocalPlayer.state.isDead then return end

    cur = { huntId = huntId, npc = npc, ped = ped, cinematic = npc.cinematic, preview = preview }

    TaskTurnPedToFaceEntity(me, ped, 1200)
    TaskLookAtEntity(ped, me, -1, 2048, 3)

    if cur.cinematic then
        Camera.Focus(ped)
    elseif Config.Hud.hideRadarInClassic then
        Hud.Radar('dialog', true)
    end
    if Config.Hud.hideInDialog then Hud.Hold('dialog', true) end

    Hints.OpenNui('dialog', { style = cur.cinematic and 'cinematic' or 'classic', name = npc.name })
    Dialog.ShowLine(1)
end

function Dialog.Close()
    if not cur then return end
    local c = cur
    cur = nil
    if DoesEntityExist(c.ped) then TaskClearLookAt(c.ped) end
    Camera.Stop()
    Hud.Radar('dialog', false)
    Hud.Hold('dialog', false)
    if Hints.nuiOpen == 'dialog' then Hints.CloseNui() end
    if c.preview then
        if c.preview.onClose then c.preview.onClose(c.after) end
    else
        Steps.OnDialogClosed(c.huntId)
    end
end

-- builder preview: play the reply locally
local function previewReply(c, reply)
    if reply.action == 'give_clue' then
        local clue = tostring(reply.clue or ''):gsub('{piece}', '??')
        return Dialog.ShowText(clue ~= '' and clue or '[give_clue: no clue text]')
    elseif reply.action == 'open_shop' then
        return Dialog.ShowText(('[opens shop "%s"%s]'):format(tostring(reply.shop or c.npc.shop or Config.Shop.defaultId or '?'),
            reply.receipt and ' + receipt piece' or ''))
    elseif reply.action == 'open_password' then
        c.after = 'password'
    end
    Dialog.Close()
end

RegisterNUICallback('dialogReply', function(data, cb)
    cb(1)
    if not cur or cur.busy or type(data) ~= 'table' then return end
    local index = tonumber(data.index)
    if not index then return end

    if not cur.line then return Dialog.Close() end -- "Leave" after a clue
    local line = cur.npc.lines[cur.line]
    if not line or #line.replies == 0 then return Dialog.Close() end
    local reply = line.replies[index]
    if not reply then return end

    if reply.action == 'next_line' then
        return Dialog.ShowLine(lineIndexById(reply.next) or (cur.line + 1))
    end

    if cur.preview then return previewReply(cur, reply) end

    -- everything else is decided by the server
    local c = cur
    c.busy = true
    local res = lib.callback.await('blaze_hints:npcReply', false, c.huntId, c.line, index) or { close = true }
    if cur ~= c then return end
    c.busy = false

    if res.line then return Dialog.ShowText(res.line) end

    local huntId = c.huntId
    Dialog.Close()
    if res.openPassword then
        Wait(200)
        Hints.OpenPassword(huntId)
    elseif res.shop then
        Wait(200)
        Hints.OpenShop(res.shop)
    end
end)
