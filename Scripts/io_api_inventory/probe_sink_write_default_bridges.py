#!/usr/bin/env python3
"""Verify the two pinned JVM Sink.write default bridges from their classfiles."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import zipfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
LOCK = HERE / "upstream-lock.json"
EXPECTED_FLAGS = {"ACC_PUBLIC", "ACC_STATIC", "ACC_SYNTHETIC"}
EXPECTED_DEFAULT_MASK_BITS = {"startIndex": 2, "endIndex": 4}
BRIDGES = (
    {
        "row_id": "jvm-03ad4cbeb43abc13",
        "coordinate": "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1",
        "owner": "kotlinx.io.Sink",
        "method": "write$default",
        "descriptor": "(Lkotlinx/io/Sink;[BIIILjava/lang/Object;)V",
        "underlying_descriptor": "([BII)V",
    },
    {
        "row_id": "jvm-ff3de7f8d455d172",
        "coordinate": "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1",
        "owner": "kotlinx.io.ByteStringsKt",
        "method": "write$default",
        "descriptor": (
            "(Lkotlinx/io/Sink;Lkotlinx/io/bytestring/ByteString;IIILjava/lang/Object;)V"
        ),
        "underlying_descriptor": (
            "(Lkotlinx/io/Sink;Lkotlinx/io/bytestring/ByteString;II)V"
        ),
    },
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def artifact_record(lock: dict, coordinate: str, jars_dir: Path) -> tuple[Path, dict]:
    records = [item for item in lock["mavenArtifacts"] if item["coordinate"] == coordinate]
    if len(records) != 1:
        raise ValueError(f"expected one locked artifact for {coordinate}")
    record = records[0]
    path = jars_dir / record["url"].rsplit("/", 1)[-1]
    if not path.is_file():
        raise ValueError(f"missing pinned JVM artifact: {path}")
    actual = sha256(path)
    if actual != record["sha256"]:
        raise ValueError(f"artifact SHA-256 mismatch for {coordinate}: {actual}")
    return path, record


def inspect_class(javap: str, classpath: str, owner: str) -> tuple[str, list[dict]]:
    completed = subprocess.run(
        [javap, "-p", "-s", "-v", "-c", "-classpath", classpath, owner],
        check=True,
        capture_output=True,
        text=True,
    )
    methods = []
    lines = completed.stdout.splitlines()
    for index, line in enumerate(lines):
        if not re.search(r"\bwrite\$default\s*\(", line):
            continue
        descriptor = next(
            (entry.split(":", 1)[1].strip() for entry in lines[index + 1:index + 5]
             if entry.strip().startswith("descriptor:")),
            None,
        )
        flags_line = next(
            (entry.strip() for entry in lines[index + 1:index + 6]
             if entry.strip().startswith("flags:")),
            None,
        )
        if descriptor is None or flags_line is None:
            raise ValueError(f"javap omitted descriptor or flags for {owner}: {line.strip()}")
        flag_match = re.search(r"\)\s*(.*)$", flags_line)
        flags = set(flag_match.group(1).split(", ")) if flag_match else set()
        code_index = next(
            (cursor for cursor in range(index + 1, len(lines)) if lines[cursor].strip() == "Code:"),
            None,
        )
        if code_index is None:
            raise ValueError(f"javap omitted bytecode for {owner}: {line.strip()}")
        instructions = []
        raw_instructions = []
        for instruction_line in lines[code_index + 1:]:
            match = re.match(r"\s*(\d+):\s*(.*)$", instruction_line)
            if match:
                raw = match.group(2).strip()
                raw_instructions.append(raw)
                instructions.append(" ".join(raw.split("//", 1)[0].split()))
            elif instructions:
                break
        if not instructions:
            raise ValueError(f"javap omitted instructions for {owner}: {line.strip()}")
        methods.append({
            "descriptor": descriptor,
            "flags": sorted(flags),
            "declaration": line.strip(),
            "instructions": instructions,
            "raw_instructions": raw_instructions,
        })
    return completed.stdout, methods


def verify(javap: str, jars_dir: Path) -> dict:
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    if lock.get("tag") != "0.9.1" or lock.get("commit") != "362bdc35e159bad6da1e08101c8321792d762281":
        raise ValueError("upstream lock does not match the issue pin")

    core_jar, core_record = artifact_record(
        lock, "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1", jars_dir
    )
    bytestring_jar, bytestring_record = artifact_record(
        lock, "org.jetbrains.kotlinx:kotlinx-io-bytestring-jvm:0.9.1", jars_dir
    )
    classpath = str(core_jar) + ":" + str(bytestring_jar)
    rows = []
    for bridge in BRIDGES:
        output, methods = inspect_class(javap, classpath, bridge["owner"])
        matches = [method for method in methods if method["descriptor"] == bridge["descriptor"]]
        if len(matches) != 1:
            raise ValueError(
                f"expected one {bridge['owner']}.{bridge['method']} with descriptor "
                f"{bridge['descriptor']}; found {len(matches)}"
            )
        flags = set(matches[0]["flags"])
        if flags != EXPECTED_FLAGS:
            raise ValueError(
                f"unexpected access flags for {bridge['row_id']}: {sorted(flags)}"
            )
        if "ACC_BRIDGE" in flags:
            raise ValueError(f"ACC_BRIDGE is not part of {bridge['row_id']} classfile flags")
        instructions = matches[0]["instructions"]
        raw_instructions = matches[0]["raw_instructions"]

        def has_sequence(sequence: list[str]) -> bool:
            return any(
                all(actual == wanted or actual.startswith(wanted + " ")
                    for actual, wanted in zip(
                        instructions[index:index + len(sequence)], sequence, strict=True
                    ))
                for index in range(len(instructions) - len(sequence) + 1)
            )

        expected_code = [
            ["iload 4", "iconst_2", "iand"],
            ["iload 4", "iconst_4", "iand"],
        ]
        if not all(has_sequence(sequence) for sequence in expected_code):
            raise ValueError(
                f"default mask bits {EXPECTED_DEFAULT_MASK_BITS} missing for "
                f"{bridge['row_id']}: {instructions}"
            )
        if not has_sequence(["iload 4", "iconst_2", "iand", "ifeq", "iconst_0", "istore_2"]):
            raise ValueError(f"startIndex default is not zero for {bridge['row_id']}: {instructions}")
        end_default = (
            ["iload 4", "iconst_4", "iand", "ifeq", "aload_1", "arraylength", "istore_3"]
            if bridge["row_id"] == "jvm-03ad4cbeb43abc13"
            else ["iload 4", "iconst_4", "iand", "ifeq", "aload_1",
                  "invokevirtual", "istore_3"]
        )
        if not has_sequence(end_default):
            raise ValueError(f"endIndex default is not source size for {bridge['row_id']}: {instructions}")
        marker_policy = "must be null; non-null throws UnsupportedOperationException"
        if bridge["row_id"] == "jvm-03ad4cbeb43abc13":
            if ("aload 5" not in instructions
                    or not any(instruction.startswith("ifnull ") for instruction in instructions)):
                raise ValueError(f"Sink.write$default marker guard is missing: {instructions}")
            if not any("UnsupportedOperationException" in line for line in raw_instructions):
                raise ValueError("Sink.write$default marker failure is not UnsupportedOperationException")
        else:
            marker_policy = "Object marker parameter is present and ignored by the static extension bridge"
            if any(instruction.endswith(" 5") or instruction == "aload 5" for instruction in instructions):
                raise ValueError(f"ByteStringsKt.write$default unexpectedly reads marker slot: {instructions}")
        regular_name = "write"
        regular_descriptors = {
            entry.split(":", 1)[1].strip()
            for index, line in enumerate(output.splitlines())
            if re.search(r"\bwrite\s*\(", line)
            for entry in output.splitlines()[index + 1:index + 5]
            if entry.strip().startswith("descriptor:")
        }
        if bridge["underlying_descriptor"] not in regular_descriptors:
            raise ValueError(
                f"underlying {regular_name} descriptor missing for {bridge['row_id']}"
            )
        classfile_path = bridge["owner"].replace(".", "/") + ".class"
        with zipfile.ZipFile(core_jar) as archive:
            classfile = archive.read(classfile_path)
        rows.append({
            **bridge,
            "access_flags": sorted(flags),
            "synthetic": "ACC_SYNTHETIC" in flags,
            "static": "ACC_STATIC" in flags,
            "bridge": "ACC_BRIDGE" in flags,
            "default_mask_bits": EXPECTED_DEFAULT_MASK_BITS,
            "marker_parameter_slot": 5,
            "marker_policy": marker_policy,
            "classfile_sha256": hashlib.sha256(classfile).hexdigest(),
            "classfile_bytes": len(classfile),
            "result": "PASS",
        })

    version = subprocess.run([javap, "-version"], check=True, capture_output=True, text=True)
    return {
        "schema_version": 1,
        "reference": {"tag": lock["tag"], "commit": lock["commit"]},
        "tool": {"name": Path(javap).name, "version": (version.stdout or version.stderr).strip()},
        "artifacts": [
            {"coordinate": core_record["coordinate"], "sha256": sha256(core_jar)},
            {"coordinate": bytestring_record["coordinate"], "sha256": sha256(bytestring_jar)},
        ],
        "rows": rows,
        "checked_method_count": len(rows),
        "candidate_jvm_classfile": "NOT_APPLICABLE: KSwiftK emits Native artifacts, not JVM classfiles",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jars-dir", required=True, type=Path)
    parser.add_argument("--javap", default=shutil.which("javap"))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.javap:
        parser.error("javap is required (set --javap or add a JDK to PATH)")
    result = verify(args.javap, args.jars_dir)
    encoded = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    print(encoded, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
