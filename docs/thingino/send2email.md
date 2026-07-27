Send to email
=============

"Send to email" is a feature that allows you to send messages from Thingino
camera to a predefined email address. This is useful for sharing data with
others or for keeping a record of your Thingino data.

### Set up SMTP server to send email to

- `SMTP server FQDN or IP address`
- `(SMTP server) port`
- `SMTP username`
- `SMTP password`
- `Use TLS/SSL`

You might want to set the script to `Ignore SSL certificate validity` if you
get errors due to self-signed certificates.

### Set up sender and recipient

`Sender's name` and `Sender's address` will appear in the "From" field of the
email. Use a real name and email address where bounce reports can be sent to.

`Recipient's name` and `Recipient's address` are where messages will be sent to.

### Set up message

Create `Email subject` and optional `Email text`. Select a form of attachment:
snapshot or a short video clip.

Save the settings and test the email sending clicking on "Send to email" button
on the preview page or running `send2email` in console. You should receive an
email shortly.
