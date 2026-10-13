#!/usr/bin/env python3
"""Aggregate complete, partial, and failed JS annotation matrix evidence."""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
from typing import Any

import run_matrix


CELLS = tuple(f"{mode}/{level}" for mode in run_matrix.ARTIFACT_MODES
              for level in run_matrix.OPTIMIZATION_LEVELS)


def classify(cell: dict[str, Any] | None) -> str:
    if cell is None:
        return "not-run"
    reasons = cell.get("failureReasons", [])
    if any(reason.startswith(("stdlib_build_", "kswiftc_not_found", "contract_input_",
                              "required_sentinel_", "compile_spawn_")) for reason in reasons):
        return "not-run"
    if any("timeout" in reason for reason in reasons):
        return "timeout"
    if cell.get("compileExitCode") is None:
        return "not-run"
    return "pass" if cell.get("status") == "pass" and not reasons else "fail"


def aggregate(evidence: dict[str, Any], stages: list[dict[str, Any]]) -> dict[str, Any]:
    document, _ = run_matrix.load_contract_sets(run_matrix.DEFAULT_CONTRACT_PAIRS)
    required = [case for case in document["cases"] if "native-compat" in case.get("lanes", [])]
    records = {case["id"]: case for case in evidence.get("cases", [])}
    failures = list(evidence.get("failureReasons", []))
    if len(records) != len(evidence.get("cases", [])):
        failures.append("duplicate_case_evidence")
    artifact = evidence.get("artifact") or {}
    compiler = evidence.get("compiler") or {}
    source = evidence.get("compilerSourceTree") or {}
    if not (artifact.get("sha256") and artifact.get("manifestSha256")
            and compiler.get("sha256") and source.get("sha256") and evidence.get("gitRevision")
            and artifact.get("builderCompilerSha256") == compiler["sha256"]
            and artifact.get("builderSourceTreeSha256") == source["sha256"]
            and artifact.get("builderGitRevision") == evidence["gitRevision"]):
        failures.append("missing_or_mismatched_build_identity")
    if source.get("sha256") != run_matrix.source_tree_identity()["sha256"]:
        failures.append("compiler_source_identity_is_stale")
    if evidence.get("gitRevision") != run_matrix.git_text("rev-parse", "HEAD"):
        failures.append("revision_identity_is_stale")
    rows = []
    for expected in required:
        record = records.get(expected["id"], {})
        cells = record.get("matrix", {})
        statuses = {key: classify(cells.get(key)) for key in CELLS}
        reasons = {key: cells.get(key, {}).get("failureReasons", []) for key in CELLS}
        if record and record.get("sourceSha256") != expected["sourceSha256"]:
            failures.append(f"fixture_identity_mismatch:{expected['id']}")
        rows.append({"id": expected["id"], "source": expected["source"],
                     "cells": statuses, "failureReasons": reasons})
    for path, _ in run_matrix.DEFAULT_CONTRACT_PAIRS:
        inputs = {item["path"]: item["sha256"] for item in evidence.get("expectationInputs", [])}
        relative = path.relative_to(run_matrix.ROOT).as_posix()
        if inputs.get(relative) != run_matrix.candidate.sha256_file(path):
            failures.append(f"expectation_identity_mismatch:{relative}")
    for _, path in run_matrix.DEFAULT_CONTRACT_PAIRS:
        inputs = {item["path"]: item["sha256"] for item in evidence.get("diagnosticMapInputs", [])}
        relative = path.relative_to(run_matrix.ROOT).as_posix()
        if inputs.get(relative) != run_matrix.candidate.sha256_file(path):
            failures.append(f"diagnostic_map_identity_mismatch:{relative}")
    counts = Counter(status for row in rows for status in row["cells"].values())
    runner_pass = {stage["id"] for stage in stages if stage.get("status") == "pass"}
    runner_ready = {"test_run_candidate", "test_run_matrix", "test_summarize_evidence"} <= runner_pass
    ready = (counts["pass"] == len(required) * len(CELLS) and runner_ready
             and evidence.get("status") == "pass" and not failures)
    return {"schemaVersion": 1, "issue": "KUU-1617", "status": "pass" if ready else "fail",
            "skipRemovalReady": ready, "migration": "dedicated-candidate-only-lane",
            "matrixRunId": evidence.get("runId"), "gitRevision": evidence.get("gitRevision"),
            "compiler": evidence.get("compiler"), "swiftVersion": evidence.get("swiftVersion"),
            "platform": evidence.get("platform"), "artifact": evidence.get("artifact"),
            "artifactRunDirectory": evidence.get("artifactRunDirectory"),
            "runnerStages": stages, "failureReasons": failures,
            "counts": {status: counts[status] for status in ("pass", "fail", "timeout", "not-run")},
            "cases": rows,
            "outOfLane": [{"id": case["id"], "lanes": case.get("lanes", [])}
                          for case in document["cases"] if "native-compat" not in case.get("lanes", [])],
            "unexecuted": ["KSwiftK JS emission/consumer (outside native target)",
                           "full Swift tests and full kotlinc diff corpus"],
            "coverageDocument": "docs/js-annotations-ci-evidence.md"}


def render_markdown(report: dict[str, Any]) -> str:
    lines = ["## js_annotations CI evidence (KUU-1617)", "",
             f"Status: **{report['status']}**; SKIP removal ready: **{str(report['skipRemovalReady']).lower()}**.",
             "", f"Revision: `{report['gitRevision']}`; matrix run: `{report['matrixRunId']}`.",
             "", "| Result | Cells |", "|---|---:|"]
    lines.extend(f"| {status} | {count} |" for status, count in report["counts"].items())
    lines.extend(["", "| Fixture | source/O0 | source/O2 | artifact/O0 | artifact/O2 |",
                  "|---|---|---|---|---|"])
    lines.extend("| " + " | ".join([row["id"], *(row["cells"][key] for key in CELLS)]) + " |"
                 for row in report["cases"])
    lines.extend(["", "Runner regressions:", ""])
    lines.extend(f"- {stage['id']}: {stage['status']} (exit={stage.get('exitCode')})"
                 for stage in report["runnerStages"])
    if not report["runnerStages"]:
        lines.append("- not-run")
    lines.extend(["", "Failures:", ""])
    lines.extend(f"- {reason}" for reason in report["failureReasons"])
    for row in report["cases"]:
        reasons = sorted({reason for values in row["failureReasons"].values() for reason in values})
        if reasons:
            lines.append(f"- {row['id']}: " + ", ".join(reasons))
    lines.extend(["", "Out of native lane (not candidate passes): " +
                  ", ".join(case["id"] for case in report["outOfLane"]), "",
                  "Unexecuted: " + "; ".join(report["unexecuted"]), "",
                  "Exact commands, compile/run stdout/stderr, exits, and timeouts are retained in the matrix run directory.",
                  "Coverage and KUU-1480 handoff: `docs/js-annotations-ci-evidence.md`.", ""])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matrix", type=Path, required=True)
    parser.add_argument("--runner-results", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    evidence = json.loads(args.matrix.read_text())
    stages = json.loads(args.runner_results.read_text())["stages"] if args.runner_results else []
    report = aggregate(evidence, stages)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.with_suffix(".json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    args.output.write_text(render_markdown(report), encoding="utf-8")
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
