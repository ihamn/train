-- fire_v21.lua —— 遮罩盖住"预热闪"（按最终定位：闪烁集中在每帧的第一次可见渲染）
-- 定位链（综合所有实测）：
--   ① 首次赋值 text ⇒ 能解析（需时间）✓（v8 静态版正常 ✓）
--   ② **重新赋值 text ⇒ 退化成原文** ✗（v13/v20 各种频率都闪 ✓ 与频率无关 ✓）
--   ③ 隐藏赋值 ⇒ 解析推迟到第一次可见 ✗ ⇒ v19"闪但少了" = **每帧第一次出现时闪一次** ✓
--   ⇒ 解法：把这些"第一次"全部藏在**全屏遮罩**后面 ✓✓ 播放时零闪 ✓
-- 流程：① 建遮罩（全屏深色）② 逐帧建+显示 2 帧（预热；被遮罩盖住，看不见闪）
--       ③ 全部预热完 ⇒ 隐藏遮罩 ⇒ 播放（只切可见性）

local PRE_TEXT = 1073741850
local PRE_IMG = 1073741851        -- 实测 = ClientUIImageControl（遮罩用它）
local ART_SQ = 100001
local COLS, ROWS = 16, 27
local SOURCE_ROWS, DECAY_MAX, EXPONENT, NLEV = 3, 3, 0.9, 25
local FONT = 24
local LEVELS = 6
local FRAMES = 12
local WARM_SHOW = 2               -- 每帧预热显示帧数（被遮罩盖着）
local PLAY_TICKS = 3              -- 播放切帧间隔（20fps）

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
local frames, heat, mask = {}, {}, nil
local phase, idx, warmLeft, cur = "build", 0, 0, 0
local bw, bh, frameY = 0, 0, 0

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

local rseed = 20261016
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
local function idxh(r, c) return r * COLS + c + 1 end

local function seedFire()
  for r = ROWS - SOURCE_ROWS, ROWS - 1 do
    for c = 0, COLS - 1 do
      if allowed(c, r) then heat[idxh(r, c)] = NLEV end
    end
  end
end
local function stepFire()
  seedFire()
  for r = ROWS - 1, 1, -1 do
    local up = r - 1
    for c = 0, COLS - 1 do
      local v = heat[idxh(r, c)]
      if v <= 1 then
        heat[idxh(up, c)] = 1
      else
        local d = rnd(DECAY_MAX + 1)
        local nx = c + rnd(3) - 1
        if nx < 0 then nx = 0 elseif nx >= COLS then nx = COLS - 1 end
        if not allowed(nx, up) then
          heat[idxh(up, nx)] = 1
        else
          local nv = v - d
          if nv < 1 then nv = 1 end
          heat[idxh(up, nx)] = nv
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
      local q = qlevel(heat[idxh(r, c)] or 1)
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

local function mk_text(name, ox, oy, w, h, fs, visible)
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

-- 全屏深色遮罩（盖住一切；预热闪都在它后面）
local function make_mask()
  local ok, c = pcall(game.InstantiateClientUIControl, PRE_IMG, host)
  if not ok or c == nil then return nil end
  builds = builds + 1
  point_anchor(c)
  t(function() c.name = "MASK" end)
  t(function() c:SetSizeDelta(W, H) end)
  t(function() c:SetAnchoredPosition(0, 0) end)
  t(function() c:SetImage(Enum.ImageSource.StaticReference, ART_SQ) end)
  local col = rgb(12, 16, 26)
  if col ~= nil then t(function() c.imageColor = col end) end
  t(function() c:SetActive(true) end)
  t(function() c:SetVisible(true) end)
  return c
end

function OnInit()
  say("boot v21（遮罩盖住预热闪）")
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
  mask = make_mask()                     -- ★ 先盖住
  say("canvas=" .. W .. "x" .. H .. " mask=" .. tostring(mask ~= nil)
    .. " frames=" .. FRAMES .. " warmShow=" .. WARM_SHOW)
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1
  if tick > 3000 then
    say("stop tick=" .. tick .. " frames=" .. #frames .. " swaps=" .. swaps .. " fails=" .. fails)
    t(function() script:EnableUpdate(false) end)
    alive = false
    return
  end
  if dt == nil or dt <= 0 then return end

  -- ① 逐帧：建（隐藏）→ 赋 text → 显示 WARM_SHOW 帧（预热，被遮罩盖着）→ 隐藏
  if phase == "build" then
    if warmLeft > 0 then
      warmLeft = warmLeft - 1
      if warmLeft == 0 and frames[idx] ~= nil then
        t(function() frames[idx]:SetVisible(false) end)
      end
      return
    end
    if tick % 2 ~= 0 then return end
    idx = idx + 1
    if idx > FRAMES then
      if mask ~= nil then t(function() mask:SetVisible(false) end) end   -- ★ 揭开遮罩
      phase = "play"
      cur = 0
      say("warm done frames=" .. #frames .. " fails=" .. fails)
      return
    end
    local s, runs = build_rich()
    local c = mk_text("F" .. idx, 80, frameY, bw, bh, FONT, false)
    if c ~= nil then
      t(function() c.text = s end)
      frames[idx] = c
      if idx == 1 then say("frame1 len=" .. #s .. " runs=" .. runs) end
      t(function() c:SetVisible(true) end)          -- 预热这一次显示（被遮罩盖住 ✓）
      warmLeft = WARM_SHOW
    end
    stepFire()
    return
  end

  -- ② 播放：只切可见性（先显后隐 ✓）
  if phase == "play" and #frames > 1 and tick % PLAY_TICKS == 0 then
    local nxt = cur % #frames + 1
    t(function() frames[nxt]:SetVisible(true) end)
    if cur > 0 and cur ~= nxt then
      t(function() frames[cur]:SetVisible(false) end)
    end
    cur = nxt
    swaps = swaps + 1
  end
end
