-- 千星客户端接线层；构建后无 require，不自动创建/扫描控件，不改挂载点几何。
-- 在编辑器预先建控件并命名，参见 docs/lua-v1.md。
local Core = __TRAIN_CORE__
local state=Core.createState({mode='endless',seed=1})
local controls,cache={},{}
local active=false
local renderClock=0
local routeVersion=nil
local function text(name,value)
  local c=controls[name]
  if c and cache[name]~=value then c.text=value;cache[name]=value end
end
local function move(name,x,y)
  local c=controls[name]
  x,y=math.floor(x+.5),math.floor(y+.5)
  local key=name..':xy'
  local value=x..':'..y
  if c and cache[key]~=value then c:SetAnchoredPosition(x,y);cache[key]=value end
end
local function size(name,w,h)
  local c=controls[name];w,h=math.floor(w+.5),math.floor(h+.5)
  local key=name..':size';local value=w..':'..h
  if c and cache[key]~=value then c:SetSizeDelta(w,h);cache[key]=value end
end
local function visible(name,on)
  local c=controls[name];local key=name..':active'
  if c and cache[key]~=on then c:SetActive(on);cache[key]=on end
end
local function color(name,hex)
  local c=controls[name];local key=name..':color'
  if c and cache[key]~=hex then c.imageColor=tonumber('ff'..hex:sub(2),16);cache[key]=hex end
end
local bindCount,bindFail=0,0
local fillDead={}   -- 填充不可写的控件名；失败即停写，避免每次数值变化都再写一次失败属性
local function bind(name,fn)
  local c=controls[name]
  if c then
    -- 真机有 AddCursorEventListener；模拟器尚未实现 ⇒ pcall 兜住，避免一条 API 缺口挡住整段验证。
    -- 计数并打印，等于让「真机/模拟器各自有没有这个 API」自报出来。
    local ok=pcall(function() c:AddCursorEventListener(Enum.CursorEventType.CursorClick,fn) end)
    if ok then bindCount=bindCount+1 else bindFail=bindFail+1 end
  end
end
local function render()
  local v=Core.view(state)
  text('SPEED',string.format('%.1f km/h',state.speed))
  text('GEAR',tostring(state.gear))
  text('TEMP',v.temperaturePercent..'%')
  text('SCORE',tostring(math.floor(state.score+.5)))
  text('TARGET',v.target)
  text('STATUS',state.phase=='ready' and '点击出发' or state.phase=='paused' and '已暂停' or
    state.phase=='finished' and ((state.result and state.result.ended) and '旅程结束' or '本站完成') or
    ('第 '..(state.legIndex+1)..' 站 · 剩余 '..math.max(0,math.floor(state.length-state.position))..' m'))
  local hint=''
  if state.noticeUntil>state.elapsed then hint=state.notice
  elseif state.sectionHint and state.sectionHint.untilTime>state.elapsed then hint=state.sectionHint.text
  elseif v.docking then hint='准备停车 · 距站心 '..string.format('%.1f',state.length-state.position)..' m'
  elseif v.approach then hint='即将进入'..v.approach.section.name..' · '..math.ceil(v.approach.distance)..' m' end
  text('HINT',hint)
  if state.sectionHint and state.sectionHint.untilTime>state.elapsed then color('HINT_BG',state.sectionHint.color)
  elseif v.approach then color('HINT_BG',v.approach.color) else color('HINT_BG',v.targetColor) end
  visible('HINT_BG',hint~='')
  -- 固定美术针帧：避免依赖未确认的旋转属性。37 帧速度 / 43 帧温度，每帧 5°。
  local speedFrame=math.floor(v.speedAngle/5+.5)
  local tempFrame=math.floor(v.temperatureAngle/5+.5)
  if cache.speedFrame~=speedFrame then
    if cache.speedFrame~=nil then visible('SPEED_F'..cache.speedFrame,false) end
    visible('SPEED_F'..speedFrame,true);cache.speedFrame=speedFrame
  end
  if cache.tempFrame~=tempFrame then
    if cache.tempFrame~=nil then visible('TEMP_F'..cache.tempFrame,false) end
    visible('TEMP_F'..tempFrame,true);cache.tempFrame=tempFrame
  end
  -- 进度容器局部坐标：左端 (0,0)，宽 600、高 12；有限段按真实距离留空隙。
  move('PROGRESS_MARKER',v.progress*600,20)
  if routeVersion~=state.route then
    for i=1,11 do
      local r=state.route[i];local on=r and Core.isLimited(r) or false
      visible('SEG'..i,on)
      if on then
        move('SEG'..i,r.from/state.length*600,0)
        size('SEG'..i,(r.to-r.from)/state.length*600,12)
        color('SEG'..i,Core.sectionColor(r))
      end
    end
    routeVersion=state.route
  end
  -- 目标区间放在仪表盘；可选直线标记，与固定美术表盘采用相同 0..120 标定。
  visible('TARGET_RANGE',v.targetFrom~=nil)
  if v.targetFrom then
    move('TARGET_RANGE',v.targetFrom*240,0)
    size('TARGET_RANGE',(v.targetTo-v.targetFrom)*240,4)
    color('TARGET_RANGE',v.targetColor)
  end
  -- 可选四个地面标记，位移来自实际路程，坡度来自与物理相同的积分曲线。
  -- TIE 控件放到独立 SCENE 容器；车头美术预先朝右，车保持相机中心 (240,0)。
  for i=1,4 do
    local x=((i-1)*180-state.position*8)%720
    local world=math.max(0,state.position+(x-240)/8)
    local y=-(Core.terrainAt(world,state).height-v.terrain.height)
    move('TIE'..i,x,y)
  end
  -- ★ 表盘：实心圆 + 径向填充（替代 37+43 帧美术 ⇒ 80 帧变 2 个控件、0 张上传素材）
  --   ① /360：Radial360 的 1.0 是整圈 ⇒ 要保留原设计的扫角，必须用 angle/360
  --      （speed 最大 180° ⇒ 0.5；temperature 最大 210° ⇒ ≈0.5833）
  --   ② 失败即"marker 不可用"并停止后续写入（不能每次数值变化都再写一次失败属性 — 那正是逐帧刷 API 的坑）
  if controls.SPEED_DIAL or controls.TEMP_DIAL then
    local function fill(name,frac)
      local c=controls[name]
      if not c or fillDead[name] then return end
      frac=math.max(0,math.min(1,frac))
      local key=name..':fill'
      if cache[key]~=frac then
        local ok=pcall(function() c.fillAmount=frac end)
        if ok then
          cache[key]=frac
        else
          fillDead[name]=true
          if print then print('TRAIN fillAmount 不可写，已停用 '..name..' 的后续填充写入') end
        end
      end
    end
    fill('SPEED_DIAL',v.speedAngle/360)
    fill('TEMP_DIAL',v.temperatureAngle/360)
  end
  visible('CONTINUE',state.mode=='endless' and state.phase=='finished' and not state.result.ended)
