# Enable Dry Run Mode (Set to $true for testing, $false to actually move files)
$DryRun = $true  # Change to $false for real execution

# Enable Rollback Mode (Set to $true to restore files from last run)
$Rollback = $false  # Change to $true to revert last run

# Define single/multiple source folders - separate with quotes and comma as shown
$SourceFolders = @(
    "S:\Source folder 1",
    "S:\Source folder 2"
)

# Define common destination root
$DestinationRoot = "S:\Destination folder"

# Regex pattern to match file prefixes (Adapt Regex for different projects as needed)
$PrefixPattern = "^[A-Z]{3}(-\d{1,2}-\d{1,2}-\d{1,2}-\d{1,2}-\d{1,3}|\.\d{4}\.\d+\.[A-Z].\d{1,2})"

# Log files
$LogFile = "S:\Destination folder\File Organisation Log.txt"
$RollbackLog = "S:\Destination folder\Rollback_Log.json"

# Load rollback data if available
$RollbackData = @{}
if (Test-Path $RollbackLog) {
    $RollbackData = Get-Content -Path $RollbackLog | ConvertFrom-Json
}

# Rollback Function
if ($Rollback) {
    Write-Host "Starting rollback process..." -ForegroundColor Yellow
    Add-Content -Path $LogFile -Value "`n$(Get-Date): Starting rollback process..."

    foreach ($Entry in $RollbackData.PSObject.Properties) {
        $FilePath = $Entry.Name
        $OriginalLocation = $Entry.Value

        if (Test-Path $FilePath) {
            Move-Item -Path $FilePath -Destination $OriginalLocation -Force
            Write-Host "Restored '$FilePath' to '$OriginalLocation'" -ForegroundColor Green
            Add-Content -Path $LogFile -Value "$(Get-Date): Restored '$FilePath' to '$OriginalLocation'"
        } else {
            Write-Host "Warning: '$FilePath' not found for rollback." -ForegroundColor Red
            Add-Content -Path $LogFile -Value "$(Get-Date): Warning: '$FilePath' not found for rollback."
        }
    }

    Remove-Item -Path $RollbackLog -Force
    Write-Host "Rollback completed." -ForegroundColor Green
    exit
}

# Store rollback data
$RollbackData = @{}

# Dry Run Directory Tree
$DirectoryTree = @{}

# Process files
foreach ($SourceFolder in $SourceFolders) {
    $Files = Get-ChildItem -Path $SourceFolder -File -Recurse

    foreach ($File in $Files) {
        try {
            if ($File.Name -match $PrefixPattern) {
                $Prefix = $Matches[0]

                # Ensure the target folder ends with ".pax" only if it's missing
                $PaxFolder = if ($Prefix -match "\.pax$") { $Prefix } else { "$Prefix.pax" }

                # Wrap ".pax" folder inside another folder named after $Prefix
                $WrapperFolder = Join-Path -Path $DestinationRoot -ChildPath $Prefix
                $TargetFolder = Join-Path -Path $WrapperFolder -ChildPath $PaxFolder

                # Define Preservation and Access folder paths
                $PreservationFolder = Join-Path -Path $TargetFolder -ChildPath "Representation_Preservation\$Prefix"
                $AccessFolder = Join-Path -Path $TargetFolder -ChildPath "Representation_Access\$Prefix"

                # Determine destination based on file type
                $DestinationFolder = $null
                if ($File.Extension -eq ".jpeg" -or $File.Extension -eq ".jpg") {
                    $DestinationFolder = $AccessFolder
                } elseif ($File.Extension -eq ".tiff" -or $File.Extension -eq ".tif") {
                    $DestinationFolder = $PreservationFolder
                }

                if ($DestinationFolder) {
                    if ($DryRun) {
                        # Store structure for dry run
                        if (-not $DirectoryTree.ContainsKey($WrapperFolder)) { $DirectoryTree[$WrapperFolder] = @{} }
                        if (-not $DirectoryTree[$WrapperFolder].ContainsKey($TargetFolder)) { $DirectoryTree[$WrapperFolder][$TargetFolder] = @{} }
                        if (-not $DirectoryTree[$WrapperFolder][$TargetFolder].ContainsKey($DestinationFolder)) { $DirectoryTree[$WrapperFolder][$TargetFolder][$DestinationFolder] = @() }
                        $DirectoryTree[$WrapperFolder][$TargetFolder][$DestinationFolder] += $File.Name
                        Write-Host "[Dry Run] Would move '$($File.FullName)' to '$DestinationFolder'" -ForegroundColor Cyan
                    } else {
                        # Track original location for rollback
                        $RollbackData[$File.FullName] = $File.FullName

                        # Ensure directories exist
                        foreach ($Folder in @($WrapperFolder, $TargetFolder, $PreservationFolder, $AccessFolder)) {
                            if (!(Test-Path -Path $Folder)) { New-Item -ItemType Directory -Path $Folder | Out-Null }
                        }

                        # Move file
                        Move-Item -Path $File.FullName -Destination $DestinationFolder
                        $RollbackData[$DestinationFolder + "\" + $File.Name] = $File.FullName
                        Write-Host "Moved '$($File.FullName)' to '$DestinationFolder'" -ForegroundColor Green
                        Add-Content -Path $LogFile -Value "$(Get-Date): Moved '$($File.FullName)' to '$DestinationFolder'"
                    }
                }
            } else {
                $ErrorMessage = "$(Get-Date): File '$($File.FullName)' does not match the required prefix pattern."
                Write-Host $ErrorMessage -ForegroundColor Yellow
                Add-Content -Path $LogFile -Value $ErrorMessage
            }
        } catch {
            $ErrorMessage = "$(Get-Date): Error processing file '$($File.FullName)'. Error: $_"
            Write-Host $ErrorMessage -ForegroundColor Red
            Add-Content -Path $LogFile -Value $ErrorMessage
        }
    }
}

# Save rollback data if running for real
if (-not $DryRun -and $RollbackData.Count -gt 0) {
    $RollbackData | ConvertTo-Json | Set-Content -Path $RollbackLog
    Write-Host "Rollback data saved. If needed, run script with `$Rollback = `$true to revert changes." -ForegroundColor Yellow
}

# Print Dry Run Directory Tree
if ($DryRun -and $DirectoryTree.Count -gt 0) {
    Write-Host "`n[Dry Run] Directory Structure that would be created:" -ForegroundColor Cyan
    foreach ($WrapperFolder in $DirectoryTree.Keys) {
        Write-Host "`n$WrapperFolder" -ForegroundColor Cyan
        foreach ($TargetFolder in $DirectoryTree[$WrapperFolder].Keys) {
            Write-Host "|-- $TargetFolder" -ForegroundColor Cyan
            foreach ($SubFolder in $DirectoryTree[$WrapperFolder][$TargetFolder].Keys) {
                Write-Host "    |-- $SubFolder" -ForegroundColor Cyan
                foreach ($FileName in $DirectoryTree[$WrapperFolder][$TargetFolder][$SubFolder]) {
                    Write-Host "        |-- $FileName" -ForegroundColor Cyan
                }
            }
        }
    }
}

# Completion message
$CompletionMessage = "$(Get-Date): File organization process $(if ($DryRun) { 'simulated (Dry Run Mode)' } else { 'completed' })."
Add-Content -Path $LogFile -Value $CompletionMessage
Write-Host $CompletionMessage -ForegroundColor Green
