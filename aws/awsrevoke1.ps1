Import-Module AWS.Tools.IoT

# First, specify URL for API, note that keyfactor is used instead of control.
# Notes from Sukhyung for using Windows Auth:
#		1.) Ensure that Windows Authentication is enabled for the KeyfactorAPI endpoint (DefaultWebsite > KeyfactorAPI) in IIS
#       2.) For normal operation the Keyfactor Service (Timer Service) account is used -- Make sure this account has the appropriate Keyfactor & AD rights
#       3.) For testing from the portal, the Application Pool account is used -- Make sure this account has the appropriate Keyfactor & AD rights
$apiURL = '<KF API URL>'

[bool]$outputLog = $true
$jsonCredsPath = '<path to JSON IAM creds (make sure these are protected!)>'
$AWSRegion = '<AWS region>'

# Generate a log file for tracing if OutputLog is true
if ($outputLog) { $outputFile = ("<path_to_log>\AWSRevokeLog_" + (get-date -UFormat "%Y%m%d%H%M") + ".txt") }

# Function: Update-LogFile
# Description: function to update log file
function Update-LogFile {
	param ($Path, $Write, $Content)
	if ($Write) {
		Add-Content $Path -Value $Content
	}
}

function Search-KFMetadata {
    param($MetadataField, $Parameter)
    $uri = "$($apiURL)/Certificates?pq.includeRevoked=true&pq.queryString=$MetadataField%20-eq%20%22$Parameter%22"
    $headers = @{}
	$headers.Add('Content-Type', 'application/json')
	$headers.Add('x-keyfactor-requested-with', 'APIClient')
    # Might add verbose logging later... but for now it's too much
	#Update-LogFile -Path $outputFile -Write $outputLog -Content "Preparing a GET from $uri to find certificate such that $MetadataField equals $Parameter"
    $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -UseDefaultCredentials
	#Update-LogFile -Path $outputFile -Write $outputLog -Content "Got back $($response)"
    return $response
}

function Initialize-AWSIoT {
    param($jsonCredentialPath)
    # Read IAM credentials from JSON file
    $jsonCreds = Get-Content -Path $jsonCredentialPath | Out-String | ConvertFrom-Json
	$AWSAccessKey = $jsonCreds.AWSAccessKey
	if ([string]::IsNullOrWhiteSpace($AWSAccessKey)) { throw "Did not find 'AWSAccessKey' in JSON specified at $jsonCredsPath" }
    Update-LogFile -Path $outputFile -Write $outputLog -Content "Found access key in JSON config specified at $jsonCredsPath"
	$AWSSecretKey = $jsonCreds.AWSSecretKey
	if ([string]::IsNullOrWhiteSpace($AWSSecretKey)) { throw "Did not find 'AWSSecretKey' in JSON specified at $jsonCredsPath" }
    Update-LogFile -Path $outputFile -Write $outputLog -Content "Found secret key in JSON config specified at $jsonCredsPath"

    # Get AWS IoT Tools version
    $checkawscli = Get-Command Get-IOTCertificate
    Update-LogFile -Path $outputFile -Write $outputLog -Content "Using $($checkawscli.Source) version $($checkawscli.Version)"
    # Create AWS IoT Credentials object using IAM creds
    $AWSCredential = New-AWSCredential `
        -AccessKey $AWSAccessKey `
        -SecretKey $AWSSecretKey
    if ([string]::IsNullOrEmpty($AWSCredential)) {
        Update-LogFile -Path $outputFile -Write $outputLog -Content "Failed to create AWS credentials"
    }
    return $AWSCredential
}

function Get-KFCertStatusFromID {
    param($CertID)
    #Update-LogFile -Path $outputFile -Write $outputLog -Content "Preparing a GET from $uri"
    $uri = "$($apiURL)/Certificates/$CertID"
    $headers = @{}
	$headers.Add('Content-Type', 'application/json')
	$headers.Add('x-keyfactor-requested-with', 'APIClient')
    $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -UseDefaultCredentials
    #Update-LogFile -Path $outputFile -Write $outputLog -Content "Got back $response"
    if ($($response.CertState) -eq '2') {return "REVOKED"}
    else {return "ACTIVE"}
}

