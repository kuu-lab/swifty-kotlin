#!/usr/bin/env python3
"""Build the pinned macOS candidate IDs for JVM-only Sink test bodies."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
REFERENCE_LOCK = HERE / "reference-lock.json"
JVM_CATALOG = HERE / "jvm-executions.expected.json"
OUTPUT = HERE / "jvm-candidate-executions.expected.json"
SOURCE_IDS = [
    "core/jvm/test/AbstractSinkTestJVM.kt#outputStream",
    "core/jvm/test/AbstractSinkTestJVM.kt#outputStreamBounds",
    "core/jvm/test/AbstractSinkTestJVM.kt#writeToClosedOutputStream",
    "core/jvm/test/AbstractSinkTestJVM.kt#outputStreamClosesSink",
    "core/jvm/test/AbstractSinkTestJVM.kt#writeNioBuffer",
    "core/jvm/test/AbstractSinkTestJVM.kt#writeLargeNioBufferWritesAllData",
    "core/jvm/test/AbstractSinkTestJVM.kt#writeNioBufferToClosedSink",
    "core/jvm/test/AbstractSinkTestJVM.kt#writeStringWithCharset",
    "core/jvm/test/AbstractSinkTestJVM.kt#writeSubstringWithCharset",
    "core/jvm/test/AbstractSinkTestJVM.kt#writeUtf8SubstringWithCharset",
]
LOCK_KEY = "jvm_candidate_execution_catalog_sha256"
CANDIDATE_COMMIT = "d610e43f3275f9f5603a41543bd5b77ab7e067b0"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def render(data: object) -> bytes:
    return (json.dumps(data, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def build_catalog(lock: dict, reference_catalog: list[dict], reference_catalog_bytes: bytes) -> dict:
    if lock.get("commit") != "362bdc35e159bad6da1e08101c8321792d762281":
        raise ValueError("reference lock is not pinned to kotlinx-io 0.9.1")
    if sha256(reference_catalog_bytes) != lock.get("jvm_execution_catalog_sha256"):
        raise ValueError("JVM execution catalog differs from its reference lock")
    rows = [row for row in reference_catalog if row.get("upstream_id") in set(SOURCE_IDS)]
    actual_source_ids = {row["upstream_id"] for row in rows}
    if actual_source_ids != set(SOURCE_IDS):
        raise ValueError(f"JVM catalog source IDs differ: missing={sorted(set(SOURCE_IDS) - actual_source_ids)}")
    classes = {row["concrete_class"] for row in rows}
    expected_classes = {"kotlinx.io.BufferSinkTestJVM", "kotlinx.io.RealSinkTestJVM"}
    if classes != expected_classes or len(rows) != 20:
        raise ValueError("JVM Sink tests must expand to the two audited concrete factories (20 executions)")
    executions = []
    for row in rows:
        if (row.get("declaring_class") != "kotlinx.io.AbstractSinkTestJVM"
                or row.get("parameter_types") != ""
                or row.get("source_set") != "jvm"
                or row.get("upstream_path") != "core/jvm/test/AbstractSinkTestJVM.kt"):
            raise ValueError(f"unexpected JVM execution shape: {row.get('execution_id')}")
        execution_id = (
            f"[engine:kswiftk-macos-native]/[class:{row['concrete_class']}]"
            f"/[method:{row['method_name']}()]"
        )
        executions.append({
            "execution_id": execution_id,
            "reference_execution_id": row["execution_id"],
            "upstream_id": row["upstream_id"],
            "concrete_class": row["concrete_class"],
            "declaring_class": row["declaring_class"],
            "method_name": row["method_name"],
            "parameter_types": row["parameter_types"],
            "upstream_path": row["upstream_path"],
            "git_blob_sha": row["git_blob_sha"],
        })
    return {
        "schema_version": 1,
        "kind": "candidate-macos-native-jvm-suite",
        "candidate_runtime": "kswiftk-native",
        "target": "macos",
        "candidate_commit": CANDIDATE_COMMIT,
        "upstream_commit": lock["commit"],
        "reference_catalog_sha256": sha256(reference_catalog_bytes),
        "source_function_ids": SOURCE_IDS,
        "execution_count": len(executions),
        "executions": executions,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help="write catalog and update its hash lock")
    mode.add_argument("--check", action="store_true", help="verify deterministic catalog and lock hash")
    args = parser.parse_args()
    try:
        lock = json.loads(REFERENCE_LOCK.read_text(encoding="utf-8"))
        catalog_bytes = JVM_CATALOG.read_bytes()
        reference_catalog = json.loads(catalog_bytes.decode("utf-8"))
        expected = render(build_catalog(lock, reference_catalog, catalog_bytes))
        digest = sha256(expected)
        if args.write:
            OUTPUT.write_bytes(expected)
            lock[LOCK_KEY] = digest
            REFERENCE_LOCK.write_bytes(render(lock))
            print(f"Wrote {OUTPUT.name}: 20 candidate execution IDs sha256={digest}")
        else:
            if not OUTPUT.is_file() or OUTPUT.read_bytes() != expected:
                raise ValueError("candidate JVM execution catalog is stale; run with --write")
            if lock.get(LOCK_KEY) != digest:
                raise ValueError("candidate JVM execution catalog hash differs from reference-lock.json")
            print(f"OK {OUTPUT.name}: 20 candidate execution IDs sha256={digest}")
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"candidate JVM catalog: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
