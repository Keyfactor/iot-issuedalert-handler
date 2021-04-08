This script is intended to be run on the keyfactor platform windows host by the svc_keyfactor service account.

AzIotEnroll.ps1 is intended to be called by the Keyfactor Platform as an 'Issued Certificate Request' handler script.  The platform will run this script after the issuance of any certificates of the specified template and check them to see if they are device-id certs.  If so the platform will register the certificate as a new device in the specified Azure Iot Core.  

This script requires the install of the Az sdk powershell module on the svc_keyfactor account.  Details of the installation of the powershell module is available here: https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-5.7.0

The azure specific values should be provided to the script as 'Static Value's from the Configure Event Handler's Parameters dialog.
These include the Azure IoT Hub Name, Application Id, Tenant Id, Subscription Guid, and the thumbprint for a certificate registered to the Service Principal credential.  The specified Service Principal should also have at IoT Admin permissions so it can create devices in IoT Hub.

Required Parameters from the Issued Certificate Alert Settings Dialog
AzHubName :
AzSubGuid :
AzAppId :
AzTenantId :
AzServicePrincipalCertTP :
OutputLog : Y to enable logging, anything else for not.
ScriptName : the string path (on the keyfactor platform windows host) for the script.
SN : the serial number of the cert.  
