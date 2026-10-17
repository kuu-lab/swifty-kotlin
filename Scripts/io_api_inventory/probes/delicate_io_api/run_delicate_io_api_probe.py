#!/usr/bin/env python3
"""Run direct DelicateIoApi declaration and opt-in probes for KUU-2613."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import urllib.request
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
INVENTORY = ROOT / "Scripts/io_api_inventory"
UPSTREAM = INVENTORY / "upstream/kotlinx-io-0.9.1"
LOCK_PATH = INVENTORY / "upstream-lock.json"
EVIDENCE_PATH = INVENTORY / "api-validation-evidence.json"
EXECUTIONS_PATH = INVENTORY / "api-validation-probe-executions.json"
GENERATOR = INVENTORY / "generate.py"
CASE_ID = "Scripts/io_api_inventory/probes/delicate_io_api/DelicateIoApi.kt#contract"
SOURCE = HERE / "DelicateIoApi.kt"
OPTED_IN = HERE / "OptedInConsumer.kt"
UNOPTED = HERE / "UnoptedConsumer.kt"
STDLIB_ANNOTATIONS = ROOT / "Sources/CompilerCore/Stdlib/kotlinx/io/Annotations.kt"
EXPECTED_OUTPUT = "DelicateIoApi:ok\n"
DELICATE_API_MESSAGE = (
    "This is a delicate API and its use requires care. Make sure you fully read and understand "
    "documentation of the declaration that is marked as a delicate API."
)
REFERENCE_DELICATE_API_MESSAGE = DELICATE_API_MESSAGE[0].lower() + DELICATE_API_MESSAGE[1:]
KOTLIN_REFERENCE_VERSION = "2.3.10"
CANDIDATE_LANES = (
    "source-O0",
    "source-O2",
    "stdlib-library-O0",
    "stdlib-library-O2",
    "producer-consumer-O0",
    "producer-consumer-O2",
)
JVM_LANE = "jvm-descriptor"
PROBE_LANES = frozenset((JVM_LANE, *CANDIDATE_LANES))
ROW_LANES = {
    "klib-9f0ca3fb595dae3d": CANDIDATE_LANES,
    "klib-ca6de80d87f0db05": CANDIDATE_LANES,
}
AUDITED_ROW_IDS = frozenset(("jvm-1ade859ef0485010", *ROW_LANES))


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_sha256(path: Path) -> str:
    return sha256(path.read_bytes())


def digest_payload(payload: dict) -> str:
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return "probe:" + sha256(encoded.encode("utf-8"))


def normalize(text: str, work: Path, dependencies: Path) -> str:
    value = text.replace(str(work), "<WORK>")
    value = value.replace(str(dependencies), "<DEPENDENCIES>")
    value = value.replace(str(ROOT), "<REPO>")
    return value


def display_command(command: list[str], work: Path, dependencies: Path) -> str:
    normalized = [normalize(part, work, dependencies) for part in command]
    return shlex.join(normalized)


def run_stage(
    name: str,
    command: list[str],
    cwd: Path,
    work: Path,
    dependencies: Path,
    environment: dict[str, str],
    timeout: int,
) -> dict:
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            env=environment,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        exit_code = result.returncode
        stdout = result.stdout
        stderr = result.stderr
    except subprocess.TimeoutExpired as error:
        exit_code = 124
        stdout = error.stdout.decode("utf-8", errors="replace") if isinstance(error.stdout, bytes) else (error.stdout or "")
        stderr = error.stderr.decode("utf-8", errors="replace") if isinstance(error.stderr, bytes) else (error.stderr or "")
        stderr += f"\nTIMEOUT after {timeout} seconds\n"
    except OSError as error:
        exit_code = 127
        stdout = ""
        stderr = f"{type(error).__name__}: {error}\n"

    return {
        "name": name,
        "command": display_command(command, work, dependencies),
        "exit_code": exit_code,
        "stdout": normalize(stdout, work, dependencies),
        "stderr": normalize(stderr, work, dependencies),
    }


def successful(stage: dict) -> bool:
    return stage["exit_code"] == 0


def stage_text(stage: dict) -> str:
    return stage["stdout"] + "\n" + stage["stderr"]


def consumer_compile_pass(subject: str, label: str, compile_stage: dict) -> bool:
    diagnostics = stage_text(compile_stage)
    if not successful(compile_stage):
        return False
    if label == "positive":
        if subject == "candidate":
            return "KSWIFTK-SEMA-OPT-IN" not in diagnostics
        return "warning:" not in diagnostics.lower()

    if "error:" in diagnostics.lower():
        return False
    if subject == "candidate":
        return (
            diagnostics.count("KSWIFTK-SEMA-OPT-IN") == 1
            and "warning" in diagnostics.lower()
            and DELICATE_API_MESSAGE in diagnostics
        )
    warning_lines = [line for line in diagnostics.splitlines() if "warning:" in line.lower()]
    return (
        len(warning_lines) == 1
        and REFERENCE_DELICATE_API_MESSAGE in diagnostics
        and "UnoptedConsumer.kt:6:" in diagnostics
    )


def artifact_snapshot(path: Path) -> dict:
    if not path.exists():
        return {"path": path.name, "exists": False, "files": 0, "sha256": None}
    files = sorted(item for item in path.rglob("*") if item.is_file()) if path.is_dir() else [path]
    entries = {
        str(item.relative_to(path)) if path.is_dir() else item.name: file_sha256(item)
        for item in files
    }
    payload = json.dumps(entries, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {"path": path.name, "exists": True, "files": len(entries), "sha256": sha256(payload)}


def load_locked_core_jar(lock: dict, directory: Path) -> Path:
    artifact = next(
        item for item in lock["mavenArtifacts"]
        if item["coordinate"] == "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1"
    )
    filename = artifact["url"].rsplit("/", 1)[-1]
    path = directory / filename
    if not path.exists():
        directory.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(artifact["url"], timeout=30) as response:
            path.write_bytes(response.read())
    observed = file_sha256(path)
    if observed != artifact["sha256"]:
        raise RuntimeError(f"pinned kotlinx-io JVM jar hash mismatch: {observed}")
    return path


def reference_pin() -> dict:
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    if lock.get("tag") != "0.9.1" or lock.get("commit") != "362bdc35e159bad6da1e08101c8321792d762281":
        raise RuntimeError("upstream lock does not match the KUU-2613 reference pin")
    return lock


def check_kotlinc(kotlinc: Path, work: Path, dependencies: Path, environment: dict[str, str]) -> dict:
    version = run_stage(
        "reference-compiler-version",
        [str(kotlinc), "-version"],
        work,
        work,
        dependencies,
        environment,
        30,
    )
    if not successful(version) or f"kotlinc-jvm {KOTLIN_REFERENCE_VERSION}" not in stage_text(version):
        raise RuntimeError(f"reference compiler must be Kotlin {KOTLIN_REFERENCE_VERSION}: {stage_text(version)}")
    return version


def inspect_upstream_jvm_declaration(core_jar: Path, javap: Path, work: Path, dependencies: Path,
                                     environment: dict[str, str]) -> dict:
    api_path = UPSTREAM / "core/api/kotlinx-io-core.api"
    source_path = UPSTREAM / "core/common/src/Annotations.kt"
    expected_api = (
        "public abstract interface annotation class kotlinx/io/DelicateIoApi : "
        "java/lang/annotation/Annotation {"
    )
    api_lines = api_path.read_text(encoding="utf-8").splitlines()
    if expected_api not in api_lines:
        raise RuntimeError("pinned JVM API dump does not contain the expected DelicateIoApi declaration")

    stage = run_stage(
        "reference-jvm-annotation-metadata",
        [str(javap), "-classpath", str(core_jar), "-v", "kotlinx.io.DelicateIoApi"],
        work,
        work,
        dependencies,
        environment,
        30,
    )
    output = stage_text(stage)
    assertions = upstream_jvm_assertions(output)
    missing = [name for name, passed in assertions.items() if not passed]
    stage["stdout"] = json.dumps(
        {
            "api_dump_line": expected_api,
            "upstream_source_sha256": file_sha256(source_path),
            "jvm_api_dump_sha256": file_sha256(api_path),
            "javap": stage["stdout"],
            "assertions": assertions,
            "missing_assertions": missing,
        },
        ensure_ascii=False,
        sort_keys=True,
    )
    return {"stage": stage, "passed": successful(stage) and not missing}


def upstream_jvm_assertions(output: str) -> dict[str, bool]:
    compact_output = " ".join(output.split())
    retention = re.search(r"kotlin\.annotation\.Retention\s*\((.*?)\)", output, re.DOTALL)
    requires_opt_in = re.search(r"kotlin\.RequiresOptIn\s*\((.*?)\)", output, re.DOTALL)
    return {
        "annotation-interface": "public interface kotlinx.io.DelicateIoApi" in output
        and all(flag in output for flag in ("ACC_PUBLIC", "ACC_INTERFACE", "ACC_ABSTRACT", "ACC_ANNOTATION")),
        "java-annotation-base": "java.lang.annotation.Annotation" in output,
        "runtime-invisible-annotations": "RuntimeInvisibleAnnotations" in output,
        "must-be-documented": "kotlin.annotation.MustBeDocumented" in output,
        "binary-retention": bool(retention and "BINARY" in retention.group(1))
        and "java.lang.annotation.Retention" in output
        and "RetentionPolicy;.CLASS" in output,
        "requires-opt-in-warning": bool(requires_opt_in and "WARNING" in requires_opt_in.group(1)),
        "exact-opt-in-message": DELICATE_API_MESSAGE in compact_output,
    }


def compile_reference_consumers(
    lane: str,
    directory: Path,
    kotlinc: Path,
    java: Path,
    core_jar: Path,
    producer_consumer: bool,
    work: Path,
    dependencies: Path,
    environment: dict[str, str],
    timeout: int,
) -> tuple[list[dict], bool]:
    stages = []
    producer_jar = directory / "Producer.jar"
    if producer_consumer:
        producer_stage = run_stage(
            "reference-producer",
            [str(kotlinc), str(SOURCE), "-classpath", str(core_jar), "-d", str(producer_jar)],
            directory,
            work,
            dependencies,
            environment,
            timeout,
        )
        stages.append(producer_stage)
        if not successful(producer_stage):
            return stages, False

    passed = True
    for label, consumer in (("positive", OPTED_IN), ("negative", UNOPTED)):
        jar = directory / f"{label}.jar"
        classpath = [str(core_jar)]
        if producer_consumer:
            classpath.append(str(producer_jar))
        source_files = [str(consumer)] if producer_consumer else [str(SOURCE), str(consumer)]
        compile_stage = run_stage(
            f"reference-{label}-compile",
            [str(kotlinc), *source_files, "-classpath", os.pathsep.join(classpath), "-include-runtime", "-d", str(jar)],
            directory,
            work,
            dependencies,
            environment,
            timeout,
        )
        stages.append(compile_stage)
        compile_ok = consumer_compile_pass("reference", label, compile_stage)
        passed = passed and compile_ok
        if not successful(compile_stage):
            continue

        class_name = "delicateprobe.consumer.OptedInConsumerKt" if label == "positive" else "delicateprobe.consumer.UnoptedConsumerKt"
        run_classpath = [str(jar), str(core_jar)]
        if producer_consumer:
            run_classpath.append(str(producer_jar))
        run_stage_result = run_stage(
            f"reference-{label}-run",
            [str(java), "-cp", os.pathsep.join(run_classpath), class_name],
            directory,
            work,
            dependencies,
            environment,
            60,
        )
        stages.append(run_stage_result)
        passed = passed and successful(run_stage_result) and run_stage_result["stdout"] == EXPECTED_OUTPUT
    return stages, passed


def build_candidate_stdlib(compiler: Path, optimization: str, output: Path, work: Path,
                           dependencies: Path, environment: dict[str, str], timeout: int) -> tuple[dict, dict]:
    artifact = output / f"KSwiftKStdlib-{optimization}.kklib"
    stage = run_stage(
        f"candidate-stdlib-{optimization}",
        [str(compiler), "--stdlib-only", f"-{optimization}", "--no-incremental", "-o", str(artifact)],
        output,
        work,
        dependencies,
        environment,
        timeout,
    )
    snapshot = artifact_snapshot(artifact)
    valid_artifact = snapshot["exists"] and any(
        (artifact / name).is_file() for name in ("metadata.bin", "manifest.json")
    )
    return stage, {**snapshot, "required_metadata_present": valid_artifact}


def compile_candidate_consumers(
    lane: str,
    optimization: str,
    mode: str,
    directory: Path,
    compiler: Path,
    stdlib: Path | None,
    work: Path,
    dependencies: Path,
    environment: dict[str, str],
    timeout: int,
) -> tuple[list[dict], bool, dict | None]:
    stages = []
    producer_klib = directory / "Producer.kklib"
    if mode == "producer-consumer":
        if stdlib is None:
            return stages, False, None
        producer_stage = run_stage(
            "candidate-producer-klib",
            [str(compiler), f"-{optimization}", "--no-incremental", "--stdlib-library", str(stdlib),
             "--emit", "library", "-m", "DelicateIoApiProducer", str(SOURCE), "-o", str(producer_klib)],
            directory,
            work,
            dependencies,
            environment,
            timeout,
        )
        stages.append(producer_stage)
        if not successful(producer_stage):
            return stages, False, artifact_snapshot(producer_klib)

    producer_artifact = artifact_snapshot(producer_klib) if mode == "producer-consumer" else None
    if mode == "producer-consumer" and not producer_artifact["exists"]:
        return stages, False, producer_artifact

    passed = True
    for label, consumer in (("positive", OPTED_IN), ("negative", UNOPTED)):
        binary = directory / f"{label}-consumer"
        command = [str(compiler), f"-{optimization}", "--no-incremental"]
        if mode == "source":
            command.append("--stdlib-from-source")
        else:
            if stdlib is None:
                return stages, False, producer_artifact
            command += ["--stdlib-library", str(stdlib)]
        if mode == "producer-consumer":
            command += ["-I", str(producer_klib), "--entry-point", "delicateprobe.consumer.main", str(consumer)]
        else:
            command += ["--entry-point", "delicateprobe.consumer.main", str(SOURCE), str(consumer)]
        command += ["-o", str(binary)]
        compile_stage = run_stage(
            f"candidate-{label}-compile",
            command,
            directory,
            work,
            dependencies,
            environment,
            timeout,
        )
        stages.append(compile_stage)
        compile_ok = consumer_compile_pass("candidate", label, compile_stage)
        passed = passed and compile_ok
        if not successful(compile_stage):
            continue
        run_stage_result = run_stage(
            f"candidate-{label}-run",
            [str(binary)],
            directory,
            work,
            dependencies,
            environment,
            60,
        )
        stages.append(run_stage_result)
        passed = passed and successful(run_stage_result) and run_stage_result["stdout"] == EXPECTED_OUTPUT
    return stages, passed, producer_artifact


def receipt_payload(*, case_id: str, lane: str, subject: str, candidate_sha: str,
                    pin: dict, stages: list[dict], passed: bool, work: Path,
                    dependencies: Path, artifacts: list[dict], reassessment: dict | None = None) -> dict:
    output_payload = {
            "case_id": case_id,
            "lane": lane,
            "subject": subject,
            "candidate_kotlin": "2.4.20",
            "reference_kotlin": KOTLIN_REFERENCE_VERSION,
            "upstream_source_sha256": file_sha256(UPSTREAM / "core/common/src/Annotations.kt"),
            "upstream_jvm_api_sha256": file_sha256(UPSTREAM / "core/api/kotlinx-io-core.api"),
            "probe_sha256": {
                path.name: file_sha256(path)
                for path in (SOURCE, OPTED_IN, UNOPTED, STDLIB_ANNOTATIONS, Path(__file__).resolve())
            },
            "consumer_case_count": 2,
            "successful_consumer_case_count": successful_consumer_case_count(subject, stages),
            "artifacts": artifacts,
            "stages": stages,
        }
    if reassessment is not None:
        output_payload["reassessment"] = reassessment
    stdout = json.dumps(output_payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    stderr = "\n".join(stage["stderr"] for stage in stages if stage["stderr"])
    payload = {
        "case_id": case_id,
        "lane": lane,
        "subject": subject,
        "candidate_sha": candidate_sha,
        "reference_version": pin["tag"],
        "reference_commit": pin["commit"],
        "command": [stage["command"] for stage in stages],
        "result": "PASS" if passed else "FAIL",
        "exit_code": 0 if passed else next(
            (stage["exit_code"] for stage in stages if stage["exit_code"] != 0), 1
        ),
        "stdout": stdout,
        "stderr": normalize(stderr, work, dependencies),
    }
    payload["stdout_sha256"] = sha256(payload["stdout"].encode("utf-8"))
    payload["stderr_sha256"] = sha256(payload["stderr"].encode("utf-8"))
    payload["execution_id"] = digest_payload(payload)
    return payload


def recorded_artifact_path(output: Path, subject: str, lane: str, artifact_path: str) -> Path:
    if artifact_path.startswith("KSwiftKStdlib-"):
        return output / artifact_path
    return output / subject / lane / artifact_path


def revalidate_captured_record(record: dict, output: Path, dependencies: Path, pin: dict) -> dict:
    """Reassess captured process outputs after correcting only probe matchers."""
    if (record.get("case_id") != CASE_ID
            or record.get("candidate_sha") != "fd01a5e98145e8295e5b299b0a7190cc8d44e3a7"
            or (record.get("reference_version"), record.get("reference_commit")) != (pin["tag"], pin["commit"])):
        raise RuntimeError("captured probe record does not match the pinned KUU-2613 inputs")
    lane = record["lane"]
    subject = record["subject"]
    if lane not in PROBE_LANES or subject not in {"reference", "candidate"}:
        raise RuntimeError("captured probe record has an unsupported subject or lane")
    if lane == JVM_LANE and subject != "reference":
        raise RuntimeError("captured JVM descriptor record cannot verify a candidate JVM artifact")

    previous = json.loads(record["stdout"])
    stages = previous.get("stages")
    artifacts = previous.get("artifacts")
    if not isinstance(stages, list) or not isinstance(artifacts, list):
        raise RuntimeError("captured probe output is missing stages or artifacts")
    old_probe_hashes = previous.get("probe_sha256", {})
    expected_probe_hashes = {
        SOURCE.name: file_sha256(SOURCE),
        OPTED_IN.name: file_sha256(OPTED_IN),
        UNOPTED.name: file_sha256(UNOPTED),
        STDLIB_ANNOTATIONS.name: file_sha256(STDLIB_ANNOTATIONS),
    }
    if any(old_probe_hashes.get(name) != digest for name, digest in expected_probe_hashes.items()):
        raise RuntimeError("captured probe input hashes no longer match the checked-in fixtures")
    if previous.get("upstream_source_sha256") != file_sha256(UPSTREAM / "core/common/src/Annotations.kt"):
        raise RuntimeError("captured upstream source hash no longer matches the pinned checkout")
    if previous.get("upstream_jvm_api_sha256") != file_sha256(UPSTREAM / "core/api/kotlinx-io-core.api"):
        raise RuntimeError("captured upstream JVM API hash no longer matches the pinned checkout")

    old_script_hash = old_probe_hashes.get(Path(__file__).name)
    if not isinstance(old_script_hash, str) or len(old_script_hash) != 64:
        raise RuntimeError("captured probe receipt is missing its original runner hash")

    for artifact in artifacts:
        if "path" in artifact:
            observed = artifact_snapshot(recorded_artifact_path(output, subject, lane, artifact["path"]))
            if observed != artifact:
                raise RuntimeError(f"captured artifact no longer matches its receipt: {artifact['path']}")
        if "core_jvm_jar" in artifact and artifact["core_jvm_jar"] != file_sha256(
            dependencies / "kotlinx-io-core-jvm-0.9.1.jar"
        ):
            raise RuntimeError("captured reference JVM artifact no longer matches its receipt")
        if "upstream_source" in artifact and artifact["upstream_source"] != expected_probe_hashes.get("Annotations.kt"):
            if artifact["upstream_source"] != file_sha256(UPSTREAM / "core/common/src/Annotations.kt"):
                raise RuntimeError("captured upstream source artifact no longer matches its receipt")
        if "upstream_jvm_api" in artifact and artifact["upstream_jvm_api"] != file_sha256(
            UPSTREAM / "core/api/kotlinx-io-core.api"
        ):
            raise RuntimeError("captured upstream JVM API artifact no longer matches its receipt")

    passed = True
    if subject == "candidate" and lane != JVM_LANE:
        optimization = "O2" if lane.endswith("O2") else "O0"
        if lane.startswith(("stdlib-library-", "producer-consumer-")):
            library_stage = next((stage for stage in stages if stage["name"] == f"candidate-stdlib-{optimization}"), None)
            passed = bool(library_stage and successful(library_stage))
    if lane.startswith("producer-consumer-"):
        producer_stage_name = "candidate-producer-klib" if subject == "candidate" else "reference-producer"
        producer_stage = next((stage for stage in stages if stage["name"] == producer_stage_name), None)
        passed = passed and bool(producer_stage and successful(producer_stage))

    if lane == JVM_LANE:
        jvm_stage = next((stage for stage in stages if stage["name"] == "reference-jvm-annotation-metadata"), None)
        if jvm_stage is None:
            raise RuntimeError("captured JVM descriptor record is missing javap output")
        jvm_capture = json.loads(jvm_stage["stdout"])
        actual_api_line = (
            "public abstract interface annotation class kotlinx/io/DelicateIoApi : "
            "java/lang/annotation/Annotation {"
        )
        api_path = UPSTREAM / "core/api/kotlinx-io-core.api"
        if actual_api_line not in api_path.read_text(encoding="utf-8").splitlines():
            raise RuntimeError("pinned JVM API dump no longer contains the DelicateIoApi declaration")
        assertions = upstream_jvm_assertions(jvm_capture["javap"])
        jvm_capture["previous_assertions"] = jvm_capture.get("assertions", {})
        jvm_capture["assertions"] = assertions
        jvm_capture["missing_assertions"] = [name for name, passed_assertion in assertions.items() if not passed_assertion]
        jvm_stage["stdout"] = json.dumps(jvm_capture, ensure_ascii=False, sort_keys=True)
        passed = passed and successful(jvm_stage) and not jvm_capture["missing_assertions"]

    consumer_passed, successful_cases = evaluate_consumer_stages(subject, lane, stages)
    passed = passed and consumer_passed
    if previous.get("consumer_case_count") != 2:
        raise RuntimeError("captured probe record does not contain exactly two consumer cases")
    return receipt_payload(
        case_id=CASE_ID,
        lane=lane,
        subject=subject,
        candidate_sha=record["candidate_sha"],
        pin=pin,
        stages=stages,
        passed=passed and successful_cases == 2,
        work=output / "tmp",
        dependencies=dependencies,
        artifacts=artifacts,
        reassessment={
            "method": "captured-command-output-recheck",
            "previous_execution_id": record["execution_id"],
            "previous_result": record["result"],
            "previous_runner_sha256": old_script_hash,
        },
    )


def evaluate_consumer_stages(subject: str, lane: str, stages: list[dict]) -> tuple[bool, int]:
    passed = True
    successful_cases = 0
    for label in ("positive", "negative"):
        compile_stage = next(
            (stage for stage in stages if stage["name"] == f"{subject}-{label}-compile"), None
        )
        run_stage_result = next(
            (stage for stage in stages if stage["name"] == f"{subject}-{label}-run"), None
        )
        case_passed = bool(
            compile_stage and run_stage_result
            and consumer_compile_pass(subject, label, compile_stage)
            and successful(run_stage_result)
            and run_stage_result["stdout"] == EXPECTED_OUTPUT
        )
        passed = passed and case_passed
        successful_cases += int(case_passed)
    return passed, successful_cases


def capture_output_artifacts(output: Path, subject: str, lane: str, artifacts: list[dict]) -> list[dict]:
    directory = output / subject / lane
    names = (
        ("positive.jar", "negative.jar", "Producer.jar")
        if subject == "reference"
        else ("positive-consumer", "negative-consumer", "Producer.kklib")
    )
    recorded = {artifact.get("path") for artifact in artifacts if isinstance(artifact, dict)}
    updated = list(artifacts)
    for name in names:
        path = directory / name
        if path.is_file() and name not in recorded:
            updated.append(artifact_snapshot(path))
    return updated


def revalidate_existing_executions(
    output: Path,
    dependencies: Path,
    candidate_sha: str,
    pin: dict,
    version_stage: dict,
) -> list[dict]:
    data = json.loads(EXECUTIONS_PATH.read_text(encoding="utf-8"))
    records = [record for record in data.get("records", []) if record.get("case_id") == CASE_ID]
    expected = {(subject, lane) for lane in CANDIDATE_LANES for subject in ("reference", "candidate")}
    expected.add(("reference", JVM_LANE))
    observed = {(record.get("subject"), record.get("lane")) for record in records}
    if len(records) != len(expected) or observed != expected:
        raise RuntimeError(f"captured execution set is incomplete: expected {len(expected)}, got {len(records)}")
    if any(record.get("candidate_sha") != candidate_sha for record in records):
        raise RuntimeError("captured executions do not all use the requested candidate SHA")

    updated = []
    for record in records:
        updated_record = revalidate_captured_record(record, output, dependencies, pin)
        payload = json.loads(updated_record["stdout"])
        if record["lane"] == JVM_LANE:
            payload["stages"].insert(0, version_stage)
        payload["artifacts"] = capture_output_artifacts(
            output, record["subject"], record["lane"], payload["artifacts"]
        )
        updated_record = receipt_payload(
            case_id=updated_record["case_id"],
            lane=updated_record["lane"],
            subject=updated_record["subject"],
            candidate_sha=updated_record["candidate_sha"],
            pin=pin,
            stages=payload["stages"],
            passed=updated_record["result"] == "PASS",
            work=output / "tmp",
            dependencies=dependencies,
            artifacts=payload["artifacts"],
            reassessment=payload["reassessment"],
        )
        updated.append(updated_record)
    return updated


def successful_consumer_case_count(subject: str, stages: list[dict]) -> int:
    successful_cases = 0
    for label in ("positive", "negative"):
        compile_stage = next((stage for stage in stages if stage["name"].endswith(f"{label}-compile")), None)
        run_stage_result = next((stage for stage in stages if stage["name"].endswith(f"{label}-run")), None)
        if not compile_stage or not run_stage_result:
            continue
        compile_ok = consumer_compile_pass(subject, label, compile_stage)
        if (compile_ok and successful(run_stage_result)
                and run_stage_result["stdout"] == EXPECTED_OUTPUT):
            successful_cases += 1
    return successful_cases


def append_execution_receipts(records: list[dict]) -> None:
    if EXECUTIONS_PATH.exists():
        data = json.loads(EXECUTIONS_PATH.read_text(encoding="utf-8"))
    else:
        data = {"schema_version": 1, "records": []}
    if data.get("schema_version") != 1 or not isinstance(data.get("records"), list):
        raise RuntimeError("local probe execution receipt file has an unsupported schema")
    retained = [entry for entry in data["records"] if entry.get("case_id") != CASE_ID]
    retained.extend(records)
    temporary = EXECUTIONS_PATH.with_suffix(".json.tmp")
    temporary.write_text(
        json.dumps({"schema_version": 1, "records": retained}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    temporary.replace(EXECUTIONS_PATH)


def clear_inventory_evidence() -> None:
    evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
    if evidence.get("schema_version") != 1 or not isinstance(evidence.get("records"), list):
        raise RuntimeError("validation evidence file has an unsupported schema")
    retained = [record for record in evidence["records"] if record.get("row_id") not in AUDITED_ROW_IDS]
    temporary = EVIDENCE_PATH.with_suffix(".json.tmp")
    temporary.write_text(
        json.dumps({"schema_version": 1, "records": retained}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    temporary.replace(EVIDENCE_PATH)


def write_inventory_evidence(candidate_sha: str, records: list[dict], pin: dict) -> None:
    by_key = {(record["subject"], record["lane"]): record for record in records}
    evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
    existing = [record for record in evidence["records"] if record["row_id"] not in AUDITED_ROW_IDS]
    created = []
    for row_id, lanes in ROW_LANES.items():
        hashes_run = subprocess.run(
            [sys.executable, str(GENERATOR), "--show-input-hashes", row_id],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        if hashes_run.returncode != 0:
            raise RuntimeError(f"could not calculate current input hashes for {row_id}: {hashes_run.stderr}")
        hashes = json.loads(hashes_run.stdout)
        executions = []
        for lane in lanes:
            reference = by_key[("reference", lane)]
            candidate = by_key[("candidate", lane)]
            if reference["result"] != "PASS" or candidate["result"] != "PASS":
                raise RuntimeError(f"cannot promote {row_id}; {lane} did not pass on both sides")
            executions.append({
                "case_id": CASE_ID,
                "lane": lane,
                "reference": {"execution_id": reference["execution_id"], "result": "PASS", "exit_code": 0},
                "candidate": {"execution_id": candidate["execution_id"], "result": "PASS", "exit_code": 0},
            })
        created.append({
            "row_id": row_id,
            "candidate_sha": candidate_sha,
            "reference_version": pin["tag"],
            "reference_commit": pin["commit"],
            **{key: hashes[key] for key in ("implementation_input_sha256", "test_input_sha256")},
            "compatibility_obligations": ["jvm-descriptor"] if row_id.startswith("jvm-") else ["native-source", "native-bridge"],
            "executions": executions,
        })
    temporary = EVIDENCE_PATH.with_suffix(".json.tmp")
    temporary.write_text(
        json.dumps({"schema_version": 1, "records": existing + created}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    temporary.replace(EVIDENCE_PATH)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=ROOT / ".build/debug/kswiftc")
    parser.add_argument("--candidate-package-root", type=Path, default=ROOT)
    parser.add_argument("--reference-kotlinc", type=Path, required=True)
    parser.add_argument("--java", type=Path, default=Path("java"))
    parser.add_argument("--javap", type=Path, default=Path("javap"))
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--dependency-dir", type=Path)
    parser.add_argument("--candidate-sha")
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument(
        "--revalidate-existing",
        action="store_true",
        help="reassess saved command outputs and artifact hashes without rerunning compilers",
    )
    args = parser.parse_args()

    clear_inventory_evidence()
    pin = reference_pin()
    compiler = args.compiler.resolve()
    candidate_package_root = args.candidate_package_root.resolve()
    kotlinc = args.reference_kotlinc.resolve()
    java = args.java.resolve() if args.java.exists() else args.java
    javap = args.javap.resolve() if args.javap.exists() else args.javap
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    dependencies = args.dependency_dir.resolve() if args.dependency_dir else output / "dependencies"
    dependencies.mkdir(parents=True, exist_ok=True)
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    core_jar = load_locked_core_jar(lock, dependencies)

    if not (candidate_package_root / "Package.swift").is_file():
        raise RuntimeError("candidate package root must contain Package.swift")
    sha_run = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=candidate_package_root,
        text=True,
        capture_output=True,
        check=True,
    )
    candidate_package_sha = sha_run.stdout.strip()
    candidate_sha = args.candidate_sha or candidate_package_sha
    if not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", candidate_sha):
        raise RuntimeError("candidate SHA must be a full 40- or 64-character lowercase Git hash")
    if candidate_sha != candidate_package_sha:
        raise RuntimeError(
            f"candidate package root is {candidate_package_sha}, expected candidate SHA {candidate_sha}"
        )

    common_tmp = output / "tmp"
    common_tmp.mkdir(exist_ok=True)
    environment = {
        **os.environ,
        "TMPDIR": str(common_tmp) + os.sep,
        "KSWIFTK_PACKAGE_ROOT": str(candidate_package_root),
        "KSWIFTK_STDLIB_CACHE_DIR": str(output / "isolated-stdlib-cache"),
    }

    if args.revalidate_existing:
        if not kotlinc.is_file():
            raise RuntimeError("the pinned Kotlin reference compiler must exist")
        version_work = output / "reference-version"
        version_work.mkdir(exist_ok=True)
        version_stage = check_kotlinc(kotlinc, version_work, dependencies, environment)
        if not successful(version_stage):
            raise RuntimeError(stage_text(version_stage))
        records = revalidate_existing_executions(output, dependencies, candidate_sha, pin, version_stage)
        append_execution_receipts(records)
        klib_passed = all(
            record["result"] == "PASS"
            for record in records
            if record["lane"] in CANDIDATE_LANES
        )
        if not klib_passed:
            print("Captured DelicateIoApi KLIB runs still contain failures; inventory evidence was not promoted.", file=sys.stderr)
            return 1
        write_inventory_evidence(candidate_sha, records, pin)
        generated = subprocess.run(
            [sys.executable, str(GENERATOR), "--write"], cwd=ROOT, text=True, capture_output=True, check=False
        )
        sys.stdout.write(generated.stdout)
        sys.stderr.write(generated.stderr)
        if generated.returncode != 0:
            return generated.returncode
        jvm_result = next(record["result"] for record in records if record["lane"] == JVM_LANE)
        print(
            f"Revalidated captured KUU-2613 KLIB runs for candidate {candidate_sha}; "
            f"JVM reference={jvm_result}, candidate JVM ABI remains unverified",
            file=sys.stderr,
        )
        return 0

    if not compiler.is_file() or not kotlinc.is_file():
        raise RuntimeError("both kswiftc and the pinned Kotlin reference compiler must exist")

    version_work = output / "reference-version"
    version_work.mkdir(exist_ok=True)
    version_stage = check_kotlinc(kotlinc, version_work, dependencies, environment)
    if not successful(version_stage):
        raise RuntimeError(stage_text(version_stage))

    candidate_standard_libraries = {}
    candidate_library_stages = {}
    for optimization in ("O0", "O2"):
        print(f"BUILD candidate standard library {optimization}", file=sys.stderr, flush=True)
        stage, artifact = build_candidate_stdlib(
            compiler, optimization, output, common_tmp, dependencies, environment, args.timeout
        )
        candidate_library_stages[optimization] = stage
        if successful(stage) and artifact["required_metadata_present"]:
            candidate_standard_libraries[optimization] = output / artifact["path"]
        else:
            print(f"FAIL candidate standard library {optimization}", file=sys.stderr, flush=True)

    probe_records = []
    all_klib_passed = True
    jvm_reference_passed = None
    for lane in (JVM_LANE, *CANDIDATE_LANES):
        optimization = "O2" if lane.endswith("O2") else "O0"
        mode = lane.split("-", 1)[0]
        subjects = ("reference",) if lane == JVM_LANE else ("reference", "candidate")
        for subject in subjects:
            directory = output / subject / lane
            directory.mkdir(parents=True, exist_ok=True)
            print(f"RUN {subject} {lane}", file=sys.stderr, flush=True)
            stages = []
            artifacts = []
            if subject == "reference":
                if lane == JVM_LANE:
                    stages.append(version_stage)
                    jvm = inspect_upstream_jvm_declaration(core_jar, javap, directory, dependencies, environment)
                    stages.append(jvm["stage"])
                    artifacts.append({
                        "upstream_source": file_sha256(UPSTREAM / "core/common/src/Annotations.kt"),
                        "upstream_jvm_api": file_sha256(UPSTREAM / "core/api/kotlinx-io-core.api"),
                        "core_jvm_jar": file_sha256(core_jar),
                    })
                    consumer_stages, consumer_passed = compile_reference_consumers(
                        lane, directory, kotlinc, java, core_jar, False,
                        common_tmp, dependencies, environment, args.timeout,
                    )
                    stages.extend(consumer_stages)
                    passed = jvm["passed"] and consumer_passed
                else:
                    consumer_stages, consumer_passed = compile_reference_consumers(
                        lane, directory, kotlinc, java, core_jar,
                        producer_consumer=(mode == "producer"),
                        work=common_tmp,
                        dependencies=dependencies,
                        environment=environment,
                        timeout=args.timeout,
                    )
                    stages.extend(consumer_stages)
                    passed = consumer_passed
                    artifacts.append({"core_jvm_jar": file_sha256(core_jar)})
            else:
                stdlib = candidate_standard_libraries.get(optimization)
                if mode == "stdlib":
                    mode = "stdlib-library"
                elif mode == "producer":
                    mode = "producer-consumer"
                if mode in {"stdlib-library", "producer-consumer"}:
                    library_build = candidate_library_stages.get(optimization, {})
                    if library_build:
                        stages.append(library_build)
                candidate_stages, candidate_passed, producer_artifact = compile_candidate_consumers(
                    lane, optimization, mode, directory, compiler, stdlib,
                    common_tmp, dependencies, environment, args.timeout,
                )
                stages.extend(candidate_stages)
                passed = candidate_passed
                if stdlib:
                    artifacts.append(artifact_snapshot(stdlib))
                if producer_artifact:
                    artifacts.append(producer_artifact)

            artifacts = capture_output_artifacts(output, subject, lane, artifacts)

            receipt = receipt_payload(
                case_id=CASE_ID,
                lane=lane,
                subject=subject,
                candidate_sha=candidate_sha,
                pin=pin,
                stages=stages,
                passed=passed,
                work=common_tmp,
                dependencies=dependencies,
                artifacts=artifacts,
            )
            probe_records.append(receipt)
            append_execution_receipts(probe_records)
            if lane == JVM_LANE:
                jvm_reference_passed = passed
            else:
                all_klib_passed = all_klib_passed and passed
            print(f"{'PASS' if passed else 'FAIL'} {subject} {lane} ({receipt['execution_id']})", file=sys.stderr, flush=True)

    if not all_klib_passed:
        print("DelicateIoApi KLIB probe has failed or incomplete lanes; inventory evidence was not promoted.", file=sys.stderr)
        return 1

    write_inventory_evidence(candidate_sha, probe_records, pin)
    generated = subprocess.run(
        [sys.executable, str(GENERATOR), "--write"], cwd=ROOT, text=True, capture_output=True, check=False
    )
    sys.stdout.write(generated.stdout)
    sys.stderr.write(generated.stderr)
    if generated.returncode != 0:
        return generated.returncode
    print(
        f"Wrote passing KUU-2613 KLIB evidence for candidate {candidate_sha}; "
        f"JVM reference={'PASS' if jvm_reference_passed else 'FAIL'}, candidate JVM ABI row remains unverified",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, json.JSONDecodeError, StopIteration) as error:
        print(f"DelicateIoApi probe failed: {error}", file=sys.stderr)
        raise SystemExit(1)
