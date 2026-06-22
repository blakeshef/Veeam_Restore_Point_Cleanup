# VEEAM STALE RESTORE-POINT CLEANUP TOOLKIT

DISCLAIMER: This is an unofficial community tool. It is not developed, supported, or endorsed by Veeam Software. No warranty is provided. Use at your own risk.

A modular set of PowerShell scripts that identify and safely remove stale restore points from a Veeam Backup & Replication environment across multiple workload types.

The toolkit consists of a single launcher that connects to a VBR/VSA server, prompts for a cutoff date, and then runs workload-specific cleanup scripts on demand. You connect once and enter the date once. Every workload script reuses that information.


DOCUMENT INFORMATION
====================

Toolkit Name: Veeam Stale Restore-Point Cleanup Toolkit
Maintainer: Zach Chamberlin
Last Updated: 2026-06-22
Version: 1.1

Notes:
- Validate the target workload before deleting restore points.
- Review generated CSV output before cleanup.
- Run with diagnostic mode enabled when testing in a new environment.
- Please review and test all changes in a non-production environment before using this toolkit against a live VBR/VSA server


TABLE OF CONTENTS
=================

1. What This Toolkit Does
2. Folder Layout
3. Supported Workloads
4. Prerequisites
5. Running the Toolkit
6. Cutoff Date Behavior
7. What Happens When a Workload Is Selected
8. Standalone Use Without the Launcher
9. CSV Output Files
10. Safety Features
11. Diagnostic Mode
12. Troubleshooting
13. Adding More Workload Scripts
14. Best Practices
15. Questions or Issues


1. WHAT THIS TOOLKIT DOES
=========================

For each supported workload, the cleanup script will:

1. Scan all backup jobs of that type on the VBR server.
2. Identify every restore point older than the cutoff date you specified.
3. Write a CSV report, but only if stale restore points were actually found.
4. Display an interactive cleanup menu where you can choose which objects to clean up.
5. Show you exactly what will be deleted and require an explicit YES confirmation before removing anything.

Nothing is deleted without explicit confirmation. The script will not modify or remove restore points newer than the cutoff date.


2. FOLDER LAYOUT
================

Veeam_Cleanup
|
+-- README.txt
+-- Veeam-Cleanup-Launcher.ps1
|
+-- Cleanup_Scripts
    +-- Cleanup_Stale_VMware_Backups_V3.ps1
    +-- Cleanup_Stale_Proxmox_Backups_V3.ps1
    +-- Cleanup_Stale_VAW_VAL_Backups_V3.ps1
    +-- Cleanup_Stale_Backup_Copies_V3.ps1
    +-- Cleanup_Stale_HPE_Morpheus_Backups_V3.ps1
    +-- Cleanup_Stale_HyperV_Backups_V3.ps1
    +-- Cleanup_Stale_Nutanix_AHV_Backups_V3.ps1

The launcher auto-detects its own folder, so you can place the entire Veeam_Cleanup folder anywhere on the system. As long as the Cleanup_Scripts subfolder stays next to the launcher, it will work.


3. SUPPORTED WORKLOADS
======================

Option    Workload         Detects
------    --------         -------
1         VMware           VMware vSphere backups
2         Proxmox          Proxmox VE backups
3         Veeam Agent      Veeam Agent for Windows and Linux
4         Backup Copy      Backup Copy job restore points
5         HPE Morpheus     HPE Morpheus VME backups
6         Hyper-V          Microsoft Hyper-V backups
7         Nutanix AHV      Nutanix AHV backups

Each workload script is self-contained and follows the same structure, so they all behave consistently.


4. PREREQUISITES
================

Before running:

1. The Veeam Backup & Replication PowerShell module must be installed on the machine running the scripts. This comes automatically when you install the Veeam Console.
2. Network access is required from your machine to the target VBR server or VSA.
3. Credentials must have permission to view and delete restore points on the VBR server.
4. Use PowerShell 5.1 for V12 and PowerShell 7 for V13.
5. The script files must be unblocked. Windows can flag scripts copied from another machine.

If you see an error such as "not recognized as a name of a cmdlet" when launching, run:

Get-ChildItem 'C:\path\to\Veeam_Cleanup' -Recurse -Filter *.ps1 | Unblock-File


