-- hello.lua —— 最小验证脚本：确认「脚本映射 -> 挂到控件 -> 试玩」这条管线是通的。
--
-- 只依赖官方 API，**不依赖 zuma.lua 的任何东西**。所以它能把问题一刀切开：
--   · hello 能跑  -> 管线没问题，那是 zuma.lua 的事
--   · hello 也不跑 -> 是"文件没进去 / 映射没建 / 没挂到控件"这类管线问题
--
-- ★★ 2026-09-25 修了一个致命 bug：控件创建**必须在 OnStart**，不能在 OnInit。
--    真机探针（miliastra-beyond-simulator / client/lua-runtime/docs/observed-contract.md §2）：
--      「Instantiate：探针 OnInit/OnDestroy → nil；OnStart → 控件」
--    也就是说 game.InstantiateClientUIControl 在 OnInit 阶段**返回 nil**。
--    原来把建控件放在 OnInit 里 → 全部返回 nil → 一个控件都没建出来
--    → 连"出错时显示原因"的那行字本身也是控件、也没建出来 → 屏幕全白，且没有任何提示。
--
-- 全程用 print() 打日志（官方日志 API，不需要控件）。好处：
--   哪怕一个控件都建不出来，游戏日志里也能看到脚本跑到哪一步、死在哪。
--
-- 期望现象：试玩后屏幕上 8 颗彩色小球绕中心转圈，上方一行状态字。
-- 出错时那行字会变成 "!! 具体原因"。
--
-- 用到的脚本变量（不填就用默认值）：
--   ballPrefab  球控件模板索引 [1]
--   hudPrefab   文本框模板索引 [2]

local t = 0
local balls = {}
local info = nil
local err = nil
local W, H = 900, 900
local built = false

-- 不依赖控件的日志通道：print 是官方日志 API
local function say(fmt, ...)
  local ok, s = pcall(string.format, fmt, ...)
  if not ok then s = tostring(fmt) end
  if print then pcall(print, '[hello] ' .. s) end
end

local function param(name, d)
  local v = script and script:GetParam(name)
  if v == nil then return d end
  return v
end

local function build()
  local w, h = game.GetUICanvasSize()
  say('画布 = %dx%d', w, h)

  local root = script.object
  if not root then
    local rs = game.GetClientUIRoots()
    root = rs and rs[1]
  end
  if not root then error('找不到挂载控件：脚本要挂在**客户端控件**上（不能挂主屏）') end
  say('挂载点 = %s', tostring(root))
  root:SetActive(true)

  local ballPrefab = param('ballPrefab', 1)
  local hudPrefab = param('hudPrefab', 2)
  say('ballPrefab = %s, hudPrefab = %s', tostring(ballPrefab), tostring(hudPrefab))

  info = game.InstantiateClientUIControl(hudPrefab, root)
  say('文本框 = %s', tostring(info))
  if info then
    info:SetActive(true)
    info:SetAnchoredPosition(0, h / 2 - 40)
    info:SetSizeDelta(math.min(w - 40, 700), 40)
    info.fontSize = 22
    info.text = 'hello: 正在创建球…'
  end

  for i = 1, 8 do
    local c = game.InstantiateClientUIControl(ballPrefab, root)
    if not c then
      error('球控件创建失败（ballPrefab = ' .. tostring(ballPrefab)
        .. '）：模板索引可能没填，或这个控件不能动态创建（主屏 / 模板控件的子节点都不行）')
    end
    c:SetActive(true)
    c:SetSizeDelta(60, 60)
    c.imageColor = Color.FromRGBA(80 + i * 20, 220 - i * 15, 255, 255)
    balls[i] = c
  end
  say('建好了 %d 颗球', #balls)
  return w, h
end

local function tryBuild()
  if built then return end
  built = true
  local ok, e = pcall(function() W, H = build() end)
  if not ok then
    err = tostring(e)
    say('建控件失败：%s', err)
  end
end

-- OnInit 阶段真机上 Instantiate 返回 nil —— 所以这里**什么都不建**
function OnInit()
  say('OnInit（只登记，不建控件）')
  -- ★★ 第二个致命坑：官方 API 有 script:EnableUpdate(enabled)，
  --    真机观察结论是「EnableUpdate 前无 OnUpdate」——不打开就永远收不到每帧回调。
  --    这里是最早的时机；放在 OnStart 也行，但放这里能保证 OnUpdate 的兜底逻辑有机会跑。
  if script and script.EnableUpdate then
    local ok, e = pcall(function() script:EnableUpdate(true) end)
    say('EnableUpdate(true) -> %s', ok and 'ok' or tostring(e))
  else
    say('警告：没有 script.EnableUpdate，逐帧回调可能不会触发')
  end
end

function OnStart()
  say('OnStart —— 开始建控件')
  tryBuild()
end

function OnUpdate(dt)
  -- 兜底：万一某些版本不调 OnStart，第一帧补建（此时已不在 OnInit 阶段）
  if not built then
    say('没等到 OnStart，在 OnUpdate 里补建')
    tryBuild()
  end

  t = t + dt
  if err then
    if info then info.text = '!! ' .. err end
    return
  end
  local n = #balls
  for i = 1, n do
    local a = t * 0.8 + (i - 1) / n * math.pi * 2
    balls[i]:SetAnchoredPosition(math.cos(a) * 160, math.sin(a) * 160)
    balls[i]:SetLocalRotation(0, 0, math.deg(a))
  end
  if info then
    info.text = string.format('hello 跑起来了 · 已运行 %.1f 秒 · 球 %d 个 · 画布 %dx%d', t, n, W, H)
  end
end

function OnLevelUpdate(dt) end
function OnDestroy() end

return { OnInit = OnInit, OnUpdate = OnUpdate, OnStart = OnStart, OnDestroy = OnDestroy }
