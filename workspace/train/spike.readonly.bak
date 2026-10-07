--[[ ===========================================================================
  probe_readonly.lua —— M0 收口的"只读诊断"探针（v7）

  为什么单独做这一版：v5.3 上真机后客户端无响应（`docs/tech-architecture.md` §7），
  而"真机 UI 只盖住左下角"的**挂载点几何**始终没拿到证据（那次本来要打印，卡死了）。
  所以在拿到事实之前，把探针降级为**纯读**：

    ✅ 只做：print、读属性、typeof、GetUICanvasSize、GetClientUIRoots
    ❌ 不做：InstantiateClientUIControl、DestroyClientUIControl（**不扫模板**）
    ❌ 不做：SetSizeDelta / SetAnchoredPosition / SetAnchor* / SetPivot（**不改几何**）
    ❌ 不做：建控件、换图、show_only

  OnUpdate 只打两行存活证据（tick=1 / tick=60），不开任何逐帧写操作。

  真机用法：把本文件内容覆盖到设备上的平铺映射文件 `spike.lua`（名字必须平铺、不能带斜杠），
  然后在千星里**保存关卡 → 试玩**（关卡会把脚本源码打包进去，不保存就不生效）。
  日志出口：`BeyondLocal\<UID>\Beyond_Debug_Log\*.gia`。
=========================================================================== ]]

local CANVAS_FALLBACK_W, CANVAS_FALLBACK_H = 1280, 720

-- 逐个字段地读，读不到就打印原因：真机上哪些字段可读、哪些方法不存在，一次问清
local function probe(tag, fn)
  local ok, v = pcall(fn)
  if ok then
    print("M0 mount probe " .. tag .. " = " .. tostring(v))
  else
    print("M0 mount probe " .. tag .. " ERR " .. tostring(v))
  end
end

-- 注意：内层匿名函数**不是 vararg**，不能在它里面用外层的 `...`
-- （Lua 5.1 报 "cannot use '...' outside a vararg function"，已在模拟器里实测踩到）。
-- 这里只支持零参方法调用 —— 本探针要问的几个 Get* 都是零参。
local function probe_method(tag, obj, name)
  local ok, v = pcall(function()
    if obj == nil then return "no-object" end
    local f = obj[name]
    if f == nil then return "no-method" end
    return f(obj)
  end)
  if ok then
    print("M0 mount probe " .. tag .. " = " .. tostring(v))
  else
    print("M0 mount probe " .. tag .. " ERR " .. tostring(v))
  end
end

function OnInit()
  print("M0 boot")
  print("M0 readonly probe (no instantiate / no geometry write / no scan / no per-frame update)")
  -- ⚠ 本版**故意不调 EnableUpdate**：这是整个探针里唯一会让引擎"持续"回调我们的东西。
  -- "OnUpdate 在真机确实会被调用"上一轮已经取证过（v5 真机 tick=1…420），不必再测，
  -- 所以这里把最后一个持续行为也去掉 —— 探针退化成"只打一次日志就安静"。
  print("M0 readonly probe stays quiet after this (no EnableUpdate, no OnUpdate)")
end

function OnStart()
  local root = script.object
  if root == nil then
    print("M0 mount=nil -> 脚本没挂在客户端控件上")
    return
  end

  local cw, ch = game.GetUICanvasSize()
  print("M0 canvas=" .. tostring(cw) .. "x" .. tostring(ch)
    .. " (fallback=" .. CANVAS_FALLBACK_W .. "x" .. CANVAS_FALLBACK_H .. ")")

  -- roots：官方判据 0 = 运行时没有"显示中的画布"，但上一轮真机 UI 明明画出来了
  local roots = game.GetClientUIRoots()
  local n = 0
  if roots ~= nil then n = #roots end
  print("M0 roots=" .. n)
  if roots ~= nil then
    for i = 1, n do
      print("M0 root[" .. i .. "] name='" .. tostring(roots[i].name)
        .. "' type=" .. tostring(typeof(roots[i])))
    end
  end

  -- 挂载点本身：这一版**只读**，不改任何东西
  print("M0 mount type=" .. tostring(typeof(root)))
  print("M0 mount name='" .. tostring(root.name) .. "'")
  print("M0 mount size=" .. tostring(root.sizeDeltaX) .. "x" .. tostring(root.sizeDeltaY))
  print("M0 mount pos=" .. tostring(root.anchoredPositionX) .. "," .. tostring(root.anchoredPositionY))
  print("M0 mount scale=" .. tostring(root.localScaleX) .. "x" .. tostring(root.localScaleY))

  probe("active", function() return root.active end)
  probe("visible", function() return root.visible end)
  probe("activeInHierarchy", function() return root.activeInHierarchy end)
  probe("prefabIndex", function() return root.prefabIndex end)
  probe("rotationZ", function() return root.rotationZ end)
  probe("interactable", function() return root.interactable end)
  probe("imageType", function() return root.imageType end)
  probe("imageSource", function() return root.imageSource end)
  probe("imageId", function() return root.imageId end)
  probe("text", function() return root.text end)

  -- 父级：裁切的元凶最可能在父级的矩形/缩放上
  probe("parent", function()
    local p = root.parent
    if p == nil then return "nil" end
    return tostring(typeof(p)) .. " name='" .. tostring(p.name) .. "'"
      .. " size=" .. tostring(p.sizeDeltaX) .. "x" .. tostring(p.sizeDeltaY)
      .. " scale=" .. tostring(p.localScaleX) .. "x" .. tostring(p.localScaleY)
  end)
  probe("childCount", function() return root.childCount end)

  -- 锚点/中心：方法能不能调、读出来是多少（这些决定子控件坐标怎么解释）
  probe_method("GetAnchorMin", root, "GetAnchorMin")
  probe_method("GetAnchorMax", root, "GetAnchorMax")
  probe_method("GetPivot", root, "GetPivot")
  probe_method("GetAnchoredPosition", root, "GetAnchoredPosition")
  probe_method("GetSizeDelta", root, "GetSizeDelta")
  probe_method("GetLocalScale", root, "GetLocalScale")

  -- 脚本挂载点上的其它可用字段，用来判断"我在哪个控件上"
  probe("script.object==root", function() return script.object == root end)
  probe("script.enableUpdate", function() return script.enableUpdate end)

  print("M0 readonly probe done (nothing was created or modified)")
end

-- 本版**故意没有 OnUpdate**：不调 EnableUpdate ⇒ 引擎不会逐帧回调我们。
-- （踩坑留档：模拟器实测 `script` 是封闭对象，`script._tick = 1` 会报
--  "cannot set _tick, no such field" ⇒ 逐帧计数只能用模块级局部变量。本版不用逐帧。）
