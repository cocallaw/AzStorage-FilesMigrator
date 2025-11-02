# AzStorage-FilesMigrator

An interactive PowerShell tool for migrating files and directories between Azure File Shares with SMB permission preservation.

## Features

* **Interactive Menu-Driven Interface** - Easy to use with numbered options
* **Single or Batch Migration** - Copy individual directories or multiple using CSV files
* **SMB Permissions Preserved** - Maintains permissions and metadata during transfer
* **Progress Tracking** - Real-time progress bars and status updates
* **Comprehensive Logging** - Automatic logging to temp directory for troubleshooting
* **Error Handling** - Robust validation and error recovery
* **Azure AD Integration Filter** - Optionally filter storage accounts with AD integration
* **Configurable Concurrency** - Adjust AzCopy performance settings

## Prerequisites

* Current Version of [Azure PowerShell](https://docs.microsoft.com/en-us/powershell/azure/install-az-p) (Az module)
* User must be logged into Azure PowerShell with appropriate RBAC permissions:
  - Read access to source storage account and file share
  - Write access to destination storage account and file share
* Windows operating system (for AzCopy download functionality)

## How to Run

### Option 1: Run directly from web (latest version)

```powershell
Invoke-Expression $(Invoke-WebRequest -uri aka.ms/azfilescopyps -UseBasicParsing).Content
```
 
Or the shorthand version:

```powershell
iwr -useb aka.ms/azfilescopyps | iex
```

### Option 2: Download and run locally

```powershell
Invoke-WebRequest -Uri aka.ms/azfilescopyps -OutFile Run-AzFilesMigrator.ps1
.\Run-AzFilesMigrator.ps1
```

## Usage

1. **Connect to Azure** (if not already connected):
   ```powershell
   Connect-AzAccount
   ```

2. **Run the script** - Follow the interactive menu:
   - Option 1: Perform Azure Files Migration
   - Option 2: Select Azure Subscription
   - Option 3: Download AzCopy (if not already installed)
   - Option 4: Adjust AZCOPY_CONCURRENCY_VALUE for performance tuning
   - Option 8: Exit

3. **For batch migrations**, prepare a CSV file with directory names:
   ```csv
   uid
   directory1
   directory2
   directory3
   ```

## Enhanced Features (v2.0)

### Performance Improvements
- Fixed environment variable handling for AzCopy concurrency settings
- Added progress bars for long-running operations
- Optimized file matching with server-side filtering
- Added detailed progress tracking for batch operations

### Usability Improvements
- Comprehensive input validation and error handling
- Azure login verification at startup
- Better error messages with context
- Success/failure tracking with migration summaries
- Automatic logging to temp directory
- Fixed parameter naming bugs in copy functions
- CSV header validation and examples

### Reliability Improvements
- Enhanced error handling with try-catch blocks
- Storage account and file share validation
- CSV file existence checking
- AzCopy installation verification
- Better error recovery and user guidance

## Logging

Logs are automatically created in your temp directory with the format:
```
%TEMP%\AzFilesMigrator_YYYYMMDD_HHmmss.log
```

The log location is displayed when the script starts and after batch migrations complete.

## Troubleshooting

- **"Not logged into Azure"**: Run `Connect-AzAccount` first
- **"AzCopy not found"**: Use Option 3 to download AzCopy
- **Permission errors**: Ensure you have proper RBAC roles on storage accounts
- **CSV errors**: Ensure CSV file has "uid" as the header (first line)
- Check the log file for detailed error information

## Version History

- **v2.0** - Enhanced edition with improved performance, usability, and error handling
- **v1.0** - Initial release
