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
    $logPath = "C:\scripts\IoTHub\RemoveDevice"
    $logFormat = "RemoveDevice_*txt"
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

if ($outputLog) { $outputFile = ("C:\scripts\IoTHub\RemoveDevice\RemoveDevice_" + (get-date -UFormat "%Y%m%d") + ".txt") } #one log file per day
if ($outputLog) { Add-Content -Path $outputFile -Value "--------------Starting Trace: $(Get-Date -format G)---------------" }
#------------------------------
#arguments for az IoTHub parameters:  not sure where to stick these:
#needed for authenticating service principal
$azureTP = 'insert service principal auth cert thumbrpint'
$ApplicationId = 'fill in with azure application id'
$TenantId = 'fill in with azure tenant id'
#parameters required by Azure to list devices on the hub
$azResourceGroupName = "fill in with azure resource group name"
$azIotHubName = "fill in with azure iot hub name"

#get all certificates from the platform with "Enabled" metadata not null AND certState "2" - revoked
$headers = @{} 
$headers.add('Content-Type', 'application/json')
$apiUrl = "https://control.thedemodrive.com/KeyfactorApi"
$uri = "$($apiUrl)/Certificates/?queryString=CertState%20-eq%20%222%22%20AND%20Enabled%20-ne%20NULL&includeRevoked=true&includeExpired=true"

$expiredCerts = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -UseDefaultCredentials
if ($expiredCerts.Count -eq 0) {
    if ($outputLog) { Add-Content -Path $outputFile -Value "no expired or revoked certs with Enabled metadata, exiting" }
    exit
}
if ($outputLog) { Add-Content -Path $outputFile -Value "expired/revoked certs with enabled metadata from keyfactor platform: $($expiredCerts.Count)" }
$devices = New-Object -TypeName "System.Collections.ArrayList"
foreach ($cert IN $expiredCerts) {
    $deviceCN = $cert.IssuedCN
    if ($deviceCN -match "control.keyfactor.com") {
        if ($outputLog) { Add-Content -Path $outputFile -Value "$deviceCN is a match, will be disabled" }
        $devices.Add($deviceCN)
    }
}
if ($outputLog) { Add-Content -Path $outputFile -Value "expired/revoked certs with enabled metadata on control.keyfactor.com: $($devices.Count)" }

$azAuthStatus = Connect-AzAccount -CertificateThumbprint $azureTP -ApplicationId $ApplicationId -Tenant $TenantId -ServicePrincipal
if ($outputLog) { Add-Content -Path $outputFile -Value "Az Auth result: $azAuthStatus" } #for debugging, TODO remove this 
$iotHubDevices = Get-AzIotHubDevice -ResourceGroupName $azResourceGroupName -IotHubName $azIotHubName #this returns a list of devices, to specify one, add -DeviceId
foreach ($device IN $iotHubDevices) {
    $azStatus = $device.Status
    $azName = $device.Id
    if ($outputLog) { Add-Content -Path $outputFile -Value "Currently on iotHub: $azName is Status: $azStatus" }
    if ($devices.Contains($azName)) {
        if ($devices[$azName] -eq "Enabled") {
            #if device is enabled, disable it.  A
            #TODO in the future might delete the device, commandlet is: Remove-AzIotHubDevice -ResourceGroupName <s> -IotHubName <s> -DeviceId <s>
            $azResult = Set-AzIotHubDevice -ResourceGroupName $ResourceGroup -IotHubName $HubName -DeviceId $azName -Status "Disabled" -StatusReason "Certificate revoked or expired"
            if ($outputLog) { Add-Content -Path $outputFile -Value "Disabled IoTHubDevice with DeviceID of: $($certCN): $azResult" }
        }
    }
}
