LxCore = {}

LxCore.Log = require("module/Log")
LxCore.LogManager = require("module/LogManager")
LxCore.FileReader = require("module/FileReader")
LxCore.Parser = require("module/Parser")
LxCore.MeshManager = require("module/MeshManager")

-- Include the Pathfinder module.  This exposes pathfinding helpers
-- under ``LxCore.Pathfinder`` without altering existing menu
-- functionality.  Users may call ``LxCore.Pathfinder.find_path`` to
-- compute A* paths on parsed navmesh tiles.
LxCore.Pathfinder = require("module/Pathfinder")

_G.LxCore = LxCore

-- Initialize comprehensive logging system
local core_logger = LxCore.LogManager("LxCore", {
    log_to_core = true,
    log_to_navigator = false,
    debug_level = "INFO"
})

-- Log core system initialization
core_logger.log_initialization("LxPS_Core", "1.0", "Core library with enhanced logging system")
core_logger.info("Loading core modules: Log, LogManager, FileReader, Parser, MeshManager, Pathfinder")

-- Initialize MeshManager with performance tracking
local mesh_init_operation = core_logger.start_operation("MeshManager_Initialize")
LxCore.MeshManager.initialize()
core_logger.end_operation(mesh_init_operation, "MeshManager initialized successfully")

-- Log system readiness
core_logger.info("LxPS_Core initialization completed - all modules loaded")
core_logger.log_performance_summary()



