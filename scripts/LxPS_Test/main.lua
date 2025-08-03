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
    run_tests_button = core.menu.button("run_tests"),
    clear_data_button = core.menu.button("clear_data"),
    status_header = core.menu.header()
}

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
        
        menu_elements.run_tests_button:render("Run System Tests")
        if menu_elements.run_tests_button:is_clicked() then
            run_tests()
        end
        
        menu_elements.clear_data_button:render("Clear Test Data")
        if menu_elements.clear_data_button:is_clicked() then
            clear_data()
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