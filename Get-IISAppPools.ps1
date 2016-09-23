
#Requires -version 2.0

[CmdletBinding(SupportsShouldProcess=$True)]

param
	(
		[Parameter(Mandatory=$True,Position=0,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    $ComputerName
		
	)#param
Begin
	{
		
		
	}#Begin
Process 
	{
		$AppPools = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
                try {
                    [Reflection.Assembly]::LoadWithPartialName('Microsoft.Web.Administration')
                }
                catch {throw "Web Administration Tools not Installed on Remote Computer!"}

                $SM = [Microsoft.Web.Administration.ServerManager]::OpenRemote('localhost')

                $SM.ApplicationPools

            }

        $AppPools
		
	}#Process


