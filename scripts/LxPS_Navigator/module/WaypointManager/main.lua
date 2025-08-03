-- WaypointManager Module
-- Waypoint creation, storage, and management utilities using Project Sylvanas API

local WaypointManager = {}

-- Internal waypoint storage
local waypoints = {}
local waypoint_routes = {}

-- Waypoint structure:
-- {
--   id = unique_id,
--   name = "waypoint_name", 
--   position = {x, y, z},
--   metadata = {
--     created_time = timestamp,
--     zone = "zone_name",
--     notes = "user_notes"
--   }
-- }

-- Create a new waypoint
-- @param name string: Waypoint name
-- @param pos table: Position {x, y, z} (optional, uses current player position)
-- @param metadata table: Additional waypoint data (optional)
-- @return string: Waypoint ID or nil if failed
function WaypointManager.create_waypoint(name, pos, metadata)
    LxNavigator.logger.info("Creating waypoint: " .. (name or "unnamed"))
    
    -- Use current player position if none provided
    if not pos then
        local player = core.object_manager.get_local_player()
        if not player then
            LxNavigator.log.error("WaypointManager", "No player found and no position provided")
            return nil
        end
        pos = player:get_position()
    end
    
    -- Validate position is on navigation mesh using our NavMesh module
    if LxNavigator.NavMesh and not LxNavigator.NavMesh.is_position_valid(pos) then
        LxNavigator.log.warning("WaypointManager", "Waypoint position may not be on valid navigation mesh")
    end
    
    -- Generate unique ID using game time
    local waypoint_id = "wp_" .. core.time() .. "_" .. math.random(1000, 9999)
    
    -- Create waypoint
    local waypoint = {
        id = waypoint_id,
        name = name or ("Waypoint_" .. waypoint_id),
        position = {x = pos.x, y = pos.y, z = pos.z},
        metadata = metadata or {}
    }
    
    -- Add timestamp if not provided
    if not waypoint.metadata.created_time then
        waypoint.metadata.created_time = core.time()
    end
    
    -- Store waypoint
    waypoints[waypoint_id] = waypoint
    
    LxNavigator.logger.info("Waypoint created: " .. waypoint.name .. " at (" .. 
              string.format("%.2f", pos.x) .. ", " .. 
              string.format("%.2f", pos.y) .. ", " .. 
              string.format("%.2f", pos.z) .. ")")
    
    return waypoint_id
end

-- Delete waypoint
-- @param waypoint_id string: Waypoint ID
-- @return boolean: True if deleted successfully
function WaypointManager.delete_waypoint(waypoint_id)
    if not waypoints[waypoint_id] then
        LxNavigator.log.warning("WaypointManager", "Waypoint not found: " .. waypoint_id)
        return false
    end
    
    local waypoint_name = waypoints[waypoint_id].name
    waypoints[waypoint_id] = nil
    
    LxNavigator.logger.info("Waypoint deleted: " .. waypoint_name)
    return true
end

-- Get waypoint by ID
-- @param waypoint_id string: Waypoint ID
-- @return table: Waypoint data or nil if not found
function WaypointManager.get_waypoint(waypoint_id)
    return waypoints[waypoint_id]
end

-- Get all waypoints
-- @return table: Array of all waypoints
function WaypointManager.get_all_waypoints()
    local all_waypoints = {}
    for _, waypoint in pairs(waypoints) do
        table.insert(all_waypoints, waypoint)
    end
    return all_waypoints
end

