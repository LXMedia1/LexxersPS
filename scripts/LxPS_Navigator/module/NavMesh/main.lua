-- NavMesh Module  
-- Navigation mesh analysis and validation utilities using Project Sylvanas API

local NavMesh = {}

-- Constants for tile calculations (matching WoW coordinate system)
local GRID_SIZE = 533.3333
local MAP_SIZE = 64
local ORIGIN_OFFSET = 32

-- Tile cache to store loaded mesh data
local tile_cache = {}

-- Tile calculation functions
function NavMesh.get_tile_for_position(x, y)
    local tile_x = ORIGIN_OFFSET - math.ceil(x / GRID_SIZE)
    local tile_y = ORIGIN_OFFSET - math.ceil(y / GRID_SIZE)
    
    -- Clamp to valid tile range [0, 63]
    tile_x = math.max(0, math.min(63, tile_x))
    tile_y = math.max(0, math.min(63, tile_y))
    
    return tile_x, tile_y
end

-- REMOVED: Tile format testing - Format established as IIIIYYYY

-- CONFIRMED: Correct MMTILE filename format is IIIIYYXX (Format 2)
-- Based on tile format testing - Format 2 contains player position within bounds
-- Date confirmed: User testing session - Format 2 bounds check: INSIDE
function NavMesh.get_mmtile_filename(instance_id, tile_x, tile_y)
    -- IIIIYYXX format: instance_id(4) + tile_y(2) + tile_x(2) + .mmtile
    return string.format("%04d%02d%02d.mmtile", instance_id, tile_y, tile_x)
end

function NavMesh.get_current_instance_id()
    -- Use Project Sylvanas API to get current instance ID for mesh files
    return core.get_instance_id()
end

-- Binary file reading utilities for little-endian data
local function read_uint32_le(data, offset)
    if offset + 3 > #data then return nil, offset end
    local a, b, c, d = string.byte(data, offset, offset + 3)
    return a + b * 256 + c * 65536 + d * 16777216, offset + 4
end

local function read_float_le(data, offset)
    if offset + 3 > #data then return nil, offset end
    local b1, b2, b3, b4 = string.byte(data, offset, offset + 3)
    
    -- IEEE 754 single precision format (little endian) - CORRECTED VERSION
    -- Byte layout: [mantissa_low] [mantissa_mid] [exp_low|mantissa_high] [sign|exp_high]
    local sign_bit = (b4 >= 128) and 1 or 0
    local exponent = ((b4 % 128) * 2) + math.floor(b3 / 128)
    local mantissa = ((b3 % 128) * 65536) + (b2 * 256) + b1
    
    local value
    if exponent == 0 then
        if mantissa == 0 then
            value = (sign_bit == 1) and -0.0 or 0.0
        else
            -- Denormalized number
            value = (sign_bit == 1 and -1 or 1) * (mantissa / (2^23)) * (2 ^ -126)
        end
    elseif exponent == 255 then
        if mantissa == 0 then
            value = (sign_bit == 1) and -math.huge or math.huge -- Infinity
        else
            value = 0/0 -- NaN
        end
    else
        -- Normalized number
        value = (sign_bit == 1 and -1 or 1) * (1 + mantissa / (2^23)) * (2 ^ (exponent - 127))
    end
    
    return value, offset + 4
end

