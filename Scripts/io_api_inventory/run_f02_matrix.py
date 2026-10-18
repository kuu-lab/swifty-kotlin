#!/usr/bin/env python3
"""Run fresh CLI processes for source, bundled artifact and user-library lanes.

Every lane has O0/O2, isolated cwd/TMPDIR/cache, byte-exact output checks and
immutable artifact receipts. A selected passing subset is never issue completion.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from generate_f02_consumers import generate
from generate import LOCAL_PROBE_EVIDENCE_CASES, local_probe_execution_id

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LANES = [(route, optimization) for route in ("source", "stdlib-library", "producer-consumer")
         for optimization in ("O0", "O2")]
# The reference compiler is pinned to Kotlin 2.3.10; KSwiftK currently emits
# artifacts with its product language version, Kotlin 2.4.20.
CANDIDATE_KOTLIN_LANGUAGE_VERSION = "2.4.20"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(path: Path) -> dict[str, str]:
    return {str(item.relative_to(path)): sha(item) for item in sorted(path.rglob("*"))
            if item.is_file() and "__pycache__" not in item.parts}


def save(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def execute(command: list[str], directory: Path, stage: str, timeout: float,
            environment: dict[str, str] | None = None) -> int:
    workspace = directory / (stage + "-work")
    workspace.mkdir()
    temporary = workspace / "tmp"
    temporary.mkdir()
    overrides = {"TMPDIR": str(temporary) + "/", "KSWIFTK_STDLIB_CACHE_DIR": str(workspace / "stdlib-cache"),
                 "KSWIFTK_PACKAGE_ROOT": str(ROOT), **(environment or {})}
    receipt = {"command": command, "cwd": str(workspace), "environment": overrides,
               "deadline_seconds": timeout, "status": "RUNNING"}
    prefix = directory / stage
    save(prefix.with_suffix(".json"), receipt)
    started = time.monotonic()
    with prefix.with_suffix(".stdout").open("wb") as stdout, prefix.with_suffix(".stderr").open("wb") as stderr:
        process = subprocess.Popen(command, cwd=workspace, env={**os.environ, **overrides},
                                   stdout=stdout, stderr=stderr, start_new_session=True)
        receipt.update(pid=process.pid, pgid=process.pid)
        save(prefix.with_suffix(".json"), receipt)
        try:
            process.wait(timeout=timeout)
            receipt["status"] = "EXITED"
        except subprocess.TimeoutExpired:
            receipt["status"] = "TIMEOUT"
            for sig in (signal.SIGTERM, signal.SIGKILL):
                try: os.killpg(process.pid, sig)
                except ProcessLookupError: pass
                try: process.wait(timeout=2)
                except subprocess.TimeoutExpired: pass
            process.wait()
    receipt.update(exitcode=process.returncode, seconds=time.monotonic() - started,
                   stdout_sha256=sha(prefix.with_suffix(".stdout")), stderr_sha256=sha(prefix.with_suffix(".stderr")))
    save(prefix.with_suffix(".json"), receipt)
    if receipt["status"] != "EXITED": return 124
    return process.returncode


def require_stage(command: list[str], directory: Path, stage: str, timeout: float,
                  environment: dict[str, str] | None = None) -> None:
    if execute(command, directory, stage, timeout, environment) != 0:
        raise RuntimeError(f"failed stage: {directory / stage}; raw streams retained")


def visibility_rejection_passed(directory: Path, stage: str, exit_code: int | None = None) -> bool:
    receipt_path = directory / f"{stage}.json"
    diagnostic_path = directory / f"{stage}.stderr"
    if not receipt_path.is_file() or not diagnostic_path.is_file():
        return False
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    actual_exit_code = receipt.get("exitcode") if exit_code is None else exit_code
    diagnostic = diagnostic_path.read_text(encoding="utf-8", errors="replace")
    return (
        receipt.get("status") == "EXITED"
        and type(actual_exit_code) is int
        and actual_exit_code != 0
        and "dataAsByteArray" in diagnostic
        and re.search(r"internal|visibility|visible", diagnostic, re.IGNORECASE) is not None
    )


def require_visibility_rejection(command: list[str], directory: Path, stage: str, timeout: float,
                                 environment: dict[str, str] | None = None) -> None:
    exit_code = execute(command, directory, stage, timeout, environment)
    if not visibility_rejection_passed(directory, stage, exit_code):
        raise RuntimeError(f"internal consumer unexpectedly compiled or did not exit: {directory / stage}")


def verify_segment_data_as_byte_array_source_metadata() -> dict:
    source = ROOT / "Sources/CompilerCore/Stdlib/kotlinx/io/Segment.kt"
    contents = source.read_text(encoding="utf-8")
    declaration = re.search(
        r"(?P<annotations>(?:^[ \t]*@[^\n]*\n)+)^[ \t]*internal fun dataAsByteArray\("
        r"(?P<parameters>[^)]*)\): (?P<return_type>[A-Za-z0-9_.]+)",
        contents,
        re.MULTILINE,
    )
    if declaration is None:
        raise RuntimeError("candidate Segment.dataAsByteArray declaration is missing")
    annotation_names = {
        annotation.rsplit(".", 1)[-1]
        for annotation in re.findall(r"^[ \t]*@([\w.]+)", declaration.group("annotations"), re.MULTILINE)
    }
    if (declaration.group("parameters") != "readOnly: Boolean"
            or declaration.group("return_type") != "ByteArray"
            or not {"PublishedApi", "JvmSynthetic"}.issubset(annotation_names)):
        raise RuntimeError("candidate Segment.dataAsByteArray source metadata does not match its ABI row")
    return {
        "status": "PASS",
        "exit_code": 0,
        "method": "source-metadata",
        "source_path": str(source.relative_to(ROOT)),
        "source_sha256": sha(source),
        "annotations": sorted(annotation_names),
    }


def local_probe_execution(case_id: str, lane: str, candidate_sha: str, reference_commit: str,
                          subject: str, result: str) -> dict:
    spec = LOCAL_PROBE_EVIDENCE_CASES[case_id]
    return {
        "execution_id": local_probe_execution_id(candidate_sha, reference_commit, case_id, lane, subject),
        "result": result,
        "exit_code": 0 if result == "PASS" else 1,
        "method": spec["methods"][subject],
    }


def segment_local_probe_case_ids(lane: str) -> list[str]:
    return [
        case_id
        for case_id, spec in LOCAL_PROBE_EVIDENCE_CASES.items()
        if case_id.endswith(("#internal-view", "#internal-visibility")) and lane in spec["lanes"]
    ]


def packaged(raw: bytes, package: str) -> bytes:
    if re.search(rb"^package\s", raw, re.MULTILINE):
        raise ValueError("only unqualified fixtures may receive a package insertion")
    # All fixture headers contain imports. Insertion before the first import
    # follows complete multiline @file annotations and preserves every body byte.
    match = re.search(rb"^import\s", raw, re.MULTILINE)
    if not match: raise ValueError("package insertion requires a fixture import header")
    index = match.start()
    return raw[:index] + ("package " + package + "\n").encode() + raw[index:]


def scenarios() -> list[dict]:
    cases = [{"id": "ledger-jvm", "producer": [HERE / "f02_consumers/Producer.kt"],
              "consumer": HERE / "f02_consumers/Consumer.kt", "entry": "f02consumer.main",
              "jvm_class": "f02consumer.ConsumerKt", "reference": "jvm", "ledger": True},
             {"id": "library-boundary", "producer": [HERE / "f02_boundary/Producer.kt"],
              "consumer": HERE / "f02_boundary/Consumer.kt", "entry": "f02boundaryconsumer.main",
              "jvm_class": "f02boundaryconsumer.ConsumerKt", "reference": "jvm"}]
    cases.append({"id": "segment-data-as-byte-array",
                  "fixture": ROOT / "Scripts/io_api_inventory/probes/segment_data_as_byte_array.kt",
                  "negative_fixture": ROOT / "Scripts/io_api_inventory/probes/segment_data_as_byte_array_negative.kt",
                  "reference_probe": ROOT / "Scripts/io_api_inventory/probes/segment_data_as_byte_array_jvm_abi.kt",
                  "entry": "f02consumer.main", "jvm_class": "f02consumer.ConsumerKt",
                  "reference_class": "f02jvmabi.SegmentDataAsByteArrayJvmAbi", "reference": "jvm"})
    fixtures = sorted((ROOT / "Scripts/diff_cases").glob("kotlinx_io*.kt"))
    cases.append({"id": "diff-consumers", "fixtures": fixtures, "reference": "jvm",
                  "entry": "f02corpusconsumer.main", "jvm_class": "f02corpusconsumer.ConsumerKt"})
    cases.append({"id": "deprecated-path-source-sink",
                  "fixture": ROOT / "Scripts/diff_cases/kotlinx_io_file_legacy_suppressed.kt",
                  "reference": "jvm"})
    base = ROOT / "Tests/CompilerBackendTests/Fixtures"
    cases += [
        {"id": "buffer-boundaries", "producer": [base / "IOBuffer1729/BufferBoundaries.kt"],
         "consumer": base / "IOBuffer1729/Consumer.kt", "entry": "kuu1729consumer.main",
         "expected": base / "IOBuffer1729/reference.stdout", "reference": "pinned-JVM"},
        {"id": "segment-read-context-impl", "producer": [base / "IOSegmentReadContextImpl2590/Producer.kt"],
         "consumer": base / "IOSegmentReadContextImpl2590/Consumer.kt", "entry": "kuu2590consumer.main",
         "jvm_class": "kuu2590consumer.ConsumerKt", "reference": "jvm", "friend_io_artifacts": True,
         "jvm_abi_probe": HERE / "f02_consumers/SegmentReadContextAbiProbe.java"},
        {"id": "buffering-contracts", "producer": [base / "IOBuffering1730/BufferingContracts.kt"],
         "consumer": base / "IOBuffering1730/Consumer.kt", "entry": "kuu1730consumer.main",
         "expected": base / "IOBuffering1730/reference.stdout", "reference": "pinned-JVM"},
        {"id": "native-eof-contracts", "producer": [base / "IOBuffering1730/EOFExceptionContracts.kt"],
         "consumer": base / "IOBuffering1730/EOFConsumer.kt", "entry": "kuu1730eofconsumer.main",
         "expected": base / "IOBuffering1730/eof-contract.expected.stdout", "reference": "declaration-contract"},
        {"id": "numeric-contracts", "producer": sorted((base / "IONumeric1731/Originals").glob("*.kt"))
             + sorted((base / "IONumeric1731/Boundaries").glob("*.kt")),
         "consumer": base / "IONumeric1731/Consumer.kt", "entry": "kuu1731integration.driver.main",
         "expected": base / "IONumeric1731/reference.stdout", "reference": "pinned-separate-JVM"},
        {"id": "apple-public", "producer": [base / "IOApple1763/PublicProducer.kt", base / "IOApple1763/ErrorAndPartialContracts.kt"],
         "consumer": base / "IOApple1763/PublicConsumer.kt", "entry": "kuu1763publicconsumer.main",
         "expected": base / "IOApple1763/public.expected.stdout", "reference": "declaration-contract", "host": "darwin"},
    ]
    apple = base / "IOApple1763"
    pins = json.loads((apple / "originals-provenance.json").read_text())
    cases.append({"id": "apple-original25", "producer": [apple / name for name in pins["producer"]],
                  "consumer": apple / pins["consumer"], "entry": pins["entry"],
                  "expected": apple / pins["expected"], "provenance": apple / "originals-provenance.json",
                  "reference": "pinned-Native-derived-original-assertions", "host": "darwin"})
    return cases


def prepare(case: dict, directory: Path) -> tuple[list[Path], Path]:
    sources = directory / "inputs"
    sources.mkdir()
    if "groups" in case:
        producers = []
        consumers = sources / "consumers"
        consumers.mkdir()
        driver = ["package f02allconsumer", "fun main() {"]
        for index, group in enumerate(case["groups"]):
            part = directory / f"part{index:03d}"
            part.mkdir()
            part_producers, part_consumer = prepare(group, part)
            for source_index, path in enumerate(part_producers):
                destination = sources / f"G{index:03d}P{source_index:03d}.kt"
                destination.write_bytes(path.read_bytes())
                producers.append(destination)
            destination = consumers / f"C{index:03d}.kt"
            destination.write_bytes(part_consumer.read_bytes())
            driver += [f'    println("BEGIN-CASE:{group["id"]}")',
                       "    try {", f'        {group.get("entry", "f02consumer.main")}()',
                       "    } catch (failure: Throwable) {",
                       f'        println("UNHANDLED-CASE:{group["id"]}:" + failure::class.simpleName + ":" + failure.message)',
                       "    }",
                       f'    println("END-CASE:{group["id"]}")']
        driver += ["}", ""]
        consumer = sources / "Consumer.kt"
        consumer.write_text("\n".join(driver))
        return producers, consumer
    if "fixtures" in case:
        producers = []
        driver = ["package f02corpusconsumer", "fun main() {"]
        for index, source in enumerate(case["fixtures"]):
            if b"SKIP-DIFF" in source.read_bytes(): raise ValueError("a skipped fixture needs an explicit disposition")
            package = f"f02fixture{index}"
            producer = sources / f"Fixture{index:03d}.kt"
            producer.write_bytes(packaged(source.read_bytes(), package))
            producers.append(producer)
            driver += [f'    println("BEGIN-FIXTURE:{source.stem}")', "    try {", f"        {package}.main()",
                       "    } catch (failure: Throwable) {",
                       f'        println("UNHANDLED-FIXTURE:{source.stem}:" + failure::class.simpleName + ":" + failure.message)',
                       "    }",
                       f'    println("END-FIXTURE:{source.stem}")']
        driver += ["}", ""]
        consumer = sources / "Consumer.kt"
        consumer.write_text("\n".join(driver))
        return producers, consumer
    if "fixture" in case:
        producer = sources / "Producer.kt"
        producer.write_bytes(packaged(case["fixture"].read_bytes(), "f02fixture"))
        consumer = sources / "Consumer.kt"
        consumer.write_text("package f02consumer\nfun main() { f02fixture.main() }\n")
        return [producer], consumer
    producers = []
    for index, source in enumerate(case["producer"]):
        destination = sources / f"P{index:03d}_{source.name}"
        destination.write_bytes(source.read_bytes())
        producers.append(destination)
    consumer = sources / "Consumer.kt"
    consumer.write_bytes(case["consumer"].read_bytes())
    return producers, consumer


def check_ledger_events(stdout: bytes, manifest: dict) -> None:
    for marker in (b"BEGIN:", b"END:", b"CALL:", b"CALL-END:"):
        observed = [line[len(marker):].decode() for line in stdout.splitlines() if line.startswith(marker)]
        expected = manifest["required_call_ids"] if marker.startswith(b"CALL") else manifest["paired_source_rows"]
        if observed != expected:
            raise RuntimeError(f"missing, duplicate or reordered ledger {marker!r} events")


def reference_friend_args(case: dict, io_jars: list[Path]) -> list[str]:
    if not case.get("friend_io_artifacts"):
        return []
    return ["-Xfriend-paths=" + ",".join(map(str, io_jars))]


def batch_group_stdout(stdout: bytes, identifier: str) -> bytes:
    lines = stdout.splitlines(keepends=True)
    begin = b"BEGIN-CASE:" + identifier.encode()
    end = b"END-CASE:" + identifier.encode()
    starts = [index for index, line in enumerate(lines) if line.rstrip(b"\r\n") == begin]
    stops = [index for index, line in enumerate(lines) if line.rstrip(b"\r\n") == end]
    if len(starts) != 1 or len(stops) != 1 or starts[0] >= stops[0]:
        raise RuntimeError(f"missing, duplicate or reordered batch group: {identifier}")
    return b"".join(lines[starts[0] + 1:stops[0]])


def reject_unhandled_events(stdout: bytes) -> None:
    for line in stdout.splitlines():
        if line.startswith((b"UNHANDLED-FIXTURE:", b"UNHANDLED-CASE:")):
            raise RuntimeError("incomplete fixture execution: " + line.decode(errors="replace"))


def normalized_paths(stdout: bytes, workspace: Path) -> bytes:
    # Only the owned execution paths differ between lanes. Preserve path suffixes
    # and every other byte (including errors, state and scalar/hash values).
    paths = [(workspace / "tmp", b"<tmp>"), (workspace, b"<work>")]
    # Foundation's NSTemporaryDirectory() can return the host user temp directory
    # even when TMPDIR is isolated for the process. Map that root to the lane temp.
    host_temporary_directory = Path(tempfile.gettempdir())
    shared_temporary_directory = Path("/tmp").resolve()
    if (host_temporary_directory.resolve() != shared_temporary_directory
            and host_temporary_directory.resolve() not in (workspace.resolve(), (workspace / "tmp").resolve())):
        paths.append((host_temporary_directory, b"<tmp>"))
    for path, label in paths:
        variants = {str(path), str(path.resolve())}
        if str(path).startswith("/private/tmp/"): variants.add(str(path).removeprefix("/private"))
        for value in sorted(variants, key=len, reverse=True): stdout = stdout.replace(value.encode(), label)
    return stdout


def run_lane(case: dict, compiler: Path, stdlib: Path, expected: bytes, directory: Path,
             route: str, optimization: str, timeout: float) -> dict:
    directory.mkdir()
    (directory / "expected.stdout").write_bytes(expected)
    producers, consumer = prepare(case, directory)
    consumer_paths = [consumer, *sorted((directory / "inputs/consumers").glob("*.kt"))]
    inputs_before = snapshot(directory / "inputs")
    stdlib_before = snapshot(stdlib)
    base = [str(compiler), "-" + optimization, "--no-incremental"]
    base += ["--stdlib-from-source"] if route == "source" else ["--stdlib-library", str(stdlib)]
    if case.get("negative_fixture"):
        negative_directory = directory / "negative-visibility"
        negative_directory.mkdir()
        negative_artifact = negative_directory / "consumer.kklib"
        require_visibility_rejection(
            base + ["--emit", "library", "-m", "F02VisibilityNegative",
                    str(case["negative_fixture"]), "-o", str(negative_artifact)],
            negative_directory, "candidate", timeout)
    artifact = None
    artifact_before = None
    if route == "producer-consumer":
        artifact = directory / "Producer.kklib"
        require_stage(base + ["--emit", "library", "-m", "F02Producer", *map(str, producers), "-o", str(artifact)],
                      directory, "producer", timeout)
        artifact_before = snapshot(artifact)
        if not artifact_before.get("metadata.bin") or not any(name.startswith("objects/") for name in artifact_before):
            raise RuntimeError("producer needs actual metadata and object files")
        # A consumer cannot silently recompile the producer from its input path.
        for path in producers: path.rename(path.with_suffix(".kt.evidence"))
        sources = list(map(str, consumer_paths))
        imports = ["-I", str(artifact)]
    else:
        sources = [*map(str, producers), *map(str, consumer_paths)]
        imports = []
    binary = directory / "candidate"
    entry = case.get("entry", "f02consumer.main")
    require_stage(base + imports + ["--entry-point", entry, *sources, "-o", str(binary)], directory, "consumer", timeout)
    require_stage([str(binary)], directory, "run", 30)
    stdout = (directory / "run.stdout").read_bytes()
    stderr = (directory / "run.stderr").read_bytes()
    observed = normalized_paths(stdout, directory / "run-work")
    reject_unhandled_events(expected)
    reject_unhandled_events(observed)
    if stderr or observed != expected:
        raise RuntimeError(f"byte difference or runtime stderr: {directory}")
    if case.get("ledger"):
        check_ledger_events(stdout, json.loads((HERE / "f02_consumers/manifest.json").read_text()))
    for group in case.get("groups", []):
        if group.get("ledger"):
            check_ledger_events(batch_group_stdout(stdout, group["id"]),
                                json.loads((HERE / "f02_consumers/manifest.json").read_text()))
    if "fixtures" in case:
        for prefix in (b"BEGIN-FIXTURE:", b"END-FIXTURE:"):
            actual = [line[len(prefix):].decode() for line in stdout.splitlines() if line.startswith(prefix)]
            if actual != [path.stem for path in case["fixtures"]]: raise RuntimeError("fixture execution missing/duplicated/reordered")
    if snapshot(stdlib) != stdlib_before or (artifact and snapshot(artifact) != artifact_before):
        raise RuntimeError("artifact changed during producer/consumer execution")
    producer_names = {str(path.relative_to(directory / "inputs")) for path in producers}
    expected_inputs = {name + ".evidence" if route == "producer-consumer" and name in producer_names else name: digest
                       for name, digest in inputs_before.items()}
    if snapshot(directory / "inputs") != expected_inputs: raise RuntimeError("staged inputs changed")
    return {"status": "PASS", "route": route, "optimization": optimization,
            "stdlib_files_sha256": stdlib_before, "producer_files_sha256": artifact_before,
            "inputs_sha256": inputs_before, "executable_sha256": sha(binary), "stdout_sha256": sha(directory / "run.stdout"),
            "normalized_stdout_sha256": hashlib.sha256(observed).hexdigest(),
            "reference_kind": case["reference"], "compiler_processes_separated": route == "producer-consumer"}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--kotlin-home", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True)
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--stdlib-library", type=Path, help="explicit supplied artifact; freshness is not inferred from its path")
    parser.add_argument("--case", action="append", help="explicit subset; default is all dedicated consumers")
    parser.add_argument("--separate-cases", action="store_true", help="compile each case separately; default batches selected cases in every lane")
    parser.add_argument("--compile-timeout", type=float, default=600)
    args = parser.parse_args(argv)
    if not math.isfinite(args.compile_timeout) or args.compile_timeout <= 0: parser.error("finite positive timeout required")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    compiler = args.compiler.resolve()
    all_scenarios = scenarios()
    selected = all_scenarios
    if args.case:
        identifiers = {case["id"] for case in selected}
        if len(set(args.case)) != len(args.case) or set(args.case) - identifiers: parser.error("unknown/duplicate case")
        selected = [case for case in selected if case["id"] in args.case]
    summary = {"status": "RUNNING", "selected_cases": [case["id"] for case in selected],
               "expected_case_ids": [case["id"] for case in all_scenarios], "lanes": LANES,
               "subset": bool(args.case), "issue_complete": False, "results": [], "compiler_sha256": sha(compiler),
               "workspace_git_sha": subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip(),
               "dirty_patch_sha256": hashlib.sha256(subprocess.check_output(["git", "-C", str(ROOT), "diff", "HEAD"])).hexdigest(),
               "local_probe_executions": [],
               "runtime_cache_provenance": "source and manifest-validated object hashes; not a clean Runtime rebuild"}
    try:
        provenance = [Path(__file__), HERE / "generate_f02_consumers.py", HERE / "generate_f01_consumers.py",
                      HERE / "api-inventory.tsv", HERE / "source-declarations.json", HERE / "upstream-lock.json",
                      ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json", ROOT / "Package.swift"]
        provenance += sorted((HERE / "f02_consumers").glob("*")) + sorted((HERE / "f02_boundary").glob("*.kt"))
        summary["harness_files_sha256"] = {str(path.relative_to(ROOT)): sha(path) for path in provenance if path.is_file()}
        scenario_inputs = {path for case in selected for path in case.get("producer", []) + case.get("fixtures", [])}
        scenario_inputs |= {case[key] for case in selected for key in (
            "consumer", "expected", "fixture", "negative_fixture", "reference_probe", "provenance", "jvm_abi_probe"
        ) if key in case}
        summary["scenario_files_sha256"] = {str(path.relative_to(ROOT)): sha(path) for path in sorted(scenario_inputs)}
        resources = next((path for path in (
            compiler.parent / "KSwiftK_CompilerCore.bundle/Contents/Resources",
            compiler.parent / "KSwiftK_CompilerCore.bundle",
            compiler.parent / "KSwiftK_CompilerCore.resources",
        ) if (path / "Stdlib").is_dir()), None)
        if resources is None: raise RuntimeError("actual compiler resource bundle required")
        dependencies = [resources, ROOT / "Sources/CompilerCore", ROOT / "Sources/CompilerBackend",
                        ROOT / "Sources/KSwiftKCLI", ROOT / "Sources/Runtime", ROOT / "Sources/RuntimeABI"]
        dependencies_before = {str(path): snapshot(path) for path in dependencies}
        summary["source_and_resource_files_sha256"] = dependencies_before
        for name, contents in generate().items():
            if (HERE / "f02_consumers" / name).read_text() != contents: raise RuntimeError("regenerate F02 consumers first")
        lock = json.loads((ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json").read_text())
        target_probe_selected = any(case["id"] == "segment-data-as-byte-array" for case in selected)
        candidate_source_metadata = None
        if target_probe_selected:
            candidate_source_metadata = verify_segment_data_as_byte_array_source_metadata()
            summary["candidate_source_metadata_assertion"] = candidate_source_metadata
        for record in lock["sdk_files"]:
            if sha(args.kotlin_home / record["path"]) != record["sha256"]: raise RuntimeError("reference SDK hash mismatch")
        jars = []
        for record in lock["jvm_artifacts"]:
            if "kotlinx-io-" in record["url"]:
                jar = (args.dependencies / record["url"].rsplit("/", 1)[1]).resolve()
                if sha(jar) != record["sha256"]: raise RuntimeError("reference IO jar hash mismatch")
                jars.append(jar)
        reference_tools = [args.java.resolve()]
        if any("jvm_abi_probe" in case for case in selected):
            reference_tools.append(args.java.resolve().parent / "javac")
        summary["reference_sha256"] = {str(path): sha(path) for path in [*jars, *reference_tools]}
        require_stage([str(args.java.resolve()), "-version"], output, "java-version", 30)
        if not re.search(rb'version "21[.\"]', (output / "java-version.stderr").read_bytes()):
            raise RuntimeError("reference requires Java 21")
        stdlib = args.stdlib_library.resolve() if args.stdlib_library else output / "KSwiftKStdlib.kklib"
        if args.stdlib_library:
            summary["stdlib_origin"] = "explicit supplied artifact; source lanes compare current resource bodies independently"
        else:
            require_stage([str(compiler), "--stdlib-only", "--no-incremental", "-o", str(stdlib)], output, "stdlib", args.compile_timeout)
            summary["stdlib_origin"] = "fresh CLI --stdlib-only process in this run"
        manifest = json.loads((stdlib / "manifest.json").read_text())
        if (manifest.get("moduleName") != "KSwiftKStdlib"
                or manifest.get("kotlinLanguageVersion") != CANDIDATE_KOTLIN_LANGUAGE_VERSION):
            raise RuntimeError("stdlib artifact module/language mismatch")
        summary["stdlib_files_sha256"] = snapshot(stdlib)
        def record_lane(case: dict, expected: bytes, directory: Path, route: str, optimization: str) -> None:
            print(f"RUN {case['id']} {route} {optimization}", flush=True)
            try:
                result = run_lane(case, compiler, stdlib, expected, directory, route, optimization, args.compile_timeout)
            except Exception as error:
                result = {"status": "FAIL", "route": route, "optimization": optimization,
                          "error": str(error), "evidence_directory": str(directory)}
            if case["id"] == "segment-data-as-byte-array":
                lane = f"{route}-{optimization}"
                for case_id in segment_local_probe_case_ids(lane):
                    candidate_result = result.get("status", "FAIL")
                    if case_id.endswith("#internal-visibility"):
                        candidate_result = (
                            "PASS" if visibility_rejection_passed(directory / "negative-visibility", "candidate")
                            else "FAIL"
                        )
                    summary["local_probe_executions"].append({
                        "case_id": case_id,
                        "lane": lane,
                        "reference": local_probe_execution(
                            case_id, lane, summary["workspace_git_sha"], lock["commit"], "reference", "PASS"
                        ),
                        "candidate": local_probe_execution(
                            case_id, lane, summary["workspace_git_sha"], lock["commit"], "candidate",
                            candidate_result,
                        ),
                    })
            summary["results"].append({"case": case["id"], **result})
            save(output / "summary.json", summary)
            print(f"{result['status']} {case['id']} {route} {optimization}", flush=True)

        expectations = []
        for case in selected:
            if case.get("host") and case["host"] != sys.platform: raise RuntimeError("Apple lane requires macOS")
            if case.get("provenance"):
                pins = json.loads(case["provenance"].read_text())
                for path in [*case["producer"], case["consumer"]]:
                    if sha(path) != pins["source_hashes"][path.name]: raise RuntimeError("pinned original source changed")
                if sha(case["expected"]) != pins["expected_sha256"]: raise RuntimeError("pinned original result changed")
            directory = output / case["id"]
            directory.mkdir()
            if case["reference"] == "jvm":
                producers, consumer = prepare(case, directory)
                jar = directory / "reference.jar"
                classpath = os.pathsep.join(map(str, jars))
                if case.get("negative_fixture"):
                    negative_directory = directory / "reference-negative"
                    negative_directory.mkdir()
                    require_visibility_rejection(
                        [str((args.kotlin_home / "bin/kotlinc").resolve()),
                         str(case["negative_fixture"]), "-classpath", classpath,
                         "-d", str(negative_directory / "consumer.jar")],
                        negative_directory, "reference", args.compile_timeout,
                        {"JAVA_HOME": str(args.java.resolve().parent.parent)})
                reference_sources = [*map(str, producers), str(consumer)]
                if case.get("reference_probe"):
                    reference_sources.append(str(case["reference_probe"]))
                reference_command = [str((args.kotlin_home / "bin/kotlinc").resolve()), *reference_sources,
                                     "-classpath", classpath, *reference_friend_args(case, jars), "-include-runtime", "-d", str(jar)]
                require_stage(reference_command, directory, "reference-compile", args.compile_timeout,
                              {"JAVA_HOME": str(args.java.resolve().parent.parent)})
                require_stage([str(args.java.resolve()), "-Djava.io.tmpdir=" + str(directory / "reference-run-work/tmp"),
                               "-cp", str(jar) + os.pathsep + classpath,
                               case.get("reference_class", case.get("jvm_class", "f02consumer.ConsumerKt"))], directory, "reference-run", 30)
                expected = normalized_paths((directory / "reference-run.stdout").read_bytes(), directory / "reference-run-work")
                reject_unhandled_events(expected)
                if (directory / "reference-run.stderr").read_bytes(): raise RuntimeError("reference runtime stderr")
                if case.get("ledger"): check_ledger_events(expected, json.loads((HERE / "f02_consumers/manifest.json").read_text()))
                if case["id"] == "segment-data-as-byte-array":
                    case_id = "local:Scripts/io_api_inventory/probes/segment_data_as_byte_array_jvm_abi.kt#jvm-descriptor"
                    lane = "jvm-descriptor"
                    summary["local_probe_executions"].append({
                        "case_id": case_id,
                        "lane": lane,
                        "reference": local_probe_execution(
                            case_id, lane, summary["workspace_git_sha"], lock["commit"], "reference", "PASS"
                        ),
                        "candidate": local_probe_execution(
                            case_id, lane, summary["workspace_git_sha"], lock["commit"], "candidate",
                            candidate_source_metadata["status"],
                        ),
                    })
                if "jvm_abi_probe" in case:
                    probe_classes = directory / "jvm-abi-probe-classes"
                    probe_classes.mkdir()
                    javac = args.java.resolve().parent / "javac"
                    require_stage([str(javac), "-d", str(probe_classes), str(case["jvm_abi_probe"])],
                                  directory, "jvm-abi-compile", args.compile_timeout)
                    require_stage([str(args.java.resolve()), "-cp", os.pathsep.join(
                        map(str, [probe_classes, jar, *jars])), "SegmentReadContextAbiProbe"],
                        directory, "jvm-abi-probe", 30)
            else:
                expected = case["expected"].read_bytes()
                reject_unhandled_events(expected)
            expectations.append(expected)
            if not args.separate_cases: continue
            for route, optimization in LANES:
                record_lane(case, expected, directory / f"{route}-{optimization}", route, optimization)
        if not args.separate_cases:
            summary["selected_reference_kinds"] = {case["id"]: case["reference"] for case in selected}
            # The original Native test module has helper declarations in actual
            # stdlib packages. Keep that module's failures independent so its
            # duplicate declarations cannot prevent unrelated consumers running.
            ordinary = [(case, value) for case, value in zip(selected, expectations, strict=True)
                        if case["id"] != "apple-original25"]
            batches = []
            if ordinary:
                batch = {"id": "all-selected", "groups": [case for case, _ in ordinary], "entry": "f02allconsumer.main",
                         "reference": "mixed; per-case reference_kind retained in selected_reference_kinds"}
                expected = b"".join(b"BEGIN-CASE:" + case["id"].encode() + b"\n" + value
                    + b"END-CASE:" + case["id"].encode() + b"\n" for case, value in ordinary)
                batches.append((batch, expected, output))
            batches += [(case, value, output / case["id"]) for case, value in zip(selected, expectations, strict=True)
                        if case["id"] == "apple-original25"]
            for case, expected, directory in batches:
                for route, optimization in LANES:
                    record_lane(case, expected, directory / f"{route}-{optimization}", route, optimization)
        if sha(compiler) != summary["compiler_sha256"]: raise RuntimeError("compiler changed during execution")
        if snapshot(stdlib) != summary["stdlib_files_sha256"]:
            raise RuntimeError("stdlib artifact changed between matrix lanes")
        for key in ("harness_files_sha256", "scenario_files_sha256"):
            if any(sha(ROOT / name) != digest for name, digest in summary[key].items()):
                raise RuntimeError("harness or scenario inputs changed between matrix lanes")
        if {str(path): snapshot(path) for path in dependencies} != dependencies_before:
            raise RuntimeError("compiler resources or runtime/stdlib source inputs changed")
        summary["runtime_object_sha256"] = {str(path.relative_to(ROOT)): sha(path)
            for path in sorted((ROOT / ".runtime-build").rglob("*.o")) if path.is_file()}
        failures = [result for result in summary["results"] if result["status"] != "PASS"]
        summary["status"] = "FAILED_OR_INCOMPLETE" if failures else "SELECTED_MATRIX_PASS"
        if failures: summary["error"] = f"{len(failures)} selected lanes failed; raw evidence retained"
    except Exception as error:
        summary.update(status="FAILED_OR_INCOMPLETE", error=str(error))
        print(str(error), file=sys.stderr)
    save(output / "summary.json", summary)
    return 0 if summary["status"] == "SELECTED_MATRIX_PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
