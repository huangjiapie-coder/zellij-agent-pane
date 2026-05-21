@echo off
REM Zellij Agent Pane - Windows Unified Deploy Script
REM Attempts bash first, falls back to PowerShell

setlocal enabledelayedexpansion

REM Check if bash is available
bash --version >nul 2>&1
if %errorlevel% equ 0 (
    echo [deploy.bat] bash detected, using deploy.sh
    bash deploy.sh %*
    exit /b %errorlevel%
)

REM No bash, use PowerShell
echo [deploy.bat] bash not found, using deploy.ps1
powershell -ExecutionPolicy Bypass -File deploy.ps1 %*
exit /b %errorlevel%
