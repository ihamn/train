-- fire_dyn6_v11.lua —— 动态 6×6（单框、活体更新，最小样本）
-- 目的：把"活体更新会不会闪"缩到**最小**：6×6=36 格、6 级色、串约 300~500 字节
--   若这都不闪 ⇒ 之前闪是"串太长/标签太多" ✓ ⇒ 解法是分块/量化 ✓
--   若这还闪 ⇒ 活体改 text 这条路本身不稳 ✗ ⇒ 只能"预生成帧 + 切可见性"
-- 算法仍是 props.lua 那套（DOOM 火焰），只是网格缩到 6×6

local PRE_TEXT = 1073741850
local COLS, ROWS = 6, 6
local SOURCE_ROWS, DECAY_MAX, EXPONENT, NLEV = 1, 1, 0.9, 25
local FONT = 28
local LEVELS = 6
local STEP_TICKS = 8

local PAL = {
  {  7,  7, 15 }, { 26, 10, 10 }, { 60, 12, 10 }, {100, 15, 12 }, {140, 20, 12 },
  {176, 28, 12 }, {206, 40, 12 }, {226, 58, 12 }, {238, 78, 14 }, {246,100, 16 },
  {250,120, 18 }, {252,140, 22 }, {254,158, 26 }, {255,172, 34 }, {255,186, 48 },
  {255,198, 66 }, {255,208, 86 }, {255,216,108 }, {255,224,132 }, {255,232,158 },
  {255,240,190 }, {255,246,215 }, {255,250,235 }, {255,253,248 }, {255,255,255 },
}
local QPAL = { PAL[4], PAL[8], PAL[12], PAL[16], PAL[21], PAL[25] }

local host, W, H = nil, 1680, 900
local tick, builds, fails, alive, updates = 0, 0, 0, true, 0
local box, heat, lastS = nil, {}, nil

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

local rseed = 20261012
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

local function build()
  local parts, runs, open = {}, 0, false
  local function close()
    if open then parts[#parts + 1] = "</color>"; open = false end
  end
  -- ★ 第一行加一个帧号（肉眼能看出"在变"）
  parts[#parts + 1] = "F" .. (updates % 10) .. "\n"
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

function OnInit()
  say("boot dyn6 v11")
  t(function() script:EnableUpdate(true) end)
end

function OnStart()
  host = script.object
  if host == nil then say("no host"); alive = false; return end
  local ok, cw, ch = pcall(game.GetUICanvasSize)
  if ok and type(cw) == "number" and type(ch) == "number" then W, H = cw, ch end
  for i = 1, COLS * ROWS do heat[i] = 1 end
  seedFire()
  for i = 1, 20 do stepFire() end

  local bw, bh = COLS * FONT + 40, (ROWS + 1) * (FONT + 4) + 20
  local ok2, c = pcall(game.InstantiateClientUIControl, PRE_TEXT, host)
  if not ok2 or c == nil then say("instantiate failed"); alive = false; return end
  builds = builds + 1
  point_anchor(c)
  t(function() c.name = "DYN6" end)
  t(function() c:SetSizeDelta(bw, bh) end)
  t(function() c:SetAnchoredPosition(math.floor(W * 0.5 - bw * 0.5), math.floor(H * 0.5 - bh * 0.5)) end)
  t(function() c.fontSize = FONT end)
  local fc = rgb(255, 255, 255)
  if fc ~= nil then
    t(function() c.fontColor = fc end)
  end
  t(function() c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle end)
  t(function() c.verticalAlignment = Enum.TextVerticalAlignment.Middle end)
  t(function() c:SetActive(true) end)
  t(function() c:SetVisible(true) end)
  box = c

  local s, runs = build()
  t(function() box.text = s end)
  lastS = s
  say("canvas=" .. W .. "x" .. H .. " grid=" .. COLS .. "x" .. ROWS
    .. " len=" .. #s .. " runs=" .. runs .. " built=" .. builds .. " fails=" .. fails)
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1
  if tick > 600 then
    say("stop tick=" .. tick .. " updates=" .. updates .. " fails=" .. fails)
    t(function() script:EnableUpdate(false) end)
    alive = false
    return
  end
  if dt == nil or dt <= 0 then return end
  if tick % STEP_TICKS ~= 0 then return end

  updates = updates + 1
  stepFire()
  local s = build()
  if s ~= lastS then
    if t(function() box.text = s end) then lastS = s end
  end
end
