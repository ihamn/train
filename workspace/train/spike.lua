--[[ ===========================================================================
  spike.lua v10 —— 「脏检查 + 节流 + 日志纪律」版（卡死机制修正后的版本）

  ★ 卡死机制（2026-10-07 由 zuma.lua 第 2276–2280 行作者原话 + 另一个 AI 追查确认）：
    动效不要无条件每帧调 API —— 引擎会把每次调用记进日志，实测 36,000 → 59,000 条，
    **客户端被自己的日志拖死**（所以我们那几次卡死连 dump 都没留下：日志管道被灌死了）。
    zuma.lua 整份 5,289 行里 `SetAnchoredPosition` 只有 6 处，且都在包装函数里，
    条件是「**值变了才写**」+「**位置取整**」。

  本版三条纪律（缺一不可）：
    ① **脏检查**：位置/尺寸/文本只在**值真的变了**时才写；位置取整（去掉浮点抖动）
    ② **节流**：写操作每 3 帧才尝试一次（≈10Hz）；换帧只在帧号变化时切
    ③ **日志纪律**：全程只有 boot / 几行结构信息 / alive×3 / stop —— 绝不每帧打日志

  其它沿用 v9 的有界护栏：索引写死候选表（每类 ≤2、合计 ≤6 次探测，建完即销毁并计数）、
  总预算上限、看门狗自毁（tick > 300）、失败即返回不重试、不碰挂载点几何、
  **不调 SetAnchorMin/SetAnchorMax/SetPivot**（锚点/中心是编辑器侧属性，运行时改它们没意义；
  zuma.lua 全量扫描里 0 次使用）。

  HUD 用**多文本框排版**：文本框没有"行间距"参数（官方编辑器文档/客户端 API 文档/模拟器 schema
  三处都没有），所以行距 = 我们自己给的 y 差（相对量，不受模板锚点/中心影响）。
=========================================================================== ]]

local USE_OWN_CONTAINER = false

local FRAME_COUNT = 6
local FRAME_INTERVAL = 0.12
local MOVE_PER_TICK = 10
local GROW_PER_TICK = 4
local MAX_TICKS = 300
local WRITE_EVERY = 3              -- 写操作节流：每 3 帧一次（≈10Hz）
local ALIVE_AT = { 15, 60, 150 }   -- 只在这三个 tick 各打一行存活日志（不打第 4 行）
local MAX_PROBES = 6
local MAX_BUILD = 24

-- 多文本框 HUD：行距 = y 差
local HUD_X, HUD_Y0 = 20, 660
local HUD_W, HUD_H = 420, 26
local HUD_LINE_GAP = 30
local HUD_FONT_SIZE = 22
local HUD_LINES = 4

-- 写死的候选索引（真机实测 [1] / 模拟器工程 [2]），无区间扫描
local TPL_CAND = {
  image = { 1073741852, 1073742003 },
  text = { 1073741851, 1073742004 },
  container = { 1073741846, 1073742005 },
}

local parts, frames, missing = {}, {}, {}
local loco, wagon, hud = nil, nil, nil
local hud_lines = {}
local canvasW, canvasH = 1280, 720
local tick, idx, ticksPerFrame = 0, 0, 0
local n_probe, n_destroy, n_build = 0, 0, 0
local alive = true
-- 脏检查缓存（只在变化时写 API）
local lastx, lasty, lastw = nil, nil, nil

