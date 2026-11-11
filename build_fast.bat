@echo off
set "PF86=%ProgramFiles(x86)%"
for /f "usebackq tokens=*" %%i in (`"%PF86%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
call "%VSDIR%\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64 >nul
set "VSCMAKE=%VSDIR%\Common7\IDE\CommonExtensions\Microsoft\CMake"
set "PATH=C:\Program Files\LLVM\bin;%VSCMAKE%\CMake\bin;%VSCMAKE%\Ninja;%VSDIR%\VC\Tools\Llvm\x64\bin;%PATH%"
if not exist out\build\release\CMakeFiles\rules.ninja (
    cmake --preset release
)
if "%~1"=="" (
    ninja -C out\build\release aa_roas.exe aa_roas.dll
    powershell -NoProfile -Command "if (Test-Path out\build\release\aa_roas.dll) { (Get-Item out\build\release\aa_roas.dll).LastWriteTime = (Get-Date) }"
) else (
    ninja -C out\build\release %*
    powershell -NoProfile -Command "if (Test-Path out\build\release\aa_roas.dll) { (Get-Item out\build\release\aa_roas.dll).LastWriteTime = (Get-Date) }"
)
