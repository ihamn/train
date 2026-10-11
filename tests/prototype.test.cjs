const { test } = require('node:test');
const assert = require('node:assert/strict');
const G = require('../prototype/game.js');
const running = () => { const s=G.createState(); G.start(s); return s; };
const near = (a,b,tolerance=1e-6) => assert.ok(Math.abs(a-b)<=tolerance,`${a} != ${b}`);

test('speed color boundaries and needle share calibration; compliance uses actual speed',()=>{
  assert.deepEqual(G.SPEED_BANDS.map(b=>b.from),[0,53,85,109]);
  for(const band of G.SPEED_BANDS) {
    near(G.speedFraction(band.from)*180,band.from/G.RULES.maxSpeed*180);
    if(band.to<G.RULES.maxSpeed)assert.equal(band.to,G.SPEED_BANDS[G.SPEED_BANDS.indexOf(band)+1].from);
  }
  const section=G.ROUTE.find(r=>r.low===53);
  assert.equal(G.speedStatus(52.9,section),'低于限速');
  assert.equal(G.speedStatus(53,section),'速度合规');
  assert.equal(G.speedStatus(84,section),'速度合规');
  assert.equal(G.speedStatus(84.1,section),'超速');
  assert.equal(G.speedStatus(150,G.ROUTE[0]),'不限速');
  assert.equal(G.speedFraction(150),1);assert.equal(G.speedFraction(-1),0);
});

test('net ±0.5 traverses green in 8 s and orange in 6 s; ±1.5 is three times faster',()=>{
  for(const [gear,sign,multiplier] of [[2,1,1],[1,-1,1],[3,1,3]]) {
    for(const [from,to,seconds] of [[53,85,8],[85,109,6]]) {
      const s=running();s.position=1950;s.gear=gear;s.speed=sign>0?from:to;
      const angleBefore=G.speedFraction(s.speed)*180;
      G.update(s,seconds/multiplier);
      near(s.speed,sign>0?to:from);
      const angularRate=(G.speedFraction(s.speed)*180-angleBefore)/(seconds/multiplier);
      near(angularRate,sign*6*multiplier);

    }
  }
});

test('blue compensates net ±1 to ±6 degrees/s and keeps motion continuous at its boundary',()=>{
  for(const net of [-1,1]) {
    const from=net>0?10:40,motion=G.advanceMotion(from,net,2);
    near((G.speedFraction(motion.speed)-G.speedFraction(from))*180/2,net*6);
  }
  // 52→53 takes .25 s in blue; the remaining .75 s advances 6 km/h in green.
  const up=G.advanceMotion(52,1,1);near(up.speed,59);
  const down=G.advanceMotion(54,-1,1);near(down.speed,49.5);
  for(const [speed,net] of [[52,1],[54,-1]]) {
    const whole=G.advanceMotion(speed,net,1);let v=speed,distance=0;
    for(let i=0;i<120;i++){const step=G.advanceMotion(v,net,1/120);v=step.speed;distance+=step.distance;}
    near(v,whole.speed);near(distance,whole.distance);
  }
  near(G.advanceMotion(53,-1,13.25).speed,0);
  near(G.stoppingDistance(53,-1),G.advanceMotion(53,-1,20).distance);
});