end
local function guard(fn)
  local ok,err=pcall(fn)
  if not ok then
    active=false;script:EnableUpdate(false)
    -- 首次错误即停，不逐帧重试，不刷屏。
    if print then print('TRAIN stopped: '..tostring(err)) end
  end
end
function OnInit() script:EnableUpdate(true) end
function OnStart()
  guard(function()
    local root=script.object
    assert(root,'需要客户端容器挂载点')
    -- ★ 光标事件的前置条件（平台事实）：控件必须能显示常驻光标，否则 AddCursorEventListener 不触发。
    -- 运行时是否允许写这个字段未逐一验证 ⇒ 用 pcall 兜住并记一行日志，便于真机核对。
    local okCursor=pcall(function() root.showCursor=true end)
    if print then print('TRAIN showCursor='..tostring(okCursor)) end
    -- ★ 表盘两个控件必须在这张表里：漏了它们 ⇒ controls.SPEED_DIAL 永远 nil ⇒ 填充代码整段被跳过
    --   （ChatGPT 审核用 mock 复现过这个遗漏；教训：新增控件时要同时改"查找表"）
    local names={'SPEED','GEAR','TEMP','SCORE','TARGET','STATUS','HINT','HINT_BG',
      'START','UP','DOWN','PAUSE','CONTINUE','END','TRIAL','ENDLESS','PROGRESS_MARKER','TARGET_RANGE',
      'SPEED_DIAL','TEMP_DIAL'}
    for i=1,11 do names[#names+1]='SEG'..i end
    for i=1,4 do names[#names+1]='TIE'..i end
    -- 37+43 帧针图方案已弃用（改为实心圆 + fillAmount）⇒ 不再查找这些控件；git 历史里有旧方案可恢复
    -- 按固定层级查找；进度/场景/目标环容器必须预先摆好，不修改父级几何。
    for _,name in ipairs(names) do
      local path=name
      if name:match('^SEG%d') or name=='PROGRESS_MARKER' then path='PROGRESS/'..name
      elseif name:match('^TIE%d') then path='SCENE/'..name
      elseif name=='TARGET_RANGE' then path='DIAL/'..name end
      local c=root:FindChild(path)
      if not c and path~=name then c=root:FindChild(name) end
      controls[name]=c
    end
    -- ★ 真机查找阶梯（来源：zuma.lua 在真机跑通的写法，不是推测）：
    --   ① 契约路径 ② 裸名 ③ 挂载点向下 walk ④ 挂载点向上 3 层 walk ⑤ game.GetClientUIRoots() 各自 walk
    --   为什么必须这样：真机上 FindChild **一次都没成功过**（zuma.lua 里 FindChild 出现 0 次），
    --   真机成立的是 GetChildren() 枚举 + .parent 回溯 + GetClientUIRoots()（"实际显示的画布默认容器节点"）。
    --   有界：总节点预算 LOOKUP_MAX + 深度上限 + seen 去重 + 共享预算 ⇒ 绝不可能无限扫描。
    local missing=0
    for _,name in ipairs(names) do if not controls[name] then missing=missing+1 end end
    if missing>0 then
      local LOOKUP_MAX=400
      local budget=LOOKUP_MAX
      local map,visited={},{}
      local function kidsOf(c)
        local ok,list=pcall(function() return c:GetChildren() end)
        if ok and type(list)=='table' then return list end
        return {}
      end
      local function collect(start,depthMax)
        if start==nil or budget<=0 then return 0 end
        local stack,seen={{start,0}},0
        while #stack>0 and budget>0 do
          local item=table.remove(stack)
          local c,d=item[1],item[2]
          if c~=nil and not visited[c] then
            visited[c]=true;budget=budget-1;seen=seen+1
            local ok,nm=pcall(function() return c.name end)
            if ok and nm~=nil and map[nm]==nil then map[nm]=c end
            if d<depthMax then
              for _,gc in ipairs(kidsOf(c)) do stack[#stack+1]={gc,d+1} end
            end
          end
        end
        return seen
      end
      local nDown=collect(root,4)
      local nUp=0
      local up=root
      for _=1,3 do
        if budget<=0 then break end
        local okp,p=pcall(function() return up.parent end)
        if not okp or p==nil then break end
        up=p
        nUp=nUp+collect(up,3)
      end
      local nRoots,rootCount=0,0
      if budget>0 then
        local okr,roots=pcall(function() return game.GetClientUIRoots() end)
        if okr and type(roots)=='table' then
          rootCount=#roots
          for i=1,#roots do nRoots=nRoots+collect(roots[i],4) end
        end
      end
      local stillMissing=0
      for _,name in ipairs(names) do
        if not controls[name] then
          controls[name]=map[name]
          if not controls[name] then stillMissing=stillMissing+1 end
        end
      end
      local mountName='?'
      pcall(function() mountName=tostring(root.name) end)
      if print then
        print('TRAIN lookup: down='..nDown..' up='..nUp..' roots='..nRoots..'/'..rootCount
          ..' miss='..stillMissing..' mount='..mountName)
      end
    end
    for _,name in ipairs({'SPEED','GEAR','TEMP','SCORE','TARGET','STATUS','HINT','START','UP','DOWN'}) do
      assert(controls[name],'缺少控件 '..name)
    end
    for i=0,36 do visible('SPEED_F'..i,false) end
    for i=0,42 do visible('TEMP_F'..i,false) end
    bind('START',function() Core.start(state) end)
    bind('UP',function() Core.shift(state,1) end)
    bind('DOWN',function() Core.shift(state,-1) end)
    bind('PAUSE',function() Core.pause(state) end)
    bind('CONTINUE',function() Core.continueJourney(state) end)
    bind('END',function() Core.endJourney(state) end)
    local function choose(mode)
      if state.phase=='ready' or state.phase=='finished' then
        state=Core.createState({mode=mode,seed=state.seed})
      end
    end
    bind('TRIAL',function() choose('trial') end)
    bind('ENDLESS',function() choose('endless') end)
    if print then print('TRAIN bound='..bindCount..' failed='..bindFail) end
    active=true;render()
  end)
end
function OnUpdate(dt)
  if not active then return end
  guard(function()
    if type(dt)~='number' or dt~=dt or dt<=0 or dt==math.huge then return end
    -- 大卡顿直接暂停，避免一次回调做海量子步；不偷偷截断时间继续行驶。
    if dt>.5 then if state.phase=='running' then Core.pause(state) end;render();return end
    Core.update(state,dt)
    renderClock=renderClock+dt
    if renderClock>=.2 then renderClock=renderClock%.2;render() end -- 5Hz + 脏检查
  end)
end
