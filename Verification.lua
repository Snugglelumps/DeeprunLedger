-- Deeprun Ledger: checking rows against the guild bank's own logs
-- A row is verified once a deposit in the log has the same name and the same gold or items.

local addon_name, shared = ...

-- Settings
local match_window_seconds = 2 * 60 * 60 -- The logs only say how many hours ago, so times are rough


-- The logs say how long ago, not when. Months count as 30 days.
local function logTime(years, months, days, hours)
    local days_ago = (years * 12 + months) * 30 + days
    return GetServerTime() - (days_ago * 24 + hours) * 60 * 60
end


-- Every deposit in the money log and each tab's item log
local function readDeposits()
    local deposits = {}

    for index = 1, GetNumGuildBankMoneyTransactions() do
        local transaction_type, name, amount, years, months, days, hours = GetGuildBankMoneyTransaction(index)

        if transaction_type == "deposit" then
            table.insert(deposits, {
                name = name,
                time = logTime(years, months, days, hours),
                gold = amount,
                item_id = 0,
                count = 0,
                used = false,
            })
        end
    end

    for tab = 1, GetNumGuildBankTabs() do
        for index = 1, GetNumGuildBankTransactions(tab) do
            local transaction_type, name, item_link, count, tab_from, tab_to, years, months, days, hours = GetGuildBankTransaction(tab, index)

            if transaction_type == "deposit" then
                table.insert(deposits, {
                    name = name,
                    time = logTime(years, months, days, hours),
                    gold = 0,
                    item_id = C_Item.GetItemInfoInstant(item_link),
                    count = count,
                    used = false,
                })
            end
        end
    end

    return deposits
end


local function depositMatchesRow(deposit, row)
    if deposit.used then
        return false
    end

    if deposit.name ~= row.name then
        return false
    end

    if math.abs(deposit.time - row.time) > match_window_seconds then
        return false
    end

    -- A gold row
    if #row.attachment == 0 then
        return deposit.item_id == 0 and deposit.gold == row.amount
    end

    local item = row.attachment[1]
    return deposit.item_id == item.item_id and deposit.count == item.count
end


-- Marks the first unused deposit that matches. One deposit can only back one row.
local function useMatchingDeposit(deposits, row)
    for deposit_number, deposit in ipairs(deposits) do
        if depositMatchesRow(deposit, row) then
            deposit.used = true
            return true
        end
    end

    return false
end


local function verifyRows()
    local deposits = readDeposits()

    -- Verified rows claim their deposits first, so running this again can't hand one to a second row
    for row_number, row in ipairs(tithe_ledger.data) do
        if row.verified == 1 and not shared.ignore_rows[row.transactionID] then
            useMatchingDeposit(deposits, row)
        end
    end

    for row_number, row in ipairs(tithe_ledger.data) do
        if row.verified == 0 and not shared.ignore_rows[row.transactionID] then
            if useMatchingDeposit(deposits, row) then
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

        for tab = 1, GetNumGuildBankTabs() do
            QueryGuildBankLog(tab)
        end

    elseif event == "GUILDBANKLOG_UPDATE" then
        verifyRows()
        shared.refreshIfOpen()
    end
end)
