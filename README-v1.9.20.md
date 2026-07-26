# 3ERoomElectrical v1.9.20 — Build 41

This build adds embedded wall appearances to GLB export.

- Wall photographs are resized to a maximum export dimension of 2048 px, JPEG-compressed, and embedded inside the GLB binary chunk.
- Solid wall colours and per-wall opacity are exported as glTF materials.
- Wall-photo geometry is generated as UV-mapped front overlays and split around detected door, window, and opening rectangles.
- All wall appearance nodes are grouped under a `Wall Photos and Colors` node so compatible viewers can hide or show the visual layer as one group.
- Electrical points, ceiling lights, doors, windows, and openings remain separate 3D nodes above the wall appearance.
- Export Center includes independent toggles for wall photos/colours and furniture.
- Multi-room GLB ZIP export applies the selected options to every room.
- Original project photographs are not modified.
- DXF, PDF, PNG, RoomPlan capture, photographic scanning, and electrical placement logic are unchanged.
