# add-candidates.ps1 -- insert a glyph-candidate row into the deployed spike.lua
# ASCII-only script: glyphs are built from code points so console encoding cannot corrupt them.
$ErrorActionPreference = 'Stop'
$lua = 'C:\Users\netease\AppData\LocalLow\miHoYo\原神\BeyondLocal\190800866\Beyond_Local_Save_Level\1073741826\external_lua_file\spike.lua'
$src = 'D:\train\workspace\train\fire_v45.lua'
$enc = New-Object System.Text.UTF8Encoding($false)
$t = [System.IO.File]::ReadAllText($lua, [System.Text.Encoding]::UTF8)

if ($t.Contains('glyph candidates')) {
  Write-Output 'candidate row already present - nothing to do'
  exit 0
}

$codes = @(0x2588, 0x2589, 0x258A, 0x258B, 0x258C, 0x258D, 0x25A0, 0x25FC, 0x25AE, 0x25CF)
$lits = @()
foreach ($c in $codes) { $lits += ("'" + [string][char]$c + "'") }
$list = $lits -join ', '

$lines = @()
$lines += '  -- glyph candidates (3 copies each, own colour): screenshot to measure ink vs advance'
$lines += ('  local cands = { ' + $list + ' }')
$lines += "  local cols = { '#FF0000','#00FF00','#0000FF','#FFFF00','#FF00FF','#00FFFF','#FF8000','#8000FF','#FFFFFF','#808080' }"
$lines += '  local gp = {}'
$lines += '  for gi = 1, #cands do'
$lines += "    gp[#gp + 1] = '<color=' .. cols[gi] .. '>'"
$lines += '    for k = 1, 3 do gp[#gp + 1] = tostring(cands[gi]) end'
$lines += "    gp[#gp + 1] = '</color> '"
$lines += '  end'
$lines += '  local grow = mk_band(9, baseX, baseY + (BANDS - 1) * step + bh + FONT * 2)'
$lines += '  if grow ~= nil then t(function() grow.text = table.concat(gp) end) end'
$lines += "  say('glyph candidates = ' .. tostring(#cands))"
$snippet = ($lines -join "`r`n") + "`r`n"

$anchor = '  say("canvas="'
$idx = $t.IndexOf($anchor)
if ($idx -lt 0) { Write-Output 'anchor not found'; exit 1 }
$out = $t.Substring(0, $idx) + $snippet + $t.Substring($idx)

[System.IO.File]::WriteAllText($src, $out, $enc)
[System.IO.File]::WriteAllText($lua, $out, $enc)
Write-Output ('inserted candidate row, file now ' + $out.Length + ' chars')
