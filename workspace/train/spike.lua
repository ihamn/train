-- workspace/train/spike.lua
-- 千星「列车」M0 平台前提探针 —— v5：改用**本工程 zuma 已验证的真机模式**
--
-- 为什么从"摆控件 + 按名字找"改成"运行时按模板建"：
--   1) 本工程的 UI 架构是**运行时实例化**（zuma.lua：InstantiateClientUIControl ×9，
--      GetChild/FindChild ×0），界面布局里不摆具名控件 ⇒ 按名字找必然 not-found；
--   2) 真机契约里可见性/图片相关字段大量**只读**（visible/imageId/imageSource/imageType），
--      必须走 SetVisible / SetImage；
--   3) 位置与尺寸在真机上用的是方法式 `SetAnchoredPosition` / `SetSizeDelta`
--      （zuma.lua 用了 6/8 次；字段式 `.anchoredPositionX =` 0 次 ⇒ 未经验证）。
--
-- 本文件里每条真机结论都来自本工程的实战记录（zuma.lua 注释，2026-09-25 真机）：
--   · game.InstantiateClientUIControl 在 OnInit 阶段返回 nil，只有 OnStart 及之后成功
--   · script:EnableUpdate 不开 = 没有 OnUpdate（冒号写法是对的）
--   · GetClientUIRoots() 返回"实际显示的客户端控件容器画布中的默认容器节点"，
--     为 0 表示运行时没有可见画布（容器没进界面布局 / 初始可见没勾 / 玩家应用布局不对）
--   · 挂载点 0×0 会把自己的子控件全部裁掉 → 表现是"脚本全跑通、屏幕全空"，需 SetSizeDelta
--   · 动态创建的图片控件**不继承模板图**，不 SetImage 就画成 "?"
--   · 模板索引是 2^30 起的大数字，可用 typeof() 探针自动识别（建完即销毁）
--   · 平台上限：单控件组 1000 / 单屏 10000
--   · 画布尺寸在真机是浮点，别用 string.format('%d')
--
-- 素材号 100001–100006 是**真实的官方素材号**（基础形状：方块/圆/三角/四角星/五角星/圆环），
-- 见 D:\moniji\千星素材号实测表.md。

local FRAME_COUNT = 6        -- F0..F5（六帧叠放，切换可见性）
local FRAME_INTERVAL = 0.12  -- 目标换帧间隔（秒），落地为整数 tick 分频
local MOVE_PER_TICK = 10     -- 车头每帧右移像素
local GROW_PER_TICK = 4      -- 车厢每帧变宽像素

local parts = {}             -- 名字 -> 控件（自己持引用，永不按名字找）
local frames = {}
local loco = nil
local wagon = nil
local hud = nil
local missing = {}
local tick = 0
local idx = 0
local ticksPerFrame = 0
local canvasW, canvasH = 1280, 720
local noteWriteOnce = {}

