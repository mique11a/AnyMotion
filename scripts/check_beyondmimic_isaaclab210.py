#!/usr/bin/env python3
"""Validate that the active environment matches whole_body_tracking requirements."""

from __future__ import annotations

import argparse
import importlib
import importlib.metadata
import pathlib
import subprocess
import sys
from dataclasses import dataclass


EXPECTED_PYTHON = (3, 10)
EXPECTED_ISAACSIM = {"4.5.0", "4.5.0.0"}
EXPECTED_ISAACLAB_TAG = "v2.1.0"


@dataclass
class CheckResult:
    name: str
    ok: bool
    detail: str


def _metadata_version(distribution: str) -> str | None:
    try:
        return importlib.metadata.version(distribution)
    except importlib.metadata.PackageNotFoundError:
        return None


def _module_attr_version(module_name: str) -> str | None:
    try:
        module = importlib.import_module(module_name)
    except Exception:
        return None
    return getattr(module, "__version__", None)


def _import_path(module_name: str) -> str | None:
    try:
        module = importlib.import_module(module_name)
    except Exception:
        return None
    file_attr = getattr(module, "__file__", None)
    return str(pathlib.Path(file_attr).resolve()) if file_attr else None


def check_python() -> CheckResult:
    found = sys.version_info[:2]
    ok = found == EXPECTED_PYTHON
    return CheckResult("python", ok, f"found {found[0]}.{found[1]}, expected {EXPECTED_PYTHON[0]}.{EXPECTED_PYTHON[1]}")


def check_isaacsim() -> CheckResult:
    version = _metadata_version("isaacsim") or _module_attr_version("isaacsim")
    if version is None:
        return CheckResult("isaacsim", False, "package not importable in current environment")
    ok = version in EXPECTED_ISAACSIM
    expected = ", ".join(sorted(EXPECTED_ISAACSIM))
    return CheckResult("isaacsim", ok, f"found {version}, expected one of {expected}")


def check_isaaclab() -> CheckResult:
    path = _import_path("isaaclab")
    if path is None:
        return CheckResult("isaaclab", False, "module not importable in current environment")
    detail = f"import path {path}"
    version = _metadata_version("isaaclab")
    if version:
        detail += f"; package version {version}"
    return CheckResult("isaaclab", True, detail)


def check_rsl_rl() -> CheckResult:
    version = _metadata_version("rsl-rl") or _metadata_version("rsl_rl")
    path = _import_path("rsl_rl")
    if version is None and path is None:
        return CheckResult("rsl_rl", False, "package not importable in current environment")
    detail_parts = []
    if version is not None:
        detail_parts.append(f"package version {version}")
    if path is not None:
        detail_parts.append(f"import path {path}")
    return CheckResult("rsl_rl", True, "; ".join(detail_parts))


def check_isaaclab_git_tag(isaaclab_dir: pathlib.Path) -> CheckResult:
    if not isaaclab_dir.exists():
        return CheckResult("isaaclab_git", False, f"directory not found: {isaaclab_dir}")
    try:
        describe = subprocess.check_output(
            ["git", "-C", str(isaaclab_dir), "describe", "--tags", "--always"],
            text=True,
        ).strip()
    except subprocess.CalledProcessError as exc:
        return CheckResult("isaaclab_git", False, f"git describe failed: {exc}")
    ok = describe == EXPECTED_ISAACLAB_TAG
    return CheckResult("isaaclab_git", ok, f"found {describe}, expected {EXPECTED_ISAACLAB_TAG}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--isaaclab-dir",
        type=pathlib.Path,
        default=pathlib.Path.home() / "public_resources" / "src" / "IsaacLab-2.1.0",
        help="Local IsaacLab checkout to validate.",
    )
    args = parser.parse_args()

    checks = [
        check_python(),
        check_isaacsim(),
        check_isaaclab(),
        check_rsl_rl(),
        check_isaaclab_git_tag(args.isaaclab_dir),
    ]

    failures = 0
    for result in checks:
        status = "OK" if result.ok else "FAIL"
        print(f"[{status}] {result.name}: {result.detail}")
        if not result.ok:
            failures += 1

    if failures:
        print(
            "\nEnvironment does not match whole_body_tracking requirements: "
            "Python 3.10 + Isaac Sim 4.5.0 + Isaac Lab v2.1.0."
        )
        return 1

    print("\nEnvironment matches whole_body_tracking requirements.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
