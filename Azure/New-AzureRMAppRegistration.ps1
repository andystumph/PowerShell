
<#
.Synopsis
    Creates a new App Registration (Azure AD Application) for use with application authentication.
.Description
    Creates a new App Registration (Azure AD Application) for use with application authentication.
.Parameter ApplicationName
    Name of the application that the registration will be created for.
.Parameter Homepage
    The URL where users can sign in and use the app. This can be changed later.
.Parameter SubscriptionName
    Name of a subscription in the Tenet where the app registration will be created. "HCHB_NONPROD", "HCHB_PROD", "HCHB_SHARED_NONPROD", "HCHB_SHARED_PROD", "HCHB_SANDBOX", "HCHB_CORP", "HCHB_PIPELINE"
.Parameter Tier
    Name of the tier the app will be used in. "DEV", "QA", "STG", "TRN", "STG", "PILOT", "PROD", "SANDBOX"
.Parameter CertificatePath
    Optional. Path to the public key .PEM file if using certificate authentication. Can be added later.
.Example
	.\New-AzureRMAppRegistration.ps1 -ApplicationName UMS_Keyvault -Homepage https://localhost.localdomain -SubscriptionName HCHB_SANDBOX -Tier SANDBOX -CertificatePath C:\Users\astumph\Downloads\UMS-Sandbox_Cert.pem
.Link
    Get-Help about_functions_advanced_Parameters
    Get-Help about_Functions_CmdletBindingAttribute
    https://docs.microsoft.com/en-us/powershell/azure/overview?view=azurermps-5.3.0
.Notes
	Name     : New-AzureRMAppRegistration.ps1
	Author   : Andy Stumph
	Lastedit : 5/3/2018
#>

#Requires -version 5.0

[CmdletBinding(SupportsShouldProcess=$True)]

param
	(
		[Parameter(Mandatory=$True,Position=0,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
        $ApplicationName,
        
        [Parameter(Mandatory=$True,Position=1,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
		$Homepage,
		
        ## Technically App Registrations are at the Tenet level, we just use the subscription to set the Tenet context.
        [Parameter(Mandatory=$True,Position=2,ValueFromPipeLine=$True)]
        [ValidateSet("HCHB_NONPROD", "HCHB_PROD", "HCHB_SHARED_NONPROD", "HCHB_SHARED_PROD", "HCHB_SANDBOX", "HCHB_CORP", "HCHB_PIPELINE")]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
		$SubscriptionName,

        [Parameter(Mandatory=$True,Position=3,ValueFromPipeLine=$True)]
        [ValidateSet("DEV", "QA", "STG", "TRN", "STG", "PLT", "PRD", "SBX")]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
		$Tier,

        [Parameter(Mandatory=$False,Position=4,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
		$CertificatePath

		
	)#param
Begin
	{
        ## Script was origianlly written with AzureRm cmdlets.
        ## This has been added to support the new Az cmdlets.
        if (Get-Command -Name Enable-AzureRmAlias -ErrorAction SilentlyContinue) {
            Enable-AzureRmAlias
        }
        
        $AzureAccount = Login-AzureRmAccount -ErrorAction SilentlyContinue
        Set-AzureRmContext -SubscriptionName $SubscriptionName

        $DisplayName = ("AR_$($ApplicationName)_$($Tier)").ToUpper()
        $IdentifierURI = "https://hchbazure.onmicrosoft.com/$([GUID]::NewGuid())"

	}#Begin
Process 
	{
		if ($CertificatePath) {
            if (!(Test-Path -Path $CertificatePath)) {
                Write-Error -Message "Could not find certificate file at location $($CertificatePath)."
                exit
            }

            if ([IO.Path]::GetExtension($CertificatePath) -ne ".pem") {
                Write-Error -Message "Certificate file must be in .PEM format!"
                exit
            }

            # Load the certificate and convert it to the form we need.
            $x509Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            $x509Cert.Import($certificatePath)
            $CertBase64Value = [System.Convert]::ToBase64String($x509Cert.GetRawCertData())

            $ADApp = New-AzureRmADApplication -DisplayName $DisplayName -HomePage $Homepage -IdentifierUris $IdentifierURI -CertValue $CertBase64Value -StartDate $x509Cert.NotBefore -EndDate $x509Cert.NotAfter
        } else {
            $ADApp = New-AzureRmADApplication -DisplayName $DisplayName -HomePage $Homepage -IdentifierUris $IdentifierURI
        }

        $ADApp

        $ServicePrincipal = New-AzureRmADServicePrincipal -SkipAssignment -ApplicationId $ADApp.ApplicationId 
        $ServicePrincipal

		
	}#Process


