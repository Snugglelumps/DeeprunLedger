-- Deeprun Ledger: the /drl settings window
-- The guild's tithe rate, weekly custom tithe limit and start level. Save sends them to every
-- ledger and tithe online in a RDY (Ready.lua), and they're the newest from then on.
-- It opens filled in with the current settings.

local addon_name, shared = ...

local settings_frame = nil
local rate_field = nil
local custom_tithe_limit_field = nil
local level_field = nil
local message_label = nil


local function saveTypedSettings()
    local tithe_rate = strtrim(rate_field:GetText())
    local custom_tithe_limit = strtrim(custom_tithe_limit_field:GetText())
    local tithes_start_at_level = strtrim(level_field:GetText())

    if tonumber(tithe_rate) == nil then
        message_label:SetText("The rate needs to be a number, like 0.05")
        return
    end

    if tonumber(custom_tithe_limit) == nil then
        message_label:SetText("The custom tithe limit needs to be gold, like 1")
        return
    end

    if tonumber(tithes_start_at_level) == nil then
        message_label:SetText("The level needs to be a number, like 20")
        return
    end

    shared.saveSettings("r=" .. tithe_rate .. ";t=0;l=" .. tithes_start_at_level .. ";c=" .. custom_tithe_limit .. ";")
    message_label:SetText("Saved and sent to everyone online")
end


local function makeField(label_text, top)
    local label = settings_frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", settings_frame, "TOPLEFT", 16, top - 4)
    label:SetText(label_text)

    local field = CreateFrame("EditBox", nil, settings_frame, "InputBoxTemplate")
    field:SetPoint("TOPLEFT", settings_frame, "TOPLEFT", 110, top)
    field:SetPoint("TOPRIGHT", settings_frame, "TOPRIGHT", -18, top)
    field:SetHeight(20)
    field:SetAutoFocus(false)
    field:SetMaxLetters(0)

    return field
end


local function buildSettingsWindow()
    settings_frame = CreateFrame("Frame", "DeeprunSettingsFrame", UIParent, "BasicFrameTemplateWithInset")
    settings_frame:SetSize(440, 190)
    settings_frame:SetPoint("CENTER")
    settings_frame.TitleText:SetText("Deeprun Settings")
    settings_frame:SetMovable(true)
    settings_frame:EnableMouse(true)
    settings_frame:RegisterForDrag("LeftButton")
    settings_frame:SetScript("OnDragStart", settings_frame.StartMoving)
    settings_frame:SetScript("OnDragStop", settings_frame.StopMovingOrSizing)

    table.insert(UISpecialFrames, "DeeprunSettingsFrame")

    rate_field = makeField("Tithe rate", -36)
    custom_tithe_limit_field = makeField("Custom limit (g)", -62)
    level_field = makeField("Start level", -88)

    local save_button = CreateFrame("Button", nil, settings_frame, "UIPanelButtonTemplate")
    save_button:SetSize(120, 22)
    save_button:SetPoint("TOPLEFT", settings_frame, "TOPLEFT", 110, -116)
    save_button:SetText("Save")
    save_button:SetScript("OnClick", saveTypedSettings)

    message_label = settings_frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    message_label:SetPoint("TOPLEFT", settings_frame, "TOPLEFT", 16, -150)
end


function shared.showSettingsWindow()
    if settings_frame == nil then
        buildSettingsWindow()
    end

    settings_frame:Show()

    rate_field:SetText(tostring(shared.tithe_rate))
    custom_tithe_limit_field:SetText(tostring(shared.custom_tithe_limit))
    level_field:SetText(tostring(shared.tithes_start_at_level))

    if ledger_settings.time == 0 then
        message_label:SetText("These are the defaults. Nobody has saved settings yet.")
    else
        message_label:SetText("Last changed " .. date("%b %d, %I:%M%p", ledger_settings.time))
    end
end
