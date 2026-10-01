# Installs Claude-Ampel for the current Windows user:
# hooks in ~/.claude/settings.json, shortcut on the desktop and in startup, start the light.
# The files stay in this folder - don't move them after installing
# (otherwise just run install.ps1 again in the new location).
param(
  [switch]$NoAutostart,
  [switch]$NoDesktop
)
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot

Write-Host 'Installing Claude-Ampel...' -ForegroundColor Cyan

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host 'Node.js was not found. Please install Node.js first: https://nodejs.org' -ForegroundColor Red
  exit 1
}

# Unblock files downloaded from the internet, otherwise Windows blocks the scripts
Get-ChildItem -LiteralPath $dir -File | Unblock-File

& node (Join-Path $dir 'setup-hooks.js') install
if ($LASTEXITCODE -ne 0) { Write-Host 'Could not register the hooks.' -ForegroundColor Red; exit 1 }

$sh = New-Object -ComObject WScript.Shell
function New-AmpelShortcut([string]$folder) {
  $lnk = $sh.CreateShortcut((Join-Path $folder 'Claude-Ampel.lnk'))
  $lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
  $lnk.Arguments = '"' + (Join-Path $dir 'start-ampel.vbs') + '"'
  $lnk.WorkingDirectory = $dir
  $lnk.IconLocation = (Join-Path $env:WINDIR 'System32\imageres.dll') + ',101'
  $lnk.Description = 'Start Claude-Ampel'
  $lnk.Save()
}
if (-not $NoDesktop)   { New-AmpelShortcut ([Environment]::GetFolderPath('Desktop')); Write-Host 'Desktop shortcut created.' }
if (-not $NoAutostart) { New-AmpelShortcut ([Environment]::GetFolderPath('Startup')); Write-Host 'Startup entry created.' }

Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"' + (Join-Path $dir 'start-ampel.vbs') + '"')

Write-Host ''
Write-Host 'Done! The light is running (on first start at the bottom right of the screen).' -ForegroundColor Green
Write-Host 'Important: restart any Claude Code sessions that are already open so they load the hooks.'
