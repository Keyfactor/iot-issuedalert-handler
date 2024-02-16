 # Copyright 2023 Keyfactor
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions
# and limitations under the License.

Import-Module Az
az config set extension.use_dynamic_install=yes_without_prompt
az extension add --name azure-iot
. $PSScriptRoot\keyfactorPSUtilities.ps1

# Check and process the context parameters
# The PowerShell alert handler injects the following into our runspace: [hashtable]$context
# We expect that a "Thumbprint" value will be passed in which was mapped from {thumbprint}
# If a "OutputLog" value is passed that starts with "Y" we will output to a log file
[bool]$outputLog = $true
#if ($context["OutputLog"] -like "Y*" ) { $outputLog = $true }
# Generate a log file for tracing if OutputLog is true
$logFile = Initialize-KFLogs $outputLog "C:\keyfactor\logs\external" "azEnroll" 5 #keep no more than 5 logs at a time
Add-KFInfoLog $outputLog $logFile "Starting Trace: $(Get-Date -format G)"

try {
    #input processing
    $certThumbprint = $context["thumbprint"]
    if ([string]::IsNullOrWhiteSpace($certThumbprint)) { throw "Context variable 'thumbprint' required" }
    Add-KFInfoLog $outputLog $logFile "Context variable 'thumbprint' = $certThumbprint"

    $certCN = $context["CN"]
    if ([string]::IsNullOrWhiteSpace($certCN)) { throw "Context variable 'CN' required" }
    Add-KFInfoLog $outputLog $logFile "Context variable 'CN' = $certCN"
    $certDN = $context["DN"] #TODO probably dont need both CN and DN anymore
    #if ([string]::IsNullOrWhiteSpace($certDN)) { throw "Context variable 'DN' required" }
    #Add-KFInfoLog $outputLog $logFile "Context variable 'DN' = $certDN"
    if ($certDN -Match 'iot-id-cert') {
        Add-KFInfoLog $outputLog $logFile "Context variable 'DN' = $certDN matches iot-id-cert, adding to IotHub"
    } else {
        Add-KFInfoLog $outputLog $logFile "Context variable 'DN' = $certDN does not contain iot-id-cert, exiting"
        exit
    }

    $clientMachine = $certCN
    #if ([string]::IsNullOrWhiteSpace($clientMachine)) { throw "Context variable 'clientMachine' required" }
    Add-KFInfoLog $outputLog $logFile "client machine name: $clientMachine"

    # These values should be filled in with the appropriate values from azure Cloud
    $HubName = $context["AzHubName"]
    if ([string]::IsNullOrWhiteSpace($HubName)) { throw "Context variable 'AzHubName' required" }
    Add-KFInfoLog $outputLog $logFile "Az IoT Hub Name: $HubName"
    $ResourceGroup = $context["azResourceGroupName"]
    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) { throw "Context variable 'AzResourceGroupName' required" }
    Add-KFInfoLog $outputLog $logFile "Az Resource Group Name: $ResourceGroup"
    $ApplicationId = $context["azApplicationId"]
    if ([string]::IsNullOrWhiteSpace($ApplicationId)) { throw "Context variable 'AzApplicationId' required" }
    Add-KFInfoLog $outputLog $logFile "Az IoT Hub Application Id: $ApplicationId"
    $SubGuid = $context["azSubscriptionId"]
    if ([string]::IsNullOrWhiteSpace($SubGuid)) { throw "Context variable 'AzSubscriptionId' required" }
    Add-KFInfoLog $outputLog $logFile "Az Subscription GUID: $SubGuid"
    $TenantId = $context["azTenantId"]
    if ([string]::IsNullOrWhiteSpace($TenantId)) { throw "Context variable 'AzTenantId' required" }
    Add-KFInfoLog $outputLog $logFile "Az Tenant Id : $TenantId"
    #testdrive optimzation, fill in with FILENAME
    $azureCertPath = "AZCERTFILENAME"
    #if ([string]::IsNullOrWhiteSpace($azureCertPath)) { throw "Context variable 'azCertPath' required" }
    #Add-KFInfoLog $outputLog $logFile "Az Service Principal Certificate path : $azureCertPath"

    # By default, expiration handlers send emails. Turn this off
    Add-KFInfoLog $outputLog $logFile "Turning off emailing"
    $context["sendEMail"] = "false"
}
catch {
    Add-KFErrorLog $outputLog $logFile "exception caught during input parsing: $_.Exception.Message" $session
    #$mutex.ReleaseMutex()
}

Add-KFInfoLog $outputLog $logFile "adding device to Azure IoT Hub" $session
[boolean] $addDevice = $true

