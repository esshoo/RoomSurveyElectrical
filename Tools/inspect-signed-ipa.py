#!/usr/bin/env python3
"""Inspect a signed 3ERoomElectrical IPA for WidgetKit registration blockers.

This is intentionally read-only. It checks bundle structure, Info.plists,
embedded provisioning profiles, App Group authorization, and nested signatures.
"""
from __future__ import annotations

import argparse
import plistlib
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Any

WIDGET_NAME = "3ERoomElectricalWidgetExtension.appex"
EXTENSION_POINT = "com.apple.widgetkit-extension"
APP_GROUP = "group.com.personal.roomsurveyelectrical"


def fail(message: str) -> None:
    print(f"FAIL: {message}")


def ok(message: str) -> None:
    print(f"PASS: {message}")


def warn(message: str) -> None:
    print(f"WARN: {message}")


def read_plist(path: Path) -> dict[str, Any]:
    with path.open("rb") as handle:
        return plistlib.load(handle)


def read_mobileprovision(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    data = path.read_bytes()
    start = data.find(b"<?xml")
    end_marker = b"</plist>"
    end = data.find(end_marker, start)
    if start < 0 or end < 0:
        return None
    end += len(end_marker)
    try:
        return plistlib.loads(data[start:end])
    except Exception:
        return None


def entitlement_groups(profile: dict[str, Any] | None) -> set[str]:
    if not profile:
        return set()
    entitlements = profile.get("Entitlements") or {}
    groups = entitlements.get("com.apple.security.application-groups") or []
    if isinstance(groups, str):
        groups = [groups]
    return {str(item) for item in groups}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path, help="Path to the signed IPA")
    args = parser.parse_args()

    ipa = args.ipa.resolve()
    if not ipa.is_file():
        fail(f"IPA not found: {ipa}")
        return 2

    failures = 0
    with tempfile.TemporaryDirectory(prefix="3e-ipa-") as temp:
        root = Path(temp)
        try:
            with zipfile.ZipFile(ipa) as archive:
                archive.extractall(root)
        except Exception as error:
            fail(f"Cannot open IPA as ZIP: {error}")
            return 2

        apps = list((root / "Payload").glob("*.app"))
        if len(apps) != 1:
            fail(f"Expected one .app in Payload, found {len(apps)}")
            return 1
        app = apps[0]
        ok(f"Host app exists: {app.name}")

        widget = app / "PlugIns" / WIDGET_NAME
        if not widget.is_dir():
            fail(f"Widget extension is missing: PlugIns/{WIDGET_NAME}")
            return 1
        ok(f"Widget extension is embedded: PlugIns/{WIDGET_NAME}")

        app_info_path = app / "Info.plist"
        widget_info_path = widget / "Info.plist"
        if not app_info_path.exists() or not widget_info_path.exists():
            fail("Host or widget Info.plist is missing")
            return 1

        app_info = read_plist(app_info_path)
        widget_info = read_plist(widget_info_path)
        app_id = str(app_info.get("CFBundleIdentifier", ""))
        widget_id = str(widget_info.get("CFBundleIdentifier", ""))
        point = str(
            (widget_info.get("NSExtension") or {}).get(
                "NSExtensionPointIdentifier", ""
            )
        )
        print(f"Host bundle ID:   {app_id or '<missing>'}")
        print(f"Widget bundle ID: {widget_id or '<missing>'}")
        print(f"Extension point:  {point or '<missing>'}")

        if not app_id:
            fail("Host CFBundleIdentifier is missing")
            failures += 1
        if widget_id != f"{app_id}.widget":
            fail("Widget bundle ID must equal host bundle ID + '.widget'")
            failures += 1
        else:
            ok("Widget bundle ID is nested under the host bundle ID")
        if point != EXTENSION_POINT:
            fail(f"Wrong WidgetKit extension point: {point!r}")
            failures += 1
        else:
            ok("WidgetKit extension point is correct")

        app_signature = app / "_CodeSignature" / "CodeResources"
        widget_signature = widget / "_CodeSignature" / "CodeResources"
        if app_signature.exists():
            ok("Host app contains a code-signature resource")
        else:
            warn("Host app has no _CodeSignature/CodeResources")
        if widget_signature.exists():
            ok("Widget extension contains its own code-signature resource")
        else:
            fail("Widget extension was not signed as a nested bundle")
            failures += 1

        app_profile = read_mobileprovision(app / "embedded.mobileprovision")
        widget_profile = read_mobileprovision(widget / "embedded.mobileprovision")
        if app_profile is None:
            warn("Host embedded.mobileprovision is missing or unreadable")
        else:
            ok("Host provisioning profile is readable")
        if widget_profile is None:
            fail("Widget embedded.mobileprovision is missing or unreadable")
            failures += 1
        else:
            ok("Widget provisioning profile is readable")

        app_groups = entitlement_groups(app_profile)
        widget_groups = entitlement_groups(widget_profile)
        print(f"Host profile App Groups:   {sorted(app_groups) or 'none'}")
        print(f"Widget profile App Groups: {sorted(widget_groups) or 'none'}")
        if APP_GROUP in app_groups and APP_GROUP in widget_groups:
            ok("Both provisioning profiles authorize the shared App Group")
        else:
            warn(
                "The widget may still appear, but recent-project data cannot be "
                "shared unless both profiles authorize the same App Group"
            )

    if failures:
        print(f"\nWidget IPA inspection: FAIL ({failures} blocking issue(s))")
        return 1
    print("\nWidget IPA inspection: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
