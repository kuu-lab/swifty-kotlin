#!/usr/bin/env python3
"""Check simple qualified filters against Swift test declarations before a build."""

from __future__ import annotations

import pathlib
import re
import sys


FILTER = re.compile(
    r"\^?([A-Za-z_][A-Za-z_0-9]*)(?:\\\.|\.)([A-Za-z_][A-Za-z_0-9]*)(?:/([A-Za-z_][A-Za-z_0-9]*))?\$?\Z"
)
DECLARATION = re.compile(r"\b(?:struct|class|enum|actor|extension)\s+([A-Za-z_][A-Za-z_0-9]*)\b[^{};]*\{")


def without_comments_and_strings(source: str) -> str:
    """Replace Swift comments and string literals with spaces, preserving braces in code."""
    result = list(source)
    i = 0
    size = len(source)
    while i < size:
        start = i
        if source.startswith("//", i):
            i = source.find("\n", i)
            if i < 0:
                i = size
        elif source.startswith("/*", i):
            i += 2
            depth = 1
            while i < size and depth:
                if source.startswith("/*", i):
                    depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
        else:
            hashes = 0
            while i + hashes < size and source[i + hashes] == "#":
                hashes += 1
            quote = i + hashes
            if quote >= size or source[quote] != '"':
                i += 1
                continue
            triple = source.startswith('"""', quote)
            delimiter = ('"""' if triple else '"') + "#" * hashes
            i = quote + (3 if triple else 1)
            while i < size:
                if source.startswith(delimiter, i):
                    i += len(delimiter)
                    break
                if hashes == 0 and source[i] == "\\":
                    i += 2
                else:
                    i += 1
        result[start:i] = ("\n" if c == "\n" else " " for c in source[start:i])
    return "".join(result)


def matching_brace(source: str, opening: int) -> int | None:
    depth = 1
    for i in range(opening + 1, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return None


def check_filter(repo: pathlib.Path, pattern: str) -> int:
    match = FILTER.fullmatch(pattern)
    if not match:
        return 0  # Regexes and other filter forms need SwiftPM's discovery.
    module, suite, test = match.groups()
    tests = repo / "Tests" / module
    if not tests.is_dir():
        return 0  # Do not guess about generated or external test targets.

    method = re.compile(r"\bfunc\s+" + re.escape(test) + r"[A-Za-z_0-9]*\b") if test else None
    found_suite = False
    found_test = False
    for path in tests.rglob("*.swift"):
        source = path.read_text(encoding="utf-8")
        if suite not in source and (test is None or test not in source):
            continue
        source = without_comments_and_strings(source)
        for declaration in DECLARATION.finditer(source):
            if not declaration.group(1).startswith(suite):
                continue
            found_suite = True
            if method is None:
                return 0
            end = matching_brace(source, declaration.end() - 1)
            if end is None:
                # Invalid or unsupported source is SwiftPM's responsibility.
                return 0
            if method.search(source, declaration.end(), end):
                found_test = True
                break
        if found_test:
            return 0

    detail = "suite" if not found_suite else "test in that suite"
    print(
        f"swift_test.sh: filter {pattern!r}: no matching {detail} found in {tests}.",
        file=sys.stderr,
    )
    print(
        "Check the Swift type and function names; for generated or inherited tests, "
        "set SWIFT_TEST_SOURCE_PREFLIGHT=0 to let SwiftPM discover them.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(check_filter(pathlib.Path(sys.argv[1]), sys.argv[2]))
