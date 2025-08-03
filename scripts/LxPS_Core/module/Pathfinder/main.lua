local Pathfinder = {}

--[[
Pathfinder
=========

This module implements a simple A* pathfinding algorithm over the
Detour navmesh data parsed by ``LxPS_Core.Parser``.  It builds an
adjacency graph from the dtPoly structures, computes polygon
centroids, and uses Euclidean distance between centroids (in world
coordinates) as the heuristic.  It also converts navmesh coordinates
to game world coordinates.  In TrinityCore/Detour, a navmesh vertex
``(x, y, z)`` corresponds to game world ``(x, z, y)``.  This module
exposes a ``nav_to_world`` helper to perform that conversion.

Usage:

```
local Pathfinder = require("module/Pathfinder")
local tile = ... -- result of Parser.parse_mmtile()
local startPoly = 4606
local goalPoly = 4067
local polyPath, worldPath = Pathfinder.find_path(tile, startPoly, goalPoly)
-- polyPath is {startPoly, ..., goalPoly}
-- worldPath is the list of centroids converted to world coordinates
-- for each polygon in polyPath.
```
]]

-- Convert a navmesh point (x, y, z) to world coordinates.
-- In the navmesh, x corresponds to world x (north–south),
-- y corresponds to world z (height), and z corresponds to world y
-- (east–west).  This function returns a new table with the
-- converted coordinates.
local function nav_to_world(pt)
    return { x = pt.x, y = pt.z, z = pt.y }
end

--- Public helper to convert navmesh coordinates to game world coordinates.
-- @param pt table A table with fields ``x``, ``y`` and ``z`` representing navmesh coords.
-- @return table A new table with ``x``, ``y`` and ``z`` fields in game world ordering.
function Pathfinder.nav_to_world(pt)
    return nav_to_world(pt)
end

-- Build adjacency and centroids for the tile.  Returns two tables:
-- ``adj`` maps a polygon index (1-based) to a list of neighbour
-- polygon indices.  ``centroids`` maps a polygon index to the
-- centroid (navmesh coordinates) of that polygon.  The centroid is
-- computed as the arithmetic mean of the vertices referenced by
-- ``poly.verts``.
local function build_graph(tile)
    local polys = tile.polygons
    local verts = tile.vertices
    local adj = {}
    local centroids = {}
    for i, poly in ipairs(polys) do
        -- compute centroid
        local cx, cy, cz = 0.0, 0.0, 0.0
        local count = poly.vertCount or #poly.verts
        for j = 1, count do
            local idx = poly.verts[j]
            -- dtPoly.vert array stores zero‑based indices into tile.vertices
            local v = verts[(idx or 0) + 1]
            if v then
                cx = cx + v.x
                cy = cy + v.y
                cz = cz + v.z
            end
        end
        if count > 0 then
            cx = cx / count
            cy = cy / count
            cz = cz / count
        end
        centroids[i] = { x = cx, y = cy, z = cz }
        -- build neighbour list
        local neighbors = {}
        for j = 1, count do
            local nei = poly.neis[j]
            -- In Detour, neighbour indices refer to other polygons in the
            -- same tile when ``nei`` is non‑zero and less than or equal to
            -- the polygon count.  Zero means no neighbour.
            if nei and nei > 0 and nei <= #polys then
                table.insert(neighbors, nei)
            end
        end
        adj[i] = neighbors
    end
    return adj, centroids
end

-- Heuristic function: Euclidean distance between two navmesh points
-- converted to world coordinates.  Returns a positive number.
local function heuristic(n1, n2)
    local w1 = nav_to_world(n1)
    local w2 = nav_to_world(n2)
    local dx = w1.x - w2.x
    local dy = w1.y - w2.y
    local dz = w1.z - w2.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Reconstruct path from cameFrom map.
local function reconstruct_path(cameFrom, current)
    local total = { current }
    while cameFrom[current] do
        current = cameFrom[current]
        table.insert(total, 1, current)
    end
    return total
end

--- Find a path on a single navmesh tile between two polygons using A*.
-- The algorithm treats each polygon as a node in a graph and uses
-- Euclidean distance between centroids as the heuristic.  It returns
-- the sequence of polygon indices traversed and the corresponding
-- centroids converted to world coordinates.  If either start or
-- goal polygon indices are invalid or no path is found, returns nil.
--
-- @param tile table The parsed navmesh tile returned from ``Parser.parse_mmtile``.
-- @param start_poly_idx number Index of the starting polygon (1-based).
-- @param goal_poly_idx number Index of the goal polygon (1-based).
-- @return table|nil, table|nil A list of polygon indices and a list of world coordinate points, or nil if no path exists.
function Pathfinder.find_path(tile, start_poly_idx, goal_poly_idx)
    if not tile or not tile.polygons or #tile.polygons == 0 then
        return nil
    end
    local adj, centroids = build_graph(tile)
    local start = start_poly_idx
    local goal = goal_poly_idx
    if not centroids[start] or not centroids[goal] then
        return nil
    end
    -- open set stores nodes to explore
    local openSet = { [start] = true }
    -- gScore[n] = cost from start to n
    local gScore = {}
    gScore[start] = 0.0
    -- fScore[n] = gScore[n] + heuristic(n, goal)
    local fScore = {}
    fScore[start] = heuristic(centroids[start], centroids[goal])
    -- cameFrom[n] = best predecessor of n on the path
    local cameFrom = {}
    while true do
        -- find node in open set with lowest fScore
        local current, currentF = nil, math.huge
        for node in pairs(openSet) do
            local f = fScore[node] or math.huge
            if f < currentF then
                current = node
                currentF = f
            end
        end
        if not current then
            break -- no nodes left
        end
        if current == goal then
            local polyPath = reconstruct_path(cameFrom, current)
            -- convert centroids to world coordinates
            local worldPath = {}
            for _, idx in ipairs(polyPath) do
                worldPath[#worldPath + 1] = nav_to_world(centroids[idx])
            end
            return polyPath, worldPath
        end
        -- remove current from open set
        openSet[current] = nil
        -- explore neighbours
        for _, neighbor in ipairs(adj[current]) do
            local tentative_g = (gScore[current] or math.huge) +
                heuristic(centroids[current], centroids[neighbor])
            if not gScore[neighbor] or tentative_g < gScore[neighbor] then
                cameFrom[neighbor] = current
                gScore[neighbor] = tentative_g
                fScore[neighbor] = tentative_g + heuristic(centroids[neighbor], centroids[goal])
                openSet[neighbor] = true
            end
        end
    end
    -- no path found
    return nil
end

return Pathfinder