/* Browser + Node: gameplay has no DOM dependency. See README for rule provenance. */
(function (root, factory) {
  const api = factory(typeof module==='object'&&module.exports?require('./endless.js'):root.TrainEndless);
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.TrainGame = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function (Endless) {
  'use strict';
  const RULES = Object.freeze({
    traction: Object.freeze([-6, -5, -4, -1, 2, 3, 4]),
    heatPerShift: .25, cooling: .05, overheatSeconds: 3, overheatPenalty: 200,
    // User calibration: net acceleration ±0.5 means needle motion ±6 degrees/s.
    // Linear 180-degree gauge with 120 km/h display range: 12 * 120 / 180 = 8.
    needleDegreesPerAcceleration: 12,
    blueResponseFactor: .5,
    accelerationScale: 12 * 120 / 180, maxSpeed: 120, scoreStep: 5, pointsPerMeter: 1,
    perfectSectionPoints: 100,
    dockingDistance: 100, dockingTolerance: 5, dockingPoints: 200,
    stopSpeed: .3, overshootDistance: 35, approachDistance: 80,
    scenePixelsPerMeter: 8
  });
  // Trial level, not recovered official level data. Transition profiles interpolate table endpoints.
  const ROUTE = Object.freeze([
    { from: 0, to: 240, name: '车站出发', environment: 0, low: null, high: null },
    { from: 240, to: 640, name: '平地慢行', environment: 0, low: 20, high: 52, leadDistance: 180 },
    { from: 640, to: 1000, name: '下坡转场', transition: true, environment: 4.5, environmentStart: 0, low: null, high: null },
    { from: 1000, to: 1480, name: '下坡快行', environment: 4.5, low: 85, high: 108, leadDistance: 300 },
    { from: 1480, to: 1950, name: '坡底转场', transition: true, environment: -2.5, environmentStart: 4.5, low: null, high: null },
    { from: 1950, to: 2180, name: '缓坡慢行', environment: -2.5, low: 20, high: 52, leadDistance: 400 },
    { from: 2180, to: 2800, name: '上坡转场', transition: true, environment: -3.5, environmentStart: -2.5, low: null, high: null },
    { from: 2800, to: 3320, name: '上坡巡行', environment: -3.5, low: 53, high: 84, leadDistance: 400 },
    { from: 3320, to: 3690, name: '站前转场', transition: true, environment: -2.5, environmentStart: -3.5, low: null, high: null },
    { from: 3690, to: 3900, name: '站前慢行', environment: -2.5, low: 20, high: 52, leadDistance: 300 },
    { from: 3900, to: 4200, name: '进站停靠', transition: true, environment: 0, environmentStart: -2.5, rampLength: 200, low: null, high: null }
  ].map(Object.freeze));
  const LENGTH = ROUTE[ROUTE.length - 1].to;
  const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
  // Shared display calibration: color arcs, needle and linear marker use these bounds.
  const SPEED_BANDS = Object.freeze([
    {from:0,to:53,color:'#74bec9'}, {from:53,to:85,color:'#98bfa4'},
    {from:85,to:109,color:'#d9a76a'}, {from:109,to:RULES.maxSpeed,color:'#d97b72'}
  ].map(Object.freeze));
  function speedFraction(speed) { return clamp(speed / RULES.maxSpeed, 0, 1); }
  function accelerationAt(speed, net) {
    if(speed>=RULES.maxSpeed&&net>=0)return 0;
    const blue=speed<53||(speed===53&&net<0);
    return net*RULES.accelerationScale*(blue?RULES.blueResponseFactor:1);
  }
  function stoppingDistance(speed, net) {
    if(net>=0)return Infinity;
    const blueSpeed=Math.min(speed,53),normalBrake=-net*RULES.accelerationScale;
    return (speed*speed-blueSpeed*blueSpeed)/(2*normalBrake*3.6)
      +blueSpeed*blueSpeed/(2*normalBrake*RULES.blueResponseFactor*3.6);
  }
  function advanceMotion(speed, net, seconds) {
    speed=clamp(speed,0,RULES.maxSpeed);
    let distance=0,remaining=seconds;
    // Split at the blue boundary, stop and top speed; integrate cruising distance at the cap.
    while(remaining>1e-10) {
      const acceleration=accelerationAt(speed,net);
      if(speed<=0&&acceleration<=0)break;
      if(acceleration===0){distance+=speed/3.6*remaining;break;}
      let duration=remaining;
      if(acceleration>0&&speed<53)duration=Math.min(duration,(53-speed)/acceleration);
      else if(acceleration>0)duration=Math.min(duration,(RULES.maxSpeed-speed)/acceleration);
      else if(acceleration<0&&speed>53)duration=Math.min(duration,(53-speed)/acceleration);
      else if(acceleration<0)duration=Math.min(duration,-speed/acceleration);
      const next=clamp(speed+acceleration*duration,0,RULES.maxSpeed);
      distance+=(speed+next)/2/3.6*duration;
      speed=Math.abs(next-53)<1e-9?53:next;
      remaining-=duration;
    }
    return {speed,distance};
  }
  function speedStatus(speed, section) {
    return !isLimited(section)?'不限速':speed<section.low?'低于限速':speed>section.high?'超速':'速度合规';
  }
  function routeOf(s) { return s?.route||ROUTE; }
  function lengthOf(s) { return s?.length||LENGTH; }
  function sectionAt(position,s) {
    const route=routeOf(s);
    return route.find(r => position < r.to) || route[route.length - 1];
  }
  function environmentAt(position,s) {
    const section=sectionAt(position,s);
    if(section.environmentStart===undefined)return section.environment;
    const length=section.rampLength||section.to-section.from;
    const t=clamp((position-section.from)/length,0,1),blend=t*t*(3-2*t);
    return section.environmentStart+(section.environment-section.environmentStart)*blend;
  }
  function isLimited(section) { return Number.isFinite(section.low) && Number.isFinite(section.high); }
  function sectionColor(section) {
    return !isLimited(section)?'#99adb6':section.high<=52?'#74bec9':section.high<=84?'#98bfa4':section.high<=108?'#d9a76a':'#d97b72';
  }
  function approachAt(position,s) {
    if(isLimited(sectionAt(position,s)))return null;
    const section=routeOf(s).find(r=>isLimited(r)&&r.from>position);
    if(!section||section.from-position>(section.leadDistance||RULES.approachDistance))return null;
    return {section,distance:section.from-position,color:sectionColor(section)};
  }
  // Screen Y grows downward: a positive downhill force makes the track descend to the right.
  // Visual inclination is a calibration, not a claim about the original game's physical slope.
  const slopePerEnvironment=.048;
  function terrainAt(position,s) {
    let area=0;
    for(const section of routeOf(s)) {
      const x=Math.max(0,Math.min(position,section.to)-section.from);
      if(section.environmentStart===undefined)area+=x*section.environment;
      else {
        const length=section.rampLength||section.to-section.from,t=Math.min(1,x/length);
        area+=section.environmentStart*Math.min(x,length)
          +(section.environment-section.environmentStart)*length*(t*t*t-.5*t*t*t*t)
          +Math.max(0,x-length)*section.environment;
      }
      if(position<section.to)break;
    }
    return {height:area*slopePerEnvironment*RULES.scenePixelsPerMeter,slope:environmentAt(position,s)*slopePerEnvironment};
  }
  function createState(options={}) {
    const mode=options.mode==='endless'?'endless':'trial',seed=(options.seed??1)>>>0,legIndex=options.legIndex||0;
    const leg=mode==='endless'?Endless.createLeg(seed,legIndex):{route:ROUTE,length:LENGTH,difficulty:0};
    return { mode,seed,legIndex,route:leg.route,length:leg.length,difficulty:leg.difficulty,
      legsCompleted:0,totalDistance:0,totalDockScore:0,legStartElapsed:0,legStartScore:0,legStartLegalDistance:0,
      phase: 'ready', gear: 0, speed: 0, position: 0, heat: 0, lock: 0,
      elapsed: 0, score: 0, distanceScore: 0, dockScore: 0, penalties: 0,
      perfectScore: 0, perfectSections: 0, sectionRuns: leg.route.map(()=>null),
      legalDistance: 0, pendingDistance: 0, shifts: 0, overheats: 0,
      acceleration: 0, result: null, notice: '', noticeUntil: 0, routeIndex: 0, sectionHint: null };
  }
  function start(s,options={}) { Object.assign(s,createState({mode:s.mode,seed:s.seed,...options}),{phase:'running'}); }
  function continueJourney(s) {
    if(s.mode!=='endless'||s.phase!=='finished'||s.result.ended)return false;
    const keep={};
    for(const key of ['elapsed','score','distanceScore','penalties','perfectScore','perfectSections','legalDistance',
      'shifts','overheats','heat','lock','legsCompleted','totalDockScore'])keep[key]=s[key];
    keep.totalDistance=s.totalDistance+s.position;
    keep.legStartElapsed=s.elapsed;keep.legStartScore=s.score;keep.legStartLegalDistance=s.legalDistance;
    Object.assign(s,createState({mode:s.mode,seed:s.seed,legIndex:s.legIndex+1}),keep,{phase:'running'});
    return true;
  }
  function endJourney(s) {
    if(s.mode!=='endless'||s.phase==='ready'||s.result?.ended)return false;
    flushDistance(s);s.phase='finished';s.result={...(s.result||{}),ended:true};return true;
  }
  function notify(s, text, seconds = 3) { s.notice = text; s.noticeUntil = s.elapsed + seconds; }
  function shift(s, direction) {
    if (s.phase !== 'running' || s.lock > 0 || (direction !== 1 && direction !== -1)) return false;
    const next = clamp(s.gear + direction, -3, 3);
    if (next === s.gear) return false;
    s.gear = next; s.shifts++;
    s.heat = Math.min(1, s.heat + RULES.heatPerShift);
    if (s.heat >= 1 - 1e-9) {
      s.gear = 0; s.lock = RULES.overheatSeconds; s.overheats++;
      const deducted=Math.min(s.score,RULES.overheatPenalty);
      s.penalties += deducted; s.score -= deducted;
      notify(s, `轴温过热 · −${Math.round(deducted)} 分 · 空档冷却`);
    }
    return true;
  }
  function flushDistance(s) {
    // Flush the last incomplete distance quantum, so discretization never loses earned distance.
    s.distanceScore += s.pendingDistance * RULES.pointsPerMeter;
    s.score += s.pendingDistance * RULES.pointsPerMeter; s.pendingDistance = 0;
  }
  function finish(s, missed = false) {
    s.phase = 'finished';flushDistance(s);
    const error = Math.abs(s.position - lengthOf(s));
    s.dockScore = missed ? 0 : Math.round(RULES.dockingPoints * clamp(1 - error / RULES.dockingTolerance, 0, 1));
    s.score += s.dockScore;
    s.totalDockScore+=s.dockScore;
    if(s.mode==='endless')s.legsCompleted++;
    s.result = { missed, error, inTarget: !missed && error <= RULES.dockingTolerance,
      legElapsed:s.elapsed-s.legStartElapsed,legScore:s.score-s.legStartScore,
      legLegalDistance:s.legalDistance-s.legStartLegalDistance,ended:false };
  }
  function addDistance(s, from, to, speed) {
    // Split at route boundaries; a transition cannot award the previous segment's speed band.
    let legal = 0;
    for (const section of routeOf(s)) {
      const metres = Math.max(0, Math.min(to, section.to) - Math.max(from, section.from));
      if (isLimited(section) && speed >= section.low && speed <= section.high) legal += metres;
    }
    s.legalDistance += legal; s.pendingDistance += legal;
    const points = Math.floor((s.pendingDistance + 1e-9) / RULES.scoreStep) * RULES.scoreStep;
    s.pendingDistance = Math.max(0, s.pendingDistance - points);
    s.distanceScore += points * RULES.pointsPerMeter; s.score += points * RULES.pointsPerMeter;
  }
  function integrate(s, dt) {
    const before = s.position, oldSpeed = s.speed;
    s.elapsed += dt;
    if (s.lock > 0) {
      s.lock = Math.max(0, s.lock - dt);
      s.heat = s.lock / RULES.overheatSeconds;
      if (s.lock < 1e-9) { s.lock = 0; s.heat = 0; notify(s, '冷却完成 · 可以换挡'); }
    } else s.heat = Math.max(0, s.heat - RULES.cooling * dt);
    const net=RULES.traction[s.gear + 3] + environmentAt(before,s);
    // The vehicle top speed applies even on unrestricted track and under downhill force.
    const motion=advanceMotion(oldSpeed,net,dt);
    s.speed=motion.speed;s.position+=motion.distance;
    s.acceleration=accelerationAt(s.speed,RULES.traction[s.gear + 3]+environmentAt(s.position,s));
    addDistance(s, before, s.position, (oldSpeed + s.speed) / 2);
    checkPerfectSections(s,before,s.position,oldSpeed,net,dt);
    const entered=sectionAt(s.position,s), index=routeOf(s).indexOf(entered);
    if(index!==s.routeIndex) {
      s.routeIndex=index;
      s.sectionHint={ text:isLimited(entered)?`进入${entered.name}限速段 · ${entered.low}–${entered.high} km/h`:`${entered.name} · ${entered.to-entered.from} m 不限速`,
        color:sectionColor(entered), until:s.elapsed+4 };
    }
    // Evaluate only on an actual stop, never simply on entering the approach bar.
    if (s.position >= lengthOf(s) - RULES.dockingTolerance && s.speed <= RULES.stopSpeed && s.acceleration <= 0) finish(s);
    else if (s.position >= lengthOf(s) + RULES.overshootDistance) finish(s, true);
  }
  function checkPerfectSections(s,from,to,oldSpeed,net,dt) {
    // Only the portion inside the section counts. Solve boundary speeds on the same motion curve.
    const speedAt=position=>{
      if(position<=from)return oldSpeed;
      if(position>=to)return s.speed;
      let low=0,high=dt;
      for(let i=0;i<40;i++) {
        const middle=(low+high)/2;
        if(advanceMotion(oldSpeed,net,middle).distance<position-from)low=middle;else high=middle;
      }
      return advanceMotion(oldSpeed,net,(low+high)/2).speed;
    };
    const route=routeOf(s);
    for(let i=0;i<route.length;i++) {
      const r=route[i];
      if(!isLimited(r)||to<r.from||from>=r.to)continue;
      let run=s.sectionRuns[i];
      if(run?.settled)continue;
      if(!run)run=s.sectionRuns[i]={entered:from<=r.from,perfect:true,covered:0,settled:false};
      run.covered+=Math.max(0,Math.min(to,r.to)-Math.max(from,r.from));
      const first=speedAt(Math.max(from,r.from)),last=speedAt(Math.min(to,r.to));
      if(first<r.low||first>r.high||last<r.low||last>r.high)run.perfect=false;
      if(to>=r.to) {
        run.settled=true;
        if(run.entered&&run.perfect&&run.covered>=r.to-r.from-1e-6) {
          s.perfectSections++;s.perfectScore+=RULES.perfectSectionPoints;s.score+=RULES.perfectSectionPoints;
          notify(s,`${r.name} · 完美通过 +${RULES.perfectSectionPoints} 分`,4);
        }
      }
    }
  }
  function update(s, dt) {
    if (s.phase !== 'running' || !Number.isFinite(dt) || dt <= 0) return;
    // Stable substeps, real elapsed seconds: no hidden 2x fast-forward.
    let remaining = dt;
    while (remaining > 1e-9 && s.phase === 'running') {
      const substep = Math.min(remaining, 1 / 120);
      integrate(s, substep); remaining -= substep;
    }
  }
  return { RULES, ROUTE, LENGTH, SPEED_BANDS, routeOf, lengthOf, speedFraction, speedStatus, accelerationAt, stoppingDistance, advanceMotion, environmentAt, createState, start, continueJourney, endJourney, shift, update, sectionAt, isLimited, sectionColor, approachAt, terrainAt, addDistance };
});
