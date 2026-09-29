# Claude-Ampel: kleines, immer sichtbares Fenster mit einer Ampel pro Claude-Code-Session.
# Rot = braucht deine Eingabe, Gelb = arbeitet, Gruen = fertig, Blau = Shell aktiv.
# Klick auf eine Ampel holt das Terminal dieser Session nach vorne, Ziehen verschiebt.
# Die Stati schreibt hook.js nach %LOCALAPPDATA%\claude-ampel\sessions.
# Daneben: Nutzung des 5-Stunden- und Wochenlimits mit Reset-Zeit (wie /usage in Claude Code).

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Net.Http
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

$root = New-Object System.Windows.Controls.StackPanel
$root.Orientation = 'Horizontal'
$win.Content = $root

$panel = New-Object System.Windows.Controls.StackPanel
$panel.Orientation = 'Horizontal'
[void]$root.Children.Add($panel)

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
  if ($el.Tag -eq 'usage') { $script:usageNext = [DateTime]::MinValue; return }
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

# --- Usage-Limits -------------------------------------------------------------
# Gleiche Quelle wie /usage in Claude Code: api.anthropic.com/api/oauth/usage mit dem
# OAuth-Token aus ~/.claude/.credentials.json (Claude Code erneuert ihn selbst).
# Nur lesend. Ohne Anmeldung per Claude-Abo bleibt der Block einfach weg.
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
$credFile  = Join-Path $env:USERPROFILE '.claude\.credentials.json'
$deCulture = [System.Globalization.CultureInfo]::GetCultureInfo('de-CH')
$invariant = [System.Globalization.CultureInfo]::InvariantCulture
$http = New-Object System.Net.Http.HttpClient
$http.Timeout = [TimeSpan]::FromSeconds(15)
$script:usageTask = $null
$script:usageNext = [DateTime]::MinValue
$script:usageData = $null
$script:usageAt   = $null

$usageBox = New-Object System.Windows.Controls.Border
$usageBox.CornerRadius = 5
$usageBox.Background = New-Brush '#1C1C1E'
$usageBox.BorderBrush = New-Brush '#48484A'
$usageBox.BorderThickness = 1
$usageBox.Padding = '7,4,7,4'
$usageBox.Margin = '1,0'
$usageBox.Visibility = 'Collapsed'
$usageBox.Tag = 'usage'
$usageBox.Cursor = [System.Windows.Input.Cursors]::Hand
$usageStack = New-Object System.Windows.Controls.StackPanel
$usageStack.VerticalAlignment = 'Center'
$usageBox.Child = $usageStack
[void]$root.Children.Add($usageBox)

$usageBarWidth = 98
function New-UsageRow([string]$name) {
  $grid = New-Object System.Windows.Controls.Grid
  $grid.Margin = '0,3,0,3'
  foreach ($w in 16, 30, 52) {
    $c = New-Object System.Windows.Controls.ColumnDefinition
    $c.Width = New-Object System.Windows.GridLength $w
    $grid.ColumnDefinitions.Add($c)
  }
  foreach ($i in 0, 1) {
    $r = New-Object System.Windows.Controls.RowDefinition
    $r.Height = [System.Windows.GridLength]::Auto
    $grid.RowDefinitions.Add($r)
  }
  $cells = foreach ($i in 0..2) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.FontSize = 10
    $t.Foreground = New-Brush '#8E8E93'
    [System.Windows.Controls.Grid]::SetColumn($t, $i)
    [void]$grid.Children.Add($t)
    $t
  }
  $cells[0].Text = $name
  $cells[1].FontWeight = 'SemiBold'
  $cells[1].TextAlignment = 'Right'
  $cells[1].Margin = '0,0,6,0'

  # duenner Fortschrittsbalken unter der Zeile
  $track = New-Object System.Windows.Controls.Border
  $track.Height = 2
  $track.Width = $usageBarWidth
  $track.HorizontalAlignment = 'Left'
  $track.CornerRadius = 1
  $track.Margin = '0,2,0,0'
  $track.Background = New-Brush '#3A3A3C'
  $fill = New-Object System.Windows.Controls.Border
  $fill.CornerRadius = 1
  $fill.HorizontalAlignment = 'Left'
  $fill.Width = 0
  $track.Child = $fill
  [System.Windows.Controls.Grid]::SetRow($track, 1)
  [System.Windows.Controls.Grid]::SetColumnSpan($track, 3)
  [void]$grid.Children.Add($track)

  [void]$usageStack.Children.Add($grid)
  @{ Pct = $cells[1]; Reset = $cells[2]; Fill = $fill }
}
$rowSession = New-UsageRow '5h'
$rowWeek    = New-UsageRow 'Wo'

function Get-ResetTime($lim) {
  if (-not $lim -or -not $lim.resets_at) { return $null }
  [DateTimeOffset]::Parse([string]$lim.resets_at, $invariant)
}

function Format-Reset($lim, [bool]$withDay) {
  $r = Get-ResetTime $lim
  if (-not $r) { return '' }
  $t = $r.LocalDateTime
  if (-not $withDay) { return $t.ToString('HH:mm') }
  "$($t.ToString('ddd', $deCulture).TrimEnd('.')) $($t.ToString('HH:mm'))"
}

