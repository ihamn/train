--[[ fire_v54.lua —— 以 v41（好基线）为准，只改"行距"这一处

  ── 为什么回到 v41 ───────────────────────────────────────────────
  v41 的两个关键机制后来被删掉了，这才是画面变坏的原因：
    · SIZE_K = 1.10：用 <size> 把**字墨放大 10%** ⇒ 闭合**列**缝（v52 改成 1.00 ⇒ 列缝回来了）
    · 带间距系数 0.955（配 SIZE_K 用）⇒ 行与行贴合
    · v52/v53 改成 FONT=44 / SIZE_K=1.00 / 系数 0.90 ⇒ 机制没了，只能靠猜
  另外 v41 里有 `cands` 彩条测试块（所以 `#cands` 有定义）；后来删了彩条却**留着**
  `say('glyph candidates = ' .. tostring(#cands))` ⇒ 真机必报运行期错误 ✗（本次一并修掉）

  ── 本版唯一的结构改动：行 = 一个文本框 ──────────────────────────
  v41 把 27 行塞进 3 个文本框（每框 9 行，\n 换行）⇒ **框内行距由引擎定、框间靠系数猜** ✗
  本版 **一行一个文本框（27 个）** ⇒ 行距 = ROW_STEP = floor(FONT × SIZE_K × ROW_K)，一个数可控 ✓
  而且每框只有 1 行 ⇒ 引擎行距无从作祟 ⇒ **可以放心保留 v41 的 <size> 列缝闭合机制** ✓

  ── 其余照抄 v41 的已验证取值 ────────────────────────────────────
  FONT=20、SIZE_K=1.10、ROW_K=0.955（v41 的间距系数）、PAL/QPAL、火焰算法、20fps、
  脏检查（串变了才写）、看门狗、锚点/轴心用**字段**写。
  新增：分帧建（每帧 4 行，避免"启动期爆发"）、日志总量有界。
=========================================================================== ]]

local PRE_TEXT = 1073741850      -- 文本框模板（新关卡 1073741826 实测；旧关卡是 1073741851）

local COLS, ROWS = 16, 27
local SOURCE_ROWS, DECAY_MAX, EXPONENT, NLEV = 3, 3, 0.9, 25
local LEVELS = 6
local FONT = 20                  -- v41 的值（好基线；不要为了"填满格子"乱加字号）
local SIZE_K = 1.10              -- v41：<size> 放大字墨 ⇒ 闭合**列**缝（每框只 1 行 ⇒ 不再有行距副作用 ✓）
local ROW_K = 0.955              -- v41 的间距系数；本版直接作用到每一行 ⇒ 行距唯一的旋钮
local STEP_TICKS = 3             -- 20fps
local ROWS_PER_TICK = 4          -- 分帧建（27 行 ⇒ 7 帧建完）
local MAX_TICKS = 3000           -- 看门狗

local PAL = {
  {  7,  7, 15 }, { 26, 10, 10 }, { 60, 12, 10 }, {100, 15, 12 }, {140, 20, 12 },
  {176, 28, 12 }, {206, 40, 12 }, {226, 58, 12 }, {238, 78, 14 }, {246,100, 16 },
  {250,120, 18 }, {252,140, 22 }, {254,158, 26 }, {255,172, 34 }, {255,186, 48 },
  {255,198, 66 }, {255,208, 86 }, {255,216,108 }, {255,224,132 }, {255,232,158 },
  {255,240,190 }, {255,246,215 }, {255,250,235 }, {255,253,248 }, {255,255,255 },
}
local QPAL = { PAL[3], PAL[7], PAL[11], PAL[15], PAL[20], PAL[25] }

local host, W, H = nil, 1680, 900
local tick, builds, fails, alive, updates = 0, 0, 0, true, 0
local rows, heat, lastS = {}, {}, {}
local bw, bh, rowStep = 0, 0, 0
local baseX0, baseY0, buildNext, said_built = 0, 0, 0, false

local function say(s) if print then pcall(print, "TR " .. s) end end
local function t(fn) local ok = pcall(fn); if not ok then fails = fails + 1 end; return ok end
local function rgb(r, g, b)
  local ok, v = pcall(function() return Color.FromRGBA(r, g, b, 255) end)
  if ok then return v end
  return nil
