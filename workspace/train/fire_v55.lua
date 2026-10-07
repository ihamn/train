--[[ fire_v55.lua —— 像素火「高密度 + 无缝」版（B 档）

  像素问题的两半，本版同时用上：
    ① **列缝**：用 `<size>` 把字墨放大 SIZE_K 倍（v41 的机制）⇒ 相邻列的墨迹相接 ✓
    ② **行距**：一行一个文本框（v54 的结构）⇒ 行距 = ROW_STEP = floor(FONT×SIZE_K×ROW_K) ✓
       （每框只有 1 行 ⇒ 引擎行距无从作祟 ⇒ ①的副作用伤不到我们）

  密度提升（B 档，模拟器实测见 tools/check_fire_density.py）：
    格数 16×27 = 432  →  **32×54 = 1728**（4 倍）
    FONT 20 → 10（同屏物理尺寸下格子变小 ⇒ 密度翻倍），SIZE_K 1.10 → 1.20（小字号要多放大一点才接得上）
    rowStep = floor(10 × 1.20 × 0.955) = 11 ；控件数 = 行数 = 54（远低于 300 的建议预算）

  性能纪律（都来自实测教训）：
    · **只重算变过的行**（脏行标记）—— 实测把 20fps 下的耗时降了 20~40%
    · 预生成颜色标签（不每帧 string.format）
    · 分帧建（每帧 4 行，54 行 ⇒ 14 帧建完）⇒ 避开"启动期爆发"
    · 日志有界：boot / 结构几行 / 每 300 次更新一行汇总（带 ms 与重写行数）/ stop
    · 看门狗 3000 tick（≈100 秒）自毁；`os.clock()` 量真实耗时（真机原生 Lua 比模拟器快得多，
      这行汇总就是给**真机**看的：ms/update 若很小 ⇒ 高密度留得住）
=========================================================================== ]]

local PRE_TEXT = 1073741850      -- 文本框模板（新关卡 1073741826 实测；旧关卡是 1073741851）

-- ★ B 档参数（要改密度就改这四行）
local COLS, ROWS = 32, 54
local FONT = 10
local SIZE_K = 1.20
local ROW_K = 0.955

local SOURCE_ROWS, DECAY_MAX, EXPONENT, NLEV = 3, 3, 0.9, 25
local LEVELS = 6
local STEP_TICKS = 3             -- 20fps
local ROWS_PER_TICK = 4          -- 分帧建
local MAX_TICKS = 3000           -- 看门狗 ≈100 秒
local SUMMARY_EVERY = 300        -- 每 300 次更新打一行汇总（含 ms）

local PAL = {
  {  7,  7, 15 }, { 26, 10, 10 }, { 60, 12, 10 }, {100, 15, 12 }, {140, 20, 12 },
  {176, 28, 12 }, {206, 40, 12 }, {226, 58, 12 }, {238, 78, 14 }, {246,100, 16 },
  {250,120, 18 }, {252,140, 22 }, {254,158, 26 }, {255,172, 34 }, {255,186, 48 },
  {255,198, 66 }, {255,208, 86 }, {255,216,108 }, {255,224,132 }, {255,232,158 },
  {255,240,190 }, {255,246,215 }, {255,250,235 }, {255,253,248 }, {255,255,255 },
}
local QPAL = { PAL[3], PAL[7], PAL[11], PAL[15], PAL[20], PAL[25] }
local TAG = {}
for i = 1, #QPAL do
  local p = QPAL[i]
  TAG[i] = string.format("<color=#%02X%02X%02X>", p[1], p[2], p[3])
end
local TAG_CLEAR, TAG_CLOSE = "<color=#00000000>", "</color>"
local TAG_SIZE_OPEN = "<size=" .. math.floor(FONT * SIZE_K) .. ">"
local TAG_SIZE_CLOSE = "</size>"

local host, W, H = nil, 1680, 900
local tick, builds, fails, alive, updates = 0, 0, 0, true, 0
local rows, heat, lastS, dirtyRow = {}, {}, {}, {}
local bw, bh, rowStep = 0, 0, 0
local baseX0, baseY0, buildNext, said_built = 0, 0, 0, false
local maxRowLen, msSum, msMax, rebuiltSum, wroteSum = 0, 0, 0, 0, 0

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

local function report(final)
  local avg = 0
  if updates > 0 then avg = msSum / updates end
  say("density=v55_B" .. (final and " FINAL" or "")
    .. " cols=" .. COLS .. " rows=" .. ROWS .. " font=" .. FONT
    .. " built=" .. builds .. " rowStep=" .. rowStep .. " maxRowLen=" .. maxRowLen
    .. " ms/update=" .. string.format("%.2f", avg * 1000)
    .. " msMax=" .. string.format("%.2f", msMax * 1000)
    .. " rebuilt/update=" .. string.format("%.1f", rebuiltSum / math.max(1, updates))
    .. " wrote/update=" .. string.format("%.1f", wroteSum / math.max(1, updates))
    .. " updates=" .. updates .. " fails=" .. fails)
end

function OnInit()
  say("boot fire_v55 densB cols=" .. COLS .. " rows=" .. ROWS .. " font=" .. FONT
    .. " sizeK=" .. SIZE_K .. " rowK=" .. ROW_K)
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
    .. " boxWxH=" .. bw .. "x" .. bh .. " fireH=" .. totalH .. " (building rows over frames)")
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1
  if tick > MAX_TICKS then
    report(true)
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
      say("rowsBuilt=" .. builds .. " rowStep=" .. rowStep .. " fails=" .. fails)
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
  wroteSum = wroteSum + wrote

  if t0 ~= nil then
    local okc2, vc2 = pcall(function() return os.clock() end)
    if okc2 and type(vc2) == "number" then
      local d = vc2 - t0
      if d < 0 then d = 0 end
      msSum = msSum + d
      if d > msMax then msMax = d end
    end
  end

  -- 日志纪律：整段运行只报 2 行汇总（第 100、300 次更新），其余静默
  if updates == 100 or updates == 300 then
    report(false)
  end
end
