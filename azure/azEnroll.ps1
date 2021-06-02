# Copyright 2021 Keyfactor
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions
# and limitations under the License.

Import-Module Az
Import-Module ../powershellModules/kf_logging

# Check and process the context parameters
# The PowerShell alert handler injects the following into our runspace: [hashtable]$context
# We expect that a "Thumbprint" value will be passed in which was mapped from {thumbprint}
# If a "OutputLog" value is passed that starts with "Y" we will output to a log file
try {
    [bool]$outputLog = $false
    if ($context["OutputLog"] -like "Y*" ) { $outputLog = $true } 
    # Generate a log file for tracing if OutputLog is true
    $logFile = Initialize-KFLogs $outputLog "azEnroll" 5 #keep no more than 5 logs at a time
    Add-InfoLog $outputLog $logFile "Starting Trace: $(Get-Date -format G)" 

    $certTP = $context["thumbprint"]
    if ([string]::IsNullOrWhiteSpace($certTP)) { throw "Context variable 'thumbprint' required" }
    Add-InfoLog $outputLog $logFile "Context variable 'thumbprint' = $certTP" 

    $certCN = $context["CN"]
    if ([string]::IsNullOrWhiteSpace($certTP)) { throw "Context variable 'CN' required" }
    Add-InfoLog $outputLog $logFile "Context variable 'CN' = $certCN" 

    # These values should be filled in with the appropriate values from azure Cloud
    $HubName = $context["AzHubName"]
    if ([string]::IsNullOrWhiteSpace($HubName)) { throw "Context variable 'AzHubName' required" }
    Add-InfoLog $outputLog $logFile "Az IoT Hub Name: $HubName" 
    $ApplicationId = $context["AzAppId"]
    if ([string]::IsNullOrWhiteSpace($ApplicationId)) { throw "Context variable 'AzAppId' required" }
    Add-InfoLog $outputLog $logFile "Az IoT Hub Application Id: $ApplicationId" 
    $SubGuid = $context["AzSubscriptionId"]
    if ([string]::IsNullOrWhiteSpace($SubGuid)) { throw "Context variable 'AzSubscriptionId' required" }
    Add-InfoLog $outputLog $logFile "Az Subscription GUID: $SubGuid" 
    $TenantId = $context["AzTenantId"]
    if ([string]::IsNullOrWhiteSpace($TenantId)) { throw "Context variable 'AzTenantId' required" }
    Add-InfoLog $outputLog $logFile "Az Tenant Id : $TenantId" 
    $azureTP = $context["AzServicePrincipalCertTP"]
    if ([string]::IsNullOrWhiteSpace($azureTP)) { throw "Context variable 'AzServicePrincipalCertTP' required" } 
    Add-InfoLog $outputLog $logFile "Az Service Principal Certificate Thumbprint : $azureTP" 

    # By default, expiration handlers send emails. Turn this off
    Add-InfoLog $outputLog $logFile "Turning off emailing"
    $context["sendEMail"] = "false"

    if ($skipAz) {
        Add-WarningLog $outputLog $logFile "Skipping post to Az IoT Hub as configured TestOnly from context[]" 
    }
    else {
        Add-InfoLog $outputLog $logFile "adding device to Azure IoT Hub" 
        try {
            Connect-AzAccount -CertificateThumbprint $azureTP -ApplicationId $ApplicationId -Tenant $TenantId -ServicePrincipal
            Add-AzIotHubDevice -ResourceId "/subscriptions/$SubGuid/resourceGroups/test_resource/providers/Microsoft.Devices/IotHubs/$HubName" -DeviceId $certCN -AuthMethod "x509_thumbprint" -PrimaryThumbprint $certThumbprint
            Add-InfoLog $outputLog $logFile "Created IoTHubDevice with DeviceID of: $($certCN) and Thumbprint: $($certThumbprint)" 
        }
        catch {
            Add-ErrorLog $outputLog $logFile "an error ocurred while creating an IotHub Device with CN of: $($certCN)" 
            Add-ErrorLog $outputLog $logFile "error: $_ " 
        }
    }
}
catch {
    Add-ErrorLog $outputLog $logFile "exception caught during operation: $_.Exception.Message" 
    Add-ErrorLog $ouputLog $logFile "error: $_ " 
}

Add-WarningLog $outputLog $logFile "Exiting script: $(Get-Date -format G)"; Add-Content -Path $outputFile "===================" 