end
-- 锚点/轴心是**字段**（方法 SetAnchorMin/SetPivot 在真机不存在）
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
  end
end

local function stepFire()
  seedFire()
  for r = ROWS - 1, 1, -1 do
    local up = r - 1
    for c = 0, COLS - 1 do
      local v = heat[idx(r, c)]
      if v <= 1 then
        heat[idx(up, c)] = 1
      else
        local d = rnd(DECAY_MAX + 1)
        local nx = c + rnd(3) - 1
        if nx < 0 then nx = 0 elseif nx >= COLS then nx = COLS - 1 end
        if not allowed(nx, up) then
          heat[idx(up, nx)] = 1
        else
          local nv = v - d
          if nv < 1 then nv = 1 end
          heat[idx(up, nx)] = nv
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

-- 单行串（v41 的写法 + <size> 包裹）：只含这一行的 16 格 ⇒ 长度 ~120 字符，远离上限
local function build_row(r)
  local parts, open = {}, false
  local function close()
    if open then parts[#parts + 1] = "</color>"; open = false end
  end
  local curQ = -1
  for c = 0, COLS - 1 do
    local q = qlevel(heat[idx(r, c)] or 1)
    if q == 0 then
      -- 冷端用"透明方块"占位：半角空格会被渲染器裁掉 ⇒ 行宽不一致 ⇒ 左右对不齐 ✗
      if curQ ~= 0 then
        close()
        parts[#parts + 1] = "<color=#00000000>"
        open, curQ = true, 0
      end
      parts[#parts + 1] = "█"
    else
      if q ~= curQ then
        close()
        local p = QPAL[q] or QPAL[1]
        parts[#parts + 1] = string.format("<color=#%02X%02X%02X>", p[1], p[2], p[3])
        open, curQ = true, q
      end
      parts[#parts + 1] = "█"
    end
  end
  close()
  -- ★ v41 的列缝闭合：把字墨放大 SIZE_K 倍（每框只 1 行 ⇒ 不会撑大"框内行距"）
  return "<size=" .. math.floor(FONT * SIZE_K) .. ">" .. table.concat(parts) .. "</size>"
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
  -- 每行一个框：Left + Top ⇒ 行距与列位完全由我们给的位置决定
  t(function() c.horizontalAlignment = Enum.TextHorizontalAlignment.Left end)
  t(function() c.verticalAlignment = Enum.TextVerticalAlignment.Top end)
  t(function() c:SetActive(true) end)
  t(function() c:SetVisible(true) end)
  return c
end

function OnInit()
  say("boot fire_v54 v41-base rows=" .. ROWS .. " font=" .. FONT
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
  bh = math.floor(FONT * SIZE_K * 2) + 8          -- 框高只是裁剪矩形：给足余量
  rowStep = math.floor(FONT * SIZE_K * ROW_K)     -- ★★ 行距（v41 的系数，作用到每一行）
  local totalH = (ROWS - 1) * rowStep + bh
  baseX0 = math.floor(W * 0.5 - bw * 0.5)
  baseY0 = math.floor(H * 0.5 - totalH * 0.5)

  say("canvas=" .. W .. "x" .. H .. " font=" .. FONT .. " rowStep=" .. rowStep
    .. " boxWxH=" .. bw .. "x" .. bh .. " (building rows over frames)")
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1
  if tick > MAX_TICKS then
    say("stop tick=" .. tick .. " updates=" .. updates .. " fails=" .. fails)
    t(function() script:EnableUpdate(false) end)
    alive = false
    return
  end
  if dt == nil or dt <= 0 then return end

  -- ① 分帧建行（避免启动期爆发）
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

  if tick % STEP_TICKS ~= 0 then return end     -- 20fps

  updates = updates + 1
  stepFire()
  local wrote, maxLen = 0, 0
  for r = 0, ROWS - 1 do
    local s = build_row(r)                      -- 脏检查：串没变就不写
    if #s > maxLen then maxLen = #s end
    if s ~= lastS[r + 1] and rows[r + 1] ~= nil then
      if t(function() rows[r + 1].text = s end) then
        lastS[r + 1] = s
        wrote = wrote + 1
      end
    end
  end
  if updates == 1 or updates % 60 == 0 then
    say("u=" .. updates .. " wrote=" .. wrote .. " maxRowLen=" .. maxLen .. " tick=" .. tick)
  end
end
