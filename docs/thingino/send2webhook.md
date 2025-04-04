Send to Webhook
===============

Send to Webhook is a Thingino feature that allows you to send data to a webhook
URL. This is useful for integrating with other services or for sending data to
a custom server.

### Configuration

Fill in the following fields to configure the Send to Webhook feature:

- `Webhook URL` is the URL to which the data will be sent.
This can be any valid URL, including a URL to a service like IFTTT or Zapier.

- `Message` is the message that will be sent to the webhook. This can be any
plain text data or a valid JSON object.

- `Attach Snapshot` is a boolean option that allows you to attach a snapshot from
the camera to the webhook request. If this option is enabled, the snapshot will
be attached as a file to the request. The file name will be `snapshot.jpg` and
the content type will be `image/jpeg`. The snapshot will be taken at the time
the webhook is sent.

### Test Webhook

You can test the webhook by clicking the "Send to Webhook" button on the preview
page. This should send a test message to the webhook URL you have configured.

Alternatively, you can wind up a make-shift tcp server to receive the webhook.
On your desktop, use `netcat` to start listening for requests on a random
available port, e.g. port 12345:

```bash
netcat -l -p 12345
```

Then, in the Thingino Web UI, set Webhook address to the IP address of your
machine and port 12345, e.g. `http://192.168.1.123:12345`. Fill in the
Message field with a JSON object, e.g. `{"foo":"bar"}`. Save the configuration,
and click the "Send to Webhook" button.

You should see the request appear in the terminal window where you started
`netcat`. The request will look something like this:

```
POST / HTTP/1.1
Host: 192.168.1.123:12345
User-Agent: curl/8.12.1
Accept: */*
Content-Length: 9
Content-Type: application/x-www-form-urlencoded

{"foo":"bar"}
```
