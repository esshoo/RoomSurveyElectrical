#!/usr/bin/env python3
"""Validate a 3ERoomElectrical pure Model Space R12 DXF.

Dependency-free so it can run on Windows and GitHub Actions.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

GRAPHICAL = {
    "LINE", "POLYLINE", "CIRCLE", "ARC", "TEXT", "POINT",
}
FORBIDDEN_RECORDS = {"LAYOUT", "VIEWPORT", "LWPOLYLINE"}
FORBIDDEN_SECTIONS = {"CLASSES", "OBJECTS"}


@dataclass
class Record:
    section: str | None
    kind: str
    pairs: list[tuple[int, str]]

    def first(self, code: int) -> str | None:
        for current_code, value in self.pairs:
            if current_code == code:
                return value
        return None


def read_pairs(path: Path) -> list[tuple[int, str]]:
    text = path.read_text(encoding="utf-8", errors="strict")
    lines = text.splitlines()
    if len(lines) % 2:
        raise ValueError("Odd line count: incomplete DXF group-code pair")
    result: list[tuple[int, str]] = []
    for index in range(0, len(lines), 2):
        try:
            code = int(lines[index].strip())
        except ValueError as exc:
            raise ValueError(
                f"Invalid group code at line {index + 1}: {lines[index]!r}"
            ) from exc
        result.append((code, lines[index + 1].strip()))
    return result


def records(pairs: list[tuple[int, str]]) -> tuple[list[Record], list[str]]:
    result: list[Record] = []
    sections: list[str] = []
    section: str | None = None
    kind: str | None = None
    current: list[tuple[int, str]] = []
    index = 0

    def finish() -> None:
        nonlocal kind, current
        if kind is not None:
            result.append(Record(section, kind, current))
        kind = None
        current = []

    while index < len(pairs):
        code, value = pairs[index]
        upper = value.upper()
        if code == 0:
            finish()
            if upper == "SECTION":
                if index + 1 >= len(pairs) or pairs[index + 1][0] != 2:
                    raise ValueError("SECTION is missing its group-code 2 name")
                section = pairs[index + 1][1].upper()
                sections.append(section)
                index += 2
                continue
            if upper == "ENDSEC":
                section = None
                index += 1
                continue
            if upper not in {"EOF", "TABLE", "ENDTAB"}:
                kind = upper
        elif kind is not None:
            current.append((code, value))
        index += 1
    finish()
    return result, sections


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("dxf", type=Path)
    args = parser.parse_args()

    if not args.dxf.is_file():
        parser.error(f"File does not exist: {args.dxf}")

    pairs = read_pairs(args.dxf)
    parsed, sections = records(pairs)
    errors: list[str] = []

    required = ["HEADER", "TABLES", "BLOCKS", "ENTITIES"]
    for section in required:
        if section not in sections:
            errors.append(f"Missing required section: {section}")
    for section in FORBIDDEN_SECTIONS:
        if section in sections:
            errors.append(f"Forbidden layout-related section exists: {section}")

    model = [
        record for record in parsed
        if record.section == "ENTITIES" and record.kind in GRAPHICAL
    ]
    forbidden_records = [
        record for record in parsed if record.kind in FORBIDDEN_RECORDS
    ]
    if forbidden_records:
        errors.append(
            "Forbidden records: "
            + ", ".join(sorted({r.kind for r in forbidden_records}))
        )

    if not model:
        errors.append("ENTITIES contains no Model Space geometry")

    if any(code == 67 and value == "1" for code, value in pairs):
        errors.append("Paper Space group code 67=1 exists")
    if any(code == 410 for code, _ in pairs):
        errors.append("Layout name group code 410 exists")
    if any(code == 0 and value.upper() == "LAYOUT" for code, value in pairs):
        errors.append("LAYOUT object exists")

    marker = any(
        code == 999 and value == "3ERoomElectrical v1.9.5 PURE_MODEL_UTF8"
        for code, value in pairs
    )
    if not marker:
        errors.append("v1.9.5 PURE_MODEL_UTF8 marker is missing")

    acadver = None
    for i, (code, value) in enumerate(pairs[:-1]):
        if code == 9 and value == "$ACADVER" and pairs[i + 1][0] == 1:
            acadver = pairs[i + 1][1]
            break
    if acadver != "AC1021":
        errors.append(f"Expected AC1021, got {acadver!r}")

    print(f"File: {args.dxf}")
    print(f"Sections: {', '.join(sections)}")
    print(f"Model-space graphical records: {len(model)}")
    print(f"Forbidden layout records: {len(forbidden_records)}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    print("Pure Model UTF-8 DXF: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
