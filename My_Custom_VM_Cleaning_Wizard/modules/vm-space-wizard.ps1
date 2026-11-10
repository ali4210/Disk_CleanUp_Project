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
$DockerDesktopModule = Join-Path -Path $ScriptDir -ChildPath "docker-desktop-engine.ps1"

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

if (Test-Path -Path $DockerDesktopModule) {
    . $DockerDesktopModule
} else {
    $DockerDesktopModule = Join-Path -Path $ScriptDir -ChildPath "modules\docker-desktop-engine.ps1"
    if (Test-Path -Path $DockerDesktopModule) { . $DockerDesktopModule }
    else { Write-Host "[!] Error: Could not locate docker-desktop-engine.ps1" -ForegroundColor Red }
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
    Write-Host "  [3] Docker Desktop / Podman on Windows (WSL2 data relocation)"
    Write-Host "  [0] Exit"
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Cyan

    $platformChoice = Read-Host "Enter choice [0-3]"

    if ($platformChoice -eq "1") {
        # VirtualBox Sub-Menu
        while ($true) {
            Show-Header
            Write-Host "--- ORACLE VIRTUALBOX ENGINE ---" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  [1] Compact Registered VDI Disks and Active Snapshot Chains"
            Write-Host "  [2] Audit and Clean Orphaned / Corrupted Snapshot Files"
            Write-Host "  [3] Run Full Maintenance (Audit + Compact All)"
            Write-Host "  [0] Back to Platform Selection"
            Write-Host ""
            Write-Host "====================================================================" -ForegroundColor Cyan

            $vboxChoice = Read-Host "Enter choice [0-3]"

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
            elseif ($vboxChoice -eq "0") {
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
            Write-Host "  [0] Back to Platform Selection"
            Write-Host ""
            Write-Host "====================================================================" -ForegroundColor Cyan

            $vmwareChoice = Read-Host "Enter choice [0-1]"

            if ($vmwareChoice -eq "1") {
                if (Get-Command Shrink-VMwareDisks -ErrorAction SilentlyContinue) {
                    Shrink-VMwareDisks
                } else {
                    Write-Host "[!] Function 'Shrink-VMwareDisks' is not loaded. Verify vmware-engine.ps1 exists!" -ForegroundColor Red
                }
                Pause-Console
            }
            elseif ($vmwareChoice -eq "0") {
                break
            }
            else {
                Write-Host "Invalid choice!" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
    elseif ($platformChoice -eq "3") {
        # Docker Desktop / Podman WSL2 Sub-Menu
        while ($true) {
            Show-Header
            Write-Host "--- DOCKER DESKTOP / PODMAN (WSL2) ENGINE ---" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  [1] Relocate Docker Desktop's WSL2 data to another drive"
            Write-Host "  [2] Relocate Windows-host Podman's WSL2 machine data to another drive"
            Write-Host "  [0] Back to Platform Selection"
            Write-Host ""
            Write-Host "====================================================================" -ForegroundColor Cyan

            $ddChoice = Read-Host "Enter choice [0-2]"

            if ($ddChoice -eq "1") {
                if (Get-Command Move-DockerDesktopData -ErrorAction SilentlyContinue) {
                    Move-DockerDesktopData
                } else {
                    Write-Host "[!] Function 'Move-DockerDesktopData' is not loaded. Verify docker-desktop-engine.ps1 exists!" -ForegroundColor Red
                }
                Pause-Console
            }
            elseif ($ddChoice -eq "2") {
                if (Get-Command Move-PodmanMachineData -ErrorAction SilentlyContinue) {
                    Move-PodmanMachineData
                } else {
                    Write-Host "[!] Function 'Move-PodmanMachineData' is not loaded. Verify docker-desktop-engine.ps1 exists!" -ForegroundColor Red
                }
                Pause-Console
            }
            elseif ($ddChoice -eq "0") {
                break
            }
            else {
                Write-Host "Invalid choice!" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
    elseif ($platformChoice -eq "0") {
        Write-Host "Goodbye!" -ForegroundColor Green
        break
    }
    else {
        Write-Host "Invalid choice!" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
}
