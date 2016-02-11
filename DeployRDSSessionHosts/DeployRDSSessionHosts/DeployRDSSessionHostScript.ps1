#
# DeployRDSSessionHostScript.ps1
#
#This script must be executed to start the deployment of an extra RDS session host in the RDS 2012 R2 farm
#This script adds the necessary computer accounts in Active Directory and starts a SCVMM Service Template deployment for the installation of the extra RDS session host

param
(
	[Parameter(Mandatory=$true)]
	[string]$SCVMMServiceTemplateName,

	[Parameter(Mandatory=$true)]
	[string]$SCVMMServiceConfigurationName,

	[Parameter(Mandatory=$true)]
	[string]$SCVMMCSVVolumeName,

	[Parameter(Mandatory=$true)]
	[string]$SCVMMServiceTemplateVersionNumber,

	[Parameter(Mandatory=$true)]
	[string]$SCVMMHostGroupName,

	[Parameter(Mandatory=$false)]
	[switch]$DeployNewService,

	[Parameter(Mandatory=$false)]
	[string]$SCVMMServerName,

	[Parameter(Mandatory=$false)]
	[string]$LogDirPath,

	[Parameter(Mandatory=$false)]
	[string]$RDSConnectionBrokerFQDN,

	[Parameter(Mandatory=$false)]
	[string]$RDSCollectionName,

	[Parameter(Mandatory=$true)]
	[string]$RDSSessionHostADGroup,

	[Parameter(Mandatory=$true)]
	[string]$ADUserName,

	[Parameter(Mandatory=$true)]
	[string]$ADPassword,

	[Parameter(Mandatory=$true)]
	[string]$DCName
)
Function WriteToLog
{
	param
	(
		[string]$LogPath,
		[string]$TextValue,
		[bool]$WriteError
	)

	Try
	{
		#create log file name
		$thisDate = (Get-Date -DisplayHint Date).ToLongDateString()
		$LogFileName = "DeployRDSSessionhost_$thisDate.log"

		#write content to log file
		if ($WriteError)
		{
			Add-Content -Value "[ERROR $(Get-Date -DisplayHint Time)] $TextValue" -Path "$LogPath\$LogFileName"
		}
		else
		{
			Add-Content -Value "[INFO $(Get-Date -DisplayHint Time)] $TextValue" -Path "$LogPath\$LogFileName"
		}
	}
	Catch
	{
		$ErrorMessage = $_.Exception.Message
		Write-Host "Error occured in WriteToLog function: $ErrorMessage" -ForegroundColor Red
	}

}

Try
{
	#add SCVMM module to powershell session
	Import-Module -Name "virtualmachinemanager"

	#get start time of execution of this script
	$deploymentStartTime = Get-Date -DisplayHint DateTime
	WriteToLog -LogPath $LogDirPath -TextValue "Start of RDS Session host deployment is $deploymentStartTime" -WriteError $false

	#get service template
    $ServiceTemplate = Get-SCServiceTemplate -VMMServer $SCVMMServerName -Name $SCVMMServiceTemplateName | ? {$_.Release -eq $SCVMMServiceTemplateVersionNumber}
	Write-Verbose "Discovered service template = $ServiceTemplate"

    #create service template config
    $hostgroup = Get-SCVMHostGroup -VMMServer $SCVMMServerName -Name $SCVMMHostGroupName
	Write-Verbose "Discovered SCVMM host group = $hostgroup"
    $ServiceConfig = New-SCServiceConfiguration -VMMServer $SCVMMServerName -ServiceTemplate $ServiceTemplate -Name $SCVMMServiceConfigurationName -VMHostGroup $hostgroup
	Write-Verbose "Discovered service template configuration = $ServiceConfig"

	#update service template config te perform placement on the configuration
    $ServiceUpdate = Update-SCServiceConfiguration -VMMServer $SCVMMServerName -ServiceConfiguration $ServiceConfig

	#check for errors on placement config
    if ($ServiceUpdate.DeploymentErrorList -ne $null)
    {
        Write-Host "Errors have occured during placement of VMs. Deployment script will stop." -ForegroundColor Red
        Write-Host $ServiceUpdate.DeploymentErrorList -ForegroundColor Red
        break
    }

	#set values for configuration items in service template
    Get-SCServiceSetting -ServiceConfiguration $ServiceConfig -Name "ConnectionBrokerFQDN" | Set-SCServiceSetting -Value $RDSConnectionBrokerFQDN | Out-Null
    Get-SCServiceSetting -ServiceConfiguration $ServiceConfig -Name "CollectionName" | Set-SCServiceSetting -Value $RDSCollectionName | Out-Null
	Get-SCServiceSetting -ServiceConfiguration $ServiceConfig -Name "RDSSessionhostADGroup" | Set-SCServiceSetting -Value $RDSSessionHostADGroup | Out-Null
	Get-SCServiceSetting -ServiceConfiguration $ServiceConfig -Name "ADUserName" | Set-SCServiceSetting -Value $ADUserName | Out-Null
	Get-SCServiceSetting -ServiceConfiguration $ServiceConfig -Name "DomainControllerName" | Set-SCServiceSetting -Value $DCName | Out-Null
	Get-SCServiceSetting -ServiceConfiguration $ServiceConfig -Name "ADPassword" | Set-SCServiceSetting -Value $ADPassword | Out-Null

	#region set csv paths
    $ComputerTier = Get-SCComputerTierConfiguration -VMMServer $SCVMMServerName -ServiceConfiguration $ServiceConfig

	#get VM configurations of VMs in service template
    $VMConfig = Get-SCVMConfiguration -VMMServer $SCVMMServerName -ComputerTierConfiguration $ComputerTier

	Write-Verbose "Set VM configuration for VM $($VMConfig.Name)"
	Set-SCVMConfiguration -VMMServer $SCVMMServerName -VMConfiguration $vmConfig -VMLocation $SCVMMCSVVolumeName | Out-Null
	#endregion

	if ($DeployNewService)
	{
		$NewService = New-SCService -VMMServer $SCVMMServerName -ServiceConfiguration $ServiceConfig -JobVariable "DeployRDSSessionhostServiceJob" -RunAsynchronously

		$JobNameString = $DeployRDSSessionhostServiceJob.CmdletName+" "+$DeployRDSSessionhostServiceJob.ResultName
		Write-Verbose "Deployment job name = $JobNameString"

		while ($DeployRDSSessionhostServiceJob.status -eq "Running")
		{
			Write-Progress -Activity "Creation of Service" -Status $DeployRDSSessionhostServiceJob.progress
			Start-Sleep -Seconds 5
		}

		$deploymentFinishTime = Get-Date -DisplayHint DateTime
		WriteToLog -LogPath $LogDirPath -TextValue "Deployment finished at $deploymentFinishTime" -WriteError $false
	}
}
Catch
{
	write-host "An error has occured" -ForegroundColor Red
    $errorMessage = $_.Exception.Message
	$errorLineInScript = $_.InvocationInfo.ScriptLineNumber
    Write-Host $errorMessage -ForegroundColor Red
    Write-Host "Error in code line: "$errorLineInScript -ForegroundColor Red

    if (Get-SCServiceConfiguration -Name $SCVMMServiceConfigurationName)
    {
        Remove-SCServiceConfiguration $ServiceConfig
    }

	WriteToLog -LogPath $LogDirPath -TextValue "Following error occured during the deployment of the RDS Session host: $errorMessage"
}