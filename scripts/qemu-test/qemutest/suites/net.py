"""Wired networking against the tap lab, link flap and persistence."""

import re
import time
from ..launch import warm_reset_timer_wedge
from ..probes import until


def test_ethernet(ctx):
    guest, res = ctx.guest, ctx.res
    out = guest.run_until("ip addr show eth0", lambda o: "inet " in o, 45, 2)
    res.check("eth0_has_ip", "inet " in out, out.strip()[:80])

    rc, out = guest.run("ip route")
    res.check("default_route_exists", "default" in out)


def test_ethwifi_behavior(ctx):
    guest, res = ctx.guest, ctx.res
    """Wired takeover: S40wired-gateway stops the portal, kills wpa,
    and unloads the WLAN module once a wired uplink exists."""
    rc, out = guest.run("cat /run/portal_mode 2>&1")
    res.check("portal_mode_off", "No such file" in out)

    rc, out = guest.run("wpa_cli -i wlan0 status 2>&1")
    wifi_dead = ("INTERFACE_DISABLED" in out or "not found" in out.lower()
                 or "Failed" in out)
    res.check("wifi_stopped_by_ethernet", wifi_dead,
              "wired uplink should disable WiFi")

    rc, out = guest.run("lsmod")
    res.check("wifi_module_unloaded", "mac80211_hwsim" not in out,
              "wired-gateway rmmods the WLAN module")

    rc, out = guest.run("cat /proc/net/dev")
    res.check("wlan_ifaces_gone", "wlan0" not in out)


def get_guest_addrs(guest):
    """Return dict of guest eth0 addresses:
    v4 [addr], v6_ll [addr], v6_global [(addr, prefixlen)]."""
    addrs = {"v4": [], "v6_ll": [], "v6_global": []}
    rc, out = guest.run("ip addr show eth0")
    for m in re.finditer(r"inet (\d+\.\d+\.\d+\.\d+)/", out):
        addrs["v4"].append(m.group(1))
    for m in re.finditer(r"inet6 ([0-9a-f:]+)/(\d+) scope (\w+)", out):
        addr, plen, scope = m.groups()
        if scope == "link":
            addrs["v6_ll"].append(addr)
        elif scope == "global":
            addrs["v6_global"].append((addr, int(plen)))
    return addrs


def in_dhcpv6_range(addr):
    m = re.match(r"fd00:5c1::([0-9a-f]{1,4})$", addr)
    return bool(m and 0x100 <= int(m.group(1), 16) <= 0x1ff)


def test_ipv4_dhcp(ctx):
    guest, res, lab = ctx.guest, ctx.res, ctx.lab
    """DHCPv4 against the host dnsmasq."""
    def leased(a):
        return any(x.startswith("192.168.100.") for x in a["v4"])
    addrs = until(lambda: get_guest_addrs(guest), 60, 2, ok=leased)
    res.check("dhcp4_lease", leased(addrs),
              ", ".join(addrs["v4"]) if addrs["v4"] else "no v4 addr")

    rc, out = guest.run("ip -4 route")
    res.check("dhcp4_default_route", "default via 192.168.100.1" in out)
    res.check("dhcp4_wired_metric", bool(
        re.search(r"default via 192\.168\.100\.1 dev eth0\s+metric 100", out)),
        "wired metric 100")

    rc, out = guest.run("cat /etc/resolv.conf")
    res.check("dhcp4_dns_in_resolv", "192.168.100.1" in out)

    lease = lab.wait_lease(want_v4=True, timeout=10)
    res.check("dhcp4_server_lease", lease is not None,
              f"{lease['addr']} hostname={lease['hostname']}" if lease else "")
    ctx.guest_v4 = addrs["v4"][0] if addrs["v4"] else None


