Scripts are intended to run on the Keyfactor platform windows host by the svc_keyfactor account. All scripts require that the AWS.Tools.IoT powershell module is installed on the Windows server. Documentation on initializing this module can be found at the below link.

https://docs.aws.amazon.com/powershell/latest/userguide/pstools-getting-set-up-windows.html

Each of the scripts configure their own credentials using a configuration JSON file containing IAM credentials, so the AWS credentials sections can be skipped.

# AWS IoT Certificate Enrollment Handler - awsenroll1.ps1

Adjust fields for $apiURL, $jsonCredsPath, $ThingProvisioningTemplatePath, and $LogPath

AWS allows for many methods of device/certificate registration, including uploading the CA to AWS (known CA), and by specifying to AWS that the CA is not known (unknown CA). This script and enrollment template assumes that the CA is known by AWS.

The enrollment handler retreives the certificate PEM and CA PEM files via the Keyfactor REST API before initializing AWS. Then, it creates a parameter hash table according to the template. The test template takes a name, serial number, device location, and the PEM certificates for the CA and device certificate. Using these values, a new thing is registered, the certificate is uploaded, and a policy for the certificate is created and attached.

The registration returns the ARNs for the certificate (contains the AWS certificate ID) and for the thing. Teh ARN for the certificate in AWS is then attached to the certificate metadata in Keyfactor.

