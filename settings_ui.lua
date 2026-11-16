-- Deeprun Ledger: the settings, in the header of the Personnel tab
-- The guild's tithe rate, weekly custom tithe limit and start level. Save sends them to every
-- ledger and tithe online in a RDY (Ready.lua), and they're the newest from then on.
-- They're filled in with the current settings each time the tab opens.
-- The bell checkbox is only yours. It's saved when you click it, not sent to anyone.
--
--   Tithe rate [  ]   Custom limit (g) [  ]   Start level [  ]   [Save]
--   [x] Ring a bell when a new tithe comes in (just you)          message

local addon_name, shared = ...

local rate_field = nil
local custom_tithe_limit_field = nil
local level_field = nil
local bell_checkbox = nil
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


-- A label with its box right after it. x is where the label starts.
local function makeField(parent, label_text, x, top, label_width, box_width)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top - 4)
    label:SetText(label_text)

    local field = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    field:SetSize(box_width, 20)
    field:SetPoint("TOPLEFT", parent, "TOPLEFT", x + label_width, top)
    field:SetAutoFocus(false)
    field:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        saveTypedSettings()
    end)

    return field
end


-- In the page's header, above the line in its background, on the same two rows as the
-- Tithes page's range buttons and sync line
function shared.buildSettingsPanel(parent)
    rate_field = makeField(parent, "Tithe rate", 14, -11, 62, 50)
    custom_tithe_limit_field = makeField(parent, "Custom limit (g)", 148, -11, 96, 50)
    level_field = makeField(parent, "Start level", 316, -11, 66, 40)

    local save_button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    save_button:SetSize(80, 22)
    save_button:SetPoint("TOPLEFT", parent, "TOPLEFT", 440, -10)
    save_button:SetText("Save")
    save_button:SetScript("OnClick", saveTypedSettings)

    bell_checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    bell_checkbox:SetSize(20, 20)
    bell_checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -34)
    bell_checkbox:SetScript("OnClick", function(self)
        ledger_bell_off = not self:GetChecked()
    end)

    local bell_label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bell_label:SetPoint("LEFT", bell_checkbox, "RIGHT", 4, 0)
    bell_label:SetText("Ring a bell when a new tithe comes in (just you)")

    message_label = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    message_label:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, -41)
end


function shared.fillSettingsPanel()
    rate_field:SetText(tostring(shared.tithe_rate))
    custom_tithe_limit_field:SetText(tostring(shared.custom_tithe_limit))
    level_field:SetText(tostring(shared.tithes_start_at_level))
    bell_checkbox:SetChecked(not ledger_bell_off)

    if ledger_settings.time == 0 then
        message_label:SetText("These are the defaults. Nobody has saved settings yet.")
    else
        message_label:SetText("Last changed " .. date("%b %d, %I:%M%p", ledger_settings.time))
    end
end
