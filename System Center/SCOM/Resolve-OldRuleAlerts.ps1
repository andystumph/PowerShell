
<#
.Synopsis
    Clears old RULE alerts in SCOM. Clears alerts that are older than $HoursOld and less than $Severity.
.Parameter SCOMServer
    Computer Name of the SCOM Managment Server to Attach to.
.Parameter HoursOld
    Clears alerts OLDER than this parameter. Default is 12.
.Parameter Severity
    Clears alerts with Severity LESS THAN this parameter. Default is Warning.

.Notes
    Severity:
        0 = Informational
        1 = Warning
        2 = Critical

    Name: Resolve-OldRuleAlerts.ps1

#>

# Requires -Version 2.0

[CmdletBinding()]

param(
    [Parameter(Mandatory=$false)]
    [string]$SCOMServer="PBSCOMMS101.hchb.local",

    [Parameter(Mandatory=$false)]
    [Int]$HoursOld = 12,

    [Parameter(Mandatory=$false)]
    [ValidateSet(0,1,2)]
    [string]$Severity=2

)


if (!(Get-Module OperationsManager)) {
        Import-Module OperationsManager }

New-SCOMManagementGroupConnection -ComputerName $SCOMServer


$Alerts = Get-SCOMAlert | where {($_.ResolutionState -eq 0) -and ($_.Severity -lt $Severity) -and ($_.IsMonitorAlert -eq $false) -and ($_.TimeRaised -le ((Get-Date).ToUniversalTime()).AddHours(-$HoursOld))}

foreach ($Alert in $Alerts) {

    $Alert | Select-Object TimeRaised, Name, MonitoringObjectPath
    #$Alert | Resolve-SCOMAlert
    $Alert | Set-SCOMAlert -ResolutionState 255

}
