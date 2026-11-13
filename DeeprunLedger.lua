-- Deeprun Ledger
-- The treasurer's side: shows who paid what in a date range. Open it with /drl.
-- Ingest.lua records the rows, Verification.lua checks them against the guild bank.

-- The prefix, rates, transaction IDs and item credit come from DeeprunShared.lua
local addon_name, shared = ...


------------------------------------------------------------
-- Settings
------------------------------------------------------------

-- Same number as the sync app's interval. Change both together.
local sync_interval_seconds = 600

-- tithe_ledger is saved account-wide (see DeeprunLedger.toc):
--   data    one row per deposit:
--     { transactionID = "<time>|<base64>", name = "First Last", time = <seconds>,
--       amount = <gold, in copper, 0 for items>, attachment = {} or { { item_id = 2589, count = 20 } },
--       verified = 0 or 1 }
--   delete  a list of transactionIDs. Those rows stay in data, hidden. Nothing ever comes off the list.
-- Rows store what was deposited, never what it's worth.

-- Every transaction ID in data. A repeated one gets ACKed but not added again.
shared.seen_transaction_ids = {}

-- Every transaction ID with a delete row. Hidden everywhere.
shared.ignore_rows = {}


------------------------------------------------------------
-- Ledger helpers
------------------------------------------------------------

function shared.rebuildIgnoreRows()
    shared.ignore_rows = {}

    for delete_number, transaction_id in ipairs(tithe_ledger.delete) do
        shared.ignore_rows[transaction_id] = true
    end
end


-- Gold plus what the items are worth. An item that hasn't loaded yet counts 0 until it does.
local function rowContribution(row)
    local contribution = row.amount

    for attachment_number, item in ipairs(row.attachment) do
        if C_Item.GetItemInfo(item.item_id) == nil then
            C_Item.RequestLoadItemDataByID(item.item_id)
        end

        contribution = contribution + shared.itemCreditValue(item.item_id, item.count)
    end

    return math.floor(contribution)
end


-- Every payment in the range, newest first
local function getPaymentsInRange(start_date, end_date)
    local payments = {}

    for row_number, row in ipairs(tithe_ledger.data) do
        if not shared.ignore_rows[row.transactionID] then
            if row.time >= start_date and row.time <= end_date then
                table.insert(payments, row)
            end
        end
    end

    table.sort(payments, function(first, second)
        return first.time > second.time
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

        player_total.copper = player_total.copper + rowContribution(row)
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


local function timeAgoText(seconds)
    if seconds < 60 * 60 then
        return math.floor(seconds / 60) .. " min ago"
    end

    if seconds < 48 * 60 * 60 then
        return math.floor(seconds / (60 * 60)) .. " hours ago"
    end

    return math.floor(seconds / (24 * 60 * 60)) .. " days ago"
end


------------------------------------------------------------
-- Window pieces, all Blizzard's own art, like FishLog's windows
------------------------------------------------------------

local function makeButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    return button
end

-- The range you're looking at stays lit
local function setButtonSelected(button, is_selected)
    if is_selected then
        button:LockHighlight()
    else
        button:UnlockHighlight()
    end
end

-- A sunken box with the Auction House's list background, for a list to sit in
local function makeListBox(parent)
    local list_box = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")

    local art = list_box:CreateTexture(nil, "BACKGROUND", nil, 2)
    art:SetAtlas("auctionhouse-background-index")
    art:SetPoint("TOPLEFT", 3, -3)
    art:SetPoint("BOTTOMRIGHT", -3, 3)

    return list_box
end

-- A list row that glows like the Auction House's when you hover it.
-- A Button, because only buttons draw their HIGHLIGHT layer on hover.
local function makeListRow(parent, row_number)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(532, 18)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -18 * (row_number - 1))

    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetAtlas("auctionhouse-ui-row-highlight")
    hover:SetBlendMode("ADD")

    row.shade = row:CreateTexture(nil, "BACKGROUND")
    row.shade:SetAllPoints()
    row.shade:SetColorTexture(1, 1, 1, 0.04)

    return row
end

