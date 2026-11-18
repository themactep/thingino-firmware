# Jooan C9TS: video missing after reboot

## Diagnosis (2026-11-18)

Wi-Fi reconnects, Prudynt remains running, but RTSP has no video subsession.
`/proc/jz/isp/isp-fs` reports zero queued/output buffers and the kernel logs:

```text
qbuf: invalid memory size, length = 3133440 sizeimage = 0
```

Exposure stays at zero. This is capture initialization failure, not an RTSP
password, browser, or Wi-Fi association failure.

The T23 whole-ISP bypass setter is not an idempotent switch. In the tested
Ingenic 1.3.0 library it stops streaming, destroys the sensor's existing links,
sets the bypass control, recreates links, and starts streaming. Passing false
selects link configuration 1; sensor enable initially selected configuration 0.
Calling it late in startup with false left NV12 format size uninitialized.
The Chinese T23 SDK header also requires the ISP to be closed for this API.

## Permanent source fix

[The Prudynt package patch](../../package/prudynt-t/0001-t23-preserve-normal-isp-links-during-startup.patch)
retains the links already established by sensor enable when T23 is configured
with `image.isp_bypass=false`. Other platforms and explicit true requests retain
their existing behavior; explicit bypass output has not been validated here.
Keep the [camera override](../../configs/cameras/jooan_c9ts_t23n_sc2336p_skw6316/prudynt.json)
at false for normal processed video.

Changing `image.isp_bypass` through `prudyntctl json` is not a runtime fix in the
tested binary: that field is not handled by its image JSON API. Merely restarting
the process after the bad call can retain the broken kernel state. Reset the
ISP/sensor modules or reboot when testing the corrected executable.

## Validation record

- Same original executable/configuration and module parameters, with only the
  late setter skipped in a temporary process after ISP/sensor module reload:
  RTSP video returned, queue count became 2, buffer counters advanced, and sensor
  integration became 300 lines. FFmpeg decoded 59 frames at 1920x1080/15 fps.
- B&W capture had real two-dimensional image detail. For a color comparison,
  switch both software mode and the optical/IR state with the day/night helper;
  software Day mode with the IR LED still on is not a valid color test.
- The temporary preload library was a diagnostic only, not a boot solution.
- The package was rebuilt from its pinned source, and the patch applied during
  the normal Buildroot extraction/patch stage.
- The rebuilt executable was installed by replacing only the rootfs binary;
  kernel and extra partitions were unchanged. The user reported advancing
  buffer counters (647/646) and successful decoding after a normal reboot.
- After a physical power cycle, capture initially worked, then stopped with
  each of the two buffers reporting 256 queues/dequeues. The user subsequently
  reported working video. The startup fix is verified; the cause of that
  temporary stall has not been established, and continuous cold-boot operation
  still needs observation.

## PTZ elevation direction

The [motor profile](../../configs/cameras/jooan_c9ts_t23n_sc2336p_skw6316/motors.json)
uses GPIO motors (`is_spi=false`). Tilt must use the reversed phase order
`51 54 52 53`, while pan uses `53 52 54 51`. Giving both axes the pan order
reverses the intended elevation direction.

The current motor startup script only passes `invert_y` to SPI drivers, so
changing that flag does not correct this camera. Preserve the reversed tilt
phase order when copying the profile to an existing camera. Applying it to a
running camera requires reloading the motor module or rebooting; restarting
the service alone retains an already loaded module's phase parameters.

## Deployment constraints

The tested camera has an 8 MiB flash with a 256 KiB writable configuration
partition. Only 32 KiB was free, insufficient for a replacement 1.7 MiB
executable. A firmware update is needed for persistence; do not install a RAM
preload hook or depend on an SD-card executable as the final fix.

Preserve the bootloader, environment, network credentials, and configuration.
Back up and verify the existing firmware/configuration before any write, and
keep power connected throughout the update. Never flash an unverified payload.
