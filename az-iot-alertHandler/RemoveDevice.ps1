# Copyright 2021 Keyfactor
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions
# and limitations under the License.

Import-Module Az

# Check and process the context parameters
# The PowerShell alert handler injects the following into our runspace: [hashtable]$context
# If a "OutputLog" value is passed that starts with "Y" we will output to a log file
try {
    [bool]$outputLog = $false
    if ($context["OutputLog"] -like "Y*" ) { $outputLog = $true } 
    # Generate a log file for tracing if OutputLog is true
    if ($outputLog) { $outputFile = ("C:\scripts\IoTHub\RemoveDevice\AzDisableDevice" + (get-date -UFormat "%Y%m%d") + ".txt") } #one log file per day
    if ($outputLog) { Add-Content -Path $outputFile -Value "Starting Trace: $(Get-Date -format G)" }

    $certCN = $context["CN"]
    if ([string]::IsNullOrWhiteSpace($certCN)) { throw "Context variable 'CN' required" }
    if ($outputLog) { Add-Content -Path $outputFile -Value "Context variable 'CN' = $certCN" }

    # These values should be filled in with the appropriate values from azure Cloud
    $HubName = $context["AzHubName"]
    if ([string]::IsNullOrWhiteSpace($HubName)) { throw "Context variable 'AzHubName' required" }

    $ApplicationId = $context["AzAppId"]
    if ([string]::IsNullOrWhiteSpace($ApplicationId)) { throw "Context variable 'AzAppId' required" }

    $SubscriptionId = $context["AzSubscriptionId"]
    if ([string]::IsNullOrWhiteSpace($SubscriptionId)) { throw "Context variable 'AzSubscriptionId' required" }

    $TenantId = $context["AzTenantId"]
    if ([string]::IsNullOrWhiteSpace($TenantId)) { throw "Context variable 'AzTenantId' required" }

    $ResourceGroup = $context["AzResourceGroupName"]
    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) { throw "Context variable 'AzResourceGroupName' required" }

    $azureTP = $context["AzServicePrincipalCertTP"]
    if ([string]::IsNullOrWhiteSpace($azureTP)) { throw "Context variable 'AzServicePrincipalCertTP' required" } 
    if ($outputLog) { 
        Add-Content -Path $outputFile -Value "Az IoT Hub Name: $HubName" 
        Add-Content -Path $outputFile -Value "Az IoT Hub Application Id: $ApplicationId" 
        Add-Content -Path $outputFile -Value "Az Subscription Id: $SubscriptionId" 
        Add-Content -Path $outputFile -Value "Az Resource Group Name : $ResourceGroup"
        Add-Content -Path $outputFile -Value "Az Tenant Id : $TenantId" 
        Add-Content -Path $outputFile -Value "Az Service Principal Certificate Thumbprint : $azureTP" 
    }

    # By default, expiration handlers send emails. Turn this off
    if ($outputLog) { Add-Content -Path $outputFile -Value "Turning off emailing" }
    $context["sendEMail"] = "false"

    if ($skipAz) {
        if ($outputLog) { Add-Content -Path $outputFile -Value "skipping action on Az IoT Hub as configured TestOnly from context[]" }
    }
    else {
        if ($outputLog) { Add-Content -Path $outputFile -Value "disabling device $certCN on Az IoT Hub" }
        try {
            Connect-AzAccount -CertificateThumbprint $azureTP -ApplicationId $ApplicationId -Tenant $TenantId -ServicePrincipal
            #todo add better logging to this, sometimes the log looks like it completed, but it did not. 
            $azResult = Set-AzIotHubDevice -ResourceGroupName $ResourceGroup -IotHubName $HubName -DeviceId $certCN -Status "Disabled" -StatusReason "Certificate revoked or expired"
            if ($outputLog) { Add-Content -Path $outputFile -Value "Disabled IoTHubDevice with DeviceID of: $($certCN): $azResult" }
        }
        catch {
            if ($outputLog) { 
                Add-Content -Path $outputFile -Value "an error ocurred while disabling an IotHub Device with CN of: $($certCN)" 
                Add-Content -Path $outputFile "error $_ " 
            } 
        }
    }
}
catch {
    if ($outputLog) { Add-Content -Path $outputFile -Value "exception caught during operation: $_.Exception.Message" }
    if ($outputLog) { Add-Content -Path $outputFile -Value $_ }
}
if ($outputLog) { Add-Content -Path $outputFile -Value "Exiting script: $(Get-Date -format G)"; Add-Content -Path $outputFile "===================" }
