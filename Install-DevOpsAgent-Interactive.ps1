#-------------------------------------------------------------------------------------------------#
# File        : Install-DevOpsAgent-Interactive.ps1
# Description : Installs a new Azure DevOps Agent and configures it to run in interactive mode.
#-------------------------------------------------------------------------------------------------#

[CmdletBinding()]
param (
  # URL to Azure DevOps organization (e.g. https://dev.azure.com/<org>)
  [Parameter(Mandatory=$true)]
  [string]$azureDevOpsURL,

  # Personal access token with scope of 'Manage Agent Pools'
  [Parameter(Mandatory=$true)]
  [SecureString]$azureDevOpsPAT,

  # Name of agent pool to register the agent against
  [Parameter(Mandatory=$true)]
  [string]$agentPool,

  # Desired agent name (typically same as machine name)
  [Parameter(Mandatory=$true)]
  [string]$agentName,

  # Service user for Windows service
  [Parameter(Mandatory=$true)]
  [string]$agentServiceUser,
  
  # Service user password for Windows service
  [Parameter(Mandatory=$true)]
  [SecureString]$agentServicePassword,

  # Agent Directory
  [Parameter(Mandatory=$true)]
  [string]$agentDirectory,

  # Agent ZIP
  [Parameter(Mandatory=$true)]
  [string]$agentZip
)

# Note: Because the $ErrorActionPreference is "Stop", this script will stop on first failure.  
$ErrorActionPreference = "Stop"

Write-Host "Exctracting DevOps Agent..."
Expand-Archive -Path $agentZip -Destination $agentDirectory -Force

Write-Host "Configuring DevOps Agent..."
$patCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "pat", $azureDevOpsPAT
$token = $patCredential.GetNetworkCredential().password
write-host "Length of token: "$token.Length" (should equal 52)"

$pwdCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "service", $agentServicePassword
$svcUserPwd = $pwdCredential.GetNetworkCredential().password
write-host "Length of pwd: "$svcUserPwd.Length

$config = "$agentDirectory/config.cmd"
iex "$config --version"
iex "$config --unattended --url $azureDevOpsURL --auth pat --token $token --pool $agentPool --agent $agentName --runAsAutoLogon --windowsLogonAccount $agentServiceUser --windowsLogonPassword $svcUserPwd"
# Note: This does restart the VM!

Write-Host "Done."
