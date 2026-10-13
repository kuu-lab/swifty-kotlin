#!/usr/bin/env python3
"""Run unchanged pinned common/Apple tests with the official Native test runner.

Reference-only: original assertions execute, but KSwiftK ports and the seven
paired observations remain unmapped. Missing discovery/execution is a failure.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import sys
import tarfile

from run_jvm_reference import execute, sha256, verify_file

HERE = Path(__file__).resolve().parent


def check_ids(actual: list[str], expected: set[str], stage: str) -> None:
    if len(actual) != len(set(actual)):
        raise ValueError(f"{stage}: duplicate execution IDs")
    if set(actual) != expected:
        raise ValueError(f"{stage}: missing={sorted(expected - set(actual))[:10]}; "
            f"unexpected={sorted(set(actual) - expected)[:10]}")


def parse_list(text: str) -> list[str]:
    suite = None
    result = []
    for line in text.splitlines():
        if not line.strip():
            continue
        if not line.startswith(" ") and line.endswith("."):
            suite = line[:-1]
        elif line.startswith("  ") and suite:
            result.append(suite + "." + line.strip())
        else:
            raise ValueError(f"unrecognized Native list line: {line}")
    return result


def decode_teamcity(value: str) -> str:
    replacements = {"|": "|", "'": "'", "n": "\n", "r": "\r", "[": "[", "]": "]"}
    def replace(match):
        if match[1] not in replacements:
            raise ValueError(f"unknown TeamCity escape: {match[0]}")
        return replacements[match[1]]
    return re.sub(r"\|(.)", replace, value)


def parse_teamcity(text: str) -> list[dict]:
    suite = None
    results = {}
    started = set()
    finished = set()
    for line in text.splitlines():
        if not line.startswith("##teamcity["):
            continue  # Preserve user test output in the raw stream.
        match = re.fullmatch(r"##teamcity\[(\w+)(.*)\]", line)
        if not match:
            raise ValueError(f"malformed TeamCity event: {line}")
        event, raw = match.groups()
        attributes = {}
        position = 0
        pattern = re.compile(r"\s+(\w+)='((?:\|.|[^'|])*)'")
        while position < len(raw):
            attribute = pattern.match(raw, position)
            if not attribute:
                raise ValueError(f"malformed TeamCity attributes: {line}")
            if attribute[1] in attributes:
                raise ValueError("duplicate TeamCity attribute")
            attributes[attribute[1]] = decode_teamcity(attribute[2])
            position = attribute.end()
        if event == "testSuiteStarted":
            if suite is not None:
                raise ValueError("nested Native suite events")
            suite = attributes["name"]
        elif event == "testSuiteFinished":
            if attributes["name"] != suite:
                raise ValueError("Native suite finish mismatch")
            suite = None
        elif event in {"testStarted", "testFinished", "testFailed", "testIgnored"}:
            if suite is None:
                raise ValueError("Native test event outside suite")
            identifier = suite + "." + attributes["name"]
            hint = attributes.get("locationHint")
            if hint and hint != "ktest:test://" + identifier:
                raise ValueError("Native locationHint mismatch")
            if event == "testStarted":
                if identifier in results:
                    raise ValueError(f"duplicate Native execution: {identifier}")
                started.add(identifier)
                results[identifier] = {"execution_id": identifier, "status": "NOT_FINISHED"}
            elif event == "testIgnored":
                if identifier in finished:
                    raise ValueError("ignored test already finished")
                result = results.setdefault(identifier, {"execution_id": identifier})
                result.update(status="SKIP", message=attributes.get("message"))
            else:
                if identifier not in started or identifier in finished:
                    raise ValueError("Native result without an active test")
                result = results[identifier]
                if event == "testFailed":
                    result.update(status="FAIL", message=attributes.get("message"),
                        details=attributes.get("details"))
                else:
                    finished.add(identifier)
                    if result["status"] == "NOT_FINISHED":
                        result["status"] = "PASS"
                    result["duration_ms"] = attributes.get("duration")
    if suite is not None:
        raise ValueError("unfinished Native suite")
    return list(results.values())


def verify_native_sdk(home: Path, archive: Path, record: dict) -> dict:
    verify_file(archive, record)
    fingerprints = []
    with tarfile.open(archive, "r:gz") as source:
        for member in source.getmembers():
            parts = Path(member.name).parts
            if not parts or ".." in parts or member.name.startswith("/"):
                raise ValueError("unsafe SDK archive member")
            relative = Path(*parts[1:])
            installed = home / relative
            if member.isfile():
                expected = hashlib.sha256()
                with source.extractfile(member) as content:
                    while chunk := content.read(1024 * 1024):
                        expected.update(chunk)
                actual = hashlib.sha256()
                with installed.open("rb") as content:
                    while chunk := content.read(1024 * 1024):
                        actual.update(chunk)
                if actual.digest() != expected.digest():
                    raise ValueError(f"installed Native SDK mismatch: {relative}")
                fingerprints.append({"path": str(relative), "sha256": actual.hexdigest(), "bytes": member.size})
            elif member.issym():
                if not installed.is_symlink() or os.readlink(installed) != member.linkname:
                    raise ValueError(f"installed Native SDK link mismatch: {relative}")
    return {"archive_sha256": record["sha256"], "verified_file_count": len(fingerprints),
        "files": fingerprints}


def dependency_fingerprint(directory: Path) -> dict:
    digest = hashlib.sha256()
    count = total = 0
    for path in sorted(directory.rglob("*")):
        if path.is_file() and not path.is_symlink():
            relative = str(path.relative_to(directory))
            file_digest = hashlib.sha256()
            with path.open("rb") as content:
                while chunk := content.read(1024 * 1024):
                    file_digest.update(chunk)
            digest.update((relative + "\0" + file_digest.hexdigest() + "\n").encode())
            count += 1
            total += path.stat().st_size
    return {"algorithm": "SHA256(sorted relative-path NUL file-SHA256 newline)",
        "sha256": digest.hexdigest(), "files": count, "bytes": total}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--kotlin-home", type=Path, required=True)
    parser.add_argument("--compiler-archive", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True)
    parser.add_argument("--konan-data", type=Path, required=True)
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--target", choices=("linux_x64", "macos_x64", "macos_arm64"), required=True)
    parser.add_argument("--offline", action="store_true", help="require already-cached Native toolchain dependencies")
    parser.add_argument("--compile-timeout", type=float, default=600)
    parser.add_argument("--run-timeout", type=float, default=180)
    args = parser.parse_args(argv)
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    lock_path = HERE / "reference-lock.json"
    lock = json.loads(lock_path.read_text())
    try:
        host = (platform.system(), platform.machine())
        supported_hosts = {"linux_x64": ("Linux", "x86_64"), "macos_x64": ("Darwin", "x86_64"),
            "macos_arm64": ("Darwin", "arm64")}
        if host != supported_hosts[args.target]:
            raise ValueError(f"reference must execute on its target host: {host}, requested {args.target}")
        for row in lock["upstream_files"]:
            verify_file(args.upstream / row["path"], row)
        sdk = verify_native_sdk(args.kotlin_home, args.compiler_archive, lock["native_compiler_archives"][args.target])
        (args.output / "sdk-verification.json").write_text(json.dumps(sdk, indent=2) + "\n")
        artifacts = [row for row in lock["native_artifacts"] if args.target.replace("_", "") in row["coordinate"]]
        libraries = []
        for artifact in artifacts:
            path = (args.dependencies / artifact["url"].rsplit("/", 1)[1]).resolve()
            verify_file(path, artifact)
            libraries.append(path)
        catalog_path = HERE / "native-executions.expected.json"
        verify_file(catalog_path, {"sha256": lock["native_execution_catalog_sha256"]})
        expected = [row for row in json.loads(catalog_path.read_text())
            if row["source_set"] == "common" or args.target.startswith("macos_")]
        expected_ids = {row["execution_id"] for row in expected}
        check_ids([row["execution_id"] for row in expected], expected_ids, "expected catalog")
        seed = json.loads((HERE / "coverage-map.seed.json").read_text())
        eligible = {row["upstream_id"] for row in seed["cases"]
            if (row["platform"] == "common" or args.target.startswith("macos_") and row["platform"] == "apple")
            and "Windows" not in row["upstream_path"]}
        if {row["upstream_id"] for row in expected} != eligible:
            raise ValueError("Native catalog does not cover every eligible upstream function ID")
        source_records = {row["path"]: row for row in lock["upstream_files"]}
        for row in expected:
            if row["git_blob_sha"] != source_records[row["upstream_path"]]["git_blob_sha"]:
                raise ValueError("Native catalog source blob mismatch")
        sources = [row["path"] for row in lock["upstream_files"]
            if "Windows" not in row["path"] and ("/common/test/" in row["path"] or "/native/test/" in row["path"]
            or args.target.startswith("macos_") and "/apple/test/" in row["path"])]
        common = [str((args.upstream / source).resolve()) for source in sources if "/common/" in source]
        args.konan_data.mkdir(parents=True, exist_ok=True)
        temporary = args.output / "tmp"
        temporary.mkdir()
        overrides = {"KONAN_DATA_DIR": str(args.konan_data.resolve()), "TMPDIR": str(temporary),
            "JAVA_HOME": str(args.java.resolve().parent.parent), "JAVACMD": str(args.java.resolve())}
        environment = {"kind": "reference-only", "target": args.target, "host": platform.platform(),
            "upstream_commit": lock["commit"], "kotlin": lock["kotlin"], "kotlinx_io": lock["kotlinx_io"],
            "reference_lock_sha256": sha256(lock_path), "runner_sha256": sha256(Path(__file__)),
            "expected_catalog_sha256": sha256(catalog_path), "source_files": sources,
            "reference_artifacts": artifacts, "environment_overrides": overrides, "offline": args.offline}
        (args.output / "environment.json").write_text(json.dumps(environment, indent=2) + "\n")
        compiler = str((args.kotlin_home / "bin/konanc").resolve())
        if execute([str(args.java.resolve()), "-version"], args.output, "java-version", 10):
            return 1
        if not re.search(r'version "21[.\"]', (args.output / "java-version.stderr").read_text()):
            raise ValueError("Native compiler requires Java 21")
        if execute([compiler, "-version"], args.output, "kotlin-version", 30, overrides):
            return 1
        version = (args.output / "kotlin-version.stdout").read_text() + (args.output / "kotlin-version.stderr").read_text()
        if not re.search(r"(?:Kotlin/Native|kotlinc-native)\s+2\.3\.10(?:\s|$)", version):
            raise ValueError("Native reference requires Kotlin/Native 2.3.10")
        if args.target.startswith("macos_"):
            for stage, command in (("xcode-version", ["xcodebuild", "-version"]),
                ("macos-sdk-version", ["xcrun", "--sdk", "macosx", "--show-sdk-version"]),
                ("macos-sdk-path", ["xcrun", "--sdk", "macosx", "--show-sdk-path"])):
                if execute(command, args.output, stage, 30):
                    return 1
        flags = ["-target", args.target]
        for library in libraries:
            flags += ["-library", str(library)]
        if args.offline:
            flags += ["-Xoverride-konan-properties=airplaneMode=true"]
        test_library = args.output / "upstream-native-tests.klib"
        io_libraries = [str(path) for path in libraries if path.name.startswith("kotlinx-io-")]
        command = [compiler] + [str((args.upstream / source).resolve()) for source in sources] + flags
        command += ["-produce", "library", "-friend-modules", os.pathsep.join(io_libraries),
            "-Xmulti-platform", "-Xcommon-sources=" + ",".join(common), "-XXLanguage:+UnnamedLocalVariables",
            "-opt-in=kotlinx.io.InternalIoApi", "-opt-in=kotlin.ExperimentalStdlibApi", "-o", str(test_library)]
        if execute(command, args.output, "compile-tests", args.compile_timeout, overrides):
            return 1
        binary = args.output / "upstream-native-tests.kexe"
        dump = args.output / "generated-tests.txt"
        command = [compiler] + flags + ["-generate-test-runner", "-Xinclude=" + str(test_library),
            "-Xdump-tests-to=" + str(dump), "-o", str(binary)]
        if execute(command, args.output, "link-runner", args.compile_timeout, overrides):
            return 1
        (args.output / "toolchain-dependencies.json").write_text(json.dumps(
            dependency_fingerprint(args.konan_data / "dependencies"), indent=2) + "\n")
        dumped = [line.strip().replace(":", ".", 1) for line in dump.read_text().splitlines() if line.strip()]
        check_ids(dumped, expected_ids, "generated dump")
        if execute([str(binary), "--ktest_list_tests"], args.output, "list", args.run_timeout, overrides):
            return 1
        listed = parse_list((args.output / "list.stdout").read_text())
        check_ids(listed, expected_ids, "runtime discovery")
        code = execute([str(binary), "--ktest_logger=TEAMCITY"], args.output, "run", args.run_timeout, overrides)
        results = parse_teamcity((args.output / "run.stdout").read_text())
        (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        check_ids([row["execution_id"] for row in results], expected_ids, "runtime execution")
        outcomes = {row["execution_id"]: row for row in results}
        mapped = [{**row, "reference_result": outcomes[row["execution_id"]], "candidate_disposition": "unmapped",
            "candidate_reason": "No verified KSwiftK port preserving this upstream assertion body yet."} for row in expected]
        (args.output / "execution-map.json").write_text(json.dumps(mapped, indent=2) + "\n")
        counts = dict(collections.Counter(row["status"] for row in results))
        summary = {"kind": "reference-only", "target": args.target, "source_file_count": len(sources),
            "concrete_execution_count": len(mapped), "reference_counts": counts,
            "candidate_counts": {"UNMAPPED": len(mapped)}, "paired_pass_count": 0}
        (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        for row in lock["upstream_files"]:
            verify_file(args.upstream / row["path"], row)
        print(json.dumps(summary))
        return 0 if code == 0 and counts == {"PASS": len(mapped)} else 1
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        (args.output / "error.txt").write_text(str(error) + "\n")
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
