Config = {}

Config.Debug = false               -- draws hint zones / target zones and prints engine logs

Config.CinematicDialog = true      -- true = letterbox + camera on NPC face + HUD hidden; false = small dialog panel bottom-right
Config.AdminGroup = 'admin'        -- checked as ace 'group.<AdminGroup>' or qbx_core:HasPermission(src, AdminGroup)
Config.BuilderCommand = 'huntbuilder' -- /huntbuilder (admins). '/huntbuilder menu' or '/huntbuilder nui' picks a style for that time
Config.BuilderStyle = 'nui'        -- 'nui' = full builder screen | 'menu' = ox_lib menus and inputs (Lation UI look when lation_ui is running)
Config.UseLationUI = true          -- menu builder: use lation_ui menus / inputs when it is started
Config.DefaultCooldown = 30        -- seconds locked out after MaxWrongTries wrong codes
Config.MaxWrongTries = 3
Config.ResetOnFail = false         -- default for password steps: true = after the lockout the hunt goes back and the player gets a new random code
Config.Accent = '#f26a21'

-- Time locks
Config.TimeZone = nil              -- real_time / date_window locks: nil = the server's own clock, or a UTC offset in hours (e.g. -5, 1, 10)
Config.TimeSync = 'auto'           -- in-game time source: 'auto' (detects Renewed-Weathersync / qb-weathersync) | 'renewed' | 'qb' | 'real'
Config.TimeLockCheck = 20          -- seconds between server checks for locks opening / closing

-- Distances (server checks)
Config.PasswordDistance = 10.0     -- from a password step's spot when submitting
Config.ZoneSlack = 5.0             -- extra metres allowed past a hint zone / scene radius
Config.NpcDistance = 5.0           -- from an NPC when picking a reply
Config.InspectDistance = 5.0       -- from an inspect spot
Config.StashDistance = 5.0         -- from a stash
Config.HintGap = 1500              -- ms between back-to-back "after previous" hints

-- Spawning (client)
Config.NpcSpawnDistance = 80.0     -- hunt NPCs only exist on your screen inside this range
Config.SceneSpawnDistance = 150.0  -- private world scenes only exist inside this range

-- Where-to-look markers: a floating icon over the current inspect spot, keypad and (unlocked) stash.
-- Only the hunter on that step sees it. Each step can turn it off in the builder ("Show a marker").
Config.Markers = {
    enabled = true,
    distance = 25.0,               -- shown inside this range
    icon = 32,                     -- GTA marker type: 32 = question mark, 2 = chevron, 29 = dollar sign, 20-22 = chevrons
    iconScale = 0.35,
    height = 0.75,                 -- metres above the spot
    bob = true,                    -- bob up and down
    ring = true,                   -- thin ring on the ground under it
    ringScale = 0.9,
    color = nil,                   -- { r, g, b, a }; nil = Config.Accent
    steps = { inspect = true, password = true, stash = true, npc = false },
}

-- Your HUD: hidden while hunt screens are open. The GTA HUD and minimap always hide during the cinematic dialog / camera.
-- It only shows again if it was on before, and only when nothing else here is still hiding it.
Config.Hud = {
    hideInDialog = true,           -- dialog (both styles)
    hideInKeypad = true,           -- keypad / word entry
    hideInReader = true,           -- note reader and inspect overlay
    hideInBuilder = true,          -- builder screen
    hideRadarInClassic = false,    -- also hide the GTA HUD + minimap during the classic (bottom-right) dialog
    -- Which export hides your HUD (client side). false = none. Either one "set visible" export:
    --   export = { resource = 'your_hud', set = 'setVisible', isVisible = 'isVisible' },
    -- or separate hide / show exports:
    --   export = { resource = 'your_hud', hide = 'hideHud', show = 'showHud' },
    export = { resource = 'element_hud', set = 'setHudVisible', isVisible = 'isHudVisible' },
    -- Or a function(hidden) for anything else, for example:
    --   toggle = function(hidden) TriggerEvent('your_hud:toggle', not hidden) end,
    -- HUDs can also listen to the client event 'blaze_hints:client:hud' (true = hide, false = show).
    toggle = false,
}

-- open_shop replies: Lation Shops when it is running (exports.lation_shops:openShop(id)), otherwise an ox_inventory shop of that type
Config.Shop = {
    system = 'auto',               -- 'auto' | 'lation' | 'ox'
    defaultId = nil,               -- used when a reply has no shop id
    receiptMinutes = 10,           -- a "shop receipt" code piece waits this long for the purchase after the shop opens
}

Config.Items = {
    note = 'blaze_note',           -- code piece written on a note (use it to read it)
    receipt = 'blaze_receipt',     -- code piece printed on a shop receipt
}

-- Personal stash defaults (per step in the builder)
Config.Stash = { slots = 20, maxWeight = 50000, label = 'Personal stash' }

-- Random words for 'word' password steps (the length setting picks words of that length when it can)
Config.Words = {
    'BLAZE', 'VAULT', 'RAVEN', 'GHOST', 'EMBER', 'CIPHER', 'HARBOR', 'ANCHOR', 'SILVER', 'COPPER', 'MARBLE',
    'LANTERN', 'MIDNIGHT', 'PHANTOM', 'JACKPOT', 'COMPASS', 'HORIZON', 'SAPPHIRE', 'SCORPION', 'THUNDER',
}

