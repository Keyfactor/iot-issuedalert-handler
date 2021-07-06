# Copyright 2021 Keyfactor
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions
# and limitations under the License.

Import-Module GoogleCloud
$ScriptDir = Split-Path -parent $MyInvocation.MyCommand.Path
Import-Module $ScriptDir\..\powershellModules\kf_logging.psm1

# Specify the API URL base.
# Note that when we call the API we use Windows Auth:
#   1.) Ensure that Windows Authentication is enabled for the KeyfactorAPI endpoint (DefaultWebsite > KeyfactorAPI) in IIS
#   2.) For normal operation the Keyfactor Service (Timer Service) account is used -- Make sure this account has the appropriate Keyfactor & AD rights
#   3.) For testing from the portal, the Application Pool account is used -- Make sure this account has the appropriate Keyfactor & AD rights
#
# NOTE: For the control.thedemodrive.com instance, it will not respond locally to control.thedemodrive.com
#       instead, use keyfactor.thedemodrive.com for all API calls
#
$apiURL = 'https://keyfactor.thedemodrive.com/KeyfactorApi'

try {
	# Check and process the context parameters
	# The PowerShell alert handler injects the following into our runspace: [hashtable]$context
	# If a "OutputLog" value is passed that starts with "Y" we will output to a log file
	# If a "TestOnly" value is passed that starts with a "Y" we will skip posting to the GCP IoT Core
	[bool]$outputLog = $false
	if ($context["OutputLog"] -like "Y*" ) { $outputLog = $true }
	# Generate a log file for tracing if OutputLog is true
	$logFile = Initialize-KFLogs $outputLog "C:\CMS\scripts\gcp\" "gcpenroll" 5 #keep no more than 5 log files
	Add-KFInfoLog $outputLog $logFile "Starting Trace: $(Get-Date -format G)"

	$certTP = $context["TP"]
	Add-KFInfoLog $outputLog $logFile "Context variable 'TP - thumbprint' = $certTP"
	if ([string]::IsNullOrWhiteSpace($certTP)) { throw "Context variable 'TP' required" }
	$certDN = $context["DN"]
	Add-KFInfoLog $outputLog $logFile "Context variable 'DN' = $certDN"
	if ([string]::IsNullOrWhiteSpace($certDN)) { throw "Context variable 'DN' required" }
	$certCN = $context["CN"]
	Add-KFInfoLog $outputLog $logFile "Context variable 'CN' = $certCN"
	if ([string]::IsNullOrWhiteSpace($certCN)) { throw "Context variable 'CN' required" }

	[bool]$scheduleJob = $true
	if ($context["TestOnly"] -like "Y*" ) { $scheduleJob = $false }
	Add-KFWarningLog $outputLog $logFile "schedule job set to: = $scheduleJob via TestOnly flag"

	# By default, expiration handlers send emails. Turn this off
	Add-KFInfoLog $outputLog $logFile "Turning off emailing"
	$context["sendEMail"] = "false"

	# These values should be filled in with the appropriate values from Google Cloud
	$gProjectId = $context["GcpProjectId"]
	if ([string]::IsNullOrWhiteSpace($gProjectId)) { throw "Context variable 'GcpProjectId' required" }
	Add-KFInfoLog $outputLog $logFile "GCP Project Id: $gProjectId"

	$gProjectLocation = $context["GcpLocation"]
	if ([string]::IsNullOrWhiteSpace($gProjectLocation)) { throw "Context variable 'GcpProjectLocation' required" }
	Add-KFInfoLog $outputLog $logFile "GCP Project Location: $gProjectLocation"

	$gProjectRegistry = $context["GcpRegistry"]
	if ([string]::IsNullOrWhiteSpace($gProjectRegistry)) { throw "Context variable 'GcpProjectRegistry' required" }
	Add-KFInfoLog $outputLog $logFile "GCP Project Registry: $gProjectRegistry"

	$jsonKeyPath = $context["GcpServiceAccountJsonPath"]
	if ([string]::IsNullOrWhiteSpace($jsonKeyPath)) { throw "Context variable 'GcpServiceAccountJsonPath' required" }
	Add-KFInfoLog $outputLog $logFile "GCP Service Account Json Key Path: $jsonKeyPath"

	$env:Path += ";C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\bin\"
	$checkgcloud = Get-Command gcloud
	Add-KFInfoLog $outputLog $logFile "checking gcloud: $checkgcloud"

	if ($certDN -match 'iot-id-cert' ) {
		Add-KFInfoLog $outputLog $logFile "iot id cert, using certCN: $certCN as devicename"
		#get machine name out of cert CN
		$clientMachine = $certCN
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
		$unencoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("$b64_encoded_string"))
	} else {
		Add-KFWarningLog $outputLog $logFile "not iot id cert, exiting"
		exit
	}

	if ($testOnly) {
		Add-KFInfoLog $outputLog $logFile "skipping post to GCP IoT Core"
	} else {
		Add-KFInfoLog $outputLog $logFile "posting to GCP IoT core"
		#activate GCP service account  -> service account json credential
		gcloud-ps auth activate-service-account --key-file="$jsonKeyPath"
		$token = gcloud-ps auth print-access-token | Out-String
		#TODO these tokens are valid for ~1hr by default.  do we want to save it and re-use for multiple calls?
		Add-KFInfoLog $outputLog $logFile "gcp access token: $token"

		$gURL = "https://cloudiot.googleapis.com/v1/projects/$gProjectId/locations/$gProjectLocation/registries/$gProjectRegistry/devices"
		#Double check the format to match the template used available options: RSA_X509_PEM, RSA_PEM, ES256_PEM or ES256_X509_PEM
		$pubKeyObj = @{"format" = "ES256_X509_PEM"; "key" = $unencoded }
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
