#!/usr/bin/env python3
"""Check the kotlinx-io Path public type and construction boundary."""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
INVENTORY = ROOT / "Scripts/io_api_inventory"
sys.path.insert(0, str(INVENTORY))
sys.path.insert(0, str(ROOT / "Scripts/kotlinx_io_upstream"))
import generate as inventory
from run_f02_matrix import execute, require_stage, sha, snapshot
from run_native_reference import dependency_fingerprint, verify_native_sdk

ROW_IDS = ("jvm-03f47bd77ab530ed", "klib-6b354812fb812d2e")
REFERENCE_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"
POSITIVE_CASE_ID = "local:Scripts/io_api_inventory/path_contract/PathContract.kt#public-surface"
JVM_ABI_CONTRACT_CASE_ID = "local:Scripts/io_api_inventory/path_contract/PathJvmAbiProbe.java#jvm-public-shape"
NEGATIVE_CASE_IDS = {
    "internal-constructor": "local:Scripts/io_api_inventory/path_contract/run_path_contract_gate.py#internal-constructor",
    "final-class": "local:Scripts/io_api_inventory/path_contract/run_path_contract_gate.py#final-class",
    "nullable-parent": "local:Scripts/io_api_inventory/path_contract/run_path_contract_gate.py#nullable-parent",
}
ENTRY_POINT = "kuu2628.pathboundaryconsumer.main"
JVM_CLASS = "kuu2628.pathboundaryconsumer.PathContractKt"
NEGATIVE_CASES = (
    ("internal-constructor", "PathInternalConstructor.kt", "ReferenceInternalConstructor.kt", r"internal|visibility|access"),
    ("final-class", "PathSubclass.kt", "ReferenceSubclass.kt", r"final|inherit"),
    ("nullable-parent", "PathParentNonNull.kt", "ReferenceParentNonNull.kt", r"nullable|null|mismatch|type"),
)
LANES = [(route, optimization) for route in ("source", "stdlib-library", "producer-consumer")
         for optimization in ("O0", "O2")]


