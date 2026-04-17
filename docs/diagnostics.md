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
By default this saves diagnostics to a random temp file in `/tmp/`.

To upload diagnostics to `tb.thingino.com`:

```bash
thingino-diag -u
```

To upload and return JSON with the link:

```bash
thingino-diag -j
```

### Saving to a File

If the camera does not have internet access, you can save the diagnostics report
to a file by running:

```bash
thingino-diag -o /path/file
```

This will generate a diagnostics report and print the path to the file.
You can also stream output to stdout with `thingino-diag -o -`.

Legacy option `-l [path]` is still accepted for local file output.

### Using an SD Card

IF you do not have access to the camera shell, you can trigger generation of a
diagnostics report by creating a file named `.diag` in the root directory of a
blank SD card and inserting the card into the running camera. The camera will
generate a diagnostics report and save it to the card.

### RTSP Stress Testing

For repeated RTSP/UDP or RTSP/TCP playback testing from a host machine, see
`rtsp-stress-test.md`.
