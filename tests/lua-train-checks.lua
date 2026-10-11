local G=dofile('workspace/train/train_core.lua')
local function near(a,b) assert(math.abs(a-b)<1e-6,tostring(a)..' ~= '..tostring(b)) end
local s=G.createState({mode='endless',seed=42});G.start(s)
assert(G.environmentAt(0,s)==0 and not G.isLimited(G.sectionAt(0,s)))
assert(G.shift(s,1) and G.shift(s,1) and G.shift(s,1) and G.shift(s,-1))
assert(s.score==0 and s.gear==0 and s.lock==3 and s.overheats==1)
G.update(s,3.1);assert(s.lock==0 and s.heat==0 and s.score==0)
near(G.advanceMotion(60,.5,6).speed,84)
near(G.advanceMotion(0,1,6).speed,24) -- 蓝色净 +1 = 6°/s
near(G.advanceMotion(24,-1,6).speed,0)
local cap=G.advanceMotion(119,10,2);near(cap.speed,120);assert(cap.distance>66)
s.heat=.5;near(G.view(s).temperatureAngle,105)
for _=1,24 do
  s.position=s.length;s.speed=.2;s.gear=-3;s.heat=.5;s.lock=2
  G.update(s,.01);assert(s.phase=='finished')
  local heat,lock,score=s.heat,s.lock,s.score
  local total=s.totalDistance+s.position
  assert(G.continueJourney(s));assert(s.position==0 and s.gear==0 and #s.route==9)
  assert(next(s.sectionRuns)==nil and s.score==score and s.heat==heat and s.lock==lock)
  near(s.totalDistance,total)
end
assert(s.legsCompleted==24)
G.addDistance(s,240,247,36);local earned=s.score+s.pendingDistance
G.pause(s);assert(G.endJourney(s));near(s.score,earned)
assert(not G.endJourney(s) and not G.continueJourney(s))
G.start(s);assert(s.legIndex==0 and s.score==0 and s.phase=='running')
-- 精确入口/出口速度：从限速外加速进入，仅区间内检查；奖励只发一次。
s=G.createState();G.start(s)
s.route={{from=0,to=1,name='准备',environment=0},
  {from=1,to=3,name='限速',environment=0,low=20,high=52},
  {from=3,to=100,name='结束',environment=0}};s.length=100
s.position=.99;s.speed=36;s.gear=0
for _=1,12 do G.update(s,1/30) end
assert(s.perfectSections==1 and s.perfectScore==100)
G.update(s,.1);assert(s.perfectSections==1)
-- 区间内一次违规，即使恢复也不能补领完美奖励。
s=G.createState();G.start(s);s.position=240;s.speed=19;s.gear=1
G.update(s,.1);assert(s.sectionRuns[2] and not s.sectionRuns[2].perfect)
-- 客户端薄层 mock：验证命名/点击接线/更新/异常停止，不替代真机 API 验证。
local children={}
local function control(name)
  local c={name=name}
  function c:SetAnchoredPosition(x,y) self.x=x;self.y=y end
  function c:SetSizeDelta(w,h) self.w=w;self.h=h end
  function c:SetActive(on) self.on=on end
  function c:AddCursorEventListener(_,fn) self.click=fn end
  children[name]=c;return c
end
local root={}
function root:FindChild(path) return children[path] end
for _,n in ipairs({'SPEED','GEAR','TEMP','SCORE','TARGET','STATUS','HINT','HINT_BG',
  'START','UP','DOWN','PAUSE','CONTINUE','END','TRIAL','ENDLESS'}) do control(n) end
control('PROGRESS/PROGRESS_MARKER');control('DIAL/TARGET_RANGE')
for i=1,11 do control('PROGRESS/SEG'..i) end
for i=1,4 do control('SCENE/TIE'..i) end
for i=0,36 do control('SPEED_F'..i) end
for i=0,42 do control('TEMP_F'..i) end
script={object=root};function script:EnableUpdate(on) self.enabled=on end
Enum={CursorEventType={CursorClick=1}}
dofile('workspace/train/train_game.lua');OnInit();OnStart()
assert(script.enabled and children.TARGET.text=='不限速')
children.START.click();children.UP.click();OnUpdate(.2)
assert(children.SPEED.text~='0.0 km/h' and children.GEAR.text=='1')
children.PAUSE.click();OnUpdate(.2);assert(children.STATUS.text=='已暂停')
children.PAUSE.click();OnUpdate(1);assert(children.STATUS.text=='已暂停')
children.END.click();OnUpdate(.2);assert(children.STATUS.text=='旅程结束')
children.TRIAL.click();children.START.click();OnUpdate(.2)
assert(children.STATUS.text:find('第 1 站'))
-- 错误只停一次；后续帧没有 UI 写入。
children.SPEED.text=nil
children['SCENE/TIE1'].SetAnchoredPosition=function() error('mock API failure') end
children.UP.click();OnUpdate(.2);assert(not script.enabled)
print('Lua core and client checks passed')
