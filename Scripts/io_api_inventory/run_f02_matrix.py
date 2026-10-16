#!/usr/bin/env python3
"""Run fresh CLI processes for source, bundled artifact and user-library lanes.

Every lane has O0/O2, isolated cwd/TMPDIR/cache, byte-exact output checks and
immutable artifact receipts. A selected passing subset is never issue completion.
"""
from __future__ import annotations

import argparse
import csv
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
    fixtures = sorted((ROOT / "Scripts/diff_cases").glob("kotlinx_io*.kt"))
    cases.append({"id": "diff-consumers", "fixtures": fixtures, "reference": "jvm",
                  "entry": "f02corpusconsumer.main", "jvm_class": "f02corpusconsumer.ConsumerKt"})
    base = ROOT / "Tests/CompilerBackendTests/Fixtures"
    cases += [
        {"id": "buffer-boundaries", "producer": [base / "IOBuffer1729/BufferBoundaries.kt"],
         "consumer": base / "IOBuffer1729/Consumer.kt", "entry": "kuu1729consumer.main",
         "expected": base / "IOBuffer1729/reference.stdout", "reference": "pinned-JVM"},
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
    segment_is_empty = HERE / "probes/segment_is_empty"
    cases.append({"id": "segment-is-empty", "producer": [segment_is_empty / "Producer.kt"],
                  "consumer": segment_is_empty / "Consumer.kt",
                  "negative_consumer": segment_is_empty / "NegativeConsumer.kt",
                  "entry": "kuu2593.segmentisemptyconsumer.main",
                  "jvm_class": "kuu2593.segmentisemptyconsumer.ConsumerKt", "reference": "jvm",
                  "evidence_id_prefix": "io-probe:segment-is-empty",
                  "evidence_case_id": "Scripts/io_api_inventory/probes/segment_is_empty/Producer.kt#segmentIsEmptyProbe"})
    return cases


def run_cases_separately(selected: list[dict], requested: bool) -> bool:
    """Keep evidence-bearing API probes mapped to their individual execution IDs."""
    return requested or any(case.get("evidence_id_prefix") for case in selected)


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
    result = {"status": "PASS", "route": route, "optimization": optimization,
            "stdlib_files_sha256": stdlib_before, "producer_files_sha256": artifact_before,
            "inputs_sha256": inputs_before, "executable_sha256": sha(binary), "stdout_sha256": sha(directory / "run.stdout"),
            "output_line_count": len(stdout.splitlines()), "stdout_byte_count": len(stdout),
            "normalized_stdout_sha256": hashlib.sha256(observed).hexdigest(),
            "reference_kind": case["reference"], "compiler_processes_separated": route == "producer-consumer"}
    if case.get("evidence_id_prefix"):
        result["execution_id"] = f"{case['evidence_id_prefix']}:candidate:{route}-{optimization}"
    return result


def check_segment_is_empty_jvm_descriptor(javap: Path, core_jar: Path, output: Path) -> dict:
    case_id = "Scripts/io_api_inventory/run_f02_matrix.py#check_segment_is_empty_jvm_descriptor"
    javap_directory = output / "segment-is-empty-jvm-descriptor"
    javap_directory.mkdir()
    command = [str(javap), "-p", "-s", "-classpath", str(core_jar), "kotlinx.io.SegmentKt"]
    code = execute(command, javap_directory, "javap", 30)
    if code != 0:
        raise RuntimeError("javap failed for the pinned kotlinx-io JVM artifact")
    stdout = (javap_directory / "javap.stdout").read_bytes()
    text = stdout.decode("utf-8")
    method = re.search(
        r"(?m)^\s*public static final boolean isEmpty\(kotlinx\.io\.Segment\);\s*\n\s*descriptor: \(Lkotlinx/io/Segment;\)Z$",
        text,
    )
    if method is None:
        raise RuntimeError("pinned JVM SegmentKt lacks public static isEmpty(Segment):boolean")
    api_path = HERE / "upstream/kotlinx-io-0.9.1/core/api/kotlinx-io-core.api"
    api_text = api_path.read_text(encoding="utf-8")
    api_signature = "public static final fun isEmpty (Lkotlinx/io/Segment;)Z"
    if api_signature not in api_text:
        raise RuntimeError("pinned JVM API dump no longer records the SegmentKt isEmpty descriptor")
    ledger_path = HERE / "api-inventory.tsv"
    with ledger_path.open(encoding="utf-8", newline="") as stream:
        rows = [row for row in csv.DictReader(stream, delimiter="\t")
                if row.get("row_id") == "jvm-11b8ac13bf35acdc"]
    if len(rows) != 1:
        raise RuntimeError("SegmentKt JVM API row is missing or duplicated")
    row = rows[0]
    if (row["signature"] != api_signature or row["owner_issue"] != "KUU-2593"
            or "PublishedApi" not in row["annotations"]
            or row["status"] not in {"unverified", "verified"}):
        raise RuntimeError("generated SegmentKt JVM ledger row does not match the pinned declaration")
    return {
        "case_id": case_id,
        "reference": {"execution_id": "io-probe:segment-is-empty:jvm-descriptor:reference",
                      "result": "PASS", "exit_code": 0, "javap_stdout_sha256": hashlib.sha256(stdout).hexdigest(),
                      "api_dump_sha256": sha(api_path)},
        "candidate": {"execution_id": "io-probe:segment-is-empty:jvm-descriptor:candidate",
                      "result": "PASS", "exit_code": 0, "row_id": row["row_id"],
                      "signature": row["signature"], "owner_issue": row["owner_issue"]},
        "javap_command": command,
    }


def check_segment_is_empty_visibility(
    compiler: Path, stdlib: Path, negative_consumer: Path, kotlin_home: Path,
    java: Path, core_jar: Path, output: Path, timeout: float,
) -> dict:
    case_id = "Scripts/io_api_inventory/probes/segment_is_empty/NegativeConsumer.kt#segmentIsEmptyMustRemainInternal"
    reference_directory = output / "segment-is-empty-reference-visibility"
    candidate_directory = output / "segment-is-empty-candidate-visibility"
    reference_directory.mkdir()
    candidate_directory.mkdir()
    reference_jar = reference_directory / "negative.jar"
    reference_command = [str((kotlin_home / "bin/kotlinc").resolve()), str(negative_consumer),
                         "-classpath", str(core_jar), "-d", str(reference_jar)]
    reference_code = execute(reference_command, reference_directory, "compile", timeout,
                             {"JAVA_HOME": str(java.resolve().parent.parent)})
    candidate_output = candidate_directory / "negative"
    candidate_command = [str(compiler), "-O0", "--no-incremental", "--stdlib-library", str(stdlib),
                         str(negative_consumer), "-o", str(candidate_output)]
    candidate_code = execute(candidate_command, candidate_directory, "compile", timeout)
    results = {}
    for subject, code, directory, execution_id in (
        ("reference", reference_code, reference_directory, "io-probe:segment-is-empty:visibility:reference"),
        ("candidate", candidate_code, candidate_directory, "io-probe:segment-is-empty:visibility:candidate"),
    ):
        stdout = (directory / "compile.stdout").read_bytes()
        stderr = (directory / "compile.stderr").read_bytes()
        diagnostic = (stdout + stderr).decode("utf-8", errors="replace").lower()
        if code == 0 or "isempty" not in diagnostic or not any(
            marker in diagnostic for marker in ("internal", "invisible", "visibility")
        ):
            raise RuntimeError(f"{subject} compiler did not reject the unsuppressed internal isEmpty call")
        results[subject] = {"execution_id": execution_id, "result": "PASS", "exit_code": 0,
                            "rejection_exit_code": code,
                            "diagnostic_sha256": hashlib.sha256(stdout + stderr).hexdigest()}
    return {"case_id": case_id, **results,
            "commands": {"reference": reference_command, "candidate": candidate_command}}


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
    separate_cases = run_cases_separately(selected, args.separate_cases)
    summary = {"status": "RUNNING", "selected_cases": [case["id"] for case in selected],
               "expected_case_ids": [case["id"] for case in all_scenarios], "lanes": LANES,
               "subset": bool(args.case), "separate_cases": separate_cases,
               "issue_complete": False, "results": [], "compiler_sha256": sha(compiler),
               "workspace_git_sha": subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip(),
               "dirty_patch_sha256": hashlib.sha256(subprocess.check_output(["git", "-C", str(ROOT), "diff", "HEAD"])).hexdigest(),
               "runtime_cache_provenance": "source and manifest-validated object hashes; not a clean Runtime rebuild"}
    try:
        provenance = [Path(__file__), HERE / "generate_f02_consumers.py", HERE / "generate_f01_consumers.py",
                      HERE / "api-inventory.tsv", HERE / "source-declarations.json", HERE / "upstream-lock.json",
                      HERE / "api-probe-executions.json",
                      ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json", ROOT / "Package.swift"]
        provenance += sorted((HERE / "f02_consumers").glob("*")) + sorted((HERE / "f02_boundary").glob("*.kt"))
        summary["harness_files_sha256"] = {str(path.relative_to(ROOT)): sha(path) for path in provenance if path.is_file()}
        scenario_inputs = {path for case in selected for path in case.get("producer", []) + case.get("fixtures", [])}
        scenario_inputs |= {case[key] for case in selected for key in
                            ("consumer", "expected", "fixture", "provenance", "negative_consumer") if key in case}
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
        for record in lock["sdk_files"]:
            if sha(args.kotlin_home / record["path"]) != record["sha256"]: raise RuntimeError("reference SDK hash mismatch")
        jars = []
        for record in lock["jvm_artifacts"]:
            if "kotlinx-io-" in record["url"]:
                jar = (args.dependencies / record["url"].rsplit("/", 1)[1]).resolve()
                if sha(jar) != record["sha256"]: raise RuntimeError("reference IO jar hash mismatch")
                jars.append(jar)
        summary["reference_sha256"] = {str(path): sha(path) for path in [*jars, args.java.resolve()]}
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
        segment_case = next((case for case in selected if case["id"] == "segment-is-empty"), None)
        if segment_case is not None:
            core_jar = next((jar for jar in jars if jar.name.startswith("kotlinx-io-core-jvm-")), None)
            if core_jar is None:
                raise RuntimeError("the locked kotlinx-io core JVM artifact is required for Segment probes")
            javap = args.java.resolve().parent / "javap"
            if not javap.is_file():
                raise RuntimeError("javap from the locked Java 21 runtime is required for Segment ABI verification")
            descriptor = check_segment_is_empty_jvm_descriptor(javap, core_jar, output)
            visibility = check_segment_is_empty_visibility(
                compiler, stdlib, segment_case["negative_consumer"], args.kotlin_home.resolve(),
                args.java.resolve(), core_jar, output, args.compile_timeout,
            )
            summary["api_probe_checks"] = {"jvm_descriptor": descriptor, "internal_visibility": visibility}
        def record_lane(case: dict, expected: bytes, directory: Path, route: str, optimization: str) -> None:
            print(f"RUN {case['id']} {route} {optimization}", flush=True)
            try:
                result = run_lane(case, compiler, stdlib, expected, directory, route, optimization, args.compile_timeout)
            except Exception as error:
                result = {"status": "FAIL", "route": route, "optimization": optimization,
                          "error": str(error), "evidence_directory": str(directory)}
            summary["results"].append({"case": case["id"], **result})
            if case.get("evidence_id_prefix"):
                probe = summary.setdefault("api_probe_runs", {}).setdefault(case["id"], {
                    "case_id": case["evidence_case_id"], "reference": None, "candidate": []
                })
                probe["candidate"].append({
                    "execution_id": result.get("execution_id"),
                    "lane": result.get("route", route) + "-" + result.get("optimization", optimization),
                    "result": result.get("status", "FAIL"),
                    "exit_code": 0 if result.get("status") == "PASS" else None,
                    "stdout_sha256": result.get("stdout_sha256"),
                    "normalized_stdout_sha256": result.get("normalized_stdout_sha256"),
                    "output_line_count": result.get("output_line_count"),
                })
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
                require_stage([str((args.kotlin_home / "bin/kotlinc").resolve()), *map(str, producers), str(consumer),
                               "-classpath", classpath, "-include-runtime", "-d", str(jar)], directory, "reference-compile", args.compile_timeout,
                              {"JAVA_HOME": str(args.java.resolve().parent.parent)})
                require_stage([str(args.java.resolve()), "-Djava.io.tmpdir=" + str(directory / "reference-run-work/tmp"),
                               "-cp", str(jar) + os.pathsep + classpath,
                               case.get("jvm_class", "f02consumer.ConsumerKt")], directory, "reference-run", 30)
                expected = normalized_paths((directory / "reference-run.stdout").read_bytes(), directory / "reference-run-work")
                reject_unhandled_events(expected)
                if (directory / "reference-run.stderr").read_bytes(): raise RuntimeError("reference runtime stderr")
                if case.get("ledger"): check_ledger_events(expected, json.loads((HERE / "f02_consumers/manifest.json").read_text()))
                if case.get("evidence_id_prefix"):
                    summary.setdefault("api_probe_runs", {})[case["id"]] = {
                        "case_id": case["evidence_case_id"],
                        "reference": {
                            "execution_id": f"{case['evidence_id_prefix']}:reference",
                            "result": "PASS", "exit_code": 0,
                            "stdout_sha256": sha(directory / "reference-run.stdout"),
                            "normalized_stdout_sha256": hashlib.sha256(expected).hexdigest(),
                            "output_line_count": len(expected.splitlines()),
                            "stdout_byte_count": len(expected),
                        },
                        "candidate": [],
                    }
            else:
                expected = case["expected"].read_bytes()
                reject_unhandled_events(expected)
            expectations.append(expected)
            if not separate_cases: continue
            for route, optimization in LANES:
                record_lane(case, expected, directory / f"{route}-{optimization}", route, optimization)
        if not separate_cases:
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
