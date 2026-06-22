# ============================================================
# Veeam Stale Restore-Point Report + Cleanup — Backup Copy Jobs
# ============================================================

# ---- Settings ----

if ($global:WrapperCutoffDate) {
    [datetime]$CutoffDate = $global:WrapperCutoffDate
} else {
    [datetime]$CutoffDate = '2026-06-20'   # fallback when run standalone
}

$CsvPath              = 'C:\Temp\Veeam-StaleBackupCopy.csv'
$EnableDiag           = $false   # set to $true to see diagnostic output

# ---- Load Veeam PowerShell ----
try {
    Import-Module Veeam.Backup.PowerShell -ErrorAction Stop
} catch {
    throw "Could not load the Veeam.Backup.PowerShell module: $_"
}

if (-not (Get-Command Connect-VBRServer -ErrorAction SilentlyContinue)) {
    throw "Veeam PowerShell is not available in this session."
}

# ---- Connect to the target VBR / VSA ----
if (-not $global:WrapperConnected) {

    $VbrType = ''
    while ($VbrType -notin @('1','2')) {
        Write-Host ""
        Write-Host "Target type:" -ForegroundColor Cyan
        Write-Host "  [1] VSA / v13 appliance   (port 443)"
        Write-Host "  [2] Windows VBR server    (port 9392)"
        $VbrType = (Read-Host "Select 1 or 2").Trim()
    }
    $VbrPort = if ($VbrType -eq '1') { 443 } else { 9392 }

    $VbrServer = (Read-Host "Enter the VBR/VSA FQDN or IP").Trim()
    if (-not $VbrServer) {
        throw "No VBR/VSA address entered."
    }

    $cred = Get-Credential -Message "Credentials for VBR/VSA '$VbrServer'"
    if (-not $cred) {
        throw "No credentials supplied for '$VbrServer'."
    }

    try {
        Connect-VBRServer -Server $VbrServer -Port $VbrPort -Credential $cred -ErrorAction Stop
    } catch {
        throw "Failed to connect to VBR/VSA '$VbrServer': $_"
    }

    Write-Host "Connected to VBR/VSA : $VbrServer (port $VbrPort)" -ForegroundColor Cyan
}

Write-Host "Cut-off date         : $($CutoffDate.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

function Get-RawPlatform {
    param($Backup)
    try { return $Backup.BackupPlatform.Platform.ToString() } catch { return '<unknown>' }
}

function Get-RawType {
    param($Backup)
    try { return $Backup.TypeToString } catch { return '' }
}

function Resolve-RepoInfo {
    param($Repo)

    if (-not $Repo) {
        return [pscustomobject]@{
            Name = '<unknown>'
            Type = '<unknown>'
        }
    }

    $name = $Repo.Name
    $type = '<unknown>'

    try { $type = $Repo.Type.ToString() } catch { }

    try {
        if ($Repo.PSObject.Properties['IsImmutabilityEnabled'] -and $Repo.IsImmutabilityEnabled) {
            $type = "$type (Immutable)"
        }
    } catch { }

    if ($type -match 'ScaleOut|SOBR') {
        $type = 'Scale-Out Repository'
    }

    return [pscustomobject]@{
        Name = $name
        Type = $type
    }
}

# ✅ Robust Backup Copy retrieval — collects from all available methods
function Get-BackupCopyRestorePoints {
    param($Backup)

    $allPoints = @()

    # Method 1: Standard call
    try {
        $rp = Get-VBRRestorePoint -Backup $Backup -ErrorAction Stop
        if ($rp) { $allPoints += $rp }
    } catch { }

    # Method 2: Wildcard fallback
    try {
        $rp = Get-VBRRestorePoint -Backup $Backup -Name "*" -ErrorAction Stop
        if ($rp) { $allPoints += $rp }
    } catch { }

    # Method 3: Child backups
    try {
        $children = $Backup.FindChildBackups()
        if ($children) {
            foreach ($child in $children) {
                try {
                    $childRp = Get-VBRRestorePoint -Backup $child -ErrorAction Stop
                    if ($childRp) { $allPoints += $childRp }
                } catch { }
            }
        }
    } catch { }

    # Deduplicate by ObjectId + CreationTime
    if ($allPoints.Count -gt 0) {
        $unique = $allPoints | Sort-Object -Property `
            @{Expression={ try { "$($_.ObjectId)" } catch { '' } }}, `
            @{Expression={ try { $_.CreationTime } catch { :MinValue } }} -Unique

        return @($unique)
    }

    return $null
}

