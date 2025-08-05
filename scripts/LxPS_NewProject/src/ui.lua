-- ui.lua
-- Minimal menu to execute Goal 1 actions with explicit, verifiable outputs
-- Note: Do NOT require("LxPS_NewProject/..."). In this sandbox, our project files
-- are available by relative module names from the scripts/ root.

-- RULE: DO NEVER USE . in require — always use /
-- RULE: When inside src/, DO NOT prefix with 'src/' in require. Use relative module name only.
local Core = require("src/core_adapter")
local Index = require("src/tile_index")
local Loader = require("src/tile_loader")
local Verifier = require("src/verifier")
local Pathfinder = require("src/pathfinder")
local MeshDraw = require("src/mesh_draw_manager")

local UI = {}

local _state = { start = nil, stop = nil, path = nil, info = nil, draw_mesh = false }
local _cache = { key = nil, tris = nil }



-- Menu elements
local elements = {
    main_tree = Core.menu_tree_node(),
    btn_probe_tile = Core.menu_button("nxp_probe_tile"),
    btn_scan_tiles = Core.menu_button("nxp_scan_tiles"),
    btn_current_calc = Core.menu_button("nxp_current_calc"),
    btn_safe_start = Core.menu_button("nxp_safe_start"),
    btn_safe_end = Core.menu_button("nxp_safe_end"),
    btn_calc_path = Core.menu_button("nxp_calc_path"),
    btn_clear_path = Core.menu_button("nxp_clear_path"),
    header_status = Core.menu_header(),
    chk_draw_mesh = (core.menu and core.menu.checkbox and core.menu.checkbox(false, "nxp_chk_draw_mesh")) or nil
}

-- Helpers
local function dump_probe_to_log(probe)
    if not probe then return end
    -- Use fixed filename so it is overwritten each run for easy locating
    local logfile = "nxp_probe.log"
    Core.create_log_file(logfile)

    local function writeln(s) Core.write_log_file(logfile, s .. "\n") end

    writeln("=== NXP TILE PROBE ===")
    -- Be robust against nil fields; avoid %d on nil which causes the reported error
    local instance_id_txt = tostring(probe.instance_id or "NA")
    local ts = Core.time_ms and Core.time_ms() or 0
    writeln(string.format("time_ms=%s instance_id=%s", tostring(ts or "NA"), instance_id_txt))
    local p = probe.position or {x=0,y=0,z=0}
    local px = tonumber(p.x) or 0
    local py = tonumber(p.y) or 0
    local pz = tonumber(p.z) or 0
    writeln(string.format("pos=(%.2f, %.2f, %.2f)", px, py, pz))

    local function write_variant(name, v)
        if not v then
            writeln(name .. ": nil")
            return
        end
        writeln(string.format("[%s] tile=(%s,%s) file=%s exists=%s parsed=%s",
            name, tostring(v.tile_x), tostring(v.tile_y), tostring(v.filename),
            tostring(v.exists), tostring(v.parsed)))
        if v.bounds then
            writeln(string.format("[%s] bounds X[%.2f..%.2f] Y[%.2f..%.2f] Z[%.2f..%.2f]",
                name, v.bounds.bmin_x, v.bounds.bmax_x,
                v.bounds.bmin_z, v.bounds.bmax_z,
                v.bounds.bmin_y, v.bounds.bmax_y))
        end
        if v.inside_axes then
            writeln(string.format("[%s] inside axes: X=%s Y=%s Z=%s",
                name, tostring(v.inside_axes.x), tostring(v.inside_axes.y), tostring(v.inside_axes.z)))
        end
        writeln(string.format("[%s] contains_player=%s", name, tostring(v.contains_player)))
    end

    write_variant("floor", probe.floor)
    write_variant("ceil", probe.ceil)
    writeln("=== END ===")

    Core.log_info("Probe written to scripts_log/" .. logfile .. " (overwritten each run)")
end

