Send to FTP
===========

This example shows how to send data to an FTP server. The data is sent as a
file with a filename template that includes the current date and time.

### Configure FTP server details

Fill in `FTP server FQDN or IP address`, `Port`, `FTP username`, `FTP password`
fields with the FTP server details.

The `Path on FTP server` field should contain the path where the file will be saved on the FTP server.

### Enable FTPS

Enable `Use FTPS (explicit TLS)` to upload over FTP over TLS (AUTH TLS).
This uses explicit FTPS on the configured control port (typically 21); implicit
FTPS on port 990 is not supported. The upload keeps the `ftp://` scheme and
requires TLS with `--ssl-reqd`, since curl's `ftps://` scheme is implicit.

The server certificate is validated against the system CA store. Enable
`Ignore SSL certificate validity` only for servers with a self-signed
certificate that cannot be trusted otherwise.

### Set up storage path and filename template

The `Filename template` field should contain the template for the filename.
The template can include directives for date and time supported by [strftime][1]
parser, such as `%Y-%m-%d` for the year, month, and day, etc.

Test the configuration by clicking the `Send to FTP` button on the preview page.
If the test is successful, you will see a new file on the FTP server.


[1]: https://strftime.net/
