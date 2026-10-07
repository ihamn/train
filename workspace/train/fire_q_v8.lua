-- fire_q_v8.lua —— 量化色版：单框 16×27 + 只有 6 级颜色（静态）
-- 目的：把"标签太多 ⇒ 解析失败"这个嫌疑单独验一次
--   v6：单框 16×27、25 级色 ⇒ 标签 ~150~200、串 ~4KB ⇒ 显示为文字 ✗
--   v8：单框 16×27、**量化到 6 级** ⇒ 每行只有少数几段 ⇒ 标签 ~30~50、串 ~1.5KB
--   对齐：Middle/Middle（v6 时是居中的 ✓，v7 我误改成 Left/Top ⇒ 回归 ✓）
--   静态：不启用 OnUpdate（排除时序干扰）
-- 判据：若这次显示成**彩色火** ⇒ 病因是"标签太多/串太长" ✓（那么量化 + 分块就是解法）
--       若仍显示成**标签文字** ⇒ 控件不支持标记 ✗

local PRE_TEXT = 1073741850
local COLS, ROWS = 16, 27
local SOURCE_ROWS, DECAY_MAX, EXPONENT, NLEV = 3, 3, 0.9, 25
local FONT = 24
local LEVELS = 6                     -- ★ 量化级数（原来 25）

-- 25 级原调色板（用于取 6 个代表色）
local PAL = {
  {  7,  7, 15 }, { 26, 10, 10 }, { 60, 12, 10 }, {100, 15, 12 }, {140, 20, 12 },
  {176, 28, 12 }, {206, 40, 12 }, {226, 58, 12 }, {238, 78, 14 }, {246,100, 16 },
  {250,120, 18 }, {252,140, 22 }, {254,158, 26 }, {255,172, 34 }, {255,186, 48 },
  {255,198, 66 }, {255,208, 86 }, {255,216,108 }, {255,224,132 }, {255,232,158 },
  {255,240,190 }, {255,246,215 }, {255,250,235 }, {255,253,248 }, {255,255,255 },
}
-- 6 个代表色（取样自 PAL）
local QPAL = { PAL[3], PAL[7], PAL[11], PAL[15], PAL[20], PAL[25] }

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

local rseed = 20261010
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

-- 热量 → 量化级（1..LEVELS）；v<=1 视为无火
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

local function mk_text(name, ox, oy, w, h, fs)
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
  -- ★ 回归 v6 的居中（v7 误改成 Left/Top）
  t(function() c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle end)
  t(function() c.verticalAlignment = Enum.TextVerticalAlignment.Middle end)
  t(function() c:SetActive(true) end)
  t(function() c:SetVisible(true) end)
  return c
end

function OnInit()
  say("boot quant v8（静态，6 级色）")
end

function OnStart()
  host = script.object
  if host == nil then say("no host"); return end
  local ok, cw, ch = pcall(game.GetUICanvasSize)
  if ok and type(cw) == "number" and type(ch) == "number" then W, H = cw, ch end

  for i = 1, COLS * ROWS do heat[i] = 1 end
  seedFire()
  for i = 1, 30 do stepFire() end

  local bw, bh = COLS * FONT + 28, ROWS * (FONT + 4)
  local y = math.max(20, H - bh - 40)

  local s, runs = build_rich()
  local box = mk_text("RICH", 80, y, bw, bh, FONT)
  if box ~= nil then t(function() box.text = s end) end
  say("rich len=" .. #s .. " runs=" .. runs .. " levels=" .. LEVELS .. " fontSize=" .. FONT)

  local a = mk_text("ASCII", 80 + bw + 60, y, bw, bh, FONT)
  if a ~= nil then
    local sa = build_ascii()
    t(function() a.text = sa end)
    say("ascii len=" .. #sa)
  end

  say("canvas=" .. W .. "x" .. H .. " built=" .. builds .. " fails=" .. fails)
end

function OnUpdate(dt) end
