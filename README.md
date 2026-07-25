# 3ERoomElectrical v1.9.14 — Build 32

## Wall photos foundation — Step 1 of 3

- The scan viewer now has a third bottom tab named **الصور** beside 2D and 3D.
- Every RoomPlan wall receives backward-compatible visual metadata and a user-editable display name.
- Each wall card shows a true elevation preview using the wall width/height ratio.
- Doors, windows, openings and electrical devices are drawn above the photo or colour preview so visual media never hides project additions.
- A wall can use the default material, an imported wall photo or a fixed user-selected colour.
- Multiple photos may be stored for one wall and one can be selected as the active photo.
- The active image can be shared/saved for external editing, then returned through the photo picker as a replacement version.
- The 3D viewer can focus the selected wall and renders imported photos or fixed colours as a separate visual overlay.
- The 3D wall overlay is cut around rectangular RoomPlan openings instead of covering doors and windows.
- A **صور وألوان الجدران** visibility toggle was added to the viewer layers.
- Full-size and thumbnail JPEG files are kept inside the scan directory and included in `.3eroom` project packages.

## Planned remaining steps

1. **Photographic scan:** guided automatic capture, adaptive wall/surface segmentation, quality scoring, cropping and coverage completion.
2. **Final visual pipeline:** photo layer rendering in 2D, stitched textures and textured GLB export.

## Safety scope

This build does not change electrical placement rules, ceiling-light placement, takeoff calculations, DXF, layered PDF, PNG, existing GLB geometry, widget code or signing configuration.
