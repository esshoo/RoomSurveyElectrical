# 3ERoomElectrical v1.9.17 — Build 37

This source continues from the accepted **v1.9.16 Build 36** adaptive photographic scan.

## New in this build

- The Photos tab contains an option to show or hide RoomPlan furniture over captured wall photos.
- When hidden, furniture geometry is removed from the 3D view while the captured wall-photo layer is active, preventing duplicated furniture already visible in the photograph.
- The App settings tab contains **إبقاء الشاشة مضاءة أثناء المسح المكاني**. It applies only while RoomPlan is actively scanning and is reset during processing, backgrounding, cancellation, or navigation away.
- Photographic capture evaluation and rendering are thermally throttled.
- Core Image context reuse, image caching, compact internal project saves, deferred wall-composite generation, and on-demand 3D rendering reduce repeated CPU/GPU and storage work.

## Preserved behaviour

- Photographic squares remain direction-free and activate according to the camera view.
- Manual/local wall-photo import remains available.
- Electrical placement modes and rules are unchanged.
- DXF, PDF, PNG, GLB geometry, widget, and signing logic are unchanged.

See `Docs/3E-v1.9.17-photo-furniture-performance.md` for implementation details.
