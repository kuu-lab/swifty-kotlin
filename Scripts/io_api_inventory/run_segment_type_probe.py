#!/usr/bin/env python3
"""Verify the public Segment type and its private construction boundary."""

from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
UPSTREAM = HERE / "upstream/kotlinx-io-0.9.1"
FIXTURES = HERE / "segment_type_probe"
CATALOG = HERE / "api-probe-catalog.json"
RESULTS = HERE / "api-validation-probe-results.json"
EVIDENCE = HERE / "api-validation-evidence.json"
LOCK = HERE / "upstream-lock.json"
REFERENCE_LOCK = ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json"
UPSTREAM_SOURCE = UPSTREAM / "core/common/src/Segment.kt"
UPSTREAM_JVM_API = UPSTREAM / "core/api/kotlinx-io-core.api"
UPSTREAM_KLIB_API = UPSTREAM / "core/api/kotlinx-io-core.klib.api"
EXPECTED_KOTLIN = "2.3.10"
EXPECTED_UPSTREAM_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_sha(path: Path) -> str:
    return sha256(path.read_bytes())


def artifact_sha(path: Path) -> str:
    files = {
        child.relative_to(path).as_posix(): file_sha(child)
        for child in sorted(path.rglob("*"))
        if child.is_file()
    }
    encoded = json.dumps(files, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return sha256(encoded)


def command_output(command: list[str], cwd: Path, env: dict[str, str], timeout: int) -> tuple[int, str, str]:
    process = subprocess.run(command, cwd=cwd, env={**os.environ, **env}, capture_output=True,
                             text=True, errors="replace", timeout=timeout)
    return process.returncode, process.stdout, process.stderr


def require_success(command: list[str], cwd: Path, env: dict[str, str], timeout: int,
                    commands: list[str], stdout: list[str], stderr: list[str]) -> None:
    code, out, err = command_output(command, cwd, env, timeout)
    commands.append(shlex.join(command))
    stdout.append(out)
    stderr.append(err)
    if code != 0:
        raise RuntimeError(f"command failed with exit {code}: {shlex.join(command)}\n{err or out}")


def require_rejection(command: list[str], cwd: Path, env: dict[str, str], timeout: int,
                      marker: str | tuple[str, ...], commands: list[str], stdout: list[str], stderr: list[str]) -> None:
    code, out, err = command_output(command, cwd, env, timeout)
    commands.append(shlex.join(command))
    stdout.append(out)
    stderr.append(err)
    combined = (out + "\n" + err).lower()
    if code == 0:
        raise RuntimeError(f"expected compilation rejection but command succeeded: {shlex.join(command)}")
    markers = (marker,) if isinstance(marker, str) else marker
    missing = [item for item in markers if item.lower() not in combined]
    if missing:
        raise RuntimeError(f"expected diagnostic markers {missing!r} were absent: {err or out}")


def normalize(text: str, output: Path) -> str:
    return text.replace(str(output), "<probe-output>")


def inspect_inputs(kotlin_home: Path, java: Path, javap: Path, dependencies: Path,
                   compiler: Path, candidate_root: Path) -> tuple[dict[str, str], Path]:
    reference_lock = json.loads(REFERENCE_LOCK.read_text(encoding="utf-8"))
    if (reference_lock.get("kotlin"), reference_lock.get("commit")) != (EXPECTED_KOTLIN, EXPECTED_UPSTREAM_COMMIT):
        raise RuntimeError("reference toolchain lock is not Kotlin 2.3.10 / kotlinx-io 0.9.1")
    inputs = {}
    for entry in reference_lock["sdk_files"]:
        path = kotlin_home / entry["path"]
        if not path.is_file() or file_sha(path) != entry["sha256"]:
            raise RuntimeError(f"Kotlin SDK file does not match the lock: {entry['path']}")
        inputs[f"reference-sdk/{entry['path']}"] = entry["sha256"]
    if not (kotlin_home / "bin/kotlinc").is_file():
        raise RuntimeError("Kotlin compiler is missing from --kotlin-home")
    version = command_output([str(kotlin_home / "bin/kotlinc"), "-version"], ROOT, {}, 30)
    if version[0] != 0 or EXPECTED_KOTLIN not in version[1] + version[2]:
        raise RuntimeError(f"reference compiler is not Kotlin {EXPECTED_KOTLIN}: {version[1]}{version[2]}")

    jars = {}
    for artifact in reference_lock["jvm_artifacts"]:
        if "kotlinx-io-" not in artifact["coordinate"]:
            continue
        jar = dependencies / artifact["url"].rsplit("/", 1)[1]
        if not jar.is_file() or file_sha(jar) != artifact["sha256"]:
            raise RuntimeError(f"pinned JVM dependency is missing or has the wrong hash: {jar}")
        jars[artifact["coordinate"].split(":")[1]] = jar
    core = jars.get("kotlinx-io-core-jvm")
    if core is None:
        raise RuntimeError("the pinned kotlinx-io-core JVM artifact is missing")

    inventory_lock = json.loads(LOCK.read_text(encoding="utf-8"))
    upstream_hashes = {entry["path"]: entry["sha256"] for entry in inventory_lock["upstreamFiles"]}
    for relative, path in (
        ("core/common/src/Segment.kt", UPSTREAM_SOURCE),
        ("core/api/kotlinx-io-core.api", UPSTREAM_JVM_API),
        ("core/api/kotlinx-io-core.klib.api", UPSTREAM_KLIB_API),
    ):
        if file_sha(path) != upstream_hashes.get(relative):
            raise RuntimeError(f"pinned upstream input changed: {relative}")

    inputs.update({
        f"repo/{path.relative_to(ROOT).as_posix()}": file_sha(path)
        for path in (CATALOG, Path(__file__), UPSTREAM_SOURCE, UPSTREAM_JVM_API, UPSTREAM_KLIB_API,
                     *sorted(FIXTURES.glob("*.kt")))
    })
    candidate_implementation = candidate_root / "Sources/CompilerCore/Stdlib/kotlinx/io/Segment.kt"
    if not candidate_implementation.is_file():
        raise RuntimeError(f"candidate Segment implementation is missing: {candidate_implementation}")
    inputs["candidate:Sources/CompilerCore/Stdlib/kotlinx/io/Segment.kt"] = file_sha(candidate_implementation)
    inputs["tool:kotlin-compiler"] = file_sha(kotlin_home / "bin/kotlinc")
    inputs["tool:java"] = file_sha(java)
    inputs["tool:javap"] = file_sha(javap)
    for name, jar in jars.items():
        inputs[f"reference:{name}"] = file_sha(jar)
    return inputs, core


def read_probe_catalog() -> tuple[dict, list[dict]]:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    if catalog.get("schema_version") != 1 or set(catalog) != {"schema_version", "cases"}:
        raise RuntimeError("malformed Segment probe catalog")
    cases = catalog["cases"]
    by_row = {case["row_id"]: case for case in cases}
    if len(by_row) != len(cases):
        raise RuntimeError("duplicate API row in Segment probe catalog")
    required = {
        "jvm-e405f88094ec1353": ["jvm-descriptor"],
        "klib-4ab35f2484026657": [
            "source-O0", "source-O2", "stdlib-library-O0", "stdlib-library-O2",
            "producer-consumer-O0", "producer-consumer-O2",
        ],
    }
    if {row_id: case["lanes"] for row_id, case in by_row.items()} != required:
        raise RuntimeError("Segment probe catalog lanes do not match the API inventory obligations")
    expected_case_ids = {
        "jvm-e405f88094ec1353": "api-probe:KUU-2609:segment-jvm-type-shape",
        "klib-4ab35f2484026657": "api-probe:KUU-2609:segment-public-type-and-construction-boundary",
    }
    if {row_id: case["case_id"] for row_id, case in by_row.items()} != expected_case_ids:
        raise RuntimeError("Segment probe catalog case IDs do not match KUU-2609")
    return catalog, cases


def check_type_correspondence(candidate_root: Path) -> str:
    with (HERE / "api-inventory.tsv").open(newline="", encoding="utf-8") as stream:
        rows = {row["row_id"]: row for row in csv.DictReader(stream, delimiter="\t")}
    jvm = rows["jvm-e405f88094ec1353"]
    klib = rows["klib-4ab35f2484026657"]
    if ("klib-4ab35f2484026657" not in jvm["jvm_abi_refs"].split(";")
            or "jvm-e405f88094ec1353" not in klib["jvm_abi_refs"].split(";")):
        raise RuntimeError("JVM and KLIB Segment rows are not paired in the generated API inventory")
    if "public final class kotlinx/io/Segment" not in jvm["signature"]:
        raise RuntimeError("the JVM inventory row does not describe the expected public final Segment class")
    if "final class kotlinx.io/Segment" not in klib["signature"]:
        raise RuntimeError("the KLIB inventory row does not describe the expected final Segment class")
    source = (candidate_root / "Sources/CompilerCore/Stdlib/kotlinx/io/Segment.kt").read_text(encoding="utf-8")
    if not re.search(r"\bpublic\s+class\s+Segment\b", source) or re.search(r"\bopen\s+class\s+Segment\b", source):
        raise RuntimeError("candidate Segment source is not public and final by Kotlin default")
    return "public-final-type-mapping:ok"


def run_reference_lane(lane: str, kotlin_home: Path, java: Path, javap: Path, core_jar: Path,
                       workspace: Path, output: Path, timeout: int) -> dict:
    workspace.mkdir(parents=True)
    kotlin = str(kotlin_home / "bin/kotlinc")
    commands: list[str] = []
    stdout: list[str] = []
    stderr: list[str] = []
    env = {"TMPDIR": str(workspace / "tmp")}
    (workspace / "tmp").mkdir()
    classpath = str(core_jar)
    if lane == "jvm-descriptor":
        javap_command = [str(javap), "-classpath", classpath, "-public", "-v", "kotlinx.io.Segment"]
        require_success(javap_command, workspace, env, timeout, commands, stdout, stderr)
        descriptor = stdout[-1]
        if not re.search(r"public\s+final\s+class\s+kotlinx\.io\.Segment\b", descriptor):
            raise RuntimeError("the pinned JVM reference does not expose public final kotlinx.io.Segment")
        if not re.search(r"flags:.*ACC_PUBLIC.*ACC_FINAL", descriptor):
            raise RuntimeError("the pinned JVM class flags are not public and final")
        observed = "public-final-type:verified\n"
        stdout[-1] = observed
    elif lane.startswith("producer-consumer"):
        producer = FIXTURES / "SegmentTypeProducer.kt"
        consumer = FIXTURES / "SegmentTypeConsumer.kt"
        producer_jar = workspace / "SegmentTypeProducer.jar"
        consumer_jar = workspace / "SegmentTypeConsumer.jar"
        require_success([kotlin, "-classpath", classpath, str(producer), "-d", str(producer_jar)],
                       workspace, env, timeout, commands, stdout, stderr)
        consumer_cp = os.pathsep.join((str(producer_jar), classpath))
        require_success([kotlin, "-classpath", consumer_cp, "-include-runtime", str(consumer), "-d", str(consumer_jar)],
                       workspace, env, timeout, commands, stdout, stderr)
        require_success([str(java), "-cp", os.pathsep.join((str(consumer_jar), consumer_cp)),
                         "io.segmenttypeprobe.consumer.SegmentTypeConsumerKt"],
                       workspace, env, timeout, commands, stdout, stderr)
        expected = "segment-library-boundary:ok\n"
        if stdout[-1] != expected:
            raise RuntimeError(f"JVM producer/consumer output mismatch: {stdout[-1]!r}")
        stdout[-1] = expected
        positive_dir = workspace / "negative"
    else:
        positive = FIXTURES / "SegmentPublicType.kt"
        jar = workspace / "SegmentPublicType.jar"
        require_success([kotlin, "-classpath", classpath, "-include-runtime", str(positive), "-d", str(jar)],
                       workspace, env, timeout, commands, stdout, stderr)
        require_success([str(java), "-cp", os.pathsep.join((str(jar), classpath)),
                         "io.segmenttypeprobe.SegmentPublicTypeKt"],
                       workspace, env, timeout, commands, stdout, stderr)
        expected = "segment-public-type:ok\n"
        if stdout[-1] != expected:
            raise RuntimeError(f"JVM public type output mismatch: {stdout[-1]!r}")
        stdout[-1] = expected
        positive_dir = workspace / "negative"

    if lane != "jvm-descriptor":
        positive_dir.mkdir(exist_ok=True)
        negative = FIXTURES / "SegmentConstructionForbidden.kt"
        subclass = FIXTURES / "SegmentSubclassForbidden.kt"
        require_rejection([kotlin, "-classpath", classpath, str(negative), str(subclass),
                           "-d", str(positive_dir / "negative.jar")],
                          positive_dir, env, timeout, ("private", "final"), commands, stdout, stderr)
        stdout.append("private-constructor:rejected\n")
        stdout.append("final-class-subclass:rejected\n")

    return make_execution("reference", lane, commands, stdout, stderr, output)


def candidate_base(compiler: Path, optimization: str, route: str, stdlib: Path | None) -> list[str]:
    command = [str(compiler), f"-{optimization}", "--no-incremental"]
    if route == "source":
        command.append("--stdlib-from-source")
    elif stdlib:
        command += ["--stdlib-library", str(stdlib)]
    return command


def run_candidate_checks(compiler: Path, optimization: str, route: str, stdlib: Path | None,
                         workspace: Path, timeout: int, output: Path,
                         candidate_root: Path, producer_library: Path | None = None) -> dict:
    workspace.mkdir(parents=True)
    (workspace / "tmp").mkdir()
    env = {"TMPDIR": str(workspace / "tmp"), "KSWIFTK_STDLIB_CACHE_DIR": str(workspace / "stdlib-cache"),
           "KSWIFTK_PACKAGE_ROOT": str(candidate_root)}
    commands: list[str] = []
    stdout: list[str] = []
    stderr: list[str] = []
    base = candidate_base(compiler, optimization, route, stdlib)
    class_shape = check_type_correspondence(candidate_root)
    stdout.append(class_shape + "\n")

    if route == "producer-consumer":
        if producer_library is None:
            producer = FIXTURES / "SegmentTypeProducer.kt"
            producer_library = workspace / "SegmentTypeProducer.kklib"
            producer_base = candidate_base(compiler, optimization, "stdlib-library", stdlib)
            require_success(producer_base + ["--emit", "library", "-m", "SegmentTypeProducer", str(producer),
                                             "-o", str(producer_library)],
                            workspace, env, timeout, commands, stdout, stderr)
            if (not (producer_library / "metadata.bin").is_file()
                    or not any((producer_library / "objects").glob("*"))):
                raise RuntimeError("candidate Segment producer library is incomplete")
        consumer = FIXTURES / "SegmentTypeConsumer.kt"
        consumer_kir = workspace / "consumer"
        consumer_base = candidate_base(compiler, optimization, "stdlib-library", stdlib)
        require_success(consumer_base + ["-I", str(producer_library), "--emit", "kir",
                                         str(consumer), "-o", str(consumer_kir)],
                        workspace, env, timeout, commands, stdout, stderr)
        consumer_output = Path(f"{consumer_kir}.kir")
        if not consumer_output.is_file() or consumer_output.stat().st_size == 0:
            raise RuntimeError("candidate Segment consumer did not emit KIR")
        stdout.append("segment-library-boundary:compiled\n")
        negative_base = consumer_base + ["-I", str(producer_library)]
    else:
        positive = FIXTURES / "SegmentPublicType.kt"
        positive_kir = workspace / "positive"
        require_success(base + ["--emit", "kir", str(positive), "-o", str(positive_kir)],
                        workspace, env, timeout, commands, stdout, stderr)
        positive_output = Path(f"{positive_kir}.kir")
        if not positive_output.is_file() or positive_output.stat().st_size == 0:
            raise RuntimeError("candidate Segment public type probe did not emit KIR")
        stdout.append("segment-public-type:compiled\n")
        negative_base = base

    negative_dir = workspace / "negative"
    negative_dir.mkdir()
    constructor = FIXTURES / "SegmentConstructionForbidden.kt"
    subclass = FIXTURES / "SegmentSubclassForbidden.kt"
    require_rejection(negative_base + ["--emit", "kir", str(constructor), str(subclass),
                                       "-o", str(negative_dir / "negative")],
                      negative_dir, env, timeout, ("private", "final"), commands, stdout, stderr)
    stdout.append("private-constructor:rejected\n")
    stdout.append("final-class-subclass:rejected\n")
    return make_execution("candidate", f"{route}-{optimization}", commands, stdout, stderr, output)


def make_execution(subject: str, lane: str, commands: list[str], stdout: list[str], stderr: list[str],
                   output: Path) -> dict:
    out = normalize("".join(stdout), output)
    err = normalize("".join(stderr), output)
    return {
        "execution_id": "",
        "result": "PASS",
        "exit_code": 0,
        "command": commands,
        "stdout": out,
        "stderr": err,
        "stdout_sha256": sha256(out.encode("utf-8")),
        "stderr_sha256": sha256(err.encode("utf-8")),
    }


def record_api_validation_evidence(results: dict) -> None:
    existing = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    if not isinstance(existing, dict) or set(existing) != {"schema_version", "records"} or existing["schema_version"] != 1:
        raise RuntimeError("existing API validation evidence has an unsupported format")
    owned_rows = {case["row_id"] for case in json.loads(CATALOG.read_text(encoding="utf-8"))["cases"]}
    records = [record for record in existing["records"] if record.get("row_id") not in owned_rows]
    executions_by_row: dict[str, list[dict]] = {}
    for execution in results["executions"]:
        executions_by_row.setdefault(execution["row_id"], []).append({
            "case_id": execution["case_id"],
            "lane": execution["lane"],
            "reference": {key: execution["reference"][key] for key in ("execution_id", "result", "exit_code")},
            "candidate": {key: execution["candidate"][key] for key in ("execution_id", "result", "exit_code")},
        })
    for row_id in sorted(owned_rows):
        process = subprocess.run([sys.executable, str(HERE / "generate.py"), "--show-input-hashes", row_id],
                                 cwd=ROOT, capture_output=True, text=True, check=True)
        hashes = json.loads(process.stdout)
        records.append({
            "row_id": row_id,
            "candidate_sha": results["candidate_sha"],
            "reference_version": results["reference_version"],
            "reference_commit": results["reference_commit"],
            "implementation_input_sha256": hashes["implementation_input_sha256"],
            "test_input_sha256": hashes["test_input_sha256"],
            "compatibility_obligations": hashes["compatibility_obligations"],
            "executions": executions_by_row[row_id],
        })
    records.sort(key=lambda record: record["row_id"])
    EVIDENCE.write_text(json.dumps({"schema_version": 1, "records": records}, ensure_ascii=False, indent=2) + "\n",
                        encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True, type=Path)
    parser.add_argument("--candidate-package-root", type=Path,
                        help="source checkout used to build the candidate compiler; defaults to this checkout")
    parser.add_argument("--kotlin-home", required=True, type=Path)
    parser.add_argument("--java", required=True, type=Path)
    parser.add_argument("--javap", type=Path)
    parser.add_argument("--dependencies", required=True, type=Path)
    parser.add_argument("--fresh-stdlib-library", type=Path,
                        help="reuse a fresh stdlib artifact already built with --compiler")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--candidate-sha", help="candidate commit SHA; defaults to the checkout HEAD")
    parser.add_argument("--timeout", type=int, default=1800)
    args = parser.parse_args()

    compiler = args.compiler.resolve()
    candidate_root = (args.candidate_package_root or ROOT).resolve()
    kotlin_home = args.kotlin_home.resolve()
    java = args.java.resolve()
    javap = (args.javap or java.with_name("javap")).resolve()
    dependencies = args.dependencies.resolve()
    output = args.output.resolve()
    if not compiler.is_file() or not os.access(compiler, os.X_OK):
        raise SystemExit(f"candidate compiler is not executable: {compiler}")
    if not java.is_file() or not javap.is_file():
        raise SystemExit("--java and --javap must name executable toolchain binaries")
    if output.exists() and any(output.iterdir()):
        raise SystemExit(f"output directory must be empty: {output}")
    output.mkdir(parents=True, exist_ok=True)

    catalog, cases = read_probe_catalog()
    probe_inputs, core_jar = inspect_inputs(kotlin_home, java, javap, dependencies, compiler, candidate_root)
    candidate_sha = args.candidate_sha
    if not candidate_sha:
        candidate_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=candidate_root, text=True).strip()
    if not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", candidate_sha):
        raise SystemExit("--candidate-sha must be a full hexadecimal Git SHA")
    root_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=candidate_root, text=True).strip()
    if candidate_sha != root_sha:
        raise SystemExit(f"candidate SHA {candidate_sha} does not match candidate package root HEAD {root_sha}")
    if args.candidate_package_root:
        dirty = subprocess.check_output(
            ["git", "status", "--porcelain", "--untracked-files=all"], cwd=candidate_root, text=True
        ).strip()
        if dirty:
            raise SystemExit("candidate package root must be clean when supplied explicitly")

    stdlib = output / "KSwiftKStdlib.kklib"
    if args.fresh_stdlib_library:
        supplied_stdlib = args.fresh_stdlib_library.resolve()
        if not supplied_stdlib.is_dir():
            raise SystemExit(f"fresh stdlib library is not a directory: {supplied_stdlib}")
        print("COPY caller-supplied fresh candidate stdlib for O0/O2 consumer lanes", flush=True)
        shutil.copytree(supplied_stdlib, stdlib)
        stdlib_origin = "caller-supplied fresh artifact"
    else:
        stdlib_workspace = output / "candidate/stdlib-build"
        stdlib_workspace.mkdir(parents=True)
        (stdlib_workspace / "tmp").mkdir()
        stdlib_env = {"TMPDIR": str(stdlib_workspace / "tmp"),
                      "KSWIFTK_STDLIB_CACHE_DIR": str(stdlib_workspace / "stdlib-cache"),
                      "KSWIFTK_PACKAGE_ROOT": str(candidate_root)}
        stdlib_command = [str(compiler), "--stdlib-only", "--emit", "library", "--no-incremental",
                          "-O0", "-o", str(stdlib)]
        print("BUILD fresh candidate stdlib for O0/O2 consumer lanes", flush=True)
        code, stdlib_stdout, stdlib_stderr = command_output(stdlib_command, stdlib_workspace, stdlib_env, args.timeout)
        (output / "candidate-stdlib.stdout").write_text(stdlib_stdout, encoding="utf-8")
        (output / "candidate-stdlib.stderr").write_text(stdlib_stderr, encoding="utf-8")
        if code != 0 or not (stdlib / "metadata.bin").is_file() or not any((stdlib / "objects").glob("*")):
            raise SystemExit(f"fresh candidate stdlib build failed; see {output / 'candidate-stdlib.stderr'}")
        stdlib_origin = "fresh CLI --stdlib-only O0 build"
    manifest = json.loads((stdlib / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("moduleName") != "KSwiftKStdlib" or manifest.get("kotlinLanguageVersion") != "2.4.20":
        raise SystemExit("fresh candidate stdlib has the wrong module or language version")
    metadata = (stdlib / "metadata.bin").read_bytes()
    metadata_text = metadata.decode("utf-8", errors="ignore")
    if "kotlinx.io.Segment" not in metadata_text and "kotlinx/io/Segment" not in metadata_text:
        raise SystemExit("fresh candidate stdlib metadata omits Segment")
    probe_inputs["candidate:stdlib-metadata"] = sha256(metadata)
    probe_inputs["candidate:stdlib-artifact-tree"] = artifact_sha(stdlib)
    # O0/O2 describe consumer compilation; the same freshly built API artifact serves both lanes.
    stdlibs = {"O0": stdlib, "O2": stdlib}

    executions = []
    shared_reference = None
    for case in cases:
        for lane in case["lanes"]:
            identifier = (case["row_id"], case["case_id"], lane)
            print(f"RUN {identifier[1]} {lane}", flush=True)
            workspace = output / lane / case["row_id"]
            workspace.parent.mkdir(parents=True, exist_ok=True)
            if lane == "jvm-descriptor":
                reference = run_reference_lane(lane, kotlin_home, java, javap, core_jar,
                                               workspace / "reference", output, args.timeout)
                reference["execution_id"] = f"{case['row_id']}:{lane}:reference"
            else:
                if shared_reference is None:
                    shared_reference = run_reference_lane("producer-consumer", kotlin_home, java, javap, core_jar,
                                                          output / "reference/klib-shared", output, args.timeout)
                    shared_reference["execution_id"] = f"{case['row_id']}:shared-reference"
                reference = copy.deepcopy(shared_reference)
            if lane == "jvm-descriptor":
                candidate = run_candidate_checks(compiler, "O0", "stdlib-library", stdlibs["O0"],
                                                 workspace / "candidate", args.timeout, output, candidate_root)
            else:
                route, optimization = lane.rsplit("-", 1)
                candidate = run_candidate_checks(compiler, optimization, route,
                                                 None if route == "source" else stdlibs[optimization],
                                                 workspace / "candidate", args.timeout, output, candidate_root)
            candidate["execution_id"] = f"{case['row_id']}:{lane}:candidate"
            executions.append({"row_id": case["row_id"], "case_id": case["case_id"], "lane": lane,
                               "reference": reference, "candidate": candidate})
            print(f"PASS {identifier[1]} {lane}", flush=True)

    results = {
        "schema_version": 1,
        "candidate_sha": candidate_sha,
        "candidate_compiler_sha256": file_sha(compiler),
        "reference_version": "0.9.1",
        "reference_kotlin_version": EXPECTED_KOTLIN,
        "reference_commit": EXPECTED_UPSTREAM_COMMIT,
        "probe_inputs_sha256": probe_inputs,
        "summary": {"case_count": len(cases), "lane_count": len(executions),
                    "passed": len(executions), "failed": 0},
        "executions": executions,
    }
    RESULTS.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    record_api_validation_evidence(results)
    summary_path = output / "summary.json"
    summary_path.write_text(json.dumps({"candidate_sha": candidate_sha,
        "candidate_compiler_sha256": file_sha(compiler), "reference_version": "0.9.1",
        "reference_kotlin_version": EXPECTED_KOTLIN, "reference_commit": EXPECTED_UPSTREAM_COMMIT,
        "stdlib_artifact_origin": f"{stdlib_origin} shared by consumer O0/O2 lanes",
        "stdlib_artifact_tree_sha256": artifact_sha(stdlib),
        "stdlib_metadata_sha256": {optimization: file_sha(stdlibs[optimization] / "metadata.bin")
                                    for optimization in ("O0", "O2")},
        "results": results["summary"], "evidence_file": str(RESULTS)}, indent=2) + "\n", encoding="utf-8")
    print(f"WROTE {RESULTS}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, json.JSONDecodeError, subprocess.SubprocessError, RuntimeError, KeyError, ValueError) as error:
        print(f"ERROR {error}", file=sys.stderr)
        raise SystemExit(1)
