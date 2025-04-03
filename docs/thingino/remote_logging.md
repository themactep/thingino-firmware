Remote logging
==============

Remote logging is useful for monitoring multiple Thingino devices at one place,
also for debugging, especially when an error makes device to reboot, and logs
get deleted.

In Web UI, open the configuration form at `Settings` -> `Remote logging`.

In the form, fill in `Syslog server FQDN or IP address` field with the IP
address or FQDN of the syslog server.

In the `Syslog server port` field, fill in the port number of the syslog server.
The default port is `514`, but you can change it to any other port if needed.

Reboot the device to apply the changes.
The device will start sending logs to the syslog server.
