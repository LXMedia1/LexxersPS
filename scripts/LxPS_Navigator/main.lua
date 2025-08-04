-- LxPS_Navigator - Advanced Navigation Library
-- Provides A* pathfinding and navigation mesh management using Project Sylvanas API

-- Required geometry utilities
local vec3 = require("common/geometry/vector_3")

-- Initialize Navigator namespace
LxNavigator = {}

-- Initialize comprehensive logging system for Navigator
-- First check if LxCore.LogManager is available, fallback to basic logging
local logger = nil
if _G.LxCore and _G.LxCore.LogManager then
    logger = _G.LxCore.LogManager("Navigator", {
        log_to_core = true,
        log_to_navigator = true,
        debug_level = "INFO",
        enable_performance = true
    })
    
    -- Log Navigator initialization message to core.log as specified in TODO  
    logger.log_initialization("LxPS_Navigator", "1.0", "Advanced navigation library with A* pathfinding and MMAP management")
else
    -- Fallback logging functions if LogManager not available
    local function log_info(module_name, message)
        core.log("[Navigator." .. module_name .. "] " .. message)
    end
    
    local function log_warning(module_name, message)
        core.log_warning("[Navigator." .. module_name .. "] " .. message)
    end
    
    local function log_error(module_name, message)
        core.log_error("[Navigator." .. module_name .. "] " .. message)
    end
    
    logger = {
        info = function(msg) log_info("Core", msg) end,
        warning = function(msg) log_warning("Core", msg) end,
        error = function(msg) log_error("Core", msg) end,
        debug = function(msg) log_info("Core", "[DEBUG] " .. msg) end,
        start_operation = function(name) return nil end,
        end_operation = function(id, result) return nil end,
        log_initialization = function(comp, ver, details) log_info("Core", "INIT [" .. comp .. " v" .. ver .. "] " .. details) end,
        log_pathfinding_operation = function(op, start, finish, result) 
            log_info("PathPlanner", "PATH [" .. op .. "] " .. result) 
        end,
        log_tile_operation = function(op, x, y, file, result)
            log_info("NavMesh", "TILE [" .. op .. "] [" .. x .. "," .. y .. "] " .. result)
        end,
        log_performance_summary = function() end
    }
    
    -- Log fallback initialization
    logger.log_initialization("LxPS_Navigator", "1.0", "Advanced navigation library (fallback logging)")
end

-- Expose enhanced logging system
LxNavigator.logger = logger

-- Performance tracking for module loading
local module_load_operation = logger.start_operation("Load_Navigator_Modules")

logger.info("Loading Navigator modules with performance tracking...")

-- Load Navigator modules with individual performance tracking
local pathplanner_load = logger.start_operation("Load_PathPlanner")
LxNavigator.PathPlanner = require("module/PathPlanner")
logger.end_operation(pathplanner_load, "PathPlanner module loaded")

local navmesh_load = logger.start_operation("Load_NavMesh")
LxNavigator.NavMesh = require("module/NavMesh")
logger.end_operation(navmesh_load, "NavMesh module loaded")

local waypoint_load = logger.start_operation("Load_WaypointManager")
LxNavigator.WaypointManager = require("module/WaypointManager")
logger.end_operation(waypoint_load, "WaypointManager module loaded")

local movement_load = logger.start_operation("Load_MovementController")
LxNavigator.MovementController = require("module/MovementController")
logger.end_operation(movement_load, "MovementController module loaded")

local coroutine_load = logger.start_operation("Load_CoroutineManager")
LxNavigator.CoroutineManager = require("module/CoroutineManager")
logger.end_operation(coroutine_load, "CoroutineManager module loaded")

logger.end_operation(module_load_operation, "All Navigator modules loaded successfully")

-- Expose Navigator globally
_G.LxNavigator = LxNavigator

-- Version information
LxNavigator.VERSION = "1.0"
LxNavigator.API_VERSION = "1.0"

