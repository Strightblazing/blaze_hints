-- Personal stash: one ox_inventory stash per stash step, registered with owner = true so every
-- character gets their own copy (ox_inventory keeps it as '<id>:<citizenid>').
-- step = { type = 'stash', coords (or a scene / the scene step before it), label, slots, maxWeight,
--          mode = 'permanent' | 'reward', rewards = { { name, count, metadata } }, showWhileLocked = true }
-- The target is locked until the character reaches that step (everything before it is done).
-- On unlock the rewards go into that character's copy once.
-- permanent = personal storage that stays; reward = one-time box: gone once it is empty.
Stash = {}

function Stash.Id(huntId, step)
    return ('blaze_hints_%d_%s'):format(huntId, tostring(step.uid or 'x'))
end

--- The hunt's stash step (the first one) and its index
function Stash.StepOf(hunt)
    for i, step in ipairs(hunt.steps) do
        if step.type == 'stash' then return step, i end
    end
end

function Stash.Spot(hunt, index)
    return Progress.SpotFor(hunt.steps, index)
end

--- Register every hunt's stash with ox_inventory (on start and whenever a hunt is saved)
function Stash.RegisterHunt(hunt)
    for i, step in ipairs(hunt.steps) do
        if step.type == 'stash' then
            local spot = Stash.Spot(hunt, i)
            exports.ox_inventory:RegisterStash(
                Stash.Id(hunt.id, step),
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

local function invRef(huntId, step, citizenid)
    return { id = Stash.Id(huntId, step), owner = citizenid }
end

--- The character reached the stash step: unlock and add the rewards (once)
function Stash.Unlock(src, row, hunt, step)
    if row.unlocked_stash ~= 0 then return end
    row.unlocked_stash = 1
    Progress.SaveRow(row)
    Stash.RegisterHunt(hunt)
    local inv = invRef(hunt.id, step, row.citizenid)
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

--- What the client should show for this hunt's stash (nil = nothing)
function Stash.Info(hunt, row)
    local step, index = Stash.StepOf(hunt)
    if not step or not row or row.unlocked_stash == 2 then return end
    local unlocked = row.unlocked_stash == 1
    if not unlocked and step.showWhileLocked == false then return end
    local spot = Stash.Spot(hunt, index)
    if not spot then return end
    local info = {
        key = ('stash:%d:%s'):format(hunt.id, tostring(step.uid)),
        coords = { x = spot.x, y = spot.y, z = spot.z },
        label = step.label or Config.Stash.label,
        unlocked = unlocked,
        marker = unlocked and Progress.MarkerOn(step, 'stash') or nil, -- only once it opens for you
    }
    -- the scene it sits on stays while the stash is there. Private scenes only: a shared scene exists
    -- (server side) while someone is on its step. Same key as the step's scene, so it is never spawned twice.
    local owner = Progress.StashSceneOwner(hunt.steps, index)
    if owner and owner.scene.visibility ~= 'shared' then
        info.scene = Progress.SceneInfo(owner.scene, owner)
        if info.scene then info.scene.key = ('scene:%d:%s'):format(hunt.id, tostring(owner.uid)) end
    end
    return info
end

function Stash.Sync(src, huntId)
    local state = Progress.players[src]
    local hunt = Hunts.Get(huntId)
    local row = state and state.rows[huntId]
    local info = (hunt and hunt.enabled and row) and Stash.Info(hunt, row) or nil
    TriggerClientEvent('blaze_hints:client:stash', src, huntId, info)
end

--- Player used the stash target
function Stash.Open(src, huntId)
    local state = Progress.players[src]
    local hunt = Hunts.Get(huntId)
    local row = state and state.rows[huntId]
    if not hunt or not row then return end
    local step, index = Stash.StepOf(hunt)
    if not step then return end
    local spot = Stash.Spot(hunt, index)
    if not spot or #(GetEntityCoords(GetPlayerPed(src)) - spot) > Config.StashDistance then return end

    if row.unlocked_stash ~= 1 then
        Progress.Notify(src, 'error', Config.Text.stashLocked, Config.Text.stashLockedMsg)
        return
    end

    Stash.RegisterHunt(hunt)
    local inv = invRef(hunt.id, step, row.citizenid)

    if step.mode == 'reward' then
        local items = exports.ox_inventory:GetInventoryItems(inv.id, inv.owner)
        if not items or next(items) == nil then
            row.unlocked_stash = 2 -- claimed: the box goes away
            Progress.SaveRow(row)
            Progress.Notify(src, 'inform', step.label or Config.Stash.label, Config.Text.stashEmpty)
            Stash.Sync(src, huntId)
            return
        end
    end

    exports.ox_inventory:forceOpenInventory(src, 'stash', inv)
end
