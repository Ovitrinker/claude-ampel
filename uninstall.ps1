# Removes Claude-Ampel again: hooks, shortcuts, the running light and stored states.
# The program folder itself stays and can be deleted by hand afterwards.
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot

Write-Host 'Removing Claude-Ampel...' -ForegroundColor Cyan

if (Get-Command node -ErrorAction SilentlyContinue) {
  & node (Join-Path $dir 'setup-hooks.js') uninstall
} else {
  Write-Host 'Node.js not found - please remove the hooks in ~/.claude/settings.json by hand (entries containing "claude-ampel").' -ForegroundColor Yellow
}

foreach ($folder in [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Startup')) {
  $lnk = Join-Path $folder 'Claude-Ampel.lnk'
  if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force; Write-Host "Removed: $lnk" }
}

# Stop the running light (powershell.exe running ampel.ps1 from this folder)
$ampel = (Join-Path $dir 'ampel.ps1')
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
  Where-Object { $_.CommandLine -and $_.CommandLine.Contains($ampel) } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$data = Join-Path $env:LOCALAPPDATA 'claude-ampel'
if (Test-Path -LiteralPath $data) { Remove-Item -LiteralPath $data -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host 'Done. You can now delete the folder with the program files.' -ForegroundColor Green
