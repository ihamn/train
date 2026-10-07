-- probe_safe.lua —— 阶梯式「安全探针」（时间切片 + 档位 + 看门狗）
--
-- 为什么要有它：v8/v9 两次把真机卡死，每次要等服务器 10 分钟回收关卡 ⇒
--   本版让「卡死」在**结构上**不可能发生：
--     ① OnStart 只做**只读**打印，绝不在启动期做重活（爆发=卡死的头号来源）
--     ② 真正的工作放在 OnUpdate，**每帧只做一件事**（时间切片，单帧成本恒定）
--     ③ 1~4 档都是「一帧做完就自停」；只有第 5 档是持续写（最危险，最后测）
--     ④ 看门狗 MAX_TICKS：到点自停（并主动 EnableUpdate(false)）
--     ⑤ dt 保护：dt==nil 或 <=0 直接 return（除零会让换帧静默失效）
--     ⑥ 模板索引走**候选表**（每类 ≤2，逐个 pcall，记录命中），不扫描区间、不重试
--     ⑦ 全程 ASCII 计数日志：M0 lvl=… tick=… built=… wrote=… destroyed=…
--
-- 换档位：改下面这个数字（我改文件即可，**不需要重新导入**），然后重进关卡。
local PROBE_LEVEL = 3        -- 0=只读(默认,绝对安全) 1=建1个 2=+设定名/图 3=+几何写1次(大红块) 4=+销毁 5=+每帧写

local MAX_TICKS = 240        -- 看门狗：到点自停（约 4~8 秒）
local MAX_BUILD = 8          -- 硬上限（本探针最多建这么多控件）

-- 模板索引候选：[1] 真机只读探针实测，[2] 模拟器工程生成值
local TPL_CAND = {
  image = { 1073741852, 1073742003 },
  text  = { 1073741851, 1073742004 },
}

local level = 0
local host = nil
local canvasW, canvasH = 1280, 720
local tick, alive = 0, true
local n_build, n_wrote, n_destroyed, n_probe = 0, 0, 0, 0
local one = nil              -- 本档位唯一的那个控件

local function say(s) if print then pcall(print, "M0 " .. s) end end
local function try(label, fn)
  local ok, err = pcall(fn)
  if not ok then say("writefail " .. label .. " -> " .. tostring(err)) end
  return ok
end
local function read_num(obj, field)
  local ok, v = pcall(function() return obj[field] end)
  if ok and type(v) == "number" then return v end
  return nil
end

-- 档位来源：先试关卡变量（几种可能形态，全 pcall），全失败就用文件里的常量
local function read_level(root)
  local names = { "probeLevel", "probe_level" }
  for i = 1, #names do
    local ok, v = pcall(function() return game.GetCustomVariable("Level", names[i]) end)
    if ok and type(v) == "number" then say("level 来自 Level." .. names[i] .. "=" .. v); return v end
    ok, v = pcall(function() return game.GetCustomVariable(root, names[i]) end)
    if ok and type(v) == "number" then say("level 来自 host." .. names[i] .. "=" .. v); return v end
  end
  return PROBE_LEVEL
end

-- 候选表探测：建一个 → 看类型 → 立刻销毁 → 计数（只有第 2/3 档会用到）
local function pick_prefab(kind)
  local cands = TPL_CAND[kind]
  if cands == nil then return nil end
  for i = 1, #cands do
    if n_probe < 6 then
      n_probe = n_probe + 1
      local p = cands[i]
      local ok, c = pcall(game.InstantiateClientUIControl, p, host)
      if ok and c ~= nil then
        local okT, t = pcall(function() return typeof(c) end)
        local tn = okT and tostring(t) or "?"
        pcall(function() game.DestroyClientUIControl(c) end)
        say("probe " .. p .. " -> " .. tn)
        if (kind == "image" and tn == "ClientUIImageControl")
          or (kind == "text" and tn == "ClientUITextBoxControl") then
          return p
        end
      else
        say("probe " .. p .. " failed")
      end
    end
  end
  return nil
end

local function build_one(prefab, name)
  if n_build >= MAX_BUILD then return nil end
  local ok, c = pcall(game.InstantiateClientUIControl, prefab, host)
  if not ok or c == nil then say("build failed at " .. name); alive = false; return nil end
  n_build = n_build + 1
  return c
end

local function summary()
  say("summary lvl=" .. level .. " tick=" .. tick
    .. " built=" .. n_build .. " wrote=" .. n_wrote
    .. " destroyed=" .. n_destroyed .. " probes=" .. n_probe
    .. " wrote_controls=" .. tostring(level >= 5 and 1 or 0))
end

function OnInit()
  say("boot")
  try("enableUpdate", function() script:EnableUpdate(true) end)
end

