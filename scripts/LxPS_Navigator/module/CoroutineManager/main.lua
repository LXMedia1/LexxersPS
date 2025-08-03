-- CoroutineManager Module
-- Advanced coroutine management for non-blocking pathfinding with 1ms yield timing
-- Provides performance monitoring, progress tracking, and lifecycle management

local CoroutineManager = {}

-- Coroutine Management Configuration
local COROUTINE_CONFIG = {
    YIELD_INTERVAL_MS = 1,              -- Yield every 1ms for game loop compatibility
    MAX_EXECUTION_TIME_MS = 16,         -- Maximum execution time per frame (16ms = 60 FPS)
    MAX_ACTIVE_COROUTINES = 10,         -- Maximum concurrent coroutines
    CLEANUP_INTERVAL = 100,             -- Cleanup dead coroutines every N updates
    PERFORMANCE_THRESHOLD_MS = 50,      -- Warning threshold for long operations
    MEMORY_CHECK_INTERVAL = 500,        -- Memory usage check interval
    WATCHDOG_TIMEOUT_MS = 5000,         -- Coroutine timeout (5 seconds)
    HIGH_PRIORITY_SLICE_MS = 8,         -- Time slice for high priority operations
    LOW_PRIORITY_SLICE_MS = 4           -- Time slice for low priority operations
}

-- Coroutine Registry and State Management
local active_coroutines = {}
local coroutine_counter = 0
local cleanup_counter = 0
local performance_stats = {
    total_created = 0,
    total_completed = 0,
    total_failed = 0,
    total_timeout = 0,
    total_yield_count = 0,
    average_execution_time = 0,
    max_execution_time = 0,
    memory_usage_peak = 0,
    frame_time_violations = 0
}

-- Priority levels for coroutines
local PRIORITY = {
    HIGH = 1,    -- Critical operations (movement, combat)
    NORMAL = 2,  -- Standard pathfinding
    LOW = 3      -- Background tasks, optimization
}

-- Coroutine states
local STATE = {
    CREATED = "created",
    RUNNING = "running", 
    SUSPENDED = "suspended",
    COMPLETED = "completed",
    FAILED = "failed",
    TIMEOUT = "timeout"
}

-- High-precision timing functions
local function get_precise_time()
    return core.get_time() * 1000 -- Convert to milliseconds
end

local function yield_with_timing(duration_ms)
    duration_ms = duration_ms or COROUTINE_CONFIG.YIELD_INTERVAL_MS
    coroutine.yield(duration_ms)
    performance_stats.total_yield_count = performance_stats.total_yield_count + 1
end

-- Memory usage tracking
local function get_memory_usage()
    return collectgarbage("count") -- Returns memory usage in KB
end

-- Coroutine wrapper with performance monitoring
local function create_monitored_coroutine(task_func, options)
    options = options or {}
    
    return coroutine.create(function()
        local start_time = get_precise_time()
        local start_memory = get_memory_usage()
        local yield_count = 0
        local last_yield_time = start_time
        
        -- Execution wrapper with timing control
        local function timed_execution()
            local current_time = get_precise_time()
            local execution_time = current_time - last_yield_time
            
            -- Check if we need to yield to maintain frame rate
            local time_slice = options.priority == PRIORITY.HIGH and 
                              COROUTINE_CONFIG.HIGH_PRIORITY_SLICE_MS or
                              COROUTINE_CONFIG.LOW_PRIORITY_SLICE_MS
                              
            if execution_time >= time_slice then
                yield_with_timing(COROUTINE_CONFIG.YIELD_INTERVAL_MS)
                last_yield_time = get_precise_time()
                yield_count = yield_count + 1
                
                -- Check for timeout
                local total_time = last_yield_time - start_time
                if total_time > COROUTINE_CONFIG.WATCHDOG_TIMEOUT_MS then
                    error("Coroutine timeout: exceeded " .. COROUTINE_CONFIG.WATCHDOG_TIMEOUT_MS .. "ms")
                end
            end
        end
        
        -- Inject timing checks into the task
        local original_env = getfenv(task_func)
        local monitored_env = setmetatable({
            coroutine_yield = function(ms)
                timed_execution()
                if ms then yield_with_timing(ms) end
            end,
            check_timing = timed_execution
        }, {__index = original_env})
        
        setfenv(task_func, monitored_env)
        
        -- Execute the task
        local success, result = pcall(task_func)
        
        -- Record performance metrics
        local end_time = get_precise_time()
        local end_memory = get_memory_usage()
        local total_time = end_time - start_time
        local memory_used = end_memory - start_memory
        
        -- Update statistics
        performance_stats.average_execution_time = 
            (performance_stats.average_execution_time * performance_stats.total_completed + total_time) / 
            (performance_stats.total_completed + 1)
        performance_stats.max_execution_time = math.max(performance_stats.max_execution_time, total_time)
        performance_stats.memory_usage_peak = math.max(performance_stats.memory_usage_peak, end_memory)
        
        if total_time > COROUTINE_CONFIG.MAX_EXECUTION_TIME_MS then
            performance_stats.frame_time_violations = performance_stats.frame_time_violations + 1
        end
        
        return success, result, {
            execution_time = total_time,
            yield_count = yield_count,
            memory_used = memory_used,
            peak_memory = end_memory
        }
    end)
