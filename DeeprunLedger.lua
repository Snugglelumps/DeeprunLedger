-- Deeprun Ledger
-- The treasurer's side: records tithe mail, checks each one's transaction ID,
-- and shows who paid what in a date range. Open it with /drl.

-- shared.sha256 comes from sha256.lua, shared.secret from guild_config.lua
local addon_name, shared = ...


------------------------------------------------------------
-- Settings
------------------------------------------------------------

local trade_goods_multiplier = 3

-- tithe_ledger is one flat list of tithe mails, saved account-wide (see DeeprunLedger.toc).
-- One row per mail:
--   { transactionID = "1793000000-9f2c4a81be", name = "Bob", amount = <gold, in copper>,
--     attachment = { { item_name = "Linen Cloth", count = 20, value = <copper> } },
--     total_value = <gold plus item values, in copper> }
-- The number before the dash is when the tithe was sent.

-- Every transaction ID already in the ledger. A repeated one gets turned away.
local seen_transaction_ids = {}


------------------------------------------------------------
-- Transaction IDs
------------------------------------------------------------

-- The time it was sent, a dash, then the first 10 characters of the hash of
-- that time, the sender's name and the secret.
-- DeeprunTithe makes them with this same function.
local function makeTransactionID(sent_time, player_name)
    local full_hash = shared.sha256(sent_time .. player_name .. shared.secret)
    return sent_time .. "-" .. string.sub(full_hash, 1, 10)
end


-- True if the tithe addon made this ID for this sender
local function isValidTransactionID(transaction_id, sender)
    local sent_time = string.match(transaction_id, "^(%d+)%-")
    if sent_time == nil then
        return false
    end

    return transaction_id == makeTransactionID(sent_time, sender)
end


-- When a tithe was sent, read from the front of its transaction ID
local function rowDate(row)
    local formatted_date = tonumber(string.match(row.transactionID, "^(%d+)"))
    return formatted_date
end


------------------------------------------------------------
-- Ledger helpers
------------------------------------------------------------

-- Every payment in the range, newest first
local function getPaymentsInRange(start_date, end_date)
    local payments = {}

    for row_number, row in ipairs(tithe_ledger) do
        if rowDate(row) >= start_date and rowDate(row) <= end_date then
            table.insert(payments, row)
        end
    end

    table.sort(payments, function(first, second)
        return rowDate(first) > rowDate(second)
    end)

    return payments
end


-- Each player's total and payment count, biggest total first
local function getPlayerTotals(payments)
    local totals_by_name = {}
    local player_totals = {}

    for payment_number, row in ipairs(payments) do
        local player_total = totals_by_name[row.name]

        if player_total == nil then
            player_total = { player = row.name, copper = 0, payments = 0 }
            totals_by_name[row.name] = player_total
            table.insert(player_totals, player_total)
        end

        player_total.copper = player_total.copper + row.total_value
        player_total.payments = player_total.payments + 1
    end

    table.sort(player_totals, function(first, second)
        return first.copper > second.copper
    end)

    return player_totals
end


------------------------------------------------------------
-- Dates and money
------------------------------------------------------------

-- Reads two date fields. Returns nil if either isn't a date like 2026-11-04,
-- or if the start is after the end.
local function getRangeDates(start_field, end_field)
    local start_year, start_month, start_day = string.match(start_field:GetText(), "^(%d%d%d%d)-(%d%d?)-(%d%d?)$")
    local end_year, end_month, end_day = string.match(end_field:GetText(), "^(%d%d%d%d)-(%d%d?)-(%d%d?)$")

    if start_year == nil or end_year == nil then
        return nil
    end

    local start_date = time({ year = tonumber(start_year), month = tonumber(start_month), day = tonumber(start_day), hour = 0, min = 0, sec = 0 })
    local end_date = time({ year = tonumber(end_year), month = tonumber(end_month), day = tonumber(end_day), hour = 23, min = 59, sec = 59 })

    if start_date > end_date then
        return nil
    end

    return start_date, end_date
end


local function friendlyDate(timestamp)
    return date("%b %d, %I:%M%p", timestamp)
end


local function moneyText(copper)
    if copper == 0 then
        return "0"
    end
    return GetMoneyString(copper)
end


------------------------------------------------------------
-- Custom button, thanks Claude
------------------------------------------------------------

local function makeFlatButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 22)
    button:SetNormalFontObject("GameFontHighlightSmall")
    button:SetText(text)

    button.background = button:CreateTexture(nil, "BACKGROUND")
    button.background:SetAllPoints()
    button.background:SetColorTexture(1, 1, 1, 0.07)

    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.08)

    return button
