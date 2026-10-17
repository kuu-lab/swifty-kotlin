#!/usr/bin/env python3
"""Probe the pinned JVM $default ABI and direct Kotlin reference consumer for KUU-2633."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
ISSUE_ROWS = {
    "jvm-29a01d1deaf3b966",
    "jvm-32ddc189d171b174",
    "jvm-5c5fb6c81ee3a3b9",
    "jvm-b88878973d5558f7",
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(command: list[str], *, timeout: int = 120) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=True, capture_output=True, text=True, timeout=timeout)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kotlin-home", type=Path, required=True)
    parser.add_argument("--java", required=True, help="Java executable used for the reference consumer")
    parser.add_argument("--dependencies", type=Path, required=True, help="Prepared pinned Maven artifacts directory")
    parser.add_argument("--javap", default="javap")
    parser.add_argument("--output", type=Path, help="Write the probe receipt to this JSON path")
    args = parser.parse_args()

    lock = json.loads((HERE / "upstream-lock.json").read_text(encoding="utf-8"))
    expected_lock = json.loads((REPO / "Scripts/kotlinx_io_upstream/reference-lock.json").read_text(encoding="utf-8"))
    if expected_lock.get("commit") != lock["commit"] or lock["tag"] != "0.9.1":
        raise SystemExit("KUU-2633 probe requires the pinned kotlinx-io 0.9.1 / Kotlin 2.3.10 reference")
    artifacts = {}
    for entry in lock["mavenArtifacts"]:
        filename = entry["url"].rsplit("/", 1)[-1]
        path = args.dependencies / filename
        if not path.is_file():
            raise SystemExit(f"missing locked JVM dependency: {path}")
        digest = sha256(path.read_bytes())
        if digest != entry["sha256"]:
            raise SystemExit(f"locked JVM dependency hash mismatch for {filename}: {digest}")
        artifacts[filename] = {"path": str(path), "sha256": digest}

    core_jar = args.dependencies / "kotlinx-io-core-jvm-0.9.1.jar"
    bytestring_jar = args.dependencies / "kotlinx-io-bytestring-jvm-0.9.1.jar"
    classpath = f"{core_jar}:{bytestring_jar}"
    obligations = json.loads((REPO / "Scripts/kotlinx_io_upstream/jvm_interop/native-default-obligations.expected.json").read_text(encoding="utf-8"))
    obligations_by_id = {row["rowID"]: row for row in obligations["rows"] if row["rowID"] in ISSUE_ROWS}
    if set(obligations_by_id) != ISSUE_ROWS or obligations.get("upstreamCommit") != lock["commit"]:
        raise SystemExit("KUU-2633 bridge shape records do not match the upstream lock")
    with (HERE / "api-inventory.tsv").open(encoding="utf-8", newline="") as stream:
        ledger = {row["row_id"]: row for row in csv.DictReader(stream, delimiter="\t") if row["row_id"] in ISSUE_ROWS}
    if set(ledger) != ISSUE_ROWS:
        raise SystemExit("KUU-2633 bridge rows are missing from api-inventory.tsv")

    javap_version_result = run([args.javap, "-version"])
    javap_version = javap_version_result.stderr.strip() or javap_version_result.stdout.strip()
    abi_receipts = []
    owner_text: dict[str, str] = {}
    for row_id in sorted(ISSUE_ROWS):
        obligation = obligations_by_id[row_id]
        ledger_row = ledger[row_id]
        owner = ledger_row["owner_fqn"].replace("/", ".")
        descriptor = obligation["originalJVMDescriptor"]
        if ledger_row["name"] != "indexOf$default" or descriptor not in ledger_row["signature"]:
            raise SystemExit(f"ledger signature drift for {row_id}")
        if owner not in owner_text:
            owner_result = run([args.javap, "-classpath", classpath, "-p", "-v", owner])
            owner_text[owner] = owner_result.stdout
        text = owner_text[owner]
        method_lines = [
            index for index, line in enumerate(text.splitlines())
            if re.match(r"\s+public static .*\bindexOf\$default\(", line)
        ]
        matches = []
        lines = text.splitlines()
        for index in method_lines:
            block = "\n".join(lines[index:index + 5])
            found_descriptor = re.search(r"^\s+descriptor: (\S+)$", block, re.MULTILINE)
            found_flags = re.search(r"^\s+flags: \([^)]*\) (.*)$", block, re.MULTILINE)
            if found_descriptor and found_descriptor.group(1) == descriptor and found_flags:
                flags = set(re.findall(r"ACC_[A-Z_]+", found_flags.group(1)))
                matches.append((flags, block))
        if len(matches) != 1:
            raise SystemExit(f"expected one exact JVM method descriptor for {row_id}, found {len(matches)}")
        flags, block = matches[0]
        required_flags = {"ACC_PUBLIC", "ACC_STATIC", "ACC_SYNTHETIC"}
        if flags != required_flags:
            raise SystemExit(f"unexpected JVM access flags for {row_id}: {sorted(flags)}")
        if "ACC_BRIDGE" in flags:
            raise SystemExit(f"default wrapper unexpectedly has ACC_BRIDGE for {row_id}")
        regular_descriptor = obligation["underlyingRegularJVMDescriptor"]
        regular_found = any(
            line.strip() == f"descriptor: {regular_descriptor}"
            for line in lines
        )
        if not regular_found:
            raise SystemExit(f"underlying regular JVM method is missing for {row_id}")
        abi_receipts.append({
            "row_id": row_id,
            "owner": owner.replace(".", "/"),
            "method": "indexOf$default",
            "descriptor": descriptor,
            "flags": sorted(flags),
            "acc_bridge": False,
            "regular_descriptor_present": True,
            "javap_block_sha256": sha256(block.encode("utf-8")),
            "result": "PASS",
        })

    fixture_root = REPO / "Tests/CompilerBackendTests/Fixtures/IOIndexOfDefault2633"
    producer = fixture_root / "producer.kt"
    consumer = fixture_root / "consumer.kt"
    expected = fixture_root / "expected.stdout"
    fixture_hashes = {path.name: sha256(path.read_bytes()) for path in (producer, consumer, expected)}
    compiler = args.kotlin_home / "bin/kotlinc"
    version = run([str(compiler), "-version"])
    compiler_version = (version.stderr + version.stdout).strip()
    if "2.3.10" not in compiler_version:
        raise SystemExit(f"expected Kotlin 2.3.10, got: {compiler_version}")

    with tempfile.TemporaryDirectory(prefix="kuu2633-jvm-reference-") as temporary:
        root = Path(temporary)
        reference_jar = root / "kuu2633-reference.jar"
        run([
            str(compiler), str(producer), str(consumer), "-classpath", classpath,
            "-include-runtime", "-d", str(reference_jar),
        ], timeout=300)
        runtime_classpath = f"{reference_jar}:{classpath}"
        reference_run = run([args.java, "-cp", runtime_classpath, "kuu2633.ConsumerKt"], timeout=60)
        expected_bytes = expected.read_bytes()
        actual_bytes = reference_run.stdout.encode("utf-8")
        if actual_bytes != expected_bytes or reference_run.stderr:
            raise SystemExit(
                "pinned JVM reference output differs from expected.stdout\n"
                f"stdout={reference_run.stdout!r}\nstderr={reference_run.stderr!r}"
            )
        consumer_javap = run([args.javap, "-classpath", runtime_classpath, "-c", "-s", "kuu2633.ConsumerKt"])
        callsite_output = consumer_javap.stdout
        for row_id in sorted(ISSUE_ROWS):
            obligation = obligations_by_id[row_id]
            owner = ledger[row_id]["owner_fqn"]
            call = f"{owner}.indexOf$default:{obligation['originalJVMDescriptor']}"
            if call not in callsite_output:
                raise SystemExit(f"Kotlin 2.3.10 reference consumer does not invoke {row_id}: {call}")

        java_version_result = run([args.java, "-version"])
        java_version_text = java_version_result.stderr or java_version_result.stdout
        with zipfile.ZipFile(reference_jar) as archive:
            consumer_class = archive.read("kuu2633/ConsumerKt.class")
        jvm_reference = {
            "compiler_version": compiler_version,
            "java_version": java_version_text.strip().splitlines()[0],
            "stdout_sha256": sha256(actual_bytes),
            "stderr_sha256": sha256(reference_run.stderr.encode("utf-8")),
            "expected_stdout_sha256": sha256(expected_bytes),
            "consumer_class_sha256": sha256(consumer_class),
            "consumer_javap_sha256": sha256(callsite_output.encode("utf-8")),
            "default_callsites": len(ISSUE_ROWS),
            "result": "PASS",
        }

    receipt = {
        "schema_version": 1,
        "issue": "KUU-2633",
        "candidate_physical_jvm_abi": "NOT_EMITTED_BY_KSWIFTK_NATIVE_TARGET",
        "reference": {
            "kotlin_version": "2.3.10",
            "kotlinx_io_version": "0.9.1",
            "upstream_commit": lock["commit"],
            "maven_artifacts": artifacts,
            "javap_version": javap_version,
            "abi": abi_receipts,
            "consumer": jvm_reference,
            "fixture_sha256": fixture_hashes,
            "result": "PASS",
        },
    }
    encoded = json.dumps(receipt, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    print(encoded, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