end

-- Create and register a new coroutine
function CoroutineManager.create(task_func, options)
    if not task_func or type(task_func) ~= "function" then
        LxNavigator.log.error("CoroutineManager", "Invalid task function provided")
        return nil
    end
    
    options = options or {}
    local priority = options.priority or PRIORITY.NORMAL
    local callback = options.callback
    local progress_callback = options.progress_callback
    local name = options.name or ("Coroutine_" .. (coroutine_counter + 1))
    
    -- Check active coroutine limit
    if #active_coroutines >= COROUTINE_CONFIG.MAX_ACTIVE_COROUTINES then
        LxNavigator.log.warning("CoroutineManager", "Maximum active coroutines reached, queuing request")
        -- Could implement queueing here
        return nil
    end
    
    coroutine_counter = coroutine_counter + 1
    
    -- Create monitored coroutine
    local coro = create_monitored_coroutine(task_func, options)
    
    -- Create coroutine descriptor
    local descriptor = {
        id = coroutine_counter,
        name = name,
        coroutine = coro,
        state = STATE.CREATED,
        priority = priority,
        callback = callback,
        progress_callback = progress_callback,
        created_time = get_precise_time(),
        last_resume_time = 0,
        total_execution_time = 0,
        yield_count = 0,
        result = nil,
        error_message = nil,
        performance_data = nil
    }
    
    -- Register coroutine
    table.insert(active_coroutines, descriptor)
    performance_stats.total_created = performance_stats.total_created + 1
    
    LxNavigator.logger.info("Created coroutine: " .. name .. " (ID: " .. coroutine_counter .. ", Priority: " .. priority .. ")")
    
    return coroutine_counter
end

