# Copyright 2021 Keyfactor
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions
# and limitations under the License.

Import-Module GoogleCloud
function Add-KFTraceLog {
    <#
    .SYNOPSIS
    Adds the $message to the logfile as it's own line marked as [T] to be used for Tracing,
    Also displays the message on the screen
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is
    .PARAMETER message - the string contents to write to the file
    #>
    param(
        [boolean]$OutputLog, 
        $LogFilePath, 
        $message)
    if ($null -eq $LogFilePath) {
        throw "trace log file path required"
    }
    if ($OutputLog) {
        $outMsg = (Get-Date -Format "hh:mm") + "[T] $message"
        Add-Content -Path $LogFilePath -Value $outMsg
        Write-Host $outMsg -ForegroundColor white
    }
}
function Add-KFInfoLog {
    <#
    .SYNOPSIS
    Adds the $message to the logfile as it's own line marked as [I] to be used for information,
    Also displays the message on the screen
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is
    .PARAMETER message - the string contents to write to the file
    #>
    param(
        [boolean]$OutputLog, 
        $LogFilePath, 
        $message)
    if ($null -eq $LogFilePath) {
        throw "info log file path required"
    }
    if ($OutputLog) {
        $outMsg = (Get-Date -Format "hh:mm") + "[I] $message"
        Add-Content -Path $LogFilePath -Value $outMsg
        Write-Host $outMsg -ForegroundColor white
    }
}
function Add-KFErrorLog {
    <#
    .SYNOPSIS
    Adds the $message to the logfile as it's own line marked as [E] to be used as an Error Message,
    Also displays the message on the screen in red
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is
    .PARAMETER message - the string contents to write to the file
    #>
    param(
        [boolean]$OutputLog, 
        $LogFilePath, 
        $message)
    if ($null -eq $LogFilePath) {
        throw "Error log file path required"
    }
    if ($OutputLog) {
        $outMsg = (Get-Date -Format "hh:mm") + "[E] $message"
        Add-Content -Path $LogFilePath -Value $outMsg
        Write-Host $outMsg -ForegroundColor red
    }
}
function Add-KFWarningLog {
    <#
    .SYNOPSIS
    Adds the $message to the logfile as it's own line marked as [W] to be used as a Warning Message,
    Also displays the message on the screen in yellow
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is
    .PARAMETER message - the string contents to write to the file
    #>
    param(
        [boolean]$OutputLog, 
        $LogFilePath, 
        $message)
    if ($null -eq $LogFilePath) {
        throw "Warning log file path required"
    }
    if ($OutputLog) {
        $outMsg = (Get-Date -Format "hh:mm") + "[W] $message"
        Add-Content -Path $LogFilePath -Value $outMsg
        Write-Host $outMsg -ForegroundColor Yellow
    }
}
function LogHelper { #TODO (sukhyung) finish+use this instead of duplicating the same stuff 4x
    param(
        [boolean]$OutputLog,
        $LogFilePath,
        $message,
        $type)
    if ($null -eq $LogFilePath) {
        throw "$type log file path required"
    }
    if ($OutputLog) {
        $outMsg = (Get-Date -Format "hh:mm") + "$type $message"
        Add-Content -Path $LogFilePath -Value $outMsg
        #switch ($type) {
        #condition {  }
        #Default {}
        #}
        #Write-Host $outMsg -ForegroundColor $Color
    }
}
function Initialize-KFLogs {
    <#
    .SYNOPSIS
    Initializes logging for a given filepath.  creates the file is not already present, one per day of the year (e.g. run the initialize
    twice in the same day, it will append the first file).  It will also ensure that only the latest $MaxFileCount log files are present.
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is/should be (YYMMDD.txt is appended to this as the filename
    .PARAMETER LogFilePrefix - the string the log file should be named.
    .PARAMETER MaxFileCount - the maximum number of log files to keep in the $LogFilePath
    .OUTPUTS
    System.String. Intialize-KFLogs returns the path to the log file that should be used.
    #>
    param(
        [boolean]$OutputLog,
        $LogFilePath,
        $LogFilePrefix,
        [int] $MaxFileCount
    )
    #todo validate arguments?
    $LogFileName = $LogFilePath + "\" + $LogFilePrefix + (Get-Date -UFormat "%Y%m%d") + ".txt" #one log file per day
    if (!(Test-Path $LogFileName)) {
        #if file doesnt exist, create it
        $null = New-Item -ItemType file $LogFileName
    }

    $LogFormat = $LogFilePrefix + "*.txt"
    $existingLogs = [System.IO.Directory]::GetFiles("$LogFilePath", "$LogFormat") | Sort-Object -Descending #want newest to be first

    if ($existingLogs.Count -gt $MaxFileCount) {
        #keep only the $MaxFileCount latest log files
        for ($i = $MaxFileCount; $i -lt $existingLogs.Count; $i++) {
            Add-KFInfoLog $OutputLog $LogFileName "Deleting expired Logfile: $existingLogs[$i]"
            [System.IO.File]::Delete($existingLogs[$i])
        }
    }
    return $LogFileName
}
# Specify the API URL base.
# Note that when we call the API we use Windows Auth:
#   1.) Ensure that Windows Authentication is enabled for the KeyfactorAPI endpoint (DefaultWebsite > KeyfactorAPI) in IIS
#   2.) For normal operation the Keyfactor Service (Timer Service) account is used -- Make sure this account has the appropriate Keyfactor & AD rights
#   3.) For testing from the portal, the Application Pool account is used -- Make sure this account has the appropriate Keyfactor & AD rights
#
# NOTE: For the control.thedemodrive.com instance, it will not respond locally to control.thedemodrive.com
#       instead, use keyfactor.thedemodrive.com for all API calls
#
$apiURL = 'https://control-ecc.thedemodrive.com/KeyfactorApi'

# Check and process the context parameters
# The PowerShell alert handler injects the following into our runspace: [hashtable]$context
# If a "OutputLog" value is passed that starts with "Y" we will output to a log file
# If a "TestOnly" value is passed that starts with a "Y" we will skip posting to the GCP IoT Core
[bool]$outputLog = $false
if ($context["OutputLog"] -like "Y*" ) { 
    $outputLog = $true 
}
# Generate a log file for tracing if OutputLog is true
$logFile = Initialize-KFLogs $outputLog "C:\Keyfactor\logs" "gcpenroll" 5 #keep no more than 5 log files

try {
    Add-KFInfoLog $outputLog $logFile "Starting Trace: $(Get-Date -format G)"

    #$apiURL = $context["ApiUrl"] -> we can hardcode this (above)
    #Add-KFInfoLog $outputLog $logFile "Context variable 'ApiUrl' = $apiURL"
    #if ([string]::IsNullOrWhiteSpace($apiURL)) { throw "Context variable 'ApiUrl' required" }

    $certTP = $context["TP"]
    Add-KFInfoLog $outputLog $logFile "Context variable 'TP - thumbprint' = $certTP"
    if ([string]::IsNullOrWhiteSpace($certTP)) { throw "Context variable 'TP' required" }

    [bool]$skipGCPpart = $false
    if ($context["SkipGCPpart"] -eq "yes") { 
        $skipGCPpart = $true 
        Add-KFInfoLog $outputLog $logFile "Skipping anything associated with GCP"
    }
    else {
        Add-KFInfoLog $outputLog $logFile "Performing GCP Part"
    }

    [bool]$scheduleJob = $true
    if ($context["TestOnly"] -like "Y*" ) { $scheduleJob = $false }
    Add-KFWarningLog $outputLog $logFile "schedule job set to: = $scheduleJob via TestOnly flag"


    # By default, expiration handlers send emails. Turn this off
    Add-KFInfoLog $outputLog $logFile "Turning off emailing"
    $context["sendEMail"] = "false"

    # These values should be filled in with the appropriate values from Google Cloud ->project/location/region are from the metadata
    $gProjectId = $context["GcpProjectId"]
	if ([string]::IsNullOrWhiteSpace($gProjectId)) { throw "Context variable 'GcpProjectId' required" }
    Add-KFInfoLog $outputLog $logFile "GCP Project Id: $gProjectId"
	
    $gProjectLocation = $context["GcpLocation"]
	if ([string]::IsNullOrWhiteSpace($gProjectLocation)) { throw "Context variable 'GcpProjectLocation' required" }
    Add-KFInfoLog $outputLog $logFile "GCP Project Location: $gProjectLocation"

    $gProjectRegistry = $context["GcpRegistry"]
	if ([string]::IsNullOrWhiteSpace($gProjectRegistry)) { throw "Context variable 'GcpProjectRegistry' required" }
    Add-KFInfoLog $outputLog $logFile "GCP Project Registry: $gProjectRegistry"

    $clientMachine = $context["CN"]
	if ([string]::IsNullOrWhiteSpace($clientMachine)) { throw "Context variable 'CN' required" }
    Add-KFInfoLog $outputLog $logFile "GCP device id/CN: $clientMachine"

    $certDN = $context["DN"]
	if ([string]::IsNullOrWhiteSpace($certDN)) { throw "Context variable 'DN' required" }
    Add-KFInfoLog $outputLog $logFile "cert DN: $certDN"

    $jsonKeyPath = $context["GcpServiceAccountJsonPath"]
    if ([string]::IsNullOrWhiteSpace($jsonKeyPath)) { throw "Context variable 'GcpServiceAccountJsonPath' required" }
    Add-KFInfoLog $outputLog $logFile "GCP Service Account Json Key Path: $jsonKeyPath"

    $env:Path += ";C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\bin\"
    $checkgcloud = Get-Command gcloud
    Add-KFInfoLog $outputLog $logFile "checking gcloud: $checkgcloud"

	if ($certDN -match 'iot-id-cert' ) {
		Add-KFInfoLog $outputLog $logFile "iot id cert, using certCN: $clientMachine as devicename"
		#get machine name out of cert CN
		
		# Send an API call to grab the certificate using the cert thumbprint
		$headers = @{}
		$headers.Add('Content-Type', 'application/json')
		$headers.Add('x-keyfactor-requested-with', 'APIClient')
		$uri = "$($apiURL)/Certificates?pq.queryString=thumbprint%20-eq%20%22$certTP%22"
		#todo figure out how to make this work, should be able to remove the second api call
		#$uri = "$($apiURL)/Certificates?pq.queryString=thumbprint%20-eq%20%22$certTP%22&verbose=2"
		Add-KFInfoLog $outputLog $logFile "Preparing a GET from $uri"
		$response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -UseDefaultCredentials
		Add-KFInfoLog $outputLog $logFile "Got back $($response)"
		$certId = $response[0].Id
		#expiration date is needed by GCP
		$expiryDate = $response[0].NotAfter

			# Send an API call to grab the certificate by its cert id
			$uri = "$($apiURL)/Certificates/Download"
			$body = @{"CertId" = $certId } | ConvertTo-Json -Compress
			$headers.Add('X-CertificateFormat', 'PEM')
			Add-KFInfoLog $outputLog $logFile "Preparing a POST from $uri with body $body"
			$response = Invoke-RestMethod -Uri $uri -Method POST -Body $body -Headers $headers -UseDefaultCredentials
			Add-KFInfoLog $outputLog $logFile "Got back $($response)"
	
			# The response should contain the base 64 PEM, We are after the payload
			$b64_encoded_string = $response[0].Content
			$unencoded1 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("$b64_encoded_string"))
		} else {
			Add-KFWarningLog $outputLog $logFile "not iot id cert, exiting"
			exit
		}
 

    if ($testOnly) {
        Add-KFInfoLog $outputLog $logFile "skipping post to GCP IoT Core"
    }
    else {
        Add-KFInfoLog $outputLog $logFile "posting to GCP IoT core"
        #activate GCP service account  -> service account json credential
        gcloud-ps auth activate-service-account --key-file="$jsonKeyPath"
        Add-KFInfoLog $outputLog $logFile "service account activated"
        #Add-KFInfoLog $outputLog $logFile "gcloud iot devices create $clientMachine --project=$gProjectId --region=$gProjectLocation --registry=$gProjectRegistry --public-key path=c:\temp\tmp1.pem,type=es256-x509-pem,expiration-time=$expiryDate --public-key path=c:\temp\tmp2.pem,type=es256-x509-pem,expiration-time=$expiryDate --auth-method='ASSOCIATION_ONLY'"
        #$gresponse = gcloud iot devices create $clientMachine --device-type=gateway --project="$gProjectId" --region="$gProjectLocation" --registry="$gProjectRegistry" --public-key "path=c:\temp\tmp1.pem,type=es256-x509-pem,expiration-time=$expiryDate" --public-key "path=c:\temp\tmp2.pem,type=es256-x509-pem,expiration-time=$expiryDate" --auth-method='ASSOCIATION_ONLY'
		$token = gcloud-ps auth print-access-token | Out-String
		#TODO these tokens are valid for ~1hr by default.  do we want to save it and re-use for multiple calls?
		Add-KFInfoLog $outputLog $logFile "gcp access token: $token"

		$gURL = "https://cloudiot.googleapis.com/v1/projects/$gProjectId/locations/$gProjectLocation/registries/$gProjectRegistry/devices"
		#Double check the format to match the template used available options: RSA_X509_PEM, RSA_PEM, ES256_PEM or ES256_X509_PEM
		$pubKeyObj = @{"format" = "ES256_X509_PEM"; "key" = $unencoded1 }
		$credObj = @{"expirationTime" = $expiryDate; "publicKey" = $pubKeyObj }
		$gBodyObj = @{"id" = $clientMachine; "credentials" = $credObj; "blocked" = $false }
		$gBodyJsonTmp = ConvertTo-Json $gBodyObj -Compress
		$gBodyJson = $gBodyJsonTmp
		$h2 = @{}
		$h2.Add('Content-Type', 'application/json')
		$h2.Add('Authorization', "Bearer $token")
		Add-KFInfoLog $outputLog $logFile "posting to GCP IoT core at $gURL with Body of $($gBodyJson); headers: $h2"
		$gresponse = Invoke-RestMethod -Uri $gURL -Method POST -Headers $h2 -ContentType 'application/json' -Body $gBodyJson
		
        Add-KFInfoLog $outputLog $logFile "response from google: $gresponse"
    }
}
catch {
    Add-KFErrorLog $outputLog $logFile "exception caught during operation: $_.Exception.Message"
    Add-KFErrorLog $outputLog $logFile $_
}
Add-KFInfoLog $outputLog $logFile "Exiting script: $(Get-Date -format G) `r`n ========================================="