# AzStorage-FilesMigrator

To run this PowerShell Script from Powershell on yout local machine run the command below -

`Invoke-Expression $(Invoke-WebRequest -uri aka.ms/azfilescopyps -UseBasicParsing).Content`
 
or the shorthand version 

`iwr -useb aka.ms/azfilescopyps | iex`

To download a local copy of the latest version of the script run the command below -

 `Invoke-WebRequest -Uri aka.ms/azfilescopyps -OutFile Run-AzFilesMigrator.ps1`