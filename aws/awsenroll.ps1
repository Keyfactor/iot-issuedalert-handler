# Copyright 2021 Keyfactor
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions
# and limitations under the License.
#
Import-Module AWS.Tools.IoT
$ScriptDir = Split-Path -parent $MyInvocation.MyCommand.Path
Import-Module $ScriptDir\..\powershellModules\kf_logging.psm1
# First part of script primarily created by Sukhyung, adapted by Hayden for AWS
# Specify the API URL base.
# Note that when we call the API we use Windows Auth:
#		1.) Ensure that Windows Authentication is enabled for the KeyfactorAPI endpoint (DefaultWebsite > KeyfactorAPI) in IIS
#       2.) For normal operation the Keyfactor Service (Timer Service) account is used -- Make sure this account has the appropriate Keyfactor & AD rights
#       3.) For testing from the portal, the Application Pool account is used -- Make sure this account has the appropriate Keyfactor & AD rights
#
# NOTE: For the control.thedemodrive.com instance, it will not respond locally to control.thedemodrive.com
#       instead, use keyfactor.thedemodrive.com for all API calls
#
$apiURL = '<KF API URL>'

# Specify path to JSON credentials file
$jsonCredsPath = '<path to JSON IAM creds (make sure these are protected!)>'
$ThingProvisioningTemplatePath = '<path to provisioning template>'
$LogPath = '<path to log file>'
[bool]$EnrollThing = $true

function InitializeAWS {
    param($jsonCredsPath)
    # Read in AWS IAM credentials from JSON specified at the top
    $jsonCreds = Get  $jsonCredsPath | Out-String | ConvertFrom-Json
    $AWSAccessKey = $jsonCreds.AWSAccessKey
    if ([string]::IsNullOrWhiteSpace($AWSAccessKey)) { throw "Did not find 'AWSAccessKey' in JSON specified at $jsonCredsPath" }
    Add-KFInfoLog $outputLog $logFile "Found access key in JSON config specified at $jsonCredsPath"
    $AWSSecretKey = $jsonCreds.AWSSecretKey
    if ([string]::IsNullOrWhiteSpace($AWSSecretKey)) { throw "Did not find 'AWSSecretKey' in JSON specified at $jsonCredsPath" }
    Add-KFInfoLog $outputLog $logFile "Found secret key in JSON config specified at $jsonCredsPath"

    # Initialize AWS
    $checkawscli = Get-Command Get-IOTCertificate
    Add-KFInfoLog $outputLog $logFile "Using $($checkawscli.Source) version $($checkawscli.Version)"
    $AWSCredential = New-AWSCredential `
        -AccessKey $AWSAccessKey `
        -SecretKey $AWSSecretKey
    return $AWSCredential
}

# Function: Add-KFInfoLog
# Description: function to update log file
function Add-KFInfoLog {
    param ($Path, $Write, $Content)
    if ($Write) {
        Add-KFInfoLog $Write $Path $Content
    }
}

# Function: Get-CertFromID
# Description: Function to get certificate PEM from Keyfactor API using KF cert ID
# Returns: Decoded PEM certificate
function Get-CertFromID {
    param ($ID)
    # Send an API call to grab the certificate by its cert id
    $uri = "$($apiURL)/Certificates/Download"
    $body = @{"CertId" = $ID } | ConvertTo-Json -Compress
    $headers = @{}
    $headers.Add('Content-Type', 'application/json')
    $headers.Add('x-keyfactor-requested-with', 'APIClient')
    $headers.Add('X-CertificateFormat', 'PEM')
    Add-KFInfoLog $outputLog $logFile "Preparing a POST from $uri with body $body"
    $response = Invoke-RestMethod -Uri $uri -Method POST -Body $body -Headers $headers -UseDefaultCredentials
    Add-KFInfoLog $outputLog $logFile "Got back $($response)"

    # The response should contain the base 64 PEM
    # We are after the payload
    $b64_encoded_string = $response[0].Content
    $unencodedCertPEM = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("$b64_encoded_string"))
    if ([string]::IsNullOrWhiteSpace($unencodedCertPEM)) { throw "Didn't get back a certificate PEM from cert with ID $ID" }
    Add-KFInfoLog $outputLog $logFile "Decoded certificate is: "
    Add-KFInfoLog $outputLog $logFile "$unencodedCertPEM"
    return $unencodedCertPEM
}

# Function: Get-CertIDFromSN
# Description: Function to retreive certificate ID from KF using cert SN, in addition to certificate issuerDN
# Returns: hashtable containing certID and issuerDN
function Get-CertIDFromSN {
    param($SN)
    # Send an API call to grab the cetificate id from the cert serial number
    # We need this in further calls
    $Return = @{} # Initialize return hashtable to return issuer DN and certitificate ID
    $headers = @{}
    $headers.Add('Content-Type', 'application/json')
    $headers.Add('x-keyfactor-requested-with', 'APIClient')
    $uri = "$($apiURL)/Certificates?pq.queryString=SerialNumber%20-eq%20%22$certSN%22"
    Add-KFInfoLog $outputLog $logFile "Preparing a GET from $uri"
    $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -UseDefaultCredentials
    $Return.Add('IssuerDN', $response[0].IssuerDN)
    Add-KFInfoLog $outputLog $logFile "Got back $($response)"
    $certId = $response[0].Id
    $return.Add('certId', $response[0].Id)
    $expiryDate = $response[0].NotAfter
    Add-KFInfoLog $outputLog $logFile "Decoded cert id as $certId with expiry of $expiryDate"

    return $Return
}