function Format-Left($lim) {
  $r = Get-ResetTime $lim
  if (-not $r) { return '' }
  $left = $r - [DateTimeOffset]::Now
  if ($left.TotalMinutes -lt 1) { return 'jetzt' }
  if ($left.TotalHours -ge 24) { return ('in {0} T {1} h' -f [int][Math]::Floor($left.TotalDays), $left.Hours) }
  if ($left.TotalHours -ge 1)  { return ('in {0} h {1:00} min' -f [int][Math]::Floor($left.TotalHours), $left.Minutes) }
  'in {0} min' -f [int][Math]::Ceiling($left.TotalMinutes)
}

function Set-UsageRow($row, $lim, [bool]$withDay) {
  if (-not $lim -or $null -eq $lim.utilization) {
    $row.Pct.Text = '-'; $row.Reset.Text = ''; $row.Fill.Width = 0; return
  }
  $p = [double]$lim.utilization
  # Reset-Zeit vorbei, aber noch keine frischen Daten: Limit ist bereits zurueckgesetzt
  $r = Get-ResetTime $lim
  $expired = $r -and $r -le [DateTimeOffset]::Now
  if ($expired) { $p = 0 }
  $color = if ($p -ge 90) { '#FF3B30' } elseif ($p -ge 70) { '#FFCC00' } else { '#E5E5EA' }
  $row.Pct.Text = '{0:0}%' -f $p
  $row.Pct.Foreground = New-Brush $color
  $row.Reset.Text = if ($expired) { '' } else { Format-Reset $lim $withDay }
  $row.Fill.Background = New-Brush $color
  $row.Fill.Width = [Math]::Max(0, [Math]::Min($usageBarWidth, $usageBarWidth * $p / 100))
}

function Update-Usage {
  # fertige Abfrage abholen
  if ($script:usageTask -and $script:usageTask.IsCompleted) {
    $t = $script:usageTask; $script:usageTask = $null
    if ($t.IsFaulted -or $t.IsCanceled) {
      Add-Content -Path (Join-Path $base 'error.log') -Value "$(Get-Date -Format s) Usage: keine Verbindung"
    } else {
      $resp = $t.Result
      if ($resp.IsSuccessStatusCode) {
        $script:usageData = $resp.Content.ReadAsStringAsync().Result | ConvertFrom-Json
        $script:usageAt = Get-Date
      } elseif ([int]$resp.StatusCode -eq 429) {
        $script:usageNext = (Get-Date).AddMinutes(5)
      }
      $resp.Dispose()
    }
  }

  # neue Abfrage starten: jede Minute, nur solange das Fenster sichtbar ist
  if (-not $script:usageTask -and $win.IsVisible -and (Get-Date) -ge $script:usageNext) {
    $script:usageNext = (Get-Date).AddSeconds(60)
    $cred = $null
    try { $cred = ([System.IO.File]::ReadAllText($credFile) | ConvertFrom-Json).claudeAiOauth } catch {}
    if ($cred -and $cred.accessToken) {
      $req = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::Get), 'https://api.anthropic.com/api/oauth/usage'
      $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue 'Bearer', $cred.accessToken
      [void]$req.Headers.TryAddWithoutValidation('anthropic-beta', 'oauth-2025-04-20')
      $script:usageTask = $http.SendAsync($req)
    }
  }

  $d = $script:usageData
  if (-not $d) { $usageBox.Visibility = 'Collapsed'; return }
  $usageBox.Visibility = 'Visible'
  Set-UsageRow $rowSession $d.five_hour $false
  Set-UsageRow $rowWeek $d.seven_day $true
  # Daten aelter als 5 min (offline, Token abgelaufen): gedimmt anzeigen
  $usageStack.Opacity = if (((Get-Date) - $script:usageAt).TotalMinutes -gt 5) { 0.45 } else { 1 }

  $tip = 'Claude-Nutzung (wie /usage)'
  foreach ($x in @(@('5-Stunden-Limit', $d.five_hour, $false), @('Wochenlimit', $d.seven_day, $true))) {
    $lim = $x[1]
    if ($lim -and $null -ne $lim.utilization) {
      $tip += "`n{0}: {1:0}% - Reset {2} ({3})" -f $x[0], [double]$lim.utilization, (Format-Reset $lim $x[2]), (Format-Left $lim)
    }
  }
  $tip += "`nStand $($script:usageAt.ToString('HH:mm:ss')) - Klick: aktualisieren"
  $usageBox.ToolTip = $tip
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(400)
$timer.Add_Tick({
  try { Update-Ampeln } catch { Add-Content -Path (Join-Path $base 'error.log') -Value "$(Get-Date -Format s) $_" }
  try { Update-Usage } catch { Add-Content -Path (Join-Path $base 'error.log') -Value "$(Get-Date -Format s) Usage: $_" }
})

# Fenster startet unsichtbar, Update-Ampeln blendet es erst bei einer Session ein.
# Application.Run statt ShowDialog: ein Dialog wuerde beim Verstecken beendet.
$app = New-Object System.Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'
$win.Add_Closed({ $timer.Stop(); $app.Shutdown() })
$timer.Start()
[void]$app.Run()
$mutex.ReleaseMutex()
