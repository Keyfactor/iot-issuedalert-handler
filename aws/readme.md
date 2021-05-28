Scripts are intended to run on the Keyfactor platform windows host by the svc_keyfactor account. All scripts require that the AWS.Tools.IoT powershell module is installed on the Windows server. Documentation on initializing this module can be found at the below link.

https://docs.aws.amazon.com/powershell/latest/userguide/pstools-getting-set-up-windows.html

Each of the scripts configure their own credentials using a configuration JSON file containing IAM credentials, so the AWS credentials sections can be skipped.

# AWS IoT Certificate Enrollment Handler - awsenroll1.ps1

Adjust fields for $apiURL, $jsonCredsPath, $ThingProvisioningTemplatePath, and $LogPath

AWS allows for many methods of device/certificate registration, including uploading the CA to AWS (known CA), and by specifying to AWS that the CA is not known (unknown CA). This script and enrollment template assumes that the CA is known by AWS.

The enrollment handler retreives the certificate PEM and CA PEM files via the Keyfactor REST API before initializing AWS. Then, it creates a parameter hash table according to the template. The test template takes a name, serial number, device location, and the PEM certificates for the CA and device certificate. Using these values, a new thing is registered, the certificate is uploaded, and a policy for the certificate is created and attached.

AWS returns booth the ARN for the certificate and for the thing. The certificate ARN is then attached to Keyfactor metadata.

## Required fields for powershell script

* AWSRegion - Region used by IoT instance
* OutputLog - Yes or No to create an output log of actions taken by script
* ScriptName - Select “Powershell Script Name” option when field is created. Value is automatically populated
* SN - Serial number of script found under “Special Text” dropdown
* TestOnly - Skips AWS enrollment for testing script
* CN - Common name attached to certificate (used for thing registration)

# AWS IoT Certificate Revocation - awsrevoke1.ps1

Adjust fields for $jsonCredsPath, $AWSRegion, and $LogPath before running script.

Obviously, when a device certificate is revoked in Keyfactor, the device should be denied access after AWS checks the CRL. This script is intended to run once daily on the Keyfactor server to disable certificates in AWS that are revoked in Keyfactor. Disabling the certificate in AWS guarentees that the device can't connect in the future.

This script works by getting a list of certificates enrolled in AWS, and comparing each ARN to Keyfactor certificates containing an ARN as metadata. If a certificate is revoked in Keyfactor with a matching ARN, a function is called to deactivate the certificate in AWS.