# Function: Get-AgentCertStatus
# Description: Determine if certificate is an agent certificate
# Returns: boolean
function Get-AgentCertStatus {
    param($certId)
    # Send an API call to find the number of stores the certificate has
    $uri = "$($apiURL)/Certificates/Locations/$certId"
    Add-KFInfoLog $outputLog $logFile "Preparing a GET from $uri"
    $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -UseDefaultCredentials
    Add-KFInfoLog $outputLog $logFile "Got back $($response)"
    $storeCount = $response.Details.StoreCount

    # Check if it is an array. - Sami edit 03/24/2021 -> s.s. i moved the $clientMachine defintion into a better place,
    # shouldnt try to access if it it doesnt exist anymore

    [bool]$agentCert = $false
    if ([string]::IsNullOrWhiteSpace($storeCount)) {
        Add-KFInfoLog  $logFile  $outputLog  "No store found, this must be an Agent cert"
        #could we just exit() here instead of having to keep this agentCert bool?
        $agentCert = $true
    }
    else {
        Add-KFInfoLog $outputLog $logFile "Found a store for this cert, so it isn't an Agent cert"
        $clientMachine = $response.Details.Locations[0].ClientMachine
        Add-KFInfoLog $outputLog $logFile "Found this cert in $storeCount stores, the first store is in machine $clientMachine"
    }
    return $agentCert
}

# Function: Get-CertIDFromDN
# Description: Retreive certificate ID using issuer DN
# Returns: Certificate ID
function Get-CertIDfromDN {
    param($IssuerDN)
    $headers = @{}
    $headers.Add('Content-Type', 'application/json')
    $headers.Add('x-keyfactor-requested-with', 'APIClient')
    $uri = "$($apiURL)/Certificates?pq.queryString=IssuedDN%20-eq%20%22$IssuerDN%22"
    Add-KFInfoLog $outputLog $logFile "Preparing a GET from $uri"
    $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -UseDefaultCredentials
    Add-KFInfoLog $outputLog $logFile "Got back $($response)"
    $CertId = $response[0].Id
    $expiryDate = $response[0].NotAfter
    Add-KFInfoLog $outputLog $logFile  "Decoded cert id as $CertId with expiry of $expiryDate"

    return $CertId
}

function Update-KFCertMetadata {
    param($CertId, $MetadataField, $NewValue)
    # Update certificate metadata with ARN returned by AWS
    $uri = "$($apiURL)/Certificates/Metadata"
    $headers = @{}
    $headers.Add('Content-Type', 'application/json')
    $headers.Add('x-keyfactor-requested-with', 'APIClient')
    $Metadata = @{}
    $Metadata.Add($MetadataField, $NewValue)
    $body = @{"Id" = $certId; "Metadata" = $Metadata } | ConvertTo-Json -Compress
    Add-KFInfoLog $outputLog $logFile "Preparing a PUT from $uri with body $body"
    $response = Invoke-RestMethod -Uri $uri -Method PUT -Body $body  -Headers $headers -UseDefaultCredentials
    if ([string]::IsNullOrWhiteSpace($response)) {
        Add-KFInfoLog $outputLog $logFile "Updated metadata successfully"
    }
}

function Register-CertificateAndThing {
    param($Name, $SerialNumber, $Location, $CertPEM, $caCertPEM, $AWSCredential)
    $TemplateBody = Get  $ThingProvisioningTemplatePath | Out-String
    $IoTThingParameter = @{}
    $IoTThingParameter.Add('ThingName', $Name)
    $IoTThingParameter.Add('SerialNumber', $SerialNumber)
    $IoTThingParameter.Add('Location', $Location)
    $IoTThingParameter.Add('CACertificatePem', $caCertPEM)
    $IoTThingParameter.Add('CertificatePem', $CertPEM)
    Add-KFInfoLog $outputLog $logFile "Registering IoT Thing with AWS named $Name with serial number $SerialNumber"
    $response = Register-IOTThing `
        -TemplateBody $TemplateBody `
        -Parameter $IoTThingParameter `
        -Region $AWSRegion `
        -Credential $AWSCredential
    Add-KFInfoLog $outputLog $logFile "Registered thing with ARN $($($response.ResourceArns.thing))"
    return $response.ResourceArns
}

