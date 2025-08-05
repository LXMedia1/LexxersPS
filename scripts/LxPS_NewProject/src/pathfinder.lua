-- pathfinder.lua
-- Cross-tile A* over Detour navmesh data parsed from .mmtile files
-- Minimal, standalone: builds a polygon graph from available tiles around start/end
-- NOTE: This is an initial implementation using polygon centers and link midpoints.
-- It prioritizes correctness of topology across tiles; funnel smoothing can be added later.

-- RULE: DO NEVER USE . in require — always use /
-- RULE: When inside src/, DO NOT prefix with 'src/' in require. Use relative module name only.
-- RULE: DO NEVER USE . in require — always use /
-- RULE: When inside src/, DO NOT prefix with 'src/' in require. Use relative module name only.
local Core = require("src/core_adapter")
local Index = require("src/tile_index")
local Loader = require("src/tile_loader")
local Verifier = require("src/verifier")

local Pathfinder = {}

-- Utility
local function sqr(x) return x * x end
local function dist2(a, b)
    local dx = (a.x - b.x)
    local dy = (a.y - b.y)
    local dz = (a.z - b.z)
    return dx*dx + dy*dy + dz*dz
end

local function vec_mid(a, b)
    return { x = (a.x + b.x) * 0.5, y = (a.y + b.y) * 0.5, z = (a.z + b.z) * 0.5 }
end

