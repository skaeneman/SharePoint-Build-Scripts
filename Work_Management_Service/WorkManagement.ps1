################################################################################################################################
# Creates the SharePoint 2013 Work Management Service Application. 
# Note: DO NOT USE THE FQDN OF THE SERVER IN THE XML FILE, JUST USE THE SERVER NAME ONLY (ex "sandox" not "sandbox.domain.com")
# Read this blog for account requirments
# http://social.technet.microsoft.com/wiki/contents/articles/12525.sharepoint-2013-work-management-service-application.aspx
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
$xmlConfig = @($configFile.WorkManagement.ServiceApplication)

#maps XML tags with variable names
$serviceApplicationName = $xmlConfig.ServiceApplicationName
$startServicesOnServers = @($xmlConfig.StartServicesOnServer.Server)
$appPoolName = $xmlConfig.AppPoolName
$appPoolAccount = $xmlConfig.AppPoolAccount
$serviceName = "Work Management Service"

#############################################################
# Checks for an existing service application and app pool
#############################################################
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
			Write-Host -ForegroundColor Cyan "The application pool '$appPoolName' does not exist, creating it"
        	New-SPServiceApplicationPool -Name $appPoolName -Account $managedAccount | Out-Null
			Start-Sleep 15
        }
    
	#####################################		
	# Creates the service application.      
	#####################################
	Write-Host -ForegroundColor Cyan "Creating the '$serviceApplicationName' Service Application"
	try{	
  		$svcApp = Get-SPServiceApplication | where-object {$_.Name -eq $serviceApplicationName}
	
        if($svcApp -eq $null)
        {
		try{
	        $workMansvcApp = New-SPWorkManagementServiceApplication `
			-Name $ServiceApplicationName `
			-ApplicationPool $appPoolName
			 Start-Sleep 10
		 }			
		 catch [system.Exception]
		 {
			$errorMessage = $_.Exception.Message
			Write-Host -ForegroundColor Red "Could not create the service application." $errorMessage
		 }	 
			##########################################		
			# Creates the service application Proxy.      
			##########################################     
			try{
			  	$svcApp = Get-SPServiceApplication | where-object {$_.Name -eq $serviceApplicationName}

				Write-Host -ForegroundColor Cyan "Creating '$serviceApplicationName' Proxy"
				  
        		$workMansvcAppProxy = New-SPWorkManagementServiceApplicationProxy `
				-Name "$serviceApplicationName Proxy" `
				-DefaultProxyGroup -ServiceApplication $serviceApplicationName
				}
			 catch [system.Exception]
			 {
				$errorMessage = $_.Exception.Message
				Write-Host -ForegroundColor Red "Could not create '$serviceApplicationName Proxy'." $errorMessage
			 }	
					 
        }#ends if
        else {Write-Host -ForegroundColor Red "the '$ServiceApplicationName' Service Application is aready enabled"}
	 }
	 catch [system.Exception]
	 {
		$errorMessage = $_.Exception.Message
		Write-Host -ForegroundColor Red "Could not create the service application." $errorMessage
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