const G=require('../../prototype/game.js');
// Test-only driver: public shift inputs, real heat/physics, no changes to gameplay state.
module.exports=function driveRoute(options={},settings={}) {
  const s=G.createState(options);G.start(s,options);let lastShift=-10,braking=false;
  for(let frame=0;frame<600*30&&s.phase==='running';frame++) {
    const route=s.route,section=G.sectionAt(s.position,s),index=route.indexOf(section);
    const next=route.slice(index+1).find(G.isLimited),limited=G.isLimited(section);
    const previous=route.slice(0,index).filter(G.isLimited).at(-1);
    const offset=next?(next.low>=85?(next.environment>0?settings.downhillOffset??15:settings.highOffset??15):next.low===53?settings.midOffset??0:0):0;
    const target=next?(next.low+next.high)/2+offset:48;
    const from=previous?(previous.low+previous.high)/2:target;
    const t=Math.min(1,(s.position-section.from)/(section.to-section.from)/.8);
    const goal=limited?(section.low+section.high)/2:target>=from?target:from+(target-from)*t*t*(3-2*t);
    let gear=s.gear;
    if(s.position>=s.length-G.RULES.dockingDistance) {
      if(s.length-s.position<=G.stoppingDistance(s.speed,-1)+.12)braking=true;
      gear=braking?0:1;
    } else {
      const environment=G.environmentAt(s.position,s);
      const choices=G.RULES.traction.map((force,i)=>({gear:i-3,net:force+environment}));
      if(limited) {
        const margin=(section.high-section.low)/2-2;
        const positive=choices.filter(x=>x.net>.1).sort((a,b)=>a.net-b.net)[0];
        const negative=choices.filter(x=>x.net<-.1).sort((a,b)=>b.net-a.net)[0];
        if(s.speed<goal-margin)gear=positive.gear;
        else if(s.speed>goal+margin)gear=negative.gear;
        else if(s.gear!==positive.gear&&s.gear!==negative.gear)gear=s.speed<goal?positive.gear:negative.gear;
      } else {
        const desired=(goal-s.speed)/(s.speed<53?4:8)/(settings.responseTime??10);
        const current=G.RULES.traction[s.gear+3]+environment;
        const best=choices.sort((a,b)=>Math.abs(a.net-desired)-Math.abs(b.net-desired))[0];
        if(Math.abs(current-desired)>Math.abs(best.net-desired)+.3)gear=best.gear;
      }
    }
    if(gear!==s.gear&&s.heat<.74&&s.elapsed-lastShift>=.1){G.shift(s,Math.sign(gear-s.gear));lastShift=s.elapsed;}
    G.update(s,1/30);
  }
  return s;
};
