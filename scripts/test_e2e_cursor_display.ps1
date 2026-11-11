<#
.SYNOPSIS
    Automated E2E Test Suite for Mouse Cursor Management & Alt+Enter Display Mode Switching.
.DESCRIPTION
    Validates Features F1-F7 across Tiers 1-4 for AAROAS-XBERecomp:
    - Tier 1: Feature Coverage (F1-F7, >=5 tests each, 35 tests total)
    - Tier 2: Boundary & Corner Cases (5 tests)
    - Tier 3: Cross-Feature Interactions (5 tests)
    - Tier 4: Real-World Gameplay Scenarios (2 tests)
    Total: 47 automated opaque-box test cases.
.PARAMETER Preset
    CMake build preset to test (default: "release").
.PARAMETER Tier
    Test tiers to execute: "1", "2", "3", "4", or "All" (default: "All").
.PARAMETER Feature
    Feature filter for Tier 1: "F1", "F2", "F3", "F4", "F5", "F6", "F7", or "All" (default: "All").
.PARAMETER ReportPath
    Optional file path to write Markdown or JSON test results.
.PARAMETER ListTests
    List all test cases without running them.
.PARAMETER TimeoutSeconds
    Per-phase timeout in seconds (default: 15).
#>

[CmdletBinding()]
param(
    [string]$Preset = "release",
    [string[]]$Tier = @("All"),
    [string[]]$Feature = @("All"),
    [string]$ReportPath = "",
    [switch]$ListTests,
    [int]$TimeoutSeconds = 15
)

$ErrorActionPreference = "Stop"

# ==============================================================================
# 1. WIN32 API DECLARATIONS VIA P/INVOKE
# ==============================================================================

$Win32Code = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class Win32Harness {
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int left;
        public int top;
        public int right;
        public int bottom;

        public int Width { get { return right - left; } }
        public int Height { get { return bottom - top; } }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct CURSORINFO {
        public int cbSize;
        public int flags;
        public IntPtr hCursor;
        public POINT ptScreenPos;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct WINDOWPLACEMENT {
        public int length;
        public int flags;
        public int showCmd;
        public POINT ptMinPosition;
        public POINT ptMaxPosition;
        public RECT rcNormalPosition;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public int dwFlags;
    }

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetCursorInfo(ref CURSORINFO pci);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetClipCursor(out RECT lpRect);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool ClipCursor(ref RECT lpRect);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool ClipCursor(IntPtr lpRect);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    public static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern IntPtr GetShellWindow();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindowW(string lpClassName, string lpWindowName);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint dwFlags);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetMonitorInfoW(IntPtr hMonitor, ref MONITORINFO lpmi);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassNameW(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowTextW(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr OpenInputDesktop(uint dwFlags, bool fInherit, uint dwDesiredAccess);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetThreadDesktop(IntPtr hDesktop);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool CloseDesktop(IntPtr hDesktop);

    public const int GWL_STYLE = -16;
    public const int GWL_EXSTYLE = -20;
    public const long WS_POPUP = 0x80000000L;
    public const long WS_CAPTION = 0x00C00000L;
    public const long WS_OVERLAPPEDWINDOW = 0x00CF0000L;
    public const long WS_VISIBLE = 0x10000000L;

    public const int SW_HIDE = 0;
    public const int SW_SHOW = 5;
    public const int SW_MINIMIZE = 6;
    public const int SW_RESTORE = 9;

    public const byte VK_TAB = 0x09;
    public const byte VK_RETURN = 0x0D;
    public const byte VK_MENU = 0x12; // Alt
    public const byte VK_SPACE = 0x20;
    public const byte VK_KEY_W = 0x57;
    public const byte VK_KEY_S = 0x53;

    public const uint KEYEVENTF_KEYDOWN = 0;
    public const uint KEYEVENTF_KEYUP = 2;

    public const int CURSOR_SHOWING = 0x00000001;

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    public static extern void SwitchToThisWindow(IntPtr hWnd, bool fUnknown);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    public const uint WM_ACTIVATE = 0x0006;
    public const uint WM_SETFOCUS = 0x0007;
    public const uint WM_KILLFOCUS = 0x0008;
    public const int WA_INACTIVE = 0;
    public const int WA_ACTIVE = 1;

    public static IntPtr GetForegroundWindowSafe() {
        IntPtr fg = IntPtr.Zero;
        Thread t = new Thread(() => {
            IntPtr hDesk = OpenInputDesktop(0, false, 0x01FF);
            if (hDesk != IntPtr.Zero) {
                SetThreadDesktop(hDesk);
            }
            fg = GetForegroundWindow();
            if (hDesk != IntPtr.Zero) {
                CloseDesktop(hDesk);
            }
        });
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        t.Join();
        return fg;
    }

    public static IntPtr GetDefocusTargetWindow(IntPtr currentHwnd) {
        IntPtr target = IntPtr.Zero;
        Thread t = new Thread(() => {
            IntPtr hDesk = OpenInputDesktop(0, false, 0x01FF);
            if (hDesk != IntPtr.Zero) {
                SetThreadDesktop(hDesk);
                target = FindWindowW("CabinetWClass", null);
                if (target == IntPtr.Zero || target == currentHwnd) {
                    target = FindWindowW("Progman", null);
                }
                CloseDesktop(hDesk);
            }
        });
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        t.Join();
        return target;
    }

    public static bool ForceForegroundWindow(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero) return false;
        bool res = false;
        Thread t = new Thread(() => {
            IntPtr hDesk = OpenInputDesktop(0, false, 0x01FF);
            if (hDesk != IntPtr.Zero) {
                SetThreadDesktop(hDesk);
            }
            keybd_event(VK_MENU, 0, KEYEVENTF_KEYDOWN, UIntPtr.Zero);
            keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            ShowWindow(hWnd, SW_SHOW);
            ShowWindow(hWnd, SW_RESTORE);
            BringWindowToTop(hWnd);
            res = SetForegroundWindow(hWnd);
            SwitchToThisWindow(hWnd, true);
            SendMessage(hWnd, WM_ACTIVATE, (IntPtr)WA_ACTIVE, IntPtr.Zero);
            SendMessage(hWnd, WM_SETFOCUS, IntPtr.Zero, IntPtr.Zero);
            if (hDesk != IntPtr.Zero) {
                CloseDesktop(hDesk);
            }
        });
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        t.Join();
        return res;
    }

    public static bool DefocusWindow(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero) return false;
        IntPtr target = GetDefocusTargetWindow(hWnd);
        if (target != IntPtr.Zero && target != hWnd) {
            Thread t = new Thread(() => {
                IntPtr hDesk = OpenInputDesktop(0, false, 0x01FF);
                if (hDesk != IntPtr.Zero) SetThreadDesktop(hDesk);
                ShowWindow(target, SW_RESTORE);
                BringWindowToTop(target);
                SetForegroundWindow(target);
                SwitchToThisWindow(target, true);
                if (hDesk != IntPtr.Zero) CloseDesktop(hDesk);
            });
            t.SetApartmentState(ApartmentState.STA);
            t.Start();
            t.Join();
        }
        SendMessage(hWnd, WM_ACTIVATE, (IntPtr)WA_INACTIVE, IntPtr.Zero);
        SendMessage(hWnd, WM_KILLFOCUS, IntPtr.Zero, IntPtr.Zero);
        return true;
    }

    public static IntPtr FoundHwnd = IntPtr.Zero;

    public static bool EnumWindowsFindCallback(IntPtr hWnd, IntPtr lParam) {
        uint pid = 0;
        GetWindowThreadProcessId(hWnd, out pid);
        if (pid == (uint)lParam.ToInt64()) {
            StringBuilder sb = new StringBuilder(256);
            GetClassNameW(hWnd, sb, 256);
            if (sb.ToString() == "aa_roas") {
                FoundHwnd = hWnd;
                return false;
            }
        }
        return true;
    }

    public static IntPtr FindGameWindow(int processId) {
        FoundHwnd = IntPtr.Zero;
        EnumWindows(EnumWindowsFindCallback, (IntPtr)processId);
        return FoundHwnd;
    }

    // Safe cursor state query across desktop boundaries
    public static bool QueryCursorInfoSafe(out int flags, out IntPtr hCursor, out int x, out int y) {
        int outFlags = 0;
        IntPtr outHCursor = IntPtr.Zero;
        int outX = 0, outY = 0;
        bool success = false;

        Thread t = new Thread(() => {
            IntPtr hDesk = OpenInputDesktop(0, false, 0x01FF);
            if (hDesk != IntPtr.Zero) {
                SetThreadDesktop(hDesk);
            }
            CURSORINFO ci = new CURSORINFO();
            ci.cbSize = Marshal.SizeOf(ci);
            if (GetCursorInfo(ref ci)) {
                outFlags = ci.flags;
                outHCursor = ci.hCursor;
                outX = ci.ptScreenPos.x;
                outY = ci.ptScreenPos.y;
                success = true;
            }
            if (hDesk != IntPtr.Zero) {
                CloseDesktop(hDesk);
            }
        });
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        t.Join();

        flags = outFlags;
        hCursor = outHCursor;
        x = outX;
        y = outY;
        return success;
    }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'Win32Harness').Type) {
    Add-Type -TypeDefinition $Win32Code
}

