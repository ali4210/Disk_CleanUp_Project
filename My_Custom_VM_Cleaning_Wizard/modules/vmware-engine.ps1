# ==============================================================================
# MODULE:       vmware-engine.ps1
# DESCRIPTION:  Handles VMware Workstation / Player VMDK disk shrinking.
# ==============================================================================

function Get-VMwarePath {
    $standardPaths = @(
        "C:\Program Files (x86)\VMware\VMware Workstation",
        "C:\Program Files\VMware\VMware Workstation",
        "C:\Program Files (x86)\VMware\VMware Player",
        "C:\Program Files\VMware\VMware Player"
    )

    foreach ($path in $standardPaths) {
        if (Test-Path -Path (Join-Path $path "vmware-vdiskmanager.exe")) {
            return $path
        }
    }
    return $null
}

function Shrink-VMwareDisks {
    $vmwareDir = Get-VMwarePath
    if (-not $vmwareDir) {
        Write-Host "[!] Error: VMware Installation or 'vmware-vdiskmanager.exe' not found!" -ForegroundColor Red
        Write-Host "[!] Please ensure VMware Workstation or Player is installed." -ForegroundColor Red
        return
    }
    Set-Location -Path $vmwareDir

    Write-Host "[+] Scanning Default VMware Directory for .vmdk Files..." -ForegroundColor Yellow

    $defaultVmPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents\Virtual Machines"
    if (-not (Test-Path -Path $defaultVmPath)) {
        $defaultVmPath = Join-Path -Path $env:USERPROFILE -ChildPath "Virtual Machines"
    }

    if (-not (Test-Path -Path $defaultVmPath)) {
        Write-Host "[!] Could not automatically locate VMware Virtual Machines directory." -ForegroundColor Red
        $customPath = Read-Host "Please enter full path to your VMware VM folder"
        if (Test-Path -Path $customPath) {
            $defaultVmPath = $customPath
        } else {
            Write-Host "[!] Invalid path provided." -ForegroundColor Red
            return
        }
    }

    # Locate base VMDKs (exclude -s001.vmdk split extents)
    $vmdkFiles = Get-ChildItem -Path $defaultVmPath -Filter "*.vmdk" -Recurse | 
                 Where-Object { $_.Name -notmatch "-s\d{3}\.vmdk$" -and $_.Name -notmatch "-flat\.vmdk$" } | 
                 Select-Object -ExpandProperty FullName

    if ($vmdkFiles.Count -eq 0) {
        Write-Host "[!] No valid .vmdk virtual disks found in $defaultVmPath" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "VMware VMDK Disks Found:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $vmdkFiles.Count; $i++) {
        $indexNum = $i + 1
        $diskPath = $vmdkFiles[$i]
        Write-Host "  [$indexNum] $diskPath"
    }
    Write-Host "  [A] Shrink ALL Disks"
    Write-Host "  [C] Cancel"

    $choice = Read-Host "Select VMDK disk to shrink"
    if ($choice -eq "C" -or $choice -eq "c") { return }

    $targetList = @()
    if ($choice -eq "A" -or $choice -eq "a") {
        $targetList = $vmdkFiles
    }
    elseif ([int]::TryParse($choice, [ref]$null) -and [int]$choice -le $vmdkFiles.Count) {
        $targetList = @($vmdkFiles[[int]$choice - 1])
    }
    else {
        Write-Host "Invalid selection." -ForegroundColor Red
        return
    }

    foreach ($vmdkFile in $targetList) {
        if (Test-Path -Path $vmdkFile) {
            Write-Host ""
            Write-Host "====================================================" -ForegroundColor Cyan
            Write-Host "Shrinking VMware VMDK: $vmdkFile" -ForegroundColor Yellow
            Write-Host "====================================================" -ForegroundColor Cyan
            
            .\vmware-vdiskmanager.exe -k "$vmdkFile"

            Write-Host ""
            Write-Host "[OK] Shrink process complete for: $vmdkFile" -ForegroundColor Green
        }
        else {
            Write-Host ""
            Write-Host "[!] Could not locate file: $vmdkFile" -ForegroundColor Red
        }
    }
}
