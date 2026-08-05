# ==============================================================================
# TOOL NAME:    vm-space-wizard.ps1
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Windows Host Compaction and Snapshot Auditor
# ==============================================================================

function Show-Header {
    Clear-Host
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "     [WIZARD] VM SPACE WIZARD - WINDOWS HOST COMPACTION AND AUDITOR   " -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
}

function Pause-Console {
    Write-Host ""
    Read-Host "Press [ENTER] to return to the menu..."
}

# --- Check VirtualBox Directory ---
$VBoxDir = "C:\Program Files\Oracle\VirtualBox"
if (-not (Test-Path -Path $VBoxDir)) {
    Write-Host "[!] Error: Oracle VirtualBox not found at C:\Program Files\Oracle\VirtualBox" -ForegroundColor Red
    Pause-Console
    return
}
Set-Location -Path $VBoxDir

# --- Module 1: Orphaned Snapshot Auditor ---
function Audit-OrphanedSnapshots {
    Show-Header
    Write-Host "[+] Auditing VirtualBox Media Registry vs Physical Disks..." -ForegroundColor Yellow
    
    $registeredVdis = .\VBoxManage.exe list hdds | Select-String "Location:" | ForEach-Object { 
        $_.ToString().Replace("Location:", "").Trim() 
    }

    $defaultVmPath = Join-Path -Path $env:USERPROFILE -ChildPath "VirtualBox VMs"
    if (Test-Path -Path $defaultVmPath) {
        $physicalVdis = Get-ChildItem -Path $defaultVmPath -Filter "*.vdi" -Recurse | Select-Object -ExpandProperty FullName

        $orphanedCount = 0
        foreach ($vdi in $physicalVdis) {
            if ($registeredVdis -notcontains $vdi) {
                $orphanedCount++
                $sizeMb = [math]::Round((Get-Item $vdi).Length / 1MB, 2)
                Write-Host ""
                Write-Host "[!] FOUND ORPHANED / CORRUPTED SNAPSHOT FILE:" -ForegroundColor Red
                Write-Host "    Path: $vdi" -ForegroundColor Gray
                Write-Host "    Size: $sizeMb MB (Unregistered in VirtualBox)" -ForegroundColor Red

                $confirm = Read-Host "    Delete this orphaned file to reclaim space? (y/N)"
                if ($confirm -eq "y" -or $confirm -eq "Y") {
                    Remove-Item -Path $vdi -Force
                    Write-Host "    [OK] File deleted successfully!" -ForegroundColor Green
                }
            }
        }

        if ($orphanedCount -eq 0) {
            Write-Host ""
            Write-Host "[OK] No orphaned or corrupted snapshot files found." -ForegroundColor Green
        }
    }
    Pause-Console
}

# --- Module 2: VDI Compaction ---
function Compact-VdiDisks {
    Show-Header
    Write-Host "[+] Scanning Registered Virtual Disks and Snapshot Chains..." -ForegroundColor Yellow

    $registeredVdis = .\VBoxManage.exe list hdds | Select-String "Location:" | ForEach-Object { 
        $_.ToString().Replace("Location:", "").Trim() 
    }

    if ($registeredVdis.Count -eq 0) {
        Write-Host ""
        Write-Host "[!] No registered virtual hard disks found in VirtualBox." -ForegroundColor Red
        Pause-Console
        return
    }

    Write-Host ""
    Write-Host "Registered Disks Found:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $registeredVdis.Count; $i++) {
        $indexNum = $i + 1
        $diskPath = $registeredVdis[$i]
        Write-Host "  [$indexNum] $diskPath"
    }
    Write-Host "  [A] Compact ALL Registered Disks and Snapshot Chains"
    Write-Host "  [C] Cancel"

    $choice = Read-Host "Select disk to compact"

    if ($choice -eq "C" -or $choice -eq "c") { return }

    $targetList = @()
    if ($choice -eq "A" -or $choice -eq "a") {
        $targetList = $registeredVdis
    }
    elseif ([int]::TryParse($choice, [ref]$null) -and [int]$choice -le $registeredVdis.Count) {
        $targetList = @($registeredVdis[[int]$choice - 1])
    }
    else {
        Write-Host "Invalid selection." -ForegroundColor Red
        Pause-Console
        return
    }

    foreach ($vdiFile in $targetList) {
        if (Test-Path -Path $vdiFile) {
            Write-Host ""
            Write-Host "====================================================" -ForegroundColor Cyan
            Write-Host "Compacting: $vdiFile" -ForegroundColor Yellow
            Write-Host "====================================================" -ForegroundColor Cyan
            
            .\VBoxManage.exe modifymedium disk $vdiFile --compact

            Write-Host ""
            Write-Host "[OK] Compaction complete for: $vdiFile" -ForegroundColor Green
        }
        else {
            Write-Host ""
            Write-Host "[!] Could not locate file: $vdiFile" -ForegroundColor Red
        }
    }
    Pause-Console
}

# --- Main Interactive Loop ---
while ($true) {
    Show-Header
    Write-Host "Please select an action:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] Compact Registered VDI Disks and Active Snapshot Chains"
    Write-Host "  [2] Audit and Clean Orphaned / Corrupted Snapshot Files"
    Write-Host "  [3] Run Full Maintenance (Audit + Compact All)"
    Write-Host "  [4] Exit"
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Cyan

    $mainChoice = Read-Host "Enter choice [1-4]"

    if ($mainChoice -eq "1") {
        Compact-VdiDisks
    }
    elseif ($mainChoice -eq "2") {
        Audit-OrphanedSnapshots
    }
    elseif ($mainChoice -eq "3") {
        Audit-OrphanedSnapshots
        Compact-VdiDisks
    }
    elseif ($mainChoice -eq "4") {
        Write-Host "Goodbye!" -ForegroundColor Green
        break
    }
    else {
        Write-Host "Invalid choice!" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
}
