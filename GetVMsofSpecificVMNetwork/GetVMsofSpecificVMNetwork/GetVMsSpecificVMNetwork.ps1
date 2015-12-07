#
# GetVMsSpecificVMNetwork.ps1
#
param
(
	[Parameter(Mandatory=$true)]
	[string]$VMNetwork
)

$foundVMs = @()
$VMs = Get-SCVirtualMachine

foreach ($vm in $VMs)
{
	$boolInVMNetwork = $false
	#get virtual adapters
	$vNICs = $vm | Get-SCVirtualNetworkAdapter

	foreach ($vNic in $vNICs)
	{
		if ($vNic.VMNetwork -eq $VMNetwork)
		{
			$boolInVMNetwork = $true
		}
	}

	if ($boolInVMNetwork)
	{
		$foundVMs += $vm
	}
}

$foundVMs | ft Name