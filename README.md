# 3ERoomElectrical v1.9.15.1 — Build 34

## Photographic scan corrective build

- The app now enters the normal electrical placement camera first.
- The photographic scan no longer appears as a modal step before electrical placement.
- A clear **تصوير الجدران** button is shown inside the electrical editor, with current coverage percentage.
- The first-time suggestion is an inline, non-blocking card with **ابدأ التصوير** and **لاحقًا**.
- Repeated taps are ignored while the shared AR camera workspace transitions.
- Electrical and photographic `ARSCNView` instances are detached in sequence instead of competing for the same `ARSession`.
- Duplicate photographic segment records are reconciled safely instead of causing a duplicate-key runtime trap.
- Capture projection is validated before Core Image perspective correction.
- The photographic bottom controls are larger and explicitly labelled.

## Test focus

Test entry to electrical mode, repeated presses on **تصوير الجدران**, repeated entry/exit from photographic mode, and the first automatic segment capture on a real iPhone.

## Unchanged systems

As-Built, Shop Drawing and new-installation logic; electrical placement and merging; existing ceiling-light capture; 2D manual/automatic lighting; interactive takeoff; DXF; PDF; PNG; current GLB geometry; widget and signing configuration remain unchanged.