def save(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def check_reference_pin(kotlin_home: Path, dependencies: Path) -> dict:
    lock_path = ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json"
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    if lock.get("commit") != REFERENCE_COMMIT:
        raise RuntimeError("upstream reference lock uses a different commit")
    for record in lock["sdk_files"]:
        path = kotlin_home / record["path"]
        if not path.is_file() or sha(path) != record["sha256"]:
            raise RuntimeError(f"Kotlin reference SDK hash mismatch: {path}")
    jars = {}
    for record in lock["jvm_artifacts"]:
        if "kotlinx-io-" not in record["url"]:
            continue
        path = dependencies / record["url"].rsplit("/", 1)[1]
        if not path.is_file() or sha(path) != record["sha256"]:
            raise RuntimeError(f"pinned kotlinx-io artifact hash mismatch: {path}")
        jars[record["coordinate"]] = path.resolve()
    core = jars.get("org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1")
    if core is None:
        raise RuntimeError("pinned kotlinx-io core JVM jar is missing")
    return {"lock": lock, "core_jar": core, "sdk_sha256": sha(lock_path),
            "jars": {name: {"path": str(path), "sha256": sha(path)} for name, path in jars.items()}}


def command_result(command: list[str], directory: Path, stage: str, timeout: float,
                   environment: dict[str, str] | None = None) -> tuple[int, bytes, bytes]:
    code = execute(command, directory, stage, timeout, environment)
    stdout = (directory / f"{stage}.stdout").read_bytes()
    stderr = (directory / f"{stage}.stderr").read_bytes()
    return code, stdout, stderr


def expect_compile_rejection(command: list[str], directory: Path, stage: str,
                             timeout: float, diagnostic: str,
                             environment: dict[str, str] | None = None) -> dict:
    code, stdout, stderr = command_result(command, directory, stage, timeout, environment)
    output = (stdout + stderr).decode("utf-8", errors="replace")
    if code == 0:
        raise RuntimeError(f"negative Path probe compiled unexpectedly: {directory / stage}")
    if re.search(diagnostic, output, re.IGNORECASE) is None:
        raise RuntimeError(f"negative Path probe failed for an unexpected reason: {directory / stage}")
    return {"status": "PASS", "raw_exit_code": code,
            "diagnostic_sha256": sha(directory / f"{stage}.stderr")}


def check_upstream_actuals() -> dict:
    upstream = INVENTORY / "upstream/kotlinx-io-0.9.1"
    common = (upstream / "core/common/src/files/Paths.kt").read_text(encoding="utf-8")
    jvm = (upstream / "core/jvm/src/files/PathsJvm.kt").read_text(encoding="utf-8")
    native = (upstream / "core/native/src/files/PathsNative.kt").read_text(encoding="utf-8")
    api = (upstream / "core/api/kotlinx-io-core.klib.api").read_text(encoding="utf-8")
    checks = {
        "common expect class": r"public\s+expect\s+class\s+Path\s*\{",
        "common nullable parent": r"public\s+val\s+parent:\s*Path\?",
        "public string factory": r"public\s+expect\s+fun\s+Path\(path:\s*String\):\s*Path",
        "public string-vararg factory": r"public\s+fun\s+Path\(base:\s*String,\s*vararg\s+parts:\s*String\):\s*Path",
        "public Path-vararg factory": r"public\s+fun\s+Path\(base:\s*Path,\s*vararg\s+parts:\s*String\):\s*Path",
        "JVM internal constructor": r"public\s+actual\s+class\s+Path\s+internal\s+constructor\s*\(internal\s+val\s+file:\s*File\)",
        "JVM nullable parent": r"public\s+actual\s+val\s+parent:\s*Path\?",
        "JVM public string factory": r"public\s+actual\s+fun\s+Path\(path:\s*String\):\s*Path",
        "Native internal constructor": r"public\s+actual\s+class\s+Path\s+internal\s+constructor\s*\(",
        "Native nullable parent": r"public\s+actual\s+val\s+parent:\s*Path\?",
        "Native public string factory": r"public\s+actual\s+fun\s+Path\(path:\s*String\):\s*Path",
        "KLIB final class": r"final\s+class\s+kotlinx\.io\.files/Path\s*\{",
        "KLIB nullable parent": r"final\s+val\s+parent\s*//[^\n]*\n\s+final\s+fun\s+<get-parent>\(\):\s*kotlinx\.io\.files/Path\?",
    }
    sources = {"common expect class": common, "common nullable parent": common,
              "public string factory": common, "public string-vararg factory": common,
              "public Path-vararg factory": common, "JVM internal constructor": jvm,
              "JVM nullable parent": jvm, "JVM public string factory": jvm,
              "Native internal constructor": native, "Native nullable parent": native,
              "Native public string factory": native,
              "KLIB final class": api, "KLIB nullable parent": api}
    failed = [label for label, pattern in checks.items() if re.search(pattern, sources[label]) is None]
    if failed:
        raise RuntimeError("pinned upstream Path declaration mismatch: " + ", ".join(failed))
    return {"status": "PASS", "reference_commit": REFERENCE_COMMIT,
            "checks": list(checks), "execution": "pinned common/JVM/Native source and KLIB API audit"}


def run_reference(kotlin_home: Path, java: Path, javac: Path, core_jar: Path,
                  output: Path, timeout: float) -> dict:
    ref_dir = output / "reference"
    ref_dir.mkdir()
    kotlin = kotlin_home / "bin/kotlinc"
    java_environment = {"JAVA_HOME": str(java.resolve().parent.parent)}
    producer = HERE / "Producer.kt"
    consumer = HERE / "PathContract.kt"
    reference_jar = ref_dir / "PathContract.jar"
    require_stage([str(kotlin), str(producer), str(consumer), "-classpath", str(core_jar),
                   "-include-runtime", "-d", str(reference_jar)], ref_dir, "compile", timeout,
                  java_environment)
    require_stage([str(java), "-cp", os.pathsep.join(map(str, (reference_jar, core_jar))), JVM_CLASS],
                  ref_dir, "run", 60)
    expected = (ref_dir / "run.stdout").read_bytes()
    if expected != b"PATH_PUBLIC_SURFACE_OK\n" or (ref_dir / "run.stderr").read_bytes():
        raise RuntimeError("pinned JVM Path public-surface output mismatch")

    negative_results = {}
    for label, _, reference_name, diagnostic in NEGATIVE_CASES:
        stage_dir = ref_dir / f"negative-{label}"
        stage_dir.mkdir()
        source = HERE / reference_name
        negative_results[label] = expect_compile_rejection(
            [str(kotlin), str(source), "-classpath", str(core_jar),
             "-d", str(stage_dir / "negative.jar")], stage_dir,
            "compile", timeout, diagnostic, java_environment,
        )

    abi_dir = ref_dir / "jvm-abi"
    abi_dir.mkdir()
    classes = abi_dir / "classes"
    classes.mkdir()
    require_stage([str(javac), "-d", str(classes), str(HERE / "PathJvmAbiProbe.java")],
                  abi_dir, "compile", timeout)
    kotlin_stdlib = kotlin_home / "lib/kotlin-stdlib.jar"
    require_stage([str(java), "-cp", os.pathsep.join(map(str, (classes, core_jar, kotlin_stdlib))),
                   "PathJvmAbiProbe"], abi_dir, "run", 60)
    abi_output = (abi_dir / "run.stdout").read_bytes()
    if abi_output != b"PATH_JVM_PUBLIC_SHAPE_OK\n" or (abi_dir / "run.stderr").read_bytes():
        raise RuntimeError("pinned JVM Path ABI probe output mismatch")
    return {"stdout": expected.decode(), "jvm_abi_stdout": abi_output.decode(),
            "negative_probes": negative_results,
            "reference_jar_sha256": sha(reference_jar),
            "reference_abi_probe_sha256": sha(classes / "PathJvmAbiProbe.class")}


def run_apple_reference(native_home: Path, native_archive: Path, native_java: Path,
                        dependencies: Path, konan_data: Path, output: Path,
                        timeout: float) -> dict:
    target = "macos_arm64"
    if (platform.system(), platform.machine()) != ("Darwin", "arm64"):
        raise RuntimeError("Apple Path reference must run on an Apple Silicon macOS host")
    lock_path = ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json"
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    archive_record = lock["native_compiler_archives"][target]
    sdk = verify_native_sdk(native_home, native_archive, archive_record)
    artifacts = [row for row in lock["native_artifacts"]
                 if "macosarm64" in row["coordinate"]]
    libraries = []
    for artifact in artifacts:
        path = dependencies / artifact["url"].rsplit("/", 1)[1]
        if not path.is_file() or sha(path) != artifact["sha256"]:
            raise RuntimeError(f"pinned macOS Native artifact hash mismatch: {path}")
        libraries.append(path.resolve())

    compiler = (native_home / "bin/konanc").resolve()
    if not compiler.is_file():
        raise RuntimeError(f"Kotlin/Native compiler is missing: {compiler}")
    output.mkdir()
    temporary = output / "tmp"
    temporary.mkdir()
    konan_data.mkdir(parents=True, exist_ok=True)
    environment = {
        "KONAN_DATA_DIR": str(konan_data.resolve()),
        "TMPDIR": str(temporary.resolve()),
        "JAVA_HOME": str(native_java.resolve().parent.parent),
        "JAVACMD": str(native_java.resolve()),
    }

    version_code, version_stdout, version_stderr = command_result(
        [str(compiler), "-version"], output, "compiler-version", 30, environment
    )
    version_text = (version_stdout + version_stderr).decode("utf-8", errors="replace")
    if version_code != 0 or "kotlinc-native 2.3.10" not in version_text:
        raise RuntimeError("pinned Kotlin/Native compiler did not report version 2.3.10")
    java_code, java_stdout, java_stderr = command_result(
        [str(native_java), "-version"], output, "java-version", 30, environment
    )
    java_text = (java_stdout + java_stderr).decode("utf-8", errors="replace")
    if java_code != 0 or re.search(r'version "21[.\"]', java_text) is None:
        raise RuntimeError("Kotlin/Native reference requires Java 21")

    library_args = [argument for library in libraries for argument in ("-library", str(library))]
    compile_dir = output / "positive"
    compile_dir.mkdir()
    executable = compile_dir / "PathContract.kexe"
    compile_command = [str(compiler), "-target", target, *library_args,
                       "-entry", ENTRY_POINT, str(HERE / "Producer.kt"),
                       str(HERE / "PathContract.kt"), "-o", str(executable)]
    require_stage(compile_command, compile_dir, "compile", timeout, environment)
    require_stage([str(executable)], compile_dir, "run", 180, environment)
    stdout = (compile_dir / "run.stdout").read_bytes()
    stderr = (compile_dir / "run.stderr").read_bytes()
    if stdout != b"PATH_PUBLIC_SURFACE_OK\n" or stderr:
        raise RuntimeError("pinned macOS Native Path public-surface output mismatch")

    negative_results = {}
    negative_cases = (
        ("internal-constructor", "ReferenceNativeInternalConstructor.kt", r"internal|visibility|access"),
        ("final-class", "ReferenceNativeSubclass.kt", r"final|inherit"),
        ("nullable-parent", "ReferenceParentNonNull.kt", r"nullable|null|mismatch|type"),
    )
    for label, source_name, diagnostic in negative_cases:
        stage_dir = output / f"negative-{label}"
        stage_dir.mkdir()
        command = [str(compiler), "-target", target, *library_args,
                   str(HERE / source_name), "-o", str(stage_dir / "negative.kexe")]
        expect_compile_rejection(command, stage_dir, "compile", timeout, diagnostic, environment)
        negative_results[label] = "EXPECTED_REJECTION"

    return {
        "status": "PASS",
        "target": target,
        "reference_commit": REFERENCE_COMMIT,
        "case_id": POSITIVE_CASE_ID,
        "kotlin_native_version": "2.3.10",
        "kotlin_native_archive_sha256": sha(native_archive),
        "reference_lock_sha256": sha(lock_path),
        "sdk_verified_file_count": sdk["verified_file_count"],
        "konan_dependencies": dependency_fingerprint(konan_data / "dependencies"),
        "native_artifacts": [{"coordinate": artifact["coordinate"],
                              "filename": path.name, "sha256": sha(path)}
                             for artifact, path in zip(artifacts, libraries)],
        "positive_execution_id": "KUU-2628:reference:path-apple-native-public-surface",
        "positive_stdout": stdout.decode(),
        "positive_executable_sha256": sha(executable),
        "negative_probes": negative_results,
    }


def reuse_verified_prefix(summary_path: Path, candidate_sha: str, compiler_sha: str,
                          native_home: Path, native_archive: Path, native_dependencies: Path,
                          konan_data: Path) -> tuple[Path, dict, dict]:
    prefix_path = summary_path.resolve()
    prefix = json.loads(prefix_path.read_text(encoding="utf-8"))
    if prefix.get("candidate_sha") != candidate_sha or prefix.get("compiler_sha256") != compiler_sha:
        raise RuntimeError("reusable Path prefix was produced by a different candidate/compiler")
    if prefix.get("reference_commit") != REFERENCE_COMMIT or prefix.get("reference_version") != "2.3.10":
        raise RuntimeError("reusable Path prefix uses a different reference pin")
    apple = prefix.get("apple_reference")
    if not isinstance(apple, dict) or apple.get("status") != "PASS":
        raise RuntimeError("reusable Path prefix has no passing Apple Native reference")
    if (apple.get("target") != "macos_arm64" or apple.get("reference_commit") != REFERENCE_COMMIT
            or apple.get("kotlin_native_version") != "2.3.10"
            or apple.get("positive_stdout") != "PATH_PUBLIC_SURFACE_OK\n"):
        raise RuntimeError("reusable Apple Native reference receipt has the wrong target or result")
    if apple.get("negative_probes") != {label: "EXPECTED_REJECTION" for label, *_ in NEGATIVE_CASES}:
        raise RuntimeError("reusable Apple Native reference did not pass every negative boundary probe")

    lock_path = ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json"
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    if apple.get("reference_lock_sha256") != sha(lock_path):
        raise RuntimeError("reusable Apple Native reference lock has changed")
    archive_record = lock["native_compiler_archives"]["macos_arm64"]
    sdk = verify_native_sdk(native_home, native_archive, archive_record)
    if (apple.get("kotlin_native_archive_sha256") != sha(native_archive)
            or apple.get("sdk_verified_file_count") != sdk["verified_file_count"]):
        raise RuntimeError("reusable Apple Native compiler archive or installed SDK has changed")
    actual_dependencies = dependency_fingerprint(konan_data / "dependencies")
    if apple.get("konan_dependencies") != actual_dependencies:
        raise RuntimeError("reusable Apple Native toolchain dependencies have changed")
    native_artifacts = []
    for artifact in lock["native_artifacts"]:
        if "macosarm64" not in artifact["coordinate"]:
            continue
        path = native_dependencies / artifact["url"].rsplit("/", 1)[1]
        if not path.is_file() or sha(path) != artifact["sha256"]:
            raise RuntimeError(f"pinned macOS Native artifact hash mismatch: {path}")
        native_artifacts.append({"coordinate": artifact["coordinate"],
                                 "filename": path.name, "sha256": sha(path)})

    native_output = prefix_path.parent / "apple-reference"
    positive_dir = native_output / "positive"
    positive_binary = positive_dir / "PathContract.kexe"
    for stage in ("compile", "run"):
        receipt = json.loads((positive_dir / f"{stage}.json").read_text(encoding="utf-8"))
        if receipt.get("status") != "EXITED" or receipt.get("exitcode") != 0:
            raise RuntimeError(f"reusable Apple Native positive {stage} receipt is incomplete")
    if (not positive_binary.is_file() or sha(positive_binary) != apple.get("positive_executable_sha256")
            or (positive_dir / "run.stdout").read_bytes() != b"PATH_PUBLIC_SURFACE_OK\n"
            or (positive_dir / "run.stderr").read_bytes()):
        raise RuntimeError("reusable Apple Native positive output does not match its receipt")
    native_negative_cases = (
        ("internal-constructor", r"internal|visibility|access"),
        ("final-class", r"final|inherit"),
        ("nullable-parent", r"nullable|null|mismatch|type"),
    )
    for label, diagnostic in native_negative_cases:
        directory = native_output / f"negative-{label}"
        receipt = json.loads((directory / "compile.json").read_text(encoding="utf-8"))
        output = (directory / "compile.stdout").read_bytes() + (directory / "compile.stderr").read_bytes()
        if (receipt.get("status") != "EXITED" or receipt.get("exitcode") == 0
                or re.search(diagnostic.encode(), output, re.IGNORECASE) is None):
            raise RuntimeError(f"reusable Apple Native {label} rejection is not valid")

    stdlib = prefix_path.parent / "KSwiftKStdlib.kklib"
    expected_stdlib = prefix.get("fresh_stdlib_sha256")
    if not isinstance(expected_stdlib, dict) or snapshot(stdlib) != expected_stdlib:
        raise RuntimeError("reusable fresh KSwiftK stdlib artifact is missing or changed")
    apple = dict(apple)
    apple.update(native_artifacts=native_artifacts, konan_dependencies=actual_dependencies,
                 sdk_verified_file_count=sdk["verified_file_count"],
                 reused_from=str(prefix_path), reused_summary_sha256=sha(prefix_path))
    return stdlib, expected_stdlib, apple


def run_candidate_lane(compiler: Path, stdlib: Path, route: str, optimization: str,
                      expected: bytes, output: Path, timeout: float) -> dict:
    output.mkdir()
    inputs = output / "inputs"
    inputs.mkdir()
    producer = inputs / "Producer.kt"
    consumer = inputs / "PathContract.kt"
    producer.write_bytes((HERE / "Producer.kt").read_bytes())
    consumer.write_bytes((HERE / "PathContract.kt").read_bytes())
    inputs_before = snapshot(inputs)
    base = [str(compiler), "-" + optimization, "--no-incremental"]
    base += ["--stdlib-from-source"] if route == "source" else ["--stdlib-library", str(stdlib)]
    errors = []
    stdout = b""
    producer_lib = None
    producer_before = None
    producer_retired = False
    try:
        if route == "producer-consumer":
            producer_lib = output / "PathProbeProducer.kklib"
            require_stage(base + ["--emit", "library", "-m", "KUU2628PathProbeProducer",
                                  str(producer), "-o", str(producer_lib)], output, "producer", timeout)
            producer_before = snapshot(producer_lib)
            if not (producer_lib / "metadata.bin").is_file() or not any(producer_lib.glob("objects/*")):
                raise RuntimeError("Path producer KLIB is missing metadata or objects")
            producer.rename(producer.with_suffix(".kt.evidence"))
            producer_retired = True
            consumer_command = base + ["-I", str(producer_lib), "--entry-point", ENTRY_POINT,
                                       str(consumer), "-o", str(output / "candidate")]
        else:
            consumer_command = base + ["--entry-point", ENTRY_POINT, str(producer), str(consumer),
                                       "-o", str(output / "candidate")]
        require_stage(consumer_command, output, "consumer", timeout)
        require_stage([str(output / "candidate")], output, "run", 60)
        stdout = (output / "run.stdout").read_bytes()
        stderr = (output / "run.stderr").read_bytes()
        if stdout != expected or stderr:
            raise RuntimeError(f"Path public-surface output differs: {output}")
    except Exception as error:
        errors.append(f"public consumer: {error}")

    negative_results = {}
    if route == "source":
        negative_results = {label: "NOT_REQUIRED_SOURCE_MODULE" for label, *_ in NEGATIVE_CASES}
    else:
        for label, candidate_name, _, diagnostic in NEGATIVE_CASES:
            stage_dir = output / f"negative-{label}"
            stage_dir.mkdir()
            command = base + [str(HERE / candidate_name), "-o", str(stage_dir / "negative")]
            try:
                negative_results[label] = expect_compile_rejection(
                    command, stage_dir, "compile", timeout, diagnostic
                )
            except Exception as error:
                negative_results[label] = {"status": "FAIL", "error": str(error)}
                errors.append(f"{label}: {error}")

    if route != "producer-consumer" and snapshot(inputs) != inputs_before:
        errors.append("Path probe input files changed during execution")
    if route == "producer-consumer" and producer_retired:
        expected_inputs = {"Producer.kt.evidence" if name == "Producer.kt" else name: digest
                           for name, digest in inputs_before.items()}
        if snapshot(inputs) != expected_inputs:
            errors.append("Path producer source was not retired before consumer compilation")
        if snapshot(producer_lib) != producer_before:
            errors.append("Path producer KLIB changed during consumer compilation")
    if errors:
        raise RuntimeError("; ".join(errors))
    return {"status": "PASS", "route": route, "optimization": optimization,
            "stdout_sha256": sha(output / "run.stdout"), "executable_sha256": sha(output / "candidate"),
            "stdlib_sha256": snapshot(stdlib) if route != "source" else None,
            "producer_kklib_sha256": producer_before, "negative_probes": negative_results,
            "compiler_processes_separated": route == "producer-consumer"}


def record_evidence(candidate_sha: str, results: list[dict], reference_result: dict) -> None:
    rows = {}
    with (INVENTORY / "api-inventory.tsv").open(encoding="utf-8", newline="") as stream:
        import csv
        rows = {row["row_id"]: row for row in csv.DictReader(stream, delimiter="\t")}
    result_by_lane = {(item["route"], item["optimization"]): item for item in results}
    records = []
    for row_id in ROW_IDS:
        row = rows[row_id]
        if row["upstream_test_refs"] != inventory.NO_DIRECT_UPSTREAM_ASSERTION:
            raise RuntimeError("regenerate the inventory before recording dedicated Path evidence")
        if row["local_test_refs"] != ";".join(inventory.PATH_CLASS_LOCAL_TEST_REFS):
            raise RuntimeError("regenerate the inventory before recording dedicated Path evidence")
        obligations = inventory.validation_obligations(row)
        executions = []
        def append_execution(lane: str, case_id: str, reference_status: str,
                             candidate_status: str) -> None:
            spec = inventory._local_probe_case_spec(row, case_id)
            if spec is None or lane not in spec["lanes"]:
                raise RuntimeError(f"unregistered Path evidence case: {case_id}")
            executions.append({
                "case_id": case_id,
                "lane": lane,
                "reference": {"execution_id": inventory.local_probe_execution_id(
                                  candidate_sha, REFERENCE_COMMIT, case_id, lane, "reference"),
                              "result": reference_status,
                              "exit_code": 0 if reference_status == "PASS" else 1,
                              "method": spec["methods"]["reference"]},
                "candidate": {"execution_id": inventory.local_probe_execution_id(
                                  candidate_sha, REFERENCE_COMMIT, case_id, lane, "candidate"),
                              "result": candidate_status,
                              "exit_code": 0 if candidate_status == "PASS" else 1,
                              "method": spec["methods"]["candidate"]},
            })

        lanes = ["jvm-descriptor"] + [f"{route}-{optimization}" for route, optimization in LANES]
        for lane in lanes:
            if lane == "jvm-descriptor":
                source_result = result_by_lane[("stdlib-library", "O0")]
                append_execution(lane, POSITIVE_CASE_ID, "PASS", source_result["status"])
                append_execution(lane, JVM_ABI_CONTRACT_CASE_ID, "PASS", source_result["status"])
                selected_negative_results = source_result["negative_probes"]
            else:
                route, optimization = lane.rsplit("-", 1)
                source_result = result_by_lane[(route, optimization)]
                append_execution(lane, POSITIVE_CASE_ID, "PASS", source_result["status"])
                if route == "source":
                    continue
                selected_negative_results = source_result["negative_probes"]
            for label, case_id in NEGATIVE_CASE_IDS.items():
                reference_status = reference_result["negative_probes"][label]["status"]
                candidate_status = selected_negative_results[label]["status"]
                append_execution(lane, case_id, reference_status, candidate_status)
        records.append({
            "row_id": row_id,
            "candidate_sha": candidate_sha,
            "reference_version": "0.9.1",
            "reference_commit": REFERENCE_COMMIT,
            **inventory.validation_input_hashes(row),
            "compatibility_obligations": obligations,
            "evidence_source": "local-probe",
            "executions": executions,
        })
    evidence_path = INVENTORY / "api-validation-evidence.json"
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    if not isinstance(evidence, dict) or set(evidence) != {"schema_version", "records"}:
        raise RuntimeError("validation evidence root has an unexpected shape")
    evidence["records"] = [record for record in evidence["records"] if record.get("row_id") not in ROW_IDS]
    evidence["records"].extend(records)
    evidence["records"].sort(key=lambda record: record["row_id"])
    save(evidence_path, evidence)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--kotlin-home", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True)
    parser.add_argument("--javac", type=Path, required=True)
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--native-home", type=Path, required=True)
    parser.add_argument("--native-archive", type=Path, required=True)
    parser.add_argument("--native-java", type=Path, required=True)
    parser.add_argument("--native-dependencies", type=Path, required=True)
    parser.add_argument("--konan-data", type=Path, required=True)
    parser.add_argument("--reuse-prefix-summary", type=Path,
                        help="reuse a verified Apple reference and fresh KLIB from the same candidate SHA")
    parser.add_argument("--compile-timeout", type=float, default=900)
    args = parser.parse_args(argv)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    summary = {"status": "RUNNING", "candidate_sha": None, "reference_commit": REFERENCE_COMMIT,
               "lanes": [], "negative_contracts": [item[0] for item in NEGATIVE_CASES],
               "apple_reference": None, "evidence_written": False}
    try:
        candidate_sha = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
        dirty_compiler = subprocess.run(["git", "-C", str(ROOT), "diff", "--quiet", "HEAD", "--",
                                         "Sources/CompilerCore", "Sources/CompilerBackend", "Sources/KSwiftKCLI",
                                         "Sources/Runtime", "Sources/RuntimeABI"]).returncode
        if dirty_compiler != 0:
            raise RuntimeError("candidate compiler/runtime sources differ from candidate_sha")
        reference = check_reference_pin(args.kotlin_home.resolve(), args.dependencies.resolve())
        summary.update(candidate_sha=candidate_sha, reference_version=reference["lock"]["kotlin"],
                       reference_sha256=reference["jars"], kotlin_sdk_lock_sha256=reference["sdk_sha256"],
                       compiler_sha256=sha(args.compiler.resolve()))
        summary["apple_source_audit"] = check_upstream_actuals()
        if args.reuse_prefix_summary:
            stdlib, stdlib_hash, apple_reference = reuse_verified_prefix(
                args.reuse_prefix_summary, candidate_sha, summary["compiler_sha256"],
                args.native_home.resolve(), args.native_archive.resolve(),
                args.native_dependencies.resolve(), args.konan_data.resolve(),
            )
            if output == args.reuse_prefix_summary.resolve().parent:
                raise RuntimeError("reused Path prefix output must be separate from the new gate output")
            summary["apple_reference"] = apple_reference
            summary["apple_reference_reused"] = True
            summary["fresh_stdlib_reused_from"] = str(stdlib)
            summary["fresh_stdlib_sha256"] = stdlib_hash
            save(output / "summary.json", summary)
        else:
            summary["apple_reference"] = run_apple_reference(
                args.native_home.resolve(), args.native_archive.resolve(), args.native_java.resolve(),
                args.native_dependencies.resolve(), args.konan_data.resolve(),
                output / "apple-reference", args.compile_timeout,
            )
            save(output / "summary.json", summary)

            stdlib = output / "KSwiftKStdlib.kklib"
            require_stage([str(args.compiler.resolve()), "--stdlib-only", "--no-incremental", "-o", str(stdlib)],
                          output, "fresh-stdlib", args.compile_timeout)
            summary["fresh_stdlib_sha256"] = snapshot(stdlib)
            save(output / "summary.json", summary)

        reference_result = run_reference(args.kotlin_home.resolve(), args.java.resolve(), args.javac.resolve(),
                                         reference["core_jar"], output, args.compile_timeout)
        summary["reference_result"] = reference_result
        expected = reference_result["stdout"].encode()
        results = []
        for route, optimization in LANES:
            print(f"RUN {route} {optimization}", flush=True)
            lane_dir = output / f"{route}-{optimization}"
            try:
                result = run_candidate_lane(args.compiler.resolve(), stdlib, route, optimization,
                                            expected, lane_dir, args.compile_timeout)
            except Exception as error:
                result = {"status": "FAIL", "route": route, "optimization": optimization,
                          "error": str(error), "evidence_directory": str(lane_dir)}
            results.append(result)
            summary["lanes"].append(result)
            save(output / "summary.json", summary)
            print(f"{result['status']} {route} {optimization}", flush=True)

        if sha(args.compiler.resolve()) != summary["compiler_sha256"]:
            raise RuntimeError("candidate compiler changed during Path gate execution")
        if snapshot(stdlib) != summary["fresh_stdlib_sha256"]:
            raise RuntimeError("fresh standard-library artifact changed during Path gate execution")
        failures = [result for result in results if result["status"] != "PASS"]
        if failures:
            summary.update(status="FAILED_OR_INCOMPLETE", error=f"{len(failures)} candidate lanes failed")
            save(output / "summary.json", summary)
            return 1
        record_evidence(candidate_sha, results, reference_result)
        summary["evidence_written"] = True
        summary["status"] = "PATH_CONTRACT_PASS"
    except Exception as error:
        summary.update(status="FAILED_OR_INCOMPLETE", error=str(error))
        print(str(error), file=sys.stderr)
    save(output / "summary.json", summary)
    return 0 if summary["status"] == "PATH_CONTRACT_PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