5. RUNNING THE TOOLKIT
======================

1. Open a PowerShell window as a user with rights to manage Veeam.
2. Navigate into the Veeam_Cleanup folder.
3. Run the launcher:

.\Veeam-Cleanup-Launcher.ps1

You will be prompted for:

1. Target type:
   [1] VSA / v13 appliance, port 443
   [2] Windows VBR server, port 9392

2. VBR/VSA server:
   Enter the FQDN or IP address.

3. Credentials:
   Enter the username and password. The password is kept as a SecureString only and is never written to disk.

4. Cutoff date:
   Anything older than this date is considered stale. Use format yyyy-MM-dd, or press Enter to use today's date.

Then the workload menu appears:

============================================
   Veeam Cleanup - Select a Workload
============================================

  1. VMware
  2. Proxmox
  3. Agent
  4. Backup Copy
  5. Morpheus
  6. Hyper-V
  7. Nutanix AHV

  D. Change cutoff date  (current: 2026-06-19)
  Q. Quit

Select option:

Pick a workload by typing its number and pressing Enter.

After the workload script finishes, you are returned to this menu. You can run as many workloads as you want without reconnecting or re-entering the date.


6. CUTOFF DATE BEHAVIOR
=======================

The cutoff date is exclusive. Restore points are flagged stale if they were created strictly before the cutoff, meaning older than midnight on that date.

Example with cutoff 2026-06-19:

Restore point creation time    Considered stale?
---------------------------    -----------------
2025-12-15, any time           Yes
2026-06-18 23:55               Yes
2026-06-19 00:00:00            No, equals cutoff
2026-06-19 02:00               No
2026-06-20, any time           No

This is conservative by design. The cutoff date itself is protected, so you cannot accidentally delete same-day data.

Changing the cutoff mid-session:

You can change the cutoff at any time during a session by picking D from the menu. The next workload you run will use the new date. The original connection stays active.

You can also type "today" at the change-date prompt as a shortcut for the current date.


7. WHAT HAPPENS WHEN A WORKLOAD IS SELECTED
===========================================

The selected script runs through these steps:

1. Scans all backups of that workload type on the VBR server.
2. Identifies stale restore points. Only restore points strictly before the cutoff are flagged. Newer ones are never touched.
3. Writes a CSV report at C:\Temp, but only if stale items were found.
4. Displays a numbered cleanup menu listing every stale object found.
5. Waits for you to pick a row to clean up, or Q to quit and return to the workload menu.
6. Shows the restore points that would be deleted and waits for YES confirmation.
7. Deletes only the stale restore points for the selected object.
8. Updates the CSV to remove the cleaned object, then continues the cleanup loop.

If no stale items are found, the script prints a friendly message and returns to the workload menu. No CSV is created, and nothing is touched.


8. STANDALONE USE WITHOUT THE LAUNCHER
======================================

Each workload script can also be run on its own without the launcher.

When run standalone:

1. The script will prompt for VBR/VSA connection details.
2. It uses the hardcoded $CutoffDate value at the top of the script. You can edit this directly.

This is useful for ad-hoc cleanup on a single workload type, or for scheduled tasks that target a specific workload.

The script detects whether the launcher already connected by checking $global:WrapperConnected. If the launcher has not set it, the script behaves like a fully self-contained tool.


9. CSV OUTPUT FILES
===================

Each workload writes its report to a separate CSV at C:\Temp.

Workload         CSV file
--------         --------
VMware           Veeam-StaleVMwareVMs.csv
Proxmox          Veeam-StaleProxmoxVMs.csv
Veeam Agent      Veeam-StaleAgentBackups.csv
Backup Copy      Veeam-StaleBackupCopy.csv
HPE Morpheus     Veeam-StaleMorpheusVMs.csv
Hyper-V          Veeam-StaleHyperVVMs.csv
Nutanix AHV      Veeam-StaleNutanixVMs.csv

Each CSV contains one row per stale object, with fields like:

- VMName
- JobName
- BackupName
- Repository
- LatestRestorePoint
- StalePointCount
- ObjectId

The CSV is only written when stale objects are actually found. If a run finds nothing, no CSV is created. Existing CSVs from previous runs are left alone.

