# Copyright 2021 Keyfactor
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions
# and limitations under the License.

Import-Module Az
$ScriptDir = Split-Path -parent $MyInvocation.MyCommand.Path
Import-Module $ScriptDir\..\powershellModules\kf_logging.psm1

# Check and process the context parameters
# The PowerShell alert handler injects the following into our runspace: [hashtable]$context
# We expect that a "Thumbprint" value will be passed in which was mapped from {thumbprint}
# If a "OutputLog" value is passed that starts with "Y" we will output to a log file
try {
    [bool]$outputLog = $false
    if ($context["OutputLog"] -like "Y*" ) { $outputLog = $true }
    # Generate a log file for tracing if OutputLog is true
    $logFile = Initialize-KFLogs $outputLog "C:\CMS\scripts\azure\" "azEnroll" 5 #keep no more than 5 logs at a time
    Add-KFInfoLog $outputLog $logFile "Starting Trace: $(Get-Date -format G)"

    $certThumbprint = $context["thumbprint"]
    if ([string]::IsNullOrWhiteSpace($certThumbprint)) { throw "Context variable 'thumbprint' required" }
    Add-KFInfoLog $outputLog $logFile "Context variable 'thumbprint' = $certThumbprint"

    $certCN = $context["CN"]
    if ([string]::IsNullOrWhiteSpace($certCN)) { throw "Context variable 'CN' required" }
    Add-KFInfoLog $outputLog $logFile "Context variable 'CN' = $certCN"
    $certDN = $context["DN"]
    if ([string]::IsNullOrWhiteSpace($certDN)) { throw "Context variable 'DN' required" }
    Add-KFInfoLog $outputLog $logFile "Context variable 'DN' = $certDN"

    if ($certDN -notmatch 'iot-id-cert') {
        Add-KFWarningLog $outputLog $logFile "Certificate not an iot id cert, exiting"
        exit
    }

    # These values should be filled in with the appropriate values from azure Cloud
    $HubName = $context["AzHubName"]
    if ([string]::IsNullOrWhiteSpace($HubName)) { throw "Context variable 'AzHubName' required" }
    Add-KFInfoLog $outputLog $logFile "Az IoT Hub Name: $HubName"
    $ResourceGroup = $context["AzResourceGroupName"]
    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) { throw "Context variable 'AzResourceGroupName' required" }
    Add-KFInfoLog $outputLog $logFile "Az Resource Group Name: $HubName"
    $ApplicationId = $context["AzAppId"]
    if ([string]::IsNullOrWhiteSpace($ApplicationId)) { throw "Context variable 'AzAppId' required" }
    Add-KFInfoLog $outputLog $logFile "Az IoT Hub Application Id: $ApplicationId"
    $SubGuid = $context["AzSubscriptionId"]
    if ([string]::IsNullOrWhiteSpace($SubGuid)) { throw "Context variable 'AzSubscriptionId' required" }
    Add-KFInfoLog $outputLog $logFile "Az Subscription GUID: $SubGuid"
    $TenantId = $context["AzTenantId"]
    if ([string]::IsNullOrWhiteSpace($TenantId)) { throw "Context variable 'AzTenantId' required" }
    Add-KFInfoLog $outputLog $logFile "Az Tenant Id : $TenantId"
    $azureTP = $context["AzServicePrincipalCertTP"]
    if ([string]::IsNullOrWhiteSpace($azureTP)) { throw "Context variable 'AzServicePrincipalCertTP' required" }
    Add-KFInfoLog $outputLog $logFile "Az Service Principal Certificate Thumbprint : $azureTP"

    # By default, expiration handlers send emails. Turn this off
    Add-KFInfoLog $outputLog $logFile "Turning off emailing"
    $context["sendEMail"] = "false"

    if ($skipAz) {
        Add-KFWarningLog $outputLog $logFile "Skipping post to Az IoT Hub as configured TestOnly from context[]"
    }
    else {
        Add-KFInfoLog $outputLog $logFile "adding device to Azure IoT Hub"
        try {
            Connect-AzAccount -CertificateThumbprint $azureTP -ApplicationId $ApplicationId -Tenant $TenantId -ServicePrincipal

            $newDeviceName = $certCN

            #get list of existing iotHub devices
            $iotHubDevices = Get-AzIotHubDevice -ResourceGroupName $ResourceGroup -IotHubName $HubName
            [boolean] $addDevice = $true
            foreach ($device IN $iotHubDevices) {
                if ($device.Id -eq $newDeviceName) {
                    #device is already in iot hub -> update hash
                    $azResult = Set-AzIotHubDevice -ResourceGroupName $ResourceGroup -IotHubName $HubName -DeviceId $newDeviceName  -AuthMethod "x509_thumbprint" -PrimaryThumbprint $certThumbprint
                    Add-KFInfoLog $outputLog $logFile "Updated IoTHubDevice with DeviceID of: $($certCN) to have new Thumbprint: $($certThumbprint): $azResult"
                    $addDevice = $false #don't add it again
                }
            }
            if ($addDevice) {
                #todo add better logging to this, sometimes the log looks like it completed, but it did not.
                $azResult = Add-AzIotHubDevice -ResourceId "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Devices/IotHubs/$HubName" -DeviceId $certCN -AuthMethod "x509_thumbprint" -PrimaryThumbprint $certThumbprint
                Add-KFInfoLog $outputLog $logFile "Created IoTHubDevice with DeviceID of: $($certCN) and Thumbprint: $($certThumbprint)"
            }
        }
        catch {
            Add-KFErrorLog $outputLog $logFile "an error ocurred while creating an IotHub Device with CN of: $($certCN)"
            Add-KFErrorLog $outputLog $logFile "error: $_ "
        }
    }
}
catch {
    Add-KFErrorLog $outputLog $logFile "exception caught during operation: $_.Exception.Message"
    Add-KFErrorLog $ouputLog $logFile "error: $_ "
}

Add-KFWarningLog $outputLog $logFile "Exiting script: $(Get-Date -format G) `r`n =========================================="
