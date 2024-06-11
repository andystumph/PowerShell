## Script does not work in PS core.
#Requires -version 5.0

[CmdletBinding(SupportsShouldProcess=$True)]

param (
    [ValidateNotNullOrEmpty()]
    [System.String]
    $URI = "https://hchb.com",

    [ValidateNotNullOrEmpty()]
    [Int32]
    $TimeoutMS = 5000
)

## Allow connection to sites with bad certs
[Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

$Request = [Net.HttpWebRequest]::Create($URI)
$Request.Timeout = $TimeoutMS
try {
    $Request.GetResponse() | Out-Null
} catch {
    throw $_
}

$Certificate = New-Object Security.Cryptography.x509Certificates.x509Certificate2($Request.ServicePoint.Certificate)
Write-Host -ForegroundColor Green "Certificate Information:"
$Certificate | Format-List
$SAN = $Certificate.Extensions | Where-Object { $_.Oid.FriendlyName -eq "Subject Alternative Name"}
Write-Host -ForegroundColor Green "Subject Alternative Name:"
$SAN.Format($true)
