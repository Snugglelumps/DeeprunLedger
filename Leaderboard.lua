-- Deeprun Ledger: the leaderboard
-- Worked out from the payments every time it's asked for. Nothing extra is saved.
-- Gold only. Weeks start Monday 00:00 by the realm's clock.
-- Each finished week: most gold gets 3 points, second 2, third 1. Tied players share a place
-- and each get its points, and the next place is skipped: two firsts, then a third.
-- This week only counts once it's over.

local addon_name, shared = ...

-- Settings
local players_per_message = 3     -- Fits a long name and big numbers in 255 letters

local seconds_per_week = 7 * 24 * 60 * 60
local points_for_place = { 3, 2, 1 }

local sending = false       -- A board is going out right now
local asked_again = false   -- An LDR came in while it was


local function send(message)
    C_ChatInfo.SendAddonMessage(shared.prefix, message, "GUILD")
end


-- The start of the week a time falls in
local function weekOf(timestamp, this_week_start)
    return this_week_start + math.floor((timestamp - this_week_start) / seconds_per_week) * seconds_per_week
end


-- Every gold payment, by week and player. And everyone's all-time gold.
--   weeks[week start][name] = { gold = copper, payments = count }
local function addUpPayments(this_week_start)
    local weeks = {}
    local all_time_gold = {}

    for row_number, row in ipairs(tithe_ledger.data) do
        if not shared.ignore_rows[row.transactionID] and row.amount > 0 then
            local week_start = weekOf(row.time, this_week_start)

            if weeks[week_start] == nil then
                weeks[week_start] = {}
            end

            local player = weeks[week_start][row.name]
            if player == nil then
                player = { gold = 0, payments = 0 }
                weeks[week_start][row.name] = player
            end

            player.gold = player.gold + row.amount
            player.payments = player.payments + 1
            all_time_gold[row.name] = (all_time_gold[row.name] or 0) + row.amount
        end
    end

    return weeks, all_time_gold
end


-- 1 plus how many paid more, so tied players get the same place
local function placeInWeek(week, gold)
    local place = 1

    for name, player in pairs(week) do
        if player.gold > gold then
            place = place + 1
        end
    end

    return place
end


-- Points and weeks at number one, from every finished week
local function addUpPoints(weeks, this_week_start)
    local points = {}
    local weeks_won = {}

    for week_start, week in pairs(weeks) do
        if week_start < this_week_start then
            for name, player in pairs(week) do
                local place = placeInWeek(week, player.gold)
                points[name] = (points[name] or 0) + (points_for_place[place] or 0)

                if place == 1 then
                    weeks_won[name] = (weeks_won[name] or 0) + 1
                end
            end
        end
    end

    return points, weeks_won
end


-- Everyone who's paid gold this week, most first, with their all-time numbers
function shared.getLeaderboard()
    local this_week_start = shared.thisWeekStart()
    local weeks, all_time_gold = addUpPayments(this_week_start)
    local points, weeks_won = addUpPoints(weeks, this_week_start)

    local players = {}
    for name, player in pairs(weeks[this_week_start] or {}) do
        table.insert(players, {
            name = name,
            week_gold = player.gold,
            payments = player.payments,
            all_time_gold = all_time_gold[name],
            points = points[name] or 0,
            weeks_won = weeks_won[name] or 0,
        })
    end

    table.sort(players, function(first, second)
        return first.week_gold > second.week_gold
    end)

    return this_week_start, players
end


-- The whole board to the guild, one message a second so the throttle never drops one.
-- If anyone asked while it was going out, it may be missing their payment, so send one more.
local function sendBoard()
    sending = true

    local week_start, players = shared.getLeaderboard()

    local messages = {}
    for first = 1, #players, players_per_message do
        local some_players = { unpack(players, first, first + players_per_message - 1) }
        table.insert(messages, shared.rnkMessage(week_start, some_players))
    end

    -- Nobody's paid yet this week. Still send the week, so tithes clear last week's board.
    if #messages == 0 then
        table.insert(messages, shared.rnkMessage(week_start, {}))
    end

    local message_number = 0
    C_Timer.NewTicker(1, function()
        message_number = message_number + 1
        send(messages[message_number])

        if message_number < #messages then
            return
        end

        sending = false

        if asked_again then
            asked_again = false
            sendBoard()
        end
    end, #messages)
end


-- LDR from a tithe. Only the answering ledger replies. However many ask during a board,
-- they all get the one more board after it.
function shared.answerLeaderboard()
    if not shared.isAnswering() then
        return
    end

    if sending then
        asked_again = true
        return
    end

    sendBoard()
end