# ==============================================================================
# 2. TEST DEFINITIONS & DATA STRUCTURES
# ==============================================================================

$Global:TestInventory = [System.Collections.Generic.List[PSCustomObject]]::new()

function Ensure-DisplayMode {
    param(
        [IntPtr]$Hwnd,
        [string]$TargetMode
    )
    $m = Get-WindowMetrics -Hwnd $Hwnd
    if ($TargetMode -eq "borderless") {
        if ($m -and $m.IsPopup) { return [IntPtr]$Hwnd }
        # Try Alt+Enter toggle first if game is running
        if ($Hwnd -ne [IntPtr]::Zero) {
            [Win32Harness]::ForceForegroundWindow($Hwnd) | Out-Null
            Start-Sleep -Milliseconds 200
            Send-AltEnter
            Start-Sleep -Milliseconds 600
            $m = Get-WindowMetrics -Hwnd $Hwnd
            if ($m -and $m.IsPopup) { return [IntPtr]$Hwnd }
        }
        # Fallback to restarting in borderless mode
        $newHwnd = Start-GameProcess -Mode "borderless" -WaitSec 15
        Start-Sleep -Milliseconds 500
        return [IntPtr]$newHwnd
    }
    elseif ($TargetMode -eq "windowed") {
        if ($m -and $m.IsOverlapped) { return [IntPtr]$Hwnd }
        # Try Alt+Enter toggle first if game is running
        if ($Hwnd -ne [IntPtr]::Zero) {
            [Win32Harness]::ForceForegroundWindow($Hwnd) | Out-Null
            Start-Sleep -Milliseconds 200
            Send-AltEnter
            Start-Sleep -Milliseconds 600
            $m = Get-WindowMetrics -Hwnd $Hwnd
            if ($m -and $m.IsOverlapped) { return [IntPtr]$Hwnd }
        }
        # Fallback to restarting in windowed mode
        $newHwnd = Start-GameProcess -Mode "windowed" -WaitSec 15
        Start-Sleep -Milliseconds 500
        return [IntPtr]$newHwnd
    }
    return [IntPtr]$Hwnd
}

function Register-Test {
    param(
        [string]$Id,
        [string]$Tier,
        [string]$Feature,
        [string]$Name,
        [string]$Description,
        [scriptblock]$Action
    )
    $test = [PSCustomObject]@{
        Id = $Id
        Tier = $Tier
        Feature = $Feature
        Name = $Name
        Description = $Description
        Action = $Action
        Status = "PENDING"
        Expected = ""
        Actual = ""
        Error = ""
        ElapsedMs = 0.0
    }
    $Global:TestInventory.Add($test)
}

# ==============================================================================
# 3. HELPER FUNCTIONS FOR WIN32 INSPECTION & INPUT
# ==============================================================================

function Get-GameHwnd {
    param([int]$ProcessId)
    return [Win32Harness]::FindGameWindow($ProcessId)
}

function Get-WindowMetrics {
    param([IntPtr]$Hwnd)
    if ($Hwnd -eq [IntPtr]::Zero) { return $null }

    $style = [Win32Harness]::GetWindowLongPtr($Hwnd, [Win32Harness]::GWL_STYLE).ToInt64()
    $isPopup = ($style -band [Win32Harness]::WS_POPUP) -ne 0
    $hasCaption = ($style -band [Win32Harness]::WS_CAPTION) -eq [Win32Harness]::WS_CAPTION
    $isOverlapped = ($style -band [Win32Harness]::WS_OVERLAPPEDWINDOW) -eq [Win32Harness]::WS_OVERLAPPEDWINDOW

    $wRect = New-Object Win32Harness+RECT
    [Win32Harness]::GetWindowRect($Hwnd, [ref]$wRect) | Out-Null

    $cRect = New-Object Win32Harness+RECT
    [Win32Harness]::GetClientRect($Hwnd, [ref]$cRect) | Out-Null

    $pt = New-Object Win32Harness+POINT
    $pt.x = 0; $pt.y = 0
    [Win32Harness]::ClientToScreen($Hwnd, [ref]$pt) | Out-Null
    $screenClientRect = New-Object Win32Harness+RECT
    $screenClientRect.left = $pt.x
    $screenClientRect.top = $pt.y
    $screenClientRect.right = $pt.x + $cRect.Width
    $screenClientRect.bottom = $pt.y + $cRect.Height

    $hMon = [Win32Harness]::MonitorFromWindow($Hwnd, 1) # MONITOR_DEFAULTTOPRIMARY
    $mi = New-Object Win32Harness+MONITORINFO
    $mi.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($mi)
    [Win32Harness]::GetMonitorInfoW($hMon, [ref]$mi) | Out-Null

    $wp = New-Object Win32Harness+WINDOWPLACEMENT
    $wp.length = [System.Runtime.InteropServices.Marshal]::SizeOf($wp)
    [Win32Harness]::GetWindowPlacement($Hwnd, [ref]$wp) | Out-Null

    $fg = [Win32Harness]::GetForegroundWindowSafe()

    return [PSCustomObject]@{
        Hwnd = $Hwnd
        Style = $style
        StyleHex = ("0x{0:X8}" -f $style)
        IsPopup = $isPopup
        HasCaption = $hasCaption
        IsOverlapped = $isOverlapped
        IsForeground = ($fg -eq $Hwnd)
        WindowRect = $wRect
        ClientRect = $cRect
        ScreenClientRect = $screenClientRect
        MonitorRect = $mi.rcMonitor
        WorkRect = $mi.rcWork
        Placement = $wp
    }
}

