XMPP test server (Prosody)
=========================

A local Prosody XMPP server is useful for testing the [Send to XMPP](../send2xmpp.md)
notification service without signing up for a public XMPP provider.

`scripts/prosody-test.sh` creates a throwaway Prosody container (podman or
docker, auto-detected) with BOSH enabled, two test accounts, and prints the
configuration to use from a camera.

## Usage

```bash
scripts/prosody-test.sh start                # start + provision + print config
scripts/prosody-test.sh start -f /tmp/cam.conf   # write config to a file
scripts/prosody-test.sh status               # container status
scripts/prosody-test.sh stop                 # stop, keep data
scripts/prosody-test.sh restart              # stop, start, re-provision users
scripts/prosody-test.sh rm                   # stop and delete container + volume
```

Options:

| Option | Meaning | Default |
|--------|---------|---------|
| `-n NAME` | container name | `prosody-test` |
| `-p PORT` | BOSH HTTP port | `5280` |
| `-d DOMAIN` | virtual host domain | `test.local` |
| `-c JID` | camera account | `camera@<domain>` |
| `-P PASS` | camera password | `camera123` |
| `-r JID` | recipient account | `paul@<domain>` |
| `-R PASS` | recipient password | `paul123` |
| `-f FILE` | write the camera config snippet to FILE | print to stdout |

## What it provisions

- A Prosody container on `:5280` with `mod_bosh` (XEP-0124/0206) and
  `internal_plain` authentication. Plain HTTP BOSH is enabled
  (`allow_unencrypted_plain_auth`, `consider_bosh_secure`) so a camera can
  connect without TLS for testing.
- Two accounts: the camera (`camera@test.local`) and the recipient
  (`paul@test.local`), registered via `prosodyctl`.
- Data persists in a named volume (`<name>-data`), so `stop`/`start` keeps
  accounts; `rm` deletes everything.

## Using it from a camera

The `start` output is a ready-to-paste `/etc/send2xmpp.conf`:

```sh
XMPP_JID="camera@test.local"
XMPP_PASSWORD="camera123"
XMPP_RECIPIENT="paul@test.local"
XMPP_BOSH_URL="http://192.168.1.10:5280/http-bind"
XMPP_RESOURCE="thingino"
XMPP_TLS_VERSION=""
```

(The host IP is detected automatically. `XMPP_TLS_VERSION=""` disables TLS
options because the container serves plain HTTP.)

On the camera, either write `/etc/send2xmpp.conf` with those values, or fill
the same fields in the Web UI under **Services → XMPP** (they are stored in
the `xmpp` section of `/etc/send2.json`). Then test:

```bash
send2xmpp -m "Hello from the camera" -v
```

Delivery can be verified on the server — unsent-while-offline messages are
stored per recipient:

```bash
podman exec prosody-test sh -c \
  'cat "/var/lib/prosody/test.local/offline/paul.list"'
```

## Notes

- Image uploads (XEP-0363 HTTP Upload) need an upload-capable server; the
  stock `prosody/prosody` image used here does not ship `mod_http_upload`
  (obsolete) or `mod_http_file_share` (Prosody 0.12+). Text messages work;
  for image upload testing, point send2xmpp at a server with HTTP Upload.
- The container serves BOSH on plain HTTP on your LAN — fine for a
  development bench, not for a production network.
