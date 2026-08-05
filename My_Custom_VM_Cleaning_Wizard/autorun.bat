@echo off
chcp 65001 >nul
TITLE VM Space Wizard - Master Launcher (Windows Host)

:: ============================================================================
:: AUTOMATED ADMINISTRATOR ELEVATION BLOCK
:: ============================================================================
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrative Privileges for VDI Compaction...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Lock working directory to the folder where autorun.bat resides
cd /d "%~dp0"
cls

echo ====================================================================
echo          [WIZARD] VM SPACE WIZARD - MASTER LAUNCHER (WINDOWS)
echo ====================================================================
echo.
echo Which stage of the cleanup process are you currently executing?
echo.
echo   [1] Stage 1: Linux System Cleanup
echo   [2] Stage 2: Windows Host VDI / VMDK Compaction (RUN HERE)
echo   [3] Exit
echo ====================================================================
set /p CHOICE="Select option [1-3]: "

if "%CHOICE%"=="1" (
    cls
    echo ====================================================================
    echo  [!] NOTICE: STAGE 1 MUST BE EXECUTED INSIDE YOUR LINUX VM
    echo ====================================================================
    echo  To clean Linux caches, Docker volumes, and zero-fill free space:
    echo.
    echo    1. Boot up your Linux Virtual Machine.
    echo    2. Open a terminal inside Linux.
    echo    3. Run: ./autorun.sh
    echo.
    echo  Once Linux cleanup finishes and the VM shuts down, return here!
    echo ====================================================================
    pause
    goto end
)

if "%CHOICE%"=="2" (
    cls
    echo [i] Launching PowerShell Compaction Module...
    echo.
    
    if exist "%~dp0vm-space-wizard.ps1" (
        powershell.exe -NoExit -ExecutionPolicy Bypass -File "%~dp0vm-space-wizard.ps1"
    ) else (
        echo.
        echo [!] ERROR: Could not find 'vm-space-wizard.ps1' in this directory!
        echo [!] Please ensure 'autorun.bat' and 'vm-space-wizard.ps1' are in the same folder.
        pause
    )
    goto end
)

if "%CHOICE%"=="3" (
    exit
)

:end
