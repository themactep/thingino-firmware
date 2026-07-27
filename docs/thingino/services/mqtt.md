MQTT
====

Install an MQTT broker and clients.

```bash
sudo apt install mosquitto mosquitto-clients
```

Configure the MQTT broker to allow anonymous access.
Edit the configuration file:

```bash
sudo vi /etc/mosquitto/conf.d/anonymous.conf
```

Add the following lines to the file:

```conf
allow_anonymous true
listener 1883
```

Save and exit the file.

Restart the MQTT broker to apply the changes:

```bash
sudo systemctl restart mosquitto
```

Test the MQTT broker by publishing a message to a topic and subscribing
to that topic.

Open a terminal and run the following command to subscribe to the topic
`test/topic`:

```bash
mosquitto_sub -h localhost -t test/topic
```
Open another terminal and run the following command to publish a message
to the topic `test/topic`:

```bash
mosquitto_pub -h localhost -t test/topic -m "Hello, MQTT!"
```

You should see the message "Hello, MQTT!" appear in the first terminal where
you subscribed to the topic. This indicates that the MQTT broker is working
correctly and you can now use it to send and receive messages between devices.
