#!/usr/bin/env -S python3 -u
"""
Generate an HTML test report from serial test results and Playwright screenshots.

Usage: python3 report.py --serial-results serial.json --report-dir test-report/
"""

import argparse
import base64
import glob
import json
import os
from datetime import datetime


def img_to_data_uri(path):
    with open(path, "rb") as f:
        data = base64.b64encode(f.read()).decode()
    ext = os.path.splitext(path)[1].lower()
    mime = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg"}.get(ext.lstrip("."), "image/png")
    return f"data:{mime};base64,{data}"


def generate_report(serial_results, report_dir, profile, mode, meta=None):
    screenshots = sorted(glob.glob(os.path.join(report_dir, "*.png")))
    pw_results_path = os.path.join(report_dir, "playwright-results.json")
    pw_results = None
    if os.path.isfile(pw_results_path):
        with open(pw_results_path) as f:
            pw_results = json.load(f)

    serial_log_tail = ""
    serial_log_path = os.path.join(report_dir, "serial.log")
    if os.path.isfile(serial_log_path):
        with open(serial_log_path, "rb") as f:
            f.seek(max(0, os.path.getsize(serial_log_path) - 60000))
            serial_log_tail = f.read().decode(errors="replace")

    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
    passed = [t for t in serial_results if t["pass"] and not t.get("skip")]
    failed = [t for t in serial_results
              if not t["pass"] and not t.get("xfail")]

    html = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>QEMU Test Report: {profile} ({mode})</title>
<style>
  body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
         max-width: 1200px; margin: 0 auto; padding: 20px; background: #1a1a2e; color: #eee; }}
  h1 {{ color: #e94560; }}
  h2 {{ color: #0f3460; background: #16213e; padding: 10px; border-radius: 4px; }}
  .pass {{ color: #4ecca3; }} .fail {{ color: #e94560; }}
  .summary {{ font-size: 1.3em; padding: 15px; background: #16213e; border-radius: 8px; margin: 20px 0; }}
  table {{ border-collapse: collapse; width: 100%; margin: 15px 0; }}
  th, td {{ padding: 8px 12px; text-align: left; border-bottom: 1px solid #333; }}
  th {{ background: #16213e; }}
  .screenshots {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(400px, 1fr)); gap: 15px; }}
  .screenshot {{ background: #16213e; border-radius: 8px; padding: 10px; }}
  .screenshot img {{ width: 100%; border-radius: 4px; }}
  .screenshot .label {{ font-size: 0.9em; color: #aaa; margin-top: 5px; }}
  .badge {{ display: inline-block; padding: 4px 12px; border-radius: 12px; font-weight: bold; }}
  .badge.pass {{ background: #1b4332; color: #4ecca3; }}
  .badge.fail {{ background: #3c1518; color: #e94560; }}
</style>
</head>
<body>
<h1>QEMU Test Report</h1>
<div class="summary">
  <strong>Profile:</strong> {profile} &nbsp;
  <strong>Mode:</strong> {mode} &nbsp;
  <strong>Date:</strong> {now}<br><br>
  <span class="badge {'pass' if not failed else 'fail'}">
    {len(passed)}/{len(serial_results)} serial tests passed
  </span>
</div>
"""
    if meta:
        html += "<h2>Run Metadata</h2>\n<table>\n"
        for k in ("profile", "soc", "mode", "net", "machine", "ram_mb",
                  "image", "kernel", "qemu", "commit", "boot_seconds"):
            if k in meta:
                html += f"<tr><td>{k}</td><td>{meta[k]}</td></tr>\n"
        html += "</table>\n"
    html += """

<h2>Serial Test Results</h2>
<table>
<tr><th>Test</th><th>Result</th><th>Detail</th></tr>
"""
    for t in serial_results:
        cls = "pass" if t["pass"] else "fail"
        icon = "&#x2705;" if t["pass"] else "&#x274C;"
        html += f'<tr><td>{t["name"]}</td><td class="{cls}">{icon}</td><td>{t.get("detail", "")}</td></tr>\n'

    html += "</table>\n"

    if pw_results and "suites" in pw_results:
        html += "<h2>Playwright Test Results</h2>\n<table>\n<tr><th>Test</th><th>Result</th></tr>\n"
        for suite in pw_results.get("suites", []):
            for spec in suite.get("specs", []):
                for test in spec.get("tests", []):
                    for result in test.get("results", []):
                        status = result.get("status", "unknown")
                        cls = "pass" if status == "passed" else "fail"
                        icon = "&#x2705;" if status == "passed" else "&#x274C;"
                        html += f'<tr><td>{spec.get("title", "?")}</td><td class="{cls}">{icon} {status}</td></tr>\n'
        html += "</table>\n"

    if screenshots:
        html += "<h2>Screenshots</h2>\n<div class='screenshots'>\n"
        for ss in screenshots:
            label = os.path.splitext(os.path.basename(ss))[0].replace("-", " ").replace("_", " ")
            data_uri = img_to_data_uri(ss)
            html += f'<div class="screenshot"><img src="{data_uri}" alt="{label}"><div class="label">{label}</div></div>\n'
        html += "</div>\n"

    if serial_log_tail:
        import html as html_mod
        html += ("<h2>Serial Console (tail)</h2>\n"
                 "<details><summary>show serial log</summary>\n"
                 "<pre style='background:#0d0d1a;padding:10px;"
                 "border-radius:6px;overflow-x:auto;font-size:0.8em'>"
                 + html_mod.escape(serial_log_tail)
                 + "</pre></details>\n")

    html += "</body></html>\n"

    out_path = os.path.join(report_dir, "report.html")
    with open(out_path, "w") as f:
        f.write(html)
    print(f"Report written to {out_path}")
    return out_path


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--serial-results", required=True)
    p.add_argument("--report-dir", required=True)
    p.add_argument("--profile", default="unknown")
    p.add_argument("--mode", default="unknown")
    args = p.parse_args()

    with open(args.serial_results) as f:
        results = json.load(f)

    generate_report(results, args.report_dir, args.profile, args.mode)
