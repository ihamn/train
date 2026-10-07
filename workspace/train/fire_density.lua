--[[ fire_density.lua —— 像素密度验证探针（只在模拟器里跑，不影响已部署的 fire_v54）

  目的：回答"提高像素密度还能不能改进、代价多少"。
  与 fire_v54 唯一区别：① 顶部参数集中在 DENSITY 表里（便于逐档替换）② 加 os.clock 计时 +
  一行 `TR density …` 汇总（行数 / 每行最长字符 / 每帧耗时）。

  量什么：
    · rowsBuilt    = 实际建成的行数（= 控件数，受预算与实例化是否成功影响）
    · rowStep      = floor(FONT × SIZE_K × ROW_K)（行距，我们唯一要控的东西）
    · maxRowLen    = 整段运行中，单行富文本串的最大长度（**文本长度上限 ~1500** ⇒ 这是密度的硬约束）
    · ms/update    = 每帧重算+脏检查的平均耗时（20fps ⇒ 预算 50ms/帧）
=========================================================================== ]]

local PRE_TEXT = 1073741850

-- ★ 密度参数（逐档替换的就是这里）
local DENSITY = {
  name = "base16x27",
  COLS = 16,
  ROWS = 27,
  FONT = 20,
  SIZE_K = 1.10,
  ROW_K = 0.955,
}

local COLS, ROWS = DENSITY.COLS, DENSITY.ROWS
local SOURCE_ROWS, DECAY_MAX, EXPONENT, NLEV = 3, 3, 0.9, 25
local LEVELS = 6
local FONT, SIZE_K, ROW_K = DENSITY.FONT, DENSITY.SIZE_K, DENSITY.ROW_K
local STEP_TICKS = 3
local ROWS_PER_TICK = 4
local MAX_TICKS = 300            -- 10 秒模拟时间就够量（100 次更新）

local PAL = {
  {  7,  7, 15 }, { 26, 10, 10 }, { 60, 12, 10 }, {100, 15, 12 }, {140, 20, 12 },
  {176, 28, 12 }, {206, 40, 12 }, {226, 58, 12 }, {238, 78, 14 }, {246,100, 16 },
  {250,120, 18 }, {252,140, 22 }, {254,158, 26 }, {255,172, 34 }, {255,186, 48 },
  {255,198, 66 }, {255,208, 86 }, {255,216,108 }, {255,224,132 }, {255,232,158 },
  {255,240,190 }, {255,246,215 }, {255,250,235 }, {255,253,248 }, {255,255,255 },
}
local QPAL = { PAL[3], PAL[7], PAL[11], PAL[15], PAL[20], PAL[25] }
-- 预生成颜色标签（避免每帧 string.format：密网格里这是主要开销）
local TAG = {}
for i = 1, #QPAL do
  local p = QPAL[i]
  TAG[i] = string.format("<color=#%02X%02X%02X>", p[1], p[2], p[3])
end
local TAG_CLEAR = "<color=#00000000>"
local TAG_CLOSE = "</color>"
local TAG_SIZE_OPEN = "<size=" .. math.floor(FONT * SIZE_K) .. ">"
local TAG_SIZE_CLOSE = "</size>"

local host, W, H = nil, 1680, 900
local tick, builds, fails, alive, updates = 0, 0, 0, true, 0
local rows, heat, lastS = {}, {}, {}
local bw, bh, rowStep = 0, 0, 0
local baseX0, baseY0, buildNext, said_built = 0, 0, 0, false
local maxRowLen, msSum, msMax = 0, 0, 0
local dirtyRow, rebuiltSum = {}, 0    -- 只重算"变过的行"（火焰上部多数行每步都不变）

local function say(s) if print then pcall(print, "TR " .. s) end end
local function t(fn) local ok = pcall(fn); if not ok then fails = fails + 1 end; return ok end
local function rgb(r, g, b)
  local ok, v = pcall(function() return Color.FromRGBA(r, g, b, 255) end)
  if ok then return v end
  return nil