test('seven signed gears and documented traction table, not target speeds',()=>{
  assert.deepEqual(G.RULES.traction,[-6,-5,-4,-1,2,3,4]);
  const s=running();s.gear=3;assert.equal(G.shift(s,1),false);s.gear=-3;assert.equal(G.shift(s,-1),false);
  s.gear=0;s.speed=40;G.update(s,.5);near(s.speed,38);
  s.position=1950;s.speed=40;s.gear=0;G.update(s,.5);near(s.speed,33);
  s.position=1950;s.speed=40;s.gear=1;G.update(s,.5);near(s.speed,39);
});
test('normal cooling is one quarter per five real seconds',()=>{
  const s=running();G.shift(s,1);near(s.heat,.25);G.update(s,5);near(s.heat,0);near(s.elapsed,5);
});
test('overheat deducts 200 once, forces neutral, locks 3 seconds, then reaches zero',()=>{
  const s=running();s.score=500;
  for(const direction of [1,1,1,-1])G.shift(s,direction);
  assert.equal(s.score,300);assert.equal(s.gear,0);assert.equal(s.overheats,1);
  assert.equal(G.shift(s,1),false);G.update(s,2.99);assert.ok(s.lock>0);assert.equal(G.shift(s,1),false);
  G.update(s,.02);near(s.heat,0);near(s.lock,0);assert.equal(G.shift(s,1),true);
});
test('overheat cannot reduce total score below zero and records only the actual deduction',()=>{
  for(const score of [0,75,200,300]) {
    const s=running();s.score=score;
    for(const direction of [1,1,1,-1])G.shift(s,direction);
    assert.equal(s.score,Math.max(0,score-200));assert.equal(s.penalties,Math.min(score,200));
    assert.equal(s.gear,0);assert.equal(s.lock,3);
  }
});
test('equal legal distances award equal points, irrespective of travel time',()=>{
  const slow=running(),fast=running();G.addDistance(slow,240,340,30);G.addDistance(fast,240,340,40);
  assert.equal(slow.score,100);assert.equal(fast.score,100);
  G.addDistance(slow,340,390,90);assert.equal(slow.score,100);
});
test('distance crossing route boundary uses each segment speed range',()=>{
  const s=running();G.addDistance(s,230,250,60);near(s.legalDistance,0);near(s.score,0);
  const fast=running();G.addDistance(fast,230,250,40);near(fast.legalDistance,10);
});
function passFirstRestriction(change) {
  const s=running();s.position=239.9;s.speed=36;let changed=false;
  while(s.position<640) {
    if(change&&!changed&&s.position>300){change(s);changed=true;}
    const gear=s.speed<25?1:s.speed>45?0:s.gear;
    if(gear!==s.gear)G.shift(s,Math.sign(gear-s.gear));
    G.update(s,1/30);
    if(s.position<640)assert.equal(s.perfectScore,0,'reward only after the exit');
  }
  return s;
}
test('full compliant section awards one bonus, retains distance points, and resets on restart',()=>{
  const s=passFirstRestriction();assert.equal(s.perfectSections,1);
  assert.equal(s.perfectScore,G.RULES.perfectSectionPoints);near(s.distanceScore,400);
  near(s.score,400+G.RULES.perfectSectionPoints);assert.match(s.notice,/完美通过 \+100 分/);
  G.update(s,1);assert.equal(s.perfectSections,1);assert.equal(s.perfectScore,100);
  G.start(s);assert.equal(s.perfectScore,0);assert.equal(s.perfectSections,0);assert.ok(s.sectionRuns.every(x=>x===null));
});
test('even a brief over/underspeed forfeits only that section bonus',()=>{
  for(const speed of [19.99,52.001]) {
    const s=passFirstRestriction(s=>{s.speed=speed;G.update(s,1/120);s.speed=36;});
    assert.equal(s.perfectScore,0);assert.equal(s.perfectSections,0);
    assert.ok(s.distanceScore>390,'ordinary legal distance points remain');
  }
});
test('perfect check uses actual entry/exit speeds and cannot reward a partial section',()=>{
  const entry=running();entry.position=239.9;entry.speed=52.004;entry.gear=0;G.update(entry,.02);
  assert.equal(entry.sectionRuns[1].perfect,true,'overspeed before entry must not invalidate the section');
  const exit=running();exit.position=639.99;exit.speed=51.99;exit.gear=1;
  exit.sectionRuns[1]={entered:true,perfect:true,covered:399.99,settled:false};G.update(exit,.02);
  assert.ok(exit.speed>52);assert.equal(exit.perfectScore,100,'overspeed after exit must not invalidate the section');
  const partial=running();partial.position=639.99;partial.speed=36;G.update(partial,.02);
  assert.equal(partial.perfectScore,0);
  const stationary=running();stationary.position=240;G.update(stationary,.01);
  assert.equal(stationary.sectionRuns[1].perfect,false,'illegal speed counts even while standing still');
});
test('departure is flat and unrestricted, contributes no speed-maintenance score',()=>{
  const section=G.sectionAt(0);assert.equal(section.environment,0);assert.equal(G.isLimited(section),false);
  const s=running();G.addDistance(s,0,180,1);G.addDistance(s,0,180,150);assert.equal(s.score,0);
  s.speed=119;s.gear=1;G.update(s,.5);near(s.speed,G.RULES.maxSpeed);
});
test('vehicle top speed includes downhill force and integrates cruising distance exactly',()=>{
  // 116→120 at net +1 takes .5 s; the remaining .5 s travels at 120.
  const whole=G.advanceMotion(116,1,1);near(whole.speed,120);
  near(whole.distance,(116+120)/2/3.6*.5+120/3.6*.5);
  let speed=116,distance=0;
  for(let i=0;i<120;i++){const step=G.advanceMotion(speed,1,1/120);speed=step.speed;distance+=step.distance;}
  near(speed,whole.speed);near(distance,whole.distance);
  near(G.accelerationAt(120,8.5),0);assert.ok(G.accelerationAt(120,-.5)<0);
  near(G.advanceMotion(120,8.5,2).distance,120/3.6*2);
  near(G.advanceMotion(120,-.5,1).speed,116);
  const s=running();s.position=1100;s.speed=119;s.gear=3;const before=s.position;
  G.update(s,1);near(s.speed,120);near(s.acceleration,0);
  assert.ok(s.position-before<=120/3.6);assert.equal(G.speedStatus(s.speed,G.sectionAt(s.position)),'超速');
  s.gear=-2;G.update(s,1);near(s.speed,116);
});
test('standing still never earns distance points',()=>{
  const s=running();s.position=G.LENGTH-50;G.update(s,30);assert.equal(s.score,0);assert.equal(s.phase,'running');
});
test('entering docking range does not settle; an actual stop settles once',()=>{
  const s=running();s.position=G.LENGTH-8;s.speed=3.6;s.gear=0;G.update(s,.5);assert.equal(s.phase,'running');assert.equal(s.dockScore,0);
  s.position=G.LENGTH;s.speed=.2;s.gear=-3;G.update(s,.1);assert.equal(s.phase,'finished');assert.ok(s.dockScore>=199);
  const score=s.score;G.update(s,20);G.shift(s,1);assert.equal(s.score,score);
});
test('passing station at speed gives no docking points, overshoot still ends trip',()=>{
  const s=running();s.position=G.LENGTH-1;s.speed=30;s.gear=0;G.update(s,.5);assert.equal(s.phase,'running');assert.equal(s.dockScore,0);
  s.position=G.LENGTH+34;s.speed=30;G.update(s,.5);assert.equal(s.phase,'finished');assert.equal(s.dockScore,0);assert.equal(s.result.missed,true);
});
test('fixed substeps make normal frame rates give consistent simulation',()=>{
  const a=running(),b=running();a.gear=b.gear=1;
  for(let i=0;i<300;i++)G.update(a,1/30);for(let i=0;i<600;i++)G.update(b,1/60);
  near(a.position,b.position);near(a.speed,b.speed);near(a.score,b.score);
});
test('pause freezes every simulation counter and restart clears prior outcome',()=>{
  const s=running();s.phase='paused';const snapshot=JSON.stringify(s);G.update(s,10);assert.equal(JSON.stringify(s),snapshot);
  Object.assign(s,{phase:'finished',score:300,gear:-2,position:G.LENGTH,result:{missed:false}});G.start(s);assert.deepEqual(s,running());
});
test('hidden image with natural dimensions still renders a right-facing train',()=>{
  const draw=require('../prototype/scene.js');
  for(const height of [120,260,540,1040]) {
    const calls=[];
    const ctx=new Proxy({canvas:{width:960,height}}, {get:(target,key)=>key in target?target[key]:(...args)=>calls.push([key,...args]),set:(target,key,value)=>(target[key]=value,true)});
    draw(ctx,{position:0,elapsed:0},{width:0,naturalWidth:240,naturalHeight:66});
    assert.equal(calls.filter(c=>c[0]==='drawImage').length,1,'hidden DOM image must not be omitted');
    assert.ok(calls.some(c=>c[0]==='scale'&&c[1]===-1&&c[2]===1),'train must face right');
  }
});
test('route has varied preparation distances and fewer continuous restrictions',()=>{
  const gaps=G.ROUTE.filter(r=>r.transition);assert.equal(gaps.length,5);assert.equal(G.LENGTH,4200);assert.deepEqual(gaps.map(r=>r.to-r.from),[360,470,620,370,300]);
  assert.equal(G.ROUTE.filter(G.isLimited).reduce((sum,r)=>sum+r.to-r.from,0),1840);
  for(const gap of gaps){assert.equal(G.isLimited(gap),false);const s=running();G.addDistance(s,gap.from,gap.to,60);assert.equal(s.score,0);}
  for(let i=1;i<G.ROUTE.length;i++)assert.equal(G.ROUTE[i].from,G.ROUTE[i-1].to);
});
test('entering a restriction emits a timed hint with the same route color',()=>{
  const s=running();s.position=239.99;s.speed=60;G.update(s,.02);
  assert.match(s.sectionHint.text,/进入平地慢行限速段.*20–52/);
  assert.equal(s.sectionHint.color,G.sectionColor(G.sectionAt(s.position)));assert.ok(s.sectionHint.until>s.elapsed);
  G.update(s,4.1);assert.ok(s.sectionHint.until<s.elapsed);
  s.position=639.99;s.speed=60;G.update(s,.02);assert.match(s.sectionHint.text,/360 m 不限速/);
});
test('visual terrain and train pitch agree with the same environment used by physics',()=>{
  const draw=require('../prototype/scene.js');
  for(const [position,sign] of [[0,0],[300,0],[1100,1],[1600,1],[2000,-1]]) {
    const terrain=G.terrainAt(position);assert.equal(Math.sign(terrain.slope),sign);
    if(position>0)near((G.terrainAt(position+.01).height-G.terrainAt(position-.01).height)/(.02*G.RULES.scenePixelsPerMeter),terrain.slope);
    const rotations=[];
    const ctx=new Proxy({canvas:{width:960,height:540}}, {get:(t,k)=>k in t?t[k]:k==='rotate'?angle=>rotations.push(angle):()=>{},set:(t,k,v)=>(t[k]=v,true)});
    draw(ctx,{position,elapsed:0},{naturalWidth:240});assert.equal(Math.sign(rotations[0]),sign);
  }
  const s=running();s.position=1100;s.speed=40;s.gear=0;G.update(s,.5);assert.ok(s.speed>40,'downhill neutral accelerates');
});

