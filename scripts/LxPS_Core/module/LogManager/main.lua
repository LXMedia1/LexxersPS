-- Enhanced LogManager for comprehensive logging with performance tracking
-- Provides execution time tracking, memory usage monitoring, and structured logging

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

local function get_memory_usage()
    -- Get Lua memory usage in KB
    return math.floor(collectgarbage("count"))
end

local function format_execution_time(start_time, end_time)
    local duration_ms = end_time - start_time
    if duration_ms < 1000 then
        return string.format("%.3fms", duration_ms)
    else
        return string.format("%.3fs", duration_ms / 1000)
    end
end

-- Performance tracking state
local performance_data = {}
local log_rotation_size = 10 * 1024 * 1024 -- 10MB per log file

local function rotate_log_if_needed(filename)
    -- Simple rotation - in practice would check file size
    -- For now, just ensure the file exists
    return true
end

return function(name, options)
    options = options or {}
    local log_to_core = options.log_to_core ~= false -- Default true
    local log_to_navigator = options.log_to_navigator or false
    local debug_level = options.debug_level or "INFO" -- DEBUG, INFO, WARNING, ERROR
    local enable_performance = options.enable_performance ~= false -- Default true
    
    local core_log_filename = "core.log"
    local navigator_log_filename = "navigator.log"
    local module_log_filename = name .. ".log"
    
    local files_created = {
        core = false,
        navigator = false,
        module = false
    }
    
    local function ensure_log_file(file_type, filename)
        if not files_created[file_type] then
            core.create_log_file(filename)
            files_created[file_type] = true
            rotate_log_if_needed(filename)
        end
    end
    
    local function write_to_log_file(filename, message, add_timestamp)
        if add_timestamp == nil then add_timestamp = true end
        local formatted_message = message
        if add_timestamp then
            local timestamp = get_timestamp()
            local memory = get_memory_usage()
            formatted_message = string.format("[%s] [%s] [MEM:%dKB] %s\n", 
                timestamp, name, memory, message)
        else
            formatted_message = message .. "\n"
        end
        core.write_log_file(filename, formatted_message)
    end
    
    local function should_log(level)
        local levels = {DEBUG = 1, INFO = 2, WARNING = 3, ERROR = 4}
        return levels[level] >= levels[debug_level]
    end
    
    -- Performance tracking methods
    local function start_operation(operation_name)
        if not enable_performance then return nil end
        
        local operation_id = name .. ":" .. operation_name .. ":" .. tostring(core.time())
        performance_data[operation_id] = {
            name = operation_name,
            module = name,
            start_time = core.time(),
            start_memory = get_memory_usage()
        }
        return operation_id
    end
    
    local function end_operation(operation_id, result_info)
        if not enable_performance or not operation_id or not performance_data[operation_id] then 
            return nil 
        end
        
        local data = performance_data[operation_id]
        local end_time = core.time()
        local end_memory = get_memory_usage()
        
        local execution_time = format_execution_time(data.start_time, end_time)
        local memory_delta = end_memory - data.start_memory
        local memory_change = memory_delta >= 0 and ("+" .. memory_delta) or tostring(memory_delta)
        
        local perf_message = string.format("PERF [%s] completed in %s (Memory: %sKB) %s", 
            data.name, execution_time, memory_change, result_info or "")
        
        -- Log performance data to all relevant files
        if log_to_core then
            ensure_log_file("core", core_log_filename)
            write_to_log_file(core_log_filename, perf_message)
        end
        
        if log_to_navigator then
            ensure_log_file("navigator", navigator_log_filename)
            write_to_log_file(navigator_log_filename, perf_message)
        end
        
        ensure_log_file("module", module_log_filename)
        write_to_log_file(module_log_filename, perf_message)
        
        -- Clean up
        performance_data[operation_id] = nil
        
        return {
            execution_time = execution_time,
            memory_delta = memory_delta,
            operation = data.name
        }
    end
    
    return {
        -- Standard logging methods
        write = function(message)
            if not should_log("INFO") then return end
            
            local timestamp = get_timestamp()
            local console_message = "[" .. timestamp .. "] [" .. name .. "] " .. message
            core.log(console_message)
            
            if log_to_core then
                ensure_log_file("core", core_log_filename)
                write_to_log_file(core_log_filename, message)
            end
        end,
        
        debug = function(message)
            if not should_log("DEBUG") then return end
            
            local timestamp = get_timestamp()
            local console_message = "[" .. timestamp .. "] [" .. name .. "] [DEBUG] " .. message
            core.log(console_message)
            
            ensure_log_file("module", module_log_filename)
            write_to_log_file(module_log_filename, "[DEBUG] " .. message)
        end,
        
        info = function(message)
            if not should_log("INFO") then return end
            
            local timestamp = get_timestamp()
            local console_message = "[" .. timestamp .. "] [" .. name .. "] [INFO] " .. message
            core.log(console_message)
            
            if log_to_core then
                ensure_log_file("core", core_log_filename)
                write_to_log_file(core_log_filename, "[INFO] " .. message)
            end
        end,
        
        warning = function(message)
            if not should_log("WARNING") then return end
            
            local timestamp = get_timestamp()
            local console_message = "[" .. timestamp .. "] [" .. name .. "] [WARNING] " .. message
            core.log_warning(console_message)
            
            if log_to_core then
                ensure_log_file("core", core_log_filename)
                write_to_log_file(core_log_filename, "[WARNING] " .. message)
            end
            
            if log_to_navigator then
                ensure_log_file("navigator", navigator_log_filename)
                write_to_log_file(navigator_log_filename, "[WARNING] " .. message)
            end
        end,
        
        error = function(message)
            if not should_log("ERROR") then return end
            
            local timestamp = get_timestamp()
            local console_message = "[" .. timestamp .. "] [" .. name .. "] [ERROR] " .. message
            core.log_error(console_message)
            
            -- Errors always go to all log files
            ensure_log_file("core", core_log_filename)
            write_to_log_file(core_log_filename, "[ERROR] " .. message)
            
            ensure_log_file("navigator", navigator_log_filename)
            write_to_log_file(navigator_log_filename, "[ERROR] " .. message)
            
            ensure_log_file("module", module_log_filename)
            write_to_log_file(module_log_filename, "[ERROR] " .. message)
        end,
        
        -- File-only logging (no console output)
        write_to_file = function(message, add_newline)
            if add_newline == nil then add_newline = true end
            ensure_log_file("module", module_log_filename)
            
            local formatted_message = message
            if add_newline then
                formatted_message = formatted_message .. "\n"
            end
            
            local timestamp = get_timestamp()
            local memory = get_memory_usage()
            local log_message = string.format("[%s] [%s] [MEM:%dKB] %s", 
                timestamp, name, memory, formatted_message)
            
            core.write_log_file(module_log_filename, log_message)
        end,
        
        -- Performance tracking methods
        start_operation = start_operation,
        end_operation = end_operation,
        
        -- Structured logging for specific events
        log_initialization = function(component, version, details)
            local init_message = string.format("INIT [%s v%s] %s", 
                component, version or "1.0", details or "initialized")
            
            if log_to_core then
                ensure_log_file("core", core_log_filename)
                write_to_log_file(core_log_filename, init_message)
            end
            
            if log_to_navigator then
                ensure_log_file("navigator", navigator_log_filename)
                write_to_log_file(navigator_log_filename, init_message)
            end
            
            -- Also log to console
            local timestamp = get_timestamp()
            core.log("[" .. timestamp .. "] [" .. name .. "] " .. init_message)
        end,
        
        log_pathfinding_operation = function(operation_type, start_pos, end_pos, result)
            local path_message = string.format("PATH [%s] Start:(%.2f,%.2f,%.2f) End:(%.2f,%.2f,%.2f) Result:%s",
                operation_type,
                start_pos.x, start_pos.y, start_pos.z,
                end_pos.x, end_pos.y, end_pos.z,
                result)
            
            if log_to_navigator then
                ensure_log_file("navigator", navigator_log_filename)
                write_to_log_file(navigator_log_filename, path_message)
            end
            
            ensure_log_file("module", module_log_filename)
            write_to_log_file(module_log_filename, path_message)
        end,
        
        log_tile_operation = function(operation_type, tile_x, tile_y, filename, result)
            local tile_message = string.format("TILE [%s] Tile:[%d,%d] File:%s Result:%s",
                operation_type, tile_x or -1, tile_y or -1, filename or "unknown", result)
            
            if log_to_navigator then
                ensure_log_file("navigator", navigator_log_filename)
                write_to_log_file(navigator_log_filename, tile_message)
            end
            
            ensure_log_file("module", module_log_filename)
            write_to_log_file(module_log_filename, tile_message)
        end,
        
        -- Memory and performance summary
        log_performance_summary = function()
            local memory = get_memory_usage()
            local active_operations = 0
            for _ in pairs(performance_data) do
                active_operations = active_operations + 1
            end
            
            local summary = string.format("PERFORMANCE_SUMMARY Memory:%dKB ActiveOps:%d", 
                memory, active_operations)
            
            ensure_log_file("module", module_log_filename)
            write_to_log_file(module_log_filename, summary)
            
            if log_to_core then
                ensure_log_file("core", core_log_filename)
                write_to_log_file(core_log_filename, summary)
            end
        end,
        
        -- Utility methods
        get_debug_level = function() return debug_level end,
        set_debug_level = function(level) debug_level = level end,
        get_memory_usage = get_memory_usage,
        is_performance_enabled = function() return enable_performance end
    }
end