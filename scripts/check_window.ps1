Set-Location "$PSScriptRoot\..\out\build\release"
$p = Start-Process -FilePath ".\aa_roas.exe" -PassThru
Start-Sleep -Seconds 6
$p.Refresh()
Write-Host "HasExited: $($p.HasExited)"
Write-Host "MainWindowHandle: $($p.MainWindowHandle)"
Write-Host "MainWindowTitle: $($p.MainWindowTitle)"
if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
