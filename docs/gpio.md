GPIO
----

### GPIO Map in Stock Firmware

Dump stock firmware.
Use `hijacker.sh` to repack the firmware without root password.
Flash it back to the camera.
Connect via UART, login and run:

```
mount -t debugfs none /sys/kernel/debug; cat /sys/kernel/debug/gpio
```

Save the output for future reference.
