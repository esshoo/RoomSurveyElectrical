# 3E Smart Embedding V1

This document describes how 3E Room Electrical stores a recoverable project
package inside exported DXF and PDF files without changing the visible drawing.

## Common Marker

- Marker: `3EROOM_PROJECT_PACKAGE_V1`
- App ID: `3EROOMELECTRICAL`
- Embedded package filename: `3ERoomElectrical.project.3eroom`
- Package format: the same `.3eroom` ZIP package exported by the app
- Integrity: read `packageSHA256` from the manifest and verify the extracted
  package bytes before import

## Manifest

The embedded manifest is JSON encoded as UTF-8. It includes:

- `formatIdentifier`
- `formatVersion`
- `marker`
- `application`
- `readableBy`
- `packageFileName`
- `packageByteCount`
- `packageSHA256`
- `packageEncoding`
- `projectID`
- `projectName`
- `projectCreatedAt`
- `exportedAt`

## DXF Storage

DXF exports use standard DXF mechanisms only:

- Register `APPID`: `3EROOMELECTRICAL`
- Store data in the `OBJECTS` section
- Add a root `DICTIONARY` entry named `3EROOMELECTRICAL_PACKAGE`
- The entry points to an `XRECORD` with handle `E3E001`

The `XRECORD` uses repeated group code `1` strings:

1. `3EROOM_PROJECT_PACKAGE_V1`
2. `MANIFEST_BASE64_BEGIN`
3. Base64 manifest chunks
4. `MANIFEST_BASE64_END`
5. Group code `90`: raw package byte count
6. Group code `90`: package Base64 chunk count
7. `PACKAGE_BASE64_BEGIN`
8. Base64 package chunks
9. `PACKAGE_BASE64_END`

Readers should concatenate chunks between the begin/end markers, Base64-decode
the package, then verify SHA-256.

## PDF Storage

Layered 2D PDF exports use standard PDF mechanisms:

- Catalog `/Names << /EmbeddedFiles ... >>`
- Catalog `/AF [...]`
- `/Filespec` with `/AFRelationship /Data`
- `/EmbeddedFile` stream containing raw `.3eroom` package bytes
- Catalog `/Metadata` XMP stream containing the marker and package SHA-256

Readers should look for the embedded file named
`3ERoomElectrical.project.3eroom`, verify SHA-256 against XMP/manifest data,
then import it as a normal `.3eroom` package.

## Compatibility

The visible DXF/PDF drawing must remain valid without the embedded package.
If another CAD/PDF application strips the custom data while saving, the file is
still viewable, but full project recovery will no longer be available.
