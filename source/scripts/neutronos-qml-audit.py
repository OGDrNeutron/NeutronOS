#!/usr/bin/env python3
"""Lightweight NeutronOS QML source audit.

This intentionally performs structural checks only. It does not instantiate
QML or require a display server. Use qmllint as an additional check when it is
installed on the target system.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

OPEN_TO_CLOSE = {"{": "}", "(": ")", "[": "]"}
CLOSERS = set(OPEN_TO_CLOSE.values())
ASSIGNMENT_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_.]*)\s*:")


def mask_non_code(text: str) -> str:
    """Preserve newlines/length while masking comments, strings and regexes."""
    out: list[str] = []
    i = 0
    state = "code"
    quote = ""
    previous_significant = ""
    regex_character_class = False

    def masked(ch: str) -> str:
        return "\n" if ch == "\n" else " "

    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""

        if state == "line_comment":
            out.append(masked(ch))
            if ch == "\n":
                state = "code"
            i += 1
            continue

        if state == "block_comment":
            out.append(masked(ch))
            if ch == "*" and nxt == "/":
                out.append(" ")
                i += 2
                state = "code"
            else:
                i += 1
            continue

        if state == "string":
            out.append(masked(ch))
            if ch == "\\" and i + 1 < len(text):
                out.append(masked(text[i + 1]))
                i += 2
            elif ch == quote:
                i += 1
                state = "code"
            else:
                i += 1
            continue

        if state == "regex":
            out.append(masked(ch))
            if ch == "\\" and i + 1 < len(text):
                out.append(masked(text[i + 1]))
                i += 2
            elif ch == "[":
                regex_character_class = True
                i += 1
            elif ch == "]" and regex_character_class:
                regex_character_class = False
                i += 1
            elif ch == "/" and not regex_character_class:
                i += 1
                while i < len(text) and text[i].isalpha():
                    out.append(" ")
                    i += 1
                state = "code"
            else:
                i += 1
            continue

        if ch == "/" and nxt == "/":
            out.extend((" ", " "))
            i += 2
            state = "line_comment"
            continue

        if ch == "/" and nxt == "*":
            out.extend((" ", " "))
            i += 2
            state = "block_comment"
            continue

        if ch in ('"', "'"):
            out.append(" ")
            quote = ch
            i += 1
            state = "string"
            continue

        # QML/JS regex literals commonly follow (, =, :, comma, return, or a
        # method argument separator. Division remains ordinary code.
        previous_word = ""
        if ch == "/":
            previous_word_match = re.search(
                r"([A-Za-z_$][A-Za-z0-9_$]*)\s*$", "".join(out))
            previous_word = previous_word_match.group(1) if previous_word_match else ""
        regex_keywords = {
            "await", "case", "delete", "in", "instanceof", "new", "return",
            "throw", "typeof", "void", "yield",
        }
        if (ch == "/" and
                (previous_significant in "(=:[,!&|?{};" or
                 previous_word in regex_keywords)):
            out.append(" ")
            i += 1
            state = "regex"
            regex_character_class = False
            continue

        out.append(ch)
        if not ch.isspace():
            previous_significant = ch
        i += 1

    return "".join(out)


def audit_file(path: Path) -> list[str]:
    errors: list[str] = []
    text = path.read_text(encoding="utf-8")
    code = mask_non_code(text)

    stack: list[tuple[str, int]] = []
    scope_properties: list[dict[str, int]] = [{}]

    for line_number, line in enumerate(code.splitlines(), start=1):
        match = ASSIGNMENT_RE.match(line)
        if match:
            key = match.group(1)
            previous = scope_properties[-1].get(key)
            if previous is not None:
                errors.append(
                    f"{path}: property/handler '{key}' is assigned at both "
                    f"lines {previous} and {line_number}"
                )
            else:
                scope_properties[-1][key] = line_number

        for ch in line:
            if ch in OPEN_TO_CLOSE:
                stack.append((ch, line_number))
                if ch == "{":
                    scope_properties.append({})
            elif ch in CLOSERS:
                if not stack:
                    errors.append(f"{path}:{line_number}: unexpected '{ch}'")
                    continue
                opening, opening_line = stack.pop()
                if OPEN_TO_CLOSE[opening] != ch:
                    errors.append(
                        f"{path}:{line_number}: '{ch}' closes '{opening}' "
                        f"from line {opening_line}"
                    )
                if opening == "{" and len(scope_properties) > 1:
                    scope_properties.pop()

    for opening, opening_line in stack:
        errors.append(f"{path}:{opening_line}: unclosed '{opening}'")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("qml_root", nargs="?", default="qml")
    args = parser.parse_args()

    qml_root = Path(args.qml_root).expanduser().resolve()
    if not qml_root.is_dir():
        print(f"QML root not found: {qml_root}", file=sys.stderr)
        return 2

    files = sorted(qml_root.rglob("*.qml"))
    errors: list[str] = []
    for path in files:
        errors.extend(audit_file(path))

    if errors:
        print("NeutronOS QML audit failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1

    print(f"NeutronOS QML audit passed: {len(files)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
