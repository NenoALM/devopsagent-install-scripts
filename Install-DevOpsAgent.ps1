#-------------------------------------------------------------------------------------------------#
# File        : Install-DevOpsAgent.ps1
# Description : Installs a new Azure DevOps Agent and configures it to run in interactive mode.
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
  [SecureString]$agentPassword,

  # URL to download Pipelines agent ZIP file from
  [string] $agentDownloadUrl = 'https://vstsagentpackage.azureedge.net/agent/2.196.2/vsts-agent-win-x64-2.196.2.zip',

  # Drive letter where agent is to be installed
  [ValidatePattern("[a-zA-Z]")]
  [ValidateLength(1, 1)]
  [string] $driveLetter = 'C',

  # Temp folder where files will be downloaded to
  [string] $workDirectory = "${driveLetter}:/Agent",

  # Temp folder where files will be downloaded to
  [string] $tempDirectory = "$env:WINDIR/Temp",
  
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

Write-Output "Script called with the following parameters:"
Write-Output "  azureDevOpsURL   : $azureDevOpsURL"
Write-Output "  agentPool        : $agentPool"
Write-Output "  agentName        : $agentName"
Write-Output "  agentInteractive : $agentInteractive"
Write-Output "  agentUser        : $agentUser"
Write-Output "  agentDownloadUrl : $agentDownloadUrl"
Write-Output "  driveLetter      : $driveLetter"
Write-Output "  workDirectory    : $workDirectory"
Write-Output "  tempDirectory    : $tempDirectory"
Write-Output "  capabilityName   : $capabilityName"
Write-Output "  capabilityValue  : $capabilityValue"

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
# AGENT CAPABILITY
#--------------------------------------------------------------------------------#
$envVar = $capabilityName.ToUpper()
Write-Output "Set variable ""$envVar""=""$capabilityValue"""
[System.Environment]::SetEnvironmentVariable($envVar, $capabilityValue, "Machine")

#--------------------------------------------------------------------------------#
# AGENT DOWNLOAD
#--------------------------------------------------------------------------------#
$timeDownload = Measure-Command {
    Write-Output "Downloading Pipelines Agent..."
    $agentZip = "$tempDirectory/agent.zip"
    Write-Output "  Target file: $agentZip"
    (New-Object System.Net.WebClient).DownloadFile($agentDownloadUrl, $agentZip)
}
Write-Output "Finished: Downloading Pipelines Agent ($($timeDownload.ToString('g')))"

#--------------------------------------------------------------------------------#
# AGENT EXTRACT
#--------------------------------------------------------------------------------#
$timeExtract = Measure-Command {
    Write-Output "Exctracting DevOps Agent..."
    $agentDirectory = Join-Path -Path ($driveLetter + ":") -ChildPath "Agent"
    Write-Output "  Target path: $agentDirectory"
    Expand-Archive -Path $agentZip -Destination $agentDirectory -Force
}
Write-Output "Finished: Exctracting DevOps Agent ($($timeExtract.ToString('g')))"

#--------------------------------------------------------------------------------#
# PREPARE PARAMETERS
#--------------------------------------------------------------------------------#
$timePrepare = Measure-Command {
    Write-Output "Preparing parameters..."

    $patCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "pat", $azureDevOpsPAT
    $token = $patCredential.GetNetworkCredential().password
    Write-Output "Length of token: $($token.Length) (should equal 52)"

    $pwdCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "service", $agentPassword
    $svcUserPwd = $pwdCredential.GetNetworkCredential().password
    Write-Output "Length of pwd: $($svcUserPwd.Length)"
}
Write-Output "Finished: Preparing parameters ($($timePrepare.ToString('g')))"

#--------------------------------------------------------------------------------#
# AGENT CONFIGURATION
#--------------------------------------------------------------------------------#
$timeConfig = Measure-Command {
    Write-Host "Configuring DevOps Agent..."
    $config = "$agentDirectory/config.cmd"
    #Invoke-Expression "$config --version"

    # see docs for parameters:
    # https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/v2-windows?view=azure-devops&WT.mc_id=DOP-MVP-21138#unattended-config
    if ($agentInteractive) {
        Invoke-Expression "$config --unattended --norestart --url $azureDevOpsURL --auth pat --token $token --pool $agentPool --agent $agentName --work $workDirectory --runAsAutoLogon --windowsLogonAccount $agentUser --windowsLogonPassword '$svcUserPwd'"
    }
    else {
        Invoke-Expression "$config --unattended --norestart --url $azureDevOpsURL --auth pat --token $token --pool $agentPool --agent $agentName --work $workDirectory --runAsService --windowsLogonAccount $agentUser --windowsLogonPassword '$svcUserPwd'"
    }
    Write-Output "  Exit Code: $LASTEXITCODE"
    if ($LASTEXITCODE -ne 0)
    {
        $errMsg = 'Agent configuration failed.'
        Write-Output $errMsg
        Write-Error $errMsg
        Exit 1
    }
}
Write-Output "Finished: Configuring DevOps Agent ($($timeConfig.ToString('g')))"

Write-Output "All done."
