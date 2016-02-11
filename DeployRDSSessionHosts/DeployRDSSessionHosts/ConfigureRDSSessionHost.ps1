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

#region add RDS session host to RDS deployment
$RDSSessionHostFQDN = $env:COMPUTERNAME | Get-Fqdn

Add-RDServer -Server $RDSSessionHostFQDN -Role RDS-RD-SERVER -ConnectionBroker $RDSConnectionBrokerFQDN

#endregion

#region add RDS session host to RDS collection
Write-Output "$RDSCollectionName"
Add-RDSessionHost -CollectionName "$RDSCollectionName" -SessionHost $RDSSessionHostFQDN -ConnectionBroker $RDSConnectionBrokerFQDN
#endregion

#region reboot RDS session host to activate correct GPOs based on computer account membership
Restart-Computer -Force
#endregion