# Installiert die Claude-Ampel fuer den aktuellen Windows-Benutzer:
# Hooks in ~/.claude/settings.json, Verknuepfung auf dem Desktop und im Autostart, Ampel starten.
# Die Dateien bleiben in diesem Ordner - nach der Installation nicht mehr verschieben
# (sonst einfach install.ps1 am neuen Ort nochmals ausfuehren).
param(
  [switch]$NoAutostart,
  [switch]$NoDesktop
)
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot

Write-Host 'Claude-Ampel wird installiert...' -ForegroundColor Cyan

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host 'Node.js wurde nicht gefunden. Bitte zuerst Node.js installieren: https://nodejs.org' -ForegroundColor Red
  exit 1
}

# Aus dem Internet geladene Dateien entsperren, sonst blockiert Windows die Skripte
Get-ChildItem -LiteralPath $dir -File | Unblock-File

& node (Join-Path $dir 'setup-hooks.js') install
if ($LASTEXITCODE -ne 0) { Write-Host 'Hooks konnten nicht eingetragen werden.' -ForegroundColor Red; exit 1 }

$sh = New-Object -ComObject WScript.Shell
function New-AmpelShortcut([string]$folder) {
  $lnk = $sh.CreateShortcut((Join-Path $folder 'Claude-Ampel.lnk'))
  $lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
  $lnk.Arguments = '"' + (Join-Path $dir 'start-ampel.vbs') + '"'
  $lnk.WorkingDirectory = $dir
  $lnk.IconLocation = (Join-Path $env:WINDIR 'System32\imageres.dll') + ',101'
  $lnk.Description = 'Claude-Ampel starten'
  $lnk.Save()
}
if (-not $NoDesktop)   { New-AmpelShortcut ([Environment]::GetFolderPath('Desktop')); Write-Host 'Verknuepfung auf dem Desktop erstellt.' }
if (-not $NoAutostart) { New-AmpelShortcut ([Environment]::GetFolderPath('Startup')); Write-Host 'Autostart eingerichtet.' }

Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"' + (Join-Path $dir 'start-ampel.vbs') + '"')

Write-Host ''
Write-Host 'Fertig! Die Ampel laeuft (beim ersten Start unten rechts am Bildschirm).' -ForegroundColor Green
Write-Host 'Wichtig: Bereits offene Claude-Code-Sessions neu starten, damit sie die Hooks laden.'
