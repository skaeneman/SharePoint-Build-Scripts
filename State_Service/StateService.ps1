#Creates the SharePoint 2013 State Service Application. 
#Note: DO NOT USE THE FQDN OF THE SERVER IN THE XML FILE, JUST USE THE SERVER NAME ONLY (ex "sandox" not "sandbox.domain.com")

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
$xmlConfig = @($configFile.StateService.ServiceApplication)

#maps XML tags with variable names
$serviceApplicationName = $xmlConfig.ServiceApplicationName
$databaseName = $xmlConfig.DatabaseName
$databaseServer = $xmlConfig.DatabaseServer

##############################################
# Checks for an existing service application
##############################################
try
{
	Write-Host -ForegroundColor Cyan "Checking for existing Service Application called: $serviceApplicationName"
    $ExistingServiceApp = Get-SPServiceApplication | where-object {$_.Name -eq $serviceApplicationName}

	if ($ExistingServiceApp -ne $null)
	{
        Write-Host -ForegroundColor Red "'$ServiceApplicationName' already exists, stopping script!";break
    }
	else
    {			
		#tries to get managed account, script will error if one doesn't exist	
		$managedAccount = Get-SPManagedAccount -Identity $appPoolAccount
		
		#Checks if the application pool already exists, if not it creates one
        $applicationPool = Get-SPServiceApplicationPool -Identity $appPoolName -ErrorAction SilentlyContinue
        if ($applicationPool -eq $null)
        {
			Write-Host -ForegroundColor Cyan "the application pool '$appPoolName' does not exist, creating it"
        	New-SPServiceApplicationPool -Name $appPoolName -Account $managedAccount | Out-Null
			Start-Sleep 30
        }
  
  	############################################		
	# Creates the database   
	############################################
	try{	
		$stateServiceDatabase = Get-SPStateServiceDatabase $databaseName
		if ($stateServiceDatabase -eq $null)
		{
		    Write-Host -ForegroundColor Cyan "the $stateSvcDatabaseName database is being created..."
		    $stateServiceDatabase = New-SPStateServiceDatabase -Name $databaseName -DatabaseServer $databaseServer -Weight 1
		    $stateServiceDatabase | Initialize-SPStateServiceDatabase
		}
		 else {Write-Host -ForegroundColor Cyan "a database named $databaseName already exists..."}  
	}#ends try
	 catch [system.Exception]
	 {
		$errorMessage = $_.Exception.Message
		Write-Host -ForegroundColor Red "Could not create the state service database." $errorMessage
	 }	
  
	############################################		
	# Creates the service application    
	############################################
	Write-Host -ForegroundColor Cyan "Creating the '$ServiceApplicationName' Service Application"
	try{	
		$stateSvcApp = Get-SPStateServiceApplication $serviceApplicationName
		if ($stateSvcApp -eq $null)
		{
		    Write-Host -ForegroundColor Cyan "The $ServiceApplicationName is being created..."
		    $stateSvcApp = New-SPStateServiceApplication -Name $serviceApplicationName -Database $databaseName
		}  
		else {Write-Host -ForegroundColor Red "$ServiceApplicationName already exists..."}      
	 }
	 catch [system.Exception]
	 {
		$errorMessage = $_.Exception.Message
		Write-Host -ForegroundColor Red "Could not create the service application." $errorMessage
	 }	
	 
	############################################# 
	# Creates the service application proxy 
	#############################################
	try{		
		$serviceAppProxyName = "$ServiceApplicationName Proxy"
		$svcAppProxy = Get-SPStateServiceApplicationProxy $serviceAppProxyName
			if ($svcAppProxy -eq $null)
			{
			    Write-Host -ForegroundColor Cyan "the '$serviceAppProxyName' is being created..."
				
			    $svcAppProxy = New-SPStateServiceApplicationProxy `
				-ServiceApplication $ServiceApplicationName `
				-Name $serviceAppProxyName `
				-DefaultProxyGroup
			}
		else {Write-Host -ForegroundColor Red "a service application proxy named $serviceAppProxyName already exists..."}   

     }
	 catch [system.Exception]{
		$errorMessage = $_.Exception.Message
		Write-Host -ForegroundColor Red "Could not create the service application proxy." $errorMessage
	 }	
	 
             
	}#ends first else
}#ends try
catch [system.Exception]
{
	$errorMessage = $_.Exception.Message
	$errorMessage
}
 
 Stop-SPAssignment -Global | Out-Null