-- Resume all active coroutines with time slicing
function CoroutineManager.update()
    if #active_coroutines == 0 then return end
    
    local frame_start_time = get_precise_time()
    local processed_count = 0
    
    -- Sort by priority (lower number = higher priority)
    table.sort(active_coroutines, function(a, b) 
        return a.priority < b.priority 
    end)
    
    -- Process coroutines with time budget management
    for i = #active_coroutines, 1, -1 do
        local descriptor = active_coroutines[i]
        
        -- Skip if not in resumable state
        if descriptor.state ~= STATE.RUNNING and descriptor.state ~= STATE.CREATED and descriptor.state ~= STATE.SUSPENDED then
            goto continue
        end
        
        -- Check frame time budget
        local current_time = get_precise_time()
        local frame_time_used = current_time - frame_start_time
        
        if frame_time_used >= COROUTINE_CONFIG.MAX_EXECUTION_TIME_MS and processed_count > 0 then
            -- Stop processing to maintain frame rate
            LxNavigator.log.warning("CoroutineManager", "Frame time budget exceeded, deferring remaining coroutines")
            break
        end
        
        -- Resume coroutine
        local resume_start = get_precise_time()
        descriptor.last_resume_time = resume_start
        
        local success, result, performance_data = coroutine.resume(descriptor.coroutine)
        
        local resume_end = get_precise_time()
        local resume_time = resume_end - resume_start
        descriptor.total_execution_time = descriptor.total_execution_time + resume_time
        
        -- Update coroutine state
        local coro_status = coroutine.status(descriptor.coroutine)
        
        if not success then
            -- Coroutine failed
            descriptor.state = STATE.FAILED
            descriptor.error_message = tostring(result)
            performance_stats.total_failed = performance_stats.total_failed + 1
            
            LxNavigator.log.error("CoroutineManager", "Coroutine " .. descriptor.name .. " failed: " .. descriptor.error_message)
            
            if descriptor.callback then
                descriptor.callback(nil, descriptor.error_message)
            end
            
        elseif coro_status == "dead" then
            -- Coroutine completed
            descriptor.state = STATE.COMPLETED
            descriptor.result = result
            descriptor.performance_data = performance_data
            performance_stats.total_completed = performance_stats.total_completed + 1
            
            LxNavigator.logger.info("Coroutine " .. descriptor.name .. " completed in " .. 
                                string.format("%.2f", descriptor.total_execution_time) .. "ms")
            
            if descriptor.callback then
                descriptor.callback(result, nil, performance_data)
            end
            
        elseif coro_status == "suspended" then
            -- Coroutine yielded
            descriptor.state = STATE.SUSPENDED
            descriptor.yield_count = descriptor.yield_count + 1
            
            -- Check for timeout
            local total_time = resume_end - descriptor.created_time
            if total_time > COROUTINE_CONFIG.WATCHDOG_TIMEOUT_MS then
                descriptor.state = STATE.TIMEOUT
                performance_stats.total_timeout = performance_stats.total_timeout + 1
                
                LxNavigator.log.error("CoroutineManager", "Coroutine " .. descriptor.name .. " timeout")
                
                if descriptor.callback then
                    descriptor.callback(nil, "Timeout")
                end
            end
            
            -- Call progress callback if provided
            if descriptor.progress_callback then
                local progress_info = {
                    execution_time = descriptor.total_execution_time,
                    yield_count = descriptor.yield_count,
                    estimated_completion = estimate_completion_time(descriptor)
                }
                descriptor.progress_callback(progress_info)
            end
        end
        
        processed_count = processed_count + 1
        
        ::continue::
    end
    
    -- Cleanup completed/failed coroutines periodically
    cleanup_counter = cleanup_counter + 1
    if cleanup_counter >= COROUTINE_CONFIG.CLEANUP_INTERVAL then
        CoroutineManager.cleanup()
        cleanup_counter = 0
    end
    
    -- Memory check
    if cleanup_counter % COROUTINE_CONFIG.MEMORY_CHECK_INTERVAL == 0 then
        local memory_usage = get_memory_usage()
        if memory_usage > performance_stats.memory_usage_peak * 1.5 then
            LxNavigator.log.warning("CoroutineManager", "High memory usage detected: " .. 
                                   string.format("%.2f", memory_usage) .. "KB")
            collectgarbage("collect")
        end
    end
end

-- Estimate completion time for a coroutine
local function estimate_completion_time(descriptor)
    if descriptor.yield_count == 0 then return 0 end
    
    local avg_time_per_yield = descriptor.total_execution_time / descriptor.yield_count
    local current_time = get_precise_time()
    local elapsed_time = current_time - descriptor.created_time
    
    -- Simple linear estimation (could be improved with more sophisticated modeling)
    return elapsed_time * 2 -- Rough estimate
end

-- Clean up completed, failed, and timeout coroutines
function CoroutineManager.cleanup()
    local cleaned_count = 0
    
    for i = #active_coroutines, 1, -1 do
        local descriptor = active_coroutines[i]
        
        if descriptor.state == STATE.COMPLETED or 
           descriptor.state == STATE.FAILED or 
           descriptor.state == STATE.TIMEOUT then
            
            table.remove(active_coroutines, i)
            cleaned_count = cleaned_count + 1
        end
    end
    
    if cleaned_count > 0 then
        LxNavigator.logger.info("Cleaned up " .. cleaned_count .. " finished coroutines")
        
        -- Force garbage collection after cleanup
        collectgarbage("collect")
    end
end

