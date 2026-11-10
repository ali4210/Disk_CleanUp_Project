# ==============================================================================
# MODULE:       docker-desktop-engine.ps1
# DESCRIPTION:  Relocates Docker Desktop's WSL2 data (images/containers/volumes)
#               and, if present, Windows-host Podman machine WSL2 data, to
#               another drive - the Windows-side equivalent of the Linux guest's
#               secondary-disk offload. Uses the documented wsl --export /
#               --unregister / --import workflow, which re-registers the distro
#               under the same name, so Docker Desktop / Podman keep working
#               without reconfiguration.
# REQUIRES:     wsl.exe (Windows 10 2004+ / Windows 11), Docker Desktop and/or
#               Podman Desktop already installed at least once (so their WSL
#               distros exist to move).
# NOTE:         This module could not be run-tested in the Linux development
#               sandbox this tool was built in (no Windows/WSL available there).
#               It was written against the documented wsl.exe workflow and
#               syntax-checked, but must be exercised for real on a Windows
#               host before being relied on. Test manually first.
# ==============================================================================

function Test-WslAvailable {
    return [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)
}

function Get-WslDistroNames {
    if (-not (Test-WslAvailable)) { return @() }
    # wsl -l -v prints a UTF-16/space-padded table; strip the asterisk (default
    # marker) and whitespace to get bare distro names.
    $raw = & wsl.exe -l -v 2>$null
    if (-not $raw) { return @() }
    return @($raw | Select-Object -Skip 1 | ForEach-Object {
        ($_ -replace '^\*', '').Trim() -split '\s+' | Select-Object -First 1
    } | Where-Object { $_ })
}

function Get-DockerDesktopDistroNames {
    return @(Get-WslDistroNames | Where-Object { $_ -in @('docker-desktop', 'docker-desktop-data') })
}

function Get-PodmanMachineDistroNames {
    return @(Get-WslDistroNames | Where-Object { $_ -like 'podman-machine-*' })
}

# Moves one WSL distro's virtual disk to $TargetDir\<distro>, preserving its
# data and re-registering it under the same name (export -> unregister -> import).
function Move-WslDistro {
    param(
        [Parameter(Mandatory)][string]$DistroName,
        [Parameter(Mandatory)][string]$TargetDir
    )
    if (-not (Test-WslAvailable)) {
        Write-Host "[!] wsl.exe not found on this system." -ForegroundColor Red
        return $false
    }
    if ((Get-WslDistroNames) -notcontains $DistroName) {
        Write-Host "[!] WSL distro '$DistroName' is not registered; nothing to move." -ForegroundColor Yellow
        return $false
    }
    if (-not (Test-Path -Path $TargetDir)) {
        New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
    }

    $destDir = Join-Path -Path $TargetDir -ChildPath $DistroName
    $tarPath = Join-Path -Path $env:TEMP -ChildPath "$DistroName-$(Get-Random).tar"

    Write-Host "[+] Shutting down WSL (stops Docker Desktop / Podman's backend briefly)..." -ForegroundColor Yellow
    & wsl.exe --shutdown
    Start-Sleep -Seconds 2

    Write-Host "[+] Exporting '$DistroName' (this can take a while for large image/volume data)..." -ForegroundColor Yellow
    & wsl.exe --export $DistroName $tarPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -Path $tarPath)) {
        Write-Host "[!] Export failed; nothing was changed. '$DistroName' is untouched." -ForegroundColor Red
        return $false
    }
    $exportSizeMb = [math]::Round((Get-Item $tarPath).Length / 1MB, 1)
    Write-Host "    Exported $exportSizeMb MB to $tarPath" -ForegroundColor Cyan

    Write-Host "[+] Unregistering '$DistroName' from its current location..." -ForegroundColor Yellow
    & wsl.exe --unregister $DistroName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Unregister failed. Your data is safe in the export at $tarPath" -ForegroundColor Red
        Write-Host "    Re-import it yourself with: wsl --import $DistroName <folder> `"$tarPath`" --version 2" -ForegroundColor Yellow
        return $false
    }

    Write-Host "[+] Importing '$DistroName' into $destDir ..." -ForegroundColor Yellow
    New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    & wsl.exe --import $DistroName $destDir $tarPath --version 2
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Import into the new location failed." -ForegroundColor Red
        Write-Host "    Your data is safe in the export at $tarPath -- re-import it manually:" -ForegroundColor Yellow
        Write-Host "    wsl --import $DistroName <folder> `"$tarPath`" --version 2" -ForegroundColor Yellow
        return $false
    }

    Remove-Item -Path $tarPath -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] '$DistroName' now lives at $destDir" -ForegroundColor Green
    return $true
}

