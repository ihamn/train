-- spike.lua —— v15「模板普查 + 文本像素第一步」
--
-- 目的（回答文档里标 unknown 的那条：文本像素能否在运行时生成 HANDOFF §32 / tech-arch §129）：
--   ① 把新关卡里**能实例化的客户端控件模板**全列出来（索引 + typeof 类型）
--      ⇒ 找到**文本框**索引（没有它，textbox.text 这条路线一个字节都测不了）
--   ② 用找到的文本框测：纯文字能不能写入、能不能读回（这是"文本像素"的地基）
--   ③ 顺带保留已验证的"红块在动"（证明画面链路仍正常，不是白跑一趟）
--
-- 安全纪律（全部来自今天的血泪）：
--   分帧建控件（每帧 1~2 个）/ 硬上限 240 帧自停 / 全程 pcall / 日志按"成功项"聚合（不逐条刷屏）
--   锚点用**字段**（不是方法）/ 颜色用 Color.FromRGBA / 图片模板用实测的 1073741851

local SCAN_RANGES = { { 1073741840, 1073741880 }, { 1073742000, 1073742010 } }
local PRE_IMAGE = 1073741851            -- 实测 = ClientUIImageControl
local ART_SQ, ART_CI = 100001, 100002

local HARD_TICKS = 240
local MOVE_EVERY = 3
local MAX_BUILD = 24

local host, W, H = nil, 1719, 900
local tick, builds, writes, fails, probes, alive = 0, 0, 0, 0, 0, true
local bg, mover, box = nil, nil, nil
local lastX, lastY = nil, nil
local found, textboxIdx = {}, nil
local didSurvey, didText = false, false

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

-- ★ 模板普查：有界、逐索引、建完即销毁；只在发现"新类型"时记一行
local function survey()
  local seen = {}
  for r = 1, #SCAN_RANGES do
    for i = SCAN_RANGES[r][1], SCAN_RANGES[r][2] do
      probes = probes + 1
      local ok, c = pcall(game.InstantiateClientUIControl, i, host)
      if ok and c ~= nil then
        local k = type_of(c)
        pcall(function() game.DestroyClientUIControl(c) end)
        if seen[k] == nil then
          seen[k] = i
          found[#found + 1] = i .. "=" .. k
          if k == "ClientUITextBoxControl" and textboxIdx == nil then textboxIdx = i end
          say("tpl " .. i .. " = " .. k)          -- 每发现一种新类型才打一行
        end
      end
    end
  end
  say("survey done probes=" .. probes .. " kinds=" .. #found
    .. " textbox=" .. tostring(textboxIdx))
end

local function set_point_box(name, prefab, artId, col, ox, oy, w, h)
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
  t(function() c:SetActive(true) end)
  t(function() c:SetVisible(true) end)
  return c
end

-- ★ 文本测试：纯文字写入 + 读回（三种候选富文本写法各试一次，看哪种能原样读回）
local function text_test()
  if textboxIdx == nil then
    say("no textbox -> 文本像素路线暂无法测（先要找到文本框模板）")
    return
  end
  box = set_point_box("BOX", textboxIdx, nil, nil, 40, H - 160, 700, 120)
  if box == nil then return end
  t(function() box.fontSize = 24 end)
  local fc = rgb(255, 255, 255, 255)
  if fc ~= nil then t(function() box.fontColor = fc end) end

  local okW = t(function() box.text = "TR text ok 123" end)
  local got = "?"
  local okR, v = pcall(function() return box.text end)
  if okR and v ~= nil then got = tostring(v) end
  say("text write=" .. tostring(okW) .. " readback='" .. got .. "'")
end

local function move_to(c, x, y)
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  if lastX == x and lastY == y then return end
  if t(function() c:SetAnchoredPosition(x, y) end) then lastX, lastY, writes = x, y, writes + 1 end
end

function OnInit()
  say("boot v15 probe")
  t(function() script:EnableUpdate(true) end)
end

function OnStart()
  host = script.object
  if host == nil then say("no host"); alive = false; return end
  local ok, cw, ch = pcall(game.GetUICanvasSize)
  if ok and type(cw) == "number" and type(ch) == "number" then W, H = cw, ch end
  say("canvas=" .. W .. "x" .. H)
  -- 安全底 + 会动的块（证明画面链路仍正常）
  bg = set_point_box("BG", PRE_IMAGE, ART_SQ, rgb(20, 32, 54, 255), 0, 0, W, H)
  mover = set_point_box("MOVER", PRE_IMAGE, ART_CI, rgb(230, 60, 60, 255), 40, math.floor(H * 0.5), 140, 140)
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1
  if tick > HARD_TICKS then
    say("stop tick=" .. tick .. " writes=" .. writes .. " fails=" .. fails .. " probes=" .. probes)
    t(function() script:EnableUpdate(false) end)
    alive = false
    return
  end
  if dt == nil or dt <= 0 then return end

  -- 第 1 帧：普查模板；第 2 帧：文本测试（都只做一次，不循环）
  if not didSurvey then didSurvey = true; survey(); return end
  if didSurvey and not didText then didText = true; text_test(); return end

  if tick % MOVE_EVERY == 0 and mover ~= nil then
    move_to(mover, 40 + (W - 220) * (tick / HARD_TICKS), math.floor(H * 0.5))
  end
end
