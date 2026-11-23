-- Codes: generated and checked on the server only. The full code never leaves this side
-- (the word scramble shows the letters in a shuffled order when that source is on).
Codes = {}

local DIGITS = '0123456789'
local MAX_LENGTH = 12

-- Code sources a password step can use. Pieces are split across the steps (between the previous
-- password step and this one) that carry one of the chosen kinds.
Codes.SourceKinds = { 'message', 'note', 'inspect', 'npc', 'receipt', 'scramble' }

function Codes.Length(step)
    return math.max(1, math.min(math.floor(tonumber(step.length) or 4), MAX_LENGTH))
end

function Codes.IsFixed(step)
    return step.codeMode == 'fixed' and step.code ~= nil and tostring(step.code) ~= ''
end

function Codes.Normalize(value, inputType)
    value = tostring(value or ''):gsub('%s+', '')
    if inputType == 'word' then value = value:upper() end
    return value
end

function Codes.RandomDigits(length)
    local out = {}
    for i = 1, length do
        local n = math.random(1, #DIGITS)
        out[i] = DIGITS:sub(n, n)
    end
    return table.concat(out)
end

function Codes.RandomWord(length)
    local exact, all = {}, {}
    for _, w in ipairs(Config.Words or {}) do
        w = tostring(w):upper()
        all[#all + 1] = w
        if #w == length then exact[#exact + 1] = w end
    end
    local pool = #exact > 0 and exact or all
    if #pool == 0 then return 'BLAZE' end
    return pool[math.random(1, #pool)]
end

--- The code value a player should get for a password step
function Codes.ForStep(step)
    if Codes.IsFixed(step) then
        return Codes.Normalize(step.code, step.inputType)
    end
    if step.inputType == 'word' then
        return Codes.RandomWord(Codes.Length(step))
    end
    return Codes.RandomDigits(Codes.Length(step))
end

function Codes.Match(input, code, inputType)
    if type(input) ~= 'string' or #input > 32 then return false end
    return Codes.Normalize(input, inputType) == code
end

--- The letters of a code in a shuffled order (never the same order when it can avoid it)
function Codes.Scramble(code)
    local chars = {}
    for i = 1, #code do chars[i] = code:sub(i, i) end
    for _ = 1, 5 do
        for i = #chars, 2, -1 do
            local j = math.random(1, i)
            chars[i], chars[j] = chars[j], chars[i]
        end
        if table.concat(chars) ~= code then break end
    end
    return chars
end

function Codes.UsesSource(step, kind)
    if type(step.sources) ~= 'table' then
        return kind ~= 'scramble' -- no choice made: every piece source, no scramble
    end
    return step.sources[kind] == true
end

--- Index of the first password step at or after `from`
function Codes.NextPassword(steps, from)
    for i = math.max(1, from or 1), #steps do
        if steps[i].type == 'password' then return i end
    end
end

--- Index of the last password step before `before` (0 if none)
function Codes.PrevPassword(steps, before)
    for i = (before or 1) - 1, 1, -1 do
        if steps[i].type == 'password' then return i end
    end
    return 0
end

--- Piece kinds a step can carry
local function stepKinds(step)
    local kinds = {}
    if step.type == 'message' and step.piece then
        kinds[1] = step.deliver == 'note' and 'note' or 'message'
    elseif step.type == 'inspect' and step.piece then
        kinds[1] = step.deliver == 'note' and 'note' or 'inspect'
    elseif step.type == 'npc' and type(step.dialog) == 'table' then
        local riddle, receipt = false, false
        for _, line in ipairs(step.dialog) do
            for _, r in ipairs(type(line.replies) == 'table' and line.replies or {}) do
                if r.action == 'give_clue' and r.piece then riddle = true end
                if r.action == 'open_shop' and r.receipt then receipt = true end
            end
        end
        if riddle then kinds[#kinds + 1] = 'npc' end
        if receipt then kinds[#kinds + 1] = 'receipt' end
    end
    return kinds
end

--- Slots carrying pieces of the code for the password step at index p: { { index, kind, key } }
function Codes.Slots(steps, p)
    local slots, pw = {}, steps[p]
    if not pw then return slots end
    for i = Codes.PrevPassword(steps, p) + 1, p - 1 do
        for _, kind in ipairs(stepKinds(steps[i])) do
            if Codes.UsesSource(pw, kind) then
                slots[#slots + 1] = { index = i, kind = kind, key = ('%d:%s'):format(i, kind) }
            end
        end
    end
    return slots
end

--- Split `code` into up to `n` contiguous pieces (earlier pieces get the leftover characters)
function Codes.Split(code, n)
    local len = #code
    n = math.max(0, math.min(n, len))
    local pieces, pos = {}, 1
    if n == 0 then return pieces end
    local base, extra = len // n, len % n
    for i = 1, n do
        local size = base + (i <= extra and 1 or 0)
        pieces[i] = code:sub(pos, pos + size - 1)
        pos = pos + size
    end
    return pieces
end

--- The piece carried by step `index` (kind `kind`) for code `code`: piece, position, total, key
function Codes.PieceFor(steps, code, index, kind)
    local p = Codes.NextPassword(steps, index)
    if not p then return end
    local slots = Codes.Slots(steps, p)
    local pieces = Codes.Split(code, #slots)
    for k, slot in ipairs(slots) do
        if slot.index == index and slot.kind == kind then
            if not pieces[k] then return end -- more piece steps than characters
            return pieces[k], k, #pieces, slot.key
        end
    end
end

--- Put a piece into a text: replaces {piece}, or adds a "Code piece: X" line
function Codes.Insert(text, piece)
    text = tostring(text or '')
    if text:find('{piece}', 1, true) then
        return (text:gsub('{piece}', function() return piece end))
    end
    return (text ~= '' and (text .. '\n') or '') .. Config.Text.pieceLine:format(piece)
end
