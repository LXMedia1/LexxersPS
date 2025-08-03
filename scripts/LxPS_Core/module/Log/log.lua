local function get_timestamp()
    local time_ms = core.time()
    local seconds = math.floor(time_ms / 1000)
    local ms = math.floor(time_ms % 1000)
    local minutes = math.floor(seconds / 60)
    local hours = math.floor(minutes / 60)
    
    seconds = seconds % 60
    minutes = minutes % 60
    hours = hours % 24
    
    return string.format("%02d:%02d:%02d.%03d", hours, minutes, seconds, ms)
end

return function(name)
    local log_filename = name .. ".log"
    local file_created = false
    
    return {
        write = function(message)
            local timestamp = get_timestamp()
            core.log("[" .. timestamp .. "] [" .. name .. "] " .. message)
        end,
        warning = function(message)
            local timestamp = get_timestamp()
            core.log_warning("[" .. timestamp .. "] [" .. name .. "] " .. message)
        end,
        error = function(message)
            local timestamp = get_timestamp()
            core.log_error("[" .. timestamp .. "] [" .. name .. "] " .. message)
        end,
        write_to_file = function(message, add_newline)
            if add_newline == nil then add_newline = true end
            if not file_created then
                core.create_log_file(log_filename)
                file_created = true
            end
            local timestamp = get_timestamp()
            local formatted_message = "[" .. timestamp .. "] [" .. name .. "] " .. message
            if add_newline then
                formatted_message = formatted_message .. "\n"
            end
            core.write_log_file(log_filename, formatted_message)
        end
    }
end