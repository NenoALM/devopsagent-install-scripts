#-------------------------------------------------------------------------------------------------#
# File        : Setup-TestMachine.ps1
# Description : 
#-------------------------------------------------------------------------------------------------#

[CmdletBinding()]
param (

  # Name + value of capability to set as environment variable
  [Parameter(Mandatory=$true)]
  [string] $capabilityName,

  [Parameter(Mandatory=$true)]
  [string] $capabilityValue
)

# Note: Because the $ErrorActionPreference is "Stop", this script will stop on first failure.  
$ErrorActionPreference = "Stop"

#################### CAPABILITY ####################
$envVar = $capabilityName.ToUpper()
Write-Output "Set variable ""$envVar""=""$capabilityValue"""
[System.Environment]::SetEnvironmentVariable($envVar, $capabilityValue, "Machine")
