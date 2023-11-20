# Copyright 2022 Keyfactor
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions
# and limitations under the License.

Import-Module Az

function Add-KFTraceLog {
    <#
    .SYNOPSIS
    Adds the $message to the logfile as it's own line marked as [T] to be used for Tracing,
    Also displays the message on the screen
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is
    .PARAMETER message - the string contents to write to the file
    #>
    param(
        [boolean]$OutputLog, 
        $LogFilePath, 
        $message)
    if ($null -eq $LogFilePath) {
        throw "trace log file path required"
    }
    if ($OutputLog) {
        $outMsg = (Get-Date -Format "hh:mm") + "[T] $message"
        Add-Content -Path $LogFilePath -Value $outMsg
        Write-Host $outMsg -ForegroundColor white
    }
}
function Add-KFInfoLog {
    <#
    .SYNOPSIS
    Adds the $message to the logfile as it's own line marked as [I] to be used for information,
    Also displays the message on the screen
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is
    .PARAMETER message - the string contents to write to the file
    #>
    param(
        [boolean]$OutputLog, 
        $LogFilePath, 
        $message)
    if ($null -eq $LogFilePath) {
        throw "info log file path required"
    }
    if ($OutputLog) {
        $outMsg = (Get-Date -Format "hh:mm") + "[I] $message"
        Add-Content -Path $LogFilePath -Value $outMsg
        Write-Host $outMsg -ForegroundColor white
    }
}
function Add-KFErrorLog {
    <#
    .SYNOPSIS
    Adds the $message to the logfile as it's own line marked as [E] to be used as an Error Message,
    Also displays the message on the screen in red
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is
    .PARAMETER message - the string contents to write to the file
    #>
    param(
        [boolean]$OutputLog, 
        $LogFilePath, 
        $message)
    if ($null -eq $LogFilePath) {
        throw "Error log file path required"
    }
    if ($OutputLog) {
        $outMsg = (Get-Date -Format "hh:mm") + "[E] $message"
        Add-Content -Path $LogFilePath -Value $outMsg
        Write-Host $outMsg -ForegroundColor red
    }
}
function Add-KFWarningLog {
    <#
    .SYNOPSIS
    Adds the $message to the logfile as it's own line marked as [W] to be used as a Warning Message,
    Also displays the message on the screen in yellow
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is
    .PARAMETER message - the string contents to write to the file
    #>
    param(
        [boolean]$OutputLog, 
        $LogFilePath, 
        $message)
    if ($null -eq $LogFilePath) {
        throw "Warning log file path required"
    }
    if ($OutputLog) {
        $outMsg = (Get-Date -Format "hh:mm") + "[W] $message"
        Add-Content -Path $LogFilePath -Value $outMsg
        Write-Host $outMsg -ForegroundColor Yellow
    }
}

function LogHelper {
    #TODO (sukhyung) finish+use this instead of duplicating the same stuff 4x
    param(
        [boolean]$OutputLog,
        $LogFilePath,
        $message,
        $type)
    if ($null -eq $LogFilePath) {
        throw "$type log file path required"
    }
    if ($OutputLog) {
        $outMsg = (Get-Date -Format "hh:mm") + "$type $message"
        Add-Content -Path $LogFilePath -Value $outMsg
        #switch ($type) {
        #condition {  }
        #Default {}
        #}
        #Write-Host $outMsg -ForegroundColor $Color
    }
}
function Initialize-KFLogs {
    <#
    .SYNOPSIS
    Initializes logging for a given filepath.  creates the file is not already present, one per day of the year (e.g. run the initialize
    twice in the same day, it will append the first file).  It will also ensure that only the latest $MaxFileCount log files are present.
    .PARAMETER OutputLog - boolean value, true to log, false to not log
    .PARAMETER LogFilePath - file path to where the log file is/should be (YYMMDD.txt is appended to this as the filename
    .PARAMETER LogFilePrefix - the string the log file should be named.
    .PARAMETER MaxFileCount - the maximum number of log files to keep in the $LogFilePath
    .OUTPUTS
    System.String. Intialize-KFLogs returns the path to the log file that should be used.
    #>
    param(
        [boolean]$OutputLog,
        $LogFilePath,
        $LogFilePrefix,
        [int] $MaxFileCount
    )
    #todo validate arguments?
    $LogFileName = $LogFilePath + "\" + $LogFilePrefix + (Get-Date -UFormat "%Y%m%d") + ".txt" #one log file per day
    if (!(Test-Path $LogFileName)) {
        #if file doesnt exist, create it
        $null = New-Item -ItemType file $LogFileName
    }

    $LogFormat = $LogFilePrefix + "*.txt"
    $existingLogs = [System.IO.Directory]::GetFiles("$LogFilePath", "$LogFormat") | Sort-Object -Descending #want newest to be first

    if ($existingLogs.Count -gt $MaxFileCount) {
        #keep only the $MaxFileCount latest log files
        for ($i = $MaxFileCount; $i -lt $existingLogs.Count; $i++) {
            Add-KFInfoLog $OutputLog $LogFileName "Deleting expired Logfile: $existingLogs[$i]"
            [System.IO.File]::Delete($existingLogs[$i])
        }
    }
    return $LogFileName
}
# Check and process the context parameters
# The PowerShell alert handler injects the following into our runspace: [hashtable]$context
# We expect that a "Thumbprint" value will be passed in which was mapped from {thumbprint}
# If a "OutputLog" value is passed that starts with "Y" we will output to a log file
[bool]$outputLog = $false
if ($context["OutputLog"] -like "Y*" ) { $outputLog = $true }
# Generate a log file for tracing if OutputLog is true
$logFile = Initialize-KFLogs $outputLog "C:\keyfactor\logs\" "azEnroll" 5 #keep no more than 5 logs at a time
Add-KFInfoLog $outputLog $logFile "Starting Trace: $(Get-Date -format G)"

try {
    #input processing
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
    [boolean]$skipAz = $false

    # By default, expiration handlers send emails. Turn this off
    Add-KFInfoLog $outputLog $logFile "Turning off emailing"
    $context["sendEMail"] = "false"

}
catch {
    Add-KFErrorLog $outputLog $logFile "exception caught during input parsing: $_.Exception.Message"
    Add-KFErrorLog $ouputLog $logFile "error: $_ "
}
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
            $azResult = Add-AzIotHubDevice -ResourceId "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Devices/IotHubs/$HubName" -DeviceId $certCN -AuthMethod "x509_thumbprint" -PrimaryThumbprint $certThumbprint 2>&1
            Add-KFInfoLog $outputLog $logFile "Created IoTHubDevice with DeviceID of: $($certCN) and Thumbprint: $($certThumbprint)"
            Add-KFInfoLog $outputLog $logFile "response from azure: $azResult"
        }
    }
    catch {
        Add-KFErrorLog $outputLog $logFile "an error ocurred while creating an IotHub Device with CN of: $($certCN)"
        Add-KFErrorLog $outputLog $logFile "error: $_ "
    }
}

Add-KFWarningLog $outputLog $logFile "Exiting script: $(Get-Date -format G) `r`n =========================================="