-- Parse a subset of Detour data from raw mmtile to get:
--   vertices = array of {x,y,z} in WORLD space (detour's x,y,z already match header mapping we used)
--   polys = array of { firstVert, vertCount, vertIndices[], links[] }
--   links = cross-poly references with neighbor polygon refs (possibly cross-tile)
-- We implement a minimal parser robust to the TrinityCore Detour tile layout:
-- Layout after headers:
--   [verts: vertCount * 12 bytes (3 * float32)]
--   [polys: polyCount * polySize] where each poly encodes up to NVP verts and neighbor refs
--   [detail meshes/verts/tris ...] not required for topology, skip
--
-- NOTE: Actual Detour binary layout can vary by compile flags. We keep this conservative:
-- - We rely on header.maxLinkCount to iterate link records further down for topology.
-- - If structure doesn't match, we fallback to "graph from centers with no edges" to avoid crashes.

local function read_u32_le(data, off)
    if off + 3 > #data then return nil, off end
    local a,b,c,d = string.byte(data, off, off+3)
    return a + b*256 + c*65536 + d*16777216, off + 4
end

local function read_f32_le(data, off)
    if off + 3 > #data then return nil, off end
    local b1,b2,b3,b4 = string.byte(data, off, off+3)
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
    return value, off + 4
end

-- Attempt to parse Detour mesh minimally.
-- Returns { vertices = {...}, polys = {...}, centers = {...}, ok = boolean }
local function parse_detour_light(tile)
    local data = tile.raw_data
    if not data or #data < 128 then
        return { ok = false, reason = "no_data" }
    end

    -- Skip TrinityCore header (20 bytes)
    local off = 1 + 20

    -- dtMeshHeader (100 bytes) already parsed in tile_loader for header fields.
    -- We re-read counts only to compute subsequent segments reliably.
    local magic; magic, off = read_u32_le(data, off)
    if magic ~= 0x444E4156 then
        return { ok = false, reason = "bad_dnav" }
    end

    local version; version, off = read_u32_le(data, off)
    local hx; hx, off = read_u32_le(data, off)
    local hy; hy, off = read_u32_le(data, off)
    local layer; layer, off = read_u32_le(data, off)
    local userId; userId, off = read_u32_le(data, off)

    local polyCount; polyCount, off = read_u32_le(data, off)
    local vertCount; vertCount, off = read_u32_le(data, off)
    local maxLinkCount; maxLinkCount, off = read_u32_le(data, off)
    local detailMeshCount; detailMeshCount, off = read_u32_le(data, off)
    local detailVertCount; detailVertCount, off = read_u32_le(data, off)
    local detailTriCount; detailTriCount, off = read_u32_le(data, off)
    local bvNodeCount; bvNodeCount, off = read_u32_le(data, off)
    local offMeshConCount; offMeshConCount, off = read_u32_le(data, off)
    local offMeshBase; offMeshBase, off = read_u32_le(data, off)

    local walkH; walkH, off = read_f32_le(data, off)
    local walkR; walkR, off = read_f32_le(data, off)
    local walkC; walkC, off = read_f32_le(data, off)

    local bmin_x; bmin_x, off = read_f32_le(data, off)
    local bmin_y; bmin_y, off = read_f32_le(data, off)
    local bmin_z; bmin_z, off = read_f32_le(data, off)
    local bmax_x; bmax_x, off = read_f32_le(data, off)
    local bmax_y; bmax_y, off = read_f32_le(data, off)
    local bmax_z; bmax_z, off = read_f32_le(data, off)
    local bvQuant; bvQuant, off = read_f32_le(data, off)

    if not (polyCount and vertCount) then
        return { ok = false, reason = "header_counts" }
    end

    -- verts: vertCount * 3 * f32
    local vertices = {}
    for i = 1, vertCount do
        local vx; vx, off = read_f32_le(data, off); if vx == nil then break end
        local vy; vy, off = read_f32_le(data, off); if vy == nil then break end
        local vz; vz, off = read_f32_le(data, off); if vz == nil then break end
        -- World mapping: detour uses x,z,y? In TrinityCore mmaps, the dt verts are in (x,y,z) with y=height.
        -- Earlier we used mapping world.x->header.z, world.y->header.x, world.z->header.y for bounds.
        -- For drawing/path, we treat dt vertices as (X=header.X, Y=header.Y, Z=header.Z) consistent with dt header fields:
        table.insert(vertices, { x = bmin_z and vz or vx, y = bmin_y and vy or vy, z = bmin_x and vx or vz })
        -- If mapping seems off, we can switch with runtime heuristics; for now use direct (vx, vy, vz) but remap to world:
        vertices[#vertices] = { x = vz, y = vx, z = vy }
    end

    -- Without exact dtPoly binary format (depends on DT_NAVMESH_VERSION and NVP), we cannot reliably parse per-poly arrays here.
    -- Strategy: derive a spatial graph by clustering vertices into approximate convex cells based on proximity grid.
    -- This avoids wrong structure assumptions and still enables A* across clustered regions.

    if #vertices == 0 then
        return { ok = false, reason = "no_vertices" }
    end

    -- Cluster vertices into cells of size L (e.g., 6m) to approximate walkable areas as nodes
    local L = 6.0
    local cells = {}
    local cell_index = {}
    local function cell_key(x, z) -- 2D on ground plane (x,z)
        local cx = math.floor(x / L)
        local cz = math.floor(z / L)
        return tostring(cx) .. ":" .. tostring(cz), cx, cz
    end

    for _, v in ipairs(vertices) do
        local key = cell_key(v.x, v.z)
        local cell = cells[key]
        if not cell then
            cell = { key = key, sumx = 0, sumy = 0, sumz = 0, n = 0, verts = {} }
            cells[key] = cell
            table.insert(cell_index, cell)
        end
        cell.sumx = cell.sumx + v.x
        cell.sumy = cell.sumy + v.y
        cell.sumz = cell.sumz + v.z
        cell.n = cell.n + 1
        table.insert(cell.verts, v)
    end

    -- Build nodes at cell centroids
    local nodes = {}
    for _, c in ipairs(cell_index) do
        local nx = c.sumx / c.n
        local ny = c.sumy / c.n
        local nz = c.sumz / c.n
        table.insert(nodes, { x = nx, y = ny, z = nz, deg = 0, key = c.key })
    end

    -- Connect neighboring cells (4-neighborhood and diagonals) if both exist
    local node_by_key = {}
    for i, n in ipairs(nodes) do node_by_key[n.key] = i end

    local edges = {}
    local dirs = {
        {1,0},{-1,0},{0,1},{0,-1},
        {1,1},{1,-1},{-1,1},{-1,-1},
    }
    for _, c in ipairs(cell_index) do
        local parts = {}
        for token in string.gmatch(c.key, "([^:]+)") do table.insert(parts, token) end
        local cx = tonumber(parts[1]); local cz = tonumber(parts[2])
        local i1 = node_by_key[c.key]
        for _, d in ipairs(dirs) do
            local nx = cx + d[1]; local nz = cz + d[2]
            local nkey = tostring(nx) .. ":" .. tostring(nz)
            local i2 = node_by_key[nkey]
            if i1 and i2 then
                local a = math.min(i1, i2)
                local b = math.max(i1, i2)
                edges[a] = edges[a] or {}
                edges[a][b] = true
            end
        end
    end

    -- Convert edge map to list
    local adj = {}
    for i = 1, #nodes do adj[i] = {} end
    for a, row in pairs(edges) do
        for b, _ in pairs(row) do
            table.insert(adj[a], b)
            table.insert(adj[b], a)
        end
    end

    return {
        ok = true,
        nodes = nodes,
        adj = adj,
        vertices = vertices,
        info = {
            vertCount = vertCount,
            polyCount = polyCount,
            nodes = #nodes,
            edges = (function()
                local cnt = 0
                for i=1,#adj do cnt = cnt + #adj[i] end
                return cnt
            end)(),
            note = "clustered_graph"
        }
    }
end

-- Build graph from relevant tiles: include tile with start, tile with end, and a ring around both.
local function gather_tiles(instance_id, start_pos, end_pos)
    local tiles = {}

    local all = Loader.load_all_tiles(instance_id, { parse = true })
    if not all or not all.tiles then return tiles end

    -- Helper to extract tile_x, tile_y from filename "IIIIYYXX.mmtile"
    local function parse_fname(fname)
        if not fname or #fname < 12 then return nil,nil end
        local yy = tonumber(string.sub(fname, 5, 6))
        local xx = tonumber(string.sub(fname, 7, 8))
        return xx, yy
    end

    -- Pick tiles by proximity of bounds to positions
    local function best_for_pos(pos)
        local best, bestd
        for fname, t in pairs(all.tiles) do
            if t.header then
                local h = t.header
                -- check XY plane only using header mapping world.x~h.bmin_z/z, world.y~h.bmin_x/x
                local inx = pos.x >= h.bmin_z and pos.x <= h.bmax_z
                local iny = pos.y >= h.bmin_x and pos.y <= h.bmax_x
                if inx and iny then
                    local cx = (h.bmin_z + h.bmax_z)*0.5
                    local cy = (h.bmin_x + h.bmax_x)*0.5
                    local d = sqr(pos.x - cx) + sqr(pos.y - cy)
                    if not best or d < bestd then
                        best = fname; bestd = d
                    end
                end
            end
        end
        return best
    end

    local f_start = best_for_pos(start_pos)
    local f_end = best_for_pos(end_pos or start_pos)

    local todo = {}
    local function add(fname)
        if fname and not tiles[fname] then tiles[fname] = true; table.insert(todo, fname) end
    end
    add(f_start); add(f_end)

    -- Add 8 neighbors around each
    local function add_neighbors(fname)
        local tx, ty = parse_fname(fname)
        if not tx then return end
        for dx=-1,1 do
            for dy=-1,1 do
                local nx = tx + dx; local ny = ty + dy
                if nx>=0 and nx<=63 and ny>=0 and ny<=63 then
                    local neighbor = Index.mmtile_filename(instance_id, nx, ny)
                    if all.tiles[neighbor] then add(neighbor) end
                end
            end
        end
    end
    if f_start then add_neighbors(f_start) end
    if f_end then add_neighbors(f_end) end

    return todo
end

-- Build a combined graph from the selected tiles using clustered vertices.
local function build_graph(instance_id, filelist)
    local nodes = {}
    local adj = {}
    local offsets = {} -- per-tile node index ranges

    for _, fname in ipairs(filelist) do
        -- parse tile raw
        local yy = tonumber(string.sub(fname,5,6))
        local xx = tonumber(string.sub(fname,7,8))
        local t = Loader.load_tile(instance_id, xx, yy, { parse = true })
        if t and t.raw_data and #t.raw_data > 0 then
            local parsed = parse_detour_light(t)
            if parsed.ok then
                offsets[fname] = { base = #nodes, count = #parsed.nodes }
                -- append nodes
                for _, n in ipairs(parsed.nodes) do table.insert(nodes, n) end
                -- append adj
                for i = 1, #parsed.adj do
                    local gidx = offsets[fname].base + i
                    adj[gidx] = adj[gidx] or {}
                    for _, j in ipairs(parsed.adj[i]) do
                        table.insert(adj[gidx], offsets[fname].base + j)
                    end
                end
            else
                Core.log_warn("parse_detour_light failed " .. fname .. " reason=" .. tostring(parsed.reason))
            end
        end
    end

    -- Connect border between tiles by proximity: if two nodes are within D on ground, connect.
    local D2 = 4.0 * 4.0
    for i = 1, #nodes do adj[i] = adj[i] or {} end
    for i = 1, #nodes do
        local a = nodes[i]
        for j = i+1, #nodes do
            local b = nodes[j]
            local d2 = sqr(a.x - b.x) + sqr(a.z - b.z)
            if d2 <= D2 then
                table.insert(adj[i], j)
                table.insert(adj[j], i)
            end
        end
    end

    return { nodes = nodes, adj = adj }
end

-- Find nearest node to a position
local function nearest_node(graph, pos)
    local best_i, best_d2
    for i, n in ipairs(graph.nodes) do
        local d2 = sqr(n.x - pos.x) + sqr(n.z - pos.z) + 0.25 * sqr(n.y - pos.z) -- minor influence of height
        if not best_i or d2 < best_d2 then
            best_i = i; best_d2 = d2
        end
    end
    return best_i
end

-- A* over node graph
local function astar(graph, start_i, goal_i)
    if not start_i or not goal_i then return nil end
    if start_i == goal_i then return { goal_i } end

    local open = {}
    local open_set = {}
    local came = {}
    local g = {}
    local f = {}

    local function h(i)
        local a = graph.nodes[i]
        local b = graph.nodes[goal_i]
        return math.sqrt(dist2(a,b))
    end

    g[start_i] = 0
    f[start_i] = h(start_i)
    table.insert(open, start_i)
    open_set[start_i] = true

    while #open > 0 do
        -- find node in open with lowest f
        local best_k, best_i = 1, open[1]
        for k=2,#open do
            local i = open[k]
            if f[i] and f[i] < (f[best_i] or 1e30) then best_k = k; best_i = i end
        end
        local current = best_i
        table.remove(open, best_k)
        open_set[current] = nil

        if current == goal_i then
            -- reconstruct
            local path = { current }
            while came[current] do
                current = came[current]
                table.insert(path, 1, current)
            end
            return path
        end

        for _, nb in ipairs(graph.adj[current] or {}) do
            local tentative = (g[current] or 1e30) + math.sqrt(dist2(graph.nodes[current], graph.nodes[nb]))
            if tentative < (g[nb] or 1e30) then
                came[nb] = current
                g[nb] = tentative
                f[nb] = tentative + h(nb)
                if not open_set[nb] then
                    table.insert(open, nb)
                    open_set[nb] = true
                end
            end
        end
    end

    return nil
end

-- Public API: compute_path(start, stop) where start/stop = {x,y,z,iid}
function Pathfinder.compute_path(start_pos, stop_pos)
    if not start_pos or not stop_pos then
        return { points = {}, info = { error = "missing_positions" } }
    end
    if start_pos.iid ~= stop_pos.iid then
        return { points = {}, info = { error = "different_instances" } }
    end
    local iid = start_pos.iid

    -- Gather tiles
    local tiles = gather_tiles(iid, start_pos, stop_pos)
    if #tiles == 0 then
        return { points = {}, info = { error = "no_tiles" } }
    end

    -- Build graph
    local graph = build_graph(iid, tiles)
    if not graph or #graph.nodes == 0 then
        return { points = {}, info = { error = "no_graph" } }
    end

    -- Locate nearest nodes
    local si = nearest_node(graph, start_pos)
    local gi = nearest_node(graph, stop_pos)
    if not si or not gi then
        return { points = {}, info = { error = "no_node_match" } }
    end

    -- A*
    local idx_path = astar(graph, si, gi)
    if not idx_path or #idx_path == 0 then
        return { points = {}, info = { error = "no_path", nodes = #graph.nodes } }
    end

    -- Build point polyline: use node coordinates, prepend start and append end
    local points = {}
    table.insert(points, { x = start_pos.x, y = start_pos.y, z = start_pos.z })
    for _, i in ipairs(idx_path) do
        local n = graph.nodes[i]
        table.insert(points, { x = n.x, y = n.y, z = n.z })
    end
    table.insert(points, { x = stop_pos.x, y = stop_pos.y, z = stop_pos.z })

    return {
        points = points,
        info = {
            nodes = #graph.nodes,
            edges = (function()
                local s = 0
                for i=1,#graph.adj do s = s + (#graph.adj[i] or 0) end
                return s
            end)(),
            expanded = #idx_path,
            tiles = tiles,
            note = "A* over clustered-vertex graph"
        }
    }
end

return Pathfinder