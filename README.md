# 3ERoomElectrical v1.9.1 (Build 18)

## Important upgrade cleanup

Before building over an older checkout, remove the obsolete source file:

```powershell
powershell -ExecutionPolicy Bypass -File .\Tools\Clean-ObsoleteFiles.ps1
```

The removed file is `RoomSurveyElectrical/SmartProjectEmbedding.swift`. It belongs to the abandoned embedded-project experiment and is not part of v1.9.1.

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

A sideload/re-signing tool must sign both the app and nested widget extension and preserve the App Group entitlements. Without the shared entitlement, the widget can still install but cannot receive recent-project data from the main app.

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
- actual single, combined, and layout DXF generation through the exporter
- independent DXF import tests
- ZIP integrity validation

A full Xcode/iOS build must still be run by GitHub Actions or Xcode because this preparation environment is not macOS.
