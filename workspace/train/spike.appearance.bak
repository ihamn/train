-- spike.lua —— 「外观修复版」（照 zuma.lua 的已验证写法）
--
-- 上一版实测：不卡死 ✓ / 3 控件建成 ✓ / 几何写入 60 次全成功 ✓ / 日志 448 字节 ✓
--   但两个现象：① 屏上是「?」② 看不到动
-- 诊断：
--   ① 「?」= 图片没设上。zuma 注释原话：「不设 = 每个图片控件画成 ?」
--      ⇒ 本版用 typeof(c) 先认出控件类型，是图片控件才 SetImage；并打印类型
--   ② 「没动」= 调用成功但被布局吞掉 ⇒ 模板是**拉伸锚点**（0,0→1,1）：
--      SetSizeDelta(W,H) 变成「父尺寸+W×H」（比屏幕还大 ⇒ 满屏白），位移也被重算回去
--      ★ 脚本侧无法改锚点（SetAnchorMin/Max/Pivot 在平台上**不存在**）
--      ⇒ 必须在编辑器里把模板/挂载控件改成**点锚点**：anchorMin=anchorMax=(0,0)、pivot=(0,0)
--      本版的做法：写完几何后**回读真实值**打进日志，用证据判断布局有没有把它改回去
--
-- 颜色：zuma 用的是带 alpha 的 ColorValue（不是数字）⇒ 本版用 Color.FromRGBA(r,g,b,a)
-- 素材号：用你们实测表里验证过的 100001 方形 / 100002 圆形 / 100006 圆环

local PRE_IMAGE_CAND = { 1073741852, 1073742003 }   -- 图片模板候选（typeof 认）
local PRE_TEXT_CAND  = { 1073741851, 1073742004 }   -- 文本框模板候选

local ART_SQ, ART_CI, ART_RING = 100001, 100002, 100006

local HARD_TICKS = 240
local MOVE_EVERY = 3
local X_FROM, X_TO = -520, 420
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

-- 颜色：ColorValue（zuma 写法），失败降级为不设色
local function rgb(r, g, b, a)
  local ok, v = pcall(function() return Color.FromRGBA(r, g, b, a or 255) end)
  if ok and v ~= nil then return v end
  return nil
end

-- 认模板：用 typeof 判断到底实例出来的是什么
local function pick(cands, wantKind)
  for i = 1, #cands do
    local ok, c = pcall(game.InstantiateClientUIControl, cands[i], host)
    if ok and c ~= nil then
      local k = type_of(c)
      kindLog[#kindLog + 1] = cands[i] .. "=" .. k
      pcall(function() game.DestroyClientUIControl(c) end)
      if k == wantKind then return cands[i], k end
    end
  end
  return cands[1], nil
end

-- 建控件（外观全部 best-effort + 类型打点）
local function mk(name, prefab, artId, col, text, ox, oy, w, h, fs)
  if builds >= MAX_BUILD then return nil end
  local ok, c = pcall(game.InstantiateClientUIControl, prefab, host)
  if not ok or c == nil then alive = false; return nil end
  builds = builds + 1
  t(function() c.name = name end)
  t(function() c:SetSizeDelta(w, h) end)              -- ★ 尺寸
  t(function() c:SetAnchoredPosition(ox, oy) end)     -- ★ 位置
  if artId ~= nil then
    if not t(function() c:SetImage(Enum.ImageSource.StaticReference, artId) end) then
      t(function() c.imageId = artId end)             -- 兜底：字段形式
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
  -- ★ 回读真实值（用证据判断布局有没有把写入改回去）
  local gx, gy, gw = "?", "?", "?"
  local okx, vx = pcall(function() return c.anchoredPositionX end); if okx then gx = tostring(vx) end
  local oky, vy = pcall(function() return c.anchoredPositionY end); if oky then gy = tostring(vy) end
  local okw, vw = pcall(function() return c.sizeDeltaX end); if okw then gw = tostring(vw) end
  say("built " .. name .. " type=" .. type_of(c) .. " want=(" .. w .. "x" .. h .. ")"
    .. " got size.x=" .. gw .. " pos=(" .. gx .. "," .. gy .. ")")
  return c
end

local function move_to(c, x, y)
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)     -- 取整（zuma 的脏检查）
  if lastX == x and lastY == y then return end
  if t(function() c:SetAnchoredPosition(x, y) end) then
    lastX, lastY, writes = x, y, writes + 1
  end
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

  -- 只建 3 个：底 / 会动的块 / 一行文字
  local white = rgb(255, 255, 255, 255)
  local dark = rgb(20, 32, 54, 255)
  local red = rgb(230, 60, 60, 255)
  bg = mk("BG", pImg, ART_SQ, dark, nil, 0, 0, 400, 240)
  mover = mk("MOVER", pImg, ART_CI, red, nil, X_FROM, 0, 140, 140)
  hud = mk("HUD", pTxt, nil, nil, "TR writes=0", 0, H * 0.5 - 70, 520, 44, 24)

  say("built=" .. builds .. " fails=" .. fails .. " canvas=" .. W .. "x" .. H
    .. " types[" .. table.concat(kindLog, " ") .. "]")
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1
  if tick > HARD_TICKS then
    local rx = "?"
    if mover ~= nil then
      local ok, v = pcall(function() return mover.anchoredPositionX end); if ok then rx = tostring(v) end
    end
    say("stop tick=" .. tick .. " writes=" .. writes .. " fails=" .. fails .. " mover.x=" .. rx)
    t(function() script:EnableUpdate(false) end)
    alive = false
    return
  end
  if dt == nil or dt <= 0 then return end
  if tick % MOVE_EVERY ~= 0 then return end

  if mover ~= nil then
    local k = tick / HARD_TICKS
    move_to(mover, X_FROM + (X_TO - X_FROM) * k, 0)
    hud_text(hud, "TR writes=" .. writes)
  end
end
