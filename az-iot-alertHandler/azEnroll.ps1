# Copyright 2021 Keyfactor
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions
# and limitations under the License.

Import-Module Az

# Check and process the context parameters
# The PowerShell alert handler injects the following into our runspace: [hashtable]$context
# We expect that a "Thumbprint" value will be passed in which was mapped from {thumbprint}
# If a "OutputLog" value is passed that starts with "Y" we will output to a log file
try {
    [bool]$outputLog = $false
    if ($context["OutputLog"] -like "Y*" ) { $outputLog = $true } 
    # Generate a log file for tracing if OutputLog is true
    if ($outputLog) { $outputFile = ("C:\CMS\scripts\azEnroll_" + (get-date -UFormat "%Y%m%d%H%M") + ".txt") }
    if ($outputLog) { Add-Content -Path $outputFile -Value "Starting Trace: $(Get-Date -format G)" }

    $certTP = $context["thumbprint"]
    if ([string]::IsNullOrWhiteSpace($certTP)) { throw "Context variable 'thumbprint' required" }
    if ($outputLog) { Add-Content -Path $outputFile -Value "Context variable 'thumbprint' = $certTP" }

    $certCN = $context["CN"]
    if ([string]::IsNullOrWhiteSpace($certTP)) { throw "Context variable 'CN' required" }
    if ($outputLog) { Add-Content -Path $outputFile -Value "Context variable 'CN' = $certCN" }

    # These values should be filled in with the appropriate values from azure Cloud
    $HubName = $context["AzHubName"]
    if ([string]::IsNullOrWhiteSpace($HubName)) { throw "Context variable 'AzHubName' required" }
    $ApplicationId = $context["AzAppId"]
    if ([string]::IsNullOrWhiteSpace($ApplicationId)) { throw "Context variable 'AzAppId' required" }
    $SubGuid = $context["AzSubscriptionId"]
    if ([string]::IsNullOrWhiteSpace($SubGuid)) { throw "Context variable 'AzSubscriptionId' required" }
    $TenantId = $context["AzTenantId"]
    if ([string]::IsNullOrWhiteSpace($TenantId)) { throw "Context variable 'AzTenantId' required" }
    $azureTP = $context["AzServicePrincipalCertTP"]
    if ([string]::IsNullOrWhiteSpace($azureTP)) { throw "Context variable 'AzServicePrincipalCertTP' required" } 
    if ($outputLog) { 
        Add-Content -Path $outputFile -Value "Az IoT Hub Name: $HubName" 
        Add-Content -Path $outputFile -Value "Az IoT Hub Application Id: $ApplicationId" 
        Add-Content -Path $outputFile -Value "Az Subscription GUID: $SubGuid" 
        Add-Content -Path $outputFile -Value "Az Tenant Id : $TenantId" 
        Add-Content -Path $outputFile -Value "Az Service Principal Certificate Thumbprint : $azureTP" 
    }

    # By default, expiration handlers send emails. Turn this off
    if ($outputLog) { Add-Content -Path $outputFile -Value "Turning off emailing" }
    $context["sendEMail"] = "false"

    if ($skipAz) {
        if ($outputLog) { Add-Content -Path $outputFile -Value "skipping post to Az IoT Hub as configured TestOnly from context[]" }
    }
    else {
        if ($outputLog) { Add-Content -Path $outputFile -Value "posting to Az IoT Hub" }
        try {
            Connect-AzAccount -CertificateThumbprint $azureTP -ApplicationId $ApplicationId -Tenant $TenantId -ServicePrincipal
            Add-AzIotHubDevice -ResourceId "/subscriptions/$SubGuid/resourceGroups/test_resource/providers/Microsoft.Devices/IotHubs/$HubName" -DeviceId $certCN -AuthMethod "x509_thumbprint" -PrimaryThumbprint $certThumbprint
            if ($outputLog) { Add-Content -Path $outputFile -Value "Created IoTHubDevice with DeviceID of: $($certCN) and Thumbprint: $($certThumbprint)" }
        }
        catch {
            if ($outputLog) { 
                Add-Content -Path $outputFile -Value "an error ocurred while creating an IotHub Device with CN of: $($certCN)" 
                dd-Content -Path $outputFile "error $_ " 
            } 
        }
    }
}
catch {
    if ($outputLog) { Add-Content -Path $outputFile -Value "exception caught during operation: $_.Exception.Message" }
    if ($outputLog) { Add-Content -Path $outputFile -Value $_ }
}
if ($outputLog) { Add-Content -Path $outputFile -Value "Exiting script: $(Get-Date -format G)"; Add-Content -Path $outputFile "===================" }


