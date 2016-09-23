

param ($ComputerName)

Get-WmiObject -ComputerName $ComputerName -Namespace Root\MicrosoftDFS -Class DfsrReplicatedFolderInfo | select ReplicationGroupName, ReplicatedFolderName, State

