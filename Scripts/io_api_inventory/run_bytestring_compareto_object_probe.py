#!/usr/bin/env python3
"""Check the pinned JVM bridge and KSwiftK ByteString compare behavior."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PROBE_DIR = HERE / "probes"
JVM_PROBE = PROBE_DIR / "ByteStringCompareToObjectJvmAbiProbe.java"
CANDIDATE_PROBE = PROBE_DIR / "ByteStringCompareToObjectCandidateProbe.kt"
CASE_ID = "Scripts/io_api_inventory/probes/ByteStringCompareToObjectJvmAbiProbe.java#main"
REFERENCE_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"
CANDIDATE_SHA = "fd01a5e98145e8295e5b299b0a7190cc8d44e3a7"
EXPECTED_CANDIDATE_OUTPUT = b"""compare:empty=0
compare:equal=0
compare:prefix=-1
compare:lexicographic=-1
compare:longer=1
compare:first-byte=1
compare:unsigned-high=1
compare:unsigned-low=-1
"""
EXPECTED_JVM_OUTPUT = b"""assignable:Comparable=true
bridge:public=true:bridge=true:synthetic=true:parameter=Object:return=int
typed:public=true:bridge=false:synthetic=false:parameter=ByteString:return=int
compare:empty=0
compare:equal=0
compare:prefix=-1
compare:lexicographic=-1
compare:longer=1
compare:first-byte=1
compare:unsigned-high=1
compare:unsigned-low=-1
boundary:wrong-type=ClassCastException
boundary:null=NullPointerException
"""


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_digest(path: Path) -> str:
    return digest(path.read_bytes())


def save(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run(command: list[str], cwd: Path, output: Path, stage: str, timeout: float,
        environment: dict[str, str] | None = None) -> tuple[dict, bytes, bytes]:
    started = time.monotonic()
    try:
        result = subprocess.run(command, cwd=cwd, env={**os.environ, **(environment or {})},
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=timeout, check=False)
        stdout = result.stdout
        stderr = result.stderr
        exit_code = result.returncode
        status = "PASS" if exit_code == 0 else "FAIL"
    except subprocess.TimeoutExpired as error:
        stdout = error.stdout or b""
        stderr = (error.stderr or b"") + f"\nTIMEOUT after {timeout}s\n".encode()
        exit_code = 124
        status = "TIMEOUT"
    elapsed = time.monotonic() - started
    stdout_path = output / f"{stage}.stdout"
    stderr_path = output / f"{stage}.stderr"
    stdout_path.write_bytes(stdout)
    stderr_path.write_bytes(stderr)
    receipt = {
        "command": command,
        "cwd": str(cwd),
        "environment": environment or {},
        "deadline_seconds": timeout,
        "result": status,
        "exit_code": exit_code,
        "seconds": elapsed,
        "stdout_path": str(stdout_path),
        "stderr_path": str(stderr_path),
        "stdout_sha256": digest(stdout),
        "stderr_sha256": digest(stderr),
    }
    save(output / f"{stage}.json", receipt)
    return receipt, stdout, stderr


def check_method_block(output: str, signature: str) -> str:
    lines = output.splitlines()
    headers = [index for index, line in enumerate(lines)
               if line.startswith("  ") and not line.startswith("    ")
               and "(" in line and line.rstrip().endswith(";")]
    matches = [index for index in headers if signature in lines[index]]
    if len(matches) != 1:
        raise RuntimeError(f"expected one javap method {signature!r}, found {len(matches)}")
    start = matches[0]
    end = next((index for index in headers if index > start), len(lines))
    return "\n".join(lines[start:end])


def verify_javap(output: str) -> dict:
    bridge = check_method_block(output, "compareTo(java.lang.Object);")
    typed = check_method_block(output, "compareTo(kotlinx.io.bytestring.ByteString);")
    if not re.search(r"^\s*descriptor:\s*\(Ljava/lang/Object;\)I\s*$", bridge, re.MULTILINE):
        raise RuntimeError("Object overload does not have descriptor (Ljava/lang/Object;)I")
    bridge_flags = re.search(r"^\s*flags:\s*\([^)]*\)(.*)$", bridge, re.MULTILINE)
    if not bridge_flags:
        raise RuntimeError("javap did not report Object bridge flags")
    bridge_flag_names = set(re.findall(r"ACC_[A-Z_]+", bridge_flags.group(1)))
    if not {"ACC_PUBLIC", "ACC_BRIDGE", "ACC_SYNTHETIC"}.issubset(bridge_flag_names):
        raise RuntimeError(f"Object overload flags are incomplete: {sorted(bridge_flag_names)}")
    if not re.search(r"checkcast\s+#\d+.*kotlinx/io/bytestring/ByteString", bridge):
        raise RuntimeError("Object bridge does not cast its argument to ByteString")
    if not re.search(r"invokevirtual\s+#\d+.*compareTo:\(Lkotlinx/io/bytestring/ByteString;\)I", bridge):
        raise RuntimeError("Object bridge does not invoke compareTo(ByteString)")
    if not re.search(r"^\s*descriptor:\s*\(Lkotlinx/io/bytestring/ByteString;\)I\s*$", typed, re.MULTILINE):
        raise RuntimeError("typed overload does not have descriptor (Lkotlinx/io/bytestring/ByteString;)I")
    typed_flags = re.search(r"^\s*flags:\s*\([^)]*\)(.*)$", typed, re.MULTILINE)
    if not typed_flags:
        raise RuntimeError("javap did not report typed overload flags")
    typed_flag_names = set(re.findall(r"ACC_[A-Z_]+", typed_flags.group(1)))
    if "ACC_PUBLIC" not in typed_flag_names or {"ACC_BRIDGE", "ACC_SYNTHETIC"} & typed_flag_names:
        raise RuntimeError(f"typed overload flags are incorrect: {sorted(typed_flag_names)}")
    return {
        "bridge_descriptor": "(Ljava/lang/Object;)I",
        "bridge_flags": sorted(bridge_flag_names),
        "typed_descriptor": "(Lkotlinx/io/bytestring/ByteString;)I",
        "typed_flags": sorted(typed_flag_names),
        "bridge_checkcast": True,
        "bridge_invokes_typed_overload": True,
    }


def artifact_digest(path: Path) -> dict:
    files = {str(file.relative_to(path)): file_digest(file)
             for file in sorted(path.rglob("*")) if file.is_file()}
    encoded = json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    return {"path": str(path), "files": len(files), "sha256": digest(encoded)}


def mark_output(receipt: dict, stdout: bytes, stderr: bytes, expected: bytes) -> None:
    if receipt["result"] == "PASS" and (stdout != expected or stderr):
        receipt["result"] = "FAIL"
        receipt["failure"] = "stdout differed from expected bytes or stderr was non-empty"


def reference_inputs(reference_root: Path) -> tuple[dict, Path, Path, Path, Path]:
    paths = json.loads((reference_root / "paths.json").read_text(encoding="utf-8"))
    lock_path = ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json"
    lock_bytes = lock_path.read_bytes()
    lock = json.loads(lock_bytes.decode("utf-8"))
    if paths.get("target") != "jvm":
        raise RuntimeError("reference root must be prepared with --target jvm")
    if paths.get("reference_lock_sha256") != digest(lock_bytes) or lock.get("commit") != REFERENCE_COMMIT:
        raise RuntimeError("reference root does not match the pinned kotlinx-io JVM lock")
    compiler_archive = Path(paths["compiler_archive"])
    if (not compiler_archive.is_file()
            or file_digest(compiler_archive) != paths.get("compiler_archive_sha256")
            or paths.get("compiler_archive_sha256") != lock["compiler_archive"].get("sha256")):
        raise RuntimeError("reference Kotlin compiler archive does not match its lock")
    installation = Path(paths["installation"])
    dependencies = Path(paths["dependencies"])
    jar = dependencies / "kotlinx-io-bytestring-jvm-0.9.1.jar"
    kotlin_stdlib = installation / "lib/kotlin-stdlib.jar"
    if not (installation / "bin/kotlinc").is_file() or not jar.is_file() or not kotlin_stdlib.is_file():
        raise RuntimeError("reference installation is missing kotlinc, the ByteString jar, or kotlin-stdlib")
    artifact = next((item for item in lock["jvm_artifacts"]
                     if item.get("coordinate") == "org.jetbrains.kotlinx:kotlinx-io-bytestring-jvm:0.9.1"), None)
    if artifact is None or file_digest(jar) != artifact.get("sha256"):
        raise RuntimeError("the reference ByteString JVM jar does not match reference-lock.json")
    stdlib_lock = next((item for item in lock["sdk_files"] if item.get("path") == "lib/kotlin-stdlib.jar"), None)
    if stdlib_lock is None or file_digest(kotlin_stdlib) != stdlib_lock.get("sha256"):
        raise RuntimeError("the reference Kotlin stdlib does not match its SDK lock")
    inventory_lock = json.loads((HERE / "upstream-lock.json").read_text(encoding="utf-8"))
    inventory_artifacts = [item for item in inventory_lock["mavenArtifacts"]
                           if item.get("coordinate") == "org.jetbrains.kotlinx:kotlinx-io-bytestring-jvm:0.9.1"]
    if len(inventory_artifacts) != 1 or inventory_artifacts[0]["sha256"] != file_digest(jar):
        raise RuntimeError("the reference ByteString JVM jar does not match the API inventory lock")
    return lock, installation, dependencies, jar, kotlin_stdlib


def verify_candidate(candidate_root: Path, compiler: Path, candidate_sha: str) -> dict:
    actual_sha = subprocess.check_output(["git", "-C", str(candidate_root), "rev-parse", "HEAD"], text=True).strip()
    if actual_sha != candidate_sha:
        raise RuntimeError(f"candidate checkout SHA mismatch: expected {candidate_sha}, got {actual_sha}")
    dirty = subprocess.run(["git", "-C", str(candidate_root), "diff", "--quiet", "HEAD", "--",
                            "Sources/CompilerCore/Stdlib/kotlinx/io/bytestring/ByteString.kt"], check=False)
    if dirty.returncode != 0:
        raise RuntimeError("candidate ByteString source has uncommitted changes")
    if not compiler.is_file() or not compiler.resolve().is_relative_to(candidate_root.resolve()):
        raise RuntimeError("candidate compiler must be an existing binary inside candidate-root")
    source = candidate_root / "Sources/CompilerCore/Stdlib/kotlinx/io/bytestring/ByteString.kt"
    bundles = list((candidate_root / ".build").rglob(
        "KSwiftK_CompilerCore.bundle/Contents/Resources/Stdlib/kotlinx/io/bytestring/ByteString.kt"))
    matching_bundles = [path for path in bundles if path.read_bytes() == source.read_bytes()]
    if not matching_bundles:
        raise RuntimeError("candidate ByteString source does not match a built compiler resource bundle")
    return {
        "candidate_sha": actual_sha,
        "compiler": str(compiler.resolve()),
        "compiler_sha256": file_digest(compiler),
        "byte_string_source_sha256": file_digest(source),
        "matching_resource_bundles": [str(path) for path in matching_bundles],
        "resource_sha256": file_digest(matching_bundles[0]),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference-root", type=Path, required=True,
                        help="output directory from prepare_reference.py --target jvm")
    parser.add_argument("--java", type=Path, required=True, help="Java executable for the pinned JVM probes")
    parser.add_argument("--candidate-root", type=Path, required=True,
                        help="clean compiler checkout at the candidate SHA")
    parser.add_argument("--compiler", type=Path, required=True, help="candidate kswiftc binary")
    parser.add_argument("--candidate-sha", default=CANDIDATE_SHA)
    parser.add_argument("--output", type=Path, required=True, help="new directory for immutable run logs")
    parser.add_argument("--compile-timeout", type=float, default=1800)
    args = parser.parse_args()
    if args.candidate_sha != CANDIDATE_SHA:
        parser.error(f"KUU-2625 is pinned to candidate {CANDIDATE_SHA}")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)

    reference_root = args.reference_root.resolve()
    java = args.java.resolve()
    javac = java.with_name("javac")
    javap = java.with_name("javap")
    if not java.is_file() or not javac.is_file() or not javap.is_file():
        parser.error("--java must point to a JDK with javac and javap beside it")
    lock, installation, _, bytestring_jar, kotlin_stdlib = reference_inputs(reference_root)
    candidate = verify_candidate(args.candidate_root.resolve(), args.compiler.resolve(), args.candidate_sha)

    java_version = subprocess.run([str(java), "-version"], stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, check=False)
    version_bytes = java_version.stdout + java_version.stderr
    if java_version.returncode != 0:
        parser.error("Java version probe failed")
    (output / "java-version.stdout").write_bytes(java_version.stdout)
    (output / "java-version.stderr").write_bytes(java_version.stderr)
    candidate["java_version"] = version_bytes.decode("utf-8", errors="replace").strip()
    candidate["java_version_sha256"] = digest(version_bytes)

    summary = {
        "schema_version": 1,
        "case_id": CASE_ID,
        "candidate_sha": args.candidate_sha,
        "reference_version": lock["kotlin"],
        "reference_commit": lock["commit"],
        "reference_artifact_sha256": file_digest(bytestring_jar),
        "probe_inputs_sha256": {JVM_PROBE.name: file_digest(JVM_PROBE),
                                 CANDIDATE_PROBE.name: file_digest(CANDIDATE_PROBE)},
        "candidate": candidate,
        "reference_jvm_abi": {},
        "reference_candidate_semantics": {},
        "candidate_lanes": [],
    }

    classes = output / "reference-classes"
    classes.mkdir()
    compile_reference, _, _ = run(
        [str(javac), "-classpath", os.pathsep.join((str(bytestring_jar), str(kotlin_stdlib))),
         "-d", str(classes), str(JVM_PROBE)], output, output, "reference-javac", 120,
    )
    javap_receipt, javap_stdout, _ = run(
        [str(javap), "-classpath", str(bytestring_jar), "-p", "-s", "-v", "-c",
         "kotlinx.io.bytestring.ByteString"], output, output, "reference-javap", 120,
    )
    javap_details = {}
    if javap_receipt["result"] == "PASS":
        try:
            javap_details = verify_javap(javap_stdout.decode("utf-8"))
        except (RuntimeError, UnicodeDecodeError) as error:
            javap_receipt["result"] = "FAIL"
            javap_receipt["failure"] = str(error)
        save(output / "reference-javap.json", javap_receipt)
    java_run = {"result": "NOT_RUN", "exit_code": None}
    java_stdout = b""
    java_stderr = b""
    if compile_reference["result"] == "PASS":
        classpath = os.pathsep.join((str(classes), str(bytestring_jar), str(kotlin_stdlib)))
        java_run, java_stdout, java_stderr = run(
            [str(java), "-classpath", classpath, "ByteStringCompareToObjectJvmAbiProbe"],
            output, output, "reference-java-probe", 120,
        )
        mark_output(java_run, java_stdout, java_stderr, EXPECTED_JVM_OUTPUT)
        save(output / "reference-java-probe.json", java_run)
    else:
        save(output / "reference-java-probe.json", java_run)
    summary["reference_jvm_abi"] = {
        "javac": compile_reference,
        "javap": {**javap_receipt, **javap_details},
        "java_probe": java_run,
    }

    reference_compiler = installation / "bin/kotlinc"
    reference_jar = output / "reference-candidate-probe.jar"
    reference_compile, _, _ = run(
        [str(reference_compiler), "-classpath", str(bytestring_jar), "-include-runtime",
         "-d", str(reference_jar), str(CANDIDATE_PROBE)], output, output,
        "reference-kotlin-compile", args.compile_timeout,
        {"JAVA_HOME": str(java.parent.parent)},
    )
    reference_kotlin_run = {"result": "NOT_RUN", "exit_code": None}
    if reference_compile["result"] == "PASS":
        classpath = os.pathsep.join((str(reference_jar), str(bytestring_jar)))
        reference_kotlin_run, stdout, stderr = run(
            [str(java), "-classpath", classpath,
             "kotlinx.io.bytestring.probe.ByteStringCompareToObjectCandidateProbeKt"],
            output, output, "reference-kotlin-run", 120,
        )
        mark_output(reference_kotlin_run, stdout, stderr, EXPECTED_CANDIDATE_OUTPUT)
        save(output / "reference-kotlin-run.json", reference_kotlin_run)
    else:
        save(output / "reference-kotlin-run.json", reference_kotlin_run)
    summary["reference_candidate_semantics"] = {
        "compile": reference_compile,
        "run": reference_kotlin_run,
        "compiler_sha256": file_digest(reference_compiler),
        "kotlin_stdlib_sha256": file_digest(kotlin_stdlib),
    }

    candidate_root = args.candidate_root.resolve()
    stdlib_path = output / "candidate-stdlib/KSwiftKStdlib.kklib"
    stdlib_path.parent.mkdir(parents=True)
    library_environment = {
        "TMPDIR": str(output / "candidate-stdlib/tmp") + "/",
        "KSWIFTK_STDLIB_CACHE_DIR": str(output / "candidate-stdlib/cache"),
        "KSWIFTK_PACKAGE_ROOT": str(candidate_root),
    }
    Path(library_environment["TMPDIR"]).mkdir(parents=True)
    Path(library_environment["KSWIFTK_STDLIB_CACHE_DIR"]).mkdir(parents=True)
    stdlib_build, _, _ = run(
        [str(args.compiler.resolve()), "--stdlib-only", "--no-incremental", "-o", str(stdlib_path)],
        output, output, "candidate-stdlib-build", args.compile_timeout, library_environment,
    )
    stdlib_digest = artifact_digest(stdlib_path) if stdlib_path.is_dir() else None
    summary["candidate_stdlib"] = {"build": stdlib_build, "artifact": stdlib_digest}
    for route in ("source", "stdlib-library"):
        for optimization in ("O0", "O2"):
            stage = f"candidate-{route}-{optimization}"
            lane = output / stage
            lane.mkdir()
            workspace = lane / "work"
            workspace.mkdir()
            temporary = workspace / "tmp"
            cache = workspace / "stdlib-cache"
            temporary.mkdir()
            cache.mkdir()
            environment = {
                "TMPDIR": str(temporary) + "/",
                "KSWIFTK_STDLIB_CACHE_DIR": str(cache),
                "KSWIFTK_PACKAGE_ROOT": str(candidate_root),
            }
            executable = lane / "compareto-object-probe"
            command = [str(args.compiler.resolve()), str(CANDIDATE_PROBE), f"-{optimization}"]
            if route == "source":
                command.append("--stdlib-from-source")
            else:
                command += ["--stdlib-library", str(stdlib_path)]
            command += ["-o", str(executable)]
            compile_receipt, _, _ = run(command, workspace, lane, "compile", args.compile_timeout, environment)
            run_receipt = {"result": "NOT_RUN", "exit_code": None}
            stdout = b""
            stderr = b""
            if compile_receipt["result"] == "PASS":
                run_receipt, stdout, stderr = run([str(executable)], workspace, lane, "run", 60, environment)
                mark_output(run_receipt, stdout, stderr, EXPECTED_CANDIDATE_OUTPUT)
                save(lane / "run.json", run_receipt)
            else:
                save(lane / "run.json", run_receipt)
            summary["candidate_lanes"].append({
                "route": route,
                "optimization": optimization,
                "compile": compile_receipt,
                "run": run_receipt,
                "stdout_sha256": digest(stdout),
                "stderr_sha256": digest(stderr),
                "fresh_stdlib_sha256": stdlib_digest["sha256"] if route == "stdlib-library" and stdlib_digest else None,
            })

    reference_pass = (
        compile_reference["result"] == "PASS"
        and javap_receipt["result"] == "PASS"
        and java_run["result"] == "PASS"
        and java_stdout == EXPECTED_JVM_OUTPUT
        and not java_stderr
    )
    if reference_pass:
        summary["reference_probe_receipt"] = {
            "execution_id": "kuu2625-reference-jvm-descriptor",
            "case_id": CASE_ID,
            "lane": "jvm-descriptor",
            "result": "PASS",
            "exit_code": 0,
            "stdout_sha256": digest(java_stdout),
            "normalized_stdout_sha256": digest(java_stdout),
            "stderr_sha256": digest(java_stderr),
            "probe_input_sha256": file_digest(JVM_PROBE),
            "candidate_sha": args.candidate_sha,
            "reference_commit": lock["commit"],
            "javap_stdout_sha256": javap_receipt["stdout_sha256"],
        }
        save(output / "reference-probe-evidence-receipt.json", summary["reference_probe_receipt"])

    all_passed = reference_pass and reference_kotlin_run.get("result") == "PASS" and stdlib_digest is not None
    all_passed = all_passed and stdlib_build["result"] == "PASS"
    all_passed = all_passed and len(summary["candidate_lanes"]) == 4
    all_passed = all_passed and all(item["compile"]["result"] == "PASS" and item["run"]["result"] == "PASS"
                                    for item in summary["candidate_lanes"])
    summary["status"] = "PASS" if all_passed else "FAILED_OR_INCOMPLETE"
    save(output / "summary.json", summary)
    print(json.dumps({"status": summary["status"], "output": str(output),
                      "candidate_sha": args.candidate_sha,
                      "candidate_lanes": [{"route": item["route"], "optimization": item["optimization"],
                                           "result": item["run"]["result"]}
                                          for item in summary["candidate_lanes"]]}, indent=2))
    return 0 if all_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
