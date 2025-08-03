-- MovementController Module
-- Character movement coordination and execution using Project Sylvanas API

local MovementController = {}

-- Movement state tracking
local movement_state = {
    is_moving = false,
    current_path = nil,
    current_waypoint_index = 1,
    target_position = nil,
    movement_threshold = 2.0,  -- Distance threshold to consider waypoint reached
    stuck_detection = {
        enabled = true,
        last_position = nil,
        stuck_time_threshold = 5.0,  -- Seconds before considering stuck
        stuck_distance_threshold = 1.0,  -- Distance moved required to not be stuck
        last_movement_time = 0
    }
}

-- Start following a path
-- @param path table: Array of waypoint positions {x, y, z}
-- @return boolean: True if movement started successfully
function MovementController.follow_path(path)
    if not path or #path == 0 then
        LxNavigator.log.error("MovementController", "Cannot follow empty path")
        return false
    end
    
    LxNavigator.logger.info("Starting path following with " .. #path .. " waypoints")
    
    movement_state.current_path = path
    movement_state.current_waypoint_index = 1
    movement_state.is_moving = true
    movement_state.target_position = path[1]
    
    -- Initialize stuck detection
    local player = core.object_manager.get_local_player()
    if player then
        movement_state.stuck_detection.last_position = player:get_position()
        movement_state.stuck_detection.last_movement_time = core.time()
    end
    
    LxNavigator.logger.info("Movement started - target: (" .. 
              string.format("%.2f", path[1].x) .. ", " .. 
              string.format("%.2f", path[1].y) .. ", " .. 
              string.format("%.2f", path[1].z) .. ")")
    
    return true
end

-- Stop movement
function MovementController.stop_movement()
    if movement_state.is_moving then
        LxNavigator.logger.info("Stopping movement")
        movement_state.is_moving = false
        movement_state.current_path = nil
        movement_state.current_waypoint_index = 1
        movement_state.target_position = nil
        
        -- TODO: Send stop movement command to character using Project Sylvanas API
        -- This might use core.movement.stop() or core.player.stop_movement()
    end
end

-- Check if currently moving
-- @return boolean: True if movement is active
function MovementController.is_moving()
    return movement_state.is_moving
end

-- Get current movement progress
-- @return table: Movement progress info or nil if not moving
function MovementController.get_movement_progress()
    if not movement_state.is_moving or not movement_state.current_path then
        return nil
    end
    
    local total_waypoints = #movement_state.current_path
    local current_waypoint = movement_state.current_waypoint_index
    local progress_percent = (current_waypoint - 1) / total_waypoints * 100
    
    return {
        total_waypoints = total_waypoints,
        current_waypoint = current_waypoint,
        progress_percent = progress_percent,
        target_position = movement_state.target_position
    }
end

-- Update movement (should be called regularly from main loop or timer)
function MovementController.update()
    if not movement_state.is_moving then
        return
    end
    
    local player = core.object_manager.get_local_player()
    if not player then
        LxNavigator.log.error("MovementController", "No player found during movement update")
        MovementController.stop_movement()
        return
    end
    
    local current_pos = player:get_position()
    
    -- Check if we've reached current target waypoint
    if movement_state.target_position then
        local dx = current_pos.x - movement_state.target_position.x
        local dy = current_pos.y - movement_state.target_position.y
        local dz = current_pos.z - movement_state.target_position.z
        local distance = math.sqrt(dx*dx + dy*dy + dz*dz)
        
        if distance <= movement_state.movement_threshold then
            LxNavigator.logger.info("Reached waypoint " .. movement_state.current_waypoint_index .. " (distance: " .. string.format("%.2f", distance) .. ")")
            
            -- Move to next waypoint
            movement_state.current_waypoint_index = movement_state.current_waypoint_index + 1
            
            if movement_state.current_waypoint_index > #movement_state.current_path then
                -- Path completed
                LxNavigator.logger.info("Path completed successfully!")
                MovementController.stop_movement()
                return
            else
                -- Continue to next waypoint
                movement_state.target_position = movement_state.current_path[movement_state.current_waypoint_index]
                LxNavigator.logger.info("Moving to next waypoint: (" .. 
                          string.format("%.2f", movement_state.target_position.x) .. ", " .. 
                          string.format("%.2f", movement_state.target_position.y) .. ", " .. 
                          string.format("%.2f", movement_state.target_position.z) .. ")")
                
                -- TODO: Send movement command to next waypoint using Project Sylvanas API
                -- This might use core.movement.move_to(movement_state.target_position)
            end
        else
            -- TODO: Ensure character is moving toward target
            -- This might use core.movement.move_to(movement_state.target_position) each frame
        end
    end
    
    -- Stuck detection
    if movement_state.stuck_detection.enabled then
        MovementController._check_stuck_detection(current_pos)
    end
end

-- Internal stuck detection logic
function MovementController._check_stuck_detection(current_pos)
    local stuck_data = movement_state.stuck_detection
    local current_time = core.time()
    
    if stuck_data.last_position then
        local dx = current_pos.x - stuck_data.last_position.x
        local dy = current_pos.y - stuck_data.last_position.y
        local dz = current_pos.z - stuck_data.last_position.z
        local movement_distance = math.sqrt(dx*dx + dy*dy + dz*dz)
        
        if movement_distance > stuck_data.stuck_distance_threshold then
            -- Character has moved, reset stuck detection
            stuck_data.last_movement_time = current_time
            stuck_data.last_position = {x = current_pos.x, y = current_pos.y, z = current_pos.z}
        else
            -- Check if stuck for too long
            local time_without_movement = (current_time - stuck_data.last_movement_time) / 1000
            if time_without_movement > stuck_data.stuck_time_threshold then
                LxNavigator.log.warning("MovementController", "Character appears to be stuck! Stopping movement.")
                LxNavigator.log.warning("MovementController", "Time without significant movement: " .. string.format("%.1f", time_without_movement) .. " seconds")
                MovementController.stop_movement()
                return
            end
        end
    else
        -- Initialize stuck detection
        stuck_data.last_position = {x = current_pos.x, y = current_pos.y, z = current_pos.z}
        stuck_data.last_movement_time = current_time
    end
end

-- Move to single position
-- @param pos table: Target position {x, y, z}
-- @return boolean: True if movement started successfully
function MovementController.move_to_position(pos)
    LxNavigator.logger.info("Moving to single position: (" .. 
              string.format("%.2f", pos.x) .. ", " .. 
              string.format("%.2f", pos.y) .. ", " .. 
              string.format("%.2f", pos.z) .. ")")
    
    -- Create single-waypoint path
    local path = {pos}
    return MovementController.follow_path(path)
end

-- Configure movement settings
-- @param settings table: Movement configuration options
function MovementController.configure(settings)
    if settings.movement_threshold then
        movement_state.movement_threshold = settings.movement_threshold
        LxNavigator.logger.info("Movement threshold set to: " .. settings.movement_threshold)
    end
    
    if settings.stuck_detection then
        local stuck_config = settings.stuck_detection
        if stuck_config.enabled ~= nil then
            movement_state.stuck_detection.enabled = stuck_config.enabled
        end
        if stuck_config.time_threshold then
            movement_state.stuck_detection.stuck_time_threshold = stuck_config.time_threshold
        end
        if stuck_config.distance_threshold then
            movement_state.stuck_detection.stuck_distance_threshold = stuck_config.distance_threshold
        end
        LxNavigator.logger.info("Stuck detection configured")
    end
end

-- Get current movement state (for debugging)
-- @return table: Current movement state
function MovementController.get_state()
    return {
        is_moving = movement_state.is_moving,
        waypoint_count = movement_state.current_path and #movement_state.current_path or 0,
        current_waypoint_index = movement_state.current_waypoint_index,
        target_position = movement_state.target_position,
        movement_threshold = movement_state.movement_threshold,
        stuck_detection = movement_state.stuck_detection
    }
end

-- Force unstuck attempt
function MovementController.attempt_unstuck()
    LxNavigator.logger.info("Attempting to unstuck character")
    
    local player = core.object_manager.get_local_player()
    if not player then
        return false
    end
    
    -- TODO: Implement unstuck logic using Project Sylvanas API
    -- This might involve:
    -- 1. Stopping current movement
    -- 2. Moving backward briefly
    -- 3. Trying alternative path
    -- 4. Using game's built-in unstuck mechanics
    
    -- For now, just reset stuck detection
    local pos = player:get_position()
    movement_state.stuck_detection.last_position = {x = pos.x, y = pos.y, z = pos.z}
    movement_state.stuck_detection.last_movement_time = core.time()
    
    return true
end

-- Check if character is facing target direction
-- @param target_pos table: Target position {x, y, z}
-- @param tolerance_degrees number: Acceptable angle difference (optional, default 10)
-- @return boolean: True if facing target
function MovementController.is_facing_target(target_pos, tolerance_degrees)
    tolerance_degrees = tolerance_degrees or 10.0
    
    local player = core.object_manager.get_local_player()
    if not player then
        return false
    end
    
    local player_pos = player:get_position()
    
    -- TODO: Use Project Sylvanas API to get player facing direction
    -- This might use player:get_facing() or core.player.get_rotation()
    -- Calculate angle between player facing and target direction
    -- Compare with tolerance
    
    -- Placeholder: assume always facing target
    return true
end

-- Turn character to face target position
-- @param target_pos table: Target position {x, y, z}
function MovementController.face_target(target_pos)
    local player = core.object_manager.get_local_player()
    if not player then
        return
    end
    
LxNavigator.logger.info("Turning to face target position")
    
    -- TODO: Use Project Sylvanas API to turn character
    -- This might use core.movement.face_position(target_pos) or similar
end

LxNavigator.logger.info("MovementController module loaded")

return MovementController