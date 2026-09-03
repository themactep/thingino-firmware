"""The ordered suite table that drives a run."""

from .config import PORTAL_PORT, SSH_FWD_PORT
from .playwright import run_playwright
from .probes import tcp_open, until
from .suites.common import setup_ssh, test_boot, test_health, test_services
from .suites.net import test_dns_and_pref, test_dual_stack_listeners, test_ethernet, test_ethwifi_behavior, test_ipv4_dhcp, test_ipv6, test_link_flap, test_mdns, test_ntp, test_persist_reboot, test_syslog_remote
from .suites.onvif import test_onvif
from .suites.webui import test_host_http, test_host_webui_access, test_webui
from .suites.wifi import test_host_portal_access, test_provision_reboot_sta, test_wifi_bridge_setup, test_wifi_modules, test_wifi_portal


#
# One ordered table drives the whole run. A suite is declared once, with
# the capabilities it needs, and everything else (execution order, --only
# filtering, the --only help text) derives from it. Adding a suite is one
# entry; nothing in the driver changes.
#
# The table is the union of every profile's plan: filtering on what the
# profile is (wired, wifi) yields the wifi-only sequence and the wired
# one, so the rows stay in one list rather than per-profile schedules.
def suite_ssh_lab(ctx):
    setup_ssh(ctx, ctx.guest_v4)


def suite_ssh_forward(ctx):
    until(lambda: tcp_open("127.0.0.1", SSH_FWD_PORT), 15, 1)
    setup_ssh(ctx, "127.0.0.1", SSH_FWD_PORT)


def suite_dns(ctx):
    test_dns_and_pref(ctx)
    test_dual_stack_listeners(ctx)


def suite_net_services(ctx):
    test_mdns(ctx)
    test_ntp(ctx)
    test_syslog_remote(ctx)


def suite_playwright_wifi(ctx):
    ctx.playwright_ok = run_playwright(ctx.res, ctx.report_dir, {
        "portal": {"url": f"http://localhost:{PORTAL_PORT}"},
        "provision": True,
    })


def suite_playwright_eth(ctx):
    ctx.playwright_ok = run_playwright(ctx.res, ctx.report_dir, {
        "webui": {"url": f"http://{ctx.guest_v4}"},
    })


# What a profile is, as requirements. A wifi-only camera has a radio and
# no wired uplink; on one with both, the wired path wins and the portal
# never starts, so portal rows require the radio AND no uplink.
WIRED = ("wired",)
WIFI_ONLY = ("wifi", "nowired")
BOTH = ("wired", "wifi")


class Suite:
    """One row of the run plan.

    name      --only token, and the label; rows may share one (a token
              like "webui" can pull in more than one row)
    fn        callable taking the run context
    requires  capability names from Ctx.has(), what the profile is and
              what the run has discovered; an unmet requirement skips the
              row silently
    header    section banner printed before the row, if any
    optional  False = always runs, never filtered out by --only
    """

    def __init__(self, name, fn, requires=(), header=None, optional=True):
        self.name = name
        self.fn = fn
        self.requires = requires
        self.header = header
        self.optional = optional

    def wanted(self, ctx, only):
        if self.optional and only and self.name not in only:
            return False
        return all(ctx.has(c) for c in self.requires)


SUITES = [
    Suite("boot", test_boot, optional=False),
    Suite("procs", test_services, optional=False),

    Suite("wifi", test_wifi_modules, WIFI_ONLY, header="WiFi",
          optional=False),
    Suite("wifi", test_wifi_portal, WIFI_ONLY, optional=False),

    Suite("ethernet", test_ethernet, WIRED, header="Ethernet",
          optional=False),
    Suite("ethwifi", test_ethwifi_behavior, BOTH,
          header="Ethernet + WiFi behavior", optional=False),

    Suite("ipv4", test_ipv4_dhcp, WIRED + ("lab",), header="IPv4 DHCP",
          optional=False),
    Suite("ssh", suite_ssh_lab, WIRED + ("lab", "v4"), optional=False),
    Suite("ipv6", test_ipv6, WIRED + ("lab",), header="IPv6"),
    Suite("dns", suite_dns, WIRED + ("lab",), header="DNS / dual-stack"),

    Suite("health", test_health, header="Health"),

    Suite("webui", test_webui, WIRED, header="Web UI"),
    Suite("webui", test_host_http, WIRED + ("lab", "v4")),
    Suite("onvif", test_onvif, WIRED + ("lab", "v4"), header="ONVIF"),
    Suite("services", suite_net_services, WIRED + ("lab", "v4"),
          header="mDNS / NTP / syslog"),

    Suite("bridge", test_wifi_bridge_setup, WIFI_ONLY + ("host",),
          header="Bridge setup", optional=False),
    Suite("ssh", suite_ssh_forward, WIFI_ONLY + ("host",), optional=False),
    Suite("portal", test_host_portal_access, WIFI_ONLY + ("host",),
          header="Host access", optional=False),

    Suite("playwright", suite_playwright_wifi, WIFI_ONLY + ("pw", "host")),
    # Only meaningful once the browser has actually submitted the portal
    # form, so it requires the playwright row above to have passed.
    Suite("persist", test_provision_reboot_sta,
          WIFI_ONLY + ("pw", "host", "reboot", "pw_ok"), optional=False),

    Suite("playwright", suite_playwright_eth, WIRED + ("pw", "lab", "v4")),
    Suite("webui", test_host_webui_access, WIRED + ("host", "nolab"),
          header="Host access"),
    Suite("linkflap", test_link_flap, WIRED + ("lab", "qmp", "v4"),
          header="Link flap"),
    Suite("persist", test_persist_reboot, WIRED + ("reboot",)),
]


OPTIONAL_SUITES = sorted({s.name for s in SUITES if s.optional})


def run_suites(ctx, only):
    for suite in SUITES:
        if not suite.wanted(ctx, only):
            continue
        if suite.header:
            print(f"\n── {suite.header} ──")
        suite.fn(ctx)
