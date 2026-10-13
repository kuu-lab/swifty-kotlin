#!/usr/bin/env python3
"""Run js_annotations native-compat fixtures without a JVM reference."""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import signal
import subprocess
import sys
import time
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = ROOT / "docs/fixtures/js_annotations"
DEFAULT_EXPECTATIONS = FIXTURE_ROOT / "expectations.json"
DEFAULT_DIAGNOSTIC_MAP = Path(__file__).resolve().parent / "diagnostic_map.json"
LANE = "native-compat"
DIAGNOSTIC_SEVERITIES = {1: "error", 2: "warning", 3: "note", 4: "info"}


def positive_seconds(value: str) -> float:
    try:
        seconds = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("seconds must be a positive number") from error
    if seconds <= 0:
        raise argparse.ArgumentTypeError("seconds must be a positive number")
    return seconds


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def run_process(
    command: list[str], *, timeout: float, cwd: Path, env: dict[str, str] | None = None
) -> dict[str, Any]:
    started = time.monotonic()
    try:
        process = subprocess.Popen(
            command,
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
    except OSError as error:
        return {
            "exitCode": None,
            "timedOut": False,
            "stdout": b"",
            "stderr": b"",
            "durationSeconds": round(time.monotonic() - started, 3),
            "spawnError": str(error),
        }

    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            stdout, stderr = process.communicate(timeout=1.0)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            stdout, stderr = process.communicate()

    return {
        "exitCode": None if timed_out else process.returncode,
        "timedOut": timed_out,
        "stdout": stdout,
        "stderr": stderr,
        "durationSeconds": round(time.monotonic() - started, 3),
    }


def candidate_compiler_environment(module_cache_root: Path) -> dict[str, str]:
    """Keep SwiftPM/Clang module caches inside this invocation's artifact tree."""
    env = os.environ.copy()
    cache_paths = {
        "SWIFTPM_MODULECACHE_OVERRIDE": module_cache_root / "swiftpm",
        "CLANG_MODULE_CACHE_PATH": module_cache_root / "clang",
        "SWIFT_MODULE_CACHE_PATH": module_cache_root / "swift",
    }
    for name, path in cache_paths.items():
        path.mkdir(parents=True, exist_ok=True)
        env[name] = str(path)
    return env


def diagnostic_json(stderr: bytes) -> list[dict[str, Any]]:
    """Read the LSP-compatible JSON diagnostic object from compiler stderr."""
    if not stderr.strip():
        return []
    text = stderr.decode("utf-8", errors="strict")
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        payload = None
        # Preserve raw stderr as evidence while allowing progress text around JSON.
        for start, char in enumerate(text):
            if char != "{":
                continue
            depth = 0
            quoted = False
            escaped = False
            for end in range(start, len(text)):
                current = text[end]
                if quoted:
                    if escaped:
                        escaped = False
                    elif current == "\\":
                        escaped = True
                    elif current == '"':
                        quoted = False
                    continue
                if current == '"':
                    quoted = True
                elif current == "{":
                    depth += 1
                elif current == "}":
                    depth -= 1
                    if depth == 0:
                        try:
                            candidate = json.loads(text[start : end + 1])
                        except json.JSONDecodeError:
                            break
                        if isinstance(candidate, dict) and "diagnostics" in candidate:
                            payload = candidate
                        break
            if payload is not None:
                break
    if not isinstance(payload, dict) or not isinstance(payload.get("diagnostics"), list):
        raise ValueError("compiler stderr did not contain a diagnostics JSON object")
    return payload["diagnostics"]


def canonical_diagnostics(
    diagnostics: list[dict[str, Any]], code_to_kind: dict[str, str]
) -> tuple[list[dict[str, Any]], list[str]]:
    result: list[dict[str, Any]] = []
    unknown_codes: list[str] = []
    for diagnostic in diagnostics:
        if not isinstance(diagnostic, dict):
            raise ValueError("diagnostics JSON contains a non-object entry")
        code = diagnostic.get("code")
        severity = diagnostic.get("severityLabel")
        if not isinstance(severity, str):
            severity = DIAGNOSTIC_SEVERITIES.get(diagnostic.get("severity"))
        if not isinstance(code, str) or not isinstance(severity, str):
            raise ValueError("diagnostic is missing a code or severity")
        severity = severity.lower()
        kind = code_to_kind.get(code)
        if kind is None:
            unknown_codes.append(code)
        result.append({"severity": severity, "kind": kind, "code": code})
    return result, sorted(set(unknown_codes))


def diagnostic_counts(items: list[dict[str, Any]]) -> Counter[tuple[str, str]]:
    return Counter((item["severity"], item["kind"]) for item in items)


def safe_case_name(case_id: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", case_id).strip("._") or "case"


def make_case_record(case_id: str, lane: str = LANE) -> dict[str, Any]:
    return {
        "id": case_id,
        "lane": lane,
        "status": "fail",
        "failureReason": None,
        "failureReasons": [],
    }


def add_failure(record: dict[str, Any], reason: str) -> None:
    if reason not in record["failureReasons"]:
        record["failureReasons"].append(reason)
    record["failureReason"] = record["failureReasons"][0]


def relative_fixture_path(fixture_root: Path, source: Any) -> Path | None:
    if not isinstance(source, str) or not source:
        return None
    candidate = (fixture_root / source).resolve()
    root = fixture_root.resolve()
    if candidate != root and root not in candidate.parents:
        return None
    return candidate


def expected_diagnostic_counts(expected: Any) -> Counter[tuple[str, str]]:
    if not isinstance(expected, list):
        raise ValueError("compile diagnostics expectation must be a list")
    counts: Counter[tuple[str, str]] = Counter()
    for item in expected:
        if not isinstance(item, dict):
            raise ValueError("compile diagnostics expectation has a non-object entry")
        severity = item.get("severity")
        kind = item.get("kind")
        if not isinstance(severity, str) or not isinstance(kind, str):
            raise ValueError("expected diagnostic needs severity and kind")
        counts[(severity.lower(), kind)] += 1
    return counts


def compare_compile_diagnostics(
    stderr: bytes,
    expected: Any,
    code_to_kind: dict[str, str],
    record: dict[str, Any],
) -> None:
    if expected is None:
        add_failure(record, "missing_expected_diagnostics")
        return
    try:
        raw_diagnostics = diagnostic_json(stderr)
        actual, unknown_codes = canonical_diagnostics(raw_diagnostics, code_to_kind)
    except (UnicodeDecodeError, ValueError) as error:
        add_failure(record, "diagnostics_unparseable")
        record["diagnosticsParseError"] = str(error)
        return

    record["actualDiagnostics"] = actual
    for code in unknown_codes:
        add_failure(record, f"unknown_diagnostic_code:{code}")

    try:
        expected_counts = expected_diagnostic_counts(expected)
    except ValueError as error:
        add_failure(record, "invalid_expected_diagnostics")
        record["expectationsError"] = str(error)
        return

    known_kinds = set(code_to_kind.values())
    for kind in sorted({kind for _, kind in expected_counts if kind not in known_kinds}):
        add_failure(record, f"unmapped_expected_diagnostic_kind:{kind}")

    actual_counts = diagnostic_counts(actual)
    if actual_counts != expected_counts:
        add_failure(record, "compile_diagnostics_mismatch")
        record["expectedDiagnosticCounts"] = [
            {"severity": severity, "kind": kind, "count": count}
            for (severity, kind), count in sorted(expected_counts.items())
        ]
        record["actualDiagnosticCounts"] = [
            {"severity": severity, "kind": kind, "count": count}
            for (severity, kind), count in sorted(actual_counts.items())
        ]


def load_contract_files(
    expectations_path: Path, diagnostic_map_path: Path
) -> tuple[dict[str, Any], dict[str, str]]:
    document = json.loads(expectations_path.read_text(encoding="utf-8"))
    if not isinstance(document, dict) or document.get("schemaVersion") != 1:
        raise ValueError("expectations.json must use schemaVersion 1")
    if not isinstance(document.get("cases"), list):
        raise ValueError("expectations.json is missing its cases list")
    mapping_document = json.loads(diagnostic_map_path.read_text(encoding="utf-8"))
    if not isinstance(mapping_document, dict) or mapping_document.get("schemaVersion") != 1:
        raise ValueError("diagnostic map must use schemaVersion 1")
    code_to_kind = mapping_document.get("codes")
    if not isinstance(code_to_kind, dict) or any(
        not isinstance(code, str)
        or not code.startswith("KSWIFTK-")
        or not isinstance(kind, str)
        for code, kind in code_to_kind.items()
    ):
        raise ValueError("diagnostic map codes must map KSWIFTK diagnostic codes to names")
    return document, code_to_kind


def select_cases(
    cases: list[dict[str, Any]], requested_ids: list[str] | None
) -> tuple[list[dict[str, Any]], list[dict[str, str]], list[dict[str, Any]]]:
    by_id: dict[str, dict[str, Any]] = {}
    duplicate_ids: set[str] = set()
    invalid: list[dict[str, Any]] = []
    for index, case in enumerate(cases):
        if not isinstance(case, dict) or not isinstance(case.get("id"), str):
            record = make_case_record(f"<case-{index}>", lane="unknown")
            add_failure(record, "invalid_case_entry")
            invalid.append(record)
            continue
        case_id = case["id"]
        if case_id in by_id:
            duplicate_ids.add(case_id)
        by_id[case_id] = case

    selected: list[dict[str, Any]] = []
    exclusions: list[dict[str, str]] = []

    if requested_ids:
        for case_id in dict.fromkeys(requested_ids):
            if case_id in duplicate_ids:
                record = make_case_record(case_id)
                add_failure(record, "duplicate_case_id")
                invalid.append(record)
                continue
            case = by_id.get(case_id)
            if case is None:
                record = make_case_record(case_id)
                add_failure(record, "unknown_case_id")
                invalid.append(record)
                continue
            lanes = case.get("lanes")
            if not isinstance(lanes, list) or LANE not in lanes:
                record = make_case_record(case_id, lane="unknown")
                add_failure(record, "case_has_no_native_compat_lane")
                invalid.append(record)
                continue
            if not isinstance(case.get("nativeContract"), dict):
                record = make_case_record(case_id)
                add_failure(record, "missing_native_contract")
                invalid.append(record)
                continue
            selected.append(case)
    else:
        for index, case in enumerate(cases):
            if not isinstance(case, dict) or not isinstance(case.get("id"), str):
                continue
            lanes = case.get("lanes")
            if not isinstance(lanes, list):
                record = make_case_record(case["id"], lane="unknown")
                add_failure(record, "missing_case_lanes")
                invalid.append(record)
            elif LANE in lanes and not isinstance(case.get("nativeContract"), dict):
                record = make_case_record(case["id"])
                add_failure(record, "missing_native_contract")
                invalid.append(record)
            elif LANE in lanes:
                selected.append(case)
            else:
                exclusions.append({"id": case["id"], "reason": "outside-native-compat-lane"})
        for case_id in sorted(duplicate_ids):
            record = make_case_record(case_id)
            add_failure(record, "duplicate_case_id")
            invalid.append(record)
            selected = [case for case in selected if case.get("id") != case_id]

    return selected, exclusions, invalid


def record_command_result(
    case_dir: Path, phase: str, result: dict[str, Any], command: list[str]
) -> None:
    case_dir.mkdir(parents=True, exist_ok=True)
    (case_dir / f"{phase}.stdout").write_bytes(result.get("stdout", b""))
    (case_dir / f"{phase}.stderr").write_bytes(result.get("stderr", b""))
    metadata = {
        "command": command,
        "exitCode": result.get("exitCode"),
        "timedOut": result.get("timedOut", False),
        "durationSeconds": result.get("durationSeconds"),
    }
    if "spawnError" in result:
        metadata["spawnError"] = result["spawnError"]
    write_json(case_dir / f"{phase}.json", metadata)


def run_case(
    case: dict[str, Any],
    *,
    case_dir: Path,
    fixture_root: Path,
    compiler: Path,
    stdlib_library: Path,
    compiler_env: dict[str, str],
    code_to_kind: dict[str, str],
    compile_timeout: float,
    run_timeout: float,
) -> dict[str, Any]:
    record = make_case_record(case["id"])
    case_dir.mkdir(parents=True, exist_ok=True)
    contract = case.get("nativeContract")
    source = relative_fixture_path(fixture_root, case.get("source"))

    if source is None:
        add_failure(record, "invalid_fixture_source_path")
    elif not source.is_file():
        add_failure(record, "fixture_source_missing")
    else:
        actual_hash = sha256_file(source)
        expected_hash = case.get("sourceSha256")
        record["source"] = str(source)
        record["sourceSha256"] = actual_hash
        record["expectedSourceSha256"] = expected_hash
        if not isinstance(expected_hash, str):
            add_failure(record, "missing_expected_source_hash")
        elif actual_hash != expected_hash:
            add_failure(record, "fixture_source_hash_mismatch")
        (case_dir / "source.kt").write_bytes(source.read_bytes())

    compile_contract = contract.get("compile") if isinstance(contract, dict) else None
    if not isinstance(compile_contract, dict):
        add_failure(record, "missing_compile_expectation")
    elif not isinstance(compile_contract.get("exitCode"), int):
        add_failure(record, "missing_expected_compile_exit_code")
    elif "diagnostics" not in compile_contract:
        add_failure(record, "missing_expected_diagnostics")

    if record["failureReasons"] or source is None or not source.is_file():
        write_json(case_dir / "result.json", record)
        return record

    output_binary = case_dir / "candidate.out"
    command = [
        str(compiler),
        "--no-stdlib",
        "--stdlib-library",
        str(stdlib_library),
        "-Xdiagnostics",
        "json",
        str(source),
        "-o",
        str(output_binary),
    ]
    compile_result = run_process(command, timeout=compile_timeout, cwd=ROOT, env=compiler_env)
    record_command_result(case_dir, "compile", compile_result, command)

    if "spawnError" in compile_result:
        add_failure(record, "compile_spawn_failed")
        record["processError"] = compile_result["spawnError"]
    elif compile_result["timedOut"]:
        add_failure(record, "compile_timeout")
    else:
        actual_compile_exit = compile_result["exitCode"]
        expected_compile_exit = compile_contract["exitCode"]
        record["actualCompileExitCode"] = actual_compile_exit
        record["expectedCompileExitCode"] = expected_compile_exit
        if actual_compile_exit != expected_compile_exit:
            add_failure(record, "compile_exit_mismatch")
        compare_compile_diagnostics(
            compile_result["stderr"],
            compile_contract.get("diagnostics"),
            code_to_kind,
            record,
        )

        if actual_compile_exit == 0 and expected_compile_exit == 0:
            run_contract = contract.get("run") if isinstance(contract, dict) else None
            if run_contract is None:
                reference = case.get("reference")
                if isinstance(reference, dict) and isinstance(reference.get("run"), dict):
                    add_failure(record, "missing_expected_run")
                    record["run"] = {"status": "missing_expectation"}
                else:
                    record["run"] = {"status": "not_applicable", "reason": "compile-only-contract"}
            elif (
                not isinstance(run_contract, dict)
                or not isinstance(run_contract.get("exitCode"), int)
                or not isinstance(run_contract.get("stdout"), str)
                or not isinstance(run_contract.get("stderr"), str)
            ):
                add_failure(record, "missing_expected_run_field")
            elif not output_binary.is_file():
                add_failure(record, "compiled_executable_missing")
            else:
                run_command = [str(output_binary)]
                run_result = run_process(
                    run_command, timeout=run_timeout, cwd=ROOT, env=os.environ.copy()
                )
                record_command_result(case_dir, "run", run_result, run_command)
                if "spawnError" in run_result:
                    add_failure(record, "run_spawn_failed")
                    record["processError"] = run_result["spawnError"]
                elif run_result["timedOut"]:
                    add_failure(record, "run_timeout")
                else:
                    record["actualRunExitCode"] = run_result["exitCode"]
                    record["expectedRunExitCode"] = run_contract["exitCode"]
                    record["actualRunStdoutSha256"] = sha256_bytes(run_result["stdout"])
                    record["expectedRunStdoutSha256"] = sha256_bytes(
                        run_contract["stdout"].encode("utf-8")
                    )
                    if run_result["exitCode"] != run_contract["exitCode"]:
                        add_failure(record, "run_exit_code_mismatch")
                    if run_result["stdout"] != run_contract["stdout"].encode("utf-8"):
                        add_failure(record, "run_stdout_mismatch")
                    if run_result["stderr"] != run_contract["stderr"].encode("utf-8"):
                        add_failure(record, "run_stderr_mismatch")
                    record["run"] = {"status": "compared"}
        elif expected_compile_exit != 0 and actual_compile_exit == expected_compile_exit:
            if contract.get("run") is not None:
                add_failure(record, "compile_failure_contract_must_not_have_run")
            else:
                record["run"] = {"status": "not_applicable", "reason": "expected-compile-failure"}

    record["status"] = "fail" if record["failureReasons"] else "pass"
    write_json(case_dir / "result.json", record)
    return record


def snapshot_toolchain(compiler: Path) -> dict[str, Any]:
    swift = run_process(["swift", "--version"], timeout=5, cwd=ROOT)
    git_revision = run_process(["git", "rev-parse", "HEAD"], timeout=5, cwd=ROOT)
    return {
        "platform": platform.platform(),
        "python": sys.version.splitlines()[0],
        "kswiftc": str(compiler),
        "kswiftcSha256": sha256_file(compiler) if compiler.is_file() else None,
        "swiftVersionExitCode": swift.get("exitCode"),
        "swiftVersion": swift.get("stdout", b"").decode("utf-8", errors="replace").strip(),
        "swiftVersionStderr": swift.get("stderr", b"").decode("utf-8", errors="replace").strip(),
        "gitRevision": git_revision.get("stdout", b"").decode("utf-8", errors="replace").strip(),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kswiftc", type=Path, default=ROOT / ".build/debug/kswiftc")
    parser.add_argument("--expectations", type=Path, default=DEFAULT_EXPECTATIONS)
    parser.add_argument("--diagnostic-map", type=Path, default=DEFAULT_DIAGNOSTIC_MAP)
    parser.add_argument(
        "--artifact-root", type=Path, default=ROOT / ".artifacts/js_annotations_candidate_only"
    )
    parser.add_argument("--stdlib-library", type=Path)
    parser.add_argument("--case", dest="case_ids", action="append", help="case id; repeatable")
    parser.add_argument("--compile-timeout", type=positive_seconds, default=60.0)
    parser.add_argument("--run-timeout", type=positive_seconds, default=10.0)
    parser.add_argument("--stdlib-timeout", type=positive_seconds, default=600.0)
    args = parser.parse_args(argv)

    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    run_dir = args.artifact_root.resolve() / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    module_cache_root = run_dir / "module-cache"
    compiler_env = candidate_compiler_environment(module_cache_root)
    expectations_path = args.expectations.resolve()
    diagnostic_map_path = args.diagnostic_map.resolve()
    compiler = args.kswiftc
    if not compiler.is_absolute():
        compiler = (ROOT / compiler).resolve()

    summary: dict[str, Any] = {
        "schemaVersion": 1,
        "runner": "js_annotations_candidate_only",
        "runId": run_id,
        "startedAt": datetime.now(timezone.utc).isoformat(),
        "lane": LANE,
        "usedJvmReference": False,
        "expectationsPath": str(expectations_path),
        "diagnosticMapPath": str(diagnostic_map_path),
        "compileTimeoutSeconds": args.compile_timeout,
        "runTimeoutSeconds": args.run_timeout,
        "stdlibTimeoutSeconds": args.stdlib_timeout,
        "artifactDirectory": str(run_dir),
        "moduleCacheDirectory": str(module_cache_root),
        "cases": [],
        "excluded": [],
        "failureReasons": [],
    }
    summary["toolchain"] = snapshot_toolchain(compiler)

    fatal_reason: str | None = None
    selected: list[dict[str, Any]] = []
    try:
        document, code_to_kind = load_contract_files(expectations_path, diagnostic_map_path)
        summary["expectationsSha256"] = sha256_file(expectations_path)
        summary["diagnosticMapSha256"] = sha256_file(diagnostic_map_path)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        fatal_reason = "contract_input_invalid"
        summary["failureReasons"].append(fatal_reason)
        summary["error"] = str(error)
        document = {"cases": []}
        code_to_kind = {}

    if fatal_reason is None:
        selected, excluded, invalid = select_cases(document["cases"], args.case_ids)
        summary["excluded"] = excluded
        summary["cases"].extend(invalid)
        if not selected:
            fatal_reason = "no_native_compat_cases_selected"
            summary["failureReasons"].append(fatal_reason)
        if not compiler.is_file() or not os.access(compiler, os.X_OK):
            fatal_reason = "kswiftc_not_found_or_not_executable"
            summary["failureReasons"].append(fatal_reason)

    stdlib_library: Path | None = None
    if fatal_reason is None:
        if args.stdlib_library:
            stdlib_library = args.stdlib_library.resolve()
            if not stdlib_library.is_dir() or not (stdlib_library / "manifest.json").is_file():
                fatal_reason = "stdlib_library_missing_or_invalid"
                summary["failureReasons"].append(fatal_reason)
        else:
            stdlib_library = run_dir / "stdlib/KSwiftKStdlib.kklib"
            stdlib_library.parent.mkdir(parents=True, exist_ok=True)
            command = [
                str(compiler),
                "--stdlib-only",
                "--emit",
                "library",
                "-o",
                str(stdlib_library),
            ]
            result = run_process(
                command, timeout=args.stdlib_timeout, cwd=ROOT, env=compiler_env
            )
            record_command_result(run_dir / "stdlib", "build", result, command)
            if "spawnError" in result:
                fatal_reason = "stdlib_build_spawn_failed"
                summary["stdlibBuildError"] = result["spawnError"]
            elif result["timedOut"]:
                fatal_reason = "stdlib_build_timeout"
            elif result["exitCode"] != 0:
                fatal_reason = "stdlib_build_failed"
                summary["stdlibBuildExitCode"] = result["exitCode"]
            elif not stdlib_library.is_dir() or not (stdlib_library / "manifest.json").is_file():
                fatal_reason = "stdlib_build_artifact_missing"
            if fatal_reason:
                summary["failureReasons"].append(fatal_reason)
            else:
                summary["stdlibLibrary"] = str(stdlib_library)

    if fatal_reason is not None:
        for case in summary["cases"]:
            add_failure(case, fatal_reason)
            write_json(run_dir / "cases" / safe_case_name(case["id"]) / "result.json", case)
        for case in selected:
            record = make_case_record(case["id"])
            add_failure(record, fatal_reason)
            summary["cases"].append(record)
            write_json(run_dir / "cases" / safe_case_name(record["id"]) / "result.json", record)
    elif stdlib_library is not None:
        for case in selected:
            record = run_case(
                case,
                case_dir=run_dir / "cases" / safe_case_name(case["id"]),
                fixture_root=expectations_path.parent,
                compiler=compiler,
                stdlib_library=stdlib_library,
                compiler_env=compiler_env,
                code_to_kind=code_to_kind,
                compile_timeout=args.compile_timeout,
                run_timeout=args.run_timeout,
            )
            summary["cases"].append(record)

    if any(case.get("status") == "fail" for case in summary["cases"]) and not summary["failureReasons"]:
        summary["failureReasons"].append("case_failure")
    summary["finishedAt"] = datetime.now(timezone.utc).isoformat()
    case_failures = sum(case.get("status") == "fail" for case in summary["cases"])
    summary["status"] = "fail" if case_failures or fatal_reason else "pass"
    summary["counts"] = {
        "total": len(summary["cases"]),
        "passed": sum(case.get("status") == "pass" for case in summary["cases"]),
        "failed": case_failures + (1 if fatal_reason and not summary["cases"] else 0),
        "outOfLane": len(summary["excluded"]),
    }
    write_json(run_dir / "summary.json", summary)

    for case in summary["cases"]:
        reasons = ",".join(case.get("failureReasons", []))
        if case.get("status") == "pass":
            print(f"PASS {case['id']} lane={case.get('lane', LANE)}")
        else:
            print(f"FAIL {case['id']} lane={case.get('lane', LANE)} reason={reasons or fatal_reason}")
    counts = summary["counts"]
    if fatal_reason and not summary["cases"]:
        print(f"FAIL runner lane={LANE} reason={fatal_reason}")
    print(
        f"Summary: lane={LANE} total={counts['total']} "
        f"failed={counts['failed']} passed={counts['passed']} out-of-lane={counts['outOfLane']}"
    )
    print(f"Artifacts: {run_dir}")
    return 1 if counts["failed"] or fatal_reason else 0


if __name__ == "__main__":
    raise SystemExit(main())
