# 🧙‍♂️ VM Space Wizard

An automated, cross-platform CLI utility suite designed to clean virtual system bloat, offload Docker & Podman runtimes to secondary drives, zero-fill unallocated storage blocks, and compact VirtualBox `.vdi` disk files on Windows hosts.

## 🚀 Features
- **Universal Linux Cleanup:** Supports Debian, Ubuntu, Kali, CentOS, RHEL, Fedora, and Rocky Linux.
- **Granular Container Prune:** Custom selection for Docker/Podman build caches, dangling images, unattached volumes, and stopped containers.
- **Secondary Drive Offloader:** Mounts secondary storage drives and routes `/var/lib/docker` and Podman `graphroot` automatically.
- **VDI Compaction Pipeline:** Zero-fills free space for physical host drive reclamation.
- **Orphaned Snapshot Auditor:** Scans and removes unregistered/corrupted `.vdi` snapshot files on Windows.

## 📁 Repository Structure
```text
My_Custom_VM_Cleaning_Wizard/
├── autorun.sh           # Linux Master Launcher
├── autorun.bat          # Windows Master Launcher (Double-Clickable)
├── vm-space-wizard.sh   # Stage 1: Linux Cleanup & Storage Engine
├── vm-space-wizard.ps1  # Stage 2: Windows Host VDI Compaction Engine
└── README.md
```






## 🛠️  Usage

Stage 1: Inside Linux Virtual Machine
```
chmod +x autorun.sh
./autorun.sh
```

Choose Stage 1 -> Perform cleanup, secondary storage setup, or zero-fill prep. The VM will gracefully shut down upon completion.


## Stage 2: On Windows Host PC
1. Open Windows Explorer and navigate to the project directory.

2. Double-click autorun.bat (Requests Admin permissions automatically).

3. Confirm Stage 1 completion and select Stage 2 to compact .vdi files.

## 📄 License

MIT License - Open for community contributions!

---

## Stage 3: Initialize Git & Push to GitHub

### Step 1: Create a New Repository on GitHub
1. Go to [GitHub.com](https://github.com) and click the **`+`** icon in the top right -> **New repository**.
2. Name the repository: `vm-space-wizard` (or `Disk_CleanUp_Project`).
3. Description: *"Cross-platform VM disk cleanup, container offloader & VirtualBox VDI compaction tool."*
4. Keep it **Public**.
5. Leave "Add a README file" **UNCHECKED** (since we created our own).
6. Click **Create repository**.

### Step 2: Initialize & Push from Kali Terminal
Back in your Kali Linux terminal inside `~/Disk_CleanUp_Project`:

```bash
# 1. Initialize local git repository
git init

# 2. Add all project files
git add .

# 3. Create initial commit
git commit -m "Initial commit: Production release of vm-space-wizard tool suite"

# 4. Set active branch to main
git branch -M main

# 5. Link local repo to your remote GitHub repo
# (Replace 'YOUR-USERNAME' and 'REPO-NAME' with your actual GitHub info)
git remote add origin https://github.com/YOUR-USERNAME/REPO-NAME.git

# 6. Push code to GitHub
git push -u origin main


(When prompted for your GitHub password, enter your GitHub Personal Access Token (PAT) or SSH key).
