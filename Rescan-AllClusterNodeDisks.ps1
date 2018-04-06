
<#
.Synopsis
    Script will perform a disk rescan on every node in a Windows Failover Cluster. Works remotely.
.Description
    Script will perform a disk rescan on every node in a Windows Failover Cluster. Works remotely.
.Parameter ClusterName
    Name of the Failover Cluster which you would like to perform the rescan on.
.Example
	.\Rescan-AllClusterNodeDisks.ps1 -ClusterName pbhypvclst03
.Link
    Get-Help about_functions
	Get-Help about_functions_advanced
    Get-Help about_functions_advanced_Parameters
    Get-Help about_Functions_CmdletBindingAttribute
.Notes
	Name     : Rescan-AllClusterNodesDisks.ps1
	Author   : Andy Stumph
	Lastedit : 01/14/2015
#>

#Requires -version 3.0

[CmdletBinding(SupportsShouldProcess=$True)]


param
	(
		[Parameter(Mandatory=$False,Position=0,ValueFromPipeLine=$True)]
	    [System.String]
	    $ClusterName
		
	)#param

$ClusterNodes = Get-ClusterNode -Cluster $ClusterName

foreach ($Node in $ClusterNodes) {

    $Node.Name
    Update-HostStorageCache -CimSession $Node.Name

}