function Get-SourceJobName {
    param($Backup)

    try {
        if ($Backup.PSObject.Properties['ParentBackupName'] -and $Backup.ParentBackupName) {
            return $Backup.ParentBackupName
        }
    } catch { }

    try {
        if ($Backup.PSObject.Properties['OriginalJobName'] -and $Backup.OriginalJobName) {
            return $Backup.OriginalJobName
        }
    } catch { }

    try {
        if ($Backup.PSObject.Methods['FindParent']) {
            $parent = $Backup.FindParent()
            if ($parent -and $parent.JobName) { return $parent.JobName }
        }
    } catch { }

    return '<unknown>'
}

# ------------------------------------------------------------
# Collect Backup Copy jobs
# ------------------------------------------------------------

$results             = New-Object System.Collections.Generic.List[object]
$encryptedBackups    = New-Object System.Collections.Generic.List[object]
$inaccessibleBackups = New-Object System.Collections.Generic.List[object]

$copyBackups = @(Get-VBRBackup | Where-Object {
    ($_.TypeToString -match 'Backup Copy') -or
    ($_.BackupPlatform.Platform.ToString() -match 'SimpleBackupCopyPolicy|BackupCopy')
})

if ($EnableDiag) {
    Write-Host ""
    Write-Host "[DIAG] Backup Copy jobs detected: $($copyBackups.Count)" -ForegroundColor Magenta
}