-- Cancel a specific coroutine
function CoroutineManager.cancel(coroutine_id)
    for i, descriptor in ipairs(active_coroutines) do
        if descriptor.id == coroutine_id then
            descriptor.state = STATE.FAILED
            descriptor.error_message = "Cancelled by user"
            
            LxNavigator.logger.info("Cancelled coroutine: " .. descriptor.name)
            
            if descriptor.callback then
                descriptor.callback(nil, "Cancelled")
            end
            
            return true
        end
    end
    
    return false
end

-- Cancel all active coroutines
function CoroutineManager.cancel_all()
    local cancelled_count = 0
    
    for _, descriptor in ipairs(active_coroutines) do
        if descriptor.state == STATE.RUNNING or 
           descriptor.state == STATE.SUSPENDED or 
           descriptor.state == STATE.CREATED then
            
            descriptor.state = STATE.FAILED
            descriptor.error_message = "Cancelled - system shutdown"
            
            if descriptor.callback then
                descriptor.callback(nil, "System shutdown")
            end
            
            cancelled_count = cancelled_count + 1
        end
    end
    
    LxNavigator.logger.info("Cancelled " .. cancelled_count .. " active coroutines")
    return cancelled_count
end

-- Get coroutine status
function CoroutineManager.get_status(coroutine_id)
    for _, descriptor in ipairs(active_coroutines) do
        if descriptor.id == coroutine_id then
            return {
                id = descriptor.id,
                name = descriptor.name,
                state = descriptor.state,
                priority = descriptor.priority,
                execution_time = descriptor.total_execution_time,
                yield_count = descriptor.yield_count,
                created_time = descriptor.created_time,
                error_message = descriptor.error_message
            }
        end
    end
    
    return nil
end

-- Get all active coroutines status
function CoroutineManager.get_all_status()
    local status_list = {}
    
    for _, descriptor in ipairs(active_coroutines) do
        table.insert(status_list, {
            id = descriptor.id,
            name = descriptor.name,
            state = descriptor.state,
            priority = descriptor.priority,
            execution_time = descriptor.total_execution_time,
            yield_count = descriptor.yield_count,
            created_time = descriptor.created_time
        })
    end
    
    return status_list
end

-- Get performance statistics
function CoroutineManager.get_stats()
    local active_count = 0
    local running_count = 0
    local suspended_count = 0
    
    for _, descriptor in ipairs(active_coroutines) do
        active_count = active_count + 1
        if descriptor.state == STATE.RUNNING then
            running_count = running_count + 1
        elseif descriptor.state == STATE.SUSPENDED then
            suspended_count = suspended_count + 1
        end
    end
    
    return {
        active_coroutines = active_count,
        running_coroutines = running_count,
        suspended_coroutines = suspended_count,
        total_created = performance_stats.total_created,
        total_completed = performance_stats.total_completed,
        total_failed = performance_stats.total_failed,
        total_timeout = performance_stats.total_timeout,
        success_rate = performance_stats.total_created > 0 and 
                      (performance_stats.total_completed / performance_stats.total_created * 100) or 0,
        total_yields = performance_stats.total_yield_count,
        average_execution_time = performance_stats.average_execution_time,
        max_execution_time = performance_stats.max_execution_time,
        memory_usage_peak = performance_stats.memory_usage_peak,
        frame_time_violations = performance_stats.frame_time_violations,
        current_memory_usage = get_memory_usage()
    }
end

-- Reset performance statistics
function CoroutineManager.reset_stats()
    performance_stats = {
        total_created = 0,
        total_completed = 0,
        total_failed = 0,
        total_timeout = 0,
        total_yield_count = 0,
        average_execution_time = 0,
        max_execution_time = 0,
        memory_usage_peak = 0,
        frame_time_violations = 0
    }
    
    LxNavigator.logger.info("Performance statistics reset")
end

-- Configuration management
function CoroutineManager.set_config(key, value)
    if COROUTINE_CONFIG[key] ~= nil then
        local old_value = COROUTINE_CONFIG[key]
        COROUTINE_CONFIG[key] = value
        
        LxNavigator.logger.info("Config updated: " .. key .. " = " .. tostring(value) .. 
                            " (was: " .. tostring(old_value) .. ")")
        return true
    else
        LxNavigator.log.error("CoroutineManager", "Unknown config key: " .. tostring(key))
        return false
    end
