-- CoroutineManager Documentation
-- Comprehensive guide to the coroutine-based pathfinding system

local Documentation = {}

Documentation.OVERVIEW = [[

=== COROUTINE-BASED PATHFINDING SYSTEM ===

The CoroutineManager provides a sophisticated coroutine system designed to prevent
game freezes during heavy pathfinding calculations. It implements precise 1ms yield
timing, priority-based scheduling, and comprehensive performance monitoring.

KEY FEATURES:
• Precise 1ms yield timing for 60 FPS game loop compatibility
• Priority-based coroutine scheduling (HIGH, NORMAL, LOW)
• Frame time budget management to prevent stuttering
• Memory usage tracking and leak detection
• Performance monitoring with detailed statistics
• Batch processing capabilities for multiple operations
• Graceful error handling and timeout protection
• Automatic cleanup and resource management

INTEGRATION:
The system integrates seamlessly with the existing PathPlanner A* implementation,
providing non-blocking pathfinding without sacrificing accuracy or performance.

]]

Documentation.QUICK_START = [[

=== QUICK START GUIDE ===

1. BASIC ASYNC PATHFINDING:
   local coroutine_id = LxNavigator.PathPlanner.find_path_async(
       start_pos, end_pos, options, callback_function
   )

2. SYSTEM UPDATE (call every frame):
   LxNavigator.update()

3. PRIORITY PATHFINDING:
   local coroutine_id = LxNavigator.PathPlanner.find_path_priority(
       start_pos, end_pos, callback_function
   )

4. BATCH PROCESSING:
   local coroutine_id = LxNavigator.PathPlanner.find_paths_batch(
       path_requests, options, callback_function
   )

5. MONITORING:
   local stats = LxNavigator.CoroutineManager.get_stats()

]]

Documentation.API_REFERENCE = [[

=== COROUTINEMANAGER API REFERENCE ===

CORE FUNCTIONS:

CoroutineManager.create(task_func, options)
  Creates and registers a new coroutine
  Parameters:
    - task_func: function - The task to execute
    - options: table - Configuration options
      • name: string - Coroutine name for debugging
      • priority: number - PRIORITY.HIGH/NORMAL/LOW
      • callback: function - Completion callback
      • progress_callback: function - Progress updates
  Returns: number - Coroutine ID or nil

CoroutineManager.update()
  Processes all active coroutines with time slicing
  Call this every frame from your main loop

CoroutineManager.cancel(coroutine_id)
  Cancels a specific coroutine
  Parameters:
    - coroutine_id: number - ID returned from create()
  Returns: boolean - Success status

CoroutineManager.get_stats()
  Returns comprehensive performance statistics
  Returns: table - Statistics data

CoroutineManager.get_status(coroutine_id)
  Gets status of a specific coroutine
  Returns: table - Status information or nil

PATHFINDING INTEGRATION:

PathPlanner.find_path_async(start_pos, end_pos, options, callback)
  Enhanced async pathfinding with coroutine management
  Returns: number - Coroutine ID

PathPlanner.find_path_priority(start_pos, end_pos, callback)
  High-priority pathfinding for critical operations
  Returns: number - Coroutine ID

PathPlanner.find_path_background(start_pos, end_pos, callback)
  Low-priority pathfinding for non-critical operations
  Returns: number - Coroutine ID

PathPlanner.find_paths_batch(path_requests, options, callback)
  Batch processing for multiple paths
  Returns: number - Coroutine ID

CONFIGURATION:

CoroutineManager.set_config(key, value)
  Adjusts system configuration
  Available keys:
    - YIELD_INTERVAL_MS: Yield timing (default: 1ms)
    - MAX_EXECUTION_TIME_MS: Frame time budget (default: 16ms)
    - MAX_ACTIVE_COROUTINES: Concurrent limit (default: 10)
    - HIGH_PRIORITY_SLICE_MS: High priority time slice (default: 8ms)
    - LOW_PRIORITY_SLICE_MS: Low priority time slice (default: 4ms)
    - WATCHDOG_TIMEOUT_MS: Operation timeout (default: 5000ms)

]]

