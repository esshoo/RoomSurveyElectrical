# 3ERoomElectrical DXF Viewer and Widget — Format/Integration Notes v1

## DXF policy

3ERoomElectrical exports plain ASCII DXF. No `.3eroom` archive, application dictionary, or binary project payload is stored in the drawing.

The current writer declares `AC1027` and therefore emits a complete modern structure, including Model Space records, block ownership, layout objects, stable handles, and subclass markers. The compatibility validator runs before files are returned to the export UI.

## DXF viewer scope

The first native viewer renders LINE, LWPOLYLINE, CIRCLE, TEXT, and MTEXT entities from the ENTITIES section. Other entity types are counted and reported but are not fabricated or approximated.

Layer visibility is viewer state only; opening or viewing a file never modifies the DXF.

## Widget data contract

The main app writes `recent-projects.json` and optional PNG preview files into the App Group container. The WidgetKit extension reads the same snapshot and never opens the app's private Documents container directly.

Snapshot fields:

- project UUID
- project name
- project kind and symbol
- scan count
- room count
- last update date
- optional preview filename

The widget deep-links to `3eroomelectrical://projects`.