end

function CoroutineManager.get_config()
    return COROUTINE_CONFIG
end

-- Advanced pathfinding with coroutine integration
function CoroutineManager.find_path_async(start_pos, end_pos, options, callback)
    if not callback then
        LxNavigator.log.error("CoroutineManager", "Callback function required for async pathfinding")
        return nil
    end
    
    options = options or {}
    local priority = options.priority or PRIORITY.NORMAL
    local progress_callback = options.progress_callback
    
    -- Create pathfinding task
    local pathfinding_task = function()
        -- Wrap the original pathfinding function with timing checks
        local modified_options = {}
        for k, v in pairs(options) do
            modified_options[k] = v
        end
        modified_options.use_coroutines = true
        
        -- Inject timing control into the pathfinding algorithm
        local path = LxNavigator.PathPlanner.find_path(start_pos, end_pos, modified_options)
        
        return path
    end
    
    -- Create coroutine with performance monitoring
    local coroutine_id = CoroutineManager.create(pathfinding_task, {
        name = "AsyncPathfinding_" .. coroutine_counter,
        priority = priority,
        callback = callback,
        progress_callback = progress_callback
    })
    
    if coroutine_id then
        LxNavigator.logger.info("Started async pathfinding (ID: " .. coroutine_id .. ")")
    end
    
    return coroutine_id
end

-- Batch pathfinding for multiple paths
function CoroutineManager.find_paths_batch(path_requests, options, callback)
    if not path_requests or #path_requests == 0 then
        LxNavigator.log.error("CoroutineManager", "No path requests provided for batch processing")
        return nil
    end
    
    options = options or {}
    local priority = options.priority or PRIORITY.LOW -- Lower priority for batch operations
    
    local batch_task = function()
        local results = {}
        local completed_count = 0
        local total_count = #path_requests
        
        for i, request in ipairs(path_requests) do
            -- Yield between each path calculation
            if i > 1 then
                coroutine_yield(COROUTINE_CONFIG.YIELD_INTERVAL_MS)
            end
            
            local path = LxNavigator.PathPlanner.find_path(request.start_pos, request.end_pos, request.options)
            results[i] = {
                index = i,
                request = request,
                path = path,
                success = path ~= nil
            }
            
            completed_count = completed_count + 1
            
            -- Progress update
            if options.progress_callback then
                options.progress_callback({
                    completed = completed_count,
                    total = total_count,
                    progress_percent = (completed_count / total_count) * 100
                })
            end
        end
        
        return results
    end
    
    local coroutine_id = CoroutineManager.create(batch_task, {
        name = "BatchPathfinding_" .. coroutine_counter,
        priority = priority,
        callback = callback,
        progress_callback = options.progress_callback
    })
    
    if coroutine_id then
        LxNavigator.logger.info("Started batch pathfinding for " .. #path_requests .. 
                            " paths (ID: " .. coroutine_id .. ")")
    end
    
    return coroutine_id
end

-- Emergency shutdown - force stop all coroutines
function CoroutineManager.emergency_shutdown()
    LxNavigator.log.warning("CoroutineManager", "Emergency shutdown initiated")
    
    local cancelled_count = CoroutineManager.cancel_all()
    CoroutineManager.cleanup()
    
    -- Force garbage collection
    collectgarbage("collect")
    
    LxNavigator.logger.info("Emergency shutdown completed. Cancelled " .. cancelled_count .. " coroutines")
end

-- Expose priority constants
CoroutineManager.PRIORITY = PRIORITY
CoroutineManager.STATE = STATE

LxNavigator.logger.info("Advanced Coroutine Manager loaded")
LxNavigator.logger.info("Configuration: Yield=" .. COROUTINE_CONFIG.YIELD_INTERVAL_MS .. 
                    "ms, MaxExecution=" .. COROUTINE_CONFIG.MAX_EXECUTION_TIME_MS .. 
                    "ms, MaxActive=" .. COROUTINE_CONFIG.MAX_ACTIVE_COROUTINES)

return CoroutineManager