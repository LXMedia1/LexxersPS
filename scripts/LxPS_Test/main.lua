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
    generate_mesh_button = core.menu.button("generate_mesh"),
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


-- Generate navigation mesh triangles (adapted from LxPS_NewProject optimized implementation)
local function generate_mesh_triangles()
    local player = core.object_manager.get_local_player()
    if not player then return end
    
    local pos = player:get_position()
    if not pos then return end
    
    -- Get tile data for current position
    local tile_data = LxNavigator and LxNavigator.NavMesh and LxNavigator.NavMesh.load_tile(pos.x, pos.y)
    if not tile_data or not tile_data.loaded then
        log_info("No tile data available for mesh generation")
        return
    end
    
    local current_time = core.time()
    local tile_key = (tile_data.filename or "unknown") .. "_" .. tostring(math.floor(current_time / mesh_cache.update_interval))
    
    -- Check if we need to update cache
    if mesh_cache.last_tile_key == tile_key and mesh_cache.tris then
        return -- Use existing cache
    end
    
    log_info("Generating mesh triangles for tile: " .. (tile_data.filename or "unknown"))
    
    -- Load raw tile data for detailed triangle parsing
    local raw_data = tile_data.raw_data
    if not raw_data or #raw_data == 0 then
        log_error("No raw tile data available")
        return
    end
    
    -- Use optimized binary parsing from LxPS_NewProject
    local triangles = parse_navigation_triangles(raw_data, tile_data)
    if triangles and #triangles > 0 then
        mesh_cache.tris = triangles
        mesh_cache.last_tile_key = tile_key
        mesh_cache.last_update = current_time
        
        -- Expose triangles for rendering
        _G.LxPS_TestMesh = { tris = mesh_cache.tris }
        
        log_info("Generated " .. #triangles .. " navigation triangles")
    else
        log_error("Failed to generate navigation triangles")
    end
end

-- Optimized triangle parsing from raw MMAP data (adapted from LxPS_NewProject)
local function parse_navigation_triangles(data, tile_data)
    if not data or #data < 120 then return {} end
    
    local Vec3 = require("common/geometry/vector_3")
    local triangles = {}
    
    -- Binary reading functions
    local function read_u32(off)
        if off + 3 > #data then return nil end
        local a, b, c, d = string.byte(data, off, off + 3)
        return a + b*256 + c*65536 + d*16777216
    end
    
    local function read_f32(off)
        if off + 3 > #data then return nil end
        local b1, b2, b3, b4 = string.byte(data, off, off + 3)
        local sign = (b4 >= 128) and -1 or 1
        local exp = ((b4 % 128) * 2) + math.floor(b3 / 128)
        local mant = ((b3 % 128) * 65536) + (b2 * 256) + b1
        if exp == 0 then return (mant == 0) and (sign * 0.0) or (sign * mant * 2^-149)
        elseif exp == 255 then return (mant == 0) and (sign * math.huge) or (0/0) end
        return sign * (1 + mant / 2^23) * 2^(exp - 127)
    end
    
    -- Parse MMAP header to get vertex/polygon counts and offsets
    local off = 1 + 20  -- Skip TrinityCore header
    local magic = read_u32(off)
    if magic ~= 0x444E4156 then return {} end  -- Not DNAV format
    
    off = off + 4  -- Skip magic
    local version = read_u32(off); off = off + 4
    local tile_x = read_u32(off); off = off + 4
    local tile_y = read_u32(off); off = off + 4
    local layer = read_u32(off); off = off + 4
    local user_id = read_u32(off); off = off + 4
    local poly_count = read_u32(off); off = off + 4
    local vert_count = read_u32(off); off = off + 4
    local max_links = read_u32(off); off = off + 4
    local detail_mesh_count = read_u32(off); off = off + 4
    local detail_vert_count = read_u32(off); off = off + 4
    local detail_tri_count = read_u32(off); off = off + 4
    
    -- Skip remaining header fields to get to vertex data
    off = 1 + 20 + 100  -- TrinityCore + DNAV header size
    
    -- Parse vertices
    local vertices = {}
    if vert_count and vert_count > 0 and off + vert_count*12 <= #data then
        for i = 1, vert_count do
            local vx = read_f32(off)
            local vy = read_f32(off + 4)
            local vz = read_f32(off + 8)
            if vx and vy and vz then
                -- Apply correct coordinate transformation: Game(X,Y,Z) = Nav(Z,X,Y)
                local wx = vz  -- Nav Z -> Game X (north-south)
                local wy = vx  -- Nav X -> Game Y (east-west)
                local wz = vy  -- Nav Y -> Game Z (height)
                vertices[i] = Vec3.new(wx, wy, wz)
            end
            off = off + 12
        end
    end
    
    if #vertices == 0 then
        log_error("No vertices parsed from navigation data")
        return {}
    end
    
    -- Parse detail triangles (this gives us the actual walkable surface triangulation)
    local detail_meshes = {}
    local poly_off = off  -- Current offset after vertices
    local dt_poly_size = 32  -- Size of dtPoly structure
    
    -- Skip to detail meshes
    local detail_meshes_off = poly_off + (poly_count or 0) * dt_poly_size
    local detail_verts_off = detail_meshes_off + (detail_mesh_count or 0) * 12
    local detail_tris_off = detail_verts_off + (detail_vert_count or 0) * 12
    
    -- Parse detail triangles for each polygon
    if detail_tri_count and detail_tri_count > 0 and detail_tris_off + detail_tri_count*4 <= #data then
        local triangle_count = 0
        
        for tri_idx = 0, detail_tri_count - 1 do
            local tri_off = detail_tris_off + tri_idx * 4
            if tri_off + 3 <= #data then
                local i0 = string.byte(data, tri_off) or 0
                local i1 = string.byte(data, tri_off + 1) or 0
                local i2 = string.byte(data, tri_off + 2) or 0
                
                -- Convert to 1-based indexing and validate
                local v1 = vertices[i0 + 1]
                local v2 = vertices[i1 + 1]
                local v3 = vertices[i2 + 1]
                
                if v1 and v2 and v3 then
                    table.insert(triangles, {v1, v2, v3})
                    triangle_count = triangle_count + 1
                end
            end
        end
        
        log_info("Parsed " .. triangle_count .. " detail triangles from " .. (detail_tri_count or 0) .. " total")
    else
        log_warning("No detail triangles available, using polygon fan triangulation")
        
        -- Fallback: create triangles from polygon data using fan triangulation
        -- This is less accurate but better than nothing
        if poly_count and poly_count > 0 then
            -- Simplified polygon parsing for fallback triangulation
            -- Would need full polygon parsing implementation here
            log_info("Using fallback polygon triangulation (not implemented yet)")
        end
    end
    
    return triangles
end


-- Optimized navigation mesh drawing (adapted from LxPS_NewProject)
-- Uses efficient triangle caching and distance culling to prevent freezes
local mesh_cache = {
    tris = nil,
    last_tile_key = nil,
    last_update = 0,
    update_interval = 2000  -- Update cache every 2 seconds
}

local function draw_navigation_debug()
    if not path_drawing_enabled then
        return
    end
    
    local success, error_msg = pcall(function()
        
        -- Generate mesh triangles if needed
        if draw_current_polygon then
            generate_mesh_triangles()
        end
        
        -- Draw cached navigation mesh if available
        if draw_current_polygon and _G.LxPS_TestMesh and _G.LxPS_TestMesh.tris then
            local Color = require("common/color")
            local fill = Color.green(60)
            local player = core.object_manager.get_local_player()
            local pos = player and player:get_position() or nil
            local R2 = 100*100  -- 100 yard culling radius squared
            
            for i = 1, #_G.LxPS_TestMesh.tris do
                local t = _G.LxPS_TestMesh.tris[i]
                if pos then
                    -- Distance culling - only draw triangles near player
                    local ax = t[1].x - pos.x
                    local ay = t[1].y - pos.y
                    local bx = t[2].x - pos.x
                    local by = t[2].y - pos.y
                    local cx = t[3].x - pos.x
                    local cy = t[3].y - pos.y
                    local d2 = math.min(ax*ax + ay*ay, math.min(bx*bx + by*by, cx*cx + cy*cy))
                    if d2 <= R2 then
                        core.graphics.triangle_3d_filled(t[1], t[2], t[3], fill)
                    end
                else
                    core.graphics.triangle_3d_filled(t[1], t[2], t[3], fill)
                end
            end
            
            -- Draw player position marker
            if pos and draw_current_polygon then
                local player_vec = vec3.new(pos.x, pos.y, pos.z + 2.0)
                core.graphics.circle_3d_filled(player_vec, 0.5, color.new(255, 255, 0, 255))
            end
        end
        
        -- Draw start position marker (lightweight)
        if LxTest.state.start_position then
            local start_vec = vec3.new(LxTest.state.start_position.x, LxTest.state.start_position.y, LxTest.state.start_position.z + 2.0)
            core.graphics.circle_3d_filled(start_vec, 1.0, color.new(0, 255, 0, 255))
        end
        
        -- Draw end position marker (lightweight)
        if LxTest.state.end_position then
            local end_vec = vec3.new(LxTest.state.end_position.x, LxTest.state.end_position.y, LxTest.state.end_position.z + 2.0)
            core.graphics.circle_3d_filled(end_vec, 1.0, color.new(255, 0, 0, 255))
        end
        
        -- Draw path lines and waypoints (optimized)
        if LxTest.state.current_path and #LxTest.state.current_path >= 2 then
            local path = LxTest.state.current_path
            
            -- Draw lines between waypoints (batched)
            for i = 1, #path - 1 do
                local start_point = path[i]
                local end_point = path[i + 1]
                local start_vec = vec3.new(start_point.x, start_point.y, start_point.z)
                local end_vec = vec3.new(end_point.x, end_point.y, end_point.z)
                core.graphics.line_3d(start_vec, end_vec, color.new(0, 255, 0, 255), 3.0)
            end
            
            -- Draw waypoint markers (batched)
            for i, waypoint in ipairs(path) do
                local waypoint_color = color.new(0, 0, 255, 255)
                if i == 1 then
                    waypoint_color = color.new(0, 255, 0, 255)
                elseif i == #path then
                    waypoint_color = color.new(255, 0, 0, 255)
                end
                local waypoint_vec = vec3.new(waypoint.x, waypoint.y, waypoint.z + 1.0)
                core.graphics.circle_3d_filled(waypoint_vec, 0.8, waypoint_color)
            end
        end
        
    end)
    
    if not success then
        if math.random() < 0.01 then
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
        
        menu_elements.draw_current_poly_button:render("Draw Navigation Mesh: " .. (draw_current_polygon and "ON" or "OFF"))
        if menu_elements.draw_current_poly_button:is_clicked() then
            draw_current_polygon = not draw_current_polygon
            log_info("Draw navigation mesh: " .. (draw_current_polygon and "enabled" or "disabled"))
            if draw_current_polygon then
                -- Clear cache to force regeneration
                mesh_cache.tris = nil
                mesh_cache.last_tile_key = nil
                _G.LxPS_TestMesh = nil
            end
        end
        
        menu_elements.generate_mesh_button:render("Generate Mesh Triangles")
        if menu_elements.generate_mesh_button:is_clicked() then
            -- Force mesh generation
            mesh_cache.tris = nil
            mesh_cache.last_tile_key = nil
            _G.LxPS_TestMesh = nil
            generate_mesh_triangles()
            log_info("Mesh generation triggered")
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