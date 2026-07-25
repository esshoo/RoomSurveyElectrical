#!/usr/bin/env python3
"""Validate a 3ERoomElectrical AutoCAD 2007 UTF-8 Model Space DXF."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

GRAPHICAL = {"LINE", "LWPOLYLINE", "CIRCLE", "ARC", "TEXT", "MTEXT", "POINT"}
EXPECTED_SUBCLASS = {
    "LINE": "AcDbLine",
    "LWPOLYLINE": "AcDbPolyline",
    "CIRCLE": "AcDbCircle",
    "ARC": "AcDbArc",
    "TEXT": "AcDbText",
    "MTEXT": "AcDbMText",
    "POINT": "AcDbPoint",
}
FORBIDDEN_RECORDS = {"LAYOUT", "VIEWPORT"}


@dataclass
class Record:
    section: str | None
    kind: str
    pairs: list[tuple[int, str]]

    def values(self, code: int) -> list[str]:
        return [value for current_code, value in self.pairs if current_code == code]

    def first(self, code: int) -> str | None:
        values = self.values(code)
        return values[0] if values else None


def read_pairs(path: Path) -> list[tuple[int, str]]:
    text = path.read_text(encoding="utf-8")
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
        result.append((code, lines[index + 1]))
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


def header_value(pairs: list[tuple[int, str]], variable: str) -> str | None:
    for index, (code, value) in enumerate(pairs[:-1]):
        if code == 9 and value == variable:
            return pairs[index + 1][1]
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("dxf", type=Path)
    args = parser.parse_args()

    if not args.dxf.is_file():
        parser.error(f"File does not exist: {args.dxf}")

    pairs = read_pairs(args.dxf)
    parsed, sections = records(pairs)
    errors: list[str] = []

    required = ["HEADER", "CLASSES", "TABLES", "BLOCKS", "ENTITIES"]
    for section in required:
        if section not in sections:
            errors.append(f"Missing required section: {section}")
    if "OBJECTS" in sections:
        errors.append("OBJECTS section must not be emitted")

    if header_value(pairs, "$ACADVER") != "AC1021":
        errors.append("$ACADVER is not AC1021")
    if (header_value(pairs, "$DWGCODEPAGE") or "").upper() != "UTF-8":
        errors.append("$DWGCODEPAGE is not UTF-8")

    forbidden = [record for record in parsed if record.kind in FORBIDDEN_RECORDS]
    if forbidden:
        errors.append(
            "Forbidden records: " + ", ".join(sorted({r.kind for r in forbidden}))
        )

    model_block_record = any(
        record.kind == "BLOCK_RECORD"
        and record.first(2) == "*Model_Space"
        and (record.first(5) or "").upper() == "31"
        for record in parsed
    )
    model_block_definition = any(
        record.section == "BLOCKS"
        and record.kind == "BLOCK"
        and record.first(2) == "*Model_Space"
        and (record.first(330) or "").upper() == "31"
        for record in parsed
    )
    if not model_block_record or not model_block_definition:
        errors.append("*Model_Space block record/definition is incomplete")

    model = [
        record
        for record in parsed
        if record.section == "ENTITIES" and record.kind in GRAPHICAL
    ]
    if not model:
        errors.append("ENTITIES contains no Model Space geometry")

    for record in model:
        if record.first(5) is None:
            errors.append(f"{record.kind} is missing a handle")
        if (record.first(330) or "").upper() != "31":
            errors.append(f"{record.kind} is not owned by *Model_Space")
        if "AcDbEntity" not in record.values(100):
            errors.append(f"{record.kind} is missing AcDbEntity")
        expected = EXPECTED_SUBCLASS[record.kind]
        if expected not in record.values(100):
            errors.append(f"{record.kind} is missing {expected}")
        if record.first(67) == "1" or record.first(410) is not None:
            errors.append(f"{record.kind} is marked as Paper Space")
        if record.kind == "LWPOLYLINE":
            declared = int(record.first(90) or "0")
            if declared < 2 or declared != len(record.values(10)):
                errors.append("Malformed LWPOLYLINE vertex count")

    marker = any(
        code == 999 and value == "3ERoomElectrical v1.9.9 MODEL_SPACE_UTF8_2007"
        for code, value in pairs
    )
    if not marker:
        errors.append("v1.9.9 Model Space UTF-8 marker is missing")

    print(f"File: {args.dxf}")
    print(f"Sections: {', '.join(sections)}")
    print(f"Model-space graphical records: {len(model)}")
    print(f"Arabic text records: {sum(r.kind == 'MTEXT' for r in model)}")
    print(f"Forbidden layout records: {len(forbidden)}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    print("AutoCAD 2007 UTF-8 Model Space DXF: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
