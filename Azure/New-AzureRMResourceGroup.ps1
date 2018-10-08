
<#
.Synopsis
    Creates a new HCHB specific Resource Group using standard naming convention and assigns the proper VSTS deployment service principal access.
.Description
    Creates a new HCHB specific Resource Group using standard naming convention and assigns the proper VSTS deployment service principal access.
.Parameter ApplicationName
    Name of the application that the resource group will be created for.
.Parameter SubscriptionName
    Name of a subscription in the Tenet where the resource group will be created. "HCHB_NONPROD", "HCHB_PROD", "HCHB_SANDBOX", "HCHB_CORP", "HCHB_PIPELINE"
.Parameter Location
    Name of the Region to create the resource group in. "East US", "West US", "East US 2", "West US 2"
.Parameter Tier
    Name of the tier the app will be used in. "DEV", "QA", "STG", "TRN", "PLT", "PRD", "SBX"
.Example
	.\New-AzureRMResourceGroup.ps1 -ApplicationName TEST -SubscriptionName HCHB_NONPROD -Location 'East US' -Tier DEV
.Link
    Get-Help about_functions_advanced_Parameters
    Get-Help about_Functions_CmdletBindingAttribute
    https://docs.microsoft.com/en-us/powershell/azure/overview?view=azurermps-5.3.0
.Notes
	Name     : New-AzureRMResourceGroup.ps1
	Author   : Andy Stumph
	Lastedit : 10/8/2018
#>

#Requires -version 5.0
#Requires -module AzureRM.Profile
#Requires -module AzureRM.Resources

[CmdletBinding(SupportsShouldProcess=$True)]

param
	(
		[Parameter(Mandatory=$True,Position=0,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
        $ApplicationName,
        
        [Parameter(Mandatory=$True,Position=1,ValueFromPipeLine=$True)]
        [ValidateSet("HCHB_NONPROD", "HCHB_PROD", "HCHB_SANDBOX", "HCHB_CORP", "HCHB_PIPELINE")]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
        $SubscriptionName,
        
        [Parameter(Mandatory=$True,Position=2,ValueFromPipeLine=$True)]
        [ValidateSet("East US", "West US", "East US 2", "West US 2")]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
		$Location,

        [Parameter(Mandatory=$True,Position=3,ValueFromPipeLine=$True)]
        [ValidateSet("DEV", "QA", "STG", "TRN", "STG", "PLT", "PRD", "SBX")]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
		$Tier



		
	)#param
Begin
	{
        Import-Module AzureRM.profile
        Import-Module AzureRM.Resources
        
        $AzureAccount = Login-AzureRmAccount -ErrorAction SilentlyContinue
        Set-AzureRmContext -SubscriptionName $SubscriptionName

        switch ($Location) {
            "East US" {$LocationCode = "UE"}
            "East US 2" {$LocationCode = "UE2"}
            "West US" {$LocationCode = "UW"}
            "West US 2" {$LocationCode = "UW2"}
        }

        switch ($Tier){

            "SBX" {$ServicePrincipalName = "AR_VSTS-PIPELINE_SANDBOX"}
            "DEV" {$ServicePrincipalName = "VSTS-PIPELINE-DEV"}
            "QA" {$ServicePrincipalName = "VSTS-PIPELINE-QA"}
            "STG" {$ServicePrincipalName = "VSTS-PIPELINE-PROD"}
            "TRN" {$ServicePrincipalName = "VSTS-PIPELINE-PROD"}
            "PLT" {$ServicePrincipalName = "VSTS-PIPELINE-PROD"}
            "PRD" {$ServicePrincipalName = "VSTS-PIPELINE-PROD"}

        }

        $DisplayName = ("RG_$($ApplicationName)_$($LocationCode)_$($Tier)").ToUpper()

	}#Begin
Process 
	{
        $RG = New-AzureRmResourceGroup -Name $DisplayName -Location $Location 
        $RG

        $Role = Get-AzureRmRoleDefinition -Name Contributor
        $SP = Get-AzureRmADServicePrincipal -DisplayName $ServicePrincipalName
        $RoleAssignment = New-AzureRmRoleAssignment -ApplicationId $SP.ApplicationId -ResourceGroupName $RG.ResourceGroupName -RoleDefinitionName $Role.Name
        $RoleAssignment
		
	}#Process


