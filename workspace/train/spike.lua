--[[ ===========================================================================
  spike.lua v8 —— M0 收口的「修复验证」版：**自建容器 + 按实测几何补偿**

  真机只读探针（2026-10-07）取到的事实：
    · 挂载点 script.object = ClientUIContainerControl，name=''，prefabIndex=1073741846
      sizeDelta = 380×1080，GetAnchorMin.x = 0，GetAnchorMax.x = 1（**水平拉伸**），GetPivot = 0.5
      ⇒ 解析矩形 2060×1080、左下角 (−1030,−540) ⇒ 与画布(1680×900)的可见交集只有左下角一块
      ⇒ 这既是 v5「有东西但偏了」的原因，也是 v5.3 试图"钉挂载点"却触发无响应的现场

  v8 的两条动作（对应 docs/tech-architecture.md §7 规则 1）：
    ① **自建容器**：InstantiateClientUIControl(1073741846, 挂载点) —— 容器模板索引是真机实测的
    ② **只钉自建容器**：锚点 (0,0)/(0,0)、pivot (0,0)、size = 画布尺寸、
       位置 = **画布原点 − 挂载点左下角**（挂载点原点在屏幕外，必须补偿，否则整块还是偏的）
    ③ 15 个控件全挂在自建容器下 ⇒ 坐标 = 干净的画布坐标
    ④ **一个动作都不碰挂载点**（不 SetAnchor*/SetPivot/SetAnchoredPosition/SetSizeDelta）

  几何补偿的算式（括号里是 2026-10-07 真机实测值，用于自检）：
    mW = canvasW*(anchorMaxX−anchorMinX) + sizeDeltaX      → 1680*(1−0)+380 = 2060
    mH = canvasH*(anchorMaxY−anchorMinY) + sizeDeltaY      → 900*0+1080     = 1080（y 锚点假设 0/0）
    mountLeft   = anchorMinX*canvasW + posX − mW*pivotX    → 0+0−1030 = −1030
    mountBottom = anchorMinY*canvasH + posY − mH*pivotY    → 0+0−540  = −540 （pivotY 假设 0.5）
    containerPos = (−mountLeft, −mountBottom)              → (+1030, +540)
  真机读不到 y 分量（GetAnchorMin/GetPivot 无参只返回 x），所以 y 锚点/pivot 是**假设**；
  但同一套算式在模拟器里能**复现**实测值（模拟器挂载点 1280×720、锚点 0/1、pivot 0.5 ⇒
  算出 mountLeft=−640，与实测 `STAGE.left=−640` 一致）⇒ 算式本身是对的，
  真机若看到整体上下偏移，只需按日志里的 `M0 calc` 行改一个假设值即可。
=========================================================================== ]]

local FRAME_COUNT = 6
local FRAME_INTERVAL = 0.12   -- 每帧停留秒数（v5 真机已验证的换帧节奏）
local MOVE_PER_TICK = 10      -- 车头每 tick 前进像素
local GROW_PER_TICK = 4       -- 车厢每 tick 变宽像素

-- 真机实测索引（只读探针 2026-10-07）
local TPL_DEVICE = { image = 1073741852, text = 1073741851, container = 1073741846 }
-- 模拟器工程的模板索引在这两个窄窗口里（认全即停）
local TPL_SCAN = { { 1073741845, 1073741870 }, { 1073741995, 1073742320 } }

local parts, frames, missing = {}, {}, {}
local loco, wagon, hud = nil, nil, nil
local canvasW, canvasH = 1280, 720
local tick, idx, ticksPerFrame = 0, 0, 0

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

-- 只用于**我们自己建的控件**：显式钉死几何，不依赖模板默认锚点/中心
local function pin(c, x, y, w, h)
  try("anchorMin", function() c:SetAnchorMin(0, 0) end)
  try("anchorMax", function() c:SetAnchorMax(0, 0) end)
  try("pivot", function() c:SetPivot(0, 0) end)
  try("SetSizeDelta", function() c:SetSizeDelta(w, h) end)
  try("SetAnchoredPosition", function() c:SetAnchoredPosition(x, y) end)
end

