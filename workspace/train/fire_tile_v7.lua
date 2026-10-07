-- fire_tile_v7.lua —— 9 宫格分块试验（静态单帧，去掉动画变量）
-- 目的：验证"富文本标签不解析"到底是**串太重**（标签太多/太长）还是**控件根本不支持**
--   分法：15 列 × 27 行 ⇒ 3×3 块，每块 5 列 × 9 行 = 45 格
--         ⇒ 每块串从 ~4KB 降到 ~1KB、标签数 ~1/9 ✓
--   若 9 块都能显示成**彩色** ⇒ 病因是"单串太重" ✓（同时这套分块就是放大像素画的通用架构 ✓）
--   若 9 块仍显示成**标签文字** ⇒ 是控件不支持标记 ✓
-- 另外保留一个"整张单色 ASCII"框做参照（纯文本 ⇒ 一定显示 ✓）
-- 本版**不启用 OnUpdate**（静态画面，排除动画/解析时序的干扰）

local PRE_TEXT = 1073741850
local COLS, ROWS = 15, 27
local SOURCE_ROWS, DECAY_MAX, EXPONENT, NLEV = 3, 3, 0.9, 25
local TILES = 3
local TW, TH = COLS / TILES, ROWS / TILES      -- 每块 5 列 × 9 行
local FONT = 22

local PAL = {
  {  7,  7, 15 }, { 26, 10, 10 }, { 60, 12, 10 }, {100, 15, 12 }, {140, 20, 12 },
  {176, 28, 12 }, {206, 40, 12 }, {226, 58, 12 }, {238, 78, 14 }, {246,100, 16 },
  {250,120, 18 }, {252,140, 22 }, {254,158, 26 }, {255,172, 34 }, {255,186, 48 },
  {255,198, 66 }, {255,208, 86 }, {255,216,108 }, {255,224,132 }, {255,232,158 },
  {255,240,190 }, {255,246,215 }, {255,250,235 }, {255,253,248 }, {255,255,255 },
}

local host, W, H = nil, 1680, 900
local builds, fails = 0, 0
local heat = {}
local CELLW, CELLH = 14, 18                -- 估算的单格像素（对齐用；不完美也能判定）

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

local rseed = 20261009
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

-- 一块（tx,ty 从 0 起）的富文本串：只含这一块的 5×9 格
local function build_tile(tx, ty)
  local parts, runs, open = {}, 0, false
  local function close()
    if open then parts[#parts + 1] = "</color>"; open = false end
  end
  local r0, r1 = ty * TH, ty * TH + TH - 1
  local c0, c1 = tx * TW, tx * TW + TW - 1
  for r = r0, r1 do
    if r > r0 then close(); parts[#parts + 1] = "\n" end
    local curV = -1
    for c = c0, c1 do
      local v = heat[idx(r, c)] or 1
      if v <= 1 then
        close(); curV = -1
        parts[#parts + 1] = " "
      else
        if v ~= curV then
          close()
          local p = PAL[v] or PAL[1]
          parts[#parts + 1] = string.format("<color=#%02X%02X%02X>", p[1], p[2], p[3])
          open, curV = true, v
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
  t(function() c.horizontalAlignment = Enum.TextHorizontalAlignment.Left end)
  t(function() c.verticalAlignment = Enum.TextVerticalAlignment.Top end)
  t(function() c:SetActive(true) end)
  t(function() c:SetVisible(true) end)
  return c
end

function OnInit()
  say("boot tile v7（静态，不启用 OnUpdate）")
end

function OnStart()
  host = script.object
  if host == nil then say("no host"); return end
  local ok, cw, ch = pcall(game.GetUICanvasSize)
  if ok and type(cw) == "number" and type(ch) == "number" then W, H = cw, ch end

  for i = 1, COLS * ROWS do heat[i] = 1 end
  seedFire()
  for i = 1, 30 do stepFire() end

  -- ① 9 宫格：每块独立文本框，各自只装 1/9 的格子
  local tileW, tileH = TW * CELLW, TH * CELLH
  local baseX, baseY = 80, math.max(20, H - ROWS * CELLH - 60)
  local totalLen = 0
  for ty = 0, TILES - 1 do
    for tx = 0, TILES - 1 do
      local s, runs = build_tile(tx, ty)
      totalLen = totalLen + #s
      local ox = baseX + tx * tileW
      local oy = baseY + (TILES - 1 - ty) * tileH      -- y 向上 ⇒ 第 0 行块放最上面
      local c = mk_text("T" .. tx .. ty, ox, oy, tileW + 8, tileH + 8, FONT)
      if c ~= nil then t(function() c.text = s end) end
      say("tile " .. tx .. "," .. ty .. " len=" .. #s .. " runs=" .. runs
        .. " at=" .. ox .. "," .. oy)
    end
  end

  -- ② 参照：整张单色 ASCII（纯文本，一定显示）
  local ascii = mk_text("ASCII", baseX + TILES * tileW + 60, baseY, TW * TILES * CELLW + 20,
    ROWS * CELLH + 20, FONT)
  if ascii ~= nil then
    local s = build_ascii()
    t(function() ascii.text = s end)
    say("ascii len=" .. #s)
  end

  say("canvas=" .. W .. "x" .. H .. " grid=" .. COLS .. "x" .. ROWS
    .. " tiles=" .. TILES .. "x" .. TILES .. " built=" .. builds
    .. " tileLen合计=" .. totalLen .. " fails=" .. fails)
end

function OnUpdate(dt) end
