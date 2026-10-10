#!/usr/bin/env python3
"""Import the pinned 0.9.1 test-name index into a non-green case matrix.

The input catalog records source-file hashes and test/sample function names,
not full test bodies or factory instantiations. Imported cases therefore stay
unmapped/unsupported until an executable adapter is supplied.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


EXPECTED_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"
EXPECTED_KOTLIN = "2.3.10"
EXPECTED_KOTLINX_IO = "0.9.1"
SOURCE_SET_LABELS = {
    "common": "common",
    "jvm": "jvm",
    "apple": "apple",
    "native": "native",
    "nativeNonApple": "native-nonapple",
    "nativeNonAndroid": "native-nonandroid",
    "androidNative": "android-native",
    "js": "js",
    "nodeJs": "node-js",
    "wasmJs": "wasm-js",
    "wasmWasi": "wasm-wasi",
}


class CatalogImportError(Exception):
    pass


def split_cell(value: str | None) -> list[str]:
    if not value or value.strip().lower() in {"", "none", "n/a"}:
        return []
    return [part.strip() for part in value.split(";") if part.strip() and part.strip().lower() != "none"]


def platform_for(path: str) -> str:
    parts = Path(path).parts
    try:
        test_index = parts.index("test")
    except ValueError:
        return "unknown"
    if test_index < 2:
        return "unknown"
    source_set = parts[test_index - 1]
    if source_set in SOURCE_SET_LABELS:
        return SOURCE_SET_LABELS[source_set]
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "-", source_set).lower()


def disposition_for(path: str, platform: str) -> tuple[str, str]:
    if "Windows" in Path(path).name:
        return "unsupported", "Upstream file is Windows-specific and this run target is macOS."
    if platform not in {"common", "jvm"}:
        return "unsupported", f"Upstream target {platform!r} is outside this macOS common/JVM harness scope."
    return "unmapped", "No upstream-test runner pair is configured for this case yet."


def read_crosswalk(path: Path | None) -> dict[str, dict[str, list[str]]]:
    result: dict[str, dict[str, set[str]]] = defaultdict(lambda: {"local_test_refs": set(), "local_candidate_refs": set()})
    if path is None:
        return {}
    try:
        with path.open(encoding="utf-8", newline="") as stream:
            rows = csv.DictReader(stream, delimiter="\t")
            required = {"upstream_test_refs", "local_test_refs", "local_candidate_refs"}
            if not rows.fieldnames or not required.issubset(rows.fieldnames):
                raise CatalogImportError(f"API inventory is missing columns: {sorted(required)}")
            for row in rows:
                for upstream_id in split_cell(row.get("upstream_test_refs")):
                    if upstream_id.endswith("#suite-reference"):
                        continue
                    result[upstream_id]["local_test_refs"].update(split_cell(row.get("local_test_refs")))
                    result[upstream_id]["local_candidate_refs"].update(split_cell(row.get("local_candidate_refs")))
    except OSError as exc:
        raise CatalogImportError(f"cannot read API crosswalk {path}: {exc}") from exc
    return {
        upstream_id: {key: sorted(values) for key, values in mapping.items()}
        for upstream_id, mapping in result.items()
    }


def build_map(
    test_index_path: Path,
    api_inventory_path: Path | None,
    upstream_lock_path: Path | None = None,
) -> dict[str, Any]:
    try:
        raw = test_index_path.read_bytes()
        index = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CatalogImportError(f"cannot read test index {test_index_path}: {exc}") from exc
    if index.get("tag") != EXPECTED_KOTLINX_IO or index.get("commit") != EXPECTED_COMMIT:
        raise CatalogImportError("test index is not pinned to kotlinx-io 0.9.1 at the expected commit")
    lock: dict[str, Any] | None = None
    if upstream_lock_path is not None:
        try:
            lock = json.loads(upstream_lock_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise CatalogImportError(f"cannot read upstream lock {upstream_lock_path}: {exc}") from exc
        if lock.get("tag") != EXPECTED_KOTLINX_IO or lock.get("commit") != EXPECTED_COMMIT:
            raise CatalogImportError("upstream lock is not pinned to kotlinx-io 0.9.1 at the expected commit")
        if lock.get("upstreamTestsIndexSha256") != hashlib.sha256(raw).hexdigest():
            raise CatalogImportError("upstream lock test-index SHA-256 does not match the supplied catalog")
    files = index.get("files")
    if not isinstance(files, list) or not files:
        raise CatalogImportError("test index must contain a non-empty files array")
    crosswalk = read_crosswalk(api_inventory_path)
    crosswalk_sha256 = None
    if api_inventory_path is not None:
        try:
            crosswalk_sha256 = hashlib.sha256(api_inventory_path.read_bytes()).hexdigest()
        except OSError as exc:
            raise CatalogImportError(f"cannot hash API crosswalk {api_inventory_path}: {exc}") from exc
    cases: list[dict[str, Any]] = []
    inventory_only_sources: list[dict[str, Any]] = []
    seen: set[str] = set()
    for source in files:
        source_path = source.get("path")
        names = source.get("testNames")
        if not isinstance(source_path, str) or not source_path:
            raise CatalogImportError("test index entries must include a source path")
        if not isinstance(names, list):
            raise CatalogImportError(f"testNames must be an array for {source_path}")
        if not names:
            inventory_only_sources.append(
                {
                    "path": source_path,
                    "git_blob_sha": source.get("gitBlobSha"),
                    "size_bytes": source.get("size"),
                    "class_names": source.get("classNames", []),
                    "status": "inventory-only helper/fixture source; no testNames entries",
                }
            )
            continue
        platform = platform_for(source_path)
        disposition, reason = disposition_for(source_path, platform)
        for name in names:
            if not isinstance(name, str) or not name:
                raise CatalogImportError(f"invalid test name in {source_path}")
            upstream_id = f"{source_path}#{name}"
            if upstream_id in seen:
                raise CatalogImportError(f"duplicate upstream function ID: {upstream_id}")
            seen.add(upstream_id)
            local = crosswalk.get(upstream_id, {"local_test_refs": [], "local_candidate_refs": []})
            has_local_test_candidate = bool(local["local_test_refs"])
            has_source_candidate = bool(local["local_candidate_refs"])
            cases.append(
                {
                    "id": upstream_id,
                    "upstream_id": upstream_id,
                    "upstream_path": source_path,
                    "platform": platform,
                    "test_kind": "sample" if "/samples/" in source_path else "test-function",
                    "disposition": disposition,
                    "reason": reason,
                    "mapping": {
                        "status": (
                            "candidate-unverified"
                            if has_local_test_candidate
                            else "source-only-candidate"
                            if has_source_candidate
                            else "unmapped"
                        ),
                        "candidate_local_test_refs": local["local_test_refs"],
                        "source_candidate_ref_count": len(local["local_candidate_refs"]),
                        "verified_assertion_mapping": False,
                    },
                    "upstream_metadata": {
                        "git_blob_sha": source.get("gitBlobSha"),
                        "source_size_bytes": source.get("size"),
                        "suite_class_names": source.get("classNames", []),
                        "factory_parameter_expansion": "not-audited",
                    },
                }
            )
    catalog = {
        "repository": index.get("repository", "https://github.com/Kotlin/kotlinx-io"),
        "tag": EXPECTED_KOTLINX_IO,
        "commit": EXPECTED_COMMIT,
        "test_index_sha256": hashlib.sha256(raw).hexdigest(),
        "local_crosswalk_sha256": crosswalk_sha256,
        "source_file_count": len(files),
        "test_and_sample_function_id_count": len(cases),
        "inventory_only_source_count": len(inventory_only_sources),
        "parameterized_factory_case_count": None,
        "warning": "Function IDs are not expanded into inherited suites, factory values, or parameterized invocations.",
    }
    reference_artifacts = []
    if lock is not None:
        reference_artifacts = [
            {
                "coordinate": artifact.get("coordinate"),
                "url": artifact.get("url"),
                "sha256": artifact.get("sha256"),
            }
            for artifact in lock.get("mavenArtifacts", [])
            if artifact.get("coordinate")
        ]
    return {
        "schema_version": 1,
        "baseline": {"kotlin": EXPECTED_KOTLIN, "kotlinx_io": EXPECTED_KOTLINX_IO},
        "catalog": catalog,
        "reference_artifacts": reference_artifacts,
        "inventory_only_sources": inventory_only_sources,
        "cases": cases,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test-index", type=Path, required=True)
    parser.add_argument("--api-inventory", type=Path)
    parser.add_argument("--upstream-lock", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        manifest = build_map(args.test_index, args.api_inventory, args.upstream_lock)
    except CatalogImportError as exc:
        print(f"coverage map import: {exc}", file=sys.stderr)
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    non_case_fields = {key: value for key, value in manifest.items() if key != "cases"}
    prefix = json.dumps(non_case_fields, ensure_ascii=False, indent=2).rstrip()
    case_lines = [
        "    " + json.dumps(case, ensure_ascii=False, separators=(",", ":"))
        for case in manifest["cases"]
    ]
    serialized = prefix[:-1].rstrip() + ',\n  "cases": [\n' + ",\n".join(case_lines) + "\n  ]\n}\n"
    args.output.write_text(serialized, encoding="utf-8")
    print(
        json.dumps(
            {
                "output": str(args.output),
                "source_files": manifest["catalog"]["source_file_count"],
                "function_ids": manifest["catalog"]["test_and_sample_function_id_count"],
                "inventory_only_sources": manifest["catalog"]["inventory_only_source_count"],
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
