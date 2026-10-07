-- fire_v14.lua —— 轻串 + 可见预渲染 + 切可见性（播放时**一次都不改 text**）
-- 结论链（本轮确认）：
--   · v8：**轻串 + 静态（只设一次）** ⇒ 正常 ✓
--   · v13：**轻串 + 每 3 帧改 text** ⇒ 依旧闪原文 ✗
--   ⇒ 结论：**只要"改 text"就会闪一次**；与串大小无关 ✓✓ ⇒ 播放期绝不能改 text ✓
--   · v5 曾做过"可见预渲染 + 切可见性"，但用的是**重串（25 级 + 8 位 alpha）** ✗
--   ⇒ 本版 = v5 的播放架构 + v8/v13 的**轻串**（6 级、6 位）✓
-- 流程：① 每 6 帧生成 1 帧（**可见**，让它解析；同时隐藏上一帧）⇒ 12 帧 ≈ 1.2 秒
--       ② 播放：只 SetVisible，**永不改 text** ⇒ 零解析 ✓

local PRE_TEXT = 1073741850
local COLS, ROWS = 16, 27
local SOURCE_ROWS, DECAY_MAX, EXPONENT, NLEV = 3, 3, 0.9, 25
local FONT = 24
local LEVELS = 6
local FRAMES = 12
local PRE_TICKS = 6          -- 预渲染：每帧可见停留帧数（你会看到火逐帧过一遍 ✓）
local PLAY_TICKS = 3         -- 播放：切帧间隔（20fps ✓）

local PAL = {
  {  7,  7, 15 }, { 26, 10, 10 }, { 60, 12, 10 }, {100, 15, 12 }, {140, 20, 12 },
  {176, 28, 12 }, {206, 40, 12 }, {226, 58, 12 }, {238, 78, 14 }, {246,100, 16 },
  {250,120, 18 }, {252,140, 22 }, {254,158, 26 }, {255,172, 34 }, {255,186, 48 },
  {255,198, 66 }, {255,208, 86 }, {255,216,108 }, {255,224,132 }, {255,232,158 },
  {255,240,190 }, {255,246,215 }, {255,250,235 }, {255,253,248 }, {255,255,255 },
}
local QPAL = { PAL[3], PAL[7], PAL[11], PAL[15], PAL[20], PAL[25] }

local host, W, H = nil, 1680, 900
local tick, builds, fails, alive, swaps = 0, 0, 0, true, 0
local frames, heat = {}, {}
local phase, shown, cur, bw, bh, frameY = "prerender", 0, 0, 0, 0, 0
local pre = nil
local WAIT_TICKS = 48

local function say(s) if print then pcall(print, "TR " .. s) end end
local function t(fn) local ok = pcall(fn); if not ok then fails = fails + 1 end; return ok end
local function rgb(r, g, b)
  local ok, v = pcall(function() return Color.FromRGBA(r, g, b, 255) end)
  if ok then return v end
  return nil
end
local function point_anchor(c)
  t(function() c.anchorMinX = 0 end); t(function() c.anchorMinY = 0 end)
  t(function() c.anchorMaxX = 0 end); t(function() c.anchorMaxY = 0 end)
  t(function() c.pivotX = 0 end);     t(function() c.pivotY = 0 end)
end

local rseed = 20261015
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
local function build_rich()
  local parts, runs, open = {}, 0, false
  local function close()
    if open then parts[#parts + 1] = "</color>"; open = false end
  end
  for r = 0, ROWS - 1 do
    if r > 0 then close(); parts[#parts + 1] = "\n" end
    local curQ = -1
    for c = 0, COLS - 1 do
      local q = qlevel(heat[idx(r, c)] or 1)
      if q == 0 then
        close(); curQ = -1
        parts[#parts + 1] = " "
      else
        if q ~= curQ then
          close()
          local p = QPAL[q] or QPAL[1]
          parts[#parts + 1] = string.format("<color=#%02X%02X%02X>", p[1], p[2], p[3])
          open, curQ = true, q
          runs = runs + 1
        end
        parts[#parts + 1] = "■"
      end
    end
  end
  close()
  return table.concat(parts), runs
end

local function mk(name, ox, oy, w, h, fs, visible)
  if builds >= 40 then return nil end
  local ok, c = pcall(game.InstantiateClientUIControl, PRE_TEXT, host)
  if not ok or c == nil then alive = false; return nil end
  builds = builds + 1
  point_anchor(c)
  t(function() c.name = name end)
  t(function() c:SetSizeDelta(w, h) end)
  t(function() c:SetAnchoredPosition(ox, oy) end)
  t(function() c.fontSize = fs or FONT end)
  local fc = rgb(255, 255, 255)
  if fc ~= nil then
    t(function() c.fontColor = fc end)
  end
  t(function() c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle end)
  t(function() c.verticalAlignment = Enum.TextVerticalAlignment.Middle end)
  t(function() c:SetActive(true) end)
  t(function() c:SetVisible(visible and true or false) end)
  return c
end

function OnInit()
  say("boot v17（预渲染约 10 秒：12 帧 × (2+48) 帧 ≈ 600 帧）")
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
  bw, bh = COLS * FONT + 28, ROWS * (FONT + 4)
  frameY = math.max(20, H - bh - 40)
  say("canvas=" .. W .. "x" .. H .. " frames=" .. FRAMES .. "（隐藏赋值 + 等 " .. WAIT_TICKS .. " 帧后显示）")
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1
  if tick > 900 then
    say("stop tick=" .. tick .. " frames=" .. #frames .. " swaps=" .. swaps .. " fails=" .. fails)
    t(function() script:EnableUpdate(false) end)
    alive = false
    return
  end
  if dt == nil or dt <= 0 then return end

  -- ── ① 可见预渲染：每 PRE_TICKS 帧建 1 帧（可见 ⇒ 解析在可见状态下完成）
  if phase == "prerender" then
    -- ★ 时序（v14 的教训：可见后立刻赋 text 会露原文一瞬 ✗）：
    --   ① 建出来先隐藏 ② 赋 text ③ 等 WAIT_TICKS 让它解析 ④ 短暂显示 2 帧 ⑤ 隐藏，进入下一帧
    if pre == nil and tick % 2 == 0 then
      shown = shown + 1
      if shown > FRAMES then
        phase = "play"
        cur = 0
        say("prerender done frames=" .. #frames .. " fails=" .. fails)
        return
      end
      local s, runs = build_rich()
      local c = mk("F" .. shown, 80, frameY, bw, bh, FONT, false)    -- ★ 先隐藏
      pre = { c = c, untilTick = tick + WAIT_TICKS, showLeft = 2 }
      if c ~= nil then
        t(function() c.text = s end)                                  -- ★ 隐藏状态下赋 text
        frames[shown] = c
        if shown == 1 then say("frame1 len=" .. #s .. " runs=" .. runs) end
      end
      stepFire()
      return
    end
    -- ★★ 按用户口径：**预渲染阶段全程不显示任何帧**（纯后台准备）
    --    所有帧都准备好后，才进入播放阶段（切可见性）✓
    if pre ~= nil and tick >= pre.untilTick then
      pre = nil                                    -- 这一帧准备完毕（保持隐藏 ✓）
    end
    return
  end

  -- ── ② 播放：只切可见性（**永不改 text**）
  if phase == "play" and #frames > 1 and tick % PLAY_TICKS == 0 then
    if cur > 0 then t(function() frames[cur]:SetVisible(false) end) end
    cur = cur % #frames + 1
    t(function() frames[cur]:SetVisible(true) end)
    swaps = swaps + 1
  end
end
