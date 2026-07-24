#!/usr/bin/env python3
"""Validate that an IPA contains a discoverable WidgetKit extension bundle."""

from __future__ import annotations

import argparse
import plistlib
import sys
import zipfile
from pathlib import Path


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def first_matching(names: list[str], suffix: str) -> str:
    matches = [name for name in names if name.endswith(suffix)]
    if not matches:
        fail(f"Missing {suffix}")
    if len(matches) > 1:
        fail(f"Found more than one {suffix}: {matches}")
    return matches[0]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    args = parser.parse_args()

    if not args.ipa.is_file():
        fail(f"IPA does not exist: {args.ipa}")

    with zipfile.ZipFile(args.ipa) as archive:
        names = archive.namelist()
        app_info = first_matching(names, ".app/Info.plist")
        app_prefix = app_info.removesuffix("Info.plist")
        widget_info = first_matching(
            names,
            ".app/PlugIns/3ERoomElectricalWidgetExtension.appex/Info.plist",
        )

        main_plist = plistlib.loads(archive.read(app_info))
        widget_plist = plistlib.loads(archive.read(widget_info))

        main_id = main_plist.get("CFBundleIdentifier")
        widget_id = widget_plist.get("CFBundleIdentifier")
        extension_point = (
            widget_plist.get("NSExtension", {})
            .get("NSExtensionPointIdentifier")
        )
        executable = widget_plist.get("CFBundleExecutable")

        if not isinstance(main_id, str) or not main_id:
            fail("Main app has no CFBundleIdentifier")
        if widget_id != f"{main_id}.widget":
            fail(
                "Widget bundle identifier must equal the final signed main "
                f"bundle identifier plus '.widget'. Main={main_id!r}, "
                f"widget={widget_id!r}"
            )
        if extension_point != "com.apple.widgetkit-extension":
            fail(f"Unexpected extension point: {extension_point!r}")
        if not isinstance(executable, str) or not executable:
            fail("Widget Info.plist has no CFBundleExecutable")

        widget_prefix = widget_info.removesuffix("Info.plist")
        executable_path = f"{widget_prefix}{executable}"
        if executable_path not in names:
            fail(f"Widget executable is missing: {executable_path}")

        nested_files = [
            name for name in names
            if name.startswith(f"{app_prefix}PlugIns/")
        ]
        if not nested_files:
            fail("The app bundle has no PlugIns content")

    print("Widget IPA structure: PASS")
    print(f"Main bundle ID: {main_id}")
    print(f"Widget bundle ID: {widget_id}")
    print(f"Widget executable: {executable}")
    print(
        "Note: this verifies packaging only. The signer must sign both the "
        "main app and the .appex and provision the shared App Group."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
