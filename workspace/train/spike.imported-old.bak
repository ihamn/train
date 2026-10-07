--[[ ===========================================================================
  spike.lua v9 —— M0 收口的「有界」版本

  v8 的真机事故（2026-10-07 客户端无响应）之后，本版把所有**可能卡死的结构**换成有界版本：

  ① 模板索引**写死**，不再扫描
     来源：2026-10-07 真机只读探针实测
       容器 = 1073741846（挂载点"容器节点"自己的模板索引）
       图片 = 1073741852、文本框 = 1073741851（zuma 工程的单控件模板）
     ⚠ 三个索引任一不可用 ⇒ **只打日志、直接返回**，不换区间、不重试
  ② 探测有界：写死候选表（每类 ≤2 个，合计 ≤6 次），每个实例化都配 Destroy 并计数
  ③ 魔数上限：总实例化预算 = 3(探测) + 1(容器) + 19(控件) = 23，超出即停止
  ④ OnUpdate 看门狗：tick > 300（约 5 秒）即 EnableUpdate(false) 并停止一切写入（自毁）
  ⑤ 建控件过程中任何一次失败 ⇒ 停止后续建造并打日志
  ⑥ **不碰挂载点几何**（不 SetAnchor*/SetPivot/SetAnchoredPosition/SetSizeDelta）
  ⑦ 不使用**带轴参数的方法调用**（v8 里 GetAnchorMin(1) 这类是首要嫌疑，已全删；
     y 分量改为尝试读**字段** anchorMinY/anchorMaxY/pivotY —— 字段读失败只是 nil，不会挂）

  阶梯式验证（docs/tech-architecture.md §7、records/playtest.md 第七轮）：
    台阶②（默认 USE_OWN_CONTAINER=false）：控件直接挂挂载点下 —— 真机已验证安全（v5），代价是坐标偏
    台阶③（USE_OWN_CONTAINER=true）：再加自建容器 —— v8 死在这一步，本版去掉嫌疑调用后重试
=========================================================================== ]]

-- ★ 台阶开关：先跑"已验证安全"的②，绿了再翻 true 试③
local USE_OWN_CONTAINER = false

local FRAME_COUNT = 6
local FRAME_INTERVAL = 0.12
local MOVE_PER_TICK = 10
local GROW_PER_TICK = 4
local MAX_TICKS = 300
local MAX_PROBES = 6            -- 候选表合计上限（3 类 × 2 候选）
-- 控件数量：18 个图片（BG/道砟/双轨/6 轨枕/车厢/车头/6 帧）+ 1 个文本框 = 19，再加可能的自建容器 = 20
-- （教训：v5/v6 里的 `#frames + 9 = 15` 是**错算术**，实际上限必须按真实数量给，否则会被截断）
local MAX_BUILD = 20

-- 写死的候选索引（无区间扫描）：[1] = 真机实测（2026-10-07 只读探针），
-- [2] = 模拟器工程（生成器分配，用于无头回归）。每类最多试 2 个，合计探测 ≤6 次，
-- 每次建完立即销毁并计数，总数打进日志。
local TPL_CAND = {
  image = { 1073741852, 1073742003 },
  text = { 1073741851, 1073742004 },
  container = { 1073741846, 1073742005 },
}

local parts, frames, missing = {}, {}, {}
local loco, wagon, hud = nil, nil, nil
local canvasW, canvasH = 1280, 720
local tick, idx, ticksPerFrame = 0, 0, 0
local n_probe, n_destroy, n_build = 0, 0, 0
local alive = true

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

local function pin(c, x, y, w, h)
  try("anchorMin", function() c:SetAnchorMin(0, 0) end)
  try("anchorMax", function() c:SetAnchorMax(0, 0) end)
  try("pivot", function() c:SetPivot(0, 0) end)
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
    print("M0 build abort at " .. name .. " (instantiate failed)")
    alive = false
    return nil
  end
  n_build = n_build + 1
  try("name", function() c.name = name end)
  pin(c, x, y, w, h)
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
    print("M0 build abort at " .. name .. " (instantiate failed)")
    alive = false
    return nil
  end
  n_build = n_build + 1
  try("name", function() c.name = name end)
  pin(c, x, y, w, h)
  try("text", function() c.text = text end)
  show_only(c, true)
  parts[name] = c
  return c
