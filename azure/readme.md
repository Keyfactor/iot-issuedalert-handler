These scripts are intended to be run on the keyfactor platform windows host by the svc_keyfactor service account. 

These scripts require the install of the Az sdk powershell module on the svc_keyfactor account.  Details of the installation of the powershell module is available here: https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-5.7.0

![image](https://user-images.githubusercontent.com/78758042/119694237-e61f7c80-be01-11eb-8a0f-847c88d469a5.png)


# AzIotEnroll.ps1 
an 'Issued Certificate Request' handler script.  The platform will run this script after the issuance of any certificates of the specified template and check them to see if they are device-id certs.  If so the platform will register the certificate as a new device in the specified Azure Iot Core.  
![image](https://user-images.githubusercontent.com/78758042/119693847-86c16c80-be01-11eb-9567-ad7f8fa88971.png)

The azure specific values should be provided to the script as 'Static Value's from the Configure Event Handler's Parameters dialog.
These include the Azure IoT Hub Name, Application Id, Tenant Id, Subscription Guid, and the thumbprint for a certificate registered to the Service Principal credential.  The specified Service Principal should also have at IoT Admin permissions so it can create devices in IoT Hub.

## Required Parameters from the Issued Certificate Alert Settings Dialog
* AzHubName: the name of the Az Iot Hub
* AzSubGuid: the string subscription Id for the azure IotHub
* AzAppId: the string application id for the IotHub
* AzTenantId: the string tenant Id for the IotHub
* AzServicePrincipalCertTP: the thumbprint of the certificate used for the service principal.  
* OutputLog : Y to enable logging, anything else for not.
* ScriptName : the string path (on the keyfactor platform windows host) for the script.
* SN : the serial number of the cert.  




