-- CoreAdapter: minimal, explicit wrapper to Project Sylvanas API
-- No reuse of other LxPS_* modules. All dependencies go through 'core'.
-- RULE: DO NEVER USE . in require — always use /
-- RULE: When inside src/, DO NOT prefix with 'src/' in require. Use relative module name only.

local CoreAdapter = {}

-- Logging
function CoreAdapter.log_info(msg) core.log("[NXP] " .. tostring(msg)) end
function CoreAdapter.log_warn(msg) core.log_warning("[NXP] " .. tostring(msg)) end
function CoreAdapter.log_error(msg) core.log_error("[NXP] " .. tostring(msg)) end

-- File IO: all paths relative to scripts_data
function CoreAdapter.read_data_file(path)
    return core.read_data_file(path)
end

-- Game context
function CoreAdapter.get_instance_id()
    if core.get_instance_id then return core.get_instance_id() end
    if core.world and core.world.map_id then return core.world.map_id() end
    return nil
end

function CoreAdapter.get_instance_name()
    if core.get_instance_name then return core.get_instance_name() end
    if core.world and core.world.map_name then return core.world.map_name() end
    return "unknown"
end

function CoreAdapter.get_player()
    if core.object_manager and core.object_manager.get_local_player then
        return core.object_manager.get_local_player()
    end
    if core.player and core.player.position then
        return {
            get_position = function()
                local p = core.player:position()
                return { x = p.x, y = p.y, z = p.z }
            end
        }
    end
    return nil
end

-- UI registration
function CoreAdapter.register_menu(render_fn)
    if core.register_on_render_menu_callback then
        core.register_on_render_menu_callback(render_fn)
    end
end

function CoreAdapter.register_render(render_fn)
    if core.register_on_render_callback then
        core.register_on_render_callback(render_fn)
    end
end

-- Menu helpers
function CoreAdapter.menu_tree_node()
    return core.menu.tree_node()
end

function CoreAdapter.menu_button(id)
    return core.menu.button(id)
end

function CoreAdapter.menu_header()
    return core.menu.header()
end

-- Log files
function CoreAdapter.create_log_file(name)
    return core.create_log_file(name)
end

function CoreAdapter.write_log_file(name, line)
    return core.write_log_file(name, line)
end

-- Time
function CoreAdapter.time_ms()
    return core.game_time and math.floor(core.game_time()) or core.time()
end

return CoreAdapter