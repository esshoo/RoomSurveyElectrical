# 3E Smart Embedding v1

## Scope of this phase

This phase makes every DXF exported from a workspace project carry the original
`.3eroom` project package. The visible geometry, layers, layouts, units, and
annotations are unchanged.

PDF associated-file embedding and import detection are intentionally deferred to
the next phase so DXF can be validated independently.

## DXF marker

The application registers this DXF APPID:

```text
3EROOMELECTRICAL
```

The package XRECORD also carries XDATA:

```text
1001 3EROOMELECTRICAL
1000 3EROOM_DXF_PACKAGE_V1
1070 1
```

## Named object dictionary

The root named object dictionary contains:

```text
3EROOMELECTRICAL -> smart project dictionary
```

The smart project dictionary contains two XRECORD values:

- `PROJECT_METADATA`: Base64-encoded JSON envelope.
- `PROJECT_PACKAGE`: binary `.3eroom` bytes in DXF group-code `310` chunks.

## Envelope

The envelope contains:

- format identifier and container version
- project UUID and name
- export date and app version
- embedded file name
- exact byte count
- SHA-256 of the embedded package
- package compression description

The current identifiers are:

```text
com.3essam.3eroomelectrical.dxf-package
3EROOM_DXF_PACKAGE_V1
```

## Integrity and compatibility

A future importer must:

1. Find the registered APPID or root dictionary entry.
2. Reassemble every `310` chunk in order.
3. Decode the metadata envelope.
4. Verify byte count and SHA-256.
5. Pass the recovered bytes to `ProjectPackageService.prepareImport`.

If the smart objects are stripped by another CAD program, the DXF remains a
normal drawing and can still be opened as geometry-only content.

## Mobile memory guard

Binary DXF chunks are represented as hexadecimal text, approximately doubling
the embedded package size. This implementation rejects packages above 256 MB to
avoid unsafe memory pressure during export on iPhone/iPad.


## AutoCAD compatibility correction (container revision 1)

The package XRECORD contains only normal DXF group codes below 1000:

- `300`: package marker `3EROOM_DXF_PACKAGE_V1`
- `90`: original package byte count
- `310`: binary package chunks, at most 127 bytes / 254 hex characters each

Do not place XDATA group codes (`1001`-`1071`) before `310` records. AutoCAD
interprets `1001` as the start of XDATA and requires extended data to follow the
normal object definition. The project is detected through the Named Object
Dictionary entry `3EROOMELECTRICAL`, so XDATA is unnecessary.
