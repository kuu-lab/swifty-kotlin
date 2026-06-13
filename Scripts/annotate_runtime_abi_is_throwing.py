#!/usr/bin/env python3
"""Annotate RuntimeABISpec entries with isThrowing: false for non-throwing callees."""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LEGACY_FILE = REPO / "Sources/CompilerCore/Lowering/ABILoweringPass+NonThrowingCallees.swift"
RUNTIME_ABI_DIR = REPO / "Sources/RuntimeABI"


def load_non_throwing_names() -> set[str]:
    text = LEGACY_FILE.read_text()
    names = set(re.findall(r'interner\.intern\("([^"]+)"\)', text))
    names.update(
        {
            "kk_kproperty_stub_create",
            "kk_kproperty_stub_name",
            "kk_kproperty_stub_return_type",
        }
    )
    return names


def find_matching_paren(text: str, open_index: int) -> int:
    depth = 0
    in_string = False
    escape = False
    for index in range(open_index, len(text)):
        ch = text[index]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return index
    return -1


def extract_name_from_block(block: str) -> str | None:
    match = re.search(r'name:\s*"([^"]+)"', block)
    if match:
        return match.group(1)
    match = re.search(r'^(?:bridgeSpec|abiParitySpec)\(\s*"([^"]+)"', block, re.MULTILINE)
    if match:
        return match.group(1)
    return None


def insert_is_throwing_false(block: str) -> str:
    if "isThrowing:" in block:
        return block
    match = re.search(r'(section:\s*"[^"]+")', block)
    if match:
        insert_at = match.end()
        return block[:insert_at] + ",\n            isThrowing: false" + block[insert_at:]
    trimmed = block.rstrip()
    if trimmed.endswith(")"):
        return trimmed[:-1] + ",\n            isThrowing: false)"
    return block


def annotate_runtime_abi_function_specs(text: str, non_throwing: set[str]) -> str:
    marker = "RuntimeABIFunctionSpec("
    result: list[str] = []
    index = 0
    while True:
        start = text.find(marker, index)
        if start == -1:
            result.append(text[index:])
            break
        open_paren = start + len(marker) - 1
        close_paren = find_matching_paren(text, open_paren)
        if close_paren == -1:
            result.append(text[index:])
            break
        result.append(text[index:start])
        block = text[start : close_paren + 1]
        name = extract_name_from_block(block)
        if name in non_throwing:
            block = insert_is_throwing_false(block)
        result.append(block)
        index = close_paren + 1
    return "".join(result)


def annotate_helper_calls(text: str, helper: str, non_throwing: set[str]) -> str:
    marker = f"{helper}("
    result: list[str] = []
    index = 0
    while True:
        start = text.find(marker, index)
        if start == -1:
            result.append(text[index:])
            break
        open_paren = start + len(marker) - 1
        close_paren = find_matching_paren(text, open_paren)
        if close_paren == -1:
            result.append(text[index:])
            break
        result.append(text[index:start])
        block = text[start : close_paren + 1]
        name = extract_name_from_block(block)
        if name in non_throwing:
            block = insert_is_throwing_false(block)
        result.append(block)
        index = close_paren + 1
    return "".join(result)


def annotate_mapped_bridge_specs(text: str, non_throwing: set[str]) -> str:
    pattern = re.compile(
        r"(\[\s*(?:\"[^\"]+\",?\s*)+\])\s*\.map\s*\{\s*bridgeSpec\((?P<call>[^)]+)\)\s*\}",
        re.DOTALL,
    )

    def repl(match: re.Match[str]) -> str:
        array_src = match.group(1)
        call = match.group("call")
        names = re.findall(r'"([^"]+)"', array_src)
        if not names or not all(name in non_throwing for name in names):
            return match.group(0)
        if "isThrowing:" in call:
            return match.group(0)
        trimmed = call.rstrip()
        if trimmed.endswith(","):
            new_call = f"{trimmed}\n            isThrowing: false"
        else:
            new_call = f"{trimmed},\n            isThrowing: false"
        return f"{array_src}.map {{ bridgeSpec({new_call}) }}"

    return pattern.sub(repl, text)


def process_file(path: Path, non_throwing: set[str]) -> bool:
    original = path.read_text()
    updated = original
    updated = annotate_runtime_abi_function_specs(updated, non_throwing)
    updated = annotate_helper_calls(updated, "bridgeSpec", non_throwing)
    updated = annotate_helper_calls(updated, "abiParitySpec", non_throwing)
    updated = annotate_mapped_bridge_specs(updated, non_throwing)
    if updated != original:
        path.write_text(updated)
        return True
    return False


def main() -> int:
    non_throwing = load_non_throwing_names()
    changed: list[str] = []
    for path in sorted(RUNTIME_ABI_DIR.glob("*.swift")):
        if process_file(path, non_throwing):
            changed.append(path.name)
    print(f"Non-throwing names from legacy list: {len(non_throwing)}")
    print(f"Updated {len(changed)} files:")
    for name in changed:
        print(f"  - {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
