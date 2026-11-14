-- Deeprun Ledger: saving tithe rows
-- Every ledger online saves every row it hears. Only the answering one ACKs (Ready.lua).
-- The sync merges the duplicates by ID.

local addon_name, shared = ...


local function send(message)
    C_ChatInfo.SendAddonMessage(shared.prefix, message, "GUILD")
end


local function ackIfAnswering(transaction_id)
    if shared.isAnswering() then
        send(shared.ackMessage(transaction_id))
    end
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


function shared.saveRow(message, sender)
    local row = build_row(message, sender)
    if row == nil then
        return
    end

    -- Deleted, so the tithe can stop sending it, but it doesn't come back
    if shared.ignore_rows[row.transactionID] then
        ackIfAnswering(row.transactionID)
        return
    end

    if shared.seen_transaction_ids[row.transactionID] then
        ackIfAnswering(row.transactionID)
        return
    end

    table.insert(tithe_ledger.data, row)
    shared.seen_transaction_ids[row.transactionID] = true
    shared.refreshIfOpen()

    ackIfAnswering(row.transactionID)
end

