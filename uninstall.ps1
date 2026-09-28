# Entfernt die Claude-Ampel wieder: Hooks, Verknuepfungen, laufende Ampel und gespeicherte Stati.
# Der Programmordner selbst bleibt liegen und kann danach von Hand geloescht werden.
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot

Write-Host 'Claude-Ampel wird entfernt...' -ForegroundColor Cyan

if (Get-Command node -ErrorAction SilentlyContinue) {
  & node (Join-Path $dir 'setup-hooks.js') uninstall
} else {
  Write-Host 'Node.js nicht gefunden - Hooks in ~/.claude/settings.json bitte von Hand entfernen (Eintraege mit "claude-ampel").' -ForegroundColor Yellow
}

foreach ($folder in [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Startup')) {
  $lnk = Join-Path $folder 'Claude-Ampel.lnk'
  if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force; Write-Host "Entfernt: $lnk" }
}

# Laufende Ampel beenden (powershell.exe, das ampel.ps1 aus diesem Ordner ausfuehrt)
$ampel = (Join-Path $dir 'ampel.ps1')
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
  Where-Object { $_.CommandLine -and $_.CommandLine.Contains($ampel) } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$data = Join-Path $env:LOCALAPPDATA 'claude-ampel'
if (Test-Path -LiteralPath $data) { Remove-Item -LiteralPath $data -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host 'Fertig. Den Ordner mit den Programmdateien kannst du jetzt loeschen.' -ForegroundColor Green
