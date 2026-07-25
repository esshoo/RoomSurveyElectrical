# 3ERoomElectrical v1.9.7 — Build 25

## DXF viewer

- Reads classic AutoCAD R12 `POLYLINE` / `VERTEX` / `SEQEND` sequences.
- Displays furniture outlines and Arabic vector glyph contours exported by v1.9.6+.
- Keeps support for `LINE`, `LWPOLYLINE`, `CIRCLE`, `TEXT`, and `MTEXT`.

## DXF size

- Arabic remains vector geometry so the file stays compatible with strict R12 readers.
- CoreText curves use five samples instead of ten.
- Near-duplicate and effectively collinear contour points are removed.
- Numeric coordinates use four decimal places (0.1 mm when the drawing unit is metres).

This makes Arabic vector DXF files substantially smaller, although they will naturally remain larger than a text-only DXF.

## Home-screen widget

The in-app diagnostic proved that Sideloadly preserved the `.appex` bundle but did not embed an independent `embedded.mobileprovision` for it. iOS therefore does not register the widget. This is a signing/provisioning limitation after the build, not a WidgetKit source-code failure. Use a signer that provisions app extensions separately (for example SideStore/AltStore) or standard Apple Developer/Xcode signing.
