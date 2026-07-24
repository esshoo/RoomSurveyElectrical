# 3E Document Hub v1

## Principle

PDF and DXF remain standard export files. No `.3eroom` archive, XRECORD payload, or binary project package is embedded into either format.

## Exact recognition

At export time the app calculates SHA-256 after the file is complete and stores an `ExportRegistryRecord` locally. SHA-256 continues to match when a file is renamed or moved without changing its bytes.

An exact registry record includes:

- export kind
- workspace project ID and name
- scope item ID
- room IDs
- file size
- export time
- relative saved path

## Fallback recognition

When a file has no registry record on the current device:

- PDF: inspect the existing `3ERoomElectrical` creator/producer metadata.
- DXF: inspect the existing `3Essam` drawing brand and the known 3E layer signature.

Fallback recognition proves that the format resembles a 3E export, but it is not presented as an exact original-project recovery.

## DXF deterministic analysis

The parser reads ASCII DXF as a stream and does not load the complete file into memory. It counts only entities that the 3E exporter creates deterministically:

- `LINE` on `WALLS`, `DOORS`, `WINDOWS`, and `OPENINGS`
- floor and furniture polylines
- `CIRCLE` on existing/proposed electrical layers
- `CIRCLE` on the ceiling-lighting layer

## iOS storage

The app owns its Documents container. With `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`, the container appears in Files. The internal path is:

```text
3Essam/3ERoomElectrical
```

An iOS app cannot silently create a separate top-level folder outside its own container. A user-selected external directory would require a document picker and a persisted security-scoped bookmark.