local function scan_all_tiles_and_log()
    local instance_id = Core.get_instance_id()
    if not instance_id then
        Core.log_error("scan_all_tiles: no instance id")
        return
    end

    local result = Loader.load_all_tiles(instance_id, { parse = true })

    -- Use fixed filename so it is overwritten each run for easy locating
    local logfile = "nxp_scan.log"
    Core.create_log_file(logfile)
    local function writeln(s) Core.write_log_file(logfile, s .. "\n") end

    writeln("=== NXP TILE SCAN ===")
    writeln(string.format("instance_id=%d files_found=%d parsed=%d",
        instance_id, result.count or 0, result.parsed_count or 0))

    local shown = 0
    for fname, t in pairs(result.tiles or {}) do
        if shown < 25 then
            if t.header then
                local h = t.header
                writeln(string.format("%s: (%02d,%02d) poly=%d vert=%d X[%.2f..%.2f] Y[%.2f..%.2f] Z[%.2f..%.2f]",
                    fname, t.tile_x or -1, t.tile_y or -1,
                    h.polyCount or -1, h.vertCount or -1,
                    h.bmin_x or 0, h.bmax_x or 0,
                    h.bmin_z or 0, h.bmax_z or 0,
                    h.bmin_y or 0, h.bmax_y or 0))
            else
                writeln(string.format("%s: (%02d,%02d) header=NIL",
                    fname, t.tile_x or -1, t.tile_y or -1))
            end
            shown = shown + 1
        end
    end
    writeln("=== END ===")

    Core.log_info("Scan summary written to scripts_log/" .. logfile .. " (overwritten each run)")
end

local function log_current_calculation()
    local player = Core.get_player()
    if not player then
        Core.log_error("current_calc: no player")
        return
    end
    local pos = player:get_position()
    if not pos then
        Core.log_error("current_calc: missing player position")
        return
    end
    local fx, fy = Index.get_tile_for_position(pos.x, pos.y)
    local cx, cy = Index.get_tile_for_position_ceil(pos.x, pos.y)
    Core.log_info(string.format("current_calc pos=(%.2f,%.2f,%.2f) floor=[%s,%s] ceil=[%s,%s]",
        pos.x, pos.y, pos.z, tostring(fx), tostring(fy), tostring(cx), tostring(cy)))
end

-- Helpers to draw overlays if Core exposes them
local function draw_circle_outline(pos, radius, color)
    if Core.draw_circle_outline then
        Core.draw_circle_outline(pos, radius, color or {r=0,g=1,b=0,a=1})
    end
end

local function draw_polyline(points, color)
    if Core.draw_polyline then
        Core.draw_polyline(points, color or {r=0,g=0.8,b=1,a=1})
    end
end

-- Helpers to draw overlays if Core exposes them
local function draw_circle_outline(pos, radius, color)
    if Core.draw_circle_outline then
        Core.draw_circle_outline(pos, radius, color or {r=0,g=1,b=0,a=1})
    end
end

local function draw_polyline(points, color)
    if Core.draw_polyline then
        Core.draw_polyline(points, color or {r=0,g=0.8,b=1,a=1})
    end
end

