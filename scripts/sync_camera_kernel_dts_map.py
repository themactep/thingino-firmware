#!/usr/bin/env python3
"""Auto-generate camera -> kernel DTS mapping."""

from __future__ import annotations

import glob
import os
import re
import subprocess
from datetime import UTC, datetime

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MAP_PATH = os.path.join(ROOT, "configs", "camera-kernel-dts.map")
CAMERA_GLOB = os.path.join(ROOT, "configs", "cameras*", "*", "thingino.json")
DEFCONFIG_GLOB = os.path.join(ROOT, "configs", "cameras*", "*", "*_defconfig")
BOARD_DTS_GLOB = os.path.join(ROOT, "board", "ingenic", "dts", "*.dts")
KERNEL_GENERIC_CONFIG_GLOB = os.path.join(ROOT, "board", "ingenic", "**", "*.generic.config")

KERNEL_REPO = "gtxaspec/thingino-linux"
KERNEL_BRANCHES = (
    "ingenic-t31",
    "ingenic-t40",
    "ingenic-a1",
    "ingenic-t41-4.4.94",
    "ingenic-t31-4.4.94",
    "ingenic-t23-4.4.94",
)


def _run(cmd: list[str]) -> str:
    return subprocess.check_output(cmd, text=True, cwd=ROOT, stderr=subprocess.DEVNULL).strip()


def _read_overrides(path: str) -> dict[str, str]:
    out: dict[str, str] = {}
    if not os.path.exists(path):
        return out
    in_manual_section = False
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            raw = line.strip()
            if raw.startswith("# Manual/seed overrides:"):
                in_manual_section = True
                continue
            if raw.startswith("# Auto-resolved mappings:"):
                in_manual_section = False
                continue
            if not in_manual_section:
                continue
            if not raw or raw.startswith("#") or "=" not in raw:
                continue
            # Keep manual overrides clean: ignore inline-commented auto rows.
            if "#" in raw:
                continue
            camera, dts = raw.split("=", 1)
            camera = camera.strip()
            dts = dts.strip()
            if camera and dts:
                out[camera] = dts
    return out


def _camera_names() -> list[str]:
    names = []
    for p in sorted(glob.glob(CAMERA_GLOB)):
        names.append(os.path.basename(os.path.dirname(p)))
    return sorted(set(names))


def _collect_local_dts_names() -> set[str]:
    names: set[str] = set()
    for p in glob.glob(BOARD_DTS_GLOB):
        names.add(os.path.splitext(os.path.basename(p))[0])
    return names


def _collect_branch_dts_names(branch: str) -> set[str]:
    names: set[str] = set()
    ref = _run(["gh", "api", f"repos/{KERNEL_REPO}/git/ref/heads/{branch}", "--jq", ".object.sha"])
    paths = _run(["gh", "api", f"repos/{KERNEL_REPO}/git/trees/{ref}?recursive=1", "--jq", ".tree[]?.path"])
    for path in paths.splitlines():
        path = path.strip()
        if not path.endswith(".dts"):
            continue
        if "arch/mips/" not in path:
            continue
        names.add(os.path.splitext(os.path.basename(path))[0])
    return names


def _collect_all_dts_names() -> tuple[set[str], dict[str, int]]:
    names = _collect_local_dts_names()
    branch_hits: dict[str, int] = {}
    for branch in KERNEL_BRANCHES:
        try:
            branch_names = _collect_branch_dts_names(branch)
        except Exception:
            branch_hits[branch] = 0
            continue
        branch_hits[branch] = len(branch_names)
        names.update(branch_names)
    return names, branch_hits


def _parse_kernel_default_dts_by_family() -> dict[str, str]:
    family_map: dict[str, str] = {}
    dt_re = re.compile(r"^CONFIG_DT_([A-Z0-9]+)_([A-Z0-9_]+)=y$")
    for cfg in glob.glob(KERNEL_GENERIC_CONFIG_GLOB, recursive=True):
        with open(cfg, "r", encoding="utf-8") as fh:
            for line in fh:
                m = dt_re.match(line.strip())
                if not m:
                    continue
                family = m.group(1).lower()
                board = m.group(2).lower()
                if board == "swan":
                    family_map[family] = f"swan_{family}"
                else:
                    family_map[family] = board
    return family_map


def _parse_legacy_board_default_by_family() -> dict[str, str]:
    family_map: dict[str, str] = {}
    board_name_re = re.compile(r'^CONFIG_BOARD_NAME="([^"]+)"$')
    for cfg in glob.glob(KERNEL_GENERIC_CONFIG_GLOB, recursive=True):
        # Legacy board names come from 3.10 generic configs.
        if "/3.10.14/" not in cfg:
            continue
        family = os.path.basename(cfg).split(".", 1)[0].lower()
        with open(cfg, "r", encoding="utf-8") as fh:
            for line in fh:
                m = board_name_re.match(line.strip())
                if not m:
                    continue
                family_map[family] = m.group(1).strip().lower()
                break
    return family_map