local function new_image(prefab, name, artId, x, y, w, h)
  local ok, c = pcall(game.InstantiateClientUIControl, prefab, parts.STAGE)
  if not ok or c == nil then
    note(name)
    return nil
  end
  try("name", function() c.name = name end)
  pin(c, x, y, w, h)
  try("SetImage", function() c:SetImage(Enum.ImageSource.StaticReference, artId) end)
  show_only(c, true)
  parts[name] = c
  return c
end

local function new_text(prefab, name, x, y, w, h, text)
  local ok, c = pcall(game.InstantiateClientUIControl, prefab, parts.STAGE)
  if not ok or c == nil then
    note(name)
    return nil
  end
  try("name", function() c.name = name end)
  pin(c, x, y, w, h)
  try("text", function() c.text = text end)
  show_only(c, true)
  parts[name] = c
  return c
end

-- 读挂载点几何（**只读**），算出它的左下角相对于画布的位置
-- 返回：mW, mH, left, bottom, 诊断字符串
local function measure_mount(root)
  local aMinX, aMaxX, pivotX = 0, 1, 0.5
  local posX = read_num(root, "anchoredPositionX") or 0
  local posY = read_num(root, "anchoredPositionY") or 0
  local sizeX = read_num(root, "sizeDeltaX") or 0
  local sizeY = read_num(root, "sizeDeltaY") or 0

  -- 尝试用带轴参数的方式读 y 分量（真机是否支持未知，读到就用，读不到就保留假设）
  local function try_axis(method, axis, label)
    local ok, v = pcall(function()
      local f = root[method]
      if f == nil then return nil end
      return f(root, axis)
    end)
    if ok and type(v) == "number" then
      print("M0 axis " .. label .. "=" .. tostring(v))
      return v
    end
    return nil
  end
  local yMin = try_axis("GetAnchorMin", 1, "anchorMinY@1") or try_axis("GetAnchorMin", "y", "anchorMinY@y")
  local yMax = try_axis("GetAnchorMax", 1, "anchorMaxY@1") or try_axis("GetAnchorMax", "y", "anchorMaxY@y")
  local yPivot = try_axis("GetPivot", 1, "pivotY@1") or try_axis("GetPivot", "y", "pivotY@y")

  local okMin, vMinX = pcall(function() return root:GetAnchorMin() end)
  if okMin and type(vMinX) == "number" then aMinX = vMinX end
  local okMax, vMaxX = pcall(function() return root:GetAnchorMax() end)
  if okMax and type(vMaxX) == "number" then aMaxX = vMaxX end
  local okPiv, vPivX = pcall(function() return root:GetPivot() end)
  if okPiv and type(vPivX) == "number" then pivotX = vPivX end

  local aMinY = yMin or 0
  local aMaxY = yMax or 0
  local pivotY = yPivot or 0.5
  local assumed = (yMin == nil or yMax == nil or yPivot == nil)

  -- ★ 拉伸轴（aMin ≠ aMax）上 **pivot 不参与**：矩形 = [aMin*W + pos, aMax*W + pos + sizeDelta]
  --   只有"点锚点"（aMin == aMax）才需要 pos − size*pivot。
  --   这条是模拟器实测逼出来的：挂载点 anchor 0→1（拉伸）、pivot 0.5、sizeDelta 0×0，
  --   按 pivot 减半会算出 left=−640，而实测 `STAGE.left = 0`（它本身就是画布矩形）。
  local mW = (aMaxX - aMinX) * canvasW + sizeX
  local mH = (aMaxY - aMinY) * canvasH + sizeY
  local left
  if aMaxX ~= aMinX then
    left = aMinX * canvasW + posX
  else
    left = aMinX * canvasW + posX - mW * pivotX
  end
  local bottom
  if aMaxY ~= aMinY then
    bottom = aMinY * canvasH + posY
  else
    bottom = aMinY * canvasH + posY - mH * pivotY
  end

  local diag = "aMin=" .. tostring(aMinX) .. "," .. tostring(aMinY)
    .. " aMax=" .. tostring(aMaxX) .. "," .. tostring(aMaxY)
    .. " pivot=" .. tostring(pivotX) .. "," .. tostring(pivotY)
    .. " size=" .. tostring(sizeX) .. "x" .. tostring(sizeY)
    .. " assumedY=" .. tostring(assumed)
  return mW, mH, left, bottom, diag
