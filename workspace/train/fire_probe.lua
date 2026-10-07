-- fire_probe_v4.lua —— 像素火 v4「预渲染阶段 + 播放阶段」
-- 用户观察：社区视频有"一段预渲染过程" ⇒ 正确做法是**一帧一帧摊到多帧生成**（等每帧解析完），
--   全部就绪后再播放。我 v3 把 12 个富文本串挤在同一帧赋值 ⇒ 解析互相踩 ⇒ 画面乱 ✗
-- ① prerender：每 2 帧生成 1 帧（先 SetVisible(false) 再赋 text ⇒ 解析在看不见时发生）
-- ② play：只切 SetVisible，**永不改 text**
-- 富文本必须成对闭合：<color=#RRGGBBAA>…</color>；对齐必须显式设置

local PRE_TEXT = 1073741850
local COLS, ROWS = 16, 27
local SOURCE_ROWS, DECAY_MAX, EXPONENT, NLEV = 3, 3, 0.9, 25
local FONT, FRAMES, SWAP_TICKS, ASCII_EVERY = 26, 12, 6, 8

local PAL = {
  {  7,  7, 15 }, { 26, 10, 10 }, { 60, 12, 10 }, {100, 15, 12 }, {140, 20, 12 },
  {176, 28, 12 }, {206, 40, 12 }, {226, 58, 12 }, {238, 78, 14 }, {246,100, 16 },
  {250,120, 18 }, {252,140, 22 }, {254,158, 26 }, {255,172, 34 }, {255,186, 48 },
  {255,198, 66 }, {255,208, 86 }, {255,216,108 }, {255,224,132 }, {255,232,158 },
  {255,240,190 }, {255,246,215 }, {255,250,235 }, {255,253,248 }, {255,255,255 },
}

local host, W, H = nil, 1680, 900
local tick, builds, fails, alive, swaps = 0, 0, 0, true, 0
local richFrames, ascii, heat = {}, nil, {}
local cur, lastAscii, richLen, runs0 = 0, nil, 0, 0
local phase, preIdx, bw, bh, frameY = "prerender", 0, 0, 0, 0

local function say(s) if print then pcall(print, "TR " .. s) end end
local function t(fn) local ok = pcall(fn); if not ok then fails = fails + 1 end; return ok end
local function rgb(r, g, b)
  local ok, v = pcall(function() return Color.FromRGBA(r, g, b, 255) end)
  if ok then return v end
  return nil
end
local function point_anchor(c)
  t(function() c.anchorMinX = 0 end); t(function() c.anchorMinY = 0 end)
  t(function() c.anchorMaxX = 0 end); t(function() c.anchorMaxY = 0 end)
  t(function() c.pivotX = 0 end);     t(function() c.pivotY = 0 end)
end

local rseed = 20261007
local function rnd(n)
  rseed = (rseed * 1103515245 + 12345) % 2147483648
  return rseed % n
end
local halfPx, ccx = math.floor(COLS / 2), (COLS - 1) / 2
local function halfAt(r)
  local tt = (ROWS - r) / math.max(1, ROWS - 1)
  local h = halfPx * ((1 - tt) ^ EXPONENT)
  if h < 0.5 then h = 0.5 end
  return h
end
local function allowed(c, r) return math.abs(c - ccx) <= halfAt(r) end
local function idx(r, c) return r * COLS + c + 1 end

local function seedFire()
  for r = ROWS - SOURCE_ROWS, ROWS - 1 do
    for c = 0, COLS - 1 do
      if allowed(c, r) then heat[idx(r, c)] = NLEV end
    end
  end
end
local function stepFire()
  seedFire()
  for r = ROWS - 1, 1, -1 do
    local up = r - 1
    for c = 0, COLS - 1 do
      local v = heat[idx(r, c)]
      if v <= 1 then
        heat[idx(up, c)] = 1
      else
        local d = rnd(DECAY_MAX + 1)
        local nx = c + rnd(3) - 1
        if nx < 0 then nx = 0 elseif nx >= COLS then nx = COLS - 1 end
        if not allowed(nx, up) then
          heat[idx(up, nx)] = 1
        else
          local nv = v - d
          if nv < 1 then nv = 1 end
          heat[idx(up, nx)] = nv
        end
      end
    end
  end
end

