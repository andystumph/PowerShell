
<#  
.SYNOPSIS  
    Retrieves the system uptime for a computer.
.DESCRIPTION
    Retrieves the system uptime for a computer.
.PARAMETER computer
    Name of computer to get the uptime for.
.NOTES  
    Name: Get-Uptime
    Author: Andy Stumph
    DateCreated: 12-12-2014

.LINK  
    http://powershell.com/cs/blogs/tips/archive/2014/12/12/gettingsystemuptime.aspx
.EXAMPLE
    Get-Uptime -computer ServerName

#> 

# Requires -version 3.0

[cmdletbinding()]

    Param(
        [Parameter(Mandatory = $True, Position = 0, ValueFromPipeline = $True)]
        [string]$Computer
        )

$Option = New-CimSessionOption -Protocol Dcom
$Session = New-CimSession -SessionOption $Option -ComputerName $Computer

$OS = Get-CimInstance -CimSession $Session -ClassName Win32_OperatingSystem
$Uptime = $OS.LocalDateTime - $OS.LastBootUpTime


#$Millisec = Invoke-Command -ComputerName $Computer -ScriptBlock {[Environment]::TickCount}
#$Uptime = [Timespan]::FromMilliseconds($Millisec)

$Uptime
#Write-Host -ForegroundColor Green "$Computer has been up for $($Uptime.Days) Days $($Uptime.Hours) Hours $($Uptime.Minutes) Minutes"