function Revoke-DeactivatedCertificates {
    $ReturnCode = 0 # Intialize return code to track if any certificates FAIL to revoke.
    # First, get entire list of certificates in AWS.
    Update-LogFile -Path $outputFile -Write $outputLog -Content "Retreiving list of AWS IoT certificates"
    $CertificateList = Get-IOTCertificateList `
        -Region $AWSRegion `
        -Credential $AWSCredential
    # Parse Keyfactor certificate metadata for all certificates that have matching ARN's with list of certificates from AWS
    for ($i = 0; $i -lt $CertificateList.GetUpperBound(0); $i++) {
        $certificateData = Search-KFMetadata -MetadataField "AWS-CertARN" -Parameter $([System.Web.HttpUtility]::UrlEncode($CertificateList[$i].CertificateArn))
        $AWSCertificateID = $CertificateList[$i].CertificateId
        # If a certificate was returned, check its status
        if (-Not $([string]::IsNullOrWhiteSpace($certificateData))) {
            $CertStatus = Get-KFCertStatusFromID -CertID $($certificateData.Id)
            Update-LogFile -Path $outputFile -Write $outputLog -Content "Certificate with KF ID $($certificateData.Id) was found to be $CertStatus"
            # If the certificate is revoked in Keyfactor, first, check if it is also revoked in AWS. If not, deactivate certificate in AWS!
            if ($CertStatus -eq "REVOKED") {
                Update-LogFile -Path $outputFile -Write $outputLog -Content "Checking status of cert with AWS ID $AWSCertificateID in AWS"
                $AWSCertData = Get-IOTCertificate `
                    -CertificateId $AWSCertificateID `
                    -Region $AWSRegion `
                    -Credential $AWSCredential
                if ($($AWSCertData.Status) -eq "ACTIVE") {
                    Update-LogFile -Path $outputFile -Write $outputLog -Content "Certificate is active in AWS. Deactivating certificate."
                    Update-IOTCertificate `
                        -CertificateId $AWSCertificateID `
                        -Region $AWSRegion `
                        -Credential $AWSCredential `
                        -NewStatus "INACTIVE"
                    $AWSCertData = Get-IOTCertificate `
                        -CertificateId $AWSCertificateID `
                        -Region $AWSRegion `
                        -Credential $AWSCredential
                        if ($($AWSCertData.Status) -eq "INACTIVE") {
                            Update-LogFile -Path $outputFile -Write $outputLog -Content "Successfully deactivated certificate"
                        }
                        else {
                            Update-LogFile -Path $outputFile -Write $outputLog -Content "Failed to deactivate certificate with AWS ID $AWSCertificateID"
                            $ReturnCode++ # I would prefer the script to run all the way through rather than error out and get stuck. Increment return code.
                        }
                }
                else {
                    Update-LogFile -Path $outputFile -Write $outputLog -Content "Certificate with AWS ID $AWSCertificateID is already deactivated!"
                }
            }
        }
    }
    return $ReturnCode
}

try {
    Update-LogFile -Path $outputFile -Write $outputLog -Content "Starting Trace: $(Get-Date -format G)"

    # Initialize AWS
    $AWSCredential = Initialize-AWSIoT -jsonCredentialPath $jsonCredsPath
    if ([string]::IsNullOrWhiteSpace($AWSCredential)) {throw "Failed to initialize AWS"}
    else {Update-LogFile -Path $outputFile -Write $outputLog -Content "Successfully initialized AWS"}

    # Revoke all deactivated certificates.
    $return = Revoke-DeactivatedCertificates
    if ($return -ne 0) {throw "Failed to deactivate $return certificate(s)"}
}
catch {
    Update-LogFile -Path $outputFile -Write $outputLog -Content $_.Exception.Message
    Update-LogFile -Path $outputFile -Write $outputLog -Content $_
}
Update-LogFile -Path $outputFile -Write $outputLog -Content "Exiting script: $(Get-Date -format G)"
Update-LogFile -Path $outputFile -Write $outputLog -Content "==================="