-- A column heading, in gold above its list
local function makeHeading(list_box, text, point, x)
    local heading = list_box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    heading:SetPoint("BOTTOM" .. point, list_box, "TOP" .. point, x, 4)
    heading:SetText(text)
    return heading
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
local sync_label = nil

-- Totals list
local totals_scroll_child = nil
local total_rows = {}
local grand_total_label = nil
local totals_message = nil

-- Payments list
local payments_scroll_child = nil
local payment_rows = {}
local payments_message = nil


-- Right-clicking a player sets what they owe (Commands.lua)
local function getTotalRow(row_number)
    local row = total_rows[row_number]

    if row == nil then
        row = makeListRow(totals_scroll_child, row_number)
        row:RegisterForClicks("RightButtonUp")
        row:SetScript("OnClick", function(self)
            shared.showSetTithe(self.player)
        end)

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
        row.player = player_total.player
        row.player_label:SetText(player_total.player)
        row.payments_label:SetText(tostring(player_total.payments))
        row.share_label:SetText(share .. "%")
        row.total_label:SetText(moneyText(player_total.copper))
    end

    totals_scroll_child:SetHeight(18 * #player_totals + 4)
end


------------------------------------------------------------
-- Payment details: click a payment to see everything about it
------------------------------------------------------------

local details_frame = nil
local details_fields = {}

-- The fields, in order. Each one's text is a box you can copy from.
local details_labels = {
    "Transaction ID",
    "Player",
    "Sent",
    "Sent (Unix time)",
    "Gold (copper)",
    "Item ID",
    "Item name",
    "Item count",
    "Counts for (copper)",
    "Verified",
}


-- A box you can select and copy from, but not change.
-- Typing puts the value straight back. Clicking in selects it all, ready for Ctrl+C.
local function makeCopyField(label_text, top)
    local label = details_frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", details_frame, "TOPLEFT", 72, top - 4)
    label:SetText(label_text)

    local field = CreateFrame("EditBox", nil, details_frame, "InputBoxTemplate")
    field:SetPoint("TOPLEFT", details_frame, "TOPLEFT", 200, top)
    field:SetPoint("TOPRIGHT", details_frame, "TOPRIGHT", -18, top)
    field:SetHeight(20)
    field:SetAutoFocus(false)

    field:SetScript("OnTextChanged", function(self, typed)
        if typed then
            self:SetText(self.value)
            self:HighlightText()
        end
    end)

    field:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)

    field:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    return field
end


