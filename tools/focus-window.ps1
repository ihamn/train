# focus-window.ps1 - list/focus/capture top-level windows (no human screenshots)
#
# ASCII only on purpose: Windows PowerShell 5.1 reads a BOM-less UTF-8 .ps1 as
# ANSI, so non-ASCII literals here would be mangled. Pass non-ASCII title
# fragments as command-line arguments instead.
#
# usage:
#   & tools\focus-window.ps1 -ListAll
#   & tools\focus-window.ps1 -ProcessName BeyondEditor -Focus
#   & tools\focus-window.ps1 -TitleMatch "..." -Focus

param(
  [string]$TitleMatch = '',
  [string]$ProcessName = '',
  [switch]$ListAll,
  [switch]$Focus,
  [string]$OutDir = 'D:\train\records\_screen'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class Win32 {
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

$wins = New-Object System.Collections.ArrayList
$cb = [Win32+EnumWindowsProc]{
  param([IntPtr]$h, [IntPtr]$l)
  if (-not [Win32]::IsWindowVisible($h)) { return $true }
  $sb = New-Object System.Text.StringBuilder 512
  [Win32]::GetWindowTextW($h, $sb, 512) | Out-Null
  $title = $sb.ToString()
  if (-not $title) { return $true }
  [uint32]$procId = 0
  [Win32]::GetWindowThreadProcessId($h, [ref]$procId) | Out-Null
  $r = New-Object RECT
  [Win32]::GetWindowRect($h, [ref]$r) | Out-Null
  $null = $wins.Add([pscustomobject]@{
    Handle = $h; Pid = [int]$procId; Title = $title
    Left = $r.Left; Top = $r.Top
    Width = ($r.Right - $r.Left); Height = ($r.Bottom - $r.Top)
    Minimized = [Win32]::IsIconic($h)
    Name = (Get-Process -Id $procId -ErrorAction SilentlyContinue).ProcessName
  })
  return $true
}
[Win32]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null

if ($ListAll) {
  $wins | Sort-Object -Property @{Expression = { $_.Width * $_.Height }} -Descending |
    ForEach-Object { Write-Output ("pid={0,-6} {1,-18} {2,5}x{3,-5} at {4},{5} min={6}  '{7}'" -f $_.Pid, $_.Name, $_.Width, $_.Height, $_.Left, $_.Top, $_.Minimized, $_.Title) }
  exit 0
}

$match = $wins
if ($ProcessName) { $match = $match | Where-Object { $_.Name -like $ProcessName } }
if ($TitleMatch)   { $match = $match | Where-Object { $_.Title -like "*$TitleMatch*" } }
$target = $match | Sort-Object -Property @{Expression = { $_.Width * $_.Height }} -Descending | Select-Object -First 1
if (-not $target) { Write-Output 'no window matched'; exit 1 }

Write-Output ("target: pid={0} {1} {2}x{3} at {4},{5} min={6} '{7}'" -f $target.Pid, $target.Name, $target.Width, $target.Height, $target.Left, $target.Top, $target.Minimized, $target.Title)

if ($Focus) {
  if ($target.Minimized) { [Win32]::ShowWindow($target.Handle, 9) | Out-Null }
  [Win32]::SetForegroundWindow($target.Handle) | Out-Null
  Start-Sleep -Milliseconds 900
}

$screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
$x = [Math]::Max(0, $target.Left - $screen.X)
$y = [Math]::Max(0, $target.Top - $screen.Y)
$w = [Math]::Min($target.Width, $screen.Width - $x)
$h2 = [Math]::Min($target.Height, $screen.Height - $y)
if ($w -lt 50 -or $h2 -lt 50) { Write-Output "window too small to capture (${w}x${h2})"; exit 1 }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$bmp = New-Object System.Drawing.Bitmap $w, $h2
$g = [System.Drawing.Graphics]::FromImage($bmp)
try {
  $g.CopyFromScreen($x + $screen.X, $y + $screen.Y, 0, 0, $bmp.Size)
  $file = Join-Path $OutDir ("window-{0}-{1}.png" -f $target.Name, (Get-Date -Format 'HHmmss'))
  $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
  Write-Output ("saved: {0} ({1} KB)" -f $file, [math]::Round((Get-Item $file).Length / 1KB, 1))
} finally { $g.Dispose(); $bmp.Dispose() }
