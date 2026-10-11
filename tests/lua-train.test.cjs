const {test}=require('node:test');
const assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const fs=require('node:fs');
const G=require('../prototype/game.js');
const drive=require('./helpers/reference-driver.cjs');
const lua=process.env.LUA||'lua';
function run(file,input='') {
  const r=spawnSync(lua,[file],{input,encoding:'utf8',maxBuffer:8*1024*1024});
  assert.ifError(r.error);assert.equal(r.status,0,r.stderr||r.stdout);
  return r.stdout.trim().split('\n').filter(Boolean);
}
function near(a,b) {assert.ok(Math.abs(a-b)<2e-6,`${a} != ${b}`);}
test('Lua deterministic routes match JS for 128 seeds and trip combinations',()=>{
  const commands=[],expected=[];
  for(const seed of [0,1,42,0xffffffff])for(let legIndex=0;legIndex<32;legIndex++) {
    commands.push(`new endless ${seed} ${legIndex}`,'route');
    for(const r of G.createState({mode:'endless',seed,legIndex}).route)
      expected.push([r.from,r.to,r.environment,r.low??'nil',r.high??'nil',r.environmentStart??'nil'].map(String));
  }
  const lines=run('tests/lua-train-runner.lua',commands.join('\n')+'\n');
  assert.equal(lines.length,expected.length);
  lines.forEach((line,i)=>line.split(' ').slice(1).forEach((value,j)=>{
    if(expected[i][j]==='nil')assert.equal(value,'nil');else near(Number(value),Number(expected[i][j]));
  }));
});
test('Lua driving matches JS throughout trial, normal and downhill endless trips',()=>{
  for(const options of [{mode:'trial',seed:1,legIndex:0},{mode:'endless',seed:42,legIndex:0},
    {mode:'endless',seed:7,legIndex:3},{mode:'endless',seed:2,legIndex:6}]) {
    const commands=[`new ${options.mode} ${options.seed} ${options.legIndex}`,'start'],expected=[];
    const originalShift=G.shift,originalUpdate=G.update;let frames=0;
    function snapshot(s){commands.push('emit');expected.push([s.speed,s.position,s.heat,s.elapsed,s.score,
      s.legalDistance,s.gear,s.overheats,s.perfectSections,s.phase]);}
    G.shift=(s,d)=>{commands.push(`shift ${d}`);return originalShift(s,d);};
    G.update=(s,dt)=>{commands.push(`update ${dt}`);originalUpdate(s,dt);if(++frames%30===0)snapshot(s);};
    let final;
    try {final=drive(options,options.mode==='trial'?{}:{midOffset:-5,highOffset:5,downhillOffset:25});snapshot(final);}
    finally {G.shift=originalShift;G.update=originalUpdate;}
    const lines=run('tests/lua-train-runner.lua',commands.join('\n')+'\n');
    assert.equal(lines.length,expected.length);
    lines.forEach((line,i)=>line.split(' ').slice(1).forEach((value,j)=>{
      if(j===9)assert.equal(value,expected[i][j]);else near(Number(value),expected[i][j]);
    }));
    assert.equal(final.phase,'finished');
  }
});
test('Lua invariants, continuation, perfect boundaries, temperature and client wiring',()=>{
  run('tests/lua-train-checks.lua');
  const template=fs.readFileSync('workspace/train/train_client.template.lua','utf8');
  const core=fs.readFileSync('workspace/train/train_core.lua','utf8');
  const bundled=fs.readFileSync('workspace/train/train_game.lua','utf8');
  assert.equal(bundled,template.replace('__TRAIN_CORE__',()=>`(function()\n${core}\nend)()`),'rebuild stale single file');
});
