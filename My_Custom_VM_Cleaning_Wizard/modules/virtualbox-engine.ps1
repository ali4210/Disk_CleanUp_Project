# ==============================================================================
# MODULE:       virtualbox-engine.ps1
# DESCRIPTION:  Handles VirtualBox VDI compaction & snapshot auditing.
# ==============================================================================

function Get-VBoxPath {
    $vboxPath = "C:\Program Files\Oracle\VirtualBox"
    if (Test-Path -Path $vboxPath) {
        return $vboxPath
    }
    return $null
}

function Audit-OrphanedSnapshotsVBox {
    $vboxDir = Get-VBoxPath
    if (-not $vboxDir) {
        Write-Host "[!] Error: Oracle VirtualBox directory not found." -ForegroundColor Red
        return
    }
    Set-Location -Path $vboxDir

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
}

function Compact-VBoxDisks {
    $vboxDir = Get-VBoxPath
    if (-not $vboxDir) {
        Write-Host "[!] Error: Oracle VirtualBox directory not found." -ForegroundColor Red
        return
    }
    Set-Location -Path $vboxDir

    Write-Host "[+] Scanning Registered Virtual Disks and Snapshot Chains..." -ForegroundColor Yellow

    $registeredVdis = .\VBoxManage.exe list hdds | Select-String "Location:" | ForEach-Object { 
        $_.ToString().Replace("Location:", "").Trim() 
    }

    if ($registeredVdis.Count -eq 0) {
        Write-Host ""
        Write-Host "[!] No registered virtual hard disks found in VirtualBox." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "Registered VirtualBox Disks Found:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $registeredVdis.Count; $i++) {
        $indexNum = $i + 1
        $diskPath = $registeredVdis[$i]
        Write-Host "  [$indexNum] $diskPath"
    }
    Write-Host "  [A] Compact ALL Registered Disks"
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
        return
    }

    foreach ($vdiFile in $targetList) {
        if (Test-Path -Path $vdiFile) {
            Write-Host ""
            Write-Host "====================================================" -ForegroundColor Cyan
            Write-Host "Compacting VDI: $vdiFile" -ForegroundColor Yellow
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
}
