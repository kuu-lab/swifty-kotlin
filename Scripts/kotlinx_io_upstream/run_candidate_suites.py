#!/usr/bin/env python3
"""Run locked direct suites together, from source or a separate test library.

Original assertions and constructors are preserved. This remains assertion-only
candidate coverage: factories/hooks need other drivers, and paired PASS is zero.
"""

from __future__ import annotations

import argparse
import collections
import json
import math
from pathlib import Path
import platform
import sys

from run_candidate_subset import parse_events, prepare_port, tree_hash
from run_jvm_reference import HERE, execute, sha256, verify_file


def prepare_suites(upstream: Path, catalog: list[dict], lock: dict,
                   suites: list[str], output: Path) -> list[dict]:
    if not suites or len(set(suites)) != len(suites):
        raise ValueError("suite selection must be nonempty and unique")
    ports = []
    source_paths = set()
    for index, suite in enumerate(suites):
        directory = output / f"suite-{index:03d}"
        directory.mkdir()
        rows = [row for row in catalog if row["concrete_class"] == suite]
        port = prepare_port(upstream, rows, lock, directory)
        if port["source_path"] in source_paths:
            raise ValueError("multiple selected classes share a source file; use a verified multi-class driver")
        source_paths.add(port["source_path"])
        ports.append(port)
    driver = ["fun main() {"]
    for port in ports:
        lines = Path(port["driver_path"]).read_text().splitlines()
        if lines[0] != "fun main() {" or lines[-1] != "}":
            raise ValueError("unexpected generated direct driver")
        driver.extend(lines[1:-1])
    driver += ["}", ""]
    (output / "CombinedDriver.kt").write_text("\n".join(driver))
    return ports


def parse_suite_results(text: str, ports: list[dict]) -> list[dict]:
    results = []
    for port in ports:
        results.extend(parse_events(text, port["execution_ids"], port["event_token"]))
    ids = [row["execution_id"] for row in results]
    if len(set(ids)) != len(ids):
        raise ValueError("duplicate execution ID across suites")
    return results


