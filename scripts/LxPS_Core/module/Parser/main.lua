local Parser = {}

--- Read a 32-bit float from binary data
---@param data string The binary data
---@param pos number The current position in the data
---@return number, number The float value and new position
function Parser.read_f32(data, pos)
    local bytes = string.sub(data, pos, pos + 3)
    if #bytes < 4 then
        error("Not enough data to read f32 at position " .. pos)
    end
    
    local b1, b2, b3, b4 = string.byte(bytes, 1, 4)
    
    -- Convert bytes to 32-bit integer (little endian)
    local int_val = b1 + (b2 * 256) + (b3 * 65536) + (b4 * 16777216)
    
    -- Reinterpret as float using bit operations
    local sign = (b4 >= 128) and -1 or 1
    local exponent = ((b4 % 128) * 2) + math.floor(b3 / 128)
    local mantissa = ((b3 % 128) * 65536) + (b2 * 256) + b1
    
    local value
    if exponent == 0 then
        if mantissa == 0 then
            value = sign * 0.0
        else
            value = sign * mantissa * (2 ^ -149) -- Denormalized
        end
    elseif exponent == 255 then
        if mantissa == 0 then
            value = sign * math.huge -- Infinity
        else
            value = 0/0 -- NaN
        end
    else
        value = sign * (1 + mantissa / (2^23)) * (2 ^ (exponent - 127))
    end
    
    return value, pos + 4
end

--- Read a 32-bit unsigned integer from binary data
---@param data string The binary data
---@param pos number The current position in the data
---@return number, number The integer value and new position
function Parser.read_u32(data, pos)
    local bytes = string.sub(data, pos, pos + 3)
    if #bytes < 4 then
        error("Not enough data to read u32 at position " .. pos)
    end
    
    local b1, b2, b3, b4 = string.byte(bytes, 1, 4)
    local value = b1 + (b2 * 256) + (b3 * 65536) + (b4 * 16777216)
    
    return value, pos + 4
end

--- Read a 32-bit signed integer from binary data
---@param data string The binary data
---@param pos number The current position in the data
---@return number, number The integer value and new position
function Parser.read_i32(data, pos)
    local value, new_pos = Parser.read_u32(data, pos)
    -- Convert unsigned to signed if necessary
    if value >= 2147483648 then
        value = value - 4294967296
    end
    return value, new_pos
end

--- Read a 16-bit unsigned integer from binary data
---@param data string The binary data
---@param pos number The current position in the data
---@return number, number The integer value and new position
function Parser.read_u16(data, pos)
    local bytes = string.sub(data, pos, pos + 1)
    if #bytes < 2 then
        error("Not enough data to read u16 at position " .. pos)
    end
    
    local b1, b2 = string.byte(bytes, 1, 2)
    local value = b1 + (b2 * 256)
    
    return value, pos + 2
end

--- Read a 8-bit unsigned integer from binary data
---@param data string The binary data
---@param pos number The current position in the data
---@return number, number The integer value and new position
function Parser.read_u8(data, pos)
    local byte = string.sub(data, pos, pos)
    if #byte < 1 then
        error("Not enough data to read u8 at position " .. pos)
    end
    
    return string.byte(byte), pos + 1
end

--- MMAP object structure
---@class MMAP
---@field orig_x number Original X coordinate
---@field orig_y number Original Y coordinate
---@field orig_z number Original Z coordinate
---@field tile_width number Width of each tile
---@field tile_height number Height of each tile
---@field max_tiles number Maximum number of tiles
---@field max_polys number Maximum number of polygons
local MMAP = {}
MMAP.__index = MMAP

--- Create a new MMAP object
---@param orig_x number
---@param orig_y number
---@param orig_z number
---@param tile_width number
---@param tile_height number
---@param max_tiles number
---@param max_polys number
---@return MMAP
function MMAP.new(orig_x, orig_y, orig_z, tile_width, tile_height, max_tiles, max_polys)
    local mmap = {
        orig_x = orig_x,
        orig_y = orig_y,
        orig_z = orig_z,
        tile_width = tile_width,
        tile_height = tile_height,
        max_tiles = max_tiles,
        max_polys = max_polys
    }
    setmetatable(mmap, MMAP)
    return mmap
end

