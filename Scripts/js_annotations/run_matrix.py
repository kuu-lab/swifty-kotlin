#!/usr/bin/env python3
"""Run audited js_annotations fixtures across source/artifact and O0/O2 modes."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import sys
import uuid
from typing import Any

import run_candidate as candidate


ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = ROOT / "docs/fixtures/js_annotations"
DEFAULT_EXPECTATIONS = FIXTURE_ROOT / "expectations.json"
DEFAULT_DIAGNOSTIC_MAP = Path(__file__).resolve().parent / "diagnostic_map.json"
DEFAULT_VIEW_EXPECTATIONS = FIXTURE_ROOT / "views-expectations.json"
DEFAULT_VIEW_DIAGNOSTIC_MAP = Path(__file__).resolve().parent / "views-diagnostic-map.json"
DEFAULT_CONTRACT_PAIRS = (
    (DEFAULT_EXPECTATIONS, DEFAULT_DIAGNOSTIC_MAP),
    (DEFAULT_VIEW_EXPECTATIONS, DEFAULT_VIEW_DIAGNOSTIC_MAP),
)
ARTIFACT_MODES = ("source-injection", "stdlib-kklib")
OPTIMIZATION_LEVELS = ("O0", "O2")

# These exact observations keep marker, generic type argument, constructor, and default
# argument metadata from being reduced to compile-only or same-output false positives.
REQUIRED_SENTINELS: dict[str, dict[str, Any]] = {
    "marker_no_opt_in": {
        "source": "diagnostics/marker_no_opt_in.kt",
        "compileExitCode": 0,
        "diagnostics": [{"severity": "warning", "kind": "OPT_IN_USAGE"}] * 3,
    },
    "no_opt_in": {
        "source": "diagnostics/no_opt_in.kt",
        "compileExitCode": 0,
        "diagnostics": [{"severity": "warning", "kind": "OPT_IN_USAGE"}] * 9,
    },
    "marker_requirements": {
        "source": "valid/marker_requirements.kt",
        "compileExitCode": 0,
        "stdout": "js-annotations\n7\n",
    },
    "native_observations": {
        "source": "valid/native_observations.kt",
        "compileExitCode": 0,
        "stdout": "js-annotations\n2:3:4\nExportedBox:createInstance:7\n",
    },
    "typed_views": {
        "source": "valid/typed_views.kt",
        "compileExitCode": 0,
        "stdout": (
            "map:3:null:0:2\n"
            "set:3:true:0:2\n"
            "array:7,2,3,4,5:0:1,2,3,4\n"
            "empty:0:0:0\n"
        ),
    },
    "reflection": {
        "source": "valid/reflection.kt",
        "compileExitCode": 0,
        "stdout": (
            "ExportedBox:7:0\n"
            "Empty\n"
            "default:41:1\n"
            "default:42:2\n"
            "required:Class should have a single no-arg constructor: class RequiredConstructor\n"
            "multiple:Class should have a single no-arg constructor: class MultipleEligibleConstructors\n"
        ),
    },
    "unbound_create_instance": {
        "source": "valid/unbound_create_instance.kt",
        "compileExitCode": 0,
        "stdout": "createInstance:7\n",
    },
    "views_map": {
        "source": "views/map.kt",
        "compileExitCode": 0,
        "stdout": (
            "minimum:2\nreplace:7:4:true\nordered:a,null,c:3\n"
            "copies:7:1:2:0\nclear:0:2\nreuse:1:true:null\n"
            "empty:0\ngrown:8:1\n"
        ),
    },
    "views_set": {
        "source": "views/set.kt",
        "compileExitCode": 0,
        "stdout": (
            "minimum:3\ninitial:x,null,y:true\nchanges:true:false:true:false\n"
            "ordered:x,null,z\ncopies:x,null,z:x,null,y:0\nclear:0:3\n"
            "reuse:again,null\nempty:0\ngrown:8,null\n"
        ),
    },
    "views_readonly_array": {
        "source": "views/readonly_array.kt",
        "compileExitCode": 0,
        "stdout": (
            "minimum:4:1,null,3,4\nchanged:7,null,4,5\n"
            "copies:7,null,4,5:1,null,3,4:0\nclear:0:4\n"
            "reuse:null,6\nempty:0\ngrown:later\nimmutable:4,3,2,1\n"
        ),
    },
    "typed_view_properties": {
        "source": "diagnostics/typed_view_properties.kt",
        "compileExitCode": 1,
        "diagnostics": [{"severity": "error", "kind": "UNRESOLVED_REFERENCE"}] * 4,
    },
    "views_typed_mutators": {
        "source": "views/typed_mutators.kt",
        "compileExitCode": 1,
        "diagnostics": [{"severity": "error", "kind": "UNRESOLVED_REFERENCE"}] * 4,
    },
    "views_variance": {
        "source": "views/variance.kt",
        "compileExitCode": 1,
        "diagnostics": [{"severity": "error", "kind": "TYPE_CONSTRAINT_FAILURE"}] * 4,
    },
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def source_tree_identity() -> dict[str, Any]:
    paths = [ROOT / "Package.swift", ROOT / "Package.resolved"]
    paths.extend(path for path in (ROOT / "Sources").rglob("*") if path.is_file())
    files = sorted((path for path in paths if path.is_file()), key=lambda path: path.relative_to(ROOT).as_posix())
    digest = hashlib.sha256()
    for path in files:
        relative = path.relative_to(ROOT).as_posix().encode("utf-8")
        contents = path.read_bytes()
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        digest.update(len(contents).to_bytes(8, "big"))
        digest.update(contents)
    return {"sha256": digest.hexdigest(), "fileCount": len(files)}


def git_text(*args: str) -> str | None:
    result = candidate.run_process(["git", *args], timeout=5, cwd=ROOT)
    if result.get("exitCode") != 0 or result.get("timedOut"):
        return None
    return result["stdout"].decode("utf-8", errors="replace").strip()


def snapshot_identity(compiler: Path) -> dict[str, Any]:
    swift = candidate.run_process(["swift", "--version"], timeout=10, cwd=ROOT)
    environment_names = (
        "KSWIFTK_LLVM_DYLIB",
        "LD_LIBRARY_PATH",
        "C_INCLUDE_PATH",
        "LIBRARY_PATH",
        "DEVELOPER_DIR",
        "SDKROOT",
    )
    return {
        "gitRevision": git_text("rev-parse", "HEAD"),
        "gitBranch": git_text("branch", "--show-current"),
        "compilerSourceTree": source_tree_identity(),
        "compiler": {
            "path": compiler.relative_to(ROOT).as_posix()
            if compiler.is_relative_to(ROOT)
            else str(compiler),
            "sha256": candidate.sha256_file(compiler) if compiler.is_file() else None,
        },
        "swiftVersionExitCode": swift.get("exitCode"),
        "swiftVersion": swift.get("stdout", b"").decode("utf-8", errors="replace").strip(),
        "swiftVersionStderr": swift.get("stderr", b"").decode("utf-8", errors="replace").strip(),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "environment": {name: os.environ[name] for name in environment_names if name in os.environ},
    }


def directory_digest(root: Path) -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        if path.is_symlink():
            content = os.readlink(path).encode("utf-8")
        elif path.is_file():
            content = path.read_bytes()
        else:
            continue
        relative = path.relative_to(root).as_posix()
        content_hash = sha256_bytes(content)
        entries.append({"path": relative, "size": len(content), "sha256": content_hash})
        relative_bytes = relative.encode("utf-8")
        digest.update(len(relative_bytes).to_bytes(8, "big"))
        digest.update(relative_bytes)
        digest.update(len(content).to_bytes(8, "big"))
        digest.update(content)
    return {"sha256": digest.hexdigest(), "fileCount": len(entries), "files": entries}


def validate_required_sentinels(cases: list[dict[str, Any]]) -> list[str]:
    by_id: dict[str, dict[str, Any]] = {}
    for case in cases:
        case_id = case.get("id")
        if isinstance(case_id, str):
            if case_id in by_id:
                return [f"duplicate_required_case:{case_id}"]
            by_id[case_id] = case

    errors: list[str] = []
    for case_id, sentinel in REQUIRED_SENTINELS.items():
        case = by_id.get(case_id)
        if case is None:
            errors.append(f"required_sentinel_case_missing:{case_id}")
            continue
        if case.get("source") != sentinel["source"]:
            errors.append(f"required_sentinel_source_changed:{case_id}")
        contract = case.get("nativeContract")
        compile_contract = contract.get("compile") if isinstance(contract, dict) else None
        if not isinstance(compile_contract, dict):
            errors.append(f"required_sentinel_compile_missing:{case_id}")
            continue
        if compile_contract.get("exitCode") != sentinel["compileExitCode"]:
            errors.append(f"required_sentinel_compile_exit_changed:{case_id}")
        if "diagnostics" in sentinel and compile_contract.get("diagnostics") != sentinel["diagnostics"]:
            errors.append(f"required_sentinel_diagnostics_changed:{case_id}")
        if "stdout" in sentinel:
            run_contract = contract.get("run")
            if not isinstance(run_contract, dict) or run_contract.get("stdout") != sentinel["stdout"]:
                errors.append(f"required_sentinel_stdout_changed:{case_id}")
            elif run_contract.get("exitCode") != 0 or run_contract.get("stderr") != "":
                errors.append(f"required_sentinel_run_contract_changed:{case_id}")
    return errors


def load_contract_sets(
    contract_pairs: tuple[tuple[Path, Path], ...],
) -> tuple[dict[str, Any], dict[str, str]]:
    merged_cases: dict[str, dict[str, Any]] = {}
    code_to_kind: dict[str, str] = {}
    for expectations_path, diagnostic_map_path in contract_pairs:
        document, mapping = candidate.load_contract_files(expectations_path, diagnostic_map_path)
        for code, kind in mapping.items():
            prior_kind = code_to_kind.get(code)
            if prior_kind is not None and prior_kind != kind:
                raise ValueError(f"diagnostic code has conflicting kinds: {code}")
            code_to_kind[code] = kind

        for original_case in document["cases"]:
            if not isinstance(original_case, dict) or not isinstance(original_case.get("id"), str):
                raise ValueError("expectations contain an invalid case entry")
            case_id = original_case["id"]
            case = dict(original_case)
            case["_fixtureRoot"] = str(expectations_path.resolve().parent)
            case["_expectationSources"] = [str(expectations_path.resolve())]
            previous = merged_cases.get(case_id)
            if previous is None:
                merged_cases[case_id] = case
                continue

            for field in ("source", "sourceSha256", "nativeContract"):
                if previous.get(field) != case.get(field):
                    raise ValueError(f"duplicate case has conflicting {field}: {case_id}")
            previous["lanes"] = sorted(set(previous.get("lanes", [])) | set(case.get("lanes", [])))
            for field in ("reference",):
                prior_value = previous.get(field)
                new_value = case.get(field)
                if prior_value is None:
                    previous[field] = new_value
                elif new_value is not None and prior_value != new_value:
                    raise ValueError(f"duplicate case has conflicting {field}: {case_id}")
            previous["_expectationSources"].extend(case["_expectationSources"])

    return {"schemaVersion": 1, "cases": list(merged_cases.values())}, code_to_kind


def expected_run_signature(record: dict[str, Any]) -> tuple[Any, ...]:
    diagnostics = record.get("actualDiagnostics", [])
    normalized_diagnostics = tuple(
        sorted(
            (
                str(item.get("severity") or ""),
                str(item.get("kind") or ""),
                str(item.get("code") or ""),
            )
            for item in diagnostics
        )
    )
    return (
        record.get("actualCompileExitCode"),
        normalized_diagnostics,
        record.get("actualRunExitCode"),
        record.get("actualRunStdoutSha256"),
        record.get("actualRunStderrSha256"),
    )


def portable_path(value: str) -> str:
    path = Path(value).expanduser()
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return f"<external>/{path.name}"


def run_matrix_case(
    case: dict[str, Any],
    *,
    case_dir: Path,
    fixture_root: Path,
    compiler: Path,
    stdlib_library: Path,
    stdlib_mode: str,
    optimization: str,
    compiler_env: dict[str, str],
    code_to_kind: dict[str, str],
    compile_timeout: float,
    run_timeout: float,
) -> dict[str, Any]:
    record = candidate.make_case_record(case["id"])
    record.update({"stdlibMode": stdlib_mode, "optimization": optimization})
    record["provenance"] = case.get("provenance")
    record["expectationSources"] = case.get("_expectationSources", [])
    contract = case.get("nativeContract")
    source = candidate.relative_fixture_path(fixture_root, case.get("source"))

    if source is None:
        candidate.add_failure(record, "invalid_fixture_source_path")
    elif not source.is_file():
        candidate.add_failure(record, "fixture_source_missing")
    else:
        actual_hash = candidate.sha256_file(source)
        expected_hash = case.get("sourceSha256")
        record["source"] = source.relative_to(fixture_root).as_posix()
        record["sourceSha256"] = actual_hash
        record["expectedSourceSha256"] = expected_hash
        if not isinstance(expected_hash, str):
            candidate.add_failure(record, "missing_expected_source_hash")
        elif actual_hash != expected_hash:
            candidate.add_failure(record, "fixture_source_hash_mismatch")
        (case_dir / "source.kt").parent.mkdir(parents=True, exist_ok=True)
        (case_dir / "source.kt").write_bytes(source.read_bytes())

    compile_contract = contract.get("compile") if isinstance(contract, dict) else None
    if not isinstance(compile_contract, dict):
        candidate.add_failure(record, "missing_compile_expectation")
    elif not isinstance(compile_contract.get("exitCode"), int):
        candidate.add_failure(record, "missing_expected_compile_exit_code")
    elif "diagnostics" not in compile_contract:
        candidate.add_failure(record, "missing_expected_diagnostics")
    else:
        record["expectedCompileExitCode"] = compile_contract["exitCode"]
        record["expectedDiagnostics"] = compile_contract["diagnostics"]
    run_contract = contract.get("run") if isinstance(contract, dict) else None
    reference = case.get("reference")
    if run_contract is None:
        if isinstance(reference, dict) and isinstance(reference.get("run"), dict):
            candidate.add_failure(record, "missing_expected_run")
            record["run"] = {"status": "missing_expectation"}
        else:
            record["run"] = {"status": "not_applicable", "reason": "compile-only-contract"}
    elif (
        not isinstance(run_contract, dict)
        or not isinstance(run_contract.get("exitCode"), int)
        or not isinstance(run_contract.get("stdout"), str)
        or not isinstance(run_contract.get("stderr"), str)
    ):
        candidate.add_failure(record, "missing_expected_run_field")
    else:
        record["expectedRun"] = run_contract

    if record["failureReasons"] or source is None or not source.is_file():
        record["status"] = "fail"
        candidate.write_json(case_dir / "result.json", record)
        return record

    output_binary = case_dir / "candidate.out"
    command = [str(compiler), f"-{optimization}", "-Xdiagnostics", "json"]
    if stdlib_mode == "source-injection":
        command.append("--stdlib-from-source")
    else:
        command.extend(["--no-stdlib", "--stdlib-library", str(stdlib_library)])
    command.extend([str(source), "-o", str(output_binary)])
    compile_result = candidate.run_process(
        command, timeout=compile_timeout, cwd=ROOT, env=compiler_env
    )
    candidate.record_command_result(case_dir, "compile", compile_result, command)

    if "spawnError" in compile_result:
        candidate.add_failure(record, "compile_spawn_failed")
        record["processError"] = compile_result["spawnError"]
    elif compile_result["timedOut"]:
        candidate.add_failure(record, "compile_timeout")
    else:
        actual_compile_exit = compile_result["exitCode"]
        expected_compile_exit = compile_contract["exitCode"]
        record["actualCompileExitCode"] = actual_compile_exit
        if actual_compile_exit != expected_compile_exit:
            candidate.add_failure(record, "compile_exit_mismatch")
        try:
            raw_diagnostics = candidate.diagnostic_json(compile_result["stderr"])
            actual_diagnostics, unknown_codes = candidate.canonical_diagnostics(
                raw_diagnostics, code_to_kind
            )
            record["actualDiagnostics"] = actual_diagnostics
            for code in unknown_codes:
                candidate.add_failure(record, f"unknown_diagnostic_code:{code}")
        except (UnicodeDecodeError, ValueError) as error:
            record["diagnosticsParseError"] = str(error)
        candidate.compare_compile_diagnostics(
            compile_result["stderr"],
            compile_contract.get("diagnostics"),
            code_to_kind,
            record,
        )

        if actual_compile_exit == 0 and expected_compile_exit == 0:
            if run_contract is None:
                record["run"] = {"status": "not_applicable", "reason": "compile-only-contract"}
            elif not output_binary.is_file():
                candidate.add_failure(record, "compiled_executable_missing")
            else:
                run_command = [str(output_binary)]
                run_result = candidate.run_process(
                    run_command, timeout=run_timeout, cwd=ROOT, env=os.environ.copy()
                )
                candidate.record_command_result(case_dir, "run", run_result, run_command)
                if "spawnError" in run_result:
                    candidate.add_failure(record, "run_spawn_failed")
                    record["processError"] = run_result["spawnError"]
                elif run_result["timedOut"]:
                    candidate.add_failure(record, "run_timeout")
                else:
                    expected_stdout = run_contract["stdout"].encode("utf-8")
                    expected_stderr = run_contract["stderr"].encode("utf-8")
                    actual_stdout = run_result["stdout"]
                    actual_stderr = run_result["stderr"]
                    record.update(
                        {
                            "actualRunExitCode": run_result["exitCode"],
                            "expectedRunExitCode": run_contract["exitCode"],
                            "actualRunStdout": actual_stdout.decode("utf-8", errors="replace"),
                            "actualRunStderr": actual_stderr.decode("utf-8", errors="replace"),
                            "actualRunStdoutSha256": sha256_bytes(actual_stdout),
                            "actualRunStderrSha256": sha256_bytes(actual_stderr),
                            "expectedRunStdoutSha256": sha256_bytes(expected_stdout),
                            "expectedRunStderrSha256": sha256_bytes(expected_stderr),
                            "run": {"status": "compared"},
                        }
                    )
                    if run_result["exitCode"] != run_contract["exitCode"]:
                        candidate.add_failure(record, "run_exit_code_mismatch")
                    if actual_stdout != expected_stdout:
                        candidate.add_failure(record, "run_stdout_mismatch")
                    if actual_stderr != expected_stderr:
                        candidate.add_failure(record, "run_stderr_mismatch")
        elif expected_compile_exit != 0 and actual_compile_exit == expected_compile_exit:
            if run_contract is not None:
                candidate.add_failure(record, "compile_failure_contract_must_not_have_run")
            else:
                record["run"] = {"status": "not_applicable", "reason": "expected-compile-failure"}

    record["status"] = "fail" if record["failureReasons"] else "pass"
    candidate.write_json(case_dir / "result.json", record)
    return record


def write_portable_evidence(path: Path, summary: dict[str, Any]) -> None:
    by_case: dict[str, dict[str, Any]] = {}
    for record in summary["cases"]:
        case = by_case.setdefault(
            record["id"],
            {
                "id": record["id"],
                "source": record.get("source"),
                "sourceSha256": record.get("sourceSha256"),
                "expectedSourceSha256": record.get("expectedSourceSha256"),
                "provenance": record.get("provenance"),
                "expectationSources": [
                    portable_path(item) for item in record.get("expectationSources", [])
                ],
                "matrix": {},
            },
        )
        key = f"{record.get('stdlibMode')}/{record.get('optimization')}"
        case["matrix"][key] = {
            "status": record.get("status"),
            "failureReasons": record.get("failureReasons", []),
            "compileExitCode": record.get("actualCompileExitCode"),
            "diagnostics": record.get("actualDiagnostics", []),
            "runExitCode": record.get("actualRunExitCode"),
            "stdout": record.get("actualRunStdout"),
            "stderr": record.get("actualRunStderr"),
            "stdoutSha256": record.get("actualRunStdoutSha256"),
            "stderrSha256": record.get("actualRunStderrSha256"),
        }

    expectation_inputs = [
        {**item, "path": portable_path(item["path"])}
        for item in summary.get("expectationInputs", [])
    ]
    diagnostic_map_inputs = [
        {**item, "path": portable_path(item["path"])}
        for item in summary.get("diagnosticMapInputs", [])
    ]
    compiler_identity = dict(summary["identity"]["compiler"])
    if compiler_identity.get("path"):
        compiler_identity["path"] = portable_path(compiler_identity["path"])

    evidence = {
        "schemaVersion": 1,
        "runner": summary["runner"],
        "status": summary["status"],
        "runId": summary["runId"],
        "startedAt": summary["startedAt"],
        "finishedAt": summary["finishedAt"],
        "artifactRunDirectory": os.path.relpath(
            summary["artifactDirectory"], path.resolve().parent
        ),
        "recordedAt": summary["finishedAt"],
        "gitRevision": summary["identity"].get("gitRevision"),
        "gitBranch": summary["identity"].get("gitBranch"),
        "compilerSourceTree": summary["identity"].get("compilerSourceTree"),
        "compiler": compiler_identity,
        "swiftVersion": summary["identity"].get("swiftVersion"),
        "platform": summary["identity"].get("platform"),
        "machine": summary["identity"].get("machine"),
        "environment": summary["identity"].get("environment"),
        "expectationInputs": expectation_inputs,
        "diagnosticMapInputs": diagnostic_map_inputs,
        "artifact": summary.get("artifact"),
        "requiredSentinels": list(REQUIRED_SENTINELS),
        "matrix": summary.get("matrix", []),
        "caseConsistency": summary.get("caseConsistency", []),
        "cases": list(by_case.values()),
        "counts": summary.get("counts"),
        "failureReasons": summary.get("failureReasons", []),
    }
    candidate.write_json(path, evidence)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kswiftc", type=Path, default=ROOT / ".build/debug/kswiftc")
    parser.add_argument("--expectations", type=Path, action="append")
    parser.add_argument("--diagnostic-map", type=Path, action="append")
    parser.add_argument(
        "--artifact-root", type=Path, default=ROOT / ".artifacts/js_annotations_matrix"
    )
    parser.add_argument("--record-summary", type=Path)
    parser.add_argument("--case", dest="case_ids", action="append", help="case id; repeatable")
    parser.add_argument("--compile-timeout", type=candidate.positive_seconds, default=600.0)
    parser.add_argument("--run-timeout", type=candidate.positive_seconds, default=10.0)
    parser.add_argument("--stdlib-timeout", type=candidate.positive_seconds, default=1800.0)
    args = parser.parse_args(argv)

    if args.expectations is None and args.diagnostic_map is None:
        contract_pairs = tuple((path.resolve(), mapping.resolve()) for path, mapping in DEFAULT_CONTRACT_PAIRS)
    elif args.expectations is None:
        parser.error("--diagnostic-map requires at least one --expectations")
    else:
        expectation_paths = [path.resolve() for path in args.expectations]
        if args.diagnostic_map is None:
            contract_pairs = tuple(
                (
                    path,
                    (DEFAULT_VIEW_DIAGNOSTIC_MAP if path == DEFAULT_VIEW_EXPECTATIONS.resolve() else DEFAULT_DIAGNOSTIC_MAP).resolve(),
                )
                for path in expectation_paths
            )
        else:
            diagnostic_paths = [path.resolve() for path in args.diagnostic_map]
            if len(expectation_paths) != len(diagnostic_paths):
                parser.error("each --expectations requires one matching --diagnostic-map")
            contract_pairs = tuple(zip(expectation_paths, diagnostic_paths))
    full_default_contracts = contract_pairs == tuple(
        (path.resolve(), mapping.resolve()) for path, mapping in DEFAULT_CONTRACT_PAIRS
    ) and args.case_ids is None

    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ") + "-" + uuid.uuid4().hex[:8]
    run_dir = args.artifact_root.resolve() / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    module_cache_root = run_dir / "module-cache"
    compiler_env = candidate.candidate_compiler_environment(module_cache_root)
    compiler = args.kswiftc if args.kswiftc.is_absolute() else (ROOT / args.kswiftc).resolve()

    summary: dict[str, Any] = {
        "schemaVersion": 1,
        "runner": "js_annotations_source_artifact_o0_o2",
        "runId": run_id,
        "startedAt": datetime.now(timezone.utc).isoformat(),
        "expectationPaths": [str(path) for path, _ in contract_pairs],
        "diagnosticMapPaths": [str(mapping) for _, mapping in contract_pairs],
        "compileTimeoutSeconds": args.compile_timeout,
        "runTimeoutSeconds": args.run_timeout,
        "stdlibTimeoutSeconds": args.stdlib_timeout,
        "artifactDirectory": str(run_dir),
        "moduleCacheDirectory": str(module_cache_root),
        "identity": snapshot_identity(compiler),
        "matrix": [],
        "cases": [],
        "caseConsistency": [],
        "excluded": [],
        "failureReasons": [],
    }

    fatal_reason: str | None = None
    selected: list[dict[str, Any]] = []
    try:
        document, code_to_kind = load_contract_sets(contract_pairs)
        summary["expectationInputs"] = [
            {"path": str(path), "sha256": candidate.sha256_file(path)}
            for path, _ in contract_pairs
        ]
        summary["diagnosticMapInputs"] = [
            {"path": str(path), "sha256": candidate.sha256_file(path)}
            for _, path in contract_pairs
        ]
    except (OSError, ValueError, json.JSONDecodeError) as error:
        document = {"cases": []}
        code_to_kind = {}
        fatal_reason = "contract_input_invalid"
        summary["contractError"] = str(error)

    if fatal_reason is None:
        selected, excluded, invalid = candidate.select_cases(document["cases"], args.case_ids)
        summary["excluded"] = excluded
        summary["cases"].extend(invalid)
        if not selected:
            fatal_reason = "no_native_compat_cases_selected"
        if not compiler.is_file() or not os.access(compiler, os.X_OK):
            fatal_reason = "kswiftc_not_found_or_not_executable"
        if full_default_contracts:
            sentinel_errors = validate_required_sentinels(document["cases"])
            if sentinel_errors:
                fatal_reason = "required_sentinel_contract_invalid"
                summary["sentinelErrors"] = sentinel_errors
    if fatal_reason:
        summary["failureReasons"].append(fatal_reason)

    artifact_path = run_dir / "stdlib/KSwiftKStdlib.kklib"
    artifact_identity: dict[str, Any] | None = None
    if fatal_reason is None:
        build_command = [
            str(compiler),
            "--stdlib-only",
            "--emit",
            "library",
            "-o",
            str(artifact_path),
        ]
        build_result = candidate.run_process(
            build_command, timeout=args.stdlib_timeout, cwd=ROOT, env=compiler_env
        )
        candidate.record_command_result(run_dir / "stdlib-build", "build", build_result, build_command)
        if "spawnError" in build_result:
            fatal_reason = "stdlib_build_spawn_failed"
            summary["stdlibBuildError"] = build_result["spawnError"]
        elif build_result["timedOut"]:
            fatal_reason = "stdlib_build_timeout"
        elif build_result["exitCode"] != 0:
            fatal_reason = "stdlib_build_failed"
            summary["stdlibBuildExitCode"] = build_result["exitCode"]
        elif not artifact_path.is_dir() or not (artifact_path / "manifest.json").is_file():
            fatal_reason = "stdlib_build_artifact_missing"
        else:
            artifact_identity = directory_digest(artifact_path)
            artifact_identity.update(
                {
                    "path": artifact_path.relative_to(run_dir).as_posix(),
                    "manifestSha256": candidate.sha256_file(artifact_path / "manifest.json"),
                    "buildCommand": [
                        "<kswiftc>",
                        "--stdlib-only",
                        "--emit",
                        "library",
                        "-o",
                        "<run-directory>/stdlib/KSwiftKStdlib.kklib",
                    ],
                    "builderCompilerSha256": summary["identity"]["compiler"].get("sha256"),
                    "builderSourceTreeSha256": summary["identity"]["compilerSourceTree"].get("sha256"),
                    "builderGitRevision": summary["identity"].get("gitRevision"),
                }
            )
            summary["artifact"] = artifact_identity
        if fatal_reason:
            summary["failureReasons"].append(fatal_reason)

    if fatal_reason is not None:
        for case in selected:
            for stdlib_mode in ARTIFACT_MODES:
                for optimization in OPTIMIZATION_LEVELS:
                    record = candidate.make_case_record(case["id"])
                    record.update({"stdlibMode": stdlib_mode, "optimization": optimization})
                    candidate.add_failure(record, fatal_reason)
                    summary["cases"].append(record)
                    candidate.write_json(
                        run_dir
                        / "cases"
                        / candidate.safe_case_name(case["id"])
                        / f"{stdlib_mode}-{optimization}"
                        / "result.json",
                        record,
                    )
    elif artifact_identity is not None:
        for stdlib_mode in ARTIFACT_MODES:
            for optimization in OPTIMIZATION_LEVELS:
                row_records: list[dict[str, Any]] = []
                for case in selected:
                    case_dir = (
                        run_dir
                        / "cases"
                        / candidate.safe_case_name(case["id"])
                        / f"{stdlib_mode}-{optimization}"
                    )
                    record = run_matrix_case(
                        case,
                        case_dir=case_dir,
                        fixture_root=Path(case["_fixtureRoot"]),
                        compiler=compiler,
                        stdlib_library=artifact_path,
                        stdlib_mode=stdlib_mode,
                        optimization=optimization,
                        compiler_env=compiler_env,
                        code_to_kind=code_to_kind,
                        compile_timeout=args.compile_timeout,
                        run_timeout=args.run_timeout,
                    )
                    summary["cases"].append(record)
                    row_records.append(record)
                summary["matrix"].append(
                    {
                        "stdlibMode": stdlib_mode,
                        "optimization": optimization,
                        "total": len(row_records),
                        "passed": sum(record["status"] == "pass" for record in row_records),
                        "failed": sum(record["status"] != "pass" for record in row_records),
                    }
                )

        by_case: dict[str, list[dict[str, Any]]] = {}
        for record in summary["cases"]:
            by_case.setdefault(record["id"], []).append(record)
        for case_id, records in by_case.items():
            signatures = {expected_run_signature(record) for record in records}
            consistent = len(records) == len(ARTIFACT_MODES) * len(OPTIMIZATION_LEVELS) and len(signatures) == 1
            consistency = {
                "id": case_id,
                "status": "pass" if consistent else "fail",
                "rows": [
                    {"stdlibMode": record.get("stdlibMode"), "optimization": record.get("optimization")}
                    for record in records
                ],
            }
            if not consistent:
                consistency["failureReason"] = "matrix_outcome_divergence"
                for record in records:
                    candidate.add_failure(record, "matrix_outcome_divergence")
                    record["status"] = "fail"
                    case_dir = (
                        run_dir
                        / "cases"
                        / candidate.safe_case_name(case_id)
                        / f"{record['stdlibMode']}-{record['optimization']}"
                    )
                    candidate.write_json(case_dir / "result.json", record)
            summary["caseConsistency"].append(consistency)

        if directory_digest(artifact_path)["sha256"] != artifact_identity["sha256"]:
            summary["failureReasons"].append("stdlib_artifact_changed_during_matrix")
            for record in summary["cases"]:
                if record.get("stdlibMode") == "stdlib-kklib":
                    candidate.add_failure(record, "stdlib_artifact_changed_during_matrix")
                    record["status"] = "fail"
                    case_dir = (
                        run_dir
                        / "cases"
                        / candidate.safe_case_name(record["id"])
                        / f"{record['stdlibMode']}-{record['optimization']}"
                    )
                    candidate.write_json(case_dir / "result.json", record)

    final_source_identity = source_tree_identity()
    final_compiler_sha = candidate.sha256_file(compiler) if compiler.is_file() else None
    final_revision = git_text("rev-parse", "HEAD")
    if (
        final_source_identity != summary["identity"]["compilerSourceTree"]
        or final_compiler_sha != summary["identity"]["compiler"]["sha256"]
        or final_revision != summary["identity"].get("gitRevision")
    ):
        summary["failureReasons"].append("compiler_or_source_identity_changed_during_matrix")

    summary["finishedAt"] = datetime.now(timezone.utc).isoformat()
    failed_runs = sum(record.get("status") != "pass" for record in summary["cases"])
    failed_consistency = sum(item.get("status") != "pass" for item in summary["caseConsistency"])
    summary["status"] = "fail" if fatal_reason or failed_runs or failed_consistency or summary["failureReasons"] else "pass"
    summary["counts"] = {
        "caseRuns": len(summary["cases"]),
        "passed": sum(record.get("status") == "pass" for record in summary["cases"]),
        "failed": failed_runs,
        "caseConsistency": len(summary["caseConsistency"]),
        "inconsistentCases": failed_consistency,
        "excluded": len(summary["excluded"]),
    }
    candidate.write_json(run_dir / "summary.json", summary)
    if args.record_summary:
        evidence_path = args.record_summary
        if not evidence_path.is_absolute():
            evidence_path = ROOT / evidence_path
        write_portable_evidence(evidence_path, summary)

    for record in summary["cases"]:
        key = f"{record.get('stdlibMode')}/{record.get('optimization')}"
        if record.get("status") == "pass":
            print(f"PASS {record['id']} matrix={key}")
        else:
            reasons = ",".join(record.get("failureReasons", []))
            print(f"FAIL {record['id']} matrix={key} reason={reasons or fatal_reason}")
    counts = summary["counts"]
    print(
        f"Summary: status={summary['status']} case-runs={counts['caseRuns']} "
        f"failed={counts['failed']} inconsistent={counts['inconsistentCases']} "
        f"excluded={counts['excluded']}"
    )
    print(f"Artifacts: {run_dir}")
    if args.record_summary:
        print(f"Evidence: {evidence_path}")
    return 1 if summary["status"] != "pass" else 0


if __name__ == "__main__":
    raise SystemExit(main())
