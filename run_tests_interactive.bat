@echo off
setlocal
cd /d "%~dp0"
title AAROAS-XBERecomp - Manual E2E Tests

echo ==============================================================================
echo   AAROAS-XBERecomp Manual E2E Test Launcher
echo ==============================================================================
echo.
echo Launching tests in an interactive visible console window so the game
echo window can take real OS foreground focus...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\test_e2e_cursor_display.ps1" %*

echo.
echo Tests completed. Press any key to exit.
pause >nul