--- Parse mmap binary data
---@param data string The binary mmap data
---@return MMAP The parsed MMAP object
function Parser.parse_mmap(data)
    local pos = 1
    
    local orig_x, orig_y, orig_z, tile_width, tile_height, max_tiles, max_polys
    
    orig_x, pos = Parser.read_f32(data, pos)
    orig_y, pos = Parser.read_f32(data, pos)
    orig_z, pos = Parser.read_f32(data, pos)
    tile_width, pos = Parser.read_f32(data, pos)
    tile_height, pos = Parser.read_f32(data, pos)
    max_tiles, pos = Parser.read_u32(data, pos)
    max_polys, pos = Parser.read_u32(data, pos)
    
    return MMAP.new(orig_x, orig_y, orig_z, tile_width, tile_height, max_tiles, max_polys)
end

Parser.MMAP = MMAP

--- dtMeshHeader structure for navigation mesh tiles
---@class dtMeshHeader
---@field magic number Tile magic number
---@field version number Tile data format version
---@field x number The x-position of the tile within the grid
---@field y number The y-position of the tile within the grid
---@field layer number The layer of the tile
---@field userId number User defined id
---@field polyCount number Number of polygons
---@field vertCount number Number of vertices
---@field maxLinkCount number Number of allocated links
---@field detailMeshCount number Number of sub-meshes in detail mesh
---@field detailVertCount number Number of unique vertices in detail mesh
---@field detailTriCount number Number of triangles in detail mesh
---@field bvNodeCount number Number of bounding volume nodes
---@field offMeshConCount number Number of off-mesh connections
---@field offMeshBase number Index of first off-mesh connection polygon
---@field walkableHeight number Agent height
---@field walkableRadius number Agent radius
---@field walkableClimb number Agent max climb
---@field bmin_x number Min bounds X
---@field bmin_y number Min bounds Y
---@field bmin_z number Min bounds Z
---@field bmax_x number Max bounds X
---@field bmax_y number Max bounds Y
---@field bmax_z number Max bounds Z
---@field bvQuantFactor number Bounding volume quantization factor
local dtMeshHeader = {}
dtMeshHeader.__index = dtMeshHeader

--- Constants for Detour navigation mesh
local DT_NAVMESH_MAGIC = 0x444E4156  -- 'DNAV' = 'VAND' in little endian
local DT_NAVMESH_VERSION = 7

--- Parse dtMeshHeader from binary data
---@param data string The binary data
---@param pos number Starting position
---@return dtMeshHeader|nil, number The header and new position, or nil if invalid
function Parser.parse_mesh_header(data, pos)
    local header = {}
    local start_pos = pos
    local log = LxCore.Log("Parser")
    log.write_to_file("=== DNAV HEADER PARSING DEBUG ===")
    log.write_to_file("Starting DNAV header parse at position: " .. pos)
    
    -- Read all header fields
    header.magic, pos = Parser.read_i32(data, pos)
    header.version, pos = Parser.read_i32(data, pos)
    header.x, pos = Parser.read_i32(data, pos)
    header.y, pos = Parser.read_i32(data, pos)
    header.layer, pos = Parser.read_i32(data, pos)
    header.userId, pos = Parser.read_u32(data, pos)
    header.polyCount, pos = Parser.read_i32(data, pos)
    header.vertCount, pos = Parser.read_i32(data, pos)
    header.maxLinkCount, pos = Parser.read_i32(data, pos)
    header.detailMeshCount, pos = Parser.read_i32(data, pos)
    header.detailVertCount, pos = Parser.read_i32(data, pos)
    header.detailTriCount, pos = Parser.read_i32(data, pos)
    header.bvNodeCount, pos = Parser.read_i32(data, pos)
    header.offMeshConCount, pos = Parser.read_i32(data, pos)
    header.offMeshBase, pos = Parser.read_i32(data, pos)
    header.walkableHeight, pos = Parser.read_f32(data, pos)
    header.walkableRadius, pos = Parser.read_f32(data, pos)
    header.walkableClimb, pos = Parser.read_f32(data, pos)
    header.bmin_x, pos = Parser.read_f32(data, pos)
    header.bmin_y, pos = Parser.read_f32(data, pos)
    header.bmin_z, pos = Parser.read_f32(data, pos)
    header.bmax_x, pos = Parser.read_f32(data, pos)
    header.bmax_y, pos = Parser.read_f32(data, pos)
    header.bmax_z, pos = Parser.read_f32(data, pos)
    header.bvQuantFactor, pos = Parser.read_f32(data, pos)
    
    log.write_to_file("DNAV header read complete, final position: " .. pos)
    log.write_to_file("Total bytes read: " .. (pos - start_pos))
    log.write_to_file("Magic: 0x" .. string.format("%08X", header.magic))
    log.write_to_file("Version: " .. header.version)
    
    -- Validate magic and version
    if header.magic ~= DT_NAVMESH_MAGIC then
        log.write_to_file("ERROR: Invalid magic number")
        return nil, start_pos
    end
    
    if header.version ~= DT_NAVMESH_VERSION then
        log.write_to_file("ERROR: Invalid version")
        return nil, start_pos
    end
    
    log.write_to_file("DNAV header validation passed")
    setmetatable(header, dtMeshHeader)
    return header, pos
