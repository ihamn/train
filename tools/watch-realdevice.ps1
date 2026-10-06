# watch-realdevice.ps1 - read the real device without asking the human for anything
#
# Two instruments, both read-only:
#  1) the 千星 sandbox dumps the client-script log into
#     ...\BeyondLocal\<UID>\Beyond_Debug_Log\*.gia  -> we copy it and decode the
#     printable strings (that file is how we learned "M0 boot / M0 missing train
#     controls" from the device).
#  2) when the game enters a Beyond trial play (output_log.txt) we burst-capture
#     the Genshin window.
#
# ASCII only on purpose: Windows PowerShell 5.1 reads a BOM-less UTF-8 .ps1 as ANSI,
# so non-ASCII literals here would be mangled. Paths use wildcards for the same
# reason (the real path contains CJK characters).
#
# usage: & tools\watch-realdevice.ps1 -Minutes 30 -Shots 15 -IntervalSec 2

param(
  [string]$DebugLogGlob = "$env:USERPROFILE\AppData\LocalLow\miHoYo\*\BeyondLocal\*\Beyond_Debug_Log\*.gia",
  [string]$GameLogGlob  = "$env:USERPROFILE\AppData\LocalLow\miHoYo\*\output_log.txt",
  [string]$GameProcess  = 'YuanShen',
  [string]$OutDir       = "D:\train\records\_screen\realdevice",
  [int]$Minutes = 30,
  [int]$Shots = 15,
  [int]$IntervalSec = 2
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$logFile = Join-Path $OutDir 'watch.log'

function Write-Log([string]$msg) {
  $line = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
  Add-Content -Path $logFile -Value $line -Encoding UTF8
  Write-Output $line
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class W32 {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@

function Get-GameWindow([string]$procName) {
  $script:found = $null
  $cb = [W32+EnumWindowsProc]{
    param([IntPtr]$h, [IntPtr]$l)
    if (-not [W32]::IsWindowVisible($h)) { return $true }
    [uint32]$wpid = 0
    [W32]::GetWindowThreadProcessId($h, [ref]$wpid) | Out-Null
    $p = Get-Process -Id $wpid -ErrorAction SilentlyContinue
    if ($p -and $p.ProcessName -eq $procName) {
      $r = New-Object RECT
      [W32]::GetWindowRect($h, [ref]$r) | Out-Null
      $area = ($r.Right - $r.Left) * ($r.Bottom - $r.Top)
      if ($area -gt 100000) {
        $script:found = [pscustomobject]@{ Handle = $h; Left = $r.Left; Top = $r.Top; Width = $r.Right - $r.Left; Height = $r.Bottom - $r.Top }
      }
    }
    return $true
  }
  [W32]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
  return $script:found
}

function Grab-Game([string]$tag) {
  $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $win = Get-GameWindow $GameProcess
  if (-not $win) { return $null }
  $x = [Math]::Max(0, $win.Left - $screen.X); $y = [Math]::Max(0, $win.Top - $screen.Y)
  $w = [Math]::Min($win.Width, $screen.Width - $x); $h = [Math]::Min($win.Height, $screen.Height - $y)
  if ($w -lt 50 -or $h -lt 50) { return $null }
  if ([W32]::IsIconic($win.Handle)) { [W32]::ShowWindow($win.Handle, 9) | Out-Null }
  [W32]::SetForegroundWindow($win.Handle) | Out-Null
  Start-Sleep -Milliseconds 250
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    $g.CopyFromScreen($x + $screen.X, $y + $screen.Y, 0, 0, $bmp.Size)
    $file = Join-Path $OutDir ("game-{0}.png" -f $tag)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    return $file
  } finally { $g.Dispose(); $bmp.Dispose() }
}

# printable-run extractor for the debug .gia dump (ASCII + UTF-8 kept as-is)
function Decode-Dump([string]$path) {
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $sb = New-Object System.Text.StringBuilder
  $run = New-Object System.Text.StringBuilder
  foreach ($b in $bytes) {
    if (($b -ge 32 -and $b -lt 127) -or $b -ge 128) {
      [void]$run.Append([char]$b)
    } else {
      if ($run.Length -ge 4) { [void]$sb.AppendLine($run.ToString()) }
      [void]$run.Clear()
    }
  }
  if ($run.Length -ge 4) { [void]$sb.AppendLine($run.ToString()) }
  return $sb.ToString()
}

$gameLog = (Get-ChildItem $GameLogGlob -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
$logOffset = if ($gameLog) { $gameLog.Length } else { 0 }
$seen = @{}
foreach ($f in (Get-ChildItem $DebugLogGlob -ErrorAction SilentlyContinue)) { $seen[$f.FullName] = $f.LastWriteTime.Ticks }
Write-Log ("watching debug dumps: {0} known; game log offset {1}" -f $seen.Count, $logOffset)

$deadline = (Get-Date).AddMinutes($Minutes)
$shotsLeft = 0
$shotTag = ''

while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 2

  # 1) new client-script dumps from the device
  foreach ($f in (Get-ChildItem $DebugLogGlob -ErrorAction SilentlyContinue)) {
    if ($seen.ContainsKey($f.FullName) -and $seen[$f.FullName] -eq $f.LastWriteTime.Ticks) { continue }
    $seen[$f.FullName] = $f.LastWriteTime.Ticks
    $copy = Join-Path $OutDir $f.Name
    Copy-Item $f.FullName $copy -Force
    Write-Log ("DEBUG DUMP: {0} ({1} B)" -f $f.Name, $f.Length)
    $text = Decode-Dump $f.FullName
    Add-Content -Path (Join-Path $OutDir 'debug-decoded.txt') -Value ("=== {0} ===" -f $f.Name) -Encoding UTF8
    Add-Content -Path (Join-Path $OutDir 'debug-decoded.txt') -Value $text -Encoding UTF8
    Write-Output $text
  }

  # 2) trial play -> burst capture the game window
  if ($shotsLeft -gt 0) {
    $file = Grab-Game ("{0}-{1:d2}" -f $shotTag, ($Shots - $shotsLeft + 1))
    if ($file) { Write-Log ("shot -> {0}" -f (Split-Path $file -Leaf)) }
    $shotsLeft--
    continue
  }
  if ($gameLog) {
    $len = (Get-Item $gameLog.FullName).Length
    if ($len -gt $logOffset) {
      $fs = [System.IO.File]::Open($gameLog.FullName, 'Open', 'Read', 'ReadWrite')
      try {
        $fs.Seek($logOffset, 'Begin') | Out-Null
        $sr = New-Object System.IO.StreamReader($fs)
        $new = $sr.ReadToEnd(); $sr.Close()
        $logOffset = $fs.Length
      } finally { $fs.Close() }
      if ($new -match 'isTrial:True|BeyondLevelPlayModule SetCurLevelData') {
        Write-Log 'trial play detected -> burst capture'
        $shotsLeft = $Shots
        $shotTag = Get-Date -Format 'HHmmss'
      }
    }
  }
}
Write-Log 'watch finished'
