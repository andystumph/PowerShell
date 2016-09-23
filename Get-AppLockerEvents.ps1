
#Requires -Module ActiveDirectory
#Requires -Version 3

[cmdletbinding()]

Param(
    [Parameter(Mandatory = $True, Position = 0, ValueFromPipeline = $True)]
    [string]$ComputerName,

    [Parameter(Mandatory = $False, Position = 1, ValueFromPipeline = $True)]
    [DateTime]$Date = (Get-Date).Date
    )

$Output = @()

$Filter = @{

    LogName = 'Microsoft-Windows-AppLocker/EXE and DLL'
    Level = 2
    StartTime = $Date


}

$Events = Get-WinEvent -FilterHashtable $Filter -ComputerName $Computername
#$Events

foreach ($Event in $Events) {

    $UserID = $Event.UserID.Value

    if ($UserID -eq 'S-1-5-18') {
        $UserName = 'SYSTEM' 
    } else {
        $User = Get-ADUser -Identity $UserID
        $UserName = $User.SamAccountName
        }

    $CustomEvent = [pscustomobject]@{
        
        ComputerName = $Event.MachineName
        Date = $Event.TimeCreated
        EventID = $Event.ID
        Level = $Event.LevelDisplayName
        User = $UserName
        Message = $Event.Message

    }

    $Output += $CustomEvent
    

}

$Output

