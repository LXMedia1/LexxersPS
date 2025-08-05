local MeshManager = {}

local log = LxCore.Log("MeshManager")
local vec3 = require("common/geometry/vector_3")
local current_continent_id = nil
local current_mmap = nil
local current_tile_grid = {} -- Cache for 3x3 tile grid
local current_tile_center = {x = nil, y = nil} -- Track center tile position

--- Initialize the MeshManager and register update callback
function MeshManager.initialize()
    log.write("Initializing MeshManager...")
    core.register_on_update_callback(MeshManager.update)
end

--- Update callback that checks for continent changes and tile changes
function MeshManager.update()
    local continent_id = core.get_instance_id()
    
    if current_continent_id ~= continent_id then
        current_continent_id = continent_id
        current_tile_center.x = nil
        current_tile_center.y = nil
        current_tile_grid = {}
        MeshManager.load_mesh_for_continent(continent_id)
    end
    
    -- Check if player moved to a different tile
    local player = core.object_manager.get_local_player()
    if player and current_continent_id then
        local pos = player:get_position()
        local tile_x, tile_y = MeshManager.get_tile_for_position(pos.x, pos.y)
        
        if tile_x and tile_y then
            -- Check if we need to load new tile grid
            if current_tile_center.x ~= tile_x or current_tile_center.y ~= tile_y then
                current_tile_center.x = tile_x
                current_tile_center.y = tile_y
                
                log.write("Player moved to tile [" .. tile_x .. ", " .. tile_y .. "] - loading surrounding tiles")
                current_tile_grid = MeshManager.load_tile_grid(current_continent_id, tile_x, tile_y)
                
                local tile_count = 0
                for _ in pairs(current_tile_grid) do
                    tile_count = tile_count + 1
                end
                log.write("Loaded " .. tile_count .. " tiles in 3x3 grid")
            end
        end
    end
    
    -- Continue tile scan coroutine if it exists
    if _G.tile_scan_coroutine and coroutine.status(_G.tile_scan_coroutine) ~= "dead" then
        coroutine.resume(_G.tile_scan_coroutine)
        if coroutine.status(_G.tile_scan_coroutine) == "dead" then
            _G.tile_scan_coroutine = nil
        end
    end
end