function OnStart()
  host = script.object
  say("start 文件档位=" .. PROBE_LEVEL)
  if host == nil then
    say("no host -> 脚本没挂在客户端控件上（这本身就是结论）")
    alive = false
    return
  end
  -- 只读信息：不建控件、不写几何
  local okc, cw, ch = pcall(game.GetUICanvasSize)
  if okc then canvasW = cw or canvasW; canvasH = ch or canvasH end
  local okr, roots = pcall(game.GetClientUIRoots)
  say("canvas=" .. tostring(canvasW) .. "x" .. tostring(canvasH)
    .. " roots=" .. tostring(okr and #roots or -1))
  say("host type=" .. tostring(typeof(host)) .. " name='" .. tostring(host.name) .. "'"
    .. " prefab=" .. tostring(host.prefabIndex)
    .. " size=" .. tostring(read_num(host, "sizeDeltaX")) .. "x" .. tostring(read_num(host, "sizeDeltaY"))
    .. " pos=" .. tostring(read_num(host, "anchoredPositionX")) .. "," .. tostring(read_num(host, "anchoredPositionY")))

  level = read_level(host)
  if level <= 0 then
    say("lvl=0 只读档：什么都不做（绝对安全）")
    alive = false
  end
end

-- 每帧只做一件事：1~4 档一帧做完即自停；5 档持续写（最危险）
function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1
  if tick > MAX_TICKS then
    say("watchdog stop tick=" .. tick)
    try("disable", function() script:EnableUpdate(false) end)
    alive = false
    summary()
    return
  end
  if dt == nil or dt <= 0 then return end   -- 除零/首帧保护

  if level == 1 then
    local c = build_one(TPL_CAND.image[1], "P1")
    if c ~= nil then say("lvl=1 built=1（未写几何）") end
    alive = false; summary(); return
  end

  if level == 2 then
    local prefab = pick_prefab("image") or TPL_CAND.image[1]
    local c = build_one(prefab, "P2")
    if c ~= nil then
      try("name", function() c.name = "P2" end)
      try("SetImage", function() c:SetImage(Enum.ImageSource.StaticReference, 100001) end)
      say("lvl=2 built=1 设了 name+image（未写几何）")
    end
    alive = false; summary(); return
  end

  if level == 3 then
    -- ★ 这一档的判据是「眼睛能不能看到」：建 1 个**大红块**（600x300，屏幕中央偏上）
    local prefab = pick_prefab("image") or TPL_CAND.image[1]
    one = build_one(prefab, "P3")
    if one ~= nil then
      try("anchorMin", function() one:SetAnchorMin(0, 0) end); n_wrote = n_wrote + 1
      try("anchorMax", function() one:SetAnchorMax(0, 0) end); n_wrote = n_wrote + 1
      try("pivot", function() one:SetPivot(0, 0) end); n_wrote = n_wrote + 1
      try("size", function() one:SetSizeDelta(600, 300) end); n_wrote = n_wrote + 1
      try("pos", function() one:SetAnchoredPosition(340, 260) end); n_wrote = n_wrote + 1
      try("image", function() one:SetImage(Enum.ImageSource.StaticReference, 100001) end)
      -- 颜色：白底白图看不出来 ⇒ 强制染红（失败也无所谓，只是一行日志）
      try("color", function() one.imageColor = 4294901760 end)
      try("show", function() one:SetActive(true); one:SetVisible(true) end)
      say("lvl=3 ★ 大红块已建：600x300 @ (340,260) —— 看屏幕中央偏上有没有红块")
      say("lvl=3 几何写入次数=" .. n_wrote)
    end
    alive = false; summary(); return
  end

  if level == 4 then
    local c = build_one(TPL_CAND.image[1], "P4")
    if c ~= nil then
      if pcall(function() game.DestroyClientUIControl(c) end) then
        n_destroyed = n_destroyed + 1
        say("lvl=4 built=1 destroyed=1（销毁这一格单独验）")
      else
        say("lvl=4 destroy 调用失败（名字可能不对）")
      end
    end
    alive = false; summary(); return
  end

  if level == 5 then
    -- ★ 最危险的一档：持续写几何（真机若卡，就是这一格）
    if one == nil then
      one = build_one(TPL_CAND.image[1], "P5")
      if one == nil then alive = false; summary(); return end
      try("anchorMin", function() one:SetAnchorMin(0, 0) end)
      try("anchorMax", function() one:SetAnchorMax(0, 0) end)
      try("pivot", function() one:SetPivot(0, 0) end)
      try("size", function() one:SetSizeDelta(120, 80) end)
      say("lvl=5 建好 1 个，开始每帧写位置")
      return
    end
    try("pos", function() one:SetAnchoredPosition(200 + 4 * tick, 200) end)
    n_wrote = n_wrote + 1
    if tick % 15 == 0 then
      say("lvl=5 tick=" .. tick .. " wrote=" .. n_wrote
        .. " pos=" .. tostring(read_num(one, "anchoredPositionX")))
    end
    return
  end

  -- 未知档位：什么都不做
  alive = false
end
