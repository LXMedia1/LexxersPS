-- verifier.lua
-- Probes current tile and validates bounds using real file data
-- Base is LxPS_NewProject; use require("src/...")

local Core = require("src/core_adapter")
local Index = require("src/tile_index")
local Loader = require("src/tile_loader")

local Verifier = {}

local function inside_bounds(pos, h)
    local in_x = pos.x >= h.bmin_z and pos.x <= h.bmax_z
    local in_y = pos.y >= h.bmin_x and pos.y <= h.bmax_x
    local in_z = pos.z >= h.bmin_y and pos.z <= h.bmax_y
    return (in_x and in_y and in_z), in_x, in_y, in_z
end

local function try_variant(instance_id, pos, calc_name, tx, ty)
    if not tx or not ty then
        return { method = calc_name, tile_x = tx, tile_y = ty, exists = false }
    end
    local tile = Loader.load_tile(instance_id, tx, ty, { parse = true })
    local info = {
        method = calc_name,
        tile_x = tx,
        tile_y = ty,
        filename = tile.filename,
        exists = tile.loaded,
        parsed = tile.parsed or false
    }
    if tile.parsed and tile.header then
        local h = tile.header
        local in_x = pos.x >= h.bmin_z and pos.x <= h.bmax_z
        local in_y = pos.y >= h.bmin_x and pos.y <= h.bmax_x
        local in_z = pos.z >= h.bmin_y and pos.z <= h.bmax_y
        local ok = (in_x and in_y and in_z)
        info.contains_player = ok
        info.bounds = {
            bmin_x = h.bmin_x, bmax_x = h.bmax_x,
            bmin_y = h.bmin_y, bmax_y = h.bmax_y,
            bmin_z = h.bmin_z, bmax_z = h.bmax_z
        }
        info.inside_axes = { x = in_x, y = in_y, z = in_z }
        info.axis_variant = "remapped_xy"
        local cx = (h.bmin_x + h.bmax_x) * 0.5
        local cy = (h.bmin_z + h.bmax_z) * 0.5
        local cz = (h.bmin_y + h.bmax_y) * 0.5
        info.tile_center = { x = cx, y = cy, z = cz }
        info.delta_xy = { dx = pos.x - cy, dy = pos.y - cx }
        info.delta_z  = pos.z - cz
        local xy_ok = (in_x and in_y)
        info.xy_only_match = xy_ok and (not in_z) or false
        if not ok then
            if xy_ok and not in_z then
                info.fail_reason = "Z_out_of_range"
            elseif (in_z and (not xy_ok)) then
                info.fail_reason = "XY_out_of_range"
            else
                info.fail_reason = "XY_and_Z_out_of_range"
            end
        else
            info.fail_reason = "OK"
        end
    end
    return info
end

function Verifier.probe_tile_at_position(instance_id, pos)
    local all = Loader.load_all_tiles(instance_id, { parse = true })
    local best = nil
    local best_reason = "NA"
    local best_xy_only = false

    Core.log_info(string.format("Full scan: instance=%s files_found=%d parsed=%d",
        tostring(instance_id), all.count or 0, all.parsed_count or 0))

    local evaluated = {}
    for fname, t in pairs(all.tiles or {}) do
        if t and t.header then
            local h = t.header
            local in_x = pos.x >= h.bmin_z and pos.x <= h.bmax_z
            local in_y = pos.y >= h.bmin_x and pos.y <= h.bmax_x
            local in_z = pos.z >= h.bmin_y and pos.z <= h.bmax_y
            local ok = (in_x and in_y and in_z)
            local xy_ok = (in_x and in_y)
            local cx = (h.bmin_x + h.bmax_x) * 0.5
            local cy = (h.bmin_z + h.bmax_z) * 0.5
            local cz = (h.bmin_y + h.bmax_y) * 0.5
            local dx = pos.x - cy
            local dy = pos.y - cx
            local dz = pos.z - cz
            evaluated[fname] = {
                filename = fname,
                contains_player = ok,
                xy_only_match = xy_ok and (not in_z) or false,
                axis_variant = "remapped_xy",
                bounds = {
                    bmin_x = h.bmin_x, bmax_x = h.bmax_x,
                    bmin_y = h.bmin_y, bmax_y = h.bmax_y,
                    bmin_z = h.bmin_z, bmax_z = h.bmax_z
                },
                tile_center = { x = cx, y = cy, z = cz },
                delta_xy = { dx = dx, dy = dy },
                delta_z = dz,
                reason = ok and "OK" or (xy_ok and "Z_out_of_range" or ((in_z and "XY_out_of_range") or "XY_and_Z_out_of_range"))
            }
            local candidate = evaluated[fname]
            if candidate.contains_player then
                best = candidate
                best_reason = "OK"
                break
            elseif candidate.xy_only_match then
                if (not best) or (best and not best.contains_player and (math.abs(candidate.delta_z or 1e9) < math.abs(best.delta_z or 1e9))) then
                    best = candidate
                    best_reason = "XY_only_min_dz"
                    best_xy_only = true
                end
            else
                local cur_xy = math.abs(candidate.delta_xy.dx or 1e9) + math.abs(candidate.delta_xy.dy or 1e9)
                local best_xy = best and (math.abs(best.delta_xy.dx or 1e9) + math.abs(best.delta_xy.dy or 1e9)) or 1e18
                if (not best) or (not best.contains_player and not best_xy_only and cur_xy < best_xy) then
                    best = candidate
                    best_reason = "closest_xy_bounds"
                end
            end
        end
    end

    if best then
        local b = best.bounds or {}
        Core.log_info(string.format(
            "FULL-SCAN BEST: %s reason=%s contains=%s axis=%s | BX[%.2f..%.2f] BY[%.2f..%.2f] BZ[%.2f..%.2f] center=(%.2f,%.2f,%.2f) dXY=(%.2f,%.2f) dZ=%.2f",
            tostring(best.filename), best_reason, tostring(best.contains_player), tostring(best.axis_variant or "?"),
            b.bmin_x or 0, b.bmax_x or 0, b.bmin_z or 0, b.bmax_z or 0, b.bmin_y or 0, b.bmax_y or 0,
            (best.tile_center and best.tile_center.x or 0), (best.tile_center and best.tile_center.y or 0), (best.tile_center and best.tile_center.z or 0),
            (best.delta_xy and best.delta_xy.dx or 0), (best.delta_xy and best.delta_xy.dy or 0), (best.delta_z or 0)
        ))
        Core.log_info(string.format("FULL-SCAN BEST FILENAME: %s", tostring(best.filename)))
    else
        Core.log_info("FULL-SCAN: No candidate tiles found (parsed=0 or empty)")
    end

    return {
        position = { x = pos.x, y = pos.y, z = pos.z },
        instance_id = instance_id,
        best = best
    }
end

return Verifier
