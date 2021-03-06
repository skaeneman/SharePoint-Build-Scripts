################################################################################################################################
# Creates the SharePoint 2013 Word Automation Service Application. 
# Note: DO NOT USE THE FQDN OF THE SERVER IN THE XML FILE, JUST USE THE SERVER NAME ONLY (ex "sandox" not "sandbox.domain.com")
#################################################################################################################################

#allows "-XmlFilePath" to be passed as a parameter in the shell (must be first line in script)
param([Parameter(Mandatory=$true, Position=0)]
      [ValidateNotNullOrEmpty()]
	  [string]$XmlFilePath)

#loads PowerShell cmdlets for SharePoint
Write-Host -ForegroundColor Cyan "Enabling SharePoint PowerShell cmdlets..."
Add-PsSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue

Start-SPAssignment -Global | Out-Null

#loads XML config file that user entered
[xml]$configFile = Get-Content $XmlFilePath
$xmlConfig = @($configFile.WordAutomation.ServiceApplication)

#maps XML tags with variable names
$serviceApplicationName = $xmlConfig.ServiceApplicationName
$startServicesOnServers = @($xmlConfig.StartServicesOnServer.Server)
$appPoolName = $xmlConfig.AppPoolName
$appPoolAccount = $xmlConfig.AppPoolAccount
$databaseServer = $xmlConfig.DatabaseServer
$databaseName = $xmlConfig.DatabaseName

$serviceName = "Word Automation Services"

#############################################################
# Checks for an existing service application and app pool
#############################################################
try
{
	Write-Host -ForegroundColor Cyan "Checking for existing Service Application called: $serviceApplicationName"
    $ExistingServiceApp = Get-SPServiceApplication | where-object {$_.Name -eq $serviceApplicationName}

	if ($ExistingServiceApp -ne $null)
	{
        Write-Host -ForegroundColor Red "'$serviceApplicationName' already exists, stopping script!";break
    }
	else
    {			
		#tries to get managed account, script will error if one doesn't exist	
		$managedAccount = Get-SPManagedAccount -Identity $appPoolAccount
		
		#Checks if the application pool already exists, if not it creates one
        $applicationPool = Get-SPServiceApplicationPool -Identity $appPoolName -ErrorAction SilentlyContinue
        if ($applicationPool -eq $null)
        {
			Write-Host -ForegroundColor Cyan "The application pool '$appPoolName' does not exist, creating it"
        	New-SPServiceApplicationPool -Name $appPoolName -Account $managedAccount | Out-Null
			Start-Sleep 30
        }
    
	#######################################		
	# Creates the service application.      
	#######################################
	
  try{
    	$svcApp = Get-SPServiceApplication | where-object {$_.Name -eq $serviceApplicationName}
       }catch { }
		
     try{   
        if($svcApp -eq $null){
		Write-Host -ForegroundColor Cyan "Creating '$serviceApplicationName'"
		
	        #Creates the service app if it doesn't exist.  Proxy is created automatically  
	        if($svcApp -eq $null)
	        {
	            Write-Host -ForegroundColor Cyan "Creating $serviceApplicationName and it's Proxy..."
	            $wordSvcApp =  New-SPWordConversionServiceApplication  `
	                           -ApplicationPool $appPoolName -Name $serviceApplicationName `
	                           -DatabaseName $databaseName -DatabaseServer $databaseServer `
	                           -Default #puts in default proxy group
	                                                                                                       
	        }#ends if
	        else {Write-Host -ForegroundColor "Red" "'$serviceApplicationName' is aready enabled"}
		
		}#ends if
        else {Write-Host -ForegroundColor Red "'$serviceApplicationName' is aready enabled"}
		
 	}#ends try    
	catch [system.exception]{ 
       		Write-Host -ForegroundColor Cyan "Couldn't create '$serviceApplicationName'." $_.Exception.Message 
    	}         
		    
	##############################################
	# Starts service instances on servers in farm
	##############################################
	try{
        Write-Host -ForegroundColor Cyan "Starting service instances on servers"
		
        foreach ($server in $startServicesOnServers) 
        {					
            #Gets the service to determine its status
            $service = $(Get-SPServiceInstance | where {$_.TypeName -match $serviceName} | where {$_.Server -match "SPServer Name="+$server.name})
            
            If (($service.Status -eq "Disabled") -or ($service.status -ne "Online")) 
            {
               	Write-Host -ForegroundColor Cyan "Starting" $service.Service "on" $server.name
                Start-SPServiceInstance -Identity $service.ID | Out-Null
            }
			else {Write-Host -ForegroundColor red $service.Service "is already enabled or could not be started on" $server.name}
        }#ends foreach
	}#ends try
		
	catch [system.Exception]
	{
			$errorMessage = $_.Exception.Message
			write-host -ForegroundColor Red "Couldn't start services on servers." $errorMessage
	}
             
	}#ends first else
}#ends first try
catch [system.Exception]
{
	$errorMessage = $_.Exception.Message
	$errorMessage
}
 

Stop-SPAssignment -Global | Out-Null