local menu_elements =
{
    main_tree = core.menu.tree_node(),
    safe_target_pos_button = core.menu.button("safe_target_pos"),
    tile_scan_button = core.menu.button("tile_scan"),
    save_target_button = core.menu.button("save_target"),
    calculate_path_button = core.menu.button("calculate_path"),
}
local function button_clicked()
    local operation_id = core_logger.start_operation("Debug_Button_Click")
    
    local player = core.object_manager.get_local_player()
    if not player then
        core_logger.warning("No player found for debug operation")
        core_logger.end_operation(operation_id, "Failed - no player")
        return
    end
    
    local pos = player:get_position()
    core_logger.debug("Player Position Debug Started")
    core.log("=== DEBUG: Player Position ===")
    core.log("Player at: (" .. string.format("%.2f", pos.x) .. ", " .. string.format("%.2f", pos.y) .. ", " .. string.format("%.2f", pos.z) .. ")")
    
    -- Debug tile calculation
    local current_mmap = LxCore.MeshManager.get_current_mmap()
    if current_mmap then
        core.log("MMAP Origin: (" .. string.format("%.2f", current_mmap.orig_x) .. ", " .. string.format("%.2f", current_mmap.orig_y) .. ", " .. string.format("%.2f", current_mmap.orig_z) .. ")")
        core.log("MMAP tile size: " .. string.format("%.2f", current_mmap.tile_width) .. " x " .. string.format("%.2f", current_mmap.tile_height))
        
        -- Show the TrinityCore tile calculation step by step
        local GRID_SIZE = 533.3333
        local tile_x_calc = 32 - math.ceil(pos.x / GRID_SIZE)
        local tile_y_calc = 32 - math.ceil(pos.y / GRID_SIZE)
        core.log("TrinityCore Tile calc: X = 32 - ceil(" .. string.format("%.2f", pos.x) .. " / " .. GRID_SIZE .. ") = " .. tile_x_calc)
        core.log("TrinityCore Tile calc: Y = 32 - ceil(" .. string.format("%.2f", pos.y) .. " / " .. GRID_SIZE .. ") = " .. tile_y_calc)
    end
    
    -- Get tile coordinates
    local tile_x, tile_y = LxCore.MeshManager.get_tile_for_position(pos.x, pos.y)
    if tile_x and tile_y then
        core.log("Current Tile: [" .. tile_x .. ", " .. tile_y .. "]")
        
        -- Check what filename this translates to
        local continent_id = LxCore.MeshManager.get_current_continent_id()
        if continent_id then
            local calculated_filename = LxCore.MeshManager.get_mmtile_filename(continent_id, tile_x, tile_y)
            core.log("Calculated filename: " .. calculated_filename)
            
            -- Check if player is in the bounds of our calculated tile
            core.log("=== BOUNDS CHECK ===")
            local tile_data = LxCore.FileReader.read("mmaps/" .. calculated_filename)
            if tile_data then
                local parsed_tile = LxCore.Parser.parse_mmtile(tile_data)
                if parsed_tile then
                    local bounds = parsed_tile.header
                    -- Test both coordinate mapping possibilities
                    -- CONFIRMED: Game Z -> Mesh Y
                    -- Option 1: Player(X,Y,Z) -> Mesh(X,Z,Y)
                    local inside_x1 = pos.x >= bounds.bmin_x and pos.x <= bounds.bmax_x  -- player X -> mesh X
                    local inside_y1 = pos.y >= bounds.bmin_z and pos.y <= bounds.bmax_z  -- player Y -> mesh Z  
                    local inside_z1 = pos.z >= bounds.bmin_y and pos.z <= bounds.bmax_y  -- player Z -> mesh Y
                    
                    -- Option 2: Player(X,Y,Z) -> Mesh(Y,Z,X)
                    local inside_x2 = pos.x >= bounds.bmin_y and pos.x <= bounds.bmax_y  -- player X -> mesh Y
                    local inside_y2 = pos.y >= bounds.bmin_z and pos.y <= bounds.bmax_z  -- player Y -> mesh Z
                    local inside_z2 = pos.z >= bounds.bmin_x and pos.z <= bounds.bmax_x  -- player Z -> mesh X
                    
                    local inside_x = inside_x1
                    local inside_y = inside_y1  
                    local inside_z = inside_z1
                    core.log("Player pos: (" .. string.format("%.2f", pos.x) .. ", " .. string.format("%.2f", pos.y) .. ", " .. string.format("%.2f", pos.z) .. ")")
                    core.log("Mesh bounds: (" .. string.format("%.2f", bounds.bmin_x) .. ", " .. string.format("%.2f", bounds.bmin_y) .. ", " .. string.format("%.2f", bounds.bmin_z) .. ") to (" .. string.format("%.2f", bounds.bmax_x) .. ", " .. string.format("%.2f", bounds.bmax_y) .. ", " .. string.format("%.2f", bounds.bmax_z) .. ")")
                    core.log("Option 1 (X->X,Y->Z,Z->Y): X=" .. tostring(inside_x1) .. ", Y=" .. tostring(inside_y1) .. ", Z=" .. tostring(inside_z1))
                    core.log("Option 2 (X->Y,Y->Z,Z->X): X=" .. tostring(inside_x2) .. ", Y=" .. tostring(inside_y2) .. ", Z=" .. tostring(inside_z2))
                    core.log("Using Option 1: X=" .. tostring(inside_x) .. ", Y=" .. tostring(inside_y) .. ", Z=" .. tostring(inside_z))
                    
                    if not inside_x or not inside_y or not inside_z then
                        core.log("Player OUTSIDE calculated tile bounds - scanning all tiles...")
                        
                        -- Scan first 10 tiles for continent 1 to find which contains player
                        local found_tile = false
                        local test_files = {
                            "00010927.mmtile", "00010928.mmtile", "00010930.mmtile", "00010931.mmtile", "00011027.mmtile",
                            "00013039.mmtile", "00001939.mmtile", "00002039.mmtile", "00002530.mmtile", "00003039.mmtile"
                        }
                        
                        for _, filename in ipairs(test_files) do
                            local test_data = LxCore.FileReader.read("mmaps/" .. filename)
                            if test_data then
                                local test_tile = LxCore.Parser.parse_mmtile(test_data)
                                if test_tile then
                                    local test_bounds = test_tile.header
                                    local test_inside_x = pos.x >= test_bounds.bmin_x and pos.x <= test_bounds.bmax_x  -- player X -> mesh X
                                    local test_inside_y = pos.y >= test_bounds.bmin_z and pos.y <= test_bounds.bmax_z  -- player Y -> mesh Z
                                    local test_inside_z = pos.z >= test_bounds.bmin_y and pos.z <= test_bounds.bmax_y  -- player Z -> mesh Y
                                    
                                    if test_inside_x and test_inside_y and test_inside_z then
                                        core.log("FOUND! Player is in tile: " .. filename)
                                        core.log("  Tile header coords: X=" .. test_tile.header.x .. ", Y=" .. test_tile.header.y)
                                        core.log("  Bounds: (" .. string.format("%.2f", test_bounds.bmin_x) .. ", " .. string.format("%.2f", test_bounds.bmin_y) .. ", " .. string.format("%.2f", test_bounds.bmin_z) .. ") to (" .. string.format("%.2f", test_bounds.bmax_x) .. ", " .. string.format("%.2f", test_bounds.bmax_y) .. ", " .. string.format("%.2f", test_bounds.bmax_z) .. ")")
                                        found_tile = true
                                        break
                                    end
                                end
                            end
                        end
                        
                        if not found_tile then
                            core.log("Player not found in any tested tiles")
                        end
                    else
                        core.log("Player IS inside calculated tile bounds!")
                    end
                end
            else
                core.log("ERROR: Calculated tile file does not exist: " .. calculated_filename)
            end
        end
        
        -- Show single tile info only
        core.log("Single tile mode - checking only current tile vertices")
        
        -- Load current tile to get bounds
        local continent_id = LxCore.MeshManager.get_current_continent_id()
        if continent_id then
            local filename = LxCore.MeshManager.get_mmtile_filename(continent_id, tile_x, tile_y)
            local tile_data = LxCore.FileReader.read("mmaps/" .. filename)
            if tile_data then
                local parsed_tile = LxCore.Parser.parse_mmtile(tile_data)
                if parsed_tile then
                    core.log("Current tile vertices: " .. #parsed_tile.vertices)
                    core.log("Current tile polygons: " .. #parsed_tile.polygons)
                    core.log("Mesh bounds: (" .. string.format("%.2f", parsed_tile.header.bmin_x) .. 
                            ", " .. string.format("%.2f", parsed_tile.header.bmin_y) .. 
                            ", " .. string.format("%.2f", parsed_tile.header.bmin_z) .. ") to (" ..
                            string.format("%.2f", parsed_tile.header.bmax_x) .. 
                            ", " .. string.format("%.2f", parsed_tile.header.bmax_y) .. 
                            ", " .. string.format("%.2f", parsed_tile.header.bmax_z) .. ")")
                end
            end
        end
        
        local polygon_info = LxCore.MeshManager.get_current_player_polygon()
        
        if polygon_info then
            local poly = polygon_info.polygon
            
            core.log("=== CURRENT POLYGON DEBUG ===")
            core.log("Polygon Index: " .. polygon_info.index)
            core.log("Polygon Vertex Count: " .. poly.vertCount)
            core.log("Polygon Flags: " .. poly.flags)
            core.log("Polygon Area/Type: " .. poly.areaAndtype)
            core.log("Found in tile: " .. (polygon_info.tile_filename or "unknown"))
            
            -- Show vertex indices
            local vert_indices = {}
            for i = 1, math.min(poly.vertCount, 6) do -- Only show first 6
                vert_indices[i] = tostring(poly.verts[i] or "nil")
            end
            core.log("Vertex Indices: " .. table.concat(vert_indices, ", "))
            
            core.log("=== END POLYGON DEBUG ===")
        else
            core.log("No polygon found at current position")
        end
    else
        core.log("Failed to get tile coordinates")
    end
    
    core_logger.end_operation(operation_id, "Debug operation completed")
    
    -- Continue tile scan coroutine if it exists
    if _G.tile_scan_coroutine and coroutine.status(_G.tile_scan_coroutine) ~= "dead" then
        core.log("Continuing tile scan...")
        coroutine.resume(_G.tile_scan_coroutine)
        if coroutine.status(_G.tile_scan_coroutine) == "dead" then
            core.log("Tile scan coroutine finished")
            _G.tile_scan_coroutine = nil
        end
    end
end

local function start_tile_scan()
    local operation_id = core_logger.start_operation("Tile_Scan_Full")
    
    local player = core.object_manager.get_local_player()
    if not player then
        core_logger.warning("No player found for tile scan")
        core_logger.end_operation(operation_id, "Failed - no player")
        return
    end
    
    local pos = player:get_position()
    local continent_id = LxCore.MeshManager.get_current_continent_id()
    if not continent_id then
        core_logger.warning("No continent ID available for tile scan")
        core_logger.end_operation(operation_id, "Failed - no continent ID")
        return
    end
    
    core_logger.info("Starting comprehensive tile scan for continent " .. continent_id)
    
    -- Create coroutine to scan all tiles with enhanced logging
    local tile_scan_co = coroutine.create(function()
        local scan_logger = LxCore.LogManager("TileScan", {
            log_to_core = false,
            log_to_navigator = false,
            debug_level = "DEBUG"
        })
        
        scan_logger.write_to_file("=== COMPLETE TILE SCAN START ===")
        scan_logger.write_to_file("Continent: " .. continent_id)
        scan_logger.write_to_file("Player pos: (" .. string.format("%.2f", pos.x) .. ", " .. string.format("%.2f", pos.y) .. ", " .. string.format("%.2f", pos.z) .. ")")
        scan_logger.write_to_file("")
        
        local tiles_checked = 0
        local tiles_found = 0
        local scan_start_time = core.time()
        
        for tile_x = 0, 63 do
            for tile_y = 0, 63 do
                local tile_operation = scan_logger.start_operation("Load_Tile_" .. tile_x .. "_" .. tile_y)
                local filename = LxCore.MeshManager.get_mmtile_filename(continent_id, tile_x, tile_y)
                
                -- Debug: Log current tile being checked
                if tiles_checked == 0 then
                    core.log("Starting with tile [" .. tile_x .. "," .. tile_y .. "] " .. filename)
                end
                
                local tile_data = LxCore.FileReader.read("mmaps/" .. filename)
                
                if tile_data then
                    local parsed_tile = LxCore.Parser.parse_mmtile(tile_data)
                    if parsed_tile then
                        local bounds = parsed_tile.header
                        local inside_x = pos.x >= bounds.bmin_x and pos.x <= bounds.bmax_x
                        local inside_y = pos.y >= bounds.bmin_z and pos.y <= bounds.bmax_z
                        local inside_z = pos.z >= bounds.bmin_y and pos.z <= bounds.bmax_y
                        
                        scan_logger.log_tile_operation("SCAN", tile_x, tile_y, filename, 
                            string.format("V:%d P:%d Inside:X=%s,Y=%s,Z=%s", 
                                #parsed_tile.vertices, #parsed_tile.polygons,
                                tostring(inside_x), tostring(inside_y), tostring(inside_z)))
                        
                        if inside_x and inside_y and inside_z then
                            scan_logger.write_to_file("  *** PLAYER IS IN THIS TILE ***")
                            core.log("FOUND PLAYER TILE: [" .. tile_x .. "," .. tile_y .. "] " .. filename)
                        end
                        
                        tiles_found = tiles_found + 1
                        tiles_checked = tiles_checked + 1
                        
                        -- Debug: Log progress to console every 50 tiles
                        if tiles_checked % 50 == 0 then
                            local elapsed = (core.time() - scan_start_time) / 1000
                            core.log(string.format("Tile scan progress: %d tiles checked, %d found (%.1fs elapsed)", 
                                tiles_checked, tiles_found, elapsed))
                        end
                        
                        scan_logger.end_operation(tile_operation, "Tile loaded and parsed successfully")
                    else
                        scan_logger.end_operation(tile_operation, "Failed to parse tile data")
                    end
                else
                    -- File doesn't exist, just skip silently
                    scan_logger.end_operation(tile_operation, "Tile file not found")
                end
                
                -- Yield every 10 tiles to prevent freezing
                if (tile_x * 64 + tile_y) % 10 == 0 then
                    coroutine.yield()
                end
            end
        end
        
        local total_elapsed = (core.time() - scan_start_time) / 1000
        scan_logger.write_to_file("=== COMPLETE TILE SCAN END ===")
        scan_logger.write_to_file(string.format("Total tiles checked: %d, found: %d", tiles_checked, tiles_found))
        scan_logger.write_to_file(string.format("Total scan time: %.2fs", total_elapsed))
        scan_logger.log_performance_summary()
        
        core.log(string.format("Tile scan completed - checked %d tiles, found %d (%.1fs) - check TileScan.log", 
            tiles_checked, tiles_found, total_elapsed))
    end)
    
    -- Start the coroutine (will run one iteration)
    coroutine.resume(tile_scan_co)
    
    -- Store coroutine globally so it can continue
    _G.tile_scan_coroutine = tile_scan_co
    core_logger.end_operation(operation_id, "Tile scan coroutine created and started")
end

-- Global storage for target position
_G.target_position = nil

local function save_target_position()
    local operation_id = core_logger.start_operation("Save_Target_Position")
    
    local player = core.object_manager.get_local_player()
    if not player then
        core_logger.warning("No player found for target position save")
        core_logger.end_operation(operation_id, "Failed - no player")
        return
    end
    
    local pos = player:get_position()
    _G.target_position = {x = pos.x, y = pos.y, z = pos.z}
    
    core.log("=== TARGET POSITION SAVED ===")
    core.log("Target position: (" .. string.format("%.2f", pos.x) .. ", " .. string.format("%.2f", pos.y) .. ", " .. string.format("%.2f", pos.z) .. ")")
    
    -- Verify the target position is on a valid navigation polygon
    local polygon_info = LxCore.MeshManager.get_current_player_polygon()
    if polygon_info then
        core.log("Target is on valid navigation mesh:")
        core.log("  Polygon Index: " .. polygon_info.index)
        core.log("  Vertex Count: " .. polygon_info.polygon.vertCount)
        core.log("  Tile: [" .. polygon_info.tile_x .. ", " .. polygon_info.tile_y .. "]")
        core_logger.end_operation(operation_id, "Target saved on valid navigation mesh")
    else
        core.log("WARNING: Target position is not on navigation mesh!")
        core_logger.end_operation(operation_id, "Target saved but not on navigation mesh")
    end
end

local function calculate_path()
    local operation_id = core_logger.start_operation("Calculate_Path")
    
    local player = core.object_manager.get_local_player()
    if not player then
        core_logger.error("No player found for pathfinding")
        core_logger.end_operation(operation_id, "Failed - no player")
        return
    end
    
    if not _G.target_position then
        core_logger.error("No target position saved! Use 'Save Target' button first")
        core_logger.end_operation(operation_id, "Failed - no target position")
        return
    end
    
    local start_pos = player:get_position()
    local end_pos = _G.target_position
    
    core.log("=== PATHFINDING REQUEST ===")
    core.log("Start: (" .. string.format("%.2f", start_pos.x) .. ", " .. string.format("%.2f", start_pos.y) .. ", " .. string.format("%.2f", start_pos.z) .. ")")
    core.log("End: (" .. string.format("%.2f", end_pos.x) .. ", " .. string.format("%.2f", end_pos.y) .. ", " .. string.format("%.2f", end_pos.z) .. ")")
    
    -- Log pathfinding operation
    core_logger.log_pathfinding_operation("A_STAR_REQUEST", start_pos, end_pos, "STARTING")
    
    -- Use the Pathfinder module to calculate path
    local pathfind_operation = core_logger.start_operation("A_Star_Pathfinding")
    local path = LxCore.Pathfinder.find_path(start_pos, end_pos)
    
    if path and #path > 0 then
        local pathfind_result = core_logger.end_operation(pathfind_operation, 
            string.format("Path found with %d waypoints", #path))
        
        core.log("=== PATH FOUND ===")
        core.log("Path length: " .. #path .. " waypoints")
        
        -- Log first few waypoints
        for i = 1, math.min(5, #path) do
            local wp = path[i]
            core.log("  Waypoint " .. i .. ": (" .. string.format("%.2f", wp.x) .. ", " .. string.format("%.2f", wp.y) .. ", " .. string.format("%.2f", wp.z) .. ")")
        end
        
        if #path > 5 then
            core.log("  ... and " .. (#path - 5) .. " more waypoints")
        end
        
        -- Calculate total distance
        local total_distance = 0
        for i = 2, #path do
            local prev = path[i-1]
            local curr = path[i]
            local dx = curr.x - prev.x
            local dy = curr.y - prev.y
            local dz = curr.z - prev.z
            total_distance = total_distance + math.sqrt(dx*dx + dy*dy + dz*dz)
        end
        core.log("Total path distance: " .. string.format("%.2f", total_distance) .. " yards")
        
        -- Store the path globally for visualization
        _G.current_path = path
        
        core_logger.log_pathfinding_operation("A_STAR_COMPLETE", start_pos, end_pos, 
            string.format("SUCCESS: %d waypoints, %.2f yards, %s", 
                #path, total_distance, pathfind_result.execution_time))
        core_logger.end_operation(operation_id, 
            string.format("Path calculated successfully (%s)", pathfind_result.execution_time))
        
    else
        core_logger.end_operation(pathfind_operation, "No path found")
        core.log("ERROR: No path found between start and end positions!")
        core_logger.log_pathfinding_operation("A_STAR_FAILED", start_pos, end_pos, "NO_PATH_FOUND")
        core_logger.end_operation(operation_id, "Failed - no path found")
    end
end

-- and now render them:
local function my_menu_render()

    -- this is the node that will appear in the main memu, under the name "Placeholder Script Menu"
    menu_elements.main_tree:render("Debug", function()
        -- this is the checkbohx that will appear upon opening the previous tree node
        menu_elements.safe_target_pos_button:render("Safe Pos")
        if menu_elements.safe_target_pos_button:is_clicked() then
            button_clicked()
        end
        
        menu_elements.tile_scan_button:render("Tile Scan")
        if menu_elements.tile_scan_button:is_clicked() then
            start_tile_scan()
        end
        
        menu_elements.save_target_button:render("Save Target")
        if menu_elements.save_target_button:is_clicked() then
            save_target_position()
        end
        
        menu_elements.calculate_path_button:render("Calculate Path")
        if menu_elements.calculate_path_button:is_clicked() then
            calculate_path()
        end
    end)
end



core.register_on_render_menu_callback(my_menu_render)

-- Path visualization
local function render_path()
    if _G.current_path and #_G.current_path > 1 then
        -- Draw path lines
        for i = 1, #_G.current_path - 1 do
            local p1 = _G.current_path[i]
            local p2 = _G.current_path[i + 1]
            
            -- Create position objects with proper coordinate mapping
            -- Game uses (X, Y, Z) where Y is up
            -- Mesh uses (X, Z, Y) where Y is up, Z is forward
            local pos1 = {x = p1.x, y = p1.y, z = p1.z}
            local pos2 = {x = p2.x, y = p2.y, z = p2.z}
            
            -- Draw line between waypoints
            core.graphics.line_3d(pos1, pos2, 0xFF00FF00, 2.0)  -- Green line, 2.0 width
        end
    end
end

core.register_on_render_callback(render_path)