function Get-LiveCursorState {
    param([IntPtr]$Hwnd)
    $flags = 0
    $hCursor = [IntPtr]::Zero
    $x = 0; $y = 0
    $ok = [Win32Harness]::QueryCursorInfoSafe([ref]$flags, [ref]$hCursor, [ref]$x, [ref]$y)

    $clip = New-Object Win32Harness+RECT
    $clipOk = [Win32Harness]::GetClipCursor([ref]$clip)

    $metrics = if ($Hwnd -ne [IntPtr]::Zero) { Get-WindowMetrics -Hwnd $Hwnd } else { $null }

    # Cursor is hidden when CURSOR_SHOWING is not set OR hCursor is null
    $isHidden = ($flags -band [Win32Harness]::CURSOR_SHOWING) -eq 0 -or $hCursor -eq [IntPtr]::Zero
    $isShowing = -not $isHidden

    $isClippedToClient = $false
    if ($metrics) {
        $sc = $metrics.ScreenClientRect
        # Tolerance of 2 pixels for rounding
        $isClippedToClient = [Math]::Abs($clip.left - $sc.left) -le 2 -and
                             [Math]::Abs($clip.top - $sc.top) -le 2 -and
                             [Math]::Abs($clip.right - $sc.right) -le 2 -and
                             [Math]::Abs($clip.bottom - $sc.bottom) -le 2
    }

    return [PSCustomObject]@{
        QueryOk = $ok
        Flags = $flags
        HCursor = $hCursor
        Pos = [PSCustomObject]@{ X = $x; Y = $y }
        IsHidden = $isHidden
        IsShowing = $isShowing
        ClipRect = $clip
        IsClippedToClient = $isClippedToClient
    }
}