-- The same portrait window as the ledger, beside it on the right
local function buildDetailsWindow()
    details_frame = CreateFrame("Frame", "DeeprunPaymentDetailsFrame", main_frame, "PortraitFrameTemplate")
    details_frame:SetSize(480, 46 + 26 * #details_labels)
    details_frame:SetPoint("TOPLEFT", main_frame, "TOPRIGHT", 4, 0)
    details_frame:SetTitle("Payment")
    details_frame:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Coin_17")
    details_frame:EnableMouse(true)

    table.insert(UISpecialFrames, "DeeprunPaymentDetailsFrame")

    for field_number, label_text in ipairs(details_labels) do
        details_fields[label_text] = makeCopyField(label_text, -36 - 26 * (field_number - 1))
    end
end


local function setDetail(label_text, value)
    local field = details_fields[label_text]
    field.value = tostring(value)
    field:SetText(field.value)
    field:SetCursorPosition(0)
end


-- Fills the details window with one payment and shows it
local function showPaymentDetails(ledger_row)
    if details_frame == nil then
        buildDetailsWindow()
    end

    -- Rows hold at most one item. No item shows as 0 and blank, the way the bank log has it.
    local item_id = 0
    local item_count = 0
    local item_name = ""

    if #ledger_row.attachment > 0 then
        item_id = ledger_row.attachment[1].item_id
        item_count = ledger_row.attachment[1].count
        item_name = C_Item.GetItemInfo(item_id) or "Not loaded yet. Click the payment again."
    end

    local verified = "No"
    if ledger_row.verified == 1 then
        verified = "Yes"
    end

    setDetail("Transaction ID", ledger_row.transactionID)
    setDetail("Player", ledger_row.name)
    setDetail("Sent", date("%Y-%m-%d %H:%M:%S", ledger_row.time))
    setDetail("Sent (Unix time)", ledger_row.time)
    setDetail("Gold (copper)", ledger_row.amount)
    setDetail("Item ID", item_id)
    setDetail("Item name", item_name)
    setDetail("Item count", item_count)
    setDetail("Counts for (copper)", rowContribution(ledger_row))
    setDetail("Verified", verified)

    details_frame:Show()
end


-- a row int he payment list: date, player, gold, total, verified, with every other row shaded
-- one at a time so they stay aligned. wrote this in python calude translated it lol
-- Clicking one opens its details.
local function getPaymentRow(row_number)
    local row = payment_rows[row_number]

    if row == nil then
        row = makeListRow(payments_scroll_child, row_number)
        row:SetScript("OnClick", function(self)
            showPaymentDetails(self.ledger_row)
        end)

        row.date_label = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.date_label:SetPoint("LEFT", row, "LEFT", 8, 0)

        row.player_label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.player_label:SetPoint("LEFT", row, "LEFT", 130, 0)

        row.gold_label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.gold_label:SetPoint("RIGHT", row, "RIGHT", -210, 0)

        row.total_label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.total_label:SetPoint("RIGHT", row, "RIGHT", -110, 0)

        row.verified_label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.verified_label:SetPoint("RIGHT", row, "RIGHT", -60, 0)

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
        row.ledger_row = ledger_row
        row.date_label:SetText(friendlyDate(ledger_row.time))
        row.player_label:SetText(ledger_row.name)
        row.gold_label:SetText(moneyText(ledger_row.amount))
        row.total_label:SetText(moneyText(rowContribution(ledger_row)))

        if ledger_row.verified == 1 then
            row.verified_label:SetText("Yes")
            row.verified_label:SetTextColor(0.25, 0.8, 0.4)
        else
            row.verified_label:SetText("No")
            row.verified_label:SetTextColor(1, 0.3, 0.3)
        end
    end

    payments_scroll_child:SetHeight(18 * #payments + 4)
end


local function updateRangeButtons()
    setButtonSelected(week_button, active_range == "week")
    setButtonSelected(month_button, active_range == "month")
    setButtonSelected(all_button, active_range == "all")
end


-- The sync app rewrites deeprun_sync_status every sync, WoW open or not.
-- So at login a running app's status is never older than sync_interval_seconds. It's checked then and kept
-- until the next reload, so a dead app shows red right away and a live one never goes red mid-session.
local sync_is_stale = false

local function checkSyncAtLogin()
    if deeprun_sync_status == nil then
        return
    end

    -- Twice the interval, so a sync that's a few seconds late doesn't trip it
    sync_is_stale = time() - deeprun_sync_status.time > 2 * sync_interval_seconds
end


local function updateSyncStatus()
    if deeprun_sync_status == nil then
        sync_label:SetText("Never synced")
        sync_label:SetTextColor(1, 0.3, 0.3)
        return
    end

    local seconds_since_sync = time() - deeprun_sync_status.time
    local sync_text = "Last synced " .. timeAgoText(seconds_since_sync) .. " · " .. deeprun_sync_status.rows_added .. " rows added"

    if sync_is_stale then
        sync_label:SetText(sync_text .. " · Check that the sync app is running")
        sync_label:SetTextColor(1, 0.3, 0.3)
        return
    end

    sync_label:SetText(sync_text)
    sync_label:SetTextColor(0.5, 0.5, 0.5)
end


local function refreshView()
    shared.rebuildIgnoreRows()
    updateRangeButtons()
    updateSyncStatus()

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
    for row_number, row in ipairs(tithe_ledger.data) do
        if row.time < first_date then
            first_date = row.time
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

-- A scrolling list inside a list box, rows 532 wide. Returns the scroll child the rows go on.
local function makeScrollList(list_box)
    local scroll = CreateFrame("ScrollFrame", nil, list_box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", list_box, "TOPLEFT", 8, -6)
    scroll:SetPoint("BOTTOMRIGHT", list_box, "BOTTOMRIGHT", -28, 6)

    local scroll_child = CreateFrame("Frame", nil, scroll)
    scroll_child:SetSize(532, 100)
    scroll:SetScrollChild(scroll_child)

    return scroll_child
end


-- The window is Blizzard's portrait frame, like the character and profession windows.
-- The coin in the portrait takes the top left corner, so the top row starts right of it.
local function buildWindow()
    main_frame = CreateFrame("Frame", "DeeprunLedgerFrame", UIParent, "PortraitFrameTemplate")
    main_frame:SetSize(600, 600)
    main_frame:SetPoint("CENTER")
    -- The version is ## Version: in DeeprunLedger.toc. The sync app checks the same number.
    main_frame:SetTitle("Deeprun Ledger " .. C_AddOns.GetAddOnMetadata(addon_name, "Version"))
    main_frame:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Coin_17")
    main_frame:SetMovable(true)
    main_frame:EnableMouse(true)
    main_frame:RegisterForDrag("LeftButton")
    main_frame:SetScript("OnDragStart", main_frame.StartMoving)
    main_frame:SetScript("OnDragStop", main_frame.StopMovingOrSizing)
    main_frame:Hide()

    -- Escape closes it, like other game windows
    table.insert(UISpecialFrames, "DeeprunLedgerFrame")

    -- Range row: [Week] [Month] [All]   [start date] to [end date] [Go]
    week_button = makeButton(main_frame, "Week", 60)
    week_button:SetPoint("TOPLEFT", main_frame, "TOPLEFT", 70, -32)
    week_button:SetScript("OnClick", function()
        fillWeek()
        refreshView()
    end)

    month_button = makeButton(main_frame, "Month", 60)
    month_button:SetPoint("LEFT", week_button, "RIGHT", 4, 0)
    month_button:SetScript("OnClick", function()
        fillMonth()
        refreshView()
    end)

    all_button = makeButton(main_frame, "All", 60)
    all_button:SetPoint("LEFT", month_button, "RIGHT", 4, 0)
    all_button:SetScript("OnClick", function()
        fillAll()
        refreshView()
    end)

    start_date_field = CreateFrame("EditBox", nil, main_frame, "InputBoxTemplate")
    start_date_field:SetSize(86, 20)
    start_date_field:SetPoint("LEFT", all_button, "RIGHT", 24, 0)
    start_date_field:SetAutoFocus(false)
    start_date_field:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        useTypedDates()
        refreshView()
    end)

    local to_label = main_frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    to_label:SetPoint("LEFT", start_date_field, "RIGHT", 6, 0)
    to_label:SetText("to")

    end_date_field = CreateFrame("EditBox", nil, main_frame, "InputBoxTemplate")
    end_date_field:SetSize(86, 20)
    end_date_field:SetPoint("LEFT", to_label, "RIGHT", 12, 0)
    end_date_field:SetAutoFocus(false)
    end_date_field:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        useTypedDates()
        refreshView()
    end)

    local go_button = makeButton(main_frame, "Go", 40)
    go_button:SetPoint("LEFT", end_date_field, "RIGHT", 8, 0)
    go_button:SetScript("OnClick", function()
        useTypedDates()
        refreshView()
    end)

    message_label = main_frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    message_label:SetPoint("TOPLEFT", main_frame, "TOPLEFT", 72, -62)

    sync_label = main_frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sync_label:SetPoint("TOPRIGHT", main_frame, "TOPRIGHT", -16, -62)

    -- Totals: title and headings on the window, the list in its box under them
    local totals_box = makeListBox(main_frame)
    totals_box:SetPoint("TOPLEFT", main_frame, "TOPLEFT", 12, -120)
    totals_box:SetPoint("TOPRIGHT", main_frame, "TOPRIGHT", -12, -120)
    totals_box:SetHeight(170)

    local totals_title = main_frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totals_title:SetPoint("BOTTOMLEFT", totals_box, "TOPLEFT", 4, 22)
    totals_title:SetText("Totals")

    grand_total_label = main_frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    grand_total_label:SetPoint("BOTTOMRIGHT", totals_box, "TOPRIGHT", -4, 22)

    -- Each heading sits over its column. The right ones are 44 in, for the scroll bar.
    makeHeading(totals_box, "Player", "LEFT", 16)
    makeHeading(totals_box, "Payments", "LEFT", 208)
    makeHeading(totals_box, "Share", "LEFT", 308)
    makeHeading(totals_box, "Total", "RIGHT", -44)

    totals_scroll_child = makeScrollList(totals_box)

    totals_message = totals_scroll_child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    totals_message:SetPoint("TOPLEFT", totals_scroll_child, "TOPLEFT", 8, -2)

    -- Payments: the same, filling the rest of the window
    local payments_box = makeListBox(main_frame)
    payments_box:SetPoint("TOPLEFT", main_frame, "TOPLEFT", 12, -336)
    payments_box:SetPoint("BOTTOMRIGHT", main_frame, "BOTTOMRIGHT", -12, 12)

    local payments_title = main_frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    payments_title:SetPoint("BOTTOMLEFT", payments_box, "TOPLEFT", 4, 22)
    payments_title:SetText("Payments")

    makeHeading(payments_box, "Sent", "LEFT", 16)
    makeHeading(payments_box, "Player", "LEFT", 138)
    makeHeading(payments_box, "Gold", "RIGHT", -246)
    makeHeading(payments_box, "Total", "RIGHT", -146)
    makeHeading(payments_box, "Verified", "RIGHT", -96)

    payments_scroll_child = makeScrollList(payments_box)

    payments_message = payments_scroll_child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    payments_message:SetPoint("TOPLEFT", payments_scroll_child, "TOPLEFT", 8, -2)
end


function shared.refreshIfOpen()
    -- Item info can arrive during the loading screen, before the window's built
    if main_frame == nil then
        return
    end

    if main_frame:IsShown() then
        refreshView()
    end
end


------------------------------------------------------------
-- Startup and slash command
------------------------------------------------------------

-- The sync app writes the gist into incoming_rows.lua, which loads on /reload:
--   shared.incoming_rows = { data = { ... }, delete = { ... } }, the same shape as tithe_ledger.
-- It holds the whole ledger, so most rows here are ones we already have.
local function mergeIncomingRows()
    if shared.incoming_rows == nil then
        return
    end

    -- Still the old mail-era list, from before the sync app wrote data and delete
    if shared.incoming_rows.data == nil then
        return
    end

    local saved_rows = {}
    for row_number, row in ipairs(tithe_ledger.data) do
        saved_rows[row.transactionID] = row
    end

    for row_number, row in ipairs(shared.incoming_rows.data) do
        local saved_row = saved_rows[row.transactionID]

        if saved_row == nil then
            table.insert(tithe_ledger.data, row)
            saved_rows[row.transactionID] = row
        elseif row.verified == 1 then
            saved_row.verified = 1
        end
    end
end


-- Adds every deleted ID we don't have yet
local function mergeIncomingDeletes()
    if shared.incoming_rows == nil then
        return
    end

    if shared.incoming_rows.delete == nil then
        return
    end

    local saved_deletes = {}
    for delete_number, transaction_id in ipairs(tithe_ledger.delete) do
        saved_deletes[transaction_id] = true
    end

    for delete_number, transaction_id in ipairs(shared.incoming_rows.delete) do
        if not saved_deletes[transaction_id] then
            table.insert(tithe_ledger.delete, transaction_id)
            saved_deletes[transaction_id] = true
        end
    end
end


local function buildSeenTransactionIDs()
    shared.seen_transaction_ids = {}

    for row_number, row in ipairs(tithe_ledger.data) do
        shared.seen_transaction_ids[row.transactionID] = true
    end
end


local ledger_events = CreateFrame("Frame")
ledger_events:RegisterEvent("PLAYER_LOGIN")
ledger_events:RegisterEvent("GET_ITEM_INFO_RECEIVED")

ledger_events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- First time on this account, or a mail-era ledger. Those rows are already in the gist and sync brings them back.
        if tithe_ledger == nil or tithe_ledger.data == nil then
            tithe_ledger = { data = {}, delete = {} }
        end

        mergeIncomingRows()
        mergeIncomingDeletes()
        shared.rebuildIgnoreRows()
        buildSeenTransactionIDs()
        checkSyncAtLogin()
        buildWindow()

    -- An item's price arrived, so its row's total can be drawn properly now
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        shared.refreshIfOpen()
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
