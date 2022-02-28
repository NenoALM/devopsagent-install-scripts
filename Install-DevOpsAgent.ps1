#-------------------------------------------------------------------------------------------------#
# File        : Install-DevOpsAgent.ps1
# Description : Installs a new Azure DevOps Agent and configures it to run in interactive mode.
#-------------------------------------------------------------------------------------------------#

[CmdletBinding()]
param (
  # URL to Azure DevOps organization (e.g. https://dev.azure.com/<org>)
  [Parameter(Mandatory=$true)]
  [string] $azureDevOpsURL,

  # Personal access token with scope of 'Manage Agent Pools'
  [Parameter(Mandatory=$true)]
  [SecureString] $azureDevOpsPAT,

  # Name of agent pool to register the agent against
  [Parameter(Mandatory=$true)]
  [string] $agentPool,

  # Desired agent name (typically same as machine name)
  [Parameter(Mandatory=$true)]
  [string] $agentName,

  # Azure DevOps agent user
  [Parameter(Mandatory=$true)]
  [string] $agentUser,
  
  # Azure DevOps user password
  [Parameter(Mandatory=$true)]
  [SecureString]$agentPassword,

  # URL to download Pipelines agent ZIP file from
  [Parameter(Mandatory=$true)]
  [string] $agentDownloadUrl = 'https://vstsagentpackage.azureedge.net/agent/2.196.2/vsts-agent-win-x64-2.196.2.zip',

  # Drive letter where agent is to be installed
  [ValidatePattern("[a-zA-Z]")]
  [ValidateLength(1, 1)]
  [string] $driveLetter = 'C',

  # Temp folder where files will be downloaded to
  [string] $tempFolder = "$env:WINDIR/Temp",
  
  # Name + value of capability to set as environment variable
  [Parameter(Mandatory=$true)]
  [string] $capabilityName,

  [Parameter(Mandatory=$true)]
  [string] $capabilityValue
)

# Note: Because the $ErrorActionPreference is "Stop", this script will stop on first failure.  
$ErrorActionPreference = "Stop"

Write-Output "Script called with the following parameters:"
Write-Output "  azureDevOpsURL   : $azureDevOpsURL"
Write-Output "  agentPool        : $agentPool"
Write-Output "  agentName        : $agentName"
Write-Output "  agentUser        : $agentUser"
Write-Output "  agentDownloadUrl : $agentDownloadUrl"
Write-Output "  driveLetter      : $driveLetter"
Write-Output "  tempFolder       : $tempFolder"
Write-Output "  capabilityName   : $capabilityName"
Write-Output "  capabilityValue  : $capabilityValue"

#################### CAPABILITY ####################
$envVar = $capabilityName.ToUpper()
Write-Output "Set variable ""$envVar""=""$capabilityValue"""
[System.Environment]::SetEnvironmentVariable($envVar, $capabilityValue, "Machine")

#################### AGENT DOWNLOAD + EXTRACT ####################
$timeDownload = Measure-Command {
    Write-Output "Downloading Pipelines Agent..."
    $agentZip = "$tempFolder/agent.zip"
    (New-Object System.Net.WebClient).DownloadFile($agentDownloadUrl, $agentZip)
}
Write-Output "Finished: Downloading Pipelines Agent ($($timeDownload.ToString('g')))"

$timeExtract = Measure-Command {
    Write-Output "Exctracting DevOps Agent..."
    $agentDirectory = Join-Path -Path ($driveLetter + ":") -ChildPath "Agent"
    Expand-Archive -Path $agentZip -Destination $agentDirectory -Force
}
Write-Output "Finished: Exctracting DevOps Agent ($($timeExtract.ToString('g')))"

#################### AGENT INSTALL ####################
$timePrepare = Measure-Command {
    Write-Output "Preparing parameters..."

    $patCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "pat", $azureDevOpsPAT
    $token = $patCredential.GetNetworkCredential().password
    Write-Output "Length of token: "$token.Length" (should equal 52)"

    $pwdCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "service", $agentPassword
    $svcUserPwd = $pwdCredential.GetNetworkCredential().password
    Write-Output "Length of pwd: "$svcUserPwd.Length
}
Write-Output "Finished: Preparing parameters ($($timePrepare.ToString('g')))"

$timeConfig = Measure-Command {
    Write-Host "Configuring DevOps Agent..."
    $config = "$agentDirectory/config.cmd"
    Invoke-Expression "$config --version"
    Invoke-Expression "$config --unattended --norestart --url $azureDevOpsURL --auth pat --token $token --pool $agentPool --agent $agentName --runAsAutoLogon --windowsLogonAccount $agentUser --windowsLogonPassword '$svcUserPwd'"
}
Write-Output "Finished: Configuring DevOps Agent ($($timeConfig.ToString('g')))"

Write-Output "Done."
