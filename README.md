# 3ERoomElectrical v1.9.15 — Build 33

## Guided photographic wall scan — Step 2 of 3

- After a RoomPlan scan reaches the electrical camera editor, the app offers to start **المسح الفوتوغرافي**.
- The feature can be reopened at any time from the camera/viewfinder button without changing electrical placement modes.
- Every planar wall detected by RoomPlan is divided into an adaptive rectangular grid based on its measured width and height.
- Angled returns, column faces, protrusions or recess faces that RoomPlan reports as separate wall planes receive their own independent grid.
- The app targets one highlighted segment at a time and does not save a continuous random stream of camera images.
- Automatic capture requires normal AR tracking, complete framing, adequate projected size, a sufficiently frontal view and a stable phone.
- The guide grid is hidden before capture; Core Image perspective correction crops the saved image to the four projected corners of the active segment.
- Each saved JPEG is linked to its wall and segment, while the segment records capture state, quality score and capture time.
- Skipped segments advance the workflow but become available again the next time the photographic scan is opened.
- The **الصور** tab now shows per-wall coverage and a coloured captured/pending/skipped segment grid.
- Captured segment photos remain separate in this build so their quality and geometric mapping can be tested safely on iPhone.

## Remaining final step

- Stitch or compose neighbouring segment photos into final wall textures.
- Render the dedicated image layer in 2D and the completed textures in 3D without covering electrical/lighting overlays.
- Export textured GLB assets with the wall images included.

## Safety scope

This build does not modify As-Built, Shop Drawing or new-installation rules; electrical merging; ceiling-light placement; takeoff calculations; DXF; layered PDF; PNG; current GLB geometry; widget code; or signing configuration.
