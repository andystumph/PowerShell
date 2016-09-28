
<#
.Synopsis
    Resets the SCOM Health Service on a remote Computer.
.Description
    The script will try to stop the Health Service on a remote computer if it's running. It will also terminate any orphaned cscript processes and purge the Health Service State cache.
.Parameter ComputerName
    The Name of the Remote computer on which the SCOM Health Service will be reset.
.Example
	.\Reset-SCOMHealthService.ps1 -ComputerName PBHYPV201
.Link
    Get-Help about_functions
	Get-Help about_functions_advanced
    Get-Help about_functions_advanced_Parameters
    Get-Help about_Functions_CmdletBindingAttribute
.Notes
	Name     : Reset-SCOMHealthService.ps1
	Author   : AStumph@hcb.com
	Lastedit : 01/12/2015
#>

#Requires -version 2.0

[CmdletBinding(SupportsShouldProcess=$True)]


param
	(
		[Parameter(Mandatory=$False,Position=0,ValueFromPipeLine=$True,HelpMessage="Enter Computer Name to Reset SCOM Health Service:")]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
	    $ComputerName
		
	)#param
Begin
	{

        Function Get-HealthService {
            param ($ComputerName)

            $Service = Get-Service -ComputerName $ComputerName -Name "HealthService" -ErrorAction SilentlyContinue
            return $Service
        }
        
        Function Clear-HealthServiceCache {
            param ($ComputerName)

            Remove-Item -Recurse -Path "\\$($ComputerName)\C$\Program Files\Microsoft Monitoring Agent\Agent\Health Service State" -Confirm:$False -ErrorAction SilentlyContinue
        }

        Function Stop-RunningScripts {
            param ($ComputerName)

            try {
                $Result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
                    [Array]$ScriptProcesses = Get-Process -Name "cscript" -ErrorAction SilentlyContinue

                    if ($ScriptProcesses) {
                        foreach ($Process in $ScriptProcesses) {
                            $Process.Kill()
                        } 
                    }
                }
            } catch {
                Write-Host -ForegroundColor Yellow "Could not connect remotely to $ComputerName to stop script processes. Continuing..."
            }
           
        }

        function Check-ServerAvailability {
            param ($ComputerName)
            $Result = Test-Connection -ComputerName $ComputerName -Quiet -Count 1
            return $Result
        }
		
	}#Begin
Process 
	{
		
        if (!(Check-ServerAvailability -ComputerName $ComputerName)) {

            Write-Host -ForegroundColor Red "Server $ComputerName does not appear to be Online!"
            exit
        }

        $HealthService = Get-HealthService -ComputerName $ComputerName

        if (!($HealthService)) {Write-Host -ForegroundColor Red "HealthService does not exist on $ComputerName !"; exit}

        If ($HealthService.Status -eq "Stopped") {

            Write-Host -ForegroundColor Yellow "Health Service is not running on $ComputerName !"
            
            Write-Host -ForegroundColor Green "Stopping any running script processes..."
            Stop-RunningScripts -ComputerName $ComputerName

            Write-Host -ForegroundColor Green "Deleting Health Service Cache..."
            Clear-HealthServiceCache -ComputerName $ComputerName

            $HealthService | Start-Service

            $HealthService = Get-HealthService -ComputerName $ComputerName

            if ($HealthService.Status -eq "Running") {
                Write-Host -ForegroundColor Green "Health Service has been Restarted on $($ComputerName)."
            } else {
                    Write-Host -ForegroundColor Red "Failed to Start HealthService on $($ComputerName)!"
                }

            exit

        }

        if ($HealthService.Status -eq "Running") {
            
            Write-Host -ForegroundColor Green "Stopping HealthService on $($ComputerName)...This might take some time..."
            $HealthService | Stop-Service -Force -ErrorAction SilentlyContinue

            $Count = 0
            while (($Count -lt 60) -and ($HealthService.Status -eq "Running")) {

                Start-Sleep 5
                $HealthService = Get-HealthService -ComputerName $ComputerName
                $Count++
            }

            if ($HealthService.Status -ne "Stopped") {
                Write-Host -ForegroundColor Red "Failed to Stop HealthService on $ComputerName"
                exit
            } else {
                
                Write-Host -ForegroundColor Green "Stopping any running script processes..."
                Stop-RunningScripts -ComputerName $ComputerName

                Write-Host -ForegroundColor Green "Deleting Health Service Cache..."
                Clear-HealthServiceCache -ComputerName $ComputerName

                $HealthService | Start-Service -ErrorAction SilentlyContinue

                $HealthService = Get-HealthService -ComputerName $ComputerName

                if ($HealthService.Status -eq "Running") {
                    Write-Host -ForegroundColor Green "Health Service has been Restarted on $($ComputerName)."
                } else {
                    Write-Host -ForegroundColor Red "Failed to Start HealthService on $($ComputerName)!"
                }
            }
        }
		
	}#Process


