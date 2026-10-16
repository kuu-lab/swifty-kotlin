#!/usr/bin/env python3
"""Run every kotlinx_io*.kt diff case against the pinned JVM reference at O0/O2."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys

from verify_gate import validate_execution_counts, write_json

ROOT = Path(__file__).resolve().parents[2]
CASE_ROOT = ROOT / "Scripts/diff_cases"


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def parse_report(path: Path) -> tuple[dict[str, int], dict[str, str]]:
    counts: collections.Counter[str] = collections.Counter()
    by_case: dict[str, str] = {}
    if not path.is_file():
        return {}, {}
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split("\t")
        if len(fields) < 2:
            continue
        case = Path(fields[0]).name
        status = fields[1].strip().upper()
        if case in by_case:
            counts["DUPLICATE"] += 1
        by_case[case] = status
        counts[status] += 1
    return dict(counts), by_case


def run_bounded(command: list[str], root: Path, environment: dict[str, str], timeout: int) -> tuple[int, str, str, bool]:
    process = subprocess.Popen(command, cwd=root, env=environment, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
        return process.returncode, stdout, stderr, False
    except subprocess.TimeoutExpired:
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(process.pid, sig)
            except ProcessLookupError:
                pass
            try:
                stdout, stderr = process.communicate(timeout=2)
                break
            except subprocess.TimeoutExpired:
                continue
        else:
            stdout, stderr = process.communicate()
        return 124, stdout or "", stderr or "", True


def run(args: argparse.Namespace) -> int:
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    cases = sorted(CASE_ROOT.glob("kotlinx_io*.kt"))
    case_manifest = [{"name": path.name, "sha256": digest(path)} for path in cases]
    summary: dict = {
        "kind": "kotlinx-io-diff-matrix",
        "status": "RUNNING",
        "commit": subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip(),
        "expected_case_count": len(cases),
        "required_optimization": args.optimization,
        "case_manifest": case_manifest,
        "optimizations": {},
    }
    errors: list[str] = []
    if not cases:
        errors.append("no Scripts/diff_cases/kotlinx_io*.kt files were found")
    if len({path.name for path in cases}) != len(cases):
        errors.append("duplicate kotlinx-io diff case basename")
    for path in (args.compiler, args.kotlinc, args.java):
        if not path.is_file():
            errors.append(f"required executable does not exist: {path}")
    for path in args.classpath:
        if not path.is_file():
            errors.append(f"required reference dependency does not exist: {path}")
    if args.compiler.is_file():
        summary["compiler_sha256"] = digest(args.compiler)
    summary["reference_sha256"] = {
        str(path): digest(path) for path in [args.kotlinc, args.java, *args.classpath]
        if path.is_file()
    }
    write_json(output / "summary.json", summary)

    if not errors:
        staged_cases = output / "inputs"
        staged_cases.mkdir(exist_ok=True)
        for case in cases:
            shutil.copy2(case, staged_cases / case.name)

        for optimization in (args.optimization,):
            report_path = output / f"diff-{optimization}.tsv"
            artifact_root = output / f"artifacts-{optimization}"
            command = [
                "bash", str(ROOT / "Scripts/diff_kotlinc.sh"),
                "--kswiftc", str(args.compiler.resolve()),
                "--kotlinc", str(args.kotlinc.resolve()),
                "--java", str(args.java.resolve()),
                "--kotlinc-classpath", os.pathsep.join(str(path.resolve()) for path in args.classpath),
                "--no-parallel", "--force-run-skipped",
                "--compile-timeout", str(args.compile_timeout),
                "--run-timeout", str(args.run_timeout),
                "--report", str(report_path),
                "--artifact-root", str(artifact_root),
                str(staged_cases),
            ]
            environment = os.environ.copy()
            environment["DIFF_KSWIFTC_FLAGS"] = f"-{optimization}"
            environment["DIFF_REQUIRE_JDK21"] = "1"
            environment["KOTLINC_REF_CACHE_DIR"] = str(output / "reference-cache")
            exit_code, stdout, stderr, timed_out = run_bounded(command, ROOT, environment, args.total_timeout)
            (output / f"diff-{optimization}.stdout").write_text(stdout, encoding="utf-8")
            (output / f"diff-{optimization}.stderr").write_text(stderr, encoding="utf-8")
            counts, by_case = parse_report(report_path)
            missing = sorted(set(path.name for path in cases) - set(by_case))
            unexpected = sorted(set(by_case) - set(path.name for path in cases))
            lane_errors = validate_execution_counts(counts, len(cases), f"diff {optimization}")
            lane_errors += [f"diff {optimization}: missing case {name}" for name in missing]
            lane_errors += [f"diff {optimization}: unexpected case {name}" for name in unexpected]
            lane_errors += [f"diff {optimization}: case {name}={status}"
                            for name, status in sorted(by_case.items()) if status != "PASS"]
            if timed_out:
                lane_errors.append(f"diff {optimization}: TIMEOUT after {args.total_timeout} seconds")
                counts["NOT_RUN"] = len(missing)
            if exit_code != 0:
                lane_errors.append(f"diff {optimization}: diff_kotlinc.sh exited {exit_code}")
            summary["optimizations"][optimization] = {
                "status": "PASS" if not lane_errors else "FAIL",
                "command": command,
                "exit_code": exit_code,
                "timed_out": timed_out,
                "counts": counts,
                "case_statuses": by_case,
                "missing_cases": missing,
                "unexpected_cases": unexpected,
                "errors": lane_errors,
            }
            errors.extend(lane_errors)
            write_json(output / "summary.json", summary)

    summary["status"] = "PASS" if not errors else "FAIL"
    summary["errors"] = errors
    write_json(output / "summary.json", summary)
    print(json.dumps({"status": summary["status"], "expected_case_count": len(cases),
                      "optimizations": {key: value.get("counts", {}) for key, value in summary["optimizations"].items()},
                      "errors": errors}, ensure_ascii=False))
    return 0 if summary["status"] == "PASS" else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--kotlinc", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True)
    parser.add_argument("--classpath", type=Path, action="append", default=[])
    parser.add_argument("--optimization", choices=["O0", "O2"], required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compile-timeout", type=int, default=600)
    parser.add_argument("--run-timeout", type=int, default=60)
    parser.add_argument("--total-timeout", type=int, default=14400)
    args = parser.parse_args(argv)
    if min(args.compile_timeout, args.run_timeout, args.total_timeout) <= 0:
        parser.error("timeouts must be positive")
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