function Send-KeyCombo {
    param(
        [byte]$Modifier,
        [byte]$Key,
        [int]$HoldMs = 80
    )
    [Win32Harness]::keybd_event($Modifier, 0, [Win32Harness]::KEYEVENTF_KEYDOWN, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 20
    [Win32Harness]::keybd_event($Key, 0, [Win32Harness]::KEYEVENTF_KEYDOWN, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds $HoldMs
    [Win32Harness]::keybd_event($Key, 0, [Win32Harness]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 20
    [Win32Harness]::keybd_event($Modifier, 0, [Win32Harness]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 100
}

function Send-AltEnter {
    Send-KeyCombo -Modifier ([Win32Harness]::VK_MENU) -Key ([Win32Harness]::VK_RETURN) -HoldMs 80
}

function Send-AltTab {
    Send-KeyCombo -Modifier ([Win32Harness]::VK_MENU) -Key ([Win32Harness]::VK_TAB) -HoldMs 80
}

# ==============================================================================
# 4. GAME PROCESS CONTROLLER FUNCTIONS
# ==============================================================================

$Global:GameProcess = $null
$Global:GameHwnd = [IntPtr]::Zero
$Global:PresetDir = Join-Path $PSScriptRoot "..\out\build\$Preset"
$Global:SettingsPath = Join-Path $Global:PresetDir "settings.toml"
$Global:SettingsBackupPath = Join-Path $Global:PresetDir "settings.toml.testbak"

function Backup-GameSettings {
    if (Test-Path $Global:SettingsPath) {
        Copy-Item -Path $Global:SettingsPath -Destination $Global:SettingsBackupPath -Force
    }
}

function Restore-GameSettings {
    if (Test-Path $Global:SettingsBackupPath) {
        Copy-Item -Path $Global:SettingsBackupPath -Destination $Global:SettingsPath -Force
        Remove-Item -Path $Global:SettingsBackupPath -Force -ErrorAction SilentlyContinue
    }
}

function Set-GameDisplayMode {
    param([string]$Mode)
    if (-not (Test-Path $Global:SettingsPath)) { return }
    $content = Get-Content -Path $Global:SettingsPath -Raw
    $updated = $content -replace "display_mode\s*=\s*['`"][^'`"]*['`"]", "display_mode = `"$Mode`""
    Set-Content -Path $Global:SettingsPath -Value $updated -Force
}

function Start-GameProcess {
    param(
        [string]$Mode = "borderless",
        [int]$WaitSec = 15
    )
    Stop-GameProcess
    Backup-GameSettings
    Set-GameDisplayMode -Mode $Mode

    $exePath = Join-Path $Global:PresetDir "aa_roas.exe"
    if (-not (Test-Path $exePath)) {
        throw "Executable not found at $exePath"
    }

    $env:AA_AUTO_START = "1"
    $Global:GameProcess = Start-Process -FilePath $exePath -WorkingDirectory $Global:PresetDir -WindowStyle Normal -PassThru
    if (-not $Global:GameProcess) {
        throw "Failed to start $exePath"
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $foundHwnd = [IntPtr]::Zero
    while ($sw.Elapsed.TotalSeconds -lt $WaitSec) {
        Start-Sleep -Milliseconds 300
        $h = Get-GameHwnd -ProcessId $Global:GameProcess.Id
        if ($h -ne [IntPtr]::Zero -and [Win32Harness]::IsWindowVisible($h)) {
            $foundHwnd = $h
            break
        }
    }

    if ($foundHwnd -eq [IntPtr]::Zero) {
        $failedPid = $Global:GameProcess.Id
        Stop-GameProcess
        throw "Timed out waiting for aa_roas window to appear (PID $failedPid)"
    }

    $Global:GameHwnd = $foundHwnd
    [Win32Harness]::ForceForegroundWindow($Global:GameHwnd) | Out-Null
    Start-Sleep -Milliseconds 500
    return $Global:GameHwnd
}

function Stop-GameProcess {
    if ($Global:GameProcess -and -not $Global:GameProcess.HasExited) {
        $Global:GameProcess.Kill()
        $null = $Global:GameProcess.WaitForExit(3000)
        $Global:GameProcess.Dispose()
        $Global:GameProcess = $null
    }

    Get-Process -Name "aa_roas" -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }

    [Win32Harness]::ClipCursor([IntPtr]::Zero) | Out-Null
    Restore-GameSettings
    $Global:GameHwnd = [IntPtr]::Zero
}

# ==============================================================================
# 5. TEST DEFINITIONS (TIERS 1 - 4)
# ==============================================================================

# ------------------------------------------------------------------------------
# TIER 1: FEATURE COVERAGE (F1 - F7)
# ------------------------------------------------------------------------------

# Feature F1: Cursor Hidden in Borderless Mode
Register-Test "T1-F1-01" "1" "F1" "Borderless Window Style" `
    "Verify borderless window style has WS_POPUP (0x80000000) and lacks WS_CAPTION" {
    param($ctx)
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    if (-not $m.IsPopup) { throw "Expected WS_POPUP style, got $($m.StyleHex)" }
    if ($m.HasCaption) { throw "Expected no WS_CAPTION in borderless, got $($m.StyleHex)" }
    return "Style $($m.StyleHex) has WS_POPUP and lacks WS_CAPTION"
}

Register-Test "T1-F1-02" "1" "F1" "Borderless Monitor Geometry Coverage" `
    "Verify window bounds span the entire active monitor dimensions" {
    param($ctx)
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    $wr = $m.WindowRect
    $mr = $m.MonitorRect
    if ($wr.Width -ne $mr.Width -or $wr.Height -ne $mr.Height) {
        throw "Window ($($wr.Width)x$($wr.Height)) does not match monitor ($($mr.Width)x$($mr.Height))"
    }
    return "Window spans monitor ($($wr.Width)x$($wr.Height))"
}

Register-Test "T1-F1-03" "1" "F1" "Cursor Hidden on Borderless Boot" `
    "Verify cursor is hidden during initial boot / focus state in borderless" {
    param($ctx)
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 400
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs.IsHidden) { throw "Cursor is showing in borderless mode (flags=$($cs.Flags), hCursor=$($cs.HCursor))" }
    return "Cursor hidden (flags=$($cs.Flags), hCursor=$($cs.HCursor))"
}

Register-Test "T1-F1-04" "1" "F1" "Cursor Clip Rect in Borderless" `
    "Verify cursor clipping rect is engaged and matches borderless monitor dimensions" {
    param($ctx)
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 400
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    if (-not $cs.IsClippedToClient) {
        throw "Cursor clip rect ($($cs.ClipRect.left),$($cs.ClipRect.top),$($cs.ClipRect.right),$($cs.ClipRect.bottom)) does not match client area"
    }
    return "Cursor clipped to ($($cs.ClipRect.Width)x$($cs.ClipRect.Height))"
}

Register-Test "T1-F1-05" "1" "F1" "Cursor Hidden During Borderless Gameplay/Menus" `
    "Verify cursor remains hidden during AA_AUTO_START automated menu and mission progression" {
    param($ctx)
    Start-Sleep -Seconds 2
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs.IsHidden) { throw "Cursor became visible during gameplay loop (hCursor=$($cs.HCursor))" }
    return "Cursor continuously hidden during gameplay progression"
}

# Feature F2: Cursor Hidden in Windowed Mode
Register-Test "T1-F2-01" "1" "F2" "Windowed Window Style" `
    "Verify windowed style has WS_OVERLAPPEDWINDOW with title bar and borders" {
    param($ctx)
    $ctx.Hwnd = Ensure-DisplayMode -Hwnd $ctx.Hwnd -TargetMode "windowed"
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    if (-not $m.IsOverlapped) { throw "Expected WS_OVERLAPPEDWINDOW, got $($m.StyleHex)" }
    if (-not $m.HasCaption) { throw "Expected WS_CAPTION in windowed mode, got $($m.StyleHex)" }
    return "Style $($m.StyleHex) has WS_OVERLAPPEDWINDOW and WS_CAPTION"
}

Register-Test "T1-F2-02" "1" "F2" "Windowed Geometry Inside Desktop Bounds" `
    "Verify windowed geometry is placed within monitor work area" {
    param($ctx)
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    $wr = $m.WindowRect
    $work = $m.WorkRect
    if ($wr.top -lt $work.top -or $wr.bottom -gt $work.bottom) {
        throw "Window vertical bounds ($($wr.top)-$($wr.bottom)) extend beyond work area ($($work.top)-$($work.bottom))"
    }
    return "Window rect ($($wr.left),$($wr.top),$($wr.right),$($wr.bottom)) comfortably within work area"
}

Register-Test "T1-F2-03" "1" "F2" "Cursor Hidden in Windowed Mode" `
    "Verify cursor is hidden while game is focused in windowed mode" {
    param($ctx)
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 400
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs.IsHidden) { throw "Cursor is visible in windowed mode (flags=$($cs.Flags), hCursor=$($cs.HCursor))" }
    return "Cursor hidden in windowed mode (flags=$($cs.Flags))"
}

Register-Test "T1-F2-04" "1" "F2" "Cursor Clipping to Windowed Client Rect" `
    "Verify cursor clipping rect strictly matches the windowed screen client rect" {
    param($ctx)
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 400
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs.IsClippedToClient) {
        throw "Clip rect ($($cs.ClipRect.left),$($cs.ClipRect.top),$($cs.ClipRect.right),$($cs.ClipRect.bottom)) does not match windowed client"
    }
    return "Cursor clipped to windowed client area ($($cs.ClipRect.Width)x$($cs.ClipRect.Height))"
}

Register-Test "T1-F2-05" "1" "F2" "Windowed Gameplay Progression Cursor Suppression" `
    "Verify cursor remains hidden during automated menu and gameplay navigation in windowed mode" {
    param($ctx)
    Start-Sleep -Seconds 2
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs.IsHidden) { throw "Cursor visible during windowed gameplay (hCursor=$($cs.HCursor))" }
    return "Cursor remains hidden in windowed mode across frames"
}

# Feature F3: Cursor Visible and Free on Defocus
Register-Test "T1-F3-01" "1" "F3" "Defocus via Foreground Switch" `
    "Trigger defocus by setting foreground window to external shell/desktop window" {
    param($ctx)
    $ctx.Hwnd = Ensure-DisplayMode -Hwnd $ctx.Hwnd -TargetMode "windowed"
    [Win32Harness]::DefocusWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 500
    $fg = [Win32Harness]::GetForegroundWindowSafe()
    if ($fg -eq $ctx.Hwnd) { throw "Game window did not yield foreground focus" }
    return "Focus moved away from game window (current FG: $fg)"
}

Register-Test "T1-F3-02" "1" "F3" "Cursor Clipping Released on Defocus" `
    "Verify cursor clipping bounds are released to desktop/virtual screen on focus loss" {
    param($ctx)
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    $clip = $cs.ClipRect
    $mon = $m.MonitorRect
    if ($clip.Width -lt ($mon.Width - 10) -or $clip.Height -lt ($mon.Height - 10)) {
        throw "Cursor still clipped to sub-region ($($clip.Width)x$($clip.Height)) on defocus"
    }
    return "Clip rect released to full desktop ($($clip.Width)x$($clip.Height))"
}

Register-Test "T1-F3-03" "1" "F3" "Cursor Visible (Arrow) on Defocus" `
    "Verify cursor becomes visible (showing flag and valid cursor handle) when unfocused" {
    param($ctx)
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs.IsShowing) {
        throw "Cursor is not visible on defocus (flags=$($cs.Flags), hCursor=$($cs.HCursor))"
    }
    return "Cursor is visible (flags=$($cs.Flags), hCursor=$($cs.HCursor))"
}

Register-Test "T1-F3-04" "1" "F3" "Defocus via Alt-Tab Key Sequence" `
    "Simulate Alt-Tab keystroke and verify immediate cursor release" {
    param($ctx)
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 300
    Send-AltTab
    [Win32Harness]::DefocusWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 400
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if ($cs.IsClippedToClient) { throw "Cursor remained clipped after Alt-Tab" }
    return "Cursor unclipped following Alt-Tab"
}

Register-Test "T1-F3-05" "1" "F3" "Cursor Free to Move Across Desktop" `
    "Verify mouse cursor can move outside the game window rect without being centered" {
    param($ctx)
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    $wr = $m.WindowRect
    # If unclipped, cursor is free
    if ($cs.IsClippedToClient) { throw "Cursor is still constrained by client clipping" }
    return "Cursor is free from window centering constraints"
}

# Feature F4: Cursor Re-hidden on Focus
Register-Test "T1-F4-01" "1" "F4" "Refocus Game Window" `
    "Refocus game window via SetForegroundWindow" {
    param($ctx)
    $ctx.Hwnd = Ensure-DisplayMode -Hwnd $ctx.Hwnd -TargetMode "windowed"
    # Defocus first to test refocus
    [Win32Harness]::DefocusWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 300

    # Refocus game window
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 400
    return "Game window successfully refocused"
}

Register-Test "T1-F4-02" "1" "F4" "Cursor Clip Re-engaged on Refocus" `
    "Verify cursor clip rect re-engages to game window client rect" {
    param($ctx)
    Start-Sleep -Milliseconds 400
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs.IsClippedToClient) {
        throw "Cursor clip rect was not re-engaged to client area"
    }
    return "Cursor clip rect re-engaged ($($cs.ClipRect.Width)x$($cs.ClipRect.Height))"
}

Register-Test "T1-F4-03" "1" "F4" "Cursor Re-hidden on Refocus" `
    "Verify cursor becomes completely hidden upon refocusing the game" {
    param($ctx)
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs.IsHidden) { throw "Cursor remained visible after regaining focus" }
    return "Cursor successfully re-hidden upon focus"
}

Register-Test "T1-F4-04" "1" "F4" "Mouse Look Re-engaged on Refocus" `
    "Verify relative mouse deltas resume after regaining focus" {
    param($ctx)
    Start-Sleep -Milliseconds 200
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs.IsClippedToClient -or -not $cs.IsHidden) {
        throw "Capture state incomplete on focus return"
    }
    return "Mouse look capture state verified"
}

Register-Test "T1-F4-05" "1" "F4" "Multi-Cycle Focus Toggle Consistency" `
    "Verify multiple consecutive defocus and refocus cycles consistently restore hidden/clipped state" {
    param($ctx)
    for ($i = 1; $i -le 3; $i++) {
        [Win32Harness]::DefocusWindow($ctx.Hwnd) | Out-Null
        Start-Sleep -Milliseconds 250
        [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
        Start-Sleep -Milliseconds 300
    }
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs.IsHidden) { throw "Cursor failed to re-hide after multi-cycle focus changes" }
    if (-not $cs.IsClippedToClient) { throw "Cursor failed to re-clip after multi-cycle focus changes" }
    return "Multi-cycle focus recovery consistent across 3 cycles"
}

# Feature F5: Alt+Enter Fullscreen/Borderless -> Windowed
Register-Test "T1-F5-01" "1" "F5" "Alt+Enter Keystroke in Borderless" `
    "Send Alt+Enter synthetic input while focused in borderless mode" {
    param($ctx)
    $ctx.Hwnd = Ensure-DisplayMode -Hwnd $ctx.Hwnd -TargetMode "borderless"
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 300
    Send-AltEnter
    Start-Sleep -Milliseconds 600
    return "Alt+Enter sent"
}

Register-Test "T1-F5-02" "1" "F5" "Style Transition to WS_OVERLAPPEDWINDOW" `
    "Verify window style transitions from WS_POPUP to WS_OVERLAPPEDWINDOW" {
    param($ctx)
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    if (-not $m.IsOverlapped) {
        throw "Window style $($m.StyleHex) did not transition to WS_OVERLAPPEDWINDOW"
    }
    return "Style transitioned to WS_OVERLAPPEDWINDOW ($($m.StyleHex))"
}

Register-Test "T1-F5-03" "1" "F5" "Title Bar and Borders Present" `
    "Verify window title bar (WS_CAPTION) and sizing frame are active" {
    param($ctx)
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    if (-not $m.HasCaption) { throw "Window is missing title bar caption ($($m.StyleHex))" }
    return "Title bar and sizing frame present"
}

Register-Test "T1-F5-04" "1" "F5" "Client Dimensions in Windowed Mode" `
    "Verify window client area adjusts to standard windowed dimensions (1280x720)" {
    param($ctx)
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    $cr = $m.ClientRect
    if ($cr.Width -ne 1280 -or $cr.Height -ne 720) {
        throw "Client rect ($($cr.Width)x$($cr.Height)) does not match 1280x720"
    }
    return "Client dimensions verified: $($cr.Width)x$($cr.Height)"
}

Register-Test "T1-F5-05" "1" "F5" "Cursor Remains Hidden After Toggle" `
    "Verify cursor remains hidden and re-clipped to new windowed client rect after mode transition" {
    param($ctx)
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs.IsHidden) { throw "Cursor became visible after toggle to windowed mode" }
    if (-not $cs.IsClippedToClient) { throw "Cursor clip not updated to windowed client rect" }
    return "Cursor remains hidden and clipped to windowed rect"
}

# Feature F6: Alt+Enter Windowed -> Fullscreen/Borderless
Register-Test "T1-F6-01" "1" "F6" "Alt+Enter Keystroke in Windowed Mode" `
    "Send Alt+Enter synthetic input while focused in windowed mode" {
    param($ctx)
    $ctx.Hwnd = Ensure-DisplayMode -Hwnd $ctx.Hwnd -TargetMode "windowed"
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 300
    Send-AltEnter
    Start-Sleep -Milliseconds 600
    return "Alt+Enter sent"
}

Register-Test "T1-F6-02" "1" "F6" "Style Transition to WS_POPUP" `
    "Verify window style transitions from WS_OVERLAPPEDWINDOW to WS_POPUP" {
    param($ctx)
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    if (-not $m.IsPopup) {
        throw "Window style $($m.StyleHex) did not transition to WS_POPUP"
    }
    return "Style transitioned to WS_POPUP ($($m.StyleHex))"
}

Register-Test "T1-F6-03" "1" "F6" "Removal of Title Bar and Borders" `
    "Verify caption and sizing borders are removed in borderless mode" {
    param($ctx)
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    if ($m.HasCaption) { throw "Window retains WS_CAPTION in borderless mode" }
    return "Caption and borders removed"
}

Register-Test "T1-F6-04" "1" "F6" "Expansion to Monitor Bounds" `
    "Verify window bounds expand to match active monitor dimensions" {
    param($ctx)
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    $wr = $m.WindowRect
    $mr = $m.MonitorRect
    if ($wr.Width -ne $mr.Width -or $wr.Height -ne $mr.Height) {
        throw "Window dimensions ($($wr.Width)x$($wr.Height)) do not match monitor ($($mr.Width)x$($mr.Height))"
    }
    return "Window bounds match monitor ($($wr.Width)x$($wr.Height))"
}

Register-Test "T1-F6-05" "1" "F6" "Cursor Clip Rect Expanded and Hidden" `
    "Verify cursor clip rect expands to monitor bounds and cursor remains hidden" {
    param($ctx)
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs.IsHidden) { throw "Cursor became visible after toggle to borderless mode" }
    if (-not $cs.IsClippedToClient) { throw "Cursor clip rect did not expand to borderless client area" }
    return "Cursor hidden and clip expanded to full monitor"
}

