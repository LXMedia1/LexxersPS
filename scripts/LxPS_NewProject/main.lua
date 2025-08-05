-- LxPS_NewProject - Standalone, structured navmesh prototype
-- Goal 1: load all tiles for current get_instance_id, determine current tile, verify calculation using real data

local NXP = {}

local CoreAdapter = require("src/core_adapter")
local TileIndex   = require("src/tile_index")
local TileLoader  = require("src/tile_loader")
local Verifier    = require("src/verifier")
local UI          = require("src/ui")

_G.LxPS_NewProject = NXP

local function init()
    CoreAdapter.log_info("LxPS_NewProject initializing...")
    CoreAdapter.log_info("Using absolute requires: scripts/LxPS_NewProject/src/*")
    CoreAdapter.log_info("Requested: disable LxPS_Core, LxPS_Navigator, LxPS_Test, LxPS_MMTileTest")
    CoreAdapter.log_info("Ensure only LxPS_NewProject/header.lua has load=true in headers")
    CoreAdapter.register_menu(UI.render_menu)
    CoreAdapter.register_render(function()
      if _G and _G.LxPS_NewProject and _G.LxPS_NewProject._render then _G.LxPS_NewProject._render() end
    end)
    CoreAdapter.log_info("LxPS_NewProject ready")
end

function NXP.load_all_tiles_for_current_instance(parse)
    local instance_id = CoreAdapter.get_instance_id()
    if not instance_id then
        CoreAdapter.log_error("No instance_id available")
        return nil
    end
    CoreAdapter.log_info(("Loading all tiles for instance %d (parse=%s)"):format(instance_id, tostring(parse ~= false)))
    local result = TileLoader.load_all_tiles(instance_id, { parse = (parse ~= false) })
    CoreAdapter.log_info(("Summary: files_found=%d parsed=%d"):format(result.count or 0, result.parsed_count or 0))
    return result
end

function NXP.probe_current_tile()
    local player = CoreAdapter.get_player()
    if not player then
        CoreAdapter.log_error("probe_current_tile: no player")
        return nil
    end
    local pos = player:get_position()
    if not pos then
        CoreAdapter.log_error("probe_current_tile: cannot read player position")
        return nil
    end
    local instance_id = CoreAdapter.get_instance_id()
    if not instance_id then
        CoreAdapter.log_error("probe_current_tile: no instance id")
        return nil
    end
    return Verifier.probe_tile_at_position(instance_id, pos)
end

init()

function NXP._render()
  local UI = require("src/ui")
  if UI and UI.render_mesh then UI.render_mesh() end
  if _G.LxPS_NewProjectMesh and _G.LxPS_NewProjectMesh.tris then
    local Color = require("common/color")
    local fill = Color.green(60)
    local player = core.object_manager and core.object_manager.get_local_player and core.object_manager.get_local_player()
    local pos = player and player:get_position() or nil
    local R2 = 100*100
    for i=1,#_G.LxPS_NewProjectMesh.tris do
      local t = _G.LxPS_NewProjectMesh.tris[i]
      if pos then
        local ax = t[1].x-pos.x; local ay=t[1].y-pos.y
        local bx = t[2].x-pos.x; local by=t[2].y-pos.y
        local cx = t[3].x-pos.x; local cy=t[3].y-pos.y
        local d2 = math.min(ax*ax+ay*ay, math.min(bx*bx+by*by, cx*cx+cy*cy))
        if d2 <= R2 then core.graphics.triangle_3d_filled(t[1],t[2],t[3], fill) end
      else
        core.graphics.triangle_3d_filled(t[1],t[2],t[3], fill)
      end
    end
  end
end

return NXP