end

local function setButtonSelected(button, is_selected)
    if is_selected then
        button.background:SetColorTexture(1, 0.82, 0, 0.30)
    else
        button.background:SetColorTexture(1, 1, 1, 0.07)
    end
end

-- A slightly lighter box that groups one section of the page
local function makePanel(parent, left, top, width, height)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -top)
    panel:SetSize(width, height)

    local fill = panel:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(1, 1, 1, 0.04)

    return panel
end


------------------------------------------------------------
-- The page
--   [Week] [Month] [All]   [start date] to [end date] [Go]
--   Totals:   each player in the range, biggest first (scrolls)
--   Payments: every tithe in the range, newest first (scrolls)
------------------------------------------------------------

local main_frame = nil

-- Range controls
local week_button = nil
local month_button = nil
local all_button = nil
local start_date_field = nil
local end_date_field = nil
local active_range = "week"   -- "week", "month", "all" or "custom"
local message_label = nil

-- Totals list
local totals_scroll_child = nil
local total_rows = {}
local grand_total_label = nil
local totals_message = nil

-- Payments list
local payments_scroll_child = nil
local payment_rows = {}
local payments_message = nil


local function getTotalRow(row_number)
    local row = total_rows[row_number]

    if row == nil then
        row = CreateFrame("Frame", nil, totals_scroll_child)
        row:SetSize(532, 18)
        row:SetPoint("TOPLEFT", totals_scroll_child, "TOPLEFT", 0, -18 * (row_number - 1))

        row.shade = row:CreateTexture(nil, "BACKGROUND")
        row.shade:SetAllPoints()
        row.shade:SetColorTexture(1, 1, 1, 0.04)

        row.player_label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.player_label:SetPoint("LEFT", row, "LEFT", 8, 0)

        row.payments_label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.payments_label:SetPoint("LEFT", row, "LEFT", 200, 0)

        row.share_label = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.share_label:SetPoint("LEFT", row, "LEFT", 300, 0)

        row.total_label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.total_label:SetPoint("RIGHT", row, "RIGHT", -8, 0)

        total_rows[row_number] = row
    end

    if row_number % 2 == 0 then
        row.shade:Show()
    else
        row.shade:Hide()
    end

    row:Show()
    return row
end


