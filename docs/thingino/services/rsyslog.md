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

You will find logged messages in the `/var/log/syslog` file on the server.

### Installing rsyslog server for remote logging on Alpine Linux

Alpine installs busybox syslogd by default, which only logs locally. Replace
it with rsyslog:

```bash
apk add rsyslog logrotate
rc-service syslog stop
rc-update del syslog boot
rc-update add rsyslog
rc-service rsyslog start
```

The `rsyslog-openrc` package provides `/etc/init.d/rsyslog`; keep that init
script as-is. A custom script that pre-creates the pidfile makes rsyslogd exit
silently, thinking another instance owns it.

Enable the network inputs in `/etc/rsyslog.d/20-network.conf`:

```
module(load="imudp")
input(type="imudp" port="514")

module(load="imtcp")
input(type="imtcp" port="514")
```

Cameras send UDP syslog, so `imudp` is required; `imtcp` is optional.

To keep one log file per camera, named by source IP, add
`/etc/rsyslog.d/30-thingino.conf`:

```
template(name="ThinginoFmt" type="string"
	string="%timereported:::date-pgsql% %syslogfacility-text%.%syslogseverity-text% %syslogtag%%msg%\n")
template(name="ThinginoPath" type="string"
	string="/var/log/thingino/%fromhost-ip%.log")

if ($inputname == "imudp" or $inputname == "imtcp") then {
	action(type="omfile" dynafile="ThinginoPath" template="ThinginoFmt")
}
```

On rsyslog 8.2604 (Alpine 3.24), dynamic file names require the `dynafile`
parameter; the `file` parameter with `%...%` placeholders is treated
literally by omfile.

Apply the changes with a restart (reload only sends HUP, which rsyslogd may
not apply):

```bash
rc-service rsyslog restart
```

Rotate per-camera logs with `/etc/logrotate.d/thingino`:

```
/var/log/thingino/*.log {
	weekly
	rotate 4
	compress
	delaycompress
	missingok
	notifempty
	copytruncate
}
```

Users that should read the logs need to be in the `adm` group.
