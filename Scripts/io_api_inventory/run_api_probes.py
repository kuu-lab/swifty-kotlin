#!/usr/bin/env python3
"""Run registered, row-specific API probes and optionally record passing evidence."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PROBE_DIR = HERE / "probes"
UPSTREAM = HERE / "upstream/kotlinx-io-0.9.1"
REFERENCE_LOCK = ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json"
INVENTORY_LOCK = HERE / "upstream-lock.json"
CATALOG_PATH = HERE / "api-probe-catalog.json"
EVIDENCE_PATH = HERE / "api-validation-evidence.json"
PROBE_RUN_EVIDENCE_PATH = HERE / "api-probe-run-evidence.json"
BUILDER_ROW = "klib-bb1a86c235fe5d90"
JVM_ROW = "jvm-1d1d46e584ca16cc"
EXPECTED_OUTPUT = b"BYTESTRINGBUILDER_CLASS_SHAPE_PASS\n"
NEGATIVE_SOURCE = PROBE_DIR / "ByteStringBuilderSubclassRejected.kt"
POSITIVE_SOURCE = PROBE_DIR / "ByteStringBuilderClassShape.kt"
PRODUCER_SOURCE = PROBE_DIR / "ByteStringBuilderClassShapeProducer.kt"
CONSUMER_SOURCE = PROBE_DIR / "ByteStringBuilderClassShapeConsumer.kt"
JVM_PROBE_SOURCE = PROBE_DIR / "ByteStringBuilderJvmClassProbe.java"
SWIFT_TEST_FILTER = "CompilerCoreTests.ByteStringBuilderClassShapeTests"
EXPECTED_REFERENCE_REPOSITORY = "https://github.com/Kotlin/kotlinx-io"
EXPECTED_REFERENCE_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"
EXPECTED_REFERENCE_VERSION = "0.9.1"
EXPECTED_KOTLIN_VERSION = "2.3.10"


def validate_final_class_diagnostic(diagnostic: str, compiler_kind: str) -> tuple[str, str]:
    if compiler_kind == "kswiftc":
        expected = ("KSWIFTK-SEMA-FINAL", "kotlinx.io.bytestring.ByteStringBuilder")
    elif compiler_kind == "kotlinc":
        expected = ("this type is final", "cannot be extended")
    else:
        raise RuntimeError(f"unsupported compiler kind for final-class probe: {compiler_kind}")
    combined = diagnostic.lower()
    if any(term.lower() not in combined for term in expected):
        raise RuntimeError(f"final-class rejection did not match {compiler_kind}: {diagnostic}")
    return expected


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_hash(path: Path) -> dict[str, str]:
    if path.is_file():
        return {path.name: sha(path)}
    return {
        file.relative_to(path).as_posix(): sha(file)
        for file in sorted(path.rglob("*"))
        if file.is_file()
    }


def save_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def normalize_validation_evidence_schema(evidence: dict) -> dict:
    sys.path.insert(0, str(HERE))
    import generate

    schema_version = evidence.get("schema_version")
    records = evidence.get("records")
    if (type(schema_version) is not int
            or schema_version not in (1, generate.VALIDATION_EVIDENCE_SCHEMA_VERSION)
            or not isinstance(records, list)
            or any(not isinstance(record, dict) for record in records)):
        raise RuntimeError("unexpected api-validation-evidence schema")
    if schema_version == 1:
        evidence["schema_version"] = generate.VALIDATION_EVIDENCE_SCHEMA_VERSION
        evidence["records"] = [
            {**record, "evidence_source": "upstream-catalog"}
            for record in records
        ]
    return evidence


class ProbeRunner:
    def __init__(self, output: Path, java: Path, kotlin_home: Path, dependencies: Path,
                 compiler: Path, timeout: float) -> None:
        self.output = output
        self.java = java.resolve()
        self.javac = self.java.parent / "javac"
        self.kotlin_home = kotlin_home.resolve()
        self.kotlinc = self.kotlin_home / "bin/kotlinc"
        self.dependencies = dependencies.resolve()
        self.compiler = compiler.resolve()
        self.timeout = timeout
        self.results: list[dict] = []
        self.lock = json.loads(REFERENCE_LOCK.read_text(encoding="utf-8"))
        inventory_lock = json.loads(INVENTORY_LOCK.read_text(encoding="utf-8"))
        expected_identity = (
            EXPECTED_REFERENCE_REPOSITORY,
            EXPECTED_REFERENCE_VERSION,
            EXPECTED_REFERENCE_COMMIT,
            EXPECTED_KOTLIN_VERSION,
        )
        reference_identity = (
            self.lock.get("repository"),
            self.lock.get("kotlinx_io"),
            self.lock.get("commit"),
            self.lock.get("kotlin"),
        )
        inventory_identity = (
            inventory_lock.get("repository"),
            inventory_lock.get("tag"),
            inventory_lock.get("commit"),
            inventory_lock.get("kotlinCompilerVersion"),
        )
        if reference_identity != expected_identity or inventory_identity != expected_identity:
            raise ValueError("both reference locks must pin kotlinx-io 0.9.1 at the expected commit and Kotlin 2.3.10")
        locked_tests = {
            entry["path"]: (entry.get("gitBlobSha"), entry.get("size"))
            for entry in inventory_lock.get("upstreamTests", [])
        }
        reference_tests = {
            entry["path"]: (entry.get("git_blob_sha"), entry.get("bytes"))
            for entry in self.lock.get("upstream_files", [])
        }
        if reference_tests != locked_tests:
            raise ValueError("the JVM reference file list differs from the API inventory's pinned upstream tests")
        locked_jars = {
            (entry["coordinate"], entry["url"], entry["sha256"])
            for entry in inventory_lock.get("mavenArtifacts", [])
        }
        reference_jars = {
            (entry["coordinate"], entry["url"], entry["sha256"])
            for entry in self.lock.get("jvm_artifacts", [])
            if "kotlinx-io-" in entry.get("url", "")
        }
        if reference_jars != locked_jars:
            raise ValueError("JVM reference artifacts differ from the API inventory's pinned Maven artifacts")
        for record in self.lock["sdk_files"]:
            path = self.kotlin_home / record["path"]
            if not path.is_file() or sha(path) != record["sha256"]:
                raise ValueError(f"missing or unlocked Kotlin reference SDK file: {path}")
        self.jars: list[Path] = []
        for record in self.lock["jvm_artifacts"]:
            if "kotlinx-io-" not in record["url"]:
                continue
            jar = self.dependencies / record["url"].rsplit("/", 1)[1]
            if not jar.is_file() or sha(jar) != record["sha256"]:
                raise ValueError(f"missing or unlocked JVM reference artifact: {jar}")
            self.jars.append(jar.resolve())
        if not self.jars:
            raise ValueError("the reference lock did not provide the kotlinx-io JVM jars")

    def stage(self, command: list[str], directory: Path, name: str,
              expected_code: int = 0, env: dict[str, str] | None = None,
              cwd: Path | None = None) -> dict:
        directory.mkdir(parents=True, exist_ok=True)
        stdout_path = directory / f"{name}.stdout"
        stderr_path = directory / f"{name}.stderr"
        environment = os.environ.copy()
        environment.update(env or {})
        started = time.monotonic()
        try:
            completed = subprocess.run(
                command, cwd=cwd or directory, env=environment, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=self.timeout, check=False,
            )
            return_code = completed.returncode
            stdout = completed.stdout
            stderr = completed.stderr
        except subprocess.TimeoutExpired as error:
            return_code = None
            stdout = error.stdout or b""
            stderr = error.stderr or b""
        stdout_path.write_bytes(stdout)
        stderr_path.write_bytes(stderr)
        result = {
            "stage": name,
            "command": command,
            "expected_exit_code": expected_code,
            "exit_code": return_code,
            "elapsed_seconds": round(time.monotonic() - started, 3),
            "stdout_path": str(stdout_path),
            "stderr_path": str(stderr_path),
            "stdout_sha256": hashlib.sha256(stdout).hexdigest(),
            "stderr_sha256": hashlib.sha256(stderr).hexdigest(),
            "stdout": stdout.decode(errors="replace"),
            "stderr": stderr.decode(errors="replace"),
        }
        if return_code != expected_code:
            result["status"] = "FAIL"
            self.results.append(result)
            raise RuntimeError(f"{name} expected exit {expected_code}, got {return_code}: {stderr.decode(errors='replace')}")
        result["status"] = "PASS"
        self.results.append(result)
        return result

    def check_negative(self, command: list[str], directory: Path, name: str,
                       compiler_kind: str, env: dict[str, str] | None = None) -> dict:
        result = self.stage(command, directory, name, expected_code=1, env=env)
        diagnostic = result["stderr"] + result["stdout"]
        try:
            expected = validate_final_class_diagnostic(diagnostic, compiler_kind)
        except RuntimeError as error:
            raise RuntimeError(f"{name} failed for an unexpected reason: {diagnostic}") from error
        result["expected_rejection"] = list(expected)
        return result

    def reference_environment(self) -> dict[str, str]:
        return {"JAVA_HOME": str(self.java.parent.parent)}

    def jvm_probe(self, directory: Path) -> list[dict]:
        classes = directory / "jvm-probe-classes"
        classes.mkdir(parents=True, exist_ok=True)
        classpath = os.pathsep.join(map(str, [classes, *self.jars]))
        results = [
            self.stage([str(self.javac), "-d", str(classes), str(JVM_PROBE_SOURCE)], directory, "javac"),
            self.stage([str(self.java), "-cp", classpath, "ByteStringBuilderJvmClassProbe"], directory, "jvm-class"),
        ]
        if (directory / "jvm-class.stdout").read_bytes() != b"BYTESTRINGBUILDER_JVM_CLASS_SHAPE_PASS\n":
            raise RuntimeError("JVM class reflection output did not match the pinned public-final shape")
        results.append({"stage": "jvm-class-files", "status": "PASS",
                        "class_files_sha256": tree_hash(classes)})
        return results

    def reference_lane(self, row_id: str, lane: str, directory: Path) -> dict:
        classpath = os.pathsep.join(map(str, self.jars))
        java_env = self.reference_environment()
        stages: list[dict] = []
        if row_id == JVM_ROW:
            stages.extend(self.jvm_probe(directory))
            positive_jar = directory / "reference-positive.jar"
            stages.append(self.stage([
                str(self.kotlinc), str(POSITIVE_SOURCE), "-classpath", classpath,
                "-include-runtime", "-d", str(positive_jar),
            ], directory, "reference-positive-compile", env=java_env))
            stages.append(self.stage([
                str(self.java), "-cp", os.pathsep.join(map(str, [positive_jar, *self.jars])),
                "io.gate.bytestring.ByteStringBuilderClassShapeKt",
            ], directory, "reference-positive-run", env=java_env))
            negative_dir = directory / "negative"
            stages.append(self.check_negative([
                str(self.kotlinc), str(NEGATIVE_SOURCE), "-classpath", classpath,
                "-d", str(negative_dir / "negative.jar"),
            ], negative_dir, "reference-negative-compile", "kotlinc", env=java_env))
        elif lane.startswith("producer-consumer-"):
            producer_jar = directory / "reference-producer.jar"
            stages.append(self.stage([
                str(self.kotlinc), "-module-name", "ByteStringBuilderProbeProducer",
                str(PRODUCER_SOURCE), "-classpath", classpath, "-d", str(producer_jar),
            ], directory, "reference-producer-compile", env=java_env))
            positive_jar = directory / "reference-consumer.jar"
            consumer_classpath = os.pathsep.join(map(str, [producer_jar, *self.jars]))
            stages.append(self.stage([
                str(self.kotlinc), str(CONSUMER_SOURCE), "-classpath", consumer_classpath,
                "-include-runtime", "-d", str(positive_jar),
            ], directory, "reference-consumer-compile", env=java_env))
            stages.append(self.stage([
                str(self.java), "-cp", os.pathsep.join(map(str, [positive_jar, producer_jar, *self.jars])),
                "io.gate.bytestring.consumer.ByteStringBuilderClassShapeConsumerKt",
            ], directory, "reference-consumer-run", env=java_env))
            negative_dir = directory / "negative"
            stages.append(self.check_negative([
                str(self.kotlinc), str(NEGATIVE_SOURCE), "-classpath", consumer_classpath,
                "-d", str(negative_dir / "negative.jar"),
            ], negative_dir, "reference-negative-compile", "kotlinc", env=java_env))
        else:
            positive_jar = directory / "reference-positive.jar"
            stages.append(self.stage([
                str(self.kotlinc), str(POSITIVE_SOURCE), "-classpath", classpath,
                "-include-runtime", "-d", str(positive_jar),
            ], directory, "reference-positive-compile", env=java_env))
            stages.append(self.stage([
                str(self.java), "-cp", os.pathsep.join(map(str, [positive_jar, *self.jars])),
                "io.gate.bytestring.ByteStringBuilderClassShapeKt",
            ], directory, "reference-positive-run", env=java_env))
            negative_dir = directory / "negative"
            stages.append(self.check_negative([
                str(self.kotlinc), str(NEGATIVE_SOURCE), "-classpath", classpath,
                "-d", str(negative_dir / "negative.jar"),
            ], negative_dir, "reference-negative-compile", "kotlinc", env=java_env))
        positive_runs = [stage for stage in stages if stage["stage"] in {"reference-positive-run", "reference-consumer-run"}]
        if any(Path(stage["stdout_path"]).read_bytes() != EXPECTED_OUTPUT for stage in positive_runs):
            raise RuntimeError("JVM reference consumer output did not match the expected shape marker")
        if any(Path(stage["stdout_path"]).read_bytes() != b"BYTESTRINGBUILDER_JVM_CLASS_SHAPE_PASS\n"
               for stage in stages if stage["stage"] == "jvm-class"):
            raise RuntimeError("JVM reflection probe did not confirm the classfile shape")
        return {"status": "PASS", "stages": stages, "jvm_jars_sha256": {str(path): sha(path) for path in self.jars}}

    def candidate_base(self, optimization: str, route: str, stdlib: Path) -> list[str]:
        command = [str(self.compiler), f"-{optimization}", "--no-incremental"]
        if route == "source":
            command.append("--stdlib-from-source")
        else:
            command.extend(["--stdlib-library", str(stdlib)])
        return command

    def candidate_lane(self, lane: str, directory: Path, stdlib: Path) -> dict:
        route, optimization = lane.rsplit("-", 1)
        command = self.candidate_base(optimization, route, stdlib)
        stages: list[dict] = []
        producer = None
        producer_files = None
        if route == "producer-consumer":
            producer = directory / "Producer.kklib"
            stages.append(self.stage(command + [
                "--emit", "library", "-m", "ByteStringBuilderProbeProducer",
                str(PRODUCER_SOURCE), "-o", str(producer),
            ], directory, "candidate-producer-compile"))
            producer_files = tree_hash(producer)
            if ("metadata.bin" not in producer_files
                    or not any(name.startswith("objects/") for name in producer_files)):
                raise RuntimeError("producer artifact must contain metadata and compiled objects")
            positive_sources = [str(CONSUMER_SOURCE)]
        else:
            positive_sources = [str(POSITIVE_SOURCE)]
        executable = directory / "candidate"
        compile_command = list(command)
        if producer is not None:
            compile_command.extend(["-I", str(producer)])
            compile_command.extend(["--entry-point", "io.gate.bytestring.consumer.main"])
        compile_command.extend([*positive_sources, "-o", str(executable)])
        stages.append(self.stage(compile_command, directory, "candidate-positive-compile"))
        stages.append(self.stage([str(executable)], directory, "candidate-positive-run"))
        if (directory / "candidate-positive-run.stdout").read_bytes() != EXPECTED_OUTPUT:
            raise RuntimeError("candidate consumer output did not match the expected shape marker")
        executable_sha256 = sha(executable)

        negative_dir = directory / "negative"
        negative_command = list(command)
        if producer is not None:
            negative_command.extend(["-I", str(producer)])
        negative_command.extend([str(NEGATIVE_SOURCE), "-o", str(negative_dir / "negative")])
        stages.append(self.check_negative(negative_command, negative_dir,
                                         "candidate-negative-compile", "kswiftc"))
        return {
            "status": "PASS",
            "stages": stages,
            "stdlib_files_sha256": tree_hash(stdlib),
            "producer_files_sha256": producer_files,
            "executable_sha256": executable_sha256,
        }

    def candidate_jvm_row(self, directory: Path, stdlib: Path) -> dict:
        stages = [self.stage([
            "bash", "Scripts/swift_test.sh", "--no-parallel", "--filter", SWIFT_TEST_FILTER,
        ], directory, "candidate-sema-shape-test", cwd=ROOT)]
        stages.append(self.stage([
            str(self.compiler), "-O0", "--no-incremental", "--stdlib-library", str(stdlib),
            str(POSITIVE_SOURCE), "-o", str(directory / "candidate"),
        ], directory, "candidate-positive-compile"))
        stages.append(self.stage([str(directory / "candidate")], directory, "candidate-positive-run"))
        if (directory / "candidate-positive-run.stdout").read_bytes() != EXPECTED_OUTPUT:
            raise RuntimeError("candidate library consumer output did not match the expected shape marker")
        executable_sha256 = sha(directory / "candidate")
        negative_dir = directory / "negative"
        stages.append(self.check_negative([
            str(self.compiler), "-O0", "--no-incremental", "--stdlib-library", str(stdlib),
            str(NEGATIVE_SOURCE), "-o", str(negative_dir / "negative"),
        ], negative_dir, "candidate-negative-compile", "kswiftc"))
        return {
            "status": "PASS",
            "stages": stages,
            "stdlib_files_sha256": tree_hash(stdlib),
            "executable_sha256": executable_sha256,
        }


def load_inventory() -> list[dict[str, str]]:
    with (HERE / "api-inventory.tsv").open(encoding="utf-8", newline="") as stream:
        rows = {row["row_id"]: row for row in csv.DictReader(stream, delimiter="\t")}
    return [rows[row_id] for row_id in (BUILDER_ROW, JVM_ROW)]


def run_git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def build_record(row: dict[str, str], probe: dict, candidate_sha: str,
                 results: dict[str, dict]) -> dict:
    sys.path.insert(0, str(HERE))
    import generate

    case_id = probe["case_id"]
    case_spec = generate.LOCAL_PROBE_EVIDENCE_CASES.get(case_id)
    if case_spec is None or row["row_id"] not in case_spec["row_ids"]:
        raise RuntimeError(f"API probe is not registered for local evidence: {row['row_id']} {case_id}")
    executions = []
    for lane in probe["lanes"]:
        reference = results[f"{row['row_id']}:{lane}:reference"]
        candidate = results[f"{row['row_id']}:{lane}:candidate"]
        executions.append({
            "case_id": case_id,
            "lane": lane,
            "reference": {
                "execution_id": generate.local_probe_execution_id(
                    candidate_sha, EXPECTED_REFERENCE_COMMIT, case_id, lane, "reference"
                ),
                "result": reference["status"],
                "exit_code": 0,
                "method": case_spec["methods"]["reference"],
            },
            "candidate": {
                "execution_id": generate.local_probe_execution_id(
                    candidate_sha, EXPECTED_REFERENCE_COMMIT, case_id, lane, "candidate"
                ),
                "result": candidate["status"],
                "exit_code": 0,
                "method": case_spec["methods"]["candidate"],
            },
        })
    return {
        "row_id": row["row_id"],
        "candidate_sha": candidate_sha,
        "reference_version": EXPECTED_REFERENCE_VERSION,
        "reference_commit": EXPECTED_REFERENCE_COMMIT,
        **generate.validation_input_hashes(row),
        "compatibility_obligations": generate.validation_obligations(row),
        "evidence_source": "local-probe",
        "executions": executions,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--kotlin-home", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True)
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compile-timeout", type=float, default=600)
    parser.add_argument("--record-evidence", action="store_true",
                        help="add the two passing records to api-validation-evidence.json")
    args = parser.parse_args(argv)
    if sys.platform != "darwin":
        parser.error("the ByteStringBuilder candidate probes require a macOS host")
    if not args.compile_timeout > 0:
        parser.error("--compile-timeout must be positive")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    compiler = args.compiler.resolve()
    kotlin_home = args.kotlin_home.resolve()
    java = args.java.resolve()
    expected_compiler = (ROOT / ".build/debug/kswiftc").resolve()
    if compiler != expected_compiler:
        parser.error(f"--compiler must be the current checkout's freshly built {expected_compiler}")
    if not (kotlin_home / "bin/kotlinc").is_file():
        parser.error("Kotlin reference installation was not found")
    if not java.is_file() or not (java.parent / "javac").is_file():
        parser.error("a JDK with java and javac is required")

    candidate_sha = run_git("rev-parse", "HEAD")
    if run_git("status", "--porcelain"):
        parser.error("probe runs require a clean committed candidate")
    manifest = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    probes = {probe["row_id"]: probe for probe in manifest["probes"]}
    inventory = {row["row_id"]: row for row in load_inventory()}
    reference_lock = json.loads(REFERENCE_LOCK.read_text(encoding="utf-8"))
    locked_upstream_hashes = {
        entry["path"]: entry["sha256"]
        for entry in reference_lock.get("upstream_files", [])
    }
    external_input_hashes = {}
    input_paths = {
        ROOT / "Scripts/io_api_inventory/generate.py",
        ROOT / "Scripts/io_api_inventory/run_api_probes.py",
        ROOT / "Scripts/io_api_inventory/api-probe-catalog.json",
        ROOT / "Scripts/io_api_inventory/upstream-lock.json",
        REFERENCE_LOCK,
    }
    for row_id, row in inventory.items():
        probe = probes[row_id]
        input_paths.update(ROOT / path for path in probe["probe_paths"])
        input_paths.update(UPSTREAM / path for path in probe["upstream_reference_paths"])
        for reference in row.get("upstream_source_refs", "").split(";"):
            relative = reference.split("#", 1)[0]
            input_paths.add(UPSTREAM / relative.rsplit(":", 1)[0]
                            if relative.rsplit(":", 1)[-1].isdigit()
                            else UPSTREAM / relative)
        for reference in row.get("upstream_test_refs", "").split(";"):
            if reference and reference != "none":
                relative = reference.split("#", 1)[0]
                path = UPSTREAM / relative
                if path.is_file():
                    input_paths.add(path)
                else:
                    digest = locked_upstream_hashes.get(relative)
                    if digest is None:
                        raise RuntimeError(f"no pinned raw hash for upstream test input {relative}")
                    external_input_hashes[f"upstream/{relative}"] = digest
        for field in ("local_candidate_refs", "local_implementation_refs", "local_test_refs"):
            for reference in row.get(field, "").split(";"):
                relative = reference.split("#", 1)[0]
                if relative and relative != "none":
                    if relative.rsplit(":", 1)[-1].isdigit():
                        relative = relative.rsplit(":", 1)[0]
                    input_paths.add(ROOT / relative)
    before = {
        str(path.relative_to(ROOT)): sha(path)
        for path in sorted(input_paths)
        if path.is_file()
    }
    before.update(external_input_hashes)
    summary = {
        "schema_version": 1,
        "candidate_sha": candidate_sha,
        "reference_version": EXPECTED_REFERENCE_VERSION,
        "reference_kotlin": EXPECTED_KOTLIN_VERSION,
        "reference_commit": EXPECTED_REFERENCE_COMMIT,
        "compiler_sha256": None,
        "kotlin_compiler_sha256": sha(kotlin_home / "bin/kotlinc"),
        "java_sha256": sha(java),
        "jvm_reference_jars_sha256": {},
        "input_files_sha256": before,
        "unexecuted_scope": [
            "Upstream ByteStringBuilderTest methods: the suite-reference is not a class-shape assertion; constructor behavior remains in its original ticket",
            "Apple reference lane: ByteStringBuilder is a common declaration with no Apple-specific actual",
            "Unrelated API rows and the full KUU-1826 matrix",
        ],
        "rows": [],
        "status": "RUNNING",
    }
    runner = None
    errors = []
    result_map: dict[str, dict] = {}
    try:
        runner = ProbeRunner(output, java, kotlin_home, args.dependencies.resolve(), compiler, args.compile_timeout)
        compiler_build = runner.stage(
            ["swift", "build", "--product", "kswiftc"], output,
            "candidate-compiler-build", cwd=ROOT,
        )
        summary["candidate_compiler_build"] = compiler_build
        if not compiler.is_file():
            raise RuntimeError("the current checkout's kswiftc product was not produced")
        summary["compiler_sha256"] = sha(compiler)
        summary["jvm_reference_jars_sha256"] = {str(path): sha(path) for path in runner.jars}
        java_version = runner.stage([str(java), "-version"], output, "java-version")
        if 'version "21' not in java_version["stderr"]:
            raise RuntimeError("the locked Kotlin/JVM reference requires a Java 21 runtime")
        summary["java_version"] = java_version
        kotlin_version = runner.stage(
            [str(runner.kotlinc), "-version"], output, "reference-kotlin-version",
            env=runner.reference_environment(),
        )
        if "kotlinc-jvm 2.3.10 " not in kotlin_version["stderr"] + kotlin_version["stdout"]:
            raise RuntimeError("the pinned reference compiler must be Kotlin 2.3.10")
        summary["kotlin_version"] = kotlin_version
        stdlib = output / "KSwiftKStdlib.kklib"
        build = runner.stage([
            str(compiler), "--stdlib-only", "--no-incremental", "-o", str(stdlib),
        ], output, "candidate-fresh-stdlib", expected_code=0)
        summary["fresh_stdlib_build"] = build
        manifest_data = json.loads((stdlib / "manifest.json").read_text(encoding="utf-8"))
        if manifest_data.get("moduleName") != "KSwiftKStdlib" or manifest_data.get("kotlinLanguageVersion") != "2.4.20":
            raise RuntimeError("fresh candidate stdlib has an unexpected module or language version")
        summary["candidate_stdlib_sha256"] = tree_hash(stdlib)

        for row_id in (BUILDER_ROW, JVM_ROW):
            probe = probes[row_id]
            row_result = {"row_id": row_id, "case_id": probe["case_id"], "executions": []}
            summary["rows"].append(row_result)
            for lane in probe["lanes"]:
                for subject in ("reference", "candidate"):
                    key = f"{row_id}:{lane}:{subject}"
                    evidence_dir = output / row_id / lane / subject
                    print(f"RUN {row_id} {lane} {subject}", flush=True)
                    stage_start = len(runner.results)
                    try:
                        if subject == "reference":
                            result = runner.reference_lane(row_id, lane, evidence_dir)
                        elif row_id == JVM_ROW:
                            result = runner.candidate_jvm_row(evidence_dir, stdlib)
                        else:
                            result = runner.candidate_lane(lane, evidence_dir, stdlib)
                    except Exception as error:
                        result = {
                            "status": "FAIL",
                            "error": str(error),
                            "evidence_dir": str(evidence_dir),
                            "stages": runner.results[stage_start:],
                        }
                        errors.append(f"{key}: {error}")
                    result_map[key] = result
                    row_result["executions"].append({
                        "lane": lane,
                        "subject": subject,
                        "execution_id": probe["lanes"][lane][subject],
                        **result,
                    })
                    print(f"{result['status']} {row_id} {lane} {subject}", flush=True)
                    save_json(output / "summary.json", summary)

        after = {
            str(path.relative_to(ROOT)): sha(path)
            for name in before if not name.startswith("upstream/")
            for path in [ROOT / name]
        }
        after.update({name: digest for name, digest in before.items() if name.startswith("upstream/")})
        if before != after:
            errors.append("probe inputs changed during execution")
        if run_git("rev-parse", "HEAD") != candidate_sha:
            errors.append("candidate HEAD changed during execution")
        if args.record_evidence and run_git("status", "--porcelain"):
            errors.append("candidate worktree changed during execution")
        if sha(compiler) != summary["compiler_sha256"]:
            errors.append("compiler binary changed during execution")

        subject_results = [
            execution
            for row_result in summary["rows"]
            for execution in row_result["executions"]
        ]
        lane_pairs = [
            (row_result, lane)
            for row_result in summary["rows"]
            for lane in probes[row_result["row_id"]]["lanes"]
        ]
        passing_lane_pairs = 0
        for row_result, lane in lane_pairs:
            results = {
                item["subject"]: item["status"]
                for item in row_result["executions"]
                if item["lane"] == lane
            }
            passing_lane_pairs += results == {"reference": "PASS", "candidate": "PASS"}
        summary["counts"] = {
            "rows": len(summary["rows"]),
            "lane_pairs": len(lane_pairs),
            "passing_lane_pairs": passing_lane_pairs,
            "successful_cases": sum(
                all(item["status"] == "PASS" for item in row_result["executions"])
                for row_result in summary["rows"]
            ),
            "reference_runs": sum(item["subject"] == "reference" for item in subject_results),
            "candidate_runs": sum(item["subject"] == "candidate" for item in subject_results),
            "reference_passes": sum(
                item["subject"] == "reference" and item["status"] == "PASS"
                for item in subject_results
            ),
            "candidate_passes": sum(
                item["subject"] == "candidate" and item["status"] == "PASS"
                for item in subject_results
            ),
        }

        if not errors:
            for row_id in (BUILDER_ROW, JVM_ROW):
                row_result = next(item for item in summary["rows"] if item["row_id"] == row_id)
                row = inventory[row_id]
                record = build_record(row, probes[row_id], candidate_sha, result_map)
                row_result["validation_record"] = record
            summary["status"] = "SELECTED_API_PROBES_PASS"
        else:
            summary["status"] = "FAILED_OR_INCOMPLETE"
            summary["errors"] = errors
        if args.record_evidence and summary["status"] == "SELECTED_API_PROBES_PASS":
            evidence = normalize_validation_evidence_schema(
                json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
            )
            run_evidence = json.loads(PROBE_RUN_EVIDENCE_PATH.read_text(encoding="utf-8"))
            if run_evidence.get("schema_version") != 1 or not isinstance(run_evidence.get("runs"), list):
                raise RuntimeError("unexpected api-probe-run-evidence schema")
            replacements = {row["row_id"]: row["validation_record"] for row in summary["rows"]}
            previous_evidence = EVIDENCE_PATH.read_bytes()
            previous_run_evidence = PROBE_RUN_EVIDENCE_PATH.read_bytes()
            generated_paths = [
                HERE / "api-inventory.tsv",
                HERE / "platform-scope.tsv",
                HERE / "inventory-summary.md",
            ]
            previous_outputs = {path: path.read_bytes() for path in generated_paths}
            evidence["records"] = [record for record in evidence["records"]
                                    if record.get("row_id") not in replacements]
            evidence["records"].extend(replacements[row_id] for row_id in (BUILDER_ROW, JVM_ROW))
            evidence["records"].sort(key=lambda record: record["row_id"])
            row_ids = set(replacements)
            run_evidence["runs"] = [
                run for run in run_evidence["runs"]
                if not row_ids.intersection(
                    row.get("row_id") for row in run.get("rows", [])
                    if isinstance(row, dict)
                )
            ]
            summary["evidence_recorded"] = True
            run_evidence["runs"].append(summary)
            save_json(EVIDENCE_PATH, evidence)
            save_json(PROBE_RUN_EVIDENCE_PATH, run_evidence)
            generation = subprocess.run(
                [sys.executable, str(HERE / "generate.py"), "--write"],
                cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            )
            (output / "evidence-generate.stdout").write_bytes(generation.stdout)
            (output / "evidence-generate.stderr").write_bytes(generation.stderr)
            validation = subprocess.run(
                [sys.executable, str(HERE / "generate.py"), "--check"],
                cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            ) if generation.returncode == 0 else None
            if validation is not None:
                (output / "evidence-check.stdout").write_bytes(validation.stdout)
                (output / "evidence-check.stderr").write_bytes(validation.stderr)
            if generation.returncode != 0 or validation is None or validation.returncode != 0:
                EVIDENCE_PATH.write_bytes(previous_evidence)
                PROBE_RUN_EVIDENCE_PATH.write_bytes(previous_run_evidence)
                for path, contents in previous_outputs.items():
                    path.write_bytes(contents)
                detail = generation.stderr.decode(errors="replace")
                if validation is not None:
                    detail += validation.stderr.decode(errors="replace")
                raise RuntimeError(
                    "recorded evidence did not survive generator write/check: " + detail
                )
    except Exception as error:
        summary["status"] = "FAILED_OR_INCOMPLETE"
        summary["evidence_recorded"] = False
        summary["errors"] = [*errors, str(error)]
    save_json(output / "summary.json", summary)
    print(f"Result summary: {output / 'summary.json'}")
    return 0 if summary["status"] == "SELECTED_API_PROBES_PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
