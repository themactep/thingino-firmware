Diagnostics and Troubleshooting
===============================

If something goes wrong, you can diagnose the problem by following these steps:

### From Web UI

Log in into the Web UI and find the diagnostics form at the
"Information -> Share Diagnostics Info" page.

### From Linux Shell

Alternatively, you can run the following command on the command line:

```bash
thingino-diag
```
This will generate a diagnostics report and send it to termbin.com server for
temporary storage. You will be presented with a URL to the report for sharing.

### Saving to a File

If the camera does not have internet access, you can save the diagnostics report
to a file by running:

```bash
thingino-diag -l /path
```

This will generate a diagnostics report and print the path to the file.

### Using an SD Card

IF you do not have access to the camera shell, you can trigger generation of a
diagnostics report by creating a file named `.diag` in the root directory of a
blank SD card and inserting the card into the running camera. The camera will
generate a diagnostics report and save it to the card.