end
local function point_anchor(c)
  t(function() c.anchorMinX = 0 end)
  t(function() c.anchorMinY = 0 end)
  t(function() c.anchorMaxX = 0 end)
  t(function() c.anchorMaxY = 0 end)
  t(function() c.pivotX = 0 end)
  t(function() c.pivotY = 0 end)
end

local rseed = 20261017
local function rnd(n)
  rseed = (rseed * 1103515245 + 12345) % 2147483648
  return rseed % n
end
local halfPx, ccx = math.floor(COLS / 2), (COLS - 1) / 2
local function halfAt(r)
  local tt = (ROWS - r) / math.max(1, ROWS - 1)
  local h = halfPx * ((1 - tt) ^ EXPONENT)
  if h < 0.5 then h = 0.5 end
  return h
end
local function allowed(c, r) return math.abs(c - ccx) <= halfAt(r) end
local function idx(r, c) return r * COLS + c + 1 end

local function seedFire()
  for r = ROWS - SOURCE_ROWS, ROWS - 1 do
    for c = 0, COLS - 1 do
      if allowed(c, r) then heat[idx(r, c)] = NLEV end
    end
    dirtyRow[r] = true
  end
end

local function stepFire()
  seedFire()
  for r = ROWS - 1, 1, -1 do
    local up = r - 1
    for c = 0, COLS - 1 do
      local v = heat[idx(r, c)]
      if v <= 1 then
        if heat[idx(up, c)] ~= 1 then heat[idx(up, c)] = 1; dirtyRow[up] = true end
      else
        local d = rnd(DECAY_MAX + 1)
        local nx = c + rnd(3) - 1
        if nx < 0 then nx = 0 elseif nx >= COLS then nx = COLS - 1 end
        if not allowed(nx, up) then
          if heat[idx(up, nx)] ~= 1 then heat[idx(up, nx)] = 1; dirtyRow[up] = true end
        else
          local nv = v - d
          if nv < 1 then nv = 1 end
          if heat[idx(up, nx)] ~= nv then heat[idx(up, nx)] = nv; dirtyRow[up] = true end
        end
      end
    end
  end
end

local function qlevel(v)
  if v <= 1 then return 0 end
  local q = math.floor((v - 1) / NLEV * LEVELS) + 1
  if q < 1 then q = 1 elseif q > LEVELS then q = LEVELS end
  return q
end

local function build_row(r)
  local parts, open, n = {}, false, 0
  local curQ = -1
  for c = 0, COLS - 1 do
    local q = qlevel(heat[idx(r, c)] or 1)
    if q ~= curQ then
      if open then n = n + 1; parts[n] = TAG_CLOSE end
      if q == 0 then n = n + 1; parts[n] = TAG_CLEAR
      else n = n + 1; parts[n] = TAG[q] or TAG[1] end
      open, curQ = true, q
    end
    n = n + 1
    parts[n] = "█"
  end
  if open then n = n + 1; parts[n] = TAG_CLOSE end
  return TAG_SIZE_OPEN .. table.concat(parts) .. TAG_SIZE_CLOSE
end

local function mk_row(r, ox, oy)
  local ok, c = pcall(game.InstantiateClientUIControl, PRE_TEXT, host)
  if not ok or c == nil then alive = false; return nil end
  builds = builds + 1
  point_anchor(c)
  t(function() c.name = "FROW" .. r end)
  t(function() c:SetSizeDelta(bw, bh) end)
  t(function() c:SetAnchoredPosition(ox, oy) end)
  t(function() c.fontSize = FONT end)
  local fc = rgb(255, 255, 255)
  if fc ~= nil then t(function() c.fontColor = fc end) end
  t(function() c.horizontalAlignment = Enum.TextHorizontalAlignment.Left end)
  t(function() c.verticalAlignment = Enum.TextVerticalAlignment.Top end)
  t(function() c:SetActive(true) end)
  t(function() c:SetVisible(true) end)
  return c
end

