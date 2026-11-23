-- Startup banner + version check (same look as Blaze Medical / Blaze Boss Menu).
-- The check reads 'repository' from fxmanifest.lua ('owner/name' on GitHub) and compares this version with
-- the latest GitHub release. Turn it off with Config.VersionCheck = false.
local RES = GetCurrentResourceName()
local VERSION = GetResourceMetadata(RES, 'version', 0) or '0.0.0'
local REPO = GetResourceMetadata(RES, 'repository', 0)

local DISCORD = 'https://discord.gg/u6b6nCDJMa' -- Blaze Scriptworks: support and updates

local TAGLINES = {
    'Clues hidden.', 'Notes scribbled.', 'Keypads wired.', 'Riddles sharpened.',
    'Breadcrumbs scattered.', 'The van is parked.', 'Stashes locked.', 'Follow the hints.',
}

-- '1.2.10' vs '1.2.9' -> 1 / 0 / -1 (a leading 'v' is ignored)
local function compare(a, b)
    local function parts(v)
        local t = {}
        for n in tostring(v):gsub('^v', ''):gmatch('%d+') do t[#t + 1] = tonumber(n) end
        return t
    end
    local x, y = parts(a), parts(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q and 1 or -1 end
    end
    return 0
end

local WIDTH = 58
-- one boxed line: pads to WIDTH, ignoring colour codes (^1 etc) and counting characters, not bytes
local function boxed(text)
    local visible = text:gsub('%^%d', '')
    local len = (utf8 and utf8.len(visible)) or #visible
    return '^3|^7' .. text .. (' '):rep(math.max(0, WIDTH - len)) .. '^3|^7'
end

-- Blaze Scriptworks logo as console art: red flame with a white </>, white BLAZE, gold SCRIPTWORKS, red bar,
-- gold frame (^1 red, ^3 gold, ^7 white). Plain ASCII, so it lines up in any console.
local FLAME = {
    [[^1      (     ]],
    [[^1     ) )    ]],
    [[^1    ( ( (   ]],
    [[^1   ) )/\ )  ]],
    [[^1  ( ^7</>^1 (   ]],
    [[^1   \____/   ]],
}
local WORD = {
    [[                                     ]],
    [[ ____   _         _     _____  _____ ]],
    [[| __ ) | |       / \   |__  / | ____|]],
    [[|  _ \ | |      / _ \    / /  |  _|  ]],
    [[| |_) || |___  / ___ \  / /_  | |___ ]],
    [[|____/ |_____|/_/   \_\/____| |_____|]],
}
local function logo()
    local out = {}
    for i = 1, #FLAME do out[#out + 1] = boxed('  ' .. FLAME[i] .. '^7' .. WORD[i]) end
    out[#out + 1] = boxed((' '):rep(22) .. '^3S C R I P T W O R K S^7')
    out[#out + 1] = boxed((' '):rep(14) .. '^1' .. ('='):rep(37) .. '^7')
    return out
end

local function timeSource()
    local want = Config.TimeSync or 'auto'
    if want == 'real' then return 'real clock' end
    if (want == 'auto' or want == 'renewed') and GetResourceState('Renewed-Weathersync') == 'started' then return 'Renewed-Weathersync' end
    if (want == 'auto' or want == 'qb') and GetResourceState('qb-weathersync') == 'started' then return 'qb-weathersync' end
    return 'real clock'
end

--- Print the "fully started" banner (after the hints have loaded from the database)
local function banner()
    local hints, on, steps = 0, 0, 0
    for _, h in pairs(Hints.All()) do
        hints = hints + 1
        if h.enabled then on = on + 1 end
        steps = steps + #h.steps
    end
    local ui = (Config.UseLationUI and GetResourceState('lation_ui') == 'started') and 'Lation UI' or 'ox_lib'
    local shop = GetResourceState('lation_shops') == 'started' and 'Lation Shops' or 'ox shops'
    local line = '^3+' .. ('-'):rep(WIDTH) .. '+^7'
    print(line)
    for _, l in ipairs(logo()) do print(l) end
    print(boxed(''))
    print(boxed(('  ^7HINTS ^1v%s^7  ·  Qbox · ox_target · %s'):format(VERSION, ui)))
    print(boxed(('  %d hints (%d on) · %d steps · %s'):format(hints, on, steps, shop)))
    print(boxed(('  In-game time: %s'):format(timeSource())))
    print(boxed('  ^2Fully started.^7 ' .. TAGLINES[math.random(#TAGLINES)]))
    print(boxed('  ^3Support & updates:^7 ' .. DISCORD .. ' ')) -- full https:// link so consoles make it clickable
    print(line)
end

local function check()
    if Config.VersionCheck == false then return end
    if type(REPO) ~= 'string' or not REPO:match('^[%w%-_%.]+/[%w%-_%.]+$') then
        print('^3[blaze_hints]^7 Version check is off: set repository \'owner/name\' in fxmanifest.lua to turn it on.')
        return
    end
    PerformHttpRequest(('https://api.github.com/repos/%s/releases/latest'):format(REPO), function(status, body)
        local latest = status == 200 and body and (json.decode(body) or {}).tag_name
        if not latest then
            if status == 404 then
                print(('^5[blaze_hints]^7 Running v%s. No GitHub release published yet, so there is nothing to compare.'):format(VERSION))
            else
                print('^3[blaze_hints]^7 Couldn\'t check for updates right now. No worries, everything still works.')
            end
            return
        end
        local c = compare(VERSION, latest)
        if c == 0 then
            print(('^2[blaze_hints] Blaze Hints is up to date (v%s). %s^7'):format(VERSION, TAGLINES[math.random(#TAGLINES)]))
        elseif c < 0 then
            print(('^3[blaze_hints] Update available: %s (you have v%s). Get it at https://github.com/%s/releases/latest^7'):format(latest, VERSION, REPO))
        else
            print(('^5[blaze_hints]^7 Running v%s, newer than the latest release (%s). Dev build?'):format(VERSION, latest))
        end
    end, 'GET', '', { ['User-Agent'] = 'blaze_hints', ['Accept'] = 'application/vnd.github+json' })
end

CreateThread(function()
    -- wait until the hints have loaded, so the banner means "fully started" and its counts are right (at most 20 s)
    local untilT = GetGameTimer() + 20000
    repeat Wait(500) until Hints.loaded or GetGameTimer() > untilT
    Wait(1000) -- after the other startup lines, so the banner isn't buried
    banner()
    check()
end)
