# Brings the terminal of a Claude Code session (by claude.exe PID) to the front.
# Classic console: activate the window directly.
# Windows Terminal: briefly set a unique title, select the tab with that title via
# UI Automation, then restore the old title.

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

  // Attaches to the console of pid, reads the title, optionally sets a new one.
  // Returns false if the console can't be reached.
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

# Returns $true if the terminal was found and brought to the front.
function Focus-ClaudeSession([int]$claudePid) {
  if ($claudePid -le 0) { return $false }
  $marker = 'AMPEL-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
  $old = $null; $hwnd = [IntPtr]::Zero; $cls = ''
  if (-not [AmpelFocus]::SwapTitle($claudePid, $null, [ref]$old, [ref]$hwnd, [ref]$cls)) { return $false }

  if ($cls -ne 'PseudoConsoleWindow' -and $hwnd -ne [IntPtr]::Zero) {
    [AmpelFocus]::Activate($hwnd)   # classic console window
    return $true
  }

  # Windows Terminal: Claude keeps overwriting the title while working,
  # so set the marker repeatedly until the tab shows it.
  # Remember the tab names first: Claude sets the title via escape sequence directly
  # in the terminal, the console itself doesn't know it.
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