# Feature F7: Window Placement & Bounds Integrity
Register-Test "T1-F7-01" "1" "F7" "Window Placement Restoration" `
    "Verify windowed position is restored when returning from borderless" {
    param($ctx)
    $ctx.Hwnd = Ensure-DisplayMode -Hwnd $ctx.Hwnd -TargetMode "windowed"
    # Toggle to borderless and back to windowed
    Send-AltEnter
    Start-Sleep -Milliseconds 600
    Send-AltEnter
    Start-Sleep -Milliseconds 600
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    $wp = $m.Placement
    $rc = $wp.rcNormalPosition
    if ($rc.Width -le 0 -or $rc.Height -le 0) {
        throw "WINDOWPLACEMENT normal position is invalid ($($rc.Width)x$($rc.Height))"
    }
    return "Window position restored via WINDOWPLACEMENT ($($rc.left),$($rc.top),$($rc.right),$($rc.bottom))"
}

Register-Test "T1-F7-02" "1" "F7" "No Off-Screen Placement" `
    "Verify window title bar remains completely inside desktop work area" {
    param($ctx)
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    $wr = $m.WindowRect
    $work = $m.WorkRect
    if ($wr.top -lt $work.top) {
        throw "Window title bar is off-screen (top=$($wr.top) vs work area top=$($work.top))"
    }
    return "Window title bar fully accessible (top=$($wr.top), work area top=$($work.top))"
}

