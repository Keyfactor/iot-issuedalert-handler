This script is intended to be run on the keyfactor platform windows host by the svc_keyfactor service account.

gcpEnroll.ps1 is intended to be called by the Keyfactor Platform as an 'Issued Certificate Request' handler script.  The platform will run this script after the issuance of any certificates of the specified template and check them to see if they are device-id certs.  If so the platform will register the certificate as a new device in the specified Google Cloud Iot Hub.  

it requires the install of the GCP cloud sdk powershell modules on the svc_keyfactor account.  Details of the installation of the powershell module is available here: https://cloud.google.com/sdk/docs/install#windows

The google specific values should be provided to the script as 'Static Value's from the Configure Event Handler's Parameters dialog.
These include the IoT Hub Project Id, Project Location, Registry, and the path for the json file containing the service account credential.  The specified service account should also have at least IoT Admin permissions so it can create devices in IoT Hub.

Required Parameters from the Issued Certificate Alert Settings Dialog
GcpProjectId : the string ID of the GCP IoT Hub Project
GcpLocation : e.g. us-central-1
GcpRegistry : the string ID of the GCP IoT Hub Registry
GcpServiceAccountJsonPath : the string path (on the keyfactor platform windows host) to the Service Account Json credential.  
OutputLog : Y to enable logging, anything else for not.
ScriptName : the string path (on the keyfactor platform windows host) for the script.
SN : the serial number of the cert.  
TestOnly : Y to enable testOnly - will NOT post to IoT Hub, anything to post to IoT Hub.


