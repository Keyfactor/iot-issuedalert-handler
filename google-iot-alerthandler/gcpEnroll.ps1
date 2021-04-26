# Copyright 2021 Keyfactor
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions
# and limitations under the License.

Import-Module GoogleCloud

# Specify the API URL base.
# Note that when we call the API we use Windows Auth:
#	1.) Ensure that Windows Authentication is enabled for the KeyfactorAPI endpoint (DefaultWebsite > KeyfactorAPI) in IIS
#   2.) For normal operation the Keyfactor Service (Timer Service) account is used -- Make sure this account has the appropriate Keyfactor & AD rights
#   3.) For testing from the portal, the Application Pool account is used -- Make sure this account has the appropriate Keyfactor & AD rights
#
# NOTE: For the control.thedemodrive.com instance, it will not respond locally to control.thedemodrive.com
#       instead, use keyfactor.thedemodrive.com for all API calls
#
$apiURL = 'https://keyfactor.thedemodrive.com/KeyfactorApi'
#fill in Google Cloud Platform Iot Core Specific identifier information.
#$gProjectId = 'iot-test-308421'
#$gProjectRegistry = 'test-registry'
#$gProjectLocation = 'us-central1'
#$jsonKeyPath = "C:\CMS\Scripts\iot-test-308421-ad1344b10b3b.json"


