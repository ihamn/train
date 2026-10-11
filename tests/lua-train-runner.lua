-- 行协议，供 Node 测试以同一组玩家输入对照 JS / Lua。
local G=dofile('workspace/train/train_core.lua')
local s
for line in io.lines() do
  local cmd,a,b,c=line:match('^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)')
  if cmd=='new' then s=G.createState({mode=a,seed=tonumber(b),legIndex=tonumber(c)})
  elseif cmd=='start' then G.start(s,{mode=s.mode,seed=s.seed,legIndex=s.legIndex})
  elseif cmd=='shift' then G.shift(s,tonumber(a))
  elseif cmd=='update' then G.update(s,tonumber(a))
  elseif cmd=='continue' then G.continueJourney(s)
  elseif cmd=='end' then G.endJourney(s)
  elseif cmd=='pause' then G.pause(s)
  elseif cmd=='emit' then
    print(string.format('S %.12f %.12f %.12f %.12f %.12f %.12f %d %d %d %s',
      s.speed,s.position,s.heat,s.elapsed,s.score,s.legalDistance,s.gear,s.overheats,s.perfectSections,s.phase))
  elseif cmd=='route' then
    for _,r in ipairs(s.route) do
      print(string.format('R %d %d %.1f %s %s %s',r.from,r.to,r.environment,
        tostring(r.low),tostring(r.high),tostring(r.environmentStart)))
    end
  else error('Unknown command '..cmd) end
end
