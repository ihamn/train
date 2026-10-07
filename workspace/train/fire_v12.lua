-- fire_v12.lua —— 按社区做法重写【关键差异全部来自用户贴出的真实作品标记】
-- 社区证据（用户贴的串）：
--   ① <b>…</b> 包整串        ⇒ 方块填满格子、无缝（像素画必需）
--   ② <color=#RRGGBB>…</color> 成对闭合
--   ③ <color=#00000000>       ⇒ 8 位带 alpha 支持，透明格用它（**而不是空格**，保持网格对齐）
--   ④ **整串没有 \n**         ⇒ 靠**文本框宽度自动折行**（我前几版一直手动 \n ⇒ 全挤乱 ✗）
-- 本版做法：
--   一行到底；外面包 <b></b>；每格 ■（热）或 ■（透明色）；框宽 = 列数 × 字号（■ 是全角=1em）
--   关掉字号自适应（adaptiveFontSize=false）⇒ 否则平台会缩字、折行点就变了 ✗
--   左/上对齐 ⇒ 折行从左上开始，可预期
--   静态单帧（先确认折行对不对，再加动画）

local PRE_TEXT = 1073741850
local COLS, ROWS = 16, 27
local SOURCE_ROWS, DECAY_MAX, EXPONENT, NLEV = 3, 3, 0.9, 25
local FONT = 24
local LEVELS = 6

local PAL = {
  {  7,  7, 15 }, { 26, 10, 10 }, { 60, 12, 10 }, {100, 15, 12 }, {140, 20, 12 },
  {176, 28, 12 }, {206, 40, 12 }, {226, 58, 12 }, {238, 78, 14 }, {246,100, 16 },
  {250,120, 18 }, {252,140, 22 }, {254,158, 26 }, {255,172, 34 }, {255,186, 48 },
  {255,198, 66 }, {255,208, 86 }, {255,216,108 }, {255,224,132 }, {255,232,158 },
  {255,240,190 }, {255,246,215 }, {255,250,235 }, {255,253,248 }, {255,255,255 },
}
local QPAL = { PAL[4], PAL[8], PAL[12], PAL[16], PAL[21], PAL[25] }

local host, W, H = nil, 1680, 900
local builds, fails = 0, 0
local heat = {}

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

local rseed = 20261013
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

-- ★★ 关键：**一行到底、没有 \n**；透明格用 <color=#00000000>■</color>（保持网格对齐）
local function build_oneline()
  local parts, runs, open, curColor = {}, 0, false, nil
  local function close()
    if open then parts[#parts + 1] = "</color>"; open = false; curColor = nil end
  end
  parts[#parts + 1] = "<b>"
  for r = 0, ROWS - 1 do
    for c = 0, COLS - 1 do
      local q = qlevel(heat[idx(r, c)] or 1)
      local col
      if q == 0 then
        col = "#00000000"                      -- 透明格（占位、保持对齐）✓
      else
        local p = QPAL[q] or QPAL[1]
        col = string.format("#%02X%02X%02X", p[1], p[2], p[3])
      end
      if col ~= curColor then
        close()
        parts[#parts + 1] = "<color=" .. col .. ">"
        open, curColor = true, col
        runs = runs + 1
      end
      parts[#parts + 1] = "■"
    end
  end
  close()
  parts[#parts + 1] = "</b>"
  return table.concat(parts), runs
end

function OnInit()
  say("boot v12（一行到底 + <b> + 透明格 #00000000）")
end

function OnStart()
  host = script.object
  if host == nil then say("no host"); return end
  local ok, cw, ch = pcall(game.GetUICanvasSize)
  if ok and type(cw) == "number" and type(ch) == "number" then W, H = cw, ch end
  for i = 1, COLS * ROWS do heat[i] = 1 end
  seedFire()
  for i = 1, 30 do stepFire() end

  -- 框宽 = 列数 × 字号（■ 是全角 ⇒ 步进≈1em）⇒ 期望正好折成 COLS 列
  local bw = COLS * FONT + 8
  local bh = ROWS * (FONT + 4) + 20
  local ok2, c = pcall(game.InstantiateClientUIControl, PRE_TEXT, host)
  if not ok2 or c == nil then say("instantiate failed"); return end
  builds = builds + 1
  point_anchor(c)
  t(function() c.name = "FIRE12" end)
  t(function() c:SetSizeDelta(bw, bh) end)
  t(function() c:SetAnchoredPosition(math.floor(W * 0.5 - bw * 0.5), math.floor(H * 0.5 - bh * 0.5)) end)
  t(function() c.fontSize = FONT end)
  local fc = rgb(255, 255, 255)
  if fc ~= nil then
    t(function() c.fontColor = fc end)
  end
  -- ★ 关掉字号自适应（否则平台会缩字 ⇒ 折行点变 ✗）
  t(function() c.adaptiveFontSize = false end)
  t(function() c.horizontalAlignment = Enum.TextHorizontalAlignment.Left end)
  t(function() c.verticalAlignment = Enum.TextVerticalAlignment.Top end)
  t(function() c:SetActive(true) end)
  t(function() c:SetVisible(true) end)

  local s, runs = build_oneline()
  t(function() c.text = s end)
  say("canvas=" .. W .. "x" .. H .. " grid=" .. COLS .. "x" .. ROWS
    .. " box=" .. bw .. "x" .. bh .. " font=" .. FONT
    .. " len=" .. #s .. " runs=" .. runs .. " fails=" .. fails)
  -- 打印串的头 90 字符，方便我自己核对写法 ✓
  say("head=" .. s:sub(1, 90))
end

function OnUpdate(dt) end
