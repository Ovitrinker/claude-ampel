# Claude-Ampel: kleines, immer sichtbares Fenster mit einer Ampel pro Claude-Code-Session.
# Rot = braucht deine Eingabe, Gelb = arbeitet, Gruen = fertig, Blau = Shell aktiv.
# Klick auf eine Ampel holt das Terminal dieser Session nach vorne, Ziehen verschiebt.
# Die Stati schreibt hook.js nach %LOCALAPPDATA%\claude-ampel\sessions.

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class AmpelNative {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int index);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int index, int value);
}
"@

. (Join-Path $PSScriptRoot 'focus.ps1')

$mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeAmpel')
if (-not $mutex.WaitOne(0)) { exit }

$base    = Join-Path $env:LOCALAPPDATA 'claude-ampel'
$sessDir = Join-Path $base 'sessions'
$posFile = Join-Path $base 'position.json'
New-Item -ItemType Directory -Force $sessDir | Out-Null

$lampOrder = 'red', 'yellow', 'green', 'blue'
$lampColor = @{ red = '#FF3B30'; yellow = '#FFCC00'; green = '#30D158'; blue = '#0A84FF' }
$stateText = @{
  red    = 'Braucht deine Eingabe'
  yellow = 'Arbeitet'
  green  = 'Fertig - wartet auf Eingabe'
  blue   = 'Shell aktiv'
}

function New-Brush([string]$hex) {
  $b = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
  $b.Freeze(); $b
}

function New-Ampel {
  $border = New-Object System.Windows.Controls.Border
  $border.CornerRadius = 5
  $border.Background = New-Brush '#1C1C1E'
  $border.BorderBrush = New-Brush '#48484A'
  $border.BorderThickness = 1
  $border.Padding = '3,4,3,2'
  $border.Margin = '1,0'

  $stack = New-Object System.Windows.Controls.StackPanel
  $border.Child = $stack

  $lamps = @{}
  foreach ($name in $lampOrder) {
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = 13; $e.Height = 13
    $e.Margin = '0,0,0,3'
    $e.Fill = New-Brush $lampColor[$name]
    $e.Opacity = 0.15
    $glow = New-Object System.Windows.Media.Effects.DropShadowEffect
    $glow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($lampColor[$name])
    $glow.ShadowDepth = 0; $glow.BlurRadius = 0
    $e.Effect = $glow
    [void]$stack.Children.Add($e)
    $lamps[$name] = $e
  }

  $label = New-Object System.Windows.Controls.TextBlock
  $label.FontSize = 8
  $label.Foreground = New-Brush '#D1D1D6'
  $label.HorizontalAlignment = 'Center'
  $label.Width = 20
  $label.TextAlignment = 'Center'
  $label.Text = ''
  [void]$stack.Children.Add($label)

  @{ Root = $border; Lamps = $lamps; Label = $label; State = '' }
}

function Set-AmpelState($a, [string]$state, [bool]$blinkOn) {
  foreach ($name in $lampOrder) {
    $lamp = $a.Lamps[$name]
    if ($name -eq $state) {
      $lamp.Opacity = if ($state -eq 'red' -and -not $blinkOn) { 0.45 } else { 1 }
      $lamp.Effect.BlurRadius = 9
    } else {
      $lamp.Opacity = 0.15
      $lamp.Effect.BlurRadius = 0
    }
  }
  $a.State = $state
}

# --- Fenster ----------------------------------------------------------------
$win = New-Object System.Windows.Window
$win.Title = 'Claude-Ampel'
$win.WindowStyle = 'None'
$win.AllowsTransparency = $true
$win.Background = [System.Windows.Media.Brushes]::Transparent
$win.Topmost = $true
$win.ShowInTaskbar = $false
$win.ShowActivated = $false
$win.ResizeMode = 'NoResize'
$win.SizeToContent = 'WidthAndHeight'
$win.WindowStartupLocation = 'Manual'

$panel = New-Object System.Windows.Controls.StackPanel
$panel.Orientation = 'Horizontal'
$win.Content = $panel

$menu = New-Object System.Windows.Controls.ContextMenu
$quit = New-Object System.Windows.Controls.MenuItem
$quit.Header = 'Ampel beenden'
$quit.Add_Click({ $win.Close() })
[void]$menu.Items.Add($quit)
$win.ContextMenu = $menu

$pos = $null
try { $pos = [System.IO.File]::ReadAllText($posFile) | ConvertFrom-Json } catch {}
$work = [System.Windows.SystemParameters]::WorkArea
if ($pos) { $win.Left = $pos.left; $win.Top = $pos.top } else { $win.Left = $work.Right - 40; $win.Top = $work.Bottom - 100 }

function Save-Position {
  try { [System.IO.File]::WriteAllText($posFile, (@{ left = $win.Left; top = $win.Top } | ConvertTo-Json)) } catch {}
}

function Keep-OnScreen {
  $l = [System.Windows.SystemParameters]::VirtualScreenLeft
  $t = [System.Windows.SystemParameters]::VirtualScreenTop
  $r = $l + [System.Windows.SystemParameters]::VirtualScreenWidth
  $b = $t + [System.Windows.SystemParameters]::VirtualScreenHeight
  if ($win.Left + $win.ActualWidth -gt $r) { $win.Left = $r - $win.ActualWidth }
  if ($win.Top + $win.ActualHeight -gt $b) { $win.Top = $b - $win.ActualHeight }
  if ($win.Left -lt $l) { $win.Left = $l }
  if ($win.Top -lt $t) { $win.Top = $t }
}