end

--- Data section structure
---@class DataSection
---@field magic string Section magic identifier
---@field version number Section version
---@field data_size number Size of section data
---@field data string Raw section data

--- MMTile object to hold parsed tile data
---@class MMTile
---@field header dtMeshHeader The tile header
---@field sections table<string, DataSection> Data sections by magic identifier
---@field data string Raw tile data
local MMTile = {}
MMTile.__index = MMTile

--- Parse a data section header
---@param data string The binary data
---@param pos number Starting position
---@return DataSection|nil, number The section and new position, or nil if invalid
function Parser.parse_section_header(data, pos)
    if pos + 12 > #data then
        return nil, pos
    end
    
    local section = {}
    local start_pos = pos
    
    -- Read magic (4 bytes)
    local magic_bytes = string.sub(data, pos, pos + 3)
    section.magic = magic_bytes
    pos = pos + 4
    
    -- Read version (4 bytes)
    section.version, pos = Parser.read_i32(data, pos)
    
    -- Read data size (4 bytes)
    section.data_size, pos = Parser.read_i32(data, pos)
    
    -- Read section data
    if pos + section.data_size > #data then
        return nil, start_pos
    end
    
    section.data = string.sub(data, pos, pos + section.data_size - 1)
    pos = pos + section.data_size
    
    return section, pos
end

