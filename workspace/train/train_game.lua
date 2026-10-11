-- 千星客户端接线层；构建后无 require，不自动创建/扫描控件，不改挂载点几何。
-- 在编辑器预先建控件并命名，参见 docs/lua-v1.md。
local Core = (function()
-- 列车玩法 v1，纯 Lua 5.1+；不调用千星 API。单位：m、s、km/h。
-- 项目自定义规则，不声称恢复了官方源码。客户端单文件由 tools/build-train-lua.mjs 生成。
local M = {}
local R = {traction={-6,-5,-4,-1,2,3,4}, maxSpeed=120, blueBoundary=53,
  heatPerShift=.25, cooling=.05, overheatSeconds=3, overheatPenalty=200,
  perfectSectionPoints=100, dockingDistance=100, dockingTolerance=5,
  dockingPoints=200, stopSpeed=.3, overshootDistance=35, scoreStep=5}
M.RULES = R
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function limited(r) return r.low ~= nil and r.high ~= nil end
M.isLimited = limited
local function round(x) return math.floor(x+.5) end
local function segment(a,b,name,e,lo,hi,start,ramp,lead)
  return {from=a,to=b,name=name,environment=e,low=lo,high=hi,
    environmentStart=start,rampLength=ramp,leadDistance=lead}
end
local function trial()
  return {
    segment(0,240,'车站出发',0),segment(240,640,'平地慢行',0,20,52,nil,nil,180),
    segment(640,1000,'下坡转场',4.5,nil,nil,0),segment(1000,1480,'下坡快行',4.5,85,108,nil,nil,300),
    segment(1480,1950,'坡底转场',-2.5,nil,nil,4.5),segment(1950,2180,'缓坡慢行',-2.5,20,52,nil,nil,400),
    segment(2180,2800,'上坡转场',-3.5,nil,nil,-2.5),segment(2800,3320,'上坡巡行',-3.5,53,84,nil,nil,400),
    segment(3320,3690,'站前转场',-2.5,nil,nil,-3.5),segment(3690,3900,'站前慢行',-2.5,20,52,nil,nil,300),
    segment(3900,4200,'进站停靠',0,nil,nil,-2.5,200)}
end
-- 32 位乘法用 16 位拆分，兼容 double / 32 位 / 64 位 Lua 的整数语义。
local U32=4294967296
local function mul32(a,b)
  local al,bl=a%65536,b%65536
  return (al*bl+((math.floor(a/65536)*bl+math.floor(b/65536)*al)%65536)*65536)%U32
end
function M.createLeg(seed,index)
  local randomState=(seed%U32+mul32(index+1,2654435769))%U32
  local function random()
    randomState=(mul32(randomState,1664525)+1013904223)%U32
    return randomState/U32
  end
  local function varied(base) return base+(math.floor(random()*5)-2)*20 end
  local difficulty=math.min(3,math.floor(index/3))
  local special=index%4==3
  local high=-2.5
  if special then high=4.5 elseif difficulty>=2 and random()<.5 then high=-3.5 end
  local stages
  if special then
    stages={{'平地慢行',0,20,52,varied(300)},
      {'下坡快行',high,85,108,varied(480),varied(640),true},
      {'上坡巡行',-2.5,53,84,varied(430),varied(660)},
      {'站前慢行',-2.5,20,52,varied(240),varied(480)}}
  else
    stages={{'平地慢行',0,20,52,varied(300)},
      {'上坡巡行',-2.5,53,84,varied(430),varied(440)},
      {'上坡快行',high,85,108,varied(480),varied(440)},
      {'站前慢行',-2.5,20,52,varied(240),varied(660)}}
  end
  local route={segment(0,240,'车站出发',0)}
  local pos,env=240,0
  for _,t in ipairs(stages) do
    if t[6] then
      local gap=segment(pos,pos+t[6],t[7] and '下坡转场' or '转场准备',t[2],nil,nil,env)
      gap.special=t[7] or false
      route[#route+1]=gap; pos=gap.to
    end
    route[#route+1]=segment(pos,pos+t[5],t[1],t[2],t[3],t[4],nil,nil,t[6] and math.min(t[6],400) or 180)
    pos=pos+t[5];env=t[2]
  end
  route[#route+1]=segment(pos,pos+300,'进站停靠',0,nil,nil,env,200)
  return {route=route,length=pos+300,difficulty=difficulty,special=special}
end
function M.sectionAt(pos,s)
  for i,r in ipairs(s.route) do if pos<r.to then return r,i end end
  return s.route[#s.route],#s.route
end
function M.environmentAt(pos,s)
  local r=M.sectionAt(pos,s)
  if r.environmentStart==nil then return r.environment end
  local t=clamp((pos-r.from)/(r.rampLength or r.to-r.from),0,1)
  return r.environmentStart+(r.environment-r.environmentStart)*t*t*(3-2*t)
end
function M.terrainAt(pos,s)
  local area=0
  for _,r in ipairs(s.route) do
    local x=math.max(0,math.min(pos,r.to)-r.from)
    if r.environmentStart==nil then area=area+x*r.environment
    else
      local length=r.rampLength or r.to-r.from
      local t=math.min(1,x/length)
      area=area+r.environmentStart*math.min(x,length)
        +(r.environment-r.environmentStart)*length*(t*t*t-.5*t*t*t*t)
        +math.max(0,x-length)*r.environment
    end
    if pos<r.to then break end
  end
  return {height=area*.048*8,slope=M.environmentAt(pos,s)*.048}
end
function M.accelerationAt(speed,net)
  if speed>=120 and net>=0 then return 0 end
  return net*((speed<53 or (speed==53 and net<0)) and 4 or 8)
end
function M.advanceMotion(speed,net,seconds)
  speed=clamp(speed,0,120)
  local distance,remaining=0,seconds
  while remaining>1e-10 do
    local a=M.accelerationAt(speed,net)
    if speed<=0 and a<=0 then break end
    if a==0 then distance=distance+speed/3.6*remaining;break end
    local duration=remaining
    if a>0 then duration=math.min(duration,((speed<53 and 53 or 120)-speed)/a)
    else duration=math.min(duration,((speed>53 and 53 or 0)-speed)/a) end
    local nextSpeed=clamp(speed+a*duration,0,120)
    distance=distance+(speed+nextSpeed)/2/3.6*duration
    speed=math.abs(nextSpeed-53)<1e-9 and 53 or nextSpeed
    remaining=remaining-duration
  end
  return {speed=speed,distance=distance}
end
function M.stoppingDistance(speed,net)
  if net>=0 then return math.huge end
  local blue=math.min(speed,53)
  return (speed*speed-blue*blue)/(2*(-net*8)*3.6)+blue*blue/(2*(-net*4)*3.6)
end
function M.createState(options)
  options=options or {}
  local mode=options.mode=='endless' and 'endless' or 'trial'
  local seed=math.floor(options.seed or 1)%U32
  local index=math.max(0,math.floor(options.legIndex or 0))
  local leg=mode=='endless' and M.createLeg(seed,index) or {route=trial(),length=4200,difficulty=0}
  return {mode=mode,seed=seed,legIndex=index,route=leg.route,length=leg.length,difficulty=leg.difficulty,
    phase='ready',gear=0,speed=0,position=0,heat=0,lock=0,elapsed=0,score=0,
    distanceScore=0,dockScore=0,penalties=0,perfectScore=0,perfectSections=0,sectionRuns={},
    legalDistance=0,pendingDistance=0,shifts=0,overheats=0,acceleration=0,notice='',noticeUntil=0,
    routeIndex=1,legsCompleted=0,totalDistance=0,totalDockScore=0,
    legStartElapsed=0,legStartScore=0,legStartLegalDistance=0}
end
local function replace(s,fresh)
  for k in pairs(s) do s[k]=nil end
  for k,v in pairs(fresh) do s[k]=v end
end
function M.start(s,options)
  options=options or {}
  local fresh=M.createState({mode=options.mode or s.mode,seed=options.seed or s.seed,legIndex=options.legIndex})
  replace(s,fresh);s.phase='running'
end
local function notify(s,text,seconds) s.notice=text;s.noticeUntil=s.elapsed+(seconds or 3) end
function M.shift(s,direction)
  if s.phase~='running' or s.lock>0 or (direction~=1 and direction~=-1) then return false end
  local gear=clamp(s.gear+direction,-3,3)
  if gear==s.gear then return false end
  s.gear=gear;s.shifts=s.shifts+1;s.heat=math.min(1,s.heat+.25)
  if s.heat>=1-1e-9 then
    s.gear=0;s.lock=3;s.overheats=s.overheats+1
    local penalty=math.min(s.score,200)
    s.score=s.score-penalty;s.penalties=s.penalties+penalty
    notify(s,'轴温过热 · -'..round(penalty)..' 分 · 空档冷却')
  end
  return true
end
local function flush(s)
  s.distanceScore=s.distanceScore+s.pendingDistance
  s.score=s.score+s.pendingDistance;s.pendingDistance=0
end
function M.addDistance(s,from,to,speed)
  local legal=0
  for _,r in ipairs(s.route) do
    if limited(r) and speed>=r.low and speed<=r.high then
      legal=legal+math.max(0,math.min(to,r.to)-math.max(from,r.from))
    end
  end
  s.legalDistance=s.legalDistance+legal;s.pendingDistance=s.pendingDistance+legal
  local points=math.floor((s.pendingDistance+1e-9)/5)*5
  s.pendingDistance=math.max(0,s.pendingDistance-points)
  s.distanceScore=s.distanceScore+points;s.score=s.score+points
end
local function perfect(s,from,to,old,net,dt)
  local function speedAt(pos)
    if pos<=from then return old elseif pos>=to then return s.speed end
    local lo,hi=0,dt
    for _=1,40 do
      local mid=(lo+hi)/2
      if M.advanceMotion(old,net,mid).distance<pos-from then lo=mid else hi=mid end
    end
    return M.advanceMotion(old,net,(lo+hi)/2).speed
  end
  for i,r in ipairs(s.route) do
    if limited(r) and to>=r.from and from<r.to then
      local run=s.sectionRuns[i]
      if not run then run={entered=from<=r.from,perfect=true,covered=0};s.sectionRuns[i]=run end
      if not run.settled then
        run.covered=run.covered+math.max(0,math.min(to,r.to)-math.max(from,r.from))
        local a,b=speedAt(math.max(from,r.from)),speedAt(math.min(to,r.to))
        if a<r.low or a>r.high or b<r.low or b>r.high then run.perfect=false end
        if to>=r.to then
          run.settled=true
          if run.entered and run.perfect and run.covered>=r.to-r.from-1e-6 then
            s.perfectSections=s.perfectSections+1;s.perfectScore=s.perfectScore+100;s.score=s.score+100
            notify(s,r.name..' · 完美通过 +100 分',4)
          end
        end
      end
    end
  end
end
local function finish(s,missed)
  flush(s);s.phase='finished'
  local error=math.abs(s.position-s.length)
  s.dockScore=missed and 0 or round(200*clamp(1-error/5,0,1))
  s.score=s.score+s.dockScore;s.totalDockScore=s.totalDockScore+s.dockScore
  if s.mode=='endless' then s.legsCompleted=s.legsCompleted+1 end
  s.result={missed=missed or false,error=error,inTarget=not missed and error<=5,
    legElapsed=s.elapsed-s.legStartElapsed,legScore=s.score-s.legStartScore,
    legLegalDistance=s.legalDistance-s.legStartLegalDistance,ended=false}
end
local function integrate(s,dt)
  local from,old=s.position,s.speed
  s.elapsed=s.elapsed+dt
  if s.lock>0 then
    s.lock=math.max(0,s.lock-dt);s.heat=s.lock/3
    if s.lock<1e-9 then s.lock=0;s.heat=0;notify(s,'冷却完成 · 可以换挡') end
  else s.heat=math.max(0,s.heat-.05*dt) end
  local net=R.traction[s.gear+4]+M.environmentAt(from,s)
  local motion=M.advanceMotion(old,net,dt)
  s.speed=motion.speed;s.position=from+motion.distance
  s.acceleration=M.accelerationAt(s.speed,R.traction[s.gear+4]+M.environmentAt(s.position,s))
  M.addDistance(s,from,s.position,(old+s.speed)/2)
  perfect(s,from,s.position,old,net,dt)
  local r,index=M.sectionAt(s.position,s)
  if index~=s.routeIndex then
    s.routeIndex=index
    s.sectionHint={text=limited(r) and ('进入'..r.name..' · '..r.low..'–'..r.high..' km/h') or (r.name..' · 不限速'),
      color=M.sectionColor(r),untilTime=s.elapsed+4}
  end
  if s.position>=s.length-5 and s.speed<=.3 and s.acceleration<=0 then finish(s,false)
  elseif s.position>=s.length+35 then finish(s,true) end
end
function M.update(s,dt)
  if s.phase~='running' or type(dt)~='number' or dt~=dt or dt==math.huge or dt<=0 then return end
  local remaining=dt
  while remaining>1e-9 and s.phase=='running' do
    local step=math.min(remaining,1/120);integrate(s,step);remaining=remaining-step
  end
end
function M.continueJourney(s)
  if s.mode~='endless' or s.phase~='finished' or not s.result or s.result.ended then return false end
  local fresh=M.createState({mode=s.mode,seed=s.seed,legIndex=s.legIndex+1})
  for _,k in ipairs({'elapsed','score','distanceScore','penalties','perfectScore','perfectSections',
    'legalDistance','shifts','overheats','heat','lock','legsCompleted','totalDockScore'}) do fresh[k]=s[k] end
  fresh.totalDistance=s.totalDistance+s.position
  fresh.legStartElapsed=s.elapsed;fresh.legStartScore=s.score;fresh.legStartLegalDistance=s.legalDistance
  fresh.phase='running';replace(s,fresh);return true
end
function M.endJourney(s)
  if s.mode~='endless' or s.phase=='ready' or (s.result and s.result.ended) then return false end
  flush(s);s.phase='finished';s.result=s.result or {};s.result.ended=true;return true
end
function M.pause(s)
  if s.phase=='running' then s.phase='paused';return true
  elseif s.phase=='paused' then s.phase='running';return true end
  return false
end
function M.sectionColor(r)
  if not limited(r) then return '#99adb6' end
  return r.high<=52 and '#74bec9' or r.high<=84 and '#98bfa4' or r.high<=108 and '#d9a76a' or '#d97b72'
end
function M.approachAt(pos,s)
  if limited(M.sectionAt(pos,s)) then return nil end
  for _,r in ipairs(s.route) do
    if limited(r) and r.from>pos then
      if r.from-pos<=(r.leadDistance or 80) then return {section=r,distance=r.from-pos,color=M.sectionColor(r)} end
      return nil
    end
  end
end
-- UI 数据契约：针角、温度总角 210°、目标环、进度段均来自同一个状态。
function M.view(s)
  local r=M.sectionAt(s.position,s)
  local segments={}
  for i,t in ipairs(s.route) do
    segments[i]={from=t.from/s.length,to=t.to/s.length,color=M.sectionColor(t),limited=limited(t)}
  end
  return {speedAngle=180*clamp(s.speed/120,0,1),temperatureAngle=210*s.heat,
    temperaturePercent=round(s.heat*100),target=limited(r) and (r.low..'–'..r.high..' km/h') or '不限速',
    targetFrom=limited(r) and r.low/120 or nil,targetTo=limited(r) and r.high/120 or nil,
    targetColor=M.sectionColor(r),progress=clamp(s.position/s.length,0,1),segments=segments,
    environment=M.environmentAt(s.position,s),terrain=M.terrainAt(s.position,s),
    approach=M.approachAt(s.position,s),docking=s.length-s.position<=100,
    totalDistance=s.totalDistance+s.position,phase=s.phase}
end
return M

end)()
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