--- Load mesh data for the specified continent
---@param continent_id number The continent ID
function MeshManager.load_mesh_for_continent(continent_id)
    local filename = string.format("%04d.mmap", continent_id)
    local continent_name = core.get_instance_name()
    
    log.write("Switched to Continent " .. continent_name .. " (" .. continent_id .. ")")
    
    local raw_data = LxCore.FileReader.read_mmap(filename)
    current_mmap = LxCore.Parser.parse_mmap(raw_data)
    
    -- Test tile calculation after loading
    local player = core.object_manager.get_local_player()
    if player then
        local pos = player:get_position()
        local tile_x, tile_y = MeshManager.get_tile_for_position(pos.x, pos.y)
        
        if tile_x and tile_y then
            local filename = MeshManager.get_mmtile_filename(continent_id, tile_x, tile_y)
            log.write("Current tile: [" .. tile_x .. ", " .. tile_y .. "] -> " .. filename)
            
            -- Load and parse the tile
            local tile_data = LxCore.FileReader.read("mmaps/" .. filename)
            if tile_data and #tile_data > 0 then
                log.write("Tile file size: " .. #tile_data .. " bytes")
                
                -- Debug: show first 16 bytes as hex
                local hex_bytes = {}
                for i = 1, math.min(16, #tile_data) do
                    hex_bytes[i] = string.format("%02X", string.byte(tile_data, i))
                end
                log.write("First 16 bytes: " .. table.concat(hex_bytes, " "))
                
                -- Debug the first 20 bytes as the TrinityCore header
                local magic = LxCore.Parser.read_u32(tile_data, 1)
                log.write("Magic number read: 0x" .. string.format("%08X", magic))
                log.write("Expected PAMM: 0x4D4D4150")
                
                local parsed_tile = LxCore.Parser.parse_mmtile(tile_data)
                if parsed_tile then
                    log.write("Tile loaded: " .. parsed_tile.header.polyCount .. " polygons, " .. parsed_tile.header.vertCount .. " vertices")
                    log.write("Parsed vertices: " .. #parsed_tile.vertices)
                    log.write("Parsed polygons: " .. #parsed_tile.polygons)
                    
                    -- Quick check of vertex 0 and 1
                    if parsed_tile.vertices[1] then
                        local v = parsed_tile.vertices[1]
                        log.write("Debug: vertices[1] = (" .. string.format("%.2f", v.x or 0) .. ", " .. string.format("%.2f", v.y or 0) .. ", " .. string.format("%.2f", v.z or 0) .. ")")
                    else
                        log.write("Debug: vertices[1] is nil")
                    end
                    
                    -- Write complete tile data to log file
                    log.write_to_file("=== COMPLETE TILE READOUT ===")
                    log.write_to_file("File: " .. filename)
                    log.write_to_file("Size: " .. #tile_data .. " bytes")
                    log.write_to_file("")
                    
                    -- TrinityCore Header
                    log.write_to_file("TrinityCore MmapTileHeader:")
                    log.write_to_file("  mmapMagic: 0x" .. string.format("%08X", parsed_tile.tc_header.mmapMagic))
                    log.write_to_file("  dtVersion: " .. parsed_tile.tc_header.dtVersion)
                    log.write_to_file("  mmapVersion: " .. parsed_tile.tc_header.mmapVersion)
                    log.write_to_file("  size: " .. parsed_tile.tc_header.size .. " bytes")
                    log.write_to_file("  usesLiquids: " .. parsed_tile.tc_header.usesLiquids)
                    log.write_to_file("")
                    
                    -- DNAV Header
                    log.write_to_file("DNAV Header:")
                    log.write_to_file("  Magic: 0x" .. string.format("%08X", parsed_tile.header.magic))
                    log.write_to_file("  Version: " .. parsed_tile.header.version)
                    log.write_to_file("  Tile X: " .. parsed_tile.header.x)
                    log.write_to_file("  Tile Y: " .. parsed_tile.header.y)
                    log.write_to_file("  Layer: " .. parsed_tile.header.layer)
                    log.write_to_file("  UserId: 0x" .. string.format("%08X", parsed_tile.header.userId))
                    log.write_to_file("  Polygon Count: " .. parsed_tile.header.polyCount)
                    log.write_to_file("  Vertex Count: " .. parsed_tile.header.vertCount)
                    log.write_to_file("  Max Link Count: " .. parsed_tile.header.maxLinkCount)
                    log.write_to_file("  Detail Mesh Count: " .. parsed_tile.header.detailMeshCount)
                    log.write_to_file("  Detail Vertex Count: " .. parsed_tile.header.detailVertCount)
                    log.write_to_file("  Detail Triangle Count: " .. parsed_tile.header.detailTriCount)
                    log.write_to_file("  BV Node Count: " .. parsed_tile.header.bvNodeCount)
                    log.write_to_file("  Off-Mesh Connection Count: " .. parsed_tile.header.offMeshConCount)
                    log.write_to_file("  Off-Mesh Base: " .. parsed_tile.header.offMeshBase)
                    log.write_to_file("  Walkable Height: " .. string.format("%.2f", parsed_tile.header.walkableHeight))
                    log.write_to_file("  Walkable Radius: " .. string.format("%.2f", parsed_tile.header.walkableRadius))
                    log.write_to_file("  Walkable Climb: " .. string.format("%.2f", parsed_tile.header.walkableClimb))
                    log.write_to_file("  Bounding Box Min: (" .. string.format("%.2f", parsed_tile.header.bmin_x) .. ", " .. string.format("%.2f", parsed_tile.header.bmin_y) .. ", " .. string.format("%.2f", parsed_tile.header.bmin_z) .. ")")
                    log.write_to_file("  Bounding Box Max: (" .. string.format("%.2f", parsed_tile.header.bmax_x) .. ", " .. string.format("%.2f", parsed_tile.header.bmax_y) .. ", " .. string.format("%.2f", parsed_tile.header.bmax_z) .. ")")
                    log.write_to_file("  BV Quantization Factor: " .. string.format("%.6f", parsed_tile.header.bvQuantFactor))
                    log.write_to_file("")
                    
                    -- Sample vertices
                    log.write_to_file("Sample Vertices (first 10):")
                    log.write_to_file("  Total vertices in array: " .. #parsed_tile.vertices)
                    for i = 1, math.min(10, #parsed_tile.vertices) do
                        local v = parsed_tile.vertices[i]
                        if v then
                            log.write_to_file("  Vertex " .. (i-1) .. ": (" .. string.format("%.2f", v.x or 0) .. ", " .. string.format("%.2f", v.y or 0) .. ", " .. string.format("%.2f", v.z or 0) .. ")")
                        else
                            log.write_to_file("  Vertex " .. (i-1) .. ": nil")
                        end
                    end
                    log.write_to_file("")
                    
                    -- Sample polygons
                    log.write_to_file("Sample Polygons (first 10):")
                    for i = 1, math.min(10, #parsed_tile.polygons) do
                        local p = parsed_tile.polygons[i]
                        log.write_to_file("  Polygon " .. (i-1) .. ":")
                        log.write_to_file("    Vertex Count: " .. p.vertCount)
                        log.write_to_file("    Flags: " .. p.flags)
                        log.write_to_file("    Area/Type: " .. p.areaAndtype)
                        log.write_to_file("    First Link: " .. p.firstLink)
                        
                        local vert_indices = {}
                        for j = 1, p.vertCount do
                            vert_indices[j] = tostring(p.verts[j])
                        end
                        log.write_to_file("    Vertex Indices: " .. table.concat(vert_indices, ", "))
                        
                        local neighbor_indices = {}
                        for j = 1, p.vertCount do
                            neighbor_indices[j] = tostring(p.neis[j])
                        end
                        log.write_to_file("    Neighbor Indices: " .. table.concat(neighbor_indices, ", "))
                    end
                    log.write_to_file("")
                    
                    -- All parsed data structures
                    log.write_to_file("Parsed Data Structures:")
                    log.write_to_file("  Polygons (dtPoly): " .. #parsed_tile.polygons)
                    log.write_to_file("  Links (dtLink): " .. #parsed_tile.links)
                    log.write_to_file("  Poly Details (dtPolyDetail): " .. #parsed_tile.poly_details)
                    log.write_to_file("  BV Nodes (dtBVNode): " .. #parsed_tile.bv_nodes)
                    log.write_to_file("  Off-mesh Connections: " .. #parsed_tile.offmesh_connections)
                    log.write_to_file("  Base Vertices: " .. #parsed_tile.vertices)
                    log.write_to_file("  Detail Vertices: " .. #parsed_tile.detail_vertices)
                    log.write_to_file("  Detail Triangles: " .. #parsed_tile.detail_triangles)
                    log.write_to_file("")
                    
                    -- Verification
                    log.write_to_file("Verification:")
                    log.write_to_file("  Header reports " .. parsed_tile.header.vertCount .. " vertices, parsed " .. #parsed_tile.vertices)
                    log.write_to_file("  Header reports " .. parsed_tile.header.polyCount .. " polygons, parsed " .. #parsed_tile.polygons)
                    log.write_to_file("  Header reports " .. parsed_tile.header.maxLinkCount .. " links, parsed " .. #parsed_tile.links)
                    log.write_to_file("  Header reports " .. parsed_tile.header.detailMeshCount .. " detail meshes, parsed " .. #parsed_tile.poly_details)
                    log.write_to_file("  Header reports " .. parsed_tile.header.detailVertCount .. " detail vertices, parsed " .. #parsed_tile.detail_vertices)
                    log.write_to_file("  Header reports " .. parsed_tile.header.detailTriCount .. " detail triangles, parsed " .. #parsed_tile.detail_triangles)
                    log.write_to_file("  Header reports " .. parsed_tile.header.bvNodeCount .. " BV nodes, parsed " .. #parsed_tile.bv_nodes)
                    log.write_to_file("  Header reports " .. parsed_tile.header.offMeshConCount .. " off-mesh connections, parsed " .. #parsed_tile.offmesh_connections)
                    log.write_to_file("")
                    
                    log.write_to_file("File Parsing:")
                    log.write_to_file("  Total file size: " .. #tile_data .. " bytes")
                    log.write_to_file("  Bytes parsed: " .. parsed_tile.bytes_parsed .. " bytes")
                    log.write_to_file("  Expected navmesh size from header: " .. parsed_tile.tc_header.size .. " bytes")
                    log.write_to_file("  Bytes remaining: " .. (#tile_data - parsed_tile.bytes_parsed) .. " bytes")
                    
                    local all_match = true
                    if parsed_tile.header.vertCount ~= #parsed_tile.vertices then
                        log.write_to_file("  ✗ Vertex count mismatch!")
                        all_match = false
                    end
                    if parsed_tile.header.polyCount ~= #parsed_tile.polygons then
                        log.write_to_file("  ✗ Polygon count mismatch!")
                        all_match = false
                    end
                    if parsed_tile.header.maxLinkCount ~= #parsed_tile.links then
                        log.write_to_file("  ✗ Link count mismatch!")
                        all_match = false
                    end
                    if parsed_tile.header.detailMeshCount ~= #parsed_tile.poly_details then
                        log.write_to_file("  ✗ Detail mesh count mismatch!")
                        all_match = false
                    end
                    if parsed_tile.header.detailVertCount ~= #parsed_tile.detail_vertices then
                        log.write_to_file("  ✗ Detail vertex count mismatch!")
                        all_match = false
                    end
                    if parsed_tile.header.detailTriCount ~= #parsed_tile.detail_triangles then
                        log.write_to_file("  ✗ Detail triangle count mismatch!")
                        all_match = false
                    end
                    if parsed_tile.header.bvNodeCount ~= #parsed_tile.bv_nodes then
                        log.write_to_file("  ✗ BV node count mismatch!")
                        all_match = false
                    end
                    if parsed_tile.header.offMeshConCount ~= #parsed_tile.offmesh_connections then
                        log.write_to_file("  ✗ Off-mesh connection count mismatch!")
                        all_match = false
                    end
                    
                    if all_match then
                        log.write_to_file("  ✓ All structure counts match headers!")
                    end
                    
                    log.write_to_file("=== END TILE READOUT ===")
                    
                    log.write("Complete tile data written to log file")
                else
                    log.error("Failed to parse tile data")
                end
            else
                log.write("Tile file not found")
            end
        else
            log.write("Player outside tile bounds")
        end
    end
end

--- Get the current MMAP object
---@return MMAP|nil The current MMAP object or nil if none loaded
function MeshManager.get_current_mmap()
    return current_mmap
end

--- Get the current continent ID
---@return number|nil The current continent ID or nil if none set
function MeshManager.get_current_continent_id()
    return current_continent_id
end

--- Load all available tiles for a given continent (instance/map id)
--- This scans the 64x64 grid and attempts to read and parse each mmtile file.
--- Returns a summary with counts and a list of successfully loaded tiles.
---@param continent_id number The continent/map id
---@param options table|nil Optional flags {parse=true|false} to parse tiles for verification
---@return table result {count, parsed_count, files_found, tiles}
function MeshManager.load_all_tiles_for_continent(continent_id, options)
    options = options or {}
    local parse_tiles = options.parse ~= false -- default true

    local result = {
        count = 0,            -- number of tile files found (exist)
        parsed_count = 0,     -- number of tiles successfully parsed
        files_found = {},     -- list of filenames that exist
        tiles = {}            -- map filename -> {tile_x, tile_y, data?}
    }

    local found_first = false
    for tile_x = 0, 63 do
        for tile_y = 0, 63 do
            local filename = MeshManager.get_mmtile_filename(continent_id, tile_x, tile_y)
            local data = LxCore.FileReader.read("mmaps/" .. filename)
            if data and #data > 0 then
                result.count = result.count + 1
                table.insert(result.files_found, filename)

                if parse_tiles then
                    local ok, parsed = pcall(LxCore.Parser.parse_mmtile, data)
                    if ok and parsed then
                        result.parsed_count = result.parsed_count + 1
                        result.tiles[filename] = {
                            tile_x = tile_x,
                            tile_y = tile_y,
                            data = parsed
                        }
                        -- Log a small header sample for the first few found
                        if not found_first then
                            log.write(string.format("First tile found: %s | poly=%d vert=%d boundsX[%.2f..%.2f] Y[%.2f..%.2f] Z[%.2f..%.2f]",
                                filename,
                                parsed.header.polyCount, parsed.header.vertCount,
                                parsed.header.bmin_x, parsed.header.bmax_x,
                                parsed.header.bmin_z, parsed.header.bmax_z,
                                parsed.header.bmin_y, parsed.header.bmax_y))
                            found_first = true
                        end
                    else
                        log.error("Failed to parse tile: " .. filename)
                        result.tiles[filename] = {
                            tile_x = tile_x,
                            tile_y = tile_y,
                            data = nil
                        }
                    end
                else
                    result.tiles[filename] = {
                        tile_x = tile_x,
                        tile_y = tile_y,
                        data = nil
                    }
                end
            end
        end
    end

    log.write(string.format("Tile scan summary for continent %d: files_found=%d parsed=%d",
        continent_id, result.count, result.parsed_count))

    return result
end

--- Get current tile grid information
---@return table Information about the currently loaded tile grid
function MeshManager.get_tile_grid_info()
    local tile_count = 0
    local total_vertices = 0
    local total_polygons = 0
    
    for filename, tile_info in pairs(current_tile_grid) do
        tile_count = tile_count + 1
        total_vertices = total_vertices + #tile_info.data.vertices
        total_polygons = total_polygons + #tile_info.data.polygons
    end
    
    return {
        tile_count = tile_count,
        total_vertices = total_vertices,
        total_polygons = total_polygons,
        center_tile = {x = current_tile_center.x, y = current_tile_center.y}
    }
end

--- Calculate which tile a position is in based on the current MMAP
---@param x number Game world X coordinate
---@param y number Game world Y coordinate  
---@return number|nil, number|nil Tile X and Y indices, or nil if no MMAP loaded or out of bounds
function MeshManager.get_tile_for_position(x, y)
    if not current_mmap then
        return nil, nil
    end
    
    -- TrinityCore formula: tileX = 32 - ceil(x / GRID_SIZE), tileY = 32 - ceil(y / GRID_SIZE)
    -- where x is north-south, y is east-west, GRID_SIZE = 533.3333
    local GRID_SIZE = 533.3333
    local tile_x = 32 - math.ceil(x / GRID_SIZE)  -- x is north-south
    local tile_y = 32 - math.ceil(y / GRID_SIZE)  -- y is east-west
    
    -- Clamp to valid range 0-63
    tile_x = math.max(0, math.min(63, tile_x))
    tile_y = math.max(0, math.min(63, tile_y))
    
    return tile_x, tile_y
end

--- DEPRECATED: Floor-based tile calculation (INCORRECT - DO NOT USE)
--- This function is deprecated and should not be used. Use get_tile_for_position instead.
--- Kept only for compatibility during transition period.
---@param x number
---@param y number
---@return number|nil, number|nil
---@deprecated Use get_tile_for_position instead
function MeshManager.get_tile_for_position_floor(x, y)
    -- DEPRECATED: This calculation is incorrect. Use get_tile_for_position instead.
    log.warning("DEPRECATED: get_tile_for_position_floor is incorrect. Use get_tile_for_position instead.")
    return MeshManager.get_tile_for_position(x, y)
end

--- Get current player tile based on player position
---@return number|nil, number|nil Current tile X and Y indices, or nil if player not found
function MeshManager.get_current_player_tile()
    local player = core.object_manager.get_local_player()
    if not player then
        return nil, nil
    end
    
    local pos = player:get_position()
    return MeshManager.get_tile_for_position(pos.x, pos.y)
end

--- Generate mmtile filename for given continent and tile coordinates
---@param continent_id number The continent/map ID
---@param tile_x number The tile X coordinate
---@param tile_y number The tile Y coordinate
---@return string The mmtile filename
function MeshManager.get_mmtile_filename(continent_id, tile_x, tile_y)
    -- Confirmed format: IIIIYYXX (instance 4 digits, tile_y 2 digits, tile_x 2 digits)
    return string.format("%04d%02d%02d.mmtile", continent_id, tile_y, tile_x)
end

--- Get the current tile filename
---@return string|nil The current mmtile filename or nil if not available
function MeshManager.get_current_tile_filename()
    if not current_continent_id then
        return nil
    end
    
    local tile_x, tile_y = MeshManager.get_current_player_tile()
    if not tile_x or not tile_y then
        return nil
    end
    
    return MeshManager.get_mmtile_filename(current_continent_id, tile_x, tile_y)
end

--- Probe utility: determine current tile via both ceil and floor formulas and log details
function MeshManager.probe_current_tile()
    local player = core.object_manager.get_local_player()
    if not player then
        log.error("probe_current_tile: no player")
        return nil
    end
    local pos = player:get_position()
    if not pos or not current_continent_id then
        log.error("probe_current_tile: missing pos or continent")
        return nil
    end

    local cx, cy = MeshManager.get_tile_for_position(pos.x, pos.y)

    log.write(string.format("Probe pos=(%.2f, %.2f, %.2f) tile=[%s,%s] (using correct ceil formula)",
        pos.x, pos.y, pos.z, tostring(cx), tostring(cy)))

    local function try_load(tx, ty, label)
        if not tx or not ty then return nil end
        local fname = MeshManager.get_mmtile_filename(current_continent_id, tx, ty)
        local bin = LxCore.FileReader.read("mmaps/" .. fname)
        if not bin or #bin == 0 then
            log.write(label .. " file missing: " .. fname)
            return { filename = fname, exists = false }
        end
        local parsed = LxCore.Parser.parse_mmtile(bin)
        if not parsed then
            log.error(label .. " failed to parse: " .. fname)
            return { filename = fname, exists = true, parsed = false }
        end
        local h = parsed.header
        log.write(string.format("%s %s parsed: poly=%d vert=%d boundsX[%.2f..%.2f] Y[%.2f..%.2f] Z[%.2f..%.2f]",
            label, fname, h.polyCount, h.vertCount, h.bmin_x, h.bmax_x, h.bmin_z, h.bmax_z, h.bmin_y, h.bmax_y))

        local inside_x = pos.x >= h.bmin_x and pos.x <= h.bmax_x
        local inside_y = pos.y >= h.bmin_z and pos.y <= h.bmax_z
        local inside_z = pos.z >= h.bmin_y and pos.z <= h.bmax_y
        log.write(string.format("%s inside? X=%s Y=%s Z=%s", label, tostring(inside_x), tostring(inside_y), tostring(inside_z)))

        return {
            filename = fname,
            exists = true,
            parsed = true,
            bounds = h,
            contains_player = inside_x and inside_y and inside_z
        }
    end

    local r1 = try_load(cx, cy, "CORRECT")
    return { correct = r1, pos = {x=pos.x,y=pos.y,z=pos.z}, continent_id = current_continent_id }
end

--- Check if a point is inside a polygon using ray casting algorithm
---@param game_x number Game X coordinate (north-south)
---@param game_y number Game Y coordinate (east-west)
---@param polygon_vertices table Array of mesh vertices {x, y, z} where x=north-south, y=height, z=east-west
---@return boolean True if point is inside polygon
function MeshManager.point_in_polygon(game_x, game_y, polygon_vertices)
    local inside = false
    local j = #polygon_vertices
    
    for i = 1, #polygon_vertices do
        local vi = polygon_vertices[i]
        local vj = polygon_vertices[j]
        
        -- Game(X,Y,Z) -> Mesh(X,Z,Y)
        -- Compare game_x with mesh.x and game_y with mesh.z
        if ((vi.z > game_y) ~= (vj.z > game_y)) and 
           (game_x < (vj.x - vi.x) * (game_y - vi.z) / (vj.z - vi.z) + vi.x) then
            inside = not inside
        end
        j = i
    end
    
    return inside
end

--- Find which polygon contains the given position
---@param x number World X coordinate
---@param y number World Y coordinate
---@param z number World Z coordinate
---@param z_tolerance number Z tolerance in yards (default 0.5)
---@return number|nil, table|nil Polygon index and polygon data, or nil if not found
function MeshManager.find_polygon_at_position(x, y, z, z_tolerance)
    z_tolerance = z_tolerance or 0.5
    
    if not current_continent_id then
        return nil, nil
    end
    
    -- Get current tile
    local tile_x, tile_y = MeshManager.get_tile_for_position(x, y)
    if not tile_x or not tile_y then
        return nil, nil
    end
    
    -- Load tile data if not already loaded or different tile
    local filename = MeshManager.get_mmtile_filename(current_continent_id, tile_x, tile_y)
    local tile_data = LxCore.FileReader.read("mmaps/" .. filename)
    if not tile_data or #tile_data == 0 then
        return nil, nil
    end
    
    local parsed_tile = LxCore.Parser.parse_mmtile(tile_data)
    if not parsed_tile then
        return nil, nil
    end
    
    -- Check each polygon
    for poly_index = 1, #parsed_tile.polygons do
        local polygon = parsed_tile.polygons[poly_index]
        
        -- Get vertices for this polygon
        local polygon_vertices = {}
        local min_z = math.huge
        local max_z = -math.huge
        
        for i = 1, polygon.vertCount do
            local vert_index = polygon.verts[i]
            if vert_index and vert_index >= 0 and vert_index < #parsed_tile.vertices then
                local vertex = parsed_tile.vertices[vert_index + 1] -- Lua 1-based indexing
                if vertex and vertex.y then
                    polygon_vertices[i] = vertex
                    min_z = math.min(min_z, vertex.y)
                    max_z = math.max(max_z, vertex.y)
                end
            end
        end
        
        -- Only check polygons with valid vertices
        if #polygon_vertices > 0 and min_z ~= math.huge and max_z ~= -math.huge then
            -- First check if point is inside polygon using correct coordinate mapping
            -- Game(X,Y,Z) -> Mesh(X,Z,Y), so we use (game_x, game_y) for 2D polygon check
            if MeshManager.point_in_polygon(x, y, polygon_vertices) then
                -- If inside polygon bounds, check if height matches using core API
                local pos_vec3 = vec3.new(x, y, z)
                local polygon_height = core.get_height_for_position(pos_vec3)
                if math.abs(z - polygon_height) <= z_tolerance then
                    return poly_index, polygon
                end
            end
        end
    end
    
    return nil, nil
end

--- Load a 3x3 grid of tiles around the given center tile
---@param continent_id number The continent ID
---@param center_x number Center tile X coordinate
---@param center_y number Center tile Y coordinate
---@return table Table of loaded tiles by filename
function MeshManager.load_tile_grid(continent_id, center_x, center_y)
    local tiles = {}
    
    -- Load 3x3 grid (center tile + 8 neighbors)
    for dx = -1, 1 do
        for dy = -1, 1 do
            local tile_x = center_x + dx
            local tile_y = center_y + dy
            
            -- Clamp to valid tile range 0-63
            if tile_x >= 0 and tile_x <= 63 and tile_y >= 0 and tile_y <= 63 then
                local filename = MeshManager.get_mmtile_filename(continent_id, tile_x, tile_y)
                local tile_data = LxCore.FileReader.read("mmaps/" .. filename)
                
                if tile_data and #tile_data > 0 then
                    local parsed_tile = LxCore.Parser.parse_mmtile(tile_data)
                    if parsed_tile then
                        tiles[filename] = {
                            tile_x = tile_x,
                            tile_y = tile_y,
                            data = parsed_tile
                        }
                    end
                end
            end
        end
    end
    
    return tiles
end

--- Find which polygon contains the given position (improved with multi-tile support)
---@param x number World X coordinate
---@param y number World Y coordinate
---@param z number World Z coordinate
---@param z_tolerance number Z tolerance in yards (default 0.5)
---@return number|nil, table|nil, string|nil Polygon index, polygon data, and tile filename, or nil if not found
function MeshManager.find_polygon_at_position_advanced(x, y, z, z_tolerance)
    z_tolerance = z_tolerance or 0.5
    
    if not current_continent_id then
        return nil, nil, nil
    end
    
    -- Get current tile
    local center_x, center_y = MeshManager.get_tile_for_position(x, y)
    if not center_x or not center_y then
        return nil, nil, nil
    end
    
    -- Use cached tile grid if available, otherwise load on demand
    local tiles = current_tile_grid
    if not tiles or not next(tiles) or 
       current_tile_center.x ~= center_x or current_tile_center.y ~= center_y then
        tiles = MeshManager.load_tile_grid(current_continent_id, center_x, center_y)
    end
    
    -- Create combined vertex array from all tiles
    local all_vertices = {}
    local vertex_offset = 0
    local tile_vertex_offsets = {}
    
    -- First pass: collect all vertices and track offsets
    for filename, tile_info in pairs(tiles) do
        tile_vertex_offsets[filename] = vertex_offset
        
        for i, vertex in ipairs(tile_info.data.vertices) do
            all_vertices[vertex_offset + i] = vertex
        end
        
        vertex_offset = vertex_offset + #tile_info.data.vertices
    end
    
    -- Second pass: check polygons in center tile with full vertex access
    local center_filename = MeshManager.get_mmtile_filename(current_continent_id, center_x, center_y)
    local center_tile = tiles[center_filename]
    
    if not center_tile then
        return nil, nil, nil
    end
    
    -- Check each polygon in center tile
    for poly_index = 1, #center_tile.data.polygons do
        local polygon = center_tile.data.polygons[poly_index]
        
        -- Get vertices for this polygon using full vertex array
        local polygon_vertices = {}
        local min_z = math.huge
        local max_z = -math.huge
        
        for i = 1, polygon.vertCount do
            local vert_index = polygon.verts[i]
            if vert_index and vert_index >= 0 then
                local vertex = all_vertices[vert_index + 1] -- Lua 1-based indexing
                if vertex and vertex.y then
                    polygon_vertices[i] = vertex
                    min_z = math.min(min_z, vertex.y)
                    max_z = math.max(max_z, vertex.y)
                end
            end
        end
        
        -- Only check polygons with valid vertices
        if #polygon_vertices > 0 and min_z ~= math.huge and max_z ~= -math.huge then
            -- First check if point is inside polygon using correct coordinate mapping
            -- Game(X,Y,Z) -> Mesh(X,Z,Y), so we use (game_x, game_y) for 2D polygon check
            if MeshManager.point_in_polygon(x, y, polygon_vertices) then
                -- If inside polygon bounds, check if height matches using core API
                local pos_vec3 = vec3.new(x, y, z)
                local polygon_height = core.get_height_for_position(pos_vec3)
                if math.abs(z - polygon_height) <= z_tolerance then
                    return poly_index, polygon, center_filename
                end
            end
        end
    end
    
    return nil, nil, nil
end

--- Find polygon using only current tile vertices (no multi-tile support)
---@param x number World X coordinate
---@param y number World Y coordinate
---@param z number World Z coordinate
---@param z_tolerance number Z tolerance in yards (default 0.5)
---@return number|nil, table|nil Polygon index and polygon data, or nil if not found
function MeshManager.find_polygon_single_tile(x, y, z, z_tolerance)
    z_tolerance = z_tolerance or 5.0  -- Increase default tolerance
    
    if not current_continent_id then
        return nil, nil
    end
    
    -- Get current tile
    local tile_x, tile_y = MeshManager.get_tile_for_position(x, y)
    if not tile_x or not tile_y then
        return nil, nil
    end
    
    -- Load only the current tile
    local filename = MeshManager.get_mmtile_filename(current_continent_id, tile_x, tile_y)
    local tile_data = LxCore.FileReader.read("mmaps/" .. filename)
    if not tile_data or #tile_data == 0 then
        return nil, nil
    end
    
    local parsed_tile = LxCore.Parser.parse_mmtile(tile_data)
    if not parsed_tile then
        return nil, nil
    end
    
    -- Check each polygon using only vertices from this tile
    log.write("Scanning " .. #parsed_tile.polygons .. " polygons for player position (" .. 
             string.format("%.2f", x) .. ", " .. string.format("%.2f", y) .. ", " .. string.format("%.2f", z) .. ")")
    
    -- Debug: Check if position is within tile bounds
    local bounds = parsed_tile.header
    log.write("Tile bounds: X[" .. string.format("%.2f", bounds.bmin_x) .. ", " .. string.format("%.2f", bounds.bmax_x) .. "]")
    log.write("            Y[" .. string.format("%.2f", bounds.bmin_y) .. ", " .. string.format("%.2f", bounds.bmax_y) .. "]")
    log.write("            Z[" .. string.format("%.2f", bounds.bmin_z) .. ", " .. string.format("%.2f", bounds.bmax_z) .. "]")
    
    local in_x = x >= bounds.bmin_x and x <= bounds.bmax_x
    local in_y = y >= bounds.bmin_z and y <= bounds.bmax_z  -- Game Y maps to mesh Z
    local in_z = z >= bounds.bmin_y and z <= bounds.bmax_y  -- Game Z maps to mesh Y
    
    log.write("Position in bounds: X=" .. tostring(in_x) .. ", Y=" .. tostring(in_y) .. ", Z=" .. tostring(in_z))
    
    for poly_index = 1, #parsed_tile.polygons do
        local polygon = parsed_tile.polygons[poly_index]
        
        -- Skip obviously invalid polygons
        if polygon.vertCount <= 6 and polygon.vertCount > 0 then
            -- Get vertices for this polygon from current tile only
            local polygon_vertices = {}
            local min_z = math.huge
            local max_z = -math.huge
            
            for i = 1, polygon.vertCount do
                local vert_index = polygon.verts[i]
                
                -- Debug vertex indices for first few polygons
                if poly_index <= 3 then
                    log.write("Polygon " .. poly_index .. " vertex " .. i .. " index: " .. tostring(vert_index) .. " (total vertices: " .. #parsed_tile.vertices .. ")")
                end
                
                -- Try direct index first
                if vert_index and vert_index >= 0 and vert_index < #parsed_tile.vertices then
                    local vertex = parsed_tile.vertices[vert_index + 1] -- Lua 1-based indexing
                    if vertex then
                        polygon_vertices[i] = vertex
                        min_z = math.min(min_z, vertex.y)  -- mesh Y is height
                        max_z = math.max(max_z, vertex.y)
                        
                        -- Debug first polygon's vertices
                        if poly_index <= 3 and i == 1 then
                            log.write("Polygon " .. poly_index .. " first vertex: index=" .. vert_index .. 
                                     ", pos=(" .. string.format("%.2f", vertex.x) .. ", " .. 
                                     string.format("%.2f", vertex.y) .. ", " .. 
                                     string.format("%.2f", vertex.z) .. ")")
                        end
                    end
                else
                    -- Debug why we can't find the vertex
                    if poly_index <= 3 then
                        log.write("Cannot find vertex " .. vert_index .. " for polygon " .. poly_index .. " (vertices array size: " .. #parsed_tile.vertices .. ")")
                    end
                end
            end
            
            -- Only check polygons where ALL vertices are available in current tile
            if #polygon_vertices == polygon.vertCount and min_z ~= math.huge and max_z ~= -math.huge then
                -- Debug: log polygon being checked
                if poly_index <= 5 then -- Only log first 5 polygons to avoid spam
                    log.write("Checking polygon " .. poly_index .. ": vertCount=" .. polygon.vertCount .. 
                             ", vertices_found=" .. #polygon_vertices .. 
                             ", height_range=[" .. string.format("%.2f", min_z) .. " to " .. string.format("%.2f", max_z) .. "]")
                end
                
                -- First check if point is inside polygon using correct coordinate mapping
                -- Game(X,Y,Z) -> Mesh(X,Z,Y), so we use (game_x, game_y) for 2D polygon check
                if MeshManager.point_in_polygon(x, y, polygon_vertices) then
                    log.write("Point inside polygon " .. poly_index .. " (2D check passed)")
                    
                    -- If inside polygon bounds, check if height matches using core API
                    local pos_vec3 = vec3.new(x, y, z)
                    local polygon_height = core.get_height_for_position(pos_vec3)
                    local height_diff = math.abs(z - polygon_height)
                    
                    log.write("Height check: Player Z=" .. string.format("%.2f", z) .. 
                             ", Polygon height=" .. string.format("%.2f", polygon_height) .. 
                             ", Difference=" .. string.format("%.2f", height_diff) .. 
                             ", Tolerance=" .. string.format("%.2f", z_tolerance))
                    
                    if height_diff <= z_tolerance then
                        log.write("✓ Found matching polygon " .. poly_index)
                        return poly_index, polygon
                    else
                        log.write("✗ Height mismatch for polygon " .. poly_index)
                    end
                end
            end
        else
            if poly_index <= 5 then
                log.write("Skipping polygon " .. poly_index .. " - invalid vertCount: " .. polygon.vertCount)
            end
        end
    end
    
    return nil, nil
end

--- Get current player polygon information (single tile only)
---@return table|nil Information about the current polygon or nil if not found
function MeshManager.get_current_player_polygon()
    local player = core.object_manager.get_local_player()
    if not player then
        return nil
    end
    
    local pos = player:get_position()
    local poly_index, polygon = MeshManager.find_polygon_single_tile(pos.x, pos.y, pos.z, 0.5)
    
    if poly_index and polygon then
        local tile_x, tile_y = MeshManager.get_tile_for_position(pos.x, pos.y)
        return {
            index = poly_index - 1, -- Convert back to 0-based for display
            polygon = polygon,
            player_pos = {x = pos.x, y = pos.y, z = pos.z},
            tile_x = tile_x,
            tile_y = tile_y,
            vertices_available = polygon.vertCount, -- How many vertices we could resolve
            vertices_needed = polygon.vertCount     -- How many the polygon needs
        }
    end
    
    return nil
end


return MeshManager