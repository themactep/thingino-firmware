# VDB2 diagnostic kernel patch

`0001-t31-swan-restore-pb27-pull-up.patch` reproduces the recovered Wyze VDB2
kernel's early weak internal pull-up on GPIO59/PB27 before userspace exports the
pin. It does not reproduce the separate late stock userspace setup.

The normal VDB2 defconfig does not apply this patch. Use it only in a separate
diagnostic image, confirm the GPIO59 power-on waveform with a scope or meter,
and retain `S14vdb2-chime` so userspace subsequently changes GPIO59, GPIO52,
and GPIO53 to output-low just as stock `iCamera` does.

The recovered stock `/system/init/app_init.sh` writes the complete port-B
pull-up register after loading the Wi-Fi driver:

```sh
devmem 0x10011110 32 0x6e094800
```

Package version 1.4 reproduced that later write, but subsequent stock-kernel
analysis established that it is only the pre-iCamera staging state. Stock GPIO
exports then clear both pulls on GPIO59/PB27, GPIO52/PB20, GPIO53/PB21, and
GPIO51/PB19, leaving the port-B pull-up register at `0x66014800`. Version 1.5
reproduces that second phase and explicitly selects GPIO input mode on GPIO51.
Use that complete stock-derived path instead of this diagnostic patch.

Expected kernel code after applying the patch:

```c
static gpio_pull_table_t soc_gpio_pull_table[] = {
	{ GPIO_PB(27), GPIO_PULL_UP },
};
```

The diagnostic image was tested with two 200 ms pulses and one 1000 ms pulse;
none produced an audible chime. The original kernel was restored and verified.
Those tests captured the early kernel setup message but not the pull register
after Wi-Fi initialization, so they must not be treated as equivalent to the
late stock `app_init.sh` write.

## Direct-register chime diagnostic

`vdb2-stock-chime-direct.c` is the final bench discriminator. It bypasses
sysfs and the shell and writes the T31 GPIO-B set/clear aliases directly. Its
`init` and `ring` paths reproduce the stock descriptor order, GPIO51 input
mode, post-export pull state, 1.5 second arming delay, 30 ms supply-stage
delays, trigger pulse, and one-second release delay. Each edge is timestamped
and checked against the physical PIN register. Register captures include mux,
pull, I/O-domain, drive-strength, slew-rate, and Schmitt state.

The binary is diagnostic-only and is not installed by the package. Build it
with the VDB2 cross compiler and stage it in `/opt`. `status` is read-only;
`ring` has an explicit live-test interlock:

```sh
/opt/vdb2-stock-chime-direct status
/opt/vdb2-stock-chime-direct init
VDB2_CHIME_LIVE=I_UNDERSTAND /opt/vdb2-stock-chime-direct ring 200
/opt/vdb2-stock-chime-direct off
```

Use the normal device smoke capture and mandatory reboot around any live ring.
