<#

.SYNOPSIS

Retrieves DFSR backlog information for all Replication Groups and Connections from the perspective of the targeted server.



.DESCRIPTION

The Get-DFSRBacklog script uses Windows Management Instrumentation (WMI) to retrieve Replication Groups, Replication Folders, and Connections from the targeted computer. 

The script then uses this information along with MicrosoftDFS WMI methods to calculate the version vector and in turn backlog for each pairing.

All of this information is returned in an array custom objects, that can be later processed as needed.

The computername defaults to "localhost", or may be passed to the –computerName parameter. 



.EXAMPLE

Output all of the DFSR backlog information from the local system into a sorted and grouped table.

.\Get-DFSRBacklog.ps1 | sort-object BacklogStatus | format-table -groupby BacklogStatus



.EXAMPLE

Specify a DFSR target remotely, with a warning threshold of 100

.\Get-DFSRBacklog.ps1 computername 100



.NOTES

You need to run this script with an account that has appropriate permission to query WMI from the remote computer.

#>


Param
(
    [string]$Computer = "localhost",
    [int]$WarningThreshold = 10,
    [int]$ErrorThreshold = 100
)

$DebugPreference = "SilentlyContinue"

Function PingCheck
{
    Param
    (
        [string]$Computer = "localhost",
        [int]$timeout = 120
    )
    Write-Debug $computer
    Write-Debug $timeout
    $Ping = New-Object System.Net.NetworkInformation.Ping
    trap 
    {
        Write-Debug "The computer $computer could not be resolved."           
        continue
    } 
   
    Write-Debug "Checking server: $computer"       
    $reply = $Ping.Send($computer,$timeout)
    Write-Debug $reply
    If ($reply.status -eq "Success") 
    {
        Write-Output $True
    } else {
        Write-Output $False
    }  
   
}

Function Check-WMINamespace ($computer, $namespace)
{
    $Namespaces = $Null
    $Namespaces = Get-WmiObject -class __Namespace -namespace root -computername $computer | Where {$_.name -eq $namespace}
    If ($Namespaces.Name -eq $Namespace)
    {
        Write-Output $True
    } else {
        Write-Output $False
    }
}

Function Get-DFSRGroup ($computer)
{
    ## Query DFSR groups from the MicrosftDFS WMI namespace.
    $WMIQuery = "SELECT * FROM DfsrReplicationGroupConfig"
    $WMIObject = Get-WmiObject -computername $computer -Namespace "root\MicrosoftDFS" -Query $WMIQuery
    Write-Output $WMIObject
}

Function Get-DFSRConnections ($computer)
{
    ## Query DFSR connections from the MicrosftDFS WMI namespace.
    $WMIQuery = "SELECT * FROM DfsrConnectionConfig"
    $WMIObject = Get-WmiObject -computername $computer -Namespace "root\MicrosoftDFS" -Query $WMIQuery
    Write-Output $WMIObject
}


Function Get-DFSRFolder ($computer)
{
    ## Query DFSR folders from the MicrosftDFS WMI namespace.
    $WMIQuery = "SELECT * FROM DfsrReplicatedFolderConfig"
    $WMIObject = Get-WmiObject -computername $computer -Namespace "root\MicrosoftDFS" -Query $WMIQuery
    Write-Output $WMIObject
}


