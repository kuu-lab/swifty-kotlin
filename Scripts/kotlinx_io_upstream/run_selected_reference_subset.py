#!/usr/bin/env python3
"""Run selected, unchanged upstream test methods on pinned JVM or Native references.

This runner is for direct, parameterless test methods in one source file. It
compiles the original file with a generated main driver and invokes only the
selected catalog entries. It does not claim paired KSwiftK evidence.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import subprocess
import sys

from run_candidate_subset import IDENTIFIER, PREFIX, parse_events
from run_candidate_suites import make_selection_manifest, select_catalog_rows
from run_jvm_reference import HERE, execute, sha256, verify_file
from run_native_reference import verify_native_sdk


def prepare_selected_port(upstream: Path, rows: list[dict], lock: dict, output: Path) -> dict:
    if not rows:
        raise ValueError("selected reference suite has no locked execution IDs")
    suite = rows[0]["concrete_class"]
    if not all(IDENTIFIER.fullmatch(part) for part in suite.split(".")):
        raise ValueError("unsupported Kotlin class identifier")
    if any(row["concrete_class"] != suite or row["declaring_class"] != suite
           or row["parameter_types"] for row in rows):
        raise ValueError("selected reference methods must be direct parameterless methods")
    paths = {row["upstream_path"] for row in rows}
    if len(paths) != 1:
        raise ValueError("selected reference methods must have one original source file")
    path = paths.pop()
    record = next((row for row in lock["upstream_files"] if row["path"] == path), None)
    if record is None:
        raise ValueError("selected source is absent from reference lock")
    source = upstream / path
    verify_file(source, record)
    raw = source.read_bytes()
    text = raw.decode("utf-8")
    if re.search(r"^\s*@(?:[\w.]*\.)?(?:BeforeTest|AfterTest|BeforeEach|AfterEach|TempDir)\b",
                 text, re.MULTILINE):
        raise ValueError("test hooks require a lifecycle-aware reference driver")
    methods = [row["method_name"] for row in rows]
    identifiers = [row["execution_id"] for row in rows]
    if len(set(methods)) != len(rows) or len(set(identifiers)) != len(rows):
        raise ValueError("duplicate locked execution ID or method")
    for row in rows:
        method = row["method_name"]
        if not IDENTIFIER.fullmatch(method) or not re.search(
                r"\bfun\s+" + re.escape(method) + r"\s*\(\s*\)", text):
            raise ValueError("locked method is not an original parameterless source declaration")
        if row["git_blob_sha"] != record["git_blob_sha"]:
            raise ValueError("catalog/source blob mismatch")
        if not isinstance(row["execution_id"], str) or any(ch in row["execution_id"] for ch in "\r\n\0\""):
            raise ValueError("unsupported execution ID")

    port = output / source.name
    port.write_bytes(PREFIX + raw)
    token = "KIO_" + hashlib.sha256(raw + suite.encode()).hexdigest()[:24]
    driver = ["fun main() {"]
    for row in rows:
        identifier = json.dumps(row["execution_id"], ensure_ascii=True)
        method = row["method_name"]
        driver += [
            f"    println(\"{token} BEGIN \" + {identifier})",
            "    try {",
            f"        {suite}().{method}()",
            f"        println(\"{token} PASS \" + {identifier})",
            "    } catch (failure: Throwable) {",
            f"        println(\"{token} FAIL \" + {identifier})",
            f"        println(\"{token} EXCEPTION \" + failure::class.qualifiedName)",
            "    }",
        ]
    driver += ["}", ""]
    driver_path = output / "SelectedReferenceDriver.kt"
    driver_path.write_text("\n".join(driver), encoding="utf-8")
    return {
        "suite": suite,
        "source_path": path,
        "source_sha256": record["sha256"],
        "source_git_blob_sha": record["git_blob_sha"],
        "prefix_bytes": len(PREFIX),
        "original_bytes_preserved_as_suffix": port.read_bytes()[len(PREFIX):] == raw,
        "assertions_parameters_constructors_changed": False,
        "constructor_policy": "fresh original class instance per selected execution",
        "port_path": str(port.resolve()),
        "port_sha256": sha256(port),
        "driver_path": str(driver_path.resolve()),
        "driver_sha256": sha256(driver_path),
        "execution_ids": identifiers,
        "event_token": token,
    }


def verify_reference_files(upstream: Path, lock: dict) -> None:
    for row in lock["upstream_files"]:
        verify_file(upstream / row["path"], row)


def input_fingerprints(args: argparse.Namespace, lock_path: Path, lock: dict,
                       catalog_path: Path, port: dict) -> dict:
    verify_reference_files(args.upstream, lock)
    verify_file(catalog_path, {"sha256": lock[
        "jvm_execution_catalog_sha256" if args.target == "jvm" else "native_execution_catalog_sha256"]})
    verify_file(Path(port["port_path"]), {"sha256": port["port_sha256"]})
    verify_file(Path(port["driver_path"]), {"sha256": port["driver_sha256"]})
    compiler = args.kotlin_home / "bin" / ("kotlinc" if args.target == "jvm" else "konanc")
    values = {
        "reference_lock_sha256": sha256(lock_path),
        "catalog_sha256": sha256(catalog_path),
        "runner_sha256": sha256(Path(__file__)),
        "compiler_sha256": sha256(compiler),
        "java_sha256": sha256(args.java),
        "source_sha256": port["source_sha256"],
        "port_sha256": sha256(Path(port["port_path"])),
        "driver_sha256": sha256(Path(port["driver_path"])),
    }
    if args.target == "jvm":
        sdk_hashes = {}
        for row in lock["sdk_files"]:
            path = args.kotlin_home / row["path"]
            verify_file(path, row)
            sdk_hashes[row["path"]] = row["sha256"]
        dependency_hashes = {}
        for row in lock["jvm_artifacts"]:
            path = args.dependencies / row["url"].rsplit("/", 1)[1]
            verify_file(path, row)
            dependency_hashes[path.name] = row["sha256"]
        values.update({"sdk_files": sdk_hashes, "dependencies": dependency_hashes})
    else:
        archive_record = lock["native_compiler_archives"][args.target]
        sdk = verify_native_sdk(args.kotlin_home, args.compiler_archive, archive_record)
        dependency_hashes = {}
        for row in lock["native_artifacts"]:
            if args.target.replace("_", "") not in row["coordinate"]:
                continue
            path = args.dependencies / row["url"].rsplit("/", 1)[1]
            verify_file(path, row)
            dependency_hashes[path.name] = row["sha256"]
        sdk_record_hash = hashlib.sha256(json.dumps(sdk["files"], sort_keys=True,
                                                    separators=(",", ":")).encode()).hexdigest()
        values.update({"compiler_archive_sha256": archive_record["sha256"],
                       "installed_sdk_file_count": sdk["verified_file_count"],
                       "installed_sdk_files_sha256": sdk_record_hash,
                       "dependencies": dependency_hashes})
    return values


def catalog_for_target(target: str) -> tuple[Path, str | None]:
    if target == "jvm":
        return HERE / "jvm-executions.expected.json", None
    return HERE / "native-executions.expected.json", "macos"


def reference_rows(target: str, catalog: list[dict], source_ids: list[str]) -> list[dict]:
    selected = select_catalog_rows(catalog, None, None if target == "jvm" else "macos",
                                   source_function_ids=source_ids)
    if {row["upstream_id"] for row in selected} != set(source_ids):
        raise ValueError("selected reference execution catalog omits a requested source function")
    return selected


def prepare_jvm(args: argparse.Namespace, rows: list[dict], lock: dict,
                port: dict, selection: dict, summary: dict,
                lock_path: Path, catalog_path: Path) -> int:
    for row in lock["sdk_files"]:
        verify_file(args.kotlin_home / row["path"], row)
    args.dependencies.mkdir(parents=True, exist_ok=True)
    jars = []
    for artifact in lock["jvm_artifacts"]:
        path = args.dependencies / artifact["url"].rsplit("/", 1)[1]
        verify_file(path, artifact)
        jars.append(path.resolve())
    sdk = args.kotlin_home.resolve() / "lib"
    test_jars = [sdk / "kotlin-test.jar", sdk / "kotlin-test-junit5.jar"]
    for path in test_jars:
        if not path.is_file():
            raise ValueError(f"missing Kotlin test runtime: {path}")
    java_version_stage = "java-version"
    java_env = {"JAVACMD": str(args.java.resolve())}
    if execute([str(args.java.resolve()), "-version"], args.output, java_version_stage, 10):
        summary["status"] = "FAIL"
        return 1
    java_version = (args.output / f"{java_version_stage}.stderr").read_text()
    if not re.search(r'version "21[.\"]', java_version):
        raise ValueError("JVM reference requires Java 21")
    compiler = args.kotlin_home.resolve() / "bin/kotlinc"
    if execute([str(compiler), "-version"], args.output, "kotlin-version", 30, java_env):
        summary["status"] = "FAIL"
        return 1
    compiler_version = ((args.output / "kotlin-version.stderr").read_text()
                        + (args.output / "kotlin-version.stdout").read_text())
    if not re.search(r"kotlinc-jvm 2\.3\.10(?:\s|$)", compiler_version):
        raise ValueError("JVM reference requires Kotlin 2.3.10")

    io_jars = [path for path in jars if path.name.startswith("kotlinx-io-")]
    compile_classpath = jars + test_jars
    jar = args.output / "selected-upstream-samples.jar"
    common_source = port["port_path"]
    command = [str(compiler), port["port_path"], port["driver_path"],
        "-classpath", os.pathsep.join(map(str, compile_classpath)),
        "-Xmulti-platform", "-Xexpect-actual-classes", "-Xcommon-sources=" + common_source,
        "-Xfriend-paths=" + ",".join(map(str, io_jars)),
        "-opt-in=kotlinx.io.InternalIoApi", "-opt-in=kotlin.ExperimentalStdlibApi",
        "-XXLanguage:+UnnamedLocalVariables", "-include-runtime", "-d", str(jar)]
    summary["compiler_command"] = command
    if execute(command, args.output, "compile", args.compile_timeout, java_env):
        summary["compile_exitcode"] = json.loads((args.output / "compile.result.json").read_text())["exitcode"]
        summary["status"] = "FAIL"
        return 1
    summary["compile_exitcode"] = 0
    summary["executable_sha256"] = sha256(jar)
    summary["executable_path"] = str(jar.resolve())
    runtime_classpath = [jar, *jars, *test_jars]
    run_command = [str(args.java.resolve()), "-Xmx1024m", "-cp",
                   os.pathsep.join(map(str, runtime_classpath)), "SelectedReferenceDriverKt"]
    summary["run_command"] = run_command
    code = execute(run_command, args.output, "run", args.run_timeout)
    summary["run_exitcode"] = code
    return finish_results(args, rows, port, selection, summary, code, lock_path, lock,
                          catalog_path)


def prepare_native(args: argparse.Namespace, rows: list[dict], lock: dict,
                   port: dict, selection: dict, summary: dict,
                   lock_path: Path, catalog_path: Path) -> int:
    if platform.system() != "Darwin":
        raise ValueError("macOS Native references must run on macOS")
    requested_arch = "arm64" if args.target == "macos_arm64" else "x86_64"
    host_arch = "arm64" if platform.machine() in {"arm64", "aarch64"} else platform.machine()
    if host_arch != requested_arch:
        raise ValueError(f"Native reference target {args.target} does not match host {platform.machine()}")
    archive = args.compiler_archive
    archive_record = lock["native_compiler_archives"][args.target]
    verify_file(archive, archive_record)
    verify_native_sdk(args.kotlin_home, archive, archive_record)
    compiler = args.kotlin_home.resolve() / "bin/konanc"
    artifacts = [row for row in lock["native_artifacts"]
                 if args.target.replace("_", "") in row["coordinate"]]
    libraries = []
    for artifact in artifacts:
        path = args.dependencies / artifact["url"].rsplit("/", 1)[1]
        verify_file(path, artifact)
        libraries.append(path.resolve())
    temporary = args.output / "tmp"
    temporary.mkdir()
    args.konan_data.mkdir(parents=True, exist_ok=True)
    overrides = {
        "KONAN_DATA_DIR": str(args.konan_data.resolve()),
        "TMPDIR": str(temporary.resolve()),
        "JAVA_HOME": str(args.java.resolve().parent.parent),
        "JAVACMD": str(args.java.resolve()),
    }
    if execute([str(args.java.resolve()), "-version"], args.output, "java-version", 10):
        summary["status"] = "FAIL"
        return 1
    java_version = (args.output / "java-version.stderr").read_text()
    if not re.search(r'version "21[.\"]', java_version):
        raise ValueError("Native reference requires Java 21")
    if execute([str(compiler), "-version"], args.output, "kotlin-version", 30, overrides):
        summary["status"] = "FAIL"
        return 1
    compiler_version = ((args.output / "kotlin-version.stdout").read_text()
                        + (args.output / "kotlin-version.stderr").read_text())
    if not re.search(r"(?:Kotlin/Native|kotlinc-native)\s+2\.3\.10(?:\s|$)", compiler_version):
        raise ValueError("Native reference requires Kotlin/Native 2.3.10")
    flags = ["-target", args.target]
    for library in libraries:
        flags += ["-library", str(library)]
    source = port["port_path"]
    test_library = args.output / "selected-upstream-samples.klib"
    io_libraries = [str(path) for path in libraries if path.name.startswith("kotlinx-io-")]
    library_command = [str(compiler), source] + flags + [
        "-produce", "library", "-friend-modules", os.pathsep.join(io_libraries),
        "-Xmulti-platform", "-Xcommon-sources=" + source,
        "-opt-in=kotlinx.io.InternalIoApi", "-opt-in=kotlin.ExperimentalStdlibApi",
        "-XXLanguage:+UnnamedLocalVariables", "-o", str(test_library.resolve())]
    summary["compiler_command"] = library_command
    if execute(library_command, args.output, "compile", args.compile_timeout, overrides):
        summary["compile_exitcode"] = json.loads((args.output / "compile.result.json").read_text())["exitcode"]
        summary["status"] = "FAIL"
        return 1
    summary["compile_exitcode"] = 0
    summary["test_library_sha256"] = sha256(test_library)
    binary = args.output / "selected-upstream-samples.kexe"
    consumer_command = [str(compiler), port["driver_path"]] + flags + [
        "-library", str(test_library.resolve()), "-o", str(binary.resolve())]
    summary["consumer_command"] = consumer_command
    if execute(consumer_command, args.output, "link-consumer", args.compile_timeout, overrides):
        summary["consumer_exitcode"] = json.loads((args.output / "link-consumer.result.json").read_text())["exitcode"]
        summary["status"] = "FAIL"
        return 1
    summary["consumer_exitcode"] = 0
    summary["executable_sha256"] = sha256(binary)
    summary["executable_path"] = str(binary.resolve())
    run_command = [str(binary)]
    summary["run_command"] = run_command
    code = execute(run_command, args.output, "run", args.run_timeout, overrides)
    summary["run_exitcode"] = code
    return finish_results(args, rows, port, selection, summary, code, lock_path, lock,
                          catalog_path)


def finish_results(args: argparse.Namespace, rows: list[dict], port: dict,
                   selection: dict, summary: dict, code: int,
                   lock_path: Path, lock: dict, catalog_path: Path) -> int:
    before = summary["input_hashes"]
    after = input_fingerprints(args, lock_path, lock, catalog_path, port)
    if before != after:
        raise ValueError("reference inputs changed during execution")
    if sha256(Path(summary["executable_path"])) != summary["executable_sha256"]:
        raise ValueError("reference executable changed during execution")
    if args.target != "jvm":
        library = args.output / "selected-upstream-samples.klib"
        if sha256(library) != summary.get("test_library_sha256"):
            raise ValueError("reference test KLIB changed during execution")
    identifiers = port["execution_ids"]
    output = args.output / "run.stdout"
    results = parse_events(output.read_text(encoding="utf-8"), identifiers, port["event_token"])
    (args.output / "results.json").write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n",
                                             encoding="utf-8")
    counts = dict(collections.Counter(row["status"] for row in results))
    summary.update({
        "selected_execution_count": len(rows),
        "selected_execution_ids": identifiers,
        "counts": counts,
        "results_sha256": sha256(args.output / "results.json"),
        "inputs_unchanged": True,
    })
    all_pass = len(results) == len(rows) and all(row["status"] == "PASS" for row in results)
    summary["status"] = "PASS" if code == 0 and all_pass else "FAIL"
    return 0 if summary["status"] == "PASS" else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=("jvm", "macos_arm64", "macos_x64"), required=True)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--kotlin-home", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True)
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--source-function-id", action="append", required=True,
                        help="select a complete upstream source-function ID; may be repeated")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compiler-archive", type=Path,
                        help="required for macOS Native references")
    parser.add_argument("--konan-data", type=Path,
                        help="required for macOS Native references")
    parser.add_argument("--compile-timeout", type=float, default=300)
    parser.add_argument("--run-timeout", type=float, default=60)
    args = parser.parse_args(argv)
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    if (len(args.source_function_id) > 10 or len(set(args.source_function_id)) != len(args.source_function_id)
            or any(not value or value != value.strip() for value in args.source_function_id)):
        raise SystemExit("source function IDs must be nonempty, unique, and limited to ten")
    if any(not math.isfinite(value) or value <= 0 for value in [args.compile_timeout, args.run_timeout]):
        raise SystemExit("timeouts must be finite and positive")
    if args.target != "jvm" and (args.compiler_archive is None or args.konan_data is None):
        raise SystemExit("Native references require --compiler-archive and --konan-data")
    lock_path = HERE / "reference-lock.json"
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    catalog_path, native_target = catalog_for_target(args.target)
    catalog_lock_key = "jvm_execution_catalog_sha256" if args.target == "jvm" else "native_execution_catalog_sha256"
    summary = {
        "kind": "selected-upstream-reference",
        "target": args.target,
        "upstream_commit": lock["commit"],
        "kotlin": lock["kotlin"],
        "kotlinx_io": lock["kotlinx_io"],
        "reference_lock_sha256": sha256(lock_path),
        "catalog_sha256": sha256(catalog_path),
        "runner_sha256": sha256(Path(__file__)),
        "host": platform.platform(),
        "requested_source_function_ids": args.source_function_id,
        "candidate_disposition": "UNMAPPED",
        "paired_pass_count": 0,
    }
    try:
        verify_file(catalog_path, {"sha256": lock[catalog_lock_key]})
        verify_reference_files(args.upstream, lock)
        catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
        rows = reference_rows(args.target, catalog, args.source_function_id)
        suite_names = {row["concrete_class"] for row in rows}
        source_paths = {row["upstream_path"] for row in rows}
        if len(suite_names) != 1 or len(source_paths) != 1:
            raise ValueError("selected reference subset must be a direct suite from one source file")
        source_hashes = {record["path"]: record["sha256"] for record in lock["upstream_files"]}
        selection = make_selection_manifest(
            catalog, rows, native_target, "explicit-ids", args.source_function_id, [],
            sha256(catalog_path), source_file_sha256=source_hashes,
            upstream_commit=lock["commit"], reference_lock_sha256=sha256(lock_path))
        port = prepare_selected_port(args.upstream, rows, lock, args.output)
        selection["port"] = port
        input_hashes = input_fingerprints(args, lock_path, lock, catalog_path, port)
        selection["input_hashes"] = input_hashes
        summary["input_hashes"] = input_hashes
        selection_path = args.output / "selection.json"
        selection_path.write_text(json.dumps(selection, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        summary.update({
            "selection": selection,
            "selection_manifest": str(selection_path),
            "selection_manifest_sha256": sha256(selection_path),
            "selected_execution_count": len(rows),
            "selected_execution_ids": [row["execution_id"] for row in rows],
            "selected_source_function_count": len(selection["selected_source_function_ids"]),
            "source": port,
        })
        if args.target == "jvm":
            return prepare_jvm(args, rows, lock, port, selection, summary, lock_path, catalog_path)
        return prepare_native(args, rows, lock, port, selection, summary, lock_path, catalog_path)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        summary.update({"status": "ERROR", "error": str(error)})
        (args.output / "error.txt").write_text(str(error) + "\n", encoding="utf-8")
        print(f"selected reference subset: {error}", file=sys.stderr)
        return 2
    finally:
        (args.output / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n",
                                                   encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