Documentation.PERFORMANCE_GUIDE = [[

=== PERFORMANCE OPTIMIZATION GUIDE ===

YIELD TIMING:
The system uses precise 1ms yields to maintain 60 FPS compatibility:
• Each yield surrenders control for exactly 1ms
• Yields occur automatically based on execution time
• Frame time budget prevents any single frame from exceeding 16ms

PRIORITY SYSTEM:
Three priority levels optimize resource allocation:
• HIGH: Critical operations (movement, combat) - 8ms per frame
• NORMAL: Standard pathfinding - 4ms per frame  
• LOW: Background tasks - 2ms per frame

MEMORY MANAGEMENT:
• Automatic memory usage tracking
• Periodic garbage collection hints
• Memory leak detection and warnings
• Node pool recycling for efficiency

PERFORMANCE MONITORING:
Key metrics tracked continuously:
• Frame time violations (should be < 5%)
• Memory usage patterns
• Yield timing accuracy
• Coroutine success rates
• Execution time statistics

TUNING RECOMMENDATIONS:

High Performance Scenarios (Combat, Movement):
• Use PRIORITY.HIGH for critical operations
• Reduce MAX_EXECUTION_TIME_MS to 8-12ms
• Increase HIGH_PRIORITY_SLICE_MS to 10ms
• Set stricter PERFORMANCE_THRESHOLD_MS

Quality Scenarios (Exploration, Planning):
• Use PRIORITY.LOW for background operations
• Increase MAX_EXECUTION_TIME_MS to 20-24ms
• Allow longer WATCHDOG_TIMEOUT_MS
• Use batch processing for multiple operations

]]

Documentation.TROUBLESHOOTING = [[

=== TROUBLESHOOTING GUIDE ===

COMMON ISSUES AND SOLUTIONS:

1. FRAME RATE DROPS:
   Symptoms: Game stuttering, low FPS
   Causes: 
     - Too many concurrent high-priority coroutines
     - MAX_EXECUTION_TIME_MS set too high
     - Heavy pathfinding operations without proper yielding
   Solutions:
     - Reduce MAX_ACTIVE_COROUTINES
     - Lower MAX_EXECUTION_TIME_MS (try 8-12ms)
     - Use PRIORITY.LOW for non-critical operations
     - Check for frame_time_violations in stats

2. PATHFINDING TIMEOUTS:
   Symptoms: Operations fail with "Timeout" error
   Causes:
     - Very complex pathfinding scenarios
     - WATCHDOG_TIMEOUT_MS set too low
     - System overloaded with operations
   Solutions:
     - Increase WATCHDOG_TIMEOUT_MS
     - Use emergency pathfinding for fallback
     - Reduce pathfinding complexity (lower max_iterations)
     - Cancel non-essential operations

3. MEMORY LEAKS:
   Symptoms: Increasing memory usage over time
   Causes:
     - Coroutines not properly cleaned up
     - Callback functions holding references
     - Large temporary data structures
   Solutions:
     - Call cleanup() regularly
     - Ensure callback functions don't retain large objects
     - Monitor memory_usage_peak in stats
     - Force garbage collection: collectgarbage("collect")

4. YIELD TIMING INACCURACY:
   Symptoms: Jerky movement, inconsistent performance
   Causes:
     - System overload
     - Incorrect yield interval configuration
     - External system interference
   Solutions:
     - Run performance tests to measure accuracy
     - Adjust YIELD_INTERVAL_MS if needed
     - Reduce concurrent operations
     - Check for other CPU-intensive processes

5. COROUTINES NOT STARTING:
   Symptoms: find_path_async returns nil
   Causes:
     - MAX_ACTIVE_COROUTINES limit reached
     - Invalid task function
     - CoroutineManager not initialized
   Solutions:
     - Check active coroutine count
     - Increase MAX_ACTIVE_COROUTINES if needed
     - Verify LxNavigator.CoroutineManager exists
     - Cancel unnecessary operations

DEBUGGING COMMANDS:

-- Check system status
local stats = LxNavigator.CoroutineManager.get_stats()
LxNavigator.logger.info("Active: " .. stats.active_coroutines)
LxNavigator.logger.info("Success rate: " .. stats.success_rate .. "%")
LxNavigator.logger.info("Frame violations: " .. stats.frame_time_violations)

-- Monitor specific coroutine
local status = LxNavigator.CoroutineManager.get_status(coroutine_id)
if status then
    LxNavigator.logger.info("State: " .. status.state)
    LxNavigator.logger.info("Execution time: " .. status.execution_time .. "ms")
end

-- Get all active coroutines
local all_status = LxNavigator.CoroutineManager.get_all_status()
for _, info in ipairs(all_status) do
    LxNavigator.logger.info("ID " .. info.id .. " State: " .. info.state .. " Priority: " .. info.priority)
end

-- Run performance tests
local test_ids = require("module/CoroutineManager/performance_tests").run_all_tests()

]]

