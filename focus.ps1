# Holt das Terminal einer Claude-Code-Session (per claude.exe-PID) nach vorne.
# Klassische Konsole: Fenster direkt aktivieren.
# Windows Terminal: kurz einen eindeutigen Titel setzen, den Tab mit diesem Titel
# per UI Automation auswaehlen, danach den alten Titel wiederherstellen.

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class AmpelFocus {
  [DllImport("kernel32.dll")] static extern bool FreeConsole();
  [DllImport("kernel32.dll")] static extern bool AttachConsole(uint pid);
  [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern uint GetConsoleTitle(StringBuilder sb, uint n);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool SetConsoleTitle(string t);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder sb, int n);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);

  // Haengt sich an die Konsole von pid, liest den Titel, setzt optional einen neuen.
  // Liefert false, wenn die Konsole nicht erreichbar ist.
  public static bool SwapTitle(uint pid, string newTitle, out string oldTitle, out IntPtr window, out string windowClass) {
    oldTitle = null; window = IntPtr.Zero; windowClass = "";
    FreeConsole();
    if (!AttachConsole(pid)) return false;
    try {
      var sb = new StringBuilder(1024);
      GetConsoleTitle(sb, (uint)sb.Capacity);
      oldTitle = sb.ToString();
      window = GetConsoleWindow();
      var cls = new StringBuilder(256);
      if (window != IntPtr.Zero) GetClassName(window, cls, cls.Capacity);
      windowClass = cls.ToString();
      if (newTitle != null) SetConsoleTitle(newTitle);
      return true;
    } finally {
      FreeConsole();
    }
  }

  public static void Activate(IntPtr h) {
    if (IsIconic(h)) ShowWindow(h, 9); // SW_RESTORE
    SetForegroundWindow(h);
  }
}
"@

function Get-TerminalTabs {
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $wtCond = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ClassNameProperty), 'CASCADIA_HOSTING_WINDOW_CLASS'
  $tabCond = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ControlTypeProperty), ([System.Windows.Automation.ControlType]::TabItem)
  foreach ($w in $root.FindAll([System.Windows.Automation.TreeScope]::Children, $wtCond)) {
    foreach ($tab in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCond)) {
      @{ Window = $w; Tab = $tab; Name = $tab.Current.Name; Id = ($tab.GetRuntimeId() -join '.') }
    }
  }
}

# Liefert $true, wenn das Terminal gefunden und nach vorne geholt wurde.
function Focus-ClaudeSession([int]$claudePid) {
  if ($claudePid -le 0) { return $false }
  $marker = 'AMPEL-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
  $old = $null; $hwnd = [IntPtr]::Zero; $cls = ''
  if (-not [AmpelFocus]::SwapTitle($claudePid, $null, [ref]$old, [ref]$hwnd, [ref]$cls)) { return $false }

  if ($cls -ne 'PseudoConsoleWindow' -and $hwnd -ne [IntPtr]::Zero) {
    [AmpelFocus]::Activate($hwnd)   # klassisches Konsolenfenster
    return $true
  }

  # Windows Terminal: Claude ueberschreibt den Titel beim Arbeiten staendig,
  # darum den Marker wiederholt setzen, bis der Tab ihn anzeigt.
  # Tab-Namen vorher merken: Claude setzt den Titel per Escape-Sequenz direkt im
  # Terminal, die Konsole selbst kennt ihn nicht.
  $before = @{}
  foreach ($t in Get-TerminalTabs) { $before[$t.Id] = $t.Name }
  $found = $null
  $deadline = [DateTime]::Now.AddSeconds(2)
  while (-not $found -and [DateTime]::Now -lt $deadline) {
    $o = $null; $h = [IntPtr]::Zero; $c = ''
    [void][AmpelFocus]::SwapTitle($claudePid, $marker, [ref]$o, [ref]$h, [ref]$c)
    Start-Sleep -Milliseconds 60
    $found = Get-TerminalTabs | Where-Object { $_.Name -like "*$marker*" } | Select-Object -First 1
  }
  if ($found -and $before[$found.Id]) { $old = $before[$found.Id] }
  $o = $null; $h = [IntPtr]::Zero; $c = ''
  [void][AmpelFocus]::SwapTitle($claudePid, $old, [ref]$o, [ref]$h, [ref]$c)
  if (-not $found) { return $false }

  try { $found.Tab.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() } catch {}
  [AmpelFocus]::Activate([IntPtr]$found.Window.Current.NativeWindowHandle)
  $true
}