end

-- 有界探测：只试写死的 3 个索引，每个建完立刻销毁并计数
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

local function apply_frame(i)
  for k = 1, FRAME_COUNT do
    show_only(frames[k], k - 1 == i)
  end
  if hud ~= nil then
    try("hud.text", function() hud.text = "M0 frame=" .. i end)
  end
end

function OnInit()
  print("M0 boot")
  local okColon, errColon = pcall(function() script:EnableUpdate(true) end)
  print("M0 enableUpdate colon=" .. tostring(okColon) .. " err=" .. tostring(errColon))
  if not okColon then
    local okDot, errDot = pcall(function() script.EnableUpdate(script, true) end)
    print("M0 enableUpdate dot(self)=" .. tostring(okDot) .. " err=" .. tostring(errDot))
  end
end

function OnStart()
  local root = script.object
  if root == nil then
    print("M0 mount=nil -> 脚本没挂在客户端控件上")
    return
  end

  local cw, ch = game.GetUICanvasSize()
  canvasW = cw or 1280
  canvasH = ch or 720
  print("M0 canvas=" .. tostring(cw) .. "x" .. tostring(ch))
  print("M0 roots=" .. tostring(#game.GetClientUIRoots()))
  print("M0 mode=" .. (USE_OWN_CONTAINER and "own-container" or "mount-children"))

  print("M0 mount untouched type=" .. tostring(typeof(root))
    .. " name='" .. tostring(root.name) .. "'"
    .. " prefab=" .. tostring(root.prefabIndex)
    .. " size=" .. tostring(root.sizeDeltaX) .. "x" .. tostring(root.sizeDeltaY)
    .. " pos=" .. tostring(root.anchoredPositionX) .. "," .. tostring(root.anchoredPositionY))

  -- y 分量：只试字段（读不到是 nil，不会挂），不再用带轴参数的方法调用
  local aMinY = read_num(root, "anchorMinY")
  local aMaxY = read_num(root, "anchorMaxY")
  local pivY = read_num(root, "pivotY")
  print("M0 yfields anchorMinY=" .. tostring(aMinY) .. " anchorMaxY=" .. tostring(aMaxY)
    .. " pivotY=" .. tostring(pivY) .. " (nil=不可读，用 0/0/0.5 假设)")

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
    .. " -> image=" .. tostring(found.image) .. " text=" .. tostring(found.text)
    .. " container=" .. tostring(found.container))
  if found.image == nil or found.text == nil then
    print("M0 abort: 写死的模板索引不可用（不扫描、不重试）")
    alive = false
    return
  end

  parts.STAGE = root
  if USE_OWN_CONTAINER then
    if found.container == nil then
      print("M0 abort: 需要容器模板但不可用")
      alive = false
      return
    end
    local okC, cont = pcall(game.InstantiateClientUIControl, found.container, root)
    if not okC or cont == nil then
      print("M0 abort: 自建容器失败")
      alive = false
      return
    end
    n_build = n_build + 1
    try("container.name", function() cont.name = "M0_ROOT" end)
    -- 坐标补偿：只读**已验证安全**的读法 —— 无参 GetAnchorMin/GetAnchorMax/GetPivot（真机只读探针跑过）
    -- 加字段 sizeDeltaX/Y（真机可读）与可选的 anchorMinY/anchorMaxY/pivotY 字段。
    -- 拉伸轴（aMin ≠ aMax）上 pivot 不参与：矩形 = [aMin*W + pos, aMax*W + pos + sizeDelta]。
    local aMinX, aMaxX, pivX = 0, 1, 0.5
    local okA, vA = pcall(function() return root:GetAnchorMin() end)
    if okA and type(vA) == "number" then aMinX = vA end
    local okB, vB = pcall(function() return root:GetAnchorMax() end)
    if okB and type(vB) == "number" then aMaxX = vB end
    local okP, vP = pcall(function() return root:GetPivot() end)
    if okP and type(vP) == "number" then pivX = vP end
    local aMinY = read_num(root, "anchorMinY") or 0
    local aMaxY = read_num(root, "anchorMaxY") or 0
    local pivY = read_num(root, "pivotY") or 0.5
    local sizeX = read_num(root, "sizeDeltaX") or 0
    local sizeY = read_num(root, "sizeDeltaY") or 0
    local posX = read_num(root, "anchoredPositionX") or 0
    local posY = read_num(root, "anchoredPositionY") or 0
    local mW = (aMaxX - aMinX) * canvasW + sizeX
    local mH = (aMaxY - aMinY) * canvasH + sizeY
    local mLeft, mBottom
    if aMaxX ~= aMinX then mLeft = aMinX * canvasW + posX else mLeft = aMinX * canvasW + posX - mW * pivX end
    if aMaxY ~= aMinY then mBottom = aMinY * canvasH + posY else mBottom = aMinY * canvasH + posY - mH * pivY end
    print("M0 calc mountWxH=" .. tostring(mW) .. "x" .. tostring(mH)
      .. " mountLeftBottom=" .. tostring(mLeft) .. "," .. tostring(mBottom)
      .. " containerPos=" .. tostring(-mLeft) .. "," .. tostring(-mBottom)
      .. " | aMin=" .. tostring(aMinX) .. "," .. tostring(aMinY)
      .. " aMax=" .. tostring(aMaxX) .. "," .. tostring(aMaxY)
      .. " pivot=" .. tostring(pivX) .. "," .. tostring(pivY))
    try("container.anchorMin", function() cont:SetAnchorMin(0, 0) end)
    try("container.anchorMax", function() cont:SetAnchorMax(0, 0) end)
    try("container.pivot", function() cont:SetPivot(0, 0) end)
    try("container.SetSizeDelta", function() cont:SetSizeDelta(canvasW, canvasH) end)
    try("container.SetAnchoredPosition", function() cont:SetAnchoredPosition(-mLeft, -mBottom) end)
    show_only(cont, true)
    parts.STAGE = cont
    print("M0 own root type=" .. tostring(typeof(cont))
      .. " size=" .. tostring(cont.sizeDeltaX) .. "x" .. tostring(cont.sizeDeltaY)
      .. " pos=" .. tostring(cont.anchoredPositionX) .. "," .. tostring(cont.anchoredPositionY))
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
  hud = new_text(found.text, "HUD", 20, 640, 600, 40, "M0 frame=0")

  tick, idx, ticksPerFrame = 0, 0, 0
  apply_frame(0)
  print("M0 budget probes=" .. n_probe .. " destroyed=" .. n_destroy .. " built=" .. n_build
    .. " (cap " .. (MAX_PROBES + 1 + MAX_BUILD) .. ")")
  print("M0 start built=" .. tostring(n_build) .. " missing=" .. #missing
    .. (#missing > 0 and (" list=" .. table.concat(missing, ",")) or ""))
  print("M0 mount after size=" .. tostring(root.sizeDeltaX) .. "x" .. tostring(root.sizeDeltaY)
    .. " pos=" .. tostring(root.anchoredPositionX) .. "," .. tostring(root.anchoredPositionY))
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1

  if tick > MAX_TICKS then
    print("M0 watchdog stop at tick=" .. tick .. " (self-disable)")
    pcall(function() script:EnableUpdate(false) end)
    alive = false
    return
  end

  if loco == nil then return end

  if ticksPerFrame == 0 then
    ticksPerFrame = math.max(1, math.floor(FRAME_INTERVAL / dt + 0.5))
  end
  local nextIdx = math.floor(tick / ticksPerFrame) % FRAME_COUNT
  if nextIdx ~= idx then
    idx = nextIdx
    apply_frame(idx)
    print("M0 frame idx=" .. idx)
  end

  local wantX = 100 + MOVE_PER_TICK * tick
  local wantW = 120 + GROW_PER_TICK * tick
  try("loco.SetAnchoredPosition", function() loco:SetAnchoredPosition(wantX, 400) end)
  try("wagon.SetSizeDelta", function() wagon:SetSizeDelta(wantW, 70) end)

  if tick == 1 or tick % 15 == 0 then
    local gx, gw = "?", "?"
    local okx, vx = pcall(function() return loco.anchoredPositionX end)
    if okx then gx = tostring(vx) end
    local okw, vw = pcall(function() return wagon.sizeDeltaX end)
    if okw then gw = tostring(vw) end
    print("M0 update tick=" .. tick .. " x=" .. gx .. "/" .. tostring(wantX)
      .. " w=" .. gw .. "/" .. tostring(wantW))
  end
end