def test_ipv6(ctx):
    guest, res, lab = ctx.guest, ctx.res, ctx.lab
    """Link-local, DAD, SLAAC, DHCPv6, RDNSS."""
    addrs = until(lambda: get_guest_addrs(guest), 30, 2, ok=lambda a: a["v6_ll"])
    ll = addrs["v6_ll"][0] if addrs["v6_ll"] else None
    res.check("ipv6_lladdr", ll is not None, ll or "no fe80 on eth0")

    rc, out = guest.run("ip -6 addr show eth0")
    res.check("ipv6_dad_ok",
              "tentative" not in out and "dadfailed" not in out)

    if ll:
        res.check("ipv6_host_ping_ll", lab.ping(ll, v6=True, link_local=True),
                  f"ping {ll}%{lab.tap}")

    # SLAAC address: /64 from the RA prefix with a full interface id
    # (the DHCPv6 IA_NA lease is a /128 from the ::100-::1ff pool).
    def find_slaac(a):
        for x, plen in a["v6_global"]:
            if (x.startswith("fd00:5c1:") and plen == 64
                    and not in_dhcpv6_range(x)):
                return x
        return None
    slaac = find_slaac(until(lambda: get_guest_addrs(guest), 45, 2,
                             ok=find_slaac))
    res.check("ipv6_slaac_addr", slaac is not None,
              slaac or "no fd00:5c1: /64 addr (RA not processed?)")

    # RA-derived routes can lag by one advertisement interval; netlab
    # advertises every 10s, so wait comfortably past that.
    def ra_route(o):
        return bool(re.search(r"default via fe80::[0-9a-f:]+ dev eth0", o))
    got_route = ra_route(guest.run_until("ip -6 route", ra_route, 35, 3))
    res.check("ipv6_default_route", got_route, "default route from RA")

    if slaac:
        res.check("ipv6_host_ping_global", lab.ping(slaac, v6=True),
                  f"ping {slaac}")

    # Stateful DHCPv6: odhcp6c should be running and holding an address
    # from the dnsmasq IA_NA range (::100 - ::1ff, distinct from SLAAC).
    rc, out = guest.run("ps w | grep -v grep | grep odhcp6c")
    odhcp_running = "odhcp6c" in out
    res.check("odhcp6c_running", odhcp_running)

    def find_dhcp6(a):
        found = None
        for x, _plen in a["v6_global"]:
            if in_dhcpv6_range(x):
                found = x
        return found
    dhcp6_addr = find_dhcp6(until(lambda: get_guest_addrs(guest), 30, 2,
                                  ok=find_dhcp6))
    res.check("dhcpv6_stateful_addr", dhcp6_addr is not None,
              dhcp6_addr or "no IA_NA address from DHCPv6 range")

    rc, out = guest.run("cat /etc/resolv.conf")
    res.check("ipv6_dns_in_resolv", "fd00:5c1::1" in out,
              "DNS from DHCPv6/RDNSS")
    ctx.guest_v6 = slaac


def test_dns_and_pref(ctx):
    guest, res, lab = ctx.guest, ctx.res, ctx.lab
    # Explicit server query: the DHCP-provided DNS answers A records.
    # (Plain nslookup iterates every resolv.conf server including the
    # static public fallbacks, which have no route in the lab.)
    rc, out = guest.run("nslookup host.lab 192.168.100.1 2>&1", timeout=20)
    res.check("dns_a_lookup", out.count("192.168.100.1") >= 2,
              "" if out.count("192.168.100.1") >= 2 else out.strip()[:120])

    # libc resolver walks resolv.conf in order: first entry is the lab's
    # v6 server, so this passing proves the file ordering works.
    rc, out = guest.run("ping -4 -c 1 -W 2 host.lab 2>&1", timeout=10)
    res.check("dns_a_via_resolv", rc == 0,
              "A record resolves through resolv.conf order")

    rc, out = guest.run("ping -6 -c 1 -W 2 host.lab 2>&1", timeout=10)
    res.check("dns_aaaa_lookup", rc == 0 or "fd00:5c1::1" in out,
              "AAAA resolves and host reachable over v6")

    n_before = len(lab.http_echo.hits)
    rc, out = guest.run("curl -s http://host.lab:8080/", timeout=15)
    hit_fam = lab.http_echo.hits[-1][0] if len(lab.http_echo.hits) > n_before else None
    res.check("v6_preference", hit_fam == "v6",
              f"dual A/AAAA name connected over {hit_fam or 'nothing'}")


def test_dual_stack_listeners(ctx):
    guest, res = ctx.guest, ctx.res
    rc, out = guest.run("netstat -tln 2>/dev/null", timeout=15)
    res.check("http_listens_v6", ":::80" in out or "::80" in out.replace(" ", ""),
              "uhttpd should be dual-stack per IPv6-first policy")
    res.check("ssh_listens_v6", ":::22" in out)
    https = "0.0.0.0:443" in out or ":::443" in out
    res.check("https_listening", https)


def test_mdns(ctx):
    guest, res, lab, guest_v4 = ctx.guest, ctx.res, ctx.lab, ctx.guest_v4
    rc, hostname = guest.run("hostname")
    hostname = hostname.strip().split("\n")[-1].strip()
    if not hostname:
        res.fail("mdns_resolve_a", "could not read hostname")
        return

    # mdnsd re-probes (and goes silent for a few seconds) whenever an
    # address event fires, RA lifetime refreshes included. Real mDNS
    # clients retry; a dead responder still fails every attempt.
    def mq(name, rtype, tries=3):
        # same attempt count as before: tries attempts, 3s apart
        return until(lambda: lab.mdns_query(name, rtype),
                     (tries - 1) * 3, 3) or []

    a = mq(f"{hostname}.local", "A")
    res.check("mdns_resolve_a", guest_v4 in a,
              f"{hostname}.local -> {a}")
    aaaa = mq(f"{hostname}.local", "AAAA")
    res.check("mdns_resolve_aaaa", len(aaaa) > 0,
              f"{hostname}.local AAAA -> {aaaa}" if aaaa
              else "no AAAA (mdnsd v4-only?)")

    # DNS-SD: this mdnsd doesn't answer the _services._dns-sd._udp
    # meta-enumeration, so browse the concrete types S50mdnsd generates
    found = {}
    for stype in ("_http._tcp", "_thingino._tcp", "_rtsp._tcp",
                  "_rtsps._tcp"):
        insts = mq(f"{stype}.local", "PTR", tries=2)
        if insts:
            found[stype] = insts[0]
    res.check("mdns_service_browse",
              "_http._tcp" in found and "_thingino._tcp" in found,
              f"advertised: {sorted(found)}")
    res.check("mdns_rtsp_advertised",
              "_rtsp._tcp" in found or "_rtsps._tcp" in found,
              "streamer RTSP service in DNS-SD")

    instances = lab.mdns_query("_http._tcp.local", "PTR", timeout=4)
    if instances:
        srv = lab.mdns_query(instances[0], "SRV", timeout=4)
        res.check("mdns_http_srv",
                  any(s.startswith("80 ") and hostname in s for s in srv),
                  f"{instances[0]} SRV -> {srv}")
    else:
        res.fail("mdns_http_srv", "no _http._tcp instance answered")


