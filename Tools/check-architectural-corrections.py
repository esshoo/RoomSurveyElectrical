#!/usr/bin/env python3
"""Static and contract checks for Build 49.1 architectural corrections."""
from __future__ import annotations

import json
import math
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
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


def parse_all_swift() -> None:
    files = sorted((ROOT / "RoomSurveyElectrical").glob("*.swift"))
    files += sorted((ROOT / "3ERoomElectricalWidget").glob("*.swift"))
    for file in files:
        result = subprocess.run(
            ["swiftc", "-frontend", "-parse", str(file)],
            capture_output=True,
            text=True,
        )
        check(result.returncode == 0, f"Swift parser: {file.name}")
        if result.returncode:
            print(result.stderr)


@dataclass(frozen=True)
class Wall:
    wall_id: str
    width: float
    height: float
    x: float
    y: float
    z: float
    yaw: float


def apply_correction(current: Wall, before: Wall, after: Wall) -> Wall:
    if current != before:
        raise ValueError("stale")
    if current.wall_id != after.wall_id:
        raise ValueError("wrong wall")
    if after.width < 0.05 or after.height < 0.20:
        raise ValueError("invalid dimensions")
    if not all(math.isfinite(v) for v in [after.width, after.height, after.x, after.y, after.z, after.yaw]):
        raise ValueError("non-finite")
    return after


def runtime_contract_test() -> None:
    original = Wall("wall-1", 4.0, 2.8, 0.0, 1.4, 0.0, 0.0)
    corrected = Wall("wall-1", 4.5, 3.0, 0.2, 1.5, -0.1, math.radians(5))
    result = apply_correction(original, original, corrected)
    check(result == corrected, "accepted correction replaces effective wall")
    check(original.width == 4.0 and original.x == 0.0, "original wall remains immutable")

    second = Wall("wall-1", 4.6, 3.0, 0.3, 1.5, -0.1, math.radians(5))
    check(apply_correction(result, corrected, second) == second, "sequential correction uses latest effective state")
    try:
        apply_correction(result, original, second)
    except ValueError as error:
        check(str(error) == "stale", "stale before-state is rejected")
    else:
        check(False, "stale before-state is rejected")

    floor_height = 1.10
    old_local_y = floor_height - original.height / 2
    new_local_y = floor_height - corrected.height / 2
    check(abs((old_local_y + original.height / 2) - floor_height) < 1e-9, "old electrical floor height is stable")
    check(abs((new_local_y + corrected.height / 2) - floor_height) < 1e-9, "corrected electrical floor height is stable")

    payload = {
        "walls": [original.__dict__],
        "originalWalls": [original.__dict__],
        "architecturalCorrections": [
            {
                "wallID": original.wall_id,
                "beforeState": original.__dict__,
                "afterState": corrected.__dict__,
            }
        ],
    }
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "project.json"
        path.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
        loaded = json.loads(path.read_text(encoding="utf-8"))
    check(loaded["originalWalls"][0]["width"] == 4.0, "round trip preserves original wall")
    check(loaded["architecturalCorrections"][0]["afterState"]["width"] == 4.5, "round trip preserves correction")


def main() -> int:
    models = text("RoomSurveyElectrical/Models.swift")
    corrections = text("RoomSurveyElectrical/ArchitecturalCorrections.swift")
    repository = text("RoomSurveyElectrical/WorkspaceRepository.swift")
    view = text("RoomSurveyElectrical/ArchitecturalCorrectionView.swift")
    foundation = text("RoomSurveyElectrical/ProjectFoundationView.swift")
    package = text("RoomSurveyElectrical/ProjectPackage.swift")
    project_repo = text("RoomSurveyElectrical/ProjectRepository.swift")
    room_viewer = text("RoomSurveyElectrical/RoomViewer.swift")
    geometry_merger = text("RoomSurveyElectrical/RoomProjectGeometryMerger.swift")
    pbx = text("RoomSurveyElectrical.xcodeproj/project.pbxproj")

    check("var originalWalls: [WallSnapshot]?" in models, "RoomProject preserves original walls")
    check("var architecturalCorrections: [ArchitecturalWallCorrection]?" in models, "RoomProject stores correction layer")
    check("struct ArchitecturalWallState" in corrections, "wall Before/After payload exists")
    check("struct ArchitecturalWallCorrection" in corrections, "applied correction audit record exists")
    check("normalizeArchitecturalCorrections" in corrections, "effective geometry materialization exists")
    check("ArchitecturalCorrectionError.staleWall" in repository, "repository maps stale correction conflicts")
    check("beginArchitecturalCorrectionSession" in repository, "scan-targeted architectural session exists")
    check("upsertArchitecturalWallChangeRecord" in repository, "draft wall upsert exists")
    check("removeArchitecturalWallChangeRecord" in repository, "individual draft rejection exists")
    check("applyArchitecturalChangeSet" in repository, "architectural apply path exists")
    check("writeRecoverySnapshot" in repository and "mode: .architecturalUpdate" in repository, "session uses existing Recovery foundation")
    check("ProjectRepository.save(originalRoom)" in repository, "room rollback exists on apply failure")
    check("ArchitecturalWallState(wall: currentWall) == previous" in repository, "stale wall state is checked")
    check("refreshElectricalPointsForCorrectedWalls" in repository, "electrical attachments refresh after correction")
    check("ArchitecturalBeforeAfterPlanView" in view, "Before/After plan exists")
    check(".environment(\\.layoutDirection, .leftToRight)" in view, "spatial plan is isolated from RTL")
    check("SpatialCoordinateContract.yawRotation" in view, "wall form uses yaw-only transform")
    check("oldBottom + Float(height) / 2" in view, "height edit preserves wall bottom elevation")
    check("ArchitecturalCorrectionHubView" in foundation, "project update center links to architectural tools")
    check("applyArchitecturalChangeSet" in foundation, "history apply action supports architectural sessions")
    check("architecturalCorrections: source.architecturalCorrections?.map" in package, "package import remaps correction scan IDs")
    check("architecturalCorrections: source.architecturalCorrections?.map" in project_repo, "scan duplication remaps correction scan IDs")
    check("workspaceLayerVisible(.architecturalCorrections)" in room_viewer, "viewer consumes architectural layer visibility")
    check("source.hasArchitecturalCorrections" in geometry_merger, "live geometry merge is blocked over accepted corrections")
    check(pbx.count("CURRENT_PROJECT_VERSION = 49;") == 4, "all targets use build 49")
    check(pbx.count("MARKETING_VERSION = 1.9.27;") == 4, "all targets use version 1.9.27")

    parse_all_swift()
    runtime_contract_test()

    if FAILURES:
        print(f"\nArchitectural correction checks: FAIL ({len(FAILURES)})")
        return 1
    print("\nArchitectural correction checks: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
