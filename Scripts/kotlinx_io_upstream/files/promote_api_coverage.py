#!/usr/bin/env python3
"""Promote only fully evidenced common/Native rows from a bound candidate ledger.

The input index maps check IDs to immutable receipt paths/hashes. Each receipt
records actual individual check results, phase codes, reaping, and the same
candidate fingerprint. Compilation alone and historical PASS never promote a
row; JVM coordination remains KUU-1762. This does not manufacture receipts.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re

FINGERPRINT_KEYS = {"main_head", "sources_sha256", "runtime_abi_sha256", "compiler_sha256",
                    "stdlib_all_files_sha256", "stdlib_producer_sha256", "fixtures_sha256",
                    "expected_shapes_sha256", "lock_sha256", "runner_sha256"}


def fingerprint_valid(value: object) -> bool:
    return isinstance(value, dict) and FINGERPRINT_KEYS <= set(value) and all(
        isinstance(value[key], str) and re.fullmatch(r"[0-9a-f]{40}" if key == "main_head" else r"[0-9a-f]{64}", value[key])
        for key in FINGERPRINT_KEYS)


def promote(ledger: dict, evidence: dict, base: Path) -> dict:
    result = copy.deepcopy(ledger)
    if ledger.get("schema_version") != 1 or evidence.get("schema_version") != 1:
        raise ValueError("unsupported schema")
    definitions = {c["check_id"]: c for c in ledger["checks"]}
    if len(definitions) != len(ledger["checks"]):
        raise ValueError("duplicate ledger check ID")
    if len({r["row_id"] for r in ledger["rows"]}) != len(ledger["rows"]):
        raise ValueError("duplicate ledger row ID")
    known = set(definitions)
    for row in ledger["rows"]:
        if not set(row["required_check_ids"]) <= known:
            raise ValueError("row references unknown check")
    entries = evidence.get("receipts", [])
    actual_ids = [e["check_id"] for e in entries]
    if len(set(actual_ids)) != len(entries) or not set(actual_ids) <= known:
        raise ValueError("duplicate or unknown evidence check ID")
    candidate = ledger.get("candidate_fingerprint")
    if entries and (not fingerprint_valid(candidate) or evidence.get("candidate_fingerprint") != candidate):
        raise ValueError("candidate must be rebound after implementation/build; stale or preparation-only evidence")
    verified = set()
    observed = {}
    cache = {}
    for entry in entries:
        path = (base / entry["path"]).resolve()
        if path not in cache:
            raw = path.read_bytes()
            cache[path] = (hashlib.sha256(raw).hexdigest(), json.loads(raw))
        digest, receipt = cache[path]
        if digest != entry["sha256"]:
            raise ValueError("immutable receipt hash mismatch")
        if receipt.get("candidate_fingerprint") != candidate:
            raise ValueError("receipt comes from a different candidate")
        check_id = entry["check_id"]
        actual = [c for c in receipt.get("checks", []) if c.get("check_id") == check_id]
        if len(actual) != 1 or actual[0].get("kind") != definitions[check_id]["kind"]:
            raise ValueError("receipt must identify the exact single declared check and kind")
        codes = receipt.get("phase_exitcodes", {})
        ran = bool(codes) and all(type(code) is int and code == 0 for code in codes.values())
        good = (ran and receipt.get("inputs_unchanged") is True and receipt.get("reaped") is True
                and actual[0].get("status") == "PASS")
        observed[check_id] = "PASS" if good else "UNVERIFIED"
        if good:
            artifacts = receipt.get("artifacts", [])
            if not artifacts:
                raise ValueError("PASS needs retained result/raw artifact provenance")
            for artifact in artifacts:
                item = (path.parent / artifact["path"]).resolve()
                if hashlib.sha256(item.read_bytes()).hexdigest() != artifact["sha256"]:
                    raise ValueError("retained artifact hash mismatch")
            verified.add(check_id)
    for check in result["checks"]:
        check["state"] = observed.get(check["check_id"], "NOT_RUN")
    for row in result["rows"]:
        required = set(row["required_check_ids"])
        row["state"] = "PASS" if row["scope"] == "COMMON_NATIVE" and required and required <= verified else "UNVERIFIED"
        row["missing_check_ids"] = sorted(required - verified)
        for cell, check_ids in row.get("required_checks_by_validation_cell", {}).items():
            cell_required = set(check_ids)
            row["validation_cells"][cell] = "PASS" if row["scope"] == "COMMON_NATIVE" and cell_required and cell_required <= verified else "NOT_RUN" if not cell_required.intersection(observed) else "UNVERIFIED"
        if row["scope"] != "COMMON_NATIVE":
            row["coordination_issue"] = "KUU-1762"
    common = [r for r in result["rows"] if r["scope"] == "COMMON_NATIVE"]
    result["state"] = "PASS" if len(common) == 41 and all(r["state"] == "PASS" for r in common) else "UNVERIFIED"
    result["family_including_jvm_state"] = "UNVERIFIED"  # separate owner receipt not inferred
    result["promoted_common_native_rows"] = sum(r["state"] == "PASS" for r in common)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = promote(json.loads(args.ledger.read_text()), json.loads(args.evidence.read_text()), args.evidence.parent)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
