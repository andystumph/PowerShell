
#Requires -version 3.0
#Requires -module VirtualMachineManager

[CmdletBinding(SupportsShouldProcess=$True)]


param
	(
		[Parameter(Mandatory=$True,Position=0,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]$ComputerName,

        [Parameter(Mandatory=$False,Position=1,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]$VMMServer = "PBSCVMM101.hchb.local"
    )

if (Get-Module VirtualMachineManager) {
    Import-Module VirtualMachineManager
}

$SCVMMServer = Get-SCVMMServer -ComputerName $VMMServer

$VM = Get-SCVirtualMachine -Name $ComputerName

$vHBAs = $VM | Get-SCVirtualFibreChannelAdapter | Select-Object Name, SlotID, VirtualFibreChannelSAN, PrimaryWorldWidePortName, SecondaryWorldWidePortName

$vHBAs