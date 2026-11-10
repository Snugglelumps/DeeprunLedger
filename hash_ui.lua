-- Deeprun Ledger: the /drl hash window
-- Makes the [[...]] code that goes in Guild Info, and reads one back into the fields.
-- It opens filled in with the current code's values, so changing a treasurer keeps the secret.

local addon_name, shared = ...

local hash_frame = nil
local treasurers_field = nil
local rate_field = nil
local level_field = nil
local secret_field = nil
local code_field = nil
local message_label = nil


local function newSecretHex()
    local secret_hex = ""

    for byte_number = 1, 24 do
        secret_hex = secret_hex .. string.format("%02x", math.random(0, 255))
    end

    return secret_hex
end


local function makeCode()
    -- Names must match exactly, so "A, B" can't leave a space on the front of B
    local treasurers = string.gsub(strtrim(treasurers_field:GetText()), "%s*,%s*", ",")
    local tithe_rate = strtrim(rate_field:GetText())
    local start_level = strtrim(level_field:GetText())
    local secret_hex = strtrim(secret_field:GetText())

    if treasurers == "" then
        message_label:SetText("Enter at least one treasurer")
        return
    end

    if tonumber(tithe_rate) == nil then
        message_label:SetText("The rate needs to be a number, like 0.05")
        return
    end

    if string.match(start_level, "^%d+$") == nil then
        message_label:SetText("Tithes start after needs to be a whole level, like 9")
        return
    end

    if secret_hex == "" then
        secret_hex = newSecretHex()
        secret_field:SetText(secret_hex)
    end

    local secret = C_EncodingUtil.DecodeHex(secret_hex)
    if secret == nil then
        message_label:SetText("The secret needs to be hex. Clear it to make a new one.")
        return
    end

    local config = "r=" .. tithe_rate .. ";l=" .. start_level .. ";t=" .. treasurers .. ";s=" .. secret

    code_field:SetText("[[" .. C_EncodingUtil.EncodeBase64(config) .. "]]")
    code_field:SetFocus()
    code_field:HighlightText()
    message_label:SetText("Press Ctrl+C, then paste it into Guild Info")
end


local function readCode()
    local encoded_config = string.match(code_field:GetText(), "%[%[(.-)%]%]")

    if encoded_config == nil then
        message_label:SetText("Paste a code with its [[ ]] into the box first")
        return
    end

    local tithe_rate, treasurer_list, secret, start_level = shared.decodeConfig(encoded_config)

    if tithe_rate == nil then
        message_label:SetText("That isn't a valid code")
        return
    end

    treasurers_field:SetText(treasurer_list)
    rate_field:SetText(tostring(tithe_rate))
    level_field:SetText(tostring(start_level))
    secret_field:SetText(C_EncodingUtil.EncodeHex(secret))
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
    hash_frame:SetSize(440, 246)
    hash_frame:SetPoint("CENTER")
    hash_frame.TitleText:SetText("Deeprun Guild Code")
    hash_frame:SetMovable(true)
    hash_frame:EnableMouse(true)
    hash_frame:RegisterForDrag("LeftButton")
    hash_frame:SetScript("OnDragStart", hash_frame.StartMoving)
    hash_frame:SetScript("OnDragStop", hash_frame.StopMovingOrSizing)

    table.insert(UISpecialFrames, "DeeprunHashFrame")

    treasurers_field = makeField("Treasurers", -36)
    rate_field = makeField("Rate", -62)
    level_field = makeField("Start after lvl", -88)
    secret_field = makeField("Secret", -114)

    local make_button = CreateFrame("Button", nil, hash_frame, "UIPanelButtonTemplate")
    make_button:SetSize(120, 22)
    make_button:SetPoint("TOPLEFT", hash_frame, "TOPLEFT", 110, -142)
    make_button:SetText("Make code")
    make_button:SetScript("OnClick", makeCode)

    local read_button = CreateFrame("Button", nil, hash_frame, "UIPanelButtonTemplate")
    read_button:SetSize(120, 22)
    read_button:SetPoint("LEFT", make_button, "RIGHT", 8, 0)
    read_button:SetText("Read code")
    read_button:SetScript("OnClick", readCode)

    code_field = makeField("Code", -172)

    message_label = hash_frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    message_label:SetPoint("TOPLEFT", hash_frame, "TOPLEFT", 16, -204)
    message_label:SetText("First treasurer gets the mail. Separate names with commas.")
end


function shared.showHashWindow()
    if hash_frame == nil then
        buildHashWindow()
    end

    hash_frame:Show()

    if shared.secret == nil then
        return
    end

    treasurers_field:SetText(table.concat(shared.treasurers, ","))
    rate_field:SetText(tostring(shared.tithe_rate))
    level_field:SetText(tostring(shared.tithes_start_after_level))
    secret_field:SetText(C_EncodingUtil.EncodeHex(shared.secret))
end
