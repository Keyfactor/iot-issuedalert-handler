# Copyright 2023 Keyfactor
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions
# and limitations under the License.

. $PSScriptRoot\keyfactorPSUtilities.ps1

# keyfactorReenrollment.ps1 - this script is intended to be run from the keyfactor expiration alert workflow.
# Begin the script, gets cert, reenrolls the store
#
[boolean]$outputLog = $true
$logFile = Initialize-KFLogs $outputLog "C:\Keyfactor\logs" "keyfactorReenrollment" 5 #keep no more than 5 log files
Add-KFInfoLog $outputLog $logFile "Starting Trace: $(Get-Date -format G)"
try {

    $apiURL = $context["ApiUrl"]
    Add-KFInfoLog $outputLog $logFile "Context variable 'ApiUrl' = $apiURL"
    if ([string]::IsNullOrWhiteSpace($apiURL)) { throw "Context variable 'ApiUrl' required" }
    $TP = $context["TP"]
    Add-KFInfoLog $outputLog $logFile "Context variable 'TP' = $TP"
    if ([string]::IsNullOrWhiteSpace($apiURL)) { throw "Context variable 'TP' required" }
}
catch {
    Add-KFErrorLog $outputLog $logFile "exception caught during input processing : $_.Exception.Message"
    Add-KFErrorLog $outputLog $logFile $_
}

try {
    #get the cert, need the ID for location
    Add-KFTraceLog $outputLog $logFile "getting the cert"
    $headers = @{}
    $headers.Add('Content-Type', 'application/json')
    $headers.Add('x-keyfactor-requested-with', 'APIClient')
    $headers.Add('x-keyfactor-api-version', '1')
    $headers.Add('Authorization', 'Basic KFAUTHHEADER')
    $uri = "$($apiURL)/Certificates?collectionId=0&pq.queryString=thumbprint%20-eq%20%22$TP%22&IncludeMetadata=true"
    Add-KFInfoLog $outputLog $logFile "Preparing a GET from $uri"
    $targetCert = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -UseDefaultCredentials
    Add-KFInfoLog $outputLog $logFile "Got back $($targetCert.Count) responses data = $($targetCert)"
    Add-KFInfoLog $outputLog $logFile "--DN $($targetCert[0].IssuedDN) "
    if (1 -ne $targetCert.Count) { throw "Error, got back more than one certificate with Thumbprint: $TP" }
}
catch {
    Add-KFErrorLog $outputLog $logFile "exception caught while getting cert: $_.Exception.Message"
    Add-KFErrorLog $outputLog $logFile $_
}

#do reenrollment stuff here. need cert store location, alias + agent id
Add-KFInfoLog $outputLog $logFile "scheduling the certificate store for reenrollment"
try {
    $certId = $targetCert[0].Id
    $uri = "$($apiURL)/Certificates/Locations/$($certId)"
    Add-KFInfoLog $outputLog $logFile "Preparing a GET to $uri  "
    $certLocation = Invoke-RestMethod -Uri $uri -Method GET -UseDefaultCredentials -Headers $headers
    Add-KFInfoLog $outputLog $logFile "Finished the GET for the Keyfactor Location: $($certLocation[0].Details.Locations)"
    Add-KFInfoLog $outputLog $logFile "Storeid: $($certLocation[0].Details.Locations.StoreId)"
    Add-KFInfoLog $outputLog $logFile "alias: $($certLocation[0].Details.Locations.Alias)"
    Add-KFInfoLog $outputLog $logFile "clientmachine: $($certLocation[0].Details.Locations.ClientMachine)"

    $storeId = $($certLocation[0].Details.Locations.StoreId)
    $alias = $($certLocation[0].Details.Locations.Alias)
    $clientMachine = $($certLocation[0].Details.Locations.ClientMachine)

    $uri = "$($apiURL)/Agents/?queryString=ClientMachine%20-eq%20%22$($clientMachine)%22&="
    $AgentInfo = Invoke-RestMethod -Uri $uri -Method GET -UseDefaultCredentials -Headers $headers
    if ($AgentInfo[0].Status -notlike "2") {
        #status enum: #New=1,Approved=2,Disapproved=3,NotInDatabase=4
        Add-KFWarningLog $outputLog $logFile "Agent Status: $($AgentInfo[0].Status); Exiting script: $(Get-Date -format G) `r`n ========================================="
        exit
    }
    $agentId = $AgentInfo[0].AgentId
    $certSubject = $targetCert[0].IssuedDN

    Add-KFInfoLog $outputLog $logFile "store id:$storeId"
    Add-KFInfoLog $outputLog $logFile "alias:$alias"
    Add-KFInfoLog $outputLog $logFile "agent id:$agentId"
    Add-KFInfoLog $outputLog $logFile "cert subject:$certSubject"

    if ([string]::IsNullOrWhiteSpace($storeId) -or
    [string]::IsNullOrWhiteSpace($alias) -or
    [string]::IsNullOrWhiteSpace($agentId) -or
    [string]::IsNullOrWhiteSpace($certSubject)) {
        Add-KFErrorLog $outputLog $logFile "Missing required parameter for reenrollment job creation, exiting script: $(Get-Date -format G) `r`n ========================================="
        exit
    }

    Add-KFTraceLog $outputLog $logFile "Preparing to reenroll cert in store: = $($storeId)"
    $uri = "$($apiURL)/CertificateStores/Reenrollment"
    $rerollObj = @{
        KeystoreId    = $storeId
        SubjectName   = $certSubject
        AgentGuid     = $agentId
        Alias         = $alias
        JobProperties = @{}
    }
    [string]$rerollJson = $rerollObj | ConvertTo-Json -Compress
    Add-KFInfoLog $outputLog $logFile "Preparing a POST to $uri with Body = $rerollJson"
    $rerollResponse = Invoke-RestMethod -Uri $uri -Method POST -Body $rerollJson -UseDefaultCredentials -Headers $headers
    Add-KFInfoLog $outputLog $logFile "finished POST to platform = $rerollResponse" #should be a 204 which doesnt really look like anything
}
catch {
    Add-KFErrorLog $outputLog $logFile "exception caught during reenrollment operation: $_.Exception.Message"
    Add-KFErrorLog $outputLog $logFile $_
}

Add-KFInfoLog $outputLog $logFile "Exiting script: $(Get-Date -format G) `r`n ========================================="
