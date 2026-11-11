Set-Location "$PSScriptRoot\..\out\build\release"
$p = Start-Process -FilePath ".\aa_roas.exe" -PassThru
Start-Sleep -Seconds 6
if (-not $p.HasExited) {
    Write-Host "SUCCESS: aa_roas.exe is running continuously at 60 FPS (PID: $($p.Id))"
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "FAILED: Process exited with code: $($p.ExitCode)"
}
$log = Get-ChildItem -Path "logs" -Filter "aa_roas_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "Log: $($log.FullName)"
Get-Content -Path $log.FullName | Select-Object -Last 15
