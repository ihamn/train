const {test}=require('node:test');
const assert=require('node:assert/strict');
const G=require('../prototype/game.js'),E=require('../prototype/endless.js');
const drive=require('./helpers/reference-driver.cjs');
const near=(a,b)=>assert.ok(Math.abs(a-b)<1e-6,`${a} != ${b}`);
function arrive(s){s.position=s.length;s.speed=.2;s.gear=-3;G.update(s,.01);assert.equal(s.phase,'finished');}

test('seeded routes are reproducible, vary between trips, and bound challenge density',()=>{
  assert.deepEqual(E.createLeg(42,3),E.createLeg(42,3));
  assert.notDeepEqual(E.createLeg(42,0).route,E.createLeg(42,1).route);
  for(const seed of [0,1,42,0xffffffff])for(let legIndex=0;legIndex<32;legIndex++) {
    const s=G.createState({mode:'endless',seed,legIndex}),limited=s.route.filter(G.isLimited);
    assert.equal(s.route.length,9);assert.equal(limited.length,4);assert.ok(s.length>=3000&&s.length<=4200);
    assert.ok(s.difficulty<=3);assert.equal(s.route.filter(r=>r.special).length,legIndex%4===3?1:0);
    for(let i=1;i<limited.length;i++)assert.notEqual(limited[i].low,limited[i-1].low);
    for(let i=2;i<limited.length;i++)assert.notEqual(limited[i].low,limited[i-2].low,'avoid A→B→A targets');
    for(let i=1;i<s.route.length;i++) {
      const r=s.route[i],prev=s.route[i-1];assert.equal(prev.to,r.from);
      near(G.environmentAt(r.from-.0001,s),G.environmentAt(r.from+.0001,s));
      if(r.transition&&i<s.route.length-1)assert.ok(r.to-r.from>=400);
    }
    for(const r of limited) {
      const nets=G.RULES.traction.map(f=>f+r.environment);assert.ok(nets.some(n=>n>0)&&nets.some(n=>n<0));
      assert.equal(G.approachAt(r.from,s),null);
    }
    near(G.environmentAt(s.length-100,s),0);near(G.environmentAt(s.length,s),0);
    assert.equal(G.isLimited(G.sectionAt(0,s)),false);
  }
});
test('station continuation retains cumulative results, temperature and only the current route',()=>{
  const s=G.createState({mode:'endless',seed:42});G.start(s);
  assert.equal(G.continueJourney(s),false);
  for(let trip=0;trip<24;trip++) {
    const route=s.route;s.score+=100;s.perfectScore+=100;s.perfectSections++;s.heat=.5;s.lock=2;
    arrive(s);const score=s.score,dock=s.totalDockScore,elapsed=s.elapsed,heat=s.heat,lock=s.lock,distance=s.totalDistance+s.position;
    assert.equal(s.legsCompleted,trip+1);assert.equal(G.continueJourney(s),true);
    assert.equal(s.score,score);assert.equal(s.totalDockScore,dock);assert.equal(s.elapsed,elapsed);
    assert.equal(s.heat,heat);assert.equal(s.lock,lock);near(s.totalDistance,distance);
    assert.equal(s.position,0);assert.equal(s.gear,0);assert.equal(s.legIndex,trip+1);
    assert.equal(s.sectionRuns.length,9);assert.ok(s.sectionRuns.every(x=>x===null));assert.notEqual(s.route,route);
    assert.equal(s.perfectSections,trip+1);assert.equal(G.continueJourney(s),false);
  }
});
test('ending a journey flushes earned distance once without inventing docking rewards; retry resets',()=>{
  const s=G.createState({mode:'endless',seed:7});G.start(s);const initial=s.route;
  G.addDistance(s,240,247,36);const expected=s.score+s.pendingDistance;
  s.phase='paused';assert.equal(G.endJourney(s),true);assert.equal(s.score,expected);assert.equal(s.dockScore,0);
  assert.equal(s.result.ended,true);assert.equal(G.endJourney(s),false);assert.equal(G.continueJourney(s),false);
  G.start(s);assert.equal(s.score,0);assert.equal(s.legIndex,0);assert.deepEqual(s.route,initial);
});
test('generated routes have complete legal, zero-overheat reference solutions including downhill trips',()=>{
  const times=[];
  for(const seed of [1,2,7,42])for(const legIndex of [0,3,6]) {
    let solved=null;
    // Try distinct preparation choices; existence of a solution does not imply automatic assistance.
    for(const midOffset of [-5,-30,-13]) {
      const s=drive({mode:'endless',seed,legIndex},{midOffset,highOffset:5,downhillOffset:25});
      if(s.phase==='finished'&&s.result.inTarget&&s.overheats===0&&s.perfectSections===4){solved=s;break;}
    }
    assert.ok(solved,`no full compliant reference solution for seed=${seed}, trip=${legIndex}`);
    near(solved.legalDistance,solved.route.filter(G.isLimited).reduce((n,r)=>n+r.to-r.from,0));
    assert.equal(solved.perfectScore,400);assert.ok(solved.elapsed<360);times.push(solved.elapsed);
  }
  console.log(`Endless reference trips: ${Math.min(...times).toFixed(1)}–${Math.max(...times).toFixed(1)} seconds`);
});
