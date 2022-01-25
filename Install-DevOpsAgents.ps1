#-------------------------------------------------------------------------------------------------#
# File        : Install-DevOpsAgent.ps1
# Description : Installs a new Azure DevOps Agent and configures it as a Windows service.
#-------------------------------------------------------------------------------------------------#

#[CmdletBinding()]
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
  
  # URL to download Pipelines agent ZIP file from
  [string]$agentDownloadUrl = 'https://vstsagentpackage.azureedge.net/agent/2.196.2/vsts-agent-win-x64-2.196.2.zip',

  # Drive letter where agent is to be installed
  [ValidatePattern("[a-zA-Z]")]
  [ValidateLength(1, 1)]
  [string] $driveLetter = 'C'
)

# Note: Because the $ErrorActionPreference is "Stop", this script will stop on first failure.  
$ErrorActionPreference = "Stop"

Write-Output "+++ BEGIN : Download Pipelines Agent +++"

$agentZip = "$env:WINDIR/Temp/agent.zip"
(New-Object System.Net.WebClient).DownloadFile($agentDownloadUrl, $agentZip)

Write-Output "+++ END   : Download Pipelines Agent +++"
Write-Output "+++ BEGIN : Install Deploy-Agent as Service +++"

$deployDirectory = Join-Path -Path ($driveLetter + ":") -ChildPath "Deploy-$AgentName"

Write-Output 'Hello'

./Install-DevOpsAgent-Service.ps1 `
    -azureDevOpsURL $azureDevOpsURL `
    -azureDevOpsPAT $azureDevOpsPAT `
    -agentPool "$agentPool-deploy" `
    -agentName "Deploy-$agentName" `
    -agentServiceUser $agentServiceUser `
    -agentServicePassword $agentServicePassword `
    -agentDirectory $deployDirectory `
    -agentZip $agentZip

Write-Output "+++ END   : Install Deploy-Agent as Service +++"

Write-Output "+++ BEGIN : Install Agent in interactive mode +++"

$agentDirectory = Join-Path -Path ($driveLetter + ":") -ChildPath "Agent-$AgentName"

./Install-DevOpsAgent-Interactive.ps1 `
    -azureDevOpsURL $azureDevOpsURL `
    -azureDevOpsPAT $azureDevOpsPAT `
    -agentPool "$agentPool-agent" `
    -agentName "Agent-$agentName" `
    -agentServiceUser $agentServiceUser `
    -agentServicePassword $agentServicePassword `
    -agentDirectory $agentDirectory `
    -agentZip $agentZip

Write-Output "+++ END   : Install Agent in interactive mode +++"
Write-Output "All Done."