if ($copyBackups.Count -gt 0) {
    foreach ($backup in $copyBackups) {

        $rawPlatform = Get-RawPlatform -Backup $backup
        $rawType     = Get-RawType -Backup $backup
        $sourceJob   = Get-SourceJobName -Backup $backup

        $repoInfo = $null
        try { $repoInfo = Resolve-RepoInfo -Repo $backup.GetRepository() }
        catch { $repoInfo = [pscustomobject]@{ Name='<error>'; Type='<error>' } }

        $allPoints = Get-BackupCopyRestorePoints -Backup $backup

        if ($EnableDiag) {
            Write-Host ""
            Write-Host "[DIAG] Backup: $($backup.Name) (Job: $($backup.JobName))" -ForegroundColor Magenta
            if ($allPoints) {
                Write-Host "[DIAG]   Total restore points returned: $($allPoints.Count)" -ForegroundColor Magenta
            } else {
                Write-Host "[DIAG]   Total restore points returned: 0 (or null)" -ForegroundColor Magenta
            }
        }

        if (-not $allPoints) {
            try {
                Get-VBRRestorePoint -Backup $backup -ErrorAction Stop | Out-Null
            } catch {
                if ($_.Exception.Message -match 'encrypted') {
                    $encryptedBackups.Add([pscustomobject]@{
                        BackupName = $backup.Name
                        JobName    = $backup.JobName
                    }) | Out-Null
                } else {
                    $inaccessibleBackups.Add([pscustomobject]@{
                        BackupName = $backup.Name
                        JobName    = $backup.JobName
                        Reason     = $_.Exception.Message
                    }) | Out-Null
                }
            }
            continue
        }

        $groups = $allPoints | Group-Object {
            $objId = ''
            try { if ($_.ObjectId) { $objId = $_.ObjectId.ToString() } } catch { }
            if ($objId -eq '') { $objId = '<no-objectid>' }

            $nameVal = ''
            try { $nameVal = $_.Name } catch { }
            if ($nameVal -eq '') {
                try { $nameVal = $_.VmName } catch { }
            }
            if ($nameVal -eq '') { $nameVal = '<no-name>' }

            "$objId|$nameVal"
        }

        if ($EnableDiag) {
            Write-Host "[DIAG]   Groups (unique objects): $($groups.Count)" -ForegroundColor Magenta
        }

        foreach ($g in $groups) {

            if ($EnableDiag) {
                Write-Host ""
                Write-Host "[DIAG]   Group: $($g.Name) — $($g.Group.Count) RP(s)" -ForegroundColor DarkMagenta
                foreach ($rp in $g.Group) {
                    $rpName = $null
                    $rpTimeShow = $null
                    try { $rpName = $rp.Name } catch { }
                    if ($rpName -eq '' -or $null -eq $rpName) {
                        try { $rpName = $rp.VmName } catch { }
                    }
                    try { $rpTimeShow = $rp.CreationTime } catch { }

                    $isStale = $rpTimeShow -and ($rpTimeShow -lt $CutoffDate)

                    Write-Host ("[DIAG]     RP: Name={0} | CreationTime={1} | StaleVsCutoff={2}" -f `
                        $rpName, $rpTimeShow, $isStale) -ForegroundColor DarkMagenta
                }
            }

            # Find every restore point in this group older than the cutoff
            $stalePoints = @()
            foreach ($rp in $g.Group) {
                $rpTime = $null
                try { $rpTime = $rp.CreationTime } catch { }

                if ($rpTime -and $rpTime -lt $CutoffDate) {
                    $stalePoints += $rp
                }
            }

            if ($stalePoints.Count -eq 0) { continue }

            # Use the most recent stale point as the row representative
            $latestStale = $stalePoints | Sort-Object CreationTime -Descending | Select-Object -First 1

            $nameVal = ''
            try { $nameVal = $latestStale.Name } catch { }
            if ($nameVal -eq '') {
                try { $nameVal = $latestStale.VmName } catch { }
            }
            if ($nameVal -eq '') { $nameVal = '<no-name>' }

            $results.Add([pscustomobject]@{
                ObjectName         = $nameVal
                CopyJobName        = $backup.JobName
                SourceJobName      = $sourceJob
                BackupName         = $backup.Name
                BackupType         = $rawType
                Platform           = $rawPlatform
                Repository         = $repoInfo.Name
                RepositoryType     = $repoInfo.Type
                LatestRestorePoint = $latestStale.CreationTime
                StalePointCount    = $stalePoints.Count
                TotalPointCount    = $g.Count
                ObjectId           = $latestStale.ObjectId
            }) | Out-Null
        }
    }
}

# Capture stale count immediately after collection
$staleCount = $results.Count

if ($EnableDiag) {
    Write-Host ""
    Write-Host "[DIAG] Total stale rows in `$results: $staleCount" -ForegroundColor Magenta
    Write-Host ""
}

# ------------------------------------------------------------
# Output
# ------------------------------------------------------------

if ($copyBackups.Count -eq 0) {

    Write-Host ""
    Write-Host "No Backup Copy Jobs Were Found" -ForegroundColor Yellow
    Write-Host ""

} elseif ($staleCount -gt 0) {


    $dir = Split-Path $CsvPath
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    $results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

    Write-Host ""
    Write-Host "$staleCount stale Backup Copy object(s) found." -ForegroundColor Green
    Write-Host "Report written to $CsvPath" -ForegroundColor Green

} else {

    Write-Host ""
    Write-Host "Backup Copy jobs exist, but no stale restore points were found before the cutoff date." -ForegroundColor Green
    Write-Host ""

}

# ------------------------------------------------------------
# Encrypted / inaccessible summary
# ------------------------------------------------------------

if ($encryptedBackups.Count -gt 0) {
    Write-Host ""
    Write-Host "The Following Backup Copy Jobs Could Not Be Listed As They Are Encrypted" -ForegroundColor Yellow
    Write-Host "---------------------------------------------------------------------------------" -ForegroundColor Yellow
    foreach ($e in $encryptedBackups) {
        Write-Host ("{0}  ({1})" -f $e.JobName, $e.BackupName) -ForegroundColor Yellow
    }
    Write-Host ""
}

if ($inaccessibleBackups.Count -gt 0) {
    Write-Host ""
    Write-Host "The Following Backup Copy Jobs Could Not Be Listed" -ForegroundColor DarkYellow
    Write-Host "-----------------------------------------------------------" -ForegroundColor DarkYellow
    foreach ($i in $inaccessibleBackups) {
        Write-Host ("{0}  ({1})" -f $i.JobName, $i.BackupName) -ForegroundColor DarkYellow
    }
    Write-Host ""
}

# ============================================================
# Cleanup section runs ONLY when this run found stale points
# ============================================================

if ($staleCount -eq 0) {

    Write-Host ""
    Write-Host "No Stale Backups Found - exiting." -ForegroundColor Green
    Write-Host ""

    if (-not $global:WrapperConnected) {
        Disconnect-VBRServer -ErrorAction SilentlyContinue
    }

} else {

    # ============================================================
    #  Interactive Backup Copy Restore-Point Cleanup (CSV-based)
    # ============================================================

    $CsvPathCleanup = $CsvPath

    $cleanupResults = @(Import-Csv -Path $CsvPathCleanup)
    Write-Host "`n[Cleanup Diagnostics] CSV loaded: $($cleanupResults.Count) row(s)." -ForegroundColor DarkGray

    while ($true) {

        $cleanupResults = @(Import-Csv -Path $CsvPathCleanup)

        if ($cleanupResults.Count -eq 0) {
            Write-Host "`nNothing left to clean up. Exiting." -ForegroundColor Green
            break
        }

        $cleanupMap = @{}
        $rowNum = 1

        $displayRows = foreach ($r in ($cleanupResults | Sort-Object LatestRestorePoint, ObjectName)) {
            $cleanupMap["$rowNum"] = $r

            [pscustomobject]@{
                Row                = $rowNum
                ObjectName         = $r.ObjectName
                CopyJobName        = $r.CopyJobName
                SourceJobName      = $r.SourceJobName
                BackupName         = $r.BackupName
                Repository         = $r.Repository
                LatestRestorePoint = $r.LatestRestorePoint
                StalePointCount    = $r.StalePointCount
            }

            $rowNum++
        }

        Write-Host "`n============================================================" -ForegroundColor Cyan
        Write-Host "  Backup Copy Stale Restore-Point Cleanup" -ForegroundColor Cyan
        Write-Host "============================================================" -ForegroundColor Cyan

        $tableText = $displayRows | Format-Table -AutoSize | Out-String
        Write-Host $tableText

        Write-Host "Map entries: $($cleanupMap.Count)" -ForegroundColor DarkGray

        $selection = Read-Host "Enter the Row number to delete that object's stale restore points (or 'Q' to quit)"

        if ($selection -eq $null -or "$selection".Trim() -eq '') { continue }

        if ($selection -match '^(q|quit|exit)$') {
            Write-Host "Exiting Backup Copy cleanup. Done." -ForegroundColor Green
            break
        }

        $selection = $selection.Trim()
        if (-not $cleanupMap.ContainsKey($selection)) {
            Write-Warning "Invalid row number. Try again."
            continue
        }

        $target = $cleanupMap[$selection]

        Write-Host ""
        Write-Host "Selected:" -ForegroundColor Cyan
        Write-Host "  ObjectName    : $($target.ObjectName)"
        Write-Host "  CopyJobName   : $($target.CopyJobName)"
        Write-Host "  SourceJobName : $($target.SourceJobName)"
        Write-Host "  BackupName    : $($target.BackupName)"
        Write-Host "  Repository    : $($target.Repository)"
        Write-Host "  LatestRP      : $($target.LatestRestorePoint)"
        Write-Host "  StaleRPs      : $($target.StalePointCount)"

        # Locate the Backup Copy backup
        $backupObj = Get-VBRBackup | Where-Object {
            $_.Name -eq $target.BackupName -and (
                ($_.TypeToString -match 'Backup Copy') -or
                ($_.BackupPlatform.Platform.ToString() -match 'SimpleBackupCopyPolicy|BackupCopy')
            )
        } | Select-Object -First 1

        if (-not $backupObj) {
            Write-Warning "Could not re-locate Backup Copy backup '$($target.BackupName)'."
            continue
        }

        # Extra safety — make sure this is really a Backup Copy chain
        $isBackupCopy = $false
        try {
            if ($backupObj.TypeToString -match 'Backup Copy') { $isBackupCopy = $true }
            if ($backupObj.BackupPlatform.Platform.ToString() -match 'SimpleBackupCopyPolicy|BackupCopy') { $isBackupCopy = $true }
        } catch { }

        if (-not $isBackupCopy) {
            Write-Warning "Safety check failed — '$($target.BackupName)' is not a Backup Copy backup. Skipping."
            continue
        }

        $allPoints = $null
        try { $allPoints = Get-BackupCopyRestorePoints -Backup $backupObj } catch { }

        if (-not $allPoints) {
            Write-Warning "Could not enumerate restore points for '$($target.BackupName)'."
            continue
        }

        # ObjectId match first
        $pointsToRemove = $null
        $targetObjectId = ''
        if ($target.ObjectId) { $targetObjectId = "$($target.ObjectId)" }

        if ($targetObjectId -and $targetObjectId.Trim() -ne '') {
            $pointsToRemove = $allPoints | Where-Object {
                try { "$($_.ObjectId)" -eq $targetObjectId } catch { $false }
            }
        }

        # Fallback to name match
        if (-not $pointsToRemove -or $pointsToRemove.Count -eq 0) {
            $pointsToRemove = $allPoints | Where-Object {
                try { $_.Name -ieq $target.ObjectName } catch { $false }
            }
        }

        if (-not $pointsToRemove -or $pointsToRemove.Count -eq 0) {
            Write-Warning "No matching restore points found for '$($target.ObjectName)' in backup '$($target.BackupName)'."
            continue
        }

        # Only stale
        $pointsToRemove = $pointsToRemove | Where-Object {
            try { $_.CreationTime -lt $CutoffDate } catch { $false }
        }

        if (-not $pointsToRemove -or $pointsToRemove.Count -eq 0) {
            Write-Warning "No stale restore points exist for '$($target.ObjectName)' before the cutoff date."
            continue
        }

        Write-Host "`nThe following Backup Copy restore points will be DELETED:" -ForegroundColor Yellow

        $previewText = $pointsToRemove |
            Sort-Object CreationTime |
            Select-Object @{n='ObjectName';e={$_.Name}},
                          CreationTime,
                          @{n='BackupName';e={$target.BackupName}},
                          @{n='Repository';e={$target.Repository}} |
            Format-Table -AutoSize -Wrap | Out-String

        Write-Host $previewText

        Write-Host ("Total restore points to delete: {0}" -f $pointsToRemove.Count) -ForegroundColor Yellow

        Write-Host ""
        Write-Host "NOTE: Deleting from a Backup Copy chain only removes COPY restore points." -ForegroundColor DarkCyan
        Write-Host "      Source primary backups are NOT affected." -ForegroundColor DarkCyan

        $confirm = Read-Host "`nType 'YES' (uppercase) to confirm permanent deletion, or anything else to cancel"
        if ($confirm -cne 'YES') {
            Write-Host "Cancelled. No restore points were deleted." -ForegroundColor Green
            continue
        }

        try {
            $pointsToRemove | Remove-VBRRestorePoint -Confirm:$false -ErrorAction Stop
            Write-Host ("Deleted {0} restore point(s) for '{1}' from backup copy '{2}'." -f `
                $pointsToRemove.Count, $target.ObjectName, $target.BackupName) -ForegroundColor Green

            $remaining = @(Import-Csv -Path $CsvPathCleanup | Where-Object {
                -not (
                    $_.BackupName    -eq $target.BackupName -and
                    $_.ObjectName    -eq $target.ObjectName -and
                    "$($_.ObjectId)" -eq $targetObjectId
                )
            })

            $remaining | Export-Csv -Path $CsvPathCleanup -NoTypeInformation -Encoding UTF8
            Write-Host "Updated Backup Copy CSV: $CsvPathCleanup" -ForegroundColor DarkGray

        } catch {
            Write-Warning "Failed to delete restore points for '$($target.ObjectName)': $_"
        }
    }

    Write-Host ""
    Write-Host "Cleanup session complete." -ForegroundColor Green

    if (-not $global:WrapperConnected) {
        Disconnect-VBRServer -ErrorAction SilentlyContinue
    }
}