#!/usr/bin/env python3
"""Reject remote GitHub Actions that are not pinned to a full commit SHA."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parent.parent
GITHUB_DIR = ROOT / ".github"
USES_LINE = re.compile(r"^\s*(?:-\s*)?uses:\s*(.*?)\s*(?:#.*)?$")
FULL_SHA = re.compile(r"^[0-9a-fA-F]{40}$")


def main() -> int:
    violations: list[str] = []

    for path in sorted(GITHUB_DIR.rglob("*.yml")) + sorted(GITHUB_DIR.rglob("*.yaml")):
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            match = USES_LINE.match(line)
            if match is None:
                continue

            reference = match.group(1).strip().strip("'\"")
            if reference.startswith("./"):
                continue

            action, separator, revision = reference.rpartition("@")
            if not separator or not action or not FULL_SHA.fullmatch(revision):
                relative_path = path.relative_to(ROOT)
                violations.append(
                    f"{relative_path}:{line_number}: remote uses must end in a full 40-character commit SHA: {reference}"
                )

    if violations:
        print("Unpinned remote GitHub Actions found:", file=sys.stderr)
        print("\n".join(violations), file=sys.stderr)
        return 1

    print("All remote GitHub Actions are pinned to full commit SHAs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
