#!/usr/bin/env python3
"""Reproduce the KUU-1604 Kotlin/JS oracle; this is not a candidate runner."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import time


FIXTURES = Path(__file__).resolve().parent
REPOSITORY = FIXTURES.parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def invoke(command, timeout, replacements):
    started = time.monotonic()
    result = {"command": command, "timeout": False}
    try:
        process = subprocess.run(command, cwd=REPOSITORY, capture_output=True, timeout=timeout)
        result.update(exitCode=process.returncode, stdout=process.stdout.decode("utf-8"),
                      stderr=process.stderr.decode("utf-8"))
    except subprocess.TimeoutExpired as error:
        result.update(exitCode=None, timeout=True, stdout=(error.stdout or b"").decode("utf-8"),
                      stderr=(error.stderr or b"").decode("utf-8"))
    result["durationSeconds"] = round(time.monotonic() - started, 3)
    for old, new in replacements:
        result["command"] = [argument.replace(old, new) for argument in result["command"]]
    return result


def diagnostics(stderr):
    return [{"severity": severity, "name": name or "UNNAMED_COMPILER_DIAGNOSTIC"}
            for severity, name in re.findall(r"(error|warning):\s*(?:\[([^]]+)\])?", stderr)]


def verify(case, observed):
    failures = []
    if observed.get("sourceSha256") != case["sourceSha256"]:
        failures.append("recorded source hash mismatch")
    for stage in ("compile", "link", "run", "consumer"):
        expected = case["reference"].get(stage)
        if expected is None:
            continue
        actual = observed.get(stage, {})
        if actual.get("timeout"):
            failures.append(stage + " timeout")
        for field in ("exitCode", "stdout", "stderr"):
            if field in expected and actual.get(field) != expected[field]:
                failures.append(stage + " " + field + " mismatch")
        if stage == "compile":
            tokens = lambda rows: Counter((row["severity"], row["name"]) for row in rows)
            if tokens(actual.get("diagnostics", [])) != tokens(expected["diagnostics"]):
                failures.append("compile diagnostic multiset mismatch")
            if expected["exitCode"] == 0 and not re.fullmatch(r"[0-9a-f]{64}", actual.get("artifactSha256", "")):
                failures.append("compiled klib artifact missing")
        if stage == "link":
            if not set(expected["requiredArtifacts"]).issubset(actual.get("artifacts", {})):
                failures.append("required JS artifact missing")
        if stage == "consumer" and actual.get("scriptSha256") != expected["scriptSha256"]:
            failures.append("recorded consumer hash mismatch")
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kotlin-dir", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--node", default="node")
    parser.add_argument("--case", action="append")
    parser.add_argument("--check-record", type=Path)
    args = parser.parse_args()
    manifest = json.loads((FIXTURES / "expectations.json").read_text())
    if manifest["schemaVersion"] != 1:
        parser.error("unknown expectation schema")
    known = {case["id"] for case in manifest["cases"]}
    if args.case and set(args.case) - known:
        parser.error("unknown case")
    cases = [case for case in manifest["cases"] if not args.case or case["id"] in args.case]
    for case in cases:
        if not set(case["lanes"]).issubset({"kotlin-js-reference", "native-compat"}):
            parser.error(case["id"] + ": unknown lane")
        if digest(FIXTURES / case["source"]) != case["sourceSha256"]:
            parser.error(case["id"] + ": source hash differs from reviewed expectation")
        consumer = case["reference"].get("consumer")
        if consumer and consumer["lane"] != "js-emission-reference":
            parser.error(case["id"] + ": unknown consumer lane")
        if consumer and digest(FIXTURES / consumer["script"]) != consumer["scriptSha256"]:
            parser.error(case["id"] + ": consumer hash differs from reviewed expectation")

    if args.check_record:
        report = json.loads(args.check_record.read_text())
        if report["schemaVersion"] != 1 or report["toolchain"]["artifactSha256"] != manifest["oracle"]["artifactSha256"]:
            parser.error("record schema or toolchain mismatch")
    else:
        if not args.kotlin_dir or not args.output_dir:
            parser.error("capture requires --kotlin-dir and --output-dir")
        kotlin = args.kotlin_dir.resolve()
        output = args.output_dir.resolve()
        output.mkdir(parents=True, exist_ok=True)
        if any(output.iterdir()):
            parser.error("output directory must be empty")
        hashes = {name: digest(kotlin / "lib" / name) for name in manifest["oracle"]["artifactSha256"]}
        if hashes != manifest["oracle"]["artifactSha256"]:
            parser.error("compiler or stdlib differs from pinned Kotlin 2.3.10")
        replacements = [(str(kotlin), "<KOTLIN_DIR>"), (str(output), "<CAPTURE_DIR>")]
        version = invoke([str(kotlin / "bin/kotlinc"), "-version"], 15, replacements)
        if version["exitCode"] != 0 or "kotlinc-jvm 2.3.10 " not in version["stderr"]:
            parser.error("unexpected compiler version")
        report = {"schemaVersion": 1, "auditDateJST": "2026-10-08", "toolchain": {
            **manifest["oracle"], "compilerVersion": version, "host": platform.platform(),
            "javaVersion": invoke(["java", "-version"], 15, replacements),
            "nodeVersion": invoke([args.node, "--version"], 15, replacements),
            "repositoryRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPOSITORY).decode().strip()
        }, "cases": {}}
        for case in cases:
            key = case["id"]
            destination = output / key
            destination.mkdir()
            compiler = str(kotlin / "bin/kotlinc-js")
            library = str(kotlin / "lib/kotlin-stdlib-js.klib")
            command = [compiler, "-Xir-produce-klib-file", "-ir-output-dir", str(destination),
                       "-ir-output-name", key, "-libraries", library, "-Xrender-internal-diagnostic-names"]
            if case["reference"]["compile"].get("werror"):
                command.append("-Werror")
            command.append(str((FIXTURES / case["source"]).relative_to(REPOSITORY)))
            observed = {"source": case["source"], "sourceSha256": digest(FIXTURES / case["source"]),
                        "compile": invoke(command, manifest["timeoutsSeconds"]["compile"], replacements)}
            observed["compile"]["diagnostics"] = diagnostics(observed["compile"]["stderr"])
            klib = destination / (key + ".klib")
            if observed["compile"]["exitCode"] == 0 and klib.is_file():
                observed["compile"]["artifactSha256"] = digest(klib)
                if "link" in case["reference"]:
                    generated = destination / "js"
                    command = [compiler, "-Xir-produce-js", "-Xinclude=" + str(klib),
                               "-ir-output-dir", str(generated), "-ir-output-name", key,
                               "-libraries", library, "-module-kind", "es", "-target", "es2015", "-main", "call"]
                    command += case["reference"]["link"]["flags"]
                    observed["link"] = invoke(command, manifest["timeoutsSeconds"]["link"], replacements)
                    observed["link"]["artifacts"] = {name: digest(generated / name)
                        for name in case["reference"]["link"]["requiredArtifacts"] if (generated / name).is_file()}
                    if observed["link"]["exitCode"] == 0:
                        observed["run"] = invoke([args.node, str(generated / (key + ".mjs"))],
                                                 manifest["timeoutsSeconds"]["run"], replacements)
                        consumer = case["reference"].get("consumer")
                        if consumer:
                            observed["consumer"] = invoke([args.node, str((FIXTURES / consumer["script"]).relative_to(REPOSITORY)),
                                str(generated / consumer["module"])], manifest["timeoutsSeconds"]["run"], replacements)
                            observed["consumer"]["scriptSha256"] = digest(FIXTURES / consumer["script"])
            report["cases"][key] = observed
            (output / "reference-results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
            print(key + ": " + ("FAIL" if verify(case, observed) else "PASS"), flush=True)

    failed = False
    for case in cases:
        errors = verify(case, report["cases"].get(case["id"], {}))
        if errors:
            failed = True
            print(case["id"] + ": " + ", ".join(errors))
    print(f"verified {len(cases)} Kotlin/JS reference cases; native implementation is not verified")
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
