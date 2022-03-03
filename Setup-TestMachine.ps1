#-------------------------------------------------------------------------------------------------#
# File        : Setup-TestMachine.ps1
# Description : Configures an Azure VM with a Pipelines agent for CUIT test execution.
#-------------------------------------------------------------------------------------------------#

[CmdletBinding()]
param (
  # URL to Azure DevOps organization (e.g. https://dev.azure.com/<org>)
  [string] $azureDevOpsURL,

  # Personal access token with scope of 'Manage Agent Pools'
  [SecureString] $azureDevOpsPAT,

  # Name of agent pool to register the agent against
  [string] $agentPool,

  # Desired agent name (typically same as machine name)
  [string] $agentName,

  # If true, agent will run as auto logon. If false, agent will install as windows service.
  [bool] $agentInteractive,

  # Azure DevOps agent user and password
  [string] $agentUser,
  [SecureString] $agentPassword,

  # URL to download Pipelines agent ZIP file from
  [string] $agentDownloadUrl = 'https://vstsagentpackage.azureedge.net/agent/2.196.2/vsts-agent-win-x64-2.196.2.zip',

  # Drive letter where agent is to be installed
  [ValidatePattern("[a-zA-Z]")]
  [ValidateLength(1, 1)]
  [string] $driveLetter = 'C',

  # Temp folder where files will be downloaded to
  [string] $workDirectory = "${driveLetter}:\Agent",

  # Temp folder where files will be downloaded to
  [string] $tempDirectory = "$env:WINDIR\Temp",
  
  # Name + value of capability to set as environment variable
  [string] $capabilityName,
  [string] $capabilityValue
)

#--------------------------------------------------------------------------------#
# FUNCTIONS
#--------------------------------------------------------------------------------#

function Validate-Parameter {
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory=$true , #irony
            ValueFromPipeline=$true
        )]
        [object]
        $o ,
    
        [String]
        $Message
    )
    
        Begin {
            if (!$Message) {
                $Message = 'The specified parameter is required.'
            }
        }
    
        Process {
            if (!$o) {
                throw [System.ArgumentException]$Message
            }
        }
    }

#--------------------------------------------------------------------------------#
# MAIN
#--------------------------------------------------------------------------------#

# Note: Because the $ErrorActionPreference is "Stop", this script will stop on first failure.  
$ErrorActionPreference = "Stop"

$stopwatch = [System.Diagnostics.Stopwatch]::new()
$stopwatch.Start()

Write-Host "Script called with the following parameters:"
Write-Host "  azureDevOpsURL   : $azureDevOpsURL"
Write-Host "  agentPool        : $agentPool"
Write-Host "  agentName        : $agentName"
Write-Host "  agentInteractive : $agentInteractive"
Write-Host "  agentUser        : $agentUser"
Write-Host "  agentDownloadUrl : $agentDownloadUrl"
Write-Host "  driveLetter      : $driveLetter"
Write-Host "  workDirectory    : $workDirectory"
Write-Host "  tempDirectory    : $tempDirectory"
Write-Host "  capabilityName   : $capabilityName"
Write-Host "  capabilityValue  : $capabilityValue"

$azureDevOpsURL | Validate-Parameter -Message "-azureDevOpsURL is a required parameter"
$azureDevOpsPAT | Validate-Parameter -Message "-azureDevOpsPAT is a required parameter"
$agentPool | Validate-Parameter -Message "-agentPool is a required parameter"
$agentName | Validate-Parameter -Message "-agentName is a required parameter"
$agentUser | Validate-Parameter -Message "-agentUser is a required parameter"
$agentPassword | Validate-Parameter -Message "-agentPassword is a required parameter"
$agentDownloadUrl | Validate-Parameter -Message "-agentDownloadUrl is a required parameter"
$driveLetter | Validate-Parameter -Message "-driveLetter is a required parameter"
$workDirectory | Validate-Parameter -Message "-workDirectory is a required parameter"
$tempDirectory | Validate-Parameter -Message "-tempDirectory is a required parameter"
$capabilityName | Validate-Parameter -Message "-capabilityName is a required parameter"
$capabilityValue | Validate-Parameter -Message "-capabilityValue is a required parameter"

