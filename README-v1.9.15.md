# v1.9.15 Build 33 — Guided photographic wall scan

This is step 2 of 3 for the wall-photo system. It is intentionally focused on device capture and coverage testing before texture stitching/export is added.

## iPhone test checklist

1. Finish a new RoomPlan scan and enter the electrical camera editor.
2. Confirm the app asks whether to start **المسح الفوتوغرافي**. Choose **لاحقًا** once and verify the camera button can reopen it.
3. Start the photographic scan and verify every detected RoomPlan wall is divided into a grid sized from the wall dimensions.
4. Aim at the yellow segment. Verify guidance requests framing, distance, frontal angle and phone stability.
5. Keep the phone steady and verify only one automatic photo is saved for the current segment, then the yellow target advances.
6. Verify no continuous/random photo stream is created while moving the phone.
7. Use **تخطي**, close the scan, reopen it and verify the skipped segment becomes available again.
8. Open the normal scan viewer, choose **الصور**, and verify each wall card shows its photographic coverage percentage and captured/pending grid.
9. Open a wall and verify each captured segment appears as an individual photo tile.
10. Close/reopen the project and export/import `.3eroom`; verify coverage and captured segment images persist.

## Scope note

This build stores perspective-corrected photos per wall segment. It does not yet stitch adjacent segment photos into one final wall texture, render the photo layer in 2D, or embed textures in GLB. Those are step 3.
