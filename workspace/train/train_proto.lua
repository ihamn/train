-- train_proto.lua —— 「脏检查动画」验证版（照 zuma.lua 的核心做法）
--
-- 为什么这一版才是对的（zuma.lua 第 2276-2280 行的原话）：
--   动效**不用 game.Tween**，而是自己算，并且靠「**脏检查缓存**」——
--   **只在值和上次写进去的不一样时才调 API**，且位置**取整**。
--   整份 5,289 行里 SetAnchoredPosition 只有 6 处（都是包装函数），不是散落的每帧调用。
--
-- 前两版（v9 / v11）错在哪：**无条件每帧写** ⇒ 值没变也调、一帧一次 ⇒
--   引擎把每次调用/错误都记进日志 ⇒ 36,000 → 59,000 条 ⇒ 客户端被日志拖死。
--
-- 本版三条纪律：
--   ① 全程**只有 3 行日志**（boot / built / stop）—— 连刷屏的机会都没有
--   ② 位置**只在变化时写**、**取整**、**每 3 帧才尝试一次**（20Hz）
--   ③ 硬上限 180 帧直接 return（**不依赖 EnableUpdate 生效**）
--   另外：只用 zuma.lua 里扫出来的已验证方法，绝不碰 SetAnchorMin/SetAnchorMax/SetPivot

local PRE_IMAGE = 1073741852
local PRE_TEXT  = 1073741851
local ART_SQ, ART_CI = 100001, 100002

local HARD_TICKS = 180
local MOVE_EVERY = 3          -- 每 3 帧尝试移动一次（20Hz），别每帧都试
local X_FROM, X_TO = -500, 420

local host, W, H = nil, 1680, 900
local tick, builds, writes, fails, alive = 0, 0, 0, 0, true
local bg, mover, hud = nil, nil, nil
local lastX, lastY = nil, nil

local function say(s) if print then pcall(print, "TR " .. s) end end
local function t(fn) local ok = pcall(fn); if not ok then fails = fails + 1 end; return ok end

-- 建控件（字段/方法都 pcall，失败只计数）
local function mk(name, prefab, artId, color, text, ox, oy, w, h, fs)
  local ok, c = pcall(game.InstantiateClientUIControl, prefab, host)
  if not ok or c == nil then alive = false; return nil end
  builds = builds + 1
  t(function() c.name = name end)
  t(function() c:SetSizeDelta(w, h) end)              -- ★ 尺寸必须显式设
  t(function() c:SetAnchoredPosition(ox, oy) end)     -- ★ 位置只用这个方法
  if artId ~= nil then
    if not t(function() c:SetImage(Enum.ImageSource.StaticReference, artId) end) then
      t(function() c.imageId = artId end)             -- 兜底：字段形式
    end
  end
  if color ~= nil then t(function() c.imageColor = color end) end
  if text ~= nil then
    t(function() c.text = text end)
    t(function() c.fontSize = fs or 24 end)
    t(function() c.fontColor = 4294967295 end)
  end
  t(function() c:SetActive(true) end)
  t(function() c:SetVisible(true) end)                -- ★ 可见性只能调方法
  return c
end

-- ★★ 脏检查写入（本版的核心）★★
local function move_to(c, x, y)
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)     -- 取整：避免 0.3px 抖动也写
  if lastX == x and lastY == y then return end        -- 值没变 ⇒ **一次 API 都不调**
  if t(function() c:SetAnchoredPosition(x, y) end) then
    lastX, lastY = x, y
    writes = writes + 1
  end
end

-- HUD 文字**也走脏检查**（zuma 的做法）：只在数字变化时写
local lastHud = nil
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

  -- 只建 3 个控件：底 / 会动的块 / 一行文字（启动期不爆发）
  bg = mk("BG", PRE_IMAGE, ART_SQ, 4279242762, nil, 0, 0, W, H)
  mover = mk("MOVER", PRE_IMAGE, ART_CI, 4294901760, nil, X_FROM, 0, 160, 160)
  hud = mk("HUD", PRE_TEXT, nil, nil, "TR writes=0", 0, H * 0.5 - 70, 520, 44, 24)
  say("built=" .. builds .. " fails=" .. fails .. " canvas=" .. W .. "x" .. H)
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1
  if tick > HARD_TICKS then
    say("stop tick=" .. tick .. " writes=" .. writes .. " fails=" .. fails)
    t(function() script:EnableUpdate(false) end)
    alive = false
    return
  end
  if dt == nil or dt <= 0 then return end
  if tick % MOVE_EVERY ~= 0 then return end            -- 20Hz

  if mover ~= nil then
    local k = tick / HARD_TICKS
    move_to(mover, X_FROM + (X_TO - X_FROM) * k, 0)     -- 只在变化时写
    hud_text(hud, "TR writes=" .. writes)               -- 屏上自证（也走脏检查）
  end
end
