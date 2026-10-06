# capture-play.ps1 - capture the 千星 trial play from the GENSHIN window, no human screenshots
#
# 2026-10-06 correction from the user: the trial play renders in the GENSHIN window,
# not in the 千星沙箱 editor window. So this version targets the game window rect
# (and raises it) instead of grabbing the whole desktop, which other windows cover.
#
# Trigger: when Genshin enters a 千星 (Beyond) trial play it appends
#   "BeyondLevelPlayModule SetCurLevelData ... isTrial:True" to output_log.txt.
# Only the NEW tail of the log is inspected, so a previous play cannot trigger it.
#
# ASCII only on purpose: Windows PowerShell 5.1 reads a BOM-less UTF-8 .ps1 as
# ANSI, so non-ASCII literals would be mangled (the first version died exactly
# that way: "...\miHoYo\原神\..." became mojibake and Get-Item failed).
#
# usage: & tools\capture-play.ps1 -WaitMinutes 15 -Shots 20 -IntervalSec 2

param(
  [string]$LogGlob = "$env:USERPROFILE\AppData\LocalLow\miHoYo\*\output_log.txt",
  [string]$GameProcess = 'YuanShen',
  [string]$OutDir  = "D:\train\records\_screen\burst",
  [int]$WaitMinutes = 15,
  [int]$Shots = 20,
  [int]$IntervalSec = 2
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$watchLog = Join-Path $OutDir 'watch.log'

function Write-Log([string]$msg) {
  $line = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
  Add-Content -Path $watchLog -Value $line -Encoding UTF8
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
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@

function Get-GameWindow([string]$procName) {
  # the callback runs in its own scope, so communicate through $script:found
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
        $script:found = [pscustomobject]@{ Handle = $h; Left = $r.Left; Top = $r.Top; Width = $r.Right - $r.Left; Height = $r.Bottom - $r.Top; Area = $area }
      }
    }
    return $true
  }
  [W32]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
  return $script:found
}

function Grab([string]$tag) {
  $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $win = Get-GameWindow $GameProcess
  if ($win) {
    $x = [Math]::Max(0, $win.Left - $screen.X)
    $y = [Math]::Max(0, $win.Top - $screen.Y)
    $w = [Math]::Min($win.Width, $screen.Width - $x)
    $h = [Math]::Min($win.Height, $screen.Height - $y)
    # raise the game window so nothing else is composited over it
    if ([W32]::IsIconic($win.Handle)) { [W32]::ShowWindow($win.Handle, 9) | Out-Null }
    [W32]::SetForegroundWindow($win.Handle) | Out-Null
    Start-Sleep -Milliseconds 250
    $region = @{ X = $x + $screen.X; Y = $y + $screen.Y; W = $w; H = $h; What = "game ${w}x${h}" }
  } else {
    $region = @{ X = $screen.X; Y = $screen.Y; W = $screen.Width; H = $screen.Height; What = 'full desktop (game window not found)' }
  }
  $bmp = New-Object System.Drawing.Bitmap $region.W, $region.H
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    $g.CopyFromScreen($region.X, $region.Y, 0, 0, $bmp.Size)
    $file = Join-Path $OutDir ("{0}.png" -f $tag)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    return @{ File = $file; What = $region.What }
  } finally { $g.Dispose(); $bmp.Dispose() }
}

$candidate = Get-ChildItem -Path $LogGlob -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $candidate) { throw "no output_log.txt matched: $LogGlob" }
$LogPath = $candidate.FullName
Write-Log ("log: {0}" -f $LogPath)
Write-Log ("game window now: {0}" -f ($(if (Get-GameWindow $GameProcess) { 'found' } else { 'NOT found' })))

$startLength = (Get-Item $LogPath).Length
$deadline = (Get-Date).AddMinutes($WaitMinutes)
Write-Log ("watching from offset {0}; deadline {1}" -f $startLength, $deadline.ToString('HH:mm:ss'))

$detected = $false
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 2
  $len = (Get-Item $LogPath).Length
  if ($len -le $startLength) { continue }
  $fs = [System.IO.File]::Open($LogPath, 'Open', 'Read', 'ReadWrite')
  try {
    $fs.Seek($startLength, 'Begin') | Out-Null
    $sr = New-Object System.IO.StreamReader($fs)
    $new = $sr.ReadToEnd()
    $sr.Close()
    $startLength = $fs.Length
  } finally { $fs.Close() }
  if ($new -match 'isTrial:True|BeyondLevelPlayModule SetCurLevelData') {
    $detected = $true
    Write-Log 'detected Beyond trial play start'
    break
  }
}

if (-not $detected) { Write-Log 'no trial play detected before deadline'; exit 0 }

for ($i = 1; $i -le $Shots; $i++) {
  $tag = "play-{0:d2}-{1}" -f $i, (Get-Date -Format 'HHmmss')
  $res = Grab $tag
  Write-Log ("shot {0}/{1} {2} -> {3} ({4} KB)" -f $i, $Shots, $res.What, (Split-Path $res.File -Leaf), [math]::Round((Get-Item $res.File).Length / 1KB, 1))
  Start-Sleep -Seconds $IntervalSec
}
Write-Log 'burst done'
