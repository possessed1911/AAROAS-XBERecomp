@echo off
set "GAME_EXE=aa_roas"
cd /d "%~dp0"
set "OUT=out\build\release"
rem the Visual C++ runtime beside the executable, so a fresh Windows install needs nothing more
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -property installationPath`) do set "VSDIR=%%i"
for /d %%v in ("%VSDIR%\VC\Redist\MSVC\1*") do for /d %%c in ("%%v\x64\Microsoft.VC*.CRT") do set "VCRUNTIME=%%c"
if not exist "%VCRUNTIME%\vcruntime140.dll" (echo Visual C++ runtime not found: install Visual Studio with the C++ workload & exit /b 1)
if not exist "%OUT%\%GAME_EXE%.exe" call build.bat || exit /b 1
if not exist "%OUT%\%GAME_EXE%.dll" call build.bat || exit /b 1
rem the configure step writes where the SDK is
if not exist "%OUT%\sdk_dir.txt" cmake --preset release >nul || exit /b 1
if not exist "%OUT%\sdk_dir.txt" echo %OUT%\sdk_dir.txt was not written, update the SDK. && exit /b 1
set /p SDK=<out\build\release\sdk_dir.txt
del /q "%GAME_EXE%.zip" 2>nul
rem an empty assets folder beside the exe, where the game (files or .iso) goes
rd /s /q "%OUT%\release" 2>nul
mkdir "%OUT%\release\assets"
rem ship the precompiled game DLL beside the exe (ensure its timestamp beats the exe across 2s zip granularity)
powershell -NoProfile -Command "$exe = Get-Item '%OUT%\%GAME_EXE%.exe'; $dll = Get-Item '%OUT%\%GAME_EXE%.dll'; $min = $exe.LastWriteTimeUtc.AddSeconds(4); if ($dll.LastWriteTimeUtc -lt $min) { $now = (Get-Date).ToUniversalTime(); $dll.LastWriteTimeUtc = if ($now -gt $min) { $now } else { $min } }" || exit /b 1
set "SEVENZ=7z"
where 7z >nul 2>nul || (
    if exist "%ProgramFiles%\7-Zip\7z.exe" (
        set "SEVENZ=%ProgramFiles%\7-Zip\7z.exe"
    ) else if exist "%ProgramFiles(x86)%\7-Zip\7z.exe" (
        set "SEVENZ=%ProgramFiles(x86)%\7-Zip\7z.exe"
    ) else (
        echo 7-Zip not found: install 7-Zip or add 7z.exe to PATH & exit /b 1
    )
)
set "SPLASH_ARG="
if exist splash.png set "SPLASH_ARG=.\splash.png"
"%SEVENZ%" a "%GAME_EXE%.zip" ".\%OUT%\%GAME_EXE%.exe" ".\%OUT%\%GAME_EXE%.dll" ".\%OUT%\release\assets" %SPLASH_ARG% .\README.md "%SDK%\THIRD_PARTY.txt" "%VCRUNTIME%\msvcp140.dll" "%VCRUNTIME%\vcruntime140.dll" "%VCRUNTIME%\vcruntime140_1.dll"
