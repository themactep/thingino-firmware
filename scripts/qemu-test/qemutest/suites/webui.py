"""Web UI reachability from the guest and the host."""

from ..config import WEBUI_PORT
from ..probes import http_get, until


def test_webui(ctx):
    guest, res = ctx.guest, ctx.res
    rc, out = guest.run(
        "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/", timeout=15)
    res.check("webui_http_200", "200" in out)

    rc, out = guest.run("curl -s http://127.0.0.1/ | head -3", timeout=15)
    res.check("webui_serves_html", "<!DOCTYPE" in out)
    res.check("webui_not_portal",
              "portal" not in out.lower() or "preview" in out.lower())


def test_host_http(ctx):
    res, guest_v4, guest_v6 = ctx.res, ctx.guest_v4, ctx.guest_v6
    for fam, addr in (("v4", guest_v4), ("v6", f"[{guest_v6}]" if guest_v6 else None)):
        name = f"host_http_{fam}"
        if not addr:
            res.skip(name, "no address")
            continue
        status, body, err = until(lambda: http_get(f"http://{addr}/", 8), 20, 2,
                                  ok=lambda r: r[0] == 200 and "<!DOCTYPE" in r[1])
        res.check(name, status == 200 and "<!DOCTYPE" in body,
                  "" if status == 200 else err[:80])


def test_host_webui_access(ctx):
    res = ctx.res
    status, body, err = until(
        lambda: http_get(f"http://localhost:{WEBUI_PORT + 1}/", 5),
        30, 2, ok=lambda r: r[0] == 200)
    res.check("host_webui_reachable", status == 200,
              "" if status == 200 else err)
    res.check("host_webui_content", "<!DOCTYPE" in body)
