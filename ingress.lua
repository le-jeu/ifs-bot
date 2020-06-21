local utils = require "utils"

local ingress_entries = {
    "Time Span",
    "Agent Name",
    "Agent Faction",
    "Date (yyyy-mm-dd)",
    "Time (hh:mm:ss)",
    "Level",
    "Lifetime AP",
    "Current AP",
    "Unique Portals Visited",
    "Unique Portals Drone Visited",
    "Portals Discovered",
    "XM Collected",
    "OPR Agreements",
    "Distance Walked",
    "Resonators Deployed",
    "Links Created",
    "Control Fields Created",
    "Mind Units Captured",
    "Longest Link Ever Created",
    "Largest Control Field",
    "XM Recharged",
    "Portals Captured",
    "Unique Portals Captured",
    "Mods Deployed",
    "Resonators Destroyed",
    "Portals Neutralized",
    "Enemy Links Destroyed",
    "Enemy Fields Destroyed",
    "Max Time Portal Held",
    "Max Time Link Maintained",
    "Max Link Length x Days",
    "Max Time Field Held",
    "Largest Field MUs x Days",
    "Unique Missions Completed",
    "Hacks",
    "Drone Hacks",
    "Glyph Hack Points",
    "Longest Hacking Streak",
    "NL-1331 Meetup(s) Attended",
    "First Saturday Events",
    "Recursions",
    "Mission Day(s) Attended",
    "Furthest Drone Flight Distance",
    "Portal Scans Uploaded",
    "Agents Successfully Recruited",
    "Seer Points",
    "Forced Drone Recalls",
    "Clear Fields Events"
}

local text_entries = {
    ["Time Span"] = true,
    ["Agent Name"] = true,
    ["Agent Faction"] = true,
    ["Date (yyyy-mm-dd)"] = true,
    ["Time (hh:mm:ss)"] = true,
}

local function parse_stats(text)
    local lines = utils.split(text, '\n')
    if #lines < 2 then
        return { error = "nothing to parse" }
    end
    local header = utils.trim(lines[1])
    local data = utils.split(utils.trim(lines[2]), "%s+")

    -- Merge locale dependent time span
    for i,v in ipairs(data) do
        if v == 'Resistance' or v == 'Enlightened' then
            data[1] = table.concat(data, ' ', 1, i-2)
            table.move(data, i-1, #data, 2)
            break
        end
    end

    -- don't assume stats but whitout prefix
    local ret = {}
    for i,value in ipairs(data) do
        local ok = false
        for _,key in ipairs(ingress_entries) do
            if header:sub(1,#key) == key then
                if text_entries[key] then
                    ret[key] = value
                else
                    ret[key] = tonumber(value)
                end

                ok = true
                header = header:sub(#key+1)
                break
            end
        end

        if #header == 0 then break end

        if not ok then
            local first = header:match('^%S+')
            ret[first] = value
            header = header:sub(#first + 1)
        end
        header = header:gsub('^%s*', '')
    end

    if not ret['Agent Name'] then
        return {
            error = 'wrong data',
            data = ret
        }
    end

    if not ret['Agent Name']:find('^%w+$')
        or (ret['Agent Faction'] ~= 'Resistance' and ret['Agent Faction'] ~= 'Enlightened') then
        return {
            error = 'wrong value',
            data = ret
        }
    end
    return {
        success = true,
        data = ret
    }
end

local function print_stats(stat, sep)
    sep = sep or '\t'
    local l1 = {}
    local l2 = {}
    for i,k in ipairs(ingress_entries) do
        if stat[k] then
            table.insert(l1, k)
            table.insert(l2, stat[k])
        end
    end
    return table.concat(l1, sep) .. '\n' .. table.concat(l2, sep) .. '\n'
end

local function diff_stats(stat1, stat2)
    local ret = {}
    for k, v in pairs(stat2) do
        if text_entries[k] then
            ret[k] = v
        else
            ret[k] = v - (stat1[k] or 0)
        end
    end
    return ret
end

return {
    parse_stats = parse_stats,
    print_stats = print_stats,
    diff_stats = diff_stats,
}