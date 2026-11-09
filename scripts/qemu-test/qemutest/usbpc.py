"""A computer on the far end of the camera's USB cable.

The QEMU fork's dwc2-ncm-host device enumerates the camera's NCM gadget and
hands its Ethernet frames to a netdev. Wired to a QEMU hub, that link can
carry several hosts at once; this module is one of them, reached through a
-netdev dgram socket (one UDP datagram per frame), so it needs no root.
It speaks just enough IPv4 to check what a laptop plugged into the camera
would get: ARP, a DHCP lease and DNS answers.
"""
import os
import random
import select
import socket
import struct
import time

BCAST = b"\xff" * 6
ETH_IP, ETH_ARP = 0x0800, 0x0806
DHCP_MAGIC = b"\x63\x82\x53\x63"


def _csum(data):
    if len(data) % 2:
        data += b"\0"
    s = sum(struct.unpack(f"!{len(data) // 2}H", data))
    s = (s >> 16) + (s & 0xffff)
    s += s >> 16
    return ~s & 0xffff


def _ip(a):
    return socket.inet_aton(a)


def _ipstr(b):
    return socket.inet_ntoa(b)


class UsbPC:
    def __init__(self, port, qemu_port, mac=None):
        """port: where this end listens; qemu_port: the dgram netdev's
        local port."""
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("127.0.0.1", port))
        self.peer = ("127.0.0.1", qemu_port)
        self.mac = mac or bytes([0x02, 0x50, 0x43]) + os.urandom(3)
        self.ip = None

    def close(self):
        self.sock.close()

    # Frames

    def _send(self, dst, ethertype, payload):
        frame = dst + self.mac + struct.pack("!H", ethertype) + payload
        self.sock.sendto(frame.ljust(60, b"\0"), self.peer)

    def _ipv4(self, src, dst, proto, payload):
        hdr = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(payload),
                          random.getrandbits(16), 0, 64, proto, 0,
                          _ip(src), _ip(dst))
        hdr = hdr[:10] + struct.pack("!H", _csum(hdr)) + hdr[12:]
        return hdr + payload

    def _udp(self, src, dst, sport, dport, data):
        # A zero checksum means none, which IPv4 allows.
        udp = struct.pack("!HHHH", sport, dport, 8 + len(data), 0) + data
        return self._ipv4(src, dst, 17, udp)

    def frames(self, timeout):
        """Yield (src_mac, ethertype, payload) until timeout, answering ARP
        for our address on the way."""
        deadline = time.time() + timeout
        while True:
            left = deadline - time.time()
            if left <= 0:
                return
            r, _, _ = select.select([self.sock], [], [], left)
            if not r:
                return
            frame, _ = self.sock.recvfrom(65536)
            if len(frame) < 14:
                continue
            dst, src = frame[:6], frame[6:12]
            ethertype = struct.unpack("!H", frame[12:14])[0]
            if dst not in (self.mac, BCAST) and not dst[0] & 1:
                continue
            payload = frame[14:]
            if ethertype == ETH_ARP:
                self._answer_arp(payload)
            yield src, ethertype, payload

    def _answer_arp(self, p):
        if len(p) < 28 or self.ip is None:
            return
        op = struct.unpack("!H", p[6:8])[0]
        sha, spa, tpa = p[8:14], p[14:18], p[24:28]
        if op == 1 and tpa == _ip(self.ip):
            reply = struct.pack("!HHBBH", 1, ETH_IP, 6, 4, 2) + \
                self.mac + tpa + sha + spa
            self._send(sha, ETH_ARP, reply)

    def _udp_in(self, timeout, dport):
        """Yield (src_mac, src_ip, sport, data) for UDP to dport."""
        for src, ethertype, p in self.frames(timeout):
            if ethertype != ETH_IP or len(p) < 28 or p[9] != 17:
                continue
            ihl = (p[0] & 0xf) * 4
            sport, port = struct.unpack("!HH", p[ihl:ihl + 4])
            if port == dport:
                yield src, _ipstr(p[12:16]), sport, p[ihl + 8:]

    # DHCP

    def _dhcp_packet(self, xid, msgtype, extra=b""):
        bootp = struct.pack("!BBBBIHH4s4s4s4s16s64s128s", 1, 1, 6, 0, xid, 0,
                            0x8000, b"\0" * 4, b"\0" * 4, b"\0" * 4,
                            b"\0" * 4, self.mac.ljust(16, b"\0"),
                            b"", b"")
        opts = bytes([53, 1, msgtype]) + extra + bytes([55, 4, 1, 3, 6, 15,
                                                         255])
        return self._udp("0.0.0.0", "255.255.255.255", 68, 67,
                         bootp + DHCP_MAGIC + opts)

    @staticmethod
    def _dhcp_parse(data, xid):
        if len(data) < 240 or data[0] != 2 or data[236:240] != DHCP_MAGIC:
            return None
        if struct.unpack("!I", data[4:8])[0] != xid:
            return None
        opts, i = {}, 240
        while i < len(data) and data[i] != 255:
            if data[i] == 0:
                i += 1
                continue
            if i + 1 >= len(data):
                break
            n = data[i + 1]
            opts[data[i]] = data[i + 2:i + 2 + n]
            i += 2 + n
        return _ipstr(data[16:20]), opts

    def dhcp(self, server, timeout=20):
        """Lease an address from the DHCP server at `server`, ignoring any
        other server on the link. Returns a dict, or None."""
        xid = random.getrandbits(32)
        deadline = time.time() + timeout
        offer = None
        while offer is None and time.time() < deadline:
            self._send(BCAST, ETH_IP, self._dhcp_packet(xid, 1))
            for src, sip, _, data in self._udp_in(3, 68):
                got = self._dhcp_parse(data, xid)
                if got and got[1].get(53) == b"\x02" and \
                        got[1].get(54) == _ip(server):
                    offer = (src, got)
                    break
        if offer is None:
            return None
        mac, (yiaddr, opts) = offer
        req = bytes([50, 4]) + _ip(yiaddr) + bytes([54, 4]) + _ip(server)
        while time.time() < deadline:
            self._send(BCAST, ETH_IP, self._dhcp_packet(xid, 3, req))
            for src, sip, _, data in self._udp_in(3, 68):
                got = self._dhcp_parse(data, xid)
                if not got or got[1].get(54) != _ip(server):
                    continue
                if got[1].get(53) == b"\x05":
                    self.ip = got[0]
                    o = got[1]
                    return {
                        "ip": got[0],
                        "server_mac": src,
                        "mask": _ipstr(o[1]) if 1 in o else None,
                        "router": _ipstr(o[3][:4]) if 3 in o else None,
                        "dns": _ipstr(o[6][:4]) if 6 in o else None,
                        "lease": struct.unpack("!I", o[51])[0]
                        if 51 in o else None,
                    }
                if got[1].get(53) == b"\x06":
                    return None
        return None

    # DNS

    def resolve(self, name, server, server_mac, timeout=10):
        """A records for name from the DNS server at server."""
        qid = random.getrandbits(16)
        q = b"".join(bytes([len(p)]) + p.encode() for p in name.split("."))
        query = struct.pack("!HHHHHH", qid, 0x0100, 1, 0, 0, 0) + q + \
            b"\0" + struct.pack("!HH", 1, 1)
        sport = random.randint(20000, 60000)
        deadline = time.time() + timeout
        while time.time() < deadline:
            self._send(server_mac, ETH_IP,
                       self._udp(self.ip, server, sport, 53, query))
            for _, sip, _, data in self._udp_in(2, sport):
                if len(data) < 12 or struct.unpack("!H", data[:2])[0] != qid:
                    continue
                return self._dns_answers(data)
        return None

    @staticmethod
    def _dns_answers(d):
        def skip_name(i):
            while i < len(d):
                n = d[i]
                if n == 0:
                    return i + 1
                if n & 0xc0 == 0xc0:
                    return i + 2
                i += 1 + n
            return i

        qd, an = struct.unpack("!HH", d[4:8])
        i = 12
        for _ in range(qd):
            i = skip_name(i) + 4
        ips = []
        for _ in range(an):
            i = skip_name(i)
            if i + 10 > len(d):
                break
            rtype, _, _, rdlen = struct.unpack("!HHIH", d[i:i + 10])
            i += 10
            if rtype == 1 and rdlen == 4:
                ips.append(_ipstr(d[i:i + 4]))
            i += rdlen
        return ips