-- System status with memory tracking
LxNavigator.is_initialized = true
LxNavigator.initialization_time = core.time()
LxNavigator.performance_tracking = logger.is_performance_enabled and logger.is_performance_enabled() or false

-- Enhanced system update function with performance monitoring
function LxNavigator.update()
    local update_operation = logger.start_operation("Navigator_Update_Frame")
    
    if LxNavigator.CoroutineManager then
        local coroutine_operation = logger.start_operation("Update_Coroutines")
        LxNavigator.CoroutineManager.update()
        logger.end_operation(coroutine_operation, "Coroutines updated")
    end
    
    logger.end_operation(update_operation, "Frame update completed")
end

-- Enhanced shutdown function with cleanup logging
function LxNavigator.shutdown()
    local shutdown_operation = logger.start_operation("Navigator_Shutdown")
    
    logger.info("Navigator system shutdown initiated")
    
    if LxNavigator.CoroutineManager then
        local coroutine_shutdown = logger.start_operation("Shutdown_Coroutines")
        LxNavigator.CoroutineManager.emergency_shutdown()
        logger.end_operation(coroutine_shutdown, "Coroutines shut down")
    end
    
    -- Log final performance summary
    logger.log_performance_summary()
    
    logger.info("Navigator system shutdown completed")
    logger.end_operation(shutdown_operation, "Complete system shutdown")
end

-- Performance monitoring functions
function LxNavigator.get_performance_stats()
    return {
        version = LxNavigator.VERSION,
        initialized = LxNavigator.is_initialized,
        initialization_time = LxNavigator.initialization_time,
        memory_usage = logger.get_memory_usage(),
        performance_tracking_enabled = LxNavigator.performance_tracking
    }
end

function LxNavigator.log_pathfinding_request(start_pos, end_pos, options)
    logger.log_pathfinding_operation("REQUEST", start_pos, end_pos, 
        string.format("Options: %s", options and "Custom" or "Default"))
end