$win.Add_MouseLeftButtonDown({
  param($sender, $e)
  $x = $win.Left; $y = $win.Top
  try { $win.DragMove() } catch {}
  if ($win.Left -ne $x -or $win.Top -ne $y) { Keep-OnScreen; Save-Position; return }

  # Kein Verschieben = Klick: angeklickte Ampel suchen und deren Session oeffnen
  $el = $e.OriginalSource
  while ($el -and -not ($el.Tag -is [string])) { $el = [System.Windows.Media.VisualTreeHelper]::GetParent($el) }
  if (-not $el) { return }
  $claudePid = $sessionPid[$el.Tag]
  $win.Cursor = [System.Windows.Input.Cursors]::Wait
  try {
    if (-not (Focus-ClaudeSession $claudePid)) { [System.Media.SystemSounds]::Beep.Play() }
  } catch {
    Add-Content -Path (Join-Path $base 'error.log') -Value "$(Get-Date -Format s) Fokus: $_"
  } finally { $win.Cursor = $null }
})
$win.Add_SizeChanged({ Keep-OnScreen })

$script:hwnd = [IntPtr]::Zero
$win.Add_SourceInitialized({
  $script:hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $win).Handle
  # Tool-Fenster: taucht nicht in Alt+Tab auf
  $ex = [AmpelNative]::GetWindowLong($script:hwnd, -20)
  [void][AmpelNative]::SetWindowLong($script:hwnd, -20, ($ex -bor 0x80))
})

# --- Aktualisierung -----------------------------------------------------------
$ampeln = @{}
$sessionPid = @{}
$script:order = ''
$script:tick = 0

function Test-SessionAlive($s) {
  if ($s.pid -gt 0) {
    try {
      $p = [System.Diagnostics.Process]::GetProcessById([int]$s.pid)
      if ($s.pname) { return ($p.ProcessName -eq $s.pname) }
      return ($p.ProcessName -match '^claude')
    } catch { return $false }
  }
  # Ohne bekannte PID: nach 12h ohne Lebenszeichen aufraeumen
  $age = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [long]$s.ts
  return ($age -lt 12 * 3600 * 1000)
}

function Update-Ampeln {
  $script:tick++
  $blinkOn = ($script:tick % 2) -eq 0

  $sessions = @()
  foreach ($f in [System.IO.Directory]::GetFiles($sessDir, '*.json')) {
    try { $s = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { continue }
    if (-not (Test-SessionAlive $s)) { try { Remove-Item -LiteralPath $f -Force } catch {}; continue }
    $sessions += $s
  }
  $sessions = @($sessions | Sort-Object { [long]$_.started })

  $seen = @{}
  foreach ($s in $sessions) {
    $id = [string]$s.session_id
    $seen[$id] = $true
    if (-not $ampeln.ContainsKey($id)) { $ampeln[$id] = New-Ampel }
    $a = $ampeln[$id]
    $a.Root.Tag = $id
    $a.Root.Cursor = [System.Windows.Input.Cursors]::Hand
    $sessionPid[$id] = [int]$s.pid
    Set-AmpelState $a ([string]$s.state) $blinkOn
    $folder = if ($s.cwd) { Split-Path -Leaf $s.cwd } else { '?' }
    $short = if ($folder.Length -gt 4) { $folder.Substring(0, 4) } else { $folder }
    $a.Label.Text = $short
    $tip = "$folder`n$($stateText[[string]$s.state])"
    if ($s.state -eq 'blue' -and $s.tool) { $tip += " ($($s.tool))" }
    $tip += "`n$($s.cwd)`nKlick: Session oeffnen"
    $a.Root.ToolTip = $tip
  }
  foreach ($id in @($ampeln.Keys)) { if (-not $seen[$id]) { $ampeln.Remove($id); $sessionPid.Remove($id) } }

  $newOrder = ($sessions | ForEach-Object { $_.session_id }) -join ','
  if ($newOrder -ne $script:order) {
    $script:order = $newOrder
    $panel.Children.Clear()
    foreach ($s in $sessions) { [void]$panel.Children.Add($ampeln[[string]$s.session_id].Root) }
  }

  # Ohne Session verschwindet die Ampel ganz, mit der ersten Session kommt sie zurueck
  if ($sessions.Count -eq 0) {
    if ($win.IsVisible) { $win.Hide() }
  } elseif (-not $win.IsVisible) {
    $win.Show()
    Keep-OnScreen
  }

  # Alle ~5s wieder ganz nach vorne holen (andere Topmost-Fenster koennen uns verdraengen)
  if ($script:hwnd -ne [IntPtr]::Zero -and ($script:tick % 12) -eq 0 -and -not $menu.IsOpen) {
    [void][AmpelNative]::SetWindowPos($script:hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x0013)
  }
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(400)
$timer.Add_Tick({ try { Update-Ampeln } catch { Add-Content -Path (Join-Path $base 'error.log') -Value "$(Get-Date -Format s) $_" } })

# Fenster startet unsichtbar, Update-Ampeln blendet es erst bei einer Session ein.
# Application.Run statt ShowDialog: ein Dialog wuerde beim Verstecken beendet.
$app = New-Object System.Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'
$win.Add_Closed({ $timer.Stop(); $app.Shutdown() })
$timer.Start()
[void]$app.Run()
$mutex.ReleaseMutex()