test('unrestricted gaps allow normal speed control and never overlap an active speed warning',()=>{
  for(const gap of G.ROUTE.filter(r=>r.transition)) {
    assert.equal(G.isLimited(gap),false);
    for(const [gear,direction] of [[-3,-1],[3,1]]) {
      const s=running();s.position=(gap.from+gap.to)/2;s.speed=60;s.gear=gear;
      G.update(s,.5);assert.equal(Math.sign(s.speed-60),direction);assert.equal(s.lock,0);
      assert.equal(G.shift(s,gear===-3?1:-1),true);
    }
  }
  for(const section of G.ROUTE.filter(G.isLimited))assert.equal(G.approachAt(section.to-.01),null);
  assert.equal(G.approachAt(700).section.from,1000);
  assert.equal(G.RULES.dockingDistance,100);
});
test('terrain and environmental force blend continuously before speed restrictions',()=>{
  for(const gap of G.ROUTE.filter(r=>r.transition)) {
    near(G.environmentAt(gap.from),gap.environmentStart);
    near(G.environmentAt(gap.to),gap.environment);
    const end=gap.from+(gap.rampLength||gap.to-gap.from);
    near(G.environmentAt((gap.from+end)/2),(gap.environmentStart+gap.environment)/2);
  }
  for(const boundary of G.ROUTE.slice(1).map(r=>r.from).concat(4100)) {
    near(G.environmentAt(boundary-.001),G.environmentAt(boundary+.001));
    near(G.terrainAt(boundary-.001).slope,G.terrainAt(boundary+.001).slope);
  }
  assert.equal(G.environmentAt(4100),0);assert.equal(G.environmentAt(4199),0);
});
test('unrestricted downhill can require braking even when the next limit is higher',()=>{
  assert.ok(G.sectionAt(600).high<G.sectionAt(1000).low);
  assert.equal(G.isLimited(G.sectionAt(950)),false);
  const coast=running(),brake=running();coast.position=brake.position=950;
  coast.speed=brake.speed=100;coast.gear=0;brake.gear=-2;
  G.update(coast,.5);G.update(brake,.5);
  assert.ok(coast.speed>100);assert.ok(brake.speed<100);
});
test('advance restriction warning appears before entry and clears at the boundary',()=>{
  assert.equal(G.approachAt(59),null);
  const warning=G.approachAt(60);assert.equal(warning.distance,180);assert.equal(warning.section.from,240);
  assert.equal(warning.color,G.sectionColor(warning.section));assert.ok(G.approachAt(239.99));
  assert.equal(G.approachAt(240),null);
  assert.equal(G.approachAt(1550).section.from,1950);
  assert.equal(G.approachAt(2400).section.from,2800);
  assert.equal(G.approachAt(G.LENGTH),null);
});
test('rendered sleepers move with physical distance, rather than a constant animation timer',()=>{
  const draw=require('../prototype/scene.js');
  function sleeperX(s) {
    let color,path=[],first=null;
    const ctx=new Proxy({canvas:{width:960,height:540}}, {get:(t,k)=>k in t?t[k]:k==='beginPath'?()=>path=[]:k==='moveTo'||k==='lineTo'?(x,y)=>path.push([x,y]):k==='fill'?()=>{if(color==='#596775'&&first===null)first=path[0][0];}:()=>{},set:(t,k,v)=>{t[k]=v;if(k==='fillStyle')color=v;return true;}});
    draw(ctx,s,null);return first;
  }
  const slow=running(),fast=running();slow.speed=30;fast.speed=60;
  const initial=sleeperX(slow);G.update(slow,.1);G.update(fast,.1);
  near(initial-sleeperX(slow),slow.position*G.RULES.scenePixelsPerMeter);
  near(initial-sleeperX(fast),fast.position*G.RULES.scenePixelsPerMeter);
  assert.ok(initial-sleeperX(fast)>(initial-sleeperX(slow))*1.9);
  const parked=running(),before=sleeperX(parked);G.update(parked,1);assert.equal(sleeperX(parked),before);
});

test('a reference driver covers the route in 240–300 seconds with no overheat',()=>{
  const s=require('./helpers/reference-driver.cjs')();
  assert.equal(s.phase,'finished');assert.equal(s.overheats,0);
  near(s.legalDistance,1840,1e-5);
  assert.equal(s.result.inTarget,true);
  assert.ok(s.elapsed>=240&&s.elapsed<=300,`trip took ${s.elapsed} seconds`);
});
