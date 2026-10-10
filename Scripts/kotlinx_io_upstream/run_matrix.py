#!/usr/bin/env python3
"""Run paired kotlinx-io upstream cases and persist strict comparison artifacts.

Each side command must emit one JSON observation on stdout.  The observation
keeps values that stdout-only comparison loses (exception type, byte counts,
buffer state, callbacks, and resource lifecycle) in the same comparison.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


RUNNER_VERSION = 1
OBSERVATION_KEYS = (
    "stdout",
    "exception_type",
    "bytes_consumed",
    "buffer_state",
    "byte_buffer_state",
    "callbacks",
    "resource_lifecycle",
)
PLATFORM_PATTERN = re.compile(r"^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$")
DISPOSITIONS = {"run", "skip", "unsupported", "unmapped"}
FAILURES = {"DIFFERENCE", "CRASH", "HANG", "XPASS", "ERROR"}
NON_PASS = {
    "DIFFERENCE", "CRASH", "HANG", "SKIP", "UNSUPPORTED", "XFAIL",
    "XPASS", "UNMAPPED", "ERROR",
}


class MatrixError(Exception):
    pass


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def git_value(root: Path, *args: str) -> str | None:
    try:
        completed = subprocess.run(
            ["git", "-C", str(root), *args],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        return completed.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise MatrixError(f"cannot read manifest {path}: {exc}") from exc
    if not isinstance(manifest, dict) or manifest.get("schema_version") != 1:
        raise MatrixError("manifest must be an object with schema_version=1")
    baseline = manifest.get("baseline")
    if not isinstance(baseline, dict) or not baseline.get("kotlin") or not baseline.get("kotlinx_io"):
        raise MatrixError("manifest baseline must pin kotlin and kotlinx_io versions")
    cases = manifest.get("cases")
    if not isinstance(cases, list) or not cases:
        raise MatrixError("manifest cases must be a non-empty array")
    seen: set[str] = set()
    for index, case in enumerate(cases):
        prefix = f"cases[{index}]"
        if not isinstance(case, dict):
            raise MatrixError(f"{prefix} must be an object")
        case_id = case.get("id")
        if not isinstance(case_id, str) or not case_id.strip():
            raise MatrixError(f"{prefix}.id must be a non-empty string")
        if case_id in seen:
            raise MatrixError(f"duplicate case id: {case_id}")
        seen.add(case_id)
        if not isinstance(case.get("platform"), str) or not PLATFORM_PATTERN.fullmatch(case["platform"]):
            raise MatrixError(f"{prefix}.platform must be a lowercase source-set label")
        disposition = case.get("disposition", "run")
        if not isinstance(disposition, str) or disposition not in DISPOSITIONS:
            raise MatrixError(f"{prefix}.disposition must be one of {sorted(DISPOSITIONS)}")
        timeout = case.get("timeout_seconds", 30)
        if not isinstance(timeout, (int, float)) or isinstance(timeout, bool) or timeout <= 0:
            raise MatrixError(f"{prefix}.timeout_seconds must be a positive number")
        if disposition == "run":
            for side in ("reference", "candidate"):
                side_config = case.get(side)
                if not isinstance(side_config, dict):
                    raise MatrixError(f"{prefix}.{side} must be an object")
                command = side_config.get("command")
                if not isinstance(command, list) or not command or not all(
                    isinstance(arg, str) for arg in command
                ):
                    raise MatrixError(f"{prefix}.{side}.command must be a non-empty string array")
        elif not isinstance(case.get("reason"), str) or not case["reason"].strip():
            raise MatrixError(f"{prefix}.reason is required for {disposition}")
        expected = case.get("expected_failure")
        if expected is not None and (
            not isinstance(expected, str) or expected not in {"DIFFERENCE", "CRASH", "HANG"}
        ):
            raise MatrixError(f"{prefix}.expected_failure must be DIFFERENCE, CRASH, or HANG")
    return manifest


def expand_command(command: list[str], replacements: dict[str, str]) -> list[str]:
    expanded: list[str] = []
    for arg in command:
        value = arg
        for name, replacement in replacements.items():
            value = value.replace("{" + name + "}", replacement)
        if re.search(r"\{[a-zA-Z_][a-zA-Z0-9_]*\}", value):
            raise MatrixError(f"unknown command placeholder in {arg!r}")
        expanded.append(value)
    return expanded


def normalize_output(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def run_side(
    side_config: dict[str, Any],
    *,
    case: dict[str, Any],
    side: str,
    root: Path,
    case_artifacts: Path,
    timeout_seconds: float,
) -> dict[str, Any]:
    side_artifacts = case_artifacts / side
    side_artifacts.mkdir(parents=True, exist_ok=True)
    replacements = {
        "repo": str(root),
        "source": str(root / case.get("source_path", "")),
        "case_id": case["id"],
        "upstream_id": str(case.get("upstream_id", case["id"])),
        "platform": case["platform"],
        "side": side,
        "artifact_dir": str(side_artifacts),
    }
    try:
        command = expand_command(side_config["command"], replacements)
    except MatrixError as exc:
        return {"status": "ERROR", "error": str(exc), "command": side_config["command"]}
    environment = os.environ.copy()
    extra_environment = side_config.get("env", {})
    if not isinstance(extra_environment, dict) or any(
        not isinstance(key, str) or not isinstance(value, str)
        for key, value in extra_environment.items()
    ):
        return {"status": "ERROR", "error": f"{side}.env must map strings to strings", "command": command}
    environment.update(extra_environment)
    environment.update(
        {
            "KIO_CASE_ID": case["id"],
            "KIO_UPSTREAM_ID": replacements["upstream_id"],
            "KIO_PLATFORM": case["platform"],
            "KIO_SIDE": side,
            "KIO_REPO_ROOT": str(root),
            "KIO_ARTIFACT_DIR": str(side_artifacts),
        }
    )
    started = time.monotonic()
    try:
        completed = subprocess.run(
            command,
            cwd=root,
            env=environment,
            capture_output=True,
            text=False,
            timeout=timeout_seconds,
            check=False,
        )
        elapsed = round(time.monotonic() - started, 6)
        stdout = normalize_output(completed.stdout)
        stderr = normalize_output(completed.stderr)
        (side_artifacts / "stdout.txt").write_text(stdout, encoding="utf-8")
        (side_artifacts / "stderr.txt").write_text(stderr, encoding="utf-8")
        if completed.returncode != 0:
            return {
                "status": "CRASH",
                "command": command,
                "exit_code": completed.returncode,
                "elapsed_seconds": elapsed,
                "stdout_path": "stdout.txt",
                "stderr_path": "stderr.txt",
            }
        try:
            observation = json.loads(stdout)
        except json.JSONDecodeError as exc:
            return {
                "status": "ERROR",
                "command": command,
                "exit_code": 0,
                "elapsed_seconds": elapsed,
                "error": f"stdout is not one JSON observation: {exc}",
                "stdout_path": "stdout.txt",
                "stderr_path": "stderr.txt",
            }
        if not isinstance(observation, dict):
            return {
                "status": "ERROR",
                "command": command,
                "exit_code": 0,
                "elapsed_seconds": elapsed,
                "error": "observation must be a JSON object",
            }
        missing = [key for key in OBSERVATION_KEYS if key not in observation]
        if missing:
            return {
                "status": "ERROR",
                "command": command,
                "exit_code": 0,
                "elapsed_seconds": elapsed,
                "error": "observation missing required keys: " + ", ".join(missing),
            }
        if not isinstance(observation["stdout"], str):
            return {
                "status": "ERROR",
                "command": command,
                "exit_code": 0,
                "elapsed_seconds": elapsed,
                "error": "observation.stdout must be a string",
            }
        if observation["exception_type"] is not None and not isinstance(observation["exception_type"], str):
            return {
                "status": "ERROR",
                "command": command,
                "exit_code": 0,
                "elapsed_seconds": elapsed,
                "error": "observation.exception_type must be a string or null",
            }
        if observation["bytes_consumed"] is not None and (
            not isinstance(observation["bytes_consumed"], int)
            or isinstance(observation["bytes_consumed"], bool)
            or observation["bytes_consumed"] < 0
        ):
            return {
                "status": "ERROR",
                "command": command,
                "exit_code": 0,
                "elapsed_seconds": elapsed,
                "error": "observation.bytes_consumed must be a non-negative integer or null",
            }
        return {
            "status": "OK",
            "command": command,
            "exit_code": 0,
            "elapsed_seconds": elapsed,
            "observation": observation,
            "stdout_path": "stdout.txt",
            "stderr_path": "stderr.txt",
        }
    except subprocess.TimeoutExpired as exc:
        elapsed = round(time.monotonic() - started, 6)
        stdout = normalize_output(exc.stdout)
        stderr = normalize_output(exc.stderr)
        (side_artifacts / "stdout.txt").write_text(stdout, encoding="utf-8")
        (side_artifacts / "stderr.txt").write_text(stderr, encoding="utf-8")
        return {
            "status": "HANG",
            "command": command,
            "elapsed_seconds": elapsed,
            "timeout_seconds": timeout_seconds,
            "stdout_path": "stdout.txt",
            "stderr_path": "stderr.txt",
        }
    except OSError as exc:
        return {"status": "ERROR", "command": command, "error": f"could not start command: {exc}"}


def classify(case: dict[str, Any], side_results: dict[str, dict[str, Any]]) -> str:
    disposition = case.get("disposition", "run")
    if disposition == "skip":
        return "SKIP"
    if disposition == "unsupported":
        return "UNSUPPORTED"
    if disposition == "unmapped":
        return "UNMAPPED"
    failures = [side_results[side]["status"] for side in ("reference", "candidate")]
    if "ERROR" in failures:
        actual = "ERROR"
    elif "HANG" in failures:
        actual = "HANG"
    elif "CRASH" in failures:
        actual = "CRASH"
    else:
        reference = side_results["reference"]["observation"]
        candidate = side_results["candidate"]["observation"]
        actual = "PASS" if reference == candidate else "DIFFERENCE"
    expected_failure = case.get("expected_failure")
    if expected_failure:
        return "XFAIL" if actual == expected_failure else "XPASS" if actual == "PASS" else actual
    return actual


def make_run_dir(artifact_root: Path, run_id: str | None, sha: str | None) -> Path:
    if run_id is None:
        stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        run_id = f"{stamp}-{(sha or 'unknown')[:8]}"
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,100}", run_id):
        raise MatrixError("run id may contain only ASCII letters, digits, dot, underscore, and dash")
    path = artifact_root / run_id
    if path.exists():
        raise MatrixError(f"artifact run directory already exists: {path}")
    path.mkdir(parents=True, exist_ok=False)
    return path


def artifact_case_name(case_id: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_.-]{1,100}", case_id) and case_id not in {".", ".."}:
        return case_id
    slug = re.sub(r"[^A-Za-z0-9_.-]+", "_", case_id).strip("._-")[:60] or "case"
    digest = hashlib.sha256(case_id.encode("utf-8")).hexdigest()[:10]
    return f"{slug}-{digest}"


def run_matrix(manifest: dict[str, Any], *, manifest_path: Path, root: Path, artifact_root: Path, run_id: str | None) -> tuple[dict[str, Any], int]:
    sha = git_value(root, "rev-parse", "HEAD")
    run_dir = make_run_dir(artifact_root, run_id, sha)
    started = utc_now()
    entries: list[dict[str, Any]] = []
    for case in manifest["cases"]:
        case_dir = run_dir / "cases" / artifact_case_name(case["id"])
        case_dir.mkdir(parents=True, exist_ok=True)
        disposition = case.get("disposition", "run")
        side_results: dict[str, dict[str, Any]] = {}
        if disposition == "run":
            timeout_seconds = float(case.get("timeout_seconds", 30))
            side_results = {
                side: run_side(
                    case[side],
                    case=case,
                    side=side,
                    root=root,
                    case_artifacts=case_dir,
                    timeout_seconds=timeout_seconds,
                )
                for side in ("reference", "candidate")
            }
        status = classify(case, side_results)
        entry = {
            "id": case["id"],
            "upstream_id": case.get("upstream_id"),
            "upstream_path": case.get("upstream_path"),
            "test_kind": case.get("test_kind"),
            "platform": case["platform"],
            "mapping": case.get("mapping"),
            "upstream_metadata": case.get("upstream_metadata"),
            "status": status,
            "reason": case.get("reason"),
            "expected_failure": case.get("expected_failure"),
            "sides": side_results,
            "artifact_dir": str(case_dir.relative_to(run_dir)),
        }
        entries.append(entry)
        (case_dir / "result.json").write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    counts = {status: 0 for status in ("PASS", "DIFFERENCE", "CRASH", "HANG", "SKIP", "UNSUPPORTED", "XFAIL", "XPASS", "UNMAPPED", "ERROR")}
    for entry in entries:
        counts[entry["status"]] += 1
    total = len(entries)
    passed = counts["PASS"]
    incomplete = sum(counts[key] for key in NON_PASS if key not in FAILURES)
    failed = sum(counts[key] for key in FAILURES)
    summary = {
        "schema_version": 1,
        "runner_version": RUNNER_VERSION,
        "run_id": run_dir.name,
        "started_at": started,
        "finished_at": utc_now(),
        "manifest": str(manifest_path.resolve()),
        "baseline": manifest["baseline"],
        "catalog": manifest.get("catalog"),
        "reference_artifacts": manifest.get("reference_artifacts", []),
        "inventory_only_sources": manifest.get("inventory_only_sources", []),
        "environment": {
            "platform": platform.platform(),
            "python": platform.python_version(),
            "repository_sha": sha,
            "repository_dirty": bool(git_value(root, "status", "--porcelain=v1")),
        },
        "counts": {"total": total, "passed": passed, "incomplete": incomplete, "failed": failed, **{key.lower(): value for key, value in counts.items()}},
        "complete": passed == total,
        "cases": entries,
    }
    (run_dir / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    markdown = [
        "# kotlinx-io upstream matrix",
        "",
        f"- Run: `{run_dir.name}`",
        f"- Commit: `{sha or 'unknown'}`",
        f"- Baseline: Kotlin `{manifest['baseline']['kotlin']}`, kotlinx-io `{manifest['baseline']['kotlinx_io']}`",
        f"- Cases: {total}; passed: {passed}; incomplete: {incomplete}; failed: {failed}",
        "",
        "| Case | Platform | Result | Mapping |",
        "|---|---|---|---|",
    ]
    for entry in entries:
        mapping = entry.get("mapping")
        mapping_status = mapping.get("status", "") if isinstance(mapping, dict) else mapping or ""
        markdown.append(f"| `{entry['id']}` | {entry['platform']} | **{entry['status']}** | {mapping_status} |")
    (run_dir / "summary.md").write_text("\n".join(markdown) + "\n", encoding="utf-8")
    if failed:
        return summary, 1
    if incomplete:
        return summary, 2
    return summary, 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True, help="JSON case matrix")
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--artifact-root", type=Path, default=None)
    parser.add_argument("--run-id", help="optional unique artifact directory name")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    root = args.repo_root.resolve()
    artifact_root = (args.artifact_root or root / ".artifacts/kotlinx_io_upstream").resolve()
    try:
        manifest = load_manifest(args.manifest)
        summary, code = run_matrix(
            manifest,
            manifest_path=args.manifest,
            root=root,
            artifact_root=artifact_root,
            run_id=args.run_id,
        )
    except MatrixError as exc:
        print(f"kotlinx-io matrix: {exc}", file=sys.stderr)
        return 64
    print(json.dumps({"run_id": summary["run_id"], "counts": summary["counts"], "complete": summary["complete"], "artifact_dir": str(artifact_root / summary["run_id"])}, ensure_ascii=False))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
