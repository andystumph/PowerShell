
<#  
.SYNOPSIS  
    Retrieves the IPv4 IP addresses for a computer.
.DESCRIPTION
    Retrieves the IPv4 IP addresses for a computer.
.PARAMETER computer
    Name of computer to get IP info from.
.NOTES  
    Name: Get-IPInfo.ps1
    Author: Andy Stumph
    DateCreated: 10-7-2016

.EXAMPLE
    Get-IPInfo -computer ServerName
.EXAMPLE
    Get-IPInfo -computer ServerName | select InterfaceAlias, IPAddress | ft

#> 

# Requires -version 3.0

[cmdletbinding()]

    Param(
        [Parameter(Mandatory = $True, Position = 0, ValueFromPipeline = $True)]
        [string]$Computer
        )

$Option = New-CimSessionOption -Protocol Dcom
$Session = New-CimSession -SessionOption $Option -ComputerName $Computer

Get-NetIPAddress -CimSession $Session -AddressFamily IPv4

Remove-CimSession -CimSession $Session