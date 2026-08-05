@echo off
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

:: Lock directory to Desktop folder where autorun.bat sits
cd /d "%~dp0"
cls

echo ====================================================================
echo          🧙‍♂️ VM SPACE WIZARD - MASTER LAUNCHER (WINDOWS)
echo ====================================================================
echo.
echo Which stage of the cleanup process are you currently executing?
echo.
echo   [1] Stage 1: Linux System Cleanup & Storage Offloading
echo   [2] Stage 2: Windows Host VDI Compaction (RUN HERE)
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
    echo ====================================================================
    echo                   [!] STAGE 2 PREREQUISITE CHECK
    echo ====================================================================
    echo  Have you already completed Stage 1 inside your Linux VM?
    echo  (Cleaning system caches + running the Zero-Fill step)
    echo.
    echo  [Y] Yes - Stage 1 is complete and Linux VM is shut down.
    echo  [N] No  - I need to run Stage 1 inside Linux first.
    echo ====================================================================
    set /p CONFIRM="Have you completed Stage 1? (Y/N): "
    
    if /I "%CONFIRM%"=="Y" (
        cls
        echo [i] Launching PowerShell Compaction Module...
        echo.
        
        if exist "%~dp0vm-space-wizard.ps1" (
            :: Execute PowerShell interactively inside the current CMD window
            powershell.exe -NoExit -ExecutionPolicy Bypass -Command "& '%~dp0vm-space-wizard.ps1'"
        ) else (
            echo.
            echo [!] ERROR: Could not find 'vm-space-wizard.ps1' on your Desktop!
            echo [!] Please make sure both 'autorun.bat' and 'vm-space-wizard.ps1' are in the same Desktop folder.
            echo.
            pause
        )
    ) else (
        echo.
        echo [!] Please start your Linux VM, run Stage 1 first, then return here.
        pause
    )
    goto end
)

if "%CHOICE%"=="3" (
    exit
)

:end
