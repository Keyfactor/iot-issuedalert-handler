# Copyright 2021 Keyfactor
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions
# and limitations under the License.

Import-Module Az

#This script is intended to be run by the timer service at a prespecified interval upon machine start up.  e.g every 15m after the machine starts.


[bool]$outputLog = $true #disable to remove logging
#check log files to see how many we have, if more than 3 save only the 3 latest
try {
    $logsToKeep = 3;
    $logPath = "C:\scripts\IoTHub\CheckMetadataAndUpdateIotHub"
    $logFormat = "metadataIotHub*txt"
    $existingLogs = [System.IO.Directory]::GetFiles("$logPath", "$logFormat") | Sort-Object -Desc #newest is first
    if ($existingLogs.Count -gt $logsToKeep) {
        #keeping the latest log files.  
        for ($i = $logsToKeep; $i -lt $existingLogs.Count; $i++) {
            if ($outputLog) { Add-Content -Path $outputFile -Value "Deleting expired log file: $existingLogs[$i]" }
            [System.IO.File]::Delete($existingLogs[$i])
        }
    }
}
catch {
    if ($outputLog) { Add-Content -Path $outputFile -Value "Execption while clearing old logs: $_" }
}


if ($outputLog) { $outputFile = ("C:\scripts\IoTHub\CheckMetadataAndUpdateIotHub\metadataIotHub_" + (get-date -UFormat "%Y%m%d") + ".txt") } #one log file per day

if ($outputLog) { Add-Content -Path $outputFile -Value "----------Starting Trace: $(Get-Date -format G)----------" }
#------------------------------
#arguments for az IoTHub parameters:  not sure where to stick these:
#needed for authenticating service principal
$azureTP = 'fill in with the thumbprint for the azure service principal certificate'
$ApplicationId = 'fill in with the azure application id'
$TenantId = 'fill in with the azure tenant id'
#parameters required by Azure to list devices on the hub
$azResourceGroupName = "fill in with the azure resource group name"
$azIotHubName = "fill in with the azure iot hub name"

#get all certificates from the platform with "Enabled" metadata not null
$headers = @{} 
$headers.add('Content-Type', 'application/json')
$apiUrl = "https://control.thedemodrive.com/KeyfactorApi"
#need verbosity 3 for the metadata object to be included
$uri = "$($apiUrl)/Certificates/?queryString=Enabled%20-ne%20NULL&verbose=3"
#todo is there a different way we can do this?  just get meta data + join CN? using verbose3 seems like a lot of data we wont use

$certs = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -UseDefaultCredentials

if ($outputLog) { Add-Content -Path $outputFile -Value "number of certs with 'Enabled' metadata: $($certs.Length) " }
$sorted = $certs.GetEnumerator() | Sort-Object -Property Id -Descending
#by desc sorting on Id, we use the newest certs per CN only, powershell hashtable doesnt overwrite values

$kfDevices = @{} # hashtable : key: device name (CN); value: enabled/disabled
ForEach ($cert in $sorted) {
    if ($kfDevices.Contains($cert.IssuedCN)) {
        #dupe, skip 
        if ($outputLog) { Add-Content -Path $outputFile -Value "duplicate of CN: $($cert.IssuedCN); id of cert: $($cert.Id) " }
        continue
    }

    if ($cert.Metadata.Enabled -eq "True") {
        $certStatus = "Enabled"
    }
    else {
        $certStatus = "Disabled"
    }
    if ($outputLog) { Add-Content -Path $outputFile -Value "enabled status of cert: $($cert.Metadata.Enabled) aka $certStatus CN: $($cert.IssuedCN) cert ID: $($cert.Id)" }
    $kfDevices.add($cert.IssuedCN, $certStatus)
}
if ($outputLog) { Add-Content -Path $outputFile -Value "devices + enabled status from keyfactor platform: $kfDevices" }
try {
    #authenticate with service principal
    Connect-AzAccount -CertificateThumbprint $azureTP -ApplicationId $ApplicationId -Tenant $TenantId -ServicePrincipal

    $iotHubDevices = Get-AzIotHubDevice -ResourceGroupName $azResourceGroupName -IotHubName $azIotHubName #this returns a list of devices, to specify one, add -DeviceId
    #if ($outputLog) { Add-Content -Path $outputFile -Value "Devices:  $iotHubDevices"} #for debugging, TODO remove this 
    if ($iotHubDevices.Count -eq 0) {
        if ($outputLog) { Add-Content -Path $outputFile -Value "0 devices found on iotHub: $iotHubName in resource group: $azResourceGroupName, exiting" }
        exit
    } 
    #Iterate over list of IoTHub devices and update status of those that are different via the platform.
    foreach ($device IN $iotHubDevices) {
        $azStatus = $device.Status
        $azName = $device.Id
        if ($outputLog) { Add-Content -Path $outputFile -Value "Currently on iotHub: $azName is Status: $azStatus" }
        if ($kfDevices.Contains($azName)) {
            #if ($outputLog) { Add-Content -Path $outputFile -Value "$azName found with metadata" }
            if ($kfDevices[$azName] -eq $azStatus) {
                #it's as expected do nothing
                if ($outputLog) { Add-Content -Path $outputFile -Value "$azName is already set to $azStatus" }
            }
            else {
                #update device status on az iot hub
                $res = Set-AzIotHubDevice -ResourceGroupName $azResourceGroupName -IotHubName $azIotHubName -DeviceId $azName -Status $kfDevices[$azName] -StatusReason "Certificate Metadata updated"
                if ($outputLog) { Add-Content -Path $outputFile -Value "Set $azName to Status: $azStrStatus on IoTHub: $res" }
            }
        }
    }
}
catch {
    if ($outputLog) { 
        Add-Content -Path $outputFile -Value "an exception was caught during Azure operations" 
        Add-Content -Path $outputFile "error $_ " 
    }
}
