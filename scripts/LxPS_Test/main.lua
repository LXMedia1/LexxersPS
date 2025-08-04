-- LxPS_Test - Navigation System Test Plugin
-- Simple menu-based testing interface for navigation functionality
-- Requires LxPS_Navigator for navigation operations

LxTest = {}

-- Simple logging
local function log_info(message)
    if LxNavigator and LxNavigator.logger then
        LxNavigator.logger.info(message)
    else
        core.log("[LxPS_Test] " .. message)
    end
end

local function log_error(message)
    if LxNavigator and LxNavigator.logger then
        LxNavigator.logger.error(message)
    else
        core.log_error("[LxPS_Test] " .. message)
    end
end

-- Test state
LxTest.state = {
    start_position = nil,
    end_position = nil,
    current_path = nil,
    test_results = {}
}

-- Menu elements using correct Project Sylvanas API
local menu_elements = {
    main_tree = core.menu.tree_node(),
    select_start_button = core.menu.button("select_start_pos"),
    select_end_button = core.menu.button("select_end_pos"),
    calculate_path_button = core.menu.button("calculate_path"),
    toggle_drawing_button = core.menu.button("toggle_drawing"),
    run_tests_button = core.menu.button("run_tests"),
    clear_data_button = core.menu.button("clear_data"),
    debug_tile_button = core.menu.button("debug_tile_data"),
    draw_current_poly_button = core.menu.button("draw_current_poly"),
    status_header = core.menu.header()
}

-- Drawing state - always enabled for debugging
local path_drawing_enabled = true  -- Always enabled to visualize navigation
local draw_current_polygon = false  -- Toggle to draw polygon at player position

-- Import required API objects
---@type vec3
local vec3 = require("common/geometry/vector_3")
---@type color
local color = require("common/color")

-- Test Functions
local function select_start_position()
    local player = core.object_manager.get_local_player()
    if player then
        LxTest.state.start_position = player:get_position()
        log_info("Start position set to player position: " .. 
                string.format("(%.2f, %.2f, %.2f)", 
                LxTest.state.start_position.x, 
                LxTest.state.start_position.y, 
                LxTest.state.start_position.z))
    else
        log_error("No player found")
    end
end

local function select_end_position()
    local player = core.object_manager.get_local_player()
    if player then
        LxTest.state.end_position = player:get_position()
        log_info("End position set to current player position: " .. 
                string.format("(%.2f, %.2f, %.2f)", 
                LxTest.state.end_position.x, 
                LxTest.state.end_position.y, 
                LxTest.state.end_position.z))
    else
        log_error("No player found")
    end
end

