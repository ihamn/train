-- spike.lua —— v14「正确模板索引版」
--
-- 上一版日志实测（真机）：
--   锚点字段写入成功 ✓  min=(0,0) max=(0,0) pivot=(0,0)
--   几何完全正确 ✓      BG 1719.8x900 @0,0 / MOVER 140x140 @40
--   动画真的在动 ✓      stop tick=241 writes=80 mover.x=1560
--   唯一错的是**模板索引**：
--     1073741852 → ClientUICursorEventAreaControl（光标检测区，不画东西 ✗）
--     1073741851 → ClientUIImageControl（★ 这才是图片 ✓）
--     文本框在新关卡里没找到（1073742004 实例化失败）✗
--
-- v14 只改两件事：
--   ① 图片统一用 1073741851（实测的图片控件）⇒ 底/方块立刻可见
--   ② 文本框：有界探测一段索引，认出 ClientUITextBoxControl 才建 HUD；认不到就跳过
--      （绝不再对着图片控件写 80 次 text ✗）
-- 其余全部保留：锚点字段、Color.FromRGBA、脏检查写入、硬上限、全程 pcall、日志有界

local PRE_IMAGE_CAND = { 1073741851, 1073741852, 1073742003 }
local TEXT_SCAN_FROM, TEXT_SCAN_TO = 1073741845, 1073741870
local ART_SQ, ART_CI = 100001, 100002

local HARD_TICKS = 240
local MOVE_EVERY = 3
local MAX_BUILD = 24
local MAX_TEXTPROBE = 20

local host, W, H = nil, 1719, 900
local tick, builds, writes, fails, alive = 0, 0, 0, 0, true
local bg, mover, hud = nil, nil, nil
local lastX, lastY, lastHud = nil, nil, nil
local seenKinds, probes = {}, 0

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
local function set_point_anchor(c)
  t(function() c.anchorMinX = 0 end); t(function() c.anchorMinY = 0 end)
  t(function() c.anchorMaxX = 0 end); t(function() c.anchorMaxY = 0 end)
  t(function() c.pivotX = 0 end);     t(function() c.pivotY = 0 end)
end

-- 有界探测：找图片模板（优先实测那个）与文本框模板
local function find_image()
  for i = 1, #PRE_IMAGE_CAND do
    local ok, c = pcall(game.InstantiateClientUIControl, PRE_IMAGE_CAND[i], host)
    if ok and c ~= nil then
      local k = type_of(c)
      seenKinds[#seenKinds + 1] = PRE_IMAGE_CAND[i] .. "=" .. k
      pcall(function() game.DestroyClientUIControl(c) end)
      if k == "ClientUIImageControl" then return PRE_IMAGE_CAND[i], k end
    end
  end
  return PRE_IMAGE_CAND[1], nil
end
local function find_text()
  for p = TEXT_SCAN_FROM, TEXT_SCAN_TO do
    if probes >= MAX_TEXTPROBE then break end
    probes = probes + 1
    local ok, c = pcall(game.InstantiateClientUIControl, p, host)
    if ok and c ~= nil then
      local k = type_of(c)
      pcall(function() game.DestroyClientUIControl(c) end)
      if k == "ClientUITextBoxControl" then
        seenKinds[#seenKinds + 1] = p .. "=" .. k
        return p, k
      end
    end
  end
  return nil, nil
end

local function mk(name, prefab, artId, col, text, ox, oy, w, h, fs)
  if builds >= MAX_BUILD then return nil end
  local ok, c = pcall(game.InstantiateClientUIControl, prefab, host)
  if not ok or c == nil then alive = false; return nil end
  builds = builds + 1
  set_point_anchor(c)
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
    .. " got=" .. fnum(c, "sizeDeltaX") .. "x" .. fnum(c, "sizeDeltaY")
    .. " pos.x=" .. fnum(c, "anchoredPositionX"))
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

  local pImg, kImg = find_image()
  local pTxt = find_text()

  bg = mk("BG", pImg, ART_SQ, rgb(20, 32, 54, 255), nil, 0, 0, W, H)
  local yMid = math.floor(H * 0.5) - 70
  mover = mk("MOVER", pImg, ART_CI, rgb(230, 60, 60, 255), nil, 40, yMid, 140, 140)
  if pTxt ~= nil then
    hud = mk("HUD", pTxt, nil, nil, "TR writes=0", 0, H - 60, 520, 44, 24)
  end

  say("canvas=" .. W .. "x" .. H .. " built=" .. builds .. " fails=" .. fails
    .. " imageTpl=" .. tostring(pImg) .. "(" .. tostring(kImg) .. ")"
    .. " textTpl=" .. tostring(pTxt) .. " probes=" .. probes
    .. " kinds[" .. table.concat(seenKinds, " ") .. "]")
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
    move_to(mover, 40 + (W - 220) * (tick / HARD_TICKS), math.floor(H * 0.5) - 70)
    hud_text(hud, "TR writes=" .. writes)
  end
end
