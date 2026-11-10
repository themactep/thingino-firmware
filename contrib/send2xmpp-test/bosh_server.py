#!/usr/bin/env python3
"""Minimal BOSH/XMPP test server for send2xmpp.

It implements just enough of the client flow (session establishment, SASL
PLAIN success, bind, session, disco items, XEP-0363 upload slot, message) to
exercise package/send2xmpp/files/send2xmpp end to end without a real XMPP
server.  The attribute quote style is selectable per request:

    /http-bind?style=double   Openfire 5.x style, sid="..."
    /http-bind?style=single   Prosody/legacy style, sid='...'

The default is double, because that is the regression reported in #1985.
Messages and uploads are exposed over GET /messages and GET /uploads so the
test runner can assert what the client actually sent.  GET /reset clears
both.
"""

import json
import secrets
import sys
import threading
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

BIND_ADDR = ("0.0.0.0", 5280)
BOSH_NS = "http://jabber.org/protocol/httpbind"
SASL_NS = "urn:ietf:params:xml:ns:xmpp-sasl"
XMPP_BIND_NS = "urn:ietf:params:xml:ns:xmpp-bind"
XMPP_SESSION_NS = "urn:ietf:params:xml:ns:xmpp-session"
DISCO_ITEMS_NS = "http://jabber.org/protocol/disco#items"
UPLOAD_NS = "urn:xmpp:http:upload:0"

LOCK = threading.Lock()
MESSAGES = []
UPLOADS = []


def localname(tag):
    return tag.rsplit("}", 1)[-1]


def attr(name, value, style):
    if style == "single":
        return "%s='%s'" % (name, value)
    return '%s="%s"' % (name, value)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code, body, content_type):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _json(self, payload):
        self._send(200, json.dumps(payload), "application/json")

    def _xml(self, body):
        self._send(200, body, "text/xml; charset=utf-8")

    def log_message(self, fmt, *args):
        sys.stderr.write("bosh: " + (fmt % args) + "\n")
        sys.stderr.flush()

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/health":
            return self._send(200, "ok", "text/plain")
        if path == "/messages":
            with LOCK:
                return self._json(MESSAGES)
        if path == "/uploads":
            with LOCK:
                return self._json(UPLOADS)
        if path == "/reset":
            with LOCK:
                MESSAGES.clear()
                UPLOADS.clear()
            return self._send(200, "ok", "text/plain")
        if path == "/upload/get":
            return self._send(200, "uploaded", "text/plain")
        return self._send(404, "not found", "text/plain")

    def do_PUT(self):
        path = urlparse(self.path).path
        if path != "/upload/put":
            return self._send(404, "not found", "text/plain")
        length = int(self.headers.get("Content-Length", "0"))
        data = self.rfile.read(length)
        with LOCK:
            UPLOADS.append({"size": len(data), "name": "upload.bin"})
        return self._send(201, "created", "text/plain")

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/http-bind":
            return self._send(404, "not found", "text/plain")

        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8", errors="replace")
        style = parse_qs(parsed.query).get("style", ["double"])[0]
        if style != "single":
            style = "double"

        try:
            root = ET.fromstring(raw)
        except ET.ParseError as exc:
            return self._send(400, "bad request: %s" % exc, "text/plain")

        children = list(root)
        auth = next((c for c in children if localname(c.tag) == "auth"), None)
        iq = next((c for c in children if localname(c.tag) == "iq"), None)
        message = next((c for c in children if localname(c.tag) == "message"), None)
        sid = root.attrib.get("sid", "")

        if root.attrib.get("type") == "terminate":
            return self._xml("<body %s %s/>" % (
                attr("type", "terminate", style), attr("xmlns", BOSH_NS, style)))

        # Session request: no sid and no child stanzas.
        if not sid and not children:
            xmpp_ns = attr("xmlns:xmpp", "urn:xmpp:xmpp-bosh", style)
            return self._xml("<body %s %s %s %s %s/>" % (
                attr("sid", secrets.token_hex(12), style),
                attr("wait", "60", style),
                attr("hold", "1", style),
                attr("xmlns", BOSH_NS, style),
                xmpp_ns,
            ))

        if auth is not None:
            return self._xml(
                "<body xmlns='%s'><success xmlns='%s'/></body>"
                % (BOSH_NS, SASL_NS))

        if message is not None:
            text = ""
            for child in message:
                if localname(child.tag) == "body":
                    text = child.text or ""
                    break
            with LOCK:
                MESSAGES.append({"body": text, "style": style})
            return self._xml("<body xmlns='%s'/>" % BOSH_NS)

        if iq is not None:
            iq_id = iq.attrib.get("id", "")
            child = next(iter(iq), None)
            lname = localname(child.tag) if child is not None else ""
            # ElementTree moves xmlns declarations into the expanded tag.
            child_ns = ""
            if child is not None and child.tag.startswith("{"):
                child_ns = child.tag[1:].split("}", 1)[0]

            if lname == "bind":
                inner = ("<bind xmlns='%s'><jid>camera@test/thingino</jid></bind>"
                         % XMPP_BIND_NS)
            elif lname == "session":
                inner = ""
            elif lname == "query" and DISCO_ITEMS_NS in child_ns:
                inner = ("<query xmlns='%s'><item %s/></query>"
                         % (DISCO_ITEMS_NS, attr("jid", "upload.test", style)))
            elif lname == "request" and UPLOAD_NS in child_ns:
                host = self.headers.get("Host", "bosh:5280")
                put_url = "http://%s/upload/put" % host
                get_url = "http://%s/upload/get" % host
                inner = ("<slot xmlns='%s'><put %s/><get %s/></slot>"
                         % (UPLOAD_NS, attr("url", put_url, style),
                            attr("url", get_url, style)))
            else:
                inner = ""

            return self._xml(
                "<body xmlns='%s'><iq %s %s>%s</iq></body>"
                % (BOSH_NS, attr("type", "result", style),
                   attr("id", iq_id, style), inner))

        # Stream restart and anything else the client sends.
        return self._xml("<body xmlns='%s'/>" % BOSH_NS)


def main():
    server = ThreadingHTTPServer(BIND_ADDR, Handler)
    server.daemon_threads = True
    print("bosh test server on http://%s:%d/http-bind" % BIND_ADDR)
    sys.stdout.flush()
    server.serve_forever()


if __name__ == "__main__":
    main()
