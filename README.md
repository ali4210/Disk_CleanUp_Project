<div align="center">

# 🧙‍♂️ VM Space Wizard
### *Universal Cross-Platform VM Disk Optimization & Host Compaction Suite*

![License](https://img.shields.io/badge/license-MIT-2ea043?style=for-the-badge)
![Version](https://img.shields.io/badge/version-V2.2-8250df?style=for-the-badge)
![Safety](https://img.shields.io/badge/safety-guarded-e3b341?style=for-the-badge)

![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Batch](https://img.shields.io/badge/Batch-000000?style=for-the-badge&logo=windows-terminal&logoColor=white)

![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Windows](https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![VirtualBox](https://img.shields.io/badge/VirtualBox-183A61?style=for-the-badge&logo=virtualbox&logoColor=white)
![VMware](https://img.shields.io/badge/VMware-607078?style=for-the-badge&logo=vmware&logoColor=white)

**Reclaim the disk space your VM never gives back — safely, automatically, and without touching Windows Explorer.**

Deleting files inside a Linux guest never shrinks the `.vdi` or `.vmdk` file on your host. VM Space Wizard is a guided, two-stage pipeline that cleans your guest, zero-fills the freed blocks, and then compacts the physical disk file on your host — without ever risking the snapshot chain.

[**Why**](#-why-this-exists) · [**Features**](#-features) · [**Install**](#-installation) · [**Usage**](#-usage-the-two-stage-workflow) · [**Preview**](#-menus-at-a-glance) · [**Safety**](#-safety-guardrails) · [**Structure**](#-repository-structure) · [**FAQ**](#-faq--troubleshooting)

</div>

---

## 💡 Why This Exists

Shrinking a VM's disk footprint is deceptively hard:

- 🗑️ You delete gigabytes of logs, Docker images, and package caches *inside* the guest OS — but the `.vdi` / `.vmdk` on your host stays exactly the same size.
- ⚠️ The common "fix" — manually deleting snapshot files from Windows Explorer — **breaks the hypervisor's media registry** and can corrupt the entire VM.
- 🧩 Actually compacting a disk requires a specific sequence: clean the guest → zero-fill the unused blocks → shut down → compact from the *host*, using the correct hypervisor CLI tool.
- 🐳 Container engines (Docker/Podman) are frequently the biggest offenders, silently consuming tens of gigabytes in build caches, dangling images, and unused volumes.

**VM Space Wizard automates this entire pipeline behind two simple menus** — one inside your Linux guest, one on your Windows host — so reclaiming real disk space takes minutes, not a support-forum deep dive.

---

## ✨ Features

### 🐧 Stage 1 — Linux Guest Engine (`linux/vm-space-wizard.sh`)

| Feature | Details |
|---|---|
| 🌍 **Universal distro support** | Debian, Ubuntu, Kali Linux, CentOS, RHEL, Fedora, and Rocky Linux — auto-detects `apt`, `dnf`, or `yum` |
| 🐳 **Granular container pruning** | Selectively prune Docker & Podman: build caches only, unused volumes only, stopped containers only, dangling images only, or a full deep clean |
| 💾 **Secondary disk offloader** | Safely detects, formats (if needed), and mounts a secondary virtual drive to `/var/lib/docker`, then repoints Podman's `graphroot` — with built-in **root-drive protection** so you can never target your active OS disk |
| 📖 **In-menu attachment guides** | Step-by-step instructions for attaching a second virtual disk in both **Oracle VirtualBox** and **VMware Workstation/Player**, shown right when you need them |
| 🧽 **OS-level cleanup** | Clears package manager caches, runs `autoremove`, vacuums `systemd` journal logs (keeps last 3 days), and clears `/tmp` and thumbnail caches |
| 🔄 **Zero-fill sequence** | Writes zeroes across unallocated disk blocks so the host hypervisor can actually reclaim the freed space, then gracefully shuts the VM down |
| 🌐 **Global CLI install** | Registers itself as `clean-wizard`, runnable from any terminal, any directory |

### 🪟 Stage 2 — Windows Host Engine (`modules/vm-space-wizard.ps1`)

| Feature | Details |
|---|---|
| 🖥️ **Multi-hypervisor support** | Full native support for **Oracle VirtualBox** (`.vdi`) via `VBoxManage.exe` and **VMware Workstation/Player** (`.vmdk`) |
| 🔍 **Orphaned snapshot auditor** | Cross-references every physical `.vdi` file on disk against VirtualBox's media registry, flags anything unregistered, and offers a guided, confirmed deletion to reclaim space safely |
| 📦 **Registered disk compactor** | Lists every disk VirtualBox actually knows about and compacts one, several, or all of them via `VBoxManage modifymedium --compact` |
| 🔐 **Automated elevation** | `autorun.bat` self-elevates to Administrator — required for hypervisor CLI access — with zero manual UAC hunting |
| 🧩 **Modular architecture** | Hypervisor logic is cleanly separated into `virtualbox-engine.ps1` and `vmware-engine.ps1`, loaded dynamically by the master entry point |

---

## 🛠️ Installation

### Requirements

| | 🐧 Linux Guest | 🪟 Windows Host |
|---|---|---|
| **Shell** | Bash | Windows PowerShell (bundled) |
| **Privileges** | `sudo` | Administrator (auto-elevated) |
| **Software** | `lsblk`, `blkid`, `dd` (standard on all supported distros); Docker and/or Podman for container pruning | Oracle VirtualBox and/or VMware Workstation/Player installed at their default paths |

### Clone the repository

```bash
git clone https://github.com/ali4210/Disk_CleanUp_Project.git
cd Disk_CleanUp_Project/My_Custom_VM_Cleaning_Wizard
```

### 🐧 Set up inside your Linux VM

```bash
chmod +x autorun.sh
./autorun.sh
```

> Permissions are also self-healing: `autorun.sh` automatically runs `chmod +x` on every `.sh` file in the repository each time it launches.

### 🪟 Set up on your Windows host

Simply **double-click `autorun.bat`**. It requests Administrator rights automatically (required for `VBoxManage.exe` and hypervisor disk access) and opens the master launcher menu.

### 🌐 Optional: install as a global command (Linux)

```bash
bash install.sh
```

This symlinks the Linux engine to `/usr/local/bin/clean-wizard`, so you can run `clean-wizard` from any directory without `cd`-ing into the repo.

---

## 🚀 Usage: The Two-Stage Workflow

```mermaid
flowchart TD
    A(["🧑 Start inside Linux VM"]) --> B["./autorun.sh"]
    B --> C{"Choose context"}
    C -- "Option 1" --> D["🐧 Stage 1 Engine<br/>vm-space-wizard.sh"]
    D --> D1["Prune Docker / Podman"]
    D --> D2["Clean OS caches & logs"]
    D --> D3["Offload storage to secondary disk"]
    D --> D4["FULL CLEANUP + Zero-Fill"]
    D4 --> E(["💤 VM shuts down"])
    E --> F["🪟 On Windows: double-click autorun.bat"]
    F --> G["🔐 Auto-elevate to Administrator"]
    G --> H["🪟 Stage 2 Engine<br/>vm-space-wizard.ps1"]
    H --> I{"Pick hypervisor"}
    I -- "VirtualBox" --> J["Audit orphaned snapshots<br/>+ Compact registered VDIs"]
    I -- "VMware" --> K["Shrink VMDK disks"]
    J --> L(["✅ Host disk space reclaimed"])
    K --> L

    classDef start fill:#1f6feb,color:#ffffff,stroke:#0b3d91;
    classDef eng fill:#8250df,color:#ffffff,stroke:#512a97;
    classDef done fill:#2ea043,color:#ffffff,stroke:#116329;
    class A,F start;
    class D,H eng;
    class E,L done;
```

### 📍 Stage 1 — Inside the Linux Guest

1. Clone or copy the repository into your VM.
2. Run the launcher:
   ```bash
   chmod +x autorun.sh
   ./autorun.sh
   ```
3. Select **`[1] Running inside LINUX GUEST`**.
4. From the main menu, run whichever tasks you need:
   - **`[1]`** Free up container space (choose granular pruning or a full deep clean)
   - **`[2]`** Free up OS system space (package caches, logs, temp files)
   - **`[3]`** Offload Docker/Podman storage to a secondary disk
   - **`[4]`** **FULL CLEANUP + Zero-Fill** — runs everything above, then zero-fills unused blocks and **shuts the VM down automatically**

### 📍 Stage 2 — On the Windows Host

1. Confirm Stage 1 has finished and the VM is shut down.
2. Double-click **`autorun.bat`** and accept the Administrator prompt.
3. Select **`[2] Stage 2: Windows Host VDI / VMDK Compaction`**.
4. Choose your hypervisor:
   - **VirtualBox** → audit orphaned snapshots, then compact one/several/all registered `.vdi` disks
   - **VMware** → shrink `.vmdk` disks
5. Watch your `.vdi`/`.vmdk` file shrink on disk. Done.

---

## 🖥️ Menus at a Glance

<details>
<summary><b>🐧 Linux Stage 1 — Main Menu</b></summary>

```text
====================================================================
         🧙‍♂️ VM SPACE WIZARD - SYSTEM & CONTAINER OPTIMIZER
====================================================================
Please select an action:

  [1] Free Up Container Space (Customizable Docker & Podman Prune)
  [2] Free Up OS System Space (Clean Package Caches & Logs)
  [3] Offload Docker & Podman Storage to Secondary HDD Drive
  [4] FULL CLEANUP + Zero-Fill for Host Disk Compaction (Stage 1)
  [5] Exit
```

</details>

<details>
<summary><b>🐳 Container Pruning Submenu</b></summary>

```text
[+] Granular Container Cleanup Engine (Docker & Podman)

  [1] Prune Build Caches Only (Safe: Keeps images & containers)
  [2] Prune Unused Volumes Only (Deletes unattached volumes)
  [3] Prune Stopped Containers Only (Deletes non-running containers)
  [4] Prune Dangling Images Only (Untagged image layers)
  [5] FULL DEEP CLEAN (Prune ALL unused containers, images, volumes & caches)
  [6] Return to Main Menu
```

</details>

<details>
<summary><b>🪟 Windows Master Launcher (autorun.bat)</b></summary>

```text
====================================================================
         VM SPACE WIZARD - MASTER LAUNCHER (WINDOWS)
====================================================================
Which stage of the cleanup process are you currently executing?

  [1] Stage 1: Linux System Cleanup
  [2] Stage 2: Windows Host VDI / VMDK Compaction (RUN HERE)
  [3] Exit
```

</details>

<details>
<summary><b>🪟 Windows Stage 2 — Hypervisor Selection</b></summary>

```text
====================================================================
  VM SPACE WIZARD V2.1 - UNIVERSAL HYPERVISOR COMPACTOR
====================================================================
Select your virtualization platform:

  [1] Oracle VirtualBox (.vdi)
  [2] VMware Workstation / Player (.vmdk)
  [3] Exit
```

```text
--- ORACLE VIRTUALBOX ENGINE ---

  [1] Compact Registered VDI Disks and Active Snapshot Chains
  [2] Audit and Clean Orphaned / Corrupted Snapshot Files
  [3] Run Full Maintenance (Audit + Compact All)
  [4] Back to Platform Selection
```

</details>

---

## 🛡️ Safety Guardrails

VM Space Wizard touches destructive operations (disk formatting, snapshot deletion, container pruning), so it is built with explicit safety rails at every dangerous step:

| Guardrail | What it prevents |
|---|---|
| 🚫 **Root drive protection** | The secondary disk offloader compares the target device against your active root filesystem's parent disk and **hard-blocks** the operation if they match |
| 🔍 **Filesystem detection before format** | `setup_secondary_disk` checks for an existing filesystem via `lsblk` first — a pre-formatted drive with data is **never** silently reformatted |
| ✅ **Confirmation prompts** | Every destructive action (formatting a disk, zero-filling, deleting an orphaned snapshot) requires an explicit `y/N` confirmation |
| 🔎 **Registry cross-check before deletion** | Orphaned snapshot detection only flags `.vdi` files that are physically present **and** absent from VirtualBox's own media registry — never a randomly-selected file |
| 🧩 **Safe container pruning tiers** | Build-cache-only pruning is offered as a non-destructive first option, separate from the full system prune |
| 🔐 **Scoped elevation** | Windows scripts only request Administrator rights for Stage 2 (hypervisor CLI access) — Stage 1 never needs elevated Windows privileges |

---

## 📁 Repository Structure

```text
Disk_CleanUp_Project/
└── My_Custom_VM_Cleaning_Wizard/
    ├── 🚀 autorun.sh                    # Universal master launcher (Linux)
    ├── 🚀 autorun.bat                   # Universal master launcher (Windows, self-elevating)
    ├── 📦 install.sh                    # Registers 'clean-wizard' as a global command
    ├── 📖 README.md
    ├── 🐧 linux/
    │   └── vm-space-wizard.sh           # Stage 1: Linux system & container engine
    └── 🪟 modules/
        ├── vm-space-wizard.ps1          # Stage 2: Windows master entry point
        ├── virtualbox-engine.ps1        # VirtualBox VDI compaction & snapshot audit
        ├── vmware-engine.ps1            # VMware VMDK shrink engine
        └── banner.txt                   # ASCII banner used by autorun.bat
```

**Tech stack:** Bash · Windows PowerShell · Batch

---

## 🔍 What Runs Under the Hood

| Action | What actually executes |
|---|---|
| Container build-cache prune | `docker builder prune -f` / `podman builder prune -f` |
| Full container deep clean | `docker system prune -a --volumes -f` / `podman system prune -a --volumes -f` |
| OS cache cleanup | `apt-get clean && apt-get autoremove -y` (or the `dnf`/`yum` equivalent) |
| Log cleanup | `journalctl --vacuum-time=3d` |
| Secondary disk mount | `mkfs.ext4` (if needed) → `mount` → UUID entry appended to `/etc/fstab` |
| Podman storage repoint | Writes `graphroot` into `~/.config/containers/storage.conf` |
| Zero-fill | `dd if=/dev/zero of=/tmp/zero.fill bs=1M` until the disk fills, then removes the fill file |
| VDI orphan audit | Diffs `VBoxManage list hdds` against every `.vdi` under `%USERPROFILE%\VirtualBox VMs` |
| VDI compaction | `VBoxManage modifymedium disk <path> --compact` |
| Global CLI install | `ln -sf linux/vm-space-wizard.sh /usr/local/bin/clean-wizard` |

---

## 🩺 FAQ & Troubleshooting

<details>
<summary><b>❓ I ran Stage 1 but my Windows disk file didn't shrink — why?</b></summary>

<br/>

Stage 1 only *prepares* the disk (cleans + zero-fills) and shuts the VM down. You still need to run **Stage 2 on the Windows host** (`autorun.bat` → Option 2) to actually compact the `.vdi`/`.vmdk` file. Compaction can only happen while the VM is powered off and from the host side.

</details>

<details>
<summary><b>⚠️ The secondary disk setup refused my selected drive</b></summary>

<br/>

That's the root-drive protection working as intended — you selected the disk that holds your active Linux OS. Pick a genuinely secondary/attached virtual disk instead. Use the in-menu VirtualBox/VMware attachment guide if you haven't created one yet.

</details>

<details>
<summary><b>🪟 "Could not locate vm-space-wizard.ps1"</b></summary>

<br/>

Ensure the repository's folder structure is intact — the script expects to find its module files inside `modules/`. Re-clone the repository if files were moved or partially downloaded.

</details>

<details>
<summary><b>🐳 Podman commands aren't running</b></summary>

<br/>

All Podman operations are wrapped in `command -v podman &>/dev/null` checks and fail silently if Podman isn't installed — only Docker will run. Install Podman if you need both engines pruned.

</details>

<details>
<summary><b>🔐 Why does Stage 2 need Administrator rights?</b></summary>

<br/>

`VBoxManage.exe` and hypervisor disk compaction require elevated access to read and modify virtual disk files on the host filesystem. `autorun.bat` requests this automatically via `net session` detection and a `RunAs` relaunch.

</details>

---

## 🧭 Roadmap

- [ ] Add native macOS host support (VMware Fusion)
- [ ] Dry-run / preview mode for destructive operations
- [ ] Progress bars for zero-fill and compaction stages
- [ ] Add a `LICENSE` file and tagged GitHub Releases
- [ ] Scheduled/automated maintenance mode

---

## 🤝 Contributing

Contributions, feature requests, and issue reports are welcome.

1. Fork the repository and create a branch: `feature/your-idea` or `fix/your-bug`
2. Keep destructive operations behind explicit confirmation prompts
3. Test changes on at least one supported distro and one hypervisor before submitting
4. Open a Pull Request describing what changed and how you tested it

---

## 👤 Author

<div align="center">

### **Saleem Ali**
*Open-source DevOps/DevSecOps contributor · AIOps student · builder of practical automation tools*

[![GitHub](https://img.shields.io/badge/GitHub-ali4210-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/ali4210)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Saleem%20Ali-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/saleem-ali-189719325/)

*If VM Space Wizard saved you disk space, consider giving the repo a ⭐*

</div>

---

## 📄 License

Distributed under the **MIT License**.