end

-- 认模板：先信真机实测索引（不扫），不成立才做窄窗口兜底
-- ⚠ 这里必须用**挂载点**当实例化父级：此时自建容器还不存在（parts.STAGE 仍为 nil），
--   传 nil 会让每一次实例化都失败（v8 首测踩到：probes=355 errs=355）。
local function instantiable(prefab, parent)
  local ok, c = pcall(game.InstantiateClientUIControl, prefab, parent)
  if not ok or c == nil then return nil end
  return c
end

local function kind_of(c)
  local ok, t = pcall(function() return typeof(c) end)
  if ok then return tostring(t) end
  return "?"
end

local function detect_templates(parent)
  local found = { image = nil, text = nil, container = nil }
  local probes, errs = 0, 0

  local function claim(prefab, parent)
    probes = probes + 1
    local c = instantiable(prefab, parent)
    if c == nil then
      errs = errs + 1
      return nil
    end
    local t = kind_of(c)
    pcall(function() game.DestroyClientUIControl(c) end)
    if t == "ClientUIImageControl" then return "image" end
    if t == "ClientUITextBoxControl" then return "text" end
    if t == "ClientUIContainerControl" then return "container" end
    return nil
  end

  local known = { { "image", TPL_DEVICE.image }, { "text", TPL_DEVICE.text }, { "container", TPL_DEVICE.container } }
  for i = 1, #known do
    local kind = claim(known[i][2], parent)
    if kind ~= nil and found[kind] == nil then found[kind] = known[i][2] end
  end

  if found.image == nil or found.text == nil or found.container == nil then
    for w = 1, #TPL_SCAN do
      local i = TPL_SCAN[w][1]
      while i <= TPL_SCAN[w][2] do
        if found.image ~= nil and found.text ~= nil and found.container ~= nil then break end
        local kind = claim(i, parent)
        if kind ~= nil and found[kind] == nil then found[kind] = i end
        i = i + 1
      end
    end
  end

  print("M0 tpl using image=" .. tostring(found.image) .. " text=" .. tostring(found.text)
    .. " container=" .. tostring(found.container) .. " probes=" .. probes .. " errs=" .. errs)
  return found
end

