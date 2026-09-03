"""ONVIF over SOAP with the streamer's own credentials."""

import json
import os
import re


def streamer_auth(guest):
    """SOAP creds the way the ONVIF server resolves them (conf.c
    load_streamer_auth): the installed streamer's own RTSP auth, first
    existing config wins; the pre-03e8595 onvif.json copy is only a
    legacy fallback. Returns (user, password, source)."""

    def nested(conf, dotted):
        node = conf
        for part in dotted.split("."):
            node = node.get(part) if isinstance(node, dict) else None
        return node if isinstance(node, str) and node else None

    def from_json(out, user_keys, pass_keys):
        try:
            conf = json.loads(out[out.index("{"):out.rindex("}") + 1])
        except ValueError:
            return None, None
        user = pw = None
        for k in user_keys:
            user = user or nested(conf, k)
        for k in pass_keys:
            pw = pw or nested(conf, k)
        return user, pw

    def flat_value(text, key):
        # Mirror the server's flat-file parser: first matching key wins,
        # an inline '#' comment counts only after whitespace, and one
        # level of quotes is removed.
        for line in text.splitlines():
            m = re.match(r"\s*" + re.escape(key) + r"\s*=\s*(.*)$", line)
            if not m:
                continue
            val = re.sub(r"\s+#.*$", "", m.group(1)).rstrip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                val = val[1:-1]
            return val or None
        return None

    def cmd_value(cmd):
        rc, out = guest.run(cmd)
        for line in out.splitlines():
            line = line.strip()
            if line and "raptorctl" not in line:
                return line
        return None

    sources = [
        ("/etc/prudynt.json", "prudynt"),
        ("/etc/streamer.d/rtsp.json", "strero"),
        ("/etc/timps.conf", "timps"),
        ("/etc/raptor.conf", "raptor"),
        ("/etc/onvif.json", "onvif.json"),
    ]
    for path, kind in sources:
        rc, out = guest.run(f"[ -r {path} ] && echo CREDSRC || true")
        if "CREDSRC" not in out:
            continue
        if kind == "prudynt":
            rc, out = guest.run(f"cat {path}")
            user, pw = from_json(out, ["rtsp.username"], ["rtsp.password"])
        elif kind == "strero":
            rc, out = guest.run(f"cat {path}")
            user, pw = from_json(
                out, ["username", "auth.username", "rtsp.username"],
                ["password", "auth.password", "rtsp.password"])
        elif kind == "timps":
            rc, out = guest.run(f"cat {path}")
            user = flat_value(out, "rtsp.user")
            pw = flat_value(out, "rtsp.pass")
        elif kind == "raptor":
            user = cmd_value("raptorctl config get rtsp username")
            pw = cmd_value("raptorctl config get rtsp password")
        else:
            rc, out = guest.run(f"cat {path}")
            user, pw = from_json(out, ["server.username"],
                                 ["server.password"])
        # Like the server: the first existing config decides, even if it
        # holds no creds (the server then requires no auth either).
        return user, pw, kind
    return None, None, "none"


def test_onvif(ctx):
    guest, res, lab = ctx.guest, ctx.res, ctx.lab
    guest_v4, report_dir = ctx.guest_v4, ctx.report_dir
    from ..onvif_client import OnvifDevice, xml_tag

    def dump(name, status, text):
        with open(os.path.join(report_dir, f"onvif-{name}.xml"), "w") as f:
            f.write(f"<!-- HTTP {status} -->\n{text}")

    out = guest.run_until("ps w | grep -v grep | grep wsd_simple_server",
                          lambda o: "wsd_simple_server" in o, 60, 3)
    res.check("onvif_wsd_running", "wsd_simple_server" in out)

    replies = lab.ws_discovery_probe()
    match = [r for r in replies if "NetworkVideoTransmitter" in r
             or "XAddrs" in r]
    xaddrs = xml_tag(match[0], "XAddrs") if match else None
    res.check("onvif_ws_discovery", bool(match),
              xaddrs or f"{len(replies)} multicast replies")

    user, password, cred_src = streamer_auth(guest)

    dev = OnvifDevice(guest_v4, user=user, password=password or "")

    status, text = dev.get_system_date_and_time()
    dump("datetime", status, text)
    year = xml_tag(text, "Year")
    res.check("onvif_datetime", status == 200 and year is not None,
              f"year={year}")

    status, text = dev.get_device_information()
    dump("device-info", status, text)
    mfr = xml_tag(text, "Manufacturer")
    fw = xml_tag(text, "FirmwareVersion")
    res.check("onvif_device_info", status == 200 and mfr is not None,
              f"{mfr} fw={fw} creds={cred_src}" if mfr
              else f"HTTP {status} (creds={cred_src}): {text[:110]}")

    status, text = dev.get_capabilities()
    dump("capabilities", status, text)
    media_xaddr = None
    m = re.search(r"<(?:[\w.-]+:)?Media>.*?<(?:[\w.-]+:)?XAddr>(.*?)<",
                  text, re.DOTALL)
    if m:
        media_xaddr = m.group(1).strip()
    res.check("onvif_capabilities", status == 200 and media_xaddr is not None,
              media_xaddr or f"HTTP {status}: {text[:120]}")

    if media_xaddr:
        dev.media_url = media_xaddr

    status, text = dev.get_profiles()
    dump("profiles", status, text)
    tokens = re.findall(r"<(?:[\w.-]+:)?Profiles[^>]*?token=\"([^\"]+)\"", text)
    res.check("onvif_media_profiles", status == 200 and len(tokens) > 0,
              f"{len(tokens)} profiles: {tokens[:4]}" if tokens
              else f"HTTP {status}: {text[:120]}")

    if tokens:
        status, text = dev.get_stream_uri(tokens[0])
        dump("stream-uri", status, text)
        uri = xml_tag(text, "Uri") or ""
        res.check("onvif_stream_uri",
                  status == 200 and
                  bool(re.match(r"rtsps?://[^/:]+(:\d+)?/", uri)),
                  uri or f"HTTP {status}")

        status, text = dev.get_snapshot_uri(tokens[0])
        dump("snapshot-uri", status, text)
        uri = xml_tag(text, "Uri") or ""
        res.check("onvif_snapshot_uri",
                  status == 200 and
                  bool(re.match(r"https?://[^/]+/", uri)),
                  uri or f"HTTP {status}")
