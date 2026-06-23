<p align="center">
  <strong>VEEAM STALE RESTORE-POINT CLEANUP TOOLKIT</strong>
</p>


<p align="center">
  <a href="https://github.com/STTGL-01/Veeam_Restore_Point_Cleanup">
    <strong>Download Latest Release</strong>
  </a>
  ·
  <a href="https://github.com/STTGL-01/Veeam_Restore_Point_Cleanup">
    <strong>Report an Issue</strong>
  </a>
</p>

---

> [!NOTE]  
> This is an unofficial community tool. It is not developed, supported, or endorsed by Veeam Software.
> No warranty is provided. Use at your own risk.

---



# VEEAM STALE RESTORE-POINT CLEANUP TOOLKIT

A modular PowerShell toolkit for identifying and safely removing stale restore points across multiple Veeam Backup & Replication workloads.

The toolkit uses a centralized launcher that:
- Establishes a single connection to a VBR or VSA server  
- Prompts once for a cutoff date  
- Executes workload-specific cleanup scripts on demand  

You connect once and define the cutoff once — all workloads reuse that session.

---

## Document Information

- **Toolkit Name:** Veeam Stale Restore-Point Cleanup Toolkit  
- **Maintainer:** Zach Chamberlin  
- **Version:** 1.1  
- **Last Updated:** 2026-06-22  

### Notes

- Validate the target workload before deleting restore points  
- Review CSV output before performing cleanup  
- Enable diagnostic mode when testing in new environments  
- Always test in non-production environments before running against live VBR/VSA systems  

---

## Table of Contents

1. What This Toolkit Does  
2. Folder Layout  
3. Supported Workloads  
4. Prerequisites  
5. Running the Toolkit  
6. Cutoff Date Behavior  
7. Workload Execution Flow  
8. Standalone Usage  
9. CSV Output Files  
10. Safety Features  
11. Diagnostic Mode  
12. Troubleshooting  
13. Extending the Toolkit  
14. Best Practices  

---

## What This Toolkit Does

For each supported workload, the toolkit:

1. Scans all backup jobs of that type  
2. Identifies restore points older than the defined cutoff date  
3. Generates a CSV report (only if stale restore points are found)  
4. Provides an interactive cleanup menu  
5. Requires explicit `YES` confirmation before deletion  

**No restore points are deleted automatically.**  
Restore points newer than the cutoff date are never modified.

---


## Folder Layout

```text
Veeam_Cleanup
│
├── README.md
├── Veeam-Cleanup-Launcher.ps1
└── Cleanup_Scripts
    ├── Cleanup_Stale_VMware_Backups_V3.ps1
    ├── Cleanup_Stale_Proxmox_Backups_V3.ps1
    ├── Cleanup_Stale_VAW_VAL_Backups_V3.ps1
    ├── Cleanup_Stale_Backup_Copies_V3.ps1
    ├── Cleanup_Stale_HPE_Morpheus_Backups_V3.ps1
    ├── Cleanup_Stale_HyperV_Backups_V3.ps1
    └── Cleanup_Stale_Nutanix_AHV_Backups_V3.ps1
```


The launcher auto-detects its location, so the toolkit can be placed anywhere as long as the `Cleanup_Scripts` folder remains alongside it.

---

## Supported Workloads

| Option | Workload       | Description                          |
|--------|--------------|--------------------------------------|
| 1      | VMware       | VMware vSphere backups              |
| 2      | Proxmox      | Proxmox VE backups                  |
| 3      | Veeam Agent  | Windows & Linux agent backups       |
| 4      | Backup Copy  | Backup Copy job restore points      |
| 5      | HPE Morpheus | Morpheus VME backups                |
| 6      | Hyper-V      | Microsoft Hyper-V backups           |
| 7      | Nutanix AHV  | Nutanix AHV backups                 |

Each workload script is modular and follows a consistent structure.

---

## Prerequisites

- Veeam Backup & Replication PowerShell module (included with Veeam Console)  
- Network access to the VBR / VSA server  
- Credentials with sufficient permissions  
- PowerShell 5.1 (V12) or PowerShell 7 (V13 recommended)  

If scripts are blocked after download:

```powershell
Get-ChildItem 'C:\path\to\Veeam_Cleanup' -Recurse -Filter *.ps1 | Unblock-File
```

---

## Running the Toolkit

```powershell
.\Veeam-Cleanup-Launcher.ps1
```
You will be prompted for:

- Target type (VSA / Windows VBR)
- Server address (FQDN or IP)
- Credentials (secure, not stored)
- Cutoff date (yyyy-MM-dd, or Enter for today)

You will then be presented with a workload selection menu.

---

## Cutoff Date Behavior

The cutoff date is exclusive.
Restore points are considered stale only if created before the cutoff date.
Example with cutoff 2026-06-19:

✅ 2026-06-18 → Stale
❌ 2026-06-19 → Not stale
❌ 2026-06-20 → Not stale

This ensures same-day restore points are always protected.

---

## Workload Execution Flow

Each workload script performs:

1. Backup enumeration
2. Restore point evaluation
3. CSV report creation (if needed)
4. Interactive selection menu
5. Deletion preview
6. Confirmation prompt (YES required)
7. Targeted cleanup

If no stale data is found, no changes are made.

---

## Standalone Usage

Each script can run independently:

- Prompts for connection
- Uses local $CutoffDate value

Useful for targeted or scheduled operations.

---

## CSV Output Files

Reports are written to:

```
C:\Temp\
```
Each workload generates its own file with fields such as:

- VMName
- JobName
- BackupName
- Repository
- LatestRestorePoint
- StalePointCount

CSV files are only created when stale data is found.

---

## Safety Features

- No automatic deletion
- YES confirmation required
- Per-object selection
- Strict cutoff enforcement
- Workload validation checks
- Safe cancellation at any prompt

---

## Diagnostic Mode

Enable detailed output:

```powershell
$EnableDiag = $true
```
Provides insight into:

- Backup detection
- Restore point evaluation
- Stale grouping logic

Disable after testing.

---

## Troubleshooting

**Module not found**
Install Veeam Console
**Connection issues**
Verify server, credentials, and network connectivity
**Scripts not recognized**
Unblock files
**Missing data**
Enable diagnostic mode

---

## Extending the Toolkit

To add a new workload:

1. Copy an existing script
2. Update detection logic
3. Define a new CSV output file
4. Update labels and messaging
5. Add entry to $ScriptMap

## Best Practices

- Start with diagnostic mode
- Use conservative cutoff dates
- Review CSV output before deletion
- Run during maintenance windows
- Maintain backups before large cleanup operations


