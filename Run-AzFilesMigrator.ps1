#region variables
$azcopyURI = "https://aka.ms/downloadazcopy-v10-windows"
$AzCopySetup = "C:\AzCopy\DL"
$AzCopyWPath = "C:\AzCopy\"
#endregion variables

#region functions
function Get-Option {
    Write-Host "What would you like to do?"
    Write-Host "1 - Perform Azure Files Migration"
    Write-Host "2 - Select Azure Subscription"    
    Write-Host "3 - Download AzCopy"
    Write-Host "4 - Adjust AZCOPY_CONCURRENCY_VALUE"
    Write-Host "8 - Exit"
    $o = Read-Host -Prompt 'Please type the number of the option you would like to perform '
    return ($o.ToString()).Trim()
}
function Helper-AzSubscription {
    param (
        [parameter (Mandatory = $false)]
        [switch]$whoami,
        [parameter (Mandatory = $false)]
        [switch]$select
    )
    if ($whoami) {
        Write-Host "You are currently logged in as:" -BackgroundColor Black -ForegroundColor Green
        Get-AzContext | ft Account, Name -AutoSize
    }
    if ($select) {
        Write-Host "Please select the Azure subscription you would like to use:" -BackgroundColor Black -ForegroundColor Yellow
        $sub = Get-AzSubscription | ogv -Title "Select Your Azure Subscription" -PassThru
        Write-Host "Changing Azure Subscription to" $sub.Name "with the ID of" $sub.Id -BackgroundColor Black -ForegroundColor Yellow
        Select-AzSubscription -SubscriptionId $sub.Id
    }
}
Function Track-Time($Time) {
    If (!($Time)) { Return Get-Date } Else {
        Return ((get-date) - $Time)
    }
}
function Get-AzCopyFromWeb {
    try {
        Write-Host "Creating download directory..." -BackgroundColor Black -ForegroundColor Green
        New-Item -Path $AzCopySetup -ItemType Directory -Force | Out-Null
        
        Write-Host "Downloading AzCopy from $azcopyURI..." -BackgroundColor Black -ForegroundColor Green
        try {
            Start-BitsTransfer -Source $azcopyURI -Destination "$AzCopySetup\azcopy_windows_amd64.zip" -Description "Downloading AzCopy" -DisplayName "AzCopy Download"
        }
        catch {
            Write-Host "BITS transfer failed, using WebRequest instead..." -BackgroundColor Black -ForegroundColor Yellow
            Invoke-WebRequest -Uri $azcopyURI -OutFile "$AzCopySetup\azcopy_windows_amd64.zip"
        }
        
        if (-not (Test-Path "$AzCopySetup\azcopy_windows_amd64.zip")) {
            throw "Failed to download AzCopy"
        }
        
        Write-Host "Downloaded AzCopy to $AzCopySetup" -BackgroundColor Black -ForegroundColor Green
        Write-Host "Expanding azcopy_windows_amd64.zip..." -BackgroundColor Black -ForegroundColor Green
        Expand-Archive "$AzCopySetup\azcopy_windows_amd64.zip" -DestinationPath "$AzCopyWPath" -Force
        
        $ci = Get-ChildItem -Path $AzCopyWPath -Include *.exe, *.txt -File -Recurse
        if ($ci.Count -eq 0) {
            throw "No AzCopy executable found in extracted files"
        }
        
        Write-Host "Copying AzCopy files to $AzCopyWPath..." -BackgroundColor Black -ForegroundColor Green
        foreach ($file in $ci) { 
            Copy-Item $file.FullName -Destination $AzCopyWPath -Force
        }
        
        Write-Host "Cleaning up temporary files..." -BackgroundColor Black -ForegroundColor Green
        Remove-Item "$AzCopySetup" -Force -Recurse -ErrorAction SilentlyContinue
        Remove-Item $ci.DirectoryName -Force -Recurse -ErrorAction SilentlyContinue
        
        if (Test-Path "$AzCopyWPath\azcopy.exe") {
            Write-Host "AzCopy Tool successfully installed at $AzCopyWPath" -BackgroundColor Black -ForegroundColor Green
        }
        else {
            throw "AzCopy installation verification failed"
        }
    }
    catch {
        Write-Host "Error downloading or installing AzCopy: $_" -BackgroundColor Black -ForegroundColor Red
        throw
    }
}
function Get-AzShareInfo {
    param (
        [parameter (Mandatory = $true)]
        [array]$storageaccts,
        [parameter (Mandatory = $false)]
        [switch]$source,
        [parameter (Mandatory = $false)]
        [switch]$dest
    )
    [hashtable]$return = @{}
    if ($source) { $L = "Source" }elseif ($dest) { $L = "Destination" }
    
    Write-Host "Please select the $L storage account" -BackgroundColor Black -ForegroundColor Yellow
    $stg = $storageaccts | ogv -Title "Select $L Storage Account" -PassThru
    
    if ($null -eq $stg -or $null -eq $stg.StorageAccountName) {
        Write-Host "No storage account selected" -BackgroundColor Black -ForegroundColor Red
        throw "Storage account selection is required"
    }
    
    Write-Host "$L storage account is" $stg.StorageAccountName -BackgroundColor Black -ForegroundColor Green
    Write-Host "Getting list of available file shares in" $stg.StorageAccountName -BackgroundColor Black -ForegroundColor Green
    
    try {
        $shares = Get-AzStorageShare -Context $stg.Context
        if ($shares.Count -eq 0) {
            Write-Host "No file shares found in storage account: $($stg.StorageAccountName)" -BackgroundColor Black -ForegroundColor Red
            throw "No file shares available"
        }
        Write-Host "Found $($shares.Count) file share(s)" -BackgroundColor Black -ForegroundColor Green
    }
    catch {
        Write-Host "Error retrieving file shares: $_" -BackgroundColor Black -ForegroundColor Red
        throw
    }
    
    Write-Host "Please Select the $L file share in" $stg.StorageAccountName -BackgroundColor Black -ForegroundColor Yellow
    $share = $shares | ogv -Title "Select $L File Share" -PassThru
    
    if ($null -eq $share -or $null -eq $share.Name) {
        Write-Host "No file share selected" -BackgroundColor Black -ForegroundColor Red
        throw "File share selection is required"
    }
    
    $return = @{"StorageAcctName" = $stg.StorageAccountName; "StorageAcctContext" = $stg.Context; "ShareName" = $share.Name }
    return $return
}
function Get-AzShareSAS {
    param (
        [parameter (Mandatory = $true)]
        [Microsoft.Azure.Commands.Common.Authentication.Abstractions.IStorageContext]$stgcontext,
        [parameter (Mandatory = $true)]
        [string]$sharename,
        [parameter (Mandatory = $false)]
        [switch]$source,
        [parameter (Mandatory = $false)]
        [switch]$dest
    )
    if ($source) { $perms = "rl" }elseif ($dest) { $perms = "rwl" }
    $StartTime = Get-Date
    $EndTime = $StartTime.AddHours(12.0)
    $s = Get-AzStorageShare -Prefix $sharename -Context $stgcontext.Context | New-AzStorageShareSASToken -Permission $perms -StartTime $StartTime -ExpiryTime $EndTime
    return $s
}
function Copy-AzFileDirectory {
    param (
        [parameter (Mandatory = $true)]
        [string]$srcstgacctname,
        [parameter (Mandatory = $true)]
        [string]$srcsharename,
        [parameter (Mandatory = $true)]
        [string]$srcdirname,
        [parameter (Mandatory = $true)]
        [string]$srcSAS,
        [parameter (Mandatory = $true)]
        [string]$deststgacctname,
        [parameter (Mandatory = $true)]
        [string]$destsharename,
        [parameter (Mandatory = $true)]
        [string]$destdirname,
        [parameter (Mandatory = $true)]
        [string]$destSAS
    )
    $srcurl = "https://" + $srcstgacctname + ".file.core.windows.net/" + $srcsharename + "/" + $srcdirname + $srcSAS
    $desturl = "https://" + $deststgacctname + ".file.core.windows.net/" + $destsharename + "/" + $destdirname + $destSAS
    
    Write-Host "Copying: $srcdirname" -BackgroundColor Black -ForegroundColor Cyan
    Write-Host "  From: $srcstgacctname/$srcsharename" -BackgroundColor Black -ForegroundColor Cyan
    Write-Host "  To: $deststgacctname/$destsharename" -BackgroundColor Black -ForegroundColor Cyan
    
    try {
        &$AzCopyWPath\azcopy.exe copy "$srcurl" "$desturl" --recursive --preserve-smb-permissions=true --preserve-smb-info=true --log-level=ERROR
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully copied: $srcdirname" -BackgroundColor Black -ForegroundColor Green
        }
        else {
            Write-Host "AzCopy completed with warnings or errors for: $srcdirname (Exit Code: $LASTEXITCODE)" -BackgroundColor Black -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Error copying $srcdirname : $_" -BackgroundColor Black -ForegroundColor Red
        throw
    }
}
function Get-CSVlistpath {
    Add-Type -AssemblyName System.Windows.Forms
    $FB = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
        InitialDirectory = [Environment]::GetFolderPath('Desktop')
        Filter           = 'CSV File (*.csv)|*.csv'
        Multiselect      = $false
    }
    $null = $FB.ShowDialog()
    return $FB.FileName
}
function Get-CSVlist {
    param (
        [parameter (Mandatory = $true)]
        [string]$csvfilepath
    )
    if (-not (Test-Path $csvfilepath)) {
        Write-Host "CSV file not found at: $csvfilepath" -BackgroundColor Black -ForegroundColor Red
        throw "CSV file not found"
    }
    
    try {
        $csv = Import-Csv -Path $csvfilepath -Header uid
        Write-Host "$($csv.count) items were imported from the CSV file provided" -BackgroundColor Black -ForegroundColor Green
        return $csv 
    }
    catch {
        Write-Host "Error reading CSV file: $_" -BackgroundColor Black -ForegroundColor Red
        throw
    }
}
function Get-UIDShareMatches {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)]
        [array]$names,
        [parameter (Mandatory = $true)]
        [string]$share,
        [parameter (Mandatory = $true)]
        [Microsoft.Azure.Commands.Common.Authentication.Abstractions.IStorageContext]$stgcontext
    )
    Write-Host "Retrieving file list from share..." -BackgroundColor Black -ForegroundColor Green
    $sfiles = Get-AzStorageFile -Context $stgcontext -ShareName $share
    Write-Host "Retrieved $($sfiles.Count) items from share" -BackgroundColor Black -ForegroundColor Green
    
    $ArrayList = New-Object -TypeName System.Collections.ArrayList
    $matchCount = 0
    $totalCount = $names.Count
    
    foreach ($n in $names) {
        $matchCount++
        Write-Progress -Activity "Matching directories" -Status "Processing $matchCount of $totalCount" -PercentComplete (($matchCount / $totalCount) * 100)
        
        $a = $n.uid
        $b = $sfiles | Where-Object { $_.Name -like "*$a*" }
        if ($null -ne $b) {
            Write-Host "$a has been matched to" $b.Name -BackgroundColor Black -ForegroundColor Green
            $match = @{id = $a; dir = $b.Name } 
            $ArrayList += $match
        }
        else {
            Write-Host "$a has not been matched to any directory" -BackgroundColor Black -ForegroundColor Yellow
        }
    }
    Write-Progress -Activity "Matching directories" -Completed
    Write-Host "Matched $($ArrayList.Count) out of $totalCount directories" -BackgroundColor Black -ForegroundColor Green
    return $ArrayList
}
function Set-AzCopyConcurrency {
    param (
        [parameter (Mandatory = $false)]
        [switch]$on1k,
        [parameter (Mandatory = $false)]
        [switch]$on2k,
        [parameter (Mandatory = $false)]
        [switch]$on3k,
        [parameter (Mandatory = $false)]
        [switch]$off
    )
    if ($on1k) {
        #set concurrency to 1000
        Write-Host "Setting AZCOPY_CONCURRENCY_VALUE to 1000" -BackgroundColor Black -ForegroundColor Green
        $env:AZCOPY_CONCURRENCY_VALUE = 1000
    }
    if ($on2k) {
        #set concurrency to 2000
        Write-Host "Setting AZCOPY_CONCURRENCY_VALUE to 2000" -BackgroundColor Black -ForegroundColor Green
        $env:AZCOPY_CONCURRENCY_VALUE = 2000
    }
    if ($on3k) {
        #set concurrency to 3000
        Write-Host "Setting AZCOPY_CONCURRENCY_VALUE to 3000" -BackgroundColor Black -ForegroundColor Green
        $env:AZCOPY_CONCURRENCY_VALUE = 3000
    }
    if ($off) {
        Write-Host "Getting CPU information to determine default value of AZCOPY_CONCURRENCY_VALUE" -BackgroundColor Black -ForegroundColor Green
        $nlp = Get-ComputerInfo -Property CsProcessors
        if ($nlp.CsProcessors.NumberOfLogicalProcessors -lt 5) {
            $env:AZCOPY_CONCURRENCY_VALUE = 32
        }
        else {
            $c = $nlp.CsProcessors.NumberOfLogicalProcessors * 16
            if ($c -gt 3000) {
                $c = 3000
                Write-Host "Setting AZCOPY_CONCURRENCY_VALUE to" $c -BackgroundColor Black -ForegroundColor Green
                $env:AZCOPY_CONCURRENCY_VALUE = $c
            }
            else {
                Write-Host "Setting AZCOPY_CONCURRENCY_VALUE to" $c -BackgroundColor Black -ForegroundColor Green
                $env:AZCOPY_CONCURRENCY_VALUE = $c
            }     
        }
    }
}
function Invoke-Option {
    param (
        [parameter (Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 1)]
        [string]$userSelection
    )
    if ($userSelection -eq "1") {
        #1 - Perform Azure Files Migration
        if ((Test-Path $AzCopyWPath\azcopy.exe -PathType Leaf) -eq $false) {
            Write-Host "AzCopy is not found at" $AzCopyWPath -BackgroundColor Black -ForegroundColor Red
            $hv = Read-Host -Prompt "Would you like to download the latest AzCopy Tool on $env:computername ? (y/n)"
            if ($hv.Trim().ToLower() -eq "y") {
                Write-Host "Downloading the latest AzCopy Tool from $azcopyURI" -BackgroundColor Black -ForegroundColor Green
                Get-AzCopyFromWeb     
            }    
            elseif ($hv.Trim().ToLower() -eq "n") {
                Write-Host "AzCopy Tool is required to perform Azure Files migration" -BackgroundColor Black -ForegroundColor Red
                Write-Host "Exiting migration, please download latest tooling to proceed further" -BackgroundColor Black -ForegroundColor Yellow
                Invoke-Option -userSelection (Get-Option)
            }
            else {
                Write-Host "Invalid option entered" -BackgroundColor Black -ForegroundColor Red
                Invoke-Option -userSelection (Get-Option)
            }
        }
        Write-Host "Getting list of available storage accounts" -BackgroundColor Black -ForegroundColor Green
        $stgaccts = Get-AzStorageAccount
        Write-Host $stgaccts.Count "storage accounts found" -BackgroundColor Black -ForegroundColor Green
        $sv = Read-Host -Prompt "Would you like to see only storage accounts with AD integration enabled? (y/n)"
        if ($sv.Trim().ToLower() -eq "y") {
            Write-host "Filtering storage accounts for those with AD integration enabled" -BackgroundColor Black -ForegroundColor Green
            $stgaccts = $stgaccts | where { $_.AzureFilesIdentityBasedAuth -ne $null }
            Write-Host $stgaccts.Count "storage accounts found with AD integration enabled" -BackgroundColor Black -ForegroundColor Green
        }
        else {
            Write-Host "Using full list of available storage accounts" -BackgroundColor Black -ForegroundColor Green
        }
        $sinfo = Get-AzShareInfo -storageaccts $stgaccts -source
        $dinfo = Get-AzShareInfo -storageaccts $stgaccts -dest
        #Output information to user about the storage account and share selected
        Write-Host "You have selected the following Storage Accounts and File Shares to use" -BackgroundColor Black -ForegroundColor Green
        Write-Host "-----Source-----" -BackgroundColor Black -ForegroundColor Green
        Write-Host "Source Storage Account" $sinfo.StorageAcctName -BackgroundColor Black -ForegroundColor Green
        Write-Host "Source File Share" $sinfo.ShareName -BackgroundColor Black -ForegroundColor Green
        Write-Host "-----Destination-----" -BackgroundColor Black -ForegroundColor Green
        Write-Host "Destination Storage Account" $dinfo.StorageAcctName -BackgroundColor Black -ForegroundColor Green
        Write-Host "Destination File Share" $dinfo.ShareName -BackgroundColor Black -ForegroundColor Green
        #Perform check on source and destination variables to ensure they are not null
        if (($sinfo.StorageAcctName -eq $null) -or ($sinfo.ShareName -eq $null) -or ($dinfo.StorageAcctName -eq $null) -or ($dinfo.ShareName -eq $null)) {
            Write-Host "One or more selections was empty/null"
            Write-Host "Restarting Selection Process"
            Invoke-Option -userSelection 1
        }
        #Confirm with user that information is correct
        $sv = Read-Host -Prompt "Is this selection correct? (y/n)"
        if ($sv.Trim().ToLower() -eq "n") {
            Write-Host "Restarting Selection Process"
            Invoke-Option -userSelection 1
        }
        Write-Host "Generating SAS Token for source and destination shares" -BackgroundColor Black -ForegroundColor Green
        $ssas = Get-AzShareSAS -stgcontext $sinfo.StorageAcctContext -sharename $sinfo.ShareName -source
        $dsas = Get-AzShareSAS -stgcontext $dinfo.StorageAcctContext -sharename $dinfo.ShareName -dest
        #Ask if moving indivual folder or using a folder list with .csv extension
        Write-Host "What would you like to do?" -BackgroundColor Black -ForegroundColor Yellow
        Write-Host "1 - Copy a single directory"
        Write-Host "2 - Copy multiple directories using a CSV"    
        $op = Read-Host -Prompt 'Please type the number of the option you would like to perform '
        if ($op.Trim().ToLower() -eq "1") {
            Write-Host "You have selected option 1" -BackgroundColor Black -ForegroundColor Green
            Write-Host "Please enter the source folder to copy" -BackgroundColor Black -ForegroundColor Yellow
            $srcdir = Read-Host -Prompt 'Please provide the name of the source directory to copy'
            $srcdir = $srcdir.Trim() 
            Copy-AzFileDirectory -srcstgacctname $sinfo.StorageAcctName -srcsharename $sinfo.ShareName -srcdirname $srcdir -srcSAS $ssas -deststgacctname $dinfo.StorageAcctName -destsharename $dinfo.ShareName -destdirname $srcdir -destSAS $dsas  
            Invoke-Option -userSelection (Get-Option)
        }
        elseif ($op.Trim().ToLower() -eq "2") {
            Write-Host "You have selected option 2" -BackgroundColor Black -ForegroundColor Green
            Write-Host "Please provide the CSV to use" -BackgroundColor Black -ForegroundColor Yellow
            $cfp = Get-CSVlistpath
            $cl = Get-CSVlist -csvfilepath $cfp
            $sm = Get-UIDShareMatches -names $cl -share $sinfo.ShareName -stgcontext $sinfo.StorageAcctContext

            #Ask user to confirm the folder list then copy the files
            $fv = Read-Host -Prompt "Is this selection correct? (y/n)"
            if ($fv.Trim().ToLower() -eq "y") {
                $i = 0
                $totalDirs = $sm.Count
                $successCount = 0
                $failureCount = 0
                $time = Track-Time $time
                
                Write-Host "`nStarting migration of $totalDirs directories..." -BackgroundColor Black -ForegroundColor Green
                
                foreach ($s in $sm) {
                    $i++
                    Write-Progress -Activity "Migrating directories" -Status "Processing $i of $totalDirs - $($s.id)" -PercentComplete (($i / $totalDirs) * 100)
                    Write-Host "`n[$i/$totalDirs] Processing $($s.id) with the directory of $($s.dir)" -BackgroundColor Black -ForegroundColor Green
                    
                    try {
                        Copy-AzFileDirectory -srcstgacctname $sinfo.StorageAcctName -srcsharename $sinfo.ShareName -srcdirname $s.dir -srcSAS $ssas -deststgacctname $dinfo.StorageAcctName -destsharename $dinfo.ShareName -destdirname $s.dir -destSAS $dsas
                        $successCount++
                    }
                    catch {
                        Write-Host "Failed to copy directory $($s.dir): $_" -BackgroundColor Black -ForegroundColor Red
                        $failureCount++
                    }
                }
                Write-Progress -Activity "Migrating directories" -Completed
                
                $time = Track-Time $time
                Write-Host "`nMigration Summary:" -BackgroundColor Black -ForegroundColor Green
                Write-Host "  Total directories processed: $i" -BackgroundColor Black -ForegroundColor Green
                Write-Host "  Successful: $successCount" -BackgroundColor Black -ForegroundColor Green
                Write-Host "  Failed: $failureCount" -BackgroundColor Black -ForegroundColor $(if ($failureCount -gt 0) { "Red" } else { "Green" })
                Write-Host "  Processing time: $($time.Hours) hours $($time.Minutes) minutes $($time.Seconds) seconds" -BackgroundColor Black -ForegroundColor Green
            }
            else {
                Write-Host "Restarting Selection Process"
                Invoke-Option -userSelection 1
            }
            Invoke-Option -userSelection (Get-Option)
        }
        else {
            Write-Host "Invalid option entered" -BackgroundColor Black -ForegroundColor Red
            Invoke-Option -userSelection (Get-Option)
        }
    }
    elseif ($userSelection -eq "2") {
        #2 - Select Azure Subscription
        Helper-AzSubscription -whoami
        Helper-AzSubscription -select
        Invoke-Option -userSelection (Get-Option)
    }
    elseif ($userSelection -eq "3") {
        #3 - Download AzCopy
        Get-AzCopyFromWeb
        Invoke-Option -userSelection (Get-Option)
    }
    elseif ($userSelection -eq "4") {
        #4 - Adjust AZCOPY_CONCURRENCY_VALUE
        Write-Host "Please select the value for AZCOPY_CONCURRENCY_VALUE" -BackgroundColor Black -ForegroundColor Yellow
        Write-Host "1 - Set to 1000"
        Write-Host "2 - Set to 2000"
        Write-Host "3 - Set to 3000" 
        Write-Host "4 - Set to default value based on CPU" 
        $acv = Read-Host -Prompt 'Please type the number for the corresponding option'
        if ($acv.Trim().ToLower() -eq "1") {
            Set-AzCopyConcurrency -on1k
        }
        elseif ($acv.Trim().ToLower() -eq "2") {
            Set-AzCopyConcurrency -on2k
        }
        elseif ($acv.Trim().ToLower() -eq "3") {
            Set-AzCopyConcurrency -on3k
        }
        elseif ($acv.Trim().ToLower() -eq "4") {
            Set-AzCopyConcurrency -off
        }
        else {
            Write-Host "Invalid option entered" -BackgroundColor Black -ForegroundColor Red
        }
        Invoke-Option -userSelection (Get-Option)
    }
    elseif ($userSelection -eq "8") {
        #8 -Exit
        break
    }
    else {
        Write-Host "You have selected an invalid option please select again." -ForegroundColor Red -BackgroundColor Black
        Invoke-Option -userSelection (Get-Option)
    }
}
#endregion functions

