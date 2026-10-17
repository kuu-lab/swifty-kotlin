#!/usr/bin/env python3
"""Verify ByteStringBuilder default bridge shapes in the pinned JVM artifact."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
LOCK_PATH = HERE / "upstream-lock.json"
JVM_DECLARATIONS_PATH = HERE / "jvm-declarations.json"
INVENTORY_PATH = HERE / "api-inventory.tsv"
UPSTREAM_SOURCE_PATH = HERE / "upstream/kotlinx-io-0.9.1/bytestring/common/src/ByteStringBuilder.kt"
CANDIDATE_SOURCE_PATH = REPO / "Sources/CompilerCore/Stdlib/kotlinx/io/bytestring/ByteStringBuilder.kt"
EXPECTED_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"

ACC_PUBLIC = 0x0001
ACC_STATIC = 0x0008
ACC_BRIDGE = 0x0040
ACC_SYNTHETIC = 0x1000

EXPECTED_METHODS = [
    {
        "row_id": "jvm-0de664be9f7d0a3a",
        "class": "kotlinx/io/bytestring/ByteStringBuilder",
        "name": "append$default",
        "descriptor": "(Lkotlinx/io/bytestring/ByteStringBuilder;[BIIILjava/lang/Object;)V",
        "flags": {"public": True, "static": True, "bridge": False, "synthetic": True},
        "marker_parameter": "java.lang.Object",
        "declaration": "kotlinx.io.bytestring.ByteStringBuilder.append([BII)",
        "kotlin_owner": "kotlinx/io/bytestring/ByteStringBuilder",
        "kotlin_name": "append",
        "kotlin_descriptor": "([BII)V",
        "omitted_parameter_sets": [[1, 2], [1], [2]],
        "upstream_ref": "bytestring/common/src/ByteStringBuilder.kt:79",
        "candidate_ref": "Sources/CompilerCore/Stdlib/kotlinx/io/bytestring/ByteStringBuilder.kt:29",
    },
    {
        "row_id": "jvm-4c5b809c5600e77b",
        "class": "kotlinx/io/bytestring/ByteStringBuilder",
        "name": "<init>",
        "descriptor": "()V",
        "flags": {"public": True, "static": False, "bridge": False, "synthetic": False},
        "marker_parameter": None,
        "declaration": "kotlinx.io.bytestring.ByteStringBuilder.<init>(I)",
        "kotlin_owner": "kotlinx/io/bytestring/ByteStringBuilder",
        "kotlin_name": "<init>",
        "kotlin_descriptor": "(I)V",
        "omitted_parameter_sets": [],
        "upstream_ref": "bytestring/common/src/ByteStringBuilder.kt:28",
        "candidate_ref": "Sources/CompilerCore/Stdlib/kotlinx/io/bytestring/ByteStringBuilder.kt:9",
    },
    {
        "row_id": "jvm-827d471d59e105ce",
        "class": "kotlinx/io/bytestring/ByteStringBuilderKt",
        "name": "buildByteString$default",
        "descriptor": "(ILkotlin/jvm/functions/Function1;ILjava/lang/Object;)Lkotlinx/io/bytestring/ByteString;",
        "flags": {"public": True, "static": True, "bridge": False, "synthetic": True},
        "marker_parameter": "java.lang.Object",
        "declaration": "kotlinx.io.bytestring.buildByteString(ILkotlin/jvm/functions/Function1;)",
        "kotlin_owner": "kotlinx/io/bytestring/ByteStringBuilderKt",
        "kotlin_name": "buildByteString",
        "kotlin_descriptor": "(ILkotlin/jvm/functions/Function1;)Lkotlinx/io/bytestring/ByteString;",
        "omitted_parameter_sets": [[0]],
        "upstream_ref": "bytestring/common/src/ByteStringBuilder.kt:126",
        "candidate_ref": "Sources/CompilerCore/Stdlib/kotlinx/io/bytestring/ByteStringBuilder.kt:56",
    },
    {
        "row_id": "jvm-f183ae0aeeced795",
        "class": "kotlinx/io/bytestring/ByteStringBuilder",
        "name": "<init>",
        "descriptor": "(IILkotlin/jvm/internal/DefaultConstructorMarker;)V",
        "flags": {"public": True, "static": False, "bridge": False, "synthetic": True},
        "marker_parameter": "kotlin.jvm.internal.DefaultConstructorMarker",
        "declaration": "kotlinx.io.bytestring.ByteStringBuilder.<init>(I)",
        "kotlin_owner": "kotlinx/io/bytestring/ByteStringBuilder",
        "kotlin_name": "<init>",
        "kotlin_descriptor": "(I)V",
        "omitted_parameter_sets": [[0]],
        "upstream_ref": "bytestring/common/src/ByteStringBuilder.kt:28",
        "candidate_ref": "Sources/CompilerCore/Stdlib/kotlinx/io/bytestring/ByteStringBuilder.kt:9",
    },
]


class ClassReader:
    def __init__(self, data: bytes):
        self.data = data
        self.offset = 0

    def take(self, size: int) -> bytes:
        end = self.offset + size
        if size < 0 or end > len(self.data):
            raise ValueError("truncated JVM classfile")
        value = self.data[self.offset:end]
        self.offset = end
        return value

    def u1(self) -> int:
        return int.from_bytes(self.take(1), "big")

    def u2(self) -> int:
        return int.from_bytes(self.take(2), "big")

    def u4(self) -> int:
        return int.from_bytes(self.take(4), "big")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(f"blob {len(data)}\0".encode("ascii") + data).hexdigest()


def read_class_methods(data: bytes) -> tuple[str, list[dict], dict[int, dict]]:
    reader = ClassReader(data)
    if reader.u4() != 0xCAFEBABE:
        raise ValueError("invalid JVM classfile magic")
    reader.u2()
    reader.u2()
    constant_pool_count = reader.u2()
    constant_pool = [None] * constant_pool_count
    index = 1
    while index < constant_pool_count:
        tag = reader.u1()
        if tag == 1:
            length = reader.u2()
            raw = reader.take(length).replace(b"\xc0\x80", b"\x00")
            constant_pool[index] = (tag, raw.decode("utf-8", errors="surrogatepass"))
        elif tag in {3, 4}:
            reader.take(4)
        elif tag in {5, 6}:
            reader.take(8)
            index += 1
        elif tag == 7:
            constant_pool[index] = (tag, reader.u2())
        elif tag in {8, 16, 19, 20}:
            reader.take(2)
        elif tag in {9, 10, 11, 12, 17, 18}:
            constant_pool[index] = (tag, reader.u2(), reader.u2())
        elif tag == 15:
            reader.take(3)
        else:
            raise ValueError(f"unsupported JVM constant-pool tag {tag}")
        index += 1

    def utf8(constant_index: int) -> str:
        entry = constant_pool[constant_index]
        if not entry or entry[0] != 1:
            raise ValueError("invalid UTF-8 constant-pool reference")
        return entry[1]

    reader.u2()
    this_class = constant_pool[reader.u2()]
    if not this_class or this_class[0] != 7:
        raise ValueError("invalid this_class constant-pool reference")
    class_name = utf8(this_class[1])
    reader.u2()
    for _ in range(reader.u2()):
        reader.u2()

    def skip_attributes(count: int) -> None:
        for _ in range(count):
            reader.u2()
            reader.take(reader.u4())

    for _ in range(reader.u2()):
        reader.take(6)
        skip_attributes(reader.u2())

    methods = []
    for _ in range(reader.u2()):
        flags = reader.u2()
        name = utf8(reader.u2())
        descriptor = utf8(reader.u2())
        code = None
        for _ in range(reader.u2()):
            attribute_name = utf8(reader.u2())
            attribute = ClassReader(reader.take(reader.u4()))
            if attribute_name != "Code":
                continue
            attribute.u2()
            attribute.u2()
            code = attribute.take(attribute.u4())
            attribute.take(attribute.u2() * 8)
            for _ in range(attribute.u2()):
                attribute.u2()
                attribute.take(attribute.u4())
            if attribute.offset != len(attribute.data):
                raise ValueError("malformed JVM Code attribute")
        methods.append({"name": name, "descriptor": descriptor, "access_flags": flags, "code": code})

    method_references = {}
    for index, entry in enumerate(constant_pool):
        if not entry or entry[0] not in {10, 11}:
            continue
        owner_entry = constant_pool[entry[1]]
        name_and_type = constant_pool[entry[2]]
        if not owner_entry or owner_entry[0] != 7 or not name_and_type or name_and_type[0] != 12:
            raise ValueError("invalid method reference in JVM constant pool")
        method_references[index] = {
            "owner": utf8(owner_entry[1]),
            "name": utf8(name_and_type[1]),
            "descriptor": utf8(name_and_type[2]),
        }
    return class_name, methods, method_references


ICONST_OPCODE = {1: 0x04, 2: 0x05, 4: 0x07}


def require_mask_branch(method: dict, local_index: int, mask: int, default_instructions: bytes) -> dict:
    code = method.get("code")
    if code is None:
        raise ValueError(f"method has no Code attribute: {method['name']}{method['descriptor']}")
    load = bytes([0x1A + local_index]) if local_index < 4 else bytes([0x15, local_index])
    prefix = load + bytes([ICONST_OPCODE[mask], 0x7E, 0x99])
    matches = []
    for start in range(len(code) - len(prefix) - 1):
        if code[start:start + len(prefix)] != prefix:
            continue
        branch_opcode = start + len(prefix) - 1
        branch_offset = int.from_bytes(code[branch_opcode + 1:branch_opcode + 3], "big", signed=True)
        target = branch_opcode + branch_offset
        default_start = branch_opcode + 3
        if (target >= default_start
                and code[default_start:target] == default_instructions):
            matches.append({"mask": mask, "mask_local": local_index, "branch_offset": start,
                            "default_instructions_hex": default_instructions.hex()})
    if len(matches) != 1:
        raise ValueError(
            f"expected one mask {mask} branch in {method['name']}{method['descriptor']}, found {len(matches)}"
        )
    return matches[0]


def verify_source_and_metadata(lock: dict) -> dict:
    source_bytes = UPSTREAM_SOURCE_PATH.read_bytes()
    source_lock = next(
        (entry for entry in lock["upstreamFiles"] if entry["path"] == "bytestring/common/src/ByteStringBuilder.kt"),
        None,
    )
    if source_lock is None or len(source_bytes) != source_lock["size"]:
        raise ValueError("pinned upstream ByteStringBuilder.kt is missing or has the wrong size")
    if git_blob_sha(source_bytes) != source_lock["gitBlobSha"] or sha256(source_bytes) != source_lock["sha256"]:
        raise ValueError("pinned upstream ByteStringBuilder.kt does not match its lock")

    upstream_lines = source_bytes.decode("utf-8").splitlines()
    expected_upstream = {
        28: "public class ByteStringBuilder(initialCapacity: Int = 0)",
        79: "public fun append(array: ByteArray, startIndex: Int = 0, endIndex: Int = array.size)",
        126: "public inline fun buildByteString(capacity: Int = 0, builderAction: ByteStringBuilder.() -> Unit): ByteString",
    }
    for line_number, declaration in expected_upstream.items():
        if line_number > len(upstream_lines) or declaration not in upstream_lines[line_number - 1]:
            raise ValueError(f"unexpected upstream declaration at ByteStringBuilder.kt:{line_number}")

    candidate = CANDIDATE_SOURCE_PATH.read_text(encoding="utf-8")
    for declaration in (
        "public class ByteStringBuilder(initialCapacity: Int = 0)",
        "public fun append(array: ByteArray, startIndex: Int = 0, endIndex: Int = array.size)",
        "capacity: Int = 0,",
    ):
        if declaration not in candidate:
            raise ValueError(f"candidate source does not contain the expected declaration fragment: {declaration}")

    metadata_bytes = JVM_DECLARATIONS_PATH.read_bytes()
    if sha256(metadata_bytes) != lock.get("jvmDeclarationsSha256"):
        raise ValueError("JVM metadata declaration catalog does not match its lock")
    metadata = json.loads(metadata_bytes.decode("utf-8"))
    entries = {
        (entry["jvmOwner"], entry["jvmName"], entry["descriptor"]): entry
        for entry in metadata["declarations"]
    }
    expected_metadata = {
        ("kotlinx/io/bytestring/ByteStringBuilder", "<init>", "(I)V"): {
            "fqName": "kotlinx.io.bytestring.ByteStringBuilder.<init>",
            "parameters": ["kotlin.Int"],
            "defaults": [True],
        },
        ("kotlinx/io/bytestring/ByteStringBuilder", "append", "([BII)V"): {
            "fqName": "kotlinx.io.bytestring.ByteStringBuilder.append",
            "parameters": ["kotlin.ByteArray", "kotlin.Int", "kotlin.Int"],
            "defaults": [False, True, True],
        },
        ("kotlinx/io/bytestring/ByteStringBuilderKt", "buildByteString", "(ILkotlin/jvm/functions/Function1;)Lkotlinx/io/bytestring/ByteString;"): {
            "fqName": "kotlinx.io.bytestring.buildByteString",
            "parameters": ["kotlin.Int", "kotlin.Function1<kotlinx.io.bytestring.ByteStringBuilder,kotlin.Unit>"],
            "defaults": [True, False],
        },
    }
    verified_metadata = []
    for key, expected in expected_metadata.items():
        entry = entries.get(key)
        if entry is None:
            raise ValueError(f"missing Kotlin metadata declaration {key}")
        for field, value in expected.items():
            if entry.get(field) != value:
                raise ValueError(f"unexpected metadata {field} for {key}: {entry.get(field)!r}")
        if entry.get("visibility") != "public":
            raise ValueError(f"underlying declaration is not public: {key}")
        verified_metadata.append({"owner": key[0], "name": key[1], "descriptor": key[2], **expected})

    return {
        "upstream_source_sha256": sha256(source_bytes),
        "upstream_source_git_blob_sha": git_blob_sha(source_bytes),
        "candidate_source_sha256": sha256(CANDIDATE_SOURCE_PATH.read_bytes()),
        "jvm_declarations_sha256": sha256(metadata_bytes),
        "declarations": verified_metadata,
    }


def verify_inventory_rows() -> list[dict]:
    with INVENTORY_PATH.open(encoding="utf-8", newline="") as stream:
        rows = {row["row_id"]: row for row in csv.DictReader(stream, delimiter="\t")}
    verified = []
    for expected in EXPECTED_METHODS:
        row = rows.get(expected["row_id"])
        if row is None:
            raise ValueError(f"missing inventory row {expected['row_id']}; regenerate the inventory")
        if row["owner_issue"] != "KUU-2619":
            raise ValueError(f"inventory row {expected['row_id']} is not assigned to KUU-2619")
        if expected["descriptor"] not in row["signature"]:
            raise ValueError(f"inventory descriptor mismatch for {expected['row_id']}")
        if (row["owner_fqn"], row["name"]) != (
            expected["class"], expected["name"]
        ):
            raise ValueError(f"inventory owner/name mismatch for {expected['row_id']}")
        if expected["upstream_ref"] != row["upstream_source_refs"]:
            raise ValueError(f"inventory upstream source mapping mismatch for {expected['row_id']}")
        if expected["candidate_ref"] not in row["local_candidate_refs"]:
            raise ValueError(f"inventory candidate mapping mismatch for {expected['row_id']}")
        if row["local_test_refs"] == "none":
            raise ValueError(f"inventory row {expected['row_id']} has no direct local probe mapping")
        for expected_ref in ("Scripts/io_api_inventory/cases/bytestring_builder_default_bridges.kt",
                             "Scripts/io_api_inventory/probe_bytestring_builder_jvm_abi.py"):
            if expected_ref not in row["local_test_refs"]:
                raise ValueError(f"inventory row {expected['row_id']} omits {expected_ref}")
        verified.append({"row_id": expected["row_id"], "descriptor": expected["descriptor"]})
    if len(rows) < 4:
        raise ValueError("API inventory is unexpectedly incomplete")
    return verified


def method_flags(flags: int) -> dict:
    return {
        "public": bool(flags & ACC_PUBLIC),
        "static": bool(flags & ACC_STATIC),
        "bridge": bool(flags & ACC_BRIDGE),
        "synthetic": bool(flags & ACC_SYNTHETIC),
    }


def verify_jar(jar_path: Path, artifact: dict, declarations: dict) -> dict:
    jar_bytes = jar_path.read_bytes()
    artifact_hash = sha256(jar_bytes)
    if artifact_hash != artifact["sha256"]:
        raise ValueError(f"pinned bytestring JVM artifact SHA-256 mismatch: {artifact_hash}")

    classes: dict[str, dict] = {}
    with zipfile.ZipFile(jar_path) as archive:
        for class_name in sorted({entry["class"] for entry in EXPECTED_METHODS}):
            class_path = class_name + ".class"
            try:
                class_bytes = archive.read(class_path)
            except KeyError as error:
                raise ValueError(f"pinned JVM artifact does not contain {class_path}") from error
            actual_name, methods, method_references = read_class_methods(class_bytes)
            if actual_name != class_name:
                raise ValueError(f"unexpected class name in {class_path}: {actual_name}")
            classes[class_name] = {
                "path": class_path,
                "sha256": sha256(class_bytes),
                "methods": methods,
                "method_references": method_references,
            }

    observed = []
    defaults_by_declaration = {
        (entry["owner"], entry["name"], entry["descriptor"]): entry["defaults"]
        for entry in declarations["declarations"]
    }
    for expected in EXPECTED_METHODS:
        class_record = classes[expected["class"]]
        matches = [method for method in class_record["methods"]
                   if method["name"] == expected["name"]
                   and method["descriptor"] == expected["descriptor"]]
        if len(matches) != 1:
            raise ValueError(
                f"expected exactly one {expected['class']}.{expected['name']}{expected['descriptor']}, found {len(matches)}"
            )
        flags = method_flags(matches[0]["access_flags"])
        if flags != expected["flags"]:
            raise ValueError(f"unexpected access flags for {expected['row_id']}: {flags}")
        defaults = defaults_by_declaration.get((
            expected["kotlin_owner"], expected["kotlin_name"], expected["kotlin_descriptor"]
        ))
        if defaults is None:
            raise ValueError(f"missing underlying Kotlin declaration for {expected['row_id']}")
        mask_values = []
        for omitted in expected["omitted_parameter_sets"]:
            if any(index < 0 or index >= len(defaults) or not defaults[index] for index in omitted):
                raise ValueError(f"mask set does not match defaults for {expected['row_id']}")
            mask_values.append(sum(1 << index for index in omitted))
        observed.append({
            **{key: value for key, value in expected.items() if key != "omitted_parameter_sets"},
            "observed_flags": flags,
            "underlying_defaults": defaults,
            "mask_parameter_values": mask_values,
        })

    builder_methods = classes["kotlinx/io/bytestring/ByteStringBuilder"]["methods"]
    default_constructor = next(
        method for method in builder_methods
        if method["name"] == "<init>"
        and method["descriptor"] == "(IILkotlin/jvm/internal/DefaultConstructorMarker;)V"
    )
    append_default = next(
        method for method in builder_methods
        if method["name"] == "append$default"
        and method["descriptor"] == "(Lkotlinx/io/bytestring/ByteStringBuilder;[BIIILjava/lang/Object;)V"
    )
    build_default = next(
        method for method in classes["kotlinx/io/bytestring/ByteStringBuilderKt"]["methods"]
        if method["name"] == "buildByteString$default"
        and method["descriptor"] == "(ILkotlin/jvm/functions/Function1;ILjava/lang/Object;)Lkotlinx/io/bytestring/ByteString;"
    )
    mask_checks = [
        {"row_id": "jvm-f183ae0aeeced795", **require_mask_branch(
            default_constructor, 2, 1, bytes([0x03, 0x3C]))},
        {"row_id": "jvm-0de664be9f7d0a3a", **require_mask_branch(
            append_default, 4, 2, bytes([0x03, 0x3D]))},
        {"row_id": "jvm-0de664be9f7d0a3a", **require_mask_branch(
            append_default, 4, 4, bytes([0x2B, 0xBE, 0x3E]))},
        {"row_id": "jvm-827d471d59e105ce", **require_mask_branch(
            build_default, 2, 1, bytes([0x03, 0x3B]))},
    ]

    noarg_constructor = next(
        method for method in builder_methods
        if method["name"] == "<init>" and method["descriptor"] == "()V"
    )
    noarg_code = noarg_constructor.get("code")
    if noarg_code is None or len(noarg_code) != 8 or noarg_code[:5] != bytes([0x2A, 0x03, 0x04, 0x01, 0xB7]) or noarg_code[7] != 0xB1:
        raise ValueError("no-arg constructor does not delegate with capacity 0, mask 1, and a null marker")
    noarg_reference_index = int.from_bytes(noarg_code[5:7], "big")
    noarg_reference = classes["kotlinx/io/bytestring/ByteStringBuilder"]["method_references"].get(noarg_reference_index)
    if noarg_reference != {
        "owner": "kotlinx/io/bytestring/ByteStringBuilder",
        "name": "<init>",
        "descriptor": "(IILkotlin/jvm/internal/DefaultConstructorMarker;)V",
    }:
        raise ValueError("no-arg constructor delegates to an unexpected JVM constructor")

    return {
        "result": "PASS",
        "artifact_coordinate": artifact["coordinate"],
        "artifact_sha256": artifact_hash,
        "classes": {name: {"path": record["path"], "sha256": record["sha256"]}
                     for name, record in classes.items()},
        "methods": observed,
        "mask_bytecode_checks": mask_checks,
        "noarg_constructor_delegation": {
            "capacity": 0,
            "mask": 1,
            "marker": None,
            "target": noarg_reference,
        },
        "boundary": (
            "This verifies physical classfile shape in the pinned reference JAR. "
            "KSwiftK emits native code; candidate source and KLIB default-dispatch runs are separate evidence."
        ),
    }


def run(jar_path: Path) -> dict:
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    if lock.get("tag") != "0.9.1" or lock.get("commit") != EXPECTED_COMMIT:
        raise ValueError("upstream lock does not point to the fixed kotlinx-io 0.9.1 commit")
    artifact = next(
        (item for item in lock["mavenArtifacts"]
         if item["coordinate"] == "org.jetbrains.kotlinx:kotlinx-io-bytestring-jvm:0.9.1"),
        None,
    )
    if artifact is None:
        raise ValueError("pinned bytestring JVM artifact is missing from upstream-lock.json")
    declarations = verify_source_and_metadata(lock)
    inventory = verify_inventory_rows()
    classfiles = verify_jar(jar_path, artifact, declarations)
    return {
        "schema_version": 1,
        "result": "PASS",
        "reference_version": lock["tag"],
        "reference_commit": lock["commit"],
        "reference_declarations": declarations,
        "inventory_rows": inventory,
        "classfile_probe": classfiles,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    jar_group = parser.add_mutually_exclusive_group(required=True)
    jar_group.add_argument("--jar", type=Path, help="previously downloaded pinned bytestring JVM jar")
    jar_group.add_argument("--download", action="store_true", help="download the pinned bytestring JVM jar")
    parser.add_argument("--output", type=Path, help="write the JSON report to this path")
    args = parser.parse_args()

    try:
        if args.jar:
            report = run(args.jar)
        else:
            lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
            artifact = next(
                item for item in lock["mavenArtifacts"]
                if item["coordinate"] == "org.jetbrains.kotlinx:kotlinx-io-bytestring-jvm:0.9.1"
            )
            with tempfile.TemporaryDirectory(prefix="kuu2619-builder-jvm-") as temporary:
                jar_path = Path(temporary) / artifact["url"].rsplit("/", 1)[-1]
                with urllib.request.urlopen(artifact["url"], timeout=60) as response:
                    jar_path.write_bytes(response.read())
                report = run(jar_path)
        output = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(output, encoding="utf-8")
        print(output, end="")
        return 0
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        print(f"ByteStringBuilder JVM ABI probe: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
