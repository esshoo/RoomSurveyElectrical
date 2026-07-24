#!/usr/bin/env python3
"""Check that a DXF contains readable model-space geometry.

This is intentionally small and dependency-free so it can run on Windows.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

GRAPHICAL = {
    "LINE", "LWPOLYLINE", "POLYLINE", "CIRCLE", "ARC", "TEXT",
    "MTEXT", "INSERT", "HATCH", "SPLINE", "ELLIPSE", "POINT",
    "VIEWPORT",
}


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
    text = path.read_text(encoding="utf-8-sig", errors="strict")
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


def records(pairs: list[tuple[int, str]]) -> list[Record]:
    result: list[Record] = []
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
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("dxf", type=Path)
    args = parser.parse_args()

    if not args.dxf.is_file():
        parser.error(f"File does not exist: {args.dxf}")

    parsed = records(read_pairs(args.dxf))
    graphical = [record for record in parsed if record.kind in GRAPHICAL]
    model = []
    paper = []
    paper_in_blocks = []
    reached_model = False
    paper_after_model = []

    for record in graphical:
        is_paper = record.first(67) == "1"
        if record.section == "BLOCKS" and is_paper:
            paper_in_blocks.append(record)
        if record.section != "ENTITIES":
            continue
        if is_paper:
            paper.append(record)
            if reached_model:
                paper_after_model.append(record)
        else:
            reached_model = True
            model.append(record)

    errors: list[str] = []
    if not model:
        errors.append("ENTITIES contains no model-space graphical entities")
    if paper_in_blocks:
        errors.append(
            f"{len(paper_in_blocks)} paper-space entities were written in BLOCKS"
        )
    if paper_after_model:
        errors.append(
            f"{len(paper_after_model)} paper-space entities appear after model entities"
        )

    for record in model:
        layout = record.first(410)
        if layout is not None and layout.lower() != "model":
            errors.append(
                f"Model entity {record.kind} has unexpected layout tag {layout!r}"
            )
            break

    print(f"File: {args.dxf}")
    print(f"Model-space entities: {len(model)}")
    print(f"Paper-space entities: {len(paper)}")
    print(f"Paper entities in BLOCKS: {len(paper_in_blocks)}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    print("DXF model-space structure: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
