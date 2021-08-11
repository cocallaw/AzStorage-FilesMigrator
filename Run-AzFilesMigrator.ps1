#region variables
$azcopyURI = "https://aka.ms/downloadazcopy-v10-windows"
$AzCopySetup = "C:\AzCopy\DL"
$AzCopyWPath = "C:\AzCopy\"
#endregion vatiables

#region functions
function Get-Option {
    Write-Host "What would you like to do?"
    Write-Host "1 - Perform Azure Files Migration"
    Write-Host "2 - Select Azure Subscription"    
    Write-Host "3 - Download AzCopy"
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
    New-Item -Path $AzCopySetup -ItemType Directory -Force
    try {
        Start-BitsTransfer -Source $azcopyURI -Destination "$AzCopySetup\azcopy_windows_amd64.zip"
    }
    catch {
        Invoke-WebRequest -Uri $azcopyURI -OutFile "$AzCopySetup\azcopy_windows_amd64.zip"
    }
    Write-Host "Downloaded AzCopy to $AzCopySetup" -BackgroundColor Black -ForegroundColor Green
    Write-Host "Expanding and cleaning up azcopy_windows_amd64.zip" -BackgroundColor Black -ForegroundColor Green
    Expand-Archive "$AzCopySetup\azcopy_windows_amd64.zip" -DestinationPath "$AzCopyWPath" -ErrorAction SilentlyContinue
    $ci = Get-ChildItem -Path $AzCopyWPath -Include *.exe, *.txt -File -Recurse
    foreach ($file in $ci) { Copy-Item $file.FullName -Destination $AzCopyWPath }
    Remove-Item "$AzCopySetup" -Force -Recurse
    Remove-Item $ci.DirectoryName -Force -Recurse -ErrorAction SilentlyContinue
    Write-Host "AzCopy Tool is located at" $AzCopyWPath -BackgroundColor Black -ForegroundColor Green
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
    Write-Host "$L storage account is" $stg.StorageAccountName -BackgroundColor Black -ForegroundColor Green
    Write-Host "Getting list of avaialble file shares in" $stg.StorageAccountName -BackgroundColor Black -ForegroundColor Green
    $shares = Get-AzStorageShare -Context $stg.Context
    Write-Host "Please Select the $L file share in" $stg.StorageAccountName -BackgroundColor Black -ForegroundColor Yellow
    $share = $shares | ogv -Title "Select $L File Share" -PassThru
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
    &$AzCopyWPath\azcopy.exe copy "$srcurl" "$desturl" --recursive --preserve-smb-permissions=true --preserve-smb-info=true
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
    $csv = Import-Csv -Path $csvfilepath -Header uid
    Write-Host $csv.count"Items were imported from the CSV file provided"  -BackgroundColor Black -ForegroundColor Green
    return $csv 
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
    $sfiles = Get-AzStorageFile -Context $stgcontext -ShareName $share
    $ArrayList = New-Object -TypeName System.Collections.ArrayList
    foreach ($n in $names) {
        $a = $n.uid
        $b = $sfiles | where { $_.Name -like "*$a*" }
        if ($b -ne $null) {
            Write-Host "$a has been matched to" $b.Name
            $match = @{id = $a; dir = $b.Name } 
            $ArrayList += $match
        }
        else {
            Write-Host "$a has not been matched to any directory"
        }
    }
    return $ArrayList
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
                Write-Host "AzCopy Tool is required to properly package MSIX apps" -BackgroundColor Black -ForegroundColor Red
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
        Write-Host "2 - Copy multiple directories using a CSV - NOT WORKING"    
        $op = Read-Host -Prompt 'Please type the number of the option you would like to perform '
        if ($op.Trim().ToLower() -eq "1") {
            Write-Host "You have selected option 1" -BackgroundColor Black -ForegroundColor Green
            Write-Host "Please enter the source folder to copy" -BackgroundColor Black -ForegroundColor Yellow
            $srcdir = Read-Host -Prompt 'Please provide the name of the source directory to copy'
            $srcdir = $srcdir.Trim() 
            Copy-AzFileDirectory -srcstgacct $sinfo.StorageAcctName -srcshare $sinfo.ShareName -srcdirname $srcdir -srcSAS $ssas -deststgacct $dinfo.StorageAcctName -destshare $dinfo.ShareName -destdirname $srcdir -destSAS $dsas  
            Invoke-Option -userSelection (Get-Option)
        }
        elseif ($op.Trim().ToLower() -eq "2") {
            Write-Host "You have selected option 2" -BackgroundColor Black -ForegroundColor Green
            Write-Host "Please provide the CSV to use" -BackgroundColor Black -ForegroundColor Yellow
            $cfp = Get-CSVlistpath
            $cl = Get-CSVlist -csvfilepath $cfp
            $sm = Get-UIDShareMatches -names $cl -share $sinfo.ShareName -stgcontext $sinfo.StorageAcctContext

            #Ask user to confim the folder list then copy the files
            $fv = Read-Host -Prompt "Is this selection correct? (y/n)"
            if ($fv.Trim().ToLower() -eq "y") {
                $i = 0
                $time = Track-Time $time
                foreach ($s in $sm) {
                    Write-Host "Processing"+$s.id+"with the directory of"$s.dir
                    Copy-AzFileDirectory -srcstgacct $sinfo.StorageAcctName -srcshare $sinfo.ShareName -srcdirname $s.dir -srcSAS $ssas -deststgacct $dinfo.StorageAcctName -destshare $dinfo.ShareName -destdirname $s.dir -destSAS $dsas
                    $i++
                }
                $time = Track-Time $time
                Write-Host "Processing complete for $i objects" -BackgroundColor Black -ForegroundColor Green
                Write-Host "Processing time: " $time.Minutes "minutes" $time.Seconds "seconds" -BackgroundColor Black -ForegroundColor Green
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
Write-Host "Welcome to the Azure Files Migrator Script"
try {
    Invoke-Option -userSelection (Get-Option)
}
catch {
    Write-Host "Something went wrong" -ForegroundColor Yellow -BackgroundColor Black
    Invoke-Option -userSelection (Get-Option)
}
#endregion main