#!/usr/bin/env python3

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
PACKAGE_DIR = PROJECT_ROOT / "package"
BUILDROOT_PACKAGE_DIR = PROJECT_ROOT / "buildroot" / "package"
DOC_PATH = PROJECT_ROOT / "docs" / "packages.md"

VERSION_RE = re.compile(r"^\s*(?:override\s+)?([A-Z0-9_]+_VERSION)\s*(?::=|\+=|\?=|=)\s*(.+?)\s*$")


@dataclass(frozen=True)
class PackageRow:
    package_dir: str
    kind: str
    buildroot_package: str
    buildroot_version: str
    thingino_version: str


def clean_value(value: str) -> str:
    value = value.strip()
    if value.startswith(("'", '"')) and value.endswith(("'", '"')) and len(value) >= 2:
        return value[1:-1]
    return value


def first_version_in_mk(mk_path: Path) -> str | None:
    for line in mk_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        stripped = line.split("#", 1)[0].strip()
        if not stripped:
            continue
        match = VERSION_RE.match(stripped)
        if match:
            return clean_value(match.group(2))
    return None


def resolve_buildroot_mk(package_name: str) -> Path | None:
    candidates: list[Path] = []

    candidates.append(BUILDROOT_PACKAGE_DIR / package_name / f"{package_name}.mk")
    candidates.append(BUILDROOT_PACKAGE_DIR / package_name / f"{package_name.replace('-', '_')}.mk")

    if "-" in package_name:
        root = package_name.split("-", 1)[0]
        candidates.append(BUILDROOT_PACKAGE_DIR / root / f"{root}.mk")
        candidates.append(BUILDROOT_PACKAGE_DIR / root / f"{root.replace('-', '_')}.mk")

    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None


def buildroot_version(package_name: str) -> str:
    mk_path = resolve_buildroot_mk(package_name)
    if not mk_path:
        return "n/a"
    return first_version_in_mk(mk_path) or "n/a"


def thingino_version(package_dir: Path, prefer_override_only: bool) -> str:
    mk_files = sorted(package_dir.glob("*.mk"))
    if prefer_override_only:
        mk_files = [mk for mk in mk_files if mk.name.endswith("-override.mk")]
    else:
        mk_files = [mk for mk in mk_files if not mk.name.endswith("-override.mk")] or mk_files

    for mk_path in mk_files:
        version = first_version_in_mk(mk_path)
        if version:
            return version
    return "n/a"


def build_rows() -> list[PackageRow]:
    rows: list[PackageRow] = []

    for package_dir in sorted(PACKAGE_DIR.iterdir()):
        if not package_dir.is_dir():
            continue
        if package_dir.name == "all-patches":
            continue

        mk_files = sorted(package_dir.glob("*.mk"))
        if not mk_files and not (package_dir / "Config.in").exists():
            continue

        override_mks = [mk for mk in mk_files if mk.name.endswith("-override.mk")]
        base_package = None
        if override_mks:
            base_package = override_mks[0].stem.removesuffix("-override")
        elif (BUILDROOT_PACKAGE_DIR / package_dir.name).exists():
            base_package = package_dir.name

        if base_package:
            rows.append(
                PackageRow(
                    package_dir=package_dir.name,
                    kind="Override",
                    buildroot_package=base_package,
                    buildroot_version=buildroot_version(base_package),
                    thingino_version=thingino_version(package_dir, prefer_override_only=True),
                )
            )
            continue

        rows.append(
            PackageRow(
                package_dir=package_dir.name,
                kind="Added",
                buildroot_package="-",
                buildroot_version="n/a",
                thingino_version=thingino_version(package_dir, prefer_override_only=False),
            )
        )

    return sorted(rows, key=lambda row: (0 if row.kind == "Added" else 1, row.package_dir))


def render_markdown(rows: list[PackageRow]) -> str:
    lines = [
        "# Thingino package inventory vs Buildroot",
        "",
        "Packages in Thingino tree that are either **added** by Thingino or **override** Buildroot packages.",
        "Versions are extracted from package `.mk` files.",
        "",
        "| Package directory | Kind | Buildroot package | Buildroot version | Thingino package version |",
        "| --- | --- | --- | --- | --- |",
    ]

    for row in rows:
        lines.append(
            f"| `{row.package_dir}` | {row.kind} | `{row.buildroot_package}` | `{row.buildroot_version}` | `{row.thingino_version}` |"
        )

    lines.extend(
        [
            "",
            f"Last checked {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC",
            "",
        ]
    )

    return "\n".join(lines)


def main() -> int:
    rows = build_rows()
    DOC_PATH.write_text(render_markdown(rows), encoding="utf-8")
    print(f"Updated {DOC_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