local function apply_frame(i)
  for k = 1, FRAME_COUNT do
    show_only(frames[k], k - 1 == i)
  end
  if hud ~= nil then
    try("hud.text", function() hud.text = "M0 frame=" .. i end)
  end
  print("M0 frame idx=" .. i)
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

  local roots = game.GetClientUIRoots()
  print("M0 roots=" .. tostring(#roots))

  -- 挂载点：**只读地记录**（这一版一个字都不写它）
  print("M0 mount untouched type=" .. tostring(typeof(root))
    .. " name='" .. tostring(root.name) .. "'"
    .. " prefab=" .. tostring(root.prefabIndex)
    .. " size=" .. tostring(root.sizeDeltaX) .. "x" .. tostring(root.sizeDeltaY)
    .. " pos=" .. tostring(root.anchoredPositionX) .. "," .. tostring(root.anchoredPositionY)
    .. " scale=" .. tostring(root.localScaleX) .. "x" .. tostring(root.localScaleY))

  local mW, mH, mLeft, mBottom, diag = measure_mount(root)
  print("M0 calc mountWxH=" .. tostring(mW) .. "x" .. tostring(mH)
    .. " mountLeftBottom=" .. tostring(mLeft) .. "," .. tostring(mBottom)
    .. " containerPos=" .. tostring(-mLeft) .. "," .. tostring(-mBottom)
    .. " | " .. diag)

  local tpl = detect_templates(root)
  if tpl.image == nil or tpl.text == nil or tpl.container == nil then
    print("M0 detect failed (image/text/container 必须都能实例化) -> 不建控件")
    return
  end

  -- ① 自建容器（挂载点只作为它的父级，不被写）
  local okC, cont = pcall(game.InstantiateClientUIControl, tpl.container, root)
  if not okC or cont == nil then
    print("M0 own container failed -> 不建控件（绝不用挂载点当布局父级，也不改它的几何）")
    return
  end
  try("container.name", function() cont.name = "M0_ROOT" end)
  -- ② 把容器左下角顶到画布左下角：位置 = 画布原点 − 挂载点左下角
  try("container.anchorMin", function() cont:SetAnchorMin(0, 0) end)
  try("container.anchorMax", function() cont:SetAnchorMax(0, 0) end)
  try("container.pivot", function() cont:SetPivot(0, 0) end)
  try("container.SetSizeDelta", function() cont:SetSizeDelta(canvasW, canvasH) end)
  try("container.SetAnchoredPosition", function() cont:SetAnchoredPosition(-mLeft, -mBottom) end)
  show_only(cont, true)
  parts.STAGE = cont
  print("M0 root built type=" .. tostring(typeof(cont))
    .. " size=" .. tostring(cont.sizeDeltaX) .. "x" .. tostring(cont.sizeDeltaY)
    .. " pos=" .. tostring(cont.anchoredPositionX) .. "," .. tostring(cont.anchoredPositionY))

  -- ③ 坐标 = 画布左下角
  new_image(tpl.image, "BG", 100001, 0, 0, canvasW, canvasH)
  new_image(tpl.image, "BALLAST", 100001, 0, 300, canvasW, 90)
  new_image(tpl.image, "RAIL_HI", 100001, 0, 370, canvasW, 8)
  new_image(tpl.image, "RAIL_LO", 100001, 0, 320, canvasW, 8)
  for i = 0, 5 do
    new_image(tpl.image, "TIE_" .. i, 100001, 130 + 180 * i, 300, 12, 90)
  end
  wagon = new_image(tpl.image, "WAGON", 100003, 320, 400, 120, 70)
  loco = new_image(tpl.image, "LOCO", 100002, 100, 400, 200, 70)
  for i = 0, FRAME_COUNT - 1 do
    frames[i + 1] = new_image(tpl.image, "F" .. i, 100001 + i, 900, 430, 140, 140)
  end
  hud = new_text(tpl.text, "HUD", 20, 640, 600, 40, "M0 frame=0")

  if #missing > 0 then
    print("M0 missing list=" .. table.concat(missing, ","))
  end

  tick, idx, ticksPerFrame = 0, 0, 0
  apply_frame(0)
  print("M0 start built=" .. tostring(#frames + 9) .. " missing=" .. #missing)

  -- ④ 收尾再读一次挂载点：证明它自始至终没被我们改过
  print("M0 mount after size=" .. tostring(root.sizeDeltaX) .. "x" .. tostring(root.sizeDeltaY)
    .. " pos=" .. tostring(root.anchoredPositionX) .. "," .. tostring(root.anchoredPositionY))
end

function OnUpdate(dt)
  tick = tick + 1

  if tick == 1 or tick % 30 == 0 then
    print("M0 update tick=" .. tick .. " loco=" .. tostring(loco ~= nil))
  end

  if loco == nil then
    return
  end

  if ticksPerFrame == 0 then
    ticksPerFrame = math.max(1, math.floor(FRAME_INTERVAL / dt + 0.5))
  end
  local nextIdx = math.floor(tick / ticksPerFrame) % FRAME_COUNT
  if nextIdx ~= idx then
    idx = nextIdx
    apply_frame(idx)
  end

  local wantX = 100 + MOVE_PER_TICK * tick
  local wantW = 120 + GROW_PER_TICK * tick
  try("loco.SetAnchoredPosition", function() loco:SetAnchoredPosition(wantX, 400) end)
  try("wagon.SetSizeDelta", function() wagon:SetSizeDelta(wantW, 70) end)

  if tick == 1 or tick % 30 == 0 then
    local gx, gw = "?", "?"
    local okx, vx = pcall(function() return loco.anchoredPositionX end)
    if okx then gx = tostring(vx) end
    local okw, vw = pcall(function() return wagon.sizeDeltaX end)
    if okw then gw = tostring(vw) end
    print("M0 writeback x=" .. gx .. " want=" .. tostring(wantX))
    print("M0 writeback w=" .. gw .. " want=" .. tostring(wantW))
  end

  if tick % 15 == 0 then
    print("M0 move k=" .. tick)
  end
end
