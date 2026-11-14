-- Deeprun Ledger: checking rows against the guild bank's money log
-- A row is verified once a deposit in the log has the same name and the same gold.
-- Old item rows never verify. They count for nothing anyway.

local addon_name, shared = ...

-- Settings
local match_window_seconds = 2 * 60 * 60 -- The logs only say how many hours ago, so times are rough


-- The logs say how long ago, not when. Months count as 30 days.
local function logTime(years, months, days, hours)
    local days_ago = (years * 12 + months) * 30 + days
    return GetServerTime() - (days_ago * 24 + hours) * 60 * 60
end


-- Every deposit in the money log.
-- Some log lines have no name: someone who's left or deleted, or a name the game hasn't
-- looked up yet. Those can't match anyone's row, so they're skipped.
local function readDeposits()
    local deposits = {}

    for index = 1, GetNumGuildBankMoneyTransactions() do
        local transaction_type, name, amount, years, months, days, hours = GetGuildBankMoneyTransaction(index)

        if transaction_type == "deposit" and name ~= nil then
            table.insert(deposits, {
                name = name,
                time = logTime(years, months, days, hours),
                gold = amount,
            })
        end
    end

    return deposits
end


-- Puts every deposit in a group keyed by who and how much gold
local function groupDeposits(deposits)
    local deposit_groups = {}

    for deposit_number, deposit in ipairs(deposits) do
        local group_key = deposit.name .. "|" .. deposit.gold

        if deposit_groups[group_key] == nil then
            deposit_groups[group_key] = {}
        end

        table.insert(deposit_groups[group_key], deposit)
    end

    return deposit_groups
end


-- Puts every row that isn't hidden in a group, with the same key as its deposit would have
local function groupRows()
    local row_groups = {}

    for row_number, row in ipairs(tithe_ledger.data) do
        if not shared.ignore_rows[row.transactionID] then
            local group_key = row.name .. "|" .. row.amount

            if row_groups[group_key] == nil then
                row_groups[group_key] = {}
            end

            table.insert(row_groups[group_key], row)
        end
    end

    return row_groups
end


-- Pairs the closest row and deposit, removes both, and repeats until no pair is inside the window.
-- Returns the rows that got a deposit. Paired deposits are gone from the deposits list afterwards.
local function pairClosest(rows, deposits)
    local paired_rows = {}

    while true do
        local best_row_number = nil
        local best_deposit_number = nil
        local best_gap = match_window_seconds + 1   -- anything inside the window beats this

        for row_number, row in ipairs(rows) do
            for deposit_number, deposit in ipairs(deposits) do
                local gap = math.abs(deposit.time - row.time)

                if gap < best_gap then
                    best_row_number = row_number
                    best_deposit_number = deposit_number
                    best_gap = gap
                end
            end
        end

        -- No pair left inside the window
        if best_row_number == nil then
            return paired_rows
        end

        table.insert(paired_rows, rows[best_row_number])
        table.remove(rows, best_row_number)
        table.remove(deposits, best_deposit_number)
    end
end


local function verifyRows()
    local deposit_groups = groupDeposits(readDeposits())
    local row_groups = groupRows()

    for group_key, deposits_in_group in pairs(deposit_groups) do
        local rows_in_group = row_groups[group_key]

        if rows_in_group ~= nil then
            local verified_rows = {}
            local unverified_rows = {}

            for row_number, row in ipairs(rows_in_group) do
                if row.verified == 1 then
                    table.insert(verified_rows, row)
                else
                    table.insert(unverified_rows, row)
                end
            end

            -- Green rows take their deposits first, so a fake row can't take one.
            -- A green row with no deposit left is just dropped. It stays green.
            pairClosest(verified_rows, deposits_in_group)

            -- Whatever deposits are left can turn unverified rows green
            local newly_verified_rows = pairClosest(unverified_rows, deposits_in_group)
            for row_number, row in ipairs(newly_verified_rows) do
                row.verified = 1
            end
        end
    end
end


local verification_frame = CreateFrame("Frame")
verification_frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
verification_frame:RegisterEvent("GUILDBANKLOG_UPDATE")

verification_frame:SetScript("OnEvent", function(self, event, interaction_type)
    -- The bank opening. GUILDBANKFRAME_OPENED never fires on Forever.
    -- The money log is the tab after the last item tab.
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and interaction_type == Enum.PlayerInteractionType.GuildBanker then
        QueryGuildBankLog(MAX_GUILDBANK_TABS + 1)

    elseif event == "GUILDBANKLOG_UPDATE" then
        verifyRows()
        shared.refreshIfOpen()
    end
end)
