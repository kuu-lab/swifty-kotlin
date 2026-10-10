#!/usr/bin/env python3
"""Validate the pinned kotlinx.atomicfu 0.33.0 API reference snapshots."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

import generate_atomicfu_api_index as api_index


ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "docs/atomicfu-0.33.0/reference"
EXPECTED_BLOBS = {
    "atomicfu.klib.api": "d170cb60f282c47b96d2c98041a7f5f2bf2e5850",
    "atomicfu.api": "43d0bf802a601d72d49c8269bcfc325aa57eefac",
}
DECLARATION_PREFIXES = (
    "final class ",
    "open class ",
    "abstract class ",
    "enum class ",
    "final object ",
    "open object ",
    "final val ",
    "final var ",
    "final fun ",
    "final inline fun ",
    "open fun ",
    "open val ",
    "open var ",
    "constructor ",
    "final inline operator fun ",
    "final operator fun ",
    "final inline suspend fun ",
    "final suspend fun ",
    "final typealias ",
    "final annotation class ",
    "open annotation class ",
    "abstract interface annotation class ",
)
EXPECTED_COMMON_NATIVE_SIGNATURES = api_index.EXPECTED_COMMON_NATIVE_SIGNATURES
UNSUPPORTED_API_NAMES = re.compile(r"\b(compareAndExchange|load|store|MemoryOrder)\b")


def git_blob_sha1(contents: bytes) -> str:
    header = f"blob {len(contents)}\0".encode("ascii")
    return hashlib.sha1(header + contents).hexdigest()


def check_pinned_files() -> dict[str, bytes]:
    contents_by_name: dict[str, bytes] = {}
    for name, expected_sha in EXPECTED_BLOBS.items():
        path = REFERENCE / name
        try:
            contents = path.read_bytes()
        except OSError as error:
            raise SystemExit(f"missing pinned API reference {path}: {error}") from error
        # The upstream JVM dump has one empty line after its final declaration.
        # The checked-in view trims that nonsemantic blank line to keep
        # git diff --check clean; restore it to verify the exact upstream blob.
        upstream_bytes = contents + b"\n" if name == "atomicfu.api" else contents
        actual_sha = git_blob_sha1(upstream_bytes)
        if actual_sha != expected_sha:
            raise SystemExit(
                f"{path.relative_to(ROOT)} blob SHA mismatch: "
                f"expected {expected_sha}, got {actual_sha}"
            )
        contents_by_name[name] = contents
    return contents_by_name


def is_declaration(line: str) -> bool:
    return line.startswith(DECLARATION_PREFIXES)


def common_native_signatures(contents: bytes) -> set[str]:
    _, records = api_index.parse_api_records(contents)
    return {
        record["signature"]
        for record in records.values()
        if record["common_native"]
    }


def main() -> int:
    snapshots = check_pinned_files()
    klib = snapshots["atomicfu.klib.api"]
    signatures = common_native_signatures(klib)
    if len(signatures) != EXPECTED_COMMON_NATIVE_SIGNATURES:
        raise SystemExit(
            "common/native signature count changed: "
            f"expected {EXPECTED_COMMON_NATIVE_SIGNATURES}, got {len(signatures)}"
        )

    index_bytes = api_index.render_index(klib)
    try:
        checked_in_index = api_index.INDEX_PATH.read_bytes()
    except OSError as error:
        raise SystemExit(
            f"missing generated declaration index {api_index.INDEX_PATH}: {error}"
        ) from error
    if checked_in_index != index_bytes:
        raise SystemExit(
            f"{api_index.INDEX_PATH.relative_to(ROOT)} is stale; "
            "run python3 Scripts/generate_atomicfu_api_index.py --write"
        )
    index = json.loads(checked_in_index)
    if index["summary"]["total_api_identity_rows"] != api_index.EXPECTED_TOTAL_DECLARATIONS:
        raise SystemExit("generated declaration index does not cover all API identities")
    if index["summary"]["legacy_flat_unique_signatures"] != api_index.EXPECTED_LEGACY_SIGNATURES:
        raise SystemExit("generated declaration index no longer covers the 130 flat-pass signatures")
    if index["summary"]["inherited_js_wasm_exclusions"] != api_index.EXPECTED_INHERITED_JS_WASM_DECLARATIONS:
        raise SystemExit("generated declaration index has an unexpected JS/Wasm target exclusion count")

    unsupported = sorted(
        {
            name
            for signature in signatures
            for name in UNSUPPORTED_API_NAMES.findall(signature)
        }
    )
    if unsupported:
        raise SystemExit(
            "unexpected names in the pinned common/native API inventory: "
            + ", ".join(unsupported)
        )

    for name, expected_sha in EXPECTED_BLOBS.items():
        print(f"PASS {name}: {expected_sha}")
    print(
        "PASS common/native KLIB surface: "
        f"{index['summary']['common_native_declarations']} declarations, "
        f"{index['summary']['common_native_unique_signatures']} unique rendered signatures"
    )
    print(
        "PASS legacy count and target audit: "
        f"{index['summary']['legacy_flat_unique_signatures']} unique flat signatures; "
        f"{index['summary']['inherited_js_wasm_exclusions']} inherited JS/Wasm declaration exclusions"
    )
    print("PASS no compareAndExchange/load/store/MemoryOrder API entries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
