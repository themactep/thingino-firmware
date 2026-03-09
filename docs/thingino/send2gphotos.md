Send to Google Photos
======================

The Google Photos integration lets Thingino upload motion snapshots and short
clips directly into your personal library (and optionally into a dedicated
album). The integration relies on the official Google Photos Library API and an
OAuth client that you manage inside your own Google Cloud project—no third-party
proxy is involved.

Prerequisites
-------------

1. A Google account with Google Photos enabled.
   (`https://console.cloud.google.com/apis/library/photoslibrary.googleapis.com`)
2. A Google Cloud project where you can enable the **Google Photos Library API**.
3. An OAuth 2.0 **Desktop** client ID/secret for that project.
4. A refresh token generated for the Photos scope
   (`https://www.googleapis.com/auth/photoslibrary.appendonly`).
5. (Optional) The camera callback URL (`https://<camera>/gphotos-auth-callback.html`)
   added to the client's **Authorized redirect URIs** list in Google Cloud
   Console if you want Thingino to capture the OAuth code automatically. Google
   only accepts HTTPS for custom redirect URIs; if your camera does not serve
   HTTPS, keep the default `http://localhost` flow and copy the code manually.

> The OAuth consent screen must include your Google account as a test user when
> the app is in testing mode. You only need the "append only" scope because
> Thingino never reads or deletes media.

Generating a Refresh Token
--------------------------

Thingino can guide you through the OAuth flow directly from the **Google Photos**
tab:

1. Enter your OAuth client ID and secret and choose a redirect URI:
   - **Default/manual flow** – leave it at `http://localhost`. After approving
     the Google consent screen, copy the `code` parameter from the localhost tab
     and paste it into the Thingino form.
   - **Automatic capture (advanced)** – click **Camera URL** to insert
   `https://<camera>/gphotos-auth-callback.html`, then add the same HTTPS
     URL to the OAuth client's redirect list. Google only accepts HTTPS for this
     path, and Thingino will append `device_id`/`device_name` for private IPs.
2. Click **Open Google consent** and approve access. If you chose the camera
   callback, Thingino captures the code automatically when Google redirects
   back; otherwise copy it from the browser address bar.
3. Click **Exchange code for refresh token** if it does not run automatically.
   Once the refresh token field is populated, click **Save** to store it in
   `/etc/send2.json`.

> If Google responds without a refresh token, revoke the app under
> Google Account → Security → Third-party apps, then run the flow again so
> Google issues a fresh token.

Fallback: Manual curl
---------------------

If the camera cannot reach Google directly, you can still exchange the code on
your PC:

```bash
curl -s https://oauth2.googleapis.com/token \
  -d client_id=YOUR_CLIENT_ID \
  -d client_secret=YOUR_CLIENT_SECRET \
  -d redirect_uri=http://localhost \
  -d grant_type=authorization_code \
  -d code=PASTED_AUTH_CODE
```

Copy the `refresh_token` from the JSON response into Thingino manually.

Finding an Album ID (optional)
-----------------------------

If you want uploads to land in a specific album, open Google Photos in a web
browser, select the album, and copy the ID from the URL. The string after the
last slash (`/album/XXXXXXXX`) is the ID. Leave the field empty to drop media in
"Photos" / "Camera Roll".

Configuring Thingino
--------------------

Open **Tools → Send to Services → Google Photos** in the web UI. Provide:

- **OAuth client ID / secret** from Google Cloud Console.
- **Refresh token** obtained earlier.
- **Album ID** (optional) to route uploads to a specific album.
- **Description template** – supports `%hostname`, `%datetime`, `%type`, and
  `%filename` placeholders.
- **Filename templates** for snapshots and clips (strftime compatible; the
  script adds `.jpg` or `.mp4`).
- Toggle whether motion events should upload photos, videos, or both.

Testing & Automation
--------------------

1. Click **Test** next to Google Photos on the summary page to force an upload.
2. Enable **Send motion alerts to → Google Photos** so `/sbin/motion` launches
   `send2gphotos` automatically when motion is detected.
3. Check `/tmp/send2gphotos.log` (if verbose mode is enabled) or the web UI test
   modal for troubleshooting—most failures are OAuth credential issues.

Tips
----

- Use a dedicated album per camera to keep uploads organized.
- Description templates can include `%hostname` and `%datetime` to make searching
  inside Google Photos easier.
- Refresh tokens do not expire unless you revoke access in Google Account
  settings; rotate them if the camera is compromised.
