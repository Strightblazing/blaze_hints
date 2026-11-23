fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'blaze_hints'
author 'Blaze'
description 'Clue hunts built in game: hints, inspect spots, NPC dialog, code pieces, password keypads, world scenes and personal stashes (Qbox, ox_lib)'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/util.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/hunts.lua',    -- DB load/save of hunts
    'server/codes.lua',    -- code generation, splitting into pieces across sources, checking
    'server/timelock.lua', -- time locks (server-side checks only)
    'server/scenes.lua',   -- shared world scenes (networked)
    'server/stash.lua',    -- personal ox_inventory stashes
    'server/progress.lua', -- per-character progress and the step engine
    'server/main.lua',     -- startup, events, callbacks, shop hooks, builder events, admin commands
}

client_scripts {
    'client/main.lua',     -- NUI helpers, code screens, items, shops, ready/cleanup
    'client/camera.lua',   -- cinematic camera + HUD hiding
    'client/dialog.lua',   -- NPC dialog (cinematic / classic)
    'client/inspect.lua',  -- inspect overlay
    'client/scenes.lua',   -- world scenes (private entities, effects, search blip)
    'client/steps.lua',    -- hint zones, password / inspect targets, NPCs, stash targets
    'client/builder.lua',  -- builder screen, menu builder, previews
}

ui_page 'web/index.html'
files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'ox_target',
    'ox_inventory',
    'qbx_core',
}
