"""WiFi portal, provisioning and slirp host access."""

import re
from ..config import PORTAL_PORT, WEBUI_PORT
from ..launch import warm_reset_timer_wedge
from ..playwright import run_playwright
from ..probes import http_get, http_ok, until


def test_wifi_portal(ctx):
    guest, res = ctx.guest, ctx.res
    # The portal is deferred behind the wired-uplink probe and its radio
    # prescan, so it can trail login by tens of seconds. Wait for the AP.
    out = guest.run_until("wpa_cli -i wlan0 status 2>/dev/null",
                          lambda o: "mode=AP" in o, 120, 3)
    res.check("wifi_ap_mode", "mode=AP" in out)
    res.check("wifi_ssid_set", "ssid=THINGINO-" in out)

    rc, out = guest.run("ip addr show wlan0")
    res.check("wlan0_has_ip", "172.16.0.1" in out)

    # The portal-mode uhttpd restart trails the AP by several seconds
    out = guest.run_until(
        "curl -s -o /tmp/_portal -w '%{http_code}:%{size_download}' "
        "http://172.16.0.1/", lambda o: "200:" in o, 60, 3, timeout=15)
    res.check("portal_http_200", "200:" in out)
    m = re.search(r"200:(\d+)", out)
    portal_bytes = int(m.group(1)) if m else 0
    res.check("portal_serves_html", portal_bytes > 100, f"{portal_bytes} bytes")

    rc, out = guest.run("cat /run/portal_mode 2>&1")
    res.check("portal_mode_flag", "No such file" not in out)


def test_wifi_modules(ctx):
    guest, res = ctx.guest, ctx.res
    rc, out = guest.run("lsmod")
    res.check("hwsim_loaded", "mac80211_hwsim" in out)

    rc, out = guest.run("cat /proc/net/dev")
    res.check("wlan0_exists", "wlan0" in out)
    res.check("wlan1_exists", "wlan1" in out)


def test_wifi_bridge_setup(ctx):
    """Set up eth0 for SLIRP bridge (WiFi-only profile with GMAC driver)."""
    guest, res = ctx.guest, ctx.res
    guest.run("ip link set eth0 up", timeout=8)
    # The a1 xgmac model loses a few RX frames right after ifup, so give
    # the exchange more rounds than the udhcpc default.
    rc, out = guest.run("udhcpc -i eth0 -n -q -t 8 -T 3 2>&1", timeout=40)
    got_ip = "obtained" in out.lower() or "lease of" in out.lower()
    res.check("bridge_eth0_dhcp", got_ip)

    guest.run("echo 1 > /proc/sys/net/ipv4/ip_forward")
    rc, out = guest.run("cat /proc/sys/net/ipv4/ip_forward")
    res.check("bridge_ip_forward", "1" in out)


