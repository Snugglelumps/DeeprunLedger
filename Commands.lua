-- Deeprun Ledger: officers setting what a player owes
-- Right-click a player in Totals. Their Tithe only does it if you're in the top three ranks.
--
-- One try. The SET goes out once, and the popup waits for their Tithe's DNE:
-- it says done, or after a few seconds, that nothing answered. Offline, or no Tithe,
-- and nothing changes. Nothing is saved or sent again later: a SET landing days late
-- would undo everything they'd sold and paid since. Their Tithe also ignores any SET
-- more than a minute old.

local addon_name, shared = ...

-- Settings
local reply_seconds = 10


local function send(message)
    C_ChatInfo.SendAddonMessage(shared.prefix, message, "GUILD")
end


local function ledgerPrint(text)
    print("|cffc87533Deeprun|r Ledger: " .. text)
end


local waiting = nil  -- the SET sent and not answered yet: { player = ..., time = ..., owed = copper }

-- Set by the popup, below
local set_button = nil
local status = nil


local function showStatus(text, r, g, b)
    status:SetText(text)
    status:SetTextColor(r, g, b)
end


-- Sends it once and waits for their DNE.
-- Server time, so their Tithe can tell how old it is.
local function setOwed(player, copper)
    local command = { player = player, time = GetServerTime(), owed = copper }
    waiting = command
    send(shared.setMessage(command))

    set_button:Disable()
    showStatus("Waiting for " .. Ambiguate(player, "none") .. "'s Tithe...", 0.6, 0.6, 0.6)

    C_Timer.After(reply_seconds, function()
        if waiting ~= command then
            return
        end

        waiting = nil
        set_button:Enable()
        showStatus("No answer. Nothing changed: they're offline, or not running the Tithe.", 1, 0.5, 0.31)
        ledgerPrint("No answer from " .. player .. ". Their tithe wasn't changed.")
    end)
end


-- DNE from the player's own Tithe, for the SET we're waiting on
function shared.commandDone(message, sender)
    local message_type, player, command_time = strsplit("|", message)

    if waiting == nil or sender ~= player or player ~= waiting.player then
        return
    end

    if tonumber(command_time) ~= waiting.time then
        return
    end

    local owed = waiting.owed
    waiting = nil
    set_button:Enable()
    showStatus("Done. " .. Ambiguate(player, "none") .. " now owes " .. GetMoneyString(owed) .. ".", 1, 0.82, 0)
    ledgerPrint(player .. "'s tithe is now " .. GetMoneyString(owed) .. ".")
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
    box:SetScript("OnEnterPressed", function()
        if waiting == nil then
            setTypedAmount()
        end
    end)
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
    set_tithe_frame:SetSize(300, 140)
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

    -- Waiting, done, or no answer
    status = set_tithe_frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOP", set_tithe_frame, "TOP", 0, -74)
    status:SetWidth(260)

    set_button = CreateFrame("Button", nil, set_tithe_frame, "UIPanelButtonTemplate")
    set_button:SetSize(110, 22)
    set_button:SetPoint("BOTTOMRIGHT", set_tithe_frame, "BOTTOM", -4, 18)
    set_button:SetText("Attempt Set")
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
    if waiting == nil then
        status:SetText("")
    end
    gold_box:SetText("")
    silver_box:SetText("")
    copper_box:SetText("")
    set_tithe_frame:Show()
    gold_box:SetFocus()
end

