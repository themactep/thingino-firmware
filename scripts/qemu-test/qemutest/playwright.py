"""Browser test runner."""

import json
import os
import subprocess

from .config import SCRIPT_DIR


def run_playwright(res, report_dir, scenarios, timeout=120,
                  check_name="playwright_tests"):
    """Run the browser scenarios named in the manifest.

    scenarios is what the plan wants exercised, keyed by describe block:
      portal     {"url": ...}                the captive portal loads
      provision  True                        fill the portal and submit
      webui      {"url": ...}                the main web UI loads
      login      {"url": ..., "password"}    the provisioned password logs in
    Absent keys are skipped on the JS side; one source of truth, no env
    flags to keep in step with the spec."""
    print("\n── Playwright ──")
    script_dir = SCRIPT_DIR
    manifest = os.path.join(report_dir, "pw-manifest.json")
    with open(manifest, "w") as f:
        json.dump(scenarios, f, indent=2)
    env = os.environ.copy()
    env["REPORT_DIR"] = report_dir
    env["PW_MANIFEST"] = manifest
    if os.geteuid() == 0:
        env["CHROMIUM_NO_SANDBOX"] = "1"
        # browsers live in the invoking user's cache, not root's
        sudo_user = os.environ.get("SUDO_USER")
        if sudo_user and "PLAYWRIGHT_BROWSERS_PATH" not in env:
            import pwd
            home = pwd.getpwnam(sudo_user).pw_dir
            env["PLAYWRIGHT_BROWSERS_PATH"] = os.path.join(
                home, ".cache", "ms-playwright")
    npx = os.environ.get("NPX_BIN") or "npx"
    pw = subprocess.run(
        [npx, "playwright", "test",
         "--config", os.path.join(script_dir, "playwright.config.js")],
        cwd=script_dir, env=env, capture_output=True, text=True,
        timeout=timeout)
    print(pw.stdout)
    if pw.stderr:
        print(pw.stderr[:500])
    res.check(check_name, pw.returncode == 0, f"exit {pw.returncode}")
    return pw.returncode == 0