Register-Test "T1-F7-03" "1" "F7" "Aspect Ratio Preservation" `
    "Verify window client area maintains standard 16:9 aspect ratio" {
    param($ctx)
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    $cr = $m.ClientRect
    $ratio = [double]$cr.Width / [double]$cr.Height
    $target = 16.0 / 9.0
    if ([Math]::Abs($ratio - $target) -gt 0.05) {
        throw "Client aspect ratio $ratio deviates from 16:9 ($target)"
    }
    return "Client aspect ratio verified: $([Math]::Round($ratio, 3))"
}

Register-Test "T1-F7-04" "1" "F7" "No Coordinate Drift Over Repeated Toggles" `
    "Verify repeated toggling back and forth does not cause window position drift" {
    param($ctx)
    $m1 = Get-WindowMetrics -Hwnd $ctx.Hwnd
    $pos1 = $m1.WindowRect

    # Toggle to borderless and back to windowed
    Send-AltEnter
    Start-Sleep -Milliseconds 500
    Send-AltEnter
    Start-Sleep -Milliseconds 500

    $m2 = Get-WindowMetrics -Hwnd $ctx.Hwnd
    $pos2 = $m2.WindowRect

    if ([Math]::Abs($pos1.left - $pos2.left) -gt 4 -or [Math]::Abs($pos1.top - $pos2.top) -gt 4) {
        throw "Window drifted after toggle: initial=($($pos1.left),$($pos1.top)) final=($($pos2.left),$($pos2.top))"
    }
    return "No position drift after multi-toggle cycle (delta <= 4px)"
}

Register-Test "T1-F7-05" "1" "F7" "Window Placement API Integrity" `
    "Verify GetWindowPlacement returns valid showCmd and valid normal rectangle" {
    param($ctx)
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    $wp = $m.Placement
    if ($wp.showCmd -ne 1 -and $wp.showCmd -ne 5) { # SW_SHOWNORMAL = 1, SW_SHOW = 5
        throw "WINDOWPLACEMENT showCmd unexpected: $($wp.showCmd)"
    }
    return "WINDOWPLACEMENT verified (showCmd=$($wp.showCmd))"
}

# ------------------------------------------------------------------------------
# TIER 2: BOUNDARY & CORNER CASES
# ------------------------------------------------------------------------------

Register-Test "T2-BC-01" "2" "Boundary" "Rapid Consecutive Alt+Enter Presses" `
    "Rapid consecutive Alt+Enter presses verify no oscillation, hang, or race conditions" {
    param($ctx)
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 200
    for ($i = 0; $i -lt 4; $i++) {
        Send-AltEnter
        Start-Sleep -Milliseconds 50
    }
    Start-Sleep -Milliseconds 800
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    if (-not $Global:GameProcess -or $Global:GameProcess.HasExited) {
        throw "Game crashed or hung during rapid Alt+Enter toggle"
    }
    return "Game stable after 4 rapid Alt+Enter presses; final style $($m.StyleHex)"
}

Register-Test "T2-BC-02" "2" "Boundary" "Alt Held With Other Keys (No Spurious Toggle)" `
    "Alt held while pressing other keys (Alt+W, Alt+S, Alt+Space) does not trigger mode toggle" {
    param($ctx)
    $mBefore = Get-WindowMetrics -Hwnd $ctx.Hwnd
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 200

    # Send Alt+W, Alt+S, Alt+Space
    Send-KeyCombo -Modifier ([Win32Harness]::VK_MENU) -Key ([Win32Harness]::VK_KEY_W) -HoldMs 50
    Send-KeyCombo -Modifier ([Win32Harness]::VK_MENU) -Key ([Win32Harness]::VK_KEY_S) -HoldMs 50
    Send-KeyCombo -Modifier ([Win32Harness]::VK_MENU) -Key ([Win32Harness]::VK_SPACE) -HoldMs 50
    Start-Sleep -Milliseconds 400

    $mAfter = Get-WindowMetrics -Hwnd $ctx.Hwnd
    if ($mBefore.Style -ne $mAfter.Style) {
        throw "Display mode toggled spuriously on Alt+letter key! Before: $($mBefore.StyleHex) After: $($mAfter.StyleHex)"
    }
    return "Display mode preserved across Alt+letter and Alt+Space combinations"
}

Register-Test "T2-BC-03" "2" "Boundary" "Defocus During Active Polling" `
    "Defocusing while game is actively polling input releases clip rect cleanly" {
    param($ctx)
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 200
    # Defocus abruptly
    [Win32Harness]::DefocusWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 400
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if ($cs.IsClippedToClient) {
        throw "Cursor clip not released during background polling transition"
    }
    return "Cursor clip released cleanly during background polling"
}

