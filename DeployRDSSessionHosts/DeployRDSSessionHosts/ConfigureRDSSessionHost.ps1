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
	[string]$ADUserName
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
$EncryptedPassword = "01000000d08c9ddf0115d1118c7a00c04fc297eb01000000ed620ffaf9d6024997d8c9e8937be7890000000002000000000003660000c000000010000000d4e27e2bd290c1e6d73b3dfabd9f9dc80000000004800000a0000000100000008fa6dd01132471bdb7a5db704355b30120000000e5773dd09627a3264c36c43baf6c51ac86727cad87a11bafd98af4e5b637655714000000b674a1a84c530fc6588b13780c53d729d8b55357"
$cred = New-Object -TypeName System.Management.Automation.PSCredential -argumentlist $ADUserName,($EncryptedPassword | ConvertTo-SecureString)

#get RDS session host name
$RDSSessionHostName = $env:COMPUTERNAME
Invoke-Command -ComputerName $DomainControllerName -ScriptBlock $ADScriptblock -Credential $cred -ArgumentList $RDSSessionHostName,$RDSSessionHostADGroup

#endregion

#region add RDS session host to RDS deployment
$RDSSessionHostFQDN = $env:COMPUTERNAME | Get-Fqdn

Add-RDServer -Server $RDSSessionHostFQDN -Role RDS-RD-SERVER -ConnectionBroker $RDSConnectionBrokerFQDN

#endregion

#region add RDS session host to RDS collection
Add-RDSessionHost -CollectionName $RDSCollectionName -SessionHost $RDSSessionHostFQDN -ConnectionBroker $RDSConnectionBrokerFQDN
#endregion

#region reboot RDS session host to activate correct GPOs based on computer account membership
Restart-Computer -Force
#endregion