Set-Location "$PSScriptRoot\..\out\build\release"
$env:AA_AUTO_START = "1"
$env:XBE_CAPTURE_DIR = "captures"

Write-Host "Starting aa_roas.exe with AA_AUTO_START=1..."
$p = Start-Process -FilePath ".\aa_roas.exe" -PassThru
Start-Sleep -Seconds 10

if (-not $p.HasExited) {
    Write-Host "Process running (PID: $($p.Id))"
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "Process exited with code: $($p.ExitCode)"
}

$latestLog = Get-ChildItem -Path "logs" -Filter "*.log" | Where-Object { $_.Name -like "aa_roas_*.log" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "Latest log: $($latestLog.FullName)"
Get-Content -Path $latestLog.FullName | Select-String "input:|xapi:|d3d12: frame captured|open Z:\\UI|pkg" | Select-Object -Last 30

Write-Host "`nAll captures:"
Get-ChildItem -Path "captures" | Select-Object Name,LastWriteTime