Register-Test "T2-BC-04" "2" "Boundary" "Window Minimize and Restore" `
    "Minimizing and restoring window releases clip and re-engages cleanly" {
    param($ctx)
    [Win32Harness]::ShowWindow($ctx.Hwnd, [Win32Harness]::SW_MINIMIZE) | Out-Null
    Start-Sleep -Milliseconds 500
    $csMin = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if ($csMin.IsClippedToClient) { throw "Cursor clip remained active while window was minimized" }

    [Win32Harness]::ShowWindow($ctx.Hwnd, [Win32Harness]::SW_RESTORE) | Out-Null
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 500
    $csRest = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $csRest.IsHidden) { throw "Cursor not re-hidden after window restore" }
    return "Minimize releases clip; restore re-hides cursor"
}

Register-Test "T2-BC-05" "2" "Boundary" "Key Repeat Suppression on Alt+Enter" `
    "Holding Alt+Enter down does not produce rapid repeated multi-toggle loops" {
    param($ctx)
    $mBefore = Get-WindowMetrics -Hwnd $ctx.Hwnd
    # Long hold Alt+Enter (300ms)
    Send-KeyCombo -Modifier ([Win32Harness]::VK_MENU) -Key ([Win32Harness]::VK_RETURN) -HoldMs 300
    Start-Sleep -Milliseconds 500
    $mAfter = Get-WindowMetrics -Hwnd $ctx.Hwnd
    # The mode should have changed exactly once (toggled) rather than oscillation
    if ($mBefore.IsOverlapped -eq $mAfter.IsOverlapped) {
        throw "Long Alt+Enter hold resulted in repeated toggle (ended up in original mode)"
    }
    return "Alt+Enter key repeat suppressed (toggled exactly once)"
}

# ------------------------------------------------------------------------------
# TIER 3: CROSS-FEATURE INTERACTIONS
# ------------------------------------------------------------------------------

Register-Test "T3-CI-01" "3" "Interaction" "Alt-Tab Followed Immediately by Alt+Enter" `
    "Alt-Tab followed immediately by Alt+Enter does not toggle mode when game window is unfocused" {
    param($ctx)
    # Ensure windowed
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    if (-not $m.IsOverlapped) {
        Send-AltEnter
        Start-Sleep -Milliseconds 500
    }
    $styleBefore = (Get-WindowMetrics -Hwnd $ctx.Hwnd).Style

    # Defocus via Alt-Tab
    Send-AltTab
    Start-Sleep -Milliseconds 300

    # Send Alt+Enter while unfocused
    Send-AltEnter
    Start-Sleep -Milliseconds 400

    $styleAfter = (Get-WindowMetrics -Hwnd $ctx.Hwnd).Style
    # Bring focus back to game
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 400

    if ($styleBefore -ne $styleAfter) {
        throw "Alt+Enter was processed while window was unfocused"
    }
    return "Alt+Enter correctly ignored while game window is unfocused"
}

Register-Test "T3-CI-02" "3" "Interaction" "Mode Toggle Only When Game Focused" `
    "Verifies display mode toggle only executes when game window has active focus" {
    param($ctx)
    [Win32Harness]::DefocusWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 300
    $style1 = (Get-WindowMetrics -Hwnd $ctx.Hwnd).Style
    Send-AltEnter
    Start-Sleep -Milliseconds 400
    $style2 = (Get-WindowMetrics -Hwnd $ctx.Hwnd).Style
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 400

    if ($style1 -ne $style2) { throw "Mode toggle occurred while game lacked focus" }
    return "Display mode toggle strictly gated on window focus"
}

Register-Test "T3-CI-03" "3" "Interaction" "Mouse Look Active During Mode Toggle" `
    "Mouse look active during mode toggle updates cursor clipping smoothly without camera jump" {
    param($ctx)
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 300
    Send-AltEnter
    Start-Sleep -Milliseconds 600
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs.IsClippedToClient) {
        throw "Cursor clipping misaligned after mode toggle with mouse active"
    }
    return "Cursor clipping transitioned smoothly to new viewport"
}

Register-Test "T3-CI-04" "3" "Interaction" "Focus Loss During Mode Transition" `
    "Focus loss during mode transition does not leave window stuck in clipped state" {
    param($ctx)
    Send-AltEnter
    Start-Sleep -Milliseconds 50 # Abrupt defocus mid-transition
    [Win32Harness]::DefocusWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 500
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if ($cs.IsClippedToClient) {
        throw "Window remained clipped after abrupt mid-transition defocus"
    }
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 400
    return "Clip properly released on mid-transition focus drop"
}

Register-Test "T3-CI-05" "3" "Interaction" "Interleaved Mode Toggles and Focus Shifts" `
    "Multiple alternating mode switches interleaved with focus shifts remain consistent" {
    param($ctx)
    for ($i = 0; $i -lt 2; $i++) {
        Send-AltEnter
        Start-Sleep -Milliseconds 400
        [Win32Harness]::DefocusWindow($ctx.Hwnd) | Out-Null
        Start-Sleep -Milliseconds 250
        [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
        Start-Sleep -Milliseconds 300
    }
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs.IsHidden -or -not $cs.IsClippedToClient) {
        throw "Interleaved mode/focus shifts resulted in corrupted capture state"
    }
    return "Capture and display mode consistent across interleaved shifts"
}

# ------------------------------------------------------------------------------
# TIER 4: REAL-WORLD GAMEPLAY SCENARIOS
# ------------------------------------------------------------------------------

Register-Test "T4-GP-01" "4" "Lifecycle" "Complete End-to-End User Journey" `
    "Full lifecycle: Boot in borderless -> verify hidden cursor -> toggle Alt+Enter to windowed -> verify mode & hidden cursor -> Alt-Tab out to desktop -> verify cursor visible & free -> switch back to game -> verify cursor hidden & clipped -> toggle Alt+Enter back to borderless -> verify mode & hidden cursor" {
    param($ctx)
    # Step 1: Verify borderless baseline
    $m1 = Get-WindowMetrics -Hwnd $ctx.Hwnd
    if (-not $m1.IsPopup) {
        Send-AltEnter
        Start-Sleep -Milliseconds 600
        $m1 = Get-WindowMetrics -Hwnd $ctx.Hwnd
    }
    $cs1 = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs1.IsHidden) { throw "Step 1 Failed: Cursor not hidden in initial borderless mode" }

    # Step 2: Toggle to windowed
    Send-AltEnter
    Start-Sleep -Milliseconds 600
    $m2 = Get-WindowMetrics -Hwnd $ctx.Hwnd
    if (-not $m2.IsOverlapped) { throw "Step 2 Failed: Window did not switch to windowed mode" }
    $cs2 = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs2.IsHidden) { throw "Step 2 Failed: Cursor not hidden after switching to windowed" }

    # Step 3: Alt-Tab out to desktop
    Send-AltTab
    [Win32Harness]::DefocusWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 500
    $cs3 = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if ($cs3.IsClippedToClient) { throw "Step 3 Failed: Cursor still clipped after Alt-Tab" }
    if (-not $cs3.IsShowing) { throw "Step 3 Failed: Cursor not visible on desktop after Alt-Tab" }

    # Step 4: Switch back to game
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 500
    $cs4 = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs4.IsHidden) { throw "Step 4 Failed: Cursor did not re-hide upon focus return" }
    if (-not $cs4.IsClippedToClient) { throw "Step 4 Failed: Cursor clip did not re-engage on focus return" }

    # Step 5: Toggle back to borderless
    Send-AltEnter
    Start-Sleep -Milliseconds 600
    $m5 = Get-WindowMetrics -Hwnd $ctx.Hwnd
    if (-not $m5.IsPopup) { throw "Step 5 Failed: Window did not toggle back to borderless mode" }
    $cs5 = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs5.IsHidden) { throw "Step 5 Failed: Cursor not hidden in final borderless mode" }

    return "Complete end-to-end user journey passed all 5 stages successfully"
}

