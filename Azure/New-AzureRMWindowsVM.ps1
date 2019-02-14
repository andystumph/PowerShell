<#
.Synopsis
    Creates a VM in Azure. Optionally, the VM can be placed in an Availability Set and/or joined to the domain.
.Description
    Creates a VM in Azure. 
    You can select from Windows Server 2012 R2, Server 2016, or Server 2019.
    Any size VM can be created. For valid VM Sizes, run Get-AzureRMVMSize -Location <region>
    A Resource group will be created if it does not alredy exist. 
    The VNet and Subnet will not be created. They must already exist in the supplied subscription.
    Optional - If an Availability Set name is passed as a parameter, the VM will be placed in that. The Availability Set can already exist, or will be created.
    Optional - The JoinDomain switch will join the VM to the hchb.local domain.
    The script does not handle Network Security Groups (NSG) at all.
.Parameter VMName
    Common name of the Azure VM resource. This will also be the Computer name in the operating system.
.Parameter SubscriptionName
    Name of the Azure subscription to place the VM in.
.Parameter ResourceGroupName
    Name of the Azure resource group to place the VM in. If it does not already exist, it will be created.
.Parameter Location
    Name of the region to place the VM in. Must be "East US", "West US", "East US 2", or "West US 2".
.Parameter WindowsSKU
    Version of the windows operating system for the VM. Must be "2012-R2-Datacenter", "2016-Datacenter", or "2019-Datacenter".
.Parameter VMSize
    Size of the VM hardware. Use "Get-AzureRMVMSize -Location <region>" for valid VM sizes in a region.
.Parameter VNetName
    Name of an existing VNet in the chosed subscription.
.Parameter VNetResourceGroupName
    Name of the resource group that contains the VNet to be used.
.Parameter SubnetName
    Name of the Subnet within the VNet to place the VM in.
.Parameter AvailabilitySetName
    Optional parameter to use an existing Availability Set or create a new one for the VM to be placed in.
.Parameter JoinDomain
    Optional Boolean switch. If true, the VM will be joined to the hchb.local domain.

.Example
	.\New-AzureRMWindowsVM.ps1 -VMName ScriptedVMTest9 -SubscriptionName HCHB_NONPROD -ResourceGroupName RG_Servers_test -Location 'East US' -WindowsSKU '2019-Datacenter' -VMSize Standard_D2_v2 -VNetName vnet_nonprod_east -vnetresourcegroupname rg_nonprod_east_network -SubnetName Infrastructure -AvailabilitySetName as_scriptedvmtest_ue_prd -JoinDomain -Verbose
.Link
    Get-Help about_functions
	Get-Help about_functions_advanced
    Get-Help about_functions_advanced_Parameters
    Get-Help about_Functions_CmdletBindingAttribute
.Notes
	Name     : New-AzureRMWindowsVM.ps1
	Author   : AStumph@
	Lastedit : 02/14/2019
#>

#Requires -version 5.0
#Requires -module AzureRM.Profile
#Requires -module AzureRM.Resources
#Requires -module AzureRM.Compute
#Requires -module AzureRM.Network
#Requires -module AzureRM.KeyVault

[CmdletBinding(SupportsShouldProcess=$True)]