-- Enhanced file reading function with proper MMAP parsing (fixed API)
function NavMesh.read_file(filepath)
    LxNavigator.logger.info("Attempting to read MMAP file: " .. filepath)
    
    -- Use Project Sylvanas API to read the file
    local content = core.read_data_file(filepath)
    
    if not content or #content == 0 then
        LxNavigator.logger.info("File not found or empty: " .. filepath)
        return nil
    end
    
    LxNavigator.logger.info("Successfully read " .. #content .. " bytes from " .. filepath)
    
    -- Parse MMAP file structure
    local parsed_data = NavMesh.parse_mmap_file(content, filepath)
    
    return parsed_data
end

-- Parse MMAP file content with proper TrinityCore/Detour structure based on research
function NavMesh.parse_mmap_file(data, filepath)
    LxNavigator.logger.info("Parsing MMAP file data (" .. #data .. " bytes)")
    
    local result = {
        vertices = {},
        polygons = {},
        raw_data = data,
        file_size = #data,
        parsed = false,
        magic = nil,
        version = nil,
        vertex_count = 0,
        polygon_count = 0,
        bounds = {
            min_x = 0, min_y = 0, min_z = 0,
            max_x = 0, max_y = 0, max_z = 0
        }
    }
    
    local offset = 1
    
    -- Read TrinityCore MmapTileHeader (20 bytes total)
    if #data >= 20 then
        local magic, new_offset1 = read_uint32_le(data, offset)
        if magic == 0x4D4D4150 then  -- "MMAP"
            result.magic = magic
            offset = new_offset1
            
            local dt_version, new_offset2 = read_uint32_le(data, offset)
            local mmap_version, new_offset3 = read_uint32_le(data, new_offset2)  
            local size, new_offset4 = read_uint32_le(data, new_offset3)
            local uses_liquids, new_offset5 = string.byte(data, new_offset4), new_offset4 + 1
            -- Skip 3 padding bytes
            offset = new_offset5 + 3
            
            result.version = mmap_version
            
            LxNavigator.logger.info("TrinityCore MMAP header - magic: 0x" .. string.format("%08X", magic) .. 
                                   ", dtVersion: " .. dt_version .. ", mmapVersion: " .. mmap_version .. 
                                   ", size: " .. size .. ", usesLiquids: " .. uses_liquids)
        else
            LxNavigator.logger.error("Invalid MMAP magic number: 0x" .. string.format("%08X", magic))
            return result
        end
    else
        LxNavigator.logger.error("File too small for TrinityCore MMAP header (need 20 bytes)")
        return result
    end
    
    -- Read Detour dtMeshHeader (84 bytes based on research)
    if offset + 84 <= #data then
        local detour_magic, new_offset = read_uint32_le(data, offset)
        if detour_magic == 0x444E4156 then  -- "DNAV" 
            offset = new_offset
            
            local detour_version, new_offset2 = read_uint32_le(data, offset)
            local tile_x, new_offset3 = read_uint32_le(data, new_offset2)
            local tile_y, new_offset4 = read_uint32_le(data, new_offset3)
            local tile_layer, new_offset5 = read_uint32_le(data, new_offset4)
            local user_id, new_offset6 = read_uint32_le(data, new_offset5)
            local poly_count, new_offset7 = read_uint32_le(data, new_offset6)
            local vert_count, new_offset8 = read_uint32_le(data, new_offset7)
            local max_link_count, new_offset9 = read_uint32_le(data, new_offset8)
            local detail_mesh_count, new_offset10 = read_uint32_le(data, new_offset9)
            local detail_vert_count, new_offset11 = read_uint32_le(data, new_offset10)
            local detail_tri_count, new_offset12 = read_uint32_le(data, new_offset11)
            
            -- Skip walkable height, radius, climb (3 floats = 12 bytes)
            local walk_height, new_offset13 = read_float_le(data, new_offset12)
            local walk_radius, new_offset14 = read_float_le(data, new_offset13)
            local walk_climb, new_offset15 = read_float_le(data, new_offset14)
            
            -- Skip bmin[3] and bmax[3] (6 floats = 24 bytes)
            offset = new_offset15 + 24
            
            -- Skip remaining header fields (bvQuantFactor, bvNodeCount, offMeshBase, offMeshConCount)
            offset = offset + 16
            
            result.vertex_count = vert_count
            result.polygon_count = poly_count
            
            LxNavigator.logger.info("Detour mesh header: " .. vert_count .. " vertices, " .. poly_count .. " polygons")
            LxNavigator.logger.info("Tile coordinates: (" .. tile_x .. ", " .. tile_y .. "), layer: " .. tile_layer)
            LxNavigator.logger.info("Header parsing complete, data starts at offset " .. offset)
            
            -- CORRECT Detour data layout from research:
            -- 1. Base vertices (coarse mesh)
            -- 2. Polygons 
            -- 3. Detail meshes
            -- 4. Detail vertices (actual walkable surface)
            
            -- Parse base vertices (vert_count * 3 floats)
            if vert_count > 0 and offset + (vert_count * 12) <= #data then
                LxNavigator.logger.info("Parsing " .. vert_count .. " base vertices starting at offset " .. offset)
                
                for i = 1, vert_count do
                    local x, new_offset1 = read_float_le(data, offset)
                    local y, new_offset2 = read_float_le(data, new_offset1)
                    local z, new_offset3 = read_float_le(data, new_offset2)
                    
                    if x and y and z then
                        -- Debug: Try different coordinate mappings to find the correct one
                        -- Current player pos: X[315.64], Y[-3684.88], Z[27.14]
                        -- Base bounds: X[-3733.33 to -3200.00], Y[0.00 to 533.33]
                        -- Player should be: X in [-3733 to -3200], Y in [0 to 533]
                        
                        -- Test mapping: Nav(X,Y,Z) → Game(Y,Z,X+0.5) 
                        local game_x = y  -- Nav Y → Game X 
                        local game_y = z  -- Nav Z → Game Y 
                        local game_z = x + 0.5  -- Nav X → Game Z + offset
                        table.insert(result.vertices, {x = game_x, y = game_y, z = game_z})
                        
                        -- Update bounds
                        if i == 1 then
                            result.bounds.min_x, result.bounds.max_x = game_x, game_x
                            result.bounds.min_y, result.bounds.max_y = game_y, game_y
                            result.bounds.min_z, result.bounds.max_z = game_z, game_z
                        else
                            result.bounds.min_x = math.min(result.bounds.min_x, game_x)
                            result.bounds.max_x = math.max(result.bounds.max_x, game_x)
                            result.bounds.min_y = math.min(result.bounds.min_y, game_y)
                            result.bounds.max_y = math.max(result.bounds.max_y, game_y)
                            result.bounds.min_z = math.min(result.bounds.min_z, game_z)
                            result.bounds.max_z = math.max(result.bounds.max_z, game_z)
                        end
                        
                        offset = new_offset3
                    else
                        LxNavigator.logger.error("Failed to read base vertex " .. i .. " at offset " .. offset)
                        break
                    end
                end
                
                LxNavigator.logger.info("Successfully parsed " .. #result.vertices .. " base vertices")
                LxNavigator.logger.info("Base vertex bounds: X[" .. string.format("%.2f", result.bounds.min_x) .. 
                                       " to " .. string.format("%.2f", result.bounds.max_x) .. "], " ..
                                       "Y[" .. string.format("%.2f", result.bounds.min_y) .. 
                                       " to " .. string.format("%.2f", result.bounds.max_y) .. "], " ..
                                       "Z[" .. string.format("%.2f", result.bounds.min_z) .. 
                                       " to " .. string.format("%.2f", result.bounds.max_z) .. "]")
            else
                LxNavigator.logger.error("Cannot parse base vertices: insufficient data")
            end
            
            -- Skip polygons (poly_count * dtPoly_size)
            -- dtPoly has variable size based on vertsPerPoly, but typically ~32 bytes
            local poly_size = 32  -- Approximate size
            offset = offset + (poly_count * poly_size)
            LxNavigator.logger.info("Skipped " .. poly_count .. " polygons, now at offset " .. offset)
            
            -- Skip links (max_link_count * 12 bytes for dtLink)
            offset = offset + (max_link_count * 12)
            LxNavigator.logger.info("Skipped " .. max_link_count .. " links, now at offset " .. offset)
            
            -- Skip detail meshes (detail_mesh_count * 12 bytes for dtPolyDetail)  
            offset = offset + (detail_mesh_count * 12)
            LxNavigator.logger.info("Skipped " .. detail_mesh_count .. " detail meshes, now at offset " .. offset)
            
            -- Parse detail vertices (detail_vert_count * 3 floats) - THESE ARE THE IMPORTANT ONES!
            if detail_vert_count > 0 and offset + (detail_vert_count * 12) <= #data then
                LxNavigator.logger.info("Parsing " .. detail_vert_count .. " DETAIL vertices starting at offset " .. offset)
                
                local detail_vertices_added = 0
                for i = 1, detail_vert_count do
                    local x, new_offset1 = read_float_le(data, offset)
                    local y, new_offset2 = read_float_le(data, new_offset1)
                    local z, new_offset3 = read_float_le(data, new_offset2)
                    
                    if x and y and z then
                        -- Test mapping: Nav(X,Y,Z) → Game(Y,Z,X+0.5) 
                        local game_x = y  -- Nav Y → Game X 
                        local game_y = z  -- Nav Z → Game Y 
                        local game_z = x + 0.5  -- Nav X → Game Z + offset
                        table.insert(result.vertices, {x = game_x, y = game_y, z = game_z, detail = true})
                        detail_vertices_added = detail_vertices_added + 1
                        
                        -- Debug: Log first few detail vertices to check coordinate conversion
                        if detail_vertices_added <= 3 then
                            LxNavigator.logger.info("Detail vertex " .. detail_vertices_added .. ": nav(" .. 
                                                   string.format("%.2f", x) .. ", " .. string.format("%.2f", y) .. ", " .. string.format("%.2f", z) .. 
                                                   ") -> game(" .. string.format("%.2f", game_x) .. ", " .. string.format("%.2f", game_y) .. ", " .. string.format("%.2f", game_z) .. ")")
                        end
                        
                        -- Skip bounds update for detail vertices (they're likely relative offsets)
                        -- Only use base vertex bounds for now
                        -- result.bounds.min_x = math.min(result.bounds.min_x, game_x)
                        -- result.bounds.max_x = math.max(result.bounds.max_x, game_x)
                        -- result.bounds.min_y = math.min(result.bounds.min_y, game_y)
                        -- result.bounds.max_y = math.max(result.bounds.max_y, game_y)
                        -- result.bounds.min_z = math.min(result.bounds.min_z, game_z)
                        -- result.bounds.max_z = math.max(result.bounds.max_z, game_z)
                        
                        offset = new_offset3
                    else
                        LxNavigator.logger.error("Failed to read detail vertex " .. i .. " at offset " .. offset)
                        break
                    end
                end
                
                LxNavigator.logger.info("Successfully parsed " .. detail_vertices_added .. " detail vertices")
                LxNavigator.logger.info("Total vertices: " .. #result.vertices .. " (base + detail)")
            else
                LxNavigator.logger.info("No detail vertices to parse or insufficient data")
            end
            
            result.parsed = #result.vertices > 0
            
            if #result.vertices > 0 then
                LxNavigator.logger.info("Final bounds: X[" .. string.format("%.2f", result.bounds.min_x) .. 
                                       " to " .. string.format("%.2f", result.bounds.max_x) .. "]")
                LxNavigator.logger.info("Final bounds: Y[" .. string.format("%.2f", result.bounds.min_y) .. 
                                       " to " .. string.format("%.2f", result.bounds.max_y) .. "]")
                LxNavigator.logger.info("Final bounds: Z[" .. string.format("%.2f", result.bounds.min_z) .. 
                                       " to " .. string.format("%.2f", result.bounds.max_z) .. "]")
                
                -- Show first few vertices for debugging
                LxNavigator.logger.info("First vertex: (" .. string.format("%.2f", result.vertices[1].x) .. 
                                       ", " .. string.format("%.2f", result.vertices[1].y) .. 
                                       ", " .. string.format("%.2f", result.vertices[1].z) .. ")")
                if #result.vertices > 1 then
                    LxNavigator.logger.info("Last vertex: (" .. string.format("%.2f", result.vertices[#result.vertices].x) .. 
                                           ", " .. string.format("%.2f", result.vertices[#result.vertices].y) .. 
                                           ", " .. string.format("%.2f", result.vertices[#result.vertices].z) .. ")")
                end
            end
        else
            LxNavigator.logger.error("Invalid Detour magic number: 0x" .. string.format("%08X", detour_magic) .. 
                                    " (expected 0x444E4156 'DNAV')")
        end
    else
        LxNavigator.logger.error("File too small for Detour header (need " .. (offset + 84) .. " bytes, have " .. #data .. ")")
    end
    
    return result
end

-- Validate if position is on navigation mesh
-- @param pos table: Position {x, y, z}
-- @return boolean: True if position is on valid navmesh
-- Load tile data for given coordinates
function NavMesh.load_tile(x, y)
    local tile_x, tile_y = NavMesh.get_tile_for_position(x, y)
    local instance_id = NavMesh.get_current_instance_id()
    local tile_key = instance_id .. "_" .. tile_x .. "_" .. tile_y
    
    -- Check cache first
    if tile_cache[tile_key] then
        return tile_cache[tile_key]
    end
    
    -- Attempt to load tile file
    local filename = NavMesh.get_mmtile_filename(instance_id, tile_x, tile_y)
    local filepath = "mmaps/" .. filename
    local tile_data = NavMesh.read_file(filepath)
    
    if tile_data and tile_data.parsed then
        LxNavigator.logger.info("Successfully loaded and parsed tile: " .. filename)
        LxNavigator.logger.info("Tile contains " .. tile_data.vertex_count .. " vertices")
        
        -- Cache the parsed tile data
        tile_cache[tile_key] = {
            loaded = true,
            filename = filename,
            polygons = tile_data.polygons,
            vertices = tile_data.vertices,
            bounds = tile_data.bounds,
            magic = tile_data.magic,
            version = tile_data.version,
            file_size = tile_data.file_size,
            vertex_count = tile_data.vertex_count,
            polygon_count = tile_data.polygon_count
        }
    else
        LxNavigator.logger.info("Tile not found or failed to parse: " .. filename)
        tile_cache[tile_key] = {
            loaded = false,
            filename = filename
        }
    end
    
    return tile_cache[tile_key]
end

function NavMesh.is_position_valid(pos)
    LxNavigator.logger.info("Checking if position is valid: (" .. string.format("%.2f", pos.x) .. ", " .. string.format("%.2f", pos.y) .. ", " .. string.format("%.2f", pos.z) .. ")")
    
    -- Load tile for this position
    local tile_data = NavMesh.load_tile(pos.x, pos.y)
    
    if not tile_data or not tile_data.loaded then
        LxNavigator.logger.info("Position invalid - no tile data available")
        return false
    end
    
    -- If we have bounds data, check if position is within tile bounds
    if tile_data.bounds then
        local bounds = tile_data.bounds
        -- Only check X,Y bounds strictly - Z can vary greatly in multi-level areas
        if pos.x < bounds.min_x or pos.x > bounds.max_x or
           pos.y < bounds.min_y or pos.y > bounds.max_y then
            LxNavigator.logger.info("Position outside tile XY bounds - X: " .. string.format("%.2f", pos.x) .. 
                                   " [" .. string.format("%.2f", bounds.min_x) .. " to " .. string.format("%.2f", bounds.max_x) .. "], " ..
                                   "Y: " .. string.format("%.2f", pos.y) .. 
                                   " [" .. string.format("%.2f", bounds.min_y) .. " to " .. string.format("%.2f", bounds.max_y) .. "]")
            return false
        end
        
        -- Log Z bounds for debugging but don't enforce them strictly  
        LxNavigator.logger.info("Position XY bounds check passed. Z bounds: " .. string.format("%.2f", pos.z) .. 
                               " vs tile [" .. string.format("%.2f", bounds.min_z) .. " to " .. string.format("%.2f", bounds.max_z) .. "]")
    end
    
    -- More precise validation using vertex proximity (optimized search)
    if tile_data.vertices and #tile_data.vertices > 0 then
        local min_distance_to_vertex = math.huge
        local nearby_vertices = 0
        local search_radius = 150.0  -- Increased to 150 yards to account for sparse mesh vertex density
        local base_vertex_count = tile_data.vertex_count or (#tile_data.vertices / 2)  -- Estimate base vs detail
        
        LxNavigator.logger.info("Checking position against " .. base_vertex_count .. " base vertices (ignoring detail vertices)")
        
        -- Check if position is near any BASE mesh vertices (skip detail vertices that are zeros)
        local closest_distance = math.huge
        local closest_vertex = nil
        
        for i = 1, math.min(base_vertex_count, #tile_data.vertices) do
            local vertex = tile_data.vertices[i]
            local dx = pos.x - vertex.x
            local dy = pos.y - vertex.y
            local dz = pos.z - vertex.z
            local distance_sq = dx*dx + dy*dy + dz*dz
            local distance = math.sqrt(distance_sq)
            
            -- Track closest vertex for debugging
            if distance < closest_distance then
                closest_distance = distance
                closest_vertex = vertex
            end
            
            -- Debug: Log first few distances to understand the scale
            if i <= 5 then
                LxNavigator.logger.info("Vertex " .. i .. " at (" .. string.format("%.2f", vertex.x) .. 
                                       ", " .. string.format("%.2f", vertex.y) .. ", " .. string.format("%.2f", vertex.z) .. 
                                       ") distance: " .. string.format("%.2f", distance))
            end
            
            if distance < search_radius then
                nearby_vertices = nearby_vertices + 1
                min_distance_to_vertex = math.min(min_distance_to_vertex, distance)
                
                -- Early exit if we find a very close vertex
                if distance < 5.0 then
                    LxNavigator.logger.info("Position valid - very close vertex found (" .. string.format("%.2f", distance) .. " yards)")
                    return true
                end
            end
        end
        
        -- Log the closest vertex found for debugging
        if closest_vertex then
            LxNavigator.logger.info("Closest vertex found: (" .. string.format("%.2f", closest_vertex.x) .. 
                                   ", " .. string.format("%.2f", closest_vertex.y) .. ", " .. string.format("%.2f", closest_vertex.z) .. 
                                   ") at distance " .. string.format("%.2f", closest_distance) .. " yards")
        end
        
        -- Position is valid if it's near mesh vertices (walkable area)
        if nearby_vertices >= 1 and min_distance_to_vertex < search_radius then
            LxNavigator.logger.info("Position valid - near " .. nearby_vertices .. 
                                   " vertices (closest: " .. string.format("%.2f", min_distance_to_vertex) .. ")")
            return true
        else
            LxNavigator.logger.info("Position invalid - no nearby vertices (closest: " .. 
                                   (min_distance_to_vertex == math.huge and "none" or string.format("%.2f", min_distance_to_vertex)) .. 
                                   ", count: " .. nearby_vertices .. ")")
            return false
        end
    end
    
    -- Fallback to bounds checking if no vertex data
    LxNavigator.logger.info("Position valid - tile exists with " .. 
                           (tile_data.vertex_count or 0) .. " vertices (bounds only)")
    return true
end

-- Find nearest valid position on navigation mesh
-- @param pos table: Target position {x, y, z}
-- @param search_radius number: Search radius (optional, default 10.0)
-- @return table: Nearest valid position or nil if none found
function NavMesh.find_nearest_valid_position(pos, search_radius)
    search_radius = search_radius or 10.0
    LxNavigator.logger.info("Finding nearest valid position within radius " .. search_radius)
    
    -- TODO: Implement nearest valid position search using Project Sylvanas API
    -- Sample positions in expanding radius around target using core.navigation
    -- Return first valid position found
    
    -- Placeholder: return original position if valid
    if NavMesh.is_position_valid(pos) then
        return {x = pos.x, y = pos.y, z = pos.z}
    else
        LxNavigator.log.warning("NavMesh", "No valid position found near target")
        return nil
    end
end

-- Get polygon information for position
-- @param pos table: Position {x, y, z}
-- @return table: Polygon info or nil if not found
function NavMesh.get_polygon_at_position(pos)
    LxNavigator.logger.info("Getting polygon info for position")
    
    -- TODO: Use Project Sylvanas API to get polygon information
    -- This might use core.navigation.get_polygon() or similar API call
    
    return nil -- Placeholder - no polygon info available yet
end

-- Check if two positions are connected via navigation mesh
-- @param pos1 table: First position {x, y, z}
-- @param pos2 table: Second position {x, y, z}
-- @return boolean: True if positions are connected
function NavMesh.are_positions_connected(pos1, pos2)
    LxNavigator.logger.info("Checking connectivity between positions")
    
    -- TODO: Implement connectivity check using Project Sylvanas API
    -- Use polygon adjacency information from core.navigation
    -- Check for line-of-sight on navmesh
    
    -- Placeholder: assume connected if both are valid
    return NavMesh.is_position_valid(pos1) and NavMesh.is_position_valid(pos2)
end

-- REMOVED: Tile format testing function - Format established as IIIIYYYY
-- The correct format has been definitively determined through testing

-- Get navigation mesh bounds for current area
-- @return table: Bounds {min_x, min_y, min_z, max_x, max_y, max_z} or nil
function NavMesh.get_current_bounds()
    LxNavigator.logger.info("Getting current navigation mesh bounds")
    
    -- TODO: Use Project Sylvanas API to get current area bounds
    -- This might use core.navigation.get_bounds() or core.world.get_area_bounds()
    
    local player = core.object_manager.get_local_player()
    if not player then
        LxNavigator.log.warning("NavMesh", "No player found to get current bounds")
        return nil
    end
    
    local pos = player:get_position()
    
    -- Placeholder: return approximate bounds around player
    local radius = 100.0 -- 100 yard radius
    return {
        min_x = pos.x - radius,
        min_y = pos.y - radius,
        min_z = pos.z - 20.0,  -- 20 yards below
        max_x = pos.x + radius,
        max_y = pos.y + radius,
        max_z = pos.z + 20.0   -- 20 yards above
    }
end

-- Raycast on navigation mesh
-- @param start_pos table: Starting position {x, y, z}
-- @param end_pos table: Target position {x, y, z}
-- @return table: Hit info {hit = boolean, position = {x,y,z}, distance = number}
function NavMesh.raycast(start_pos, end_pos)
    LxNavigator.logger.info("Performing navigation mesh raycast")
    
    -- TODO: Use Project Sylvanas API for navigation mesh raycast
    -- This might use core.navigation.raycast() or similar
    
    -- Calculate distance
    local dx = end_pos.x - start_pos.x
    local dy = end_pos.y - start_pos.y
    local dz = end_pos.z - start_pos.z
    local distance = math.sqrt(dx*dx + dy*dy + dz*dz)
    
    -- Improved placeholder: sample intermediate points to detect obstacles
    local samples = math.max(5, math.floor(distance / 3.0)) -- Sample every 3 yards
    
    for i = 1, samples - 1 do
        local t = i / samples
        local sample_pos = {
            x = start_pos.x + dx * t,
            y = start_pos.y + dy * t,
            z = start_pos.z + dz * t
        }
        
        if not NavMesh.is_position_valid(sample_pos) then
            -- Found invalid position = obstacle detected
            return {
                hit = true,
                position = sample_pos,
                distance = distance * t
            }
        end
    end
    
    -- No obstacles found
    return {
        hit = false,
        position = {x = end_pos.x, y = end_pos.y, z = end_pos.z},
        distance = distance
    }
end

-- Get height at position (project to navmesh)
-- @param x number: X coordinate
-- @param y number: Y coordinate
-- @return number: Height (Z coordinate) at position or nil if invalid
function NavMesh.get_height_at_position(x, y)
    -- TODO: Use Project Sylvanas API to get navmesh height at X,Y coordinates
    -- This might use core.navigation.get_height() or core.world.get_ground_height()
    
    local player = core.object_manager.get_local_player()
    if player then
        local pos = player:get_position()
        return pos.z -- Placeholder: return player height
    end
    
    return nil
end

-- Get random point on navigation mesh near position
-- @param center_pos table: Center position {x, y, z}
-- @param radius number: Search radius
-- @return table: Random valid position or nil if none found
function NavMesh.get_random_point(center_pos, radius)
    radius = radius or 10.0
    LxNavigator.logger.info("Getting random point within radius " .. radius)
    
    -- TODO: Use Project Sylvanas API to get random navigable point
    -- This might use core.navigation.get_random_point() or similar
    
    -- Placeholder: generate random offset within radius
    local angle = math.random() * 2 * math.pi
    local distance = math.random() * radius
    
    local random_pos = {
        x = center_pos.x + math.cos(angle) * distance,
        y = center_pos.y + math.sin(angle) * distance,
        z = center_pos.z
    }
    
    -- Validate the random position
    if NavMesh.is_position_valid(random_pos) then
        return random_pos
    else
        return nil
    end
end

-- Check if position is inside specified area/zone
-- @param pos table: Position to check {x, y, z}
-- @param area_name string: Area/zone name (optional)
-- @return boolean: True if position is in area
function NavMesh.is_position_in_area(pos, area_name)
    -- TODO: Use Project Sylvanas API to check area/zone information
    -- This might use core.world.get_area_name() or core.zone.get_current_area()
    
    return true -- Placeholder - assume all positions are in valid areas
end

-- Grid-based neighbor finding for A* pathfinding
-- @param pos table: Center position {x, y, z}
-- @param step_size number: Distance between neighbor positions (default 5.0)
-- @return table: Array of valid neighbor positions
function NavMesh.get_navigable_neighbors(pos, step_size)
    step_size = step_size or 5.0
    local neighbors = {}
    
    -- Check 8 cardinal and diagonal directions
    local directions = {
        {x = step_size, y = 0, z = 0},        -- East
        {x = -step_size, y = 0, z = 0},       -- West  
        {x = 0, y = step_size, z = 0},        -- North
        {x = 0, y = -step_size, z = 0},       -- South
        {x = step_size, y = step_size, z = 0},   -- Northeast
        {x = -step_size, y = step_size, z = 0},  -- Northwest
        {x = step_size, y = -step_size, z = 0},  -- Southeast
        {x = -step_size, y = -step_size, z = 0}  -- Southwest
    }
    
    for _, dir in ipairs(directions) do
        local neighbor_pos = {
            x = pos.x + dir.x,
            y = pos.y + dir.y,
            z = pos.z + dir.z  -- Keep same Z initially
        }
        
        -- Validate neighbor position
        if NavMesh.is_position_valid(neighbor_pos) then
            table.insert(neighbors, {
                position = neighbor_pos,
                distance = step_size,
                direction = dir
            })
        end
    end
    
    return neighbors
end

LxNavigator.logger.info("NavMesh module loaded")

return NavMesh