# 3ERoomElectrical v1.8.1 Build 16

Build-fix release for the v1.8 document hub.

- Fixes SwiftUI `Section` header/footer construction in `ExternalDocumentOpenView.swift`.
- Keeps original DXF and PDF exporters unchanged.
- The obsolete `SmartProjectEmbedding.swift` file must not exist in the project.

# 3E Room Electrical — v1.8 Build 15

This source restores the original AutoCAD-compatible DXF and PDF exporters. It does not embed `.3eroom` packages or custom XRECORD objects inside exported drawings.

## Document hub

On launch the app creates this structure inside its iOS Documents container:

```text
3Essam/
└── 3ERoomElectrical/
    ├── Projects/
    │   ├── Workspaces/
    │   └── Scans/
    ├── Exports/
    ├── Opened Files/
    ├── Previews/
    └── Index/
```

Legacy folders are migrated automatically:

- `3ERoomElectricalProjects` → `Projects/Workspaces`
- `RoomSurveyProjects` → `Projects/Scans`

`UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` expose the Documents container in the iOS Files app.

## PDF, DXF and .3eroom opening

The app registers as:

- Owner/editor for `.3eroom`
- Alternate viewer for PDF
- Alternate viewer for DXF

Opening a PDF or DXF copies it into `Opened Files`, calculates SHA-256, and compares it with the local export registry.

## Export registry

Exported files are copied into `Exports/<format>` before sharing. The app records:

- SHA-256
- export method
- project ID and name
- scope and room IDs
- file size and export date

The registry identifies an unchanged export exactly even after the file is renamed or moved. No project package is embedded inside PDF or DXF.

When no local registry match exists, the app uses the existing PDF metadata or the known DXF brand/layer signature. It never labels a fallback match as an exact project restoration.

## Recent projects

The home screen includes a recent-project carousel. It renders and caches a static 3D preview from the latest USDZ scan when available and falls back to a 2D plan preview.
