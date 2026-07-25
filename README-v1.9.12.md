# 3ERoomElectrical v1.9.12 — Build 30

This release supersedes the experimental v1.9.11 camera-lighting change. It is rebuilt directly from the stable v1.9.10 source and adds only **existing ceiling-light capture after RoomPlan scanning**.

## Camera ceiling-light capture

- Tap a detected ceiling directly in the post-scan camera editor.
- Confirm **Existing ceiling light – As-Built**.
- The light is stored using the same `CeilingLight` model used by the 2D editor.
- Camera lights are never treated as New Installation or proposed Shop Drawing items.
- Socket, switch, wall-light, door-offset, opening-avoidance, and merge rules are unchanged.
- Undo removes the last camera ceiling light without changing the existing wall-point workflow.

## Compatibility model

`CeilingLight` now has an optional source marker:

- `cameraExisting`
- `planManual`
- `planAutomatic`

The property is optional so projects created by older versions continue to decode. Legacy lights are inferred from their existing manual/automatic placement mode.

## 2D and takeoff

- Existing camera lights have a green outline in the 2D plan.
- Manual 2D design remains white.
- Automatic 2D design remains blue.
- Takeoff separates existing camera lights from manual and automatic proposed lighting.

## Unchanged systems

This release does not modify:

- DXF export or validation
- PDF export or viewer
- widget code or signing
- electrical design modes
- wall-device placement rules
- automatic 2D lighting distribution

A full iOS build still requires Xcode or GitHub Actions.
