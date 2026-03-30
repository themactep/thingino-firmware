WireGuard Provisioner
=====================

Thingino can import WireGuard client profiles from an external HTTP service.
This service is optional. Cameras can still be configured manually without it.

This document describes the HTTP contract expected by Thingino and shows one
simple way to build a compatible provisioner.

What the camera expects
-----------------------

The camera UI stores a provisioner base URL and a peer name. During import, the
camera requests:

```text
<provision_url>/<peer_name>?create=1
```

If a token is configured, the camera appends it as:

```text
<provision_url>/<peer_name>?create=1&token=<token>
```

Peer names are restricted to these characters:

- letters `A-Z` and `a-z`
- digits `0-9`
- underscore `_`
- hyphen `-`

Expected endpoints
------------------

### Peer index

Optional but useful for browsing:

```text
GET /provision/wireguard/peer
```

### Peer fetch

Required:

```text
GET /provision/wireguard/peer/<peer_name>
```

### On-demand create

Optional but supported by Thingino:

```text
GET /provision/wireguard/peer/<peer_name>?create=1
POST /provision/wireguard/peer/<peer_name>
```

If you do not want to support automatic creation, you can ignore `create=1` and
serve only pre-generated peers.

Response format
---------------

The camera expects JSON. These fields are required in the `data` object:

- `address`
- `privkey`
- `endpoint`
- `peerpub`

These fields are optional but supported:

- `dns`
- `peerpsk`
- `allowed`
- `port`
- `keepalive`
- `mtu`

Successful response example:

```json
{
  "status": "ok",
  "data": {
    "address": "10.13.13.5/32",
    "privkey": "<camera private key>",
    "dns": "1.1.1.1",
    "endpoint": "192.168.88.20:51820",
    "peerpub": "<server public key>",
    "peerpsk": "<optional preshared key>",
    "allowed": "10.13.13.0/24",
    "port": "",
    "keepalive": "25",
    "mtu": ""
  }
}
```

Error response example:

```json
{
  "status": "error",
  "error": "peer not found"
}
```

Import behavior on the camera
-----------------------------

After a successful import, Thingino:

- stores the profile in `/etc/thingino.json`
- saves the profile as enabled by default
- defaults keepalive to `25` if your server omits it
- remembers the provisioner URL, peer name, and optional token for future use

Minimal architecture
--------------------

The simplest provisioner has three pieces:

1. A WireGuard server.
2. A directory of pre-generated camera profiles.
3. A tiny HTTP service that returns profile JSON for a named peer.

This means the provisioner does not need to create peers dynamically unless you
want that feature.

Preparing a pre-generated peer
------------------------------

Create a camera peer entry on the WireGuard server and reserve a unique tunnel
address for it.

Server peer example:

```ini
[Peer]
PublicKey = <camera public key>
PresharedKey = <optional preshared key>
AllowedIPs = 10.13.13.5/32
```

Create a JSON file for the camera profile, for example
`peers/cam160.json`:

```json
{
  "address": "10.13.13.5/32",
  "privkey": "<camera private key>",
  "dns": "1.1.1.1",
  "endpoint": "192.168.88.20:51820",
  "peerpub": "<server public key>",
  "peerpsk": "<optional preshared key>",
  "allowed": "10.13.13.0/24",
  "port": "",
  "keepalive": "25",
  "mtu": ""
}
```

Minimal Flask implementation
----------------------------

This example serves pre-generated peer JSON files from a directory.

```python
from pathlib import Path
import json
import os

from flask import Flask, jsonify, abort, request

app = Flask(__name__)
PEER_DIR = Path(os.environ.get("PEER_DIR", "./peers"))
WG_TOKEN = os.environ.get("WG_PROVISION_TOKEN", "")


def token_ok():
    if not WG_TOKEN:
        return True
    return request.args.get("token", "") == WG_TOKEN


def valid_peer_name(name: str) -> bool:
    return name.replace("-", "").replace("_", "").isalnum()


@app.get("/provision/wireguard/peer")
def list_peers():
    peers = sorted(path.stem for path in PEER_DIR.glob("*.json"))
    return jsonify({
        "status": "ok",
        "peers": peers,
        "example": "/provision/wireguard/peer/<peer_name>",
    })


@app.route("/provision/wireguard/peer/<peer_name>", methods=["GET", "POST"])
def get_peer(peer_name):
    if not valid_peer_name(peer_name):
        return jsonify({"status": "error", "error": "invalid peer name"}), 422

    if not token_ok():
        return jsonify({"status": "error", "error": "invalid token"}), 403

    peer_file = PEER_DIR / f"{peer_name}.json"
    if not peer_file.exists():
        return jsonify({"status": "error", "error": "peer not found"}), 404

    with peer_file.open() as handle:
        data = json.load(handle)

    return jsonify({"status": "ok", "data": data})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8081)
```

Install and run it:

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install flask
export PEER_DIR=$PWD/peers
export WG_PROVISION_TOKEN=optional-shared-secret
python3 provision-server.py
```

Testing the provisioner
-----------------------

```bash
curl http://127.0.0.1:8081/provision/wireguard/peer
curl 'http://127.0.0.1:8081/provision/wireguard/peer/cam160?create=1'
curl 'http://127.0.0.1:8081/provision/wireguard/peer/cam160?create=1&token=optional-shared-secret'
```

The final response must contain the peer profile in the `data` object.

Optional: automatic peer creation
---------------------------------

If you want the provisioner to create peers on demand, support one of these
patterns:

- `GET /provision/wireguard/peer/<peer_name>?create=1`
- `POST /provision/wireguard/peer/<peer_name>`

Your server can then:

1. Allocate the next unused tunnel address.
2. Generate a private key and public key for the camera.
3. Generate an optional pre-shared key.
4. Add a matching peer entry to the WireGuard server.
5. Save a JSON profile for future requests.
6. Return the profile in the same response format shown above.

The exact implementation is up to you. Thingino only cares that the endpoint
returns valid JSON in the expected format.

Security notes
--------------

- Treat returned camera private keys as secrets.
- Use a token if the provisioner is reachable outside a trusted LAN.
- Prefer serving the provisioner only on a management network.
- If you expose it over the internet, put it behind TLS and authentication.

Camera-side configuration example
---------------------------------

In the Thingino Web UI, set:

```text
Provisioner URL: http://192.168.88.20:8081/provision/wireguard/peer
Peer Name: cam160
Provision Token: optional-shared-secret
```

Then click `Import from provisioner`.

If you prefer not to run a provisioner at all, configure the camera manually as
described in `wireguard-client.md`.