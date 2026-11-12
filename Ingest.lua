-- Deeprun Ledger: the listener
-- Every ledger online records every tithe row and ACKs it. The sync merges the duplicates by ID.

local addon_name, shared = ...

-- Settings
local rdy_every_seconds = 300 -- Tithes stop sending if they haven't heard RDY in 6 minutes


local function send(message)
    C_ChatInfo.SendAddonMessage(shared.prefix, message, "GUILD")
end


-- Turns a ROW message into a ledger row, or nil if it doesn't check out
local function build_row(message, sender)
    local message_type, sent_time, encoded_part, gold, item_id, item_count = strsplit("|", message)
    local transaction_id = sent_time .. "|" .. encoded_part

    -- The ID has to match what the real sender would have made.
    -- That catches someone else's name inside it, and gold or items that don't match the ID.
    if shared.makeTransactionID(sender, sent_time, gold, item_id, item_count) ~= transaction_id then
        return nil
    end

    local attachment = {}
    if tonumber(item_id) ~= 0 then
        table.insert(attachment, { item_id = tonumber(item_id), count = tonumber(item_count) })
    end

    return {
        transactionID = transaction_id,
        name = sender,
        time = tonumber(sent_time),
        amount = tonumber(gold),
        attachment = attachment,
        verified = 0,
    }
end


local function listener(message, sender)
    if string.sub(message, 1, 4) ~= "ROW|" then
        return
    end

    local row = build_row(message, sender)
    if row == nil then
        return
    end

    -- Deleted, so the tithe can stop sending it, but it doesn't come back
    if shared.ignore_rows[row.transactionID] then
        send(shared.ackMessage(row.transactionID))
        return
    end

    if shared.seen_transaction_ids[row.transactionID] then
        send(shared.ackMessage(row.transactionID))
        return
    end

    table.insert(tithe_ledger.data, row)
    shared.seen_transaction_ids[row.transactionID] = true
    shared.refreshIfOpen()

    send(shared.ackMessage(row.transactionID))
end


local ingest_frame = CreateFrame("Frame")
ingest_frame:RegisterEvent("PLAYER_LOGIN")
ingest_frame:RegisterEvent("CHAT_MSG_ADDON")

ingest_frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        C_ChatInfo.RegisterAddonMessagePrefix(shared.prefix)

        send(shared.rdyMessage())
        C_Timer.NewTicker(rdy_every_seconds, function()
            send(shared.rdyMessage())
        end)

    elseif event == "CHAT_MSG_ADDON" then
        local message_prefix, message, channel, sender = ...
        if message_prefix == shared.prefix then
            listener(message, sender)
        end
    end
end)
