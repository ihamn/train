/* Seeded station-to-station routes. Physics and scoring remain in game.js. */
(function(root,factory){
  const api=factory();
  if(typeof module==='object'&&module.exports)module.exports=api;else root.TrainEndless=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(){
  'use strict';
  function createLeg(seed,legIndex=0) {
    let randomState=((seed>>>0)+Math.imul(legIndex+1,0x9e3779b9))>>>0;
    const random=()=>{randomState=(Math.imul(randomState,1664525)+1013904223)>>>0;return randomState/4294967296;};
    const varied=(base)=>base+(Math.floor(random()*5)-2)*20;
    const difficulty=Math.min(3,Math.floor(legIndex/3));
    // One downhill trap trip in four. Avoid A→B→A speed-target sequences.
    const special=legIndex%4===3;
    const middleEnvironment=-2.5;
    const highEnvironment=special?4.5:difficulty>=2&&random()<.5?-3.5:-2.5;
    // Keep the final low-speed approach thermally gentle before the flat stopping area.
    const endingEnvironment=-2.5;
    const stages=special?[
      {name:'平地慢行',environment:0,low:20,high:52,length:varied(300)},
      {name:'下坡快行',environment:highEnvironment,low:85,high:108,length:varied(480),gap:varied(640),special:true},
      {name:'上坡巡行',environment:middleEnvironment,low:53,high:84,length:varied(430),gap:varied(660)},
      {name:'站前慢行',environment:endingEnvironment,low:20,high:52,length:varied(240),gap:varied(480)}
    ]:[
      {name:'平地慢行',environment:0,low:20,high:52,length:varied(300)},
      {name:'上坡巡行',environment:middleEnvironment,low:53,high:84,length:varied(430),gap:varied(440)},
      {name:'上坡快行',environment:highEnvironment,low:85,high:108,length:varied(480),gap:varied(440)},
      {name:'站前慢行',environment:endingEnvironment,low:20,high:52,length:varied(240),gap:varied(660)}
    ];
    const route=[{from:0,to:240,name:'车站出发',environment:0,low:null,high:null}];
    let position=240,environment=0;
    for(const stage of stages) {
      if(stage.gap) {
        route.push({from:position,to:position+stage.gap,name:stage.special?'下坡转场':'转场准备',transition:true,
          environmentStart:environment,environment:stage.environment,low:null,high:null,special:!!stage.special});
        position+=stage.gap;
      }
      route.push({from:position,to:position+stage.length,name:stage.name,environment:stage.environment,
        low:stage.low,high:stage.high,leadDistance:stage.gap?Math.min(stage.gap,400):180});
      position+=stage.length;environment=stage.environment;
    }
    route.push({from:position,to:position+300,name:'进站停靠',transition:true,environmentStart:environment,
      environment:0,rampLength:200,low:null,high:null});
    return {route:Object.freeze(route.map(Object.freeze)),length:position+300,difficulty,special};
  }
  return {createLeg};
});
