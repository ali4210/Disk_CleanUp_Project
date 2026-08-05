# 🧹 Disk CleanUp Project

Welcome to the **Disk CleanUp Project** repository! 

This repository houses **VM Space Wizard (V2.1)**—an open-source, cross-platform DevOps utility suite designed to safely clean Linux virtual machines, offload heavy Docker/Podman runtimes to secondary drives, and compact physical virtual disks (`.vdi` & `.vmdk`) on Windows host PCs without snapshot corruption.

---

## 🚀 Quick Start & Project Access

All active tool source code, launchers, and modules are organized inside the **`My_Custom_VM_Cleaning_Wizard/`** directory.

👉 **[Click Here to Enter `My_Custom_VM_Cleaning_Wizard`](./My_Custom_VM_Cleaning_Wizard)**

---

## 📁 Repository Overview

```text
Disk_CleanUp_Project/
│
├── README.md                          <-- (You are here: Main Landing Guide)
│
└── My_Custom_VM_Cleaning_Wizard/      <-- 📂 MAIN TOOL SUITE
    ├── autorun.sh                     # Linux Master Launcher
    ├── autorun.bat                    # Windows Master Launcher (Double-Clickable)
    ├── README.md                      # Detailed Technical Documentation & Usage
    ├── linux/
    │   └── vm-space-wizard.sh         # Stage 1: Linux System & Container Engine
    └── modules/
        ├── vm-space-wizard.ps1        # Stage 2: Windows Master Entry Point
        ├── virtualbox-engine.ps1      # VirtualBox VDI & Snapshot Engine
        └── vmware-engine.ps1          # VMware VMDK Shrink Engine

```

---

## 🛠️ Summary of Included Tools

Inside `My_Custom_VM_Cleaning_Wizard`, you will find:

1. **Linux Guest Engine (`linux/vm-space-wizard.sh`):**
* Package manager cleaning (`apt`, `dnf`, `yum`) and system log vacuuming.
* Granular Docker & Podman container pruning (build caches, unattached volumes, dangling images).
* Secondary storage drive offloader with GUI setup instructions for both VirtualBox and VMware.
* Zero-fill sequence for host storage reclamation prep.


2. **Windows Host Engine (`modules/vm-space-wizard.ps1` & `autorun.bat`):**
* Universal hypervisor compaction supporting **Oracle VirtualBox (`.vdi`)** and **VMware Workstation/Player (`.vmdk`)**.
* VirtualBox Orphaned Snapshot Auditor to detect and safely clean disconnected/corrupted snapshot files.
* Self-elevating batch launcher for seamless double-click execution.



---

## 📖 Detailed Instructions

For step-by-step setup guides, prerequisites, and detailed terminal workflows, please open the full project documentation:

➡ **[Read Full Documentation inside `My_Custom_VM_Cleaning_Wizard/README.md](https://www.google.com/search?q=./My_Custom_VM_Cleaning_Wizard/README.md)**`

```

---

## How to Commit & Push This Update to GitHub

Run these commands in your Kali Linux terminal inside `~/Disk_CleanUp_Project`:

```bash
# 1. Stage the root README file
git add README.md

# 2. Commit the change
git commit -m "Docs: Add root landing README guide pointing to My_Custom_VM_Cleaning_Wizard"

# 3. Push to GitHub
git push origin main

```

