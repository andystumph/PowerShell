#Requires -Version 5

[cmdletbinding()]

param (
    [parameter(Mandatory=$true)] 
    [ValidateNotNullOrEmpty()] 
    [System.IO.FileInfo] $MSIPath
)

if (!(Test-Path $MSIPath.FullName)) { 
    throw "File $($MSIPath.FullName) does not exist"
}

$Results = [PSCustomObject]@{}
$Properties = @("Manufacturer", "ProductName", "ProductVersion", "ProductCode" )

try {
    $WindowsInstaller = New-Object -com WindowsInstaller.Installer 
    $Database = $WindowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $Null, $WindowsInstaller, @($MSIPATH.FullName, 0)) 
} catch {
    throw "Failed to open MSI database: $_"
}

try {
    foreach ($Property in $Properties) {
        $Query = "SELECT Value FROM Property WHERE Property = '$Property'"
        $View = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $Null, $Database, ($Query))
        $View.GetType().InvokeMember("Execute", "InvokeMethod", $Null, $View, $Null) | Out-Null
        $Record = $View.GetType().InvokeMember( "Fetch", "InvokeMethod", $Null, $View, $Null )
        $Value = $Record.GetType().InvokeMember( "StringData", "GetProperty", $Null, $Record, 1 )
        $Results | Add-Member -MemberType NoteProperty -Name $Property -Value $Value
    }
} catch {
    throw "Failed to get MSI $Property info: $_"
}

try {
    $Database.GetType().InvokeMember("Commit", "InvokeMethod", $null, $Database, $null)
    $View.GetType().InvokeMember("Close", "InvokeMethod", $null, $View, $null)
} catch {
    throw "Failed to close MSI database: $_"
}

Write-Output $Results