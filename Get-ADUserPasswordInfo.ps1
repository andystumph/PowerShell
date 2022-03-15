

#Requires -version 3.0
#Requires -module ActiveDirectory

[CmdletBinding(SupportsShouldProcess=$True)]

param
	(
		[Parameter(Mandatory=$True,Position=0,ValueFromPipeLine=$True)]
	    [ValidateNotNullOrEmpty()]
	    [System.String]
		$UserName,
		
		[Parameter(Mandatory=$False,Position=1,ValueFromPipeLine=$True)]
		[ValidateNotNullOrEmpty()]
		[System.String]
		$DomainController = "PBDC74"
		
	)#param
Process 
	{
        try {
            $User = Get-ADUser -Identity $UserName -Server $DomainController -Properties AccountExpires, DisplayName, PasswordLastSet, PasswordExpired, PasswordNeverExpires, BadPwdCount, BadPasswordTime, msDS-UserPasswordExpiryTimeComputed, LastLogon, LockedOut
        } catch {
            throw
		}

		$AEProperty = $User.AccountExpires
		try {
			$AE = [datetime]::FromFileTime($AEProperty)
		} catch {
			$AE = "Never"
		}
		if ($AE -eq "12/31/1600 7:00:00 PM") {
			$AE = "Never"
		}

        $User | Select-Object -Property DisplayName, @{Name="AccountExpires";Expression={$AE}}, PasswordLastSet, PasswordExpired, PasswordNeverExpires, @{Name="ExpiryDate";Expression={[datetime]::FromFileTime($_."msDS-UserPasswordExpiryTimeComputed")}},@{Name="LastLogonTime";Expression={[datetime]::FromFileTime($_.LastLogon)}}, BadPwdCount, @{Name="BadPasswordTime";Expression={[datetime]::FromFileTime($_.BadPasswordTime)}}, LockedOut 
		
	}#Process