def _camera_soc_family(camera: str) -> str | None:
    # SoC token can appear in different positions (e.g. tapo_c500_t23n...).
    known_families = {"t10", "t20", "t21", "t23", "t30", "t31", "t40", "t41", "a1", "c100"}
    matches: list[str] = []
    for token in camera.lower().split("_"):
        m = re.match(r"(t[0-9]{2,3}|a1|c100)[a-z]*$", token)
        if m:
            matches.append(m.group(1))
    if matches:
        # Prefer the rightmost known SoC family; model tokens can look similar (e.g. t110, t55a).
        for family in reversed(matches):
            if family in known_families:
                return family
        return matches[-1]
    # Fallback to defconfig SOC symbol when camera name doesn't include SoC token.
    expected = f"{camera}_defconfig"
    for path in glob.glob(DEFCONFIG_GLOB):
        if os.path.basename(path) != expected:
            continue
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line.startswith("BR2_INGENIC_SOC_MODEL"):
                    continue
                if "=" not in line:
                    continue
                raw = line.split("=", 1)[1].strip().strip('"').lower()
                m = re.match(r"(t[0-9]{2,3}|a1|c100)[a-z]*$", raw)
                if m:
                    return m.group(1)
                break
    return None


def _candidate_trims(camera: str) -> list[str]:
    candidates = [camera]
    parts = camera.split("_")
    for drop in (1, 2, 3, 4):
        if len(parts) - drop >= 2:
            candidates.append("_".join(parts[:-drop]))
    seen: set[str] = set()
    ordered: list[str] = []
    for c in candidates:
        if c not in seen:
            seen.add(c)
            ordered.append(c)
    return ordered


def _best_prefix_match(name: str, dts_names: set[str]) -> str | None:
    matches = [d for d in dts_names if name == d or name.startswith(f"{d}_")]
    if not matches:
        return None
    return max(matches, key=len)


def _resolve(camera: str, dts_names: set[str]) -> tuple[str | None, str]:
    if camera in dts_names:
        return camera, "exact"

    best = _best_prefix_match(camera, dts_names)
    if best is not None:
        return best, "prefix"

    for trim in _candidate_trims(camera)[1:]:
        if trim in dts_names:
            return trim, "trimmed"
        best = _best_prefix_match(trim, dts_names)
        if best is not None:
            return best, "trimmed-prefix"

    return None, "unresolved"


def _write_map(
    path: str,
    overrides: dict[str, str],
    resolved: dict[str, tuple[str, str]],
    unresolved: list[str],
    branch_hits: dict[str, int],
) -> None:
    now = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = [
        "# camera_name=base_kernel_dts_name",
        "# Auto-generated by scripts/sync_camera_kernel_dts_map.py",
        f"# Generated at: {now}",
        "#",
        "# Source sets:",
    ]
    for branch, count in branch_hits.items():
        lines.append(f"# - {branch}: {count} dts files discovered")
    lines.extend(
        [
            "",
            "# Manual/seed overrides:",
        ]
    )

    for camera in sorted(overrides):
        lines.append(f"{camera}={overrides[camera]}")

    lines.extend(["", "# Auto-resolved mappings:"])
    for camera in sorted(resolved):
        if camera in overrides:
            continue
        dts_name, method = resolved[camera]
        lines.append(f"{camera}={dts_name}  # {method}")

    lines.extend(["", "# Unresolved cameras (set manually):"])
    for camera in sorted(unresolved):
        lines.append(f"# {camera}=")

    lines.append("")

    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))


def main() -> int:
    overrides = _read_overrides(MAP_PATH)
    cameras = _camera_names()
    dts_names, branch_hits = _collect_all_dts_names()
    family_dts = _parse_kernel_default_dts_by_family()
    legacy_board = _parse_legacy_board_default_by_family()

    resolved: dict[str, tuple[str, str]] = {}
    unresolved: list[str] = []
    for camera in cameras:
        if camera in overrides:
            resolved[camera] = (overrides[camera], "override")
            continue

        family = _camera_soc_family(camera)
        if family and family in family_dts:
            resolved[camera] = (family_dts[family], "soc-family-default")
            continue

        if family and family in legacy_board:
            resolved[camera] = (legacy_board[family], "soc-family-legacy-board")
            continue

        dts_name, method = _resolve(camera, dts_names)
        if dts_name is None:
            unresolved.append(camera)
            continue
        resolved[camera] = (dts_name, method)

    _write_map(MAP_PATH, overrides, resolved, unresolved, branch_hits)

    print(f"cameras: {len(cameras)}")
    print(f"resolved: {len(resolved)}")
    print(f"unresolved: {len(unresolved)}")
    print(f"soc-family defaults: {len(family_dts)}")
    print(f"legacy board defaults: {len(legacy_board)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