-- World scene presets. Offsets are { right, forward, up } from the scene coords, turned by its heading.
-- spot = where an inspect point / stash on that scene sits.
Config.ScenePresets = {
    armored_van = {
        label = 'Armored van',
        vehicle = 'stockade',
        rearDoors = { 2, 3 },      -- stockade rear doors (0 FL, 1 FR, 2 RL, 3 RR, 4 hood, 5 trunk)
        spot = { 0.0, -4.4, 0.0 }, -- behind the open rear doors
        guardSpots = { { -1.6, -6.2, 0.0, 180.0 }, { 1.6, -6.2, 0.0, 180.0 }, { -2.6, 1.5, 0.0, 90.0 }, { 2.6, 1.5, 0.0, 270.0 } },
        props = { { model = 'prop_money_bag_01', offset = { 0.4, -3.9, -0.55 } } },
        effects = { smoke = { 0.0, 2.6, 0.2 }, sparks = { 0.0, -3.4, 0.6 }, flare = { 2.5, -6.5, -0.9 } },
    },
    crate_drop = {
        label = 'Crate drop',
        spot = { 0.0, -1.0, 0.0 },
        guardSpots = { { -3.0, 2.0, 0.0, 0.0 }, { 3.0, 2.0, 0.0, 0.0 }, { -3.0, -3.0, 0.0, 180.0 }, { 3.0, -3.0, 0.0, 180.0 } },
        props = { { model = 'prop_mil_crate_01', offset = { 0.0, 0.0, -1.0 } }, { model = 'prop_box_ammo03a', offset = { 1.2, 0.4, -1.0 } } },
        effects = { smoke = { 0.0, 0.0, -0.8 }, sparks = { 0.0, 0.0, 0.0 }, flare = { 1.8, -1.2, -0.9 } },
    },
    briefcase = {
        label = 'Briefcase',
        spot = { 0.0, 0.0, -0.6 },
        guardSpots = { { -2.0, 1.5, 0.0, 0.0 }, { 2.0, 1.5, 0.0, 0.0 }, { -2.0, -2.0, 0.0, 180.0 }, { 2.0, -2.0, 0.0, 180.0 } },
        props = { { model = 'prop_ld_case_01', offset = { 0.0, 0.0, -0.95 } } },
        effects = { smoke = { 0.0, 1.0, -0.9 }, sparks = { 0.0, 0.0, -0.6 }, flare = { 1.0, -0.8, -0.9 } },
    },
}

Config.SceneEffects = {
    smoke = { asset = 'core', name = 'exp_grd_bzgas_smoke', scale = 0.8 },
    sparks = { asset = 'core', name = 'ent_amb_sparking_wires', scale = 1.2 },
    flare = { asset = 'core', name = 'exp_grd_flare', scale = 1.0 },
}

Config.Guards = {
    model = 's_m_m_security_01',
    calmWeapon = 'WEAPON_PISTOL',
    hostileWeapon = 'WEAPON_CARBINERIFLE',
    accuracy = 25,
}

Config.Notify = {
    duration = 7000,
    position = nil,                -- nil = ox_lib / Lation default
}

Config.Text = {
    newHint       = 'New hint',
    pieceLine     = 'Code piece: %s',
    pieceFound    = 'Code piece found',
    pieceCount    = '%d of %d',
    pieceOverlay  = 'Code piece %d of %d found',
    wrongCode     = 'Wrong code',
    triesLeft     = '%d tries left',
    lockedOut     = 'Too many wrong tries. Locked for %d seconds.',
    lockedReset   = 'Too many wrong tries. The trail went cold. Start over: you will need a new code.',
    cooldown      = 'Locked. Try again in %d seconds.',
    huntComplete  = 'Hunt complete',
    enterCode     = 'Enter code',
    notesTitle    = 'Hunt notes',
    noNotes       = 'You have not found any code pieces yet.',
    talk          = 'Talk',
    inspect       = 'Inspect',
    shopClosed    = 'Shop closed',
    shopClosedMsg = 'There is nothing for sale right now.',
    leave         = 'Leave',
    nothingHere   = 'Nothing here right now.',
    noteFound     = 'You found a note. Use it from your inventory to read it.',
    noteTitle     = 'A handwritten note',
    receiptFound  = 'Your receipt has something scribbled on it.',
    receiptTitle  = 'A shop receipt',
    stashUnlocked = 'Personal stash unlocked',
    stashUnlockedMsg = 'Something is waiting for you.',
    stashLocked   = 'Locked',
    stashLockedMsg = 'This will not open for you yet.',
    stashEmpty    = 'It is empty now.',
    comeBack      = 'Come back later',
    tooLate       = 'Too late',
    tooLateMsg    = 'You took too long. The trail went cold: start over with a new code.',
    stopInspect   = '[E] Stop inspecting',
    stopInspectLook = '[E] Stop inspecting  ·  Mouse to look around',
}
