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
local function bind(name,fn)
  local c=controls[name]
  if c then c:AddCursorEventListener(Enum.CursorEventType.CursorClick,fn) end
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
    local names={'SPEED','GEAR','TEMP','SCORE','TARGET','STATUS','HINT','HINT_BG',
      'START','UP','DOWN','PAUSE','CONTINUE','END','TRIAL','ENDLESS','PROGRESS_MARKER','TARGET_RANGE'}
    for i=1,11 do names[#names+1]='SEG'..i end
    for i=1,4 do names[#names+1]='TIE'..i end
    for i=0,36 do names[#names+1]='SPEED_F'..i end
    for i=0,42 do names[#names+1]='TEMP_F'..i end
    -- 按固定层级查找；进度/场景/目标环容器必须预先摆好，不修改父级几何。
    for _,name in ipairs(names) do
      local path=name
      if name:match('^SEG%d') or name=='PROGRESS_MARKER' then path='PROGRESS/'..name
      elseif name:match('^TIE%d') then path='SCENE/'..name
      elseif name=='TARGET_RANGE' then path='DIAL/'..name end
      controls[name]=root:FindChild(path)
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
