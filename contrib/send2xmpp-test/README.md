# send2xmpp regression test

Containerized test bench for `package/send2xmpp/files/send2xmpp`.

It exists because the BOSH session parser originally accepted only
single-quoted attributes. Openfire 5.x returns `sid=""`, so session
establishment failed there even though Prosody and older Openfire worked
(issue #1985). The same quote assumption existed in the XEP-0363 component
discovery parser.

The server in this directory is a small BOSH/XMPP mock, not a real XMPP
server. It answers the flow send2xmpp needs: session establishment, SASL
PLAIN, resource bind, session, disco items, HTTP upload slot, message and
terminate. The attribute quote style is selected per request:

| URL | Behaviour |
|-----|-----------|
| `http://bosh:5280/http-bind?style=double` | Openfire 5.x style (`sid="..."`) |
| `http://bosh:5280/http-bind?style=single` | Prosody/legacy style (`sid='...'`) |

The test runner sends text and image messages in both styles, checks that
the server received them, checks that the uploaded bytes arrived, and sends
a message containing XML-special characters. It runs the script with the
Alpine BusyBox shell, matching the camera's `ash`.

## Run

```sh
./run.sh
```

Uses `podman compose` when available, otherwise `docker compose`. The test
runner installs `curl` in its container. Build and run output is shown; the
final line is `All send2xmpp tests passed.` with exit status 0.

To run the mock server by hand:

```sh
podman build -t send2xmpp-bosh .
podman run --rm -p 5280:5280 send2xmpp-bosh
```

## Files

| File | Purpose |
|------|---------|
| `bosh_server.py` | BOSH/XMPP mock with selectable attribute quote style |
| `docker-compose.yml` | Mock server plus an Alpine test runner |
| `run-tests.sh` | Test cases and assertions |
| `run.sh` | Compose wrapper |

For a real server, see `package/send2xmpp/files/README-xmpp.md` and
`QUICKSTART.md` in the package (Prosody BOSH/HTTP upload setup).