local function note(what)
  missing[#missing + 1] = what
end

-- 写一次失败就报一行，之后不再刷屏
local function try(label, fn)
  local ok, err = pcall(fn)
  if not ok and not noteWriteOnce[label] then
    noteWriteOnce[label] = true
    print("M0 writefail " .. label .. " err=" .. tostring(err))
  end
  return ok
end

-- 只读字段（visible 等）写会报；统一走方法。SetActive 失败退回 SetVisible。
local function show_only(c, on)
  if c == nil then return end
  if not try("SetActive", function() c:SetActive(on) end) then
    try("SetVisible", function() c:SetVisible(on) end)
  end
end

-- 自动认客户端控件模板：从 2^30 起扫，用 typeof 判类型，探针建完即销毁（不占控件数）
local function detect_templates(root)
  local found = {}
  if not (typeof and game.InstantiateClientUIControl and game.DestroyClientUIControl) then
    print("M0 detect SKIPPED (typeof/Instantiate/Destroy 不全)")
    return found
  end
  local BASE = 1073741824 -- 2^30：真机"客户端控件模板索引"的空间
  -- ⚠ 2026-10-06 真机卡死后收窄：只扫两个**已被实测确认**的窄窗口，认全就收工。
  --   真机实测点：图片 1073741852、文本框 1073741851（本工程 zuma 的模板）；
  --   模拟器/新建模板工程：1073742003/2004、1073742102/2101。
  --   上一版扫 2^30+1..+512（60~500 次建/销毁）嫌疑很大，这里改成 ~25 个索引上限。
  local ranges = { { 1073741845, 1073741870 }, { 1073741995, 1073742320 } }
  local probes, errs = 0, 0
  for r = 1, #ranges do
    for i = ranges[r][1], ranges[r][2] do
      if found.image and found.text then break end
      local ok, c = pcall(game.InstantiateClientUIControl, i, root)
      if ok and c then
        probes = probes + 1
        local t = tostring(typeof(c))
        if not found.image and t:find("Image", 1, true) then
          found.image = i
          found.imageType = t
        end
        if not found.text and t:find("TextBox", 1, true) then
          found.text = i
          found.textType = t
        end
        pcall(game.DestroyClientUIControl, c)
      else
        errs = errs + 1
      end
    end
  end
  print("M0 detect image=" .. tostring(found.image) .. " (" .. tostring(found.imageType) .. ")"
    .. " text=" .. tostring(found.text) .. " (" .. tostring(found.textType) .. ")"
    .. " probes=" .. probes .. " errs=" .. errs)
  return found
end

-- 几何一律显式钉死，且不依赖模板/挂载点的默认值。
-- mode：'lb' 固定左下角（锚点/中心都 (0,0)，SetAnchoredPosition = 画布左下角坐标）
--       'stretch' 双向铺满父矩形（offset 0、size 0）
--       'stretch-x' 水平铺满、纵向固定（SetAnchoredPosition.y 仍是底边距离）
-- 为什么要钉：模拟器与真机都实测过，运行时建出来的控件几何会跟着模板默认值飘。
local function pin_geometry(c, mode, x, y, w, h)
  try("anchorMin", function() c:SetAnchorMin(0, 0) end)
  if mode == 'stretch' then
    try("anchorMax", function() c:SetAnchorMax(1, 1) end)
    try("pivot", function() c:SetPivot(0, 0) end)
    try("SetSizeDelta", function() c:SetSizeDelta(0, 0) end)
    try("SetAnchoredPosition", function() c:SetAnchoredPosition(0, 0) end)
  elseif mode == 'stretch-x' then
    try("anchorMax", function() c:SetAnchorMax(1, 0) end)
    try("pivot", function() c:SetPivot(0, 0) end)
    try("SetSizeDelta", function() c:SetSizeDelta(0, h) end)
    try("SetAnchoredPosition", function() c:SetAnchoredPosition(0, y) end)
  else
    try("anchorMax", function() c:SetAnchorMax(0, 0) end)
    try("pivot", function() c:SetPivot(0, 0) end)
    try("SetSizeDelta", function() c:SetSizeDelta(w, h) end)
    try("SetAnchoredPosition", function() c:SetAnchoredPosition(x, y) end)
  end
end

-- 建一个图片控件：动态创建**不继承模板图**，所以必须显式 SetImage
local function new_image(prefab, name, artId, mode, x, y, w, h)
  local ok, c = pcall(game.InstantiateClientUIControl, prefab, parts.STAGE)
  if not ok or c == nil then
    note(name)
    return nil
  end
  try("name", function() c.name = name end)
  pin_geometry(c, mode, x, y, w, h)
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
  pin_geometry(c, 'lb', x, y, w, h)
  try("text", function() c.text = text end)
  show_only(c, true)
  parts[name] = c
  return c
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
  -- 第一行就要说话：日志里看不到这行 = 脚本根本没跑起来（映射没挂上 / 容器不可见）
  print("M0 boot")
  -- 真机结论：EnableUpdate 不开就没有 OnUpdate；冒号写法正确
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
    print("M0 mount=nil -> 脚本必须挂在客户端控件上（不能挂主屏）")
    return
  end

  -- 画布（真机是浮点，别用 %d）
  local cw, ch = game.GetUICanvasSize()
  canvasW = cw or 1280
  canvasH = ch or 720
  print("M0 canvas=" .. tostring(cw) .. "x" .. tostring(ch))

  -- 运行时到底认不认这层 UI：0 = 没有可见画布（容器没进界面布局 / 初始可见没勾）
  local roots = game.GetClientUIRoots()
  print("M0 roots=" .. #roots)
  for i = 1, #roots do
    print("M0 root[" .. i .. "] name=" .. tostring(roots[i].name))
  end
  print("M0 mount name=" .. tostring(root.name) .. " prefab=" .. tostring(root.prefabIndex))

  -- 挂载点：**只读地打印它的几何**，除了 SetSizeDelta 之外不再改动它。
  -- ⚠ 2026-10-06 真机卡死后回退：上一版还对挂载点做了 SetAnchorMin/SetAnchorMax/SetPivot/
  --   SetAnchoredPosition（挂载点很可能是 zuma 自己的容器），并给满屏元素加了拉伸锚点 ——
  --   这两处是"v5 跑得好好的 → v5.3 卡死"之间唯一的新增变量，已全部回退。
  --   zuma.lua 的真机做法里只对容器做 SetAnchoredPosition(0,0)+SetSizeDelta(w,h)，
  --   这里先只保留 SetSizeDelta，把它自己的锚点/中心/位置留原样。
  print("M0 mount type=" .. tostring(typeof(root))
    .. " name='" .. tostring(root.name) .. "'"
    .. " prefab=" .. tostring(root.prefabIndex)
    .. " size=" .. tostring(root.sizeDeltaX) .. "x" .. tostring(root.sizeDeltaY)
    .. " pos=" .. tostring(root.anchoredPositionX) .. "," .. tostring(root.anchoredPositionY)
    .. " scale=" .. tostring(root.localScaleX) .. "x" .. tostring(root.localScaleY)
    .. " active=" .. tostring(root.active) .. " visible=" .. tostring(root.visible)
    .. " inHierarchy=" .. tostring(root.activeInHierarchy))
  show_only(root, true)
  try("root.SetSizeDelta", function() root:SetSizeDelta(canvasW, canvasH) end)
  print("M0 mount after size=" .. tostring(root.sizeDeltaX) .. "x" .. tostring(root.sizeDeltaY))

  -- 自动认模板（用户不用填任何变量）
  local tpl = detect_templates(root)
  if tpl.image == nil or tpl.text == nil then
    print("M0 detect failed -> 屏幕空白的可能原因：")
    print("   ① 模板要「存为模板」：界面控件组库 → 客户端控件模板 → 添加客户端控件 → 存为模板")
    print("   ② 或把编辑器里点开控件看到的大数字（形如 1073741xxx）填进脚本变量")
    return
  end

  -- 建控件前先定义 pin_geometry 用到的锚点/中心策略见该函数注释
  parts.STAGE = root

  -- 背景与轨道：显式尺寸（v5 的形态，真机跑通过、不卡；只是会被挂载点裁切）
  -- ⚠ 拉伸锚点在 v5.3 引入后真机卡死，已回退，不要再改回 stretch
  new_image(tpl.image, "BG", 100001, 'lb', 0, 0, canvasW, canvasH)
  new_image(tpl.image, "BALLAST", 100001, 'lb', 0, 300, canvasW, 90)
  new_image(tpl.image, "RAIL_HI", 100001, 'lb', 0, 370, canvasW, 8)
  new_image(tpl.image, "RAIL_LO", 100001, 'lb', 0, 320, canvasW, 8)
  for i = 0, 5 do
    new_image(tpl.image, "TIE_" .. i, 100001, 'lb', 130 + 180 * i, 300, 12, 90)
  end
  wagon = new_image(tpl.image, "WAGON", 100003, 'lb', 320, 400, 120, 70)
  loco = new_image(tpl.image, "LOCO", 100002, 'lb', 100, 400, 200, 70)
  for i = 0, FRAME_COUNT - 1 do
    frames[i + 1] = new_image(tpl.image, "F" .. i, 100001 + i, 'lb', 900, 430, 140, 140)
  end
  hud = new_text(tpl.text, "HUD", 20, 640, 600, 40, "M0 frame=0")

  if #missing > 0 then
    print("M0 missing list=" .. table.concat(missing, ","))
  end

  tick, idx, ticksPerFrame = 0, 0, 0
  apply_frame(0)
  print("M0 start built=" .. tostring(#frames + 9) .. " missing=" .. #missing)
end

function OnUpdate(dt)
  tick = tick + 1

  -- 存活证据：OnUpdate 到底有没有被调用（真机结论：EnableUpdate 不开就没有）
  if tick == 1 or tick % 30 == 0 then
    print("M0 update tick=" .. tick .. " loco=" .. tostring(loco ~= nil))
  end

  if loco == nil then
    return
  end

  -- 换帧用整数 tick 分频（0.12 / (1/30) = 3.6，累加秒数会踩浮点毛刺，实测会早 1 帧）
  if ticksPerFrame == 0 then
    ticksPerFrame = math.max(1, math.floor(FRAME_INTERVAL / dt + 0.5))
  end
  local nextIdx = math.floor(tick / ticksPerFrame) % FRAME_COUNT
  if nextIdx ~= idx then
    idx = nextIdx
    apply_frame(idx)
  end

  -- 位置/尺寸用方法式（真机 zuma.lua 验证过的写法）；坐标 = 画布左下角（锚点/中心已钉死 0,0）
  local wantX = 100 + MOVE_PER_TICK * tick
  local wantW = 120 + GROW_PER_TICK * tick
  try("loco.SetAnchoredPosition", function() loco:SetAnchoredPosition(wantX, 400) end)
  try("wagon.SetSizeDelta", function() wagon:SetSizeDelta(wantW, 70) end)

  -- 写回校验：证明方法式写入在真机真的生效
  if tick == 1 or tick % 30 == 0 then
    local gx = "?"
    local okx, vx = pcall(function() return loco.anchoredPositionX end)
    if okx then gx = tostring(vx) end
    local gw = "?"
    local okw, vw = pcall(function() return wagon.sizeDeltaX end)
    if okw then gw = tostring(vw) end
    print("M0 writeback x=" .. gx .. " want=" .. tostring(wantX))
    print("M0 writeback w=" .. gw .. " want=" .. tostring(wantW))
  end

  if tick % 15 == 0 then
    print("M0 move k=" .. tick)
  end
end
