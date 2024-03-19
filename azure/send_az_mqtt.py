from paho.mqtt import client as mqtt
import ssl
import time
import sys

print ('num args', len(sys.argv))
print ('arg list: ', str(sys.argv))
if (len(sys.argv) < 3):
    print ("please input device_id and iot_hub name as parameters")
    exit()

if (sys.argv[1]):
    device_id = sys.argv[1]
    print ("device_id input:", device_id)
else:
    print ("invalid device_id input, exiting")
    exit

if (sys.argv[2]):
    iot_hub_name = "keyfactor-iot-demos"
    print ("iot_hub name input:", iot_hub_name)
else:
    print ("invalid iot_hub name input, exiting")
    exit

path_to_root_cert = "/home/keyfactor/DigiCertGlobalRootG2.pem"

def on_connect(client, userdata, flags, rc):
    print("Device connected with result code: " + str(rc))

def on_disconnect(client, userdata, rc):
    print("Device disconnected with result code: " + str(rc))
    client.loop_stop()

def on_publish(client, userdata, mid):
    print("Device sent message_id:", mid)

client = mqtt.Client(client_id=device_id, protocol=mqtt.MQTTv311)

client.on_connect = on_connect
client.on_disconnect = on_disconnect
client.on_publish = on_publish

client.username_pw_set(username=iot_hub_name+".azure-devices.net/" +
                       device_id + "/?api-version=2018-06-30", password=None)

# Set the certificate and key paths on your client
cert_file = "/home/keyfactor/Keyfactor-CAgent/certs/IoT.store"
key_file = "/home/keyfactor/Keyfactor-CAgent/certs/IoT.key"

client.tls_set(ca_certs=path_to_root_cert, certfile=cert_file, keyfile=key_file,
               cert_reqs=ssl.CERT_REQUIRED, tls_version=ssl.PROTOCOL_TLSv1_2, ciphers=None)

client.connect(iot_hub_name+".azure-devices.net", port=8883)
for x in range (25):
    msg = {"value": x}
    print("publishing message: ", str(msg))
    client.publish("devices/" + device_id + "/messages/events/", str(msg), qos=1)
    client.loop()
    time.sleep(1.5)
