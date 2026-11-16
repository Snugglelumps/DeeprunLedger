-- Deeprun Ledger: accounts, to tie alts together
-- Every tithe answers RDY with ACC|<account id>. We record the character under that ID with the time.
-- Every ledger listens, the quiet ones too, so everyone's Personnel tab works.
--
-- An account's main is the character promoted last. If nobody's been promoted, it's the
-- character who's paid the most gold. Promoting never removes anything, it just writes a newer time.
--
-- Saved in tithe_ledger (see DeeprunLedger.toc), and shared through the gist by the sync app:
--   accounts  { [account id] = { [character] = last time it sent ACC } }
--   mains     { [account id] = { [character] = time it was promoted } }   the latest is the main
--
-- Not saved, for the status dots: when each character was last heard this session.
-- A /reload clears it.

local addon_name, shared = ...

-- Settings
-- Tithes answer every RDY, so a character online is heard about this often. One and a half RDYs.
local green_window_seconds = shared.ready_every_seconds * 1.5

local heard_this_session = {}   -- [character] = GetServerTime() of its last ACC


function shared.heardAccount(message, sender)
    local account_id = string.sub(message, 5)

    if string.match(account_id, "^%x%x%x%x%-%x%x%x%x%x%x$") == nil then
        return
    end

    if tithe_ledger.accounts[account_id] == nil then
        tithe_ledger.accounts[account_id] = {}
    end

    tithe_ledger.accounts[account_id][sender] = GetServerTime()
    heard_this_session[sender] = GetServerTime()
end


function shared.promoteMain(account_id, character)
    if tithe_ledger.mains[account_id] == nil then
        tithe_ledger.mains[account_id] = {}
    end

    tithe_ledger.mains[account_id][character] = GetServerTime()
end


-- Everyone's gold from every payment that isn't deleted. Worked out once, then handed to accountMain.
function shared.goldByName()
    local gold_by_name = {}

    for row_number, row in ipairs(tithe_ledger.data) do
        if not shared.ignore_rows[row.transactionID] then
            gold_by_name[row.name] = (gold_by_name[row.name] or 0) + row.amount
        end
    end

    return gold_by_name
end


-- Promoted last, or else the most gold. Ties on gold go by name, so it doesn't jump around.
function shared.accountMain(account_id, gold_by_name)
    local main = nil
    local promoted_time = 0

    for character, promoted in pairs(tithe_ledger.mains[account_id] or {}) do
        if promoted > promoted_time then
            main = character
            promoted_time = promoted
        end
    end

    if main ~= nil then
        return main
    end

    local most_gold = -1

    for character in pairs(tithe_ledger.accounts[account_id]) do
        local gold = gold_by_name[character] or 0

        if gold > most_gold or (gold == most_gold and character < main) then
            main = character
            most_gold = gold
        end
    end

    return main
end


------------------------------------------------------------
-- Status dots
------------------------------------------------------------

-- "green": the latest heard on its account, heard inside the green window.
-- "yellow": heard this session, but not lately, or another character on the account came after it.
-- "gray": not heard this session.
-- WoW only lets one character per account be online, so only one per account can be green.
function shared.characterStatus(account_id, character)
    local heard = heard_this_session[character]

    if heard == nil then
        return "gray"
    end

    if GetServerTime() - heard > green_window_seconds then
        return "yellow"
    end

    for other_character in pairs(tithe_ledger.accounts[account_id]) do
        local other_heard = heard_this_session[other_character]

        if other_heard ~= nil and other_heard > heard then
            return "yellow"
        end
    end

    return "green"
end


-- The same colour as its latest heard character, or gray if none have been heard
function shared.accountStatus(account_id)
    local latest_character = nil
    local latest_heard = 0

    for character in pairs(tithe_ledger.accounts[account_id]) do
        local heard = heard_this_session[character]

        if heard ~= nil and heard > latest_heard then
            latest_character = character
            latest_heard = heard
        end
    end

    if latest_character == nil then
        return "gray"
    end

    return shared.characterStatus(account_id, latest_character)
end


------------------------------------------------------------
-- From the sync app
------------------------------------------------------------

-- Every account and character from both sides. Where both have one, the later time wins.
local function keepLaterTimes(saved, incoming)
    for account_id, characters in pairs(incoming) do
        if saved[account_id] == nil then
            saved[account_id] = {}
        end

        for character, incoming_time in pairs(characters) do
            local saved_time = saved[account_id][character]

            if saved_time == nil or incoming_time > saved_time then
                saved[account_id][character] = incoming_time
            end
        end
    end
end


-- incoming_rows.lua (see DeeprunLedger.lua). An older sync app doesn't write accounts or mains,
-- so each one is skipped if it isn't there.
function shared.mergeIncomingAccounts()
    if shared.incoming_rows == nil then
        return
    end

    if shared.incoming_rows.accounts ~= nil then
        keepLaterTimes(tithe_ledger.accounts, shared.incoming_rows.accounts)
    end

    if shared.incoming_rows.mains ~= nil then
        keepLaterTimes(tithe_ledger.mains, shared.incoming_rows.mains)
    end
end
