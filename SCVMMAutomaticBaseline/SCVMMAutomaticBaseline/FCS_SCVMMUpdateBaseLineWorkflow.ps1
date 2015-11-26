#
# FCS_SCVMMUpdateBaseLineWorkflow.ps1
#
Workflow FCS_SCVMMUpdateBaseLineWorkflow
{
	#region get automation variables
	
	#get SCVMM connection settings
	$SCVMMServerModuleCon = Get-AutomationConnection -Name "FCS_SCVMMServerConnection"

	#endregion

	#region generate variables from SCVMM automation variable
	if ($SCVMMServerModuleCon -eq $null)
	{
		Write-Output "SCVMM Connection asset FCS_SCVMMServerConnection is not configured"
	}
	else
	{
		$SCVMMServer = $SCVMMServerModuleCon.ComputerName
		$SCVMMServerPassword = ConvertTo-SecureString -AsPlainText -String $SCVMMServerModuleCon.Password -Force
		$SCVMMServerCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $SCVMMServerModuleCon.Username, $SCVMMServerPassword
	}
	#endregion



	#region start inline script to run the script for update baseline automation
	InlineScript
	{
		#update function
		Function Update-BaseLineUpdates
		{
			Param
			(
				 [Parameter(Mandatory=$false,
				 ValueFromPipeline=$true,
				 ValueFromPipelineByPropertyName=$true,
				 ValueFromRemainingArguments=$false,
				 Position=0)]
				 [String]
				 $BaseLineName,

				[Parameter(Mandatory=$true)]
				[string]$SCVMMServer
			)

			$baseline = Get-SCBaseline -VMMserver $SCVMMServer -Name $BaseLineName

			# Set-SCBaseline -Baseline $baseline -Name $BaseLineName -Description $BaseLineName -RemoveUpdates $baseline.Updates
			Write-Output "Current number of Updates in Baseline $BaseLineName = $($baseline.UpdateCount)"

			$addedUpdateList = ""
			$addedUpdateList = @()

			if ($baseline.UpdateCount -eq 0) 
			{ 
				Write-Output "No previous updates in $BaselineName, adding all existing updates for $BaseLineName from WSUS"  
				$addedUpdateList += Get-SCUpdate -VMMServer $SCVMMServer | Where-Object -Property UpdateClassification -EQ -Value $BaseLineName | Where-Object -Property IsApproved -Like -Value "True" | Where-Object -Property IsDeclined -Like -Value "False"| Where-Object -Property IsExpired -Like -Value "False" | Where-Object -Property IsSuperseded -Like -Value "False" | Where-Object -Property Products -like "*Windows Server 2012*"
				Write-Output "Number of new updates to be added in $Baseline = $($addedUpdateList.Count)"
				Set-SCBaseline -VMMServer $SCVMMServer -Baseline $baseline -Name $BaseLineName -Description $BaseLineName -AddUpdates $addedUpdateList -RunAsynchronously | Out-Null
			}

			if ($baseline.UpdateCount -gt 0 ) 
			{ 
				Write-Output "Scanning Newest 500 WSUS Updates for matching updates for $BaselineName" 
				$LatestUpdates = Get-SCUpdate -VMMServer $SCVMMServer -Newest 500 | Where-Object -Property UpdateClassification -EQ -Value $BaseLineName | Where-Object -Property IsApproved -Like -Value "True" | Where-Object -Property IsDeclined -Like -Value "False"| Where-Object -Property IsExpired -Like -Value "False" | Where-Object -Property IsSuperseded -Like -Value "False" | Where-Object -Property Products -like "*Windows Server 2012*"
				Write-Output "$($LatestUpdates.Count) updates found, verifying if update(s) already exist in $BaseLineName"

				Compare-Object -ReferenceObject $baseline.Updates -DifferenceObject $LatestUpdates -IncludeEqual | % {
				if($_.SideIndicator -eq '=>') { $addedUpdateList += Get-SCUpdate -VMMServer $SCVMMServer -ID $_.inputobject.id } 
				}

				Write-Output "Number of new updates to be added to SCVMM for $BaseLineName = $($addedUpdateList.Count)" 
				Write-Output $addedUpdateList | ft
				Set-SCBaseline -VMMServer $SCVMMServer -Baseline $baseline -Name $BaseLineName -Description $BaseLineName -AddUpdate $addedupdateList -RunAsynchronously | Out-Null
			}

			Write-Output "Scan WSUS for updates that should not be checked anymore" 
			$remove = ""
			$remove = @()
			$removeUpdateList = ""
			$removeUpdateList = @()

			$remove += Get-SCUpdate -VMMServer $SCVMMServer | Where-Object -Property UpdateClassification -EQ -Value $BaseLineName | Where-Object -Property IsApproved -Like -Value "False" | Where-Object -Property Products -like "*Windows Server 2012*"
			$remove += Get-SCUpdate -VMMServer $SCVMMServer | Where-Object -Property UpdateClassification -EQ -Value $BaseLineName | Where-Object -Property IsDeclined -Like -Value "True"| Where-Object -Property Products -like "*Windows Server 2012*"
			$remove += Get-SCUpdate -VMMServer $SCVMMServer | Where-Object -Property UpdateClassification -EQ -Value $BaseLineName | Where-Object -Property IsExpired -Like -Value "True" | Where-Object -Property Products -like "*Windows Server 2012*"
			$remove += Get-SCUpdate -VMMServer $SCVMMServer | Where-Object -Property UpdateClassification -EQ -Value $BaseLineName | Where-Object -Property IsSuperseded -Like -Value "True" | Where-Object -Property Products -like "*Windows Server 2012*"

			Write-Output "Number of unapproved/superseded/expired/declined updates to be removed = $($remove.count)" 

			Compare-Object -ReferenceObject $baseline.Updates -DifferenceObject $remove -IncludeEqual | % {
			if($_.SideIndicator -eq '==') { $removeUpdateList += Get-SCUpdate -VMMServer $SCVMMServer -ID $_.inputobject.id } 
			}

			Set-SCBaseline -VMMServer $SCVMMServer -Baseline $baseline -Name $BaseLineName -Description $BaseLineName -RemoveUpdates $RemoveupdateList | Out-Null
		}

		Write-Output "Synchronizing with WSUS server..." 
		Get-SCUpdateServer -VMMServer $SCVMMServer | Start-SCUpdateServerSynchronization | out-null

		. Update-BaseLineUpdates -BaseLineName "Security Updates" -SCVMMServer $Using:SCVMMServer
		. Update-BaseLineUpdates -BaseLineName "Critical Updates" -SCVMMServer $Using:SCVMMServer
		. Update-BaseLineUpdates -BaseLineName "Updates" -SCVMMServer $Using:SCVMMServer
		. Update-BaseLineUpdates -BaseLineName "Update Rollups" -SCVMMServer $Using:SCVMMServer

	} -PSComputerName $SCVMMServer -PSCredential $SCVMMServerCred
	#endregion
}