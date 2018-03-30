    
<#  
.SYNOPSIS  
    Retrieves Disk and space information from a computer.
.DESCRIPTION
    Retrieves Disk and space information from a computer.
.PARAMETER computer
    Name of computer to get disk information on.
.NOTES  
    Name: Get-DiskSize
    Author: Andy Stumph
    DateCreated: 7-5-2015
.EXAMPLE
    .\Get-DiskSize.ps1 -Computer ServerName

#> 

# Requires -version 3.0

[cmdletbinding()]

    Param(
    [Parameter(Mandatory = $False, Position = 0, ValueFromPipeline = $True)]
    [string[]]$Computer = 'localhost'
    )

$Output = @()
## DCOM for older OS's.
$Option = New-CimSessionOption -Protocol Dcom
$Session = New-CimSession -SessionOption $Option -ComputerName $Computer

$LogicalDisks = Get-CimInstance -CimSession $Session -ClassName Win32_LogicalDisk

foreach ($LogicalDisk in $LogicalDisks) {

    $Type = $LogicalDisk.DriveType
    Switch ($Type)
     {
         2 {$Type="FDD"}
         3 {$Type="HDD"}
	     4 {$Type="NET"}
         5 {$Type="CD "}
     }

     If ($LogicalDisk.Size / 1MB -ne 0.00) {$FreeSpacePercent = (($LogicalDisk.FreeSpace / 1MB) / ($LogicalDisk.Size / 1MB))} else {$FreeSpacePercent = 0}

     $Disk = [pscustomobject]@{
        
        Computer = $LogicalDisk.PSComputerName
        "Device_ID" = $LogicalDisk.DeviceID
        Type = $Type
        "Volume Name" = "{0:N0}" -f $LogicalDisk.VolumeName
        "Size (MB)" = "{0:N0}" -f $($LogicalDisk.Size / 1MB)
        "Free Space (MB)" = "{0:N0}" -f $($LogicalDisk.FreeSpace / 1MB)
        "Percent Free" = "{0:P0}" -f $FreeSpacePercent
     }
     
     $Output += $Disk
}     

$Output | Format-Table

