local config = require("config")
local json = require('dkjson')
local utils = require("utils")

local ingress = require "ingress"

local api = require('telegram-bot-lua.core').configure(config.bot_token)

local bot = api.get_me().result
print(json.encode(bot))

local db = require("db")(config.db_file)

local admin_only = true

local function is_member(chatmember)
    if chatmember then
        local status = chatmember.status
        return status == 'member'
            or status == "creator"
            or status == "administrator"
            or status == "restricted"
    end
end

-- users cache
local users = {}
function users:get(id)
    id = tonumber(id)
    if self[id] then return self[id] end
    local user = db.TelegramUser{user_id = id}
    -- check if member of the common group
    local ret = api.get_chat_member(config.chat_membership, user.user_id)
    print('member', config.chat_membership, json.encode(ret))
    if ret and ret.ok then
        user.member = is_member(ret.result) and 1 or 0
        if ret.result.user.username then
            user.username = ret.result.user.username
        end
    end
    -- check if member of the amdin group
    local ret = api.get_chat_member(config.admin_chat, user.user_id)
    print('admin', config.admin_chat, json.encode(ret))
    if ret and ret.ok then
        user.admin = is_member(ret.result) and 1 or 0
        if ret.result.user.username then
            user.username = ret.result.user.username
        end
    end
    self[id] = user
    return user
end

local msg_ok = [[Merci pour le selfie, voici le lien pour rejoindre le salon Zoom :

https://cccconfer.zoom.us/j/123456789

Le Google form pour renseigner tes stats :

https://docs.google.com/forms/d/12345678901234567890/edit

MERCI DE NE PAS DIFFUSER CES LIENS, BONNE APRÈS MIDI !
🤪🤩🥳]]

local yesNoInlineKeyboard =
    api.inline_keyboard():row(
        api.row():callback_data_button(
            'Oui',
            'yes'
        ):callback_data_button(
            'Non',
            'no'
        )
    )

local function fwd_photo(chat_id, photo)
    local agents = {}
    for photo_agent in db.PhotoAgent:where_iterator{photo_id = photo.file_unique_id} do
        local agent = db.IngressAgent:get{agent_id = photo_agent.agent_id}
        if agent then table.insert(agents, agent.name) end
    end
    local user = users:get(photo.user_id)
    local verified = photo.status == 'verified'
    local valid = photo.valid ~= 0
    local public = photo.public ~= 0
    local yes = ''
    local no = ''
    if verified and valid then yes = '☑️ ' end
    if verified and not valid then no = '❌ ' end
    local inline_keyboard
    if verified and valid then
        inline_keyboard =
            api.inline_keyboard():row(
                api.row():callback_data_button(
                    '☑️ Valide',
                    'yes'
                )
            )
    else
        inline_keyboard =
            api.inline_keyboard():row(
                api.row():callback_data_button(
                    yes .. 'Valide',
                    'yes'
                ):callback_data_button(
                    no .. 'Invalide',
                    'no'
                )
            )
    end
    api.send_photo(
        chat_id,
        photo.file_id,
        "TG: @" .. user.username ..
        "\nAgents: " .. table.concat(agents, ', ') ..
        "\nPublic: " .. (public and "oui" or "non"),
        nil,
        nil,
        nil,
        inline_keyboard
    )
end

local function handle_new_photo(user, message)
    -- drop everything else than verified and verification
    local bad_ids = {}
    for photo in db.TelegramPhoto:where_iterator{user_id = user.user_id} do
        if photo.status ~= 'verification' and photo.status ~= 'verified' then
            table.insert(bad_ids, photo.file_unique_id)
        end
    end
    if #bad_ids > 0 then
        -- fake foreign key
        for _, id in ipairs(bad_ids) do
            db.PhotoAgent:delete_where{photo_id = id}
        end
        db.TelegramPhoto:delete_where{user_id = user.user_id, status = 'new'}
        db.TelegramPhoto:delete_where{user_id = user.user_id, status = 'caption'}
        db.TelegramPhoto:delete_where{user_id = user.user_id, status = 'public'}
    end
    local photo = db.TelegramPhoto{
        file_id = message.photo[1].file_id,
        file_unique_id = message.photo[1].file_unique_id,
        status = 'new',
        user_id = user.user_id,
        timestamp = message.date
    }
    -- new photo
    if photo.status == 'new' and photo.user_id == user.user_id then
        api.send_message(
            message,
            "Quels sont les agents sur la photo ?"
        )
    else
        api.send_message(
            message,
            "J'ai déjà vu ça quelque part..."
        )
    end
end

