# 🧙‍♂️ VM Space Wizard (V2.1 Universal Release)

An automated, cross-platform CLI utility suite designed to perform deep system maintenance inside Linux virtual machines, offload heavy container storage, zero-fill unallocated storage blocks, and safely compact physical virtual disk files (`.vdi` & `.vmdk`) on Windows hosts.

---

## 💡 Why This Tool Was Built

Deleting files inside a Linux guest OS **never** automatically shrinks the physical virtual disk file on your Windows host. In an attempt to reclaim disk space manually, many developers delete `.vdi` or `.vmdk` snapshot files directly from Windows File Explorer. 

This dangerous practice breaks the snapshot registry chain, corrupting the virtual machine and leading to catastrophic data loss.

**VM Space Wizard** solves this problem by providing a safe, multi-stage pipeline:
1. **Stage 1 (Linux Guest):** Deep package cleaning, customizable container pruning, optional secondary storage offloading, and unallocated disk space zero-filling.
2. **Stage 2 (Windows Host):** Automated snapshot auditing and native hypervisor disk compaction/shrinking via CLI engines (`VBoxManage` & `vmware-vdiskmanager`).

---

## 🚀 Key Features

### 🐧 Linux Guest Engine (`linux/vm-space-wizard.sh`)
- **Universal Package Maintenance:** Supports Debian, Ubuntu, Kali Linux, CentOS, RHEL, Fedora, and Rocky Linux.
- **Granular Container Pruning:** Selectively prune Docker & Podman build caches, unattached volumes, stopped containers, or dangling images.
- **Secondary Drive Offloader:** Safely formats and routes `/var/lib/docker` and Podman `graphroot` to external or secondary virtual drives without data destruction. Includes step-by-step GUI attachment guides for both VirtualBox and VMware.
- **Zero-Fill Sequence:** Fills unallocated disk blocks with zeroes to prepare the virtual disk for host compaction.

### 🪟 Windows Host Engine (`modules/vm-space-wizard.ps1` & `autorun.bat`)
- **Multi-Hypervisor Support:** Fully supports **Oracle VirtualBox (`.vdi`)** and **VMware Workstation / Player (`.vmdk`)**.
- **Orphaned Snapshot Auditor (VirtualBox):** Scans for physical `.vdi` files disconnected from the VirtualBox media registry to prevent corruption and reclaim storage.
- **Automated UAC Elevation:** Master launchers handle Administrator elevation and execution policy bypass automatically.
- **Modular Architecture:** Clean separation of hypervisor-specific CLI logic into a dedicated `modules/` directory.

---

## 📁 Repository Structure

```text
Disk_CleanUp_Project/
├── autorun.sh                   # Universal Master Launcher (Linux)
├── autorun.bat                  # Universal Master Launcher (Windows)
├── README.md                    # Project Documentation
├── linux/
│   └── vm-space-wizard.sh       # Stage 1: Linux System & Container Engine
└── modules/
    ├── vm-space-wizard.ps1      # Stage 2: Windows Master Entry Point
    ├── virtualbox-engine.ps1    # VirtualBox VDI & Snapshot Engine
    └── vmware-engine.ps1        # VMware VMDK Shrink Engine

---

## 🛠️ Complete Workflow & Usage

### 📍 Stage 1: Inside Your Linux Virtual Machine

1. Transfer or clone the repository into your Linux VM.
2. Open a terminal, make the launcher executable, and run it:
```bash
chmod +x autorun.sh
./autorun.sh

```


3. Select **Option 1 [Running inside LINUX GUEST]**.
4. Execute desired tasks (System Cleanup, Container Pruning, or Secondary Disk Setup).
5. Select **Option 4 (FULL CLEANUP + Zero-Fill)**. Upon completion, the script will gracefully shut down your Linux VM.

---

### 📍 Stage 2: On Your Windows Host PC

1. Open Windows Explorer and navigate to your project directory.
2. **Double-click `autorun.bat**` (it will automatically request Administrative privileges).
3. Confirm that Stage 1 has been completed inside the VM.
4. Select **Option 2 (Stage 2: Windows Host VDI / VMDK Compaction)**.
5. Select your active Hypervisor:
* **Option 1 [Oracle VirtualBox]:** Run snapshot audit and compact registered `.vdi` disks.
* **Option 2 [VMware Workstation / Player]:** Scan for `.vmdk` disks and execute the shrink process.



---

## 🛠️ Safety Features & Guardrails

* **Root Drive Protection:** The secondary storage offloader automatically blocks users from selecting the active Linux root (`/`) OS drive.
* **Filesystem Verification:** Inspects existing drive formats using `lsblk` before mounting, preserving user data on pre-formatted storage drives.
* **Interactive Prompting:** Confirms actions before executing destructive file deletions or full system prunes.

---

## 🤝 Contributing

Contributions, feature requests, and issue reports are welcome! Feel free to check the issues page if you want to contribute.

---

## 📄 License

This project is open-source under the **MIT License**.

```

---

==>> FINAL GIT COMMANDS TO PUSH EVERYTHING

Now you can commit all updated files and push the entire V2.1 suite live to GitHub:

```bash
git add .
git commit -m "Release V2.1: Modular directory structure, VMware guidelines, and universal README"
git push origin main

```

Your project is now 100% complete, fully modularized, robust, and ready for the world!
