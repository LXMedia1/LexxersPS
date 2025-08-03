-- CoroutineManager Usage Examples
-- Demonstrates how to use the coroutine-based pathfinding system

local Examples = {}

-- Example 1: Basic async pathfinding with progress tracking
function Examples.basic_async_pathfinding()
    local start_pos = {x = 100, y = 200, z = 50}
    local end_pos = {x = 500, y = 600, z = 55}
    
    -- Progress callback to track pathfinding progress
    local progress_callback = function(progress_info)
        LxNavigator.logger.debug("Pathfinding progress:")
        LxNavigator.logger.debug("  Execution time: " .. string.format("%.2f", progress_info.execution_time) .. "ms")
        LxNavigator.logger.debug("  Yields: " .. progress_info.yield_count)
        LxNavigator.logger.debug("  Estimated completion: " .. string.format("%.2f", progress_info.estimated_completion) .. "ms")
    end
    
    -- Result callback
    local result_callback = function(path, error_message, performance_data)
        if path then
            LxNavigator.logger.info("Path found with " .. #path .. " waypoints!")
            if performance_data then
                LxNavigator.logger.debug("Performance data:")
                LxNavigator.logger.debug("  Total execution time: " .. string.format("%.2f", performance_data.execution_time) .. "ms")
                LxNavigator.logger.debug("  Total yields: " .. performance_data.yield_count)
                LxNavigator.logger.debug("  Memory used: " .. string.format("%.2f", performance_data.memory_used) .. "KB")
                LxNavigator.logger.debug("  Peak memory: " .. string.format("%.2f", performance_data.peak_memory) .. "KB")
            end
        else
            LxNavigator.logger.error("Pathfinding failed: " .. (error_message or "Unknown error"))
        end
    end
    
    -- Start async pathfinding
    local coroutine_id = LxNavigator.PathPlanner.find_path_async(
        start_pos, 
        end_pos, 
        {progress_callback = progress_callback}, 
        result_callback
    )
    
    if coroutine_id then
        LxNavigator.logger.info("Started pathfinding operation (ID: " .. coroutine_id .. ")")
    else
        LxNavigator.logger.error("Failed to start pathfinding operation")
    end
    
    return coroutine_id
end

-- Example 2: High-priority pathfinding for combat scenarios
function Examples.priority_pathfinding()
    local player_pos = {x = 123, y = 456, z = 78}
    local escape_pos = {x = 789, y = 012, z = 90}
    
    local urgent_callback = function(path, error_message, performance_data)
        if path then
            LxNavigator.logger.warning("URGENT: Escape path found immediately!")
            -- Immediately start movement
            -- LxNavigator.MovementController.follow_path(path)
        else
            LxNavigator.logger.error("CRITICAL: No escape path available!")
        end
    end
    
    -- High-priority pathfinding gets more CPU time per frame
    local coroutine_id = LxNavigator.PathPlanner.find_path_priority(
        player_pos, 
        escape_pos, 
        urgent_callback
    )
    
    LxNavigator.logger.info("Started high-priority pathfinding (ID: " .. (coroutine_id or "FAILED") .. ")")
    return coroutine_id
end

-- Example 3: Background pathfinding for exploration
function Examples.background_pathfinding()
    local current_pos = {x = 0, y = 0, z = 0}
    local exploration_target = {x = 1000, y = 1000, z = 100}
    
    local exploration_callback = function(path, error_message, performance_data)
        if path then
            LxNavigator.logger.info("Exploration path ready (background processing)")
            LxNavigator.logger.debug("Path quality: " .. (performance_data and "high" or "standard"))
        else
            LxNavigator.logger.warning("Background pathfinding completed without result")
        end
    end
    
    -- Background pathfinding uses lower priority but more thorough search
    local coroutine_id = LxNavigator.PathPlanner.find_path_background(
        current_pos, 
        exploration_target, 
        exploration_callback
    )
    
    LxNavigator.logger.info("Started background pathfinding (ID: " .. (coroutine_id or "FAILED") .. ")")
    return coroutine_id
end

-- Example 4: Batch pathfinding for multiple destinations
function Examples.batch_pathfinding()
    local waypoints = {
        {x = 100, y = 100, z = 50},
        {x = 200, y = 200, z = 55},
        {x = 300, y = 300, z = 60},
        {x = 400, y = 400, z = 65},
        {x = 500, y = 500, z = 70}
    }
    
    -- Create path requests for visiting all waypoints in sequence
    local path_requests = {}
    for i = 1, #waypoints - 1 do
        table.insert(path_requests, {
            start_pos = waypoints[i],
            end_pos = waypoints[i + 1],
            options = {heuristic_weight = 1.0}
        })
    end
    
    -- Batch progress callback
    local batch_progress = function(progress_info)
        LxNavigator.logger.debug("Batch progress: " .. progress_info.completed .. "/" .. progress_info.total .. 
              " (" .. string.format("%.1f", progress_info.progress_percent) .. "%)")
    end
    
    -- Batch completion callback
    local batch_callback = function(results, error_message, performance_data)
        if results then
            LxNavigator.logger.info("Batch pathfinding completed!")
            local successful_paths = 0
            for _, result in ipairs(results) do
                if result.success then
                    successful_paths = successful_paths + 1
                end
            end
            LxNavigator.logger.info("Successful paths: " .. successful_paths .. "/" .. #results)
        else
            LxNavigator.logger.error("Batch pathfinding failed: " .. (error_message or "Unknown error"))
        end
    end
    
    -- Start batch pathfinding
    local coroutine_id = LxNavigator.PathPlanner.find_paths_batch(
        path_requests,
        {
            priority = LxNavigator.CoroutineManager.PRIORITY.NORMAL,
            progress_callback = batch_progress
        },
        batch_callback
    )
    
    LxNavigator.logger.info("Started batch pathfinding for " .. #path_requests .. " paths (ID: " .. (coroutine_id or "FAILED") .. ")")
    return coroutine_id
end

-- Example 5: Monitoring and management
function Examples.monitoring_example()
    LxNavigator.logger.info("=== Coroutine System Status ===")
    
    -- Get overall system statistics
    local stats = LxNavigator.CoroutineManager.get_stats()
    LxNavigator.logger.info("Active coroutines: " .. stats.active_coroutines)
    LxNavigator.logger.info("Running: " .. stats.running_coroutines .. ", Suspended: " .. stats.suspended_coroutines)
    LxNavigator.logger.info("Success rate: " .. string.format("%.1f", stats.success_rate) .. "%")
    LxNavigator.logger.info("Average execution time: " .. string.format("%.2f", stats.average_execution_time) .. "ms")
    LxNavigator.logger.info("Memory usage: " .. string.format("%.2f", stats.current_memory_usage) .. "KB")
    LxNavigator.logger.info("Frame time violations: " .. stats.frame_time_violations)
    
    -- Get all active coroutines
    local active_coroutines = LxNavigator.CoroutineManager.get_all_status()
    LxNavigator.logger.info("\n=== Active Coroutines ===")
    for _, coroutine_info in ipairs(active_coroutines) do
        LxNavigator.logger.info("ID " .. coroutine_info.id .. ": " .. coroutine_info.name)
        LxNavigator.logger.info("  State: " .. coroutine_info.state)
        LxNavigator.logger.info("  Priority: " .. coroutine_info.priority)
        LxNavigator.logger.info("  Execution time: " .. string.format("%.2f", coroutine_info.execution_time) .. "ms")
        LxNavigator.logger.info("  Yields: " .. coroutine_info.yield_count)
    end
    
    -- Get integrated performance report
    local performance_report = LxNavigator.PathPlanner.get_performance_report()
    LxNavigator.logger.info("\n=== Performance Report ===")
    LxNavigator.logger.info("PathPlanner stats:")
    LxNavigator.logger.info("  Success rate: " .. string.format("%.1f", performance_report.pathfinder.success_rate) .. "%")
    LxNavigator.logger.info("  Average time: " .. string.format("%.2f", performance_report.pathfinder.average_time) .. "s")
    LxNavigator.logger.info("  Memory efficiency: " .. string.format("%.1f", performance_report.pathfinder.memory_efficiency) .. "%")
    
    LxNavigator.logger.info("Coroutine integration: " .. performance_report.integration_status)
    if performance_report.coroutines.active_coroutines then
        LxNavigator.logger.info("  Active operations: " .. performance_report.coroutines.active_coroutines)
        LxNavigator.logger.info("  Total yields: " .. performance_report.coroutines.total_yields)
    end
end

-- Example 6: Cancellation and cleanup
function Examples.cancellation_example()
    -- Start a long-running pathfinding operation
    local start_pos = {x = 0, y = 0, z = 0}
    local distant_pos = {x = 10000, y = 10000, z = 1000} -- Very far away
    
    local callback = function(path, error_message, performance_data)
        LxNavigator.logger.info("Long pathfinding completed or cancelled")
    end
    
    local coroutine_id = LxNavigator.PathPlanner.find_path_background(start_pos, distant_pos, callback)
    
    if coroutine_id then
        LxNavigator.logger.info("Started long pathfinding operation (ID: " .. coroutine_id .. ")")
        
        -- Wait a bit, then cancel
        -- In real usage, this might be triggered by user action or changing game state
        LxNavigator.logger.warning("Cancelling operation after delay...")
        
        local cancelled = LxNavigator.PathPlanner.cancel_pathfinding(coroutine_id)
        if cancelled then
            LxNavigator.logger.info("Operation cancelled successfully")
        else
            LxNavigator.logger.warning("Failed to cancel operation (may have already completed)")
        end
    end
end

-- Example 7: Custom coroutine task
function Examples.custom_coroutine_task()
    -- Create a custom task that uses the coroutine system
    local custom_task = function()
        LxNavigator.logger.info("Starting custom task...")
        
        -- Simulate heavy computation with yielding
        for i = 1, 100 do
            -- Do some work
            local dummy_calculation = 0
            for j = 1, 1000 do
                dummy_calculation = dummy_calculation + math.sqrt(j)
            end
            
            -- Yield every 10 iterations to maintain responsiveness
            if i % 10 == 0 then
                coroutine_yield(1) -- 1ms yield
                LxNavigator.logger.debug("Custom task progress: " .. i .. "/100")
            end
        end
        
        LxNavigator.logger.info("Custom task completed!")
        return "Task result data"
    end
    
    local task_callback = function(result, error_message, performance_data)
        if result then
            LxNavigator.logger.info("Custom task finished with result: " .. tostring(result))
        else
            LxNavigator.logger.error("Custom task failed: " .. (error_message or "Unknown error"))
        end
    end
    
    -- Create custom coroutine
    local coroutine_id = LxNavigator.CoroutineManager.create(custom_task, {
        name = "CustomTask_Example",
        priority = LxNavigator.CoroutineManager.PRIORITY.NORMAL,
        callback = task_callback
    })
    
    LxNavigator.logger.info("Started custom coroutine task (ID: " .. (coroutine_id or "FAILED") .. ")")
    return coroutine_id
end

-- Example 8: Configuration and tuning
function Examples.configuration_example()
    LxNavigator.logger.info("=== Current Configuration ===")
    local config = LxNavigator.CoroutineManager.get_config()
    for key, value in pairs(config) do
        LxNavigator.logger.info(key .. " = " .. tostring(value))
    end
    
    LxNavigator.logger.info("\n=== Tuning for High Performance ===")
    -- Adjust settings for high performance scenarios
    LxNavigator.CoroutineManager.set_config("MAX_EXECUTION_TIME_MS", 8) -- Shorter frame time
    LxNavigator.CoroutineManager.set_config("HIGH_PRIORITY_SLICE_MS", 6) -- More time for priority tasks
    LxNavigator.CoroutineManager.set_config("PERFORMANCE_THRESHOLD_MS", 25) -- Lower warning threshold
    
    LxNavigator.logger.info("\n=== Tuning for Quality ===")
    -- Adjust settings for quality scenarios (exploration, planning)
    LxNavigator.CoroutineManager.set_config("MAX_EXECUTION_TIME_MS", 24) -- Longer frame time allowed
    LxNavigator.CoroutineManager.set_config("LOW_PRIORITY_SLICE_MS", 8) -- More time for background tasks
    LxNavigator.CoroutineManager.set_config("WATCHDOG_TIMEOUT_MS", 10000) -- Allow longer operations
end

-- Demonstration function that runs all examples
function Examples.run_all_examples()
    LxNavigator.logger.info("=== CoroutineManager Examples ===")
    LxNavigator.logger.info("Note: Call LxNavigator.update() repeatedly to process coroutines")
    LxNavigator.logger.info("")
    
    -- Run examples with delays between them
    local example_functions = {
        {"Basic Async Pathfinding", Examples.basic_async_pathfinding},
        {"Priority Pathfinding", Examples.priority_pathfinding},
        {"Background Pathfinding", Examples.background_pathfinding},
        {"Batch Pathfinding", Examples.batch_pathfinding},
        {"System Monitoring", Examples.monitoring_example},
        {"Cancellation", Examples.cancellation_example},
        {"Custom Coroutine", Examples.custom_coroutine_task},
        {"Configuration", Examples.configuration_example}
    }
    
    for i, example in ipairs(example_functions) do
        LxNavigator.logger.info("--- " .. example[1] .. " ---")
        example[2]()
        LxNavigator.logger.info("")
        
        -- Simulate processing time between examples
        if i < #example_functions then
            LxNavigator.logger.debug("(Simulating processing time...)")
            for j = 1, 10 do
                LxNavigator.update() -- Process coroutines
            end
            LxNavigator.logger.info("")
        end
    end
    
    LxNavigator.logger.info("=== Examples Complete ===")
    LxNavigator.logger.info("Final system status:")
    Examples.monitoring_example()
end

return Examples