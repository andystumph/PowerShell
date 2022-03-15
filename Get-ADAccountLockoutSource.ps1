

#Requires -module ActiveDirectory

[CmdletBinding(SupportsShouldProcess=$True)]

param
	(
		[Parameter(Mandatory=$True,Position=0,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
		$UserName
	
    )#param

$PDC = (Get-ADDomain).PDCEmulator

$Parameters = @{
    ComputerName = $PDC
    LogName = "Security"
    FilterXPath = "*[System[EventID=4740] and EventData[Data[@Name='TargetUserName']='$UserName']]"
}

try {
    $Events = Get-WinEvent @Parameters -ErrorAction Stop
} catch {
    Write-Host -ForegroundColor Yellow "No events were found for user $UserName"
    exit 0
}

$Events | foreach {$_.Properties[1].value + ' ' + $_.TimeCreated}