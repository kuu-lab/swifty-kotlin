#!/usr/bin/env python3
"""Audit strict kotlinx-io API/test coverage and same-commit CI receipts."""

from __future__ import annotations

import argparse
import collections
import csv
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
VERIFIED_DISPOSITIONS = {"paired", "verified"}
VERIFIED_MAPPING_STATES = {"paired", "pass", "verified"}
VERIFIED_API_STATES = {"implemented", "verified"}
F02_LANES = {
    ("source", "O0"), ("source", "O2"),
    ("stdlib-library", "O0"), ("stdlib-library", "O2"),
    ("producer-consumer", "O0"), ("producer-consumer", "O2"),
}
REQUIRED_SUMMARY_ARTIFACTS = {
    "api-audit": ("kotlinx-io-gate-api-", "/api-gate-summary.json"),
    "reference-jvm": ("kotlinx-io-gate-reference-jvm-", "/reference/results/summary.json"),
    "reference-native-apple": ("kotlinx-io-gate-reference-native-apple-", "/reference/results/summary.json"),
    "f02-matrix": ("kotlinx-io-gate-f02-", "/f02/results/summary.json"),
    "candidate-source-O0": ("kotlinx-io-gate-candidate-source-O0-", "/candidate/source-O0/summary.json"),
    "candidate-source-O2": ("kotlinx-io-gate-candidate-source-O2-", "/candidate/source-O2/summary.json"),
    "candidate-stdlib-library-O0": ("kotlinx-io-gate-candidate-stdlib-library-O0-", "/candidate/stdlib-library-O0/summary.json"),
    "candidate-stdlib-library-O2": ("kotlinx-io-gate-candidate-stdlib-library-O2-", "/candidate/stdlib-library-O2/summary.json"),
    "candidate-producer-consumer-O0": ("kotlinx-io-gate-candidate-producer-consumer-O0-", "/candidate/producer-consumer-O0/summary.json"),
    "candidate-producer-consumer-O2": ("kotlinx-io-gate-candidate-producer-consumer-O2-", "/candidate/producer-consumer-O2/summary.json"),
    "ktor-consumer": ("kotlinx-io-gate-ktor-", "/ktor/summary.json"),
    "diff-O0": ("kotlinx-io-gate-diff-O0-", "/diff/O0/summary.json"),
    "diff-O2": ("kotlinx-io-gate-diff-O2-", "/diff/O2/summary.json"),
    "related-goldens": ("kotlinx-io-gate-goldens-", "/goldens/summary.json"),
}
REQUIRED_WORKFLOW_JOBS = {
    "api-audit", "upstream-reference", "f02-matrix", "candidate-native",
    "ktor-consumer", "kotlinx-diff", "related-goldens",
}


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def inventory_case_ids(index: dict[str, Any]) -> set[str]:
    return set(inventory_case_list(index))


def inventory_case_list(index: dict[str, Any]) -> list[str]:
    return [
        f"{record['path']}#{name}"
        for record in index.get("files", [])
        for name in record.get("testNames", [])
    ]


def validate_execution_counts(counts: dict[str, int], expected: int, label: str) -> list[str]:
    """Require an exact all-PASS execution count; never accept an empty run."""
    normalized = {str(key).upper().replace("-", "_"): int(value) for key, value in counts.items()}
    problems: list[str] = []
    actual = sum(normalized.values())
    if expected <= 0:
        problems.append(f"{label}: expected execution count must be positive (got {expected})")
    if actual != expected:
        problems.append(f"{label}: result count {actual} does not match expected {expected}")
    for state, count in sorted(normalized.items()):
        if state != "PASS" and count:
            problems.append(f"{label}: {state}={count}")
    if normalized.get("PASS", 0) != expected:
        problems.append(f"{label}: PASS={normalized.get('PASS', 0)}; expected {expected}")
    return problems


