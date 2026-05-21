@echo off
REM Zellij Agent Pane - Windows Unified Uninstall Script
REM Attempts bash first, falls back to PowerShell

setlocal enabledelayedexpansion

REM Check if bash is available
bash --version >nul 2>&1
if %errorlevel% equ 0 (
    echo [uninstall.bat] bash detected, using uninstall.sh
    bash uninstall.sh %*
    exit /b %errorlevel%
)

REM No bash, use PowerShell
echo [uninstall.bat] bash not found, using uninstall.ps1
powershell -ExecutionPolicy Bypass -File uninstall.ps1 %*
exit /b %errorlevel%
