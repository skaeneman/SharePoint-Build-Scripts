<# 
Description: The following script will read an XML configuration file create the Incomming and Outgoing
             email settings for a SharePoint 2010 farm. 
#>
Add-PSSnapin "Microsoft.SharePoint.PowerShell" -ErrorAction SilentlyContinue
Start-SPAssignment -global

function ConfigureEmail {
  [CmdletBinding()]
  param 
  (  
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$SettingsFile
  )
#prompts for xml file
[xml]$configFile = Get-Content "d:\IncommingOutgoingEmail.xml"

#$SettingsFile

#gets XML data and stores in variable
$emailConfig = ($configFile.Email)

#reads variables from XML for outgoing email settings
$server = $emailConfig.OutgoingEmail.OutboundSMTPServer
$from = $emailConfig.OutgoingEmail.FromAddress
$replyto = $emailConfig.OutgoingEmail.ReplyToAddress
$charset = $emailConfig.OutgoingEmail.CharacterSet

#gets central admin web application and sets outgoing email settings
$webApp = Get-SPWebApplication -IncludeCentralAdministration
$centralAdmin = $webApp | Where-Object {$_.IsAdministrationWebApplication}

if ( ($server -ne $null) -and ($from -ne $null) -and ($replyto -ne $null) -and ($charset -ne $null) )
{
    Write-Host -ForegroundColor "yellow" "Configuring outgoing email settings..."
    $centralAdmin.UpdateMailSettings($server, $from, $replyto, $charset)
    Write-Host -ForegroundColor "yellow" "Outgoing email has been sucessfully configured..."
}
else{ Write-Host -ForegroundColor "red" "One or more values were null for outgoing email.  Check XML input file..." }
}#ends function


#calls function
ConfigureEmail

Stop-SPAssignment -global