function Register-CertificateWithAWS {
    param($CertPEM, $caCertPEM, $AWSCredential)
    # Register certificate with AWS
    Add-KFInfoLog $outputLog $logFile "Registering certificate with AWS"
    $RegisterIoTResponse = Register-IOTCertificate `
        -CaCertificatePem $caCertPEM `
        -CertificatePem $CertPEM `
        -Status ACTIVE `
        -Region $AWSRegion `
        -Credential $AWSCredential
    if ([string]::IsNullOrWhiteSpace($RegisterIoTResponse.CertificateArn)) { throw "Did not find AWS ARN" }
    Add-KFInfoLog $outputLog $logFile "Registered IoT certificate with ARN $($RegisterIoTResponse.CertificateArn) and certificate ID $($RegisterIoTResponse.CertificateId)"
    return $RegisterIoTResponse.CertificateArn
}

# The PowerShell alert handler injects the following into our runspace: [hashtable]$context
# We expect that a "SN" value will be passed in which was mapped from {sn}
# If a "OutputLog" value is passed that starts with "Y" we will output to a log file
# If a "TestOnly" value is passed that starts with a "Y" we will skip the AWS IoT portion

# Check and process the context parameters
[bool]$outputLog = $false
if ($context["OutputLog"] -like "Y*" ) { $outputLog = $true }

# Generate a log file for tracing if OutputLog is true
if ($outputLog) {
    $logFile = Initialize-KFLogs $outputLog $LogPath "AWSEnrollLog_" 5
}
Add-KFInfoLog $outputLog $logFile "Starting Trace: $(Get-Date -format G)"

try {
    # Find certificate serial number from context hash table
    $certSN = $context["SN"]
    Add-KFInfoLog $outputLog $logFile "Context variable 'SN' = $certSN"
    if ([string]::IsNullOrWhiteSpace($certSN)) { throw "Context variable 'SN' required" }

    # Determine if invocation is a test
    [bool]$testOnly = $false
    if ($context["TestOnly"] -like "Y*" ) { $testOnly = $true }
    Add-KFInfoLog $outputLog $logFile "Is test? $testOnly"

    # Use context to determine AWS region
    $AWSRegion = $context["AWSRegion"]
    Add-KFInfoLog $outputLog $logFile "Using $AWSRegion as AWS region"
    if ([string]::IsNullOrWhiteSpace($AWSRegion)) { throw "Context variable 'AWSRegion' required" }

    # Find certificate common name from context hash table
    $certCN = $context["CN"]
    Add-KFInfoLog $outputLog $logFile "Context variable 'CN' = $certCN"
    if ([string]::IsNullOrWhiteSpace($certCN)) { throw "Context variable 'CN' required" }

    # By default, expiration handlers send emails. Turn this off
    Add-KFInfoLog $outputLog $logFile "Turning off emailing"
    $context["sendEMail"] = "false"

    $CertID_IssuerDN = Get-CertIDFromSN -SN $certSN # This function returns hash table for cert ID and issuer DN
    $IssuerDN = $CertID_IssuerDN['IssuerDN'] # Assign values from hash table into variables
    $certId = $CertID_IssuerDN['certId']
    if ([string]::IsNullOrWhiteSpace($certId)) { throw "Did not get back a certId" }

    # Check if cert is agent cert
    $agentCert = Get-AgentCertStatus -certId $certId

    if ($false -eq $agentCert) {
        # Now that we know that the certifcate is not an agent cert, we can use the issuer DN to get the CA certificate
        $caCertID = Get-CertIDfromDN -IssuerDN $IssuerDN
        if ([string]::IsNullOrWhiteSpace($CertId)) { throw "Did not get back a CA certId from issuer DN" }

        # Using CA cert ID, call get-certfromid to return CA PEM certificate
        $unencodedCACertPEM = Get-CertFromID -ID $caCertID

        # Finally, we can get the certificate data from the certificate ID from above
        $unencodedCertPEM = Get-CertFromID -ID $certId

        if ($testOnly) {
            Add-KFInfoLog $outputLog $logFile "Skipping AWS registration"
        }

        else {
            $AWSCredential = InitializeAWS -jsonCredsPath $jsonCredsPath
            if ([string]::IsNullOrEmpty($AWSCredential)) {
                Add-KFInfoLog $outputLog $logFile "Failed to create AWS credentials"
                throw "Failed to create AWS credentials"
            }

            if ($EnrollThing) {
                $ARNs = Register-CertificateAndThing -Name $certCN -SerialNumber $certSN -Location 'AZ' -CertPEM $unencodedCertPEM -caCertPEM $unencodedCACertPEM -AWSCredential $AWSCredential
                $CertARN = $ARNs.certificate
                $ThingARN = $ARNs.thing
            }
            else {
                $CertARN = Register-CertificateWithAWS -CertPEM $unencodedCertPEM -caCertPEM $unencodedCACertPEM -AWSCredential $AWSCredential
            }
            # Update KF metadata for certificate ARN returned by registration
            Update-KFCertMetadata -MetadataField "AWS-CertARN" -CertId $certId -NewValue $CertARN
        }
    }
}
catch {
    Add-KFInfoLog $outputLog $logFile $_.Exception.Message
    Add-KFInfoLog $outputLog $logFile $_
}

Add-KFInfoLog $outputLog $logFile "Exiting script: $(Get-Date -format G) `r`n ==================================="
