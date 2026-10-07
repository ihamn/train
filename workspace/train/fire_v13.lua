-- fire_v13.lua —— v8 的轻串 + 20fps 动画（两个已验证的东西相加）
-- 依据（本轮确认）：
--   · v6（25 级 / 标签 ~150 / 串 ~4KB）⇒ 整屏原文 ✗
--   · v8（6 级 / 标签 ~30 / 串 ~1.5KB，静态）⇒ 用户看到火 ✓
--   · 社区线索：实机 ~20fps 在改 text ⇒ 目标频率 = 每 3 帧一改（20Hz）✓
--   · 截图 s0705 拍到闪的正是 "<color=#…" 原文 ⇒ 解析失败 = 串太重 ✓
-- 本版 = v8（6 级量化、6 位色、居中）+ 每 3 帧重算一次 text + 脏检查
-- 另留一个单色 ASCII 框做对照（纯文本，一定显示 ✓）

local PRE_TEXT = 1073741850
local COLS, ROWS = 16, 27
local SOURCE_ROWS, DECAY_MAX, EXPONENT, NLEV = 3, 3, 0.9, 25
local FONT = 24
local LEVELS = 6
local STEP_TICKS = 3          -- ★ 20fps（每 3 帧一改）
local ASCII_EVERY = 6

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
local rich, ascii, heat = nil, nil, {}
local lastRich, lastAscii = nil, nil

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

local rseed = 20261014
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

-- 轻串：6 级、6 位色、同色合并、换行用 \n
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

local RAMP = { [1]=" ", [2]=".", [3]=".", [4]=":", [5]=":", [6]=":", [7]="*", [8]="*", [9]="*", [10]="*",
  [11]="o", [12]="o", [13]="o", [14]="o", [15]="O", [16]="O", [17]="O", [18]="#", [19]="#", [20]="#",
  [21]="@", [22]="@", [23]="@", [24]="@", [25]="@" }
local function build_ascii()
  local parts = {}
  for r = 0, ROWS - 1 do
    if r > 0 then parts[#parts + 1] = "\n" end
    for c = 0, COLS - 1 do
      parts[#parts + 1] = RAMP[heat[idx(r, c)] or 1] or " "
    end
  end
  return table.concat(parts)
end

local function mk(name, ox, oy, w, h, fs)
  if builds >= 40 then return nil end
  local ok, c = pcall(game.InstantiateClientUIControl, PRE_TEXT, host)
  if not ok or c == nil then return nil end
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
  t(function() c:SetVisible(true) end)
  return c
end

function OnInit()
  say("boot v13（v8 轻串 + 20fps）")
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

  local s, runs = build_rich()
  rich = mk("RICH13", 80, y, bw, bh, FONT)
  if rich ~= nil then
    t(function() rich.text = s end)
    lastRich = s
  end
  local sa = build_ascii()
  ascii = mk("ASCII13", 80 + bw + 60, y, bw, bh, FONT)
  if ascii ~= nil then
    t(function() ascii.text = sa end)
    lastAscii = sa
  end
  say("canvas=" .. W .. "x" .. H .. " levels=" .. LEVELS .. " richLen=" .. #s
    .. " runs=" .. runs .. " asciiLen=" .. #sa .. " built=" .. builds .. " fails=" .. fails)
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1
  if tick > 900 then
    say("stop tick=" .. tick .. " updates=" .. updates .. " fails=" .. fails)
    t(function() script:EnableUpdate(false) end)
    alive = false
    return
  end
  if dt == nil or dt <= 0 then return end
  if tick % STEP_TICKS ~= 0 then return end          -- ★ 20fps

  updates = updates + 1
  stepFire()
  local s = build_rich()
  if rich ~= nil and s ~= lastRich then
    if t(function() rich.text = s end) then lastRich = s end
  end
  if ascii ~= nil and tick % ASCII_EVERY == 0 then
    local sa = build_ascii()
    if sa ~= lastAscii then
      if t(function() ascii.text = sa end) then lastAscii = sa end
    end
  end
end