#--------------------------------------------------------------------------------#
# PREPARE PARAMETERS
#--------------------------------------------------------------------------------#
$timePrepare = Measure-Command {
    Write-Host "Preparing parameters..."

    $patCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "pat", $azureDevOpsPAT
    $token = $patCredential.GetNetworkCredential().password
    Write-Host "  Length of token: $($token.Length) (should equal 52)"

    $pwdCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "service", $agentPassword
    $svcUserPwd = $pwdCredential.GetNetworkCredential().password
    Write-Host "  Length of pwd: $($svcUserPwd.Length)"
}
Write-Host "Finished: Preparing parameters ($($timePrepare.ToString('g')))"

#--------------------------------------------------------------------------------#
# AGENT CAPABILITY
#--------------------------------------------------------------------------------#
$envVar = $capabilityName.ToUpper()
Write-Host "Set variable ""$envVar""=""$capabilityValue"""
[System.Environment]::SetEnvironmentVariable($envVar, $capabilityValue, "Machine")
[System.Environment]::SetEnvironmentVariable($envVar, $capabilityValue, "Process")

#--------------------------------------------------------------------------------#
# RENAME COMPUTER
#--------------------------------------------------------------------------------#
$timeRenamePC = Measure-Command {
    Write-Host "Renaming PC..."
    $currentComputerName = $env:COMPUTERNAME
    $newComputerName = $agentName

    if ($currentComputerName -ne $newComputerName)
    {
        Write-Host "  Rename computer from $currentComputerName to $newComputerName"
        Rename-Computer -NewName "$newComputerName" -Force
    }
    else {
        Write-Host "  Computer name is: $newComputerName. No changes."
    }
}
Write-Host "Finished: Renaming PC ($($timeRenamePC.ToString('g')))"

#--------------------------------------------------------------------------------#
# AGENT DOWNLOAD
#--------------------------------------------------------------------------------#
$timeDownload = Measure-Command {
    Write-Host "Downloading Pipelines Agent..."
    $agentZip = "$tempDirectory\agent.zip"
    Write-Host "  Target file: $agentZip"
    (New-Object System.Net.WebClient).DownloadFile($agentDownloadUrl, $agentZip)
}
Write-Host "Finished: Downloading Pipelines Agent ($($timeDownload.ToString('g')))"

#--------------------------------------------------------------------------------#
# AGENT EXTRACT
#--------------------------------------------------------------------------------#
$timeExtract = Measure-Command {
    Write-Host "Exctracting DevOps Agent..."
    $agentDirectory = Join-Path -Path ($driveLetter + ":") -ChildPath "Agent"
    Write-Host "  Target path: $agentDirectory"
    Expand-Archive -Path $agentZip -Destination $agentDirectory -Force
}
Write-Host "Finished: Exctracting DevOps Agent ($($timeExtract.ToString('g')))"

#--------------------------------------------------------------------------------#
# AGENT CONFIGURATION
#--------------------------------------------------------------------------------#
$timeConfig = Measure-Command {
    Write-Host "Configuring DevOps Agent..."
    $config = "$agentDirectory/config.cmd"
    Write-Host "  Command: $config"

    # see docs for parameters:
    # https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/v2-windows?view=azure-devops&WT.mc_id=DOP-MVP-21138#unattended-config
    if ($agentInteractive) {
        Write-Host "  Mode: --runAsAutoLogon"
        Invoke-Expression "$config --unattended --norestart --url $azureDevOpsURL --auth pat --token $token --pool $agentPool --agent $agentName --work $workDirectory --runAsAutoLogon --windowsLogonAccount $agentUser --windowsLogonPassword '$svcUserPwd'"
    }
    else {
        Write-Host "  Mode: --runAsService"
        Invoke-Expression "$config --unattended --norestart --url $azureDevOpsURL --auth pat --token $token --pool $agentPool --agent $agentName --work $workDirectory --runAsService --windowsLogonAccount $agentUser --windowsLogonPassword '$svcUserPwd'"
    }
    Write-Host "  Exit Code: $LASTEXITCODE"
    if ($LASTEXITCODE -ne 0)
    {
        $errMsg = 'Agent configuration failed.'
        Write-Host $errMsg
        Write-Error $errMsg
        Exit 1
    }
}
Write-Host "Finished: Configuring DevOps Agent ($($timeConfig.ToString('g')))"

$Stopwatch.Stop()
Write-Host "All done. ($($stopwatch.Elapsed.ToString('g')))"
