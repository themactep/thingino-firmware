"""
Minimal ONVIF SOAP client for harness assertions. No external deps.

Speaks just enough SOAP to exercise thingino-onvif (onvif_simple_server
CGI behind uhttpd): device information, capabilities, date/time, media
profiles, stream/snapshot URIs. Supports WS-UsernameToken digest auth.
"""

import base64
import hashlib
import os
import re
import time
import urllib.request

SOAP_ENV = """<?xml version="1.0" encoding="UTF-8"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"
 xmlns:tds="http://www.onvif.org/ver10/device/wsdl"
 xmlns:trt="http://www.onvif.org/ver10/media/wsdl"
 xmlns:tt="http://www.onvif.org/ver10/schema">
{header}
<s:Body>{body}</s:Body>
</s:Envelope>"""

SECURITY_HDR = """<s:Header>
<Security s:mustUnderstand="1"
 xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
<UsernameToken>
<Username>{user}</Username>
<Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">{digest}</Password>
<Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">{nonce}</Nonce>
<Created xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">{created}</Created>
</UsernameToken>
</Security>
</s:Header>"""


def _security_header(user, password):
    nonce = os.urandom(16)
    created = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    digest = base64.b64encode(
        hashlib.sha1(nonce + created.encode() + password.encode()).digest()
    ).decode()
    return SECURITY_HDR.format(user=user, digest=digest,
                               nonce=base64.b64encode(nonce).decode(),
                               created=created)


def soap_call(url, body, user=None, password=None, timeout=10):
    """POST a SOAP body, return (http_status, response_text)."""
    header = _security_header(user, password) if user else ""
    envelope = SOAP_ENV.format(header=header, body=body)
    req = urllib.request.Request(
        url, data=envelope.encode(),
        headers={"Content-Type": "application/soap+xml; charset=utf-8"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")
    except OSError as e:
        return 0, str(e)


def xml_tag(text, tag):
    """Extract first <...:tag>value</...:tag> (namespace-agnostic)."""
    m = re.search(rf"<(?:[\w.-]+:)?{tag}[^>]*>(.*?)</(?:[\w.-]+:)?{tag}>",
                  text, re.DOTALL)
    return m.group(1).strip() if m else None


def xml_tags(text, tag):
    return [m.strip() for m in re.findall(
        rf"<(?:[\w.-]+:)?{tag}[^>]*>(.*?)</(?:[\w.-]+:)?{tag}>",
        text, re.DOTALL)]


def xml_attr(text, tag, attr):
    m = re.search(rf"<(?:[\w.-]+:)?{tag}\s[^>]*?{attr}=\"([^\"]+)\"", text)
    return m.group(1) if m else None


class OnvifDevice:
    def __init__(self, host, user=None, password=None):
        self.base = f"http://{host}"
        self.device_url = f"{self.base}/onvif/device_service"
        self.media_url = f"{self.base}/onvif/media_service"
        self.user = user
        self.password = password

    def call(self, url, body, auth=True):
        user = self.user if auth else None
        return soap_call(url, body, user=user, password=self.password)

    def get_device_information(self):
        return self.call(self.device_url,
                         "<tds:GetDeviceInformation/>")

    def get_capabilities(self):
        return self.call(
            self.device_url,
            '<tds:GetCapabilities><tds:Category>All</tds:Category>'
            '</tds:GetCapabilities>')

    def get_system_date_and_time(self):
        # ONVIF spec: GetSystemDateAndTime must work without auth
        return self.call(self.device_url,
                         "<tds:GetSystemDateAndTime/>", auth=False)

    def get_services(self):
        return self.call(
            self.device_url,
            '<tds:GetServices><tds:IncludeCapability>false'
            '</tds:IncludeCapability></tds:GetServices>')

    def get_profiles(self):
        return self.call(self.media_url, "<trt:GetProfiles/>")

    def get_stream_uri(self, profile_token):
        body = ('<trt:GetStreamUri>'
                '<trt:StreamSetup>'
                '<tt:Stream>RTP-Unicast</tt:Stream>'
                '<tt:Transport><tt:Protocol>RTSP</tt:Protocol></tt:Transport>'
                '</trt:StreamSetup>'
                f'<trt:ProfileToken>{profile_token}</trt:ProfileToken>'
                '</trt:GetStreamUri>')
        return self.call(self.media_url, body)

    def get_snapshot_uri(self, profile_token):
        body = ('<trt:GetSnapshotUri>'
                f'<trt:ProfileToken>{profile_token}</trt:ProfileToken>'
                '</trt:GetSnapshotUri>')
        return self.call(self.media_url, body)
