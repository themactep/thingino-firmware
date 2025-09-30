Thingino
--------

Thingino (_/θinˈdʒiːno/_, _thin-jee-no_) is an open-source firmware for Ingenic SoC IP cameras.

![Thingino Web UI][10]

### Supported Hardware

Please find [the full list of supported cameras](docs/supported_hardware.md)
in a separate document. Visit [our website][0] for an illustrated version of
the list.

---

### Thingino Repository Branches Explaned

We've split the Thingino repository into two branches: stable and master, to better manage development and provide reliable releases for users.

**Stable Branch**

Provides a reliable, tested version of Thingino for general use. It includes carefully selected, stable changes. It uses the original ONVIF server and Prudynt with libconfig.
The stable branch will receive critical fixes. New features will only be added once they are thoroughly tested and mature in the master branch.

For users who want a dependable version of Thingino without needing to build or contribute to development.

**Master Branch**

The development hub for new features and experimental changes. Includes advanced features like Matroska, Opus, and improved file recording for Prudynt. These are still in development and may not be stable.

Only for developers and contributors who can build the project themselves and actively participate in improving the code.

This structure allows us to maintain a reliable version (stable) for most users while continuing to innovate and test new features (master). Critical fixes and matured features from master will be gradually integrated into stable for broader use.

> [!NOTE]
> If you’re not contributing to development, we recommend sticking with the stable branch.

Thank you for using Thingino! For questions or contributions, please join our Discord community or check the GitHub issues page.

### Building

```
git clone --recurse-submodules https://github.com/themactep/thingino-firmware
cd thingino-firmware
make
```

Read [Building from sources][7] article for more info.

### Resources

- [Project Website][0]
- [Project Wiki][1]
- Buildroot Manual [HTML][5] [PDF][6]
- [Discord channel][3]
- [Telegram group][4]

### GitHub CI Status

[![toolchain-x86_64][11]][8]
[![firmware-x86_64][12]][9]

[0]: https://thingino.com/
[1]: https://github.com/themactep/thingino-firmware/wiki
[3]: https://discord.gg/xDmqS944zr
[4]: https://t.me/thingino
[5]: https://buildroot.org/downloads/manual/manual.html
[6]: https://nightly.buildroot.org/manual.pdf
[7]: https://github.com/themactep/thingino-firmware/wiki/Building-from-sources
[8]: https://github.com/themactep/thingino-firmware/actions/workflows/toolchain.yaml
[9]: https://github.com/themactep/thingino-firmware/actions/workflows/firmware.yaml
[10]: https://github.com/user-attachments/assets/6fe68e13-eb49-4c33-8836-af1e97bf8b4e
[11]: https://github.com/themactep/thingino-firmware/actions/workflows/toolchain-x86_64.yaml/badge.svg
[12]: https://github.com/themactep/thingino-firmware/actions/workflows/firmware-stable.yaml/badge.svg