local function build_rich()
  local parts, runs, open = {}, 0, false
  local function close()
    if open then parts[#parts + 1] = "</color>"; open = false end
  end
  for r = 0, ROWS - 1 do
    if r > 0 then close(); parts[#parts + 1] = "\n" end
    local curV = -1
    for c = 0, COLS - 1 do
      local v = heat[idx(r, c)] or 1
      if v <= 1 then
        close(); curV = -1
        parts[#parts + 1] = " "
      else
        if v ~= curV then
          close()
          local p = PAL[v] or PAL[1]
          local a = 255
          if v <= 4 then a = 120 elseif v <= 8 then a = 200 end
          parts[#parts + 1] = string.format("<color=#%02X%02X%02X%02X>", p[1], p[2], p[3], a)
          open, curV = true, v
          runs = runs + 1
        end
        parts[#parts + 1] = "■"
      end
    end
  end
  close()
  return table.concat(parts), runs
end

local RAMP = { [1]=" ", [2]=".", [3]=".", [4]=":", [5]=":", [6]=":", [7]="*", [8]="*", [9]="*", [10]="*",
  [11]="o", [12]="o", [13]="o", [14]="o", [15]="O", [16]="O", [17]="O", [18]="#", [19]="#", [20]="#",
  [21]="@", [22]="@", [23]="@", [24]="@", [25]="@" }
local function build_ascii()
  local parts = {}
  for r = 0, ROWS - 1 do
    if r > 0 then parts[#parts + 1] = "\n" end
    for c = 0, COLS - 1 do
      parts[#parts + 1] = RAMP[heat[idx(r, c)] or 1] or " "
    end
  end
  return table.concat(parts)
end

local function mk_text(name, ox, oy, w, h, fs, hideFirst)
  if builds >= 40 then return nil end
  local ok, c = pcall(game.InstantiateClientUIControl, PRE_TEXT, host)
  if not ok or c == nil then alive = false; return nil end
  builds = builds + 1
  point_anchor(c)
  t(function() c.name = name end)
  t(function() c:SetSizeDelta(w, h) end)
  t(function() c:SetAnchoredPosition(ox, oy) end)
  t(function() c.fontSize = fs or FONT end)
  local fc = rgb(255, 255, 255)
  if fc ~= nil then
    t(function() c.fontColor = fc end)
  end
  t(function() c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle end)
  t(function() c.verticalAlignment = Enum.TextVerticalAlignment.Middle end)
  if hideFirst then t(function() c:SetVisible(false) end) end
  t(function() c:SetActive(true) end)
  return c
end

function OnInit()
  say("boot fire v4")
  t(function() script:EnableUpdate(true) end)
end

function OnStart()
  host = script.object
  if host == nil then say("no host"); alive = false; return end
  local ok, cw, ch = pcall(game.GetUICanvasSize)
  if ok and type(cw) == "number" and type(ch) == "number" then W, H = cw, ch end
  for i = 1, COLS * ROWS do heat[i] = 1 end
  seedFire()
  for i = 1, 30 do stepFire() end

  bw, bh = COLS * FONT + 28, ROWS * (FONT + 4)
  frameY = math.max(20, H - bh - 40)
  say("canvas=" .. W .. "x" .. H .. " prerender=" .. FRAMES .. " (每2帧1帧)")

  ascii = mk_text("ASCII", 60 + bw + 60, frameY, bw, bh, FONT, false)
  if ascii ~= nil then
    local s = build_ascii()
    t(function() ascii.text = s end)
    lastAscii = s
  end
end

function OnUpdate(dt)
  if not alive then return end
  tick = tick + 1
  if tick > 900 then
    say("stop tick=" .. tick .. " frames=" .. #richFrames .. " swaps=" .. swaps .. " fails=" .. fails)
    t(function() script:EnableUpdate(false) end)
    alive = false
    return
  end
  if dt == nil or dt <= 0 then return end

  if phase == "prerender" then
    if tick % 2 ~= 0 then return end
    preIdx = preIdx + 1
    if preIdx > FRAMES then
      phase = "play"
      say("prerender done frames=" .. #richFrames .. " richLen=" .. richLen
        .. " runs=" .. runs0 .. " fails=" .. fails)
      if #richFrames > 0 then
        t(function() richFrames[1]:SetVisible(true) end)
        cur = 1
      end
      return
    end
    local s, runs = build_rich()
    local c = mk_text("FIRE" .. preIdx, 60, frameY, bw, bh, FONT, true)
    if c == nil then
      phase = "play"
      return
    end
    t(function() c.text = s end)
    richFrames[preIdx] = c
    if preIdx == 1 then richLen, runs0 = #s, runs end
    stepFire()
    return
  end

  if phase == "play" and #richFrames > 1 and tick % SWAP_TICKS == 0 then
    t(function() richFrames[cur]:SetVisible(false) end)
    cur = cur % #richFrames + 1
    t(function() richFrames[cur]:SetVisible(true) end)
    swaps = swaps + 1
  end

  if ascii ~= nil and tick % ASCII_EVERY == 0 then
    stepFire()
    local s = build_ascii()
    if s ~= lastAscii then
      if t(function() ascii.text = s end) then lastAscii = s end
    end
  end
end
