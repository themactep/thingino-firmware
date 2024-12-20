DHCP
----

Thingino creates a unique MAC address per camera per interface using the
hardware data as a source, namely the SoC ID. This makes it easy to set up a
bunch of such cameras on a LAN and pin the MAC address to an IP address in DHCP
leases. This makes the user experience indistinguishable from using static
addresses.

The DHCP protocol requires leases to be renewed regularly. If your DHCP server's
default TTL is 600 seconds, renewals will happen every 300 seconds. Log records
will look similar to this one:

```
Sep 28 19:07:15 ing-wyze-c3-bdca daemon.info udhcpc[1460]: sending renew to server 192.168.1.1
Sep 28 19:07:15 ing-wyze-c3-bdca daemon.info udhcpc[1460]: lease of 192.168.1.36 obtained from 192.168.1.1, lease time 600
```

A real static IP connection doesn't need updates and relies on the information
in the camera's configuration files.

Day/Night
---------

The `daynight` command runs every minute to monitor changes in brightness,
and switch IR-filter, IR LEDs, and color mode of the image sensor.

The command in its current state is a shell script, and that means that each
time it runs, it starts a separate shell process and brings all of its load
with it.

If you want to switch your camera to night mode at night and to day mode during
the day without additional tracking of brightness changes, you can use the
`Day/Night by Sun` service, which monitors astronomical sunsets and sunrises
for your geographic location and creates tasks for the cron service to switch
the camera mode accordingly.

