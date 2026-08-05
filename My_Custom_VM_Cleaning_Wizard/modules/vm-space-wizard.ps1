# ==============================================================================
# TOOL NAME:    vm-space-wizard.ps1 (V2.1 Universal Master Entry)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Cross-Platform Host Compaction for VirtualBox and VMware.
# ==============================================================================

# Lock execution context to the directory where this script actually lives
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

# --- Load Engine Modules (Located in the same directory as this script) ---
$VBoxModule = Join-Path -Path $ScriptDir -ChildPath "virtualbox-engine.ps1"
$VMwareModule = Join-Path -Path $ScriptDir -ChildPath "vmware-engine.ps1"

if (Test-Path -Path $VBoxModule) {
    . $VBoxModule
} else {
    # Fallback check if script is executed from parent root
    $VBoxModule = Join-Path -Path $ScriptDir -ChildPath "modules\virtualbox-engine.ps1"
    if (Test-Path -Path $VBoxModule) { . $VBoxModule }
    else { Write-Host "[!] Error: Could not locate virtualbox-engine.ps1" -ForegroundColor Red }
}

if (Test-Path -Path $VMwareModule) {
    . $VMwareModule
} else {
    # Fallback check if script is executed from parent root
    $VMwareModule = Join-Path -Path $ScriptDir -ChildPath "modules\vmware-engine.ps1"
    if (Test-Path -Path $VMwareModule) { . $VMwareModule }
    else { Write-Host "[!] Error: Could not locate vmware-engine.ps1" -ForegroundColor Red }
}

function Show-Header {
    Clear-Host
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "  [WIZARD] VM SPACE WIZARD V2.1 - UNIVERSAL HYPERVISOR COMPACTOR    " -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
}

function Pause-Console {
    Write-Host ""
    Read-Host "Press [ENTER] to return to the menu..."
}

# --- Main Hypervisor Selection Menu ---
while ($true) {
    Show-Header
    Write-Host "Select your virtualization platform:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] Oracle VirtualBox (.vdi)"
    Write-Host "  [2] VMware Workstation / Player (.vmdk)"
    Write-Host "  [3] Exit"
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Cyan

    $platformChoice = Read-Host "Enter choice [1-3]"

    if ($platformChoice -eq "1") {
        # VirtualBox Sub-Menu
        while ($true) {
            Show-Header
            Write-Host "--- ORACLE VIRTUALBOX ENGINE ---" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  [1] Compact Registered VDI Disks and Active Snapshot Chains"
            Write-Host "  [2] Audit and Clean Orphaned / Corrupted Snapshot Files"
            Write-Host "  [3] Run Full Maintenance (Audit + Compact All)"
            Write-Host "  [4] Back to Platform Selection"
            Write-Host ""
            Write-Host "====================================================================" -ForegroundColor Cyan

            $vboxChoice = Read-Host "Enter choice [1-4]"

            if ($vboxChoice -eq "1") {
                if (Get-Command Compact-VBoxDisks -ErrorAction SilentlyContinue) {
                    Compact-VBoxDisks
                } else {
                    Write-Host "[!] Function 'Compact-VBoxDisks' is not loaded. Verify virtualbox-engine.ps1 exists!" -ForegroundColor Red
                }
                Pause-Console
            }
            elseif ($vboxChoice -eq "2") {
                if (Get-Command Audit-OrphanedSnapshotsVBox -ErrorAction SilentlyContinue) {
                    Audit-OrphanedSnapshotsVBox
                } else {
                    Write-Host "[!] Function 'Audit-OrphanedSnapshotsVBox' is not loaded!" -ForegroundColor Red
                }
                Pause-Console
            }
            elseif ($vboxChoice -eq "3") {
                if (Get-Command Compact-VBoxDisks -ErrorAction SilentlyContinue) {
                    Audit-OrphanedSnapshotsVBox
                    Compact-VBoxDisks
                } else {
                    Write-Host "[!] VirtualBox functions are not loaded!" -ForegroundColor Red
                }
                Pause-Console
            }
            elseif ($vboxChoice -eq "4") {
                break
            }
            else {
                Write-Host "Invalid choice!" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
    elseif ($platformChoice -eq "2") {
        # VMware Sub-Menu
        while ($true) {
            Show-Header
            Write-Host "--- VMWARE ENGINE ---" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  [1] Shrink Virtual Machine Disks (.vmdk)"
            Write-Host "  [2] Back to Platform Selection"
            Write-Host ""
            Write-Host "====================================================================" -ForegroundColor Cyan

            $vmwareChoice = Read-Host "Enter choice [1-2]"

            if ($vmwareChoice -eq "1") {
                if (Get-Command Shrink-VMwareDisks -ErrorAction SilentlyContinue) {
                    Shrink-VMwareDisks
                } else {
                    Write-Host "[!] Function 'Shrink-VMwareDisks' is not loaded. Verify vmware-engine.ps1 exists!" -ForegroundColor Red
                }
                Pause-Console
            }
            elseif ($vmwareChoice -eq "2") {
                break
            }
            else {
                Write-Host "Invalid choice!" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
    elseif ($platformChoice -eq "3") {
        Write-Host "Goodbye!" -ForegroundColor Green
        break
    }
    else {
        Write-Host "Invalid choice!" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
}