#region main
Write-Host "Welcome to the Azure Files Migrator Script" -BackgroundColor Black -ForegroundColor Cyan
Write-Host "Version 2.0 - Enhanced Edition" -BackgroundColor Black -ForegroundColor Cyan

# Check if user is logged into Azure
try {
    $context = Get-AzContext
    if ($null -eq $context -or $null -eq $context.Account) {
        Write-Host "`nYou are not logged into Azure. Please run 'Connect-AzAccount' first." -BackgroundColor Black -ForegroundColor Red
        Write-Host "Exiting script..." -BackgroundColor Black -ForegroundColor Yellow
        exit
    }
    Write-Host "`nAzure connection verified" -BackgroundColor Black -ForegroundColor Green
    Write-Host "Account: $($context.Account)" -BackgroundColor Black -ForegroundColor Green
    Write-Host "Subscription: $($context.Subscription.Name)" -BackgroundColor Black -ForegroundColor Green
}
catch {
    Write-Host "`nError checking Azure connection: $_" -BackgroundColor Black -ForegroundColor Red
    Write-Host "Please run 'Connect-AzAccount' and try again." -BackgroundColor Black -ForegroundColor Yellow
    exit
}

try {
    Invoke-Option -userSelection (Get-Option)
}
catch {
    Write-Host "`nAn error occurred: $_" -ForegroundColor Red -BackgroundColor Black
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red -BackgroundColor Black
    Write-Host "`nReturning to main menu..." -ForegroundColor Yellow -BackgroundColor Black
    Start-Sleep -Seconds 3
    try {
        Invoke-Option -userSelection (Get-Option)
    }
    catch {
        Write-Host "`nCritical error occurred. Exiting script." -ForegroundColor Red -BackgroundColor Black
        exit
    }
}
#endregion main