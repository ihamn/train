-- fire_v53.lua —— ★ 一行一个文本框（解决行间距的唯一可靠办法）
--
-- 为什么必须这么改（v52 的病根）：
--   v52 把 27 行塞进 3 个文本框（每框 9 行，用 \n 换行）⇒ **框内部的行距由引擎定，脚本管不着**；
--   而框与框之间又用 `step = 9 × FONT × 0.90` 里那个硬编码的 0.90 去猜 ⇒ 两边不等就必然错位 ✗
--   ⇒ 这就是"行间距死活调不好"的真相：**行距一半由引擎决定、一半靠猜**。
--
-- 本版：**27 个文本框，每框只装 1 行** ⇒
--   · 行距 = 我给的 `ROW_STEP`（下面一个数字）⇒ 完全可控、可精调 ✓
--   · 每行串只有 ~16 个像素 ≈ 260 字符 ⇒ 顺带远离"文本长度上限"（实测 ~1500 字符）✓
--   · 想更紧/更松：只改 ROW_K（或 ROW_STEP）一个数 ✓
--
-- 另外修掉 v52 的真 bug：`say('glyph candidates = ' .. tostring(#cands))` 引用了不存在的 `cands`
-- ⇒ 真机上会直接报错（那也是文档里说的"测试彩条残留"）。
--
-- 纪律（都来自实测教训）：脏检查（串变了才写）、20fps、日志总量有界、看门狗自毁、
-- 锚点/轴心用**字段**写（方法不存在）、位置/尺寸用方法。

local PRE_TEXT = 1073741850      -- 文本框模板（新关卡 1073741826 实测；旧关卡是 1073741851）

local COLS, ROWS = 16, 27
local SOURCE_ROWS, DECAY_MAX, EXPONENT, NLEV = 3, 3, 0.9, 25
local LEVELS = 6
local FONT = 44                  -- 字号：像素大小就是它（不要用 <size>：会把引擎行距一起撑大）
local ROW_K = 0.95               -- ★★ 行距系数：ROW_STEP = FONT × ROW_K。行距有问题就只调这一个数
local STEP_TICKS = 3             -- 20fps
local MAX_BUILD = 40             -- 27 行 + 余量
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
local ROWS_PER_TICK = 2                 -- 分帧建：每帧建几行（27 行 ⇒ 约 14 帧建完）
local buildNext = 0                     -- 下一个要建的行号（0..ROWS）
local said_built = false                -- 建完只报一次（防止每帧重复打日志）
local baseX0, baseY0 = 0, 0             -- OnStart 算好的基准（分帧建时用）

local function say(s) if print then pcall(print, "TR " .. s) end end
local function t(fn) local ok = pcall(fn); if not ok then fails = fails + 1 end; return ok end
local function rgb(r, g, b)
  local ok, v = pcall(function() return Color.FromRGBA(r, g, b, 255) end)
  if ok then return v end
  return nil
end
-- 锚点/轴心是**字段**（方法 SetAnchorMin/SetPivot 在真机不存在，用了会静默失败）
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

-- 单行串（只含这一行的 16 个格子）⇒ 长度 ~260 字符，稳在上限内
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
  return table.concat(parts)
end

local function mk_row(r, ox, oy)
  if builds >= MAX_BUILD then return nil end
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
  -- 每行一个框：左对齐 + 顶对齐 ⇒ 行距完全由 oy 决定
  t(function() c.horizontalAlignment = Enum.TextHorizontalAlignment.Left end)
  t(function() c.verticalAlignment = Enum.TextVerticalAlignment.Top end)
  t(function() c:SetActive(true) end)
  t(function() c:SetVisible(true) end)
  return c
end

function OnInit()
  say("boot fire_v53 rows=" .. ROWS .. " (one textbox per row)")
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

  bw = COLS * FONT + 20
  bh = FONT * 2 + 8                                  -- 框高只是裁剪矩形：给足余量即可
  rowStep = math.floor(FONT * ROW_K)                 -- ★★ 行距 = 这一个数

  local totalH = (ROWS - 1) * rowStep + bh
  local baseX = math.floor(W * 0.5 - bw * 0.5)
  local baseY = math.floor(H * 0.5 - totalH * 0.5)
  baseX0, baseY0 = baseX, baseY

  -- ★ 分帧建：不在 OnStart 里一次建 27 个控件（那是"启动期爆发"⇒ 真机卡死的头号成因）
  --   每帧建 ROWS_PER_TICK 个，边建边赋初值；建完才开始动画。
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

  -- ① 建行阶段：每帧建 ROWS_PER_TICK 个（分帧建，避免启动期爆发）
  --    注意用 `<`：buildNext == ROWS 表示建完了，必须让后续动画分支接管，
  --    否则会每帧重复打日志（= 又踩"日志风暴"那条坑）。
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