local function calculate_path()
    if not LxTest.state.start_position or not LxTest.state.end_position then
        log_error("Cannot calculate path: Start or end position not set")
        return
    end
    
    log_info("Starting path calculation...")
    
    if not LxNavigator or not LxNavigator.PathPlanner then
        log_error("LxNavigator not available")
        return
    end
    
    local path = LxNavigator.PathPlanner.find_path(
        LxTest.state.start_position, 
        LxTest.state.end_position
    )
    
    if path and #path > 0 then
        LxTest.state.current_path = path
        log_info("Path calculated successfully with " .. #path .. " waypoints")
        
        -- Display all waypoints
        for i, waypoint in ipairs(path) do
            log_info("Waypoint " .. i .. ": (" .. 
                    string.format("%.2f", waypoint.x) .. ", " .. 
                    string.format("%.2f", waypoint.y) .. ", " .. 
                    string.format("%.2f", waypoint.z) .. ")")
        end
    else
        log_error("Path calculation failed")
    end
end

local function run_tests()
    log_info("Running navigation system tests...")
    
    local tests_passed = 0
    local tests_total = 0
    
    -- Test 1: Navigator availability
    tests_total = tests_total + 1
    if LxNavigator then
        log_info("✓ Navigator system available")
        tests_passed = tests_passed + 1
    else
        log_error("✗ Navigator system not available")
    end
    
    -- Test 2: PathPlanner module
    tests_total = tests_total + 1
    if LxNavigator and LxNavigator.PathPlanner then
        log_info("✓ PathPlanner module available")
        tests_passed = tests_passed + 1
    else
        log_error("✗ PathPlanner module not available")
    end
    
    -- Test 3: NavMesh module
    tests_total = tests_total + 1
    if LxNavigator and LxNavigator.NavMesh then
        log_info("✓ NavMesh module available")
        tests_passed = tests_passed + 1
    else
        log_error("✗ NavMesh module not available")
    end
    
    -- Test 4: Current position validation
    tests_total = tests_total + 1
    local player = core.object_manager.get_local_player()
    if player and LxNavigator and LxNavigator.NavMesh then
        local pos = player:get_position()
        local is_valid = LxNavigator.NavMesh.is_position_valid(pos)
        if is_valid then
            log_info("✓ Current position is on navigation mesh")
            tests_passed = tests_passed + 1
        else
            log_error("✗ Current position is not on navigation mesh")
        end
    else
        log_error("✗ Cannot test position validation")
    end
    
    log_info("Tests completed: " .. tests_passed .. "/" .. tests_total .. " passed")
end

-- REMOVED: Tile format testing - Format established as IIIIYYXX

local function clear_data()
    LxTest.state.start_position = nil
    LxTest.state.end_position = nil
    LxTest.state.current_path = nil
    log_info("Test data cleared")
end

local function toggle_path_drawing()
    path_drawing_enabled = not path_drawing_enabled
    log_info("Path drawing " .. (path_drawing_enabled and "enabled" or "disabled"))
end


-- Draw mesh from vertex data to form polygon-like visualization
local function draw_vertex_mesh(vertices, polygon_color)
    if not vertices or #vertices < 3 then
        return
    end
    
    -- Validate vertices have valid coordinates
    for i, v in ipairs(vertices) do
        if not v.x or not v.y or not v.z then
            log_error("Invalid vertex at index " .. i .. " - missing coordinates")
            return
        end
    end
    
    -- Draw polygon based on vertex count
    if #vertices == 3 then
        -- Triangle - use triangle_3d_filled
        local v1 = vec3.new(vertices[1].x, vertices[1].y, vertices[1].z)
        local v2 = vec3.new(vertices[2].x, vertices[2].y, vertices[2].z)
        local v3 = vec3.new(vertices[3].x, vertices[3].y, vertices[3].z)
        
        core.graphics.triangle_3d_filled(v1, v2, v3, polygon_color)
    elseif #vertices == 4 then
        -- Rectangle - use rect_3d_filled
        core.graphics.rect_3d_filled(
            vec3.new(vertices[1].x, vertices[1].y, vertices[1].z),
            vec3.new(vertices[2].x, vertices[2].y, vertices[2].z),
            vec3.new(vertices[3].x, vertices[3].y, vertices[3].z),
            vec3.new(vertices[4].x, vertices[4].y, vertices[4].z),
            polygon_color
        )
    else
        -- More vertices - use fan triangulation
        local first = vec3.new(vertices[1].x, vertices[1].y, vertices[1].z)
        for i = 2, #vertices - 1 do
            core.graphics.triangle_3d_filled(
                first,
                vec3.new(vertices[i].x, vertices[i].y, vertices[i].z),
                vec3.new(vertices[i+1].x, vertices[i+1].y, vertices[i+1].z),
                polygon_color
            )
        end
    end
    
    -- Draw outline
    for i = 1, #vertices do
        local next_i = (i % #vertices) + 1
        core.graphics.line_3d(
            vec3.new(vertices[i].x, vertices[i].y, vertices[i].z),
            vec3.new(vertices[next_i].x, vertices[next_i].y, vertices[next_i].z),
            color.new(255, 255, 255, 255) -- White outline
        )
    end
end

-- Draw polygon at a specific position using real polygon data
local function draw_polygon_at_position(position, polygon_color)
    if not LxNavigator or not LxNavigator.NavMesh then
        return
    end
    
    -- Get the tile data for this position
    local tile_data = LxNavigator.NavMesh.load_tile(position.x, position.y)
    if not tile_data or not tile_data.vertices or #tile_data.vertices == 0 then
        return
    end
    
    -- Check if we have polygon data
    if not tile_data.polygons or #tile_data.polygons == 0 then
        log_error("No polygon data available in tile")
        return
    end
    
    log_info("Drawing ALL " .. #tile_data.polygons .. " polygons in tile at position: " .. string.format("(%.2f, %.2f, %.2f)", position.x, position.y, position.z))
    
    -- Log tile bounds information
    if tile_data.tile_bounds then
        log_info("Tile bounds: min[" .. string.format("%.2f, %.2f, %.2f", tile_data.tile_bounds.min.x, tile_data.tile_bounds.min.y, tile_data.tile_bounds.min.z) .. 
                "] max[" .. string.format("%.2f, %.2f, %.2f", tile_data.tile_bounds.max.x, tile_data.tile_bounds.max.y, tile_data.tile_bounds.max.z) .. "]")
    else
        log_info("No tile bounds data available")
    end
    
    local polygons_drawn = 0
    local polygons_skipped = 0
    
    -- Draw ALL polygons in the tile
    for poly_idx, polygon in ipairs(tile_data.polygons) do
        if polygon.vertices and polygon.vertCount >= 3 then
            -- Check if polygon is walkable (flags & 1 means walkable in Detour)
            if polygon.flags and (polygon.flags % 2) == 1 then
                local polygon_vertices = {}
                
                -- Collect polygon vertices (only up to vertCount, ignore padding)
                for i = 1, polygon.vertCount do
                    local vert_idx = polygon.vertices[i]
                    if vert_idx and vert_idx > 0 and vert_idx <= #tile_data.vertices then
                        local vertex = tile_data.vertices[vert_idx]
                        if vertex then
                            table.insert(polygon_vertices, vertex)
                        end
                    end
                end
                
                -- Draw the polygon if we have enough vertices
                if #polygon_vertices >= 3 then
                    -- Log first polygon vertices for debugging
                    if polygons_drawn == 0 then
                        log_info("First polygon vertices:")
                        for vi, v in ipairs(polygon_vertices) do
                            log_info("  V" .. vi .. ": (" .. string.format("%.2f, %.2f, %.2f", v.x, v.y, v.z) .. ")")
                        end
                    end
                    draw_vertex_mesh(polygon_vertices, polygon_color)
                    polygons_drawn = polygons_drawn + 1
                else
                    polygons_skipped = polygons_skipped + 1
                end
            else
                polygons_skipped = polygons_skipped + 1
            end
        else
            polygons_skipped = polygons_skipped + 1
        end
    end
    
    log_info("Drew " .. polygons_drawn .. " walkable polygons, skipped " .. polygons_skipped .. " non-walkable/invalid polygons")
end

-- Enhanced drawing function with polygon visualization using triangles and rectangles
local function draw_navigation_debug()
    if not path_drawing_enabled then
        return
    end
    
    -- Safely try drawing - if API doesn't exist, disable drawing
    local success, error_msg = pcall(function()
        
        -- 0. Draw current player polygon if enabled
        if draw_current_polygon then
            local player = core.object_manager.get_local_player()
            if player then
                local player_pos = player:get_position()
                if player_pos then
                    draw_polygon_at_position(player_pos, color.new(255, 255, 0, 200))  -- Yellow polygon with higher opacity
                    -- Draw player position marker
                    local player_vec = vec3.new(player_pos.x, player_pos.y, player_pos.z + 2.0)
                    core.graphics.circle_3d_filled(player_vec, 0.5, color.new(255, 255, 0, 255))  -- Bright yellow circle
                end
            end
        end
        
        -- 1. Draw start position polygon (if set)
        if LxTest.state.start_position then
            draw_polygon_at_position(LxTest.state.start_position, color.new(0, 255, 0, 150))  -- Semi-transparent green
            -- Draw start position marker
            local start_vec = vec3.new(LxTest.state.start_position.x, LxTest.state.start_position.y, LxTest.state.start_position.z + 2.0)
            core.graphics.circle_3d_filled(start_vec, 1.0, color.new(0, 255, 0, 255))  -- Bright green circle
        end
        
        -- 2. Draw end position polygon (if set)
        if LxTest.state.end_position then
            draw_polygon_at_position(LxTest.state.end_position, color.new(255, 0, 0, 150))  -- Semi-transparent red
            -- Draw end position marker
            local end_vec = vec3.new(LxTest.state.end_position.x, LxTest.state.end_position.y, LxTest.state.end_position.z + 2.0)
            core.graphics.circle_3d_filled(end_vec, 1.0, color.new(255, 0, 0, 255))  -- Bright red circle
        end
        
        -- 3. Draw path polygons and waypoints (if exists)
        if LxTest.state.current_path and #LxTest.state.current_path >= 2 then
            local path = LxTest.state.current_path
            
            -- Draw polygons for each waypoint
            for i, waypoint in ipairs(path) do
                draw_polygon_at_position(waypoint, color.new(0, 255, 0, 100))  -- Semi-transparent green for path polygons
            end
            
            -- Draw lines between waypoints
            for i = 1, #path - 1 do
                local start_point = path[i]
                local end_point = path[i + 1]
                
                -- Convert table positions to vec3 objects
                local start_vec = vec3.new(start_point.x, start_point.y, start_point.z)
                local end_vec = vec3.new(end_point.x, end_point.y, end_point.z)
                
                -- Draw line between waypoints (bright green)
                core.graphics.line_3d(
                    start_vec,
                    end_vec,
                    color.new(0, 255, 0, 255),  -- Bright green
                    3.0  -- thicker for visibility
                )
            end
            
            -- Draw waypoint markers
            for i, waypoint in ipairs(path) do
                local waypoint_color = color.new(0, 0, 255, 255)  -- Blue for regular waypoints
                if i == 1 then
                    waypoint_color = color.new(0, 255, 0, 255)  -- Green for start
                elseif i == #path then
                    waypoint_color = color.new(255, 0, 0, 255)  -- Red for end
                end
                
                -- Convert position to vec3 object
                local waypoint_vec = vec3.new(waypoint.x, waypoint.y, waypoint.z + 1.0)  -- Slightly above ground
                
                -- Draw circle at each waypoint
                core.graphics.circle_3d_filled(
                    waypoint_vec,
                    0.8,  -- Larger radius for visibility
                    waypoint_color
                )
            end
        end
        
    end)
    
    if not success then
        -- Only log error occasionally to prevent spam
        if math.random() < 0.01 then -- 1% chance to log
            log_error("Drawing error: " .. tostring(error_msg))
        end
    end
end

-- Debug tile data - load current tile and save all data to readable file
local function debug_tile_data()
    local player = core.object_manager.get_local_player()
    if not player then
        log_error("Cannot get player object")
        return
    end
    
    local player_pos = player:get_position()
    if not player_pos then
        log_error("Cannot get player position")
        return
    end
    
    log_info("Loading tile data for player position: (" .. 
             string.format("%.2f", player_pos.x) .. ", " .. 
             string.format("%.2f", player_pos.y) .. ", " .. 
             string.format("%.2f", player_pos.z) .. ")")
    
    -- Load the tile data
    local tile_data = LxNavigator.NavMesh.load_tile(player_pos.x, player_pos.y)
    if not tile_data then
        log_error("Failed to load tile data")
        return
    end
    
    -- Create detailed debug output
    local debug_output = {}
    table.insert(debug_output, "=== MMAP TILE DEBUG DATA ===")
    table.insert(debug_output, "Generated at time: " .. tostring(core.time()) .. "ms")
    table.insert(debug_output, "Player Position: (" .. string.format("%.2f", player_pos.x) .. ", " .. 
                                                     string.format("%.2f", player_pos.y) .. ", " .. 
                                                     string.format("%.2f", player_pos.z) .. ")")
    table.insert(debug_output, "")
    
    -- Tile info
    table.insert(debug_output, "=== TILE INFO ===")
    table.insert(debug_output, "Loaded: " .. tostring(tile_data.loaded))
    table.insert(debug_output, "Filename: " .. (tile_data.filename or "unknown"))
    table.insert(debug_output, "File Size: " .. (tile_data.file_size or 0) .. " bytes")
    table.insert(debug_output, "Magic: " .. (tile_data.magic and string.format("0x%08X", tile_data.magic) or "none"))
    table.insert(debug_output, "Version: " .. (tile_data.version or "unknown"))
    table.insert(debug_output, "Vertex Count: " .. (tile_data.vertex_count or 0))
    table.insert(debug_output, "Polygon Count: " .. (tile_data.polygon_count or 0))
    table.insert(debug_output, "")
    
    -- Bounds info
    if tile_data.bounds then
        table.insert(debug_output, "=== TILE BOUNDS ===")
        table.insert(debug_output, "X: [" .. string.format("%.2f", tile_data.bounds.min_x) .. " to " .. string.format("%.2f", tile_data.bounds.max_x) .. "]")
        table.insert(debug_output, "Y: [" .. string.format("%.2f", tile_data.bounds.min_y) .. " to " .. string.format("%.2f", tile_data.bounds.max_y) .. "]")
        table.insert(debug_output, "Z: [" .. string.format("%.2f", tile_data.bounds.min_z) .. " to " .. string.format("%.2f", tile_data.bounds.max_z) .. "]")
        table.insert(debug_output, "")
    end
    
    -- Vertex data
    if tile_data.vertices and #tile_data.vertices > 0 then
        table.insert(debug_output, "=== VERTICES (first 20) ===")
        for i = 1, math.min(20, #tile_data.vertices) do
            local v = tile_data.vertices[i]
            local detail_marker = v.detail and " [DETAIL]" or " [BASE]"
            table.insert(debug_output, "Vertex " .. i .. ": (" .. 
                        string.format("%.2f", v.x) .. ", " .. 
                        string.format("%.2f", v.y) .. ", " .. 
                        string.format("%.2f", v.z) .. ")" .. detail_marker)
        end
        if #tile_data.vertices > 20 then
            table.insert(debug_output, "... (" .. (#tile_data.vertices - 20) .. " more vertices)")
        end
        table.insert(debug_output, "")
    end
    
    -- Polygon data
    table.insert(debug_output, "=== POLYGONS ===")
    if tile_data.polygons and #tile_data.polygons > 0 then
        table.insert(debug_output, "Found " .. #tile_data.polygons .. " polygons:")
        for i = 1, math.min(10, #tile_data.polygons) do
            local poly = tile_data.polygons[i]
            table.insert(debug_output, "Polygon " .. i .. ":")
            table.insert(debug_output, "  Vertices: [" .. table.concat(poly.vertices or {}, ", ") .. "]")
            table.insert(debug_output, "  VertCount: " .. (poly.vertCount or 0))
            table.insert(debug_output, "  Flags: " .. (poly.flags or 0))
            table.insert(debug_output, "  FirstLink: " .. (poly.firstLink or 0))
        end
    else
        table.insert(debug_output, "NO POLYGONS LOADED!")
    end
    table.insert(debug_output, "")
    
    -- Links data
    table.insert(debug_output, "=== LINKS ===")
    if tile_data.links and #tile_data.links > 0 then
        table.insert(debug_output, "Found " .. #tile_data.links .. " active links:")
        for i = 1, math.min(5, #tile_data.links) do
            local link = tile_data.links[i]
            table.insert(debug_output, "Link " .. i .. ": ref=" .. (link.ref or 0) .. ", edge=" .. (link.edge or 0))
        end
    else
        table.insert(debug_output, "No active links found")
    end
    table.insert(debug_output, "")
    
    -- Detail mesh data
    table.insert(debug_output, "=== DETAIL MESHES ===")
    if tile_data.detail_meshes and #tile_data.detail_meshes > 0 then
        table.insert(debug_output, "Found " .. #tile_data.detail_meshes .. " detail meshes:")
        for i = 1, math.min(5, #tile_data.detail_meshes) do
            local dm = tile_data.detail_meshes[i]
            table.insert(debug_output, "DetailMesh " .. i .. ": verts=" .. (dm.vertCount or 0) .. ", tris=" .. (dm.triCount or 0))
        end
    else
        table.insert(debug_output, "No detail meshes found")
    end
    table.insert(debug_output, "")
    
    -- Write to log file
    -- Use game_time for a better timestamp
    local timestamp = math.floor(core.game_time())
    local filename = "tile_debug_" .. tostring(timestamp) .. ".log"
    
    -- Create log file first
    core.create_log_file(filename)
    
    -- Write each line to the log file
    for _, line in ipairs(debug_output) do
        core.write_log_file(filename, line .. "\n")
    end
    
    log_info("Tile debug data saved to: scripts_log/" .. filename)
    log_info("Vertices loaded: " .. (tile_data.vertices and #tile_data.vertices or 0))
    log_info("Polygons loaded: " .. (tile_data.polygons and #tile_data.polygons or 0))
end

-- Menu rendering using correct Project Sylvanas API
local function my_menu_render()
    menu_elements.main_tree:render("LxPS Navigation Test", function()
        
        menu_elements.select_start_button:render("Set Start Position (Player)")
        if menu_elements.select_start_button:is_clicked() then
            select_start_position()
        end
        
        menu_elements.select_end_button:render("Set End Position (Player)")
        if menu_elements.select_end_button:is_clicked() then
            select_end_position()
        end
        
        menu_elements.calculate_path_button:render("Calculate Path")
        if menu_elements.calculate_path_button:is_clicked() then
            calculate_path()
        end
        
        menu_elements.toggle_drawing_button:render(path_drawing_enabled and "Disable Path Drawing" or "Enable Path Drawing")
        if menu_elements.toggle_drawing_button:is_clicked() then
            toggle_path_drawing()
        end
        
        menu_elements.run_tests_button:render("Run System Tests")
        if menu_elements.run_tests_button:is_clicked() then
            run_tests()
        end
        
        menu_elements.clear_data_button:render("Clear Test Data")
        if menu_elements.clear_data_button:is_clicked() then
            clear_data()
        end
        
        menu_elements.debug_tile_button:render("Debug Tile Data")
        if menu_elements.debug_tile_button:is_clicked() then
            debug_tile_data()
        end
        
        menu_elements.draw_current_poly_button:render("Draw Current Polygon: " .. (draw_current_polygon and "ON" or "OFF"))
        if menu_elements.draw_current_poly_button:is_clicked() then
            draw_current_polygon = not draw_current_polygon
            log_info("Draw current polygon: " .. (draw_current_polygon and "enabled" or "disabled"))
        end
        
        -- Show basic status using header
        local status_text = "Status: "
        if LxTest.state.start_position and LxTest.state.end_position then
            if LxTest.state.current_path then
                status_text = status_text .. "Path calculated (" .. #LxTest.state.current_path .. " points)"
            else
                status_text = status_text .. "Positions set, ready to calculate"
            end
        elseif LxTest.state.start_position then
            status_text = status_text .. "Start set, need end position"
        else
            status_text = status_text .. "Set start and end positions"
        end
        
        -- Display status text (removed header due to API issues)
        
    end)
end

-- Initialize test system
function LxTest.initialize()
    log_info("LxPS_Test plugin initialized")
    log_info("Simple menu-based navigation testing interface ready")
    
    -- Check Navigator availability
    if LxNavigator then
        log_info("LxNavigator system detected")
    else
        log_error("LxNavigator system not available - some tests will fail")
    end
end

-- Expose globally
_G.LxTest = LxTest

-- Initialize on load
LxTest.initialize()

-- Register the menu render function
core.register_on_render_menu_callback(my_menu_render)

-- Register the enhanced drawing render function for 3D rendering
core.register_on_render_callback(draw_navigation_debug)