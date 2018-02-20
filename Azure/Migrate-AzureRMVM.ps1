
<#
.Synopsis
    Migrates (Copies) an Azure Resource Manager virtual machine from one subscrition to another. Can migrate between Tenets as well.
.Description
    Migrates (Copies) an Azure Resource Manager virtual machine from one subscrition to another. Can migrate between Tenets as well.
    This script will only work against Azure Resource Manager (ARM). It will not work against Azure Classic - Azure Service Manager (ASM).
    PROCESS:
        Connects/Logins to Azure Resource Manager.
        Gathers security context information about the source and destination subscriptions.
        Shut down the Virtual Machine in the source subscription.
        Gathers basic information about the Virtual Machine.
        Checks to see if the destination resource group exists, if not, create it.
        Gathers all disk information about the source VM.
            Create a Storage Account and Container if needed
            If the disks are managed and the source and destination subscriptions are in the same tenet, perform a managed disk snapshot copy. (Quick)
            If the disks are managed and the source and destination subscriptions are in different tenets, perform a blob copy. (Slow)
            If the disks are un-managed, perform a blob copy.(Slow)
        Creates a new VM in the destination resource group using the copied disk and a new network interface in the destination Subnet
    ASSUMPTIONS:
        The destination resource group for the virtual machine can be existing or a new one will be created.
        All artifacts for the virtual machine (VM, NIC, Storage Accounts, Disks)  will go into the same resource group.
        If a storage account is needed, one will be created based upon the VM name. It will meet Azure SA naming conventions.
        The destination virtual network must already exist. A new one will not be created.
        The destination subnet in the virtual network must already exist. A new one will not be created.
        The VM will get a dynamic private IP from the destination subnet.
        A public IP will not be assigned to the new VM. You must add this yourself if you need a public IP.
        A network security group will not be copied, nor will one be applied to the copied VM.
        If the source VM is using managed disks and a blob copy must be done between tenets, the VM will be converted back to Managed in the destination.
        The source VM will be left turned off and untouched.
.Parameter VMName
    The name of the virtual machine that is to be migrated.
.Parameter SourceSubscriptionName
    The name of the Azure RM subscription where the VM will be copied from.
.Parameter SourceResourceGroupName
    The name of the Azure RM Resource Group in the source subscription that the VM belongs to.
.Parameter DestSubscriptionName
    The name of the Destination subscription that the VM will be migrated to.
.Parameter DestResourceGroupName
    The name of the Destination Resource Group where the VM will be migrated to. This can be new or existing.
.Parameter DestVNetName
    The name of the Destination Virtual Network in the subscription where the VM will be migrated to. The virtual network must already exist, it will not be created new.
.Parameter DestSubnetName
    The name of the Destination Subnet in the virtual network where the VM will be migrated to. The Subnet must already exist, it will not be created new.
.Parameter DestNetworkResourceGroupName
    The name of the Resource Group where the destination virtual network exists.
.Example
	.\Migrate-AzureVM.ps1 -VMName "MySourceVM" -SourceSubscriptionName "SourceSubName" -SourceResourceGroupName "SourceRGName" -DestSubscriptionName "DestSubName" -DestResourceGroupName "DestRGName" -DestVNetName "DestVNETName" -DestSubnetName "DestSubnetName" -DestNetworkResourceGroupName "DestNetworkRGName"
.Link
    Get-Help about_functions
	Get-Help about_functions_advanced
    Get-Help about_functions_advanced_Parameters
    Get-Help about_Functions_CmdletBindingAttribute
    https://docs.microsoft.com/en-us/powershell/azure/overview?view=azurermps-5.3.0
.Notes
	Name     : Migrate-AzureRMVM.ps1
	Author   : Andy Stumph
	Lastedit : 2/20/2018
#>

#Requires -version 3.0
#Requires -module AzureRM.Profile
#Requires -module AzureRM.Compute
#Requires -module AzureRM.Network
#Requires -module AzureRM.Storage
#Requires -module AzureRM.Resources
#Requires -module Azure.Storage

