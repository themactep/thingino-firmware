Prusa Connect
=============

The Prusa Connect integration pushes Thingino camera metadata and periodic
snapshots to the Prusa Connect cloud service so your printer dashboard can
show near real-time imagery.

Collect credentials
-------------------

1. Sign in to [connect.prusa3d.com](https://connect.prusa3d.com/).
2. Pick the printer that should host the camera feed.
3. Click **Add new web camera** and note the generated **Token**.
4. Create a unique fingerprint/UUID for this camera:
   * Web UI: use the **Generate fingerprint** button on the Prusa Connect page.
   * CLI: run `prusa-connect generate-fingerprint` over SSH.
   * Any RFC4122 UUID generator also works.

Configure via Web UI
--------------------

1. Open **Services → Prusa Connect** in the Thingino Web UI.
2. Toggle **Enable Prusa Connect**.
3. Enter the Token and Fingerprint from the previous section.
4. Adjust the snapshot and metadata intervals if needed.
5. (Optional) Specify a hostname to ping before uploads, or override the
   Prusa API endpoints for testing.
6. Click **Save settings**, then use **Test upload now** to confirm a 204/200
   HTTP status appears in the status panel.

Configure via CLI
-----------------

SSH into the camera and use the helper script:

```bash
prusa-connect setup <TOKEN> <FINGERPRINT>
prusa-connect status
prusa-connect test        # one-shot info + snapshot upload
prusa-connect enable      # or disable
prusa-connect set-interval 30
prusa-connect set-info-interval 600
```

All values now live in `/etc/prusa-connect.json`. Inspect or tweak them via
`jct /etc/prusa-connect.json print` if you prefer editing over SSH.

Troubleshooting
---------------

* **Host unreachable** – the optional reachability host must resolve and
  reply to ICMP. Leave the field empty to skip the check.
* **HTTP 401/403** – verify both Token and Fingerprint exactly match the
  values shown in Prusa Connect.
* Logs are tagged `prusa-connect`; review them with `logread | grep prusa` or
  from the Web UI debug panel.
