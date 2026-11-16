-- Deeprun Ledger: the Personnel tab, its own side tab under the Ledger's
-- The settings along the top (settings_ui.lua), and under them every account as a tree:
-- the account under its main's name, then each of its characters, latest seen first.
-- Dots show who's online right now (Accounts.lua). Right-click a character to make it the main.
--
--   (dot) Snuggyl Lumps   aa04-1ce814                          2 characters
--         (dot) Snuggyl Lumps   main                  last seen Nov 14, 09:12PM
--         (dot) Snuggyl Alt                           last seen Nov 13, 08:40PM

local addon_name, shared = ...

local dot_textures = {
    green = "Interface\\COMMON\\Indicator-Green",
    yellow = "Interface\\COMMON\\Indicator-Yellow",
    gray = "Interface\\COMMON\\Indicator-Gray",
}

local page = nil
local scroll_child = nil
local tree_rows = {}
local empty_label = nil


-- The account and character are passed in as the popup's data
StaticPopupDialogs["DEEPRUN_PROMOTE_MAIN"] = {
    text = "Make %s the main for account %s?",
    button1 = "Promote",
    button2 = "Cancel",
    OnAccept = function(self, promote)
        shared.promoteMain(promote.account_id, promote.character)
        shared.showPersonnel()
    end,
    timeout = 0,
    hideOnEscape = true,
}


-- One row, for an account or a character. Right-clicking a character asks to promote it.
local function getTreeRow(row_number)
    local row = tree_rows[row_number]

    if row == nil then
        row = shared.makeListRow(scroll_child, row_number)
        row:RegisterForClicks("RightButtonUp")
        row:SetScript("OnClick", function(self)
            if self.character == nil then
                return
            end

            StaticPopup_Show("DEEPRUN_PROMOTE_MAIN", self.character, self.account_id,
                { account_id = self.account_id, character = self.character })
        end)

        row.dot = row:CreateTexture(nil, "OVERLAY")
        row.dot:SetSize(12, 12)

        row.name_label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name_label:SetPoint("LEFT", row.dot, "RIGHT", 6, 0)

        row.note_label = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.note_label:SetPoint("LEFT", row.name_label, "RIGHT", 10, 0)

        row.right_label = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.right_label:SetPoint("RIGHT", row, "RIGHT", -10, 0)

        tree_rows[row_number] = row
    end

    row.shade:SetShown(row_number % 2 == 0)
    row:Show()
    return row
end


local function showAccountRow(row, account_id, main, character_count)
    row.account_id = account_id
    row.character = nil

    row.dot:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.dot:SetTexture(dot_textures[shared.accountStatus(account_id)])

    row.name_label:SetText(main)
    row.name_label:SetTextColor(1, 0.82, 0)
    row.note_label:SetText(account_id)

    if character_count == 1 then
        row.right_label:SetText("1 character")
    else
        row.right_label:SetText(character_count .. " characters")
    end
end


local function showCharacterRow(row, account_id, character, last_seen, is_main)
    row.account_id = account_id
    row.character = character

    row.dot:SetPoint("LEFT", row, "LEFT", 28, 0)
    row.dot:SetTexture(dot_textures[shared.characterStatus(account_id, character)])

    row.name_label:SetText(character)
    row.name_label:SetTextColor(1, 1, 1)

    if is_main then
        row.note_label:SetText("|cffffd100main|r")
    else
        row.note_label:SetText("")
    end

    row.right_label:SetText("last seen " .. date("%b %d, %I:%M%p", last_seen))
end


-- Accounts by their main's name, each followed by its characters, latest seen first
function shared.showPersonnel()
    if page == nil or not page:IsVisible() then
        return
    end

    for _, row in ipairs(tree_rows) do
        row:Hide()
    end

    local gold_by_name = shared.goldByName()

    local accounts = {}
    for account_id, characters in pairs(tithe_ledger.accounts) do
        local account = { account_id = account_id, main = shared.accountMain(account_id, gold_by_name), characters = {} }

        for character, last_seen in pairs(characters) do
            table.insert(account.characters, { name = character, last_seen = last_seen })
        end

        table.sort(account.characters, function(first, second)
            return first.last_seen > second.last_seen
        end)

        table.insert(accounts, account)
    end

    table.sort(accounts, function(first, second)
        return first.main < second.main
    end)

    if #accounts == 0 then
        empty_label:SetText("No account data yet. Accounts appear as members log in.")
    else
        empty_label:SetText("")
    end

    local row_number = 0
    for _, account in ipairs(accounts) do
        row_number = row_number + 1
        showAccountRow(getTreeRow(row_number), account.account_id, account.main, #account.characters)

        for _, character in ipairs(account.characters) do
            row_number = row_number + 1
            showCharacterRow(getTreeRow(row_number), account.account_id, character.name,
                character.last_seen, character.name == account.main)
        end
    end

    scroll_child:SetHeight(18 * row_number + 4)
end


-- Settings in the header, then the accounts list filling the rest, starting where Totals does.
-- Opening it fills in the current settings and the accounts.
function shared.buildPersonnelPage(parent)
    page = parent
    page:SetScript("OnShow", function()
        shared.fillSettingsPanel()
        shared.showPersonnel()
    end)

    shared.buildSettingsPanel(parent)

    local accounts_box = shared.makeListBox(parent)
    accounts_box:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -92)
    accounts_box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, 8)

    local accounts_title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    accounts_title:SetPoint("BOTTOMLEFT", accounts_box, "TOPLEFT", 4, 22)
    accounts_title:SetText("Accounts")

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", accounts_box, "TOPRIGHT", -4, 22)
    hint:SetText("Right-click a character to make it the main")

    shared.makeHeading(accounts_box, "Account and characters", "LEFT", 16)
    shared.makeHeading(accounts_box, "Last seen", "RIGHT", -44)

    scroll_child = shared.makeScrollList(accounts_box)

    empty_label = scroll_child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty_label:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", 8, -2)
end
