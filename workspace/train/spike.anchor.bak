-- spike.lua —— 「锚点字段版」（zuma 的正确用法：锚点/轴心是**字段**，位置/尺寸是**方法**）
--
-- 前几版的错误与修正：
--   ✗ c:SetAnchorMin/SetAnchorMax/SetPivot  → **方法不存在**，pcall 静默失败 ⇒ 模板保持拉伸锚点
--        ⇒ SetSizeDelta(W,H) 变成「父尺寸+W×H」（满屏白）、位移被布局重算（日志写着写了，画面没动）
--   ✓ zuma 的做法：**字段赋值** anchorMinX/Y、anchorMaxX/Y、pivotX/Y（只读探针在真机上成功读到这几个字段）
--   其余保持：typeof() 认模板、Color.FromRGBA 颜色、实测素材号 100001/100002、脏检查写入、硬上限、全程 pcall
--
-- 日志有界（约 5 行）：boot / built×3（含锚点与尺寸回读）/ stop

local PRE_IMAGE_CAND = { 1073741852, 1073742003 }
local PRE_TEXT_CAND  = { 1073741851, 1073742004 }
local ART_SQ, ART_CI = 100001, 100002

local HARD_TICKS = 240
local MOVE_EVERY = 3
local MAX_BUILD = 24

local host, W, H = nil, 1719, 900
local tick, builds, writes, fails, alive = 0, 0, 0, 0, true
local bg, mover, hud = nil, nil, nil
local lastX, lastY, lastHud = nil, nil, nil
local kindLog = {}

local function say(s) if print then pcall(print, "TR " .. s) end end
local function t(fn) local ok = pcall(fn); if not ok then fails = fails + 1 end; return ok end
local function type_of(c)
  local ok, v = pcall(function() return typeof(c) end)
  if ok and v ~= nil then return tostring(v) end
  return "?"
end
local function rgb(r, g, b, a)
  local ok, v = pcall(function() return Color.FromRGBA(r, g, b, a or 255) end)
  if ok and v ~= nil then return v end
  return nil
end
local function fnum(c, f)
  local ok, v = pcall(function() return c[f] end)
  if ok and v ~= nil then return tostring(v) end
  return "?"
end

-- ★★ 关键：锚点/轴心用**字段**，把拉伸锚点改成点锚点（左上角为参照）
local function set_point_anchor(c, px, py)
  px = px or 0; py = py or 0
  t(function() c.anchorMinX = px end); t(function() c.anchorMinY = py end)
  t(function() c.anchorMaxX = px end); t(function() c.anchorMaxY = py end)
  t(function() c.pivotX = px end);     t(function() c.pivotY = py end)
end
local function anchor_str(c)
  return "min=(" .. fnum(c, "anchorMinX") .. "," .. fnum(c, "anchorMinY") .. ")"
    .. " max=(" .. fnum(c, "anchorMaxX") .. "," .. fnum(c, "anchorMaxY") .. ")"
    .. " pivot=(" .. fnum(c, "pivotX") .. "," .. fnum(c, "pivotY") .. ")"
end

local function pick(cands, wantKind)
  for i = 1, #cands do
    local ok, c = pcall(game.InstantiateClientUIControl, cands[i], host)
    if ok and c ~= nil then
      local k = type_of(c)
      kindLog[#kindLog + 1] = cands[i] .. "=" .. k
      pcall(function() game.DestroyClientUIControl(c) end)
      if k == wantKind then return cands[i] end
    end
  end
  return cands[1]
end

local function mk(name, prefab, artId, col, text, ox, oy, w, h, fs)
  if builds >= MAX_BUILD then return nil end
  local ok, c = pcall(game.InstantiateClientUIControl, prefab, host)
  if not ok or c == nil then alive = false; return nil end
  builds = builds + 1
  set_point_anchor(c, 0, 0)                               -- ★ 先改锚点，再定位/定尺寸
  t(function() c.name = name end)
  t(function() c:SetSizeDelta(w, h) end)
  t(function() c:SetAnchoredPosition(ox, oy) end)
  if artId ~= nil then
    if not t(function() c:SetImage(Enum.ImageSource.StaticReference, artId) end) then
      t(function() c.imageId = artId end)
    end
  end
  if col ~= nil then t(function() c.imageColor = col end) end
  if text ~= nil then
    t(function() c.text = text end)
    t(function() c.fontSize = fs or 24 end)
    local fc = rgb(255, 255, 255, 255)
    if fc ~= nil then t(function() c.fontColor = fc end) end
  end
  t(function() c:SetActive(true) end)
  t(function() c:SetVisible(true) end)
  say("built " .. name .. " type=" .. type_of(c) .. " want=" .. w .. "x" .. h
    .. " got size.x=" .. fnum(c, "sizeDeltaX") .. " pos.x=" .. fnum(c, "anchoredPositionX")
    .. " " .. anchor_str(c))
  return c
end

local function move_to(c, x, y)
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  if lastX == x and lastY == y then return end
  if t(function() c:SetAnchoredPosition(x, y) end) then lastX, lastY, writes = x, y, writes + 1 end
end
local function hud_text(c, s)
  if c == nil or lastHud == s then return end
  if t(function() c.text = s end) then lastHud = s end
end

function OnInit()
  say("boot")
  t(function() script:EnableUpdate(true) end)
end

function OnStart()
  host = script.object
  if host == nil then say("no host"); alive = false; return end
  local ok, cw, ch = pcall(game.GetUICanvasSize)
  if ok and type(cw) == "number" and type(ch) == "number" then W, H = cw, ch end

  local pImg = pick(PRE_IMAGE_CAND, "ClientUIImageControl")
  local pTxt = pick(PRE_TEXT_CAND, "ClientUITextBoxControl")

  -- 点锚点后坐标以**容器左下角**为原点：底铺满、方块在中线高度、文字贴顶
  bg = mk("BG", pImg, ART_SQ, rgb(20, 32, 54, 255), nil, 0, 0, W, H)
  local yMid = math.floor(H * 0.5)
  mover = mk("MOVER", pImg, ART_CI, rgb(230, 60, 60, 255), nil, 40, yMid - 70, 140, 140)
  hud = mk("HUD", pTxt, nil, nil, "TR writes=0", 0, H - 60, 520, 44, 24)

  say("canvas=" .. W .. "x" .. H .. " built=" .. builds .. " fails=" .. fails
    .. " types[" .. table.concat(kindLog, " ") .. "]")
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1
  if tick > HARD_TICKS then
    say("stop tick=" .. tick .. " writes=" .. writes .. " fails=" .. fails
      .. " mover.x=" .. (mover ~= nil and fnum(mover, "anchoredPositionX") or "?"))
    t(function() script:EnableUpdate(false) end)
    alive = false
    return
  end
  if dt == nil or dt <= 0 then return end
  if tick % MOVE_EVERY ~= 0 then return end
  if mover ~= nil then
    local x = 40 + (W - 200) * (tick / HARD_TICKS)
    move_to(mover, x, math.floor(H * 0.5) - 70)
    hud_text(hud, "TR writes=" .. writes)
  end
end
