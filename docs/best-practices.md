Best Practices
==============

Networking
----------

### MAC Address

Thingino generates a unique MAC address for each camera per interface by
utilizing the hardware data, specifically the SoC ID.

This simplifies the process of setting up multiple cameras on a LAN and
assigning the MAC address to an IP address in DHCP leases, making the user
experience similar to using static addresses.

### DHCP

The DHCP protocol mandates regular lease renewals. If your DHCP server has a
default TTL of 600 seconds, renewals will occur every 300 seconds.

The log entries will appear as follows:

```
Sep 28 19:07:15 ing-wyze-c3-bdca daemon.info udhcpc[1460]: sending renew to server 192.168.1.1
Sep 28 19:07:15 ing-wyze-c3-bdca daemon.info udhcpc[1460]: lease of 192.168.1.36 obtained from 192.168.1.1, lease time 600
```

A true static IP connection does not require updates and depends on the details
in the camera's configuration files.

### Remote Access by Key

On the client computer, generate an ssh key and upload its public part to the
camera.

```
ssh-keygen -t ed25519 -C "your_email@example.com"
ssh-copy-id root@192.168.1.10
```

Enter password when prompted to authenticate and upload the key.

### Remote Logging

Camera logs are stored on temporary storage, which is a RAM disk. This means
these logs will be lost after a reboot. If you need to keep logs for a longer
period, you can use a syslog server to store them.

Setup a syslog server on your network and configure the camera to send logs to
the server by adding remote syslog server IP address to `rsyslog_host` parameter
of U-Boot environment, e.g.: `fw_setenv rsyslog_host 192.168.1.66`


Day/Night
---------

The `daynight` script runs every minute to monitor changes in brightness and
switch IR-filter, IR LEDs, and color mode of the image sensor.

The command in its current state is a shell script, and that means that each
time it runs, it starts a separate shell process and brings all of its load
with it.

If you want to switch your camera to night mode at night and to day mode during
the day without additional tracking of brightness changes, you can use the
`Day/Night by Sun` service, which monitors astronomical sunsets and sunrises
for your geographic location and creates tasks for the cron service to switch
the camera mode accordingly.