local function updateTotals(player_totals)
    for row_number, row in ipairs(total_rows) do
        row:Hide()
    end

    local range_total = 0
    local payment_count = 0
    for total_number, player_total in ipairs(player_totals) do
        range_total = range_total + player_total.copper
        payment_count = payment_count + player_total.payments
    end

    grand_total_label:SetText(moneyText(range_total) .. " from " .. payment_count .. " payments")

    if #player_totals == 0 then
        totals_message:SetText("Nobody paid in this range")
    else
        totals_message:SetText("")
    end

    for row_number, player_total in ipairs(player_totals) do
        local share = 0
        if range_total > 0 then
            share = math.floor(100 * player_total.copper / range_total + 0.5)
        end

        local row = getTotalRow(row_number)
        row.player_label:SetText(player_total.player)
        row.payments_label:SetText(tostring(player_total.payments))
        row.share_label:SetText(share .. "%")
        row.total_label:SetText(moneyText(player_total.copper))
    end

    totals_scroll_child:SetHeight(18 * #player_totals + 4)
end


-- a row int he payment list: date, player, gold, items, total, with every other row shaded
-- one at a time so they stay aligned. wrote this in python calude translated it lol
local function getPaymentRow(row_number)
    local row = payment_rows[row_number]

    if row == nil then
        row = CreateFrame("Frame", nil, payments_scroll_child)
        row:SetSize(532, 18)
        row:SetPoint("TOPLEFT", payments_scroll_child, "TOPLEFT", 0, -18 * (row_number - 1))

        row.shade = row:CreateTexture(nil, "BACKGROUND")
        row.shade:SetAllPoints()
        row.shade:SetColorTexture(1, 1, 1, 0.04)

        row.date_label = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.date_label:SetPoint("LEFT", row, "LEFT", 8, 0)

        row.player_label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.player_label:SetPoint("LEFT", row, "LEFT", 130, 0)

        row.gold_label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.gold_label:SetPoint("RIGHT", row, "RIGHT", -200, 0)

        row.items_label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.items_label:SetPoint("RIGHT", row, "RIGHT", -100, 0)

        row.total_label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.total_label:SetPoint("RIGHT", row, "RIGHT", -8, 0)

        payment_rows[row_number] = row
    end

    if row_number % 2 == 0 then
        row.shade:Show()
    else
        row.shade:Hide()
    end

    row:Show()
    return row
end


local function updatePayments(payments)
    for row_number, row in ipairs(payment_rows) do
        row:Hide()
    end

    if #payments == 0 then
        payments_message:SetText("No payments in this range")
    else
        payments_message:SetText("")
    end

    for row_number, ledger_row in ipairs(payments) do
        local row = getPaymentRow(row_number)
        row.date_label:SetText(friendlyDate(rowDate(ledger_row)))
        row.player_label:SetText(ledger_row.name)
        row.gold_label:SetText(moneyText(ledger_row.amount))
        row.items_label:SetText(moneyText(ledger_row.total_value - ledger_row.amount))
        row.total_label:SetText(moneyText(ledger_row.total_value))
    end

    payments_scroll_child:SetHeight(18 * #payments + 4)
end


local function updateRangeButtons()
    setButtonSelected(week_button, active_range == "week")
    setButtonSelected(month_button, active_range == "month")
    setButtonSelected(all_button, active_range == "all")
end


local function refreshView()
    updateRangeButtons()

    local start_date, end_date = getRangeDates(start_date_field, end_date_field)

    if start_date == nil then
        message_label:SetText("Dates need to look like 2026-11-04, with the start on or before the end")
        return
    end

    message_label:SetText("")

    local payments = getPaymentsInRange(start_date, end_date)

    updateTotals(getPlayerTotals(payments))
    updatePayments(payments)
end


------------------------------------------------------------
-- Range buttons: fill in the two date fields
------------------------------------------------------------

local function fillLastDays(day_count)
    local today = date("*t")
    local first_day = time({ year = today.year, month = today.month, day = today.day - (day_count - 1), hour = 12 })

    start_date_field:SetText(date("%Y-%m-%d", first_day))
    end_date_field:SetText(date("%Y-%m-%d"))
end

local function fillWeek()
    active_range = "week"
    fillLastDays(7)
end

local function fillMonth()
    active_range = "month"
    fillLastDays(30)
end

-- From the oldest tithe in the ledger to today
local function fillAll()
    active_range = "all"

    local first_date = time()
    for row_number, row in ipairs(tithe_ledger) do
        if rowDate(row) < first_date then
            first_date = rowDate(row)
        end
    end

    start_date_field:SetText(date("%Y-%m-%d", first_date))
    end_date_field:SetText(date("%Y-%m-%d"))
end

-- Typed dates: none of the range buttons stay lit
local function useTypedDates()
    active_range = "custom"
end


------------------------------------------------------------
-- window
------------------------------------------------------------

local function buildWindow()
    main_frame = CreateFrame("Frame", "DeeprunLedgerFrame", UIParent, "BasicFrameTemplateWithInset")
    main_frame:SetSize(600, 560)
    main_frame:SetPoint("CENTER")
    main_frame.TitleText:SetText("Deeprun Ledger")
    main_frame:SetMovable(true)
    main_frame:EnableMouse(true)
    main_frame:RegisterForDrag("LeftButton")
    main_frame:SetScript("OnDragStart", main_frame.StartMoving)
    main_frame:SetScript("OnDragStop", main_frame.StopMovingOrSizing)
    main_frame:Hide()

    -- Escape closes it, like other game windows
    table.insert(UISpecialFrames, "DeeprunLedgerFrame")

    -- A flat dark background over the template's stone texture, below the title bar
    local content = CreateFrame("Frame", nil, main_frame)
    content:SetPoint("TOPLEFT", main_frame, "TOPLEFT", 3, -22)
    content:SetPoint("BOTTOMRIGHT", main_frame, "BOTTOMRIGHT", -3, 3)

    local content_background = content:CreateTexture(nil, "BACKGROUND")
    content_background:SetAllPoints()
    content_background:SetColorTexture(0.05, 0.05, 0.06, 0.97)

    -- Range row: [Week] [Month] [All]   [start date] to [end date] [Go]
    week_button = makeFlatButton(content, "Week", 60)
    week_button:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -10)
    week_button:SetScript("OnClick", function()
        fillWeek()
        refreshView()
    end)

    month_button = makeFlatButton(content, "Month", 60)
    month_button:SetPoint("LEFT", week_button, "RIGHT", 4, 0)
    month_button:SetScript("OnClick", function()
        fillMonth()
        refreshView()
    end)

    all_button = makeFlatButton(content, "All", 60)
    all_button:SetPoint("LEFT", month_button, "RIGHT", 4, 0)
    all_button:SetScript("OnClick", function()
        fillAll()
        refreshView()
    end)

    start_date_field = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    start_date_field:SetSize(86, 20)
    start_date_field:SetPoint("LEFT", all_button, "RIGHT", 24, 0)
    start_date_field:SetAutoFocus(false)
    start_date_field:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        useTypedDates()
        refreshView()
    end)

    local to_label = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    to_label:SetPoint("LEFT", start_date_field, "RIGHT", 6, 0)
    to_label:SetText("to")

    end_date_field = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    end_date_field:SetSize(86, 20)
    end_date_field:SetPoint("LEFT", to_label, "RIGHT", 12, 0)
    end_date_field:SetAutoFocus(false)
    end_date_field:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        useTypedDates()
        refreshView()
    end)

    local go_button = makeFlatButton(content, "Go", 40)
    go_button:SetPoint("LEFT", end_date_field, "RIGHT", 8, 0)
    go_button:SetScript("OnClick", function()
        useTypedDates()
        refreshView()
    end)

    message_label = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    message_label:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -38)

    -- Totals panel
    local totals_panel = makePanel(content, 12, 56, 570, 180)

    local totals_title = totals_panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totals_title:SetPoint("TOPLEFT", totals_panel, "TOPLEFT", 12, -10)
    totals_title:SetText("Totals")

    grand_total_label = totals_panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    grand_total_label:SetPoint("TOPRIGHT", totals_panel, "TOPRIGHT", -12, -12)

    local totals_player_heading = totals_panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    totals_player_heading:SetPoint("TOPLEFT", totals_panel, "TOPLEFT", 16, -30)
    totals_player_heading:SetText("Player")

    local totals_payments_heading = totals_panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    totals_payments_heading:SetPoint("TOPLEFT", totals_panel, "TOPLEFT", 208, -30)
    totals_payments_heading:SetText("Payments")

    local totals_share_heading = totals_panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    totals_share_heading:SetPoint("TOPLEFT", totals_panel, "TOPLEFT", 308, -30)
    totals_share_heading:SetText("Share")

    local totals_total_heading = totals_panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    totals_total_heading:SetPoint("TOPRIGHT", totals_panel, "TOPRIGHT", -38, -30)
    totals_total_heading:SetText("Total")

    local totals_scroll = CreateFrame("ScrollFrame", nil, totals_panel, "UIPanelScrollFrameTemplate")
    totals_scroll:SetPoint("TOPLEFT", totals_panel, "TOPLEFT", 8, -46)
    totals_scroll:SetPoint("BOTTOMRIGHT", totals_panel, "BOTTOMRIGHT", -30, 8)

    totals_scroll_child = CreateFrame("Frame", nil, totals_scroll)
    totals_scroll_child:SetSize(532, 100)
    totals_scroll:SetScrollChild(totals_scroll_child)

    totals_message = totals_scroll_child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    totals_message:SetPoint("TOPLEFT", totals_scroll_child, "TOPLEFT", 8, -2)

    -- Payments panel
    local payments_panel = makePanel(content, 12, 246, 570, 284)

    local payments_title = payments_panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    payments_title:SetPoint("TOPLEFT", payments_panel, "TOPLEFT", 12, -10)
    payments_title:SetText("Payments")

    local payments_date_heading = payments_panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    payments_date_heading:SetPoint("TOPLEFT", payments_panel, "TOPLEFT", 16, -30)
    payments_date_heading:SetText("Sent")

    local payments_player_heading = payments_panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    payments_player_heading:SetPoint("TOPLEFT", payments_panel, "TOPLEFT", 138, -30)
    payments_player_heading:SetText("Player")

    local payments_gold_heading = payments_panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    payments_gold_heading:SetPoint("TOPRIGHT", payments_panel, "TOPRIGHT", -238, -30)
    payments_gold_heading:SetText("Gold")

    local payments_items_heading = payments_panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    payments_items_heading:SetPoint("TOPRIGHT", payments_panel, "TOPRIGHT", -138, -30)
    payments_items_heading:SetText("Items")

    local payments_total_heading = payments_panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    payments_total_heading:SetPoint("TOPRIGHT", payments_panel, "TOPRIGHT", -38, -30)
    payments_total_heading:SetText("Total")

    local payments_scroll = CreateFrame("ScrollFrame", nil, payments_panel, "UIPanelScrollFrameTemplate")
    payments_scroll:SetPoint("TOPLEFT", payments_panel, "TOPLEFT", 8, -46)
    payments_scroll:SetPoint("BOTTOMRIGHT", payments_panel, "BOTTOMRIGHT", -30, 8)

    payments_scroll_child = CreateFrame("Frame", nil, payments_scroll)
    payments_scroll_child:SetSize(532, 100)
    payments_scroll:SetScrollChild(payments_scroll_child)

    payments_message = payments_scroll_child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    payments_message:SetPoint("TOPLEFT", payments_scroll_child, "TOPLEFT", 8, -2)
