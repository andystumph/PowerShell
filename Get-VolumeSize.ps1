
    
<#  
.SYNOPSIS  
    Retrieves Disk and space information from a computer. ** Works with Mount Points **
.DESCRIPTION
    Retrieves Disk and space information from a computer. Works with Mount Points.
.PARAMETER computer
    Name of computer to get disk information on.
.NOTES  
    Name: Get-VolumeSize
    Author: Andy Stumph
    DateCreated: 7-17-2019
.EXAMPLE
    .\Get-VolumeSize.ps1 -Computer ServerName

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

$Volumes = Get-CimInstance -CimSession $Session -ClassName Win32_Volume
$Volumes = $Volumes | Sort-Object -Property Name

foreach ($Volume in $Volumes) {

    ## Don't list recovery volumes or volumes with no drive mount.
    If ($Volume.Name -match "Volume{") {continue}

    ## Don't be silly, you can't divide by Zero.
    If ($Volume.Capacity / 1MB -ne 0.00) {$FreeSpacePercent = (($Volume.FreeSpace / 1MB) / ($Volume.Capacity / 1MB))} else {$FreeSpacePercent = 0}

    $Disk = [pscustomobject]@{

    Computer = $Volume.SystemName
    #"Device_ID" = $Volume.DeviceID
    "Disk" = "{0:N0}" -f $Volume.Name
    "Label" = "{0:N0}" -f $Volume.Label
    "Size (MB)" = "{0:N0}" -f $($Volume.Capacity / 1MB)
    "Free Space (MB)" = "{0:N0}" -f $($Volume.FreeSpace / 1MB)
    "Percent Free" = "{0:P0}" -f $FreeSpacePercent
    }

    $Output += $Disk
}     

$Output | Format-Table