param
	(
		[Parameter(Mandatory=$True,Position=0,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
        $VMName,
        
        [Parameter(Mandatory=$True,Position=1,ValueFromPipeLine=$True)]
        [ValidateSet("HCHB_NONPROD", "HCHB_PROD", "HCHB_CORP", "HCHB_PIPELINE")]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
        $SubscriptionName,

        [Parameter(Mandatory=$True,Position=2,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
        $ResourceGroupName,

        [Parameter(Mandatory=$True,Position=3,ValueFromPipeLine=$True)]
        [ValidateSet("East US", "West US", "East US 2", "West US 2")]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
        $Location,

        [Parameter(Mandatory=$True,Position=4,ValueFromPipeLine=$True)]
        [ValidateSet("2012-R2-Datacenter", "2016-Datacenter", "2019-Datacenter")]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
        $WindowsSKU,

        [Parameter(Mandatory=$True,Position=5,ValueFromPipeLine=$True)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Get-AzureRmVMSize -Location $Location | Where-Object Name -eq $_})]
	    [System.String]
        $VMSize,

        [Parameter(Mandatory=$True,Position=6,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
        $VNetName,

        [Parameter(Mandatory=$True,Position=7,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
        $VNetResourceGroupName,

        [Parameter(Mandatory=$True,Position=8,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
        $SubnetName,

        [Parameter(Mandatory=$False,Position=9,ValueFromPipeLine=$True)]
	    [System.String]
        $AvailabilitySetName,

        [Parameter(Mandatory=$False,Position=10,ValueFromPipeLine=$True)]
	    [Switch]
        $JoinDomain
		
	)#param
Begin
	{
        Import-Module AzureRM.profile
        Import-Module AzureRM.Compute
        
        $AzureAccount = Login-AzureRmAccount -ErrorAction SilentlyContinue
        $Context = Set-AzureRmContext -SubscriptionName $SubscriptionName
        
        ## Variables
        $VMName = $VMName.ToUpper()
        $ComputerName = $VMName
        $NICName = "$($VMName)_NIC"
        $ResourceGroupName = $ResourceGroupName.ToUpper()
        $AvailabilitySetName = $AvailabilitySetName.ToUpper()
        $Publisher = "MicrosoftWindowsServer"
        $Offer = "WindowsServer"
        $LicenseType = "Windows_Server"
        $VaultName = "KV-HCHB-TECHOPS-UE2-PRD"
        $LocalAdminName = "hchbadmin"
        Write-Verbose -Message "Retrieving secret password for $($LocalAdminName) from KeyVault $($VaultName)..."
        $LocalAdminPassword = (Get-AzureKeyVaultSecret -VaultName $VaultName  -Name $LocalAdminName).SecretValueText | ConvertTo-SecureString -AsPlainText -Force
        if ($LocalAdminPassword -eq $null){
            Write-Verbose -Message "Could not retrieve secret password for $($LocalAdminName) from KeyVault $($VaultName)"
            Write-Error -Message "Could not retrieve secret password for $($LocalAdminName) from KeyVault $($VaultName)"
            exit
        }
        $Credential = New-Object System.Management.Automation.PSCredential($LocalAdminName,$LocalAdminPassword)

        ## Logging/Diagnostics Info
        if ($SubscriptionName -eq "HCHB_PROD") {
            $LoggingResourceGroupName = "RG_LOGGING_PROD"
            $LoggingStorageAccountName = "saloggingprod"

        }

        if ($SubscriptionName -eq "HCHB_NONPROD") {
            $LoggingResourceGroupName = "RG_LOGGING_NONPROD"
            $LoggingStorageAccountName = "saloggingnonprod"
        }

        ## Join To Domain Info
        if ($JoinDomain){
            $DomainName = "hchb.local"
            $JoinUser = "azure-svc-join-dom"
            Write-Verbose -Message "Retrieving secret password for $($JoinUser) from KeyVault $($VaultName)..."
            $JoinPassword = (Get-AzureKeyVaultSecret -VaultName $VaultName  -Name $JoinUser).SecretValueText | ConvertTo-SecureString -AsPlainText -Force
            if ($JoinPassword -eq $null){
                Write-Verbose -Message "Could not retrieve secret password from KeyVault $($VaultName)"
                Write-Error -Message "Could not retrieve secret password from KeyVault $($VaultName)"
                exit
            }
            $JoinCred = New-Object System.Management.Automation.PSCredential("$($JoinUser)@$($DomainName)",$JoinPassword)
            $OUPath = "OU=Utility,OU=Servers,OU=Hosted Resources,DC=hchb,DC=local"

        }

        ## Validate ResourceGroup
            ## If the Resource Group does not exist, we will create it later
        $RG = Get-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location -ErrorAction SilentlyContinue
        
        ## Validate VNet and Subnet
            ## VNet and Subnet must already exist. We will not create it.
        $VNet = Get-AzureRmVirtualNetwork -Name $VNetName -ResourceGroupName $VNetResourceGroupName -ErrorAction SilentlyContinue
        if (!($VNet)) {
            Write-Verbose -Message "VNet $($VNetName) does not exist in Resource Group $($VNetResourceGroupName) in Subscription $($SubscriptionName). It must be created first."
            Write-Error -Message "VNet $($VNetName) does not exist in Resource Group $($VNetResourceGroupName) in Subscription $($SubscriptionName). It must be created first."
            exit
        }

        $Subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $VNet -ErrorAction SilentlyContinue
        if (!($Subnet)) {
            Write-Verbose -Message "Subnet $($SubnetName) does not exist in VNet $($VNetName). It must be created first."
            Write-Error -Message "Subnet $($SubnetName) does not exist in VNet $($VNetName). It must be created first."
            exit
        }
        
        ## Validate Availability Set
        if ($AvailabilitySetName) {
            ## If the Availability Set does not exist, we will create it later.
            $AS = Get-AzureRmAvailabilitySet -ResourceGroupName $ResourceGroupName -Name $AvailabilitySetName -ErrorAction SilentlyContinue
            if ($AS){
                if ($AS.Sku -ne "Aligned"){
                    Write-Verbose -Message "Availability Set $($AvailabilitySetName) exists, but it does not have a SKU of 'Aligned'. This AS cannot be used with VMs with managed disks."
                    Write-Error -Message "Availability Set $($AvailabilitySetName) exists, but it does not have a SKU of 'Aligned'. This AS cannot be used with VMs with managed disks."
                    exit
                }
            }
        }


		
	}#Begin
Process 
	{
        if ($RG -eq $null) {
            ## Create Resource Group
            Write-Verbose -Message "Resource Group does not exist. Creating $($ResourceGroupName)..."
            $RG = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location
        }

        Write-Verbose -Message "Creating Network Interface (NIC) for VM..."
        $NIC = New-AzureRmNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $Subnet.Id

        Write-Verbose -Message "Creating Virtual Machine Configuration..."
        if ($AvailabilitySetName){
            if (!($AS)) {
                Write-Verbose -Message "Availability Set $($AvailabilitySetName) does exist. Creating $($AvailabilitySetName)..."
                $AS = New-AzureRmAvailabilitySet -ResourceGroupName $ResourceGroupName -Name $AvailabilitySetName -Location $Location -PlatformUpdateDomainCount 3 -PlatformFaultDomainCount 2 -Sku Aligned
            }
            $VMConfig = New-AzureRmVMConfig -VMName $VMName -VMSize $VMSize -AvailabilitySetId $AS.Id -LicenseType $LicenseType
        } else {
            $VMConfig = New-AzureRmVMConfig -VMName $VMName -VMSize $VMSize -LicenseType $LicenseType
        }

        ## Operating System
        $VMConfig = Set-AzureRmVMOperatingSystem -VM $VMConfig -Windows -ComputerName $ComputerName -Credential $Credential -ProvisionVMAgent
        $VMConfig = Add-AzureRmVMNetworkInterface -VM $VMConfig -Id $NIC.Id
        ## Storage
        if ($SubscriptionName -eq "HCHB_PROD"){
            $VMConfig = Set-AzureRmVMOSDisk -VM $VMConfig -StorageAccountType Premium_LRS -CreateOption FromImage
        } else {
            $VMConfig = Set-AzureRmVMOSDisk -VM $VMConfig -StorageAccountType StandardSSD_LRS -CreateOption FromImage
        }
        ## Boot Diagnostics
        if ($LoggingResourceGroupName) {
            $VMConfig = Set-AzureRmVMBootDiagnostics -VM $VMConfig -Enable -ResourceGroupName $LoggingResourceGroupName -StorageAccountName $LoggingStorageAccountName 
        } else {
            $VMConfig = Set-AzureRmVMBootDiagnostics -VM $VMConfig -Disable
        }
        ## Image
        $VMConfig = Set-AzureRmVMSourceImage -VM $VMConfig -PublisherName $Publisher -Offer $Offer -Skus $WindowsSKU -Version latest
        
        try {
            Write-Verbose -Message "Creating Virtual Machine $($VMName) in Resource Group $($ResourceGroupName) in Subscription $($SubscriptionName)..."
            $VM = New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VMConfig -ErrorAction Stop
        } catch {
            Write-Verbose -Message "Failed to create VM $($VMName)!"
            Write-Error $_
            exit
        }

                Write-Verbose -Message "VM Creation Complete!"

        if ($JoinDomain){
            Write-Verbose -Message "Joining VM $($VMName) to domain $($DomainName) and restarting..."
            #Set-AzureRmVMExtension @JoinDomainSettings
            $DomainJoin = Set-AzureRmVMADDomainExtension -DomainName $DomainName -JoinOption 3 -Credential $JoinCred -Restart -ResourceGroupName $ResourceGroupName -VMName $VMName -Name JoinDomain -TypeHandlerVersion 1.0 -Location $Location
        }

        Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VMName
        Write-Verbose -Message "Script Complete!"

	}#Process

