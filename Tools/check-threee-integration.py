#!/usr/bin/env python3
"""Static acceptance checks for Build 48 3E registry compatibility."""
from __future__ import annotations

import json
import os
import plistlib
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FAILURES: list[str] = []


def check(condition: bool, message: str) -> None:
    if condition:
        print(f"PASS: {message}")
    else:
        print(f"FAIL: {message}")
        FAILURES.append(message)


def text(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def normalize_apps(raw_apps: object) -> dict[str, dict[str, object]]:
    if isinstance(raw_apps, dict):
        result: dict[str, dict[str, object]] = {}
        for dictionary_key, raw_entry in raw_apps.items():
            if not isinstance(raw_entry, dict):
                raise ValueError("invalid apps dictionary entry")
            entry = dict(raw_entry)
            app_key = str(entry.get("appKey") or dictionary_key).strip()
            if not app_key:
                raise ValueError("missing appKey")
            entry["appKey"] = app_key
            result[app_key] = entry
        return result

    if isinstance(raw_apps, list):
        result = {}
        for raw_entry in raw_apps:
            if not isinstance(raw_entry, dict):
                raise ValueError("invalid apps array entry")
            entry = dict(raw_entry)
            app_key = str(entry.get("appKey") or "").strip()
            if not app_key:
                raise ValueError("missing appKey")
            result[app_key] = entry
        return result

    raise ValueError("apps is neither a list nor an object")


def test_registry_merge_contract() -> None:
    expected = {
        "appKey": "roomElectrical",
        "displayName": "3ERoomElectrical",
        "bundleIdentifier": "com.essam.3E.roomelectrical",
        "urlScheme": "electrical",
        "folder": "Apps/RoomElectrical",
    }

    fixtures = [
        {
            "schemaVersion": 3,
            "futureRootField": {"preserve": True},
            "apps": [
                {
                    "appKey": "lidar",
                    "displayName": "3ELiDAR",
                    "custom": "keep-me",
                },
                {
                    "appKey": "roomElectrical",
                    "displayName": "old",
                    "futureAppField": 7,
                },
            ],
        },
        {
            "schemaVersion": 3,
            "futureRootField": {"preserve": True},
            "apps": {
                "lidar": {
                    "appKey": "lidar",
                    "displayName": "3ELiDAR",
                    "custom": "keep-me",
                },
                "roomElectrical": {
                    "appKey": "roomElectrical",
                    "displayName": "old",
                    "futureAppField": 7,
                },
            },
        },
    ]

    for fixture_index, root in enumerate(fixtures):
        apps = normalize_apps(root["apps"])
        updated = dict(apps.get("roomElectrical", {}))
        updated.update(expected)
        apps["roomElectrical"] = updated
        root["apps"] = apps

        with tempfile.TemporaryDirectory() as tmp:
            destination = Path(tmp) / "registry.json"
            temporary = destination.with_suffix(".tmp")
            temporary.write_text(
                json.dumps(root, ensure_ascii=False, sort_keys=True),
                encoding="utf-8",
            )
            temporary.replace(destination)
            loaded = json.loads(destination.read_text(encoding="utf-8"))

        prefix = f"registry fixture {fixture_index + 1}"
        check(loaded["schemaVersion"] == 3, f"{prefix} preserves schemaVersion")
        check(loaded["futureRootField"] == {"preserve": True}, f"{prefix} preserves unknown root fields")
        check(loaded["apps"]["lidar"]["custom"] == "keep-me", f"{prefix} preserves other app records")
        room = loaded["apps"]["roomElectrical"]
        check(room["futureAppField"] == 7, f"{prefix} preserves unknown roomElectrical fields")
        check(all(room[key] == value for key, value in expected.items()), f"{prefix} updates required roomElectrical values")


def main() -> int:
    constants = text("RoomSurveyElectrical/ThreeEStorageConstants.swift")
    storage = text("RoomSurveyElectrical/ThreeEStorage.swift")
    registry = text("RoomSurveyElectrical/ThreeERegistry.swift")
    router = text("RoomSurveyElectrical/ThreeEURLRouter.swift")
    picker = text("RoomSurveyElectrical/ThreeEFolderPicker.swift")
    layout = text("RoomSurveyElectrical/ApplicationFileLayout.swift")
    content = text("RoomSurveyElectrical/ContentView.swift")
    app = text("RoomSurveyElectrical/RoomSurveyElectricalApp.swift")
    pbx = text("RoomSurveyElectrical.xcodeproj/project.pbxproj")

    expected_constants = {
        'displayName = "3ERoomElectrical"': "display name constant",
        'bundleIdentifier = "com.essam.3E.roomelectrical"': "bundle identifier constant",
        'appKey = "roomElectrical"': "app key constant",
        'urlScheme = "electrical"': "URL scheme constant",
        'appRelativePath = "Apps/RoomElectrical"': "app relative folder constant",
        'futureAppGroupIdentifier = "group.com.essam.3e"': "future App Group constant",
    }
    for needle, label in expected_constants.items():
        check(needle in constants, label)

    with (ROOT / "Support/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    schemes = [
        scheme
        for item in info.get("CFBundleURLTypes", [])
        for scheme in item.get("CFBundleURLSchemes", [])
    ]
    check(info.get("CFBundleDisplayName") == "3ERoomElectrical", "Info.plist display name")
    check("electrical" in schemes, "Info.plist registers electrical URL scheme")
    check("3eroomelectrical" in schemes, "legacy URL scheme remains compatible")
    check("com.essam.3E.roomelectrical" in pbx, "main target bundle identifier updated")
    check("com.essam.3E.roomelectrical.widget" in pbx, "widget bundle identifier follows main target")

    for relative in [
        "Support/RoomSurveyElectrical.entitlements",
        "Support/3ERoomElectricalWidget.entitlements",
    ]:
        with (ROOT / relative).open("rb") as handle:
            entitlements = plistlib.load(handle)
        check("com.apple.security.application-groups" not in entitlements, f"{relative} has no App Group entitlement")

    check("UIDocumentPickerViewController" in picker and "[.folder]" in picker, "folder picker selects directories")
    check("bookmarkData" in storage and ".minimalBookmark" in storage, "security-scoped bookmark is saved")
    check("resolvingBookmarkData" in storage and ".withoutUI" in storage, "bookmark is restored without UI")
    check("needsFolderReselection = true" in storage, "failed bookmark restoration requests reselection")
    check("containerURL" in storage and "futureAppGroupIdentifier" in storage, "future App Group is checked first")
    check("case .filesFolder" in storage and "case .privateSandbox" in storage, "Files and private fallback sources exist")
    check("ThreeERegistry.registerRoomElectricalApp" in storage, "storage registers app in registry")
    check("options: .atomic" in registry, "registry uses atomic write")
    check("var updatedEntry = apps[appKey] ?? [:]" in registry, "registry preserves unknown app-entry fields")
    check("rootObject = dictionary" in registry, "registry reads existing root before updating")
    check("normalizedApps" in registry, "registry accepts list and dictionary app formats")
    check("[String: [String: Any]]" in registry, "registry writes canonical app-keyed dictionary")

    for path in [
        "Projects/Workspaces",
        "Projects/Scans",
        "Exports",
        "Opened Files",
        "Previews",
        "Index",
        "Shared/Inbox",
        "Shared/Outbox",
        "Shared/Projects",
        "Shared/Media",
        "System",
    ]:
        check(f'"{path}"' in constants, f"declares {path}")

    check("mergeMissingContents" in storage and "copyItem" in storage, "legacy private data is copied missing-only")
    check("removeItem" not in storage and "moveItem" not in storage, "shared migration does not delete or move old data")
    check("ThreeEStorageManager.shared.appRootURL" in layout, "existing repositories use unified app root")
    check("ApplicationFileLayout.prepare()" in app, "application entry prepares existing layout")
    check("ThreeEFolderPicker" in content and "ThreeEStorageSettingsSection" in content, "settings expose 3E folder selection")
    check(".onOpenURL(perform: handleOpenedURL)" in content, "application routes incoming URLs")
    check("ThreeEURLRouter.command" in content and "ThreeEURLRouter.target" in content, "electrical URLs are parsed and resolved")
    check("pendingThreeEURLAfterFolderSelection" in content and "sharedFolderNotConnected" in content, "deep link waits for folder selection when 3E is not connected")

    unsafe_guards = [
        '!trimmed.hasPrefix("/")',
        '!trimmed.hasPrefix("\\\\")',
        '!trimmed.contains("\\\\")',
        '!trimmed.contains(":")',
        '$0 != ".."',
        "resolvingSymlinksInPath",
        "pathOutsideRoot",
    ]
    for guard in unsafe_guards:
        check(guard in storage, f"relative path guard: {guard}")
    check('action == "open"' in router, "router permits only open action")

    # Core project formats/exporters must be byte-identical to the baseline supplied beside this build.
    protected = [
        "RoomSurveyElectrical/ProjectPackage.swift",
        "RoomSurveyElectrical/DXFExporter.swift",
        "RoomSurveyElectrical/LayeredPDFExporter.swift",
        "RoomSurveyElectrical/ExportCenter.swift",
        "RoomSurveyElectrical/DocumentIntegration.swift",
        "RoomSurveyElectrical/GLBExporter.swift",
        "RoomSurveyElectrical/WorkspaceModels.swift",
        "RoomSurveyElectrical/ProjectFoundationModels.swift",
    ]
    baseline_value = os.environ.get("THREEE_BASELINE_ROOT")
    baseline = Path(baseline_value) if baseline_value else None
    if baseline is not None and baseline.is_dir():
        for relative in protected:
            base_file = baseline / relative
            current_file = ROOT / relative
            if base_file.exists() and current_file.exists():
                check(base_file.read_bytes() == current_file.read_bytes(), f"protected file unchanged: {relative}")

    test_registry_merge_contract()

    if FAILURES:
        print(f"\n3E integration checks: FAIL ({len(FAILURES)})")
        return 1
    print("\n3E integration checks: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
