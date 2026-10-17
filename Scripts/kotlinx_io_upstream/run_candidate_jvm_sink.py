#!/usr/bin/env python3
"""Run the locked JVM AbstractSinkTestJVM bodies on the macOS native candidate."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys

from run_candidate_subset import parse_events, tree_hash
from run_jvm_reference import HERE, execute, sha256, verify_file

REFERENCE_LOCK = HERE / "reference-lock.json"
REFERENCE_CATALOG = HERE / "jvm-executions.expected.json"
CANDIDATE_CATALOG = HERE / "jvm-candidate-executions.expected.json"
SUPPORT_SOURCE = HERE / "fixtures/jvm_sink_test_support.kt"
CONTRACT_PROBE_SOURCE = HERE / "fixtures/jvm_sink_contract_probe.kt"
CONTRACT_PROBE_EXPECTED = HERE / "jvm-sink-contract-probe.expected.json"
SOURCE_PATH = "core/jvm/test/AbstractSinkTestJVM.kt"
FACTORY_PATH = "core/common/test/SinkFactory.kt"
PREFIX = b'@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")\n\n'
IMPORT_REWRITES = {
    "import kotlin.test.Test": "import kotlinx.io.Test",
    "import kotlin.test.assertEquals": "import kotlinx.io.assertEquals",
    "import kotlin.test.assertFailsWith": "import kotlinx.io.assertFailsWith",
}
LANES = {"source", "stdlib-library", "producer-consumer"}


def canonical_sha256(value: object) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def git_head(root: Path) -> str:
    result = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
                            capture_output=True, text=True, check=True)
    return result.stdout.strip()


def prepare_port(upstream: Path, selected: list[dict], lock: dict, output: Path) -> dict:
    records = {row["path"]: row for row in lock["upstream_files"]}
    source_record = records.get(SOURCE_PATH)
    factory_record = records.get(FACTORY_PATH)
    if source_record is None or factory_record is None:
        raise ValueError("locked JVM Sink source or factory source is missing")
    source = upstream / SOURCE_PATH
    factory = upstream / FACTORY_PATH
    verify_file(source, source_record)
    verify_file(factory, factory_record)
    raw = source.read_bytes()
    text = raw.decode("utf-8")
    lines = text.splitlines(keepends=True)
    replacement_counts = {line: 0 for line in IMPORT_REWRITES}
    transformed = []
    for line in lines:
        key = line.rstrip("\r\n")
        if key in IMPORT_REWRITES:
            replacement_counts[key] += 1
            newline = "\r\n" if line.endswith("\r\n") else "\n" if line.endswith("\n") else ""
            transformed.append(IMPORT_REWRITES[key] + newline)
        else:
            transformed.append(line)
    if any(count != 1 for count in replacement_counts.values()):
        raise ValueError("the pinned JVM test imports differ from the reviewed candidate adapter")
    ported = PREFIX + "".join(transformed).encode("utf-8")
    port_path = output / "AbstractSinkTestJVM.kt"
    port_path.write_bytes(ported)
    factory_path = output / "SinkFactory.kt"
    factory_path.write_bytes(PREFIX + factory.read_bytes())
    support_path = SUPPORT_SOURCE.resolve()
    if not support_path.is_file():
        raise ValueError("JVM Sink candidate test support source is missing")
    contract_probe = CONTRACT_PROBE_SOURCE.resolve()
    if not contract_probe.is_file():
        raise ValueError("JVM Sink candidate contract probe source is missing")
    ported_probe = output / "SinkContractProbe.kt"
    ported_probe.write_bytes(contract_probe.read_bytes())

    candidate_ids = [row["execution_id"] for row in selected]
    if not candidate_ids or len(candidate_ids) != len(set(candidate_ids)):
        raise ValueError("candidate execution selection must be nonempty and unique")
    token = "KIO_" + hashlib.sha256(raw + json.dumps(candidate_ids).encode()).hexdigest()[:24]
    probe_token = token + "_CONTRACT_PROBE"
    driver = ["import kotlinx.io.SinkTestObservations", "", "fun main() {"]
    for row in selected:
        candidate_id = row["execution_id"]
        suite = row["concrete_class"]
        method = row["method_name"]
        driver += [
            "    SinkTestObservations.reset()",
            f'    println("{token} BEGIN {candidate_id}")',
            "    try {",
            f"        {suite}().{method}()",
            f'        println("{token}_OBS {candidate_id} " + SinkTestObservations.toJson())',
            f'        println("{token} PASS {candidate_id}")',
            "    } catch (failure: Throwable) {",
            f'        println("{token} FAIL {candidate_id}")',
            f'        println("{token} EXCEPTION " + failure::class.qualifiedName)',
            "    }",
        ]
    driver += [
        f'    println("{probe_token} " + kotlinx.io.contractprobe.verifySinkWriteStringContracts())',
    ]
    driver += ["}", ""]
    driver_path = output / "CandidateDriver.kt"
    driver_path.write_text("\n".join(driver), encoding="utf-8")
    return {
        "source_path": SOURCE_PATH,
        "original_source_sha256": source_record["sha256"],
        "source_git_blob_sha": source_record["git_blob_sha"],
        "ported_source_sha256": sha256(port_path),
        "assertion_bodies_unchanged": True,
        "rewritten_imports": replacement_counts,
        "factory_source_sha256": factory_record["sha256"],
        "ported_factory_sha256": sha256(factory_path),
        "support_source_path": str(support_path),
        "support_source_sha256": sha256(support_path),
        "contract_probe_source_path": str(contract_probe),
        "contract_probe_source_sha256": sha256(contract_probe),
        "ported_contract_probe_sha256": sha256(ported_probe),
        "contract_probe_expected_sha256": sha256(CONTRACT_PROBE_EXPECTED),
        "contract_probe_event_token": probe_token,
        "driver_path": str(driver_path),
        "driver_sha256": sha256(driver_path),
        "execution_ids": candidate_ids,
        "reference_execution_ids": [row["reference_execution_id"] for row in selected],
        "event_token": token,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--lane", choices=sorted(LANES), required=True)
    parser.add_argument("--stdlib-library", type=Path,
                        help="fresh KSwiftKStdlib.kklib required for library-based lanes")
    parser.add_argument("--execution-id", action="append", default=[],
                        help="select one candidate execution ID; defaults to all 20 locked IDs")
    parser.add_argument("--optimization", choices=("O0", "O2"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compile-timeout", type=float, default=900)
    parser.add_argument("--run-timeout", type=float, default=180)
    args = parser.parse_args(argv)
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    root = args.package_root.resolve()
    summary = {
        "kind": "candidate-jvm-only-native-sink-suite",
        "status": "NOT_RUN",
        "candidate_target": "macos-native",
        "lane": args.lane,
        "optimization": args.optimization,
        "host": platform.platform(),
        "package_root": str(root),
        "candidate_sha": None,
        "candidate_catalog_count": None,
        "selected_execution_count": 0,
        "paired_disposition": "UNMAPPED",
        "paired_pass_count": 0,
    }
    try:
        if platform.system() != "Darwin":
            raise ValueError("the macOS native candidate lane must execute on Darwin")
        if args.lane == "source" and args.stdlib_library is not None:
            raise ValueError("source lane must not accept a stdlib library")
        if args.lane != "source" and args.stdlib_library is None:
            raise ValueError("library-based lanes require a fresh stdlib library")
        if args.stdlib_library is not None and (
                not args.stdlib_library.is_dir() or not (args.stdlib_library / "manifest.json").is_file()):
            raise ValueError("stdlib artifact must be a KSwiftKStdlib.kklib directory")

        lock = json.loads(REFERENCE_LOCK.read_text(encoding="utf-8"))
        verify_file(CONTRACT_PROBE_SOURCE, {
            "sha256": lock["jvm_sink_contract_probe_source_sha256"],
        })
        verify_file(CONTRACT_PROBE_EXPECTED, {
            "sha256": lock["jvm_sink_contract_probe_expected_sha256"],
        })
        reference_bytes = REFERENCE_CATALOG.read_bytes()
        candidate_bytes = CANDIDATE_CATALOG.read_bytes()
        if hashlib.sha256(reference_bytes).hexdigest() != lock["jvm_execution_catalog_sha256"]:
            raise ValueError("JVM execution catalog differs from reference lock")
        if hashlib.sha256(candidate_bytes).hexdigest() != lock["jvm_candidate_execution_catalog_sha256"]:
            raise ValueError("candidate JVM execution catalog differs from reference lock")
        catalog = json.loads(candidate_bytes.decode("utf-8"))
        if (catalog.get("schema_version") != 1
                or catalog.get("upstream_commit") != lock["commit"]
                or catalog.get("candidate_runtime") != "kswiftk-native"
                or catalog.get("target") != "macos"):
            raise ValueError("candidate JVM execution catalog has an unexpected scope")
        if catalog.get("candidate_commit") != git_head(root):
            raise ValueError("candidate JVM execution catalog does not match the issue-pinned candidate commit")
        all_rows = catalog["executions"]
        all_ids = [row["execution_id"] for row in all_rows]
        if len(all_rows) != 20 or len(all_ids) != len(set(all_ids)):
            raise ValueError("candidate JVM execution catalog must contain 20 unique IDs")
        if args.execution_id:
            if len(args.execution_id) != len(set(args.execution_id)):
                raise ValueError("candidate execution selection contains duplicate IDs")
            unknown = set(args.execution_id) - set(all_ids)
            if unknown:
                raise ValueError(f"unknown candidate execution ID: {sorted(unknown)[0]}")
            selected_ids = set(args.execution_id)
            selected = [row for row in all_rows if row["execution_id"] in selected_ids]
        else:
            selected = list(all_rows)
        if not selected:
            raise ValueError("candidate selection resolved to no JVM tests")
        if any(row["upstream_path"] != SOURCE_PATH for row in selected):
            raise ValueError("selected candidate IDs must refer to AbstractSinkTestJVM.kt")

        by_path = {row["path"]: row for row in lock["upstream_files"]}
        source_lock_rows = [by_path[path] for path in (SOURCE_PATH, FACTORY_PATH)]
        port = prepare_port(args.upstream.resolve(), selected, lock, args.output)
        resources = args.compiler.resolve().parent / "KSwiftK_CompilerCore.resources"
        if not (resources / "Stdlib").is_dir():
            resources = args.compiler.resolve().parent / "KSwiftK_CompilerCore.bundle" / "Contents" / "Resources"
        if args.lane == "source" and not (resources / "Stdlib").is_dir():
            raise ValueError("source lane requires the compiler's actual stdlib resource bundle")
        if any(not math_is_positive(value) for value in (args.compile_timeout, args.run_timeout)):
            raise ValueError("timeouts must be positive")

        def snapshot() -> dict:
            values = {
                "workspace_git_sha": git_head(root),
                "compiler_sha256": sha256(args.compiler),
                "compiler_resources_sha256": tree_hash(resources) if (resources / "Stdlib").is_dir() else None,
                "stdlib_library_sha256": tree_hash(args.stdlib_library) if args.stdlib_library else None,
                "stdlib_sources_sha256": tree_hash(root / "Sources/CompilerCore/Stdlib"),
                "runtime_sources_sha256": tree_hash(root / "Sources/Runtime"),
                "runtime_abi_sources_sha256": tree_hash(root / "Sources/RuntimeABI"),
                "package_manifest_sha256": sha256(root / "Package.swift"),
                "reference_lock_sha256": sha256(REFERENCE_LOCK),
                "reference_catalog_sha256": sha256(REFERENCE_CATALOG),
                "candidate_catalog_sha256": sha256(CANDIDATE_CATALOG),
                "runner_sha256": sha256(Path(__file__)),
                "event_parser_sha256": sha256(HERE / "run_candidate_subset.py"),
                "upstream_sources": {row["path"]: sha256(args.upstream / row["path"])
                                     for row in source_lock_rows},
                "support_source_sha256": sha256(SUPPORT_SOURCE),
                "contract_probe_source_sha256": sha256(CONTRACT_PROBE_SOURCE),
                "contract_probe_expected_sha256": sha256(CONTRACT_PROBE_EXPECTED),
                "ported_contract_probe_sha256": sha256(args.output / "SinkContractProbe.kt"),
                "ported_source_sha256": sha256(args.output / "AbstractSinkTestJVM.kt"),
                "ported_factory_sha256": sha256(args.output / "SinkFactory.kt"),
                "driver_sha256": sha256(Path(port["driver_path"])),
            }
            if args.stdlib_library:
                values["stdlib_manifest_sha256"] = sha256(args.stdlib_library / "manifest.json")
            return values

        inputs = snapshot()
        summary.update({
            "candidate_sha": inputs["workspace_git_sha"],
            "selected_execution_count": len(selected),
            "candidate_catalog_count": len(all_rows),
            "selected_execution_ids": [row["execution_id"] for row in selected],
            "selected_reference_execution_ids": [row["reference_execution_id"] for row in selected],
            "selected_upstream_function_ids": sorted({row["upstream_id"] for row in selected}),
            "selection_sha256": canonical_sha256(selected),
            "port": port,
            "inputs": inputs,
            "expected_count": len(selected),
            "test_body_mode": "library-consumer" if args.lane == "producer-consumer" else "source",
        })

        compiler = str(args.compiler.resolve())
        base = [compiler, f"-{args.optimization}"]
        if args.lane == "source":
            base.append("--stdlib-from-source")
        else:
            base += ["--no-stdlib", "--stdlib-library", str(args.stdlib_library.resolve())]
        environment = {"KSWIFTK_PACKAGE_ROOT": str(root)}
        source_paths = [str(args.output / "AbstractSinkTestJVM.kt"),
                        str(args.output / "SinkFactory.kt"), str(SUPPORT_SOURCE.resolve())]
        probe_source = args.output / "SinkContractProbe.kt"
        driver = Path(port["driver_path"])
        binary = args.output / "candidate"
        test_library = None
        code = 1
        if args.lane == "producer-consumer":
            test_library = args.output / "JvmSinkTests.kklib"
            library_command = base + ["--emit", "library", "-m", "KioJvmSinkTests"] + source_paths + ["-o", str(test_library)]
            code = execute(library_command, args.output, "test-library-compile", args.compile_timeout, environment)
            summary["test_library_compile_exitcode"] = code
            if code == 0:
                summary["test_library_sha256"] = tree_hash(test_library)
                command = base + ["-I", str(test_library), str(probe_source), str(driver), "-o", str(binary)]
        else:
            command = base + source_paths + [str(probe_source), str(driver), "-o", str(binary)]
        if args.lane != "producer-consumer" or code == 0:
            code = execute(command, args.output, "compile", args.compile_timeout, environment)
            summary["compile_exitcode"] = code
        if code == 0:
            executable_sha = sha256(binary)
            summary["candidate_executable_sha256"] = executable_sha
            code = execute([str(binary)], args.output, "run", args.run_timeout)
            summary["run_exitcode"] = code
            run_stdout = (args.output / "run.stdout").read_text(encoding="utf-8")
            probe_marker = port["contract_probe_event_token"] + " "
            probe_lines = [line[len(probe_marker):] for line in run_stdout.splitlines()
                           if line.startswith(probe_marker)]
            expected_probe = json.loads(CONTRACT_PROBE_EXPECTED.read_text(encoding="utf-8"))
            actual_probe = probe_lines[0] if len(probe_lines) == 1 else None
            probe_status = "PASS" if actual_probe == expected_probe.get("expected_output") else "FAIL"
            probe_result = {
                "status": probe_status,
                "expected": expected_probe.get("expected_output"),
                "actual": actual_probe,
                "event_count": len(probe_lines),
                "source_sha256": inputs["contract_probe_source_sha256"],
                "expected_contract_sha256": inputs["contract_probe_expected_sha256"],
                "lane": args.lane,
                "optimization": args.optimization,
                "candidate_sha": inputs["workspace_git_sha"],
                "candidate_executable_sha256": executable_sha,
            }
            probe_result_path = args.output / "contract-probe-results.json"
            probe_result_path.write_text(json.dumps(probe_result, indent=2, ensure_ascii=False) + "\n",
                                         encoding="utf-8")
            summary["contract_probe"] = {
                "status": probe_status,
                "artifact": probe_result_path.name,
                "sha256": sha256(probe_result_path),
                "checks": 4,
            }
            parsed = parse_events((args.output / "run.stdout").read_text(encoding="utf-8"),
                                  [row["execution_id"] for row in selected], port["event_token"])
            result_by_id = {row["execution_id"]: row for row in parsed}

            def observations_for(row: dict) -> dict[str, list[str]]:
                marker = f"{port['event_token']}_OBS {row['execution_id']} "
                matching = [line[len(marker):] for line in row["stdout"].splitlines()
                            if line.startswith(marker)]
                if row["status"] == "PASS" and len(matching) != 1:
                    raise ValueError(f"expected one assertion-observation record for {row['execution_id']}")
                if not matching:
                    return {}
                records = json.loads(matching[0])
                if not isinstance(records, list):
                    raise ValueError(f"malformed assertion observations for {row['execution_id']}")
                observations: dict[str, list[str]] = collections.defaultdict(list)
                for record in records:
                    if (not isinstance(record, dict) or record.get("kind") not in {"value", "exception_type"}
                            or not isinstance(record.get("value"), str)):
                        raise ValueError(f"malformed assertion observation for {row['execution_id']}")
                    observations[record["kind"]].append(record["value"])
                return {
                    kind: "; ".join(values) if kind == "exception_type" else values
                    for kind, values in observations.items()
                }

            results = []
            for row in selected:
                parsed_result = result_by_id[row["execution_id"]]
                results.append({
                    "execution_id": row["execution_id"],
                    "reference_execution_id": row["reference_execution_id"],
                    "upstream_id": row["upstream_id"],
                    "concrete_class": row["concrete_class"],
                    "declaring_class": row["declaring_class"],
                    "method_name": row["method_name"],
                    "status": parsed_result["status"],
                    "exception_type": parsed_result.get("exception_type"),
                    "observations": observations_for(parsed_result),
                    "stdout": parsed_result.get("stdout", ""),
                    "lane": args.lane,
                    "optimization": args.optimization,
                    "candidate_sha": inputs["workspace_git_sha"],
                    "candidate_executable_sha256": executable_sha,
                    "candidate_catalog_sha256": inputs["candidate_catalog_sha256"],
                    "source_git_blob_sha": row["git_blob_sha"],
                })
            if sha256(binary) != executable_sha:
                raise ValueError("candidate executable changed during execution")
        else:
            results = [{"execution_id": row["execution_id"],
                        "reference_execution_id": row["reference_execution_id"],
                        "upstream_id": row["upstream_id"], "status": "NOT_RUN"} for row in selected]

        after = snapshot()
        if after != inputs:
            raise ValueError("candidate inputs changed during execution")
        results_path = args.output / "results.json"
        results_path.write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        result_counts = dict(collections.Counter(row["status"] for row in results))
        summary.update({
            "inputs_unchanged": True,
            "counts": result_counts,
            "result_count": len(results),
            "results_sha256": sha256(results_path),
            "paired_disposition": "candidate-native-to-jvm-reference-execution-map",
            "candidate_executions": sum(row["status"] in {"PASS", "FAIL"} for row in results),
            "status": "PASS" if code == 0 and len(results) == len(selected)
                and all(row["status"] == "PASS" for row in results)
                and summary.get("contract_probe", {}).get("status") == "PASS" else "FAIL",
        })
        return 0 if summary["status"] == "PASS" else 1
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        summary.update({"status": "ERROR", "error": str(error)})
        (args.output / "error.txt").write_text(str(error) + "\n", encoding="utf-8")
        return 1
    finally:
        (args.output / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n",
                                                  encoding="utf-8")


def math_is_positive(value: float) -> bool:
    return value > 0 and value < float("inf")


if __name__ == "__main__":
    raise SystemExit(main())