The CSV is also updated automatically as you delete items during the cleanup loop. Once an object's old restore points are removed, that row is removed from the file.


10. SAFETY FEATURES
===================

The toolkit is designed to make accidental deletion difficult:

1. No automatic deletion.
   Every cleanup operation requires you to type YES in uppercase at a confirmation prompt.

2. Per-object selection.
   You choose which object to clean up, one row at a time.

3. Strict cutoff filter.
   Only restore points strictly older than the cutoff date are eligible for deletion.

4. Workload type check.
   Cleanups verify the selected backup is actually that type before proceeding.

5. No CSV side effects.
   Running a workload that finds nothing will not delete an existing CSV from a previous run.

6. Friendly cancel.
   Pressing Enter at any prompt without typing YES cancels that deletion and returns to the menu.


11. DIAGNOSTIC MODE
===================

Each workload script has an $EnableDiag variable near the top:

$EnableDiag = $false # set to $true to see diagnostic output

When set to $true, the script prints detailed magenta [DIAG] lines showing:

1. How many backups of that workload type were detected.
2. How many restore points each backup returned.
3. Each individual restore point's creation time and whether it is stale.
4. Total stale rows after grouping.

This is helpful for verifying that the script is seeing what you expect. Set it back to $false when you are done diagnosing.


12. TROUBLESHOOTING
===================

Issue:
"Could not load the Veeam.Backup.PowerShell module"

Resolution:
You need the Veeam Console or VBR installed on the machine running the scripts. The PowerShell module is included automatically.


Issue:
"Veeam PowerShell is not available in this session"

Resolution:
The module loaded but Connect-VBRServer is not available. This usually means a much older Veeam version is installed.


Issue:
"Failed to connect to VBR/VSA ..."

Resolution:
1. Verify the FQDN or IP address is correct.
2. Verify the credentials are correct.
3. Verify network connectivity.
4. Try Test-NetConnection with the correct port:

   Test-NetConnection -ComputerName <server> -Port 9392
   Test-NetConnection -ComputerName <server> -Port 443

5. Verify your account has permission to log into Veeam.


Issue:
"Not recognized as a name of a cmdlet, function, script file, or executable program"

Resolution:
This usually means the .ps1 files are blocked by Windows. Unblock them:

Get-ChildItem 'C:\path\to\Veeam_Cleanup' -Recurse -Filter *.ps1 | Unblock-File


Issue:
A workload reports "No Backup Jobs Were Found"

Resolution:
1. Verify those backup jobs actually exist on the VBR server.
2. Run the script with $EnableDiag = $true to see how the script is detecting jobs.


Issue:
Stale items are not appearing as expected

Resolution:
1. Confirm the cutoff date is correct, especially the year.
2. Run with $EnableDiag = $true to see exact creation times being compared.
3. Restore points equal to or newer than the cutoff are never flagged stale.


13. ADDING MORE WORKLOAD SCRIPTS
================================

To add a new workload type, copy one of the existing scripts. The Hyper-V or Nutanix AHV scripts are good templates.

Then update the following:

1. Change the detection regex to match the new platform or type strings.
2. Update the CSV path to a unique filename.
3. Update all workload labels in messages, for example from "Hyper-V" to "Your Workload".
4. Save the file in the Cleanup_Scripts folder.
5. Add it to the launcher's $ScriptMap block:

'8' = @{ Label = 'Your Workload'; File = 'Cleanup_Stale_YourWorkload_V3.ps1' }

That is it. The launcher picks up the new script automatically.


14. BEST PRACTICES
==================

1. Start with diagnostic mode the first time you run against a new environment. Verify the script sees the backups and creation times you expect.
2. Use a recent but past cutoff date to start, such as anything older than 30 days. This gives you predictable, conservative results.
3. Review the CSV before cleanup if you are acting on a large number of objects.
4. Run during a maintenance window if you are cleaning a lot of objects at once, since Veeam will be working in the background.
5. Keep a backup of your VBR configuration before doing large cleanup operations.


15. QUESTIONS OR ISSUES
=======================

If something behaves unexpectedly, run the affected workload with $EnableDiag = $true first. The output will usually pinpoint exactly what is happening.

Each script is self-contained and well-commented. Open one in a text editor or PowerShell ISE if you want to understand the flow.