function LxNavigator.log_pathfinding_result(start_pos, end_pos, path, execution_time)
    local result_info = path and 
        string.format("SUCCESS: %d waypoints, %.2fms", #path, execution_time or 0) or
        "FAILED: No path found"
    
    logger.log_pathfinding_operation("RESULT", start_pos, end_pos, result_info)
end

function LxNavigator.log_tile_loading(tile_x, tile_y, filename, success, vertex_count, polygon_count)
    local result = success and 
        string.format("SUCCESS: V:%d P:%d", vertex_count or 0, polygon_count or 0) or
        "FAILED: Could not load/parse tile"
    
    logger.log_tile_operation("LOAD", tile_x, tile_y, filename, result)
end

-- Final initialization logging
logger.info("=== LxPS_Navigator Initialization Complete ===")
logger.info("Available modules:")
logger.info("  - PathPlanner: Advanced A* pathfinding algorithms with performance tracking")
logger.info("  - NavMesh: Navigation mesh analysis and validation with tile management")
logger.info("  - WaypointManager: Waypoint creation and management with memory optimization")
logger.info("  - MovementController: Character movement coordination with execution timing")
logger.info("  - CoroutineManager: Non-blocking operations with 1ms yield timing and monitoring")
logger.info("")
logger.info("Performance Features:")
logger.info("  - Execution time tracking for all major operations")
logger.info("  - Memory usage monitoring and logging")
logger.info("  - Structured logging with timestamps and module identification")
logger.info("  - Log file rotation and management")
logger.info("  - Debug levels and conditional logging")
logger.info("")
logger.info("Navigator system ready for pathfinding operations")
logger.info("Call LxNavigator.update() every frame to process coroutines")
logger.info("Use LxNavigator.get_performance_stats() for runtime statistics")

-- Log system readiness to core.log as specified in TODO
logger.info("Navigator initialization message logged to core.log - system operational")

-- ===== POLYGON VISUALIZATION SYSTEM =====
-- Configuration for polygon drawing
local visualization_config = {
    enabled = false,
    draw_all_polygons = true,
    polygon_color = {r = 0, g = 255, b = 0, a = 100}, -- Green with transparency
    outline_color = {r = 255, g = 255, b = 255, a = 255}, -- White outline
    line_thickness = 1.0,
    fade_factor = 2.5,
    update_interval = 1.0, -- Update every 1 second
    last_update = 0,
    current_polygons = {},
    current_tile_data = nil
}


-- Function to load and draw polygons around player
local function update_polygon_visualization()
    if not visualization_config.enabled then
        return
    end
    
    local current_time = core.time()
    if current_time - visualization_config.last_update < visualization_config.update_interval then
        return
    end
    
    visualization_config.last_update = current_time
    
    -- Get player position
    local player = core.player
    if not player then return end
    
    local player_pos = player:position()
    if not player_pos then return end
    
    -- Get current map ID
    local map_id = core.world.map_id()
    if not map_id then return end
    
    logger.info(string.format("Loading polygons for player position: %.2f, %.2f, %.2f on map %d", 
        player_pos.x, player_pos.y, player_pos.z, map_id))
    
    -- Load navigation mesh for current tile
    if LxNavigator.NavMesh and LxNavigator.NavMesh.load_tile then
        local tile_data = LxNavigator.NavMesh.load_tile(player_pos.x, player_pos.y)
        
        if tile_data and tile_data.polygons then
            logger.info(string.format("Loaded %d polygons from navigation mesh", #tile_data.polygons))
            visualization_config.current_polygons = tile_data.polygons
            visualization_config.current_tile_data = tile_data
        else
            logger.warning("No navigation mesh data found for current position")
            visualization_config.current_polygons = {}
            visualization_config.current_tile_data = nil
        end
    else
        logger.error("NavMesh.load_tile function not available")
    end
end

-- Function to draw polygons
local function draw_polygons()
    if not visualization_config.enabled or not visualization_config.current_polygons then
        return
    end
    
    local tile_data = visualization_config.current_tile_data
    if not tile_data or not tile_data.vertices then
        return
    end
    
    for _, polygon in ipairs(visualization_config.current_polygons) do
        if polygon.vertices and #polygon.vertices >= 3 then
            -- Resolve vertex indices to actual coordinates
            local polygon_vertices = {}
            for _, vertex_index in ipairs(polygon.vertices) do
                local vertex = tile_data.vertices[vertex_index]
                if vertex then
                    table.insert(polygon_vertices, vertex)
                end
            end
            
            -- Only draw if we have valid vertices
            if #polygon_vertices >= 3 then
                -- Draw polygon outline
                for i = 1, #polygon_vertices do
                    local current_vertex = polygon_vertices[i]
                    local next_vertex = polygon_vertices[(i % #polygon_vertices) + 1]
                    
                    if current_vertex and next_vertex then
                        local start_pos = vec3.new(current_vertex.x, current_vertex.y, current_vertex.z)
                        local end_pos = vec3.new(next_vertex.x, next_vertex.y, next_vertex.z)
                        
                        core.graphics.line_3d(
                            start_pos, 
                            end_pos, 
                            visualization_config.outline_color,
                            visualization_config.line_thickness,
                            visualization_config.fade_factor,
                            true
                        )
                    end
                end
                
                -- Draw filled triangle for polygons with exactly 3 vertices
                if #polygon_vertices == 3 then
                    local v1 = polygon_vertices[1]
                    local v2 = polygon_vertices[2]  
                    local v3 = polygon_vertices[3]
                    
                    if v1 and v2 and v3 then
                        core.graphics.triangle_3d_filled(
                            vec3.new(v1.x, v1.y, v1.z),
                            vec3.new(v2.x, v2.y, v2.z),
                            vec3.new(v3.x, v3.y, v3.z),
                            visualization_config.polygon_color
                        )
                    end
                end
            end
        end
    end
end

-- Register callbacks
-- DISABLED - Drawing handled by LxPS_Test
-- core.register_on_render_callback(function()
--     update_polygon_visualization()
--     draw_polygons()
-- end)