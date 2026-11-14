-- Deeprun Ledger: which ledger answers, and the guild's settings
-- One ledger answers at a time. It sends RDY every 4 minutes, and when a tithe logs in and
-- asks RDY?. It ACKs rows and answers LDR.
-- A ledger that hears another's RDY stands down for 5 minutes: no RDY, no ACKs, no RNK.
-- It still saves every row it hears. If no RDY comes for 5 minutes, it takes over.
--
-- The settings ride in RDY. The newest settings time wins, for every ledger and every tithe.
--
-- Saved (see DeeprunLedger.toc):
--   ledger_settings  { time = <server time they were made, 0 for the defaults>, text = "r=0.05;t=0;l=20;c=1;" }

local addon_name, shared = ...

-- Settings
local ready_every_seconds = 240
local stand_down_seconds = 300

-- Made at login and kept for the session. Tells our own RDY apart from another ledger's.
local ledger_id = nil
local stood_down_until = 0    -- GetServerTime() we can answer again
local last_ready_sent = 0     -- GetServerTime() of our last RDY


local function send(message)
    C_ChatInfo.SendAddonMessage(shared.prefix, message, "GUILD")
end


function shared.isAnswering()
    return GetServerTime() >= stood_down_until
end


local function sendReady()
    send(shared.rdyMessage(ledger_id, ledger_settings.time))
    last_ready_sent = GetServerTime()
end


-- Checked every 10 seconds, so RDY comes 4:00 to 4:10 apart, well inside everyone's 5 minutes.
-- A ledger that stood down takes over within 10 seconds of it being its turn.
local function sendReadyIfAnswering()
    if not shared.isAnswering() then
        return
    end

    if GetServerTime() - last_ready_sent < ready_every_seconds then
        return
    end

    sendReady()
end


-- RDY? from a tithe that just logged in. Only the answering ledger replies.
function shared.answerReadyQuestion()
    if not shared.isAnswering() then
        return
    end

    sendReady()
end


local function useNewSettings(settings_time, settings_text)
    ledger_settings = { time = settings_time, text = settings_text }
    shared.useSettings(settings_text)
    shared.refreshIfOpen()
end


-- RDY from any ledger, our own included
function shared.heardReady(message)
    local message_type, sender_id, settings_time, settings_text = strsplit("|", message)
    settings_time = tonumber(settings_time)

    if sender_id == ledger_id then
        return
    end

    -- An old ledger, or a RDY typed by hand, has no settings
    if settings_time == nil then
        return
    end

    if settings_time > ledger_settings.time then
        useNewSettings(settings_time, settings_text)
    end

    -- Theirs are older, like an officer back after a week away. We send ours so everyone,
    -- that ledger too, gets the newer ones. That makes us the one answering.
    if settings_time < ledger_settings.time then
        stood_down_until = 0
        sendReady()
        return
    end

    stood_down_until = GetServerTime() + stand_down_seconds
end


-- An officer saved new settings: they're the newest now, and everyone hears them straight away
function shared.saveSettings(settings_text)
    useNewSettings(GetServerTime(), settings_text)
    stood_down_until = 0
    sendReady()
end


local ready_frame = CreateFrame("Frame")
ready_frame:RegisterEvent("PLAYER_LOGIN")

ready_frame:SetScript("OnEvent", function(self, event)
    if ledger_settings == nil then
        ledger_settings = { time = 0, text = shared.settingsText() }
    end

    shared.useSettings(ledger_settings.text)
    ledger_id = tostring(math.random(1, 999999999))

    -- Any ledger already answering hears this and stands down, so we answer now
    sendReady()
    C_Timer.NewTicker(10, sendReadyIfAnswering)
end)
