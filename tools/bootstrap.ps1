# bootstrap.ps1 - restore the dev toolchain after switching cloud instances
#
# 云电脑的系统盘（C:）会随"换环境"被重置，但 D 盘不清。
# 因此本脚本的设计是：**工具本体常驻 D 盘**（便携版），需要时把它们
# "投射"到 C 盘（junction）+ 写进用户 PATH + 生成 node 垫片，
# 让新环境的命令行跟"预装了工具"一样可用。
#
# 幂等：重复运行只补缺的部分，不会重复下载、不会覆盖已有配置。
#
# ASCII only on purpose: Windows PowerShell 5.1 reads a BOM-less UTF-8 .ps1 as
# ANSI, so non-ASCII literals here would be mangled (this bit us before).
#
# usage:
#   powershell -ExecutionPolicy Bypass -File D:\train\tools\bootstrap.ps1
#   powershell -ExecutionPolicy Bypass -File ...\bootstrap.ps1 -LinkRoot "$env:LOCALAPPDATA\tools"

param(
  [string]$ToolRoot = 'D:\tools',
  [string]$LinkRoot = 'C:\tools',
  [string]$MinGitVersion = '2.56.0.windows.1',
  [string]$MinGitFile = 'MinGit-2.56.0-64-bit.zip',
  [string]$PythonVersion = '3.12.10',
  [string]$ElectronExe = 'D:\deepseek harness\DeepSeek Harness.exe',
  [string]$GitUserName = 'DSH agent',
  [string]$GitUserEmail = 'agent@dsh.local',
  [switch]$SkipDownload
)

$ErrorActionPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

function Say([string]$m) { Write-Output $m }

function Ensure-Dir([string]$p) { if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }

function Download([string]$url, [string]$out) {
  Say ("  downloading " + $url)
  Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -TimeoutSec 300
  Say ("  saved " + $out + " (" + [math]::Round((Get-Item $out).Length / 1MB, 1) + " MB)")
}

# ---------------------------------------------------------------- git (MinGit)
$gitExe = Join-Path $ToolRoot 'MinGit\cmd\git.exe'
if (-not (Test-Path $gitExe)) {
  Say '[git] missing on D:, fetching portable MinGit'
  Ensure-Dir $ToolRoot
  $zip = Join-Path $ToolRoot 'MinGit.zip'
  if (-not $SkipDownload) {
    $base = "https://mirrors.huaweicloud.com/git-for-windows/$MinGitVersion/"
    Download ($base + $MinGitFile) $zip
  }
  if (Test-Path $zip) {
    Remove-Item (Join-Path $ToolRoot 'MinGit') -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive $zip -DestinationPath (Join-Path $ToolRoot 'MinGit') -Force
  }
} else { Say '[git] already on D:' }
if (Test-Path $gitExe) { Say ("[git] " + (& $gitExe --version)) } else { Say '[git] NOT available' }

# ------------------------------------------------------------ python (embed)
$pyExe = Join-Path $ToolRoot 'python\python.exe'
if (-not (Test-Path $pyExe)) {
  Say '[python] missing on D:, fetching embeddable python'
  Ensure-Dir $ToolRoot
  $zip = Join-Path $ToolRoot 'python-embed.zip'
  if (-not $SkipDownload) {
    Download ("https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip") $zip
  }
  if (Test-Path $zip) {
    Remove-Item (Join-Path $ToolRoot 'python') -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive $zip -DestinationPath (Join-Path $ToolRoot 'python') -Force
  }
} else { Say '[python] already on D:' }
if (Test-Path $pyExe) { Say ("[python] " + (& $pyExe --version)) } else { Say '[python] NOT available' }

# --------------------------------------------------- expose on C: via junctions
$usedLinkRoot = $LinkRoot
try {
  Ensure-Dir $LinkRoot
  $probe = Join-Path $LinkRoot '.write-probe'
  Set-Content -Path $probe -Value 'ok' -ErrorAction Stop
  Remove-Item $probe -Force -ErrorAction SilentlyContinue
} catch {
  $usedLinkRoot = Join-Path $env:LOCALAPPDATA 'tools'
  Say ("[link] C:\tools not writable, falling back to " + $usedLinkRoot)
  Ensure-Dir $usedLinkRoot
}
Say ("[link] root = " + $usedLinkRoot)

foreach ($pair in @(@('git', (Join-Path $ToolRoot 'MinGit')), @('python', (Join-Path $ToolRoot 'python')))) {
  $link = Join-Path $usedLinkRoot $pair[0]
  $target = $pair[1]
  if (-not (Test-Path $target)) { continue }
  if (Test-Path $link) { Say ("[link] " + $pair[0] + " already exists") ; continue }
  try {
    New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop | Out-Null
    Say ("[link] " + $link + " -> " + $target)
  } catch {
    Say ("[link] junction failed for " + $pair[0] + ": " + $_.Exception.Message)
  }
}

# ------------------------------------------------------------------ node shim
$binDir = Join-Path $usedLinkRoot 'bin'
Ensure-Dir $binDir
$nodeShim = Join-Path $binDir 'node.cmd'
if (Test-Path $ElectronExe) {
  $shimBody = "@echo off`r`nset ELECTRON_RUN_AS_NODE=1`r`n`"$ElectronExe`" %*`r`n"
  Set-Content -Path $nodeShim -Value $shimBody -Encoding ASCII
  Say ("[node] shim written: " + $nodeShim + " -> " + $ElectronExe)
} else {
  Say ("[node] electron not found at " + $ElectronExe + "; skip node shim")
}

# ------------------------------------------------------------------- user PATH
$wanted = @(
  (Join-Path $usedLinkRoot 'git\cmd'),
  (Join-Path $usedLinkRoot 'git\bin'),
  (Join-Path $usedLinkRoot 'python'),
  $binDir
)
$cur = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($null -eq $cur) { $cur = '' }
$parts = $cur.Split(';') | Where-Object { $_ -ne '' }
$added = @()
foreach ($w in $wanted) {
  if ($parts -notcontains $w) { $parts += $w; $added += $w }
}
if ($added.Count -gt 0) {
  [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
  Say ("[path] added: " + ($added -join '; '))
} else { Say '[path] already contains all entries' }

# ------------------------------------------------------------------ git config
if (Test-Path $gitExe) {
  $gname = & $gitExe config --global user.name 2>$null
  if (-not $gname) { & $gitExe config --global user.name $GitUserName; Say ("[git] global user.name = " + $GitUserName) }
  $gmail = & $gitExe config --global user.email 2>$null
  if (-not $gmail) { & $gitExe config --global user.email $GitUserEmail; Say ("[git] global user.email = " + $GitUserEmail) }
  $key = 'D:/ssh/id_ed25519_github'
  if (Test-Path 'D:\ssh\id_ed25519_github') {
    & $gitExe config --global core.sshCommand ("ssh -i " + $key + " -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new")
    Say '[git] global core.sshCommand -> D:/ssh/id_ed25519_github'
  } else { Say '[git] D:\ssh\id_ed25519_github not found; skip ssh config' }
}

Say ''
Say '=== summary (new shells will see these on PATH) ==='
Say ("  git    : " + $gitExe)
Say ("  python : " + $pyExe)
Say ("  node   : " + $nodeShim + "  (Electron as node)")
Say ("  links  : " + $usedLinkRoot)
