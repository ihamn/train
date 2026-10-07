-- fire_min_v10.lua —— 最小验证：**一个文本框渲染 6×6 方阵**（无任何标签）
-- 用户要求：最简单的，不搞多个 ✓
-- 内容就是 6 行 × 6 个 ■，用 \n 换行；不加 <color>、不加任何标记
-- 目的：确认"文本框能渲染多行方块矩阵"这个最底层事实（若这都不行，后面全不用谈）
-- 顺带在同一框里加第 2 段：**每行一个颜色**（6 行 6 个颜色，用 <color=#RRGGBB>行</color>）
--   —— 但为了"最简单"，两段分开：BOX_SIMPLE 纯方阵 / BOX_ROWCOLOR 每行一色
--   ★ 若你只想看最简那一步，BOX_SIMPLE 就是答案

local PRE_TEXT = 1073741850
local FONT = 24
local N = 6                      -- 6×6

local host, W, H = nil, 1680, 900
local builds, fails = 0, 0

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

-- ① 最简：纯 6×6 方阵（无标签）
local function plain_grid()
  local rows = {}
  for r = 1, N do
    local row = {}
    for c = 1, N do row[#row + 1] = "■" end
    rows[#rows + 1] = table.concat(row)
  end
  return table.concat(rows, "\n")
end

-- ② 每行一个颜色（6 行 6 色，标签成对闭合）
local ROWCOL = {
  { 255,  60,  60 }, { 255, 140,  40 }, { 255, 210,  70 },
  { 180, 255,  90 }, {  90, 220, 255 }, { 170, 120, 255 },
}
local function rowcolor_grid()
  local rows = {}
  for r = 1, N do
    local p = ROWCOL[r]
    local row = {}
    for c = 1, N do row[#row + 1] = "■" end
    rows[#rows + 1] = string.format("<color=#%02X%02X%02X>%s</color>", p[1], p[2], p[3], table.concat(row))
  end
  return table.concat(rows, "\n")
end

local function mk(name, ox, oy, w, h, text)
  if builds >= 8 then return nil end
  local ok, c = pcall(game.InstantiateClientUIControl, PRE_TEXT, host)
  if not ok or c == nil then return nil end
  builds = builds + 1
  point_anchor(c)
  t(function() c.name = name end)
  t(function() c:SetSizeDelta(w, h) end)
  t(function() c:SetAnchoredPosition(ox, oy) end)
  t(function() c.fontSize = FONT end)
  local fc = rgb(255, 255, 255)
  if fc ~= nil then
    t(function() c.fontColor = fc end)
  end
  t(function() c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle end)
  t(function() c.verticalAlignment = Enum.TextVerticalAlignment.Middle end)
  t(function() c:SetActive(true) end)
  t(function() c:SetVisible(true) end)
  t(function() c.text = text end)
  return c
end

function OnInit()
  say("boot min v10（6x6）")
end

function OnStart()
  host = script.object
  if host == nil then say("no host"); return end
  local ok, cw, ch = pcall(game.GetUICanvasSize)
  if ok and type(cw) == "number" and type(ch) == "number" then W, H = cw, ch end

  local bw, bh = N * FONT + 30, N * (FONT + 4) + 20
  local y = math.floor(H * 0.5 - bh * 0.5)

  local s1 = plain_grid()
  local s2 = rowcolor_grid()
  say("plain len=" .. #s1 .. " rowcolor len=" .. #s2 .. " grid=" .. N .. "x" .. N)

  mk("SIMPLE", math.floor(W * 0.5 - bw - 40), y, bw, bh, s1)      -- 左：纯方阵
  mk("ROWCOLOR", math.floor(W * 0.5 + 40), y, bw, bh, s2)         -- 右：每行一色

  say("canvas=" .. W .. "x" .. H .. " built=" .. builds .. " fails=" .. fails)
end

function OnUpdate(dt) end
