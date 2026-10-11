(function (root, factory) {
  const draw = factory(typeof module === 'object' && module.exports ? require('./game.js') : root.TrainGame);
  if (typeof module === 'object' && module.exports) module.exports = draw;
  else root.drawTrainScene = draw;
})(typeof globalThis !== 'undefined' ? globalThis : this, function (G) {
  'use strict';
  const W = 960, H = 540;
  const hash = n => { const v = Math.sin(n * 127.1 + 311.7) * 43758.5453; return v - Math.floor(v); };
  function polygon(c, points, color) {
    c.fillStyle = color; c.beginPath(); points.forEach(([x,y],i)=>i ? c.lineTo(x,y) : c.moveTo(x,y)); c.closePath(); c.fill();
  }
  function mountain(c, y, seed, color, offset=0) {
    const pts = [[-60,H]];
    const origin=Math.floor(offset/60)*60;
    for(let x=-60;x<=W+60;x+=60) pts.push([x+origin-offset, y - Math.floor(hash(x+origin+seed)*100/6)*6]);
    pts.push([W,H]); polygon(c,pts,color);
  }
  function pine(c,x,y,size) {
    x=Math.round(x); y=Math.round(y); size=Math.round(size);
    c.fillStyle='#617787'; c.fillRect(x-3,y-size*.15,6,size*.2);
    for(let i=0;i<3;i++) {
      const top=y-size+i*size*.22, half=size*(.17+i*.07);
      polygon(c,[[x,top],[x-half,top+size*.45],[x+half,top+size*.45]],i===2?'#2d485a':'#35566a');
      polygon(c,[[x,top],[x-half*.65,top+size*.3],[x+half*.15,top+size*.3]],'#a5c0cb');
    }
  }
  return function draw(c,state,train) {
    const metresToPixels=G.RULES.scenePixelsPerMeter, scroll=state.position*metresToPixels;
    // Fit the camera to the actual canvas; CSS cover cropping must never hide the train.
    const vw=c.canvas.width, vh=c.canvas.height;
    const zoom=Math.min(1,vw/600,vh/260);
    c.save(); c.imageSmoothingEnabled=false; c.clearRect(0,0,vw,vh);
    c.fillStyle='#182e42';c.fillRect(0,0,vw,vh);
    c.fillStyle='#d0dce0';c.fillRect(0,vh*.66,vw,vh*.34);
    c.translate(vw/2-480*zoom,vh*.66-330*zoom);c.scale(zoom,zoom);
    c.fillStyle='#182e42'; c.fillRect(0,0,W,H);
    c.fillStyle='#254054'; c.fillRect(0,64,W,108);
    // Stepped silhouettes and limited palette, instead of blurred gradients.
    mountain(c,230,17,'#3c586a',scroll*.08); mountain(c,295,43,'#6c899a',scroll*.14); mountain(c,320,12,'#8da7b6',scroll*.22);
    polygon(c,[[0,307],[135,267],[310,320],[460,283],[655,312],[820,271],[960,303],[960,H],[0,H]],'#bbced3');
    polygon(c,[[0,406],[205,362],[413,402],[625,347],[960,411],[960,H],[0,H]],'#d0dce0');
    const terrain=G.terrainAt(state.position,state);
    const trackY=x=>350+G.terrainAt(state.position+(x-480)/metresToPixels,state).height-terrain.height;
    const ground=[];
    for(let x=0;x<=W;x+=16)ground.push([x,trackY(x)+35]);
    polygon(c,[...ground,[W,H],[0,H]],'#d0dce0');
    for(let i=-2;i<14;i++) {
      const world=i*118+Math.floor(scroll/118)*118;
      const x=world-scroll;
      pine(c,x,trackY(x)-50,45+hash(world)*40);
    }
    function ribbon(offset,width,color) {
      const top=[],bottom=[];
      for(let x=0;x<=W;x+=16){top.push([x,trackY(x)+offset]);bottom.push([x,trackY(x)+offset+width]);}
      polygon(c,[...top,...bottom.reverse()],color);
    }
    ribbon(-20,44,'#82959d');ribbon(24,6,'#a7bec7');
    for(let x=-40-(scroll%38);x<W+40;x+=38) {
      polygon(c,[[x,trackY(x)-18],[x+9,trackY(x+9)-18],[x+26,trackY(x+26)+22],[x+17,trackY(x+17)+22]],'#596775');
    }
    for(const offset of [-11,13]) {
      ribbon(offset,4,'#35495a');ribbon(offset,1,'#e6eef0');
    }
    // Departure and arrival are separate landmarks; the first frame is at a station.
    for(const stationPosition of [0,G.lengthOf(state)]) {
      const stationX=470+(stationPosition-state.position)*metresToPixels;
      if(stationX < -280 || stationX > 1200) continue;
      polygon(c,[[stationX-45,trackY(stationX)-58],[stationX+210,trackY(stationX+210)-58],[stationX+235,trackY(stationX+235)-23],[stationX-20,trackY(stationX-20)-23]],'#627b8d');
      polygon(c,[[stationX-45,trackY(stationX)-58],[stationX+210,trackY(stationX+210)-58],[stationX+210,trackY(stationX+210)-52],[stationX-45,trackY(stationX)-52]],'#e6eff0');
      c.fillStyle='#334d60'; c.fillRect(stationX+42,trackY(stationX+42)-130,84,70);
      c.fillStyle='#e6c88d'; c.fillRect(stationX+54,trackY(stationX+42)-110,15,18); c.fillRect(stationX+88,trackY(stationX+42)-110,15,18);
      polygon(c,[[stationX+32,trackY(stationX+42)-130],[stationX+74,trackY(stationX+42)-158],[stationX+136,trackY(stationX+42)-130]],'#e2ecee');
      c.fillStyle='#ae8054'; c.fillRect(stationX,trackY(stationX)-36,5,42);
      c.fillStyle='#ecce95'; c.fillRect(stationX-12,trackY(stationX)-41,29,8);
    }
    // The source sprite faces left. Mirror at rendering time: original art stays intact.
    if(train && (train.naturalWidth || train.width)) {
      c.save(); c.translate(480,trackY(480)+9); c.rotate(Math.atan(terrain.slope));
      c.fillStyle='#516b7880'; c.fillRect(-208,0,416,11);
      c.scale(-1,1); c.drawImage(train,-216,-112,432,119);
      // Wheel spokes use travelled distance, so they accelerate, brake and stop with the train.
      const angle=-scroll/10;
      c.strokeStyle='#c5c8b0';c.lineWidth=1.4;
      for(const sourceX of [53,114,166,218]) {
        const x=-216+sourceX*1.8,y=-112+57*1.8;
        c.beginPath();c.moveTo(x-Math.cos(angle)*4,y-Math.sin(angle)*4);c.lineTo(x+Math.cos(angle)*4,y+Math.sin(angle)*4);c.stroke();
      }
      c.restore();
    }
    for(let i=0;i<6;i++) {
      const world=i*270+Math.floor(scroll/270)*270, x=world-scroll;
      const y=trackY(x)-34;
      c.fillStyle='#597488'; c.fillRect(x,y-88,5,90);
      c.fillStyle='#d4e2e5'; c.fillRect(x-1,y-90,30,5);
      c.fillStyle='#c0a780'; c.fillRect(x+23,y-85,4,12);
    }
    for(let i=-1;i<14;i++) {
      const world=i*80+Math.floor(scroll/80)*80,x=world-scroll;
      c.fillStyle='#b5cbd1';c.fillRect(x,trackY(x)+55+hash(world+17)*75,10+hash(world)*15,2);
    }
    for(let i=0;i<25;i++) {
      const x=(hash(i+901)*W-state.elapsed*(3+hash(i)*5)+W*20)%W;
      const y=(hash(i+400)*H+state.elapsed*(7+hash(i+3)*8))%H;
      c.fillStyle=i%3?'#e8f0f16a':'#e8f0f1aa'; c.fillRect(Math.floor(x),Math.floor(y),2,2);
    }
    c.restore();
  };
});
