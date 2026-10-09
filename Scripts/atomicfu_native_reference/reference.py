#!/usr/bin/env python3
"""Pinned Linux/x64 atomicfu Native oracle; never tests candidate behavior."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import posixpath
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent
EXIT_CODES = {"PASS": 0, "DIFFERENCE": 1, "ERROR": 2, "UNSUPPORTED": 77, "TIMEOUT": 124}


class ReferenceFailure(Exception):
    def __init__(self, status, message, execution=None):
        super().__init__(message)
        self.status = status
        self.execution = execution


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_file(path, artifact):
    if path.stat().st_size != artifact["size"] or sha256(path) != artifact["sha256"]:
        raise ReferenceFailure("ERROR", "Checksum/size mismatch: " + str(path))


def load_lock():
    lock = json.loads((ROOT / "lock.json").read_text())
    for filename, expected in lock["fixtures"].items():
        if sha256(ROOT / filename) != expected:
            raise ReferenceFailure("ERROR", "Fixture checksum mismatch: " + filename)
    return lock


def cached_artifacts(lock, cache, fetch, roles=None):
    cache.mkdir(parents=True, exist_ok=True)
    paths = {}
    for artifact in lock["artifacts"]:
        if roles is not None and artifact["role"] not in roles:
            continue
        path = cache / artifact["filename"]
        if not path.exists():
            if not fetch:
                raise ReferenceFailure("UNSUPPORTED", "Missing cached artifact; run fetch first: " + str(path))
            temporary = path.with_suffix(path.suffix + ".part")
            try:
                with urllib.request.urlopen(artifact["url"], timeout=90) as response, temporary.open("wb") as output:
                    shutil.copyfileobj(response, output)
                verify_file(temporary, artifact)
                temporary.replace(path)
            finally:
                temporary.unlink(missing_ok=True)
        verify_file(path, artifact)
        paths[artifact["role"]] = path.resolve()
    return paths


def extract_archive(path, destination, prefix):
    # Only locked, verified official archives reach here. Validate names and links
    # before invoking tar, and extract into a newly created run directory.
    with tarfile.open(path, "r:gz") as archive:
        for member in archive:
            name = PurePosixPath(member.name)
            if name.is_absolute() or ".." in name.parts or not name.parts or name.parts[0] != prefix:
                raise ReferenceFailure("ERROR", "Unexpected archive path: " + member.name)
            if member.issym() or member.islnk():
                base = posixpath.dirname(member.name) if member.issym() else ""
                target = posixpath.normpath(posixpath.join(base, member.linkname))
                if target != prefix and not target.startswith(prefix + "/"):
                    raise ReferenceFailure("ERROR", "Unexpected archive link: " + member.name)
    subprocess.run(["tar", "--no-same-owner", "-xzf", str(path), "-C", str(destination)], check=True)


def manifest(path):
    with zipfile.ZipFile(path) as archive:
        contents = archive.read("default/manifest").decode()
    return dict(line.split("=", 1) for line in contents.splitlines() if "=" in line)


def execute(command, output, name, timeout, env=None):
    stdout_path = output / (name + ".stdout")
    stderr_path = output / (name + ".stderr")
    result = {"command": command, "exit_code": None,
              "stdout": stdout_path.name, "stderr": stderr_path.name}
    with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
        process = subprocess.Popen(command, stdout=stdout, stderr=stderr, env=env, start_new_session=True)
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            result["exit_code"] = process.returncode
            result["timeout_seconds"] = timeout
            raise ReferenceFailure("TIMEOUT", name + " exceeded " + str(timeout) + " seconds", result)
    result["exit_code"] = process.returncode
    if process.returncode != 0:
        raise ReferenceFailure("ERROR", name + " exited " + str(process.returncode) + "; see " + stderr_path.name, result)
    return result


def verify_result(output, name, expected):
    if (output / (name + ".stdout")).read_bytes() != (ROOT / expected).read_bytes():
        raise ReferenceFailure("DIFFERENCE", name + " stdout differs from " + expected)
    if (output / (name + ".stderr")).read_bytes():
        raise ReferenceFailure("DIFFERENCE", name + " produced unexpected stderr")


def run_reference(args, lock, output, report):
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "amd64"):
        raise ReferenceFailure("UNSUPPORTED", "This lock covers Linux/x86_64 -> linux_x64 only")
    java_path = shutil.which("java")
    if not java_path or not shutil.which("tar"):
        raise ReferenceFailure("UNSUPPORTED", "JDK 21 and tar are required")
    java_path = str(Path(java_path).resolve())
    roles = {artifact["role"] for artifact in lock["artifacts"]
             if args.jvm_kotlinc or artifact["role"] != "atomicfu_jvm"}
    paths = cached_artifacts(lock, args.cache, False, roles)
    report["verified_artifact_roles"] = sorted(paths)
    java = execute([java_path, "-version"], output, "java-version", 15)
    java_text = (output / java["stderr"]).read_text()
    if not re.search(r'version "21(?:\.|\")', java_text):
        raise ReferenceFailure("UNSUPPORTED", "Use JDK 21; see java-version.stderr")
    report["java_version"] = java_text
    report["java_executable"] = java_path
    for role, expected in lock["klib_manifests"].items():
        actual = manifest(paths[role])
        for key, value in expected.items():
            if actual.get(key) != value:
                raise ReferenceFailure("ERROR", "Incompatible " + role + " manifest: " + key)
        report.setdefault("klib_manifests", {})[role] = actual

    install = output / "installation"
    install.mkdir()
    dependencies = install / "konan-data" / "dependencies"
    dependencies.mkdir(parents=True)
    for artifact in lock["artifacts"]:
        if "extract_root" in artifact:
            destination = install if artifact["role"] == "native_compiler" else dependencies
            extract_archive(paths[artifact["role"]], destination, artifact["extract_root"])
    (dependencies / ".extracted").write_text("".join(
        artifact["extract_root"] + "\n" for artifact in lock["artifacts"]
        if artifact["role"].startswith("dependency_")))
    native_home = install / lock["native_home"]
    properties = native_home / "konan" / "konan.properties"
    if sha256(properties) != lock["konan_properties_sha256"]:
        raise ReferenceFailure("ERROR", "Unexpected konan.properties")
    env = dict(os.environ, KONAN_DATA_DIR=str(install / "konan-data"),
               JAVACMD=java_path, JAVA_HOME=str(Path(java_path).parents[1]))
    compiler = str(native_home / "bin" / "konanc")
    version = execute([compiler, "-version"], output, "native-version", 30, env)
    version_text = (output / version["stdout"]).read_text() + (output / version["stderr"]).read_text()
    if "kotlinc-native " + lock["kotlin_version"] not in version_text:
        raise ReferenceFailure("ERROR", "Unexpected Native compiler version")
    report["native_version"] = version_text
    executable = output / "native-probe"
    report["native_compile"] = execute([
        compiler, str(ROOT / "native_probe.kt"), "-target", lock["target"],
        "-library", str(paths["atomicfu_native"]), "-library", str(paths["atomicfu_cinterop"]),
        "-Xoverride-konan-properties=airplaneMode=true", "-o", str(executable)
    ], output, "native-compile", args.compile_timeout, env)
    report["native_run"] = execute([str(executable) + ".kexe"], output, "native-run", args.run_timeout, env)
    verify_result(output, "native-run", "native.expected")
    report["native_status"] = "PASS"

    if args.jvm_kotlinc:
        kotlin = shutil.which(args.jvm_kotlinc)
        if not kotlin:
            raise ReferenceFailure("UNSUPPORTED", "Missing requested JVM kotlinc")
        version = execute([kotlin, "-version"], output, "jvm-version", 30, env)
        version_text = (output / version["stdout"]).read_text() + (output / version["stderr"]).read_text()
        if "kotlinc-jvm " + lock["kotlin_version"] not in version_text:
            raise ReferenceFailure("UNSUPPORTED", "JVM contrast requires kotlinc " + lock["kotlin_version"])
        report["jvm_version"] = version_text
        jar = output / "jvm-probe.jar"
        report["jvm_compile"] = execute([
            kotlin, str(ROOT / "jvm_probe.kt"), "-classpath", str(paths["atomicfu_jvm"]),
            "-include-runtime", "-d", str(jar)
        ], output, "jvm-compile", args.compile_timeout, env)
        report["jvm_run"] = execute([
            java_path, "-XX:-UsePerfData", "-cp", str(jar) + os.pathsep + str(paths["atomicfu_jvm"]), "Jvm_probeKt"
        ], output, "jvm-run", args.run_timeout, env)
        verify_result(output, "jvm-run", "jvm.expected")
        report["jvm_status"] = "PASS"
    else:
        report["jvm_status"] = "NOT_REQUESTED"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("check", "fetch", "run"))
    parser.add_argument("--cache", type=Path, default=ROOT.parents[1] / ".runtime-build" / "atomicfu-native-reference")
    parser.add_argument("--output", type=Path, help="New/empty directory for run artifacts and report.json")
    parser.add_argument("--jvm-kotlinc", help="Optional Kotlin/JVM 2.3.10 compiler for the contrast fixture")
    parser.add_argument("--compile-timeout", type=int, default=300)
    parser.add_argument("--run-timeout", type=int, default=15)
    args = parser.parse_args()
    if args.action == "run" and args.output is None:
        parser.error("run requires --output")
    if args.compile_timeout <= 0 or args.run_timeout <= 0:
        parser.error("timeouts must be positive")
    output = args.output.resolve() if args.output is not None else None
    if output is not None:
        if output.exists() and any(output.iterdir()):
            parser.error("--output must be a new/empty directory")
        output.mkdir(parents=True, exist_ok=True)
    report = {"status": "ERROR", "candidate_comparison": "NOT_RUN", "action": args.action,
              "native_status": "NOT_RUN", "jvm_status": "NOT_RUN"}
    try:
        lock = load_lock()
        report.update({"upstream": lock["upstream"], "target": lock["target"],
                       "lock_sha256": sha256(ROOT / "lock.json"), "artifacts": lock["artifacts"],
                       "fixtures": lock["fixtures"]})
        if args.action == "run":
            run_reference(args, lock, output, report)
        elif args.action == "fetch":
            cached_artifacts(lock, args.cache, True)
        report["status"] = "PASS"
    except ReferenceFailure as failure:
        report.update(status=failure.status, message=str(failure))
        if failure.execution is not None:
            report["failed_step"] = failure.execution
    except (OSError, ValueError, subprocess.SubprocessError, tarfile.TarError, zipfile.BadZipFile, KeyError) as failure:
        report.update(status="ERROR", message=str(failure))
    if output is not None:
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(report["status"] + (": " + report["message"] if "message" in report else ""))
    return EXIT_CODES[report["status"]]


if __name__ == "__main__":
    sys.exit(main())
