#!/usr/bin/env python3
"""Check pinned JVM default bridges from the physical class file with javap."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import urlopen


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
INVENTORY = HERE / "api-inventory.tsv"
LOCK = HERE / "upstream-lock.json"
ROW_IDS = (
    "jvm-06eee316b84478d8",
    "jvm-0a7391fd7c844ff7",
    "jvm-1ba14d2113458d26",
    "jvm-c376d0d1321523df",
    "jvm-ebe766fdf289f961",
)
REQUIRED_FLAGS = {"ACC_PUBLIC", "ACC_STATIC", "ACC_SYNTHETIC"}
REGULAR_DECLARATIONS = {
    "jvm-06eee316b84478d8": (
        "decode", "(Lkotlin/io/encoding/Base64;Lkotlinx/io/bytestring/ByteString;II)[B"
    ),
    "jvm-0a7391fd7c844ff7": (
        "decodeToByteString", "(Lkotlin/io/encoding/Base64;Ljava/lang/CharSequence;II)Lkotlinx/io/bytestring/ByteString;"
    ),
    "jvm-1ba14d2113458d26": (
        "decodeToByteString", "(Lkotlin/io/encoding/Base64;[BII)Lkotlinx/io/bytestring/ByteString;"
    ),
    "jvm-c376d0d1321523df": (
        "decodeIntoByteArray", "(Lkotlin/io/encoding/Base64;Lkotlinx/io/bytestring/ByteString;[BIII)I"
    ),
    "jvm-ebe766fdf289f961": (
        "decodeToByteString", "(Lkotlin/io/encoding/Base64;Lkotlinx/io/bytestring/ByteString;II)Lkotlinx/io/bytestring/ByteString;"
    ),
}
METHOD_HEADER = re.compile(r"^\s{2}(?:public|protected|private)\s+.*(?<![\w$])([A-Za-z_$][\w$]*)\(.*\);$")


def descriptor_from_signature(signature: str) -> tuple[str, str]:
    match = re.search(r"\bfun\s+([^\s]+)\s+\((.*)\)(\S+)$", signature)
    if not match:
        raise ValueError(f"cannot parse JVM signature: {signature}")
    return match.group(1), f"({match.group(2)}){match.group(3)}"


def target_rows() -> list[dict[str, str]]:
    with INVENTORY.open(encoding="utf-8", newline="") as stream:
        by_id = {row["row_id"]: row for row in csv.DictReader(stream, delimiter="\t")}
    if set(ROW_IDS) - by_id.keys():
        raise ValueError("one or more targeted default bridge rows are absent from api-inventory.tsv")
    rows = []
    for row_id in ROW_IDS:
        row = by_id[row_id]
        if row["api_kind"] != "default/synthetic bridge" or row["owner_fqn"] != "kotlinx/io/bytestring/Base64Kt":
            raise ValueError(f"unexpected ledger classification for {row_id}")
        name, descriptor = descriptor_from_signature(row["signature"])
        if not row["signature"].startswith("public static synthetic fun ") or name != row["name"]:
            raise ValueError(f"unexpected bridge declaration flags/name in inventory for {row_id}")
        rows.append({"row_id": row_id, "owner": row["owner_fqn"].replace("/", "."),
                     "name": name, "descriptor": descriptor,
                     "regular_name": REGULAR_DECLARATIONS[row_id][0],
                     "regular_descriptor": REGULAR_DECLARATIONS[row_id][1]})
    return rows


def verify_underlying_descriptors(rows: list[dict[str, str]]) -> None:
    catalog = json.loads((HERE / "jvm-declarations.json").read_text(encoding="utf-8"))
    declarations = catalog["declarations"]
    for row in rows:
        matches = [declaration for declaration in declarations
                   if declaration["module"] == "bytestring"
                   and declaration["jvmOwner"] == row["owner"].replace(".", "/")
                   and declaration["jvmName"] == row["regular_name"]
                   and declaration["descriptor"] == row["regular_descriptor"]]
        bridge_source = row["row_id"]
        if len(matches) != 1:
            raise ValueError(f"{bridge_source} expected one underlying Kotlin declaration, found {len(matches)}")
        declaration = matches[0]
        regular_descriptor = declaration["descriptor"]
        parameter_descriptor, return_descriptor = regular_descriptor[1:].split(")", 1)
        mask_count = math.ceil(sum(declaration["defaults"]) / 32)
        expected_bridge_descriptor = f"({parameter_descriptor}{'I' * mask_count}Ljava/lang/Object;){return_descriptor}"
        if declaration["visibility"] != "public" or not mask_count:
            raise ValueError(f"{bridge_source} underlying declaration is not public with default parameters")
        if row["descriptor"] != expected_bridge_descriptor:
            raise ValueError(
                f"{bridge_source} descriptor does not match its regular declaration/default mask: "
                f"{expected_bridge_descriptor}"
            )


def parse_javap(text: str) -> list[dict[str, object]]:
    lines = text.splitlines()
    methods = []
    index = 0
    while index < len(lines):
        header = METHOD_HEADER.match(lines[index])
        if not header:
            index += 1
            continue
        name = header.group(1)
        descriptor = None
        flags: set[str] = set()
        cursor = index + 1
        while cursor < len(lines) and not METHOD_HEADER.match(lines[cursor]):
            descriptor_match = re.match(r"\s*descriptor:\s*(\S+)", lines[cursor])
            if descriptor_match:
                descriptor = descriptor_match.group(1)
            flags_match = re.match(r"\s*flags:.*?\b(ACC_[A-Z_]+(?:,\s*ACC_[A-Z_]+)*)\s*$", lines[cursor])
            if flags_match:
                flags.update(re.findall(r"ACC_[A-Z_]+", flags_match.group(1)))
            cursor += 1
        if descriptor is not None:
            methods.append({"name": name, "descriptor": descriptor, "flags": flags})
        index = cursor
    return methods


def verify_methods(expected_rows: list[dict[str, str]], methods: list[dict[str, object]]) -> list[str]:
    output = []
    for row in expected_rows:
        matches = [method for method in methods
                   if method["name"] == row["name"] and method["descriptor"] == row["descriptor"]]
        if len(matches) != 1:
            raise ValueError(f"{row['row_id']} expected one exact JVM method, found {len(matches)}")
        flags = matches[0]["flags"]
        if flags != REQUIRED_FLAGS:
            raise ValueError(f"{row['row_id']} unexpected JVM flags: {sorted(flags)}")
        output.append(
            f"PASS {row['row_id']} physical-jvm-descriptor={row['descriptor']} "
            f"flags={','.join(sorted(flags))}; ACC_BRIDGE absent"
        )
    return output


def inspect_jar(javap: str, jar: Path) -> str:
    result = subprocess.run(
        [javap, "-v", "-p", "-classpath", str(jar), "kotlinx.io.bytestring.Base64Kt"],
        check=True, capture_output=True, text=True,
    )
    if result.stderr:
        raise ValueError(f"javap emitted unexpected stderr: {result.stderr.strip()}")
    return result.stdout


def pinned_jar() -> dict[str, str]:
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    artifact = next((item for item in lock["mavenArtifacts"]
                     if item["coordinate"].startswith("org.jetbrains.kotlinx:kotlinx-io-bytestring-jvm:")), None)
    if artifact is None:
        raise ValueError("pinned bytestring JVM artifact is missing from upstream-lock.json")
    return {"url": artifact["url"], "sha256": artifact["sha256"],
            "filename": artifact["url"].rsplit("/", 1)[-1]}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jar", type=Path, help="locked kotlinx-io-bytestring-jvm-0.9.1.jar")
    parser.add_argument("--javap", default="javap", help="JDK javap executable")
    parser.add_argument("--report", type=Path, help="write a deterministic JSON receipt for the pinned classfile probe")
    args = parser.parse_args(argv)
    try:
        javap = shutil.which(args.javap)
        if javap is None:
            raise ValueError(f"javap executable not found: {args.javap}")
        artifact = pinned_jar()
        expected_rows = target_rows()
        verify_underlying_descriptors(expected_rows)
        if args.jar:
            jar = args.jar.resolve()
            if sha256(jar) != artifact["sha256"]:
                raise ValueError("provided jar does not match the pinned upstream SHA-256")
            methods = inspect_jar(javap, jar)
            result = verify_methods(expected_rows, parse_javap(methods))
            for line in result:
                print(line)
        else:
            with tempfile.TemporaryDirectory(prefix="kuu-2617-jvm-abi-") as temporary:
                jar = Path(temporary) / artifact["filename"]
                with urlopen(artifact["url"], timeout=60) as response:
                    jar.write_bytes(response.read())
                if sha256(jar) != artifact["sha256"]:
                    raise ValueError("downloaded jar does not match the pinned upstream SHA-256")
                methods = inspect_jar(javap, jar)
                result = verify_methods(expected_rows, parse_javap(methods))
                for line in result:
                    print(line)
        if args.report:
            receipt = {
                "schema_version": 1,
                "reference": {
                    "tag": "0.9.1",
                    "commit": "362bdc35e159bad6da1e08101c8321792d762281",
                    "artifact": artifact["filename"],
                    "artifact_sha256": artifact["sha256"],
                    "javap": Path(javap).name,
                    "captured_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                },
                "results": [
                    {"row_id": row["row_id"], "descriptor": row["descriptor"],
                     "regular_method": row["regular_name"], "flags": sorted(method["flags"]),
                     "stdout_sha256": hashlib.sha256((line + "\n").encode()).hexdigest(),
                     "stderr_sha256": hashlib.sha256(b"").hexdigest(),
                     "output_count": 1}
                    for row, line in zip(expected_rows, result, strict=True)
                    for method in [next(item for item in parse_javap(methods)
                                        if item["name"] == row["name"] and item["descriptor"] == row["descriptor"])]
                ],
            }
            args.report.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        return 0
    except (OSError, subprocess.SubprocessError, ValueError, KeyError) as error:
        parser.exit(1, f"JVM default bridge probe failed: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
