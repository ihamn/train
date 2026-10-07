-- fire_v9.lua —— 动起来的量化火（单框 16×27、6 级色、活体更新）
-- 结论链：
--   v6：25 级色 ⇒ 标签 ~150、串 ~4KB ⇒ 显示成标签文字 ✗
--   v8：6 级色 ⇒ 标签 ~30、串 ~1.5KB ⇒ **显示成彩色火** ✓（用户："画面不动" —— 静态是故意的）
--   本版：在 v8 基础上加回动画 ⇒ 验证"串轻了之后，活体更新还会不会闪"
-- 仍不做的：多帧预渲染（先看活体更新这一条）

local PRE_TEXT = 1073741850
local COLS, ROWS = 16, 27
local SOURCE_ROWS, DECAY_MAX, EXPONENT, NLEV = 3, 3, 0.9, 25
local FONT = 24
local LEVELS = 6
local STEP_TICKS = 8            -- 更新频率（约 7.5fps）

local PAL = {
  {  7,  7, 15 }, { 26, 10, 10 }, { 60, 12, 10 }, {100, 15, 12 }, {140, 20, 12 },
  {176, 28, 12 }, {206, 40, 12 }, {226, 58, 12 }, {238, 78, 14 }, {246,100, 16 },
  {250,120, 18 }, {252,140, 22 }, {254,158, 26 }, {255,172, 34 }, {255,186, 48 },
  {255,198, 66 }, {255,208, 86 }, {255,216,108 }, {255,224,132 }, {255,232,158 },
  {255,240,190 }, {255,246,215 }, {255,250,235 }, {255,253,248 }, {255,255,255 },
}
local QPAL = { PAL[3], PAL[7], PAL[11], PAL[15], PAL[20], PAL[25] }

local host, W, H = nil, 1680, 900
local tick, builds, fails, alive = 0, 0, 0, true
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

local rseed = 20261011
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

function OnInit()
  say("boot fire v9（量化 6 级 + 活体更新）")
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

  local bw, bh = COLS * FONT + 28, ROWS * (FONT + 4)
  local y = math.max(20, H - bh - 40)
  local ok2, c = pcall(game.InstantiateClientUIControl, PRE_TEXT, host)
  if not ok2 or c == nil then say("instantiate failed"); alive = false; return end
  builds = builds + 1
  point_anchor(c)
  t(function() c.name = "FIRE" end)
  t(function() c:SetSizeDelta(bw, bh) end)
  t(function() c:SetAnchoredPosition(80, y) end)
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

  local s, runs = build_rich()
  t(function() box.text = s end)
  lastS = s
  say("canvas=" .. W .. "x" .. H .. " len=" .. #s .. " runs=" .. runs
    .. " levels=" .. LEVELS .. " built=" .. builds .. " fails=" .. fails)
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1
  if tick > 600 then
    say("stop tick=" .. tick .. " updates=" .. math.floor(tick / STEP_TICKS) .. " fails=" .. fails)
    t(function() script:EnableUpdate(false) end)
    alive = false
    return
  end
  if dt == nil or dt <= 0 then return end
  if tick % STEP_TICKS ~= 0 then return end

  stepFire()
  local s = build_rich()
  if s ~= lastS then
    if t(function() box.text = s end) then lastS = s end
  end
end