--- Parse vertices from binary data
---@param data string The binary data
---@param pos number Starting position
---@param count number Number of vertices to read
---@param vertex_type string Type of vertices being parsed (for logging)
---@return table, number Array of vertices and new position
function Parser.parse_vertices(data, pos, count, vertex_type)
    vertex_type = vertex_type or "vertices"
    local vertices = {}
    local log = LxCore.Log("Parser")
    
    -- Debug first few bytes
    if count > 0 then
        local hex_bytes = {}
        for j = 1, math.min(48, #data - pos + 1) do
            hex_bytes[j] = string.format("%02X", string.byte(data, pos + j - 1))
        end
        log.write_to_file("First 48 bytes of " .. vertex_type .. " data: " .. table.concat(hex_bytes, " "))
    end
    
    for i = 1, count do
        local x, y, z
        x, pos = Parser.read_f32(data, pos)
        y, pos = Parser.read_f32(data, pos)
        z, pos = Parser.read_f32(data, pos)
        vertices[i] = {x = x, y = y, z = z}
        
        -- Debug first vertex in detail
        if i == 1 then
            log.write_to_file("First " .. vertex_type .. " raw values: x=" .. tostring(x) .. ", y=" .. tostring(y) .. ", z=" .. tostring(z))
        end
    end
    
    log.write_to_file("parse_vertices returning " .. #vertices .. " " .. vertex_type)
    return vertices, pos
end

--- Parse polygons from binary data
---@param data string The binary data
---@param pos number Starting position
---@param count number Number of polygons to read
---@return table, number Array of polygons and new position
--- Parse polygons from binary data.  The Detour ``dtPoly`` structure
-- contains a variable‑length array of vertex and neighbour indices.
-- The number of entries is determined by ``vertsPerPoly``.  This
-- function will read exactly ``vertsPerPoly`` vertices and neighbours
-- for each polygon.  The total size per polygon is ``4 * vertsPerPoly + 8``
-- bytes: 4 bytes for ``firstLink``, 2×``vertsPerPoly`` bytes for
-- ``verts``, 2×``vertsPerPoly`` bytes for ``neis``, 2 bytes for
-- ``flags``, and 1 byte each for ``vertCount`` and ``areaAndtype``.
--
-- @param data string The binary data
-- @param pos number Starting position
-- @param count number Number of polygons to read
-- @param vertsPerPoly number Number of vertices per polygon (6, 8, 10, 12)
-- @return table, number Array of polygons and new position
function Parser.parse_polygons(data, pos, count, vertsPerPoly)
    vertsPerPoly = vertsPerPoly or 6
    local polygons = {}
    local start_pos = pos
    for i = 1, count do
        local poly = {}
        local poly_start_pos = pos
        -- firstLink (4 bytes)
        poly.firstLink, pos = Parser.read_u32(data, pos)
        -- verts array (vertsPerPoly x 2 bytes)
        poly.verts = {}
        for j = 1, vertsPerPoly do
            poly.verts[j], pos = Parser.read_u16(data, pos)
        end
        -- neis array (vertsPerPoly x 2 bytes)
        poly.neis = {}
        for j = 1, vertsPerPoly do
            poly.neis[j], pos = Parser.read_u16(data, pos)
        end
        -- flags (2 bytes)
        poly.flags, pos = Parser.read_u16(data, pos)
        -- vertCount (1 byte)
        poly.vertCount, pos = Parser.read_u8(data, pos)
        -- areaAndtype (1 byte)
        poly.areaAndtype, pos = Parser.read_u8(data, pos)
        -- Clamp vertCount to [0, vertsPerPoly]
        if poly.vertCount > vertsPerPoly then
            poly.vertCount = vertsPerPoly
        end
        -- Debug: log the first few polygons
        if i <= 3 then
            local log = LxCore.Log("Parser")
            log.write_to_file("Polygon " .. i .. " debug:")
            log.write_to_file("  Start pos: " .. poly_start_pos)
            log.write_to_file("  End pos: " .. pos)
            log.write_to_file("  Bytes read: " .. (pos - poly_start_pos))
            log.write_to_file("  firstLink: " .. poly.firstLink)
            log.write_to_file("  flags: " .. poly.flags)
            log.write_to_file("  vertCount: " .. poly.vertCount .. " (max " .. vertsPerPoly .. ")")
            log.write_to_file("  areaAndtype: " .. poly.areaAndtype)
            log.write_to_file("")
        end
        polygons[i] = poly
    end
    local total_bytes = pos - start_pos
    return polygons, pos
end

--- Parse the MmapTileHeader (first 20 bytes)
---@param data string The binary data
---@param pos number Starting position
---@return table|nil, number The TrinityCore header and new position, or nil if invalid
function Parser.parse_mmap_tile_header(data, pos)
    if pos + 19 > #data then
        return nil, pos
    end
    
    local header = {}
    local start_pos = pos
    
    -- Read mmapMagic (4 bytes) - should be 'PAMM' = 0x50414D4D 
    header.mmapMagic, pos = Parser.read_u32(data, pos)
    if header.mmapMagic ~= 0x4D4D4150 then -- 'PAMM' in little endian
        return nil, start_pos
    end
    
    -- Read remaining fields
    header.dtVersion, pos = Parser.read_u32(data, pos)     -- DetourNavMesh version (7)
    header.mmapVersion, pos = Parser.read_u32(data, pos)   -- TrinityCore version (15 for 3.3.5)
    header.size, pos = Parser.read_u32(data, pos)          -- size of navmesh data
    header.usesLiquids, pos = Parser.read_u32(data, pos)   -- whether liquids included
    
    return header, pos
end

--- Parse dtLink array
---@param data string The binary data
---@param pos number Starting position
---@param count number Number of links to read
---@return table, number Array of links and new position
function Parser.parse_links(data, pos, count)
    local links = {}
    for i = 1, count do
        local link = {}
        -- dtLink for TrinityCore: ref (4 bytes), next (4 bytes), edge, side, bmin, bmax (1 byte each) = 12 bytes total
        link.ref, pos = Parser.read_u32(data, pos)  -- 32-bit ref (4 bytes)
        link.next, pos = Parser.read_u32(data, pos) -- 4 bytes
        link.edge, pos = Parser.read_u8(data, pos)  -- 1 byte
        link.side, pos = Parser.read_u8(data, pos)  -- 1 byte
        link.bmin, pos = Parser.read_u8(data, pos)  -- 1 byte
        link.bmax, pos = Parser.read_u8(data, pos)  -- 1 byte
        links[i] = link
    end
    return links, pos
end

--- Parse dtPolyDetail array
---@param data string The binary data
---@param pos number Starting position
---@param count number Number of detail meshes to read
---@return table, number Array of detail meshes and new position
function Parser.parse_poly_details(data, pos, count)
    local details = {}
    for i = 1, count do
        local detail = {}
        detail.vertBase, pos = Parser.read_u32(data, pos)
        detail.triBase, pos = Parser.read_u32(data, pos)
        detail.vertCount, pos = Parser.read_u8(data, pos)
        detail.triCount, pos = Parser.read_u8(data, pos)
        pos = pos + 2  -- padding
        details[i] = detail
    end
    return details, pos
end

--- Parse dtBVNode array
---@param data string The binary data
---@param pos number Starting position
---@param count number Number of BV nodes to read
---@return table, number Array of BV nodes and new position
function Parser.parse_bv_nodes(data, pos, count)
    local nodes = {}
    for i = 1, count do
        local node = {}
        -- Each node is 16 bytes: bmin[3], bmax[3] (6 shorts), i (int)
        node.bmin = {}
        node.bmax = {}
        for j = 1, 3 do
            node.bmin[j], pos = Parser.read_u16(data, pos)
        end
        for j = 1, 3 do
            node.bmax[j], pos = Parser.read_u16(data, pos)
        end
        node.i, pos = Parser.read_i32(data, pos)
        nodes[i] = node
    end
    return nodes, pos
end

--- Parse dtOffMeshConnection array
---@param data string The binary data
---@param pos number Starting position
---@param count number Number of off-mesh connections to read
---@return table, number Array of connections and new position
function Parser.parse_offmesh_connections(data, pos, count)
    local connections = {}
    for i = 1, count do
        local conn = {}
        -- pos (6 floats), rad (float), poly (short), flags, side, userId
        conn.pos = {}
        for j = 1, 6 do
            conn.pos[j], pos = Parser.read_f32(data, pos)
        end
        conn.rad, pos = Parser.read_f32(data, pos)
        conn.poly, pos = Parser.read_u16(data, pos)
        conn.flags, pos = Parser.read_u8(data, pos)
        conn.side, pos = Parser.read_u8(data, pos)
        conn.userId, pos = Parser.read_u32(data, pos)
        connections[i] = conn
    end
    return connections, pos
end

--- Parse detail triangles
---@param data string The binary data
---@param pos number Starting position
---@param count number Number of triangles to read
---@return table, number Array of triangles and new position
function Parser.parse_detail_triangles(data, pos, count)
    local triangles = {}
    local bytes_needed = count * 4
    
    -- Check if we have enough data
    if pos + bytes_needed - 1 > #data then
        local log = LxCore.Log("Parser")
        log.write_to_file("WARNING: Not enough data for detail triangles. Need " .. bytes_needed .. " bytes, but only " .. (#data - pos + 1) .. " bytes remaining")
        -- Parse as many as we can
        count = math.floor((#data - pos + 1) / 4)
        log.write_to_file("Parsing only " .. count .. " detail triangles instead")
    end
    
    for i = 1, count do
        local tri = {}
        tri.v1, pos = Parser.read_u8(data, pos)
        tri.v2, pos = Parser.read_u8(data, pos)
        tri.v3, pos = Parser.read_u8(data, pos)
        tri.flags, pos = Parser.read_u8(data, pos)
        triangles[i] = tri
    end
    return triangles, pos
end

--- Parse a complete mmtile file according to TrinityCore format
---@param data string The binary mmtile data
---@return MMTile|nil The parsed tile or nil if invalid
function Parser.parse_mmtile(data)
    local pos = 1
    local log = LxCore.Log("Parser")
    
    log.write_to_file("=== MMTILE PARSING DEBUG ===")
    log.write_to_file("Total file size: " .. #data .. " bytes")
    
    -- Parse the TrinityCore MmapTileHeader first (20 bytes)
    log.write_to_file("Parsing TrinityCore header at pos: " .. pos)
    local tc_header, new_pos = Parser.parse_mmap_tile_header(data, pos)
    if not tc_header then
        return nil
    end
    log.write_to_file("TrinityCore header parsed, new pos: " .. new_pos .. " (read " .. (new_pos - pos) .. " bytes)")
    
    pos = new_pos
    
    -- Parse the Detour dtMeshHeader (100 bytes)
    log.write_to_file("Parsing DNAV header at pos: " .. pos)
    local mesh_header, mesh_pos = Parser.parse_mesh_header(data, pos)
    if not mesh_header then
        return nil
    end
    log.write_to_file("DNAV header parsed, new pos: " .. mesh_pos .. " (read " .. (mesh_pos - pos) .. " bytes)")
    log.write_to_file("Expected DNAV header size: 100 bytes (25 fields * 4 bytes each)")
    
    pos = mesh_pos
    
    log.write_to_file("Starting data parsing at pos: " .. pos)
    log.write_to_file("Expected polygon start: pos " .. pos)
    log.write_to_file("Polygon count: " .. mesh_header.polyCount)
    -- Try to detect vertsPerPoly by attempting to parse with different values
    -- and checking if the resulting polygon count and structure makes sense
    local vertsPerPoly = 6  -- Default fallback
    local candidates = {6, 8, 10, 12}
    
    for _, candidate in ipairs(candidates) do
        local test_pos = pos
        local test_success = true
        local expected_poly_size = 4 + (candidate * 2) + (candidate * 2) + 2 + 1 + 1  -- 4*candidate + 8
        local total_poly_bytes = mesh_header.polyCount * expected_poly_size
        
        -- Check if we have enough data for this candidate
        if pos + total_poly_bytes <= #data then
            -- Try parsing a few polygons to validate
            for i = 1, math.min(3, mesh_header.polyCount) do
                if test_pos + expected_poly_size > #data then
                    test_success = false
                    break
                end
                
                -- Skip to vertCount position and check if it's reasonable
                local vertCount_pos = test_pos + 4 + (candidate * 4) + 2
                if vertCount_pos <= #data then
                    local vertCount = string.byte(data, vertCount_pos)
                    if vertCount > candidate or vertCount < 3 then
                        test_success = false
                        break
                    end
                end
                test_pos = test_pos + expected_poly_size
            end
            
            if test_success then
                vertsPerPoly = candidate
                log.write_to_file("Detected vertsPerPoly=" .. vertsPerPoly .. " for polygon parsing")
                break
            end
        end
    end

    -- Expected polygon bytes based on detected vertsPerPoly
    local expected_poly_bytes = mesh_header.polyCount * (4 * vertsPerPoly + 8)
    log.write_to_file("Expected polygon bytes based on vertsPerPoly: " .. expected_poly_bytes)

    -- Parse polygons first using detected vertsPerPoly
    local polygons = {}
    if mesh_header.polyCount > 0 then
        local poly_start = pos
        polygons, pos = Parser.parse_polygons(data, pos, mesh_header.polyCount, vertsPerPoly)
        local poly_bytes_read = pos - poly_start
        log.write_to_file("Polygon parsing completed: read " .. poly_bytes_read .. " bytes for " .. mesh_header.polyCount .. " polygons")
        if poly_bytes_read ~= expected_poly_bytes then
            log.write_to_file("WARNING: polygon data size mismatch. Expected " .. expected_poly_bytes .. ", got " .. poly_bytes_read)
            -- Do not throw error; continue parsing.
        end
    end
    
    -- Debug: Show first 32 bytes at link start as hex
    local hex_bytes = {}
    for i = 1, math.min(32, #data - pos + 1) do
        hex_bytes[i] = string.format("%02X", string.byte(data, pos + i - 1))
    end
    log.write_to_file("First 32 bytes at link start: " .. table.concat(hex_bytes, " "))
    
    -- Parse all data arrays in the correct order according to documentation
    local start_pos = pos
    
    -- Initialize all data structures
    local vertices = {}
    
    -- 2. dtLink array - maxLinkCount entries, 12 bytes each (TrinityCore 32-bit refs)
    local links = {}
    if mesh_header.maxLinkCount > 0 then
        local link_start = pos
        links, pos = Parser.parse_links(data, pos, mesh_header.maxLinkCount)
        local link_bytes = pos - link_start
        local expected_link_bytes = mesh_header.maxLinkCount * 12
        if link_bytes ~= expected_link_bytes then
            error("Link parsing size mismatch: read " .. link_bytes .. " bytes, expected " .. expected_link_bytes)
        end
    end
    
    -- 3. dtPolyDetail array - detailMeshCount entries, 12 bytes each
    local poly_details = {}
    if mesh_header.detailMeshCount > 0 then
        poly_details, pos = Parser.parse_poly_details(data, pos, mesh_header.detailMeshCount)
    end
    
    -- 4. dtBVNode array - bvNodeCount entries, 16 bytes each
    local bv_nodes = {}
    if mesh_header.bvNodeCount > 0 then
        bv_nodes, pos = Parser.parse_bv_nodes(data, pos, mesh_header.bvNodeCount)
    end
    
    -- 5. dtOffMeshConnection array - offMeshConCount entries, 36 bytes each
    local offmesh_connections = {}
    if mesh_header.offMeshConCount > 0 then
        offmesh_connections, pos = Parser.parse_offmesh_connections(data, pos, mesh_header.offMeshConCount)
    end
    
    -- 6. verts array - vertCount base vertices, 12 bytes each (3 floats)
    -- Note: vertices already declared at start of data parsing
    if mesh_header.vertCount > 0 then
        log.write_to_file("Parsing BASE vertices: " .. mesh_header.vertCount .. " vertices at position " .. pos)
        local vert_start = pos
        vertices, pos = Parser.parse_vertices(data, pos, mesh_header.vertCount, "base vertices")
        local vert_bytes = pos - vert_start
        log.write_to_file("Base vertex parsing completed: read " .. vert_bytes .. " bytes")
        
        -- Debug: immediately check what parse_vertices returned
        log.write_to_file("IMMEDIATE CHECK: parse_vertices returned " .. #vertices .. " vertices")
        if #vertices > 0 and vertices[1] then
            log.write_to_file("IMMEDIATE CHECK: First vertex: (" .. string.format("%.2f", vertices[1].x) .. ", " .. string.format("%.2f", vertices[1].y) .. ", " .. string.format("%.2f", vertices[1].z) .. ")")
        end
        
        -- Debug: log first few vertices
        log.write_to_file("Base vertices array has " .. #vertices .. " entries")
        for i = 1, math.min(5, #vertices) do
            local v = vertices[i]
            if v then
                log.write_to_file("  Base Vertex " .. (i-1) .. ": (" .. string.format("%.2f", v.x) .. ", " .. string.format("%.2f", v.y) .. ", " .. string.format("%.2f", v.z) .. ")")
            else
                log.write_to_file("  Base Vertex " .. (i-1) .. ": nil")
            end
        end
    end
    
    -- 7. detailVerts array - detailVertCount vertices, 12 bytes each
    local detail_vertices = {}
    if mesh_header.detailVertCount > 0 then
        detail_vertices, pos = Parser.parse_vertices(data, pos, mesh_header.detailVertCount, "detail vertices")
    end
    
    -- 8. detailTris array - detailTriCount triangles, 4 bytes each
    local detail_triangles = {}
    if mesh_header.detailTriCount > 0 then
        log.write_to_file("Parsing detail triangles at position " .. pos .. ", need " .. (mesh_header.detailTriCount * 4) .. " bytes")
        log.write_to_file("Bytes remaining in file: " .. (#data - pos + 1))
        detail_triangles, pos = Parser.parse_detail_triangles(data, pos, mesh_header.detailTriCount)
    end
    
    log.write_to_file("Final parsing position: " .. pos)
    log.write_to_file("File size: " .. #data)
    log.write_to_file("Bytes parsed: " .. (pos - 1))
    log.write_to_file("Bytes remaining: " .. (#data - pos + 1))
    
    local tile = {
        tc_header = tc_header,
        header = mesh_header,
        polygons = polygons,
        links = links,
        poly_details = poly_details,
        bv_nodes = bv_nodes,
        offmesh_connections = offmesh_connections,
        vertices = vertices,
        detail_vertices = detail_vertices,
        detail_triangles = detail_triangles,
        data = data,
        bytes_parsed = pos - 1
    }
    
    -- Debug: verify vertices were stored
    log.write_to_file("Tile structure created with " .. #vertices .. " vertices")
    if #vertices > 0 then
        log.write_to_file("First vertex in tile: (" .. string.format("%.2f", vertices[1].x) .. ", " .. string.format("%.2f", vertices[1].y) .. ", " .. string.format("%.2f", vertices[1].z) .. ")")
        
        -- Additional debug: check if vertices is the same reference we returned from parse_vertices
        log.write_to_file("Vertices variable type: " .. type(vertices))
        log.write_to_file("Vertices[1] type: " .. type(vertices[1]))
        if vertices[1] then
            log.write_to_file("Vertices[1].x type: " .. type(vertices[1].x))
            log.write_to_file("Vertices[1].x value: " .. tostring(vertices[1].x))
        end
    end
    
    setmetatable(tile, MMTile)
    return tile
end

Parser.MMTile = MMTile
Parser.dtMeshHeader = dtMeshHeader

return Parser