function Move-DockerDesktopData {
    Write-Host "[+] Docker Desktop (WSL2) Data Relocation" -ForegroundColor Yellow
    Write-Host "This moves the WSL virtual disks holding your Docker images, containers and" -ForegroundColor Cyan
    Write-Host "volumes to a drive of your choice. Docker Desktop must be closed first." -ForegroundColor Cyan
    Write-Host ""

    $distros = Get-DockerDesktopDistroNames
    if ($distros.Count -eq 0) {
        Write-Host "[!] No 'docker-desktop' / 'docker-desktop-data' WSL distro found." -ForegroundColor Red
        Write-Host "    Is Docker Desktop installed and has it been run at least once?" -ForegroundColor Yellow
        return
    }

    Write-Host "Found WSL distro(s): $($distros -join ', ')" -ForegroundColor Cyan
    Write-Host "'docker-desktop-data' holds your images/containers/volumes (move this one)." -ForegroundColor Cyan
    Write-Host "'docker-desktop' is the small utility VM (optional to move)." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Close Docker Desktop completely (including the tray icon) before continuing." -ForegroundColor Red
    $confirm = Read-Host "Is Docker Desktop fully closed, and ready to proceed? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }

    $targetDir = Read-Host "Target directory for Docker Desktop's WSL data (e.g. D:\DockerData)"
    if ([string]::IsNullOrWhiteSpace($targetDir)) {
        Write-Host "[!] No target directory given; cancelled." -ForegroundColor Red
        return
    }

    $toMove = @($distros | Where-Object { $_ -eq 'docker-desktop-data' })
    if ($distros -contains 'docker-desktop') {
        $alsoMoveUtility = Read-Host "Also move the small 'docker-desktop' utility VM here? (y/N)"
        if ($alsoMoveUtility -eq "y" -or $alsoMoveUtility -eq "Y") { $toMove += 'docker-desktop' }
    }

    $allOk = $true
    foreach ($d in $toMove) {
        if (-not (Move-WslDistro -DistroName $d -TargetDir $targetDir)) { $allOk = $false }
    }

    Write-Host ""
    if ($allOk) {
        Write-Host "[OK] Done. Start Docker Desktop normally -- it finds its distros by name," -ForegroundColor Green
        Write-Host "     not by location, so no further configuration is needed." -ForegroundColor Green
    } else {
        Write-Host "[!] One or more distros failed to move. Read the messages above before" -ForegroundColor Red
        Write-Host "    starting Docker Desktop -- an export .tar may still be sitting in `$env:TEMP." -ForegroundColor Red
    }
}

function Move-PodmanMachineData {
    Write-Host "[+] Windows-host Podman (WSL2 machine) Data Relocation" -ForegroundColor Yellow
    $distros = Get-PodmanMachineDistroNames
    if ($distros.Count -eq 0) {
        Write-Host "[!] No 'podman-machine-*' WSL distro found. Is Podman (Desktop) installed," -ForegroundColor Red
        Write-Host "    and has 'podman machine init' been run at least once?" -ForegroundColor Yellow
        return
    }
    Write-Host "Found: $($distros -join ', ')" -ForegroundColor Cyan
    Write-Host "Stop the Podman machine first: podman machine stop" -ForegroundColor Red
    $confirm = Read-Host "Is the Podman machine stopped, and ready to proceed? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }
    $targetDir = Read-Host "Target directory for Podman's WSL data (e.g. D:\PodmanData)"
    if ([string]::IsNullOrWhiteSpace($targetDir)) {
        Write-Host "[!] No target directory given; cancelled." -ForegroundColor Red
        return
    }
    $allOk = $true
    foreach ($d in $distros) {
        if (-not (Move-WslDistro -DistroName $d -TargetDir $targetDir)) { $allOk = $false }
    }
    if ($allOk) {
        Write-Host "[OK] Done. Run 'podman machine start' -- it finds its machine by name, not location." -ForegroundColor Green
    }
}
