#
# ConfigureRDSSessionHost.ps1
#
#This script is used by the RDS session host SCVMM service template to automatically deploy extra RDS session hosts in the existing RDS 2012 R2 Farm deployment
#INFO: error logging is handled by SCVMM deployment process

param
(
	[string]$RDSConnectionBrokerFQDN,
	[string]$RDSCollectionName,
	[string]$RDSSessionHostADGroup,
	[string]$DomainControllerName,
	[string]$ADUserName,
	[string]$ADPassword
)

function Get-Fqdn {
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $ComputerName
    )

    PROCESS {
        foreach ($Name in $ComputerName) {
            Resolve-DnsName -Name $Name -Type A | Select-Object -ExpandProperty Name
        }
    }
}

#region add RDS session host to correct AD security group
$ADScriptblock = {
	param
	(
		$RDSServerName,
		$RDSADGroup
	)

	$RDSComputerAccount = Get-ADComputer $RDSServerName
	Add-ADGroupMember -Identity $RDSADGroup -Members $RDSComputerAccount
}

#encrypted password of the account which is used to execute the AD script block
$EncryptedPassword = $ADPassword | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object -TypeName System.Management.Automation.PSCredential -argumentlist $ADUserName,$EncryptedPassword

#get RDS session host name
$RDSSessionHostName = $env:COMPUTERNAME
Invoke-Command -ComputerName $DomainControllerName -ScriptBlock $ADScriptblock -Credential $cred -ArgumentList $RDSSessionHostName,$RDSSessionHostADGroup

#endregion

#region add RDS session host to deployment and RDS collection
$RDSSessionHostFQDN = $env:COMPUTERNAME | Get-Fqdn
$AddRDSSessionHostScriptBlock = {
	param
	(
		$RDSColName,
		$RDSSHFQDN,
		$RDSConBrFQDN
	)

	Add-RDServer -Server $RDSSHFQDN -Role RDS-RD-SERVER -ConnectionBroker $RDSConBrFQDN -ErrorAction SilentlyContinue
	Add-RDSessionHost -CollectionName "$RDSColName" -SessionHost $RDSSHFQDN -ConnectionBroker $RDSConBrFQDN -ErrorAction SilentlyContinue
}

#Invoke-Command -ComputerName $RDSConnectionBrokerFQDN -ScriptBlock $AddRDSSessionHostScriptBlock -Credential $cred -ArgumentList "$RDSCollectionName", $RDSSessionHostFQDN, $RDSConnectionBrokerFQDN

Add-RDServer -Server $RDSSessionHostFQDN -Role RDS-RD-SERVER -ConnectionBroker $RDSConnectionBrokerFQDN -ErrorAction SilentlyContinue
Write-Output "Start sleep of configuration script for 30 seconds before adding session host to collection for the first time"
Start-Sleep -Seconds 30
Add-RDSessionHost -CollectionName "$RDSCollectionName" -SessionHost $RDSSessionHostFQDN -ConnectionBroker $RDSConnectionBrokerFQDN -ErrorAction SilentlyContinue

#possible bug in RDS powershell. A remove and re-add to the RDS collection should solve the "element not found" error when connecting to newly added RDS session host using connection broker
Write-Output "Start sleep of configuration script for 30 seconds before re-adding the session host to the collection"
Start-Sleep -Seconds 30

Remove-RDSessionHost -SessionHost $RDSSessionHostFQDN -ConnectionBroker $RDSConnectionBrokerFQDN -ErrorAction SilentlyContinue
Add-RDSessionHost -CollectionName "$RDSCollectionName" -SessionHost $RDSSessionHostFQDN -ConnectionBroker $RDSConnectionBrokerFQDN -ErrorAction SilentlyContinue

#endregion

#region add RDS session host to RDS gateway local group
$RDSGWScriptBlock = {
	param
	(
		$RDSSessionHostFQDN
	)
	Import-Module RemoteDesktopServices
	cd RDS:
	cd GatewayServer
	cd GatewayManagedComputerGroups
	cd 'RDS 2012 R2 Farm'
	cd computers

	New-Item -Name $RDSSessionHostFQDN
}

#get RDS gateway servername
$RDSGatewayServerNameFQDN = (Get-RDServer -ConnectionBroker $RDSConnectionBrokerFQDN | ? Roles -eq "RDS-GATEWAY").Server

#start scriptblock
Invoke-Command -ComputerName $RDSGatewayServerNameFQDN -Credential $cred -ScriptBlock $RDSGWScriptBlock -ArgumentList $RDSSessionHostFQDN

#endregion

#region reboot RDS session host to activate correct GPOs based on computer account membership
Restart-Computer -Force
#endregion