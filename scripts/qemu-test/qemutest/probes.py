"""Waiting on the guest: poll to a deadline, never sleep for effect.

Under TCG the guest is slow and load-sensitive, and every fixed wait the
suite has ever had flaked at least once. A suite that needs something to
become true says so with until(); the interval is a retry cadence, not a
guess at how long the thing takes.
"""
import socket
import time
import urllib.request


def until(fn, timeout, interval=2.0, ok=None):
    """Call fn() until ok(value) holds or timeout elapses.

    ok defaults to truthiness. Returns fn's last value either way, so the
    caller uses it for the check and still has what was last seen when
    reporting a failure. The final sleep is clipped to the deadline so a
    slow interval never overshoots the budget.
    """
    ok = ok or bool
    deadline = time.time() + timeout
    while True:
        val = fn()
        if ok(val):
            return val
        left = deadline - time.time()
        if left <= 0:
            return val
        time.sleep(min(interval, left))


def http_get(url, timeout=5.0, limit=1024):
    """(status, body, error). status is None and error is set on failure."""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return r.status, r.read(limit).decode(errors="replace"), ""
    except Exception as e:
        return None, "", str(e)


def http_ok(url, timeout=5.0):
    return http_get(url, timeout)[0] == 200


def tcp_open(host, port, timeout=2.0):
    """True when something accepts a TCP connection at host:port."""
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False