end


local function refreshIfOpen()
    if main_frame:IsShown() then
        refreshView()
    end
end


------------------------------------------------------------
-- recording the mail
------------------------------------------------------------

-- this calculates the value of trade goods. its just a flat * trade_goids_multiplier.
-- i suppose using some market db would be smart, but idk... thats a LOT more work
local function itemTitheValue(item_id, stack_count, item_quality)
    local vendor_price = select(11, C_Item.GetItemInfo(item_id))
    local item_class_id = select(12, C_Item.GetItemInfo(item_id))

    if vendor_price == nil then
        return 0
    end

    -- Grays make debt but don't pay it. Must match DeeprunTithe.
    if item_quality == Enum.ItemQuality.Poor then
        return 0
    end

    if item_class_id == Enum.ItemClass.Tradegoods then
        return vendor_price * stack_count * trade_goods_multiplier
    end

    return 0
end


local function recordMail(mail_number)
    -- Without the code from Guild Info there's nothing to check IDs against
    if shared.secret == nil then
        return
    end

    local package_icon, stationery_icon, sender, subject, money, cod_amount = GetInboxHeaderInfo(mail_number)

    -- i dont really understand the cod thing. 
    -- to my eye it shows up as just a value.. which I think could trick the system??
    if cod_amount > 0 then
        return
    end

    local transaction_id = string.match(subject, "%d+%-%x+")
    if transaction_id == nil then
        return
    end

    if seen_transaction_ids[transaction_id] then
        return
    end

    if not isValidTransactionID(transaction_id, sender) then
        return
    end

    local attachments = {}
    local total_value = money

    for attachment_number = 1, ATTACHMENTS_MAX_RECEIVE do
        local item_name, item_id, item_texture, stack_count, item_quality = GetInboxItem(mail_number, attachment_number)

        if item_id ~= nil then
            local item_value = itemTitheValue(item_id, stack_count, item_quality)
            table.insert(attachments, { item_name = item_name, count = stack_count, value = item_value })
            total_value = total_value + item_value
        end
    end

    table.insert(tithe_ledger, {
        transactionID = transaction_id,
        name = sender,
        amount = money,
        attachment = attachments,
        total_value = total_value,
    })
    seen_transaction_ids[transaction_id] = true
