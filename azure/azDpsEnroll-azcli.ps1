 # Copyright 2023 Keyfactor
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions
# and limitations under the License.

#Import-Module Az
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
$logFile = Initialize-KFLogs $outputLog "C:\keyfactor\logs\" "azDpsEnroll" 5 #keep no more than 5 logs at a time
Add-KFInfoLog $outputLog $logFile "Starting Trace: $(Get-Date -format G)"

try {
    #input processing
    $certThumbprint = $context["thumbprint"]
    if ([string]::IsNullOrWhiteSpace($certThumbprint)) { throw "Context variable 'thumbprint' required" }
    Add-KFInfoLog $outputLog $logFile "Context variable 'thumbprint' = $certThumbprint"

    #$apiURL = $context["ApiUrl"] -> testdrive optimization
    $apiURL = "KFAPIURL"
    Add-KFInfoLog $outputLog $logFile "Context variable 'ApiUrl' = $apiURL "
    if ([string]::IsNullOrWhiteSpace($apiURL)) { throw "Context variable 'ApiUrl' required" }
    $certCN = $context["CN"]
    if ([string]::IsNullOrWhiteSpace($certCN)) { throw "Context variable 'CN' required" }
    Add-KFInfoLog $outputLog $logFile "Context variable 'CN' = $certCN"
    $certDN = $context["DN"] #TODO probably dont need both CN and DN anymore
    if ([string]::IsNullOrWhiteSpace($certDN)) { throw "Context variable 'DN' required" }
    Add-KFInfoLog $outputLog $logFile "Context variable 'DN' = $certDN"
    $clientMachine = $certCN
    #$clientMachine = $context["clientMachine"] #todo just use the CN value?
    #if ([string]::IsNullOrWhiteSpace($clientMachine)) { throw "Context variable 'clientMachine' required" }
    #Add-KFInfoLog $outputLog $logFile "client machine name: $clientMachine"

    # These values should be filled in with the appropriate values from azure Cloud
    $dpsName = $context["AzDpsName"]
    if ([string]::IsNullOrWhiteSpace($dpsName)) { throw "Context variable 'AzDpsName' required" }
    Add-KFInfoLog $outputLog $logFile "Az DPS Name: $dpsName"
    $ResourceGroup = $context["AzResourceGroupName"]
    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) { throw "Context variable 'AzResourceGroupName' required" }
    Add-KFInfoLog $outputLog $logFile "Az Resource Group Name: $ResourceGroup"
    $ApplicationId = $context["AzAppId"]
    if ([string]::IsNullOrWhiteSpace($ApplicationId)) { throw "Context variable 'AzApplicationId' required" }
    Add-KFInfoLog $outputLog $logFile "Az IoT Hub Application Id: $ApplicationId"
    $TenantId = $context["AzTenantId"]
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
    Add-KFErrorLog $outputLog $logFile "exception caught during input parsing: $_.Exception.Message"
}

Add-KFInfoLog $outputLog $logFile "adding Individual Enrollment to Azure DPS"
[boolean] $addEnrollment = $true

try {
    # Send API calls to download the certificate -> save to a temp file in c:\temp this path must exist and be writable by the service
    $uri = "$($apiURL)/Certificates/Download"
    Add-KFInfoLog $outputLog $logFile "Preparing a POST from $uri"
    $body = @{"Thumbprint" = $certThumbprint } | ConvertTo-Json -Compress
    $headers = @{}
    $headers.Add('X-CertificateFormat', 'PEM') 
    $headers.Add('x-keyfactor-requested-with', 'APIClient')
    $headers.Add('x-keyfactor-api-version', '1')
    $headers.Add('Content-Type', 'application/json')
    #testdrive optimization, inject the authheader
    $headers.Add('Authorization', 'Basic KFAUTHHEADER')
    Add-KFInfoLog $outputLog $logFile "Preparing a POST from $uri - BODY: $body"
    $response = Invoke-RestMethod -Uri $uri -Method POST -Body $body -Headers $headers -UseDefaultCredentials
    Add-KFTraceLog $outputLog $logFile "Got back $($response)"

    # The response should contain the base 64 PEM, We are after the payload
    $b64_encoded_string = $response[0].Content
    $unencoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("$b64_encoded_string"))
    Out-File -FilePath "c:\temp\tmp$certCN.pem" -InputObject $unencoded -Encoding ascii 
    #keyfactor has a comment with the CN at the top of the cert, azure doesnt like that 
    (Get-Content "C:\temp\tmp$certCN.pem" | Select-Object -Skip 1) | Set-Content C:\temp\tmp$certCN-clean.pem
    #todo verify download success
    $downloadedCert = "c:\temp\tmp$certCN-clean.pem"
}
catch {
    Add-KFErrorLog $outputLog $logFile "exception caught during cert download operation: $_.Exception.Message"
    Add-KFErrorLog $outputLog $logFile $_
}

