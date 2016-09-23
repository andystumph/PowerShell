
#Requires -version 3.0

[CmdletBinding(SupportsShouldProcess=$True)]

param
    (  
    [System.String]$ComputerName = $ENV:ComputerName
    )  
  
foreach ($Computer in $ComputerName) {  
    try { 
     
        $Params = @{ 
            Namespace    = 'root\WMI' 
            class        = 'MSFC_FCAdapterHBAAttributes' 
            ComputerName = $Computer  
            ErrorAction  = 'Stop' 
            } 
     
        $HBAs = Get-WmiObject @Params

        foreach ($HBA in $HBAs) {  
                
                $InstanceName = $HBA.InstanceName -replace '\\','\\'
                $Params['Class'] = "MSFC_FibrePortHBAAttributes"
                $Params['Filter'] = "InstanceName='$InstanceName'" 
                $Ports = (@(Get-WmiObject @Params | Select -Expandproperty Attributes | % { ($_.PortWWN | % {"{0:x2}" -f $_}) -join ":"})) -replace '[{}]',''

                $MyHash=@{  
                    ComputerName     = $HBA.__SERVER  
                    NodeWWN          = (($HBA.NodeWWN) | ForEach-Object {"{0:X2}" -f $_}) -join ":" ## This has to be converted to HEX
                    PortWWN          = $Ports
                    Active           = $HBA.Active  
                    DriverName       = $HBA.DriverName  
                    DriverVersion    = $HBA.DriverVersion  
                    FirmwareVersion  = $HBA.FirmwareVersion  
                    Model            = $HBA.Model  
                    ModelDescription = $HBA.ModelDescription  
                    }  

                [PSCustomObject]$MyHash

            }#Foreach 
    }#try 
    catch { 
        Write-Warning -Message $_ 
    } 
 
}#Foreach
  