Function Get-DFSRBacklogInfo ($Computer, $RGroups, $RFolders, $RConnections)
{
   $objSet = @()
   
   Foreach ($Group in $RGroups)
   {
        $ReplicationGroupName = $Group.ReplicationGroupName    
        $ReplicationGroupGUID = $Group.ReplicationGroupGUID
           
        Foreach ($Folder in $RFolders) 
        {
           If ($Folder.ReplicationGroupGUID -eq $ReplicationGroupGUID) 
           {
                $ReplicatedFolderName = $Folder.ReplicatedFolderName
                $FolderEnabled = $Folder.Enabled
                Foreach ($Connection in $Rconnections)
                {
                    If ($Connection.ReplicationGroupGUID -eq $ReplicationGroupGUID) 
                    {    
                        $ConnectionEnabled = $Connection.Enabled
                        $BacklogCount = $Null
                        If ($FolderEnabled) 
                        {
                            If ($ConnectionEnabled)
                            {
                                If ($Connection.Inbound)
                                {
                                    Write-Debug "Connection Is Inbound"
                                    $Smem = $Connection.PartnerName.Trim()
                                    Write-Debug $smem
                                    $Rmem = $Computer.ToUpper()
                                    Write-Debug $Rmem
                                    
                                    #Get the version vector of the inbound partner
                                    $WMIQuery = "SELECT * FROM DfsrReplicatedFolderInfo WHERE ReplicationGroupGUID = '" + $ReplicationGroupGUID + "' AND ReplicatedFolderName = '" + $ReplicatedFolderName + "'"
                                    $InboundPartnerWMI = Get-WmiObject -computername $Rmem -Namespace "root\MicrosoftDFS" -Query $WMIQuery
                                    
                                    $WMIQuery = "SELECT * FROM DfsrReplicatedFolderConfig WHERE ReplicationGroupGUID = '" + $ReplicationGroupGUID + "' AND ReplicatedFolderName = '" + $ReplicatedFolderName + "'"
                                    $PartnerFolderEnabledWMI = Get-WmiObject -computername $Smem -Namespace "root\MicrosoftDFS" -Query $WMIQuery
                                    $PartnerFolderEnabled = $PartnerFolderEnabledWMI.Enabled             
                                    
                                    If ($PartnerFolderEnabled)
                                    {
                                        $Vv = $InboundPartnerWMI.GetVersionVector().VersionVector
                                        
                                        #Get the backlogcount from outbound partner
                                        $WMIQuery = "SELECT * FROM DfsrReplicatedFolderInfo WHERE ReplicationGroupGUID = '" + $ReplicationGroupGUID + "' AND ReplicatedFolderName = '" + $ReplicatedFolderName + "'"
                                        $OutboundPartnerWMI = Get-WmiObject -computername $Smem -Namespace "root\MicrosoftDFS" -Query $WMIQuery
                                        $BacklogCount = $OutboundPartnerWMI.GetOutboundBacklogFileCount($Vv).BacklogFileCount  
                                    }
                                } else {
                                    Write-Debug "Connection Is Outbound"
                                    $Smem = $Computer.ToUpper()  
                                    Write-Debug $smem                   
                                    $Rmem = $Connection.PartnerName.Trim()
                                    Write-Debug $Rmem
                                    
                                    #Get the version vector of the inbound partner
                                    $WMIQuery = "SELECT * FROM DfsrReplicatedFolderInfo WHERE ReplicationGroupGUID = '" + $ReplicationGroupGUID + "' AND ReplicatedFolderName = '" + $ReplicatedFolderName + "'"
                                    $InboundPartnerWMI = Get-WmiObject -computername $Rmem -Namespace "root\MicrosoftDFS" -Query $WMIQuery
                                    
                                    $WMIQuery = "SELECT * FROM DfsrReplicatedFolderConfig WHERE ReplicationGroupGUID = '" + $ReplicationGroupGUID + "' AND ReplicatedFolderName = '" + $ReplicatedFolderName + "'"
                                    $PartnerFolderEnabledWMI = Get-WmiObject -computername $Rmem -Namespace "root\MicrosoftDFS" -Query $WMIQuery
                                    $PartnerFolderEnabled = $PartnerFolderEnabledWMI.Enabled
                                    
                                    If ($PartnerFolderEnabled)
                                    {
                                        $Vv = $InboundPartnerWMI.GetVersionVector().VersionVector
                                        
                                        #Get the backlogcount from outbound partner
                                        $WMIQuery = "SELECT * FROM DfsrReplicatedFolderInfo WHERE ReplicationGroupGUID = '" + $ReplicationGroupGUID + "' AND ReplicatedFolderName = '" + $ReplicatedFolderName + "'"
                                        $OutboundPartnerWMI = Get-WmiObject -computername $Smem -Namespace "root\MicrosoftDFS" -Query $WMIQuery
                                        $BacklogCount = $OutboundPartnerWMI.GetOutboundBacklogFileCount($Vv).BacklogFileCount
                                    }              
                                }
                            }
                        }
                    
                        $obj = New-Object psobject
                        $obj | Add-Member noteproperty ReplicationGroupName $ReplicationGroupName
                        write-debug $ReplicationGroupName
                        $obj | Add-Member noteproperty ReplicatedFolderName $ReplicatedFolderName 
                        write-debug $ReplicatedFolderName
                        $obj | Add-Member noteproperty SendingMember $Smem
                        write-debug $Smem
                        $obj | Add-Member noteproperty ReceivingMember $Rmem
                        write-debug $Rmem
                        $obj | Add-Member noteproperty BacklogCount $BacklogCount
                        write-debug $BacklogCount
                        $obj | Add-Member noteproperty FolderEnabled $FolderEnabled
                        write-debug $FolderEnabled
                        $obj | Add-Member noteproperty ConnectionEnabled $ConnectionEnabled
                        write-debug $ConnectionEnabled
                        $obj | Add-Member noteproperty Inbound $Connection.Inbound
                        write-debug $Connection.Inbound
                        
                        
                        If ($BacklogCount -ne $Null)
                        {
                            If ($BacklogCount -lt $WarningThreshold) 
                            {
                                $Backlogstatus = "Low"
                            }
                            elseif (($BacklogCount -ge $WarningThreshold) -and ($BacklogCount -lt $ErrorThreshold))
                            {
                                $Backlogstatus = "Warning"
                            }
                            elseif ($BacklogCount -ge $ErrorThreshold)
                            {
                                $Backlogstatus = "Error"
                            } 
                        } else {
                            $Backlogstatus = "Disabled"
                        }
                    
                        $obj | Add-Member noteproperty BacklogStatus $BacklogStatus
                    
                        $objSet += $obj
                    }
                }  
           } 
        }
   }
   Write-Output $objSet
}

$Pingable = PingCheck $computer
If ($Pingable)
{
    $NamespaceExists = Check-WMINamespace $computer "MicrosoftDFS"
    If ($NamespaceExists)
    {
        $RGroups = Get-DFSRGroup $computer
        $RFolders = Get-DFSRFolder $computer
        $RConnections = Get-DFSRConnections $computer

        $BacklogInfo = Get-DFSRBacklogInfo $Computer $RGroups $RFolders $RConnections

        Write-Output $BacklogInfo
    } else {
        Write-Error "MicrosoftDFS WMI Namespace does not exist on '$computer'.  Run locally on a system with the Namespace, or provide computer parameter of that system to run remotely."
    }
} else {
    Write-Error "The computer '$computer' did not respond to ping."
}