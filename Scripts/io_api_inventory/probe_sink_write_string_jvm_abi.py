#!/usr/bin/env python3
"""Check the pinned JVM classfile shape for Sink.writeString default bridges."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
LOCK_PATH = HERE / "upstream-lock.json"
TEST_INDEX_PATH = HERE / "upstream-tests-index.json"
JVM_DECLARATIONS_PATH = HERE / "jvm-declarations.json"
UPSTREAM_UTF8_PATH = HERE / "upstream/kotlinx-io-0.9.1/core/common/src/Utf8.kt"
LOCAL_UTF8_PATH = REPO / "Sources/CompilerCore/Stdlib/kotlinx/io/Utf8.kt"
UPSTREAM_TEST_PATH = "core/common/test/AbstractSinkTest.kt"
EXPECTED_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"
CLASS_PATH = "kotlinx/io/Utf8Kt.class"

EXPECTED_DECLARATIONS = {
    (
        "writeString",
        "(Lkotlinx/io/Sink;Ljava/lang/String;II)V",
    ): {
        "fqName": "kotlinx.io.writeString",
        "receiver": "kotlinx.io.Sink",
        "parameters": ["kotlin.String", "kotlin.Int", "kotlin.Int"],
        "defaults": [False, True, True],
        "visibility": "public",
        "source_line": 170,
        "local_line": 16,
        "bridge_descriptor": (
            "(Lkotlinx/io/Sink;Ljava/lang/String;IIILjava/lang/Object;)V"
        ),
        "source_declaration": (
            "public fun Sink.writeString(string: String, startIndex: Int = 0, "
            "endIndex: Int = string.length) {"
        ),
        "local_declaration": (
            "public fun Sink.writeString(string: String, startIndex: Int = 0, "
            "endIndex: Int = string.length) {"
        ),
        "local_has_opt_in": True,
        "parameter_type": "String",
        "input_name": "string",
    },
    (
        "writeString",
        "(Lkotlinx/io/Sink;Ljava/lang/CharSequence;II)V",
    ): {
        "fqName": "kotlinx.io.writeString",
        "receiver": "kotlinx.io.Sink",
        "parameters": ["kotlin.CharSequence", "kotlin.Int", "kotlin.Int"],
        "defaults": [False, True, True],
        "visibility": "public",
        "source_line": 191,
        "local_line": 22,
        "bridge_descriptor": (
            "(Lkotlinx/io/Sink;Ljava/lang/CharSequence;IIILjava/lang/Object;)V"
        ),
        "source_declaration": (
            "public fun Sink.writeString(chars: CharSequence, startIndex: Int = 0, "
            "endIndex: Int = chars.length) {"
        ),
        "local_declaration": (
            "public fun Sink.writeString(chars: CharSequence, startIndex: Int = 0, "
            "endIndex: Int = chars.length) {"
        ),
        "local_has_opt_in": True,
        "parameter_type": "CharSequence",
        "input_name": "chars",
    },
}

EXPECTED_EXCEPTIONS = (
    "IndexOutOfBoundsException",
    "IllegalArgumentException",
    "IllegalStateException",
    "IOException",
)

ACC_PUBLIC = 0x0001
ACC_STATIC = 0x0008
ACC_BRIDGE = 0x0040
ACC_SYNTHETIC = 0x1000


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


def git_blob_sha(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_class_methods(data: bytes) -> tuple[str, list[dict]]:
    reader = ClassReader(data)
    if reader.u4() != 0xCAFEBABE:
        raise ValueError("Utf8Kt.class has an invalid classfile magic number")
    reader.u2()
    reader.u2()
    constant_pool_count = reader.u2()
    constant_pool = [None] * constant_pool_count

    index = 1
    while index < constant_pool_count:
        tag = reader.u1()
        if tag == 1:
            length = reader.u2()
            modified_utf8 = reader.take(length).replace(b"\xc0\x80", b"\x00")
            constant_pool[index] = (tag, modified_utf8.decode("utf-8", errors="surrogatepass"))
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
            reader.take(4)
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
        raise ValueError("invalid this_class entry in Utf8Kt.class")
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
        skip_attributes(reader.u2())
        methods.append({"name": name, "descriptor": descriptor, "access_flags": flags})
    return class_name, methods


def _source_block(lines: list[str], line_number: int) -> str:
    declaration_index = line_number - 1
    start = declaration_index
    while start > 0 and lines[start - 1].strip() != "/**":
        start -= 1
    return "\n".join(lines[start:declaration_index + 1])


def _has_direct_opt_in(lines: list[str], line_number: int) -> bool:
    index = line_number - 2
    return index >= 0 and lines[index].strip() == "@OptIn(DelicateIoApi::class)"


def verify_pinned_inputs(lock: dict) -> dict:
    if lock.get("commit") != EXPECTED_COMMIT:
        raise ValueError("upstream lock does not point to the fixed kotlinx-io commit")

    upstream_bytes = UPSTREAM_UTF8_PATH.read_bytes()
    source_lock = next(
        (row for row in lock["upstreamFiles"] if row["path"] == "core/common/src/Utf8.kt"),
        None,
    )
    if source_lock is None or len(upstream_bytes) != source_lock["size"]:
        raise ValueError("pinned upstream Utf8.kt is missing or has the wrong size")
    if (git_blob_sha(upstream_bytes) != source_lock["gitBlobSha"]
            or sha256(upstream_bytes) != source_lock["sha256"]):
        raise ValueError("pinned upstream Utf8.kt does not match its lock")

    test_index_bytes = TEST_INDEX_PATH.read_bytes()
    if sha256(test_index_bytes) != lock.get("upstreamTestsIndexSha256"):
        raise ValueError("upstream test index does not match its lock")
    test_index = json.loads(test_index_bytes.decode("utf-8"))
    test_file = next((row for row in test_index["files"] if row["path"] == UPSTREAM_TEST_PATH), None)
    test_lock = next((row for row in lock["upstreamTests"] if row["path"] == UPSTREAM_TEST_PATH), None)
    if test_file is None or test_lock is None or (
        test_file.get("gitBlobSha"), test_file.get("size")
    ) != (test_lock.get("gitBlobSha"), test_lock.get("size")):
        raise ValueError("AbstractSinkTest.kt is absent or mismatched in the pinned test index")
    if not {
        "writeUtf8FromIndex",
        "writeUtf8WithInvalidIndexes",
        "writeCharSequenceFromIndex",
        "writeCharSequenceWithInvalidIndexes",
    }.issubset(set(test_file.get("testNames", []))):
        raise ValueError("the pinned sink tests do not include the required direct assertions")

    declarations_bytes = JVM_DECLARATIONS_PATH.read_bytes()
    if sha256(declarations_bytes) != lock.get("jvmDeclarationsSha256"):
        raise ValueError("JVM metadata declaration catalog does not match its lock")
    declaration_catalog = json.loads(declarations_bytes.decode("utf-8"))
    metadata = {
        (entry["jvmName"], entry["descriptor"]): entry
        for entry in declaration_catalog["declarations"]
        if entry["jvmOwner"] == "kotlinx/io/Utf8Kt"
    }
    upstream_lines = upstream_bytes.decode("utf-8").splitlines()
    local_bytes = LOCAL_UTF8_PATH.read_bytes()
    local_lines = local_bytes.decode("utf-8").splitlines()
    verified = {}

    for key, expected in EXPECTED_DECLARATIONS.items():
        entry = metadata.get(key)
        if entry is None:
            raise ValueError(f"missing Kotlin metadata declaration for {key[0]} {key[1]}")
        for field in ("fqName", "receiver", "parameters", "defaults", "visibility"):
            if entry.get(field) != expected[field]:
                raise ValueError(f"unexpected Kotlin metadata {field} for {key[0]} {key[1]}")

        upstream_declaration = upstream_lines[expected["source_line"] - 1].strip()
        local_declaration = local_lines[expected["local_line"] - 1].strip()
        if upstream_declaration != expected["source_declaration"]:
            raise ValueError(f"pinned upstream source line does not match {expected['fqName']}")
        if local_declaration != expected["local_declaration"]:
            raise ValueError(f"local source line does not match the expected overload: {local_declaration}")

        upstream_block = _source_block(upstream_lines, expected["source_line"])
        if not all(f"@throws {exception}" in upstream_block for exception in EXPECTED_EXCEPTIONS):
            raise ValueError(f"upstream exception contract is incomplete for {expected['parameter_type']}")
        if "@OptIn(DelicateIoApi::class)" not in upstream_block:
            raise ValueError(f"upstream declaration lacks its DelicateIoApi implementation opt-in")
        local_opt_in = _has_direct_opt_in(local_lines, expected["local_line"])
        if local_opt_in != expected["local_has_opt_in"]:
            raise ValueError(f"unexpected local opt-in marker for {expected['parameter_type']}")
        local_block = "\n".join(local_lines[expected["local_line"] - 1:expected["local_line"] + 2])
        if "checkBounds(" not in local_block or "writeToInternalBuffer" not in local_block:
            raise ValueError(f"local {expected['parameter_type']} implementation does not match the pinned contract path")

        default_parameters = [
            index for index, has_default in enumerate(entry["defaults"]) if has_default
        ]
        mask_count = (len(entry["defaults"]) + 31) // 32
        mask_values = [0] * mask_count
        for parameter_index in default_parameters:
            mask_values[parameter_index // 32] |= 1 << (parameter_index % 32)
        if mask_values != [6]:
            raise ValueError(f"unexpected default mask for {expected['parameter_type']}: {mask_values}")

        verified[key] = {
            "fqName": entry["fqName"],
            "receiver": entry["receiver"],
            "parameters": entry["parameters"],
            "defaults": entry["defaults"],
            "visibility": entry["visibility"],
            "source_ref": f"core/common/src/Utf8.kt:{expected['source_line']}",
            "source_opt_in": "DelicateIoApi",
            "local_source_ref": f"Sources/CompilerCore/Stdlib/kotlinx/io/Utf8.kt:{expected['local_line']}",
            "local_source_opt_in": "DelicateIoApi" if local_opt_in else "none",
            "local_opt_in_boundary": (
                "implementation annotation only; the direct consumer has no use-site opt-in"
            ),
            "documented_exceptions": list(EXPECTED_EXCEPTIONS),
            "default_parameter_names": ["startIndex", "endIndex"],
            "default_mask_values_when_both_indices_are_omitted": mask_values,
            "bridge_descriptor": expected["bridge_descriptor"],
        }

    return {
        "declarations": verified,
        "source_sha256": sha256(upstream_bytes),
        "local_source_sha256": sha256(local_bytes),
        "jvm_declarations_sha256": sha256(declarations_bytes),
        "upstream_test_index_sha256": sha256(test_index_bytes),
        "upstream_test_file_git_blob_sha": test_lock["gitBlobSha"],
        "upstream_test_file_size": test_lock["size"],
        "probe_sha256": sha256(Path(__file__).read_bytes()),
    }


def verify_jar(jar_path: Path, artifact: dict, inputs: dict) -> dict:
    jar_bytes = jar_path.read_bytes()
    actual_hash = sha256(jar_bytes)
    if actual_hash != artifact["sha256"]:
        raise ValueError(f"pinned core JVM artifact SHA-256 mismatch: {actual_hash}")
    with zipfile.ZipFile(jar_path) as archive:
        try:
            class_data = archive.read(CLASS_PATH)
        except KeyError as error:
            raise ValueError(f"pinned JVM artifact does not contain {CLASS_PATH}") from error

    class_name, methods = read_class_methods(class_data)
    if class_name != "kotlinx/io/Utf8Kt":
        raise ValueError(f"unexpected facade class name: {class_name}")
    observed = []
    for (name, descriptor), declaration in inputs["declarations"].items():
        implementation_matches = [
            method for method in methods
            if method["name"] == name and method["descriptor"] == descriptor
        ]
        if len(implementation_matches) != 1:
            raise ValueError(f"expected exactly one underlying {name}{descriptor}, found {len(implementation_matches)}")
        bridge_name = name + "$default"
        matches = [
            method for method in methods
            if method["name"] == bridge_name and method["descriptor"] == declaration["bridge_descriptor"]
        ]
        if len(matches) != 1:
            raise ValueError(
                f"expected exactly one {bridge_name}{declaration['bridge_descriptor']}, found {len(matches)}"
            )
        flags = matches[0]["access_flags"]
        actual_flags = {
            "public": bool(flags & ACC_PUBLIC),
            "static": bool(flags & ACC_STATIC),
            "synthetic": bool(flags & ACC_SYNTHETIC),
            "bridge": bool(flags & ACC_BRIDGE),
        }
        expected_flags = {"public": True, "static": True, "synthetic": True, "bridge": False}
        if actual_flags != expected_flags:
            raise ValueError(f"unexpected flags on {bridge_name}{declaration['bridge_descriptor']}: {actual_flags}")

        observed.append({
            "underlying_name": name,
            "underlying_descriptor": descriptor,
            "name": bridge_name,
            "descriptor": declaration["bridge_descriptor"],
            "flags": actual_flags,
            "default_mask_values_when_both_indices_are_omitted": (
                declaration["default_mask_values_when_both_indices_are_omitted"]
            ),
            "mask_parameter": "int before final marker",
            "marker_parameter": "java.lang.Object",
            "underlying_declaration": declaration["fqName"],
            "source_ref": declaration["source_ref"],
        })

    return {
        "result": "PASS",
        "artifact_coordinate": artifact["coordinate"],
        "artifact_sha256": actual_hash,
        "class": CLASS_PATH,
        "class_sha256": sha256(class_data),
        "methods": observed,
        "candidate_boundary": (
            "The JVM classfile check applies only to the pinned reference artifact. KSwiftK emits native code; "
            "the candidate's default-dispatch behavior is verified by separate source and KLIB executions."
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    jar_group = parser.add_mutually_exclusive_group(required=True)
    jar_group.add_argument("--jar", type=Path, help="previously downloaded pinned core JVM jar")
    jar_group.add_argument("--download", action="store_true", help="download the pinned core JVM jar")
    args = parser.parse_args()

    try:
        lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
        inputs = verify_pinned_inputs(lock)
        artifact = next(
            entry for entry in lock["mavenArtifacts"]
            if entry["coordinate"] == "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1"
        )
        if args.jar:
            report = verify_jar(args.jar, artifact, inputs)
        else:
            with tempfile.TemporaryDirectory(prefix="kuu2634-sink-write-string-jvm-") as temporary:
                jar_path = Path(temporary) / artifact["url"].rsplit("/", 1)[-1]
                with urllib.request.urlopen(artifact["url"], timeout=60) as response:
                    jar_path.write_bytes(response.read())
                report = verify_jar(jar_path, artifact, inputs)
        serializable_inputs = {
            **inputs,
            "declarations": [
                {"jvm_name": name, "descriptor": descriptor, **declaration}
                for (name, descriptor), declaration in sorted(inputs["declarations"].items())
            ],
        }
        print(json.dumps({"reference_version": lock["tag"], "reference_commit": lock["commit"],
                          "inputs": serializable_inputs, "probe": report}, ensure_ascii=False,
                         indent=2, sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError, StopIteration, zipfile.BadZipFile,
            json.JSONDecodeError) as error:
        print(f"Sink.writeString JVM ABI probe: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