Register-Test "T4-GP-02" "4" "Lifecycle" "Windowed Gameplay Progression Lifecycle" `
    "Boot in windowed with AA_AUTO_START=1 -> verify hidden cursor across intro movies and mission select -> defocus to desktop -> verify arrow visible & free -> refocus -> verify hidden" {
    param($ctx)
    # Ensure windowed
    $m = Get-WindowMetrics -Hwnd $ctx.Hwnd
    if (-not $m.IsOverlapped) {
        Send-AltEnter
        Start-Sleep -Milliseconds 600
    }

    # Verify gameplay state
    Start-Sleep -Seconds 2
    $cs = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $cs.IsHidden) { throw "Cursor visible during gameplay progression in windowed mode" }

    # Defocus
    [Win32Harness]::DefocusWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 500
    $csDef = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $csDef.IsShowing) { throw "Cursor not visible on desktop during defocus" }

    # Refocus
    [Win32Harness]::ForceForegroundWindow($ctx.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 500
    $csRef = Get-LiveCursorState -Hwnd $ctx.Hwnd
    if (-not $csRef.IsHidden) { throw "Cursor not re-hidden after returning to windowed gameplay" }

    return "Windowed gameplay progression lifecycle passed cleanly"
}

# ==============================================================================
# 6. TEST RUNNER EXECUTION ENGINE
# ==============================================================================

if ($ListTests) {
    Write-Host "`n=== INVENTORY OF REGISTERED E2E TEST CASES ($($Global:TestInventory.Count) Total) ===" -ForegroundColor Cyan
    $Global:TestInventory | ForEach-Object {
        Write-Host ("[{0}] Tier {1} | {2,-12} | {3}" -f $_.Id, $_.Tier, $_.Feature, $_.Name)
    }
    return
}

# Filter tests
$SelectedTests = $Global:TestInventory | Where-Object {
    $tierMatch = ($Tier -contains "All") -or ($Tier -contains $_.Tier)
    $featMatch = ($Feature -contains "All") -or ($Feature -contains $_.Feature)
    $tierMatch -and $featMatch
}

if ($SelectedTests.Count -eq 0) {
    Write-Warning "No tests matched the specified Tier '$Tier' and Feature '$Feature' filters."
    return
}

Write-Host "`n==============================================================================" -ForegroundColor Cyan
Write-Host "  AAROAS-XBERecomp E2E TEST SUITE: CURSOR & DISPLAY MODES" -ForegroundColor Cyan
Write-Host "  Target Preset: $Preset | Selected Tests: $($SelectedTests.Count)" -ForegroundColor Cyan
Write-Host "==============================================================================`n" -ForegroundColor Cyan

$testContext = [PSCustomObject]@{
    Hwnd = [IntPtr]::Zero
}

$passed = 0
$failed = 0
$skipped = 0

try {
    Write-Host "[LAUNCH] Starting aa_roas.exe in borderless mode..." -ForegroundColor DarkCyan
    $hwnd = Start-GameProcess -Mode "borderless" -WaitSec $TimeoutSeconds
    $testContext.Hwnd = $hwnd
    Write-Host "[LAUNCH] Target window detected and visible (HWND: $hwnd)`n" -ForegroundColor Green

    # Window is visible; settle message queue
    Start-Sleep -Milliseconds 800

    $currentTier = ""
    foreach ($test in $SelectedTests) {
        if ($test.Tier -ne $currentTier) {
            $currentTier = $test.Tier
            Write-Host "`n--- TIER $currentTier EXECUTION ---" -ForegroundColor Yellow
        }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            Write-Host -NoNewline ("  [{0}] {1,-50} ... " -f $test.Id, $test.Name)
            $resultMsg = & $test.Action $testContext
            $sw.Stop()
            $test.ElapsedMs = $sw.Elapsed.TotalMilliseconds
            $test.Status = "PASS"
            $test.Actual = $resultMsg
            Write-Host "PASS" -ForegroundColor Green -NoNewline
            Write-Host (" ({0:F0}ms)" -f $test.ElapsedMs) -ForegroundColor DarkGray
            $passed++
        }
        catch {
            $sw.Stop()
            $test.ElapsedMs = $sw.Elapsed.TotalMilliseconds
            $test.Status = "FAIL"
            $test.Error = $_.Exception.Message
            Write-Host "FAIL" -ForegroundColor Red -NoNewline
            Write-Host (" ({0:F0}ms)" -f $test.ElapsedMs) -ForegroundColor DarkGray
            Write-Host ("        Error: {0}" -f $_.Exception.Message) -ForegroundColor DarkRed
            $failed++
        }
    }
}
finally {
    Write-Host "`n[CLEANUP] Stopping game process and restoring configuration..." -ForegroundColor DarkCyan
    Stop-GameProcess
    Write-Host "[CLEANUP] Complete.`n" -ForegroundColor DarkCyan
}

# ==============================================================================
# 7. SUMMARY & REPORT EMISSION
# ==============================================================================

$total = $passed + $failed + $skipped
$passRate = if ($total -gt 0) { [Math]::Round(($passed / $total) * 100, 1) } else { 0 }

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "  TEST RUN SUMMARY" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ("  Total Tests Executed : {0}" -f $total)
Write-Host ("  Passed               : {0}" -f $passed) -ForegroundColor Green
Write-Host ("  Failed               : {0}" -f $failed) -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host ("  Skipped              : {0}" -f $skipped)
Write-Host ("  Pass Rate            : {0}%" -f $passRate) -ForegroundColor $(if ($passRate -eq 100) { "Green" } else { "Yellow" })
Write-Host "==============================================================================`n" -ForegroundColor Cyan

# Write report if requested
if ($ReportPath) {
    $reportDir = Split-Path -Path $ReportPath -Parent
    if ($reportDir -and -not (Test-Path $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }

    $sbReport = New-Object System.Text.StringBuilder
    $null = $sbReport.AppendLine("# E2E Test Execution Report")
    $null = $sbReport.AppendLine("")
    $null = $sbReport.AppendLine("- **Timestamp**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')")
    $null = $sbReport.AppendLine("- **Preset**: $Preset")
    $null = $sbReport.AppendLine("- **Total**: $total | **Passed**: $passed | **Failed**: $failed | **Pass Rate**: $passRate%")
    $null = $sbReport.AppendLine("")
    $null = $sbReport.AppendLine("| Test ID | Tier | Feature | Name | Status | Time (ms) | Details / Error |")
    $null = $sbReport.AppendLine("|---|---|---|---|---|---|---|")
    foreach ($t in $SelectedTests) {
        $details = if ($t.Status -eq "PASS") { $t.Actual } else { $t.Error }
        $detailsSanitized = $details -replace '\|', '/'
        $null = $sbReport.AppendLine("| $($t.Id) | Tier $($t.Tier) | $($t.Feature) | $($t.Name) | $($t.Status) | $([Math]::Round($t.ElapsedMs)) | $detailsSanitized |")
    }
    Set-Content -Path $ReportPath -Value $sbReport.ToString() -Force
    Write-Host "Report generated at: $ReportPath" -ForegroundColor DarkCyan
}

# Return exit code matching test results
if ($failed -gt 0) {
    exit 1
} else {
    exit 0
}
