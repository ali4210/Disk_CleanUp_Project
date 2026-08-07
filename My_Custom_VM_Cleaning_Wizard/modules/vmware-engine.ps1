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

# --- Load Engine Modules ---
$VBoxModule = Join-Path -Path $ScriptDir -ChildPath "virtualbox-engine.ps1"
$VMwareModule = Join-Path -Path $ScriptDir -ChildPath "vmware-engine.ps1"

if (Test-Path -Path $VBoxModule) {
    . $VBoxModule
} else {
    $VBoxModule = Join-Path -Path $ScriptDir -ChildPath "modules\virtualbox-engine.ps1"
    if (Test-Path -Path $VBoxModule) { . $VBoxModule }
    else { Write-Host "[!] Error: Could not locate virtualbox-engine.ps1" -ForegroundColor Red }
}

if (Test-Path -Path $VMwareModule) {
    . $VMwareModule
} else {
    $VMwareModule = Join-Path -Path $ScriptDir -ChildPath "modules\vmware-engine.ps1"
    if (Test-Path -Path $VMwareModule) { . $VMwareModule }
    else { Write-Host "[!] Error: Could not locate vmware-engine.ps1" -ForegroundColor Red }
}

function Show-Header {
    Clear-Host
    Write-Host @"
WIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARD
WIZARDWIZARDWIZARDWIZARDWIZAR..::::::::::::::::..IZARDWIZARDWIZARDWIZARDWIZARD
WIZARDWIZARDWIZARDWIZARD.::::::::::::::::::::::::::::.WIZARDWIZARDWIZARDWIZARD
WIZARDWIZARDWIZARDWI.:::::::::'mmMMMMMMMMMMMMmm`:::::::::.RDWIZARDWIZARDWIZARD
WIZARDWIZARDWIZAR.:::::::'mMMMMMMMMMMMMMMMMMMMMMMMMm`:::::::.IZARDWIZARDWIZARD
WIZARDWIZARDWI.::::::'mMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMm`:::::.ARDWIZARDWIZARD
WIZARDWIZARDW.::::'mMMMMMM"            "MMMMMMMMMMMMMMMMMMm`::::.DWIZARDWIZA D
WIZARDWIZAR.::::'mMMMM"   mmMMMMMm          "MMMMMMMMMMMMMMMm`::::.IZARDWIZAr
WIZARDWIZ.::::'mMMMM mmMMMMMMMMMMMMMMm          "MMMMMMMMMMMMMMMMMMMZARDWIZ42
WIZARDWI.:::'mMMMMMMMMMMMMMMMMMMMMMMMMMm           "MMMMMMMMMMMM     ARDWIZa
WIZARDW.:::'mMMMMMMMMMMMMMMMMMMMMMMMMMMMMm            MMMMMMMMMM      RDWIZ  I
WIZARD::::'MMMMMMMMMMMMMMMMMMMMMMMMMMMMMm            mMMMMMMMMMMM     RDWI   D
WIZAR.:::'mMMMMMMMMMMMMMMMMMMM    MMMM"              MMMMMMMMMMMMMMMMMMW"   iD
WIZA.:::'MMMMMMMMMMMMMMMMM           MMMm             MMMMMMMMMM           .AD
WIZA:::'mMMMMMMMMMMMMMM                 MMM         mMMMMMMMMMM            ARD
WIZ.:::mMMMMMMMMMMMM             M        MM       mM  MMMMMMM            ZARD
WIZ:::'MMMMMMMMMMM              mMMm       MM     mM     MMMM            M:ARD
WI.:::MMMMMMMMMM               mMMMMMm      MM   mM        M           mM::.RD
WI:::'MMMMMMMM                mMMMMMMM       MM mM  mM               mMM`:::RD
WI:::mMMMMMMM                mMMMMMMMM        MMM  mMMMM          mMMMMMm:::.D
W':::MMMMMMM                mMMMMMMMMMMM          mMMMMMMM    mMMMMMMMMMM:::`D
W:::'MMMMMM        mMMMMMMMMMMMMMMMMMM MM        mMMMMMMMMMMMMMMMMMMMMMMM`:::D
i:::iMMMMM      mMMMMM     MMMMMMMMMM   MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMi:::D
z:::IMMMM"    mMMMMMMM      MMMMMMMM                             MMMMMMMMI:::)
a:::iMMMM   mMMMMMMMMMM     MMMMMMMM                              MMMMMMMi:::D
r:::`MMMM  MMMMMMMMMMMMMMMMMMMMMMMMMM                             MMMMMMM,:::D
d`:::MMMm mMMMMMMMMMMMMMMMMMMMMMMM  MM               mMMMm       MMMMMMMM:::,D
W`:::mMMM MMMMMMMMMMMMMMMMMMMMMMM    MMMMMMMMMMMMMMMMMMM        mMMMMMMMm:::.D
WI:::`MMMmMMMMMMMMMMMMMMMMMMMMMM            mMMMMMMMMM         mMMMMMMMM,:::RD
WI`:::MMMMMMMMMMMMMMMMMMMMMMMMM           mMMMMMMMMM           MMMMMMMMM:::'RD
WIZ:::.MMMMMMMMMMMMMMMMMMMMMMM          mMMMMMMMMM            mMMMMMMMM':::ARD
WIZ`MMMMM"""        ""MMMMMMM         mMMMMMMMMM              MMMMMMMMm:::'ARD
WIZA"                     "M        mMMMMMMMMM               mMMMMMMMM'::'ZARD
WI"                               mMMMMMMMMM                 MMMMMMMM,::.IZARD
W  ZAMMMm                       mMMMMMMMMM                   MMMMMMM,:::'IZARD
 IZARD`::Mm                   MMMMMMMMMM        mMMMMMMMMMMMMMMMMMM,:::'WIZARD
WIZARDW`:::M               mMMMMMMMMMMM     mMMMMMMMMM      MMMMMMMm::'DWIZARD
WIZARDWI`::MM           mMMMMMMMMMMMMM   mMMMMMMMMMMM             MM:'RDWIZARD
WIZARDWIZAM MM       mMMMMMMMMMMMMMMM  mMMMMMMMMMMMMMmmmmmmmmmmmMMM:ZARDWIZARD
WIZARDWIZA   Mm   mMMMMMMMMMMMMMMMMM" mMMMMMMMMMMMMMMMMMMMMMM'::::'IZARDWIZARD
WIZARDWIZ     M mMM.MMMMMMMMMMMMMMMm mMMMMMMMMMMMMMMMMMMMMM.::::'DWIZARDWIZARD
WIZARDWI    DWMm`::::"MMMMMMMMMMMMMm MMMMMMMMMMMMMMMMMMM".::::'ARDWIZARDWIZARD
WIZARDW   ARDWIZAR`:::::."MMMMMMMMMMmMMMMMMMMMMMMMMM".:::::'WIZARDWIZARDWIZARD
WIZARDW  ZARDWIZARDWI`:::::::.""MMMMMMMMMMMMMM"".::::::::'RDWIZARDWIZARDWIZARD
WIZARDW  ZARDWIZARDWIZAR`::::::::::::::::::::::::::::'WIZARDWIZARDWIZARDWIZARD
WIZARDWIZARDWIZARDWIZARDWIZAR``::::::::::::::::''IZARDWIZARDWIZARDWIZARDWIZARD
WIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARDWIZARD
	   .aMMMb  dMP     dMMMMMP .aMMMb  dMMMMb  dMP dMP dMP dMP dMMMMMP 
	  dMP"VMP dMP     dMP     dMP"dMP dMP dMP dMP dMP dMP amr   .dMP"  
	 dMP     dMP     dMMMP   dMMMMMP dMP dMP dMP dMP dMP dMP  .dMP"    
	dMP.aMP dMP     dMP     dMP dMP dMP dMP dMP.dMP.dMP dMP .dMP"      
	VMMMP" dMMMMMP dMMMMMP dMP dMP dMP dMP  VMMMPVMMP" dMP dMMMMMP    
                                                                   
"@ -ForegroundColor Cyan

    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "         VM SPACE WIZARD V2.1 - UNIVERSAL HYPERVISOR COMPACTOR        " -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "GitHub  : https://github.com/ali4210" -ForegroundColor Yellow
    Write-Host "Active Repository Context: $TargetRepoDir" -ForegroundColor Yellow
}

function Pause-Console {
    Write-Host ""
    Read-Host "Press [ENTER] to return to the menu..."
}

# --- Main Hypervisor Selection Menu ---
while ($true) {
    Show-Header
    Write-Host "Select your virtualization platform:`n" -ForegroundColor Yellow
    Write-Host "  [1] Oracle VirtualBox (.vdi)" -ForegroundColor Green
    Write-Host "  [2] VMware Workstation / Player (.vmdk)" -ForegroundColor Green
    Write-Host "  [3] Exit" -ForegroundColor Green
    Write-Host "`n====================================================================" -ForegroundColor Cyan

    $platformChoice = Read-Host "Enter choice [1-3]"

    if ($platformChoice -eq "1") {
        # VirtualBox Sub-Menu
        while ($true) {
            Show-Header
            Write-Host "--- ORACLE VIRTUALBOX ENGINE ---`n" -ForegroundColor Yellow
            Write-Host "  [1] Compact Registered VDI Disks and Active Snapshot Chains" -ForegroundColor Green
            Write-Host "  [2] Audit and Clean Orphaned / Corrupted Snapshot Files" -ForegroundColor Green
            Write-Host "  [3] Run Full Maintenance (Audit + Compact All)" -ForegroundColor Green
            Write-Host "  [4] Back to Platform Selection" -ForegroundColor Green
            Write-Host "`n====================================================================" -ForegroundColor Cyan

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
            Write-Host "--- VMWARE ENGINE ---`n" -ForegroundColor Yellow
            Write-Host "  [1] Shrink Virtual Machine Disks (.vmdk)" -ForegroundColor Green
            Write-Host "  [2] Back to Platform Selection" -ForegroundColor Green
            Write-Host "`n====================================================================" -ForegroundColor Cyan

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
        Write-Host "`nKeep optimizing your virtual environment! Goodbye!" -ForegroundColor Green
        break
    }
    else {
        Write-Host "Invalid choice!" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
}