# 3ERoomElectrical v1.9.4 Build 21

## Important upgrade cleanup

Before building over an older checkout, remove the obsolete source file:

```powershell
powershell -ExecutionPolicy Bypass -File .\Tools\Clean-ObsoleteFiles.ps1
```

The removed file is `RoomSurveyElectrical/SmartProjectEmbedding.swift`. It belongs to the abandoned embedded-project experiment and is not part of v1.9.2.

## v1.9.2 fixes

- Added an explicit **إغلاق** action to the full-screen DXF viewer.
- Moved paper-space viewports and annotations from `BLOCKS` to `ENTITIES`.
- Tagged every exported graphical entity with its Model or paper layout.
- Added validation that every DXF contains real Model Space geometry.
- Made the Model Space combined export the first multi-room DXF option.
- Added strict widget-extension bundle checks to GitHub Actions.
- Added installed-widget diagnostics inside the main app.
- Added Windows tools for checking a DXF and inspecting the final signed IPA.

See `Docs/3E-v1.9.2-runtime-fixes.md`.

# 3ERoomElectrical v1.9 Build 17

This release adds a native DXF viewer, repairs the DXF writer for strict AutoCAD-compatible structure, and adds a real WidgetKit Home Screen widget for recent projects.

## 1. Strict DXF export

The exporter no longer writes a minimal modern DXF that only tolerant viewers accept. Every generated DXF now includes the modern sections and ownership structure expected by strict readers:

```text
HEADER
CLASSES
TABLES
BLOCKS
ENTITIES
OBJECTS
EOF
```

The file contains Model Space table/block records, handles, owners, and entity subclass markers. A built-in validator checks every DXF before it is written; an invalid drawing is rejected instead of being shared.

The exported drawing does **not** contain embedded `.3eroom` data or custom project XRECORD payloads.

## 2. Native DXF viewer

Opening a `.dxf` file now offers **Open DXF Viewer**. The viewer supports:

- LINE
- LWPOLYLINE
- CIRCLE
- TEXT and MTEXT
- layer visibility controls
- pan and pinch zoom
- double-tap or toolbar fit-to-screen
- layer/entity counters and unsupported-entity notice

The renderer is optimized for the layers produced by 3ERoomElectrical while remaining able to display supported entities from ordinary ASCII DXF files.

## 3. iPhone Home Screen widget

A new `3ERoomElectricalWidgetExtension` target provides small, medium, and large widgets showing recent projects. It uses a cached 3D preview when available and falls back to project artwork.

Shared widget data uses this App Group:

```text
group.com.personal.roomsurveyelectrical
```

Before distribution, enable that App Group for both identifiers in the Apple Developer portal:

```text
com.personal.roomsurveyelectrical
com.personal.roomsurveyelectrical.widget
```

A sideload/re-signing tool must sign both the app and nested widget extension and preserve the App Group entitlements. The final provisioning profiles must authorize the App Group for both the main app and the widget extension. A signer that drops the nested extension or rewrites only the main bundle identifier prevents iOS from registering the widget.

## 4. Existing document hub retained

The v1.8 document hub remains in place:

```text
3Essam/
└── 3ERoomElectrical/
    ├── Projects/
    ├── Exports/
    ├── Opened Files/
    ├── Previews/
    └── Index/
```

PDF and DXF exports remain free of embedded project packages. The local SHA-256 export registry continues to identify unchanged files exported on the same installation.

## Build status

The source has passed:

- Swift syntax parsing for all app and widget files
- plist and Xcode project validation
- DXF validator round-trip tests
- static Model/Paper Space structure checks
- dependency-free DXF model-space validation
- ZIP integrity validation

A full Xcode/iOS build must still be run by GitHub Actions or Xcode because this preparation environment is not macOS.

## v1.9.3 changes

- DXF export is Model Space only; Paper Space/Layout export is disabled.
- The legacy Layout export function now emits the combined Model Space drawing.
- Model entities omit optional group code 67 and do not carry Paper Space tags.
- The export validator rejects every Paper Space entity.
- Widget gallery name now matches the application name.
- `Tools/inspect-signed-ipa.py` diagnoses widget loss during signing.


## v1.9.4 pure compatibility test

- DXF export is now an ASCII AutoCAD R12 (`AC1009`) file.
- Every graphical entity is written directly in `ENTITIES`; no `LAYOUT`, `VIEWPORT`, `OBJECTS`, `CLASSES`, group `67`, or group `410` is emitted.
- Classic `POLYLINE` / `VERTEX` / `SEQEND` records replace `LWPOLYLINE`.
- Exported names include `PureModel-R12`, and the file includes the marker `3ERoomElectrical v1.9.4 PURE_MODEL_R12`.
- The Home Screen widget is intentionally static and has no App Group or custom entitlements, to isolate Sideloadly extension signing.
