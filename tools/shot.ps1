# Screenshot the game window only (works while it is behind other windows), e.g. to attach to a bug report.
# Usage: pwsh tools/shot.ps1 [-Out shots\name.png] [-Scale 0.5]   (prints the saved path)
param([string]$Process = 'doa4', [string]$Out = '', [double]$Scale = 0.5)
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class GameWin {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  public struct RECT { public int L, T, R, B; }
}
'@
$p = Get-Process $Process -ErrorAction Stop | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
if (-not $Out) { $Out = Join-Path $PSScriptRoot "..\shots\shot-$(Get-Date -Format yyyyMMdd-HHmmss).png" }
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$Out = [IO.Path]::GetFullPath($Out)
$r = New-Object GameWin+RECT
[GameWin]::GetClientRect($p.MainWindowHandle, [ref]$r) | Out-Null
$full = [System.Drawing.Bitmap]::new([math]::Max(1, $r.R), [math]::Max(1, $r.B))
$g = [System.Drawing.Graphics]::FromImage($full)
$dc = $g.GetHdc()
[GameWin]::PrintWindow($p.MainWindowHandle, $dc, 3) | Out-Null  # 3 = client area + full GPU content
$g.ReleaseHdc($dc)
$small = [System.Drawing.Bitmap]::new($full, [math]::Max(1, [int]($r.R * $Scale)), [math]::Max(1, [int]($r.B * $Scale)))
$small.Save($Out)
$small.Dispose(); $g.Dispose(); $full.Dispose()
$Out
