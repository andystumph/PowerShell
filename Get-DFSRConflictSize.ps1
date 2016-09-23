<#  
.SYNOPSIS  
    Retrieves the size of the DFSR Conflict and Deleted folders for each replicated folder on a server.
.DESCRIPTION
    Retrieves the size of the DFSR Conflict and Deleted folders for each replicated folder on a server.
.PARAMETER ComputerName
    Name of computer to run query against.              
.NOTES  
    Name: Get-DFSRConflictSize
    Author: Andy Stumph
    DateCreated: 12/29/2014

.LINK  
    
.EXAMPLE
Get-DFSRConflictSize -ComputerName "server1"

#> 

#Requires -Version 2

[cmdletbinding()]

    Param(
        [Parameter(Mandatory = $False, Position = 0, ValueFromPipeline = $True)]
        [string]$ComputerName = "Localhost"
        )

Get-WmiObject -ComputerName $ComputerName -Namespace Root\MicrosoftDFS -Class DFSRReplicatedFolderInfo | Select-Object -Property @{Name='ComputerName'; Expression = {$_.MemberName}}, ReplicatedFolderName, ReplicatedFolderGUID, CurrentConflictSizeInMb | Format-Table -AutoSize
