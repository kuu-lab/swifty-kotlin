#!/usr/bin/env python3
"""Run pinned public Kotlin consumers against their recorded JVM outputs."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CORPUS = Path(__file__).resolve().parent / "round1"


def default_compiler():
    if "KSWIFTC" in os.environ:
        return os.environ["KSWIFTC"]
    for path in [ROOT / ".build/debug/kswiftc", ROOT / ".build/out/Products/Debug/kswiftc"]:
        if path.is_file():
            return str(path)
    return str(ROOT / ".build/debug/kswiftc")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_file(root, record):
    path = (root / record["path"]).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError(f"Missing or invalid corpus path: {record['path']}")
    if sha256(path) != record["sha256"]:
        raise ValueError(f"Corpus hash mismatch: {record['path']}")
    return path


def load_corpus(root):
    manifest = json.loads((root / "manifest.json").read_text())
    if manifest["schema_version"] != 1 or not manifest["cases"]:
        raise ValueError("Unsupported or empty corpus manifest")
    if manifest["issue"] == "KUU-1854" and len(manifest["cases"]) != 23:
        raise ValueError("KUU-1854 requires all 23 original consumers")
    names = set()
    for case in manifest["cases"]:
        name = case["name"]
        if not re.fullmatch(r"[a-z][a-z0-9_]*", name) or name in names:
            raise ValueError(f"Invalid or duplicate case name: {name}")
        names.add(name)
        if not case["sources"] or not re.fullmatch(r"[0-9a-f]{40}", case["revision"]):
            raise ValueError(f"Missing pinned upstream sources: {name}")
        for source in case["sources"]:
            expected_url = (
                f"https://github.com/{case['repository']}/blob/"
                f"{case['revision']}/{source['upstream_path']}"
            )
            if source["url"] != expected_url:
                raise ValueError(f"Upstream URL does not match revision: {name}")
            checked_file(root, source)
        for record in [case["main"], case["license"],
                       case["expected"]["stdout"], case["expected"]["stderr"]]:
            checked_file(root, record)
        if not isinstance(case["expected"]["exit_code"], int):
            raise ValueError(f"Invalid expected exit code: {name}")
    return manifest


def executable(value):
    path = shutil.which(str(value))
    if path is None:
        raise ValueError(f"Executable not found: {value}")
    return str(Path(path).resolve())


def run_command(command, directory, stage, timeout):
    started = time.monotonic()
    stdout = directory / f"{stage}.stdout"
    stderr = directory / f"{stage}.stderr"
    result = {"command": command, "timed_out": False}
    with stdout.open("wb") as out, stderr.open("wb") as err:
        process = subprocess.Popen(
            command, cwd=ROOT, stdout=out, stderr=err, start_new_session=True
        )
        try:
            result["exit_code"] = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            result.update(exit_code=124, timed_out=True)
        except BaseException:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            raise
    result["seconds"] = round(time.monotonic() - started, 3)
    return result


def artifact_hashes(path):
    if not path.is_dir():
        raise ValueError(f"Compiler did not produce stdlib artifact: {path}")
    if not (path / "manifest.json").is_file():
        raise ValueError(f"Stdlib artifact has no manifest: {path}")
    return {str(p.relative_to(path)): sha256(p)
            for p in sorted(path.rglob("*")) if p.is_file()}


def run_case(root, case, lane, output, compiler, java, stdlib, args):
    directory = output / lane / case["name"]
    directory.mkdir(parents=True)
    sources = [str(checked_file(root, s)) for s in [*case["sources"], case["main"]]]
    binary = directory / ("program.jar" if lane == "reference" else "program")
    if lane == "reference":
        command = [compiler, *sources, "-include-runtime", "-d", str(binary)]
        run = [java, "-XX:-UsePerfData", "-jar", str(binary)]
    else:
        flags = (["--no-stdlib", "--stdlib-library", str(stdlib)]
                 if stdlib else ["--stdlib-from-source"])
        command = [compiler, *flags, "-" + lane.removeprefix("native-"),
                   *sources, "-o", str(binary)]
        run = [str(binary)]
    result = {"case": case["name"], "lane": lane, "related_issues": case["related_issues"]}
    result["compile"] = run_command(command, directory, "compile", args.compile_timeout)
    if result["compile"]["timed_out"]:
        result["status"] = "COMPILE_TIMEOUT"
    elif result["compile"]["exit_code"] != 0:
        result["status"] = "COMPILE_FAIL"
    elif not binary.is_file():
        result["status"] = "MISSING_EXECUTABLE"
    else:
        result["run"] = run_command(run, directory, "run", args.run_timeout)
        result["stdout_match"] = (
            (directory / "run.stdout").read_bytes()
            == checked_file(root, case["expected"]["stdout"]).read_bytes()
        )
        result["stderr_match"] = (
            (directory / "run.stderr").read_bytes()
            == checked_file(root, case["expected"]["stderr"]).read_bytes()
        )
        result["exit_match"] = result["run"]["exit_code"] == case["expected"]["exit_code"]
        if result["run"]["timed_out"]:
            result["status"] = "RUN_TIMEOUT"
        elif not result["exit_match"]:
            result["status"] = "RUN_FAIL"
        elif not (result["stdout_match"] and result["stderr_match"]):
            result["status"] = "OUTPUT_MISMATCH"
        else:
            result["status"] = "PASS"
    (directory / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"{result['status']} {lane}/{case['name']}", flush=True)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument("--lane", choices=["all", "reference", "native"], default="all")
    parser.add_argument("--case", action="append", dest="cases")
    parser.add_argument("--kswiftc", default=default_compiler())
    parser.add_argument("--kotlinc", default=os.environ.get("KOTLINC", "kotlinc"))
    parser.add_argument("--java", default=os.environ.get("JAVA_BIN", "java"))
    parser.add_argument("--stdlib-mode", choices=["library", "source"], default="library")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--compile-timeout", type=float, default=600)
    parser.add_argument("--stdlib-timeout", type=float, default=1200)
    parser.add_argument("--run-timeout", type=float, default=10)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args(argv)
    for timeout in [args.compile_timeout, args.stdlib_timeout, args.run_timeout]:
        if not math.isfinite(timeout) or timeout <= 0:
            parser.error("Timeouts must be finite and positive")
    root = args.corpus.resolve()
    output = None
    report = {"results": [], "complete_verification": False}
    try:
        manifest = load_corpus(root)
        names = {c["name"] for c in manifest["cases"]}
        if args.cases and set(args.cases) - names:
            raise ValueError(f"Unknown cases: {sorted(set(args.cases) - names)}")
        cases = [c for c in manifest["cases"] if not args.cases or c["name"] in args.cases]
        if args.validate_only:
            print(f"Validated {len(manifest['cases'])} pinned consumers; no programs executed.")
            return 0
        new_output = (args.output_dir or ROOT / ".artifacts/real_programs" / uuid.uuid4().hex).resolve()
        # A new directory prevents a previous executable or report from satisfying this run.
        new_output.mkdir(parents=True, exist_ok=False)
        output = new_output
        report.update(
            issue=manifest["issue"], corpus_sha256=sha256(root / "manifest.json"),
            total_cases=len(names), selected_cases=[c["name"] for c in cases],
            full_corpus=len(cases) == len(names), stdlib_mode=args.stdlib_mode,
        )
        lanes = []
        reference = java = native = None
        if args.lane in ["all", "reference"]:
            reference, java = executable(args.kotlinc), executable(args.java)
            version = run_command([reference, "-version"], output, "kotlinc-version", args.compile_timeout)
            version_text = ((output / "kotlinc-version.stdout").read_text()
                            + (output / "kotlinc-version.stderr").read_text())
            if version["exit_code"] != 0 or not re.search(
                r"kotlinc-jvm\s+" + re.escape(manifest["reference_kotlin_version"]) + r"(?:\s|$)", version_text
            ):
                raise ValueError(f"Reference must be Kotlin {manifest['reference_kotlin_version']}: {version_text.strip()}")
            java_version = run_command([java, "-version"], output, "java-version", args.compile_timeout)
            if java_version["exit_code"] != 0:
                raise ValueError("Cannot determine reference Java version")
            report["reference"] = {"kotlinc": reference, "version": version_text.strip(), "java": java}
            lanes.append("reference")
        stdlib = None
        if args.lane in ["all", "native"]:
            native = executable(args.kswiftc)
            report["compiler"] = {"path": native, "sha256": sha256(Path(native))}
            revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True)
            report["compiler"]["checkout_revision"] = revision.stdout.strip()
            dirty = subprocess.run(["git", "status", "--porcelain", "--", "Sources", "Package.swift"],
                                   cwd=ROOT, capture_output=True, text=True)
            report["compiler"]["checkout_changes"] = dirty.stdout.splitlines()
            lanes.extend(["native-O0", "native-O2"])
            if args.stdlib_mode == "library":
                stdlib = output / "stdlib.kklib"
                report["stdlib_build"] = run_command(
                    [native, "--stdlib-only", "--emit", "library", "-o", str(stdlib)],
                    output, "stdlib-build", args.stdlib_timeout
                )
                if report["stdlib_build"]["exit_code"] != 0:
                    raise ValueError("Fresh stdlib build failed; see stdlib-build.stderr")
                report["stdlib_hashes"] = artifact_hashes(stdlib)
        report["lanes"] = lanes
        for lane in lanes:
            for case in cases:
                report["results"].append(run_case(
                    root, case, lane, output, reference if lane == "reference" else native,
                    java, stdlib, args
                ))
                (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        # Recheck shared inputs after execution so concurrent changes cannot produce a green report.
        load_corpus(root)
        if sha256(root / "manifest.json") != report["corpus_sha256"]:
            raise ValueError("Corpus manifest changed during execution")
        if native and sha256(Path(native)) != report["compiler"]["sha256"]:
            raise ValueError("Compiler changed during execution")
        if stdlib and artifact_hashes(stdlib) != report["stdlib_hashes"]:
            raise ValueError("Shared stdlib changed during execution")
        passed = sum(r["status"] == "PASS" for r in report["results"])
        report["complete_verification"] = (
            passed == len(report["results"]) and report["full_corpus"] and args.lane == "all"
            and args.stdlib_mode == "library"
        )
        print(f"{passed}/{len(report['results'])} executions passed; {len(cases)}/{len(names)} consumers. Report: {output / 'report.json'}")
        return 0 if passed == len(report["results"]) else 1
    except (ValueError, KeyError, OSError) as error:
        report["error"] = str(error)
        print(str(error), file=sys.stderr)
        return 2
    finally:
        if output is not None and output.is_dir():
            (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    sys.exit(main())
