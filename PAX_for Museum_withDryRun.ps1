# Enable Dry Run Mode (Set to $true for testing, $false to actually move files)
$DryRun = $false  # Change to $false for real execution

# Enable Rollback Mode (Set to $true to restore files from last run)
$Rollback = $false  # Change to $true to revert last run

# Define multiple source folders
$SourceFolders = @(
    "S:\DAC Projects\CSM Museum and Study Collection\Alan Bartram Photographic Prints\CLR Reorganised\Box 3 North"
)

# Define common destination root
$DestinationRoot = "S:\DAC Projects\CSM Museum and Study Collection\CLR for upload to preservica\Box 3 North"

# Regex patterns
$TopLevelFolderPattern = "^[A-Z]{3}\.\d{4}\.\d{1,4}\.[A-Z](\.\d+-\d+)?$"
$SubPrefixPattern = "^[A-Z]{3}\.\d{4}\.\d{1,4}\.[A-Z](\.\d{1,2})?(?=\.[^.]+$)"

# Log files
$LogFile = "$DestinationRoot\File Organisation Log.txt"
$RollbackLog = "$DestinationRoot\Rollback_Log.json"

# Load rollback data if available
$RollbackData = @{}
if (Test-Path $RollbackLog) {
    $RollbackData = Get-Content -Path $RollbackLog | ConvertFrom-Json
}

# Rollback Function
if ($Rollback) {
    Write-Host "Starting rollback process..." -ForegroundColor Yellow
    foreach ($Entry in $RollbackData.PSObject.Properties) {
        $FilePath = $Entry.Name
        $OriginalLocation = $Entry.Value
        if (Test-Path $FilePath) {
            Move-Item -Path $FilePath -Destination $OriginalLocation -Force
            Write-Host "Restored '$FilePath' to '$OriginalLocation'" -ForegroundColor Green
        } else {
            Write-Host "Warning: '$FilePath' not found for rollback." -ForegroundColor Red
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

# Process folders and files
foreach ($SourceFolder in $SourceFolders) {
    $Subfolders = Get-ChildItem -Path $SourceFolder -Directory

    foreach ($Subfolder in $Subfolders) {
        # Check if the subfolder matches the TopLevelFolderPattern
        if ($Subfolder.Name -match $TopLevelFolderPattern) {
            $TopLevelFolder = Join-Path $DestinationRoot $Subfolder.Name

            # Process all files in this subfolder
            $Files = Get-ChildItem -Path $Subfolder.FullName -File -Recurse
            foreach ($File in $Files) {
                try {
                    # Remove the file extension before applying regex
                    $fileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)

                    # Debugging output to see what the script is checking
                    Write-Host "Checking file: '$file' against SubPrefixPattern"

                    # Check if it matches the sub-prefix pattern
                    if ($file -match $SubPrefixPattern) {
                     Write-Host "✅ Match Found: $file"
                    } else {
                    Write-Host "❌ No Match: $file (Pattern: $SubPrefixPattern)"
                    }


                    # Match sub-prefix pattern for files
                    if ($File.Name -match $SubPrefixPattern) {
                        $SubPrefix = $Matches[0]

                        # Define paths
                        $PaxFolder = Join-Path $TopLevelFolder "$SubPrefix.pax"
                        $PreservationFolder = Join-Path (Join-Path $PaxFolder "Representation_Preservation") $SubPrefix
                        $AccessFolder = Join-Path (Join-Path $PaxFolder "Representation_Access") $SubPrefix

                        # Determine destination folder based on file type
                        $DestinationFolder = if ($File.Extension -match "\.jpe?g$") {
                            $AccessFolder
                        } elseif ($File.Extension -match "\.tiff?$") {
                            $PreservationFolder
                        } else {
                            $null
                        }

                        if ($DestinationFolder) {
                            if ($DryRun) {
                                if (-not $DirectoryTree.ContainsKey($TopLevelFolder)) { $DirectoryTree[$TopLevelFolder] = @{} }
                                if (-not $DirectoryTree[$TopLevelFolder].ContainsKey($PaxFolder)) { $DirectoryTree[$TopLevelFolder][$PaxFolder] = @{} }
                                if (-not $DirectoryTree[$TopLevelFolder][$PaxFolder].ContainsKey($DestinationFolder)) { $DirectoryTree[$TopLevelFolder][$PaxFolder][$DestinationFolder] = @() }
                                $DirectoryTree[$TopLevelFolder][$PaxFolder][$DestinationFolder] += $File.Name
                                Write-Host "[Dry Run] Would move '$($File.FullName)' to '$DestinationFolder'" -ForegroundColor Cyan
                            } else {
                                foreach ($Folder in @($TopLevelFolder, $PaxFolder, $PreservationFolder, $AccessFolder)) {
                                    if (!(Test-Path -Path $Folder)) { New-Item -ItemType Directory -Path $Folder | Out-Null }
                                }
                                Move-Item -Path $File.FullName -Destination $DestinationFolder
                                Write-Host "Moved '$($File.FullName)' to '$DestinationFolder'" -ForegroundColor Green
                            }
                        }
                    } else {
                        Write-Host "Warning: '$($File.FullName)' does not match the required sub-prefix pattern." -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "Error processing file '$($File.FullName)': $_" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "Skipping subfolder '$($Subfolder.Name)' - Does not match expected top-level pattern." -ForegroundColor Yellow
        }
    }
}

# Save rollback data if running for real
if (-not $DryRun -and $RollbackData.Count -gt 0) {
    $RollbackData | ConvertTo-Json | Set-Content -Path $RollbackLog
    Write-Host "Rollback data saved." -ForegroundColor Yellow
}

# Print Dry Run Directory Tree
if ($DryRun -and $DirectoryTree.Count -gt 0) {
    Write-Host "`n[Dry Run] Directory Structure that would be created:" -ForegroundColor Cyan
    foreach ($TopLevelFolder in $DirectoryTree.Keys) {
        Write-Host "`n$TopLevelFolder" -ForegroundColor Cyan
        foreach ($PaxFolder in $DirectoryTree[$TopLevelFolder].Keys) {
            Write-Host "|-- $PaxFolder" -ForegroundColor Cyan
            foreach ($SubFolder in $DirectoryTree[$TopLevelFolder][$PaxFolder].Keys) {
                Write-Host "    |-- $SubFolder" -ForegroundColor Cyan
                foreach ($FileName in $DirectoryTree[$TopLevelFolder][$PaxFolder][$SubFolder]) {
                    Write-Host "        |-- $FileName" -ForegroundColor Cyan
                }
            }
        }
    }
}

Write-Host "$(Get-Date): File organization process $(if ($DryRun) { 'simulated (Dry Run Mode)' } else { 'completed' })." -ForegroundColor Green
