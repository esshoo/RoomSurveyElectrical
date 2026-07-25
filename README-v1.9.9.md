# 3ERoomElectrical v1.9.10 — Build 28

This release cleans the projects home screen and replaces the temporary R12 vector-text DXF path with a modern, editable Unicode DXF export.

## Home screen

The home screen now contains only working project content:

- recent projects
- all active projects
- archive access
- create, open, and import actions

Version information, LiDAR compatibility, supported file types, Bundle IDs, and complete Home Screen widget diagnostics are now inside **Settings → App**.

## DXF export

DXF export now targets **AutoCAD 2007 (`AC1021`)** and writes UTF-8 strings directly:

- Arabic is stored as real editable `MTEXT`
- ASCII labels and dimensions use `TEXT`
- `Arial.ttf` is referenced by the `3E_ARABIC` text style
- every graphical entity belongs to the `*Model_Space` block record
- no `LAYOUT`, `VIEWPORT`, Paper Space entity, or `OBJECTS` section is generated
- files retain independent CAD layers and metre units

The built-in validator checks the version, UTF-8 code page, Model Space ownership, modern entity subclasses, section order, and absence of Paper Space records before the file can be shared.

## PDF viewer

The full-screen PDF viewer keeps the explicit close button introduced in v1.9.8.

## Home Screen widget

The dynamic widget remains configured to display recent projects, preview images, scan counts, and room counts through the shared App Group. It will appear after the nested widget extension is signed with its own valid provisioning profile.

## Upgrade cleanup

When updating an older checkout, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Tools\Clean-ObsoleteFiles.ps1
```

A full iOS build still needs Xcode or GitHub Actions.
