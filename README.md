# 3ERoomElectrical v1.9.18 — Build 38

This source continues from **v1.9.17 Build 37**.

## New in this build

- App settings now include three performance/quality profiles:
  - **موفر للطاقة**
  - **متوازن**
  - **جودة عالية**
- The selected profile controls photographic-scan rendering/evaluation, stored photographic image size, wall-composite resolution, and 3D viewer frame rate/antialiasing.
- Spatial-scan content can be set to:
  - **غرفة كاملة**
  - **حوائط وفتحات فقط**
- Architecture-only scans retain walls, floors, doors, windows, and openings while excluding RoomPlan furniture from the saved project, takeoff, 2D/3D overlays, and app exports.
- Architecture-only scans do not retain raw RoomPlan diagnostic data, reducing project storage and post-scan memory work.
- The scan screen shows the active content mode.
- Existing projects and settings remain backward compatible; missing new values default to **متوازن** and **غرفة كاملة**.

## Important RoomPlan limitation

RoomPlan does not currently expose a configuration option that disables object recognition itself. Architecture-only mode therefore discards furniture after RoomPlan processes the room; it reduces app-side saving, rendering, takeoff, and export work, but cannot guarantee a reduction in Apple framework recognition work during the live scan.

## Preserved behaviour

- Adaptive photographic capture remains direction-free.
- Manual/local wall-photo import remains available.
- Electrical placement modes and rules are unchanged.
- DXF and electrical geometry logic are unchanged.

See `Docs/3E-v1.9.18-performance-quality-scan-scope.md`.
