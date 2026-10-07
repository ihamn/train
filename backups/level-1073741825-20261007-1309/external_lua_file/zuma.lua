-- ============================================================
-- zuma.lua —— 由 miliastra/tools/bundle-lua.mjs 自动生成，**不要手改**。
-- 源文件：miliastra/lua/src/*.lua（那边才是真源）
--
-- 用法：整个文件作为**一个客户端脚本**上传 -> 在客户端控件容器的
--       脚本页签里挂上它 -> 把控件模板索引填进脚本变量（见 lua/src/game.lua 顶部）。
-- ============================================================

local __M = {}
local __cache = {}
local function __require(name)
  local hit = __cache[name]
  if hit ~= nil then return hit end
  local f = __M[name]
  if not f then error("module not found: " .. tostring(name)) end
  local v = f()
  if v == nil then v = true end
  __cache[name] = v
  return v
end
local require = __require   -- ★ 必须在模块体之前，模块体里的 require 才绑得到它

-- ---------------- rng ----------------
__M["rng"] = function()
-- rng.lua —— src/rng.js 的 Lua 5.3 移植。
--
-- ★ 必须**逐位**复刻 JS 的 32 位语义：Math.imul / >>> / |0 在 Lua 里都要手写。
--   Lua 5.3 的整数是 64 位，所以每个中间结果都要 & 0xFFFFFFFF 收回 32 位。
--   两个 32 位数直接相乘会溢出 64 位（(2^32)^2 ≈ 1.8e19 > 2^63），
--   所以 imul 拆成 16 位半字相乘 —— 这是本文件唯一需要小心的地方。
--
-- ★ 与 JS 的**唯一**接口差异：JS 的 rng 是函数对象，Lua 的函数不能挂字段，
--   所以这里用"可调用的表"（__call）。用法仍然是 rng() / rng.int(n) / rng.pick(t)。

local M = {}

local U32 = 0xFFFFFFFF

local function imul(a, b)
  a = a & U32
  b = b & U32
  local a0, a1 = a & 0xFFFF, a >> 16
  local b0, b1 = b & 0xFFFF, b >> 16
  local lo = a0 * b0
  local mid = ((a0 * b1 + a1 * b0) & 0xFFFF) << 16
  return (lo + mid) & U32
end
M.imul = imul

function M.makeRng(seed)
  local a = seed & U32
  if a == 0 then a = 0x9e3779b9 end

  local function step()
    a = (a + 0x6d2b79f5) & U32
    local t = imul(a ~ (a >> 15), (1 | a) & U32)
    t = ((t + imul(t ~ (t >> 7), (61 | t) & U32)) & U32) ~ t
    t = t & U32
    return ((t ~ (t >> 14)) & U32) / 4294967296
  end

  local rng = setmetatable({}, { __call = function(_, ...) return step() end })
  -- ★★ 取下标前**必须夹一次**：Lua 的整数位宽不是我们能控制的。
  --    64 位（真机 Lua 5.3）= 上面的掩码有效，step() 恒在 [0,1)，下面的折叠**是恒等变换**，
  --    一个数都不会变 —— 对拍 81339 个数值就是这条的证据。
  --    但换成 32 位整数的环境（例如跑在 Fengari 上的模拟器，0xFFFFFFFF == -1），
  --    step() 会跑到 [-0.5, 0.5)，math.floor(step()*n) 就成了负数或越界，
  --    arr[idx+1] 直接是 nil —— 然后 nil 会一路传下去（碱基 nil → 球画成白色、
  --    isComplement(nil) 之类更难查的错），而不是"当场报错"。
  --    与其让环境差异变成 nil，不如折回 [0,1)：环境坏了也就是颜色序列不对，不至于崩。
  local function unit()
    local v = step()
    if v ~= v then return 0 end          -- nan
    v = v % 1                            -- [0,1) 之外的（负数 / ≥1）折回来
    if v < 0 then v = v + 1 end          -- 兜底：万一 % 给了 -0.0
    return v
  end
  rng.int = function(n) return math.floor(unit() * n) end
  rng.pick = function(arr) return arr[rng.int(#arr) + 1] end   -- Lua 数组从 1 开始
  rng.seed = seed & U32                                        -- 与 JS 一致：记的是**入参** seed
  return rng
end

return M
end

-- ---------------- config ----------------
__M["config"] = function()
-- config.lua —— src/config.js 的 Lua 5.3 移植。
-- 数值一律与 config.js 逐字对应；改数值只改这里（对应本体的"只改一个文件"约定）。

local M = {}

M.BASES = { 'A', 'U', 'G', 'C', 'T' }

-- 互补配对表（不对称：A 是唯一的双配碱基）
M.COMPLEMENT = {
  A = { 'U', 'T' },
  U = { 'A' },
  T = { 'A' },
  G = { 'C' },
  C = { 'G' },
}

-- 颜色（第二通道）。互补碱基的颜色互为反色。
M.BASE_COLOR = {
  A = '#e05cff', T = '#5cc93f', U = '#9dff7a', G = '#33b8ff', C = '#ff6b33',
}
M.BASE_INK = {
  A = '#1c0a24', T = '#0d2205', U = '#132a08', G = '#04203a', C = '#2b0f04',
}
M.WRONG_COLOR = '#6b7280'
M.WRONG_INK = '#0b1220'
M.WRONG_GLOW = '#ff5555'

function M.complementColor(base)
  local c = M.COMPLEMENT[base]
  if c then return M.BASE_COLOR[c[1]] end
  return '#ffffff'
end

M.DESIGN = {
  base = 900,
  spawnRadius = 19,
  smallDiameterRatio = 1 / math.sqrt(2),
  railClearance = 9.0,
  beadGap = 1.5,
  pathSamples = 2400,
  outerFit = 0.45,
  outerFitWide = 0.62,
  outerFitTall = 0.86,
  minScale = 0.82,
  innerRatio = 0.32,
  turns = 1.9,

  chainSpeed = 42,
  chainAccel = 30,
  chainDecel = 620,
  slowDistance = 0,
  slowFactor = 2.6,

  ribosomeRadius = 30,
  fireCooldown = 0.16,
  shotSpeed = 1150,
  shotRadiusRatio = 0.9,
  shotMaxLife = 3.0,
  dockTime = 0.30,
  readWindow = 0.30,

  startLives = 3,
  ballBudget = 0,
  scoreTarget = 500,
  winOnClear = true,
  scorePerBall = 10,
  losingSpeed = 1500,

  mergeTime = 0.26,
  defaultMode = 'match',

  elemFreezeTime = 3.0,
  elemAutoPairCount = 3,
  elemSwirlRange = 2,
  elemBurnTime = 3.0,
  elemBurnTick = 0.25,
  elemCoreLife = 6.0,
  elemCoreMax = 5,
  elemReactionDepth = 4,
  elemShieldMax = 3,
  elemScorePerReaction = 10,
  reactionFlashTime = 1.2,
  elemHints = true,
  hintMaxCount = 4,
  modeFlashTime = 0.28,

  bagBias = 1.0,
  retreatTime = 0.22,
  backFrames = 30,
  backStopFrames = 20,
  insertPairs = false,
}

M.Z = { projectile = 50, actor = 60, fx = 70, hud = 100 }

function M.metrics(scale)
  local D = M.DESIGN
  local R = D.spawnRadius * scale
  local r = R * D.smallDiameterRatio
  local d = R + r + D.railClearance * scale
  local linkGap = D.beadGap * scale
  local p = 2 * R + linkGap
  return {
    scale = scale,
    R = R,
    r = r,
    d = d,
    p = p,
    linkGap = linkGap,
    diameterRatio = R / r,
    areaRatio = (R * R) / (r * r),
  }
end

function M.viewFor(w, h)
  local D = M.DESIGN
  local base = math.min(w, h)
  local scale = math.max(base / D.base, math.min(D.minScale, base / 450))
  local portrait = h > w * 1.25
  local capX = base * D.outerFitWide
  local capY = base * (portrait and D.outerFitTall or D.outerFitWide)
  return {
    w = w, h = h, dpr = 1,
    cx = w / 2, cy = h / 2,
    rx = math.min(w * D.outerFit, capX),
    ry = math.min(h * D.outerFit, capY),
    base = base, scale = scale, portrait = portrait,
  }
end

-- 模式按钮矩形（render / main 共用一份）
function M.modeButtonRect(view, mt)
  local r = 40 * mt.scale
  local pad = 26 * mt.scale
  return { x = view.w - r - pad, y = view.h - r - pad, r = r }
end

function M.menuButtonRect(view, mt)
  local r = 22 * mt.scale
  local pad = 26 * mt.scale
  return { x = r + pad, y = view.h - r - pad, r = r }
end

function M.isComplement(tRNA, mRNA)
  local c = M.COMPLEMENT[mRNA]
  if not c then return false end
  for i = 1, #c do if c[i] == tRNA then return true end end
  return false
end

-- ==================== 经典祖玛专用配色（DESIGN.md §66.6）====================
-- 奇匠要求："原版球的颜色不要沿用，重新搞"。
-- ★ 内部 token 仍是 A/U/C/G/T（规则/对拍/控件池一律不动），只换**显示颜色**。
M.CLASSIC_COLOR = {
  A = '#e8453c',   -- 红
  U = '#f2c53d',   -- 黄
  G = '#3b7ddd',   -- 蓝
  C = '#3fbf6f',   -- 绿
  T = '#9a5bd6',   -- 紫
}
M.CLASSIC_INK = {
  A = '#2a0705', U = '#2b2205', G = '#04122b', C = '#052a12', T = '#1b0733',
}

-- 按 ruleset 取色：'classic' 用经典那套，其它（含缺省）用 RNA 碱基色
function M.colorOf(base, rules)
  local t = (rules == 'classic') and M.CLASSIC_COLOR or M.BASE_COLOR
  return t[base] or '#ffffff'
end
function M.inkOf(base, rules)
  local t = (rules == 'classic') and M.CLASSIC_INK or M.BASE_INK
  return t[base] or '#101820'
end

return M
end

-- ---------------- elements ----------------
__M["elements"] = function()
-- elements.lua —— src/elements.js 的 Lua 5.3 移植（**部分**）。
--
-- ⚠ 只移植了"匹配/加球模式跑得起来"所需的部分：七元素表 + canAttach / elemName / elemColor。
--   **反应表（REACTIONS / sevenReaction / beadElemsFor）没有移植** ——
--   七球模式已被用户明确搁置（§65「先不管」），移植它没有意义。
--   如果以后要做，照 elements.js 逐条抄数据即可（它是考证结论，不是平衡数值）。
--
-- 为什么必须先有 canAttach：核糖体的 loadedElem 初始化要抽两次元素，
-- **这会消耗确定性随机数**（rng 的调用次数必须与 JS 完全一致，否则整条链全错位）。

local M = {}

M.ELEMENTS = { 'pyro', 'hydro', 'cryo', 'electro', 'dendro', 'geo', 'anemo' }

M.ELEM = {
  pyro    = { name = '火', color = '#ff7a45', ink = '#3a1204', attachable = true },
  hydro   = { name = '水', color = '#49b6ff', ink = '#04223a', attachable = true },
  cryo    = { name = '冰', color = '#a8ecff', ink = '#0b2b38', attachable = true },
  electro = { name = '雷', color = '#c08cff', ink = '#220b3a', attachable = true },
  dendro  = { name = '草', color = '#8ede52', ink = '#10300a', attachable = true },
  geo     = { name = '岩', color = '#ffc94d', ink = '#3a2604', attachable = false },
  anemo   = { name = '风', color = '#6fe8c8', ink = '#0a332a', attachable = false },
}

M.QUICK = 'quick'

function M.canAttach(elem)
  local e = M.ELEM[elem]
  return (e ~= nil) and (e.attachable == true)
end

function M.elemName(elem)
  if elem == M.QUICK then return '激' end
  local e = M.ELEM[elem]
  return e and e.name or '—'
end

function M.elemColor(elem)
  if elem == M.QUICK then return '#d9f24a' end
  local e = M.ELEM[elem]
  return e and e.color or '#8899aa'
end

return M
end

-- ---------------- geometry ----------------
__M["geometry"] = function()
-- geometry.lua —— src/geometry.js 的 Lua 5.3 移植。
--
-- ★ 唯一的**非逐字**改动：数组下标从 0 基改成 1 基（Lua 惯例）。
--   凡是涉及"第几个"的地方都标注了 -- 1基。跨端对拍由 tools/parity.mjs 负责对账。
--
-- 语义与 geometry.js 完全一致：弧长参数化 + 法线偏移双轨 + 层级分段 + 校验器。

local M = {}

M.TAU = math.pi * 2

local function clamp(v, a, b) if v < a then return a elseif v > b then return b else return v end end
M.clamp = clamp

local function hypot(x, y) return math.sqrt(x * x + y * y) end

local TrackPath = {}
TrackPath.__index = TrackPath

function M.newPath(pts, length)
  return setmetatable({ pts = pts, length = length }, TrackPath)
end

function TrackPath:samples() return #self.pts end

-- u ∈ [0,1] -> 弧长
function TrackPath:sAtU(u)
  local n = #self.pts
  local i0 = math.floor(clamp(u, 0, 1) * (n - 1) + 0.5)   -- 0 基
  if i0 < 0 then i0 = 0 elseif i0 > n - 1 then i0 = n - 1 end
  return self.pts[i0 + 1].s
end

-- 弧长 -> 采样区间左端点下标（返回 1 基下标）
function TrackPath:indexAt(s)
  local pts = self.pts
  local n = #pts
  if s <= 0 then return 1 end
  if s >= self.length then return n - 1 end
  local lo, hi = 1, n
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if pts[mid].s <= s then lo = mid else hi = mid end
  end
  return lo
end

function TrackPath:pointAt(s)
  local pts = self.pts
  local sc = clamp(s, 0, self.length)
  local i = self:indexAt(sc)
  local a, b = pts[i], pts[i + 1]
  local seg = b.s - a.s
  local t = seg > 1e-9 and (sc - a.s) / seg or 0
  return {
    x = a.x + (b.x - a.x) * t,
    y = a.y + (b.y - a.y) * t,
    s = sc,
    z = (t < 0.5) and a.z or b.z,
  }
end

function TrackPath:normalAt(s)
  local pts = self.pts
  local sc = clamp(s, 0, self.length)
  local i = self:indexAt(sc)
  local a, b = pts[i], pts[i + 1]
  local seg = b.s - a.s
  local t = seg > 1e-9 and (sc - a.s) / seg or 0
  local nx = a.nx + (b.nx - a.nx) * t
  local ny = a.ny + (b.ny - a.ny) * t
  local L = hypot(nx, ny)
  if L == 0 then L = 1 end
  return { x = nx / L, y = ny / L }
end

function TrackPath:zAt(s)
  local i = self:indexAt(clamp(s, 0, self.length))
  return self.pts[i].z
end

-- 采样骨架曲线并建立弧长表。spineFn(u) -> {x,y}
function M.buildPath(spineFn, opts)
  opts = opts or {}
  local n = math.max(64, opts.samples or 2400)
  local pts = {}
  local s, px, py = 0, 0, 0
  for i = 0, n do
    local u = i / n
    local q = spineFn(u)
    if i > 0 then s = s + hypot(q.x - px, q.y - py) end
    px, py = q.x, q.y
    pts[i + 1] = { u = u, x = q.x, y = q.y, s = s, nx = 0, ny = 0, z = 0 }
  end
  local path = M.newPath(pts, s)
  M.computeNormals(path, opts.center)
  return path
end

-- 法线沿弧长连续：起点用"背离中心"定向，其后用点积连续性翻正。
function M.computeNormals(path, center)
  local pts = path.pts
  local n = #pts
  for i = 1, n do
    local a = pts[i > 1 and i - 1 or 1]
    local b = pts[i < n and i + 1 or n]
    local tx, ty = b.x - a.x, b.y - a.y
    local L = hypot(tx, ty)
    if L == 0 then L = 1 end
    tx, ty = tx / L, ty / L
    pts[i].nx, pts[i].ny = -ty, tx
  end
  if center then
    local p0 = pts[1]
    local rx, ry = p0.x - center.x, p0.y - center.y
    if rx * p0.nx + ry * p0.ny < 0 then p0.nx, p0.ny = -p0.nx, -p0.ny end
  end
  for i = 2, n do
    if pts[i].nx * pts[i - 1].nx + pts[i].ny * pts[i - 1].ny < 0 then
      pts[i].nx, pts[i].ny = -pts[i].nx, -pts[i].ny
    end
  end
  return path
end

function M.assignLayers(path, spec)
  local pts = path.pts
  for i = 1, #pts do pts[i].z = 0 end
  if not spec then return path end
  for k = 1, #spec do
    local seg = spec[k]
    for i = 1, #pts do
      if pts[i].s >= seg.from and pts[i].s <= seg.to then pts[i].z = seg.z end
    end
  end
  return path
end

function M.layerRuns(path)
  local pts = path.pts
  local runs = {}
  local i0 = 1
  for i = 2, #pts + 1 do
    if i == #pts + 1 or pts[i].z ~= pts[i0].z then
      runs[#runs + 1] = { z = pts[i0].z, i0 = i0, i1 = i - 1 }
      i0 = i
    end
  end
  return runs
end

function M.buildRail(path, offset)
  local pts = path.pts
  local out = {}
  for i = 1, #pts do
    out[i] = {
      x = pts[i].x + pts[i].nx * offset,
      y = pts[i].y + pts[i].ny * offset,
      s = pts[i].s,
      z = pts[i].z,
    }
  end
  return out
end

function M.curvatureAt(pts, i)
  local n = #pts
  local a = pts[i > 1 and i - 1 or 1]
  local b = pts[i]
  local c = pts[i < n and i + 1 or n]
  local abx, aby = b.x - a.x, b.y - a.y
  local bcx, bcy = c.x - b.x, c.y - b.y
  local acx, acy = c.x - a.x, c.y - a.y
  local crossv = abx * bcy - aby * bcx
  local denom = hypot(abx, aby) * hypot(bcx, bcy) * hypot(acx, acy)
  if denom < 1e-9 then return 0 end
  return (2 * crossv) / denom
end

local function segCross(o, a, b)
  return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
end

local function segIntersect(a, b, c, d)
  local d1 = segCross(c, d, a)
  local d2 = segCross(c, d, b)
  local d3 = segCross(a, b, c)
  local d4 = segCross(a, b, d)
  if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)) then
    local t = d1 / (d1 - d2)
    return { x = c.x + (d.x - c.x) * t, y = c.y + (d.y - c.y) * t }
  end
  return nil
end

function M.selfCrossings(poly, opts)
  opts = opts or {}
  local step = math.max(1, opts.step or 8)
  local segs = {}
  local i = 1
  while i + step <= #poly do
    local j = math.min(#poly, i + step)
    local a, b = poly[i], poly[j]
    if hypot(b.x - a.x, b.y - a.y) >= 1e-6 then
      segs[#segs + 1] = { a = a, b = b, i0 = i, i1 = j }
    end
    i = i + step
  end
  local out = {}
  for x = 1, #segs do
    for y = x + 1, #segs do
      if segs[y].i0 - segs[x].i1 >= step * 2 then
        local hit = segIntersect(segs[x].a, segs[x].b, segs[y].a, segs[y].b)
        if hit then out[#out + 1] = { x = hit.x, y = hit.y, s1 = segs[x].a.s, s2 = segs[y].a.s } end
      end
    end
  end
  return out
end

function M.validateTrack(path, mt, opts)
  opts = opts or {}
  local issues = {}
  local maxOffset = opts.maxOffset ~= nil and opts.maxOffset or mt.d / 2
  local pts = path.pts

  local worst, worstS = 0, 0
  for i = 2, #pts - 1 do
    local need = math.abs(M.curvatureAt(pts, i)) * maxOffset
    if need > worst then worst, worstS = need, pts[i].s end
  end
  if worst >= 1 then
    issues[#issues + 1] = { code = 'CURVATURE_OFFSET', severity = 'error', s = worstS,
      detail = '偏移 ' .. string.format('%.1f', maxOffset) .. 'px 超过最小曲率半径；内偏轨道会折叠' }
  elseif worst > 0.85 then
    issues[#issues + 1] = { code = 'CURVATURE_TIGHT', severity = 'warn', s = worstS,
      detail = '偏移接近最小曲率半径（占比 ' .. string.format('%.2f', worst) .. '），弯道处珠距会明显压缩' }
  end

  if mt.d < mt.R + mt.r then
    issues[#issues + 1] = { code = 'RAIL_OVERLAP', severity = 'error', s = 0,
      detail = '两轨中心距 ' .. string.format('%.1f', mt.d) .. ' < 半径和 ' .. string.format('%.1f', mt.R + mt.r) }
  end
  if mt.p < 2 * mt.R then
    issues[#issues + 1] = { code = 'BEAD_OVERLAP', severity = 'error', s = 0,
      detail = '同轨球心距 ' .. string.format('%.1f', mt.p) .. ' < 直径 ' .. string.format('%.1f', 2 * mt.R) }
  end

  local rails = opts.rails or { mt.d / 2, -mt.d / 2 }
  for k = 1, #rails do
    local poly = M.buildRail(path, rails[k])
    local xs = M.selfCrossings(poly, { step = opts.step or 8 })
    for m = 1, #xs do
      local x = xs[m]
      local z1 = path:zAt(x.s1)
      local z2 = path:zAt(x.s2)
      if z1 == z2 then
        issues[#issues + 1] = { code = 'SELF_CROSS_SAME_Z', severity = 'error', x = x.x, y = x.y, s = x.s1,
          detail = '同一 z 层 (' .. tostring(z1) .. ') 自交，遮挡关系无解' }
      else
        issues[#issues + 1] = { code = 'BRIDGE', severity = 'info', x = x.x, y = x.y, s = x.s1,
          detail = '跨层桥 z' .. tostring(z1) .. ' / z' .. tostring(z2) }
      end
    end
  end
  return issues
end

return M
end

-- ---------------- spines ----------------
__M["spines"] = function()
-- spines.lua —— src/spines.js 的 Lua 5.3 移植。骨架原型（DESIGN.md §5.1）。
-- 关键：接缝必须 C1 连续，否则法线偏移会在接缝处折叠（geometry.validateTrack 会报 CURVATURE_OFFSET）。

local GEO = require('geometry')
local CFG = require('config')

local M = {}

M.UNITS_PER_TURN = 1704   -- 900x900 视图、innerRatio 0.32 下，1 圈螺旋的轨道长

-- ★★ §62 轨道长度按这一关自己的球数定（规则见 DESIGN.md §62）
function M.turnsForBudget(view, budget)
  local D = CFG.DESIGN
  if budget == nil or not (budget > 0) then return D.turns end   -- 无尽关：球无上限，用最长轨道
  local p = CFG.metrics(view.scale).p
  local cap = budget * 1.25
  local perTurn = M.UNITS_PER_TURN * (math.min(view.w, view.h) / 900)
  local t = cap * p / perTurn
  return math.max(0.55, math.min(D.turns, t))   -- 下限 0.55 圈：再短就不像一条"轨道"了
end

-- ★ 与 JS 的接口差异：JS 的函数是对象，可以挂字段（crossReturnSpine 会挂 junctionU）。
--   Lua 的函数不能挂字段，所以这里统一返回"**可调用的表**"（__call），
--   调用方式与 JS 完全相同：fn(u)、fn.junctionU。rng.lua 用的是同一招。
local function callable(f, fields)
  local t = setmetatable({}, { __call = function(_, ...) return f(...) end })
  if fields then
    for k, v in pairs(fields) do t[k] = v end
  end
  return t
end
M.callable = callable

-- 经典螺旋内收：rad 1 -> innerRatio，共 turns 圈
function M.spiralSpine(view, level)
  local D = CFG.DESIGN
  local turns
  if level and level.turns ~= nil then turns = level.turns
  else turns = M.turnsForBudget(view, level and level.ballBudget) end
  local inner = (level and level.innerRatio ~= nil) and level.innerRatio or D.innerRatio
  local phase = -math.pi / 2
  return callable(function(u)
    local th = phase + u * turns * GEO.TAU
    local rad = 1 - (1 - inner) * u
    return { x = view.cx + math.cos(th) * rad * view.rx, y = view.cy + math.sin(th) * rad * view.ry }
  end)
end

-- 遮挡演示骨架：内收螺旋 + 出核孔回程（同一条极坐标曲线，全程 C1 连续）
function M.crossReturnSpine(view, level)
  local r1 = 0.50
  local turnsIn = 1.6
  local turnsOut = 0.9
  local r2 = 0.88
  local th1 = turnsIn * GEO.TAU
  local dth = turnsOut * GEO.TAU
  local a = (1 - r1) / th1
  local b = 2 * (r2 - r1) / dth + a
  local phase = -math.pi / 2

  local function radiusAt(t)
    if t <= th1 then return 1 - (1 - r1) * (t / th1) end
    local s = math.min(1, (t - th1) / dth)
    return r1 - a * dth * s + (a + b) * dth * (s * s * s - s * s * s * s / 2)
  end

  return callable(function(u)
    local t = u * (th1 + dth)
    local th = phase + t
    local rad = radiusAt(t)
    return { x = view.cx + math.cos(th) * rad * view.rx, y = view.cy + math.sin(th) * rad * view.ry }
  end, { junctionU = th1 / (th1 + dth) })
end

return M
end

-- ---------------- chain ----------------
__M["chain"] = function()
-- chain.lua —— src/chain.js 的 Lua 5.3 移植。U3 珠串模型（绳子/推动）。
--
-- ★ 下标约定：**balls[1] 最靠近洞穴（队头），balls[#balls] 是刚冒出来的队尾。**
--   JS 版是 0 基：JS 的 balls[0] = Lua 的 balls[1]，JS 的 balls[n-1] = Lua 的 balls[#balls]。
--   removeRange / insertBall 的下标参数在 Lua 侧一律是 **1 基**。

local CFG = require('config')
local M = {}

-- 相邻两颗球"相接"所需的弧长距离。逐对算半径（两轨球大小不同，1:√2）。
function M.touchDist(mt, a, b)
  return a.r + b.r + mt.linkGap
end

function M.makeChain(mt, opts)
  opts = opts or {}
  local D = CFG.DESIGN
  return {
    mt = mt,
    balls = {},
    speed = 0,
    targetSpeed = opts.speed ~= nil and opts.speed or D.chainSpeed * mt.scale,
    accel = D.chainAccel * mt.scale,
    decel = D.chainDecel * mt.scale,
    slowDistance = D.slowDistance * mt.scale,
    slowFactor = D.slowFactor,
    spawnWp = opts.spawnWp ~= nil and opts.spawnWp or 0,
    stopTime = 0,
    freezeTime = 0,
    nextId = 1,
    stats = { spawned = 0, drained = 0, removed = 0 },
  }
end

-- 速度平滑：加速慢、减速快
function M.smoothSpeed(ch, dt)
  local t = ch.targetSpeed
  if ch.speed < t then
    ch.speed = math.min(t, ch.speed + ch.accel * dt)
  elseif ch.speed > t then
    ch.speed = math.max(t, ch.speed - ch.decel * dt)
  end
  return ch.speed
end

-- 洞穴前的减速带（B7 冻结：slowDistance = 0 即禁用）
function M.speedAtHead(ch, headWp, curveLength)
  if not (ch.slowDistance > 0) then return ch.speed end
  local slope = curveLength - ch.slowDistance
  if headWp <= slope then return ch.speed end
  if headWp >= curveLength then return ch.speed / ch.slowFactor end
  local t = (headWp - slope) / ch.slowDistance
  return ch.speed * (1 - t) + (ch.speed / ch.slowFactor) * t
end

-- 一帧推进：只推队尾 -> 推动逐节向队头传递（遇空隙即断）
function M.advanceChain(ch, dt, curveLength)
  local balls = ch.balls
  local n = #balls                     -- ★ 与 JS 一致：先取 n，后面用这个 n

  -- §57 冻结反应：整链停止前进
  if ch.freezeTime > 0 then
    ch.freezeTime = math.max(0, ch.freezeTime - dt)
    return
  end

  local movedBack = M.advanceBackwardBalls(ch, dt)
  if movedBack then ch.stopTime = math.max(ch.stopTime, CFG.DESIGN.backStopFrames) end
  M.recycleFront(ch)
  if movedBack or ch.stopTime > 0 then
    if ch.stopTime > 0 then ch.stopTime = ch.stopTime - 1 end
    return
  end

  M.smoothSpeed(ch, dt)
  if n == 0 then return end

  local head = balls[1]
  local effSpeed = curveLength ~= nil and M.speedAtHead(ch, head.wp, curveLength) or ch.speed
  balls[n].wp = balls[n].wp + effSpeed * dt

  for i = n - 1, 1, -1 do
    local back = balls[i + 1]
    local front = balls[i]
    local d = back.wp + M.touchDist(ch.mt, front, back)
    if front.wp < d then
      front.visOff = (front.visOff or 0) - (d - front.wp)
      front.wp = d
    end
  end
end

-- 给**某一颗球**施加后退（对应原版 Ball::SetBackwardsCount / SetBackwardsSpeed）。
function M.applyBackward(ch, i, frames, dist)
  local b = ch.balls[i]
  if not b then return nil end
  local f = math.max(1, frames)
  local bl = b.backLeft or 0
  local remain = 0
  if bl > 0 then remain = b.backSpeed * (bl / 60) end
  b.backLeft = math.max(bl, f)
  b.backSpeed = (remain + dist) / (b.backLeft / 60)
  return b.backSpeed
end

function M.hasBackward(ch)
  local balls = ch.balls
  for i = 1, #balls do
    if (balls[i].backLeft or 0) > 0 then return true end
  end
  return false
end

-- ★ CurveMgr::AdvanceBackwardBalls 的同构实现：从洞端扫到出球端
function M.advanceBackwardBalls(ch, dt)
  local balls = ch.balls
  local anyMoved, collided, speed = false, false, 0
  for i = 1, #balls do
    local b = balls[i]
    if (b.backLeft or 0) > 0 then
      speed = b.backSpeed
      b.wp = b.wp - speed * dt
      b.backLeft = b.backLeft - 1
      collided = true
      anyMoved = true
    end
    if collided then
      local nb = balls[i + 1]
      if not nb then break end                 -- ★ 与 JS 的 break 一致
      local T = M.touchDist(ch.mt, b, nb)
      if b.wp - nb.wp <= T + 1e-6 then
        nb.wp = nb.wp - speed * dt             -- 挨着 -> 同速拖
      else
        local over = (b.wp - T) - nb.wp
        if over < speed * dt then
          nb.wp = b.wp - T
          speed = dt > 0 and (over / dt) or 0
        else
          collided = false                     -- 缝太大 -> 停止传递
        end
      end
    end
  end
  return anyMoved
end

-- 回收滚出出球端的球（原版 RemoveBallsAtFront）
function M.recycleFront(ch)
  local balls = ch.balls
  local cut = 0
  while cut < #balls and balls[#balls - cut].wp < ch.spawnWp do cut = cut + 1 end
  for _ = 1, cut do table.remove(balls) end
  if cut > 0 then
    ch.stats.leftField = (ch.stats.leftField or 0) + cut
  end
  return cut
end

-- 从队尾冒一颗新球；必须等队尾让出位置
function M.spawnBall(ch, base, radius)
  local balls = ch.balls
  local r = radius ~= nil and radius or ch.mt.R
  local cand = { wp = ch.spawnWp, base = base, r = r, id = ch.nextId }
  ch.nextId = ch.nextId + 1                   -- ★ 与 JS 一致：先自增（即使后面 return nil）
  if #balls > 0 then
    local tail = balls[#balls]
    if tail.wp < cand.wp + M.touchDist(ch.mt, cand, tail) then return nil end
  end
  balls[#balls + 1] = cand
  ch.stats.spawned = ch.stats.spawned + 1
  return cand
end

-- 队头越过洞穴即被吸入
function M.drainHead(ch, curveLength)
  local out = {}
  local balls = ch.balls
  while #balls > 0 and balls[1].wp >= curveLength do
    out[#out + 1] = table.remove(balls, 1)
    ch.stats.drained = ch.stats.drained + 1
  end
  return out
end

-- 按"相接"判据切出连续段（队头在前）。返回的 i0/i1 是 **1 基**。
function M.chainRuns(ch)
  local balls = ch.balls
  local runs = {}
  if #balls == 0 then return runs end
  local i0 = 1
  for i = 1, #balls - 1 do
    local linked = (balls[i].wp - balls[i + 1].wp) <= M.touchDist(ch.mt, balls[i], balls[i + 1]) + 1e-6
    if not linked then
      runs[#runs + 1] = { i0 = i0, i1 = i }
      i0 = i + 1
    end
  end
  runs[#runs + 1] = { i0 = i0, i1 = #balls }
  return runs
end

function M.chainHasGap(ch)
  return #M.chainRuns(ch) > 1
end

-- 闭区间移除（1 基闭区间）
function M.removeRange(ch, i0, i1)
  local balls = ch.balls
  local removed = {}
  for _ = 1, (i1 - i0 + 1) do
    removed[#removed + 1] = table.remove(balls, i0)
  end
  ch.stats.removed = ch.stats.removed + #removed
  return removed
end

-- 预装珠串：i=0 放在队头（wp 最大），队尾正好落在 wp=0 的冒球口。
-- ★ 必须把下标 i 传给回调（§60）：固定开局序列要靠它取第 i 颗。
function M.prefillChain(ch, count, baseFn)
  local opts = { r = ch.mt.R }
  local T = M.touchDist(ch.mt, opts, opts)
  for i = 0, count - 1 do
    table.insert(ch.balls, 1, {
      wp = i * T, base = baseFn(i), r = ch.mt.R, id = ch.nextId,
      n = i, paired = false, pairBase = nil,
    })
    ch.nextId = ch.nextId + 1
  end
  return ch
end

-- 把一颗球插进珠串（U12 加球）。index 是 **1 基**。
function M.insertBall(ch, index, ball)
  table.insert(ch.balls, index, ball)
  if ch.stats.inserted == nil then ch.stats.inserted = 0 end
  ch.stats.inserted = ch.stats.inserted + 1
  return ball
end

function M.chainLength(ch)
  return #ch.balls
end

return M
end

-- ---------------- run ----------------
__M["run"] = function()
-- run.lua —— src/run.js 的 Lua 5.3 移植。三消道的 3N 消除。纯逻辑。
--
-- 记号：x_i ∈ {0,1} 表示序列里第 i 颗主链球是否"已被读出"。
-- ★ 这里的"序列"就是 chain.balls 的顺序：balls[1] = 洞端，balls[#balls] = 出球端。

local M = {}

-- 标记是否已"定型"（吸附飞行结束）。1 和 2 都算标记，只是含义不同。
function M.isMarked(b)
  return b.paired == true and (b.dock == nil or b.dock >= 1)
end

-- 定型后的状态值：0 = 空、1 = 正确配对、2 = 错误配对。
function M.markFinal(b)
  if not M.isMarked(b) then return 0 end
  return b.wrongMark == true and 2 or 1
end

-- 一颗球是否"已被读出"（x=1）：**正确**配对，且吸附飞行已完成。
-- 注意：错误配对（2）在这里和 0 一样返回 false —— 所以 2 会像 0 一样断开 run。
function M.isDocked(b)
  return M.isMarked(b) and b.wrongMark ~= true
end

-- ★ 爆炸判定（DESIGN.md §32 / §34）。返回下标（1 基），无则返回 -1。
function M.findExplosion(chain)
  local balls = chain.balls
  for i = 2, #balls - 1 do
    if M.markFinal(balls[i]) == 2 then
      local l = M.markFinal(balls[i - 1])
      local r = M.markFinal(balls[i + 1])
      if l ~= 0 and r ~= 0 then
        if (l == 1) == (r == 1) then return i end
      end
    end
  end
  return -1
end

-- run = 标记序列上的极大连续区间（只看序列相邻，与出球道的物理空隙无关）
function M.computeRuns(chain)
  local balls = chain.balls
  local runs = {}
  local cur = nil
  for i = 1, #balls do
    local b = balls[i]
    if not M.isDocked(b) then
      cur = nil
    else
      if cur == nil then
        cur = { i0 = i, i1 = i, len = 1, key = b.id }
        runs[#runs + 1] = cur
      else
        cur.i1 = i
        cur.len = cur.len + 1
      end
    end
  end
  return runs
end

-- 当前所有"该消"的段：长度是 3 的倍数且 >= 3
function M.clearableRuns(chain)
  local out = {}
  local runs = M.computeRuns(chain)
  for i = 1, #runs do
    local r = runs[i]
    if r.len >= 3 and r.len % 3 == 0 then out[#out + 1] = r end
  end
  return out
end

-- ==================== 经典祖玛（DESIGN.md §66）====================
-- ★★ 纯追加：上面的 computeRuns / clearableRuns（RNA 配对玩法用的）**一个字都没动**。
-- 规则差异：RNA 是"已配对标记的球、连续段长度是 3 的倍数"；经典是"**同色**连续段 ≥ 3"。
-- 和 src/run.js 的 classicRuns / classicClearable 一一对应（进对拍）。
function M.classicRuns(chain)
  local balls = chain.balls
  local runs = {}
  local cur = nil
  for i = 1, #balls do
    local b = balls[i]
    if cur == nil or cur.base ~= b.base then
      cur = { i0 = i, i1 = i, len = 1, base = b.base, key = b.id }
      runs[#runs + 1] = cur
    else
      cur.i1 = i
      cur.len = cur.len + 1
    end
  end
  return runs
end

function M.classicClearable(chain)
  local out = {}
  local runs = M.classicRuns(chain)
  for i = 1, #runs do
    if runs[i].len >= 3 then out[#out + 1] = runs[i] end
  end
  return out
end

-- 给渲染用的读数
function M.runStatus(run)
  local mod = run.len % 3 == 0
  return {
    len = run.len,
    mod = mod,
    toNext = mod and 0 or (3 - (run.len % 3)),
  }
end

return M
end

-- ---------------- projectile ----------------
__M["projectile"] = function()
-- projectile.lua —— src/projectile.js 的 Lua 5.3 移植。
-- 扫掠判据 = "胶囊测试"（线段到球心的距离 <= 半径和），等价于连续时间的圆-圆相交。

local CFG = require('config')
local M = {}

function M.makeProjectile(shot, mt, mode)
  local D = CFG.DESIGN
  local speed = D.shotSpeed * mt.scale
  return {
    x = shot.x, y = shot.y, px = shot.x, py = shot.y,
    vx = math.cos(shot.angle) * speed,
    vy = math.sin(shot.angle) * speed,
    r = (mode == 'insert' and mt.R or mt.r) * D.shotRadiusRatio,
    base = shot.base,
    elem = shot.elem or nil,
    life = 0,
  }
end

function M.advanceProjectile(p, dt)
  p.px, p.py = p.x, p.y
  p.x = p.x + p.vx * dt
  p.y = p.y + p.vy * dt
  p.life = p.life + dt
  return p
end

-- 在 (x0,y0)->(x1,y1) 这一段位移上找**最先**撞到的球。
-- 返回 { index = i(1 基), t = , x = , y = } 或 nil。
function M.sweepHit(balls, x0, y0, x1, y1, pr, skipPaired)
  local dx, dy = x1 - x0, y1 - y0
  local len2 = dx * dx + dy * dy
  local best, bestT, hx, hy = -1, math.huge, 0, 0
  if skipPaired == nil then skipPaired = true end
  for i = 1, #balls do
    local b = balls[i]
    -- ★ 本帧刚冒出来、还没 syncBeads 的球没有 x/y。
    --   JS 那边 x 是 undefined -> 全是 NaN -> 所有比较为 false -> 自然地"跳过"这颗。
    --   Lua 里对 nil 做算术会直接报错，所以这里显式跳过 —— 语义与 JS 完全一致。
    if b.x ~= nil and b.y ~= nil and not (skipPaired and b.paired == true) then
      local rr = pr + b.r
      local t = 0
      if len2 > 1e-12 then
        t = ((b.x - x0) * dx + (b.y - y0) * dy) / len2
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
      end
      local cx, cy = x0 + dx * t, y0 + dy * t
      local ddx, ddy = b.x - cx, b.y - cy
      if ddx * ddx + ddy * ddy <= rr * rr then
        if t < bestT then bestT, best, hx, hy = t, i, cx, cy end
      end
    end
  end
  if best < 0 then return nil end
  return { index = best, t = bestT, x = hx, y = hy }
end

function M.projectileExpired(p, view, mt)
  local D = CFG.DESIGN
  if p.life > D.shotMaxLife then return true end
  local m = mt.R * 8
  return p.x < -m or p.y < -m or p.x > view.w + m or p.y > view.h + m
end

return M
end

-- ---------------- ribosome ----------------
__M["ribosome"] = function()
-- ribosome.lua —— src/ribosome.js 的 Lua 5.3 移植。U6 核糖体（玩家）。
--
-- ★★ 这个文件里**每一次 rng 抽样都必须与 JS 严格同序**：
--   makeRibosome 抽 4 次（2 碱基 + 2 元素），drawBase 抽 1~2 次，refreshStale 最多 6 次/颗。
--   少一次或多一次，后面的整条随机序列就全错位 —— 而且**不会报错**，只会"玩起来不一样"。
--   只有逐值对拍能抓到这类错。

local CFG = require('config')
local EL = require('elements')

local M = {}

function M.makeRibosome(x, y, mt, rng)
  return {
    x = x, y = y,
    r = CFG.DESIGN.ribosomeRadius * mt.scale,
    aim = -math.pi / 2,
    loaded = { rng.pick(CFG.BASES), rng.pick(CFG.BASES) },          -- [1] 在炮口，[2] 待命
    loadedElem = { rng.pick(EL.ELEMENTS), rng.pick(EL.ELEMENTS) },
    cooldown = 0,
    tokens = CFG.BASES,
    rng = rng,
  }
end

function M.aimAt(rb, tx, ty)
  -- Lua 5.3 没有 math.atan2：两参数的 math.atan(y, x) 就是 atan2
  rb.aim = math.atan(ty - rb.y, tx - rb.x)
  return rb.aim
end

function M.rotateAim(rb, d)
  rb.aim = rb.aim + d
  return rb.aim
end

function M.swapLoaded(rb)
  rb.loaded[1], rb.loaded[2] = rb.loaded[2], rb.loaded[1]
  if rb.loadedElem then
    rb.loadedElem[1], rb.loadedElem[2] = rb.loadedElem[2], rb.loadedElem[1]
  end
  return rb.loaded[1]
end

-- 抽一个身份 token。挂了 poolFn（场景给的加权池）就按 bagBias 的概率从池里抽。
function M.drawBase(rb)
  if rb.poolFn and rb.rng() < CFG.DESIGN.bagBias then
    local pool = rb.poolFn()
    if pool and #pool > 0 then
      -- ★ 避免和手里那颗重复（DESIGN.md §39）
      local cand = pool
      if #pool > 1 and rb.loaded and rb.loaded[1] then
        local alt = {}
        for i = 1, #pool do
          if pool[i] ~= rb.loaded[1] then alt[#alt + 1] = pool[i] end
        end
        if #alt > 0 then cand = alt end
      end
      return rb.rng.pick(cand)
    end
  end
  return rb.rng.pick(rb.tokens or CFG.BASES)
end

-- ★★ 过期刷新（DESIGN.md §54）：手里的珠子若"场上已经没有它能配的未配对球"，就重抽。
function M.refreshStale(rb)
  if not (rb.poolFn and rb.freshFn) then return end
  for k = 1, #rb.loaded do
    if not rb.freshFn(rb.loaded[k]) then
      for _ = 1, 6 do
        local nb = M.drawBase(rb)
        if rb.freshFn(nb) then rb.loaded[k] = nb; break end
      end
    end
  end
end

-- 抽一个元素。不做"必须可附着"的硬过滤，只保证不会连着两颗都是风/岩。
function M.drawElem(rb)
  local first = rb.loadedElem and rb.loadedElem[1]
  local pool
  if first == 'anemo' or first == 'geo' then
    pool = {}
    for i = 1, #EL.ELEMENTS do
      if EL.canAttach(EL.ELEMENTS[i]) then pool[#pool + 1] = EL.ELEMENTS[i] end
    end
  else
    pool = EL.ELEMENTS
  end
  return rb.rng.pick(pool)
end

function M.tickRibosome(rb, dt)
  M.refreshStale(rb)
  if rb.cooldown > 0 then rb.cooldown = math.max(0, rb.cooldown - dt) end
end

function M.canFire(rb)
  return rb.cooldown <= 0
end

function M.fire(rb)
  if rb.cooldown > 0 then return nil end
  local shot = {
    x = rb.x + math.cos(rb.aim) * rb.r,
    y = rb.y + math.sin(rb.aim) * rb.r,
    angle = rb.aim,
    base = rb.loaded[1],
    elem = rb.loadedElem and rb.loadedElem[1] or nil,
  }
  rb.loaded[1] = rb.loaded[2]
  rb.loaded[2] = M.drawBase(rb)
  if rb.loadedElem then rb.loadedElem[2] = M.drawElem(rb) end
  rb.cooldown = CFG.DESIGN.fireCooldown
  return shot
end

return M
end

-- ---------------- board ----------------
__M["board"] = function()
-- board.lua —— src/scene.js 的 Lua 5.3 移植（**规则层**：装配 + 每帧推进 + 结算）。
--
-- ★ 与 scene.js 的差异只有两条（其余逐字对应）：
--   1. 下标 1 基（Lua 惯例）。balls[1] = 洞端，balls[#balls] = 出球端。
--   2. 关卡用**纯数据**（level.spineKind）而不是 level.makeSpine 函数 ——
--      真实关卡数据里不该有函数，这对千星奇域尤其重要（那边的关卡是表）。
--
-- 没移植：七球模式（元素反应）。sc.mode == 'seven' 时不工作。
-- 已移植：装配、命中分流、加球/并入、结算循环（爆炸 + 3n 消）、后退冲量、生命、分数、过关。

local CFG = require('config')
local GEO = require('geometry')
local RNG = require('rng')
local CH = require('chain')
local RUN = require('run')
local PJ = require('projectile')
local RB = require('ribosome')
local SP = require('spines')
local EL = require('elements')

local M = {}
local DESIGN = CFG.DESIGN

-- ==================== §60 固定开局序列的解析 ====================

function M.parseScript(str)
  local out = {}
  for i = 1, #str do
    local c = str:sub(i, i)
    if c ~= ' ' and c ~= ',' and c ~= '|' then
      -- 数字是**紧跟着上一颗球的标记**，不是独立的一颗球
      if c == '0' or c == '1' or c == '2' then
        if #out > 0 then out[#out] = out[#out]:sub(1, 1) .. c end
      else
        out[#out + 1] = c
      end
    end
  end
  return out
end

-- "A" 未配对 / "A1" 已正确读出 / "A2" 配错（灰球）
function M.parseScriptEntry(tok)
  local d = tok:sub(2, 2)
  local mark = (d == '1') and 1 or ((d == '2') and 2 or 0)
  return { base = tok:sub(1, 1), mark = mark, paired = mark ~= 0 }
end

function M.allowedComplements(sc, base)
  local c = CFG.COMPLEMENT[base]
  if not c then return {} end
  local pool = sc.bases or CFG.BASES
  local out = {}
  for i = 1, #c do
    for j = 1, #pool do
      if pool[j] == c[i] then out[#out + 1] = c[i]; break end
    end
  end
  return out
end

function M.inPool(sc, base)
  local pool = sc.bases or CFG.BASES
  for i = 1, #pool do if pool[i] == base then return true end end
  return false
end

-- 珠袋可用池（去重）。七球模式未移植。
function M.usefulPool(sc)
  local out = {}
  if sc.mode == 'seven' then return out end
  local balls = sc.chain.balls
  for i = 1, #balls do
    local b = balls[i]
    if not b.paired then
      local c = M.allowedComplements(sc, b.base)
      for k = 1, #c do
        local seen = false
        for j = 1, #out do if out[j] == c[k] then seen = true; break end end
        if not seen then out[#out + 1] = c[k] end
      end
    end
  end
  return out
end

-- ★★ 加权池（DESIGN.md §54）：**不去重** —— 场上每有一颗粒子需要某个碱基，它就多出现一次。
function M.weightedPool(sc)
  local out = {}
  if sc.mode == 'seven' then return out end
  local balls = sc.chain.balls
  for i = 1, #balls do
    local b = balls[i]
    if not b.paired then
      local c = M.allowedComplements(sc, b.base)
      for k = 1, #c do out[#out + 1] = c[k] end
    end
  end
  return out
end

-- 轨道上的球心 = 骨架点 + 法线偏移（k：0 = 贴合主轨，1 = 完全落到三消道）
function M.beadPos(path, rail, wp, k)
  local s = k == nil and 1 or k
  local p = path:pointAt(wp)
  local n = path:normalAt(wp)
  return { x = p.x + n.x * rail.offset * s, y = p.y + n.y * rail.offset * s, z = p.z }
end

local function makeSpine(level, view)
  if level.spineKind == 1 then return SP.crossReturnSpine(view, level) end
  return SP.spiralSpine(view, level)
end

-- ==================== 装配 ====================

-- 按关卡配方把珠串铺上轨道（assembleScene 与 restartBoard 共用一份 —— 单一真源）
local function fillChain(sc, ch)
  local level = sc.level
  if level.script then
    local bs2 = M.parseScript(level.script)
    local n = #bs2
    -- 下标方向：prefillChain 的第 i 次调用对应 wp = i*T，而 balls[1] = 洞端，
    -- 所以脚本的第 1 颗要放到**最后一次**调用。
    CH.prefillChain(ch, n, function(i) return M.parseScriptEntry(bs2[n - i]).base end)
    for i = 1, #ch.balls do
      local spec = M.parseScriptEntry(bs2[i])
      local b = ch.balls[i]
      if spec.mark ~= 0 then
        local c = CFG.COMPLEMENT[b.base]
        b.paired = true
        b.wrongMark = (spec.mark == 2)
        b.pairBase = (c and #c > 0) and c[1] or nil
        b.dock = 1
      end
    end
  else
    CH.prefillChain(ch, level.prefill or 14, function() return sc.rng.pick(sc.bases) end)
  end
  -- 用**占轨道全长的比例**：语义是"让**队头**落在这个比例处"
  if level.startWpFrac and #ch.balls > 0 then
    local off = level.startWpFrac * sc.path.length - ch.balls[1].wp
    if off > 0 then
      for i = 1, #ch.balls do ch.balls[i].wp = ch.balls[i].wp + off end
    end
  end
  -- 静止练习关：把整链摆到轨道正中间
  if level.centerChain and #ch.balls > 0 then
    local lo, hi = math.huge, -math.huge
    for i = 1, #ch.balls do
      lo = math.min(lo, ch.balls[i].wp); hi = math.max(hi, ch.balls[i].wp)
    end
    local off = sc.path.length / 2 - (lo + hi) / 2
    for i = 1, #ch.balls do ch.balls[i].wp = ch.balls[i].wp + off end
  end
end
M.fillChain = fillChain

function M.assembleScene(level, view, seed)
  local mt = CFG.metrics(view.scale)
  local spine = makeSpine(level, view)
  local path = GEO.buildPath(spine, { samples = DESIGN.pathSamples, center = { x = view.cx, y = view.cy } })
  local spec = nil
  if level.layersFromJunction then
    local cut = path:sAtU(spine.junctionU or 0.64)
    spec = { { from = 0, to = cut, z = 0 }, { from = cut, to = path.length, z = 1 } }
  end
  GEO.assignLayers(path, spec)

  local sign = (level.railOrder == 'spawn-outer') and 1 or -1
  local rails = {
    spawn = { id = 'spawn', offset = sign * mt.d / 2, radius = mt.R },
    eliminate = { id = 'eliminate', offset = -sign * mt.d / 2, radius = mt.r },
  }
  local railPolys = {
    spawn = GEO.buildRail(path, rails.spawn.offset),
    eliminate = GEO.buildRail(path, rails.eliminate.offset),
  }
  local runs = { spawn = GEO.layerRuns(path), eliminate = GEO.layerRuns(path) }
  local zLevels = {}
  for i = 1, #runs.spawn do
    local z = runs.spawn[i].z
    local seen = false
    for j = 1, #zLevels do if zLevels[j] == z then seen = true; break end end
    if not seen then zLevels[#zLevels + 1] = z end
  end
  table.sort(zLevels)

  local issues = GEO.validateTrack(path, mt, { rails = { rails.spawn.offset, rails.eliminate.offset } })

  local rng = RNG.makeRng(seed)
  local chain = CH.makeChain(mt, {})
  local rb = RB.makeRibosome(view.cx, view.cy, mt, rng)

  local sc = {
    level = level, spine = spine, metrics = mt, path = path, rails = rails,
    railPolys = railPolys, runs = runs, zLevels = zLevels, issues = issues,
    view = view, rng = rng, chain = chain, rb = rb,
    projectiles = {}, merges = {}, events = {}, spawnCount = 0, drained = 0,
    winReason = nil,
    still = (level.still == true),
    noClear = (level.noClear == true),
    goalMatchAll = (level.goal == 'matchAll'),
    shields = 0, cores = {}, nextCoreId = 1, lastReaction = nil, reactionFlash = 0,
    stopAdding = (level.stopAdding == true),
    mode = DESIGN.defaultMode, modeFlash = 0,
    -- 经典祖玛（DESIGN §66）：rules = 'classic' 走"同色连续≥3消"，与 RNA 玩法完全分开
    rules = level.rules or 'rna',
    lives = DESIGN.startLives, score = 0, losing = false, gameOver = false, won = false,
    runsInfo = {}, lastClear = nil,
    stats = { fired = 0, pairs = 0, mismatches = 0, merges = 0, cleared = 0, codons = 0, lost = 0,
              explosions = 0, reactions = 0, cores = 0, freezes = 0, reactionRemoves = 0 },
    beads = { spawn = {}, eliminate = {} },
  }

  sc.bases = (level.bases and #level.bases > 0) and level.bases or CFG.BASES
  fillChain(sc, chain)
  if level.still then
    chain.targetSpeed = 0
  elseif level.speed ~= nil then
    chain.targetSpeed = level.speed * mt.scale
  end
  sc.spawnCount = #chain.balls

  rb.poolFn = function() return M.weightedPool(sc) end
  rb.freshFn = function(tok)
    local bs = sc.chain.balls
    for i = 1, #bs do
      if not bs[i].paired then
        if sc.mode == 'seven' then
          error('七球模式未移植')
        elseif CFG.isComplement(tok, bs[i].base) and M.inPool(sc, tok) then
          return true
        end
      end
    end
    return false
  end
  rb.tokens = (sc.mode == 'seven') and EL.ELEMENTS or (sc.bases or CFG.BASES)
  rb.loaded = {}
  rb.loaded[1] = RB.drawBase(rb)
  rb.loaded[2] = RB.drawBase(rb)
  M.syncBeads(sc)
  return sc
end

-- 经典祖玛（§66）：规则函数按 ruleset 选 —— RNA 用"已配对 + 3 的倍数"，经典用"同色 ≥3"。
local function clearableFor(sc)
  return (sc.rules == 'classic') and RUN.classicClearable(sc.chain) or RUN.clearableRuns(sc.chain)
end
local function refreshRuns(sc)
  sc.runsInfo = (sc.rules == 'classic') and RUN.classicRuns(sc.chain) or RUN.computeRuns(sc.chain)
end

-- 同步"被规则读到"的位置量（渲染用的颜色/描边不在这里，但 pairGlow 留着给 UI 用）
function M.syncBeads(sc)
  local spawn, eliminate = {}, {}
  local balls = sc.chain.balls
  for i = 1, #balls do
    local b = balls[i]
    local wpv = b.wp + (b.visOff or 0)
    b.wpv = wpv
    local p = M.beadPos(sc.path, sc.rails.spawn, wpv, nil)
    b.x, b.y, b.z = p.x, p.y, p.z
    b.index = i
    b.label = b.base
    b.pairGlow = b.paired and (b.wrongMark and CFG.WRONG_GLOW or CFG.complementColor(b.base)) or nil
    spawn[#spawn + 1] = b
    if b.paired then
      local k = b.dock == nil and 1 or b.dock
      local q = M.beadPos(sc.path, sc.rails.eliminate, wpv, k)
      eliminate[#eliminate + 1] = {
        x = q.x, y = q.y, z = q.z, r = sc.metrics.r, base = b.pairBase,
        partner = b, paired = true, wrong = (b.wrongMark == true), docked = (k >= 1), index = i,
      }
    end
  end
  sc.beads.spawn = spawn
  sc.beads.eliminate = eliminate
end

local function pushEvent(sc, ev)
  sc.events[#sc.events + 1] = ev
  if #sc.events > 64 then
    for _ = 1, #sc.events - 64 do table.remove(sc.events, 1) end
  end
end
M.pushEvent = pushEvent

-- ==================== 命中分流 ====================

local function resolveHit(sc, p, hit)
  local ball = sc.chain.balls[hit.index]
  local ev = { type = '', index = hit.index, x = hit.x, y = hit.y, base = p.base,
               target = ball.base, mode = p.mode }
  if sc.mode == 'seven' then error('七球模式未移植') end
  if sc.rules == 'classic' then
    ev.type = 'insert'
    local mgc = M.startMerge(sc, ball, p.base, hit.x, hit.y)
    mgc.elem = p.elem or nil
    ev.willMerge = true
    pushEvent(sc, ev)
    return ev
  end
  if p.mode == 'insert' then
    ev.type = 'insert'
    local mg = M.startMerge(sc, ball, p.base, hit.x, hit.y)
    mg.elem = p.elem or nil
    ev.willMerge = true
  elseif CFG.isComplement(p.base, ball.base) then
    ball.paired = true
    ball.wrongMark = false
    ball.pairBase = p.base
    ball.dock = 0
    ev.type = 'pair'
    sc.stats.pairs = sc.stats.pairs + 1
  else
    ball.paired = true
    ball.wrongMark = true
    ball.pairBase = p.base
    ball.dock = 0
    ev.type = 'mismatch'
    sc.stats.mismatches = sc.stats.mismatches + 1
  end
  pushEvent(sc, ev)
  return ev
end
M.resolveHit = resolveHit

-- ★ 命中侧判定（§49）：flag = (子弹位置 − 球心) × 轨道法线 < 0 -> 插在靠洞那一侧
function M.startMerge(sc, target, base, hitX, hitY)
  local n = sc.path:normalAt(target.wp)
  local dx = (hitX == nil and target.x or hitX) - target.x
  local dy = (hitY == nil and target.y or hitY) - target.y
  local inFront = (dx * n.y - dy * n.x) < 0
  local m = {
    targetId = target.id, base = base, inFront = inFront, t = 0,
    x = target.x, y = target.y, z = target.z, r = sc.metrics.r,
  }
  sc.merges[#sc.merges + 1] = m
  sc.stats.merges = sc.stats.merges + 1
  pushEvent(sc, { type = 'merge', base = base, index = target.index })
  return m
end

-- 返回 1 基下标，找不到返回 -1
function M.findBallIndex(ch, id)
  for i = 1, #ch.balls do if ch.balls[i].id == id then return i end end
  return -1
end

local function updateMerges(sc, dt)
  local mt = sc.metrics
  for i = #sc.merges, 1, -1 do
    local m = sc.merges[i]
    local idx = M.findBallIndex(sc.chain, m.targetId)
    if idx < 0 then
      table.remove(sc.merges, i)          -- 目标被消掉了，并入作废
    else
      local target = sc.chain.balls[idx]
      m.t = m.t + dt / DESIGN.mergeTime
      local k = math.min(1, m.t)
      local T = CH.touchDist(sc.chain.mt, target, { r = mt.R })
      local wp = m.inFront and (target.wp + T * k) or math.max(0, target.wp - T * k)
      local p = M.beadPos(sc.path, sc.rails.spawn, wp, nil)
      m.x, m.y, m.z = p.x, p.y, p.z
      m.r = mt.r + (mt.R - mt.r) * k
      if m.t >= 1 then
        -- 下标 1 = 洞端。插在靠洞那侧 -> idx；靠出球端那侧 -> idx+1
        local at = m.inFront and idx or (idx + 1)
        local nb = {
          wp = wp, base = m.base, r = mt.R, id = sc.chain.nextId,
          n = nil, paired = false, wrongMark = false, pairBase = nil, dock = nil,
          elem = m.elem or nil,
        }
        sc.chain.nextId = sc.chain.nextId + 1
        CH.insertBall(sc.chain, at, nb)
        if DESIGN.insertPairs then M.tryInsertPair(sc, at) end
        table.remove(sc.merges, i)
      end
    end
  end
end

-- 加球的正反馈（§18）：插入后若与**任一邻居**互补，这颗新球自己获得绑定小球。
function M.tryInsertPair(sc, i)
  local balls = sc.chain.balls
  local b = balls[i]
  if not b or b.paired then return nil end
  local head = balls[i - 1]
  local tail = balls[i + 1]
  local mate = nil
  if head and CFG.isComplement(b.base, head.base) then
    mate = head
  elseif tail and CFG.isComplement(b.base, tail.base) then
    mate = tail
  end
  if not mate then return nil end
  b.paired = true
  b.wrongMark = false
  b.pairBase = mate.base
  b.dock = 0
  pushEvent(sc, { type = 'insert-pair', base = b.base, with = mate.base })
  return b
end

local function updateProjectiles(sc, dt)
  local list = sc.projectiles
  for i = #list, 1, -1 do
    local p = list[i]
    PJ.advanceProjectile(p, dt)
    local hit = PJ.sweepHit(sc.chain.balls, p.px, p.py, p.x, p.y, p.r, p.mode ~= 'insert')
    if hit then
      resolveHit(sc, p, hit)
      table.remove(list, i)
    elseif PJ.projectileExpired(p, sc.view, sc.metrics) then
      table.remove(list, i)
    end
  end
end

-- ★ 消除后退（§42）：消掉 k 颗 -> 往出球端方向共退 k 个球位。
--   判定条件只有一个：**消除段是不是贴在洞端**（headEnd <= 1 就不退 —— 删除本身已经兑现过奖励）。
--
--   ⚠ headEnd 在 Lua 侧是 **1 基**下标：JS 的条件是 headEnd <= 0（0 基），
--     换算过来就是 <= 1。这一处差一位曾经让"爆炸后退"整条路径对不上（对拍抓到过）。
local function pushBack(sc, clearedCount, headEnd)
  local ch = sc.chain
  if #ch.balls == 0 then return nil end
  if headEnd == nil or headEnd <= 1 then return nil end
  local T = CH.touchDist(ch.mt, { r = sc.metrics.R }, { r = sc.metrics.R })
  return CH.applyBackward(ch, 1, DESIGN.backFrames, clearedCount * T)   -- Lua 下标 1 = 洞端
end

-- ★ 过关：分数达标 / 场上清空 / 全部读出（三选一）。
local function win(sc, reason)
  if sc.won then return false end
  sc.won = true
  sc.stopAdding = true
  sc.winReason = reason
  pushEvent(sc, { type = 'win', score = sc.score, reason = reason })
  return true
end
M.win = win

-- ★ 爆炸：移除那颗 2 **加上左右各一颗**，共 3 颗。i 是 1 基下标。
--   爆炸**不施加**后退冲量 —— 后退是 3n 消的奖励，爆炸是玩家主动付出的成本。
local function explodeAt(sc, i)
  local bs = sc.chain.balls
  local pat = {
    (i - 2 >= 1) and RUN.markFinal(bs[i - 2]) or -1,
    (i - 1 >= 1) and RUN.markFinal(bs[i - 1]) or -1,
    2,
    (i + 1 <= #bs) and RUN.markFinal(bs[i + 1]) or -1,
    (i + 2 <= #bs) and RUN.markFinal(bs[i + 2]) or -1,
  }
  local removed = CH.removeRange(sc.chain, i - 1, i + 1)
  sc.stats.explosions = sc.stats.explosions + 1
  pushEvent(sc, { type = 'explode', index = i, n = #removed, pat = pat })
  -- 爆炸也走后退 —— 它移除 3 颗，和 3n 消在几何上完全一样。
  -- headEnd = i - 1：接缝靠洞端那一侧的下界（和 eliminateRun 传 run.i0 同义）。
  pushBack(sc, #removed, i - 1)
  return #removed
end

-- ★ 结算循环（§32）：**先爆炸，后 3n 消，循环到不动点**。
--   一次只处理一个爆炸、从左到右扫 —— 结果因此是确定的。
local function settle(sc)
  local total = 0
  if not sc.noClear then
    for _ = 1, 128 do
      local ei = (sc.rules == 'classic') and -1 or RUN.findExplosion(sc.chain)
      if ei >= 0 then
        total = total + explodeAt(sc, ei)
      else
        local cleared = M.clearImmediately(sc)
        if cleared == 0 then break end
        total = total + cleared
      end
    end
  end
  refreshRuns(sc)

  -- §64 读出全部：判据用 mark ~= 0（读对读错都算"打中过"）
  if sc.goalMatchAll and not sc.losing and not sc.gameOver and not sc.won and #sc.chain.balls > 0 then
    local all = true
    for i = 1, #sc.chain.balls do
      if RUN.markFinal(sc.chain.balls[i]) == 0 then all = false; break end
    end
    if all then win(sc, 'match') end
  end

  -- 清空过关：**预算已发满** + 场上不足 3 颗（不足 3 颗 = 逻辑上已经不可能再消）
  if DESIGN.winOnClear and not sc.losing and not sc.gameOver and not sc.won and #sc.chain.balls < 3 then
    local bud = sc.level.ballBudget ~= nil and sc.level.ballBudget or DESIGN.ballBudget
    if bud > 0 and sc.spawnCount >= bud then win(sc, 'clear') end
  end
  return total
end
M.settle = settle

-- 立即消除 + 级联到不动点（从后往前删，避免下标位移）。
-- ★ 整帧只结算一次后退（同一帧可能连续消多段，每段各施加一次会互相踩到）。
function M.clearImmediately(sc)
  local total = 0
  local minPos = -1
  for _ = 1, 64 do
    local hits = clearableFor(sc)
    if #hits == 0 then break end
    for i = #hits, 1, -1 do
      local run = hits[i]
      total = total + #M.eliminateRun(sc, run)
      if run.i0 > 1 and (minPos < 0 or run.i0 < minPos) then minPos = run.i0 end
    end
  end
  if total > 0 then
    pushBack(sc, total, minPos)
    refreshRuns(sc)
  end
  return total
end

-- 整段消除。消除后**不回填、不瞬移**：留下空隙，由绳模型的后段追上来补。
function M.eliminateRun(sc, run)
  local removed = CH.removeRange(sc.chain, run.i0, run.i1)
  sc.stats.cleared = sc.stats.cleared + #removed
  sc.stats.codons = sc.stats.codons + 1
  local gained = 0
  for k = 1, #removed do gained = gained + DESIGN.scorePerBall * (removed[k].amp or 1) end
  sc.score = sc.score + math.floor(gained + 0.5)
  -- 过关条件一：分数达标
  local sTgt = sc.level.scoreTarget ~= nil and sc.level.scoreTarget or DESIGN.scoreTarget
  if not sc.won and sTgt > 0 and sc.score >= sTgt then win(sc, 'score') end
  sc.lastClear = { i0 = run.i0, i1 = run.i1, len = run.len }
  pushEvent(sc, { type = 'clear', len = run.len, i0 = run.i0, i1 = run.i1 })
  refreshRuns(sc)
  return removed
end

-- A15 失败条件：队头撞到降解洞穴 -> 整条珠串被吸进去，扣 1 命。
function M.startLosing(sc)
  if sc.losing or sc.gameOver then return sc.lives end
  -- 结晶护盾（§57）：晶片抵挡一次洞穴吞噬 —— 不扣命，把整链往回拽一截。
  if sc.shields > 0 then
    sc.shields = sc.shields - 1
    local bs = sc.chain.balls
    if #bs > 0 then
      local pull = 3 * CH.touchDist(sc.chain.mt, bs[1], bs[math.min(2, #bs)])
      for i = 1, #bs do bs[i].wp = math.max(0, bs[i].wp - pull) end
      sc.chain.stopTime = DESIGN.backStopFrames
    end
    pushEvent(sc, { type = 'shieldBlock', shields = sc.shields })
    return sc.lives
  end
  sc.losing = true
  sc.lives = math.max(0, sc.lives - 1)
  sc.stats.lost = sc.stats.lost + 1
  pushEvent(sc, { type = 'losing', lives = sc.lives })
  return sc.lives
end

local function updateLosing(sc, dt)
  local ch = sc.chain
  local endLen = sc.path.length
  local step = DESIGN.losingSpeed * sc.metrics.scale * dt
  local keep = {}
  for i = 1, #ch.balls do
    local b = ch.balls[i]
    b.wp = b.wp + step
    if b.wp < endLen then keep[#keep + 1] = b end
  end
  ch.balls = keep
  M.syncBeads(sc)
  if #ch.balls > 0 then return end
  if sc.lives <= 0 then
    sc.losing = false
    sc.gameOver = true
    pushEvent(sc, { type = 'gameover', score = sc.score })
    return
  end
  M.restartBoard(sc)
end

-- 扣命后重开本关（分数与剩余命保留）
function M.restartBoard(sc)
  local ch = sc.chain
  ch.balls = {}
  ch.speed = 0
  fillChain(sc, ch)
  sc.spawnCount = #ch.balls
  sc.runsInfo = {}
  sc.projectiles = {}
  sc.merges = {}
  sc.cores = {}
  sc.losing = false
  pushEvent(sc, { type = 'restart', lives = sc.lives })
  M.syncBeads(sc)
end

-- ★ 切模式（scene.js setMode 的同构）。只支持 match / insert；七球模式未移植。
--   对应原版的"一发两用"之外的取舍：模式决定这一发干什么，化学只决定匹配模式下的结果。
function M.setMode(sc, mode)
  if mode == 'seven' then error('七球模式未移植') end
  sc.mode = (mode == 'insert') and 'insert' or 'match'
  sc.modeFlash = DESIGN.modeFlashTime
  return sc.mode
end

function M.toggleMode(sc)
  return M.setMode(sc, sc.mode == 'insert' and 'match' or 'insert')
end

function M.fireShot(sc)
  if sc.losing or sc.gameOver or sc.won then return nil end
  local shot = RB.fire(sc.rb)
  if not shot then return nil end
  local p = PJ.makeProjectile(shot, sc.metrics, sc.mode)
  p.mode = sc.mode
  sc.projectiles[#sc.projectiles + 1] = p
  sc.stats.fired = sc.stats.fired + 1
  return p
end

-- 视觉滞后量的指数衰减。纯渲染量，但 visOff 会进 wpv -> x/y，而 x/y 被命中判定读到。
local function decayVisual(sc, dt)
  local k = math.exp(-dt / (DESIGN.retreatTime / 3))
  local balls = sc.chain.balls
  for i = 1, #balls do
    local b = balls[i]
    if b.visOff then
      b.visOff = b.visOff * k
      if math.abs(b.visOff) < 0.05 then b.visOff = 0 end
    end
  end
end

-- 一帧推进：冒球 -> 绳子推进 -> 核糖体/弹丸 -> 吸附 -> 结算 -> 洞穴吞球 -> 同步位置
function M.advanceScene(sc, dt)
  if sc.gameOver then return end
  if sc.won then return end
  if sc.losing then updateLosing(sc, dt); return end
  local ch = sc.chain

  local budget = sc.level.ballBudget ~= nil and sc.level.ballBudget or DESIGN.ballBudget
  local underBudget = budget <= 0 or sc.spawnCount < budget
  if not sc.still and not sc.stopAdding and underBudget and ch.stopTime <= 0 and not CH.hasBackward(ch) then
    local tail = #ch.balls > 0 and ch.balls[#ch.balls].base or nil
    -- ⚠ 本体里 DESIGN.baseRepeat **已经被删掉了**（DESIGN.md §54.1 说它无效），
    --   于是 scene.js 里 sc.rng() < undefined 恒为 false —— 即"永远换成不同的碱基"。
    --   这里照抄这个行为：**抽一次随机数**（必须消耗，否则随机序列错位），但条件恒假。
    local bt = DESIGN.baseRepeat
    local takeRepeat = false
    if tail then
      local r = sc.rng()
      if bt ~= nil and r < bt then takeRepeat = true end
    end
    local base
    if takeRepeat then
      base = tail
    else
      local pool = sc.bases or CFG.BASES
      base = sc.rng.pick(pool)
      local guard = 0
      while base == tail and guard < 16 do
        base = sc.rng.pick(pool)
        guard = guard + 1
      end
    end
    local ball = CH.spawnBall(ch, base)
    if ball then
      ball.n = sc.spawnCount
      sc.spawnCount = sc.spawnCount + 1
    end
  end

  CH.advanceChain(ch, dt, sc.path.length)
  RB.tickRibosome(sc.rb, dt)
  updateProjectiles(sc, dt)
  updateMerges(sc, dt)
  -- tickElements：七球模式专用（草原核/燃烧/冻结）；匹配模式下它什么都不做，故未移植。

  for i = 1, #ch.balls do
    local b = ch.balls[i]
    if not (b.dock == nil or b.dock >= 1) then
      b.dock = math.min(1, b.dock + dt / DESIGN.dockTime)
      if b.dock >= 1 and b.dockDone ~= true then b.dockDone = true end
    end
  end

  if sc.modeFlash > 0 then sc.modeFlash = math.max(0, sc.modeFlash - dt) end
  decayVisual(sc, dt)

  settle(sc)

  if not sc.still and #ch.balls > 0 and ch.balls[1].wp >= sc.path.length then M.startLosing(sc) end

  M.syncBeads(sc)
end

-- 给渲染/测试用的读数（对应 scene.js 的 sceneInfo）
function M.sceneInfo(sc)
  local ch = sc.chain
  local runs = {}
  for i = 1, #sc.runsInfo do runs[i] = sc.runsInfo[i].len end
  return {
    balls = #ch.balls,
    headWp = #ch.balls > 0 and ch.balls[1].wp or 0,
    tailWp = #ch.balls > 0 and ch.balls[#ch.balls].wp or 0,
    speed = ch.speed,
    curveLength = sc.path.length,
    progress = #ch.balls > 0 and (ch.balls[1].wp / sc.path.length) or 0,
    paired = #sc.beads.eliminate,
    runs = runs,
    shots = #sc.projectiles,
  }
end

function M.drainEvents(sc)
  local out = sc.events
  sc.events = {}
  return out
end

return M
end

-- ---------------- levels_data ----------------
__M["levels_data"] = function()
-- levels_data.lua —— 由 miliastra/tools/export-levels.mjs 从 src/levels.js 生成，**不要手改**。
--
-- ★ 与 levels.js 的唯一结构差异：level.makeSpine 是一个**函数**，跨语言传不过去，
--   所以换成 spineKind（0 = 螺旋，1 = 交叉桥）；与之配套的 level.layers 也换成
--   layersFromJunction（分层切在骨架的 junctionU 处）。
--
-- 关卡顺序：新手关在前，原本那四个核心关在后（= ALL_LEVELS 的顺序）。
-- 字段含义见 DESIGN.md §5.3 / §55 / §60，以及 docs/05-移植方案.md。

local M = {}

M.LEVELS = {
  {
    id = "t1-pair",
    name = "① 配对",
    short = "配对",
    rules = "rna",
    group = nil,
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = 0.75,
    innerRatio = nil,
    prefill = 12,
    ballBudget = 12,
    scoreTarget = math.huge,
    still = true,
    centerChain = true,
    noClear = true,
    goal = "matchAll",
    speed = nil,
    startWpFrac = nil,
    bases = nil,
    script = nil,
    hint = { "球面颜色和字母互为反色 —— 打一颗反色的，就把它「读出」。", "这一关不用凑三颗：把 12 颗全读出来就过关。" },
  },
  {
    id = "t2-multiple",
    name = "② 三的倍数",
    short = "三的倍数",
    rules = "rna",
    group = nil,
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = 0.75,
    innerRatio = nil,
    prefill = nil,
    ballBudget = 9,
    scoreTarget = math.huge,
    still = true,
    centerChain = true,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = nil,
    script = "A1 A1 A1 A1 A0 U0 G0 C0 U0",
    hint = { "这一关开始要消球了：连着读出的球**必须是 3 的倍数**才能消。", "看徽章上的「还差 M」—— 差几颗就再补几颗。" },
  },
  {
    id = "t3-wrong",
    name = "③ 配错的代价",
    short = "配错的代价",
    rules = "rna",
    group = nil,
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = 0.75,
    innerRatio = nil,
    prefill = nil,
    ballBudget = 12,
    scoreTarget = math.huge,
    still = true,
    centerChain = true,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = nil,
    script = "A1 A2 A1 A0 U0 A0 U0 A0 U0 A0 U0 A0",
    hint = { "打错颜色 = 灰球。灰球**不会立刻炸** ——", "要等它左右两颗都已经读出、而且**状态一样**（都配对 / 都配错）时，才连它一起炸掉 3 颗。", "刚才那一炸就是这么来的。不扣分，但那一段白配了。" },
  },
  {
    id = "t4-insert",
    name = "④ 加球",
    short = "加球",
    rules = "rna",
    group = nil,
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = 0.75,
    innerRatio = nil,
    prefill = 12,
    ballBudget = 12,
    scoreTarget = math.huge,
    still = true,
    centerChain = true,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = { "A", "U" },
    script = nil,
    hint = { "按 Tab（手机点右下角）切到「加球」—— 往链里插一颗，序列的长度就变了。", "凑不成 3 的倍数时，这是除了消球之外的另一种调整手段。", "插错了按 R 重来。" },
  },
  {
    id = "t5-deadball",
    name = "⑤ 死球",
    short = "死球",
    rules = "rna",
    group = nil,
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = 0.75,
    innerRatio = nil,
    prefill = nil,
    ballBudget = 9,
    scoreTarget = math.huge,
    still = true,
    centerChain = true,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = { "A", "U" },
    script = "A1 A1 U0 A1 A1 A0 A0 A0 A0",
    hint = { "两段各 2 颗，中间夹着 1 颗没读的。", "★ 别急着配中间那颗：配了它，两段会并成 5 颗，反而更远。", "去把后面那几颗凑成一段；真踩了坑，就再补一颗到 6。" },
  },
  {
    id = "t6-cave",
    name = "⑥ 洞穴",
    short = "洞穴",
    rules = "rna",
    group = nil,
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = nil,
    innerRatio = nil,
    prefill = nil,
    ballBudget = 22,
    scoreTarget = math.huge,
    still = false,
    centerChain = false,
    noClear = false,
    goal = nil,
    speed = 14,
    startWpFrac = 0.72,
    bases = { "A", "U" },
    script = "A U A U A U A U A U",
    hint = { "★ 到这里才有轨道：球会一直往洞穴爬，队头滚进去就扣一条命。", "它现在离洞口很近 —— 先把最前面那几颗消掉。" },
  },
  {
    id = "t7-mix",
    name = "⑦ 综合",
    short = "综合",
    rules = "rna",
    group = nil,
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = nil,
    innerRatio = nil,
    prefill = 16,
    ballBudget = 36,
    scoreTarget = math.huge,
    still = false,
    centerChain = false,
    noClear = false,
    goal = nil,
    speed = 26,
    startWpFrac = nil,
    bases = nil,
    script = nil,
    hint = { "把前面学的都用上：反色配对、凑 3 的倍数、别去配 1-间隔的那颗。" },
  },
  {
    id = "spiral-outer",
    name = "螺旋 · 出球道在外",
    short = "螺旋·外",
    rules = "rna",
    group = nil,
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = nil,
    innerRatio = nil,
    prefill = 14,
    ballBudget = 48,
    scoreTarget = math.huge,
    still = false,
    centerChain = false,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = nil,
    script = nil,
    hint = nil,
  },
  {
    id = "cross-return",
    name = "交叉演示 · 遮挡与桥",
    short = "交叉桥",
    rules = "rna",
    group = nil,
    spineKind = 1,
    layersFromJunction = true,
    railOrder = "spawn-outer",
    turns = nil,
    innerRatio = nil,
    prefill = 16,
    ballBudget = 60,
    scoreTarget = math.huge,
    still = false,
    centerChain = false,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = nil,
    script = nil,
    hint = nil,
  },
  {
    id = "endless",
    name = "无尽 · 无限出球",
    short = "无尽",
    rules = "rna",
    group = nil,
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = nil,
    innerRatio = nil,
    prefill = 18,
    ballBudget = 0,
    scoreTarget = 500,
    still = false,
    centerChain = false,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = nil,
    script = nil,
    hint = nil,
  },
  {
    id = "classic-spiral",
    name = "经典 · 螺旋",
    short = "经典螺旋",
    rules = "classic",
    group = "经典祖玛",
    spineKind = 0,
    layersFromJunction = false,
    railOrder = "spawn-outer",
    turns = 4,
    innerRatio = nil,
    prefill = 20,
    ballBudget = 48,
    scoreTarget = math.huge,
    still = false,
    centerChain = false,
    noClear = false,
    goal = nil,
    speed = nil,
    startWpFrac = nil,
    bases = nil,
    script = nil,
    hint = nil,
  },
}

-- 前多少个是新手关（本体 TUTORIALS.length）；菜单按它分组
M.TUTORIAL_COUNT = 7

function M.byId(id)
  for i = 1, #M.LEVELS do
    if M.LEVELS[i].id == id then return M.LEVELS[i] end
  end
  return nil
end

return M
end

-- ---------------- ui ----------------
__M["ui"] = function()
-- ui.lua —— 表现层：board 的状态 -> 客户端控件。
--
-- ★★ 这里**不重新实现任何规则**：位置/颜色/显隐全部来自 sc（board.lua 算好的）。
--   ui 的职责只有四件：坐标换算、控件池复用、脏检查、**动效**。
--
-- 坐标：board 用的是"画布像素、原点左上、y 向下"；控件 anchoredPosition 在父级下
--       是"相对父级中心、y 向上"。所以 y 要翻一次号：uiY = view.cy - y。
--       父级 = 一块铺满画布、居中在画布中心的容器控件。
--
-- ★★ 画什么、画多大、什么颜色，全部照网页版 `src/render.js` 搬（百分比/半径/透明度用它的原式）：
--     轨道（双轨路面）              <-  drawTrackLayer（本体用 canvas 描线；我们用一段段"棒"拼）
--     洞穴（降解口）+ 红晕          <-  drawCave
--     配对连线（正确=直棒 / 错配=折线"断掉的键"）<- drawPairLink / drawPairLinks
--     绑定小球（副轨上读出的那一半）<-  drawBeadLayer 的 beads.eliminate
--     球 + 状态光晕 + 碱基字母      <-  drawBead（label / ink / pairGlow）
--     并入过程中的球                <-  drawMergeLayer
--     核糖体 + 两颗待发球 + 瞄准线  <-  drawRibosome
--     开火冷却环                    <-  本体没有（新增）：一眼看出能不能打
--     HUD 文本 + 半透明底板         <-  drawRunBadges / drawStats
--
-- ⚠ 近似之处（图片控件没有描边/渐变，只有填充色 + 柔边 + 径向填充）：
--     - 核糖体：一个暗色圆 + 外圈柔边光晕（本体是填充 + 蓝描边）
--     - 洞穴：中心暗圆 + 三层递减透明度的红晕（本体是径向渐变 + 红描边）
--     - 轨道：一段段带柔边的"棒"（本体是描线；米字路口/自交处会略有接缝）
--     - 球面字母用**文本框**叠在球上（本体是 canvas 文字）；副轨上的绑定小球没叠字母（省控件）
--
-- ★ 控件池的**创建顺序就是绘制顺序**（运行时：同级索引大的在上面，契约 §13）：
--   轨道 -> 洞穴 -> 连线 -> 光晕 -> 绑定小球 -> 球 -> 弹药 -> 并入球 -> 字母
--   -> 瞄准线 -> 冷却环 -> 核糖体 -> 待发球 -> HUD
--
-- ★★ 动效为什么**不用 `game.Tween`** 而是自己算：我们的脏检查缓存按"上一次写进去的值"判断要不要再写，
--   而 Tween 会绕过缓存直接改字段 —— 两条路同时改同一个字段就会互相打架（Tween 刚拉开，下一帧 sync 又写回去）。
--   所以这里：**动画只碰 sync 不碰的字段**（`localScaleX/Y`、以及临时改的 `imageColor` 透明度），
--   用一个短命的效果表 `ui.fx` 自己推进，结束时显式复位并把该控件的颜色缓存作废。
--   （`game.Tween` 仍在假宿主/真机上可用，将来要做"编辑期摆好的动效"再用。）

local CFG = require('config')
local MENU = require('menu')     -- 菜单布局（本体 config.js 的 1:1 移植，进对拍）

local M = {}

-- ==================== 视觉常量（照 src/render.js） ====================

local V = {
  aimLen = 110,        -- drawRibosome：瞄准线长 = R + 110 × scale
  aimWidth = 1.4,      -- drawRibosome：线宽 = max(1, 1.4 × scale)
  linkWidth = 3.4,     -- drawPairLink：连线宽 = max(3, 3.4 × scale)
  linkAmp = 3.4,       -- drawPairLink：错配折线的横向幅度
  caveR = 1.5,         -- drawCave：洞穴半径 = mt.R × 1.5
  linkFrom = 0.26,     -- drawPairLink：连线画在 26%~74% 之间
  linkTo = 0.74,
  haloScale = 1.16,     -- （旧）按比例放大的近似 —— 现在用 haloWidth/glowRadius（绝对值）
  haloPad = 3,          -- （旧）球外 +3 —— 现在按本体线宽算，见 glowRadius
  haloStrokeK = 0.18,   -- 描边线宽 = max(1.5, r × 0.18)（本体 render.js drawBead 的 glow）
  haloStrokeMin = 1.5,
  letterScale = 1.15,  -- 球面字母字号 = 球半径 × 1.15
  trackWidthK = 2.3,   -- 轨道路面宽 = 轨半径 × 2.3（盖住珠子）
}

-- 颜色：网页版用的是 rgba(...)，这里用 '#rrggbbaa'（官方 imageColor 是带 alpha 的 ColorValue）
local C = {
  aim = '#96c8ff4d',        -- rgba(150,200,255,0.30)
  cd = '#96c8ff5c',         -- 冷却环
  roadOuter = '#16202ea6',  -- 出球道路面（大球那条轨）
  roadInner = '#1d2b3ca6',  -- 三消道路面（小球那条轨）
  railLine = '#7f9dc94d',   -- 导轨细线（本体 drawTrackLayer 画的两条细亮线，很提神）
  backdrop = '#0b1119ff',   -- 整块背板（半透明深色）：让画面像个界面，而不是浮在关卡场景上
  caveCore = '#0a060ad9',   -- 洞穴中心
  -- 三层红晕（本体是径向渐变）：**要克制** —— 第一版给太大太红，整个洞口像块红布
  caveGlow = { '#ff5a6e40', '#ff5a6e26', '#ff5a6e14' },
  rbBody = '#22303f',
  rbHalo = '#96c8ff2e',
  panel = '#0a0e12a6',      -- HUD 底板（65%）
  panelLight = '#0a0e1266', -- 提示语那种大块文字用更淡的底板（40%）
  letterOnLight = '#101820',
}

-- '#rrggbb' / '#rrggbbaa' -> Color
local function hexColor(s, fallback)
  if type(s) ~= 'string' or #s < 7 then return fallback or Color.FromRGBA(255, 255, 255, 255) end
  local r = tonumber(s:sub(2, 3), 16) or 255
  local g = tonumber(s:sub(4, 5), 16) or 255
  local b = tonumber(s:sub(6, 7), 16) or 255
  local a = (#s >= 9) and (tonumber(s:sub(8, 9), 16) or 255) or 255
  return Color.FromRGBA(r, g, b, a)
end
M.hexColor = hexColor

-- 取色的 rgb 分量（做"淡出"时要按同一底色改 alpha）
local function rgbOf(hex)
  return tonumber(hex:sub(2, 3), 16) or 255, tonumber(hex:sub(4, 5), 16) or 255, tonumber(hex:sub(6, 7), 16) or 255
end

-- ★★ 控件运行时 ID 的字段名：官方是 **`Id`（首字母大写）**。
--    真机观察（客户端 Lua 运行时契约 §16）：「`Id`（客户端控件运行时ID，首字母大写）/ `prefabIndex`；
--    旧 probe 中的 `control.id` / `prefabId` 是**旧版本接口，不作为兼容口径**」。
--    官方文档的字段表里写的是小写 `id` —— 以真机探针为准，两个都认。
local function ctrlId(c)
  return c.Id or c.id
end

local function cacheOf(ui, c)
  local id = ctrlId(c)
  local cache = ui.last[id]
  if cache == nil then cache = {}; ui.last[id] = cache end
  return cache
end

local function setField(ui, c, key, value)
  local cache = cacheOf(ui, c)
  if cache[key] == value then return false end
  cache[key] = value
  c[key] = value
  return true
end

local function setColor(ui, c, hex)
  local cache = cacheOf(ui, c)
  if cache.__color == hex then return false end
  cache.__color = hex
  c.imageColor = hexColor(hex)
  return true
end

-- 动效直接改过颜色之后，把缓存作废，下一帧才会把底色重新写回去
local function invalidateColor(ui, c)
  local cache = cacheOf(ui, c)
  cache.__color = nil
end

-- 图片素材 id（真机结论，2026-09-25 用户实测）：
--   ★★ **动态创建的图片控件不会继承模板/画布上那张图** —— 必须脚本显式
--      `SetImage(Enum.ImageSource.StaticReference, <资产号>)`。不设 = 每个图片控件画成"?"，
--      球 / 轨道（一堆棒拼的）/ 中央核糖体全能中招（用户就是这么看到的）。
--   ★ 别把两个数字搞混：**图片控件模板索引**（形如 1073741852）不是素材 id；
--      素材 id 是编辑器里那张图的"**资产号**"（当前用 100002 = 一张白圆图）。
--   ui.artAny = 全局兜底资产号（棒/光晕/核糖体等不分碱基的控件用它）；
--   ui.art[base] = 该碱基专属的图（不配就跟 artAny 一样）。
local function artIdOf(ui, base)
  if base == nil then return ui.artAny end
  local a = ui.art
  return (a and a[base]) or ui.artAny
end

local function setImage(ui, c, id)
  if id == nil then return false end
  local cache = cacheOf(ui, c)
  if cache.__image == id then return false end
  cache.__image = id
  c:SetImage(Enum.ImageSource.StaticReference, id)
  return true
end
M.setImageById = setImage

-- ★★ 可见性：官方契约里 `visible` 是**只读**字段 —— 读得到，**写会报**
--    「cannot set visible, no such field」。改可见性必须调方法 SetVisible()。
local function setVisible(ui, c, v)
  local cache = cacheOf(ui, c)
  if cache.__visible == v then return false end
  cache.__visible = v
  c:SetVisible(v)
  return true
end

-- 把一个控件放到游戏坐标 (x, y)、尺寸 w×h、绕中心转 rot 度
local function place(ui, c, cx, cy, x, y, w, h, rot)
  setField(ui, c, 'anchoredPositionX', x - cx)
  setField(ui, c, 'anchoredPositionY', cy - y)
  setField(ui, c, 'sizeDeltaX', w)
  setField(ui, c, 'sizeDeltaY', h)
  setField(ui, c, 'localRotationZ', rot or 0)
  setVisible(ui, c, true)
end

-- ★ 旋转角：board 的 y 向下、控件空间的 y 向上，所以角度要翻号。
local function rotDeg(dx, dy)
  return math.deg(math.atan(-dy, dx))
end

-- 把控件当"一根棒"用：从 (x1,y1) 拉到 (x2,y2)，粗细 w
local function placeSeg(ui, c, cx, cy, x1, y1, x2, y2, w, hex, artId)
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1e-6 then setVisible(ui, c, false); return end
  place(ui, c, cx, cy, (x1 + x2) / 2, (y1 + y2) / 2, len, w, rotDeg(dx, dy))
  setColor(ui, c, hex)
  -- ★ 棒也要设素材：真机上不设就画成"?" —— 轨道/连线/瞄准线全是棒，
  --   用户看到的"轨道是一堆问号拼出来的"就是这里。
  --   ★ 棒优先用 artBar（**方图**；圆图拉成长条会鼓出来，用户已反馈"轨道用圆有点难看"）。
  setImage(ui, c, artId or ui.artBar or ui.artAny)
end

-- 把一个控件当"一颗球"用
local function placeBead(ui, c, cx, cy, x, y, r, hex, artId)
  local d = 2 * r
  place(ui, c, cx, cy, x, y, d, d, 0)
  setColor(ui, c, hex)
  setImage(ui, c, artId or ui.artAny)
end

-- ★★ 描边（本体 drawBead 的 glow）**正确的复刻方式**：
--   本体是 `arc(r + 3)` + `lineWidth = max(1.5, r*0.18)` 的一圈**细描边**。
--   图片控件没有描边能力 —— 一度改成"用空心圆素材画环"，但**环的粗细由素材决定**，
--   放大后那圈跟着变粗，看着就是"匹配以后球变大了"（用户三次反馈的就是这个）。
--   正确做法：**拿实心圆放大一圈、垫在球下面**，露出来的那一圈环宽 = 我们要的线宽。
--   → 宽度完全可控、和我们手里那张实心圆素材的形状无关。
local function glowRadius(r)
  return r + math.max(V.haloStrokeMin, r * V.haloStrokeK)
end

-- 柔边（发光）：图片控件没有描边，靠 enableSoftEdge 做"糊一圈"的效果
local function softEdge(c, on, width)
  c.enableSoftEdge = on and true or false
  if on then
    c.softEdgeMode = Enum.ImageMaskSoftEdgeMode.Percentage
    c.softEdgeWidthX = width or 60
    c.softEdgeWidthY = width or 60
  end
end

-- 动效：直接写 localScale（不进脏检查缓存 —— 这些字段 sync 不碰，不会打架）
local function setScaleRaw(c, s)
  c.localScaleX = s
  c.localScaleY = s
  c.localScaleZ = 1
end

-- ★★ 清掉某个控件身上还没播完的动效（给了 kind 就只清那一种），并把缩放/颜色复位。
--    为什么必须有它：控件是**池化复用**的，而 'gone'（炸开淡出）会把控件放大到 1.9×；
--    若 0.22 秒内这颗控件被回收去显示另一颗球，新球就会"异常增大"——用户报的
--    "3n 道上的小球异常增大"就是这个（HANDOFF §29）。
--    本体用 canvas 每帧重画、不存在复用，所以这是移植侧必须自己管的事。
local function cancelFx(ui, c, kind)
  if not (ui and ui.fx and c) then return end
  for i = #ui.fx, 1, -1 do
    local fx = ui.fx[i]
    if fx.c == c and (kind == nil or fx.kind == kind) then
      setScaleRaw(c, 1)          -- 一律复位：pop 会留下 0.25、gone 会留下 1.9，都不能带给下一颗球
      if fx.hex then invalidateColor(ui, c) end
      table.remove(ui.fx, i)
    end
  end
end

-- 便宜的缓动（够用即可；要 30 种缓动可以换 game.Tween，见文件头说明）
local function easeOut(u) return 1 - (1 - u) * (1 - u) end
local function easeBack(u)
  local s = 1.9
  local v = u - 1
  return 1 + (s + 1) * v * v * v + s * v * v
end

-- ==================== 建池 ====================

-- opts:
--   parent / canvas / ballPrefab / ballCount / shotPrefab / shotCount / art / hudPrefab / hud   —— 同以前
--   linkPrefab / linkCount / cavePrefab / mergeCount                                            —— 同以前
--   track          1 = 轨道也由 Lua 画（0 = 用编辑器里摆的静态图）
--   trackSegments  每条轨画多少段（默认 64；控件预算紧张时调小）
--   letters        1 = 球面上叠碱基字母文本框（0 = 只靠图片素材）
--   fancy          1 = 光晕 / 冷却环 / 动效（0 = 只留静态画面）
function M.create(opts)
  opts = opts or {}
  local parent = opts.parent
  if not parent then error('ui.create: 需要 parent') end
  local canvas = opts.canvas or { w = 900, h = 900 }

  local ui = {
    canvas = canvas,
    parent = parent,
    last = {},
    balls = {}, shots = {}, links = {}, elim = {}, merges = {}, halo = {}, letter = {}, elimLetter = {}, loadedLetter = {}, track = {},
    loaded = {}, hud = {},
    fx = {},                 -- 短命动效表
    elimOwner = {},          -- 球 id -> 正在显示它的绑定小球控件（用来播"被消掉"的动效）
    elimHex = {},            -- 球 id -> 绑定小球的颜色（淡出时要用同一个底色改 alpha）
    wasPaired = {},          -- 球 id -> 上一帧是否已读出
    elimShown = {},          -- 槽位 i -> 该槽位当前显示的是哪颗球（换球 = 回收，必须先清动效）
    elimSlot = {},           -- 球 id -> 它占的槽位 i（用来判断"槽位是否已空"）
    t = 0,
    stats = { writes = 0, ballWrites = 0, hudWrites = 0 },
  }

  -- ★ 素材 id：**默认不打补丁**（见文件顶部 artIdOf 的注释 —— 写死 1..5 会让真机全画成"?"）
  --   opts.art 给了才用；键是碱基（A/U/G/C/T），值是编辑器里那张图的素材 id。
  ui.art = opts.art or {}
  -- 全局兜底资产号：棒/光晕/核糖体/冷却环这些不分碱基的控件用它（不设就全是"?"）
  ui.artAny = opts.artAny or ui.art['A'] or ui.art[CFG.BASES[1]]
  -- 棒（轨道/连线/瞄准线）专用素材：**方图**最好（圆图拉长会鼓出来）
  ui.artBar = opts.artBar or ui.artAny
  -- 环（洞穴那几圈）专用素材：**空心圆**（实心圆装成环要叠层，效果差）
  ui.artRing = opts.artRing or ui.artAny
  -- 开火冷却环：**本体没有** → 默认关（cd=1 才画）
  -- 球的描边/光晕总开关（默认开；填 glow=0 全关，保留其他美化）
  ui.glowOn = (opts.glow == nil) and 1 or opts.glow
  ui.cdOn = opts.cd or 0
  ui.fancy = (opts.fancy == nil) and 1 or opts.fancy
  ui.letters = (opts.letters == nil) and 1 or opts.letters
  ui.trackOn = (opts.track == nil) and 1 or opts.track
  -- ★ 优化：轨道池 = 段数×2 个控件（占预算最多的一块）。64→40 省 48 个控件，
  --   段与段两端本来就互相叠着压住接缝，40 段在 1815×900 下肉眼看不出差别（已出图核对）。
  -- ★ 长相优化（2026-09-25）：64 段在"绕好几圈的螺旋"上会露出折线棱角 ⇒ 提到 72 段换顺滑。
  --   代价是 64 个控件，从球池腾（ballCount 96→80 省 80 个）⇒ 净 987/1000。
  ui.trackSegments = opts.trackSegments or 72
  ui.trackKey = nil
  ui.letterProbe = opts.letterProbe or 0     -- 临时探针，默认关（2026-09-25 用它定位过 ③ 不显示）

  local ballPrefab = opts.ballPrefab or 1
  local hudPrefab = opts.hudPrefab or 2
  local linkPrefab = opts.linkPrefab or ballPrefab
  local cavePrefab = opts.cavePrefab or ballPrefab

  -- ★ 动态创建失败时要**响亮地失败**：不然玩家看到的是空白画面，而错误在日志里
  local function build(prefab, what, i)
    local c = game.InstantiateClientUIControl(prefab, parent)
    if not c then
      error(what .. '创建失败（第 ' .. i .. ' 个，模板索引 ' .. tostring(prefab)
        .. '）。模板索引可能没填，或这个控件不能动态创建（主屏 / 模板控件的子节点都不行）')
    end
    c:SetActive(true)                       -- 文档：动态创建默认 active=false
    c:SetVisible(false)
    c.canControllerFocus = false
    -- ★★ 兜底：**凡是图片控件，建出来就先把素材设上**。
    --   真机事实：动态创建的图片控件**不继承**模板图，不设素材就画成"?"。
    --   原来靠每个绘制分支自己记得设 —— 漏一处就冒一批问号（用户报了两次）。
    --   放在这里 = 从源头堵住，跟后面怎么画无关。
    if ui.artAny then
      local t = typeof and typeof(c) or nil
      if type(t) == 'string' and t:find('Image', 1, true) then
        setImage(ui, c, ui.artAny)     -- 棒后面会被 placeSeg 改成 ui.artBar（方图）
      end
    end
    return c
  end

  local n = opts.ballCount or 96
  local sn = opts.shotCount or 8

  -- ⓪ "底"：一整块深色背板（用户反馈"没有底"）—— 只花 1 个控件，先建所以画在最底下。
  --    半透明（留一点关卡场景透出来），有它整局才像"一个界面"而不是浮在半空。
  --    backdrop = 0 可关掉（编辑器里自己摆了底图就用 0）。
  if opts.backdrop ~= 0 then
    -- ★ 2026-09-25（奇匠："打底希望是长方形的"）：原来用**球**的素材建背板 ⇒ 屏幕底衬是个**大圆** ✗。
    --   改用**方块**素材（轨道/连线用的那个 100001；空心圆是洞穴、实心圆是球）
    --   ⇒ 尺寸设成整屏就是一块**长方形**打底 ✓。
    -- ★★ 2026-09-25（奇匠连报两次"没有打底"）：**别再拿图片素材做底** ✗。
    --   图片控件的形状 = 素材的形状，而手上的三个素材（实心圆/方块/空心圆）里，
    --   那个"方块"是**给轨道用的半透明软块** ⇒ 铺满全屏也只是一层看不见的雾 ✓（这就是"没有打底"）。
    --   改用**文本框控件**：它的 `bgColor` 是一个**实心长方形面板**（屏幕上"分数/命"那两个黑框就是它 ✓），
    --   空文字 + 全屏尺寸 + 深色底 = 一块**保证看得见的长方形打底** ✓✓。
    local bg = build(hudPrefab, '打底控件', 1)
    bg.text = ''
    bg.bgColor = hexColor(C.backdrop or '#0b1119f2')
    bg.enableOutline = false
    ui.backdrop = bg
  end

  -- ① 轨道（最底下）：一段段"棒"拼成两条轨路面
  if ui.trackOn ~= 0 then
    for i = 1, ui.trackSegments * 2 do ui.track[i] = build(linkPrefab, '轨道控件', i) end
  end

  -- ② 洞穴：三层红晕 + 暗心 + 文字
  ui.caveGlow = { build(cavePrefab, '洞穴光晕控件', 1), build(cavePrefab, '洞穴光晕控件', 2),
                  build(cavePrefab, '洞穴光晕控件', 3) }
  ui.cave = build(cavePrefab, '洞穴控件', 1)
  ui.caveLabel = build(hudPrefab, '洞穴文字控件', 1)
  ui.caveLabel.fontSize = 18
  ui.caveLabel.horizontalAlignment = Enum.TextHorizontalAlignment.Middle
  ui.caveLabel.verticalAlignment = Enum.TextVerticalAlignment.Middle
  ui.caveLabel.enableOutline = true
  ui.caveLabel.text = '降解洞穴'
  ui.caveLabel:SetSizeDelta(160, 28)
  for i = 1, #ui.caveGlow do softEdge(ui.caveGlow[i], ui.fancy ~= 0, 70) end
  softEdge(ui.cave, ui.fancy ~= 0, 35)

  -- ③ 连线
  local ln = opts.linkCount or (n * 2)
  for i = 1, ln do ui.links[i] = build(linkPrefab, '连线控件', i) end

  -- ④ 状态光晕（在球下面）
  if ui.fancy ~= 0 then
    -- ★ 光晕池 = **2n**：主轨球用 halo[i]、副轨绑定球用 halo[haloHalf + i]。
    --   本体 render.js 的 drawBeadLayer 把 `['eliminate','spawn']` **两条轨都画一遍**，
    --   两边 paired 时都带 glow（副轨那颗的 glowColor 是空的 → 回落成白色描边）。
    ui.haloHalf = n
    for i = 1, 2 * n do
      ui.halo[i] = build(ballPrefab, '光晕控件', i)
      -- ★★ **环上不开柔边**：柔边（80）是当初给"实心圆盘做发光"调的；
      --    现在这一圈用的是**空心圆素材**，再叠柔边会把环糊成一团 →
      --    用户看到的"有的球描边会突然变坏"就是这个。环要清晰（本体也是硬描边）。
      softEdge(ui.halo[i], false, 0)
    end
  end

  -- ⑤ 绑定小球（副轨上"读出的那一半"）
  for i = 1, n do ui.elim[i] = build(ballPrefab, '绑定小球控件', i) end

  -- ⑥ 球池 / ⑦ 弹药池 / ⑧ 并入球
  for i = 1, n do ui.balls[i] = build(ballPrefab, '球控件', i) end
  for i = 1, sn do ui.shots[i] = build(opts.shotPrefab or ballPrefab, '弹药控件', i) end
  local mn = opts.mergeCount or 8
  for i = 1, mn do ui.merges[i] = build(ballPrefab, '并入球控件', i) end

  -- ⑨ 球面字母（盖在球上面）
  if ui.letters ~= 0 then
    for i = 1, n do
      local c = build(hudPrefab, '字母控件', i)
      c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle
      c.verticalAlignment = Enum.TextVerticalAlignment.Middle
      c.enableOutline = false
      ui.letter[i] = c
    end
    -- ★ 绑定小球（三消道上那颗）**本体也带字母** —— 本体 render.js 用它自己那套
    --   drawBead(..., b.label || b.base, ...) 画**所有**珠子，主轨副轨都画。
    --   第一版只给主轨画了字母，用户报"用来匹配的小球没有字母"，就是这里漏的。
    for i = 1, n do
      local c = build(hudPrefab, '绑定球字母控件', i)
      c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle
      c.verticalAlignment = Enum.TextVerticalAlignment.Middle
      c.enableOutline = false
      ui.elimLetter[i] = c
    end
  end

  -- ⑩ 瞄准线 -> 冷却环 -> 核糖体本体 -> 待发球描边 -> 两颗待发球 -> 字母
  -- ★★ **建控件的顺序 = 图层顺序**（后建的盖在上面）。真机上"待发球看不到字母"就是
  --    因为我把描边控件建在了字母**之后** → 描边压在字母上。正确顺序：环 → 球 → 字母。
  ui.aim = build(linkPrefab, '瞄准线控件', 1)
  ui.cd = build(ballPrefab, '冷却环控件', 1)
  ui.rb = build(ballPrefab, '核糖体控件', 1)
  softEdge(ui.rb, ui.fancy ~= 0, 45)
  -- 本体给"炮口那颗"画了 glow（drawBead 第 9 个参数 true）→ 白色描边
  ui.loadedHalo = { build(ballPrefab, '待发球描边控件', 1), build(ballPrefab, '待发球描边控件', 2) }
  for i = 1, 2 do softEdge(ui.loadedHalo[i], false, 0) end   -- 同理：环上不加柔边
  ui.loaded[1] = build(ballPrefab, '待发球控件', 1)
  ui.loaded[2] = build(ballPrefab, '待发球控件', 2)
  -- ★ 待发球也要字母（本体 render.js：`drawBead(..., lb(1), ...)` 和 `lb(0)` —— **两颗都带字**）
  --   放在最后建 → 一定盖在球和描边之上。
  -- ★★ 2026-09-25 【已改回】这一段 + 下面 sync 里的字号，就是"④ 显示正常"那一版的**原文**。
  --    当天 13:10 的提交（43cfc76）把这里做成了"挪到 M.create 最后 + 白描边 + 字号 1.35"，
  --    结果两颗字母全糊（12~19px 小字被描边吃掉）—— 用户报"原本 4 是正常的现在修没了，3 也没好"。
  --    ⚠ 以后别再动这三样：**别挪位置、别加 enableOutline、别改字号公式**。
  if ui.letters ~= 0 then
    for i = 1, 2 do
      local c = build(hudPrefab, '待发球字母控件', i)
      c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle
      c.verticalAlignment = Enum.TextVerticalAlignment.Middle
      c.enableOutline = false
      ui.loadedLetter[i] = c
    end
  end

  -- ⑪ HUD 文本（加半透明底板，免得字飘在背景上）
  ui.hudOrder = {}
  for i = 1, #(opts.hud or {}) do
    local spec = opts.hud[i]
    local c = build(hudPrefab, '文本框控件', i)
    c:SetVisible(true)
    c:SetAnchoredPosition(spec.x or 0, spec.y or 0)
    c:SetSizeDelta(spec.w or 400, spec.h or 60)
    c.fontSize = spec.size or 28
    c.horizontalAlignment = spec.align == 'right' and Enum.TextHorizontalAlignment.Right
      or (spec.align == 'center' and Enum.TextHorizontalAlignment.Middle or Enum.TextHorizontalAlignment.Left)
    c.verticalAlignment = Enum.TextVerticalAlignment.Middle
    c.enableOutline = true
    -- 底板：默认 65% 半透明；spec.panel == 'light' 更淡一点（提示文字块很大，别做成黑板）
    local panelHex = '#00000000'
    if spec.panel == 'light' then panelHex = C.panelLight
    elseif spec.panel ~= false then panelHex = C.panel end
    c.bgColor = hexColor(panelHex)
    c.text = spec.text or ''
    ui.hud[spec.key] = c
    ui.hudOrder[#ui.hudOrder + 1] = spec.key
  end

  -- ⑬ 开始菜单（DESIGN.md §61 / 本体 render.js drawMenu + drawMenuButton）
  --   ⚠ 必须在 create() 里建：真机契约是"只有 OnStart 能建控件"（见 HANDOFF §10）。
  --   预算：暗幕 1 + 标题 1 + 副标题 1 + 分组 2 + 按钮 10 + 按钮文字 10 + 底部说明 1
  --         + 局内"菜单"按钮 1 + 它的文字 1 = **28 个**（M.count 里算进去了）。
  do
    local m = {}
    m.scrim = build(ballPrefab, '菜单暗幕控件', 1)
    setColor(ui, m.scrim, '#060a12de')              -- 本体 rgba(6,10,18,0.87)
    softEdge(m.scrim, false, 0)
    local function mkText(what, i)
      local c = build(hudPrefab, what, i)
      c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle
      c.verticalAlignment = Enum.TextVerticalAlignment.Middle
      c.enableOutline = false
      c.bgColor = hexColor('#00000000')
      return c
    end
    m.title = mkText('菜单标题控件', 1)
    m.subtitle = mkText('菜单副标题控件', 1)
    m.footer = mkText('菜单说明控件', 1)
    -- ⚠ 分组标题池同理：原来只有 2 个，加第三组后"经典祖玛"这行标题没控件可画（和按钮池同一类坑）
    m.groups = { mkText('菜单分组控件', 1), mkText('菜单分组控件', 2),
                 mkText('菜单分组控件', 3), mkText('菜单分组控件', 4) }
    m.btn = {}
    m.btnLabel = {}
    -- ⚠ 按钮池要**够放全部关卡**：原来写死 10 个，加了经典关（11 关）之后第 11 个按钮压根不存在
    --   ⇒ 菜单里第三组整个不显示（实测踩过：图上只有新手关/核心关）。
    --   留到 16 个，以后再加关也不用动这里。
    for i = 1, 12 do
      m.btn[i] = build(ballPrefab, '菜单按钮控件', i)
      softEdge(m.btn[i], false, 0)
      m.btnLabel[i] = mkText('菜单按钮文字控件', i)
    end
    -- 局内左下角「回菜单」按钮（本体 §61：手机没有 Esc，这是离开一关的唯一出路）
    m.playBtn = build(ballPrefab, '回菜单按钮控件', 1)
    softEdge(m.playBtn, false, 0)
    m.playLabel = mkText('回菜单文字控件', 1)
    m.playLabel.text = '菜单'
    m.ready = false                                      -- 位置/文字要不要重算（换关/换画布尺寸时）
    ui.menu = m
  end

  -- ⑭ 彩蛋「璃月黄金交易所」（奇匠：一个开始按键 + 一个面板）
  --   规则逻辑在 egg.lua（纯逻辑、可单测）；这里只负责"画出来 + 接点击"。
  --   控件：暗幕 1 + 标题 1 + 数据 5 + 按钮(图+字) 12 + 菜单入口(图+字) 2 = 21 个
  do
    local e = {}
    e.scrim = build(ballPrefab, '彩蛋暗幕控件', 1)
    setColor(ui, e.scrim, '#05070df0')
    softEdge(e.scrim, false, 0)
    local function mk(what, i)
      local c = build(hudPrefab, what, i)
      c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle
      c.verticalAlignment = Enum.TextVerticalAlignment.Middle
      c.enableOutline = false
      c.bgColor = hexColor('#00000000')
      return c
    end
    e.title = mk('彩蛋标题控件', 1)
    e.lines = {}
    for i = 1, 5 do e.lines[i] = mk('彩蛋数据控件', i) end
    -- ★★ 复用菜单的按钮池（12 个按钮 + 12 个文字）：
    --   彩蛋屏和菜单**永远不会同屏** ⇒ 没必要再建一套（那样 1008 会超平台上限 1000 ✗）。
    --   syncEgg 在 syncMenu **之后**跑，所以哪怕 syncMenu 把它们藏了，这一帧也会被重新摆好 ✓。
    e.btn = ui.menu.btn
    e.btnLabel = ui.menu.btnLabel
    -- ★ K 线式折线图的"笔画池"：每个报价点之间画一段（复用轨道的"棒"素材 ✓）。
    --   48 段 ⇒ 最多画 49 个价格点（egg.lua 的 M.HISTORY = 48 ✓）。控件 868→916 ✓ 仍在上限内。
    e.chart = {}
    for i = 1, 49 do
      e.chart[i] = build(linkPrefab, '彩蛋折线控件', i)
      softEdge(e.chart[i], false, 0)
    end
    -- ★ 奇匠要的"彩蛋开始按键"：摆在菜单里（右下角 —— 左上角是平台自己的按键，见 §42）
    e.entry = build(ballPrefab, '彩蛋入口控件', 1)
    softEdge(e.entry, false, 0)
    e.entryLabel = mk('彩蛋入口文字控件', 1)
    e.entryLabel.text = '◈ 交易所'
    e.ready = false
    ui.egg = e
  end

  -- 平台上限自检（《编辑项范围限制》：单控件组 1000 / 单屏 10000）
  local total = M.count(ui)
  if total > 900 then
    if print then
      pcall(print, string.format('[zuma] ⚠ 控件数 %d 接近上限 1000：把 ballCount / trackSegments 调小，或把 track / letters 关掉', total))
    end
  end

  return ui
end

-- ==================== 轨道 ====================

-- 轨道用"一段段棒"拼：本体 drawTrackLayer 是 canvas 描线，图片控件只能这样近似。
-- 只在换关时写一次（静态），每帧不碰 —— 所以哪怕 128 个控件也不吃帧预算。
local function placeTrack(ui, sc)
  local cx, cy = sc.view.cx, sc.view.cy
  -- ⓪ 背板：铺满画布的一大块（每次尺寸变了才写）
  if ui.backdrop then
    place(ui, ui.backdrop, cx, cy, cx, cy, sc.view.w, sc.view.h, 0)
    setVisible(ui, ui.backdrop, true)
  end
  if ui.trackOn == 0 or #ui.track == 0 then return end
  local mt = sc.metrics
  local key = tostring(sc.level and sc.level.id) .. '#' .. tostring(math.floor(sc.path.length)) ..
    '#' .. tostring(sc.rails and sc.rails.spawn and sc.rails.spawn.offset or 0)
  if ui.trackKey == key then return end
  ui.trackKey = key

  local N = ui.trackSegments
  local seg = 0
  local function drawRail(poly, radius, hex)
    local m = #poly
    if m < 2 then return end
    local w = V.trackWidthK * radius
    -- ★ 每段两端各伸出去半个宽度：相邻两段**互相压住**，接缝就看不出来了
    --   （不伸的话，圆头"棒"接起来会露出一圈小缺口 —— 第一版出图时能看见一道道的暗痕）
    local ext = w * 0.5
    for k = 0, N - 1 do
      local i0 = 1 + math.floor(k * (m - 1) / N)
      local i1 = 1 + math.floor((k + 1) * (m - 1) / N)
      if i1 > i0 then
        local a, b = poly[i0], poly[i1]
        local dx, dy = b.x - a.x, b.y - a.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 1e-6 then
          local ux, uy = dx / len, dy / len
          seg = seg + 1
          placeSeg(ui, ui.track[seg], cx, cy,
            a.x - ux * ext, a.y - uy * ext, b.x + ux * ext, b.y + uy * ext, w, hex)
          softEdge(ui.track[seg], ui.fancy ~= 0, 50)
        end
      end
    end
  end

  if sc.railPolys then
    drawRail(sc.railPolys.spawn, (sc.rails.spawn and sc.rails.spawn.radius) or mt.R, C.roadOuter)
    -- ★ 经典祖玛（§66）：**单轨** —— 经典关不画那条"三消道"（原版只有一条轨道）。
    --   不画它也就没人会以为"球该往那条道上走"。
    if sc.rules ~= 'classic' then
      drawRail(sc.railPolys.eliminate, (sc.rails.eliminate and sc.rails.eliminate.radius) or mt.r, C.roadInner)
    end
  end
  for i = seg + 1, #ui.track do setVisible(ui, ui.track[i], false) end
end

-- ==================== 彩蛋：璃月黄金交易所（绘制） ====================
-- 逻辑全在 egg.lua；这里只把 st.egg 的字段摆到屏幕上，并接好 6 个按钮的位置。
-- 按钮：1 买1g / 2 卖1g / 3 借1万 / 4 借100g / 5 打工 / 6 返回
local function syncEgg(ui, sc, st)
  local e = ui.egg
  if not e then return end
  local inMenu = (st.screen == 'menu')
  local inEgg = (st.screen == 'egg')
  local cx, cy = sc.view.cx, sc.view.cy
  local W, H, s = sc.view.w, sc.view.h, sc.metrics.scale

  -- ★ 菜单里那颗"彩蛋开始按键"：右下角（左上被平台占了）
  if e.entry then
    local x = W - 130 * s
    local y = H - 62 * s
    place(ui, e.entry, cx, cy, x, y, 208 * s, 66 * s, 0)
    setVisible(ui, e.entry, inMenu)
    setColor(ui, e.entry, '#1b2436')
    place(ui, e.entryLabel, cx, cy, x, y, 208 * s, 48 * s, 0)
    setVisible(ui, e.entryLabel, inMenu)
    e.entryLabel.fontSize = math.max(14, math.floor(20 * s))
    e.entryLabel.fontColor = hexColor('#cfe0ff')
  end

  setVisible(ui, e.scrim, inEgg)
  setVisible(ui, e.title, inEgg)
  for i = 1, #e.lines do setVisible(ui, e.lines[i], inEgg) end
  -- ⚠⚠ 按钮是**和菜单共用**的池子：**只有进了彩蛋屏才动它们**。
  --   踩过：这里无条件 `setVisible(..., inEgg)` ⇒ 菜单里刚摆好的关卡按钮被这行全藏掉，
  --   屏幕上只剩三个分组标题（出图才看出来）。
  if inEgg then
    -- ★★ 关键：按钮是**复用菜单控件**的（菜单那几个控件建得比彩蛋的暗幕**早** ✗）
    --   ⇒ 在"创建顺序 = 前后层级"的平台规则下，它们会被暗幕（94% 不透明）压得完全看不见
    --   —— 奇匠反馈"无功能按钮"就是这个（折线控件一并提上来，防同类问题）。
    --   用 SetAsLastSibling 提到最上层（移植侧允许；套 pcall 保证真机上万一不支持也不会崩）。
    local function raise(c)
      if c and c.SetAsLastSibling then pcall(c.SetAsLastSibling, c) end
    end
    -- ⚠⚠ 池子有 12 个，彩蛋只用 **7** 个 ⇒ 第 8~12 个必须**藏掉** ✗：
    --   上一版这里是 `for i = 1, #e.btn do setVisible(..., true)`（全放出来）⇒ 出两个 bug：
    --     ① 后 5 个还留着菜单的关卡名（"8 螺旋·外 / 9 交叉桥 / 10 无尽 / 经典 · 螺旋"）
    --        —— 奇匠："8910经典螺旋不会消失"
    --     ② 它们没被设过颜色、又停在菜单原位（屏幕中央）⇒ 球素材原色 = **中央一个白圆**
    local EGG_BTN = 7
    for i = 1, #e.btn do
      local want = (i <= EGG_BTN)
      setVisible(ui, e.btn[i], want)
      setVisible(ui, e.btnLabel[i], want)
      if want then raise(e.btn[i]); raise(e.btnLabel[i]) end
    end
    for i = 1, #e.chart do raise(e.chart[i]) end
  end
  -- ★★ 退出交易所时必须**主动把折线藏掉** ✗ ——
  --   下面的代码靠 `if not inEgg then return end` 早退，早退就**跳过了清理**
  --   ⇒ 折线控件留在菜单/关卡画面上（奇匠："退出交易所后折线图不会消失"）。
  --   （和"门禁把交易所暗幕藏掉"、"彩蛋把菜单按钮藏掉"是同一类坑：**早退前先做完自己的收尾** ✓）
  if not inEgg then
    for i = 1, #e.chart do setVisible(ui, e.chart[i], false) end
    return
  end

  -- ★ 彩蛋屏要把**局内 HUD 全藏掉**（分数/连读/命/模式/提示都不该出现在交易所里）。
  --   syncMenu 在本函数**之前**跑，所以这里覆盖它、且只在彩蛋屏生效。
  for i = 1, #ui.hudOrder do setVisible(ui, ui.hud[ui.hudOrder[i]], false) end
  if ui.menu and ui.menu.playBtn then setVisible(ui, ui.menu.playBtn, false) end
  if ui.menu and ui.menu.playLabel then setVisible(ui, ui.menu.playLabel, false) end

  -- 暗幕铺满
  place(ui, e.scrim, cx, cy, W * 0.5, H * 0.5, W, H, 0)
  -- 标题（⚠ 文字必须在这里赋值 —— 建控件时不赋值就一直是空的，出图时才发现标题不见了）
  place(ui, e.title, cx, cy, W * 0.5, H * 0.16, math.min(W - 80, 760 * s), 64 * s, 0)
  e.title.text = '璃月黄金交易所'
  e.title.fontSize = math.max(20, math.floor(34 * s))
  e.title.fontColor = hexColor('#e6d3a3')
  -- 五行数据
  local st2 = st.egg or {}
  local rows = {
    '金价   ' .. string.format('%.1f', st2.price or 0) .. ' 元/g   ' ..
      (st2.lastDelta and string.format('(%+.1f)', st2.lastDelta) or ''),
    '现金   ' .. string.format('%.0f', st2.cash or 0) .. ' 元      持仓   ' ..
      string.format('%.0f', st2.gold or 0) .. ' g',
    '欠款   ' .. string.format('%.0f', st2.debtCash or 0) .. ' 元     金欠   ' ..
      string.format('%.1f', st2.debtGold or 0) .. ' g',
    '利息   ' .. string.format('%.0f', st2.interestPaid or 0) .. ' 元（30 秒 +10%，复利）',
    -- ★★ 署名：原作者授权本项目移植的条件就是**注明来源**，这一行不能删（见 egg.lua 头部）。
    --   ⚠ 必须**两个分支都带** —— 第一版只写在"不打工"那一支上，一进打工（30 秒）署名就消失了 ✗。
    ((st2.tWork and st2.tWork > 0)
      and ('打工中… 剩 ' .. string.format('%.0f', st2.tWork) .. ' 秒')
      or '（打工：仅欠款时可用，30 秒，还 20%）')
      .. '    感谢傻傻白老师对本项目的支持',
  }
  for i = 1, 5 do
    local c = e.lines[i]
    place(ui, c, cx, cy, W * 0.5, H * 0.24 + (i - 1) * 46 * s, math.min(W - 120, 820 * s), 42 * s, 0)
    c.text = rows[i]
    c.fontSize = math.max(13, math.floor(19 * s))
    c.fontColor = hexColor(i == 1 and '#f0e6d2' or '#c8d4e6')
  end
  -- ★★ 折线图（奇匠："不想要柱" ⇒ 折线）。初始价基准 = 100 元/g（= egg.lua 的 M.PRICE0）。
  --   ⚠⚠ 这里原来写的是 `M.PRICE0` —— 那是 **egg.lua** 的字段，ui.lua 的 M 里根本不存在 ✗
  --   ⇒ nil 参与算术直接抛错 ⇒ **syncEgg 从这一行起中断 ⇒ 按钮和折线全都不会被执行**
  --   = 奇匠反馈的"无功能按钮，无折线图"（一个 nil 造成两个症状）。
  local BASE = 100
  --   为什么这一版能画出来、上一版不能：上一版的历史**只有 1 个点**（初始点是在第一次报价之后才记的，
  --   种子问题已修 ✓）⇒ 连不成线。现在 egg.lua 开局就播了一个初始价 ✓，且一局 10 分钟 / 3 秒 ≈
  --   **200 个点** ✓ —— 界面按 48 个点的窗口**等距抽样**（多点少段，控件只用 47 段 ✓）。
  --   画法用 placeSeg（轨道同款，自带 setImage ✓ 是验证过的 ✓），涨红跌绿。
  local hist = st2.hist or {}
  local n = #hist
  local cw, chh = 1180 * s, 230 * s
  local x0, y0 = W * 0.5 - cw * 0.5, H * 0.36
  local PTS = 48
  local step = math.max(1, math.ceil(n / PTS))
  local pts = {}
  for i = n, 1, -step do table.insert(pts, 1, hist[i]) end
  local m = #pts
  local lo, hi = nil, nil
  for i = 1, m do
    local v = pts[i]
    if lo == nil or v < lo then lo = v end
    if hi == nil or v > hi then hi = v end
  end
  if lo == nil then lo, hi = 100 - 10, 100 + 10 end
  if hi - lo < 2 then hi = lo + 2 end
  local pad = (hi - lo) * 0.12
  lo, hi = lo - pad, hi + pad
  local function px(i) return x0 + (i - 1) * cw / math.max(1, m - 1) end
  local function pyv(v) return y0 + chh - (v - lo) / (hi - lo) * chh end
  local used = 0
  -- 基准线（初始价 100）：用最后一段控件画一条横线，让玩家看得出"现在比开局高还是低"
  if e.chart[#e.chart] then
    local yb = pyv(100)
    placeSeg(ui, e.chart[#e.chart], cx, cy, x0, yb, x0 + cw, yb, 2 * s, '#4a5568')
    setVisible(ui, e.chart[#e.chart], true)
  end
  for i = 1, m - 1 do
    local seg = e.chart[i]
    if seg then
      used = i
      placeSeg(ui, seg, cx, cy, px(i), pyv(pts[i]), px(i + 1), pyv(pts[i + 1]),
        3 * s, (pts[i + 1] >= pts[i]) and '#e8453c' or '#3fbf6f')
      setVisible(ui, seg, true)
    end
  end
  for i = used + 1, #e.chart - 1 do setVisible(ui, e.chart[i], false) end
  -- 收盘后盖一层提示（不再能交易）
  if st2.ended then
    e.lines[5].text = '★ 已收盘（10 分钟到）—— 点「返 回」结算'
  end

  -- 六个按钮：两行三列
  -- ★ 按原奇域的逻辑：买卖是**比例**下单（50% / 梭哈 / 50% / 全部），不是"买 1g"
  local labels = { '买入 50%', '梭哈买入', '卖出 50%',
                   '全部卖出', '借 1 万', '借金套现',
                   '还金 100g', '打 工', '返 回' }
  local bw, bh = 190 * s, 62 * s
  for i = 1, #labels do
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    local x = W * 0.5 + (col - 1) * (bw + 26 * s)
    local y = H * 0.66 + row * (bh + 22 * s)
    place(ui, e.btn[i], cx, cy, x, y, bw, bh, 0)
    setColor(ui, e.btn[i], (i == 7) and '#20242e' or '#3a2f1c')
    place(ui, e.btnLabel[i], cx, cy, x, y, bw, 44 * s, 0)
    e.btnLabel[i].text = labels[i]
    e.btnLabel[i].fontSize = math.max(13, math.floor(19 * s))
    e.btnLabel[i].fontColor = hexColor((i == 6) and '#c8d4e6' or '#f0dfae')
  end
  e.ready = true
end

-- ==================== 彩蛋门禁（谜题锁） ====================
-- 谜面不给数字：要被玩家**自己去原奇域翻排行榜**（docs/08）。
-- 键盘复用菜单那 12 个按钮池（门禁屏菜单不可见 ⇒ 零新控件），谜面/输入复用本图层 5 行。
local LOCK_KEYS = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '清除', '0', '确认' }
local LOCK_RIDDLE = {
  '十人坠崖，皆是赌徒。',
  '榜不在我，榜在人间。',      -- ⇒ 去原奇域《璃月黄金交易所》翻它的排行榜
  '合而为一，去其零头。',      -- ⇒ 十个数相加、四舍五入取整（先合后取零）
  '无正无负，方入此门。',      -- ⇒ 不要负号
}
local function syncLock(ui, sc, st)
  local e = ui.egg
  if not e then return end
  -- ★★ 不在门禁屏就**什么都别碰** ✗ —— 本函数在 syncEgg **之后**跑，
  --   如果在这里 setVisible(..., false) 收尾，就会把**交易所屏的暗幕**一起藏掉
  --   ⇒ 底下的关卡场景（第一关）会从面板底下冒出来（奇匠："这版门锁打开后会让第一关奇怪的出现"）。
  if st.screen ~= 'lock' then return end
  local inLock = true
  local cx, cy = sc.view.cx, sc.view.cy
  local W, H, s = sc.view.w, sc.view.h, sc.metrics.scale

  setVisible(ui, e.scrim, true)
  setVisible(ui, e.title, true)
  for i = 1, #e.lines do setVisible(ui, e.lines[i], true) end

  -- 局内 HUD 全藏（和交易所屏同理）
  for i = 1, #ui.hudOrder do setVisible(ui, ui.hud[ui.hudOrder[i]], false) end
  if ui.menu and ui.menu.playBtn then setVisible(ui, ui.menu.playBtn, false) end
  if ui.menu and ui.menu.playLabel then setVisible(ui, ui.menu.playLabel, false) end

  place(ui, e.scrim, cx, cy, W * 0.5, H * 0.5, W, H, 0)
  place(ui, e.title, cx, cy, W * 0.5, H * 0.12, math.min(W - 80, 760 * s), 64 * s, 0)
  e.title.text = '璃月黄金交易所 · 门禁'
  e.title.fontSize = math.max(18, math.floor(30 * s))
  e.title.fontColor = hexColor('#e6d3a3')

  local lk = st.lock or {}
  local tries = lk.tries or 0
  local red = lk.red == true
  for i = 1, 4 do
    local c = e.lines[i]
    place(ui, c, cx, cy, W * 0.5, H * 0.22 + (i - 1) * 44 * s, math.min(W - 120, 900 * s), 40 * s, 0)
    -- 连错 3 次 ⇒ 保底：谜面换成"十行数字"（一行两人），玩家照样能自己算
    if tries >= 3 and i <= 3 then
      local P = {
        { 'CocaKlee -136692.77', '有可言遇 -114347.34' },
        { '晓月之星 -111297.93', '屑旅行人 -92331.79' },
        { '✧白星簌雪✧ -56715.82', '欧若洛樱 -33180.86' },
      }
      c.text = P[i][1] .. '    ' .. P[i][2]
      c.fontColor = hexColor('#a9b6c8')
    else
      c.text = LOCK_RIDDLE[i]
      c.fontColor = hexColor(i == 2 and '#f0dfae' or '#dce6ff')
    end
    c.fontSize = math.max(12, math.floor(18 * s))
  end
  if tries >= 3 then
    e.lines[4].text = '哈基喵 -22676.93   诸葛茗云 -16977.06'
    e.lines[5]  = e.lines[5] or e.lines[4]
  end
  -- 输入行（第 5 行）：○ 表示已输入的位数
  local inp = tostring(lk.input or '')
  e.lines[5].text = '输入： ' .. (inp == '' and '—' or inp) .. '        （输满 6 位自动验）'
  place(ui, e.lines[5], cx, cy, W * 0.5, H * 0.22 + 4 * 44 * s, math.min(W - 120, 900 * s), 40 * s, 0)
  e.lines[5].fontSize = math.max(13, math.floor(20 * s))
  e.lines[5].fontColor = hexColor(red and '#ff6b6b' or '#8fe3b0')
  -- 第 4 行在保底模式下补上后两人（上面被 riddle 占了）
  if tries >= 3 then
    e.lines[4].text = '哈基喵 -22676.93   诸葛茗云 -16977.06   天使的糖豆 -2981.4   凝銘 -12297.19'
    place(ui, e.lines[4], cx, cy, W * 0.5, H * 0.22 + 3 * 44 * s, math.min(W - 120, 1100 * s), 40 * s, 0)
    e.lines[4].fontColor = hexColor('#a9b6c8')
  end

  -- 12 键：4 行 3 列（复用菜单池 + 提到最上层，否则被暗幕压住）
  local bw, bh = 150 * s, 60 * s
  for i = 1, 12 do
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    local x = W * 0.5 + (col - 1) * (bw + 24 * s)
    local y = H * 0.60 + row * (bh + 16 * s)
    place(ui, e.btn[i], cx, cy, x, y, bw, bh, 0)
    setColor(ui, e.btn[i], (i == 12) and '#2f4a35' or ((i == 10) and '#4a2f2f' or '#333a48'))
    place(ui, e.btnLabel[i], cx, cy, x, y, bw, 42 * s, 0)
    e.btnLabel[i].text = LOCK_KEYS[i]
    e.btnLabel[i].fontSize = math.max(13, math.floor(19 * s))
    e.btnLabel[i].fontColor = hexColor('#e8f0ff')
    setVisible(ui, e.btn[i], true)
    setVisible(ui, e.btnLabel[i], true)
    if e.btn[i].SetAsLastSibling then pcall(e.btn[i].SetAsLastSibling, e.btn[i]) end
    if e.btnLabel[i].SetAsLastSibling then pcall(e.btnLabel[i].SetAsLastSibling, e.btnLabel[i]) end
  end
  -- 多余的按钮（池子 12 个，正好够）
end

-- ==================== 每帧同步 ====================

-- st（可选）: { dt, events, hintLines = {..}, mode = 'match'|'insert' }
local syncMenu   -- 前置声明：定义在本函数之后（菜单图层）

function M.sync(ui, sc, st)
  st = st or {}
  local view = sc.view
  local mt = sc.metrics
  local cx, cy = view.cx, view.cy
  local dt = st.dt or 0
  ui.t = ui.t + dt
  ui.stats.writes = 0

  -- ★ 经典祖玛（§66）：经典关用**专用配色**（奇匠要求"原版球的颜色不要沿用"）。
  --   一处收口：所有"球色"都经过它 ⇒ 只改这一行就全局生效。
  local function baseColor(b)
    return CFG.colorOf(b, sc.rules) or '#ffffff'
  end

  -- ---- 动效推进（先推进，再让本帧的静态同步覆盖"非动画字段"）----
  for i = #ui.fx, 1, -1 do
    local fx = ui.fx[i]
    fx.t = fx.t + dt
    local u = fx.dur > 0 and math.min(1, fx.t / fx.dur) or 1
    local c = fx.c
    if fx.kind == 'pop' then
      setScaleRaw(c, 0.25 + (1 - 0.25) * easeBack(u))
    elseif fx.kind == 'fire' then
      local k = (u < 0.4) and (u / 0.4) or (1 - (u - 0.4) / 0.6)
      setScaleRaw(c, 1 + 0.18 * k)
    end
    -- ★★ 2026-09-25 删掉 'gone'（"炸开淡出"：把控件放大到 1.9× 再淡出）。
    --   用户原话："我说变大直接删掉就可以了" —— 他会把那个放大效果本身当成"小球异常增大"，
    --   而且它确实带来一整类"池化复用把上一颗球的缩放带给新球"的问题（HANDOFF §29）。
    --   现在被消掉的球就是**直接收掉**（下一帧槽位空了自然隐藏），不再有放大/淡出。
    if u >= 1 then
      setScaleRaw(c, 1)
      if fx.hex then invalidateColor(ui, c) end
      table.remove(ui.fx, i)
    end
  end

  -- ---- 轨道（换关才写）----
  placeTrack(ui, sc)

  -- ---- 洞穴（静止练习关没有轨道，也就没有洞穴）----
  if ui.cave then
    if sc.still or not sc.path then
      setVisible(ui, ui.cave, false)
      setVisible(ui, ui.caveLabel, false)
      for i = 1, #ui.caveGlow do setVisible(ui, ui.caveGlow[i], false) end
    else
      local e = sc.path:pointAt(sc.path.length)
      local R = mt.R * V.caveR
      -- 三层红晕（本体是径向渐变）+ 暗心；fancy 关了就只有暗心
      if ui.fancy ~= 0 then
        for i = 1, #ui.caveGlow do
          local k = 1 + 0.16 * i          -- 1.16 / 1.32 / 1.48：贴着本体那一圈，不要铺开一大片
          local glow = ui.caveGlow[i]
          -- ★ 用**空心圆**素材（ui.artRing）：洞口本来就是"环"，空心圆染红正好；
          --   实心圆在这里得靠叠层+透明度装成环，效果差一截。
          placeBead(ui, glow, cx, cy, e.x, e.y, R * k, C.caveGlow[i] or C.caveGlow[1], ui.artRing)
          -- 呼吸：慢慢放大缩小，让"洞口"看着是活的
          setScaleRaw(glow, 1 + 0.05 * math.sin((ui.t + i * 0.35) * 2.4))
        end
      else
        for i = 1, #ui.caveGlow do setVisible(ui, ui.caveGlow[i], false) end
      end
      placeBead(ui, ui.cave, cx, cy, e.x, e.y, R, C.caveCore)
      place(ui, ui.caveLabel, cx, cy, e.x, e.y + R + 14 * (mt.scale or 1), 160, 28, 0)
    end
  end

  -- ---- 球（+ 状态光晕 + 碱基字母）----
  local beads = sc.beads.spawn
  local pool = ui.balls
  for i = 1, #pool do
    local c = pool[i]
    local b = beads[i]
    if b then
      local d = 2 * b.r
      if setField(ui, c, 'anchoredPositionX', b.x - cx) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      if setField(ui, c, 'anchoredPositionY', cy - b.y) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      if setField(ui, c, 'sizeDeltaX', d) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      if setField(ui, c, 'sizeDeltaY', d) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      if setVisible(ui, c, true) then ui.stats.ballWrites = ui.stats.ballWrites + 1 end
      -- 配错 = 灰球；已配对但还没定型，用原色（吸附飞行途中）
      local hex = b.wrongMark and CFG.WRONG_COLOR or baseColor(b.base)
      setColor(ui, c, hex)
      setImage(ui, c, artIdOf(ui, b.base))

      -- 光晕：读出/配错才亮（本体 drawBead 的 glow：球外 r+3 处一圈**描边**，不是大圆盘）
      if ui.halo[i] then
        if ui.fancy ~= 0 and ui.glowOn ~= 0 and b.pairGlow then
          -- ★ 用**空心圆**素材画成细环（实心圆画 2.1× 会像"球变大了" —— 用户一眼看出不对）
        placeBead(ui, ui.halo[i], cx, cy, b.x, b.y, glowRadius(b.r), b.pairGlow, ui.artAny)
        else
          setVisible(ui, ui.halo[i], false)
        end
      end

      -- 字母：本体把 label 画在球面上
      -- ★ 经典祖玛（§66）：原版是**纯色球、没有字母** ⇒ 经典关不画字母（隐藏该控件）
      if ui.letter[i] then
        if sc.rules == 'classic' then
          setVisible(ui, ui.letter[i], false)
        else
          local lc = ui.letter[i]
          local ink = b.wrongMark and (CFG.WRONG_INK or C.letterOnLight) or (CFG.inkOf(b.base, sc.rules) or C.letterOnLight)
          place(ui, lc, cx, cy, b.x, b.y, d, d, 0)
          lc.text = tostring(b.label or b.base or '')
          lc.fontSize = math.max(8, math.floor(b.r * V.letterScale))
          lc.fontColor = hexColor(ink)
        end
      end
    else
      setVisible(ui, c, false)
      if ui.halo[i] then setVisible(ui, ui.halo[i], false) end
      if ui.letter[i] then setVisible(ui, ui.letter[i], false) end
    end
  end

  -- ---- 绑定小球 + 配对连线（"读出"这件事的可视化）----
  -- sc.beads.eliminate[i] = 副轨上的那一半；它的 .partner 指向主轨上被读出的球。
  local elim = sc.beads.eliminate
  local li = 0
  -- ★ 优化：这张表每帧都要用，**复用**而不是新建（真机 GC 压力）
  local liveElim = ui._liveElim or {}
  ui._liveElim = liveElim
  for k in pairs(liveElim) do liveElim[k] = nil end
  for i = 1, #ui.elim do
    local e = elim[i]
    if e then
      -- ★★ 控件复用前先复位（HANDOFF §29）：绑定小球池是按**槽位**复用的，
      --   而这颗槽位上一颗球的"炸开淡出"（把控件放大到 1.9×）可能还没播完 →
      --   新球就会顶着 1.9 倍出现。用户报的"3n 道上的小球异常增大"就是这个，
      --   而且他给的分界完全对：新手第 1 关**不发生消除**（gone 动效 0 次）所以从没出现，
      --   第 2 关开始才消除 → 第 2 关起才开始出现。
      local key = (e.partner and e.partner.id) or ('dock:' .. tostring(e.base))
      if ui.elimShown[i] ~= key then
        cancelFx(ui, ui.elim[i])          -- 换了另一颗球 = 回收：清掉残留动效 + 缩放复位
        ui.elimShown[i] = key
      end
      placeBead(ui, ui.elim[i], cx, cy, e.x, e.y, e.r,
        e.wrong and CFG.WRONG_COLOR or baseColor(e.base), artIdOf(ui, e.base))
      -- ★ 副轨绑定球的描边（本体：它的 glow=true 且 glowColor 为空 → 白色描边）
      local eh = ui.halo and ui.haloHalf and ui.halo[ui.haloHalf + i]
      if eh and ui.fancy ~= 0 and ui.glowOn ~= 0 then
        placeBead(ui, eh, cx, cy, e.x, e.y, glowRadius(e.r), '#ffffff80', ui.artAny)  -- 本体是 rgba(255,255,255,0.5)
      elseif eh then
        setVisible(ui, eh, false)
      end
      -- ★ 绑定小球上的字母（本体副轨那颗也画字母）
      local lc = ui.elimLetter and ui.elimLetter[i]
      if lc then
        local d2 = 2 * e.r
        place(ui, lc, cx, cy, e.x, e.y, d2, d2, 0)
        lc.text = tostring(e.base or '')
        lc.fontSize = math.max(8, math.floor(e.r * V.letterScale))
        local ink = e.wrong and (CFG.WRONG_INK or C.letterOnLight) or (CFG.BASE_INK[e.base] or C.letterOnLight)
        lc.fontColor = hexColor(ink)
        setVisible(ui, lc, true)
      end
      local pid = e.partner and e.partner.id
      if pid ~= nil then
        liveElim[pid] = true
        ui.elimOwner[pid] = ui.elim[i]
        ui.elimSlot[pid] = i
        ui.elimHex[pid] = e.wrong and CFG.WRONG_COLOR or baseColor(e.base)
        -- ★★ 2026-09-25 删掉"配对时弹一下"（原来会先把控件缩到 0.25 再弹回 1）。
        --   用户原话："变大我看上去没有任何意义，删掉就好了"；而且**本体也没有这个效果**
        --   （本体只有 pairGlow 的描边，不改尺寸）。现在绑定小球出现即 1:1 大小。
      end
    else
      setVisible(ui, ui.elim[i], false)
      ui.elimShown[i] = nil      -- 槽位空出来：下次有新球进来就算"换球"，会先复位动效/缩放
      if ui.elimLetter and ui.elimLetter[i] then setVisible(ui, ui.elimLetter[i], false) end
      -- ★★ 这里原来写的是 `if eh then setVisible(ui, eh, false) end` —— 而 eh 是上面 if 分支里的
      --    local，**出了作用域**（Lua 不报错，直接是 nil），于是这条隐藏**永远不执行**
      --    → 亮过的白圈永久留在三消道上。用户报"没匹配也有一堆奇怪白圈"就是它。
      --    教训：跨分支用局部变量这种错 Lua 静默通过，只有"配对消失后要收干净"的测试能逮住。
      local stale = ui.halo and ui.haloHalf and ui.halo[ui.haloHalf + i]
      if stale then setVisible(ui, stale, false) end
    end
  end
  -- 读完的球（或整段被消掉）：把它的绑定小球**直接收掉**（原有"炸开淡出"已按用户要求删除，见上）
  if ui.fancy ~= 0 then
    for pid, c in pairs(ui.elimOwner) do
      if not liveElim[pid] then
        local wasLive = false
        for i = 1, #elim do
          local e = elim[i]
          if e and e.partner and e.partner.id == pid then wasLive = true; break end
        end
        if not wasLive and ui.wasPaired[pid] == true then
          -- 收掉这颗球：如果它的槽位还残留着动效（比如"弹一下"还没播完），一并清掉并复位缩放
          cancelFx(ui, c)
        end
        ui.elimOwner[pid] = nil
        ui.elimSlot[pid] = nil
        ui.elimHex[pid] = nil
        ui.wasPaired[pid] = nil
      end
    end
  end
  local barW = math.max(2, V.linkWidth * (mt.scale or 1))
  for i = 1, #elim do
    local e = elim[i]
    local p = e.partner
    if p then
      local hex = e.wrong and CFG.WRONG_COLOR or baseColor(e.base)
      local dx, dy = p.x - e.x, p.y - e.y
      local len = math.sqrt(dx * dx + dy * dy)
      if len > 1e-6 then
        if e.wrong then
          -- 错配：折线（DESIGN §32：主题上就是"氢键接不上"）。两段 = 两个控件。
          local px, py = -dy / len, dx / len
          local amp = math.max(2.5, V.linkAmp * (mt.scale or 1))
          if li + 2 <= #ui.links then
            li = li + 1
            placeSeg(ui, ui.links[li], cx, cy,
              e.x + dx * V.linkFrom, e.y + dy * V.linkFrom,
              e.x + dx * 0.42 + px * amp, e.y + dy * 0.42 + py * amp, barW, hex)
            li = li + 1
            placeSeg(ui, ui.links[li], cx, cy,
              e.x + dx * 0.58 - px * amp, e.y + dy * 0.58 - py * amp,
              e.x + dx * V.linkTo, e.y + dy * V.linkTo, barW, hex)
          end
        elseif li + 1 <= #ui.links then
          li = li + 1
          placeSeg(ui, ui.links[li], cx, cy,
            e.x + dx * V.linkFrom, e.y + dy * V.linkFrom,
            e.x + dx * V.linkTo, e.y + dy * V.linkTo, barW, hex)
        end
      end
    end
  end
  for i = li + 1, #ui.links do setVisible(ui, ui.links[i], false) end

  -- ---- 状态记忆（给下一帧判断"刚读出/刚消失"）----
  for i = 1, #beads do
    local b = beads[i]
    if b.id ~= nil then ui.wasPaired[b.id] = b.paired and true or false end
  end

  -- ---- 弹药 ----
  local shots = sc.projectiles
  for i = 1, #ui.shots do
    local c = ui.shots[i]
    local p = shots[i]
    if p then
      placeBead(ui, c, cx, cy, p.x, p.y, p.r, baseColor(p.base), artIdOf(ui, p.base))
    else
      setVisible(ui, c, false)
    end
  end

  -- ---- 并入球（U12：正在挤进去的那颗，画在同层链珠之上）----
  local merges = sc.merges or {}
  for i = 1, #ui.merges do
    local m = merges[i]
    if m then
      placeBead(ui, ui.merges[i], cx, cy, m.x, m.y, m.r, baseColor(m.base), artIdOf(ui, m.base))
    else
      setVisible(ui, ui.merges[i], false)
    end
  end

  -- ---- 核糖体（发射口）+ 两颗待发球 + 瞄准线 + 冷却环 ----
  local rb = sc.rb
  if rb then
    local R = rb.r
    local ax, ay = math.cos(rb.aim), math.sin(rb.aim)
    -- 瞄准线：从炮口沿 aim 方向，长度 R + 110×scale（本体 drawRibosome 原式），30% 透明
    placeSeg(ui, ui.aim, cx, cy, rb.x, rb.y,
      rb.x + ax * (R + V.aimLen * (mt.scale or 1)), rb.y + ay * (R + V.aimLen * (mt.scale or 1)),
      math.max(1, V.aimWidth * (mt.scale or 1)), C.aim)
    -- 核糖体本体
    placeBead(ui, ui.rb, cx, cy, rb.x, rb.y, R, C.rbBody)
    -- 开火冷却环：径向填充，满了就该能打了。
    -- ★★ **本体没有这个东西**（`src/render.js` 里根本没有 cooldown 的绘制，它只是规则值）。
    --    按"屏幕上默认不许出现本体没有的东西"这条规矩（HANDOFF §19），**默认关**；
    --    想看就填脚本变量 cd=1。
    if ui.cd then
      if ui.fancy ~= 0 and ui.cdOn == 1 and rb.cooldown and rb.cooldown > 0.001 then
        local total = (CFG.DESIGN and CFG.DESIGN.fireCooldown) or 0.16
        local p = 1 - math.min(1, rb.cooldown / total)
        placeBead(ui, ui.cd, cx, cy, rb.x, rb.y, R * 1.45, C.cd)
        ui.cd:SetFillRadial360(Enum.ImageFillRadialType.Top, p)
      else
        setVisible(ui, ui.cd, false)
      end
    end
    -- 两颗待发球：炮口那颗在前（+0.8R，半径 ×1.0）、待命那颗在后（−0.7R，半径 ×0.8）
    -- （本体 render.js drawRibosome 原文：`bR = (mode==='insert') ? mt.R : mt.r`）
    local bR = (sc.mode == 'insert') and mt.R or mt.r
    local b1, b2 = rb.loaded and rb.loaded[1], rb.loaded and rb.loaded[2]
    local lx1, ly1 = rb.x + ax * R * 0.8, rb.y + ay * R * 0.8
    local lx2, ly2 = rb.x - ax * R * 0.7, rb.y - ay * R * 0.7
    placeBead(ui, ui.loaded[1], cx, cy, lx1, ly1, bR, baseColor(b1), artIdOf(ui, b1))
    placeBead(ui, ui.loaded[2], cx, cy, lx2, ly2, bR * 0.8, baseColor(b2), artIdOf(ui, b2))
    -- ★★ 两颗待发球的字母（本体 lb(1) / lb(0) 都画）。
    -- ★★★ 2026-09-25 **临时探针**（定位"③ 的字母设好了却不显示"）：
    --   真机日志已证明 ③ 的文本框「文字=G 可见=true 字号=15 位置=(0,-21)」全都正常，
    --   屏幕上却没有 —— 只剩两种可能，探针一次判定：
    --     · 看到"红底方块 + 白字 G" → 控件会被绘制，是尺寸/颜色问题 → 据此收窄；
    --     · 什么都看不到            → 这个控件不在绘制列表里 → 改用**链珠字母那套池子**画。
    --   探针只动 ③（k=2），④ 全程不动；`letterProbe=0` 可关掉。
    for k = 1, 2 do
      local lc = ui.loadedLetter and ui.loadedLetter[k]
      -- ★ 经典祖玛（§66.6）：原版是**纯色球** —— 核糖体上那两颗（炮口/预备）也**不加字母**。
      --   奇匠原话："经典模式下的核糖体就别在上面加字母了"。（链珠字母早在 §66 就关了。）
      if sc.rules == 'classic' then lc = nil end
      if lc then
        local base = (k == 1) and b1 or b2
        local rr = (k == 1) and bR or bR * 0.8
        local xx = (k == 1) and lx1 or lx2
        local yy = (k == 1) and ly1 or ly2
        local probe = (ui.letterProbe ~= 0) and (k == 2)
        -- ★★ 框尺寸：**不小于链珠字母的框**（2×mt.r）。
        --   真机事实（2026-09-25）：③ 原来用 2×rr = 21.5px 的框，状态全对（文字/可见/字号/位置
        --   都对）却**不显示**；探针把框放大 + 换红底白字后立刻显示。而链珠字母的框是 26.9px，
        --   一直显示正常 ⇒ 取 max(2×球半径, 2×链珠半径)，即"用已被证明能显示的尺寸"。
        local box = math.max(2 * rr, 2 * mt.r)
        local d2 = probe and (rr * 5.6) or box
        place(ui, lc, cx, cy, xx, yy, d2, d2, 0)
        if probe then
          lc.text = 'G'
          lc.fontSize = 24
          lc.fontColor = hexColor('#ffffff')
          lc.bgColor = hexColor('#ff0000cc')
        else
          lc.text = tostring(base or '')
          -- 字号 = 半径 × V.letterScale，**下限 15**：4/链珠/绑定球的自然值都 ≥15，
          -- 所以这个下限只抬升 ③ 那颗最小的球（10.7 → 12 抬到 15）。别改成整体放大，更别加描边。
          lc.fontSize = math.max(15, math.floor(rr * V.letterScale))
          lc.fontColor = hexColor(CFG.BASE_INK[base] or C.letterOnLight)
          lc.bgColor = hexColor('#00000000')
        end
        setVisible(ui, lc, true)
      end
    end
    -- ★ 炮口那颗的白色描边（本体那次 drawBead 的 glow 参数是 true）
    local lh = ui.loadedHalo
    if lh and ui.fancy ~= 0 and ui.glowOn ~= 0 then
      placeBead(ui, lh[1], cx, cy, lx1, ly1, glowRadius(bR), '#ffffff80', ui.artAny)  -- 本体同样 50%
      setVisible(ui, lh[2], false)
    elseif lh then
      setVisible(ui, lh[1], false)
      setVisible(ui, lh[2], false)
    end
  end

  -- ---- 开火后坐（stats.fired 涨了就弹一下）----
  if ui.fancy ~= 0 and ui.rb then
    local fired = (sc.stats and sc.stats.fired) or 0
    if ui.lastFired == nil then ui.lastFired = fired end
    if fired > ui.lastFired then
      ui.fx[#ui.fx + 1] = { c = ui.rb, kind = 'fire', t = 0, dur = 0.16 }
    end
    ui.lastFired = fired
  end

  -- ---- HUD 文本 ----
  -- ★ 没文字的文本框要**连底板一起藏起来**：首轮美化里"结果"文本框一直是空的，
  --   却把 640×120 的半透明黑板画在正中央，把核糖体整个盖住了。
  local function text(key, s)
    local c = ui.hud[key]
    if not c then return end
    if c.text ~= s then c.text = s; ui.stats.hudWrites = ui.stats.hudWrites + 1 end
    if s and s ~= '' then
      setVisible(ui, c, true)
    else
      setVisible(ui, c, false)
    end
  end
  text('score', '分数 ' .. tostring(sc.score))
  text('lives', '命 ' .. tostring(sc.lives))
  local runs = {}
  for i = 1, #sc.runsInfo do
    local r = sc.runsInfo[i]
    runs[#runs + 1] = tostring(r.len) .. (r.len % 3 == 0 and '✓' or ('(+' .. tostring(3 - r.len % 3) .. ')'))
  end
  -- ★ 经典祖玛（§66）：**没有"配对了几个"这回事** —— "连读 x(+y)"那套是 RNA 的 3n 读数，
  --   在经典关显示出来就是一串没意义的 "1(+2) 2(+1)…"（出图时看到满屏都是）。所以经典关不显示。
  if sc.rules == 'classic' then
    text('runs', '')
    text('mode', '')
  else
    text('runs', '连读 ' .. (#runs > 0 and table.concat(runs, ' ') or '—'))
    text('mode', st.mode == 'insert' and '模式：加球' or '模式：配对')
  end
  -- 判定诊断行（st.lastHit / st.mate 由 game.lua 填）：屏幕上直接看得到"这次算配对还是错配"
  if ui.hud.hit then text('hit', st.lastHit or '') end
  if ui.hud.mate then text('mate', st.mate or '') end
  if ui.hud.hint then
    text('hint', st.hintLines and table.concat(st.hintLines, '\n') or '')
  end

  -- ---- 开始菜单（§61）：局内只画左下角那个"回菜单"按钮；菜单态画整屏 ----
  syncMenu(ui, sc, st)
  syncEgg(ui, sc, st)
  syncLock(ui, sc, st)      -- ★ 门禁：调用必须在 syncEgg **之后**（它会覆盖标题/行/按钮）
  return ui
end

-- ==================== 开始菜单（§61）====================
-- 布局**不在**这里算：game.lua 用 menu.lua 算好（那套是本体 config.js 的 1:1 移植、进对拍），
-- 通过 st.menuLayout 传进来。这里只负责画。
syncMenu = function(ui, sc, st)
  local m = ui.menu
  if not m then return end
  local view, mt = sc.view, sc.metrics
  local s = mt.scale or 1
  local cx = view.cx
  local inMenu = (st.screen == 'menu')

  -- 局内左下角「回菜单」按钮（本体 render.js drawMenuButton）
  local pb = MENU.playButtonRect(view, mt)
  local showPb = not inMenu
  place(ui, m.playBtn, cx, view.cy, pb.x, pb.y, pb.r * 2, pb.r * 2, 0)
  setColor(ui, m.playBtn, '#0c1422db')
  setVisible(ui, m.playBtn, showPb)
  place(ui, m.playLabel, cx, view.cy, pb.x, pb.y, pb.r * 2.4, pb.r * 2.4, 0)
  m.playLabel.fontSize = math.max(10, math.floor(12 * s + 0.5))
  m.playLabel.fontColor = hexColor('#e2eefff2')
  setVisible(ui, m.playLabel, showPb)

  if not inMenu then
    setVisible(ui, m.scrim, false)
    setVisible(ui, m.title, false)
    setVisible(ui, m.subtitle, false)
    setVisible(ui, m.footer, false)
    for i = 1, #m.groups do setVisible(ui, m.groups[i], false) end
    for i = 1, #m.btn do
      setVisible(ui, m.btn[i], false)
      setVisible(ui, m.btnLabel[i], false)
    end
    return
  end

  -- ★★ 菜单态**不画局内 HUD**（本体 §61：菜单是独立一屏，HUD 不该从后面透出来）。
  --   HUD 的显示是 M.sync 里的 text() 每帧设的，所以这里在它之后统一收掉；
  --   回到 playing 的下一帧 text() 会自己再显示出来（不用手动恢复）。
  for i = 1, #ui.hudOrder do
    local h = ui.hud[ui.hudOrder[i]]
    if h then setVisible(ui, h, false) end
  end
  if ui.caveLabel then setVisible(ui, ui.caveLabel, false) end

  local L = st.menuLayout
  if not L then return end

  -- 暗幕（本体 rgba(6,10,18,0.87)）
  place(ui, m.scrim, cx, view.cy, cx, view.cy, view.w, view.h, 0)
  setColor(ui, m.scrim, '#060a12de')
  setVisible(ui, m.scrim, true)

  -- 标题 + 副标题（本体 drawMenu 的文案与字号）
  local tw = view.w
  place(ui, m.title, cx, view.cy, cx, L.titleY, tw, math.max(40, 60 * s), 0)
  m.title.text = 'RNA 祖玛'
  m.title.fontSize = math.max(26, math.floor(44 * s + 0.5))
  m.title.fontColor = hexColor('#e8f2ff')
  setVisible(ui, m.title, true)

  place(ui, m.subtitle, cx, view.cy, cx, L.titleY + math.max(20, 30 * s), tw, 30 * s, 0)
  m.subtitle.text = '反色配对 · 凑三颗 · 读出 mRNA'
  m.subtitle.fontSize = math.max(11, math.floor(15 * s + 0.5))
  m.subtitle.fontColor = hexColor('#a0c3ebf2')
  setVisible(ui, m.subtitle, true)

  -- 分组标题（左对齐在 x0）
  for i = 1, #m.groups do
    local g = m.groups[i]
    local rec = L.groups[i]
    if rec then
      place(ui, g, cx, view.cy, L.x0 + L.innerW / 2, rec.y + 8 * s, L.innerW, 20 * s, 0)
      g.horizontalAlignment = Enum.TextHorizontalAlignment.Left
      g.text = rec.name
      g.fontSize = math.max(11, math.floor(14 * s + 0.5))
      g.fontColor = hexColor('#96c8f0e6')
      setVisible(ui, g, true)
    else
      setVisible(ui, g, false)
    end
  end

  -- 关卡按钮（本体：新手关偏青、核心关偏蓝；⚠ 图片控件画不了描边，所以只有填充色）
  for i = 1, #m.btn do
    local b = L.buttons[i]
    local btn, lab = m.btn[i], m.btnLabel[i]
    if b then
      local tut = (b.item.group == '新手关')
      place(ui, btn, cx, view.cy, b.x + b.w / 2, b.y + b.h / 2, b.w, b.h, 0)
      setColor(ui, btn, tut and '#1a3c3af2' or '#162032f2')
      setVisible(ui, btn, true)
      place(ui, lab, cx, view.cy, b.x + b.w / 2, b.y + b.h / 2, b.w, b.h, 0)
      lab.text = b.item.label or ''
      lab.fontSize = math.max(11, math.floor(15 * s + 0.5))
      lab.fontColor = hexColor('#eaf4ff')
      setVisible(ui, lab, true)
    else
      setVisible(ui, btn, false)
      setVisible(ui, lab, false)
    end
  end

  -- 底部操作说明（★ 本体那句写的是 "Esc 回菜单"；移植侧没有 Esc，
  --   离开一关靠左下角实体按钮 —— 所以这里按**移植侧真实操作**改写过，别照抄本体）
  place(ui, m.footer, cx, view.cy, cx, L.footerY, view.w, 30 * s, 0)
  m.footer.text = '点关卡开始 · 点画面发射 · 点核糖体换珠 · 点右下角切模式 · 点左下角回菜单'
  m.footer.fontSize = math.max(10, math.floor(12 * s + 0.5))
  m.footer.fontColor = hexColor('#96b4d7e6')
  setVisible(ui, m.footer, true)
end

-- ui 一共建了多少个控件（诊断行 + 预算自检用）
function M.count(ui)
  -- ★★ 2026-09-25 修：这个自检**少算了 101 个**（漏了绑定球字母池 96 + 背板 1 +
  --   待发球描边 2 + 待发球字母 2）—— 长期报 817，而真实占用是 917。
  --   平台上限是"单控件组 1000"，少算 101 会把余量看成 183（实际只有 83）✗。
  --   现在按池子列全；test_perf 里有断言钉死"它必须等于真机建出来的控件数"。
  local n = #ui.balls + #ui.shots + #ui.links + #ui.elim + #ui.merges
    + #ui.track + #ui.halo + #ui.letter + #ui.loaded
    + #(ui.elimLetter or {}) + #(ui.loadedLetter or {}) + #(ui.loadedHalo or {})
    + (ui.backdrop and 1 or 0)
    + (ui.rb and 1 or 0) + (ui.aim and 1 or 0) + (ui.cd and 1 or 0)
    + (ui.cave and 1 or 0) + (ui.caveLabel and 1 or 0) + #ui.caveGlow
    + #ui.hudOrder
    + (ui.egg and 56 or 0)                   -- 彩蛋图层（暗幕1 + 标题1 + 数据5；按钮复用菜单池 ⇒ 不计）
    + (ui.menu and (6 + #ui.menu.groups + #ui.menu.btn * 2 + 2) or 0)   -- 菜单图层（暗幕/标题/副标题/说明/分组/按钮+文字/回菜单按钮+文字）
  return n
end

-- 平台上限自检（《编辑项范围限制》：单控件组 1000 / 单屏 10000）
function M.budget(ui)
  return M.count(ui), 1000, 10000
end

return M
end

-- ---------------- input ----------------
__M["input"] = function()
-- input.lua —— 输入层：光标/按键 -> 瞄准角与"要做什么"的意图。
--
-- ★ 这一层**不直接调 board**：它只改 sc.rb.aim（瞄准是输入的事）并留下意图标志，
--   由 game.lua 决定什么时候真的开火/换球/切模式。这样输入层可以单独测。

local CFG = require('config')
local RB = require('ribosome')

local M = {}

-- 画布 UI 坐标（官方：以画布**左下角**为原点，y 向上）
-- -> board 坐标（画布像素、原点左上、y 向下）
function M.toBoard(canvas, x, y)
  return x, canvas.h - y
end

-- opts:
--   area       CursorEventArea 控件（铺满玩区的那块）
--   keyTarget  挂键盘监听的控件（一般是画布根控件）
--   canvas     { w, h }
--   stick      是否也用手柄摇杆瞄准（默认关）
function M.create(opts)
  opts = opts or {}
  local canvas = opts.canvas or { w = 900, h = 900 }
  local inp = {
    canvas = canvas,
    firing = false,        -- 按住 = 连发（冷却由 DESIGN.fireCooldown 管）
    pending = 0,           -- 一次性开火（模拟点击会给一个）
    wantSwap = false,
    wantMode = false,
    wantRestart = false,
    useCursor = true,
    stickX = 0, stickY = 0,
    hold = false,
    stats = { clicks = 0, keys = 0, fires = 0 },
  }

  local area = opts.area
  if area then
    area:AddCursorEventListener(Enum.CursorEventType.CursorDown, function(d)
      inp.hold = true
      inp.stats.clicks = inp.stats.clicks + 1
    end)
    area:AddCursorEventListener(Enum.CursorEventType.CursorUp, function()
      inp.hold = false
    end)
    area:AddCursorEventListener(Enum.CursorEventType.CursorClick, function(d)
      inp.pending = inp.pending + 1
      inp.stats.clicks = inp.stats.clicks + 1
      -- ★ 菜单/按钮要用"点在哪"。官方 API 直接给光标坐标（左下原点、y 向上），
      --   这里立刻换算成**棋盘坐标**存下来 —— 不依赖回调参数 d 的形状（那个没文档保证）。
      local ok, gx, gy = pcall(game.GetCursorUIPos)
      if ok and type(gx) == 'number' and type(gy) == 'number' then
        local bx, by = M.toBoard(inp.canvas, gx, gy)
        inp.clickX, inp.clickY = bx, by
      end
    end)
  end

  local kt = opts.keyTarget
  if kt then
    -- ★★ 真机契约（2026-09-25 真机日志）：
    --   1. `Enum.KeyEventType` 是**逐键**成员 —— `KeyboardNormalAttackKeyDown`、
    --      `KeyboardCharacterSkill3KeyDown`、`KeyboardJumpKeyDown` …（官方文档里 164 个），
    --      **没有** `KeyDown` / `KeyUp` 这种通用成员。第一版按通用名写，真机直接报
    --      `bad argument #2 to 'AddKeyEventListener' (KeyEventType expected, got nil)`。
    --   2. 回调**没有参数**（不是"给你一个键码让你自己比"），注册哪个键就代表哪个键；
    --      返回 true = 已处理（容器内其他控件不再响应这次按键）。
    --   3. 成员名在不同版本可能微调 → 这里按候选名**探测**，缺哪个就在日志里点名，
    --      而不是让整局崩在这一行。
    local KEYMAP = {
      { 'fireDown', { 'KeyboardNormalAttackKeyDown', 'ControllerNormalAttackKeyDown' } },
      { 'fireUp', { 'KeyboardNormalAttackKeyUp', 'ControllerNormalAttackKeyUp' } },
      { 'modeDown', { 'KeyboardOpenShortcutWheelKeyDown' } },          -- Tab：切模式
      { 'swapDown', { 'KeyboardJumpKeyDown', 'ControllerJumpKeyDown' } }, -- 空格：换手里那颗
      { 'restartDown', { 'KeyboardCharacterSkill3KeyDown' } },         -- R：重开本关
    }

    local function pick(cands)
      for i = 1, #cands do
        local v = Enum.KeyEventType[cands[i]]
        if v ~= nil then return v, cands[i] end
      end
      return nil, cands[1]
    end

    -- 不依赖控件的日志通道（和 game.lua 一样：挂了也要说清是哪个键没注册上）
    local function log(fmt, a, b)
      if not print then return end
      local ok, s = pcall(string.format, fmt, a, b)
      if not ok then s = tostring(fmt) end
      pcall(print, '[zuma] ' .. s)
    end

    local handlers = {
      fireDown = function()
        inp.hold = true
        inp.stats.keys = inp.stats.keys + 1
        return true
      end,
      fireUp = function()
        inp.hold = false
        return true
      end,
      modeDown = function() inp.wantMode = true; return true end,
      swapDown = function() inp.wantSwap = true; return true end,
      restartDown = function() inp.wantRestart = true; return true end,
    }

    local bound = {}
    for i = 1, #KEYMAP do
      local act, cands = KEYMAP[i][1], KEYMAP[i][2]
      local et, name = pick(cands)
      if et == nil then
        log('⚠ 按键事件 %s 在这台机器上不存在（试过：%s）—— 这个操作暂时用不了', act, name)
      else
        local ok, err = pcall(function() kt:AddKeyEventListener(et, handlers[act]) end)
        if ok then
          bound[#bound + 1] = act .. '=' .. name
        else
          log('⚠ 注册按键事件 %s 失败：%s', name, tostring(err))
        end
      end
    end
    log('按键绑定：%s', table.concat(bound, ' '), nil)
  end

  return inp
end

-- 每帧：更新瞄准角，并把意图整理成 inp.firing / wantXxx
function M.update(inp, sc, dt)
  if inp.useCursor then
    local gx, gy = game.GetCursorUIPos()
    local bx, by = M.toBoard(inp.canvas, gx, gy)
    RB.aimAt(sc.rb, bx, by)
  elseif inp.stickX ~= 0 or inp.stickY ~= 0 then
    sc.rb.aim = math.atan(inp.stickY, inp.stickX)
  end

  inp.firing = (inp.hold or inp.pending > 0)
  return inp
end

-- 开火意图被消费掉之后调用
function M.consume(inp)
  inp.pending = 0
  inp.clickX, inp.clickY = nil, nil
end

return M
end

-- ---------------- game ----------------
__M["game"] = function()
-- game.lua —— 宿主胶水：脚本生命周期 + 每帧主循环 + 关卡推进。
--
-- 这就是**最终要上传到千星奇域的那个脚本**的门面（打包器会把它和内核一起打成 out/zuma.lua）。
--
-- 编辑器里要做的事（详见 miliastra/pc/操作手册.html）：
--   1. 建一个**客户端控件容器画布**（不要用主屏）；
--   2. 建 4 个客户端控件模板：图片（球）/ 文本框 / 光标检测区域 / 玩区容器；
--   3. 在这个容器的**脚本页签**里挂上打包后的 zuma.lua；
--   4. 把模板索引填进脚本变量（下面这张表）。
--
-- 脚本变量（编辑期填，运行期用 script:GetParam 读；不填就用括号里的默认值）：
--   levelIndex   从第几关开始（1..11，1 = ① 配对）              [1]
--   autoPrefabs  自动认控件模板（下面的索引**一个都不用填**）      [1]
--   ballPrefab   球控件的客户端控件模板索引（填了就不用自动认）    [自动]
--   shotPrefab   弹药控件的模板索引（不填则跟球一样）              [= ballPrefab]
--   hudPrefab    文本框控件的模板索引                              [自动]
--   cursorPrefab 光标检测区域控件的模板索引                        [自动]
--   playPrefab   玩区容器控件的模板索引（不填则跟球一样）          [自动]
--   ballCount    球池大小                                        [96]
--   shotCount    弹药池大小                                      [8]
--   fancy        光晕 / 冷却环 / 动效（0 = 只留静态画面）          [1]
--   track        轨道也由 Lua 画（0 = 用编辑器里摆的静态图）      [1]
--   trackSegments 每条轨画多少段（⚠ 调小省控件但真机有接缝）      [64]
--   letters      球面叠碱基字母（0 = 只靠图片素材）               [1]
--   seed         随机种子                                        [12345]
--   autoNext     过关后自动进下一关（0 = 不自动）                [1]
--   diag         屏幕左下角显示诊断行（排错用，正式发布再关）    [1]
--
-- ★★ 为什么要 diag：我在手机上**看不到你的电脑屏幕**。
--   出问题时屏幕上那行字就是你转述给我的唯一线索，所以默认开着。

local CFG = require('config')
local BOARD = require('board')
local RB = require('ribosome')
local UI = require('ui')
local MENU = require('menu')       -- 开始菜单（§61）：布局是本体 config.js 的 1:1 移植
local INPUT = require('input')
local LEVELS_DATA = require('levels_data')

local G = {}

G.screen = 'boot'          -- boot | playing | won | lost | error
G.resultTimer = 0
G.nextDelay = 2.5
G.loseDelay = 3.0
G.error = nil
G.frames = 0

local function param(name, default)
  local v = script and script:GetParam(name)
  if v == nil then return default end
  return v
end

-- 不依赖控件的日志通道（官方日志 API）。
-- ★ 为什么必须有：真机上控件要等到 OnStart 才建得出来，一旦在那之前失败，
--   屏幕上那行"诊断字"本身也是控件、也建不出来 —— 这时只剩日志能告诉我们死在哪。
-- ★★ 为什么格式化失败也要把值打出来：第一次真机试玩时这行打成了字面量 `画布 %dx%d` ——
--   `%d` 遇到非整数（真机 canvas 尺寸是浮点）会抛错，pcall 一接住就只剩格式串，
--   等于**把最想看的信息吞了**。现在退回"格式串 + 值"，丑但有用。
local function say(fmt, ...)
  local ok, s = pcall(string.format, fmt, ...)
  if not ok then
    local n = select('#', ...)
    local parts = {}
    for i = 1, n do parts[i] = tostring((select(i, ...))) end
    s = tostring(fmt) .. '   [' .. table.concat(parts, ' ') .. ']'
  end
  if print then pcall(print, '[zuma] ' .. s) end
end

-- 玩区容器的尺寸 = 画布尺寸；它以画布中心为原点
-- panel: 'solid'（默认，65% 底板）/ 'light'（40%，给大块文字）/ false（不画底板）
-- ★★ 规则：移植版**默认要和本体长得一样**。
--   下面这两条是移植期加的"辅助线"，本体没有 —— 所以**默认关**，要排查时填脚本变量开：
--     diag=1  → 左下角那行状态（帧/关卡/球数/控件数/状态）
--     teach=1 → 左上角两行教学（手里该打谁 + 上次命中判定）
--   默认全关时，屏幕上的东西和网页版一一对应，不多一个字。
local function buildHudSpecs(w, h, teach)
  local pad = 16
  local halfW, halfH = w / 2, h / 2
  local specs = {
    { key = 'score', x = -halfW + 230 + pad, y = halfH - 92 - pad, w = 240, h = 44, size = 30, align = 'left' },
    { key = 'lives', x = halfW - 120 - pad, y = halfH - 32 - pad, w = 240, h = 44, size = 30, align = 'right' },
    { key = 'runs', x = -halfW + 330 + pad, y = halfH - 144 - pad, w = 440, h = 40, size = 26, align = 'left' },
    { key = 'mode', x = -halfW + 120 + pad, y = -halfH + 32 + pad, w = 240, h = 44, size = 26, align = 'left' },
    { key = 'hint', x = 0, y = -halfH + 130, w = math.min(w - 40, 760), h = 130, size = 24, align = 'center', panel = 'light' },
    -- 结果框在正中央：**平时没有文字**，所以不给底板（给了就是一块盖住核糖体的黑板）
    { key = 'result', x = 0, y = 0, w = math.min(w - 40, 640), h = 120, size = 40, align = 'center', panel = false },
  }
  -- teach=1 才加那两行辅助（本体没有）：手里该打谁 + 上次命中判定
  if teach then
    specs[#specs + 1] = { key = 'mate', x = -halfW + 230 + pad, y = halfH - 238 - pad, w = 640, h = 36, size = 22, align = 'left' }
    specs[#specs + 1] = { key = 'hit', x = -halfW + 230 + pad, y = halfH - 196 - pad, w = 640, h = 36, size = 22, align = 'left' }
  end
  return specs
end

-- ★★ 自动"借"一张图：真机上图片控件没配图就画成"?"（用户实测：球、轨道、中央全是"?"）。
--   素材 id 在编辑器里是大数字，抄起来烦 —— 所以让脚本自己在**画布里找**：
--   官方 ClientUIBaseControl:GetChildren() 能拿到直接子控件，图片控件的 imageId 是**只读**字段。
--   只要你**在画布里放一个配好图的图片控件**（哪怕是个装饰图标），脚本就把它那张图的 id
--   拿来当所有球/轨道/光晕的素材，一个数字都不用抄。
--   （也可以直接填 `artImage=1073741860` 指定；或按碱基分别填 `art=A:id,U:id,...`）
local function adoptImageId(root)
  local found = {}
  local seen = {}
  local function walk(ctrl, depth)
    if not ctrl or depth > 4 or #found >= 12 or seen[ctrl] then return end
    seen[ctrl] = true
    local ok, kids = pcall(function() return ctrl:GetChildren() end)
    if not ok or type(kids) ~= 'table' then return end
    for i = 1, #kids do
      local ch = kids[i]
      local id = ch and ch.imageId
      local t = typeof and typeof(ch) or nil
      -- ★ 只认**正整数**：0 表示"没配图"（真机/假宿主都会这么给），捡了 0 等于没设 → 全画成"?"
      if type(id) == 'number' and id > 0 and type(t) == 'string' and t:find('Image', 1, true) then
        found[#found + 1] = { id = id, name = tostring(ch.name), t = t }
      end
      walk(ch, depth + 1)
    end
  end
  -- ① 挂载点往下；② 挂载点往上的三层（用户可能把"配好图的控件"摆在画布别处）；
  -- ③ 官方 game.GetClientUIRoots()（"实际显示的画布默认容器节点"）各自的子树。
  walk(root, 1)
  local up = root
  for _ = 1, 3 do
    if not up then break end
    up = up.parent
    walk(up, 1)
  end
  local okr, roots = pcall(function() return game.GetClientUIRoots() end)
  if okr and type(roots) == 'table' then
    for i = 1, #roots do walk(roots[i], 1) end
  end
  return found
end

-- ==================== 启动 ====================

function G.OnInit()
  -- ★★ 第一行就要说话：**日志里看不到这行 = 脚本根本没跑起来**（映射没挂上 / 容器不可见）。
  --   这是排错的第一分叉点，所以放在所有可能失败的动作之前，而且用不依赖控件的 print。
  say('★ zuma 脚本已启动（日志里能看到这行 = 脚本挂上了）')
  -- ★★ 真机限制（来源：客户端 Lua 运行时真机探针 + 官方《客户端控件 API 文档》）：
  --   1. game.InstantiateClientUIControl 在 **OnInit 阶段返回 nil**，只有 OnStart 及之后成功。
  --      —— 所以这里**一个控件都不建**，全部挪到 OnStart（见 G.tryBoot）。
  --   2. 官方 API 有 script:EnableUpdate(enabled)；真机结论是「EnableUpdate 前无 OnUpdate」。
  --      —— 不打开它，OnUpdate 永远不会被调用，画面就是死的。
  -- 因此 OnInit 里只做**不可能失败**的事。
  local ok0, w, h = pcall(game.GetUICanvasSize)
  if not ok0 then w, h = 900, 900 end
  G.canvas = { w = w, h = h }
  G.view = CFG.viewFor(w, h)
  -- ★★ 显示缩放 zoom（**移植侧旋钮，本体没有** → 默认 1 = 完全照本体）。
  --   用途：只想让整个画面（球/轨道/洞穴）大一点，又不想去编辑器改画布尺寸时，
  --   填 zoom=1.2 就行。做法是把 rx/ry/scale **一起**乘 —— 于是所有尺寸等比放大，
  --   R/r 仍是 √2、规则数值一个没动（碰撞/间距都由 mt 推导，等比缩放不改变行为）。
  --   ★ 更"正统"的做法是改画布：画布 1280×1280 时 base=1280 → scale=1.4222，
  --     大球 R 19→27.0、小球 r 13.4→19.1（正好就是"2 : √2"），且本体同样视口算出来一模一样。
  local zoom = tonumber(tostring(param('zoom', '')))
  if zoom and zoom > 0 and zoom ~= 1 then
    G.view.rx, G.view.ry, G.view.scale =
      G.view.rx * zoom, G.view.ry * zoom, G.view.scale * zoom
    G.zoom = zoom
  end
  G.diag = param('diag', 0) ~= 0        -- ★ 默认关：屏幕上要和本体一样，不多一个字
  G.teach = param('teach', 0) ~= 0      -- ★ 默认关：教学辅助行（手里该打谁 / 上次命中判定）
  G.error = nil          -- ★ 每次重来都清掉：否则上一次的错误会一直挂在屏幕上（测试抓到的）
  G.booted = false

  say('OnInit：画布 %s x %s', tostring(w), tostring(h))
  if script and script.EnableUpdate then
    local eok, eerr = pcall(function() script:EnableUpdate(true) end)
    say('EnableUpdate(true) -> %s', eok and 'ok' or tostring(eerr))
  else
    say('警告：没有 script.EnableUpdate，逐帧回调可能不会触发')
  end
  return G
end

-- 真正建控件。**只能在 OnStart 及之后调用**：真机 OnInit 阶段 Instantiate 返回 nil。
function G.tryBoot()
  if G.booted then return end
  G.booted = true
  say('tryBoot：开始建控件')
  local ok, err = pcall(G.boot)
  if ok then
    say('tryBoot：成功')
  else
    G.error = tostring(err)
    G.screen = 'error'
    say('tryBoot 失败：%s', tostring(err))
    -- ★ 失败在"建控件之前"（多半是挂载点/模板/容器的问题）→ 把**真实控件树**打进日志。
    --   官方 API：game.PrintClientUITree() "将当前客户端控件树按父子层级写入日志"。
    --   只在 ui 还没建起来时打（那时树很小）；建了一半就别打了，几百个控件会刷屏。
    if not G.ui and game.PrintClientUITree then
      pcall(game.PrintClientUITree)
      say('已把客户端控件树打进日志（用来确认容器/挂载点到底存不存在）')
    end
    if printerr then pcall(printerr, '[zuma] 建控件失败：' .. tostring(err)) end
  end
  G.refreshDiag()
end

-- ★★ 自动认控件模板：**用户一个变量都不用填**。
--
-- 官方文档《客户端控件和客户端脚本》§八：「编辑时，可以通过点击客户端控件查看对应的控件模板索引ID」
-- —— 也就是说索引是编辑器给的数字，要人去点开看、再抄进脚本变量表。这一步既枯燥又容易抄错
-- （抄错的后果是"球建不出来"或"点击没反应"）。
--
-- 但官方同时提供了 `typeof(value)`（"返回运行时类型名称；用于识别宿主对象"），
-- 于是可以**自己问**：从索引 1 开始挨个尝试建一个控件，看它的运行时类型名是什么，是图片就是球、
-- 是文本框就是 HUD、是光标检测区域就是点击区、是容器就是玩区。探针用完立刻销毁（不占控件数）。
-- 填了脚本变量的以变量为准；没填的用自动认出来的；自动认不出才退回 1/2/3/4。
local function detectPrefabs(root)
  local want = {          -- 变量名 -> 类型名里必须出现的关键词
    ballPrefab = 'Image',
    hudPrefab = 'TextBox',
    cursorPrefab = 'Cursor',
    playPrefab = 'Container',
  }
  local found = {}
  local probe = {}        -- 诊断用：建出来的/报错的都记一笔
  if not (typeof and game.InstantiateClientUIControl and game.DestroyClientUIControl) then
    return found, probe
  end

  -- ★★ 索引空间（这是第一版踩的坑）：真机上"客户端控件模板索引"是**大数字**，
  --   不是 1/2/3/4。实测数据点：用户点开模板看到 1073741846，关卡目录是 1073741825
  --   —— 都从 2^30 起（同一个 ID 空间）。只扫 1..32 的话，"明明存了模板"也会全报 nil。
  local BASE = 1073741824          -- 2^30
  local RANGES = {
    { 1, 32 },                     -- 有些环境/子控件确实用小索引
    { BASE + 1, BASE + 192 },      -- 客户端控件模板的真实空间（覆盖 1073741846 这种）
  }

  local built = 0
  for r = 1, #RANGES do
    local lo, hi = RANGES[r][1], RANGES[r][2]
    local madeHere = 0
    for i = lo, hi do
      -- 小范围（1~32）要**扫完**，否则会漏掉容器模板（它常常排在最后）；
      -- 大范围（2^30 起，192 个索引）只要三个必需的认出来就收工，省得白试两百次。
      if r > 1 and found.ballPrefab and found.hudPrefab and found.cursorPrefab then break end
      local ok, c = pcall(game.InstantiateClientUIControl, i, root)
      if ok and c then
        madeHere = madeHere + 1
        built = built + 1
        local t = typeof(c)
        if #probe < 12 then
          -- ★ 顺带把"这张图控件自带什么图"读出来（官方：imageSource / imageId 是**只读**字段）。
          --   真机上如果这里打出 id=nil，就是"模板根本没配图" → 每个实例都会画成"?"。
          local src, iid = c.imageSource, c.imageId
          probe[#probe + 1] = '索引 ' .. tostring(i) .. '：建出 ' .. tostring(t) ..
            '（自带图 source=' .. tostring(src) .. ' id=' .. tostring(iid) .. '）'
          -- ★★ 图片类型（基础 / 拉伸）：**真机上只读**（我们自己的契约 §14：赋值报
          --    "cannot set imageType"）→ 脚本改不了，只能读出来提醒。
          --    若模板是"拉伸"且素材是三宫格/九宫格，我们放大控件时**四角不变、中间被拉**，
          --    球与光晕各自形变 → 看上去就是"球变大了 / 描边变形"（用户反复反馈的那个）。
          local it = c.imageType
          if it ~= nil then
            local okE, basicVal = pcall(function() return Enum.ImageType.Basic end)
            local isBasic = okE and (it == basicVal)
            probe[#probe + 1] = '图片类型 = ' .. tostring(it) ..
              (isBasic and '（基础 ✓ 正确）'
                or '（★ 拉伸 —— 请到图片模板里把「图片类型」改成基础，素材也别用三宫格/九宫格）')
          end
        end
        for k, word in pairs(want) do
          if found[k] == nil and type(t) == 'string' and t:find(word, 1, true) then found[k] = i end
        end
        pcall(game.DestroyClientUIControl, c)      -- 探针不留痕
      elseif not ok and #probe < 12 then
        probe[#probe + 1] = '索引 ' .. tostring(i) .. '：报错 ' .. tostring(c)
      end
    end
    if madeHere == 0 and #probe < 12 then
      probe[#probe + 1] = '范围 ' .. tostring(lo) .. '~' .. tostring(hi) .. '：一个都建不出来'
    end
  end
  return found, probe, built
end

-- 真正干活的初始化。任何一步失败都会被 OnInit 的 pcall 接住并显示在屏幕上。
function G.boot()
  local w, h = G.canvas.w, G.canvas.h
  G.seed = param('seed', 12345)
  G.autoNext = param('autoNext', 1) ~= 0

  local root = script.object
  local roots = game.GetClientUIRoots and game.GetClientUIRoots() or nil
  local rootCount = (roots and #roots) or 0
  -- ★ 官方定义：GetClientUIRoots() = "实际显示的客户端控件容器画布中的默认容器节点"。
  --   0 = 关卡运行时**没有显示中的画布**（容器没加进界面布局 / 初始可见没勾 / 玩家应用的布局不对）
  --   —— 这种情况下就算模板建好了也什么都看不见，所以单独报一声。
  say('客户端控件根控件数 = %s', tostring(rootCount))
  if rootCount == 0 then
    say('   ⚠ 运行时看不到任何 UI 根控件：请确认那个"客户端控件容器"是加在')
    say('      【界面控件组管理 → 界面布局】里、勾了【初始可见】，且参数配置窗口里玩家应用的就是这个布局')
  end
  if not root then
    root = roots and roots[1] or nil
  end
  if not root then error('找不到挂载控件：脚本要挂在**客户端控件**上（不能挂主屏）') end
  G.root = root
  root:SetActive(true)
  -- ★★ 光标常驻 + CursorEvent 的前置条件（官方 API 文档 §24 ClientUIContainerControl）：
  --     showCursor  boolean 读写 —— "是否显示常驻光标；**CursorEvent 相关方法都需设置该参数为真后
  --     才可正常使用**"。
  --   也就是说：不设它，玩家得**按住 Alt** 才能看见光标（用户实测就是这个），
  --   而且点击/光标事件也可能不生效。设上 = 光标常驻 + 事件正常。
  --   （编辑器里等价开关：容器节点控件 → 功能设置 → 【显示常驻光标】）
  do
    local targets = { root }
    if G.area and G.area ~= root then targets[#targets + 1] = G.area end
    local done = {}
    for i = 1, #targets do
      local c = targets[i]
      local ok, err = pcall(function() c.showCursor = true end)
      if ok then
        done[#done + 1] = tostring(c)
      else
        say('⚠ 设 showCursor 失败（%s）：%s', tostring(c), tostring(err))
      end
    end
    say('★ 已开"显示常驻光标" showCursor=true（%s）—— 不用再按住 Alt', table.concat(done, ' '))
  end
  -- ★ 挂载点（客户端控件容器）自己也要**有尺寸**：它在编辑器里如果是 0×0，
  --   我们挂进去的所有控件都会被裁掉 —— 表现就是"脚本全跑通了、屏幕上什么都没有"。
  --   ⚠ 只设尺寸、**不动位置**：位置由编辑器/布局决定，乱设会让整盘偏移。
  do
    local ok, err = pcall(function() root:SetSizeDelta(w, h) end)
    if G.zoom then say('显示缩放 zoom=%s（等比放大，规则数值未动）', tostring(G.zoom)) end
  say('把挂载点尺寸设成画布尺寸（%s x %s）：%s', tostring(w), tostring(h), ok and 'ok' or ('失败 ' .. tostring(err)))
  end
  say('挂载点 = %s', tostring(root))

  -- ★ 模板索引定下来：填了变量的用变量，没填的**自动认**（见 detectPrefabs 注释）
  local useAuto = param('autoPrefabs', 1) ~= 0
  local auto, probe, built = {}, {}, 0
  if useAuto then
    auto, probe, built = detectPrefabs(root)
    say('自动认模板：球=%s 文本=%s 光标=%s 容器=%s（探测共建出 %s 个控件）',
      tostring(auto.ballPrefab), tostring(auto.hudPrefab),
      tostring(auto.cursorPrefab), tostring(auto.playPrefab), tostring(built))
    for i = 1, #probe do say('   %s', probe[i]) end
    if not (auto.ballPrefab or auto.hudPrefab or auto.cursorPrefab or auto.playPrefab) then
      say('⚠ 两个索引空间都没找到客户端控件模板 —— 这就是屏幕空白的原因')
      say('   ① 模板要"存为模板"：界面控件组库 → 客户端控件模板 → 【添加客户端控件】→ 选类型 → 存为模板')
      say('   ② 实在找不到就把编辑器里点开控件看到的那个大数字（形如 1073741xxx）填进脚本变量：')
      say('      ballPrefab / hudPrefab / cursorPrefab（填了就优先用你填的）')
    end
  end
  G.prefabs = {
    ball = param('ballPrefab', auto.ballPrefab or 1),
    hud = param('hudPrefab', auto.hudPrefab or 2),
    -- 光标必须真的有（类型不对就没有点击事件）；容器没有就用画布默认容器节点
    -- 关掉自动认时，按手册建议的顺序建的话模板③就是光标检测区域 → 兜底成 3
    cursor = param('cursorPrefab', auto.cursorPrefab or (not useAuto and 3 or nil)),
    play = param('playPrefab', auto.playPrefab),
  }
  G.prefabs.shot = param('shotPrefab', G.prefabs.ball)
  say('用这套模板索引：球=%s 弹药=%s 文本=%s 光标=%s 玩区=%s', tostring(G.prefabs.ball), tostring(G.prefabs.shot),
    tostring(G.prefabs.hud), tostring(G.prefabs.cursor), tostring(G.prefabs.play))

  -- ★★ 诊断框**第一个建**：万一后面哪一步炸了，屏幕上还有地方显示原因。
  --   （这一条很关键：我在手机上看不到你的屏幕，那行字就是唯一的线索）
  local dok, dc = pcall(game.InstantiateClientUIControl, G.prefabs.hud, root)
  if dok and dc then
    -- 文本框类型要是不对（比如拿图片模板当 HUD），真机上写 .text / .fontSize 会直接报"字段不存在"
    local ht = typeof and typeof(dc) or nil
    if type(ht) == 'string' and not ht:find('TextBox', 1, true) then
      error('模板 ' .. tostring(G.prefabs.hud) .. ' 是 ' .. ht .. '，不是**文本框控件** —— ' ..
        '分数/提示/球面字母都靠它，请到 界面控件组库 → 客户端控件模板 里建一个文本框并存为模板')
    end
    G.diagControl = dc
    dc:SetActive(true)
    dc:SetAnchoredPosition(0, -h / 2 + 20)
    dc:SetSizeDelta(math.min(w - 40, 760), 30)
    dc.fontSize = 18
    dc.horizontalAlignment = Enum.TextHorizontalAlignment.Left
    dc.verticalAlignment = Enum.TextVerticalAlignment.Middle
    if not G.diag then dc:SetVisible(false) end
    dc.bgColor = Color.FromRGBA(8, 12, 18, 170)     -- 半透明底板，压着字也看得清
  end

  say('诊断框 = %s', tostring(G.diagControl))

  -- 玩区容器：**有就用，没有就直接挂在画布自带的默认容器节点下**（省掉模板④）。
  -- ★ 为什么这样设计：千星奇域里有两个名字很像的"容器"——
  --   ① 客户端控件容器 = 画布本身（服务器控件，必须有，客户端控件靠它显示、脚本靠它挂）
  --   ② 容器节点控件   = 普通控件模板（ClientUIContainerControl），只是我们拿来当"玩区父节点"
  --   ② 完全可以省掉：画布的默认容器节点（game.GetClientUIRoots 返回的那个）就能当父节点。
  local playPrefab = param('playPrefab', auto.playPrefab)
  if playPrefab then
    G.area = game.InstantiateClientUIControl(playPrefab, root)
    if not G.area then
      error('创建玩区容器失败：模板索引 = ' .. tostring(playPrefab) .. '（可以不填 —— 留空就用画布默认容器）')
    end
    G.area:SetActive(true)
    G.area:SetAnchoredPosition(0, 0)
    G.area:SetSizeDelta(w, h)
    -- 如果用户拿图片模板当玩区（省一个模板），它默认是块白图，会把整屏糊住 → 调成全透明
    local at = typeof and typeof(G.area) or nil
    if type(at) == 'string' and not at:find('Container', 1, true) then
      pcall(function() G.area.imageColor = Color.FromRGBA(0, 0, 0, 0) end)
      say('玩区容器用的是 %s（不是容器节点控件）→ 已调成全透明，免得糊住屏幕', tostring(at))
    end
  else
    G.area = root
    say('没建容器节点模板 → 直接用画布的默认容器节点当玩区（少建一个模板）')
  end

  -- 光标检测区域：**必须是"光标检测区域"控件**（类型不对则根本没有 AddCursorEventListener，
  -- 真机上会以"调用 nil"崩掉，而假宿主什么方法都有、本地发现不了 → 这里用 typeof 当场拦下）
  local cursorPrefab = param('cursorPrefab', auto.cursorPrefab)
  if not cursorPrefab then
    error('没找到"光标检测区域"控件模板：请到 界面控件组库 → 客户端控件模板 → 添加客户端控件 → 选"光标检测区域" → 存为模板')
  end
  G.cursorArea = game.InstantiateClientUIControl(cursorPrefab, G.area)
  if not G.cursorArea then
    error('创建光标检测区域失败：模板索引 = ' .. tostring(cursorPrefab) .. '（要建一个"光标检测区域"控件并存为模板）')
  end
  local ct = typeof and typeof(G.cursorArea) or nil
  if type(ct) == 'string' and not ct:find('Cursor', 1, true) then
    error('模板 ' .. tostring(cursorPrefab) .. ' 是 ' .. ct .. '，不是"光标检测区域"控件 —— ' ..
      '类型不对就没有点击事件，必须建一个光标检测区域并存为模板')
  end
  G.cursorArea:SetActive(true)
  G.cursorArea:SetAnchoredPosition(0, 0)
  G.cursorArea:SetSizeDelta(w, h)
  say('玩区 = %s / 光标区 = %s', tostring(G.area), tostring(G.cursorArea))

  -- ★★ 球面素材 id。
  --   真机事实（2026-09-25 用户实测）：**动态创建的图片控件不会继承模板/画布上那张图**，
  --   必须脚本自己 `SetImage(Enum.ImageSource.StaticReference, <资产号>)`，
  --   否则每个图片控件都画成"?"（球、轨道、中央核糖体全中招）。
  --   优先级：art=A:id,U:id,...（按碱基分别指定）> artImage=<id> > 画布里借一张 > 默认值。
  --   ⚠ 注意区分两个数字：**图片控件模板索引**（形如 1073741852）不是素材 id；
  --     素材 id 是编辑器里那张图的"**资产号**"。
  --   ★ 用户在编辑器里的三张图（2026-09-25 报的资产号）：
  --       100002 实心圆 → 球面/光晕/核糖体本体/背板
  --       100001 方块   → 轨道 / 配对连线 / 瞄准线（拉成长条，圆图会鼓出来）
  --       100006 空心圆 → 洞穴那几圈红环（本来就是"环"）
  local DEFAULT_ART = 100002       -- 实心圆
  local DEFAULT_BAR = 100001       -- 方块
  local DEFAULT_RING = 100006      -- 空心圆
  local art = {}
  local artAny = nil          -- 全局兜底资产号（光晕/核糖体/背板等不分碱基的控件用它）
  local artBar = tonumber(tostring(param('artBar', ''))) or DEFAULT_BAR    -- 棒（轨道/连线/瞄准线）
  local artRing = tonumber(tostring(param('artRing', ''))) or DEFAULT_RING -- 环（洞穴）
  do
    local spec = param('art', '')
    if type(spec) == 'string' and spec ~= '' then
      for pair in string.gmatch(spec, '[^,;%s]+') do
        local k, v = string.match(pair, '([AUGC]):(%d+)')
        if k and v then art[k] = tonumber(v) end
      end
    end
    if not next(art) then
      local one = tonumber(tostring(param('artImage', '')))
      if not one then
        local cand = adoptImageId(root)
        for i = 1, #cand do
          say('画布里发现一张配好图的控件：%s（%s）id=%s', cand[i].name, cand[i].t, tostring(cand[i].id))
        end
        if cand[1] then one = tonumber(tostring(cand[1].id)) end
      end
      if not one then
        one = DEFAULT_ART
        say('没在画布里借到图 → 用默认资产号 %s（要换就填 artImage=<资产号>）', tostring(DEFAULT_ART))
      end
      if one then
        artAny = one
        for i = 1, #CFG.BASES do art[CFG.BASES[i]] = one end
        say('★ 球面素材资产号 = %s（全部碱基共用；想分别指定就填 art=A:id,U:id,...）', tostring(one))
      say('★ 素材：实心圆=%s 方块(轨道/连线)=%s 空心圆(洞穴)=%s', tostring(one), tostring(artBar), tostring(artRing))
      end
    end
    if next(art) then
      local parts = {}
      for i = 1, #CFG.BASES do
        local b = CFG.BASES[i]
        if art[b] then parts[#parts + 1] = b .. '=' .. tostring(art[b]) end
      end
      say('球面素材 id：%s', table.concat(parts, ' '))
    else
      say('球面素材：没找到任何可用素材 id → 会画成"?"。请在画布里放一个配好图的图片控件，或填 artImage=<素材id>')
    end
  end

  -- ★★ imgTest=1：画一排"候选素材 id"格子（每格一个图片控件，下面一行小字写编号）。
  --   为什么需要它：真机上**动态创建的图片控件不会继承模板/画布上那张图**，必须脚本用
  --   SetImage(素材id) 指定；而"素材 id"在编辑器里是大数字，抄起来烦。
  --   做法：把 2^30 起的一段候选 id 挨个试一遍，用户**看一眼哪格是白圆图**，报编号即可。
  --   日志里同时打印"编号 -> id"的对应表（1 = 1073741825 …）。
  if param('imgTest', 0) ~= 0 then
    local base = tonumber(tostring(param('imgTestBase', ''))) or 1073741824
    local n = tonumber(tostring(param('imgTestCount', ''))) or 24
    local map = {}
    for i = 1, n do
      local id = base + i
      local x = -w / 2 + 36 + (i - 1) * 66
      local cell = game.InstantiateClientUIControl(G.prefabs.ball, G.area)
      if cell then
        cell:SetActive(true)
        cell:SetVisible(true)
        cell:SetSizeDelta(56, 56)
        cell:SetAnchoredPosition(x, h / 2 - 44)
        local ok = pcall(function() cell:SetImage(Enum.ImageSource.StaticReference, id) end)
        if not ok then say('  imgTest %s：SetImage 报错', tostring(id)) end
        local lab = game.InstantiateClientUIControl(G.prefabs.hud, G.area)
        if lab then
          lab:SetActive(true)
          lab:SetVisible(true)
          lab.text = tostring(i)
          lab.fontSize = 16
          lab.horizontalAlignment = Enum.TextHorizontalAlignment.Middle
          lab:SetSizeDelta(60, 20)
          lab:SetAnchoredPosition(x, h / 2 - 82)
        end
        map[#map + 1] = tostring(i) .. '=' .. tostring(id)
      end
    end
    say('imgTest：上面那排格子的编号对应表 —— %s', table.concat(map, ' '))
    say('imgTest：哪一格是白圆图，就把格子编号（或那个 id）填进 artImage=…')
  end

  G.ui = UI.create({
    parent = G.area,
    canvas = G.canvas,
    art = art,
    artAny = artAny,
    artBar = artBar,
    artRing = artRing,
    cd = tonumber(tostring(param('cd', ''))) or 0,   -- 开火冷却环（本体没有 → 默认关）
    glow = tonumber(tostring(param('glow', ''))),    -- 球的描边/光晕总开关（默认开；0 = 全关）
    ballPrefab = G.prefabs.ball,
    ballCount = param('ballCount', 80),   -- ★ 从球池腾控件给轨道段数（72 段轨道更顺滑）
    shotPrefab = G.prefabs.shot,
    shotCount = param('shotCount', 8),
    -- 连线 / 轨道 / 洞穴都用**球的模板**（拉长就是一根棒、放大就是一个洞）—— 编辑器里不用多建模板
    linkPrefab = param('linkPrefab', G.prefabs.ball),
    linkCount = param('linkCount', param('ballCount', 96) * 2),
    cavePrefab = param('cavePrefab', G.prefabs.ball),
    mergeCount = param('mergeCount', 8),
    -- 三档"美化"开关（真机上哪条炸了就改脚本变量关掉，不用重新打包逻辑）
    fancy = param('fancy', 1),               -- 光晕 / 冷却环 / 动效
    track = param('track', 1),               -- 轨道也由 Lua 画（0 = 用编辑器摆的静态图）
    trackSegments = param('trackSegments', 72),   -- ⚠ 别为了省控件调小：真机轨道会出现接缝（出图看不出来，踩过）
    letters = param('letters', 1),           -- 球面叠碱基字母（0 = 只靠图片素材）
    hudPrefab = G.prefabs.hud,
    hud = buildHudSpecs(w, h, G.teach),
  })

  G.input = INPUT.create({
    area = G.cursorArea,
    keyTarget = root,
    canvas = G.canvas,
  })


  say('控件池：球 %s / 弹药 %s', tostring(#G.ui.balls), tostring(#G.ui.shots))

  -- ★ 诊断行要**画在所有东西上面**（排错的生命线，被压住就等于没有）：
  --   必须在**所有控件都建完之后**再提到最上层 —— 早了会被后建的玩区/HUD 盖回去。
  if G.diagControl and G.diagControl.SetAsLastSibling then
    pcall(function() G.diagControl:SetAsLastSibling() end)
  end

  G.startLevel(param('levelIndex', 1))
  say('关卡 %s 已装配', tostring(G.level and G.level.id or '?'))

  -- ★★ §61 开局进菜单（本体 main.js：G.screen 初值就是 'menu'）。
  --   刚装配好的这一关就**当菜单背景板**用（本体也是这么省的：不另画美术），
  --   菜单态里 tick 不推进盘面，所以它是静止的。
  --   levelIndex 那个脚本变量仍然有效：想**跳过菜单**直接进某一关，就填 levelIndex=8（配 skipMenu=1）。
  G.menuItems = MENU.items(LEVELS_DATA.LEVELS, LEVELS_DATA.TUTORIAL_COUNT or 0)
  G.screen = (param('skipMenu', 0) == 1) and ((param('egg',0)==1) and ((param('eggUnlocked',0)==1) and 'egg' or 'lock') or 'playing') or ((param('egg',0)==1) and ((param('eggUnlocked',0)==1) and 'egg' or 'lock') or 'menu')
  say('开始菜单：%d 个条目（新手关 %d + 核心关 %d）；当前屏幕=%s（skipMenu=1 可跳过菜单）',
    #G.menuItems, tonumber(LEVELS_DATA.TUTORIAL_COUNT) or 0,
    #G.menuItems - (tonumber(LEVELS_DATA.TUTORIAL_COUNT) or 0), tostring(G.screen))

  -- ★ 洞穴状态（回答"洞穴看不到"这类问题：是本体规则、还是位置/图层）
  --   本体 render.js：`if (!(G.sc && G.sc.still)) drawCave(...)` —— **静止关本来就不画洞穴**。
  do
    local still = G.sc and G.sc.still
    local e = (G.sc and G.sc.path) and G.sc.path:pointAt(G.sc.path.length) or nil
    say('洞穴：静止关=%s 可见=%s 位置=%s,%s（静止关按本体规则不画）',
      tostring(still), tostring(not still),
      e and string.format('%.0f', e.x) or '?', e and string.format('%.0f', e.y) or '?')
    if e then
      say('  画布中心=%s,%s 洞穴离中心 %s,%s（画布 %sx%s）',
        string.format('%.0f', w / 2), string.format('%.0f', h / 2),
        string.format('%.0f', e.x - w / 2), string.format('%.0f', e.y - h / 2),
        string.format('%.0f', w), string.format('%.0f', h))
    end
  end

  -- ★★ 碱基抽样（排"打中全变灰 / 球发白"这类问题用）：
  --   若这里打出 nil，说明真机上**碱基没生成出来** → 球会是白的、且每次命中都判"错配"。
  --   若碱基正常而命中仍判错配，那就是"打中的是旁边那颗"（碰撞/瞄准）问题。
  do
    local balls = G.sc and G.sc.chain and G.sc.chain.balls or {}
    local sample = {}
    for i = 1, math.min(#balls, 8) do sample[#sample + 1] = tostring(balls[i].base) end
    say('球碱基抽样（共 %s 颗，前 8）：%s', tostring(#balls), table.concat(sample, ' '))
    local rb = G.sc and G.sc.rb or nil
    if rb and rb.loaded then
      say('核糖体待发碱基：%s / %s', tostring(rb.loaded[1]), tostring(rb.loaded[2]))
    end
    say('本关允许的碱基：%s', table.concat(G.sc and G.sc.bases or {}, ' '))
    -- ★ 待发球自检放到**第一次 UI.sync 之后**（见下面的 ⑨）—— 原来写在这里，
    --   而字母的 .text 是在 UI.sync 里才写进去的 ⇒ 这行**永远报"文字=空"**，
    --   测的不是真状态（用户就是这样被我误导了一轮）。
  end
  return G
end

-- ==================== 关卡 ====================

function G.startLevel(idx)
  local total = #LEVELS_DATA.LEVELS
  if idx < 1 then idx = 1 end
  if idx > total then idx = total end
  G.levelIndex = idx
  G.level = LEVELS_DATA.LEVELS[idx]
  G.sc = BOARD.assembleScene(G.level, G.view, G.seed + idx)
  G.screen = 'playing'
  G.resultTimer = 0
  -- ★ 立刻同步一次：否则换关后的第一帧里，画面上还留着上一关的球
  if G.ui then UI.sync(G.ui, G.sc, G.syncState()) end
  -- ⑨ ★ 待发球自检：**必须在上面这次 sync 之后**（字母的 .text 是 sync 里写的）。
  --   三项一起报，才能分清到底是哪一环：源碱基有没有 → 文字写进去没 → 可见/字号对不对。
  do
    local rb = G.sc and G.sc.rb
    local ui = G.ui
    local names = { '④炮口球', '③预备球' }     -- k=1 是炮口那颗、k=2 是身后那颗（本体 lb(1)/lb(0)）
    for k = 1, 2 do
      local src = rb and rb.loaded and rb.loaded[k]
      local lc = ui and ui.loadedLetter and ui.loadedLetter[k]
      -- ★ 一行里给出**完整对照**：源碱基 → 球颜色 → 控件文字/可见/字号/位置/控件尺寸
      --   缺哪一环一眼可见（源=nil → 球会是白的；文字=空 → 没写进去；可见=false → 被藏了）
      local ballHex = (src == nil) and '（源碱基 nil → 球会被画成白色！）' or '（有源）'
      say('%s：源碱基=%s %s 球半径=%.1f', names[k], tostring(src), ballHex,
        (k == 1) and ((G.sc.mode == 'insert') and G.sc.metrics.R or G.sc.metrics.r)
          or (((G.sc.mode == 'insert') and G.sc.metrics.R or G.sc.metrics.r) * 0.8))
      if lc then
        say('   控件：文字=[%s] 可见=%s 字号=%s 框尺寸=%.1fx%.1f 位置=(%.0f,%.0f)',
          tostring(lc.text), tostring(lc.visible), tostring(lc.fontSize),
          lc.sizeDeltaX or -1, lc.sizeDeltaY or -1,
          lc.anchoredPositionX or -999, lc.anchoredPositionY or -999)
      else
        say('   控件：**不存在**（ui.loadedLetter[%d] = nil，letters 关了？）', k)
      end
    end
  end
  return G.sc
end

-- ==================== 诊断行 ====================

-- ★ 这一行是"远程排错"的生命线：用户把屏幕上这句话念给我，我就知道卡在哪。
--   ⚠ 但出**错**时必须永远显示（那不属于"辅助线"，是救命的）—— 只有"正常状态那行"受 diag 开关控制。
function G.refreshDiag()
  local hc = G.diagControl
  if not hc then return end
  if not G.diag and not G.error then
    -- 没开辅助线、也没出错 → 这一格留空（空文字会被隐藏，屏幕上和本体一致）
    if hc.text ~= '' then hc.text = '' end
    return
  end
  local s
  if G.error then
    s = '!! ' .. G.error
  else
    local balls = G.sc and #G.sc.chain.balls or 0
    local pool = G.ui and #G.ui.balls or 0
    -- 控件总数 = ui 建的 + 脚本自己建的 3 个（诊断框 / 玩区 / 光标区）
    local ctrl = G.ui and (UI.count(G.ui) + 3) or 0
    -- ★ 诊断行里带上**轨道朝向**（出球道在内/在外）：这类"内外"的争论看一眼这行就有结论，
    --   不用再靠猜或互相描述（2026-09-25 为"内外"来回了好几轮，根因就是当时没这个信息）。
    local rail = G.level and G.level.railOrder
    local railTxt = (rail == 'spawn-outer') and '外' or (rail == 'spawn-inner') and '内' or '?'
    s = string.format('帧%d 关%s(出球道在%s) 球%d/%d 控件%d 状态%s', G.frames,
      tostring(G.level and G.level.id or '?'), railTxt, balls, pool, ctrl, G.screen)
  end
  if #s > 240 then s = s:sub(1, 240) end
  if hc.text ~= s then hc.text = s end
end

-- ==================== 每帧 ====================

function G.OnUpdate(dt)
  -- 兜底：万一某些版本不调 OnStart，第一帧补建（此时已不在 OnInit 阶段，控件建得出来）
  if not G.booted then
    say('没等到 OnStart，在 OnUpdate 里补建')
    G.tryBoot()
  end
  G.frames = G.frames + 1
  if G.error then
    G.refreshDiag()
    return
  end
  local ok, err = pcall(G.tick, dt)
  if not ok then
    G.error = tostring(err)
    G.screen = 'error'
  end
  G.refreshDiag()
end

function G.tick(dt)
  if not G.sc then return end

  -- ★★ §61 菜单态：**不推进盘面**（本体 main.js update() 的早期 return）。
  --   否则玩家在菜单里挑关卡时，链子会自己往洞口爬，点进去已经快输了。
  if G.screen == 'menu' then
    -- 只判菜单按钮；点别处什么都不做（尤其**不能发射**）
    if (G.input.pending or 0) > 0 then
      local mx, my = G.input.clickX, G.input.clickY
      INPUT.consume(G.input)
      if mx then
        -- ★ 彩蛋开始按键：菜单右下角那颗「◈ 交易所」（命中公式与 ui.syncEgg 的摆放一致）
        local s = G.sc.metrics.scale
        local ex, ey = G.view.w - 130 * s, G.view.h - 62 * s
        if math.abs(mx - ex) <= 104 * s and math.abs(my - ey) <= 33 * s then
          G.egg = G.egg or require('egg').new(G.levelIndex * 7919 + 13)
          -- ★ 门禁谜题（docs/08）：没解锁过就先过密码锁；解锁过就直接进
          if G.eggUnlocked then
            G.screen = 'egg'
          else
            G.lockInput = G.lockInput or ''
            G.lockTries = G.lockTries or 0
            G.lockRed = false
            G.screen = 'lock'
          end
          UI.sync(G.ui, G.sc, G.syncState(dt))
          return
        end
        local L = MENU.layout(G.view, G.sc.metrics, G.menuItems)
        local item = MENU.pick(L, mx, my)
        if item then
          G.startLevel(item.index + 1)        -- 本体 0 基 / 移植侧 1 基
          return
        end
      end
    end
    UI.sync(G.ui, G.sc, G.syncState(dt))
    return
  end

  -- ★★ 门禁屏（谜题锁，docs/08）：只接受 12 键，不推进任何东西
  if G.screen == 'lock' then
    local EGG = require('egg')
    if (G.input.pending or 0) > 0 then
      local mx, my = G.input.clickX, G.input.clickY
      INPUT.consume(G.input)
      if mx then
        local s = G.sc.metrics.scale
        local bw, bh = 150 * s, 60 * s
        local hit = 0
        for i = 1, 12 do
          local col = (i - 1) % 3
          local row = math.floor((i - 1) / 3)
          local bx = G.view.w * 0.5 + (col - 1) * (bw + 24 * s)
          local by = G.view.h * 0.60 + row * (bh + 16 * s)
          if math.abs(mx - bx) <= bw * 0.5 and math.abs(my - by) <= bh * 0.5 then hit = i end
        end
        local keys = { '1','2','3','4','5','6','7','8','9','clear','0','ok' }
        local k = keys[hit]
        if k == 'clear' then
          G.lockInput = ''
          G.lockRed = false
        elseif k == 'ok' or (k and k ~= 'clear') then
          if k ~= 'ok' then
            if #G.lockInput < 6 then G.lockInput = G.lockInput .. k end
            if #G.lockInput == 6 then k = 'ok' end   -- 输满 6 位自动验
          end
          if k == 'ok' then
            if tonumber(G.lockInput) == EGG.LOCK_CODE then
              G.eggUnlocked = true
              G.screen = 'egg'
            else
              G.lockTries = (G.lockTries or 0) + 1
              G.lockRed = true
              G.lockInput = ''
            end
          end
        end
      end
    end
    UI.sync(G.ui, G.sc, G.syncState(dt))
    return
  end

  -- ★★ 彩蛋屏「璃月黄金交易所」：只跑交易所自己的时间，**不推进盘面**（和菜单同理）
  if G.screen == 'egg' then
    local EGG = require('egg')
    G.egg = G.egg or EGG.new(20260925)
    EGG.tick(G.egg, dt)
    if (G.input.pending or 0) > 0 then
      local mx, my = G.input.clickX, G.input.clickY
      INPUT.consume(G.input)
      if mx then
        local s = G.sc.metrics.scale
        local bw, bh = 190 * s, 62 * s
        local hit = 0
        for i = 1, 9 do
          local col = (i - 1) % 3
          local row = math.floor((i - 1) / 3)
          local bx = G.view.w * 0.5 + (col - 1) * (bw + 26 * s)
          local by = G.view.h * 0.66 + row * (bh + 22 * s)
          if math.abs(mx - bx) <= bw * 0.5 and math.abs(my - by) <= bh * 0.5 then hit = i end
        end
        -- ★ 原奇域的交易逻辑：**比例下单**（花 50% 余额 / 梭哈 / 卖 50% / 全部卖出），不是"买 1g"
        if hit == 1 then EGG.buyPct(G.egg, 0.5)
        elseif hit == 2 then EGG.buyAll(G.egg)
        elseif hit == 3 then EGG.sellPct(G.egg, 0.5)
        elseif hit == 4 then EGG.sellAll(G.egg)
        elseif hit == 5 then EGG.borrowCash(G.egg)
        elseif hit == 6 then EGG.short(G.egg)           -- 借金套现：每回 100g
        elseif hit == 7 then EGG.repayGold(G.egg)       -- 还金：平仓
        elseif hit == 8 then EGG.work(G.egg)
        elseif hit == 9 then G.screen = 'menu' end
      end
    end
    UI.sync(G.ui, G.sc, G.syncState(dt))
    return
  end

  -- 结算画面：只等按键或超时，不再推进盘面
  if G.screen == 'won' or G.screen == 'lost' then
    G.resultTimer = G.resultTimer + dt
    local advance = G.input.wantRestart
    if not advance and G.resultTimer >= ((G.screen == 'won') and G.nextDelay or G.loseDelay) then
      advance = true
    end
    if advance then
      G.input.wantRestart = false
      if G.screen == 'won' and G.autoNext and G.levelIndex < #LEVELS_DATA.LEVELS then
        G.startLevel(G.levelIndex + 1)
      else
        G.startLevel(G.levelIndex)
      end
      return
    end
    UI.sync(G.ui, G.sc, G.syncState(dt))
    return
  end

  if G.input.wantRestart then
    G.input.wantRestart = false
    G.startLevel(G.levelIndex)
    return
  end

  INPUT.update(G.input, G.sc, dt)

  if G.input.wantSwap then
    G.input.wantSwap = false
    RB.swapLoaded(G.sc.rb)
  end
  if G.input.wantMode then
    G.input.wantMode = false
    BOARD.toggleMode(G.sc)
  end

  -- ★ 左下角「回菜单」按钮（本体 §61：手机上没 Esc，这是离开一关的唯一出路）。
  --   判定要在**开火之前**，否则点按钮会顺带打一枪。
  if (G.input.pending or 0) > 0 and G.input.clickX then
    local mb = MENU.playButtonRect(G.view, G.sc.metrics)
    if MENU.hitButton(mb, G.input.clickX, G.input.clickY, 1.3) then
      INPUT.consume(G.input)
      G.screen = 'menu'
      UI.sync(G.ui, G.sc, G.syncState(dt))
      return
    end
  end

  if G.input.firing then
    -- 冷却由 board/RB 管：没冷却好会返回 nil，这时**不要**消费掉意图
    if BOARD.fireShot(G.sc) then INPUT.consume(G.input) end
  end

  BOARD.advanceScene(G.sc, dt)
  UI.sync(G.ui, G.sc, G.syncState(dt))

  if G.sc.won then
    G.screen = 'won'
    G.resultTimer = 0
  elseif G.sc.gameOver then
    G.screen = 'lost'
    G.resultTimer = 0
  end
end

-- 给 ui.sync 的那一小包"表现层才关心的东西"
-- dt：动效要按时间推进；events：board 攒的事件（清段/爆炸/命中），表现层拿去播一次性动效
-- ★★ 教玩家怎么打：手里这颗该打谁。
--   这是本作最容易误解的一点 —— 它是 **RNA 互补配对**（A↔U/T、G↔C），
--   **不是**祖玛那种"同色三消"。真机上用户"打中了却变灰"，九成就是打了同字母的球。
function G.mateText()
  if not G.sc or G.sc.mode ~= 'match' then return '' end
  local rb = G.sc.rb
  local b = rb and rb.loaded and rb.loaded[1]
  if not b then return '' end
  local c = CFG.COMPLEMENT[b] or {}
  if #c == 0 then return '手里 ' .. tostring(b) end
  -- ⚠ 文本框宽度有限（640），太长会被裁掉 —— 规则说明放在关卡提示里，这里只给结论
  return '手里 ' .. tostring(b) .. ' → 打 ' .. table.concat(c, '/') .. ' 的球'
end

-- ★ 优化（2026-09-25）：菜单布局缓存。
--   原来 syncState 每帧都调 MENU.layout（一次分配十几张表）—— 真机 Lua 的 GC 会因此抖动。
--   布局只由这三样决定：画布宽高、scale、条目数。菜单是静止的，这三样不变就不必重算。
--   而且只在**菜单态**才算（syncMenu 只在菜单态读它），游玩时一次都不算。
function G.menuLayoutCached()
  local v, items = G.view, G.menuItems or {}
  local sc = (G.sc and G.sc.metrics and G.sc.metrics.scale) or 1
  local c = G._menuLayout
  if c and c.w == v.w and c.h == v.h and c.scale == sc and c.n == #items then return c end
  local L = MENU.layout(v, (G.sc and G.sc.metrics) or CFG.metrics(sc), items)
  L.w, L.h, L.scale, L.n = v.w, v.h, sc, #items
  G._menuLayout = L
  return L
end

function G.syncState(dt)
  local lines = {}
  if G.level and G.level.hint then
    for i = 1, #G.level.hint do lines[#lines + 1] = G.level.hint[i] end
  end
  if G.error then
    lines = { '出错了：' .. G.error }
  elseif G.screen == 'won' then
    lines = { '过关！（' .. tostring(G.sc.winReason) .. '）  按 R 重来' }
  elseif G.screen == 'lost' then
    lines = { '命数用尽  按 R 重来' }
  end
  -- ★★ 判定诊断：每次命中都打一行「弹丸碱基 vs 目标球碱基 → 配对/错配」。
  --   真机第一次试玩"打中全变灰、也不进三消道"就只能靠这种行定位
  --   （要么碱基是 nil，要么判定反了，要么命中的是旁边那颗）。
  local events = G.sc and BOARD.drainEvents(G.sc) or nil
  if events then
    for i = 1, #events do
      local e = events[i]
      -- 事件的字段（见 board.resolveHit）：base = **弹丸**的碱基，target = **被打中那颗球**的碱基
      if e.type == 'pair' then
        G.lastHit = '上次命中：弹丸 ' .. tostring(e.base) .. ' 打中球 ' .. tostring(e.target) .. ' → 配对 ✅'
        say('%s', G.lastHit)
      elseif e.type == 'mismatch' then
        G.lastHit = '上次命中：弹丸 ' .. tostring(e.base) .. ' 打中球 ' .. tostring(e.target)
          .. ' → 错配 ❌（球变灰、绑定球也是灰的）'
        say('%s', G.lastHit)
      elseif e.type == 'insert' then
        G.lastHit = '上次命中：弹丸 ' .. tostring(e.base) .. ' 并入球 ' .. tostring(e.target) .. '（加球模式）'
        say('%s', G.lastHit)
      end
    end
  end
  return {
    dt = dt,
    events = events,   -- ★ 只有一个消费者：这里取走，别处再取就没了
    mode = G.sc and G.sc.mode or 'match',
    hintLines = lines,
    lastHit = G.lastHit,
    mate = G.mateText and G.mateText() or nil,
    -- ★ 菜单：UI 层要知道"现在是不是菜单态"，以及按钮画在哪（布局在 menu.lua 里算，进对拍）
    screen = G.screen,
    egg = G.egg,
    lock = { input = G.lockInput, tries = G.lockTries, red = G.lockRed },   -- ★ 门禁状态（ui.syncLock 读它）                        -- ★ 彩蛋「璃月黄金交易所」的状态（ui.syncEgg 读它）
    -- ★ 优化（2026-09-25）：菜单布局**只在菜单态才算**，而且算一次就缓存 ——
    --   原来每帧都调 MENU.layout（一次分配十几张表），真机 Lua 的 GC 会因此抖动；
    --   而菜单是**静止**的（菜单态不推进盘面），画布/条目不变就没必要重算。
    --   （syncMenu 只在菜单态用 st.menuLayout，所以游玩时不传也完全没问题）
    menuLayout = (G.screen == 'menu') and G.menuLayoutCached() or nil,
  }
end

function G.OnStart()
  -- 真机上这里是**第一个能建控件**的时机（OnInit 阶段 Instantiate 返回 nil）
  G.tryBoot()
end
function G.OnEnable() end
function G.OnDisable() end
function G.OnLevelUpdate(dt) end   -- OnUpdate 已经不受时停影响，这里不再重复推进
function G.OnDestroy()
  G.sc = nil
  G.ui = nil
  G.input = nil
end

-- 供本地测试/调试用（不改变行为）
function G.info()
  if not G.sc then return { screen = G.screen, error = G.error } end
  local info = BOARD.sceneInfo(G.sc)
  info.screen = G.screen
  info.level = G.level and G.level.id or '?'
  info.mode = G.sc.mode
  info.won = G.sc.won
  info.winReason = G.sc.winReason
  info.gameOver = G.sc.gameOver
  info.error = G.error
  return info
end

return G
end

-- ---------------- egg ----------------
__M["egg"] = function()
--[[
================================================================================
彩蛋：「璃月黄金交易所」（千星奇域玩法致敬 · 隐藏小游戏）

★★ 授权与署名（奇匠与原作者约定的使用条件，**请勿删除**）★★
    本彩蛋的玩法规则来自玩家自制的千星奇域作品《璃月黄金交易所》，
    经原作者授权移植到本项目中，**条件是注明来源**：
        「感谢傻傻白老师对本项目的支持」
    署名同时显示在彩蛋面板上（ui.lua 的 syncEgg）。
================================================================================
来源：奇匠提供的玩家自制千星奇域玩法（模拟金融）。规则**照抄**，一条不改：

  · 报价    每 5s 更新一次，初始 100 元/g
  · 波动    单次 ±20，**近似正态**（开发者说不是纯随机，加了限制与算法）
  · 杠杆    可贷款加杠杆；单次只能借 1 万元，或借 100g 黄金去套现
  · 利息    只要欠款（含亏损/借款）就计息：**30 秒一次、每次 10%**，连本带利滚
            ⇒ 指数增长（"高利贷"）⇒ 利息从总资金里抽走 ⇒ **负和游戏**
  · 借款上限 欠款 ≥ 10 万，或黄金欠 > 1000g ⇒ **不能再借**
  · 做空    后期加入（本模块留了 sellShort 的口子）
  · 打工    耗时 30 秒、**仅欠款时可用**、单次还 20% ⇒ 唯一的**正和**出路

★ 本模块是**纯逻辑**（不建控件、不碰画面）：
  ui/game 侧只要读 st 里的字段就能把它画出来 —— 所以它**不占控件预算**，
  也**不影响对拍**（对拍比的是本体规则；彩蛋是移植侧专属）。

确定性：自带 LCG（不用 rng.lua，避免取到 nil 的老坑），同 seed 同结果 ⇒ 可测。
================================================================================
--]]

local M = {}

M.NAME = '璃月黄金交易所'

-- 规则常量（要调就改这里；注释里是玩法来源）
M.PRICE0      = 100      -- 初始价 元/g
M.TICK_SEC    = 3        -- 报价刷新间隔（奇匠："金价每3秒更新价格一次"）
M.VOL         = 20       -- 单次波动上限 ±20
M.INT_SEC     = 30       -- 利息结算间隔
M.INT_RATE    = 0.10     -- 每次 10%
M.BORROW_CASH = 10000    -- 单次能借 1 万元
M.BORROW_GOLD = 100      -- 或借 100g 黄金（套现）
M.CAP_CASH    = 100000   -- 欠款 ≥ 10 万 ⇒ 不能再借
M.CAP_GOLD    = 1000     -- 黄金欠 > 1000g ⇒ 不能再借
M.WORK_SEC    = 30       -- 打工占 30 秒
M.WORK_REPAY  = 0.20     -- 单次还 20%
M.WORK_PAY    = 3000     -- 打工一次的现金收入（用来还债；可调）

-- 自带线性同余，取值 [0,1)。参数取自 Numerical Recipes。
local function lcgNext(s)
  s = (1103515245 * s + 12345) % 2147483648
  return s, s / 2147483648
end

function M.new(seed)
  local st = {
    seed      = math.floor(seed or 20260925) % 2147483648,
    price     = M.PRICE0,
    cash      = 20000,     -- 本钱
    gold      = 0,         -- 持仓 g
    debtCash  = 0,         -- 欠的钱
    debtGold  = 0,         -- 欠的黄金 g
    tPrice    = 0,         -- 报价计时
    tInt      = 0,         -- 计息计时
    tWork     = 0,         -- 打工剩余时间（>0 表示正在打工）
    workDone  = 0,         -- 打工完成次数
    traded    = 0,         -- 成交次数
    interestPaid = 0,      -- 累计付出的利息（用来点题"负和"）
    lastDelta = 0,
    -- ★ 价格历史给界面画折线图。**开局就放一个初始价** ——
    --   否则第一个点是在第一次报价之后才记的，前两个点同值 ⇒ 画出来是零高度的线，看不见（踩过）。
    hist      = { M.PRICE0 },
    log       = {},
  }
  return st
end

local function note(st, s)
  st.log[#st.log + 1] = s
  if #st.log > 40 then table.remove(st.log, 1) end
end

function M.debtTotal(st)
  return st.debtCash + st.debtGold * st.price      -- 黄金欠款按现价折算
end

function M.netWorth(st)
  return st.cash + st.gold * st.price - M.debtTotal(st)
end

function M.canBorrow(st)
  return st.debtCash < M.CAP_CASH and st.debtGold <= M.CAP_GOLD
end

-- ★ 近似正态：三个均匀数之和（Irwin–Hall），再夹到 ±VOL
function M.rollDelta(st)
  local acc = 0
  for _ = 1, 3 do
    local r
    st.seed, r = lcgNext(st.seed)
    acc = acc + r
  end
  local d = (acc / 3 - 0.5) * 2 * M.VOL     -- 大致落在 ±VOL
  if d > M.VOL then d = M.VOL end
  if d < -M.VOL then d = -M.VOL end
  return d
end

-- 推进时间：报价刷新 / 计息 / 打工完成 / 一局限时
function M.tick(st, dt)
  local ev = {}
  -- ★ 局时倒计时（10 分钟）。时间到 ⇒ 不能再交易（结算画面由界面负责）。
  if not st.ended then
    st.left = (st.left or M.SESSION_SEC) - dt
    if st.left <= 0 then
      st.left = 0
      st.ended = true
      note(st, '时间到，收盘')
      ev[#ev + 1] = { type = 'close' }
    end
  end
  if st.ended then return ev end      -- 收盘后不再刷新报价/计息/打工
  -- 打工
  if st.tWork > 0 then
    st.tWork = st.tWork - dt
    if st.tWork <= 0 then
      st.tWork = 0
      local pay = M.WORK_PAY
      -- 先还债（20%），剩下的进现金
      local repay = M.debtTotal(st) * M.WORK_REPAY
      if repay > pay then repay = pay end
      local left = repay
      local fromCash = math.min(left, st.debtCash)
      st.debtCash = st.debtCash - fromCash
      left = left - fromCash
      if left > 0 then
        local g = left / st.price
        st.debtGold = math.max(0, st.debtGold - g)
      end
      st.cash = st.cash + (pay - repay)
      st.workDone = st.workDone + 1
      note(st, '打工完成，还了 ' .. string.format('%.0f', repay))
      ev[#ev + 1] = { type = 'work', repay = repay }
    end
  end
  -- 计息（只在有欠款时）
  st.tInt = st.tInt + dt
  while st.tInt >= M.INT_SEC do
    st.tInt = st.tInt - M.INT_SEC
    if M.debtTotal(st) > 0 then
      local add = st.debtCash * M.INT_RATE + st.debtGold * M.INT_RATE
      st.debtCash = st.debtCash + st.debtCash * M.INT_RATE
      st.debtGold = st.debtGold + st.debtGold * M.INT_RATE
      st.interestPaid = st.interestPaid + add
      note(st, '利息 +' .. string.format('%.0f', add) .. '（10% / 30s）')
      ev[#ev + 1] = { type = 'interest', add = add }
    end
  end
  -- 报价
  st.tPrice = st.tPrice + dt
  while st.tPrice >= M.TICK_SEC do
    st.tPrice = st.tPrice - M.TICK_SEC
    local d = M.rollDelta(st)
    local np = st.price + d
    if np < 1 then np = 1 end
    st.lastDelta = np - st.price
    st.price = np
    st.priceTick = (st.priceTick or 0) + 1    -- ★ 报价序号：还金要等它变过（借金/还金之间必须隔一次波动）
    -- ★ 价格历史（给界面画折线图用）：只留最近 HISTORY 个点
    st.hist = st.hist or { st.price }
    st.hist[#st.hist + 1] = np
    while #st.hist > M.HISTORY do table.remove(st.hist, 1) end
    note(st, string.format('报价 %.0f（%+.1f）', st.price, st.lastDelta))
    ev[#ev + 1] = { type = 'price', price = st.price, delta = st.lastDelta }
  end
  return ev
end

-- 交易
function M.buy(st, grams)
  grams = grams or 1
  local cost = grams * st.price
  if cost > st.cash then return false, '现金不够' end
  st.cash = st.cash - cost
  st.gold = st.gold + grams
  st.traded = st.traded + 1
  return true
end

function M.sell(st, grams)
  grams = grams or 1
  if grams > st.gold then return false, '没这么多黄金' end
  st.gold = st.gold - grams
  st.cash = st.cash + grams * st.price
  st.traded = st.traded + 1
  return true
end

-- ★ 按比例买卖（**原奇域的逻辑**：花 50% 余额买入 / 梭哈买入 / 卖 50% / 全部卖出）
--   注意：不是"买 1g"那种定量买卖 —— 是**按余额/持仓的比例**下单。
function M.buyPct(st, pct)
  local cash = st.cash * pct
  if cash <= 0 or st.price <= 0 then return false, '没钱可买' end
  return M.buy(st, cash / st.price)
end
function M.buyAll(st) return M.buyPct(st, 1) end

function M.sellPct(st, pct)
  local grams = st.gold * pct
  if grams <= 0 then return false, '没有持仓' end
  return M.sell(st, grams)
end
function M.sellAll(st) return M.sellPct(st, 1) end

-- 借 1 万元
function M.borrowCash(st)
  if not M.canBorrow(st) then return false, '欠款到顶，借不了了' end
  st.cash = st.cash + M.BORROW_CASH
  st.debtCash = st.debtCash + M.BORROW_CASH
  note(st, '借款 ' .. M.BORROW_CASH)
  return true
end

-- 借 100g 黄金并立刻套现
function M.borrowGold(st)
  if not M.canBorrow(st) then return false, '欠款到顶，借不了了' end
  st.debtGold = st.debtGold + M.BORROW_GOLD
  st.cash = st.cash + M.BORROW_GOLD * st.price
  note(st, '借金 ' .. M.BORROW_GOLD .. 'g 套现')
  return true
end

-- ★ 做空（奇匠："做空每回100啊！"）：每按一次借入 100g 黄金并立刻按现价卖掉
--   ⇒ 手上多一笔现金、同时欠 100g 黄金 ⇒ 金价跌了就赚、涨了就亏。
-- ★ 借金套现（奇匠术语："借金" = 借金套现）：借入 100g 黄金并**立刻按现价卖掉**
--   ⇒ 手上多一笔现金、同时欠 100g 黄金。金价跌了赚、涨了亏。
--   ⚠ 一次一档价：同一档报价里借的，**必须等到下一次报价刷新**才能还金（见下）。
M.SHORT_GOLD = 100
-- ★ 一局 10 分钟（原奇域的限时）。报价 3 秒一档 ⇒ 一局大约 **200 个价格点**。
--   界面不画 200 段折线（控件不够，也不好看），而是**聚合成 40 根 K 线柱**（每根 5 档）：
--   柱高 = 这 5 档里的最高/最低，色 = 收在开盘之上红、之下绿 —— 这才是"现实里的 K 线"观感。
M.SESSION_SEC = 600      -- 一局多久（10 分钟）
-- ★★ 门禁密码（谜题答案）：
--   原奇域《璃月黄金交易所》那张**亏损榜**十个人的数**加起来、四舍五入取整、去负号**：
--     CocaKlee -136692.77 / 有可言遇 -114347.34 / 晓月之星 -111297.93 / 屑旅行人 -92331.79 /
--     ✧白星簌雪✧ -56715.82 / 欧若洛樱 -33180.86 / 哈基喵 -22676.93 / 诸葛茗云 -16977.06 /
--     凝銘 -12297.19 / 天使的糖豆 -2981.4
--   合计 -599499.09 ⇒ 取整 **599499** ✓
--   ⚠ 那个榜是"活的"（玩家还在继续亏）⇒ 数字会漂。要跟着改，**只改这一个常量**。
--     （门禁读不到那个榜 —— 脚本没有跨奇域/联网能力，只能验固定值。）
M.LOCK_CODE = 599499
M.HISTORY    = 200       -- 保留多少个报价点（10 分钟 ÷ 3 秒 ≈ 200）
function M.short(st)
  if not M.canBorrow(st) then return false, '欠款到顶，借不了金' end
  st.debtGold = st.debtGold + M.SHORT_GOLD
  st.cash = st.cash + M.SHORT_GOLD * st.price
  st.traded = st.traded + 1
  st.shortPrice = st.price          -- ★ 记下借金套现那一档的价格
  st.shortTick = st.priceTick or 0  -- ★ 以及那一档的报价序号
  note(st, '借金套现 ' .. M.SHORT_GOLD .. 'g @ ' .. string.format('%.1f', st.price)
    .. '（欠金 ' .. string.format('%.0f', st.debtGold) .. 'g）')
  return true
end

-- ★ 还金（借金套现的**平仓**）：按**现价**把欠的黄金折成现金还掉（等量黄金价值的现金）。
--   ⚠ 奇匠纠正过：**不需要等波动** —— 玩家完全可以"借完秒还" ✓。
--   我一度加了"必须等下一次报价"的硬约束，那是**错的** ✗（已撤）。
--   秒还的后果天然合理：同一档价借了立刻还 ⇒ 现金原地打转、不赚不赔 ⇒ 想赚就得自己等波动 ✓，
--   这个"等"是玩家自己的选择，不该由系统锁死 ✓。
M.REPAY_GOLD = 100
function M.repayGold(st)
  if (st.debtGold or 0) <= 0 then return false, '没有金欠要还' end
  local grams = math.min(M.REPAY_GOLD, st.debtGold)
  local cost = grams * st.price          -- 等量黄金价值 = 克数 × 现价
  if cost > st.cash then return false, '现金不够还这一笔' end
  st.cash = st.cash - cost
  st.debtGold = st.debtGold - grams
  st.traded = st.traded + 1
  note(st, '还金 ' .. string.format('%.0f', grams) .. 'g @ ' .. string.format('%.1f', st.price)
    .. '（付现金 ' .. string.format('%.0f', cost) .. '）')
  return true
end

-- 打工：30 秒、仅欠款时可用
function M.work(st)
  if M.debtTotal(st) <= 0 then return false, '不欠钱，不用打工' end
  if st.tWork > 0 then return false, '正在打工' end
  st.tWork = M.WORK_SEC
  note(st, '开始打工（30s）')
  return true
end

return M
end

-- ---------------- menu ----------------
__M["menu"] = function()
-- 开始菜单（DESIGN.md §61）—— src/config.js 的 menuItems / menuLayout / menuButtonRect 的 Lua 移植。
--
-- 为什么单独一个模块：这三样是**纯计算**（条目表、按钮矩形、命中判定），
--   JS 侧和 Lua 侧必须一模一样 —— 所以它们进对拍（parity）当证据，而不是"看着差不多"。
--   ★ 与本体一一对应：
--     menuItems      = main.js  rebuild() 里那段 ALL_LEVELS.map(...)
--     menuLayout     = config.js  menuLayout(view, mt, items)
--     menuButtonRect = config.js  menuButtonRect(view, mt)   （局内左下角"菜单"按钮）

local CFG = require('config')

local M = {}

-- 菜单条目：**优先读关卡自己的 group**（经典祖玛那组就是这么来的）；
-- 没写的仍按老规矩分：新手关（前 tutorialCount 个）/ 核心关 —— 现有 10 关的显示一个字不变。
-- （和本体 main.js 的 menuItems 一一对应，进对拍）
function M.items(levels, tutorialCount)
  local out = {}
  for i = 1, #levels do
    local l = levels[i]
    local tut = i <= (tutorialCount or 0)
    local label
    if l.group then
      label = l.name or l.short
    elseif tut then
      label = l.name or l.short
    else
      label = tostring(i) .. ' ' .. (l.short or l.name)
    end
    out[i] = {
      index = i - 1,                       -- 本体是 0 基；这里保留 0 基，方便和本体逐值对拍
      group = l.group or (tut and '新手关' or '核心关'),
      label = label,
    }
  end
  return out
end

-- 菜单布局：竖屏（窄）2 列、横屏/桌面 4 列（本体 config.js 原文，逐式照搬）
--   view: { w, h, cx, cy }   mt: { scale }
function M.layout(view, mt, items)
  local s = (mt and mt.scale) or 1
  local W, H = view.w, view.h
  local narrow = W < 640
  local cols = narrow and 2 or 4
  local pad = math.max(10, 18 * s)
  local gapX, gapY = 9 * s, 8 * s
  local innerW = math.min(W - pad * 2, narrow and (440 * s) or (760 * s))
  local x0 = (W - innerW) / 2
  local bh = math.max(36, 50 * s)
  local bw = (innerW - gapX * (cols - 1)) / cols
  local buttons, groups = {}, {}
  local y = math.max(76 * s, H * 0.26)
  local col, last = 0, nil
  for i = 1, #items do
    local it = items[i]
    if it.group ~= last then
      if last ~= nil then y = y + bh + gapY + 24 * s end   -- 换组：留出组标题的位置
      groups[#groups + 1] = { name = it.group, y = y }
      y = y + 20 * s
      col = 0
      last = it.group
    end
    buttons[#buttons + 1] = {
      x = x0 + col * (bw + gapX), y = y, w = bw, h = bh, item = it, index = i - 1,
    }
    col = col + 1
    if col >= cols then col = 0; y = y + bh + gapY end
  end
  return {
    x0 = x0, innerW = innerW, cols = cols, bw = bw, bh = bh,
    buttons = buttons, groups = groups,
    titleY = math.max(40 * s, H * 0.14),
    footerY = H - math.max(22 * s, 30 * s),
  }
end

-- 命中的是哪个条目（本体 main.js onPointerDown 里那段矩形判定）
--   返回 item（含 index），点空处返回 nil
function M.pick(layout, x, y)
  for i = 1, #layout.buttons do
    local b = layout.buttons[i]
    if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
      return b.item
    end
  end
  return nil
end

-- 局内左下角「回菜单」按钮（本体 config.js menuButtonRect）
function M.playButtonRect(view, mt)
  local s = (mt and mt.scale) or 1
  -- ★ 与本体 config.js 的 menuButtonRect 同步（对拍基准）：r 22→30、pad 26→44
  local r = 30 * s
  local pad = 44 * s
  return { x = r + pad, y = view.h - r - pad, r = r }
end

-- 点是否落在按钮的判定圈里（本体用 r*1.3 的宽松判定：手指友好）
function M.hitButton(btn, x, y, k)
  k = k or 1.3
  local dx, dy = x - btn.x, y - btn.y
  return (dx * dx + dy * dy) <= (btn.r * k) * (btn.r * k)
end

return M
end

-- ---------------- 对外门面 ----------------
-- 字段名与 lua/src 的文件名一致。
ZUMA = {
  rng = __require("rng"),
  config = __require("config"),
  elements = __require("elements"),
  geometry = __require("geometry"),
  spines = __require("spines"),
  chain = __require("chain"),
  run = __require("run"),
  projectile = __require("projectile"),
  ribosome = __require("ribosome"),
  board = __require("board"),
  levels_data = __require("levels_data"),
  ui = __require("ui"),
  input = __require("input"),
  game = __require("game"),
  egg = __require("egg"),
  menu = __require("menu"),
}

-- ★ 把生命周期回调暴露成**全局**：运行时是按固定名字查找的。
--   这些函数内部引用的是模块级的 G，不依赖 self，所以裸调用完全等价。
local __LIFECYCLE_NAMES = {
  "OnInit", "OnStart", "OnEnable", "OnDisable", "OnUpdate", "OnLevelUpdate", "OnDestroy"
}
for i = 1, #__LIFECYCLE_NAMES do
  local __n = __LIFECYCLE_NAMES[i]
  local __f = ZUMA.game[__n]
  if type(__f) == "function" then _G[__n] = __f end
end

return ZUMA
