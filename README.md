# 3ERoomElectrical v1.9.16 — Build 36

## Compile fix

This patch fixes the Swift compiler error in `AdaptivePhotographicWallScanView.swift` where the `position` computed property did not explicitly return a `CGPoint` after declaring a local margin constant.

No capture, electrical, DXF, PDF, GLB, wall-photo storage or project-data behaviour was changed.

This source is built from **v1.9.14 Build 32**, not from the rejected v1.9.15/v1.9.15.1 capture flow.

### What changed

- No photographic prompt appears before or on entry to the electrical editor.
- A large, explicit **المسح الفوتوغرافي للجدران** button is available only inside the electrical camera editor.
- Wall squares are not captured in a fixed order. The square best aligned with the current camera view becomes active automatically.
- The active square is highlighted yellow, shows an on-square circular waiting/capture progress indicator and uses the message **انتظر قليلًا** while the phone stabilises.
- Captured squares turn green. Pending squares remain cyan.
- The header shows captured coverage and the exact number of remaining squares.
- When no remaining square is visible, a pulsing yellow edge arrow guides the user toward the nearest remaining square.
- Every captured square is perspective-corrected and stored separately.
- After every capture, the app rebuilds a wall composite image and automatically sets it as the wall photo appearance, so the result becomes visible on the wall in the existing 3D image layer.
- Manual/local photo import from v1.9.14 remains available as a fallback if the automatic scan is stopped or unsuitable.

### Isolation

The new scan implementation lives in separate source files:

- `AdaptivePhotographicWallScanView.swift`
- `WallPhotoCompositeBuilder.swift`

Only the minimum integration and optional project metadata were added to existing files. Electrical placement rules, ceiling lights, takeoff, DXF, PDF, PNG, GLB geometry and widget/signing code were not changed.

### Still deferred

- The dedicated wall-photo drawing layer inside the top-down 2D plan.
- Seam blending/colour matching between neighbouring squares.
- GLB texture export.

These remain the final photo-render/export step after this camera behaviour is verified on iPhone.