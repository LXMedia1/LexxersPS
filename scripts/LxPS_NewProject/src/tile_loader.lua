-- tile_loader.lua
-- Standalone tile file IO and minimal parsing to verify file integrity and bounds
-- Base is LxPS_NewProject; use require("src/...")

local Core = require("src/core_adapter")
local Index = require("src/tile_index")

local TileLoader = {}

local function read_u32_le(data, pos)
    if pos + 3 > #data then return nil, pos end
    local a,b,c,d = string.byte(data, pos, pos+3)
    return a + b*256 + c*65536 + d*16777216, pos + 4
end

local function read_f32_le(data, pos)
    if pos + 3 > #data then return nil, pos end
    local b1,b2,b3,b4 = string.byte(data, pos, pos+3)
    local sign = (b4 >= 128) and -1 or 1
    local exp = ((b4 % 128) * 2) + math.floor(b3 / 128)
    local mant = ((b3 % 128) * 65536) + (b2 * 256) + b1
    local value
    if exp == 0 then
        value = (mant == 0) and (sign * 0.0) or (sign * mant * 2^-149)
    elseif exp == 255 then
        value = (mant == 0) and (sign * math.huge) or (0/0)
    else
        value = sign * (1 + mant / 2^23) * 2^(exp - 127)
    end
    return value, pos + 4
end

local function parse_tc_header(data, pos)
    local header = {}
    header.mmapMagic, pos = read_u32_le(data, pos)
    if header.mmapMagic ~= 0x4D4D4150 then
        return nil, pos
    end
    header.dtVersion, pos = read_u32_le(data, pos)
    header.mmapVersion, pos = read_u32_le(data, pos)
    header.size, pos = read_u32_le(data, pos)
    header.usesLiquids, pos = read_u32_le(data, pos)
    return header, pos
end

local function parse_dnav_header(data, pos)
    local h = {}
    h.magic, pos = read_u32_le(data, pos)
    if h.magic ~= 0x444E4156 then return nil, pos end
    h.version, pos = read_u32_le(data, pos)
    h.x, pos = read_u32_le(data, pos)
    h.y, pos = read_u32_le(data, pos)
    h.layer, pos = read_u32_le(data, pos)
    h.userId, pos = read_u32_le(data, pos)
    h.polyCount, pos = read_u32_le(data, pos)
    h.vertCount, pos = read_u32_le(data, pos)
    h.maxLinkCount, pos = read_u32_le(data, pos)
    h.detailMeshCount, pos = read_u32_le(data, pos)
    h.detailVertCount, pos = read_u32_le(data, pos)
    h.detailTriCount, pos = read_u32_le(data, pos)
    h.bvNodeCount, pos = read_u32_le(data, pos)
    h.offMeshConCount, pos = read_u32_le(data, pos)
    h.offMeshBase, pos = read_u32_le(data, pos)
    h.walkableHeight, pos = read_f32_le(data, pos)
    h.walkableRadius, pos = read_f32_le(data, pos)
    h.walkableClimb, pos = read_f32_le(data, pos)
    h.bmin_x, pos = read_f32_le(data, pos)
    h.bmin_y, pos = read_f32_le(data, pos)
    h.bmin_z, pos = read_f32_le(data, pos)
    h.bmax_x, pos = read_f32_le(data, pos)
    h.bmax_y, pos = read_f32_le(data, pos)
    h.bmax_z, pos = read_f32_le(data, pos)
    h.bvQuantFactor, pos = read_f32_le(data, pos)
    return h, pos
end

local function parse_mmtile_minimal(data)
    if not data or #data < 120 then return nil end
    local pos = 1
    local tc, p1 = parse_tc_header(data, pos)
    if not tc then return nil end
    local dnav, p2 = parse_dnav_header(data, p1)
    if not dnav then return nil end
    local tile = {
        tc_header = tc,
        header = dnav,
        bytes_parsed = p2 - 1,
        file_size = #data
    }
    return tile
end

function TileLoader.load_tile(instance_id, tile_x, tile_y, opts)
    opts = opts or {}
    local filename = Index.mmtile_filename(instance_id, tile_x, tile_y)
    local path = "mmaps/" .. filename
    local content = Core.read_data_file(path)
    if not content or #content == 0 then
        return { filename = filename, loaded = false }
    end
    local parsed = parse_mmtile_minimal(content)
    if not parsed then
        return { filename = filename, loaded = true, parsed = false }
    end
    return {
        filename = filename,
        loaded = true,
        parsed = true,
        header = parsed.header,
        tc_header = parsed.tc_header,
        file_size = parsed.file_size,
        raw_data = content
    }
end

function TileLoader.load_all_tiles(instance_id, options)
    options = options or {}
    local parse_tiles = options.parse ~= false
    local result = { count = 0, parsed_count = 0, files_found = {}, tiles = {} }
    for x = 0, 63 do
        for y = 0, 63 do
            local filename = Index.mmtile_filename(instance_id, x, y)
            local path = "mmaps/" .. filename
            local content = Core.read_data_file(path)
            if content and #content > 0 then
                result.count = result.count + 1
                table.insert(result.files_found, filename)
                if parse_tiles then
                    local parsed = parse_mmtile_minimal(content)
                    if parsed then
                        result.parsed_count = result.parsed_count + 1
                        result.tiles[filename] = {
                            tile_x = x, tile_y = y, header = parsed.header, tc_header = parsed.tc_header
                        }
                    else
                        result.tiles[filename] = { tile_x = x, tile_y = y, header = nil }
                    end
                end
            end
        end
    end
    Core.log_info(string.format("[NXP] Tile scan summary: instance=%d files_found=%d parsed=%d",
        instance_id, result.count, result.parsed_count))
    return result
end

return TileLoader
