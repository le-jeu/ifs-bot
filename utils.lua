local utils = {}

function utils.split(str, sep)
    local ret = {}
    local pos = 1
    while true do
        local start, stop = str:find(sep, pos)
        if not start then
            start = #str + 1
        end
        table.insert(ret, str:sub(pos, start-1))
        if not stop then break end
        pos = stop + 1
    end
    return ret
end

function utils.trim(str)
    return str:gsub('^%s+', ''):gsub('%s+$', '')
end

local function msgh(err)
    print(debug.traceback(err, 2))
end

function utils.pcall(f, ...)
    local status, ret = xpcall(f, msgh, ...)
    if status then return ret end
end

return utils