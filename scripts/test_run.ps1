Set-Location "$PSScriptRoot\..\out\build\release"
$env:XBE_CAPTURE_DIR = "captures"

$p = Start-Process -FilePath ".\aa_roas.exe" -PassThru
Start-Sleep -Seconds 7

if (-not $p.HasExited) {
    Write-Host "Process is still running smoothly (PID: $($p.Id))"
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "Process exited with code: $($p.ExitCode)"
}

$latestLog = Get-ChildItem -Path "logs" -Filter "*.log" | Where-Object { $_.Name -like "aa_roas_*.log" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "Latest log: $($latestLog.FullName)"
Get-Content -Path $latestLog.FullName | Select-String "d3d|gpu|Present|Swap|Clear|Draw|captur" | Select-Object -Last 20

Write-Host "`nChecking captured files:"
Get-ChildItem -Path "captures" -Recurse | Select-Object FullName,Length
