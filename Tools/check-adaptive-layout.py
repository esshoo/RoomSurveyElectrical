#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
room_viewer = (root / "RoomSurveyElectrical" / "RoomViewer.swift").read_text()
electrical = (root / "RoomSurveyElectrical" / "ElectricalEditorView.swift").read_text()
photo = (root / "RoomSurveyElectrical" / "AdaptivePhotographicWallScanView.swift").read_text()

checks = {
    "room viewer uses geometry-driven layout": "adaptiveViewerLayout(size: geometry.size)" in room_viewer,
    "portrait viewer bar exists": "horizontalViewerControls" in room_viewer,
    "landscape side rail exists": "verticalViewerControls" in room_viewer,
    "viewer no longer uses bottom safe-area mode bar": ".safeAreaInset(edge: .bottom) {\n            viewerControls" not in room_viewer,
    "2D controls use actual viewport size": "controlsOverlay(viewSize: geometry.size)" in room_viewer,
    "2D add menu has compact mode": "editMenu(compact: compactHeight)" in room_viewer,
    "electrical editor has compact landscape chrome": "electricalChrome(size: geometry.size)" in electrical,
    "photo editor has compact landscape chrome": "adaptivePhotoChrome(size: geometry.size)" in photo,
}

failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"[{'PASS' if passed else 'FAIL'}] {name}")

if failed:
    raise SystemExit("Adaptive layout source checks failed: " + ", ".join(failed))
