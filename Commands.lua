-- Deeprun Ledger: officers setting what a player owes
-- Right-click a player in Totals. Their Tithe only does it if you're the Guild Master or an officer.
--
-- Saved (see DeeprunLedger.toc):
--   deeprun_commands  commands their Tithe hasn't said DNE to yet, one per player, newest wins.
--                     { player = ..., time = ..., owed = copper }

local addon_name, shared = ...

-- Settings
local resend_every_seconds = 300 -- Offline players get it within 5 minutes of logging in


local function send(message)
    C_ChatInfo.SendAddonMessage(shared.prefix, message, "GUILD")
end


local function ledgerPrint(text)
    print("|cffc87533Deeprun|r Ledger: " .. text)
end


-- Saves it until their Tithe says DNE, and sends it now in case they're online.
-- Server time, so a PC clock that's off can't make an old command look new.
local function setOwed(player, copper)
    deeprun_commands[player] = { player = player, time = GetServerTime(), owed = copper }
    send(shared.setMessage(deeprun_commands[player]))

    ledgerPrint("Setting " .. player .. "'s tithe to " .. GetMoneyString(copper)
        .. ". If they're offline it goes through when they log in.")
end


local function sendWaitingCommands()
    for player, command in pairs(deeprun_commands) do
        send(shared.setMessage(command))
    end
end


-- DNE from the player's own Tithe, for the newest command we have for them
function shared.commandDone(message, sender)
    local message_type, player, command_time = strsplit("|", message)

    local command = deeprun_commands[player]
    if command == nil then
        return
    end

    if sender ~= player then
        return
    end

    -- DNE to an older one we've since replaced
    if tonumber(command_time) < command.time then
        return
    end

    deeprun_commands[player] = nil
    ledgerPrint(player .. "'s tithe is now " .. GetMoneyString(command.owed) .. ".")
end


------------------------------------------------------------
-- The popup: what they should owe, in gold, silver and copper
------------------------------------------------------------

local set_tithe_frame = nil
local set_tithe_player = nil
local question = nil
local gold_box = nil
local silver_box = nil
local copper_box = nil


local function setTypedAmount()
    local gold = tonumber(gold_box:GetText()) or 0
    local silver = tonumber(silver_box:GetText()) or 0
    local copper = tonumber(copper_box:GetText()) or 0

    set_tithe_frame:Hide()
    setOwed(set_tithe_player, gold * 10000 + silver * 100 + copper)
end


-- A number box with its coin after it
local function makeCoinBox(left, width, max_letters, coin_texture)
    local box = CreateFrame("EditBox", nil, set_tithe_frame, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetPoint("TOPLEFT", set_tithe_frame, "TOPLEFT", left, -44)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(max_letters)
    box:SetScript("OnEnterPressed", setTypedAmount)
    box:SetScript("OnEscapePressed", function()
        set_tithe_frame:Hide()
    end)

    local coin = set_tithe_frame:CreateTexture(nil, "ARTWORK")
    coin:SetSize(14, 14)
    coin:SetPoint("LEFT", box, "RIGHT", 2, 0)
    coin:SetTexture(coin_texture)

    return box
end


-- Looks like Blizzard's popups, the same as Tithe's Pay Custom Tithe box
local function buildSetTitheFrame()
    set_tithe_frame = CreateFrame("Frame", "DeeprunSetTitheFrame", UIParent, "BackdropTemplate")
    set_tithe_frame:SetSize(300, 116)
    set_tithe_frame:SetPoint("TOP", UIParent, "TOP", 0, -135)
    set_tithe_frame:SetFrameStrata("DIALOG")
    set_tithe_frame:EnableMouse(true)
    set_tithe_frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    table.insert(UISpecialFrames, "DeeprunSetTitheFrame")

    question = set_tithe_frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    question:SetPoint("TOP", set_tithe_frame, "TOP", 0, -20)

    gold_box = makeCoinBox(52, 64, 6, "Interface\\MoneyFrame\\UI-GoldIcon")
    silver_box = makeCoinBox(144, 32, 2, "Interface\\MoneyFrame\\UI-SilverIcon")
    copper_box = makeCoinBox(204, 32, 2, "Interface\\MoneyFrame\\UI-CopperIcon")

    local set_button = CreateFrame("Button", nil, set_tithe_frame, "UIPanelButtonTemplate")
    set_button:SetSize(110, 22)
    set_button:SetPoint("BOTTOMRIGHT", set_tithe_frame, "BOTTOM", -4, 18)
    set_button:SetText("Set")
    set_button:SetScript("OnClick", setTypedAmount)

    local cancel_button = CreateFrame("Button", nil, set_tithe_frame, "UIPanelButtonTemplate")
    cancel_button:SetSize(110, 22)
    cancel_button:SetPoint("BOTTOMLEFT", set_tithe_frame, "BOTTOM", 4, 18)
    cancel_button:SetText("Cancel")
    cancel_button:SetScript("OnClick", function()
        set_tithe_frame:Hide()
    end)

    set_tithe_frame:Hide()
end


-- Opens empty, with the cursor in the gold box. Leaving it all empty sets 0.
function shared.showSetTithe(player)
    if set_tithe_frame == nil then
        buildSetTitheFrame()
    end

    set_tithe_player = player
    question:SetText("What should " .. Ambiguate(player, "none") .. " owe?")
    gold_box:SetText("")
    silver_box:SetText("")
    copper_box:SetText("")
    set_tithe_frame:Show()
    gold_box:SetFocus()
end


local commands_frame = CreateFrame("Frame")
commands_frame:RegisterEvent("PLAYER_LOGIN")

commands_frame:SetScript("OnEvent", function(self, event)
    if deeprun_commands == nil then
        deeprun_commands = {}
    end

    sendWaitingCommands()
    C_Timer.NewTicker(resend_every_seconds, sendWaitingCommands)
end)
