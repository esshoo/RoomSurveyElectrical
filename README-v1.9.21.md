# 3ERoomElectrical v1.9.21 — Build 42

This build improves photographic wall composites without modifying original segment photographs.

- Adds per-segment image quality analysis using exposure, clipping, contrast, edge detail, and the existing geometric capture score.
- Shows good, weak, and missing segment counts for every wall.
- Lets the user mark only weak segments for recapture; the next photographic scan targets those marked segments together with any missing segments.
- Keeps previous segment photographs when a replacement is captured, preserving the original source material.
- Adds manual rebuilding of the wall composite from the Photos tab.
- Normalises colour balance between adjacent segment photographs with conservative channel correction.
- Softens internal tile seams using a low-opacity feathered overlap while retaining an opaque base pass.
- Processes segments one at a time with autorelease pools and a shared Core Image context to limit temporary memory and heat.
- Leaves RoomPlan scanning, electrical placement, DXF, PDF, PNG, 2D/3D layers, and GLB export geometry unchanged.