Documentation.ARCHITECTURE = [[

=== SYSTEM ARCHITECTURE ===

COMPONENT OVERVIEW:

1. COROUTINE MANAGER CORE:
   • Coroutine registry and lifecycle management
   • Priority-based scheduling system
   • Time slicing and frame budget management
   • Performance monitoring and statistics

2. TIMING SYSTEM:
   • High-precision millisecond timing
   • 1ms yield implementation with tolerance checking
   • Frame time budget enforcement
   • Watchdog timeout protection

3. MEMORY MANAGEMENT:
   • Usage tracking and leak detection
   • Automatic cleanup of completed coroutines
   • Garbage collection hints and optimization
   • Memory threshold monitoring

4. INTEGRATION LAYER:
   • PathPlanner integration wrapper
   • Fallback mode for systems without CoroutineManager
   • Callback and error handling standardization
   • Performance data collection

DATA FLOW:

1. User Request → CoroutineManager.create()
2. Task Registration → Priority Queue
3. Frame Update → LxNavigator.update()
4. Time Slicing → Process by Priority
5. Yield Control → 1ms Timing System
6. Completion → Callback Execution
7. Cleanup → Resource Deallocation

THREADING MODEL:
• Single-threaded cooperative multitasking
• Voluntary yielding prevents blocking
• Priority-based time allocation
• Frame-rate aware processing

PERFORMANCE CHARACTERISTICS:
• Sub-millisecond yield accuracy (±2ms tolerance)
• 60 FPS compatibility (16.67ms frame budget)
• Memory efficient (node pool recycling)
• Scalable (configurable concurrent limits)

]]

Documentation.EXAMPLES = [[

=== USAGE EXAMPLES ===

EXAMPLE 1 - Basic Async Pathfinding:

local callback = function(path, error_message, performance_data)
    if path then
        LxNavigator.logger.info("Path found with " .. #path .. " waypoints")
        -- Use the path for movement
    else
        LxNavigator.logger.error("Pathfinding failed: " .. (error_message or "Unknown"))
    end
end

local coroutine_id = LxNavigator.PathPlanner.find_path_async(
    {x = 100, y = 100, z = 50},  -- start
    {x = 500, y = 500, z = 70},  -- end
    {},                          -- options
    callback                     -- result callback
)

EXAMPLE 2 - Priority Pathfinding:

-- High priority for combat escape
local escape_callback = function(path, error)
    if path then
        -- Immediately start movement
        start_escape_movement(path)
    else
        -- Use emergency fallback
        use_emergency_escape()
    end
end

local escape_id = LxNavigator.PathPlanner.find_path_priority(
    player_position, safe_position, escape_callback
)

EXAMPLE 3 - Batch Processing:

local waypoints = {{x=100,y=100,z=50}, {x=200,y=200,z=55}, {x=300,y=300,z=60}}
local path_requests = {}

for i = 1, #waypoints - 1 do
    table.insert(path_requests, {
        start_pos = waypoints[i],
        end_pos = waypoints[i + 1],
        options = {}
    })
end

local batch_callback = function(results, error)
    if results then
        LxNavigator.logger.info("Batch completed: " .. #results .. " paths")
        for i, result in ipairs(results) do
            if result.success then
                -- Use result.path
            end
        end
    end
end

local batch_id = LxNavigator.PathPlanner.find_paths_batch(
    path_requests, {}, batch_callback
)

EXAMPLE 4 - Progress Tracking:

local progress_callback = function(progress_info)
    local percent = (progress_info.yield_count / 100) * 100  -- Rough estimate
    update_progress_bar(math.min(percent, 100))
end

local result_callback = function(path, error, performance_data)
    hide_progress_bar()
    -- Handle result
end

local tracking_id = LxNavigator.PathPlanner.find_path_async(
    start_pos, end_pos,
    {progress_callback = progress_callback},
    result_callback
)

EXAMPLE 5 - Custom Coroutine Task:

local custom_task = function()
    for i = 1, 1000 do
        -- Do some work
        perform_calculation(i)
        
        -- Yield every 50 iterations for responsiveness
        if i % 50 == 0 then
            coroutine_yield(1)  -- 1ms yield
        end
    end
    
    return "Task completed"
end

local custom_callback = function(result, error, performance_data)
    LxNavigator.logger.info("Custom task result: " .. tostring(result))
end

local custom_id = LxNavigator.CoroutineManager.create(custom_task, {
    name = "CustomCalculation",
    priority = LxNavigator.CoroutineManager.PRIORITY.LOW,
    callback = custom_callback
})

]]

-- Function to display documentation sections
function Documentation.show_section(section_name)
    local section = Documentation[section_name:upper()]
    if section then
        LxNavigator.logger.info(section)
    else
        LxNavigator.logger.info("Available documentation sections:")
        for key, _ in pairs(Documentation) do
            if type(Documentation[key]) == "string" and key ~= "show_section" then
                LxNavigator.logger.info("  " .. key:lower())
            end
        end
    end
end

-- Display all documentation
function Documentation.show_all()
    local sections = {"OVERVIEW", "QUICK_START", "API_REFERENCE", "PERFORMANCE_GUIDE", "TROUBLESHOOTING", "ARCHITECTURE", "EXAMPLES"}
    
    for _, section in ipairs(sections) do
        LxNavigator.logger.info("=" .. string.rep("=", 60) .. "=")
        LxNavigator.logger.info(Documentation[section])
        LxNavigator.logger.info("")
    end
end

return Documentation