local Core = require("src/core_adapter")
local Index = require("src/tile_index")
local Loader = require("src/tile_loader")
local Vec3 = require("common/geometry/vector_3")
local Color = require("common/color")

local M = { cache = { key=nil, tris=nil, bbox=nil } }

local function read_u32(data, off)
  if off+3 > #data then return nil end
  local a,b,c,d = string.byte(data, off, off+3); return a + b*256 + c*65536 + d*16777216
end
local function read_f32(data, off)
  if off+3 > #data then return nil end
  local b1,b2,b3,b4 = string.byte(data, off, off+3)
  local sign = (b4 >= 128) and -1 or 1
  local exp = ((b4 % 128) * 2) + math.floor(b3 / 128)
  local mant = ((b3 % 128) * 65536) + (b2 * 256) + b1
  if exp == 0 then return (mant == 0) and (sign * 0.0) or (sign * mant * 2^-149)
  elseif exp == 255 then return (mant == 0) and (sign * math.huge) or (0/0) end
  return sign * (1 + mant / 2^23) * 2^(exp - 127)
end

local function parse_tile_to_tris(tile)
  local h = tile and tile.header; local data = tile and tile.raw_data
  if not (h and data) then return nil,nil end
  local bbox = {
    x1=h.bmin_z, x2=h.bmax_z,
    y1=h.bmin_x, y2=h.bmax_x,
    z1=h.bmin_y, z2=h.bmax_y,
  }
  local verts_off = 1 + 20 + 100
  local vertCount = tonumber(h.vertCount) or 0
  if verts_off + vertCount*12 > #data then return {}, bbox end
  local vertices = {}
  local o = verts_off
  for i=1,vertCount do
    local vx = read_f32(data,o); local vy = read_f32(data,o+4); local vz = read_f32(data,o+8); o = o + 12
    if not (vx and vy and vz) then break end
    local wx,wy,wz = vz, vx, vy
    vertices[i] = Vec3.new(wx,wy,wz)
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
  local dmesh = {}
  local dm_off = detail_meshes_off
  for i=1,detailMeshCount do
    if dm_off+15 > #data then break end
    local vb = read_u32(data,dm_off); dm_off = dm_off + 4
    local nv = read_u32(data,dm_off); dm_off = dm_off + 4
    local tb = read_u32(data,dm_off); dm_off = dm_off + 4
    local nt = read_u32(data,dm_off); dm_off = dm_off + 4
    if not (vb and nv and tb and nt) then break end
    dmesh[i] = { vb=vb, nv=nv, tb=tb, nt=nt }
  end
  local dverts_off = dm_off
  local dtris_off  = dverts_off + detailVertCount * 12
  local function read_vec3_at(off)
    local x = read_f32(data,off); local y = read_f32(data,off+4); local z = read_f32(data,off+8)
    return x,y,z
  end
  local function get_detail_vert(i)
    local off = dverts_off + (i*12)
    if off+8 > #data then return nil end
    local vx,vy,vz = read_vec3_at(off)
    if not vx then return nil end
    local wx,wy,wz = vz, vx, vy
    return Vec3.new(wx,wy,wz)
  end
  local tris = {}
  local function tri_for_poly(pi)
    local dm = dmesh[pi+1]; if not dm then return end
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
      if a and b and c then tris[#tris+1] = {a,b,c} end
    end
  end
  for pi=0,polyCount-1 do tri_for_poly(pi) end
  return tris, bbox
end

function M.ensure_loaded_current_tile()
  local iid = Core.get_instance_id(); if not iid then return end
  local player = Core.get_player(); if not player then return end
  local pos = player:get_position(); if not pos then return end
  local ty, tx = Index.get_tile_for_position(pos.x, pos.y)
  if not (tx and ty) then return end
  local key = tostring(iid)..":"..tostring(tx)..":"..tostring(ty)
  if M.cache.key == key and M.cache.tris then return end
  local tile = Loader.load_tile(iid, tx, ty, { parse = true })
  if not (tile and tile.parsed and tile.raw_data and tile.header) then return end
  local tris, bbox = parse_tile_to_tris(tile)
  M.cache.key = key; M.cache.tris = tris or {}; M.cache.bbox = bbox
end

function M.get_tris()
  return M.cache.tris
end

function M.get_bbox()
  return M.cache.bbox
end

return M