function OnInit()
  say("boot density=" .. DENSITY.name .. " cols=" .. COLS .. " rows=" .. ROWS
    .. " font=" .. FONT .. " sizeK=" .. SIZE_K .. " rowK=" .. ROW_K)
  t(function() script:EnableUpdate(true) end)
end

function OnStart()
  host = script.object
  if host == nil then say("no host"); alive = false; return end
  local ok, cw, ch = pcall(game.GetUICanvasSize)
  if ok and type(cw) == "number" and type(ch) == "number" then W, H = cw, ch end

  for i = 1, COLS * ROWS do heat[i] = 1 end
  seedFire()
  for i = 1, 30 do stepFire() end

  bw = math.floor(COLS * FONT * SIZE_K) + 20
  bh = math.floor(FONT * SIZE_K * 2) + 8
  rowStep = math.floor(FONT * SIZE_K * ROW_K)
  local totalH = (ROWS - 1) * rowStep + bh
  baseX0 = math.floor(W * 0.5 - bw * 0.5)
  baseY0 = math.floor(H * 0.5 - totalH * 0.5)
  say("canvas=" .. W .. "x" .. H .. " rowStep=" .. rowStep
    .. " boxWxH=" .. bw .. "x" .. bh .. " fireH=" .. totalH)
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1
  if tick > MAX_TICKS then
    local avg = 0
    if updates > 0 then avg = msSum / updates end
    say("density=" .. DENSITY.name .. " cols=" .. COLS .. " rows=" .. ROWS
      .. " font=" .. FONT .. " built=" .. builds .. " rowStep=" .. rowStep
      .. " maxRowLen=" .. maxRowLen .. " ms/update=" .. string.format("%.2f", avg * 1000)
      .. " msMax=" .. string.format("%.2f", msMax * 1000)
      .. " rebuilt/update=" .. string.format("%.1f", rebuiltSum / math.max(1, updates))
      .. " updates=" .. updates .. " fails=" .. fails)
    t(function() script:EnableUpdate(false) end)
    alive = false
    return
  end
  if dt == nil or dt <= 0 then return end

  if buildNext < ROWS then
    for k = 1, ROWS_PER_TICK do
      local r = buildNext
      if r < ROWS then
        local oy = baseY0 + (ROWS - 1 - r) * rowStep
        local c = mk_row(r, baseX0, oy)
        rows[r + 1] = c
        local s = build_row(r)
        lastS[r + 1] = s
        if c ~= nil then t(function() c.text = s end) end
        buildNext = buildNext + 1
      end
    end
    if buildNext >= ROWS and not said_built then
      said_built = true
      say("rowsBuilt=" .. builds)
    end
    return
  end

  if tick % STEP_TICKS ~= 0 then return end
  updates = updates + 1

  local t0 = nil
  local okc, vc = pcall(function() return os.clock() end)
  if okc then t0 = vc end

  stepFire()
  local wrote, rebuilt = 0, 0
  for r = 0, ROWS - 1 do
    -- ★ 只重算"这一步真的变过"的行（其余行的串必然与上次相同）
    if dirtyRow[r] then
      dirtyRow[r] = false
      rebuilt = rebuilt + 1
      local s = build_row(r)
      if #s > maxRowLen then maxRowLen = #s end
      if s ~= lastS[r + 1] and rows[r + 1] ~= nil then
        if t(function() rows[r + 1].text = s end) then
          lastS[r + 1] = s
          wrote = wrote + 1
        end
      end
    end
  end
  rebuiltSum = rebuiltSum + rebuilt

  if t0 ~= nil then
    local okc2, vc2 = pcall(function() return os.clock() end)
    if okc2 and type(vc2) == "number" then
      local d = vc2 - t0
      if d < 0 then d = 0 end
      msSum = msSum + d
      if d > msMax then msMax = d end
    end
  end

  if updates == 1 or updates % 100 == 0 then
    say("u=" .. updates .. " wrote=" .. wrote .. " maxRowLen=" .. maxRowLen)
  end
end
