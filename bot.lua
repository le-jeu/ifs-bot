local config = require("config")
local json = require('dkjson')
local utils = require("utils")

local ingress = require "ingress"

local api = require('telegram-bot-lua.core').configure(config.bot_token)

local bot = api.get_me().result
print(json.encode(bot))

local db = require("db")(config.db_file)

local function reply_message(message, text, inline_keyboard)
    api.send_message(
        message.chat.id,
        text,
        "Markdown",
        nil,
        nil,
        message.message_id,
        inline_keyboard
    )
end

-- users cache
local users = {}
function users:get(id)
    id = tonumber(id)
    if self[id] then return self[id] end
    local user = db.TelegramUser{user_id = id}
    self[id] = user
    return user
end

function comma_value(n)
    local sign,num = string.match(string.format("%+d", n),'([+-])(%d+)')
    return sign..(num:reverse():gsub('(%d%d%d)','%1,'):reverse())
end

local function handle_stats(message, stats)
    local ok, stats = pcall(ingress.parse_stats, stats)
    local answer = ""
    if ok then
        local last_stat
        if stats.data["Agent Name"] then
            for stat in db.AgentStat:where_iterator{user_id = message.from.id, name = stats.data["Agent Name"]} do
                last_stat = stat
            end
        end
        local format_list = {
            "Agent Name",
            "Agent Faction",
            "Level",
            "Lifetime AP",
            "XM Recharged"
        }
        local err = false
        for _,k in ipairs(format_list) do
            if not stats.data[k] then
                err = true
                break
            end
            answer = answer .. string.format("%s: _%s_\n", k, stats.data[k])
        end
        if not err then
            local entry = db.AgentStat{
                user_id = message.from.id,
                agent_id = stats.data["Agent Name"]:lower(),
                name = stats.data["Agent Name"],
                timestamp = message.date,
                time_span = stats.data["Time Span"],
                faction = stats.data["Agent Faction"],
                date = stats.data["Date (yyyy-mm-dd)"],
                time = stats.data["Time (hh:mm:ss)"],
                level = stats.data["Level"],
                lifetime_ap = stats.data["Lifetime AP"],
                xm_recharged = stats.data["XM Recharged"],
            }
            if last_stat then
                answer = answer .. "\n*Difference:*\n"
                local diff_list = {
                    ["Level"] = "level",
                    ["Lifetime AP"] = "lifetime_ap",
                    ["XM Recharged"] = "xm_recharged",
                }
                for k,v in pairs(diff_list) do
                    answer = answer .. string.format("%s: _%s_\n", k, comma_value(entry[v] - last_stat[v]))
                end
            end
        else
            answer = "error parsing data"
        end
    else
        answer = "error parsing data…"
    end
    reply_message(message, answer)
end

-- log for replay
function api.on_update(update)
    local update_file = io.open(config.update_file, 'a')
    update_file:write(json.encode(update), '\n')
    update_file:close()
end

function api.on_message(message)
    -- ignore anything without from
    if not message.from then
        return
    end

    local user = users:get(message.from.id)
    -- udate username
    if message.from.username then user.username = message.from.username end

    -- ignore group messages
    if message.chat.type ~= "private" then
        return
    end

    if message.text then
        -- parse any two lines looking like stats
        for stats in message.text:gmatch("Time Span[^\r\n]+\n[^\r\n]+") do
            utils.pcall(handle_stats, message, stats)
        end
    end
end

api.run()