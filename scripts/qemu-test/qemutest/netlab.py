"""
Host-side network lab for QEMU tap-mode testing.

Creates a tap interface with dual-stack addressing, runs dnsmasq as the
DHCPv4 + RA/SLAAC + stateful DHCPv6 + DNS server, and hosts small test
listeners (SNTP, syslog, family-echo HTTP). Also provides host-side
probes: ping6, WS-Discovery, mDNS.

Requires root. Runs inside a private network namespace (see
enter_netns), so the host's :53/:123/:514 and any system resolver are
never touched, and several runs can share one host.
"""

import os
import socket
import struct
import subprocess
import sys
import threading
import time

V4_HOST = "192.168.100.1"
V4_PLEN = 24
V4_RANGE = ("192.168.100.50", "192.168.100.150")
V6_PREFIX = "fd00:5c1::"
V6_HOST = "fd00:5c1::1"
V6_RANGE = ("fd00:5c1::100", "fd00:5c1::1ff")
DNS_NAME = "host.lab"
HTTP_ECHO_PORT = 8080
NTP_EPOCH_OFFSET = 2208988800


def run(cmd, check=True):
    return subprocess.run(cmd, shell=True, check=check,
                          capture_output=True, text=True)


NETNS_ENV = "QEMUTEST_NETNS"


def reap_stale_netns():
    """Remove qt-* namespaces whose owning harness is gone. A killed run
    leaves its qemu and dnsmasq alive in there, burning CPU; they cannot
    block a new run (different namespace) but there is no reason to keep
    them."""
    for line in run("ip netns list", check=False).stdout.split("\n"):
        name = line.split()[0] if line.strip() else ""
        if not name.startswith("qt-"):
            continue
        pid = name[3:]
        if pid.isdigit() and os.path.exists(f"/proc/{pid}"):
            continue                                # a live run owns it
        pids = run(f"ip netns pids {name}", check=False).stdout.split()
        for p in pids:
            run(f"kill -9 {p}", check=False)
        run(f"ip netns del {name}", check=False)
        print(f"  (netlab: reaped stale namespace {name}, {len(pids)} procs)")


def enter_netns():
    """Re-exec this process inside a private network namespace named
    after its pid (exec keeps the pid, so the name stays meaningful).

    Everything the run spawns afterwards, qemu's tap, dnsmasq, the
    listeners, ssh, the browser, inherits the namespace. Returns at once
    when already inside, which the env marker records."""
    if os.environ.get(NETNS_ENV):
        return
    reap_stale_netns()
    name = f"qt-{os.getpid()}"
    run(f"ip netns add {name}")
    run(f"ip netns exec {name} ip link set lo up")
    env = dict(os.environ, **{NETNS_ENV: name})
    os.execvpe("ip", ["ip", "netns", "exec", name, sys.executable, *sys.argv],
               env)


class SntpServer(threading.Thread):
    """Minimal SNTP (mode 3 -> mode 4) responder."""

    def __init__(self, bind_addr):
        super().__init__(daemon=True)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((bind_addr, 123))
        self.sock.settimeout(0.5)
        self.requests = 0
        self._stop = False

    def run(self):
        while not self._stop:
            try:
                data, peer = self.sock.recvfrom(512)
            except socket.timeout:
                continue
            except OSError:
                break
            if len(data) < 48:
                continue
            self.requests += 1
            now = time.time() + NTP_EPOCH_OFFSET
            sec = int(now)
            frac = int((now - sec) * 2**32)
            reply = bytearray(48)
            reply[0] = 0x1C          # LI=0 VN=3 Mode=4 (server)
            reply[1] = 2             # stratum
            reply[2] = data[2]       # poll
            reply[3] = 0xEC          # precision
            reply[12:16] = b"LOCL"
            ts = struct.pack("!II", sec, frac)
            reply[16:24] = ts        # reference
            reply[24:32] = data[40:48]  # originate = client transmit
            reply[32:40] = ts        # receive
            reply[40:48] = ts        # transmit
            try:
                self.sock.sendto(bytes(reply), peer)
            except OSError:
                pass

    def stop(self):
        self._stop = True
        try:
            self.sock.close()
        except OSError:
            pass


