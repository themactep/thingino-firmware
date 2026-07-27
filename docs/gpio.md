GPIO
====

### GPIO Map in Stock Firmware

Dump stock firmware.
Use `hijacker.sh` to repack the firmware without root password.
Flash the repacked binary back to the camera.
Connect via UART, login as `root` with empty password and run:

```
mount -t debugfs none /sys/kernel/debug; cat /sys/kernel/debug/gpio
```

Save the output for future reference.

### GPIO scanning

Sweeping a range of pins can be done using the following simple
one-liner, where 0 and 35 are the range of pins to toggle:

```
for i in $(seq 0 35); do echo $i; gpio set $i 1; sleep 1; gpio set $i 0; done
```
