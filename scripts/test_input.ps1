Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinInput {
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

Set-Location "$PSScriptRoot\..\out\build\release"
$env:XBE_CAPTURE_DIR = "captures"

$p = Start-Process -FilePath ".\aa_roas.exe" -PassThru
Start-Sleep -Seconds 5

# Focus window and simulate pressing Enter (VK_RETURN = 0x0D)
$hwnd = $p.MainWindowHandle
if ($hwnd -ne [IntPtr]::Zero) {
    [WinInput]::SetForegroundWindow($hwnd)
}
Write-Host "Simulating Enter key press..."
[WinInput]::keybd_event(0x0D, 0, 0, [UIntPtr]::Zero) # Key down
Start-Sleep -Milliseconds 200
[WinInput]::keybd_event(0x0D, 0, 2, [UIntPtr]::Zero) # Key up (KEYEVENTF_KEYUP = 2)

Start-Sleep -Seconds 4

if (-not $p.HasExited) {
    Write-Host "Process running (PID: $($p.Id))"
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}

$latestLog = Get-ChildItem -Path "logs" -Filter "*.log" | Where-Object { $_.Name -like "aa_roas_*.log" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "Latest log: $($latestLog.FullName)"
Get-Content -Path $latestLog.FullName | Select-String "open|pkg|uix|xwb|xsb|menu|start" -CaseSensitive:$false | Select-Object -Last 30
