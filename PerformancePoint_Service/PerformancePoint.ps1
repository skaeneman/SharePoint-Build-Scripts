################################################################################################################################
# Creates the SharePoint 2013 PerformancePoint Service Application. 
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
$xmlConfig = @($configFile.PerformancePoint.ServiceApplication)

#maps XML tags with variable names
$serviceApplicationName = $xmlConfig.ServiceApplicationName
$startServicesOnServers = @($xmlConfig.StartServicesOnServer.Server)
$appPoolName = $xmlConfig.AppPoolName
$appPoolAccount = $xmlConfig.AppPoolAccount
$databaseServer = $xmlConfig.DatabaseServer
$databaseName = $xmlConfig.DatabaseName

$farmAccount = $xmlConfig.SecureStoreTarget.FarmAccount #SP2013 farm admin account (domain\user)
$unattendedSvcAcct = $xmlConfig.SecureStoreTarget.UnattendedServiceAccount  #secure store unattended service account to be used for excel services
$unattendedSvcPass = $xmlConfig.SecureStoreTarget.UnattendedServiceAccountPassword #password for the secure store unattended service account
$targetAppEmail = $xmlConfig.SecureStoreTarget.TargetApplicationEmail  #email address to be used for secure store target application

$serviceName = "PerformancePoint Service"

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
	
        #gets service app
        try{
            $svcApp = Get-SPPerformancePointServiceApplication $serviceApplicationName -ErrorAction SilentlyContinue
        }catch { }
        
              #creates the PerformancePoint service app  
        if($svcApp -eq $null)
        {
            Write-Host -ForegroundColor Cyan "Creating the PerformancePoint Service Application..."
            # to see all available options use "Get-Help New-SPPerformancePointServiceApplication -full"
            $performancePointSvcApp = New-SPPerformancePointServiceApplication `
                           -DatabaseServer $databaseServer -DatabaseName $databaseName  `
                           -ApplicationPool $appPoolName -Name $serviceApplicationName -AnalyticQueryCellMax 100000  `
                           -AnalyticQueryLoggingEnabled $false  -ApplicationCacheEnabled $true  `
                           -ApplicationCacheMinimumHitCount 2 -ApplicationProxyCacheEnabled $true  `
                           -CommentsDisabled $false -CommentsScorecardMax 1000  `
                           -DataSourceQueryTimeoutSeconds 300  -DecompositionTreeMaximum 25  `
                           -ElementCacheSeconds 15 -FilterRememberUserSelectionsDays 90  `
                           -FilterTreeMembersMax 500  -IndicatorImageCacheSeconds 10  `
                           -MSMQEnabled $false -MSMQName "MessageQueue" -SelectMeasureMaximum 10  `
                           -SessionHistoryHours 2  -ShowDetailsInitialRows 1000 -ShowDetailsMaxRows 10000  `
                           -ShowDetailsMaxRowsDisabled $false -TrustedContentLocationsRestricted $false  `
                           -TrustedDataSourceLocationsRestricted $false 
            Start-Sleep -Seconds 30     
             
            ##############################################################
            # Creates the service application proxy for PerformancePoint  
            ##############################################################
            Write-Host -ForegroundColor Cyan "Creating the PerformancePoint Service Application Proxy..."
            $performancePointSvcAppProxy = New-SPPerformancePointServiceApplicationProxy   `
            -ServiceApplication $performancePointSvcApp.Id -Name "$($performancePointSvcApp.Name) Proxy" `
            -Default #adds to default proxy group for all web apps
             Start-Sleep -Seconds 30                                                                                                    
             
        }#ends if
        else {Write-Host -ForegroundColor Red "'$ServiceApplicationName' is aready enabled"}
    }#ends try    
catch [system.exception]{ 
       $($_.Exception.Message) 
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
 
#########################################################################################################
# Adds the farm admin account to the PerformancePoint database.
# There is a known issue where the farm admin account is not automatically added to the PerformancePoint
# database.  The below function sets the farm admin as a "db_owner" on the database.
#########################################################################################################   
     try{
            $svcApp = Get-SPPerformancePointServiceApplication $serviceApplicationName -ErrorAction SilentlyContinue
        }catch { }
        
        if($svcApp -ne $null)
        {
            Write-Host -ForegroundColor Cyan "Granting 'db_owner' permissions to $farmAccount on $databaseName"
            $svcApp = Get-SPServiceApplication $svcApp.Id
            $svcApp.Database.GrantOwnerAccessToDatabaseAccount()
        }
        else {Write-Host -ForegroundColor Red "Could NOT grant 'db_owner' permissions to $farmAccount on $databaseName"}
        
#####################################################################################
# Creates the Secure Store target application for PerformancePoint
#####################################################################################   

    #Get credentials for unattended service account
    $unattendedSvcPassSecure = ConvertTo-SecureString -String $unattendedSvcPass -AsPlainText -force 
    $unattendedAccount = New-Object System.Management.Automation.PSCredential($unattendedSvcAcct, $unattendedSvcPassSecure)
    
    #gets service app
     try{
            $ppSvcApp = Get-SPPerformancePointServiceApplication -ErrorAction SilentlyContinue
        }catch { }
        
        if($ppSvcApp -ne $null)
        {
            Write-Host -ForegroundColor Cyan "Creating the Secure Store Target Application for PerformancePoint..."
            Set-SPPerformancePointSecureDataValues  -ServiceApplication $ppSvcApp  `
            -DataSourceUnattendedServiceAccount $unattendedAccount  
        }
        else {Write-Host -ForegroundColor Red $_.Exception.Message "There was an error creating the PerformancePoint Secure Store Target Application..."}         


Stop-SPAssignment -Global | Out-Null