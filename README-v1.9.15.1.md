# v1.9.15.1 Build 34 — Photographic scan launch and crash fix

This corrective build keeps step 2 of the wall-photo system but fixes the device workflow reported from iPhone testing.

## Corrected workflow

1. Complete RoomPlan and enter the normal electrical camera editor first.
2. The photographic option is shown inside that editor as a non-blocking card, not as a screen or sheet before electrical placement.
3. A large, clearly labelled **تصوير الجدران** button remains available in the electrical action area.
4. One tap starts the photographic scan. Repeated taps are ignored while the shared AR camera view is transitioning.
5. **إنهاء والعودة للكهرباء** returns through the same protected transition.

## Crash hardening

- Removed the bottom-sheet start button and automatic modal offer that could be tapped repeatedly while dismissing.
- Added a transition interval so two `ARSCNView` instances are not mounted on the same shared `ARSession` simultaneously.
- Explicitly detaches the outgoing SceneKit view without pausing the shared RoomPlan session.
- Replaced duplicate-key `Dictionary(uniqueKeysWithValues:)` initializers in photographic segment restoration with non-trapping reconciliation.
- Prevented duplicated `CADisplayLink` instances and cancelled capture state during view dismantling.
- Added finite-corner, viewport and polygon-area checks before perspective correction.
- Removed duplicate project saves from every photographic segment update.
- Enlarged and clarified the automatic-capture and return controls.

## iPhone regression checklist

1. Finish RoomPlan and confirm the electrical camera editor is visible and usable before any photographic prompt.
2. Add or inspect an electrical point to confirm the existing workflow is active.
3. Press **تصوير الجدران** once and confirm the app transitions without closing.
4. Rapidly tap the launch area and confirm only one transition occurs.
5. Enter/exit photographic mode three times and confirm the app returns to electrical mode each time.
6. Capture one segment and confirm it advances without closing the app.
7. Reopen a project containing duplicated or interrupted photographic segment records and confirm it no longer crashes.

No changes were made to electrical rules, ceiling-light rules, takeoff, DXF, PDF, PNG, GLB geometry, widgets or signing.
