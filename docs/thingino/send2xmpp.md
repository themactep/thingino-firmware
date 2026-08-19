Send to XMPP
============

Send to XMPP is a Thingino feature that sends motion alerts (and optionally a
snapshot) to an XMPP/Jabber contact. It is implemented by the `send2xmpp`
script — a pure shell + curl XMPP client — so it runs on the camera without
Python or other dependencies.

It talks to the server over **BOSH** (HTTP binding, XEP-0124/0206) and
authenticates with SASL PLAIN. Snapshots are uploaded as attachments via
**HTTP Upload** (XEP-0363).

## Server requirements

Your XMPP server must expose:

- a **BOSH endpoint** — Prosody: `https://xmpp.example.com:5281/http-bind`
  (`mod_bosh`), ejabberd: port 5443, Openfire: port 7443;
- **HTTP Upload** (XEP-0363) for image attachments (optional — text messages
  work without it).

The camera needs a registered account (e.g. `camera@example.com`). For a
quick local test server, see
[Services: XMPP test server](services/xmpp-test-server.md).

## Configuration

Two equivalent ways to configure send2xmpp:

**1. Configuration file** `/etc/send2xmpp.conf` (takes precedence):

```sh
XMPP_JID="camera@example.com"       # camera account
XMPP_PASSWORD="secret"              # its password
XMPP_RECIPIENT="you@example.com"    # who receives the alerts
XMPP_BOSH_URL="https://xmpp.example.com:5281/http-bind"
XMPP_RESOURCE="thingino"            # optional session identifier
# XMPP_UPLOAD_COMPONENT="upload.example.com"   # optional, auto-discovered
```

**2. Web UI** — Services → XMPP (stored in the `xmpp` section of
`/etc/send2.json`): JID, password, resource, BOSH endpoint URL, recipient,
and "Send photo" (requires HTTP Upload). Used automatically when
`/etc/send2xmpp.conf` is absent.

## Usage

```bash
send2xmpp -m "Motion detected"                     # text message
send2xmpp -i /tmp/snapshot.jpg -m "Motion at 14:30"  # image + caption
echo "Camera online" | send2xmpp                   # message from stdin
send2xmpp -v -m "test"                             # verbose
```

On motion events, `send2xmpp` runs automatically when the **XMPP** toggle is
enabled on the Web UI Services page (`motion.send2xmpp` in the camera config);
the motion snapshot is attached when available.

## Example (Prosody)

With a Prosody server (`mod_bosh` enabled), a camera account and a recipient
account registered, put the config above in `/etc/send2xmpp.conf` and test:

```bash
send2xmpp -m "Hello from $(hostname)" -v
```

Expected verbose output: *Connecting… Authenticating… Binding resource…
Sending message… Closing connection… Done!* — and the message arrives in your
XMPP client.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `Error: Failed to establish BOSH session` | BOSH endpoint reachable? `curl <bosh_url>` should return a BOSH body; server has `mod_bosh` enabled |
| `Error: Authentication failed` | Account exists, password correct. SASL PLAIN over plain HTTP is refused by default on many servers — use an HTTPS BOSH endpoint or enable `allow_unencrypted_plain_auth`/`consider_bosh_secure` for a local test server |
| Image not delivered | Server lacks HTTP Upload (XEP-0363) — send2xmpp falls back to a text-only message; check `XMPP_UPLOAD_COMPONENT` |
| Sends are slow (~60s) | BOSH `wait` hold: the script uses `wait=1` so sends return in ~1s; a stuck request usually means the server never responds — check the BOSH endpoint |