def test_ntp(ctx):
    guest, res, lab = ctx.guest, ctx.res, ctx.lab
    before = lab.sntp.requests
    rc, out = guest.run("ntpd -n -q -p 192.168.100.1 2>&1", timeout=30)
    served = lab.sntp.requests > before
    res.check("ntp_query", served,
              f"{lab.sntp.requests - before} SNTP requests answered")
    rc, out = guest.run("date -u +%Y")
    year = out.strip().split("\n")[-1].strip()
    res.check("clock_sane", year.isdigit() and int(year) >= 2025,
              f"year={year}")


def test_syslog_remote(ctx):
    guest, res, lab = ctx.guest, ctx.res, ctx.lab
    """Point busybox syslogd at the host sink and verify delivery."""
    guest.run("killall syslogd 2>/dev/null; sleep 1; "
              "syslogd -R 192.168.100.1", timeout=10)
    guest.run_until("ps w", lambda o: "syslogd -R" in o, 10, 1)
    marker = f"qemu-test-syslog-{int(time.time())}"
    guest.run(f"logger {marker}")
    got = bool(until(lambda: any(marker in msg
                                 for _, msg in lab.syslog.messages), 10, 1))
    res.check("syslog_remote_delivery", got,
              f"{len(lab.syslog.messages)} messages received")
    guest.run("killall syslogd 2>/dev/null; /etc/init.d/S01syslogd start "
              ">/dev/null 2>&1", timeout=10)


def test_link_flap(ctx):
    guest, res, qmp = ctx.guest, ctx.res, ctx.qmp
    lab, guest_v4 = ctx.lab, ctx.guest_v4
    """Drop and restore the link via QMP. The GMAC model mirrors the
    backend link state into the PHY's BMSR, and the guest drivers poll
    the PHY, so carrier must follow within a few poll intervals."""
    qmp.set_link("n0", False)
    res.check("link_down_datapath", until(lambda: not lab.ping(guest_v4), 20, 1),
              "host ping must fail while link is down")
    # phylib polls the PHY every second of guest time, which can lag
    # wall time badly on loaded runners: poll instead of one shot.
    out = guest.run_until("cat /sys/class/net/eth0/carrier 2>&1",
                          lambda o: o.strip().endswith("0"), 20, 2, via="serial")
    res.check("link_down_carrier", out.strip().endswith("0"),
              "carrier must drop with the link")

    qmp.set_link("n0", True)
    res.check("link_up_datapath", bool(until(lambda: lab.ping(guest_v4), 60, 2)),
              "host ping works again")

    rc, out = guest.run("ip -4 addr show eth0", via="serial")
    res.check("link_flap_addr_kept", "192.168.100." in out)


def test_persist_reboot(ctx):
    """Overlay persistence: write markers, reboot, verify."""
    ser, guest, res, report_dir = ctx.ser, ctx.guest, ctx.res, ctx.report_dir
    timeout = max(ctx.args.timeout, 240)
    print("\n── Persistence reboot ──")
    marker = f"marker-{int(time.time())}"
    guest.run(f"touch /etc/qemu-test-marker && "
              f"jct /etc/thingino.json set qemutest {marker}",
              via="serial", timeout=15)
    guest.reboot()
    # login() refuses any prompt until the reset banner, so persistence is
    # asserted against the rebooted system and not the dying shell.
    if not ser.login(timeout):
        if warm_reset_timer_wedge(report_dir):
            res.xfail("persist_reboot_complete", False,
                      "QEMU warm-reset timer wedge (fork bug, "
                      "guest crawls after system reset)")
            res.skip("persist_file", "reboot did not complete")
            res.skip("persist_config", "reboot did not complete")
        else:
            res.fail("persist_reboot_complete",
                     "no login prompt after reboot")
        return
    res.ok("persist_reboot_complete")

    # Positive sentinel: a bare "not absent" check reads as success against
    # a U-Boot "syntax error" too, so confirm the file is really there.
    rc, out = guest.run("[ -f /etc/qemu-test-marker ] && echo MARKER_OK",
                        via="serial")
    res.check("persist_file", "MARKER_OK" in out)
    rc, out = guest.run("jct /etc/thingino.json get qemutest 2>&1",
                        via="serial")
    res.check("persist_config", marker in out)
    rc, out = guest.run("rm -f /etc/qemu-test-marker; "
                        "jct /etc/thingino.json del qemutest 2>&1",
                        via="serial")
