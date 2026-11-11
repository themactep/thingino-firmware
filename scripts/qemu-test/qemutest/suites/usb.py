"""USB direct networking: the camera as an NCM gadget on a USB cable.

The QEMU fork's dwc2-ncm-host device plays the computer at the other end:
it enumerates the gadget through the emulated DWC2 controller and puts its
frames on a QEMU hub. A slirp netdev on that hub carries host TCP to the
camera and, in client mode, its DHCP; the usbpc module is a second host on
the hub that checks the camera's own DHCP and DNS servers in server mode.
"""

import re

from ..config import USB_HTTP_PORT, USB_PC_PORT, USB_PC_QEMU_PORT
from ..probes import until
from ..usbpc import UsbPC

USB_DIRECT_IP = "172.16.17.1"


def _usb0(ctx, timeout):
    """Wait for the gadget's carrier; returns `ip addr show usb0`."""
    guest = ctx.guest
    out = guest.run_until("cat /sys/class/net/usb0/carrier 2>&1",
                          lambda o: o.strip().endswith("1"), timeout, 2)
    carrier = out.strip().endswith("1")
    rc, addr = guest.run("ip -4 addr show usb0 2>&1")
    return carrier, addr


def _inet(out):
    m = re.search(r"inet \S+", out)
    return m.group(0) if m else out.strip()[:80]


def _host_state(ctx):
    if ctx.qmp is None:
        return None
    try:
        return ctx.qmp.cmd("qom-get", path="/machine/peripheral/usbhost",
                            property="state")
    except Exception:
        return None


def _http(port):
    import urllib.request
    try:
        r = urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=10)
        return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return None


def test_usb_direct(ctx):
    """Server mode: the camera is 172.16.17.1 and hands out leases."""
    guest, res = ctx.guest, ctx.res

    rc, out = guest.run("lsmod 2>&1")
    res.check("usb_g_ncm_loaded", "g_ncm" in out)

    carrier, addr = _usb0(ctx, 60)
    res.check("usb_host_enumerated", _host_state(ctx) == "running",
              f"host side: {_host_state(ctx)}")
    res.check("usb0_carrier", carrier)
    res.check("usb0_address", f"inet {USB_DIRECT_IP}/24" in addr,
              _inet(addr))

    rc, out = guest.run("ps w")
    res.check("usb_udhcpd_running", "udhcpd" in out)
    res.check("usb_dnsd_running", "dnsd" in out)

    # usb0's default route is a last resort: an uplink outranks it, and
    # with the cable as the only link it is where the camera's own
    # address comes from.
    rc, out = guest.run("ip -4 route show default")
    fallback = rf"via {re.escape(USB_DIRECT_IP)} dev usb0 .*metric 1000"
    res.check("usb_fallback_route", re.search(fallback, out) is not None,
              " / ".join(out.split("\n")).strip()[:120])
    rc, out = guest.run("ip -4 route get 1")
    if ctx.has("wired"):
        res.check("usb_uplink_wins", "dev eth0" in out, out.strip()[:80])
    else:
        res.check("usb_route_src", f"src {USB_DIRECT_IP}" in out,
                  out.strip()[:80])

    pc = UsbPC(USB_PC_PORT, USB_PC_QEMU_PORT)
    try:
        lease = pc.dhcp(USB_DIRECT_IP, timeout=30)
        res.check("usb_dhcp_lease", lease is not None and
                  lease["ip"].startswith("172.16.17."),
                  lease["ip"] if lease else f"no lease from {USB_DIRECT_IP}")
        if lease:
            res.check("usb_dhcp_dns_option", lease["dns"] == USB_DIRECT_IP,
                      f"dns {lease['dns']}")
            ips = pc.resolve("thingino.local", USB_DIRECT_IP,
                             lease["server_mac"])
            res.check("usb_dns_thingino_local", ips == [USB_DIRECT_IP],
                      f"answers {ips}")
    finally:
        pc.close()

    status = until(lambda: _http(USB_HTTP_PORT), 30, 2, ok=bool)
    res.check("usb_webui_http", status in (200, 301, 302, 401),
              f"HTTP {status} over USB")


def test_usb_direct_client(ctx):
    """Client mode: the camera leases its usb0 address from the host."""
    guest, res = ctx.guest, ctx.res

    rc, out = guest.run("lsmod 2>&1")
    res.check("usb_g_ncm_loaded", "g_ncm" in out)

    carrier, addr = _usb0(ctx, 60)
    res.check("usb_host_enumerated", _host_state(ctx) == "running",
              f"host side: {_host_state(ctx)}")
    res.check("usb0_carrier", carrier)

    out = guest.run_until("ip -4 addr show usb0 2>&1",
                          lambda o: "inet 10.0.3." in o, 60, 2)
    res.check("usb0_dhcp_lease", "inet 10.0.3." in out, _inet(out))

    status = until(lambda: _http(USB_HTTP_PORT), 30, 2, ok=bool)
    res.check("usb_webui_http", status in (200, 301, 302, 401),
              f"HTTP {status} over USB")
