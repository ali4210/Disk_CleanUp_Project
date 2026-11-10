# ==============================================================================
# MODULE:       vmware-engine.ps1
# DESCRIPTION:  Handles VMware Workstation/Player .vmdk disk shrinking via
#               vmware-vdiskmanager.exe (falls back to vmrun.exe to at least
#               detect/refuse running VMs when vdiskmanager is unavailable).
# ==============================================================================

function Get-VMwarePath {
    $candidates = @(
        "C:\Program Files (x86)\VMware\VMware Workstation",
        "C:\Program Files\VMware\VMware Workstation",
        "C:\Program Files (x86)\VMware\VMware Player",
        "C:\Program Files\VMware\VMware Player"
    )
    foreach ($path in $candidates) {
        if (Test-Path -Path $path) { return $path }
    }
    return $null
}

function Get-VMwareDiskManagerExe {
    $vmwareDir = Get-VMwarePath
    if (-not $vmwareDir) { return $null }
    $exe = Join-Path -Path $vmwareDir -ChildPath "vmware-vdiskmanager.exe"
    if (Test-Path -Path $exe) { return $exe }
    return $null
}

function Get-VMwareRunExe {
    $vmwareDir = Get-VMwarePath
    if (-not $vmwareDir) { return $null }
    $exe = Join-Path -Path $vmwareDir -ChildPath "vmrun.exe"
    if (Test-Path -Path $exe) { return $exe }
    return $null
}

# Returns the full paths (lowercased, trimmed) of .vmx files for VMs vmrun
# reports as currently running, so we can refuse to shrink their disks.
function Get-RunningVMwareVmxPaths {
    $vmrunExe = Get-VMwareRunExe
    if (-not $vmrunExe) { return @() }
    try {
        $out = & $vmrunExe -T ws list 2>$null
    } catch {
        return @()
    }
    # First line is a count/header ("Total running VMs: N"); the rest are .vmx paths.
    return @($out | Where-Object { $_ -match '\.vmx$' } | ForEach-Object { $_.Trim().ToLower() })
}

function Find-VMwareVmdkFiles {
    $searchRoots = @(
        (Join-Path -Path $env:USERPROFILE -ChildPath "Documents\Virtual Machines"),
        (Join-Path -Path $env:PUBLIC -ChildPath "Documents\Virtual Machines")
    )
    $found = @()
    foreach ($root in $searchRoots) {
        if (Test-Path -Path $root) {
            $found += Get-ChildItem -Path $root -Filter "*.vmdk" -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '-s\d{3}\.vmdk$' } |  # skip split-disk fragment files
                Select-Object -ExpandProperty FullName
        }
    }
    return @($found | Sort-Object -Unique)
}

# True if this .vmdk belongs to a VM vmrun reports as running - found by
# checking whether any running .vmx's directory contains this .vmdk.
function Test-VmdkBelongsToRunningVm {
    param([string]$VmdkPath, [string[]]$RunningVmxPaths)
    if ($RunningVmxPaths.Count -eq 0) { return $false }
    $vmdkDir = (Split-Path -Path $VmdkPath -Parent).ToLower()
    foreach ($vmx in $RunningVmxPaths) {
        if ((Split-Path -Path $vmx -Parent).ToLower() -eq $vmdkDir) { return $true }
    }
    return $false
}

function Shrink-VMwareDisks {
    $vdiskManager = Get-VMwareDiskManagerExe
    if (-not $vdiskManager) {
        Write-Host "[!] Error: Could not find vmware-vdiskmanager.exe under the detected VMware install." -ForegroundColor Red
        Write-Host "    VMware Workstation 16+/Player sometimes omits it; shrinking then requires" -ForegroundColor Yellow
        Write-Host "    the VM's own Settings -> Hard Disk -> Utilities -> Shrink in the VMware UI instead." -ForegroundColor Yellow
        return
    }

    Write-Host "[+] Scanning for .vmdk files under your Virtual Machines folder..." -ForegroundColor Yellow
    $vmdkFiles = Find-VMwareVmdkFiles
    if ($vmdkFiles.Count -eq 0) {
        Write-Host ""
        Write-Host "[!] No .vmdk files found under the default Virtual Machines folder(s)." -ForegroundColor Red
        Write-Host "    If yours live elsewhere, shrink manually: vmware-vdiskmanager.exe -k <path.vmdk>" -ForegroundColor Yellow
        return
    }

    $runningVmx = Get-RunningVMwareVmxPaths
    if ($runningVmx.Count -gt 0) {
        Write-Host ""
        Write-Host "[!] $($runningVmx.Count) VM(s) are currently running. Their disks will be skipped (shrinking" -ForegroundColor Yellow
        Write-Host "    a running VM's disk can corrupt it) - shut them down first to shrink those too." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Virtual Disks Found:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $vmdkFiles.Count; $i++) {
        $indexNum = $i + 1
        $isRunning = Test-VmdkBelongsToRunningVm -VmdkPath $vmdkFiles[$i] -RunningVmxPaths $runningVmx
        $tag = if ($isRunning) { " (VM RUNNING - will be skipped)" } else { "" }
        Write-Host "  [$indexNum] $($vmdkFiles[$i])$tag"
    }
    Write-Host "  [A] Shrink ALL eligible (not running) disks"
    Write-Host "  [C] Cancel"

    $choice = Read-Host "Select disk to shrink"
    if ($choice -eq "C" -or $choice -eq "c") { return }

    $targetList = @()
    if ($choice -eq "A" -or $choice -eq "a") {
        $targetList = $vmdkFiles
    }
    elseif ([int]::TryParse($choice, [ref]$null) -and [int]$choice -ge 1 -and [int]$choice -le $vmdkFiles.Count) {
        $targetList = @($vmdkFiles[[int]$choice - 1])
    }
    else {
        Write-Host "Invalid selection." -ForegroundColor Red
        return
    }

    foreach ($vmdkFile in $targetList) {
        if (-not (Test-Path -Path $vmdkFile)) {
            Write-Host ""
            Write-Host "[!] Could not locate file: $vmdkFile" -ForegroundColor Red
            continue
        }
        if (Test-VmdkBelongsToRunningVm -VmdkPath $vmdkFile -RunningVmxPaths $runningVmx) {
            Write-Host ""
            Write-Host "[!] Skipping $vmdkFile - its VM is currently running." -ForegroundColor Yellow
            continue
        }

        Write-Host ""
        Write-Host "====================================================" -ForegroundColor Cyan
        Write-Host "Shrinking VMDK: $vmdkFile" -ForegroundColor Yellow
        Write-Host "====================================================" -ForegroundColor Cyan

        # -k shrinks a disk that has already been zero-filled from inside the
        # guest (Stage 1); a split/non-preallocated disk is required for this
        # to reclaim space - vdiskmanager reports its own error if that's not met.
        & $vdiskManager -k $vmdkFile

        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "[OK] Shrink complete for: $vmdkFile" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "[!] vmware-vdiskmanager reported an error (exit $LASTEXITCODE) for: $vmdkFile" -ForegroundColor Red
        }
    }
}