-- Find waypoints by name (partial match)
-- @param name_pattern string: Name pattern to search for
-- @return table: Array of matching waypoints
function WaypointManager.find_waypoints_by_name(name_pattern)
    local matches = {}
    name_pattern = string.lower(name_pattern)
    
    for _, waypoint in pairs(waypoints) do
        if string.find(string.lower(waypoint.name), name_pattern) then
            table.insert(matches, waypoint)
        end
    end
    
    LxNavigator.logger.info("Found " .. #matches .. " waypoints matching '" .. name_pattern .. "'")
    return matches
end

-- Find nearest waypoint to position
-- @param pos table: Position {x, y, z}
-- @param max_distance number: Maximum search distance (optional)
-- @return table: Nearest waypoint or nil if none found
function WaypointManager.find_nearest_waypoint(pos, max_distance)
    local nearest_waypoint = nil
    local nearest_distance = max_distance or math.huge
    
    for _, waypoint in pairs(waypoints) do
        local wp_pos = waypoint.position
        local dx = wp_pos.x - pos.x
        local dy = wp_pos.y - pos.y
        local dz = wp_pos.z - pos.z
        local distance = math.sqrt(dx*dx + dy*dy + dz*dz)
        
        if distance < nearest_distance then
            nearest_distance = distance
            nearest_waypoint = waypoint
        end
    end
    
    if nearest_waypoint then
        LxNavigator.logger.info("Nearest waypoint: " .. nearest_waypoint.name .. " (distance: " .. string.format("%.2f", nearest_distance) .. ")")
    else
        LxNavigator.logger.info("No waypoints found within distance limit")
    end
    
    return nearest_waypoint
end

-- Create route from waypoints
-- @param route_name string: Route name
-- @param waypoint_ids table: Array of waypoint IDs in order
-- @return string: Route ID or nil if failed
function WaypointManager.create_route(route_name, waypoint_ids)
    LxNavigator.logger.info("Creating route: " .. route_name .. " with " .. #waypoint_ids .. " waypoints")
    
    -- Validate all waypoints exist
    for _, wp_id in ipairs(waypoint_ids) do
        if not waypoints[wp_id] then
            LxNavigator.log.error("WaypointManager", "Waypoint not found in route: " .. wp_id)
            return nil
        end
    end
    
    local route_id = "route_" .. core.time() .. "_" .. math.random(1000, 9999)
    
    waypoint_routes[route_id] = {
        id = route_id,
        name = route_name,
        waypoint_ids = waypoint_ids,
        created_time = core.time()
    }
    
    LxNavigator.logger.info("Route created: " .. route_name)
    return route_id
end

-- Get route waypoint positions
-- @param route_id string: Route ID
-- @return table: Array of positions {x, y, z}
function WaypointManager.get_route_positions(route_id)
    local route = waypoint_routes[route_id]
    if not route then
        LxNavigator.log.warning("WaypointManager", "Route not found: " .. route_id)
        return nil
    end
    
    local positions = {}
    for _, wp_id in ipairs(route.waypoint_ids) do
        local waypoint = waypoints[wp_id]
        if waypoint then
            table.insert(positions, waypoint.position)
        else
            LxNavigator.log.warning("WaypointManager", "Waypoint missing from route: " .. wp_id)
        end
    end
    
    return positions
end

-- Save waypoints to file (for persistence)
-- @param filename string: File name (optional, defaults to "waypoints.dat")
-- @return boolean: True if saved successfully
function WaypointManager.save_waypoints_to_file(filename)
    filename = filename or "waypoints.dat"
    LxNavigator.logger.info("Saving waypoints to file: " .. filename)
    
    -- TODO: Use Project Sylvanas API file I/O to save waypoints
    -- This might use core.file.write() or similar API
    -- For now, just log the count
    
    local count = 0
    for _ in pairs(waypoints) do
        count = count + 1
    end
    
    LxNavigator.logger.info("Would save " .. count .. " waypoints to " .. filename)
    return true -- Placeholder
end

-- Load waypoints from file
-- @param filename string: File name (optional, defaults to "waypoints.dat")
-- @return boolean: True if loaded successfully
function WaypointManager.load_waypoints_from_file(filename)
    filename = filename or "waypoints.dat"
    LxNavigator.logger.info("Loading waypoints from file: " .. filename)
    
    -- TODO: Use Project Sylvanas API file I/O to load waypoints
    -- This might use core.file.read() or similar API
    
    LxNavigator.logger.info("Waypoint loading not yet implemented")
    return false -- Placeholder
end

-- Export waypoints in human-readable format
-- @return string: Formatted waypoint data
function WaypointManager.export_waypoints()
    local export_data = {}
    table.insert(export_data, "LxPS_Navigator Waypoint Export")
    table.insert(export_data, "Generated: " .. os.date())
    table.insert(export_data, "")
    
    local count = 0
    for _, waypoint in pairs(waypoints) do
        count = count + 1
        table.insert(export_data, "Waypoint " .. count .. ":")
        table.insert(export_data, "  ID: " .. waypoint.id)
        table.insert(export_data, "  Name: " .. waypoint.name)
        table.insert(export_data, "  Position: (" .. 
                     string.format("%.2f", waypoint.position.x) .. ", " .. 
                     string.format("%.2f", waypoint.position.y) .. ", " .. 
                     string.format("%.2f", waypoint.position.z) .. ")")
        if waypoint.metadata.notes then
            table.insert(export_data, "  Notes: " .. waypoint.metadata.notes)
        end
        table.insert(export_data, "")
    end
    
    table.insert(export_data, "Total waypoints: " .. count)
    return table.concat(export_data, "\n")
end

-- Clear all waypoints
function WaypointManager.clear_all_waypoints()
    local count = 0
    for _ in pairs(waypoints) do
        count = count + 1
    end
    
    waypoints = {}
    waypoint_routes = {}
    
    LxNavigator.logger.info("Cleared " .. count .. " waypoints and all routes")
end

-- Get waypoint statistics
-- @return table: Statistics about waypoints
function WaypointManager.get_statistics()
    local waypoint_count = 0
    local route_count = 0
    
    for _ in pairs(waypoints) do
        waypoint_count = waypoint_count + 1
    end
    
    for _ in pairs(waypoint_routes) do
        route_count = route_count + 1
    end
    
    return {
        waypoint_count = waypoint_count,
        route_count = route_count
    }
end

LxNavigator.logger.info("WaypointManager module loaded")

return WaypointManager