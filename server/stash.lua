-- Personal stash: one ox_inventory stash per stash step, registered with owner = true so every
-- character gets their own copy (ox_inventory keeps it as '<id>:<citizenid>').
-- step = { type = 'stash', coords (or a scene / the scene step before it), label, slots, maxWeight,
--          mode = 'permanent' | 'reward', rewards = { { name, count, metadata } }, showWhileLocked = true }
-- The target is locked until the character reaches that step (everything before it is done).
-- On unlock the rewards go into that character's copy once.
-- permanent = personal storage that stays; reward = one-time box: gone once it is empty.
Stash = {}

function Stash.Id(hintId, step)
    return ('blaze_hints_%d_%s'):format(hintId, tostring(step.uid or 'x'))
end

--- The hint's stash step (the first one) and its index
function Stash.StepOf(hint)
    for i, step in ipairs(hint.steps) do
        if step.type == 'stash' then return step, i end
    end
end

function Stash.Spot(hint, index)
    return Progress.SpotFor(hint.steps, index)
end

--- Register every hint's stash with ox_inventory (on start and whenever a hint is saved)
function Stash.RegisterHint(hint)
    for i, step in ipairs(hint.steps) do
        if step.type == 'stash' then
            local spot = Stash.Spot(hint, i)
            exports.ox_inventory:RegisterStash(
                Stash.Id(hint.id, step),
                step.label or Config.Stash.label,
                math.max(1, math.floor(tonumber(step.slots) or Config.Stash.slots)),
                math.max(1000, math.floor(tonumber(step.maxWeight) or Config.Stash.maxWeight)),
                true,
                nil,
                spot
            )
        end
    end
end

local function invRef(hintId, step, citizenid)
    return { id = Stash.Id(hintId, step), owner = citizenid }
end

--- The character reached the stash step: unlock and add the rewards (once)
function Stash.Unlock(src, row, hint, step)
    if row.unlocked_stash ~= 0 then return end
    row.unlocked_stash = 1
    Progress.SaveRow(row)
    Stash.RegisterHint(hint)
    local inv = invRef(hint.id, step, row.citizenid)
    for _, r in ipairs(type(step.rewards) == 'table' and step.rewards or {}) do
        local count = math.max(1, math.floor(tonumber(r.count) or 1))
        if type(r.name) == 'string' and r.name ~= '' then
            local ok, err = exports.ox_inventory:AddItem(inv, r.name, count, type(r.metadata) == 'table' and r.metadata or nil)
            if not ok then
                print(('^3[blaze_hints]^7 stash reward %s x%d for %s failed: %s'):format(r.name, count, row.citizenid, tostring(err)))
            end
        end
    end
    Progress.Notify(src, 'success', Config.Text.stashUnlocked, step.unlockText or Config.Text.stashUnlockedMsg)
end

--- What the client should show for this hint's stash (nil = nothing)
function Stash.Info(hint, row)
    local step, index = Stash.StepOf(hint)
    if not step or not row or row.unlocked_stash == 2 then return end
    local unlocked = row.unlocked_stash == 1
    if not unlocked and step.showWhileLocked == false then return end
    local spot = Stash.Spot(hint, index)
    if not spot then return end
    local info = {
        key = ('stash:%d:%s'):format(hint.id, tostring(step.uid)),
        coords = { x = spot.x, y = spot.y, z = spot.z },
        label = step.label or Config.Stash.label,
        unlocked = unlocked,
        marker = unlocked and Progress.MarkerOn(step, 'stash') or nil, -- only once it opens for you
    }
    -- the scene it sits on stays while the stash is there. Private scenes only: a shared scene exists
    -- (server side) while someone is on its step. Same key as the step's scene, so it is never spawned twice.
    local owner = Progress.StashSceneOwner(hint.steps, index)
    if owner and owner.scene.visibility ~= 'shared' then
        info.scene = Progress.SceneInfo(owner.scene, owner)
        if info.scene then info.scene.key = ('scene:%d:%s'):format(hint.id, tostring(owner.uid)) end
    end
    return info
end

function Stash.Sync(src, hintId)
    local state = Progress.players[src]
    local hint = Hints.Get(hintId)
    local row = state and state.rows[hintId]
    local info = (hint and hint.enabled and row) and Stash.Info(hint, row) or nil
    TriggerClientEvent('blaze_hints:client:stash', src, hintId, info)
end

--- Player used the stash target
function Stash.Open(src, hintId)
    local state = Progress.players[src]
    local hint = Hints.Get(hintId)
    local row = state and state.rows[hintId]
    if not hint or not row then return end
    local step, index = Stash.StepOf(hint)
    if not step then return end
    local spot = Stash.Spot(hint, index)
    if not spot or #(GetEntityCoords(GetPlayerPed(src)) - spot) > Config.StashDistance then return end

    if row.unlocked_stash ~= 1 then
        Progress.Notify(src, 'error', Config.Text.stashLocked, Config.Text.stashLockedMsg)
        return
    end

    Stash.RegisterHint(hint)
    local inv = invRef(hint.id, step, row.citizenid)

    if step.mode == 'reward' then
        local items = exports.ox_inventory:GetInventoryItems(inv.id, inv.owner)
        if not items or next(items) == nil then
            row.unlocked_stash = 2 -- claimed: the box goes away
            Progress.SaveRow(row)
            Progress.Notify(src, 'inform', step.label or Config.Stash.label, Config.Text.stashEmpty)
            Stash.Sync(src, hintId)
            return
        end
    end

    exports.ox_inventory:forceOpenInventory(src, 'stash', inv)
end