end


local function onMailTaken(mail_number)
    recordMail(mail_number)
    refreshIfOpen()
end


hooksecurefunc("TakeInboxMoney", onMailTaken)
hooksecurefunc("TakeInboxItem", onMailTaken)
hooksecurefunc("AutoLootMailItem", onMailTaken)


------------------------------------------------------------
-- Startup and slash command
------------------------------------------------------------

-- The sync app writes rows from the gist into incoming_rows.lua, which loads on /reload.
-- It holds the whole ledger, so most rows here are ones we already have.
local function mergeIncomingRows()
    if shared.incoming_rows == nil then
        return
    end

    for row_number, row in ipairs(shared.incoming_rows) do
        if not seen_transaction_ids[row.transactionID] then
            table.insert(tithe_ledger, row)
            seen_transaction_ids[row.transactionID] = true
        end
    end
end


local ledger_events = CreateFrame("Frame")
ledger_events:RegisterEvent("PLAYER_LOGIN")

ledger_events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- First time on this account, there's no saved ledger yet
        if tithe_ledger == nil then
            tithe_ledger = {}
        end

        for row_number, row in ipairs(tithe_ledger) do
            seen_transaction_ids[row.transactionID] = true
        end

        mergeIncomingRows()
        buildWindow()
    end
end)

SLASH_DEEPRUNLEDGER1 = "/drl"
SlashCmdList["DEEPRUNLEDGER"] = function(typed_text)
    if typed_text == "hash" then
        shared.showHashWindow()
        return
    end

    main_frame:Show()

    -- Open on the last week the first time, then keep whatever range was picked
    if start_date_field:GetText() == "" then
        fillWeek()
    end

    refreshView()
end
