-- CoroutineManager Performance Testing Module
-- Validates 1ms yield timing, frame rate maintenance, and performance characteristics

local PerformanceTests = {}

-- Test configuration
local TEST_CONFIG = {
    FRAME_TARGET_MS = 16.67,        -- 60 FPS target
    YIELD_ACCURACY_TOLERANCE = 2,   -- ±2ms tolerance for yield timing
    STRESS_TEST_DURATION = 5000,    -- 5 second stress test
    MEMORY_LEAK_THRESHOLD = 1024    -- 1MB memory increase threshold
}

-- Performance measurement utilities
local function get_precise_time_ms()
    return core.get_time() * 1000
end

local function get_memory_usage_kb()
    return collectgarbage("count")
end

-- Test 1: Validate 1ms yield timing accuracy
function PerformanceTests.test_yield_timing_accuracy()
    LxNavigator.logger.info("=== Yield Timing Accuracy Test ===")
    
    local timing_results = {}
    local test_iterations = 100
    
    local timing_task = function()
        local start_time = get_precise_time_ms()
        local yield_times = {}
        
        for i = 1, test_iterations do
            local yield_start = get_precise_time_ms()
            coroutine_yield(1) -- Request 1ms yield
            local yield_end = get_precise_time_ms()
            
            local actual_yield_time = yield_end - yield_start
            table.insert(yield_times, actual_yield_time)
        end
        
        local total_time = get_precise_time_ms() - start_time
        
        return {
            yield_times = yield_times,
            total_time = total_time,
            iterations = test_iterations
        }
    end
    
    local test_callback = function(result, error_message, performance_data)
        if result then
            local yield_times = result.yield_times
            local total_yield_time = 0
            local min_yield = math.huge
            local max_yield = 0
            local accurate_yields = 0
            
            for _, yield_time in ipairs(yield_times) do
                total_yield_time = total_yield_time + yield_time
                min_yield = math.min(min_yield, yield_time)
                max_yield = math.max(max_yield, yield_time)
                
                -- Check if yield is within acceptable tolerance
                if math.abs(yield_time - 1.0) <= TEST_CONFIG.YIELD_ACCURACY_TOLERANCE then
                    accurate_yields = accurate_yields + 1
                end
            end
            
            local average_yield = total_yield_time / #yield_times
            local accuracy_percentage = (accurate_yields / #yield_times) * 100
            
            LxNavigator.logger.info("Results:")
            LxNavigator.logger.info("  Average yield time: " .. string.format("%.2f", average_yield) .. "ms (target: 1.00ms)")
            LxNavigator.logger.info("  Min yield time: " .. string.format("%.2f", min_yield) .. "ms")
            LxNavigator.logger.info("  Max yield time: " .. string.format("%.2f", max_yield) .. "ms")
            LxNavigator.logger.info("  Accuracy: " .. string.format("%.1f", accuracy_percentage) .. "% within ±" .. TEST_CONFIG.YIELD_ACCURACY_TOLERANCE .. "ms")
            LxNavigator.logger.info("  Total test time: " .. string.format("%.2f", result.total_time) .. "ms")
            
            -- Pass/fail criteria
            if accuracy_percentage >= 80 and average_yield <= 3.0 then
                LxNavigator.logger.info("  RESULT: PASS")
            else
                LxNavigator.logger.error("  RESULT: FAIL - Yield timing not accurate enough")
            end
        else
            LxNavigator.logger.error("Test failed: " .. (error_message or "Unknown error"))
        end
    end
    
    local coroutine_id = LxNavigator.CoroutineManager.create(timing_task, {
        name = "YieldTimingTest",
        priority = LxNavigator.CoroutineManager.PRIORITY.HIGH,
        callback = test_callback
    })
    
    return coroutine_id
end

-- Test 2: Frame rate impact measurement
function PerformanceTests.test_frame_rate_impact()
    LxNavigator.logger.info("=== Frame Rate Impact Test ===")
    
    local frame_impact_task = function()
        local frame_times = {}
        local test_duration = 2000 -- 2 seconds
        local start_time = get_precise_time_ms()
        local last_frame_time = start_time
        local iterations = 0
        
        while (get_precise_time_ms() - start_time) < test_duration do
            iterations = iterations + 1
            
            -- Simulate pathfinding work
            local dummy_work = 0
            for i = 1, 1000 do
                dummy_work = dummy_work + math.sqrt(i) * math.sin(i)
            end
            
            -- Measure frame time before yield
            local current_time = get_precise_time_ms()
            local frame_time = current_time - last_frame_time
            table.insert(frame_times, frame_time)
            last_frame_time = current_time
            
            -- Yield every 50 iterations (typical A* yield interval)
            if iterations % 50 == 0 then
                coroutine_yield(1)
            end
        end
        
        return {
            frame_times = frame_times,
            total_iterations = iterations,
            test_duration = test_duration
        }
    end
    
    local frame_callback = function(result, error_message, performance_data)
        if result then
            local frame_times = result.frame_times
            local total_frame_time = 0
            local max_frame_time = 0
            local frame_violations = 0
            
            for _, frame_time in ipairs(frame_times) do
                total_frame_time = total_frame_time + frame_time
                max_frame_time = math.max(max_frame_time, frame_time)
                
                if frame_time > TEST_CONFIG.FRAME_TARGET_MS then
                    frame_violations = frame_violations + 1
                end
            end
            
            local average_frame_time = total_frame_time / #frame_times
            local violation_percentage = (frame_violations / #frame_times) * 100
            local effective_fps = 1000 / average_frame_time
            
            LxNavigator.logger.info("Results:")
            LxNavigator.logger.info("  Total frames analyzed: " .. #frame_times)
            LxNavigator.logger.info("  Average frame time: " .. string.format("%.2f", average_frame_time) .. "ms")
            LxNavigator.logger.info("  Max frame time: " .. string.format("%.2f", max_frame_time) .. "ms")
            LxNavigator.logger.info("  Effective FPS: " .. string.format("%.1f", effective_fps))
            LxNavigator.logger.info("  Frame time violations: " .. frame_violations .. " (" .. string.format("%.1f", violation_percentage) .. "%)")
            LxNavigator.logger.info("  Total iterations: " .. result.total_iterations)
            
            -- Pass/fail criteria
            if violation_percentage <= 5 and effective_fps >= 55 then
                LxNavigator.logger.info("  RESULT: PASS")
            else
                LxNavigator.logger.error("  RESULT: FAIL - Frame rate impact too high")
            end
        else
            LxNavigator.logger.error("Test failed: " .. (error_message or "Unknown error"))
        end
    end
    
    local coroutine_id = LxNavigator.CoroutineManager.create(frame_impact_task, {
        name = "FrameRateTest",
        priority = LxNavigator.CoroutineManager.PRIORITY.NORMAL,
        callback = frame_callback
    })
    
    return coroutine_id
end

-- Test 3: Memory leak detection
function PerformanceTests.test_memory_leaks()
    LxNavigator.logger.info("=== Memory Leak Detection Test ===")
    
    local memory_test_task = function()
        local initial_memory = get_memory_usage_kb()
        local memory_samples = {initial_memory}
        local test_duration = 3000 -- 3 seconds
        local start_time = get_precise_time_ms()
        local iterations = 0
        
        while (get_precise_time_ms() - start_time) < test_duration do
            iterations = iterations + 1
            
            -- Create and destroy temporary objects to stress memory management
            local temp_data = {}
            for i = 1, 100 do
                temp_data[i] = {
                    position = {x = math.random(1000), y = math.random(1000), z = math.random(100)},
                    data = string.rep("x", 50) -- 50 byte strings
                }
            end
            
            -- Sample memory usage periodically
            if iterations % 100 == 0 then
                local current_memory = get_memory_usage_kb()
                table.insert(memory_samples, current_memory)
                coroutine_yield(1)
            end
            
            -- Clear temp data
            temp_data = nil
        end
        
        -- Final memory measurement after garbage collection
        collectgarbage("collect")
        local final_memory = get_memory_usage_kb()
        table.insert(memory_samples, final_memory)
        
        return {
            initial_memory = initial_memory,
            final_memory = final_memory,
            memory_samples = memory_samples,
            iterations = iterations
        }
    end
    
    local memory_callback = function(result, error_message, performance_data)
        if result then
            local memory_increase = result.final_memory - result.initial_memory
            local max_memory = 0
            local min_memory = math.huge
            
            for _, sample in ipairs(result.memory_samples) do
                max_memory = math.max(max_memory, sample)
                min_memory = math.min(min_memory, sample)
            end
            
            local peak_increase = max_memory - result.initial_memory
            
            LxNavigator.logger.info("Results:")
            LxNavigator.logger.info("  Initial memory: " .. string.format("%.2f", result.initial_memory) .. "KB")
            LxNavigator.logger.info("  Final memory: " .. string.format("%.2f", result.final_memory) .. "KB")
            LxNavigator.logger.info("  Memory increase: " .. string.format("%.2f", memory_increase) .. "KB")
            LxNavigator.logger.info("  Peak memory usage: " .. string.format("%.2f", max_memory) .. "KB")
            LxNavigator.logger.info("  Peak increase: " .. string.format("%.2f", peak_increase) .. "KB")
            LxNavigator.logger.info("  Total iterations: " .. result.iterations)
            
            -- Pass/fail criteria
            if memory_increase <= TEST_CONFIG.MEMORY_LEAK_THRESHOLD and peak_increase <= TEST_CONFIG.MEMORY_LEAK_THRESHOLD * 2 then
                LxNavigator.logger.info("  RESULT: PASS")
            else
                LxNavigator.logger.error("  RESULT: FAIL - Potential memory leak detected")
            end
        else
            LxNavigator.logger.error("Test failed: " .. (error_message or "Unknown error"))
        end
    end
    
    local coroutine_id = LxNavigator.CoroutineManager.create(memory_test_task, {
        name = "MemoryLeakTest",
        priority = LxNavigator.CoroutineManager.PRIORITY.LOW,
        callback = memory_callback
    })
    
    return coroutine_id
end

-- Test 4: Concurrent coroutine stress test
function PerformanceTests.test_concurrent_stress()
    LxNavigator.logger.info("=== Concurrent Coroutine Stress Test ===")
    
    local stress_results = {
        completed_coroutines = 0,
        failed_coroutines = 0,
        total_execution_time = 0,
        max_concurrent = 0
    }
    
    local stress_task = function(task_id)
        local start_time = get_precise_time_ms()
        local iterations = math.random(100, 500) -- Variable workload
        
        for i = 1, iterations do
            -- Variable work simulation
            local work_amount = math.random(500, 1500)
            local dummy_work = 0
            for j = 1, work_amount do
                dummy_work = dummy_work + math.sqrt(j)
            end
            
            -- Yield periodically
            if i % 25 == 0 then
                coroutine_yield(1)
            end
        end
        
        local execution_time = get_precise_time_ms() - start_time
        return {
            task_id = task_id,
            iterations = iterations,
            execution_time = execution_time
        }
    end
    
    local stress_callback = function(result, error_message, performance_data)
        if result then
            stress_results.completed_coroutines = stress_results.completed_coroutines + 1
            stress_results.total_execution_time = stress_results.total_execution_time + result.execution_time
        else
            stress_results.failed_coroutines = stress_results.failed_coroutines + 1
        end
        
        -- Check if this is the last coroutine
        local total_expected = 20 -- We'll create 20 concurrent coroutines
        if (stress_results.completed_coroutines + stress_results.failed_coroutines) >= total_expected then
            LxNavigator.logger.info("Stress Test Results:")
            LxNavigator.logger.info("  Completed coroutines: " .. stress_results.completed_coroutines)
            LxNavigator.logger.info("  Failed coroutines: " .. stress_results.failed_coroutines)
            LxNavigator.logger.info("  Success rate: " .. string.format("%.1f", (stress_results.completed_coroutines / total_expected) * 100) .. "%")
            LxNavigator.logger.info("  Average execution time: " .. string.format("%.2f", stress_results.total_execution_time / math.max(1, stress_results.completed_coroutines)) .. "ms")
            
            local system_stats = LxNavigator.CoroutineManager.get_stats()
            LxNavigator.logger.info("  Peak concurrent coroutines: " .. system_stats.active_coroutines)
            LxNavigator.logger.info("  Total yields during test: " .. system_stats.total_yields)
            LxNavigator.logger.info("  Frame time violations: " .. system_stats.frame_time_violations)
            
            -- Pass/fail criteria
            if stress_results.completed_coroutines >= 18 and system_stats.frame_time_violations <= 5 then
                LxNavigator.logger.info("  RESULT: PASS")
            else
                LxNavigator.logger.error("  RESULT: FAIL - System unable to handle concurrent load")
            end
        end
    end
    
    -- Create multiple concurrent coroutines
    local coroutine_ids = {}
    for i = 1, 20 do
        local task_func = function() return stress_task(i) end
        local coroutine_id = LxNavigator.CoroutineManager.create(task_func, {
            name = "StressTest_" .. i,
            priority = math.random(1, 3), -- Random priority
            callback = stress_callback
        })
        
        if coroutine_id then
            table.insert(coroutine_ids, coroutine_id)
        end
    end
    
    LxNavigator.logger.info("Created " .. #coroutine_ids .. " concurrent stress test coroutines")
    return coroutine_ids
end

-- Test 5: Priority scheduling validation
function PerformanceTests.test_priority_scheduling()
    LxNavigator.logger.info("=== Priority Scheduling Test ===")
    
    local completion_order = {}
    local completion_times = {}
    local start_time = get_precise_time_ms()
    
    local priority_task = function(priority, task_id)
        local task_start = get_precise_time_ms()
        
        -- High priority tasks do less work, low priority do more work
        local iterations = priority == 1 and 100 or (priority == 2 and 200 or 400)
        
        for i = 1, iterations do
            local dummy_work = 0
            for j = 1, 500 do
                dummy_work = dummy_work + math.sqrt(j)
            end
            
            if i % 50 == 0 then
                coroutine_yield(1)
            end
        end
        
        local completion_time = get_precise_time_ms() - start_time
        return {
            priority = priority,
            task_id = task_id,
            completion_time = completion_time,
            iterations = iterations
        }
    end
    
    local priority_callback = function(result, error_message, performance_data)
        if result then
            table.insert(completion_order, {
                priority = result.priority,
                task_id = result.task_id,
                completion_time = result.completion_time
            })
            completion_times[result.task_id] = result.completion_time
        end
        
        -- Check if all tasks completed
        if #completion_order >= 9 then -- 3 tasks per priority level
            LxNavigator.logger.info("Priority Scheduling Results:")
            
            -- Sort by completion time
            table.sort(completion_order, function(a, b) return a.completion_time < b.completion_time end)
            
            LxNavigator.logger.info("  Completion order (by time):")
            for i, task in ipairs(completion_order) do
                LxNavigator.logger.info("    " .. i .. ". Priority " .. task.priority .. " Task " .. task.task_id .. 
                      " (" .. string.format("%.2f", task.completion_time) .. "ms)")
            end
            
            -- Analyze priority correctness
            local high_priority_completed = 0
            local normal_priority_completed = 0
            
            for i = 1, math.min(6, #completion_order) do -- Check first 6 completions
                if completion_order[i].priority == 1 then
                    high_priority_completed = high_priority_completed + 1
                elseif completion_order[i].priority == 2 then
                    normal_priority_completed = normal_priority_completed + 1
                end
            end
            
            LxNavigator.logger.info("  First 6 completions: " .. high_priority_completed .. " high priority, " .. 
                  normal_priority_completed .. " normal priority")
            
            -- Pass/fail criteria (high priority should complete first)
            if high_priority_completed >= 2 then
                LxNavigator.logger.info("  RESULT: PASS")
            else
                LxNavigator.logger.error("  RESULT: FAIL - Priority scheduling not working correctly")
            end
        end
    end
    
    -- Create tasks with different priorities
    local task_priorities = {
        {1, "High1"}, {1, "High2"}, {1, "High3"},
        {2, "Normal1"}, {2, "Normal2"}, {2, "Normal3"},
        {3, "Low1"}, {3, "Low2"}, {3, "Low3"}
    }
    
    local coroutine_ids = {}
    for _, task_info in ipairs(task_priorities) do
        local priority = task_info[1]
        local task_id = task_info[2]
        
        local task_func = function() return priority_task(priority, task_id) end
        local coroutine_id = LxNavigator.CoroutineManager.create(task_func, {
            name = "PriorityTest_" .. task_id,
            priority = priority,
            callback = priority_callback
        })
        
        if coroutine_id then
            table.insert(coroutine_ids, coroutine_id)
        end
    end
    
    LxNavigator.logger.info("Created " .. #coroutine_ids .. " priority test coroutines")
    return coroutine_ids
end

-- Run all performance tests
function PerformanceTests.run_all_tests()
    LxNavigator.logger.info("=== CoroutineManager Performance Test Suite ===")
    LxNavigator.logger.info("Starting comprehensive performance validation...")
    LxNavigator.logger.info("")
    
    -- Reset statistics before testing
    LxNavigator.CoroutineManager.reset_stats()
    
    local test_functions = {
        {"Yield Timing Accuracy", PerformanceTests.test_yield_timing_accuracy},
        {"Frame Rate Impact", PerformanceTests.test_frame_rate_impact},
        {"Memory Leak Detection", PerformanceTests.test_memory_leaks},
        {"Concurrent Stress Test", PerformanceTests.test_concurrent_stress},
        {"Priority Scheduling", PerformanceTests.test_priority_scheduling}
    }
    
    local all_test_ids = {}
    
    for i, test_info in ipairs(test_functions) do
        LxNavigator.logger.info("Starting: " .. test_info[1])
        local test_ids = test_info[2]()
        
        if type(test_ids) == "table" then
            for _, id in ipairs(test_ids) do
                table.insert(all_test_ids, id)
            end
        elseif test_ids then
            table.insert(all_test_ids, test_ids)
        end
        
        LxNavigator.logger.info("")
        
        -- Allow some processing time between tests
        for j = 1, 20 do
            LxNavigator.update()
        end
    end
    
    LxNavigator.logger.info("=== All Performance Tests Started ===")
    LxNavigator.logger.info("Total test coroutines created: " .. #all_test_ids)
    LxNavigator.logger.info("Call LxNavigator.update() repeatedly to process tests")
    LxNavigator.logger.info("Tests will complete automatically and report results")
    
    return all_test_ids
end

-- Benchmark pathfinding performance specifically
function PerformanceTests.benchmark_pathfinding()
    LxNavigator.logger.info("=== Pathfinding Performance Benchmark ===")
    
    local benchmark_positions = {
        {start = {x = 100, y = 100, z = 50}, dest = {x = 200, y = 200, z = 55}},
        {start = {x = 0, y = 0, z = 0}, dest = {x = 500, y = 500, z = 70}},
        {start = {x = 300, y = 400, z = 60}, dest = {x = 800, y = 200, z = 45}},
        {start = {x = 1000, y = 1000, z = 100}, dest = {x = 1500, y = 800, z = 90}},
        {start = {x = 50, y = 300, z = 25}, dest = {x = 750, y = 600, z = 80}}
    }
    
    local benchmark_results = {}
    local completed_benchmarks = 0
    
    local benchmark_callback = function(path, error_message, performance_data)
        completed_benchmarks = completed_benchmarks + 1
        
        local result = {
            success = path ~= nil,
            path_length = path and #path or 0,
            error = error_message
        }
        
        if performance_data then
            result.execution_time = performance_data.execution_time
            result.yield_count = performance_data.yield_count
            result.memory_used = performance_data.memory_used
        end
        
        table.insert(benchmark_results, result)
        
        if completed_benchmarks >= #benchmark_positions then
            LxNavigator.logger.info("Pathfinding Benchmark Results:")
            
            local total_time = 0
            local successful_paths = 0
            local total_yields = 0
            local total_waypoints = 0
            
            for i, result in ipairs(benchmark_results) do
                LxNavigator.logger.info("  Test " .. i .. ":")
                if result.success then
                    successful_paths = successful_paths + 1
                    LxNavigator.logger.info("    SUCCESS - " .. result.path_length .. " waypoints")
                    if result.execution_time then
                        LxNavigator.logger.debug("    Execution time: " .. string.format("%.2f", result.execution_time) .. "ms")
                        LxNavigator.logger.debug("    Yields: " .. (result.yield_count or 0))
                        total_time = total_time + result.execution_time
                        total_yields = total_yields + (result.yield_count or 0)
                        total_waypoints = total_waypoints + result.path_length
                    end
                else
                    LxNavigator.logger.error("    FAILED - " .. (result.error or "Unknown error"))
                end
            end
            
            LxNavigator.logger.info("  Summary:")
            LxNavigator.logger.info("    Success rate: " .. string.format("%.1f", (successful_paths / #benchmark_results) * 100) .. "%")
            if successful_paths > 0 then
                LxNavigator.logger.info("    Average execution time: " .. string.format("%.2f", total_time / successful_paths) .. "ms")
                LxNavigator.logger.info("    Average yields per path: " .. string.format("%.1f", total_yields / successful_paths))
                LxNavigator.logger.info("    Average waypoints per path: " .. string.format("%.1f", total_waypoints / successful_paths))
            end
            
            local final_stats = LxNavigator.CoroutineManager.get_stats()
            LxNavigator.logger.info("    System stats during benchmark:")
            LxNavigator.logger.info("      Frame time violations: " .. final_stats.frame_time_violations)
            LxNavigator.logger.info("      Memory usage: " .. string.format("%.2f", final_stats.current_memory_usage) .. "KB")
        end
    end
    
    -- Start all benchmark paths
    local benchmark_ids = {}
    for i, positions in ipairs(benchmark_positions) do
        local coroutine_id = LxNavigator.PathPlanner.find_path_async(
            positions.start,
            positions.dest,
            {priority = LxNavigator.CoroutineManager.PRIORITY.NORMAL},
            benchmark_callback
        )
        
        if coroutine_id then
            table.insert(benchmark_ids, coroutine_id)
        end
    end
    
    LxNavigator.logger.info("Started " .. #benchmark_ids .. " pathfinding benchmarks")
    return benchmark_ids
end

return PerformanceTests