local function note(n) missing[#missing + 1] = n end

local function try(label, fn)
  local ok, err = pcall(fn)
  if not ok then print("M0 writefail " .. label .. " -> " .. tostring(err)) end
  return ok
end

local function read_num(obj, field)
  local ok, v = pcall(function() return obj[field] end)
  if ok and type(v) == "number" then return v end
  return nil
end

local function show_only(c, on)
  if c == nil then return end
  try("setActive", function() c:SetActive(on) end)
  try("setVisible", function() c:SetVisible(on) end)
end

-- 只改"位置 + 尺寸"（锚点/中心是编辑器属性，这里不碰）
local function place(c, x, y, w, h)
  try("SetSizeDelta", function() c:SetSizeDelta(w, h) end)
  try("SetAnchoredPosition", function() c:SetAnchoredPosition(x, y) end)
end

local function new_image(prefab, name, artId, x, y, w, h)
  if n_build >= MAX_BUILD then
    note(name .. "(budget)")
    return nil
  end
  local ok, c = pcall(game.InstantiateClientUIControl, prefab, parts.STAGE)
  if not ok or c == nil then
    note(name)
    print("M0 build abort at " .. name)
    alive = false
    return nil
  end
  n_build = n_build + 1
  try("name", function() c.name = name end)
  place(c, x, y, w, h)
  try("SetImage", function() c:SetImage(Enum.ImageSource.StaticReference, artId) end)
  show_only(c, true)
  parts[name] = c
  return c
end

local function new_text(prefab, name, x, y, w, h, text)
  if n_build >= MAX_BUILD then
    note(name .. "(budget)")
    return nil
  end
  local ok, c = pcall(game.InstantiateClientUIControl, prefab, parts.STAGE)
  if not ok or c == nil then
    note(name)
    print("M0 build abort at " .. name)
    alive = false
    return nil
  end
  n_build = n_build + 1
  try("name", function() c.name = name end)
  place(c, x, y, w, h)
  try("text", function() c.text = text end)
  show_only(c, true)
  parts[name] = c
  return c
end

local function probe_fixed_prefab(prefab, parent)
  if n_probe >= MAX_PROBES then return nil end
  n_probe = n_probe + 1
  local ok, c = pcall(game.InstantiateClientUIControl, prefab, parent)
  if not ok or c == nil then return nil end
  local okT, t = pcall(function() return typeof(c) end)
  local kind = okT and tostring(t) or "?"
  local okD = pcall(function() game.DestroyClientUIControl(c) end)
  if okD then n_destroy = n_destroy + 1 end
  if kind == "ClientUIImageControl" then return "image" end
  if kind == "ClientUITextBoxControl" then return "text" end
  if kind == "ClientUIContainerControl" then return "container" end
  return nil
end

-- 换帧：只在帧号变化时切换（不是每帧都写 active）
local n_frame_log = 0   -- 换帧留痕上限：只记前 3 次（日志纪律：全程行数有界）
local function apply_frame(i)
  for k = 1, FRAME_COUNT do
    show_only(frames[k], k - 1 == i)
  end
  if hud_lines[3] ~= nil then
    try("hud2", function() hud_lines[3].text = "FRAME " .. i .. " / " .. FRAME_COUNT end)
  end
  if n_frame_log < 3 then
    n_frame_log = n_frame_log + 1
    print("M0 frame " .. i)
  end
end

function OnInit()
  print("M0 boot")
  local okColon, errColon = pcall(function() script:EnableUpdate(true) end)
  if not okColon then
    local okDot, errDot = pcall(function() script.EnableUpdate(script, true) end)
    if not okDot then print("M0 enableUpdate failed " .. tostring(errDot)) end
  end
end

function OnStart()
  local root = script.object
  if root == nil then
    print("M0 mount=nil")
    return
  end

  local cw, ch = game.GetUICanvasSize()
  canvasW = cw or 1280
  canvasH = ch or 720
  print("M0 canvas=" .. tostring(cw) .. "x" .. tostring(ch)
    .. " mode=" .. (USE_OWN_CONTAINER and "own" or "mount"))
  print("M0 mount type=" .. tostring(typeof(root))
    .. " name='" .. tostring(root.name) .. "'"
    .. " prefab=" .. tostring(root.prefabIndex)
    .. " size=" .. tostring(root.sizeDeltaX) .. "x" .. tostring(root.sizeDeltaY)
    .. " pos=" .. tostring(root.anchoredPositionX) .. "," .. tostring(root.anchoredPositionY))

  local found = {}
  local kinds = { "image", "text", "container" }
  for i = 1, #kinds do
    local kind = kinds[i]
    local cands = TPL_CAND[kind]
    for c = 1, #cands do
      if found[kind] == nil and n_probe < MAX_PROBES then
        local got = probe_fixed_prefab(cands[c], root)
        if got == kind then found[kind] = cands[c] end
      end
    end
  end
  print("M0 probes=" .. n_probe .. " destroyed=" .. n_destroy
    .. " image=" .. tostring(found.image) .. " text=" .. tostring(found.text))
  if found.image == nil or found.text == nil then
    print("M0 abort: 写死的模板索引不可用（不扫描、不重试）")
    alive = false
    return
  end

  parts.STAGE = root
  if USE_OWN_CONTAINER then
    if found.container == nil then
      print("M0 abort: no container template")
      alive = false
      return
    end
    local okC, cont = pcall(game.InstantiateClientUIControl, found.container, root)
    if not okC or cont == nil then
      print("M0 abort: own container failed")
      alive = false
      return
    end
    n_build = n_build + 1
    try("container.name", function() cont.name = "M0_ROOT" end)
    place(cont, 0, 0, canvasW, canvasH)
    show_only(cont, true)
    parts.STAGE = cont
  end

  new_image(found.image, "BG", 100001, 0, 0, canvasW, canvasH)
  new_image(found.image, "BALLAST", 100001, 0, 300, canvasW, 90)
  new_image(found.image, "RAIL_HI", 100001, 0, 370, canvasW, 8)
  new_image(found.image, "RAIL_LO", 100001, 0, 320, canvasW, 8)
  for i = 0, 5 do
    new_image(found.image, "TIE_" .. i, 100001, 130 + 180 * i, 300, 12, 90)
  end
  wagon = new_image(found.image, "WAGON", 100003, 320, 400, 120, 70)
  loco = new_image(found.image, "LOCO", 100002, 100, 400, 200, 70)
  for i = 0, FRAME_COUNT - 1 do
    frames[i + 1] = new_image(found.image, "F" .. i, 100001 + i, 900, 430, 140, 140)
  end

  hud_lines = {}
  for i = 0, HUD_LINES - 1 do
    local t = new_text(found.text, "HUD_L" .. i, HUD_X, HUD_Y0 - i * HUD_LINE_GAP, HUD_W, HUD_H, "")
    if t ~= nil then
      try("hud.fontSize", function() t.fontSize = HUD_FONT_SIZE end)
      hud_lines[i + 1] = t
    end
  end
  hud = hud_lines[1]
  if hud_lines[1] ~= nil then
    try("hud0", function() hud_lines[1].text = "GEAR +2   SPEED 068" end)
  end
  if hud_lines[2] ~= nil then
    try("hud1", function() hud_lines[2].text = "AXLE 40%  TEMP OK" end)
  end
  if hud_lines[4] ~= nil then
    try("hud3", function() hud_lines[4].text = "LINE GAP " .. HUD_LINE_GAP .. "px by y diff" end)
  end
  print("M0 hud lines=" .. #hud_lines .. " gap=" .. HUD_LINE_GAP .. " y0=" .. HUD_Y0)

  tick, idx, ticksPerFrame = 0, 0, 0
  lastx, lasty, lastw = nil, nil, nil
  apply_frame(0)
  print("M0 built=" .. tostring(n_build) .. " missing=" .. #missing
    .. " cap=" .. tostring(MAX_PROBES + 1 + MAX_BUILD))
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1

  -- 看门狗：无论 EnableUpdate 是否生效，靠 tick 自毁
  if tick > MAX_TICKS then
    print("M0 stop tick=" .. tick)
    pcall(function() script:EnableUpdate(false) end)
    alive = false
    return
  end

  -- 日志纪律：全程只有这几行
  if tick == ALIVE_AT[1] or tick == ALIVE_AT[2] or tick == ALIVE_AT[3] then
    print("M0 alive " .. tick)
  end

  if loco == nil then return end
  if tick % WRITE_EVERY ~= 0 then return end        -- ② 节流

  if ticksPerFrame == 0 then
    ticksPerFrame = math.max(1, math.floor(FRAME_INTERVAL / dt + 0.5))
  end
  local nextIdx = math.floor(tick / ticksPerFrame) % FRAME_COUNT
  if nextIdx ~= idx then                            -- ① 脏检查
    idx = nextIdx
    apply_frame(idx)
  end

  -- ① 脏检查 + 取整：值没变就不调 API（这就是 zuma 的做法）
  local wantX = math.floor(100 + MOVE_PER_TICK * tick + 0.5)
  local wantY = 400
  local wantW = math.floor(120 + GROW_PER_TICK * tick + 0.5)
  if lastx ~= wantX or lasty ~= wantY then
    lastx, lasty = wantX, wantY
    try("loco.pos", function() loco:SetAnchoredPosition(wantX, wantY) end)
  end
  if lastw ~= wantW then
    lastw = wantW
    try("wagon.size", function() wagon:SetSizeDelta(wantW, 70) end)
  end
end