-- Public: render menu
function UI.render_menu()
    elements.main_tree:render("LxPS New Project", function()
        elements.btn_probe_tile:render("Probe Current Tile (log)")
        if elements.btn_probe_tile:is_clicked() then
            local player = Core.get_player()
            if player then
                local pos = player:get_position()
                local iid = Core.get_instance_id()
                if pos and iid then
                    local probe = Verifier.probe_tile_at_position(iid, pos)
                    dump_probe_to_log(probe)
                else
                    Core.log_error("Cannot probe: missing pos or instance")
                end
            else
                Core.log_error("Cannot probe: no player")
            end
        end

        elements.btn_scan_tiles:render("Scan All Tiles (log)")
        if elements.btn_scan_tiles:is_clicked() then
            scan_all_tiles_and_log()
        end

        elements.btn_current_calc:render("Show Current Tile Calculation")
        if elements.btn_current_calc:is_clicked() then
            log_current_calculation()
        end

        -- Safe/End and Path buttons
        elements.btn_safe_start:render("Safe Position Start")
        if elements.btn_safe_start:is_clicked() then
            local p = Core.get_player()
            if not p then Core.log_error("Safe Start: no player") else
                local pos = p:get_position()
                local iid = Core.get_instance_id()
                if pos and iid then
                    _state.start = {x=pos.x,y=pos.y,z=pos.z,iid=iid}
                    Core.log_info(string.format("[NXP] Start saved (%.2f, %.2f, %.2f) iid=%s", pos.x,pos.y,pos.z,tostring(iid)))
                else
                    Core.log_error("Safe Start: missing pos or iid")
                end
            end
        end

        elements.btn_safe_end:render("Safe Position End")
        if elements.btn_safe_end:is_clicked() then
            local p = Core.get_player()
            if not p then Core.log_error("Safe End: no player") else
                local pos = p:get_position()
                local iid = Core.get_instance_id()
                if pos and iid then
                    _state.stop = {x=pos.x,y=pos.y,z=pos.z,iid=iid}
                    Core.log_info(string.format("[NXP] End saved (%.2f, %.2f, %.2f) iid=%s", pos.x,pos.y,pos.z,tostring(iid)))
                else
                    Core.log_error("Safe End: missing pos or iid")
                end
            end
        end

        elements.btn_calc_path:render("Calculate Path")
        if elements.btn_calc_path:is_clicked() then
            if not _state.start or not _state.stop then
                Core.log_error("Path: need both start and end")
            else
                local res = Pathfinder.compute_path(_state.start, _state.stop)
                if not res or not res.points or #res.points == 0 then
                    Core.log_error("Path: failed to compute")
                else
                    _state.path = res.points
                    _state.info = res.info
                    Core.log_info(string.format("[NXP] Path computed with %d points", #res.points))
                end
            end
        end

        elements.btn_clear_path:render("Clear Path")
        if elements.btn_clear_path:is_clicked() then
            _state.path = nil
            _state.info = nil
            Core.log_info("[NXP] Path cleared")
        end

        -- Draw overlays
        if _state.start then draw_circle_outline(_state.start, 2.0, {r=0,g=1,b=0,a=1}) end
        if _state.stop then draw_circle_outline(_state.stop, 2.0, {r=1,g=0,b=0,a=1}) end
        if _state.path and #_state.path >= 2 then draw_polyline(_state.path, {r=0,g=0.8,b=1,a=1}) end
        if elements.chk_draw_mesh then
            elements.chk_draw_mesh:render("Draw Mesh", "Render parsed tiles as wireframe")
            _state.draw_mesh = elements.chk_draw_mesh:get_state()
        end
    end)
end

function UI.render_mesh()
    if not _state.draw_mesh then return end
    local gfx = core.graphics
    if not gfx or not gfx.line_3d then return end
    MeshDraw.ensure_loaded_current_tile()
    local tris = MeshDraw.get_tris() or {}
    if #tris == 0 then return end
    local Color = require("common/color")
    local Vec3 = require("common/geometry/vector_3")
    local col = Color.green(150)
    local player = Core.get_player(); if not player then return end
    local pos = player:get_position(); if not pos then return end
    local tris = MeshDraw.get_tris() or {}
    local bbox = MeshDraw.get_bbox()
    local in_x = pos.x >= h.bmin_z and pos.x <= h.bmax_z
    local in_y = pos.y >= h.bmin_x and pos.y <= h.bmax_x
    local in_z = pos.z >= h.bmin_y and pos.z <= h.bmax_y
    Core.log_info(string.format("DrawMesh: contains X=%s Y=%s Z=%s", tostring(in_x), tostring(in_y), tostring(in_z)))
    local zmin = h.bmin_y
    local zmax = h.bmax_y
    local p1b = Vec3.new(h.bmin_z, h.bmin_x, zmin)
    local p2b = Vec3.new(h.bmax_z, h.bmin_x, zmin)
    local p3b = Vec3.new(h.bmax_z, h.bmax_x, zmin)
    local p4b = Vec3.new(h.bmin_z, h.bmax_x, zmin)
    local p1t = Vec3.new(h.bmin_z, h.bmin_x, zmax)
    local p2t = Vec3.new(h.bmax_z, h.bmin_x, zmax)
    local p3t = Vec3.new(h.bmax_z, h.bmax_x, zmax)
    local p4t = Vec3.new(h.bmin_z, h.bmax_x, zmax)
    gfx.line_3d(p1b,p2b,col,1.5,2.5,0)
    gfx.line_3d(p2b,p3b,col,1.5,2.5,0)
    gfx.line_3d(p3b,p4b,col,1.5,2.5,0)
    gfx.line_3d(p4b,p1b,col,1.5,2.5,0)
    gfx.line_3d(p1t,p2t,col,1.5,2.5,0)
    gfx.line_3d(p2t,p3t,col,1.5,2.5,0)
    gfx.line_3d(p3t,p4t,col,1.5,2.5,0)
    gfx.line_3d(p4t,p1t,col,1.5,2.5,0)
    gfx.line_3d(p1b,p1t,col,1.0,2.5,0)
    gfx.line_3d(p2b,p2t,col,1.0,2.5,0)
    gfx.line_3d(p3b,p3t,col,1.0,2.5,0)
    gfx.line_3d(p4b,p4t,col,1.0,2.5,0)

    if not _cache.tris then _cache.header = h; _cache.data = tile.raw_data; _cache.tris = {} end
    local data = _cache.data
    local function read_u32(off)
        local a,b,c,d = string.byte(data, off, off+3); return a + b*256 + c*65536 + d*16777216
    end
    local function read_f32(off)
        local b1,b2,b3,b4 = string.byte(data, off, off+3)
        local sign = (b4 >= 128) and -1 or 1
        local exp = ((b4 % 128) * 2) + math.floor(b3 / 128)
        local mant = ((b3 % 128) * 65536) + (b2 * 256) + b1
        if exp == 0 then return (mant == 0) and (sign * 0.0) or (sign * mant * 2^-149)
        elseif exp == 255 then return (mant == 0) and (sign * math.huge) or (0/0) end
        return sign * (1 + mant / 2^23) * 2^(exp - 127)
    end

    local off = 1 + 20
    local magic = read_u32(off); if magic ~= 0x444E4156 then return end
    off = off + 4
    local version = read_u32(off); off = off + 4
    off = off + 4*4
    off = off + 4*6
    off = off + 4*3
    local bmin_x = read_f32(off); off = off + 4
    local bmin_y = read_f32(off); off = off + 4
    local bmin_z = read_f32(off); off = off + 4
    local bmax_x = read_f32(off); off = off + 4
    local bmax_y = read_f32(off); off = off + 4
    local bmax_z = read_f32(off); off = off + 4
    off = off + 4

    local verts_off = 1 + 20 + 100
    local vertCount = tonumber(h.vertCount) or 0
    if verts_off + vertCount*12 > #data then return end
    local vertices = {}
    local o = verts_off
    for i=1,vertCount do
        local vx = read_f32(o); local vy = read_f32(o+4); local vz = read_f32(o+8); o = o + 12
        if vx and vy and vz then
            local wx = vz
            local wy = vx
            local wz = vy
            vertices[i] = Vec3.new(wx, wy, wz)
        end
    end

    local polyCount = tonumber(h.polyCount) or 0
    local NVP = 6
    local polys_off = verts_off + vertCount * 12
    local dt_poly_size = 2 + 2*NVP + 4 + 4 + 2
    if polys_off + polyCount*dt_poly_size > #data then polyCount = math.max(0, math.floor((#data - polys_off)/dt_poly_size)) end

    local detailMeshCount = tonumber(h.detailMeshCount) or 0
    local detailVertCount = tonumber(h.detailVertCount) or 0
    local detailTriCount  = tonumber(h.detailTriCount) or 0

    local detail_meshes_off = polys_off + polyCount * dt_poly_size
    local function read_u32_at(off)
        if not off or off+3 > #data then return nil end
        local a,b,c,d=string.byte(data,off,off+3); return a + b*256 + c*65536 + d*16777216
    end

    local dmesh = {}
    local dm_off = detail_meshes_off
    for i=1,detailMeshCount do
        if dm_off+15 > #data then break end
        local vb = read_u32_at(dm_off); dm_off = dm_off + 4
        local nv = read_u32_at(dm_off); dm_off = dm_off + 4
        local tb = read_u32_at(dm_off); dm_off = dm_off + 4
        local nt = read_u32_at(dm_off); dm_off = dm_off + 4
        if not (vb and nv and tb and nt) then break end
        dmesh[i] = { vb=vb, nv=nv, tb=tb, nt=nt }
    end

    local dverts_off = dm_off
    local dtris_off  = dverts_off + detailVertCount * 12
    if dtris_off > #data then return end

    local function read_vec3_at(off)
        if not off or off+8 > #data then return nil,nil,nil end
        local x = read_f32(off); local y = read_f32(off+4); local z = read_f32(off+8)
        return x,y,z
    end

    local function get_detail_vert(i)
        local off = dverts_off + (i*12)
        local vx,vy,vz = read_vec3_at(off)
        if not vx then return nil end
        local wx = vz; local wy = vx; local wz = vy
        return Vec3.new(wx,wy,wz)
    end

    local function draw_detail_for_poly(pi)
        local dm = dmesh[pi+1]; if not dm then return end
        if not (dm.vb and dm.nv and dm.tb and dm.nt) then return end
        for t=0,dm.nt-1 do
            local toff = dtris_off + ( (dm.tb + t) * 4 )
            if toff+3 > #data then break end
            local i0 = string.byte(data, toff) or 0
            local i1 = string.byte(data, toff+1) or 0
            local i2 = string.byte(data, toff+2) or 0
            local function vert_for(idx)
                if idx < dm.nv then
                    return get_detail_vert(dm.vb + idx)
                else
                    local base = polys_off + pi * dt_poly_size
                    local voff = base + 2 + (idx - dm.nv)
                    if voff > #data then return nil end
                    local vind = (string.byte(data, voff) or 0) + 1
                    return vertices[vind]
                end
            end
            local a = vert_for(i0); local b = vert_for(i1); local c = vert_for(i2)
            if a and b and c then
                _cache.tris[#_cache.tris+1] = {a,b,c}
            end
        end
    end

    for pi=0,polyCount-1 do draw_detail_for_poly(pi) end
    Core.log_info(string.format("DrawMesh: cached %d triangles", #_cache.tris))
    _G.LxPS_NewProjectMesh = { tris = _cache.tris }
end

return UI