def compiler_resource_bundle(compiler: Path, explicit: Path | None) -> Path | None:
    if explicit:
        candidates = [explicit.resolve()]
    else:
        directory = compiler.resolve().parent
        candidates = [directory / "KSwiftK_CompilerCore.resources",
                      directory / "KSwiftK_CompilerCore.bundle"]
    for candidate in candidates:
        if (candidate / "Stdlib").is_dir():
            return candidate
        resource_path = candidate / "Contents" / "Resources"
        if (resource_path / "Stdlib").is_dir():
            return resource_path
    if explicit:
        raise ValueError("compiler resource bundle must contain Stdlib")
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--compiler-resource-bundle", type=Path,
                        help="actual Bundle.module directory; defaults to the compiler's sibling resources/bundle")
    parser.add_argument("--suite", action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    stdlib = parser.add_mutually_exclusive_group(required=True)
    stdlib.add_argument("--stdlib-library", type=Path)
    stdlib.add_argument("--stdlib-from-source", action="store_true")
    parser.add_argument("--test-library", action="store_true",
                        help="compile original bodies to .kklib, then compile a separate consumer driver")
    parser.add_argument("--optimization", choices=["O0", "O2"], default="O0")
    parser.add_argument("--compile-timeout", type=float, default=240)
    parser.add_argument("--run-timeout", type=float, default=30)
    args = parser.parse_args(argv)
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    root = args.package_root.resolve()
    lock_path = HERE / "reference-lock.json"
    catalog_path = HERE / "native-executions.expected.json"
    summary = {"kind": "candidate-assertion-direct-suites", "paired_pass_count": 0,
               "paired_disposition": "UNMAPPED", "seven_observations_exported": False,
               "host": platform.platform(), "python_version": sys.version,
               "optimization": args.optimization, "package_root": str(root),
               "stdlib_mode": "source" if args.stdlib_from_source else "library",
               "test_body_mode": "library-consumer" if args.test_library else "source",
               "runtime_cache_provenance": "Runtime source hashes only; cached object bytes are outside this proof"}
    try:
        if any(not math.isfinite(value) or value <= 0 for value in [args.compile_timeout, args.run_timeout]):
            raise ValueError("timeouts must be finite and positive")
        if args.stdlib_library and (not args.stdlib_library.is_dir() or
                                   not (args.stdlib_library / "manifest.json").is_file()):
            raise ValueError("stdlib must be a library directory containing manifest.json")
        resources = compiler_resource_bundle(args.compiler, args.compiler_resource_bundle)
        if args.stdlib_from_source and resources is None:
            raise ValueError("source mode requires the actual compiler resource bundle")
        summary["compiler_resource_bundle"] = str(resources) if resources else None
        summary["compiler_resource_bundle_provenance"] = (
            "explicit caller-selected Bundle.module directory" if args.compiler_resource_bundle
            else "compiler sibling Bundle.module directory" if resources
            else "not found; library lane only")
        lock = json.loads(lock_path.read_text())
        for record in lock["upstream_files"]:
            verify_file(args.upstream / record["path"], record)
        verify_file(catalog_path, {"sha256": lock["native_execution_catalog_sha256"]})
        ports = prepare_suites(args.upstream, json.loads(catalog_path.read_text()), lock, args.suite, args.output)
        driver = args.output / "CombinedDriver.kt"

        def inputs() -> dict:
            return {
                "compiler_sha256": sha256(args.compiler),
                "compiler_resource_bundle_sha256": tree_hash(resources) if resources else None,
                "stdlib_content_sha256": tree_hash(args.stdlib_library) if args.stdlib_library else None,
                "stdlib_sources_sha256": tree_hash(root / "Sources" / "CompilerCore" / "Stdlib"),
                "runtime_sources_sha256": tree_hash(root / "Sources" / "Runtime"),
                "runtime_abi_sources_sha256": tree_hash(root / "Sources" / "RuntimeABI"),
                "package_manifest_sha256": sha256(root / "Package.swift"),
                "lock_sha256": sha256(lock_path), "catalog_sha256": sha256(catalog_path),
                "runner_sha256": sha256(Path(__file__)),
                "direct_runner_sha256": sha256(HERE / "run_candidate_subset.py"),
                "helper_sha256": sha256(HERE / "run_jvm_reference.py"),
                "driver_sha256": sha256(driver),
                "port_sha256": {port["port_path"]: sha256(Path(port["port_path"])) for port in ports},
            }

        before = inputs()
        count = sum(len(port["execution_ids"]) for port in ports)
        summary.update({"ports": ports, "inputs": before, "expected_count": count})
        base = [str(args.compiler.resolve()), "-" + args.optimization]
        base += ["--stdlib-from-source"] if args.stdlib_from_source else ["--stdlib-library", str(args.stdlib_library.resolve())]
        environment = {"KSWIFTK_PACKAGE_ROOT": str(root)}
        binary = args.output / "candidate"
        sources = [port["port_path"] for port in ports]
        results = [{"execution_id": identifier, "status": "NOT_RUN"}
                   for port in ports for identifier in port["execution_ids"]]
        library = None
        library_ready = False
        if args.test_library:
            library = args.output / "OriginalTests.kklib"
            code = execute(base + ["--emit", "library", "-m", "KioOriginalTests"] + sources + ["-o", str(library)],
                           args.output, "library-compile", args.compile_timeout, environment)
            summary["library_compile_exitcode"] = code
            library_ready = code == 0
            if library_ready:
                summary["test_library_sha256"] = tree_hash(library)
            command = base + ["-I", str(library), str(driver), "-o", str(binary)]
        else:
            command = base + sources + [str(driver), "-o", str(binary)]
        if not args.test_library or library_ready:
            code = execute(command, args.output, "compile", args.compile_timeout, environment)
            summary["compile_exitcode"] = code
        if code == 0:
            summary["executable_sha256"] = sha256(binary)
            code = execute([str(binary)], args.output, "run", args.run_timeout)
            summary["run_exitcode"] = code
            results = parse_suite_results((args.output / "run.stdout").read_text(), ports)
            if sha256(binary) != summary["executable_sha256"]:
                raise ValueError("candidate executable changed during execution")
        for record in lock["upstream_files"]:
            verify_file(args.upstream / record["path"], record)
        if inputs() != before or (library_ready and tree_hash(library) != summary["test_library_sha256"]):
            raise ValueError("candidate inputs changed during execution")
        (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        summary.update({"counts": dict(collections.Counter(row["status"] for row in results)),
                        "inputs_unchanged": True,
                        "candidate_executions": sum(row["status"] in {"PASS", "FAIL"} for row in results)})
        summary["status"] = "PASS" if code == 0 and len(results) == count and all(row["status"] == "PASS" for row in results) else "FAIL"
        return 0 if summary["status"] == "PASS" else 1
    except (OSError, ValueError, KeyError) as error:
        summary.update({"status": "ERROR", "error": str(error)})
        return 1
    finally:
        (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    sys.exit(main())
