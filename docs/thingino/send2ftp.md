Send to FTP
===========

This example shows how to send data to an FTP server. The data is sent as a
file with a filename template that includes the current date and time.

### Configure FTP server details

Fill in `FTP server FQDN or IP address`, `Port`, `FTP username`, `FTP password`
fields with the FTP server details.

The `Path on FTP server` field should contain the path where the file will be saved on the FTP server.

### Set up storage path and filename template

The `Filename template` field should contain the template for the filename.
The template can include directives for date and time supported by [strftime][1]
parser, such as `%Y-%m-%d` for the year, month, and day, etc.

Test the configuration by clicking the `Send to FTP` button on the preview page.
If the test is successful, you will see a new file on the FTP server.


[1]: https://strftime.net/