class SyslogServer(threading.Thread):
    """UDP syslog sink, dual stack."""

    def __init__(self):
        super().__init__(daemon=True)
        self.sock = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        self.sock.bind(("::", 514))
        self.sock.settimeout(0.5)
        self.messages = []
        self._stop = False

    def run(self):
        while not self._stop:
            try:
                data, peer = self.sock.recvfrom(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            self.messages.append((peer[0], data.decode(errors="replace")))

    def stop(self):
        self._stop = True
        try:
            self.sock.close()
        except OSError:
            pass


class FamilyEchoHttp(threading.Thread):
    """Dual-stack HTTP listener that records the peer address family of
    every request and answers with it. Used to verify the guest prefers
    IPv6 when a name has both A and AAAA records."""

    def __init__(self, port=HTTP_ECHO_PORT):
        super().__init__(daemon=True)
        self.sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        self.sock.bind(("::", port))
        self.sock.listen(4)
        self.sock.settimeout(0.5)
        self.hits = []   # list of ("v4"|"v6", addr)
        self._stop = False

    def run(self):
        while not self._stop:
            try:
                conn, peer = self.sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            addr = peer[0]
            fam = "v4" if addr.startswith("::ffff:") else "v6"
            self.hits.append((fam, addr))
            try:
                conn.settimeout(2)
                conn.recv(2048)
                body = f"family={fam}\n"
                conn.sendall(
                    ("HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\n"
                     f"Content-Length: {len(body)}\r\n\r\n{body}").encode())
            except OSError:
                pass
            finally:
                conn.close()

    def stop(self):
        self._stop = True
        try:
            self.sock.close()
        except OSError:
            pass


class NetLab:
    def __init__(self, report_dir, tap="qtap0"):
        self.report_dir = report_dir
        self.tap = tap
        self.dnsmasq = None
        self.sntp = None
        self.syslog = None
        self.http_echo = None
        self.leases_path = os.path.join(report_dir, "dnsmasq.leases")

    def up(self):
        if os.geteuid() != 0:
            raise RuntimeError("tap mode requires root")
        if not os.environ.get(NETNS_ENV):
            raise RuntimeError("the tap lab must run inside its namespace "
                               "(driver calls enter_netns first)")
        run(f"ip link del {self.tap}", check=False)
        run(f"ip tuntap add dev {self.tap} mode tap")
        run(f"ip addr add {V4_HOST}/{V4_PLEN} dev {self.tap}")
        run(f"ip addr add {V6_HOST}/64 dev {self.tap}")
        run(f"ip link set {self.tap} up")
        # dnsmasq (bind-interfaces) can only bind fd00:5c1::1 once DAD
        # has finished on it
        deadline = time.time() + 5
        while time.time() < deadline:
            out = run(f"ip -6 addr show dev {self.tap}", check=False).stdout
            if "tentative" not in out:
                break
            time.sleep(0.3)

        conf_path = os.path.join(self.report_dir, "dnsmasq.conf")
        log_path = os.path.join(self.report_dir, "dnsmasq.log")
        with open(conf_path, "w") as f:
            f.write(f"""\
interface={self.tap}
bind-interfaces
port=53
no-resolv
no-hosts
domain=lab
local=/lab/
host-record={DNS_NAME},{V4_HOST},{V6_HOST}
dhcp-authoritative
dhcp-leasefile={self.leases_path}
# 30m lease: a 2m lease makes udhcpc renew every ~60s, and each renew
# re-asserts the address, which sends mdnsd into a re-probe (mute for
# seconds). Suites whose mDNS phase lands on that window see no answers.
dhcp-range={V4_RANGE[0]},{V4_RANGE[1]},255.255.255.0,30m
dhcp-option=option:router,{V4_HOST}
dhcp-option=option:dns-server,{V4_HOST}
dhcp-option=option:ntp-server,{V4_HOST}
enable-ra
# Long leases: every renew re-applies addresses and sends mdnsd into
# a re-probe (mute for seconds), eating whichever phase it lands on.
# Without ra-param
# dnsmasq derives the RA router lifetime from it too, and the guest's
# default route then expires between unsolicited RAs. Advertise every
# 10s with a 600s router lifetime: short enough that the guest installs
# the RA default route well inside the harness poll window (a 30s
# interval could exceed it), long lifetime so the route never expires
# between RAs.
ra-param={self.tap},10,600
dhcp-range={V6_RANGE[0]},{V6_RANGE[1]},slaac,64,30m
dhcp-option=option6:dns-server,[{V6_HOST}]
log-dhcp
log-queries
log-facility={log_path}
""")
        dm_err = open(log_path, "a")
        self.dnsmasq = subprocess.Popen(
            ["dnsmasq", "--conf-file=" + conf_path, "--no-daemon"],
            stdout=dm_err, stderr=dm_err)
        time.sleep(0.5)
        if self.dnsmasq.poll() is not None:
            raise RuntimeError(f"dnsmasq exited {self.dnsmasq.returncode}, "
                               f"see {log_path}")

        self.sntp = SntpServer(V4_HOST)
        self.sntp.start()
        self.syslog = SyslogServer()
        self.syslog.start()
        self.http_echo = FamilyEchoHttp()
        self.http_echo.start()

    def down(self):
        for t in (self.sntp, self.syslog, self.http_echo):
            if t:
                t.stop()
        if self.dnsmasq and self.dnsmasq.poll() is None:
            self.dnsmasq.terminate()
            try:
                self.dnsmasq.wait(5)
            except subprocess.TimeoutExpired:
                self.dnsmasq.kill()
        run(f"ip link del {self.tap}", check=False)
        # We are inside the namespace, and `ip netns exec` gave this process
        # a private mount namespace: unmounting the name from in here only
        # changes our own view and the host entry survives. Delete it from
        # the host's mount namespace; the kernel frees the namespace itself
        # once the last process (this one) leaves.
        run(f"nsenter --mount=/proc/1/ns/mnt ip netns del {os.environ[NETNS_ENV]}",
            check=False)

    # ── host-side probes ─────────────────────────────────────

    def leases(self):
        """Parse dnsmasq lease file -> list of dicts."""
        out = []
        try:
            with open(self.leases_path) as f:
                for line in f:
                    parts = line.split()
                    if len(parts) >= 4:
                        out.append({"expiry": parts[0], "mac": parts[1],
                                    "addr": parts[2], "hostname": parts[3]})
        except FileNotFoundError:
            pass
        return out

    def wait_lease(self, want_v4=True, timeout=60):
        deadline = time.time() + timeout
        while time.time() < deadline:
            for l in self.leases():
                is_v4 = "." in l["addr"]
                if is_v4 == want_v4:
                    return l
            time.sleep(1)
        return None

    def ping(self, addr, v6=False, link_local=False):
        target = addr
        if link_local:
            target = f"{addr}%{self.tap}"
        cmd = f"ping {'-6' if v6 else '-4'} -c 2 -W 2 {target}"
        return run(cmd, check=False).returncode == 0

    def ws_discovery_probe(self, timeout=3.0):
        """Send a WS-Discovery Probe, return list of raw XML responses."""
        probe = """<?xml version="1.0" encoding="UTF-8"?>
<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"
 xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing"
 xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"
 xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
<e:Header>
<w:MessageID>uuid:84ede3de-7dec-11d0-c360-f01234567890</w:MessageID>
<w:To e:mustUnderstand="true">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>
<w:Action e:mustUnderstand="true">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>
</e:Header>
<e:Body>
<d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe>
</e:Body>
</e:Envelope>"""
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF,
                        socket.inet_aton(V4_HOST))
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
        sock.settimeout(0.5)
        sock.sendto(probe.encode(), ("239.255.255.250", 3702))
        replies = []
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                data, _ = sock.recvfrom(65535)
                replies.append(data.decode(errors="replace"))
            except socket.timeout:
                continue
        sock.close()
        return replies

    def mdns_query(self, name, rtype="A", timeout=3.0, collect_all=False):
        """Minimal mDNS query (legacy unicast response path).
        Returns rdata strings: A/AAAA -> address, PTR -> target name,
        SRV -> 'port target'. collect_all keeps listening for the whole
        timeout (service enumeration spans multiple answers)."""
        qtype = {"A": 1, "AAAA": 28, "PTR": 12, "SRV": 33}[rtype]
        pkt = struct.pack("!HHHHHH", 0, 0, 1, 0, 0, 0)
        for label in name.strip(".").split("."):
            pkt += bytes([len(label)]) + label.encode()
        pkt += b"\x00" + struct.pack("!HH", qtype, 1)

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((V4_HOST, 0))
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF,
                        socket.inet_aton(V4_HOST))
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
        sock.settimeout(0.5)
        sock.sendto(pkt, ("224.0.0.251", 5353))

        results = []
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                data, _ = sock.recvfrom(65535)
            except socket.timeout:
                continue
            results.extend(self._parse_dns_answers(data, qtype))
            if results and not collect_all:
                break
        sock.close()
        return sorted(set(results)) if collect_all else results

    @staticmethod
    def _parse_dns_answers(data, want_qtype):
        def decode_name(o, depth=0):
            labels = []
            while o < len(data) and depth < 16:
                ln = data[o]
                if ln == 0:
                    return ".".join(labels), o + 1
                if ln & 0xC0 == 0xC0:
                    ptr = struct.unpack("!H", data[o:o + 2])[0] & 0x3FFF
                    tail, _ = decode_name(ptr, depth + 1)
                    labels.append(tail)
                    return ".".join(labels), o + 2
                labels.append(data[o + 1:o + 1 + ln].decode(errors="replace"))
                o += 1 + ln
            return ".".join(labels), o

        try:
            _, _, qd, an, _, _ = struct.unpack("!HHHHHH", data[:12])
            off = 12
            for _ in range(qd):
                _, off = decode_name(off)
                off += 4
            out = []
            for _ in range(an):
                _, off = decode_name(off)
                rtype, _, _, rdlen = struct.unpack("!HHIH", data[off:off + 10])
                off += 10
                rdata_off = off
                off += rdlen
                if rtype != want_qtype:
                    continue
                if rtype == 1 and rdlen == 4:
                    out.append(socket.inet_ntoa(data[rdata_off:off]))
                elif rtype == 28 and rdlen == 16:
                    out.append(socket.inet_ntop(socket.AF_INET6,
                                                data[rdata_off:off]))
                elif rtype == 12:                      # PTR
                    tgt, _ = decode_name(rdata_off)
                    out.append(tgt)
                elif rtype == 33:                      # SRV
                    _, _, port = struct.unpack(
                        "!HHH", data[rdata_off:rdata_off + 6])
                    tgt, _ = decode_name(rdata_off + 6)
                    out.append(f"{port} {tgt}")
            return out
        except (struct.error, IndexError):
            return []