[CmdletBinding(SupportsShouldProcess=$True)]

param
	(
		[Parameter(Mandatory=$True,Position=0,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
	    $VMName,

        [Parameter(Mandatory=$True,Position=1,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
	    $SourceSubscriptionName,

        [Parameter(Mandatory=$True,Position=2,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
	    $SourceResourceGroupName,

        [Parameter(Mandatory=$True,Position=3,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
	    $DestSubscriptionName,

        [Parameter(Mandatory=$True,Position=4,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
	    $DestResourceGroupName,

        [Parameter(Mandatory=$True,Position=5,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
	    $DestVNetName,

        [Parameter(Mandatory=$True,Position=5,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
	    $DestSubnetName,

        [Parameter(Mandatory=$True,Position=5,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
	    $DestNetworkResourceGroupName
		
	)#param
Begin
	{
		
        ## Modules
        Import-Module AzureRM.profile
        Import-Module AzureRM.Compute
        Import-Module AzureRM.Network
        Import-Module AzureRM.Storage
        Import-Module AzureRM.Resources
        Import-Module Azure.Storage
        
        ## Login
        try {
            $Login = Login-AzureRmAccount -ErrorAction Stop
            } catch {}

        ## Initialize some variables
        $ManagedDisk = $False

        $Convert = $False

        $DiskCopies = $null
        $NewManagedDisks = $null

        $DestStorageAccountName = "sa$($VMName.ToLower())"
        if ($DestStorageAccountName.Length -gt 24) {
            ## Storage account names can be max 24 chars long
            $DestStorageAccountName = $DestStorageAccountName.Substring(0,24)
        }
        $AlphaNumericOnly = "^[a-zA-Z0-9\s]+$"
        if ($DestStorageAccountName -notmatch $AlphaNumericOnly) {
            ## Remove any non alpha numeric chars
            $DestStorageAccountName = $DestStorageAccountName -replace "[^a-zA-Z0-9]", ''
        }

        $AllDisks = @()

        ## Functions ##

        function Write-Log {
            param
            (
                [String]$Message,
                [Switch]$IsError
            )

            if ($IsError) {
                Write-Error -Message "$((Get-Date).ToShortTimeString()) - $Message" -ErrorAction Stop
            } else {
                Write-Verbose -Message "$((Get-Date).ToShortTimeString()) - $Message" -Verbose
            }
        }

        function Stop-AzureVMNow {

            param
            (
                [Parameter(Mandatory=$True)]
                [String]$VMName,

                [Parameter(Mandatory=$True)]
                [String]$ResourceGroupName,

                [Parameter(Mandatory=$True)]
                $Context
            )
            
            try {
                $VMStatus = (Get-AzureRmVM -Name $VMName -ResourceGroupName $ResourceGroupName -DefaultProfile $Context -Status -ErrorAction Stop -Verbose).Statuses
            } catch {
                Write-Error "VM $VMName in Resource Group $ResourceGroupName was not found!"
                break
            }

            if ($VMStatus[1].Code -match "deallocated") {
                Write-Log -Message "VM $VMName is already deallocated..."
                return
            }

            try {
                Stop-AzureRmVM -Name $VMName -ResourceGroupName $ResourceGroupName -DefaultProfile $Context -Force -Verbose -ErrorAction Stop
            } catch {
                Write-Log -Message "Failed to perform Stop on $($VMName)!" -IsError
                return $_
            }

        }

        function Start-AzureVMNow {

            param
            (
                [Parameter(Mandatory=$True)]
                [String]$VMName,

                [Parameter(Mandatory=$True)]
                [String]$ResourceGroupName,

                [Parameter(Mandatory=$True)]
                $Context
            )
            
            try {
                $VMStatus = (Get-AzureRmVM -Name $VMName -ResourceGroupName $ResourceGroupName -DefaultProfile $Context -Status -ErrorAction Stop -Verbose).Statuses
            } catch {
                Write-Log "VM $VMName in Resource Group $ResourceGroupName was not found!" -IsError
                break
            }

            if ($VMStatus[1].Code -match "running") {
                Write-Log -Message "VM $VMName is already running/starated..."
                return
            }

            try {
                Start-AzureRmVM -Name $VMName -ResourceGroupName $ResourceGroupName -DefaultProfile $Context -Force -Verbose -ErrorAction Stop
            } catch {
                Write-Log -Message "Failed to perform Start on $($VMName)!" -IsError
            }

        }

        function Create-AzureRMResourceGroup {
            param
            (

                [Parameter(Mandatory=$True)]
                $Context,

                [Parameter(Mandatory=$True)]
                [String]$ResourceGroupName,

                [Parameter(Mandatory=$True)]
                [String]$Location

            )

            ## Check to see if the resource group exists, if not, create it
            $ResourceGroup = Get-AzureRmResourceGroup -Name $ResourceGroupName -DefaultProfile $Context -ErrorAction SilentlyContinue
            if ($ResourceGroup) {
                Write-Log -Message "Destination Resource Group already exists..."
                return $ResourceGroup
            } else {
                Write-Log -Message "Creating Resource Group $ResourceGroupName in $($Context.Subscription.Name)..."
                $NewResourceGroup = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location -DefaultProfile $Context
                return $NewResourceGroup
            }
        }

        function Create-AzureRMStorageAccount {
            param
            (

                [Parameter(Mandatory=$True)]
                $Context,

                [Parameter(Mandatory=$True)]
                [String]$ResourceGroupName,

                [Parameter(Mandatory=$True)]
                [String]$StorageAccountName,

                [Parameter(Mandatory=$True)]
                [String]$Location,

                [Parameter(Mandatory=$True)]
                [String]$SkuName,

                [Parameter(Mandatory=$True)]
                [String]$Kind

            )

            ## Check to see if the Storage account exists, if not, create it
            $StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -DefaultProfile $Context -ErrorAction SilentlyContinue
            if ($StorageAccount) {
                Write-Log -Message "Storage Account $StorageAccountName in $($Context.Subscription.Name) already exists..."
                return $StorageAccount
            } else {
                Write-Log -Message "Creating Storage Account $StorageAccountName in $($Context.Subscription.Name)..."
                $NewStorageAccount = New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $Location -SkuName $SkuName -Kind $Kind -DefaultProfile $Context
                return $NewStorageAccount
            }
        }

        function Create-AzureRMStorageContainer {
            param
            (

                [Parameter(Mandatory=$True)]
                [String]$ContainerName,
                
                [Parameter(Mandatory=$True)]
                $StorageAccountContext

            )
            
            $StorageContainer = Get-AzureStorageContainer -Name $ContainerName -Context $StorageAccountContext -ErrorAction SilentlyContinue
            if ($StorageContainer) {
                Write-Log -Message "Storage Container already exists..."
                return $StorageContainer
            } else {
                ## Add a small pause because Azure API can take it's time...
                Start-Sleep -Seconds 30
                Write-Log -Message "Create Storage Container $ContainerName ..."
                $NewStorageContainer = New-AzureStorageContainer -Name $ContainerName -Context $StorageAccountContext
                return $NewStorageContainer
            }

        }
        
        function Get-AzureRMManagedDisks {
            param
            (
                [Parameter(Mandatory=$True)]
                [Array]$Disks,

                [Parameter(Mandatory=$True)]
                [String]$ResourceGroupName,

                [Parameter(Mandatory=$True)]
                $SourceContext
            )

            $ManagedDisks = @()
            foreach ($Disk in $Disks) {
                $ManagedDisks += Get-AzureRmDisk -ResourceGroupName $ResourceGroupName -DiskName $Disk.Name -DefaultProfile $SourceContext
            }
            return $ManagedDisks
        }
        
        function Copy-AzureRMManagedDisks {
            param
            (
                [Parameter(Mandatory=$True)]
                [Array]$Disks,

                [Parameter(Mandatory=$True)]
                $SourceContext,

                [Parameter(Mandatory=$True)]
                [String]$SourceResourceGroupName,

                [Parameter(Mandatory=$True)]
                $DestContext,

                [Parameter(Mandatory=$True)]
                [String]$Location

            )

            $DiskCopies = @()
            ## Copy all disks
            foreach ($Disk in $Disks) {
                Write-Log -Message "Copying Disk $($Disk.Name)..."
                try {
                    $AzureRMDisk = Get-AzureRmDisk -ResourceGroupName $SourceResourceGroupName -DiskName $Disk.Name -DefaultProfile $SourceContext -Verbose -ErrorAction Stop
                    $DiskConfig = New-AzureRmDiskConfig -SourceResourceId $AzureRMDisk.Id -Location $Location -CreateOption Copy -DefaultProfile $SourceContext
                    $DiskCopies += New-AzureRmDisk -Disk $DiskConfig -DiskName $AzureRMDisk.Name -ResourceGroupName $DestResourceGroupName -DefaultProfile $DestContext -Verbose -ErrorAction Stop
                } catch {
                    Write-Log -Message "Failed to Copy managed disk $($Disk.Name)!" -IsError
                }
            }
            return $DiskCopies
        }

        function Copy-AzureRMUnManagedBlobDisks {
            param
            (
                [Parameter(Mandatory=$True)]
                [Array]$Disks,

                [Parameter(Mandatory=$True)]
                $SourceStorageAccountContext,

                [Parameter(Mandatory=$True)]
                $DestStorageAccountContext,

                [Parameter(Mandatory=$True)]
                $SourceStorageContainerName,

                [Parameter(Mandatory=$True)]
                $DestStorageContainerName
            )
            $DiskCopies = @()

            foreach ($Disk in $Disks) {
                $Blob = ($Disk.Vhd.Uri).split('/')[4]
                $DiskCopies += Start-AzureStorageBlobCopy -SrcBlob $Blob -Context $SourceStorageAccountContext -SrcContainer $SourceStorageContainerName -DestContext $DestStorageAccountContext -DestContainer $DestStorageContainerName -Verbose
            }
            return $DiskCopies
        }

        function Copy-AzureRMManagedBlobDisks {
             param
            (
                [Parameter(Mandatory=$True)]
                [Array]$Disks,

                [Parameter(Mandatory=$True)]
                $ResourceGroupName,

                [Parameter(Mandatory=$True)]
                $SourceContext,

                [Parameter(Mandatory=$True)]
                $DestStorageAccountContext,

                [Parameter(Mandatory=$True)]
                $DestStorageContainerName
            )
            $DiskCopies = @()

            foreach ($Disk in $Disks) {
                try {
                    $SAS = Grant-AzureRmDiskAccess -ResourceGroupName $ResourceGroupName -DiskName $Disk.Name -Access Read -DefaultProfile $SourceContext -DurationInSecond 43200 -Verbose -ErrorAction Stop
                    } catch {
                        Write-Log -Message "Failed to Grant read-only disk access to $($Disk.Name) in resource group $ResourceGroupName !" -IsError
                        }
                try {
                    $DiskCopies += Start-AzureStorageBlobCopy -AbsoluteUri $SAS.AccessSAS -DestContainer $DestStorageContainerName -DestBlob "$($Disk.Name).vhd" -DestContext $DestStorageAccountContext -Verbose -ErrorAction Stop
                    } catch {
                        Write-Log -Message "Failed to perform copy on $($Disk.Name) !" -IsError
                     }
            }
            return $DiskCopies
        }

        function Get-AzureRMStorageCopyState {
            param
            (
                [Parameter(Mandatory=$True)]
                [Array]$DiskCopies

            )
            $StartTime = Get-Date

            $DiskCopies | Get-AzureStorageBlobCopyState -WaitForComplete -Verbose

            $StopTime = Get-Date
            $Difference = $StopTime - $StartTime
            $ElapsedTime = "{0:hh} hours, {0:mm} minutes, {0:ss} seconds" -f $Difference
            Write-Log -Message "Blob Disk copy process took $($ElapsedTime)..."
        }

        function Create-AzureRMVMFromUnmanagedDisks {
            param
            (
                [Parameter(Mandatory=$True)]
                [String]$VMName,

                [Parameter(Mandatory=$True)]
                [Array]$Disks,

                [Parameter(Mandatory=$True)]
                [String]$ResourceGroupName,

                [Parameter(Mandatory=$True)]
                [String]$VirtualNetworkName,

                [Parameter(Mandatory=$True)]
                [String]$SubnetName,

                [Parameter(Mandatory=$True)]
                [String]$NetworkResourceGroupName,

                [Parameter(Mandatory=$True)]
                [String]$Location,

                [Parameter(Mandatory=$True)]
                [String]$VMSize,

                [Parameter(Mandatory=$True)]
                [String]$OSType,

                [Parameter(Mandatory=$True)]
                $Context
            )

            try {
                $VNet = Get-AzureRmVirtualNetwork -Name $VirtualNetworkName -ResourceGroupName $NetworkResourceGroupName -DefaultProfile $Context -ErrorAction Stop -Verbose
                $Subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $VNet -DefaultProfile $Context -ErrorAction Stop -Verbose
                $NetworkInterface = New-AzureRmNetworkInterface -Name "$($VMName)-NI" -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $Subnet.Id -DefaultProfile $Context
                } catch {
                    Write-Log -Message "Error creating network configuration for VM $VMName - $Error[0]" -IsError
                }
            $VMConfig = New-AzureRmVMConfig -VMName $VMName -VMSize $VMSize
            $VMConfig = Add-AzureRmVMNetworkInterface -VM $VMConfig -Id $NetworkInterface.Id
            foreach ($Disk in $Disks) {
                if ($Disks.IndexOf($Disk) -eq 0) {
                    #Add OS Disk
                    if ($OSType -eq "Windows") {
                    $VMconfig = Set-AzureRmVMOSDisk -VM $VMConfig -Name ($Disk.Name).Split('.')[0] -VhdUri $Disk.ICloudBlob.Uri.AbsoluteUri -CreateOption Attach -Windows -DefaultProfile $Context -ErrorAction Stop -Verbose
                    } elseif ($OSType -eq "Linux") {
                        $VMconfig = Set-AzureRmVMOSDisk -VM $VMConfig -Name ($Disk.Name).Split('.')[0] -VhdUri $Disk.ICloudBlob.Uri.AbsoluteUri -CreateOption Attach -Linux -DefaultProfile $Context -ErrorAction Stop -Verbose
                    }
                } else {
                    $VMConfig = Add-AzureRmVMDataDisk -VM $VMConfig -Name ($Disk.Name).Split('.')[0] -VhdUri $Disk.ICloudBlob.Uri.AbsoluteUri -CreateOption Attach -Lun $Disks.IndexOf($Disk) -Caching ReadOnly -DefaultProfile $Context -ErrorAction Stop -Verbose
                }
            }
            try {
                $VM = New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VMConfig -DefaultProfile $Context -ErrorAction Stop -Verbose
                return $VM
                } catch {
                    Write-Log -Message "Failed to create VM $VMName - $Error[0]" -IsError
                }
        }

        function Create-AzureRMVMFromManagedDisks {
            param
            (
                [Parameter(Mandatory=$True)]
                [String]$VMName,

                [Parameter(Mandatory=$True)]
                [Array]$Disks,

                [Parameter(Mandatory=$True)]
                [String]$ResourceGroupName,

                [Parameter(Mandatory=$True)]
                [String]$VirtualNetworkName,

                [Parameter(Mandatory=$True)]
                [String]$SubnetName,

                [Parameter(Mandatory=$True)]
                [String]$NetworkResourceGroupName,

                [Parameter(Mandatory=$True)]
                [String]$Location,

                [Parameter(Mandatory=$True)]
                [String]$VMSize,

                [Parameter(Mandatory=$True)]
                [String]$OSType,

                [Parameter(Mandatory=$True)]
                $Context
            )

            try {
                $VNet = Get-AzureRmVirtualNetwork -Name $VirtualNetworkName -ResourceGroupName $NetworkResourceGroupName -DefaultProfile $Context -ErrorAction Stop -Verbose
                $Subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $VNet -DefaultProfile $Context -ErrorAction Stop -Verbose
                $NetworkInterface = New-AzureRmNetworkInterface -Name "$($VMName)-NI" -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $Subnet.Id -DefaultProfile $Context
                } catch {
                    Write-Log -Message "Error creating network configuration for VM $VMName - $Error[0]" -IsError
                }
            $VMConfig = New-AzureRmVMConfig -VMName $VMName -VMSize $VMSize
            $VMConfig = Add-AzureRmVMNetworkInterface -VM $VMConfig -Id $NetworkInterface.Id
            foreach ($Disk in $Disks) {
                if ($Disks.IndexOf($Disk) -eq 0) {
                    #Add OS Disk
                    if ($OSType -eq "Windows") {
                    $VMconfig = Set-AzureRmVMOSDisk -VM $VMConfig -Name $Disk.Name -ManagedDiskId $Disk.Id -Caching ReadWrite -CreateOption Attach -Windows -DefaultProfile $Context -ErrorAction Stop -Verbose
                    } elseif ($OSType -eq "Linux") {
                        $VMconfig = Set-AzureRmVMOSDisk -VM $VMConfig -Name $Disk.Name -ManagedDiskId $Disk.Id -Caching ReadWrite -CreateOption Attach -Linux -DefaultProfile $Context -ErrorAction Stop -Verbose
                    }
                } else {
                    $VMConfig = Add-AzureRmVMDataDisk -VM $VMConfig -Name $Disk.Name -ManagedDiskId $Disk.Id -CreateOption Attach -Lun $Disks.IndexOf($Disk) -Caching ReadOnly -DefaultProfile $Context -ErrorAction Stop -Verbose
                }
            }
            try {
                $VM = New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VMConfig -DefaultProfile $Context -ErrorAction Stop -Verbose
                return $VM
                } catch {
                    Write-Log -Message "Failed to create VM $VMName - $Error[0]" -IsError
                }
        }
		
	}#Begin
Process 
	{

        ## Connect to source subscription
        Write-Log -Message "Getting Source and Destination Subscriptions context..."
        try {
            $DestContext = Select-AzureRmContext -InputObject (Select-AzureRmSubscription -SubscriptionName $DestSubscriptionName) -Verbose -ErrorAction Stop
            $SourceContext = Select-AzureRmContext -InputObject (Select-AzureRmSubscription -SubscriptionName $SourceSubscriptionName) -Verbose -ErrorAction Stop
            #$SourceSubscription = Select-AzureRmSubscription -SubscriptionName $SourceSubscriptionName -ErrorAction Stop -Verbose
        } catch {
            Write-Error -Message "Could not connect to subscription $($SourceSubscriptionName)!"
            break
        }

        ## Shut down source VM if not already deallocated
        Write-Log -Message "Attempting to deallocate (Stop) VM..."
        try {
            Stop-AzureVMNow -VMName $VMName -ResourceGroupName $SourceResourceGroupName -Context $SourceContext -Verbose -ErrorAction Stop
        } catch {
            Write-Error -Message "Could not deallocate VM $($VMName) in Resource Group $($SourceResourceGroupName). Please check. Stopping script."
            break 
        }

        ## Gather VM Info
        try {
            $VM = Get-AzureRmVM -ResourceGroupName $SourceResourceGroupName -Name $VMName -ErrorAction Stop
        } catch {Write-Error -Message "Could not get a handle to VM $VMName in Resource Group $SourceResourceGroupName"; break}

        $Location = $VM.Location
        $VMSize = $VM.HardwareProfile.VmSize
        $OSType = $VM.StorageProfile.OsDisk.OsType

        ## Create the destination resource group if it doesn't exist
        $DestResourceGroup = Create-AzureRMResourceGroup -Context $DestContext -ResourceGroupName $DestResourceGroupName -Location $Location -Verbose
        
        ## Check to see if VM is using Managed disks
        Write-Log -Message "Checking to see if VM is using Managed or Unmanaged disks..."
        if ($VM.StorageProfile.OsDisk.ManagedDisk) {
            Write-Log -Message "VM Disks are Managed."
            $ManagedDisk = $True
        } elseif ($VM.StorageProfile.OsDisk.Vhd) {
            Write-Log -Message "VM Disks are Unmanaged."
            $ManagedDisk = $False
        }

        ## Gather all disk info and copy ##       
        if ($ManagedDisk) {

            ## Gather all managed disk info
            $AllDisks += $VM.StorageProfile.OsDisk
            if ($VM.StorageProfile.DataDisks) {
                foreach ($Disk in $VM.StorageProfile.DataDisks) {
                    $AllDisks += $Disk
                }
            }

            ## If source and destination are differnt tenets, we have to blob copy the disks like unmanaged disk. Cross tenet migration is not supported on managed disks.
            if ($SourceContext.Tenant.Id -ne $DestContext.Tenant.Id) {
                Write-Log -Message "Source and Destination subscriptions are in different Tenets. Preparing to perform Blob copy..."
                
                ## Get the managed disks info
                $ManagedDisks = Get-AzureRmManagedDisks -Disks $AllDisks -ResourceGroupName $SourceResourceGroupName -SourceContext $SourceContext
                switch ($ManagedDisks[0].Sku.Name) {
                    "StandardLRS" {$SkuName = "Standard_LRS"}
                    "StandardZRS" {$SkuName = "Standard_ZRS"}
                    "StandardGRS" {$SkuName = "Standard_GRS"}
                    "StandardRAGRS" {$SkuName = "Standard_RAGRS"}
                    "PremiumLRS" {$SkuName = "Premium_LRS"}
                }
            
                ## Create new or use existing storage account in destination
                $DestStorageAccount = Create-AzureRMStorageAccount -Context $DestContext -ResourceGroupName $DestResourceGroupName -StorageAccountName $DestStorageAccountName -Location $Location -SkuName $SkuName -Kind Storage -Verbose
                $DestStorageAccountContext = $DestStorageAccount.Context

                ## Create new or use existing "vhds" container in storage account
                $DestStorageContainer = Create-AzureRMStorageContainer -ContainerName 'vhds' -StorageAccountContext $DestStorageAccountContext -Verbose

                ## Copy each disk to the destination storage account
                Write-Log -Message "Performing blob copies..."
                $DiskCopies = Copy-AzureRMManagedBlobDisks -Disks $ManagedDisks -ResourceGroupName $SourceResourceGroupName -SourceContext $SourceContext -DestStorageAccountContext $DestStorageAccountContext -DestStorageContainerName $DestStorageContainer.Name -Verbose

                ## Wait for all copies to complete
                Write-Log -Message "Waiting for Blob copies to complete...This could take some time..."
                Get-AzureRMStorageCopyState -DiskCopies $DiskCopies -Verbose

                ## VM will be converted back to Managed disk when complete.
                $Convert = $True

                
            } else {
                ## Source and destination tenet is the same, so we can do a much faster managed disk copy.
                Write-Log -Message "Source and Destination subscriptions are in the same Tenet. Performing a Managed disk snapshot copy..."
                $NewManagedDisks = Copy-AzureRMManagedDisks -Disks $AllDisks -SourceContext $SourceContext -SourceResourceGroupName $SourceResourceGroupName -DestContext $DestContext -Location $Location -Verbose

            }


        } elseif (!($ManagedDisk)) {
            
            ## Gather all unmanged disk info
            $AllDisks += $VM.StorageProfile.OsDisk
            if ($VM.StorageProfile.DataDisks) {
                foreach ($Disk in $VM.StorageProfile.DataDisks) {
                    $AllDisks += $Disk
                }
            }

            ## Get the source storage account info
            $SourceStorageAccountName = (($AllDisks[0].Vhd.Uri).Split('.')[0]).split('/')[2]
            $SourceStorageContainerName = ($AllDisks[0].Vhd.Uri).Split('/')[3]
            $SourceStorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $SourceResourceGroupName -Name $SourceStorageAccountName -DefaultProfile $SourceContext
            $SourceStorageAccountContext = $SourceStorageAccount.Context
            switch ($SourceStorageAccount.Sku.Name) {
                "StandardLRS" {$SkuName = "Standard_LRS"}
                "StandardZRS" {$SkuName = "Standard_ZRS"}
                "StandardGRS" {$SkuName = "Standard_GRS"}
                "StandardRAGRS" {$SkuName = "Standard_RAGRS"}
                "PremiumLRS" {$SkuName = "Premium_LRS"}
            }
            
            ## Create new or use existing storage account in destination
            $DestStorageAccount = Create-AzureRMStorageAccount -Context $DestContext -ResourceGroupName $DestResourceGroupName -StorageAccountName $DestStorageAccountName -Location $Location -SkuName $SkuName -Kind $SourceStorageAccount.Kind -Verbose
            $DestStorageAccountContext = $DestStorageAccount.Context

            ## Create new or use existing "vhds" container in storage account
            $DestStorageContainer = Create-AzureRMStorageContainer -ContainerName $SourceStorageContainerName -StorageAccountContext $DestStorageAccountContext -Verbose

            ## Copy each disk to the destination storage account
            Write-Log -Message "Performing blob copies..."
            $DiskCopies = Copy-AzureRMUnManagedBlobDisks -Disks $AllDisks -SourceStorageAccountContext $SourceStorageAccountContext -DestStorageAccountContext $DestStorageAccountContext -SourceStorageContainerName $SourceStorageContainerName -DestStorageContainerName $DestStorageContainer.Name -Verbose

            ## Wait for all copies to complete
            Write-Log -Message "Waiting for Blob copies to complete...This could take some time..."
            Get-AzureRMStorageCopyState -DiskCopies $DiskCopies -Verbose

        } else {
            Write-Log -Message "Could not determine if VM $VMName is using managed or unmanaged disks!" -IsError
            break
        }

        ## Recreate the VM in the destination subscription ##
        
        ## Check to see if this is using unmanaged disks
        if ($DiskCopies) {
            Write-Log -Message "Creating VM $VMName using unmanaged disks..."
            $NewVM = Create-AzureRMVMFromUnmanagedDisks -VMName $VMName -Disks $DiskCopies -ResourceGroupName $DestResourceGroupName -VirtualNetworkName $DestVNetName -SubnetName $DestSubnetName -NetworkResourceGroupName $DestNetworkResourceGroupName -Location $Location -VMSize $VMSize -OSType $OSType -Context $DestContext -Verbose
             ## If VM was originally using managed disks. Convert it.
            if ($Convert) {
                Write-Log -Message "Attempting to stop VM $VMName if it's running and convert it back to managed disks..."
                Stop-AzureVMNow -VMName $VMName -ResourceGroupName $DestResourceGroupName -Context $DestContext -Verbose
                ConvertTo-AzureRmVMManagedDisk -VMName $VMName -ResourceGroupName $DestResourceGroupName -DefaultProfile $DestContext -ErrorAction Stop -Verbose
                #Write-Log -Message "Attempting to Start VM $VMName ..."
                #Start-AzureVMNow -VMName $VMName -ResourceGroupName $DestResourceGroupName -Context $DestContext -Verbose
            }
        } elseif ($NewManagedDisks) {
            Write-Log -Message "Creating VM $VMName using managed disks..."
            $NewVm = Create-AzureRMVMFromManagedDisks -VMName $VMName -Disks $NewManagedDisks -ResourceGroupName $DestResourceGroupName -VirtualNetworkName $DestVNetName -SubnetName $DestSubnetName -NetworkResourceGroupName $DestNetworkResourceGroupName -Location $Location -VMSize $VMSize -OSType $OSType -Context $DestContext -Verbose
        } else {Write-Log -Message "Could not determine the type of disks that were used for migration! Cannot create VM." -IsError}

        ## Script complete
        Write-Log -Message "VM $VMName has been migrated. Script complete."
		
	}#Process


