rsyslog
=======

### Installing rsyslog server for remote logging

You can configure remote logging to send logs from a camera to a remote syslog
server. This is useful for centralizing logs from multiple devices.

Debian and some other distro do not have a syslog server installed by default.
You can install it with the following command:

```bash
sudo apt-get install rsyslog
```

To enable remote logging, you need to allow remote access to the syslog.
This can be done by modifying the rsyslog configuration file usually located
at `/etc/rsyslog.conf` as follows:

Allow access using TCP and UDP protocols, add the following lines to the:

```bash
# Load the imudp module
module(load="imudp")
# Listen on UDP port 514
input(type="imudp" port="514")

# Load the imtcp module
module(load="imtcp")
# Listen on TCP port 514
input(type="imtcp" port="514")
```

After making these changes, restart the rsyslog service to apply the new
configuration:

```bash
sudo systemctl restart rsyslog
```

You can check the status of the rsyslog service to ensure it is running:

```bash
sudo systemctl status rsyslog
```

You will fing logged messages in the `/var/log/syslog` file on the server.
