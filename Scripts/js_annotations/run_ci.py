#!/usr/bin/env python3
"""Run JS annotation runner regressions and publish the complete native matrix."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys
import uuid

import run_candidate as candidate
import run_matrix
import summarize_evidence


ROOT = run_matrix.ROOT
SCRIPT_DIR = Path(__file__).resolve().parent


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kswiftc", type=Path, default=ROOT / ".build/debug/kswiftc")
    parser.add_argument("--artifact-root", type=Path, default=ROOT / ".artifacts/js_annotations_ci")
    parser.add_argument("--compile-timeout", type=candidate.positive_seconds, default=600)
    parser.add_argument("--run-timeout", type=candidate.positive_seconds, default=10)
    parser.add_argument("--stdlib-timeout", type=candidate.positive_seconds, default=1800)
    args = parser.parse_args(argv)
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ") + "-" + uuid.uuid4().hex[:8]
    directory = args.artifact_root.resolve() / run_id
    directory.mkdir(parents=True, exist_ok=False)
    origin = ROOT / "Scripts/diff_cases/js_annotations.kt"
    inputs = {
        "pythonVersion": sys.version,
        "runnerSha256": {path.name: candidate.sha256_file(path)
                         for path in sorted(SCRIPT_DIR.glob("*.py"))},
        "workflowRunUrl": (
            f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/"
            f"{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
            if os.environ.get("GITHUB_REPOSITORY") and os.environ.get("GITHUB_RUN_ID") else None
        ),
    }
    if origin.is_file():
        (directory / "original-diff-case.kt").write_bytes(origin.read_bytes())
        inputs["originalDiffCase"] = {
            "path": origin.relative_to(ROOT).as_posix(), "sha256": candidate.sha256_file(origin),
        }
    candidate.write_json(directory / "inputs.json", inputs)
    stages = []
    # Run both adapters even when one regression fails, retaining its exact result.
    for name in ("test_run_candidate", "test_run_matrix", "test_summarize_evidence"):
        command = [sys.executable, str(SCRIPT_DIR / f"{name}.py")]
        result = candidate.run_process(command, timeout=300, cwd=ROOT)
        candidate.record_command_result(directory / name, "test", result, command)
        status = "timeout" if result["timedOut"] else (
            "pass" if result["exitCode"] == 0 else "fail"
        )
        stages.append({"id": name, "status": status, "exitCode": result["exitCode"]})
        print(f"{status.upper()} {name}", flush=True)
    candidate.write_json(directory / "runner-results.json", {"stages": stages})
    evidence = directory / "matrix-results.json"
    matrix_exit = run_matrix.main([
        "--kswiftc", str(args.kswiftc.resolve()),
        "--artifact-root", str(directory / "matrix"),
        "--record-summary", str(evidence),
        "--compile-timeout", str(args.compile_timeout),
        "--run-timeout", str(args.run_timeout),
        "--stdlib-timeout", str(args.stdlib_timeout),
    ])
    report = summarize_evidence.aggregate(json.loads(evidence.read_text()), stages)
    report["inputs"] = inputs
    candidate.write_json(directory / "evidence.json", report)
    markdown = summarize_evidence.render_markdown(report)
    (directory / "evidence.md").write_text(markdown, encoding="utf-8")
    print(markdown)
    print(f"CI evidence: {directory}")
    return 1 if matrix_exit or report["status"] != "pass" else 0


if __name__ == "__main__":
    raise SystemExit(main())
