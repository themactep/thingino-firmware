# Changelog

please refer to https://github.com/themactep/thingino-firmware/activity

## Unreleased

- thingino-button / kernel 3.10: a lost key release can no longer arm the
  20 s factory reset. XBurst1 GPIO both-edge emulation re-arms until the pin
  level is stable, gpio-keys re-checks a pressed key every 50 ms, and
  thingino-button drops holds the kernel no longer reports and measures
  holds with the monotonic clock. S15thingino-button records the real pid
  (`-s` instead of `-d`) and `stop`/`restart` no longer leave a daemon
  behind. See docs/thingino/reset-button.md.
