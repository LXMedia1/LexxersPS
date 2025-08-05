-- tile_index.lua
-- Deterministic tile index math and filename utilities (standalone)

local TileIndex = {}

local GRID_SIZE = 533.3333
local MAP_SIZE = 64
local ORIGIN_OFFSET = 32

-- CORRECT tile calculation (matches working MeshManager implementation)
function TileIndex.get_tile_for_position(x, y)
    if x == nil or y == nil then return nil, nil end
    local tile_x = ORIGIN_OFFSET - math.ceil(x / GRID_SIZE)
    local tile_y = ORIGIN_OFFSET - math.ceil(y / GRID_SIZE)
    tile_x = math.max(0, math.min(MAP_SIZE - 1, tile_x))
    tile_y = math.max(0, math.min(MAP_SIZE - 1, tile_y))
    return tile_x, tile_y
end

-- DEPRECATED: Floor-based calculation (kept for compatibility, do not use)
function TileIndex.get_tile_for_position_floor(x, y)
    if x == nil or y == nil then return nil, nil end
    local tile_x = ORIGIN_OFFSET - math.floor(x / GRID_SIZE)
    local tile_y = ORIGIN_OFFSET - math.floor(y / GRID_SIZE)
    tile_x = math.max(0, math.min(MAP_SIZE - 1, tile_x))
    tile_y = math.max(0, math.min(MAP_SIZE - 1, tile_y))
    return tile_x, tile_y
end

-- DEPRECATED: Ceil-based calculation alias (use get_tile_for_position instead)
function TileIndex.get_tile_for_position_ceil(x, y)
    return TileIndex.get_tile_for_position(x, y)
end

-- IIIIYYXX filename format (confirmed)
function TileIndex.mmtile_filename(instance_id, tile_x, tile_y)
    return string.format("%04d%02d%02d.mmtile", instance_id, tile_y, tile_x)
end

return TileIndex