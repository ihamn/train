-- fire_v23.lua —— 分块版（每块串 ~900 字符，稳在"文本长度上限"内）
-- 真凶（引擎日志原文）：`#spike:211: 文本长度超出限制` ⇒ 文本框 text 有长度上限 ✗
--   · v8  ~1500 字符 ⇒ 正常 ✓     v20 ~2485 / v21 ~2683 ⇒ 超限 ⇒ 赋值失败 ⇒ 显示原文 ✗
--   · pcall 不会抛错（引擎只记日志）⇒ 我的 fails=0 骗了我 ✗
-- 解法：把 16×27 拆成 **3 条行带**（每带 16×9 格）⇒ 每带串约 800~900 字符 ✓
--   每帧照常重算并赋值（只要不超限 ⇒ 不闪 ✓）—— 不需要预渲染、遮罩、切可见性 ✓
-- 对齐：Left + Top（每带左上角对齐 ⇒ 三条带能拼回完整火 ✓）
-- 尺寸：FONT=12（上一版按要求减半）

local PRE_TEXT = 1073741850
local COLS, ROWS = 16, 27
local SOURCE_ROWS, DECAY_MAX, EXPONENT, NLEV = 3, 3, 0.9, 25
local FONT = 20
local LEVELS = 6
local BANDS = 3
local BAND_ROWS = ROWS / BANDS          -- 9 行/带
local STEP_TICKS = 3                    -- 20fps
local SIZE_K = 1.10     -- <size> = FONT * SIZE_K : oversize glyph ink to close column gaps (paired with bh/step below)
local SCALE_X, SCALE_Y = 1.0, 1.0       -- 不缩放（用户口径：间距问题靠调字号解决）

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
local bands, heat, lastS = {}, {}, {}
local bw, bh = 0, 0

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

-- 一条行带的串（只含本带的 9 行 ✓ ⇒ 每带 ~900 字符 ✓）
local function build_band(b)
  local r0 = b * BAND_ROWS
  local r1 = r0 + BAND_ROWS - 1
  local parts, runs, open = {}, 0, false
  local function close()
    if open then parts[#parts + 1] = "</color>"; open = false end
  end
  for r = r0, r1 do
    if r > r0 then close(); parts[#parts + 1] = "\n" end
    local curQ = -1
    for c = 0, COLS - 1 do
      local q = qlevel(heat[idx(r, c)] or 1)
      if q == 0 then
        -- ★ 冷端用"黑色方块"占位（而不是空格）：行尾空格会被渲染器裁掉 ⇒ 各带宽度不一致 ⇒ 对不齐 ✗
        if curQ ~= 0 then
          close()
          parts[#parts + 1] = "<color=#00000000>"
          open, curQ = true, 0
          runs = runs + 1
        end
        parts[#parts + 1] = "█"
      else
        if q ~= curQ then
          close()
          local p = QPAL[q] or QPAL[1]
          parts[#parts + 1] = string.format("<color=#%02X%02X%02X>", p[1], p[2], p[3])
          open, curQ = true, q
          runs = runs + 1
        end
        parts[#parts + 1] = "█"
      end
    end
  end
  close()
  -- wrap band in <size> : ink overflows into neighbours so columns touch (paired with bh/step above)
  return "<size=" .. math.floor(FONT * SIZE_K) .. ">" .. table.concat(parts) .. "</size>", runs
end

local function mk_band(b, ox, oy)
  if builds >= 20 then return nil end
  local ok, c = pcall(game.InstantiateClientUIControl, PRE_TEXT, host)
  if not ok or c == nil then alive = false; return nil end
  builds = builds + 1
  point_anchor(c)
  t(function() c.name = "BAND" .. b end)
  t(function() c:SetSizeDelta(bw, bh) end)
  t(function() c:SetAnchoredPosition(ox, oy) end)
  t(function() c.fontSize = FONT end)
  local fc = rgb(255, 255, 255)
  if fc ~= nil then
    t(function() c.fontColor = fc end)
  end
  -- ★ 左上对齐：三条带各占一块，位置固定 ⇒ 拼回完整火 ✓
  t(function() c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle end)
  t(function() c.verticalAlignment = Enum.TextVerticalAlignment.Top end)   -- Top: never clip even if box is a hair short
  t(function() c.localScaleX = SCALE_X end)
  t(function() c.localScaleY = SCALE_Y end)
  t(function() c:SetActive(true) end)
  t(function() c:SetVisible(true) end)
  return c
end

function OnInit()
  say("boot v26（满格字形 + 按框尺寸居中）")
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
  bh = math.floor(BAND_ROWS * FONT * SIZE_K) + 8
  local step = math.floor(BAND_ROWS * FONT * 0.955 * SIZE_K)   -- band placement pitch (closes seams without shrinking the box)
  -- ★ 居中：按整团火的尺寸算左上角
  local totalW = bw
  local totalH = (BANDS - 1) * step + bh
  local baseX = math.floor(W * 0.5 - totalW * 0.5)
  local baseY = math.floor(H * 0.5 - totalH * 0.5)

  for b = 0, BANDS - 1 do
    -- y 向上 ⇒ 第 0 带（顶部行）放在最上面
    local oy = baseY + (BANDS - 1 - b) * step
    local c = mk_band(b, baseX, oy)
    bands[b + 1] = c
  end
  -- 首次赋值 + 记长度（确认每带都在上限内 ✓）
  local lens = {}
  for b = 1, BANDS do
    local s, runs = build_band(b - 1)
    lastS[b] = s
    lens[#lens + 1] = #s
    if bands[b] ~= nil then t(function() bands[b].text = s end) end
  end
  -- glyph candidate row (3 copies each, distinct colour): screenshot so ink width vs advance can be measured
  local cands = { '█', '▉', '▊', '▋', '▌', '▍', '■', '◼', '▮', '●' }
  local cols = { '#FF0000','#00FF00','#0000FF','#FFFF00','#FF00FF','#00FFFF','#FF8000','#8000FF','#FFFFFF','#808080' }
  local gp = {}
  for gi = 1, #cands do
    gp[#gp + 1] = '<color=' .. cols[gi] .. '>'
    for k = 1, 3 do gp[#gp + 1] = tostring(cands[gi]) end
    gp[#gp + 1] = '</color> '
  end
  local grow = mk_band(9, baseX, baseY + BANDS * bh + FONT)
  if grow ~= nil then t(function() grow.text = table.concat(gp) end) end
  say('glyph candidates = ' .. tostring(#cands))  say("canvas=" .. W .. "x" .. H .. " font=" .. FONT .. " bandWxH=" .. bw .. "x" .. bh
    .. " lens=" .. table.concat(lens, ",") .. " built=" .. builds .. " fails=" .. fails)
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1
  if tick > 3000 then
    say("stop tick=" .. tick .. " updates=" .. updates .. " fails=" .. fails)
    t(function() script:EnableUpdate(false) end)
    alive = false
    return
  end
  if dt == nil or dt <= 0 then return end
  if tick % STEP_TICKS ~= 0 then return end     -- 20fps

  updates = updates + 1
  stepFire()
  for b = 1, BANDS do
    local s = build_band(b - 1)
    if s ~= lastS[b] and bands[b] ~= nil then
      if t(function() bands[b].text = s end) then lastS[b] = s end
    end
  end
end