def audit_static(root: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    """Return a machine-readable gate report and a joined API/test map."""
    inventory_path = root / "Scripts/io_api_inventory/api-inventory.tsv"
    test_index_path = root / "Scripts/io_api_inventory/upstream-tests-index.json"
    lock_path = root / "Scripts/io_api_inventory/upstream-lock.json"
    reference_lock_path = root / "Scripts/kotlinx_io_upstream/reference-lock.json"
    coverage_path = root / "Scripts/kotlinx_io_upstream/coverage-map.seed.json"
    jvm_catalog_path = root / "Scripts/kotlinx_io_upstream/jvm-executions.expected.json"
    native_catalog_path = root / "Scripts/kotlinx_io_upstream/native-executions.expected.json"

    api_rows = read_tsv(inventory_path)
    test_index = read_json(test_index_path)
    lock = read_json(lock_path)
    reference_lock = read_json(reference_lock_path)
    coverage = read_json(coverage_path)
    jvm_catalog = read_json(jvm_catalog_path)
    native_catalog = read_json(native_catalog_path)
    blockers: list[dict[str, str]] = []

    required_api_columns = {"row_id", "status", "owner_issue", "upstream_test_refs", "local_test_refs"}
    actual_api_columns = set(api_rows[0]) if api_rows else set()
    for column in sorted(required_api_columns - actual_api_columns):
        blockers.append({"kind": "api-schema", "id": column, "reason": "required column missing"})

    api_status_counts = collections.Counter(row.get("status", "").strip().lower() for row in api_rows)
    if not api_rows:
        blockers.append({"kind": "api-inventory", "id": str(inventory_path), "reason": "API inventory is empty"})
    api_ids = [row.get("row_id", "") for row in api_rows]
    duplicates = sorted(identifier for identifier, count in collections.Counter(api_ids).items()
                        if not identifier or count > 1)
    for identifier in duplicates:
        blockers.append({"kind": "api-identity", "id": identifier or "<empty>",
                         "reason": "empty or duplicate API row ID"})
    for row in api_rows:
        status = row.get("status", "").strip().lower()
        if status in {"missing", "stub", "unverified"}:
            blockers.append({"kind": "api-status", "id": row.get("row_id", "<empty>"),
                             "reason": status})
        elif status not in VERIFIED_API_STATES:
            blockers.append({"kind": "api-status", "id": row.get("row_id", "<empty>"),
                             "reason": f"unrecognized status: {status or '<empty>'}"})

    indexed_case_list = inventory_case_list(test_index)
    indexed_ids = set(indexed_case_list)
    for identifier, count in sorted(collections.Counter(indexed_case_list).items()):
        if count > 1:
            blockers.append({"kind": "test-identity", "id": identifier,
                             "reason": f"duplicate upstream test index ID ({count} entries)"})
    cases = coverage.get("cases", [])
    coverage_ids = [case.get("upstream_id", case.get("id", "")) for case in cases]
    duplicate_coverage_ids = sorted(identifier for identifier, count in
                                    collections.Counter(coverage_ids).items() if not identifier or count > 1)
    for identifier in duplicate_coverage_ids:
        blockers.append({"kind": "test-identity", "id": identifier or "<empty>",
                         "reason": "empty or duplicate upstream test ID"})
    coverage_id_set = set(coverage_ids)
    for identifier in sorted(indexed_ids - coverage_id_set):
        blockers.append({"kind": "test-coverage", "id": identifier, "reason": "missing from coverage map"})
    for identifier in sorted(coverage_id_set - indexed_ids):
        blockers.append({"kind": "test-coverage", "id": identifier, "reason": "not present in upstream index"})

    disposition_counts = collections.Counter(str(case.get("disposition", "")).lower() for case in cases)
    mapping_state_counts = collections.Counter(
        str(case.get("mapping", {}).get("status", "")).lower()
        for case in cases if isinstance(case.get("mapping"), dict)
    )
    target_case_count = 0
    target_case_ids: set[str] = set()
    for case in cases:
        identifier = case.get("upstream_id", case.get("id", "<empty>"))
        disposition = str(case.get("disposition", "")).strip().lower()
        path = str(case.get("upstream_path", ""))
        reason = str(case.get("reason", ""))
        if disposition == "unsupported":
            if "windows" not in path.lower() or "windows-specific" not in reason.lower():
                blockers.append({"kind": "test-scope", "id": identifier,
                                 "reason": "unsupported is allowed only for an explicitly Windows-only source"})
            continue
        target_case_count += 1
        target_case_ids.add(identifier)
        mapping = case.get("mapping") if isinstance(case.get("mapping"), dict) else {}
        mapping_status = str(mapping.get("status", "")).strip().lower()
        if disposition not in VERIFIED_DISPOSITIONS:
            blockers.append({"kind": "test-mapping", "id": identifier, "reason": disposition or "missing disposition"})
        if mapping_status not in VERIFIED_MAPPING_STATES or not mapping.get("verified_assertion_mapping", False):
            blockers.append({"kind": "test-mapping", "id": identifier,
                             "reason": f"assertion mapping is not verified ({mapping_status or 'missing status'})"})

    locked_commit = lock.get("commit")
    reference_commits = {
        "upstream_test_index": test_index.get("commit"),
        "coverage_map": coverage.get("catalog", {}).get("commit"),
        "reference_lock": reference_lock.get("commit"),
    }
    for name, commit in reference_commits.items():
        if commit != locked_commit:
            blockers.append({"kind": "upstream-lock", "id": name,
                             "reason": f"commit {commit!r} differs from locked commit {locked_commit!r}"})

    catalog_hashes = {}
    for name, path, lock_key in (
        ("jvm", jvm_catalog_path, "jvm_execution_catalog_sha256"),
        ("native", native_catalog_path, "native_execution_catalog_sha256"),
    ):
        actual_hash = hashlib.sha256(path.read_bytes()).hexdigest()
        catalog_hashes[name] = actual_hash
        if reference_lock.get(lock_key) != actual_hash:
            blockers.append({"kind": "execution-catalog", "id": path.name,
                             "reason": f"SHA-256 {actual_hash} differs from the reference lock"})

    jvm_source_ids = {row.get("upstream_id") for row in jvm_catalog}
    native_source_ids = {row.get("upstream_id") for row in native_catalog}
    unknown_execution_ids = sorted((jvm_source_ids | native_source_ids) - indexed_ids)
    for identifier in unknown_execution_ids:
        blockers.append({"kind": "execution-catalog", "id": str(identifier),
                         "reason": "execution points outside the pinned upstream test index"})
    if not jvm_catalog:
        blockers.append({"kind": "execution-catalog", "id": "jvm-executions.expected.json",
                         "reason": "JVM execution catalog is empty"})
    if not native_catalog:
        blockers.append({"kind": "execution-catalog", "id": "native-executions.expected.json",
                         "reason": "Native execution catalog is empty"})
    for name, catalog in (("JVM", jvm_catalog), ("Native", native_catalog)):
        execution_ids = [row.get("execution_id", "") for row in catalog]
        duplicate_ids = sorted(identifier for identifier, count in collections.Counter(execution_ids).items()
                               if not identifier or count > 1)
        for identifier in duplicate_ids:
            blockers.append({"kind": "execution-identity", "id": identifier or "<empty>",
                             "reason": f"empty or duplicate {name} concrete execution ID"})
    catalog_source_ids = (jvm_source_ids | native_source_ids) - {None, ""}
    for identifier in sorted(target_case_ids - catalog_source_ids):
        blockers.append({"kind": "execution-coverage", "id": identifier,
                         "reason": "target upstream function ID is absent from both execution catalogs"})
    for identifier in sorted(catalog_source_ids - target_case_ids):
        blockers.append({"kind": "execution-coverage", "id": str(identifier),
                         "reason": "execution catalog points to a non-target upstream function ID"})

    executions_by_source: dict[str, dict[str, list[str]]] = collections.defaultdict(
        lambda: {"jvm": [], "native": []}
    )
    for platform, catalog in (("jvm", jvm_catalog), ("native", native_catalog)):
        for execution in catalog:
            source_id = str(execution.get("upstream_id", ""))
            execution_id = str(execution.get("execution_id", ""))
            if source_id and execution_id:
                executions_by_source[source_id][platform].append(execution_id)

    api_mapping = {
        "schema_version": 1,
        "upstream_commit": locked_commit,
        "execution_catalog_sha256": catalog_hashes,
        "api_rows": [
            {key: row.get(key, "") for key in (
                "row_id", "module", "representation", "platform_scope", "api_kind", "name",
                "signature", "status", "owner_issue", "upstream_test_refs", "local_test_refs",
                "local_implementation_refs", "local_contract_differences",
            )}
            for row in api_rows
        ],
        "upstream_test_cases": cases,
        "execution_coverage": [
            {
                "upstream_id": identifier,
                "disposition": str(case.get("disposition", "")),
                "mapping": case.get("mapping", {}),
                "jvm_execution_ids": sorted(executions_by_source[identifier]["jvm"]),
                "native_execution_ids": sorted(executions_by_source[identifier]["native"]),
            }
            for case in sorted(cases, key=lambda row: str(row.get("upstream_id", row.get("id", ""))))
            for identifier in [str(case.get("upstream_id", case.get("id", "")))]
        ],
    }
    report = {
        "schema_version": 1,
        "status": "PASS" if not blockers else "FAIL",
        "upstream_commit": locked_commit,
        "api": {
            "row_count": len(api_rows),
            "status_counts": dict(sorted(api_status_counts.items())),
            "blocking_count": sum(api_status_counts.get(state, 0) for state in ("missing", "stub", "unverified")),
            "rows_with_upstream_test_refs": sum(bool(row.get("upstream_test_refs", "").strip()) for row in api_rows),
            "rows_with_local_test_refs": sum(bool(row.get("local_test_refs", "").strip()) for row in api_rows),
        },
        "upstream_tests": {
            "source_function_count": len(indexed_ids),
            "coverage_case_count": len(cases),
            "target_case_count": target_case_count,
            "disposition_counts": dict(sorted(disposition_counts.items())),
            "mapping_status_counts": dict(sorted(mapping_state_counts.items())),
            "jvm_concrete_execution_count": len(jvm_catalog),
            "jvm_execution_catalog_sha256": catalog_hashes["jvm"],
            "jvm_source_function_count": len(jvm_source_ids),
            "native_concrete_execution_count": len(native_catalog),
            "native_execution_catalog_sha256": catalog_hashes["native"],
            "native_source_function_count": len(native_source_ids),
        },
        "blocker_count": len(blockers),
        "blockers": blockers,
    }
    return report, api_mapping


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def validate_candidate_artifacts(summary: dict[str, Any], summary_path: Path,
                                 label: str,
                                 expected_native_execution_ids: set[str] | None = None,
                                 expected_native_source_ids: set[str] | None = None,
                                 expected_native_catalog_sha256: str | None = None,
                                 expected_upstream_commit: str | None = None) -> list[str]:
    """Check that a Native candidate summary matches its immutable selection and result files."""
    problems: list[str] = []
    manifest_path = summary_path.with_name("selection.json")
    results_path = summary_path.with_name("results.json")
    selection = summary.get("selection")
    if not manifest_path.is_file():
        problems.append(f"{label}: candidate selection manifest is missing")
    else:
        try:
            manifest = read_json(manifest_path)
            if not isinstance(manifest, dict) or manifest != selection:
                problems.append(f"{label}: candidate selection manifest differs from summary")
            if isinstance(manifest, dict):
                if manifest.get("target") != "macos":
                    problems.append(f"{label}: candidate target is not macos")
                if expected_upstream_commit and manifest.get("upstream_commit") != expected_upstream_commit:
                    problems.append(f"{label}: candidate upstream commit differs from the audit lock")
                if manifest.get("selection_mode") != "full-target-catalog":
                    problems.append(f"{label}: candidate selection mode is not full-target-catalog")
                if not manifest.get("covers_full_catalog"):
                    problems.append(f"{label}: candidate selection does not cover the full target catalog")
                if (expected_native_catalog_sha256
                        and manifest.get("catalog_sha256") != expected_native_catalog_sha256):
                    problems.append(f"{label}: candidate Native catalog hash differs from the audit lock")
                input_hashes = manifest.get("input_hashes")
                if not isinstance(input_hashes, dict):
                    problems.append(f"{label}: candidate selection input hashes are missing")
                elif (expected_native_catalog_sha256
                      and input_hashes.get("catalog_sha256") != expected_native_catalog_sha256):
                    problems.append(f"{label}: candidate input Native catalog hash differs from the audit lock")
                elif isinstance(input_hashes, dict):
                    for key in ("compiler_sha256", "runtime_sources_sha256", "catalog_sha256",
                                "runner_sha256", "driver_sha256"):
                        digest = input_hashes.get(key)
                        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
                            problems.append(f"{label}: candidate input hash {key} is missing or malformed")
                    summary_inputs = summary.get("inputs")
                    if not isinstance(summary_inputs, dict):
                        problems.append(f"{label}: candidate summary input hashes are missing")
                    else:
                        for key, digest in input_hashes.items():
                            if summary_inputs.get(key) != digest:
                                problems.append(f"{label}: candidate selection input hash {key} differs from summary")
                        if summary_inputs.get("selection_manifest_sha256") != hashlib.sha256(
                                manifest_path.read_bytes()).hexdigest():
                            problems.append(f"{label}: candidate summary selection hash does not match")
                    recorded_workspace_sha = input_hashes.get("workspace_git_sha")
                    if expected_upstream_commit and not isinstance(recorded_workspace_sha, str):
                        problems.append(f"{label}: candidate workspace Git SHA is missing")
                selected_source_ids = manifest.get("selected_source_function_ids")
                if (not isinstance(selected_source_ids, list)
                        or len(selected_source_ids) != len(set(selected_source_ids))):
                    problems.append(f"{label}: selected source-function IDs are missing or duplicated")
                elif (expected_native_source_ids is not None
                      and set(selected_source_ids) != expected_native_source_ids):
                    problems.append(f"{label}: selected source-function IDs do not cover the full Native catalog")
                selected_ids = manifest.get("selected_execution_ids")
                if not isinstance(selected_ids, list) or any(not isinstance(value, str) for value in selected_ids):
                    problems.append(f"{label}: selected execution IDs are missing or malformed")
                elif len(selected_ids) != len(set(selected_ids)):
                    problems.append(f"{label}: selected execution IDs are duplicated")
                else:
                    if manifest.get("selected_execution_count") != len(selected_ids):
                        problems.append(f"{label}: selected execution count differs from its manifest")
                    if expected_native_execution_ids is not None and set(selected_ids) != expected_native_execution_ids:
                        problems.append(f"{label}: selected execution IDs do not cover the full Native catalog")
            recorded_hash = summary.get("selection_manifest_sha256")
            actual_hash = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
            if recorded_hash != actual_hash:
                problems.append(f"{label}: candidate selection manifest hash does not match")
        except (OSError, json.JSONDecodeError) as error:
            problems.append(f"{label}: candidate selection manifest is unreadable: {error}")
    if not results_path.is_file():
        problems.append(f"{label}: candidate results file is missing")
        return problems
    try:
        results = read_json(results_path)
        if not isinstance(results, list) or not isinstance(selection, dict):
            raise TypeError("candidate results and selection must be lists/objects")
        result_ids = [str(row.get("execution_id", "")) for row in results if isinstance(row, dict)]
        if len(result_ids) != len(results) or len(result_ids) != len(set(result_ids)):
            problems.append(f"{label}: candidate result IDs are malformed or duplicated")
        selected_ids = selection.get("selected_execution_ids")
        if not isinstance(selected_ids, list) or len(selected_ids) != len(set(selected_ids)):
            problems.append(f"{label}: selected execution IDs are missing or duplicated")
        elif result_ids != selected_ids:
            problems.append(f"{label}: candidate result IDs differ from the selection manifest")
        if any(str(row.get("status", "NOT_RUN")).upper() != "PASS" for row in results
               if isinstance(row, dict)):
            problems.append(f"{label}: candidate results contain a non-PASS execution")
    except (OSError, TypeError, ValueError, json.JSONDecodeError) as error:
        problems.append(f"{label}: candidate results are unreadable: {error}")
    return problems


def audit_command(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    try:
        report, mapping = audit_static(root)
        commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        try:
            report, mapping = audit_static(root)
        except (OSError, ValueError, KeyError, TypeError, AttributeError, IndexError,
                json.JSONDecodeError, csv.Error) as error:
            report = {"schema_version": 1, "status": "FAIL", "blocker_count": 1,
                      "blockers": [{"kind": "audit-input", "id": str(root), "reason": str(error)}]}
            mapping = {"schema_version": 1, "api_rows": [], "upstream_test_cases": []}
        commit = args.commit or "unknown"
    except (OSError, ValueError, KeyError, TypeError, AttributeError, IndexError,
            json.JSONDecodeError, csv.Error) as error:
        report = {"schema_version": 1, "status": "FAIL", "blocker_count": 1,
                  "blockers": [{"kind": "audit-input", "id": str(root), "reason": str(error)}]}
        mapping = {"schema_version": 1, "api_rows": [], "upstream_test_cases": []}
        commit = args.commit or "unknown"
    report["commit"] = args.commit or commit
    try:
        generation = subprocess.run(
            [sys.executable, str(root / "Scripts/io_api_inventory/generate.py"), "--check"],
            cwd=root, capture_output=True, text=True, timeout=300, check=False,
        )
        generation_result = {
            "status": "PASS" if generation.returncode == 0 else "FAIL",
            "exit_code": generation.returncode,
            "stdout": generation.stdout,
            "stderr": generation.stderr,
        }
    except (OSError, subprocess.TimeoutExpired) as error:
        generation_result = {"status": "FAIL", "exit_code": 124, "error": str(error),
                             "stdout": "", "stderr": ""}
    report["inventory_generation"] = generation_result
    if generation_result["status"] != "PASS":
        report.setdefault("blockers", []).append({
            "kind": "api-inventory-reproducibility",
            "id": "Scripts/io_api_inventory/generate.py --check",
            "reason": generation_result.get("error") or generation_result.get("stderr", "").strip()[-2000:],
        })
        report["blocker_count"] = len(report["blockers"])
    report["status"] = "PASS" if report["blocker_count"] == 0 else "FAIL"
    write_json(output / "api-gate-summary.json", report)
    write_json(output / "api-coverage-mapping.json", mapping)
    (output / "inventory-generation.stdout").write_text(generation_result.get("stdout", ""), encoding="utf-8")
    (output / "inventory-generation.stderr").write_text(generation_result.get("stderr", ""), encoding="utf-8")
    for relative in ("Scripts/io_api_inventory/api-inventory.tsv",
                     "Scripts/kotlinx_io_upstream/coverage-map.seed.json"):
        source = root / relative
        if source.is_file():
            shutil.copy2(source, output / source.name)
    print(json.dumps({key: report[key] for key in ("status", "commit", "api", "upstream_tests", "blocker_count")},
                     ensure_ascii=False))
    return 0 if report["status"] == "PASS" else 1


def receipt_command(args: argparse.Namespace) -> int:
    try:
        actual_commit = subprocess.check_output(
            ["git", "-C", str(REPO), "rev-parse", "HEAD"], text=True,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"cannot verify checkout SHA for receipt: {error}", file=sys.stderr)
        return 1
    write_json(args.output.resolve(), {
        "job": args.job,
        "workflow_job": args.workflow_job,
        "status": args.status.lower(),
        "commit": actual_commit,
        "expected_commit": args.commit,
        "run_id": args.run_id,
        "run_attempt": args.run_attempt,
    })
    if actual_commit != args.commit:
        print(f"checkout SHA {actual_commit} differs from expected {args.commit}", file=sys.stderr)
        return 1
    return 0


def finalize_command(args: argparse.Namespace) -> int:
    evidence = args.evidence.resolve()
    try:
        job_results = json.loads(args.job_results_json)
    except json.JSONDecodeError as error:
        job_results = {}
        parse_error = str(error)
    else:
        parse_error = None

    receipts: list[dict[str, Any]] = []
    for path in sorted(evidence.rglob("job-receipt.json")) if evidence.exists() else []:
        try:
            receipt = read_json(path)
            receipt["artifact_file"] = str(path.relative_to(evidence))
            receipts.append(receipt)
        except (OSError, json.JSONDecodeError) as error:
            receipts.append({"artifact_file": str(path), "status": "invalid", "error": str(error)})

    blockers: list[str] = []
    if parse_error:
        blockers.append(f"needs result JSON is invalid: {parse_error}")
    if not isinstance(job_results, dict) or not job_results:
        blockers.append("workflow produced no required-job results")
        job_results = {}
    missing_jobs = sorted(REQUIRED_WORKFLOW_JOBS - set(job_results))
    unexpected_jobs = sorted(set(job_results) - REQUIRED_WORKFLOW_JOBS)
    blockers.extend(f"missing workflow job result: {name}" for name in missing_jobs)
    blockers.extend(f"unexpected workflow job result: {name}" for name in unexpected_jobs)
    for name, result in sorted(job_results.items()):
        status = result.get("result") if isinstance(result, dict) else None
        if status != "success":
            blockers.append(f"required workflow job {name} concluded {status or 'unknown'}")

    expected = set(args.expected_receipts)
    by_name: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for receipt in receipts:
        by_name[str(receipt.get("job", ""))].append(receipt)
        if receipt.get("commit") != args.commit:
            blockers.append(f"receipt {receipt.get('job', '<unknown>')} uses commit {receipt.get('commit')!r}, expected {args.commit}")
        if str(receipt.get("run_id")) != str(args.run_id):
            blockers.append(f"receipt {receipt.get('job', '<unknown>')} belongs to run {receipt.get('run_id')!r}, expected {args.run_id}")
        if str(receipt.get("run_attempt")) != str(args.run_attempt):
            blockers.append(f"receipt {receipt.get('job', '<unknown>')} belongs to attempt {receipt.get('run_attempt')!r}, expected {args.run_attempt}")
        if receipt.get("status") != "success":
            blockers.append(f"receipt {receipt.get('job', '<unknown>')} concluded {receipt.get('status', 'unknown')}")
    for name in sorted(expected - set(by_name)):
        blockers.append(f"missing job receipt: {name}")
    for name in sorted(set(by_name) - expected):
        blockers.append(f"unexpected job receipt: {name}")
    for name in sorted(expected & set(by_name)):
        if len(by_name[name]) != 1:
            blockers.append(f"job {name} produced {len(by_name[name])} receipts; expected exactly one")

    for name, (artifact_marker, suffix) in sorted(REQUIRED_SUMMARY_ARTIFACTS.items()):
        matches = [path for path in evidence.rglob("*.json")
                   if artifact_marker in path.as_posix() and path.as_posix().endswith(suffix)] if evidence.exists() else []
        if len(matches) != 1:
            blockers.append(f"required evidence summary {name} found {len(matches)} times; expected exactly one")
        else:
            try:
                if not isinstance(read_json(matches[0]), dict):
                    blockers.append(f"required evidence summary {name} is not a JSON object")
            except (OSError, json.JSONDecodeError) as error:
                blockers.append(f"required evidence summary {name} is unreadable: {error}")

    expected_jvm_execution_count: int | None = None
    expected_native_execution_count: int | None = None
    expected_native_execution_ids: set[str] | None = None
    expected_native_source_ids: set[str] | None = None
    expected_native_catalog_sha256: str | None = None
    expected_upstream_commit: str | None = None
    api_mapping_files = [path for path in evidence.rglob("api-coverage-mapping.json")
                         if "kotlinx-io-gate-api-" in path.as_posix()] if evidence.exists() else []
    api_summary_files = [path for path in evidence.rglob("api-gate-summary.json")
                         if "kotlinx-io-gate-api-" in path.as_posix()] if evidence.exists() else []
    if len(api_mapping_files) != 1:
        blockers.append(f"API coverage mapping found {len(api_mapping_files)} times; expected exactly one")
    elif len(api_summary_files) == 1:
        try:
            api_mapping = read_json(api_mapping_files[0])
            api_report = read_json(api_summary_files[0])
            if not isinstance(api_mapping, dict) or not isinstance(api_report, dict):
                raise TypeError("API mapping and audit summary must be JSON objects")
            expected_native_execution_count = api_report.get("upstream_tests", {}).get(
                "native_concrete_execution_count"
            )
            expected_native_execution_ids = {
                str(identifier)
                for row in api_mapping.get("execution_coverage", []) if isinstance(row, dict)
                for identifier in row.get("native_execution_ids", [])
            }
            expected_native_source_ids = {
                str(row.get("upstream_id", ""))
                for row in api_mapping.get("execution_coverage", []) if isinstance(row, dict)
                if row.get("native_execution_ids")
            }
            expected_native_source_ids.discard("")
            expected_native_catalog_sha256 = api_report.get("upstream_tests", {}).get(
                "native_execution_catalog_sha256"
            )
            expected_upstream_commit = api_report.get("upstream_commit")
            mapping_catalog_hash = api_mapping.get("execution_catalog_sha256", {}).get("native")
            if not isinstance(expected_upstream_commit, str) or not expected_upstream_commit:
                blockers.append("API audit summary is missing its locked upstream commit")
            if (not isinstance(expected_native_catalog_sha256, str)
                    or len(expected_native_catalog_sha256) != 64
                    or any(character not in "0123456789abcdef" for character in expected_native_catalog_sha256)):
                blockers.append("API audit summary is missing its locked Native catalog hash")
            if api_mapping.get("upstream_commit") != expected_upstream_commit:
                blockers.append("API mapping upstream commit differs from the audit summary")
            if expected_native_catalog_sha256 != mapping_catalog_hash:
                blockers.append("API mapping Native catalog hash differs from the audit summary")
            if (expected_native_execution_count is not None
                    and len(expected_native_execution_ids) != expected_native_execution_count):
                blockers.append("API mapping Native execution IDs differ from the audit catalog count")
            native_source_count = api_report.get("upstream_tests", {}).get("native_source_function_count")
            if native_source_count is not None and len(expected_native_source_ids) != native_source_count:
                blockers.append("API mapping Native source-function IDs differ from the audit catalog count")
            expected_jvm_execution_count = api_report.get("upstream_tests", {}).get(
                "jvm_concrete_execution_count"
            )
            if len(api_mapping.get("api_rows", [])) != api_report.get("api", {}).get("row_count"):
                blockers.append("API coverage mapping row count differs from the API audit summary")
            if len(api_mapping.get("upstream_test_cases", [])) != api_report.get("upstream_tests", {}).get("coverage_case_count"):
                blockers.append("API coverage mapping test count differs from the API audit summary")
            if len(api_mapping.get("execution_coverage", [])) != api_report.get("upstream_tests", {}).get("coverage_case_count"):
                blockers.append("API concrete execution coverage count differs from the API audit summary")
            case_rows = api_mapping.get("upstream_test_cases", [])
            execution_rows = api_mapping.get("execution_coverage", [])
            case_ids = [str(row.get("upstream_id", row.get("id", "")))
                        for row in case_rows if isinstance(row, dict)]
            execution_ids = [str(row.get("upstream_id", ""))
                             for row in execution_rows if isinstance(row, dict)]
            if len(case_ids) != len(case_rows) or len(execution_ids) != len(execution_rows):
                blockers.append("API coverage mapping contains malformed case rows")
            if len(case_ids) != len(set(case_ids)) or set(case_ids) != set(execution_ids):
                blockers.append("API concrete execution coverage IDs do not exactly match upstream cases")
            for row in execution_rows:
                if not isinstance(row, dict):
                    continue
                disposition = str(row.get("disposition", "")).lower()
                ids = row.get("jvm_execution_ids", []) + row.get("native_execution_ids", [])
                if disposition != "unsupported" and not ids:
                    blockers.append(f"API concrete execution mapping is empty for {row.get('upstream_id', '<empty>')}")
        except (OSError, TypeError, AttributeError, json.JSONDecodeError) as error:
            blockers.append(f"API coverage mapping is invalid: {error}")

    summaries: list[dict[str, Any]] = []
    for path in sorted(evidence.rglob("*.json")) if evidence.exists() else []:
        if path.name in {"job-receipt.json", "needs.json"}:
            continue
        try:
            value = read_json(path)
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(value, dict) and any(key in value for key in ("status", "counts", "reference_counts")):
            artifact_file = str(path.relative_to(evidence))
            summary = {key: value[key] for key in (
                "status", "kind", "target", "optimization", "required_optimization", "commit",
                "workspace_git_sha", "stdlib_mode", "test_body_mode", "exit_code", "timed_out",
                "expected_count", "candidate_executions", "concrete_execution_count", "reference_counts",
                "candidate_counts", "counts", "selected_cases", "lanes", "optimization_lanes",
                "expected_lane_count", "api", "upstream_tests", "blocker_count",
                "inventory_generation", "expected_case_count", "expected_case_ids", "selection",
                "selection_manifest_sha256",
            ) if key in value}
            try:
                if isinstance(value.get("results"), list):
                    result_states = collections.Counter(
                        str(row.get("status", "NOT_RUN")).upper()
                        for row in value["results"] if isinstance(row, dict)
                    )
                    summary["result_count"] = len(value["results"])
                    summary["result_status_counts"] = dict(sorted(result_states.items()))
                if value.get("kind") == "kotlinx-io-diff-matrix":
                    optimizations = value.get("optimizations", {})
                    if not isinstance(optimizations, dict):
                        raise TypeError("optimization summaries must be an object")
                    summary["lane_counts"] = {
                        optimization: lane.get("counts", {})
                        for optimization, lane in optimizations.items()
                        if isinstance(lane, dict)
                    }
                if value.get("kind") == "ktor-io-consumer":
                    summary["counts"] = {"PASS": len(value.get("optimization_lanes", []))}
                if "api" in value or "upstream_tests" in value:
                    api_counts = value.get("api")
                    test_counts = value.get("upstream_tests")
                    if not isinstance(api_counts, dict) or not isinstance(test_counts, dict):
                        raise TypeError("API and upstream test counts must be objects")
                    summary["counts"] = {
                        "api_rows": api_counts.get("row_count", 0),
                        "api_blocking_rows": api_counts.get("blocking_count", 0),
                        "upstream_functions": test_counts.get("source_function_count", 0),
                        "target_functions": test_counts.get("target_case_count", 0),
                        "jvm_executions": test_counts.get("jvm_concrete_execution_count", 0),
                        "native_executions": test_counts.get("native_concrete_execution_count", 0),
                    }
                summary_blockers = validate_summary(
                    value, artifact_file, args.commit, expected_native_execution_count,
                    expected_jvm_execution_count, expected_native_execution_ids,
                )
                if "/candidate/" in artifact_file:
                    summary_blockers.extend(validate_candidate_artifacts(
                        value, path, artifact_file, expected_native_execution_ids,
                        expected_native_source_ids, expected_native_catalog_sha256,
                        expected_upstream_commit,
                    ))
            except (TypeError, ValueError, KeyError, AttributeError) as error:
                summary = {"status": "INVALID", "error": str(error)}
                summary_blockers = [f"{artifact_file}: malformed summary: {error}"]
            if "status" not in summary and isinstance(value.get("reference_counts"), dict) and not summary_blockers:
                summary["status"] = "PASS"
            summary["artifact_file"] = artifact_file
            blockers.extend(summary_blockers)
            summaries.append(summary)

    final = {
        "schema_version": 1,
        "status": "PASS" if not blockers else "FAIL",
        "commit": args.commit,
        "workflow_run_id": args.run_id,
        "workflow_run_attempt": args.run_attempt,
        "workflow_job_results": {name: row.get("result") if isinstance(row, dict) else None
                                  for name, row in sorted(job_results.items())},
        "job_receipts": receipts,
        "summaries": summaries,
        "blocker_count": len(blockers),
        "blockers": blockers,
    }
    output = args.output.resolve()
    write_json(output / "gate-summary.json", final)
    markdown = ["# kotlinx-io gate result", "", f"- Status: **{final['status']}**",
                f"- Commit: `{args.commit}`", f"- Blocking findings: **{len(blockers)}**", ""]
    markdown += [f"- {blocker}" for blocker in blockers] or ["- Every required job and receipt passed on this commit."]
    markdown += ["", "## Evidence summaries", "", "| Artifact | Status | Count summary |", "|---|---|---|"]
    for item in summaries:
        counts = item.get("counts", item.get("reference_counts", item.get("result_status_counts", item.get("lane_counts", {}))))
        markdown.append(f"| `{item['artifact_file']}` | {item.get('status', 'recorded')} | `{json.dumps(counts, ensure_ascii=False)}` |")
    (output / "gate-summary.md").write_text("\n".join(markdown) + "\n", encoding="utf-8")
    print((output / "gate-summary.md").read_text(encoding="utf-8"))
    return 0 if final["status"] == "PASS" else 1


def validate_summary(
    value: dict[str, Any], label: str, expected_commit: str | None = None,
    expected_native_execution_count: int | None = None,
    expected_jvm_execution_count: int | None = None,
    expected_native_execution_ids: set[str] | None = None,
) -> list[str]:
    """Reject failed summaries even if a workflow step masked its exit code."""
    problems: list[str] = []
    status = str(value.get("status", "")).strip().lower()
    accepted = {"pass", "selected_matrix_pass"}
    if status and status not in accepted:
        problems.append(f"{label}: summary status is {value.get('status')}")
    if "exit_code" in value and value.get("exit_code") != 0:
        problems.append(f"{label}: runner exit code is {value.get('exit_code')}")
    if value.get("timed_out") is True:
        problems.append(f"{label}: run timed out")
    if expected_commit:
        for key in ("commit", "workspace_git_sha"):
            recorded_commit = value.get(key)
            if recorded_commit and recorded_commit != expected_commit:
                problems.append(f"{label}: {key} is {recorded_commit!r}; expected {expected_commit}")

    if isinstance(value.get("reference_counts"), dict):
        expected = int(value.get("concrete_execution_count", 0))
        problems.extend(validate_execution_counts(value["reference_counts"], expected, label))
        if "reference-jvm-" in label and expected_jvm_execution_count is not None and expected != expected_jvm_execution_count:
            problems.append(f"{label}: reference execution count does not cover the full JVM catalog")
        if "reference-native-apple-" in label and expected_native_execution_count is not None and expected != expected_native_execution_count:
            problems.append(f"{label}: reference execution count does not cover the full Apple Native catalog")
    elif isinstance(value.get("counts"), dict) and "expected_count" in value:
        problems.extend(validate_execution_counts(value["counts"], int(value["expected_count"]), label))

    if "/candidate/" in label:
        path_parts = label.split("/")
        try:
            lane = path_parts[path_parts.index("candidate") + 1]
            route, optimization = lane.rsplit("-", 1)
        except (ValueError, IndexError):
            problems.append(f"{label}: candidate route/optimization is missing from the artifact path")
        else:
            expected_stdlib_mode = "source" if route == "source" else "library"
            expected_test_body_mode = "library-consumer" if route == "producer-consumer" else "source"
            if value.get("optimization") != optimization:
                problems.append(f"{label}: candidate optimization does not match its artifact lane")
            if value.get("stdlib_mode") != expected_stdlib_mode:
                problems.append(f"{label}: candidate stdlib route does not match its artifact lane")
            if value.get("test_body_mode") != expected_test_body_mode:
                problems.append(f"{label}: candidate test-body route does not match its artifact lane")
            if expected_native_execution_count is not None and int(value.get("expected_count", 0)) != expected_native_execution_count:
                problems.append(f"{label}: candidate execution count does not cover the full Native catalog")
            selection = value.get("selection")
            if not isinstance(selection, dict):
                problems.append(f"{label}: candidate selection manifest is missing from the summary")
            else:
                if selection.get("selection_mode") != "full-target-catalog":
                    problems.append(f"{label}: candidate selection mode is {selection.get('selection_mode')!r}; expected full-target-catalog")
                full_count = selection.get("target_catalog_execution_count")
                selected_count = selection.get("selected_execution_count")
                selected_ids = selection.get("selected_execution_ids")
                if expected_native_execution_count is not None and full_count != expected_native_execution_count:
                    problems.append(f"{label}: selection full-catalog count differs from the Native catalog")
                if selected_count != value.get("expected_count"):
                    problems.append(f"{label}: selection count differs from expected execution count")
                if not isinstance(selected_ids, list) or len(selected_ids) != len(set(selected_ids)):
                    problems.append(f"{label}: selected execution IDs are missing or duplicated")
                else:
                    if len(selected_ids) != selected_count:
                        problems.append(f"{label}: selected execution ID count differs from its manifest")
                    if expected_native_execution_ids is not None and set(selected_ids) != expected_native_execution_ids:
                        problems.append(f"{label}: selected execution IDs do not cover the full Native catalog")
                if selection.get("covers_full_catalog") is not True:
                    problems.append(f"{label}: candidate selection is not marked as full-catalog coverage")
                if selection.get("requested_source_function_ids") or selection.get("requested_execution_ids"):
                    problems.append(f"{label}: full-catalog run contains an explicit ID selection")
                input_hashes = selection.get("input_hashes")
                if not isinstance(input_hashes, dict):
                    problems.append(f"{label}: candidate input hashes are missing from the selection manifest")
                else:
                    for key in ("compiler_sha256", "runtime_sources_sha256", "catalog_sha256",
                                "runner_sha256", "driver_sha256"):
                        digest = input_hashes.get(key)
                        if (not isinstance(digest, str) or len(digest) != 64
                                or any(character not in "0123456789abcdef" for character in digest)):
                            problems.append(f"{label}: candidate selection input hash {key} is missing or malformed")
                    recorded_workspace_sha = input_hashes.get("workspace_git_sha")
                    if expected_commit and recorded_workspace_sha != expected_commit:
                        problems.append(f"{label}: selection workspace SHA does not match the workflow commit")
                if expected_commit and value.get("workspace_git_sha") != expected_commit:
                    problems.append(f"{label}: candidate workspace SHA does not match the workflow commit")
            manifest_hash = value.get("selection_manifest_sha256")
            if (not isinstance(manifest_hash, str) or len(manifest_hash) != 64
                    or any(character not in "0123456789abcdef" for character in manifest_hash)):
                problems.append(f"{label}: candidate selection manifest hash is missing or malformed")

    if value.get("kind") == "kotlinx-io-diff-matrix":
        expected_cases = int(value.get("expected_case_count", 0))
        manifest = value.get("case_manifest", [])
        expected_names = {str(row.get("name")) for row in manifest if isinstance(row, dict)}
        optimizations = value.get("optimizations", {})
        required_optimization = value.get("required_optimization")
        expected_optimizations = ({required_optimization} if required_optimization in {"O0", "O2"}
                                  else {"O0", "O2"})
        if expected_cases <= 0 or len(expected_names) != expected_cases:
            problems.append(f"{label}: missing or duplicate expected diff cases")
        if set(optimizations) != expected_optimizations:
            problems.append(f"{label}: optimization lanes are {sorted(optimizations)}; expected {sorted(expected_optimizations)}")
        for optimization, lane in optimizations.items():
            if not isinstance(lane, dict):
                problems.append(f"{label} {optimization}: lane summary is not an object")
                continue
            if str(lane.get("status", "")).upper() != "PASS":
                problems.append(f"{label} {optimization}: lane status is {lane.get('status', 'missing')}")
            if lane.get("exit_code") != 0:
                problems.append(f"{label} {optimization}: runner exit code is {lane.get('exit_code', 'missing')}")
            if lane.get("timed_out") is not False:
                problems.append(f"{label} {optimization}: lane timed out or timeout evidence is missing")
            counts = lane.get("counts", {}) if isinstance(lane, dict) else {}
            problems.extend(validate_execution_counts(counts, expected_cases, f"{label} {optimization}"))
            case_statuses = lane.get("case_statuses", {}) if isinstance(lane, dict) else {}
            if set(case_statuses) != expected_names:
                problems.append(f"{label} {optimization}: case set differs from the manifest")
            if any(str(status).upper() != "PASS" for status in case_statuses.values()):
                problems.append(f"{label} {optimization}: non-PASS case status exists")
    if value.get("kind") == "ktor-io-consumer":
        lanes = value.get("optimization_lanes", [])
        expected_lanes = {"O0", "O2"}
        prefix = "PASS ktor_io_macos compile + consumer link/run "
        observed_lanes = [str(row)[len(prefix):] for row in lanes
                          if str(row).startswith(prefix)]
        if int(value.get("expected_lane_count", 0)) != 2 or len(lanes) != 2 or set(observed_lanes) != expected_lanes:
            problems.append(f"{label}: Ktor consumer did not record exactly one O0 and one O2 lane")

    results = value.get("results")
    is_f02_summary = ("selected_cases" in value or "lanes" in value
                      or label.endswith("/f02/results/summary.json"))
    if is_f02_summary:
        selected_cases = value.get("selected_cases")
        expected_case_ids = value.get("expected_case_ids")
        lanes = value.get("lanes")
        if not isinstance(selected_cases, list) or not isinstance(lanes, list):
            problems.append(f"{label}: F02 selected_cases or lanes are missing")
        if not isinstance(expected_case_ids, list):
            problems.append(f"{label}: F02 expected_case_ids manifest is missing")
        elif (len(expected_case_ids) != len(set(expected_case_ids))
              or set(expected_case_ids) != set(selected_cases or [])):
            problems.append(f"{label}: F02 selected cases differ from the full scenario manifest")
        if not isinstance(results, list):
            problems.append(f"{label}: F02 result rows are missing")

    if isinstance(results, list):
        statuses = collections.Counter(str(row.get("status", "NOT_RUN")).upper() for row in results
                                       if isinstance(row, dict))
        if statuses and any(state != "PASS" and count for state, count in statuses.items()):
            problems.extend(f"{label}: {state}={count}" for state, count in sorted(statuses.items())
                            if state != "PASS" and count)
        if statuses and statuses.get("PASS", 0) != len(results):
            problems.append(f"{label}: PASS={statuses.get('PASS', 0)}; result rows={len(results)}")
        selected_cases = value.get("selected_cases")
        lanes = value.get("lanes")
        if is_f02_summary and isinstance(selected_cases, list) and isinstance(lanes, list):
            if not selected_cases:
                problems.append(f"{label}: no F02 cases were selected")
            normalized_lane_rows = [tuple(str(part) for part in lane) for lane in lanes
                                    if isinstance(lane, (list, tuple))]
            normalized_lanes = set(normalized_lane_rows)
            if normalized_lanes != F02_LANES or len(normalized_lane_rows) != len(F02_LANES):
                problems.append(f"{label}: F02 lane set differs from the required six routes")
            expected_results = len(selected_cases) * len(F02_LANES)
            if len(results) != expected_results:
                problems.append(f"{label}: result rows={len(results)}; expected matrix rows={expected_results}")
            expected_matrix = collections.Counter(
                (case, route, optimization)
                for case in selected_cases
                for route, optimization in F02_LANES
            )
            actual_matrix = collections.Counter(
                (str(row.get("case", "")), str(row.get("route", "")), str(row.get("optimization", "")))
                for row in results if isinstance(row, dict)
            )
            if actual_matrix != expected_matrix:
                problems.append(f"{label}: F02 result rows contain missing, duplicate, or unexpected case/lane tuples")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    audit = commands.add_parser("audit", help="audit the pinned API and upstream test maps")
    audit.add_argument("--root", type=Path, default=REPO)
    audit.add_argument("--output", type=Path, required=True)
    audit.add_argument("--commit")
    audit.set_defaults(run=audit_command)

    receipt = commands.add_parser("receipt", help="write a workflow job receipt")
    receipt.add_argument("--job", required=True)
    receipt.add_argument("--workflow-job", required=True)
    receipt.add_argument("--status", required=True)
    receipt.add_argument("--commit", required=True)
    receipt.add_argument("--run-id", required=True)
    receipt.add_argument("--run-attempt", required=True)
    receipt.add_argument("--output", type=Path, required=True)
    receipt.set_defaults(run=receipt_command)

    finalize = commands.add_parser("finalize", help="aggregate same-commit gate artifacts")
    finalize.add_argument("--evidence", type=Path, required=True)
    finalize.add_argument("--job-results-json", required=True)
    finalize.add_argument("--expected-receipts", required=True,
                          help="comma-separated logical receipt names")
    finalize.add_argument("--commit", required=True)
    finalize.add_argument("--run-id", required=True)
    finalize.add_argument("--run-attempt", required=True)
    finalize.add_argument("--output", type=Path, required=True)
    finalize.set_defaults(run=finalize_command)

    args = parser.parse_args(argv)
    if args.command == "finalize":
        args.expected_receipts = [item for item in args.expected_receipts.split(",") if item]
    return args.run(args)


if __name__ == "__main__":
    raise SystemExit(main())