def test_provision_reboot_sta(ctx):
    """After portal submit: wait for reboot, set up fake AP, verify STA."""
    ser, guest, res = ctx.ser, ctx.guest, ctx.res
    report_dir, qmp = ctx.report_dir, ctx.qmp
    timeout = max(ctx.args.timeout, 240)
    print("\n── Post-provision reboot ──")
    print("  Waiting for guest reboot...")
    # Drop the SLIRP link for the STA boot: the qemu profile has a GMAC
    # that real WiFi-only cameras lack, and an instant SLIRP lease on
    # eth0 makes S40wired-gateway kill WiFi as "wired uplink present".
    if qmp:
        qmp.set_link("n0", False)
    # The portal reboots the camera itself; refuse any prompt until the
    # reset banner so the dying pre-reboot shell cannot pass as the new one.
    guest.expect_reboot()
    # Provisioning set the root password (playwright fills TestPass1)
    if not ser.login(timeout, passwords=("TestPass1", "root")):
        if warm_reset_timer_wedge(report_dir):
            res.xfail("reboot_complete", False,
                      "QEMU warm-reset timer wedge (fork bug)")
        else:
            res.fail("reboot_complete", "no login prompt after reboot")
        if qmp:
            qmp.set_link("n0", True)
        return
    res.ok("reboot_complete")

    # With the debug=1 console there is no login step, so verify the
    # provisioned password against the shadow hash on the guest.
    rc, out = guest.run(
        "h=$(grep '^root:' /etc/shadow | cut -d: -f2); "
        "t=$(echo \"$h\" | cut -d'$' -f2); "
        "s=$(echo \"$h\" | cut -d'$' -f3); "
        "case \"$t\" in 1) m=md5;; 5) m=sha256;; 6) m=sha512;; *) m='';; esac; "
        "if [ -n \"$m\" ] && "
        "[ \"$(mkpasswd -m $m -S \"$s\" TestPass1)\" = \"$h\" ]; "
        "then echo PWMATCH=yes; else echo PWMATCH=no; fi", timeout=15)
    res.check("provisioned_password_set", "PWMATCH=yes" in out,
              "root shadow hash matches provisioned password")

    rc, out = guest.run("hostname")
    res.check("saved_hostname", "qemu-test" in out,
              "provisioned hostname persisted")

    rc, out = guest.run("cat /etc/wpa_supplicant.conf 2>/dev/null")
    res.check("saved_wpa_conf", "TestNetwork" in out)

    print("  Seeding entropy from DTRNG...")
    guest.run("devmem 0x10072000 32 0x1")
    guest.run("for i in $(seq 1 20); do "
              "devmem 0x10072004 32 | sed 's/0x//' | "
              "xxd -r -p >> /dev/urandom; done", timeout=15)

    print("  Setting up fake AP on wlan1 (WPA-PSK)...")
    ser.cmd("cat > /tmp/fake_ap.conf << 'APEOF'\n"
            "ctrl_interface=/var/run/wpa_fakeap\n"
            "network={\n"
            '    ssid="TestNetwork"\n'
            "    mode=2\n"
            "    key_mgmt=WPA-PSK\n"
            '    psk="testpass123"\n'
            "    frequency=2437\n"
            "}\n"
            "APEOF")
    guest.run("wpa_supplicant -B -i wlan1 -c /tmp/fake_ap.conf", timeout=10)
    guest.run_until("wpa_cli -i wlan1 -p /var/run/wpa_fakeap status",
                    lambda o: "mode=AP" in o, 15, 2)
    guest.run("ip addr add 192.168.1.1/24 dev wlan1")

    rc, out = guest.run(
        "wpa_cli -i wlan1 -p /var/run/wpa_fakeap status | grep mode")
    res.check("fake_ap_running", "mode=AP" in out)

    # Thingino configures ap_scan=2 for vendor WiFi chips; hwsim's
    # nl80211 driver needs ap_scan=1 to scan and associate normally
    # (wpa itself warns about the combination at startup).
    guest.run("wpa_cli -i wlan0 ap_scan 1")
    print("  Triggering wlan0 rescan...")
    guest.run("wpa_cli -i wlan0 scan")
    guest.run_until("wpa_cli -i wlan0 scan_results",
                    lambda o: "TestNetwork" in o, 30, 3)

    attempts = []

    def sta_up():
        rc, out = guest.run("wpa_cli -i wlan0 status")
        if "wpa_state=COMPLETED" in out and "TestNetwork" in out:
            return True
        attempts.append(1)
        print(f"  Scan attempt {len(attempts)}...")
        guest.run("wpa_cli -i wlan0 scan")       # nudge, then look again
        return False
    connected = bool(until(sta_up, 70, 10))
    res.check("sta_connected_to_ap", connected,
              "wlan0 should connect to TestNetwork via WPA-PSK")

    if connected:
        guest.run("ip addr add 192.168.1.100/24 dev wlan0 2>/dev/null")
        rc, out = guest.run("ping -c 3 -W 2 192.168.1.1", timeout=15)
        res.check("sta_ping_ap",
                  "3 packets received" in out or "bytes from" in out)

    if qmp:
        qmp.set_link("n0", True)

    # The provisioned password must open the web UI. Re-bridge eth0 for
    # the slirp forward and drive the login form, capturing the login
    # screen and the logged-in page for the report.
    # Static bridge config: a fresh DHCP exchange after the reboot gets
    # the next slirp address, but the host forwards point at the slirp
    # default (10.0.2.15).
    guest.run("ip link set eth0 up", timeout=8)
    guest.run_until("cat /sys/class/net/eth0/carrier 2>&1",
                    lambda o: o.strip().endswith("1"), 10, 1)
    guest.run("ip addr flush dev eth0; ip addr add 10.0.2.15/24 dev eth0; "
              "ip route add default via 10.0.2.2 2>/dev/null; true",
              timeout=10)
    # The MAC is regenerated every boot; one ping refreshes slirp's ARP
    # entry for 10.0.2.15, which otherwise points the host forwards at
    # the previous boot's MAC until it expires.
    guest.run("ping -c 1 -W 2 10.0.2.2", timeout=10)
    webui_up = until(lambda: http_ok(f"http://localhost:{WEBUI_PORT + 1}/", 3),
                     45, 2)
    res.check("webui_up_after_reboot", webui_up)
    if webui_up:
        run_playwright(res, report_dir, {
            "login": {"url": f"http://localhost:{WEBUI_PORT + 1}",
                      "password": "TestPass1"},
        }, check_name="webui_login_screens")


def test_host_portal_access(ctx):
    res = ctx.res
    # The forward to the guest AP settles a beat after the bridge comes up,
    # and a loaded TCG guest can miss a single window; the in-guest twin
    # (portal_http_200) already polls, so poll here too.
    status, body, err = until(
        lambda: http_get(f"http://localhost:{PORTAL_PORT}/", 5),
        60, 3, ok=lambda r: r[0] == 200)
    res.check("host_portal_reachable", status == 200,
              "" if status == 200 else err)
    res.check("host_portal_content",
              "Thingino" in body or "<!DOCTYPE" in body)
