

param ($SendingMember, $ReceivingMember, $ReplicatedFolder)

$ReplGrpGUID = Get-WmiObject -ComputerName $SendingMember -Namespace root\MicrosoftDFS -Query "SELECT * FROM DfsrReplicatedFolderInfo WHERE ReplicatedFolderName LIKE ""$ReplicatedFolder"""

    if ($ReplGrpGUID -eq $Null) {Write-Host -ForegroundColor Red "Replicated Folder $ReplicatedFolder was not found!"; break}

$InBoundpartner = Get-WmiObject -ComputerName $ReceivingMember -Namespace root\MicrosoftDFS `
-Query "SELECT * FROM DfsrReplicatedFolderInfo WHERE ReplicationGroupGUID = ""$($ReplGrpGUID.ReplicationGroupGUID)"" AND ReplicatedFolderName = ""$($ReplicatedFolder)"""

    if ($InBoundpartner.ReplicatedFolderName -ne $ReplicatedFolder) {
        Write-Host -ForegroundColor Red "Could not find replicated folder $ReplicatedFolder on member $ReceivingMember"
        break
    }

$OutBoundpartner = Get-WmiObject -ComputerName $SendingMember -Namespace root\MicrosoftDFS `
-Query "SELECT * FROM DfsrReplicatedFolderInfo WHERE ReplicationGroupGUID = ""$($ReplGrpGUID.ReplicationGroupGUID)"" AND ReplicatedFolderName = ""$($ReplicatedFolder)"""

    if ($OutBoundpartner.ReplicatedFolderName -ne $ReplicatedFolder) {
        Write-Host -ForegroundColor Red "Could not find replicated folder $ReplicatedFolder on member $SendingMember"
        break
    }

$Vv = $Inboundpartner.GetVersionVector().versionvector

$RecordsIndex = $Outboundpartner.GetOutboundBacklogFileIDrecords($Vv).IdRecordIndex

IF ($RecordsIndex) {$Backlog = $OutBoundPartner.GetOutboundBacklogFileIDrecords($Vv) | SELECT -ExpandProperty BacklogIdrecords | SELECT FullPathName }

Write-Output $Backlog