local function handle_agents(user, message)
    local photos = db.TelegramPhoto:where{user_id = user.user_id}
    if #photos > 0 then
        local last_photo = photos[#photos]
        if last_photo.status == "new" then
            local agents = {}
            for agent in message.text:gmatch("%w+") do
                table.insert(agents, agent)
            end
            if #agents > 0 then
                last_photo.status = 'caption'
                local data = {}
                for _,agent in ipairs(agents) do
                    table.insert(data, { agent_id = agent:lower(), name = agent, photo_id = last_photo.file_unique_id })
                end
                -- remove old entries
                db.PhotoAgent:delete_where{ photo_id = last_photo.file_unique_id }
                -- add agents
                db.IngressAgent:insert_from_list(data)
                -- add relations
                db.PhotoAgent:insert_from_list(data)

                local answer = "Agents: @" .. table.concat(agents, ', @') .. " ?"
                api.send_message(
                    user.user_id,
                    answer,
                    nil,
                    true,
                    false,
                    nil,
                    yesNoInlineKeyboard
                )
            end
        end
    end
end



local function handle_stats(message, stats)
    do
        local f = io.open("stats", "a")
        f:write(stats, '\n')
        f:close()
    end
    local ok, stats = pcall(ingress.parse_stats, stats)
    local answer = ""
    if ok then
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
            answer = answer .. string.format("*%s*: _%s_\n", k, stats.data[k])
        end
        if not err then
            db.AgentStat{
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
        else
            answer = "error parsing data"
        end
    else
        print(json.encode(stats))
        answer = "error parsing data…"
    end
    if not ok then
        print(json.encode(stats))
    end
    api.send_message(
        message.from.id,
        answer,
        "Markdown",
        true,
        false,
        nil,
        nil
    )
end

local commands = {
    {
        name = "public",
        description = "activer les messages privés des participants",
        action = function (message, words)
            admin_only = false
            api.send_message(
                message.chat.id,
                "Les participants peuvent m'envoyer des selfies",
                nil,
                nil,
                nil,
                message.message_id
            )
        end,
    },
    {
        name = "stop",
        description = "désactiver les messages privés des participants",
        action = function (message, words)
            admin_only = true
            api.send_message(
                message.chat.id,
                "J'arrête les selfies",
                nil,
                nil,
                nil,
                message.message_id
            )
        end,
    },
    {
        name = "msgok",
        description = "message reçu après validation",
        action = function (message, words)
            api.send_message(
                message.chat.id,
                msg_ok,
                nil,
                nil,
                nil,
                message.message_id
            )
        end,
    },
    {
        name = "pending",
        description = "rappelle un selfie non vérifié",
        action = function (message, words)
            local photo = db.TelegramPhoto:get{status = 'verification'}
            if photo then
                fwd_photo(config.fwd_to, photo)
            else
                api.send_message(
                    message.chat.id,
                    "Aucune photo en attente",
                    nil,
                    nil,
                    nil,
                    message.message_id
                )
            end
        end,
    },
    {
        name = "check",
        description = "indique si un joueur est validé",
        action = function (message, words)
            if not words[2] then return end
            local agent_id = words[2]:lower():match('%w+')
            if agent_id then
                local photos_id = {}
                for photo_agent in db.PhotoAgent:where_iterator{agent_id = agent_id} do
                    photos_id[photo_agent.photo_id] = true
                end
                local valid = false
                local user
                local count = 0
                for photo_id in pairs(photos_id) do
                    local photo = db.TelegramPhoto:get{file_unique_id = photo_id}
                    if photo.valid ~= 0 then
                        valid = true
                        user = users:get(photo.user_id).username
                        break
                    end
                    count = count + 1
                end
                if valid then
                    api.send_message(
                        message.chat.id,
                        "L'agent " .. agent_id .. ' est validé par un selfie de @' .. user,
                        nil,
                        nil,
                        nil,
                        message.message_id
                    )
                else
                    api.send_message(
                        message.chat.id,
                        "L'agent " .. agent_id .. " n'est validé sur aucun selfie parmi " .. tostring(count),
                        nil,
                        nil,
                        nil,
                        message.message_id
                    )
                end
            end
        end,
    },
    {
        name = 'selfies',
        description = 'donne les selfies sur lesquels apparaît le joueur',
        action = function (message, words)
            if not words[2] then return end
            local agent_id = words[2]:lower():match('%w+')
            if agent_id then
                local photos_id = {}
                for photo_agent in db.PhotoAgent:where_iterator{agent_id = agent_id} do
                    photos_id[photo_agent.photo_id] = true
                end
                for photo_id in pairs(photos_id) do
                    local photo = db.TelegramPhoto:get{file_unique_id = photo_id}
                    fwd_photo(message.chat.id, photo)
                end
            end
        end,
    },
}

for _,c in ipairs(commands) do
    commands[c.name] = c
end


function api.on_message(message)
    print(json.encode(message))
    -- update authorization on join
    if message.new_chat_members and message.chat.id == config.chat_membership then
        for i, user in ipairs(message.new_chat_members) do
            local user = users:get(user.id)
            user.member = 1
        end
        return
    end
    -- update authorization on leave
    if message.left_chat_member and message.chat.id == config.chat_membership then
        local user = users:get(message.left_chat_member.id)
        user.member = 0
        return
    end

    -- ignore anything without from
    if not message.from then
        return
    end

    local user = users:get(message.from.id)
    -- udate username
    if message.from.username then user.username = message.from.username end

    -- update admins
    if message.chat.id == config.admin_chat then
        user.admin = 1
    end

    --
    if message.chat.id == config.admin_chat and message.text then
        local text = message.text:gsub("@" .. bot.username, '')
        local words = utils.split(text, "%s+")
        if #words > 0 then
            local command = words[1]:match("/([%w_]+)")
            if command == 'help' then
                local help_message = ""
                for _, c in ipairs(commands) do
                    help_message = help_message .. string.format(
                        "/%s@%s - %s\n",
                        c.name,
                        bot.username,
                        c.description
                        )
                end
                api.send_message(
                    message.chat.id,
                    help_message,
                    nil,
                    nil,
                    nil,
                    message.message_id
                )
            elseif commands[command] then
                commands[command].action(message, words)
            end
        end
    end


    if admin_only then
        return
    end

    -- ignore group messages
    if message.chat.type ~= "private" then
        return
    end

    if user.member == 0 and user.admin == 0 then
        return
    end

    if message.text then
        local has_stats = false
        for stats in message.text:gmatch("Time Span[^\r\n]+\n[^\r\n]+") do
            utils.pcall(handle_stats, message, stats)
            has_stats = true
        end
        if not has_stats then
            utils.pcall(handle_agents, user, message)
        end
    end
    if message.photo then
        utils.pcall(handle_new_photo, user, message)
    end
end

function api.on_channel_post(channel_post)
    print(json.encode(channel_post))
end

local function callback_caption(answer, message, photo)
    if answer == 'yes' then
        photo.status = "public"
        api.edit_message_text(
            message.chat.id,
            message.message_id,
            "Autoriser l'utilisation dans le montage de la photo de groupe ?",
            nil,
            true,
            yesNoInlineKeyboard
        )
    else
        photo.status = "new"
        api.edit_message_text(
            message.chat.id,
            message.message_id,
            "Quels sont les agents sur la photo ?"
        )
    end
end

local function callback_public(answer, message, photo)
    photo.status = "verification"
    if answer == 'yes' then
        photo.public = 1
    elseif answer == 'no' then
        photo.public = 0
    end
    fwd_photo(config.fwd_to, photo)
    api.edit_message_text(
        message.chat.id,
        message.message_id,
        "Merci, la photo a été transmise aux organisateurs"
    )
end

local function callback_validate(answer, message, photo)
    local inline_keyboard
    if answer == 'yes' and photo.valid == 0 then
        photo.valid = 1
        inline_keyboard =
            api.inline_keyboard():row(
                api.row():callback_data_button(
                    '☑️ Valide',
                    'yes'
                )
            )
        -- message de validation pour le joueur
        api.send_message(
            photo.user_id,
            msg_ok
        )
    elseif photo.status == 'verification' and answer ~= 'yes' then
        photo.valid = 0
        inline_keyboard =
            api.inline_keyboard():row(
                api.row():callback_data_button(
                    'Valide',
                    'yes'
                ):callback_data_button(
                    '❌ Invalide',
                    'no'
                )
            )
    else
        return
    end
    photo.status = 'verified'
    api.edit_message_reply_markup(
        message.chat.id,
        message.message_id,
        nil,
        inline_keyboard
    )
end

function api.on_callback_query(callback_query)
    print(json.encode(callback_query))
    if not callback_query.message then return end

    -- verification
    if callback_query.message.chat.id == config.fwd_to and callback_query.message.photo then
        local photo = db.TelegramPhoto:get{file_unique_id = callback_query.message.photo[1].file_unique_id}
        if not photo or (photo.status ~= 'verification' and photo.status ~= 'verified') then
            api.answer_callback_query(
                callback_query.id,
                "Erreur: la photo n'existe pas dans la bdd ou est mal placée"
            )
        else
            utils.pcall(callback_validate, callback_query.data, callback_query.message, photo)
        end
        return
    end

    -- user step
    if callback_query.message.chat.type == "private" then
        local photo
        for v in  db.TelegramPhoto:where_iterator{user_id = callback_query.from.id} do
            if v.status == 'caption' or v.status == 'public' then
                photo = v
                break
            end
        end

        -- check existance and date
        if photo and photo.timestamp < callback_query.message.date then
            local answer = callback_query.data
            if photo.status == "caption" then
                utils.pcall(callback_caption, answer, callback_query.message, photo)
            elseif photo.status == "public" then
                utils.pcall(callback_public, answer, callback_query.message, photo)
            end
        else
            api.answer_callback_query(
                callback_query.id,
                "Ce message n'est plus valide. Un selfie peut être ?"
            )
            -- remove message
            api.delete_message(
                callback_query.message.chat.id,
                callback_query.message.message_id
            )
        end
        return
    end

    api.answer_callback_query(
        callback_query.id,
        "Ce message n'est plus valide."
    )
    -- remove message
    api.delete_message(
        callback_query.message.chat.id,
        callback_query.message.message_id
    )
end

api.run()