try {
	# Check and process the context parameters
	# The PowerShell alert handler injects the following into our runspace: [hashtable]$context
	# We expect that a "SN" value will be passed in which was mapped from {sn}
	# If a "OutputLog" value is passed that starts with "Y" we will output to a log file
	# If a "TestOnly" value is passed that starts with a "Y" we will skip posting to the GCP IoT Core
	[bool]$outputLog = $false
	if ($context["OutputLog"] -like "Y*" ) { $outputLog = $true } 
	# Generate a log file for tracing if OutputLog is true
	if ($outputLog) { $outputFile = ("C:\CMS\scripts\gcpenroll_" + (get-date -UFormat "%Y%m%d%H") + ".txt") }
	if ($outputLog) { Add-Content -Path $outputFile -Value "Starting Trace: $(Get-Date -format G)" }

	$certTP = $context["TP"]
	if ($outputLog) { Add-Content -Path $outputFile -Value "Context variable 'TP - thumbprint' = $certTP" }
	if ([string]::IsNullOrWhiteSpace($certTP)) { throw "Context variable 'TP' required" }
	$certDN = $context["DN"]
	if ($outputLog) { Add-Content -Path $outputFile -Value "Context variable 'DN' = $certDN" }
	if ([string]::IsNullOrWhiteSpace($certDN)) { throw "Context variable 'DN' required" }
	$certCN = $context["CN"]
	if ($outputLog) { Add-Content -Path $outputFile -Value "Context variable 'CN' = $certCN" }
	if ([string]::IsNullOrWhiteSpace($certCN)) { throw "Context variable 'CN' required" }

	[bool]$scheduleJob = $true
	if ($context["TestOnly"] -like "Y*" ) { $scheduleJob = $false } 
	if ($outputLog) { Add-Content -Path $outputFile -Value "schedule job set to: = $scheduleJob via TestOnly flag" }

	# By default, expiration handlers send emails. Turn this off
	if ($outputLog) { Add-Content -Path $outputFile -Value "Turning off emailing" }
	$context["sendEMail"] = "false"

	# These values should be filled in with the appropriate values from Google Cloud
	$gProjectId = $context["GcpProjectId"]
	if ([string]::IsNullOrWhiteSpace($gProjectId)) { throw "Context variable 'GcpProjectId' required" }
	$gProjectLocation = $context["GcpLocation"]
	if ([string]::IsNullOrWhiteSpace($gProjectLocation)) { throw "Context variable 'GcpProjectLocation' required" } 
	$gProjectRegistry = $context["GcpRegistry"]
	if ([string]::IsNullOrWhiteSpace($gProjectRegistry)) { throw "Context variable 'GcpProjectRegistry' required" }
	$jsonKeyPath = $context["GcpServiceAccountJsonPath"]
	if ([string]::IsNullOrWhiteSpace($jsonKeyPath)) { throw "Context variable 'GcpServiceAccountJsonPath' required" }
	if ($outputLog) { 
		Add-Content -Path $outputFile -Value "GCP Project Id: $gProjectId" 
		Add-Content -Path $outputFile -Value "GCP Project Location: $gProjectLocation" 
		Add-Content -Path $outputFile -Value "GCP Project Registry: $gProjectRegistry" 
		Add-Content -Path $outputFile -Value "GCP Service Account Json Key Path: $jsonKeyPath" 
	}

	$env:Path += ";C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\bin\"
	$checkgcloud = Get-Command gcloud
	if ($outputLog) { Add-Content -Path $outputFile -Value "checking gcloud: $checkgcloud" }

	if ($certDN -match 'iot-id-cert' ) {
		if ($outputLog) { Add-Content -Path $outputFile -Value "iot id cert, using certCN: $certCN as devicename" }
		#get machine name out of cert CN
		$clientMachine = $certCN
		# Send an API call to grab the cetificate from the cert serial number
		$headers = @{}
		$headers.Add('Content-Type', 'application/json')
		$headers.Add('x-keyfactor-requested-with', 'APIClient')
		$uri = "$($apiURL)/Certificates?pq.queryString=thumbprint%20-eq%20%22$certTP%22"
		#todo figure out how to make this work, should be able to remove the second api call
		#$uri = "$($apiURL)/Certificates?pq.queryString=thumbprint%20-eq%20%22$certTP%22&verbose=2"
		if ($outputLog) { Add-Content -Path $outputFile -Value "Preparing a GET from $uri" }
		$response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -UseDefaultCredentials
		if ($outputLog) { Add-Content -Path $outputFile -Value "Got back $($response)" }
		$certId = $response[0].Id
		#TODO this is already in the right format, but needs to have ----begin/end certificate----- and lines
		#$b64_encoded_cert = $response[0].ContentBytes
		#decode the cert
		#if ($outputLog) { Add-Content $outputFile -Value "b64 encoded certificate is: "; Add-Content $outputFile -Value "$b64_encoded_cert" }
		#$decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("$b64_encoded_cert"))
		#if ($outputLog) { Add-Content $outputFile -Value "Decoded certificate is: "; Add-Content $outputFile -Value "$decoded" }

	# Send an API call to grab the certificate by its cert id
	$uri = "$($apiURL)/Certificates/Download"
	$body = @{"CertId" = $certId } | ConvertTo-Json -Compress 
	$headers.Add('X-CertificateFormat', 'PEM')
	if ($outputLog) { Add-Content -Path $outputFile -Value "Preparing a POST from $uri with body $body" }
	$response = Invoke-RestMethod -Uri $uri -Method POST -Body $body -Headers $headers -UseDefaultCredentials
	if ($outputLog) { Add-Content -Path $outputFile -Value "Got back $($response)" }

	# The response should contain the base 64 PEM
	# We are after the payload
	$b64_encoded_string = $response[0].Content
	$unencoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("$b64_encoded_string"))


	} else {
		if ($outputLog) { Add-Content -Path $outputFile -Value "not iot id cert, exiting" }
		exit
	}

	if ($testOnly) {
		if ($outputLog) { Add-Content -Path $outputFile -Value "skipping post to GCP IoT Core" }
	} else {
		if ($outputLog) { Add-Content -Path $outputFile -Value "posting to GCP IoT core" }
		#activate GCP service account  -> service account json credential
		gcloud-ps auth activate-service-account --key-file="$jsonKeyPath"
		$token = gcloud-ps auth print-access-token | Out-String
		#these tokens are valid for ~1hr by default.  do we want to save it and re-use for multiple calls?
		if ($outputLog) { Add-Content -Path $outputFile -Value "gcp access token: $token" }

		$gURL = "https://cloudiot.googleapis.com/v1/projects/$gProjectId/locations/$gProjectLocation/registries/$gProjectRegistry/devices"
		$pubKeyObj = @{"format" = "RSA_X509_PEM"; "key" = $unencoded }
		$credObj = @{"expirationTime" = $expiryDate; "publicKey" = $pubKeyObj } 
		$gBodyObj = @{"id" = $clientMachine; "credentials" = $credObj; "blocked" = $false } 
		$gBodyJsonTmp = ConvertTo-Json $gBodyObj -Compress
		$gBodyJson = $gBodyJsonTmp
		$h2 = @{}
		$h2.Add('Content-Type', 'application/json')
		$h2.Add('Authorization', "Bearer $token")
		if ($outputLog) { Add-Content -Path $outputFile -Value "posting to GCP IoT core at $gURL with Body of $($gBodyJson); headers: $h2" }
		$gresponse = Invoke-RestMethod -Uri $gURL -Method POST -Headers $h2 -ContentType 'application/json' -Body $gBodyJson
		if ($outputLog) { Add-Content -Path $outputFile -Value "response from google: $gresponse" }
	}
}
catch {
	if ($outputLog) { Add-Content -Path $outputFile -Value "exception caught during operation: $_.Exception.Message" }
	if ($outputLog) { Add-Content -Path $outputFile -Value $_ }
}
if ($outputLog) { Add-Content -Path $outputFile -Value "Exiting script: $(Get-Date -format G)"; Add-Content -Path $outputFile "===================" }
