@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "TAG="
set "TITLE="
set "DRY_RUN=0"
set "INTERACTIVE=0"

:parse_args
if "%~1"=="" goto :args_done
if /i "%~1"=="--dry-run" (
    set "DRY_RUN=1"
    shift
    goto :parse_args
)
if /i "%~1"=="-h" goto :help
if /i "%~1"=="--help" goto :help
if not defined TAG (
    set "TAG=%~1"
    shift
    goto :parse_args
)
if not defined TITLE (
    set "TITLE=%~1"
    shift
    goto :parse_args
)
echo Error: Unexpected argument "%~1".
goto :usage_err

:args_done
set "GH_EXE=gh"
where gh >nul 2>nul
if errorlevel 1 (
    if exist "%ProgramFiles%\GitHub CLI\gh.exe" (
        set "GH_EXE=%ProgramFiles%\GitHub CLI\gh.exe"
    ) else if exist "%ProgramFiles(x86)%\GitHub CLI\gh.exe" (
        set "GH_EXE=%ProgramFiles(x86)%\GitHub CLI\gh.exe"
    ) else (
        echo GitHub CLI ^(gh^) not found. Install with: winget install --id GitHub.cli -e
        goto :fail
    )
)

"%GH_EXE%" auth status >nul 2>nul
if errorlevel 1 (
    echo GitHub CLI is not signed in. Run: "%GH_EXE%" auth login
    goto :fail
)

if defined TAG goto :tag_ready
set "INTERACTIVE=1"
echo.
echo Recent GitHub releases:
"%GH_EXE%" release list --limit 5
echo.
set /p "TAG=Enter release tag (e.g. v1.0.0.1): "
if not defined TAG (
    echo Error: Release tag is required.
    goto :fail
)
set /p "TITLE=Enter release title (leave blank to use tag): "

:tag_ready
if not defined TITLE set "TITLE=%TAG%"

rem Require clean tracked files so tagged binaries match committed source.
git diff-index --quiet HEAD --
if errorlevel 1 (
    echo Error: Working tree has uncommitted changes to tracked files.
    echo Commit or stash changes before publishing a release.
    goto :fail
)

set "BRANCH="
for /f "delims=" %%b in ('git symbolic-ref --short HEAD 2^>nul') do set "BRANCH=%%b"
set "HEAD_SHA="
for /f "delims=" %%h in ('git rev-parse HEAD') do set "HEAD_SHA=%%h"
if not defined HEAD_SHA (
    echo Error: Could not resolve HEAD commit.
    goto :fail
)

echo [1/3] Building release binaries...
if not exist config\game.toml (
    cmd /c "set CI=1&& call build.bat" || goto :fail
) else (
    call build_fast.bat || goto :fail
)

echo [2/3] Packaging aa_roas.zip...
call release.bat || goto :fail
if not exist aa_roas.zip (
    echo Error: release.bat did not produce aa_roas.zip.
    goto :fail
)

echo [3/3] Checking GitHub release "%TAG%"...
"%GH_EXE%" release view "%TAG%" >nul 2>nul
if not errorlevel 1 goto :upload_existing

if "%DRY_RUN%"=="1" (
    echo [dry-run] Release "%TAG%" does not exist yet.
    if defined BRANCH echo [dry-run] Would run: git push origin "%BRANCH%"
    echo [dry-run] Would run: "%GH_EXE%" release create "%TAG%" aa_roas.zip --target "%HEAD_SHA%" --title "%TITLE%" --generate-notes
    goto :done
)

if defined BRANCH (
    echo Pushing "%BRANCH%" to origin...
    git push origin "%BRANCH%" || goto :fail
)
echo Creating release "%TAG%" and uploading aa_roas.zip to Assets...
"%GH_EXE%" release create "%TAG%" aa_roas.zip --target "%HEAD_SHA%" --title "%TITLE%" --generate-notes || goto :fail
goto :done

:upload_existing
if "%DRY_RUN%"=="1" (
    echo [dry-run] Release "%TAG%" already exists on GitHub.
    echo [dry-run] Would run: "%GH_EXE%" release upload "%TAG%" aa_roas.zip --clobber
    goto :done
)

echo Release "%TAG%" already exists: uploading aa_roas.zip to Assets ^(--clobber^)...
"%GH_EXE%" release upload "%TAG%" aa_roas.zip --clobber || goto :fail

:done
echo.
echo Done: aa_roas.zip handled for release "%TAG%".
if "%INTERACTIVE%"=="1" pause
exit /b 0

:help
set "HELP_EXIT=0"
goto :usage_print

:usage_err
set "HELP_EXIT=1"

:usage_print
echo Usage: publish_release.bat ^<tag^> [title] [--dry-run]
echo Examples:
echo   publish_release.bat v1.0.0.1
echo   publish_release.bat v1.0.0.1 "v1.0.0.1 - Mouse & Alt-Tab Fixes"
echo   publish_release.bat v1.0.0.1 --dry-run
exit /b %HELP_EXIT%

:fail
if "%INTERACTIVE%"=="1" pause
exit /b 1