try {
    Add-KFInfoLog $outputLog $logFile "calling az cli: az login --service-principal -u $($ApplicationId) -p $($azureCertPath) --tenant $($TenantId) 2>&1"
    $connRes = az login --service-principal -u $($ApplicationId) -p "$($azureCertPath)" --tenant $($TenantId) 2>&1

    Add-KFInfoLog $outputLog $logFile "connection response from azure: $connRes"

    $newDeviceName = $clientMachine

    # az cli returns an array of strings instead of a powershell object, parse as necessary

    Add-KFInfoLog $outputLog $logFile "calling: az iot hub device-identity show --device-id $($newDeviceName) --hub-name $($HubName) --resource-group $($ResourceGroup) 2>&1"
    $listJob = Start-Job -ScriptBlock {
            (az iot hub device-identity show `
            --device-id $($args[0]) `
            --hub-name $($args[1]) `
            --resource-group $($args[2])) 2>&1
    } -ArgumentList "$newDeviceName", "$HubName", "$ResourceGroup"
    Wait-Job $listJob

    if ($listJob.State -like "Completed") {
        $listRes = Receive-Job $listJob
        Add-KFInfoLog $outputLog $logFile "az iot hub device-identity show response from azure: $listRes"
        if ($listRes -notcontains "DeviceNotFound") {
            $devId = $listRes | Where-Object { $_ -match 'deviceId' } # loops over every line looking for 'deviceId'
            Add-KFInfoLog $outputLog $logFile "az iot hub device-identity show response looped : $devId"
            if (![string]::IsNullOrWhiteSpace($devId)) {
                Add-KFInfoLog $outputLog $logFile "$($newDeviceName) already exists in iot hub, updating thumbprint"
                Add-KFInfoLog $outputLog $logFile "calling: az iot hub device-identity update --device-id $($newDeviceName) -n $($HubName) --resource-group $($ResourceGroup) --primary-thumbprint $($certThumbprint) 2>&1"
                $azUpdateResult = az iot hub device-identity update --device-id $($newDeviceName) -n $($HubName) --resource-group $($ResourceGroup) --primary-thumbprint $($certThumbprint) --secondary-thumbprint $($certThumbprint) 2>&1
                Add-KFInfoLog $outputLog $logFile "Updated IoTHubDevice with DeviceID of: $($certCN) to have new Thumbprint: $($certThumbprint): $azUpdateResult"
                $addDevice = $false;
            }
        }
    }
    else {
        Add-KFInfoLog $outputLog $logFile "az iot hub device-identity show timed out " $session
        Remove-Job $listJob
    }
} catch {
    Add-KFErrorLog $outputLog $logFile "an error ocurred while listing existing IotHub Device with CN of: $($certCN)"
    Add-KFErrorLog $outputLog $logFile "error: $_ "
}

try {
    if ($addDevice) {
        Add-KFInfoLog $outputLog $logFile "Adding IoTHubDevice with DeviceID of: $($certCN) and Thumbprint: $($certThumbprint)" $session # adds both primary and secondary thumbprint as the same if not already set

        #[boolean] $enableEdge = $false #change this boolean to set edge enabled
        #TESTDRIVE version: no edge enabling
        #if ($enableEdge) {
            #this is for edge enabled
            #Add-KFInfoLog $outputLog $logFile "calling: az iot hub device-identity create --device-id $($newDeviceName) -n $($HubName) --resource-group $($ResourceGroup) --auth-method "x509_thumbprint" --primary-thumbprint $($certThumbprint) --secondary-thumbprint $($certThumbprint) --edge-enabled="true" 2>&1"
            #$azAddResult = az iot hub device-identity create --device-id $($newDeviceName) -n $($HubName) --resource-group $($ResourceGroup) --auth-method "x509_thumbprint" --primary-thumbprint $($certThumbprint) --secondary-thumbprint $($certThumbprint) --edge-enabled="true" 2>&1
        #}
        #else {
            Add-KFInfoLog $outputLog $logFile "calling: az iot hub device-identity create --device-id $($newDeviceName) -n $($HubName) --resource-group $($ResourceGroup) --auth-method "x509_thumbprint" --primary-thumbprint $($certThumbprint) --secondary-thumbprint $($certThumbprint) 2>&1"
            $azAddResult = az iot hub device-identity create --device-id $($newDeviceName) -n $($HubName) --resource-group $($ResourceGroup) --auth-method "x509_thumbprint" --primary-thumbprint $($certThumbprint) --secondary-thumbprint $($certThumbprint) 2>&1
        #}
        Add-KFInfoLog $outputLog $logFile "response from azure: $azAddResult"
    }
}
catch {
    Add-KFErrorLog $outputLog $logFile "an error ocurred while creating an IotHub Device with CN of: $($certCN)"
    Add-KFErrorLog $outputLog $logFile "error: $_ "
    #$mutex.ReleaseMutex()
}

Add-KFWarningLog $outputLog $logFile "Exiting script: $(Get-Date -format G) `r`n =========================================="
#$mutex.ReleaseMutex()

