#
# RemoveRDSSessionhost.ps1
#
param
(
	[string]$RDSConnectionBrokerFQDN,
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

#region remove RDS session host in AD
$ADScriptblock = {
	param
	(
		$RDSServerName
	)

	$RDSComputerAccount = Get-ADComputer $RDSServerName
	Remove-ADComputer $RDSComputerAccount -
}

#remove RDS session host from deployment
$RDSSessionHostNameFQDN = $env:COMPUTERNAME | Get-Fqdn
Remove-RDSessionHost -SessionHost $RDSSessionHostNameFQDN -ConnectionBroker $RDSConnectionBrokerFQDN -Force
Remove-RDServer -Server $RDSSessionHostNameFQDN -ConnectionBroker $RDSConnectionBrokerFQDN -Role RDS-RD-SERVER -Force

#remove RDS session host AD computer object
$RDSSessionHostName = $env:COMPUTERNAME
$EncryptedPassword = $ADPassword | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object -TypeName System.Management.Automation.PSCredential -argumentlist $ADUserName,$EncryptedPassword
Invoke-Command -ComputerName $DomainControllerName -ScriptBlock $ADScriptblock -Credential $cred -ArgumentList $RDSSessionHostName


