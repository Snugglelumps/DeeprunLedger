-- Deeprun Ledger: the /drl hash window
-- Makes the [[...]] code that goes in Guild Info, and reads one back into the fields.
-- It opens filled in with the current code's values.

local addon_name, shared = ...

local hash_frame = nil
local rate_field = nil
local trade_good_rate_field = nil
local code_field = nil
local message_label = nil


local function makeCode()
    local tithe_rate = strtrim(rate_field:GetText())
    local trade_good_rate = strtrim(trade_good_rate_field:GetText())

    if tonumber(tithe_rate) == nil then
        message_label:SetText("The rate needs to be a number, like 0.05")
        return
    end

    if tonumber(trade_good_rate) == nil then
        message_label:SetText("The trade good rate needs to be a number, like 2")
        return
    end

    -- DeeprunShared.lua's readSettings reads this back. r has to stay first.
    local settings = "r=" .. tithe_rate .. ";t=" .. trade_good_rate .. ";"

    code_field:SetText("[[" .. C_EncodingUtil.EncodeBase64(settings) .. "]]")
    code_field:SetFocus()
    code_field:HighlightText()
    message_label:SetText("Press Ctrl+C, then paste it into Guild Info")
end


local function readCode()
    local settings_code = string.match(code_field:GetText(), "%[%[(.-)%]%]")

    if settings_code == nil then
        message_label:SetText("Paste a code with its [[ ]] into the box first")
        return
    end

    local tithe_rate, trade_good_rate = shared.readSettings(settings_code)

    if tithe_rate == nil then
        message_label:SetText("That isn't a valid code")
        return
    end

    rate_field:SetText(tostring(tithe_rate))
    trade_good_rate_field:SetText(tostring(trade_good_rate))
    message_label:SetText("Read it into the fields above")
end


local function makeField(label_text, top)
    local label = hash_frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", hash_frame, "TOPLEFT", 16, top - 4)
    label:SetText(label_text)

    local field = CreateFrame("EditBox", nil, hash_frame, "InputBoxTemplate")
    field:SetPoint("TOPLEFT", hash_frame, "TOPLEFT", 110, top)
    field:SetPoint("TOPRIGHT", hash_frame, "TOPRIGHT", -18, top)
    field:SetHeight(20)
    field:SetAutoFocus(false)
    field:SetMaxLetters(0)

    return field
end


local function buildHashWindow()
    hash_frame = CreateFrame("Frame", "DeeprunHashFrame", UIParent, "BasicFrameTemplateWithInset")
    hash_frame:SetSize(440, 194)
    hash_frame:SetPoint("CENTER")
    hash_frame.TitleText:SetText("Deeprun Guild Code")
    hash_frame:SetMovable(true)
    hash_frame:EnableMouse(true)
    hash_frame:RegisterForDrag("LeftButton")
    hash_frame:SetScript("OnDragStart", hash_frame.StartMoving)
    hash_frame:SetScript("OnDragStop", hash_frame.StopMovingOrSizing)

    table.insert(UISpecialFrames, "DeeprunHashFrame")

    rate_field = makeField("Tithe rate", -36)
    trade_good_rate_field = makeField("Trade good rate", -62)

    local make_button = CreateFrame("Button", nil, hash_frame, "UIPanelButtonTemplate")
    make_button:SetSize(120, 22)
    make_button:SetPoint("TOPLEFT", hash_frame, "TOPLEFT", 110, -90)
    make_button:SetText("Make code")
    make_button:SetScript("OnClick", makeCode)

    local read_button = CreateFrame("Button", nil, hash_frame, "UIPanelButtonTemplate")
    read_button:SetSize(120, 22)
    read_button:SetPoint("LEFT", make_button, "RIGHT", 8, 0)
    read_button:SetText("Read code")
    read_button:SetScript("OnClick", readCode)

    code_field = makeField("Code", -120)

    message_label = hash_frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    message_label:SetPoint("TOPLEFT", hash_frame, "TOPLEFT", 16, -152)
    message_label:SetText("Items count for their vendor price times the trade good rate.")
end


function shared.showHashWindow()
    if hash_frame == nil then
        buildHashWindow()
    end

    hash_frame:Show()

    if shared.tithe_rate == nil then
        return
    end

    rate_field:SetText(tostring(shared.tithe_rate))
    trade_good_rate_field:SetText(tostring(shared.trade_good_rate))
end