try {
    Add-KFInfoLog $outputLog $logFile "calling az cli: az login --service-principal -u $($ApplicationId) -p $($azureCertPath) --tenant $($TenantId) 2>&1"
    $connRes = az login --service-principal -u $($ApplicationId) -p "$($azureCertPath)" --tenant $($TenantId) 2>&1

    Add-KFInfoLog $outputLog $logFile "connection response from azure: $connRes"

    $newDeviceName = $clientMachine

    # az cli returns an array of strings instead of a powershell object, parse as necessary

    Add-KFInfoLog $outputLog $logFile "calling: az iot dps enrollment show --dps-name $($dpsName) --resource-group $($ResourceGroup) --enrollment-id $($clientMachine) 2>&1"
    $listJob = Start-Job -ScriptBlock {
            (az iot hub dps enrollment show `
            --dps-name $($args[0]) `
            --resource-group $($args[1]) `
            --enrollment-id $($args[2])) 2>&1
    } -ArgumentList "$dpsName", "$ResourceGroup", "$clientMachine"
    Wait-Job $listJob

    if ($listJob.State -like "Completed") {
        $listRes = Receive-Job $listJob
        Add-KFInfoLog $outputLog $logFile "az iot dps enrollment show response from azure: $listRes"
        if ($listRes -notcontains "Not Found") {
            $devId = $listRes | Where-Object { $_ -match 'deviceId' } # loops over every line looking for 'deviceId'
            Add-KFInfoLog $outputLog $logFile "az iot hub device-identity show response looped : $devId"
            if (![string]::IsNullOrWhiteSpace($devId)) {
                Add-KFInfoLog $outputLog $logFile "$($newDeviceName) already exists in iot hub, updating thumbprint"
                Add-KFInfoLog $outputLog $logFile "calling: az iot dps enrollment update --resource-group $($ResourceGroup) --dps-name $($dpsName) --enrollment-id $($certCN) --certificate-path $($downloadedCert) 2>&1"
                $azUpdateResult = az iot dps enrollment update --resource-group $($ResourceGroup) --dps-name $($dpsName) --enrollment-id $($certCN) --certificate-path $($downloadedCert) 2>&1
                Add-KFInfoLog $outputLog $logFile "Updated individual Enrollment with DeviceID of: $($certCN) to have new Certificate: $azUpdateResult"
                $addEnrollment = $false;
            }
        }
    }
    else {
        Add-KFInfoLog $outputLog $logFile "az iot dps enrollment show timed out "
        Remove-Job $listJob
    }
} catch {
    Add-KFErrorLog $outputLog $logFile "an error ocurred while listing existing DPS enrollment with CN of: $($certCN)"
    Add-KFErrorLog $outputLog $logFile "error: $_ "
}

try {
    if ($addEnrollment) {
        Add-KFInfoLog $outputLog $logFile "Adding DPS enrollment with DeviceID of: $($certCN) and certificate: $($downloadedCert)"
        Add-KFInfoLog $outputLog $logFile "calling: az iot dps enrollment create --resource-group $($ResourceGroup) --dps-name $($dpsName) --enrollment-id $($certCN) --attestation-type "x509" --certificate-path $($downloadedCert) 2>&1"
        $azCreateResult = az iot dps enrollment create --resource-group $($ResourceGroup) --dps-name $($dpsName) --enrollment-id $($certCN) --attestation-type "x509" --certificate-path $($downloadedCert) 2>&1
        Add-KFInfoLog $outputLog $logFile "response from azure: $azCreateResult"
    }
}
catch {
    Add-KFErrorLog $outputLog $logFile "an error ocurred while creating an individual enrollment with CN of: $($certCN)"
    Add-KFErrorLog $outputLog $logFile "error: $_ "
}

Add-KFWarningLog $outputLog $logFile "Exiting script: $(Get-Date -format G) `r`n =========================================="
