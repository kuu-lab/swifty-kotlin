#!/usr/bin/env python3
"""Check the pinned JVM classfile shape for kotlinx-io Hex default bridges."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
LOCK_PATH = HERE / "upstream-lock.json"
JVM_DECLARATIONS_PATH = HERE / "jvm-declarations.json"
UPSTREAM_HEX_PATH = HERE / "upstream/kotlinx-io-0.9.1/bytestring/common/src/Hex.kt"
EXPECTED_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"
CLASS_PATH = "kotlinx/io/bytestring/HexKt.class"

EXPECTED_DECLARATIONS = {
    (
        "toHexString",
        "(Lkotlinx/io/bytestring/ByteString;Lkotlin/text/HexFormat;)Ljava/lang/String;",
    ): {
        "fqName": "kotlinx.io.bytestring.toHexString",
        "receiver": "kotlinx.io.bytestring.ByteString",
        "parameters": ["kotlin.text.HexFormat"],
        "defaults": [True],
        "visibility": "public",
        "source_line": 17,
        "bridge_descriptor": "(Lkotlinx/io/bytestring/ByteString;Lkotlin/text/HexFormat;ILjava/lang/Object;)Ljava/lang/String;",
    },
    (
        "toHexString",
        "(Lkotlinx/io/bytestring/ByteString;IILkotlin/text/HexFormat;)Ljava/lang/String;",
    ): {
        "fqName": "kotlinx.io.bytestring.toHexString",
        "receiver": "kotlinx.io.bytestring.ByteString",
        "parameters": ["kotlin.Int", "kotlin.Int", "kotlin.text.HexFormat"],
        "defaults": [True, True, True],
        "visibility": "public",
        "source_line": 34,
        "bridge_descriptor": "(Lkotlinx/io/bytestring/ByteString;IILkotlin/text/HexFormat;ILjava/lang/Object;)Ljava/lang/String;",
    },
    (
        "hexToByteString",
        "(Ljava/lang/String;Lkotlin/text/HexFormat;)Lkotlinx/io/bytestring/ByteString;",
    ): {
        "fqName": "kotlinx.io.bytestring.hexToByteString",
        "receiver": "kotlin.String",
        "parameters": ["kotlin.text.HexFormat"],
        "defaults": [True],
        "visibility": "public",
        "source_line": 53,
        "bridge_descriptor": "(Ljava/lang/String;Lkotlin/text/HexFormat;ILjava/lang/Object;)Lkotlinx/io/bytestring/ByteString;",
    },
}

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
        raise ValueError("HexKt.class has an invalid classfile magic number")
    reader.u2()  # minor version
    reader.u2()  # major version
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

    reader.u2()  # class access flags
    this_class = constant_pool[reader.u2()]
    if not this_class or this_class[0] != 7:
        raise ValueError("invalid this_class entry in HexKt.class")
    class_name = utf8(this_class[1])
    reader.u2()  # super_class
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


def verify_pinned_inputs(lock: dict) -> dict:
    if lock.get("commit") != EXPECTED_COMMIT:
        raise ValueError("upstream lock does not point to the fixed kotlinx-io commit")
    source = UPSTREAM_HEX_PATH.read_bytes()
    source_lock = next(
        (row for row in lock["upstreamFiles"] if row["path"] == "bytestring/common/src/Hex.kt"),
        None,
    )
    if source_lock is None or len(source) != source_lock["size"]:
        raise ValueError("pinned upstream Hex.kt is missing or has the wrong size")
    if git_blob_sha(source) != source_lock["gitBlobSha"] or sha256(source) != source_lock["sha256"]:
        raise ValueError("pinned upstream Hex.kt does not match its lock")

    declarations_bytes = JVM_DECLARATIONS_PATH.read_bytes()
    if sha256(declarations_bytes) != lock.get("jvmDeclarationsSha256"):
        raise ValueError("JVM metadata declaration catalog does not match its lock")
    declaration_catalog = json.loads(declarations_bytes.decode("utf-8"))
    metadata = {
        (entry["jvmName"], entry["descriptor"]): entry
        for entry in declaration_catalog["declarations"]
        if entry["jvmOwner"] == "kotlinx/io/bytestring/HexKt"
    }
    source_lines = source.decode("utf-8").splitlines()
    verified = {}
    for key, expected in EXPECTED_DECLARATIONS.items():
        entry = metadata.get(key)
        if entry is None:
            raise ValueError(f"missing Kotlin metadata declaration for {key[0]} {key[1]}")
        for field in ("fqName", "receiver", "parameters", "defaults", "visibility"):
            if entry.get(field) != expected[field]:
                raise ValueError(f"unexpected Kotlin metadata {field} for {key[0]} {key[1]}")
        source_line = source_lines[expected["source_line"] - 1]
        if "fun " not in source_line or entry["fqName"].rsplit(".", 1)[-1] not in source_line:
            raise ValueError(f"source declaration line does not match {entry['fqName']}")
        verified[key] = {
            "fqName": entry["fqName"],
            "receiver": entry["receiver"],
            "parameters": entry["parameters"],
            "defaults": entry["defaults"],
            "visibility": entry["visibility"],
            "source_ref": f"bytestring/common/src/Hex.kt:{expected['source_line']}",
            "bridge_descriptor": expected["bridge_descriptor"],
        }
    return verified


def verify_jar(jar_path: Path, artifact: dict, declarations: dict) -> dict:
    jar_bytes = jar_path.read_bytes()
    actual_hash = sha256(jar_bytes)
    if actual_hash != artifact["sha256"]:
        raise ValueError(f"pinned bytestring JVM artifact SHA-256 mismatch: {actual_hash}")
    with zipfile.ZipFile(jar_path) as archive:
        try:
            class_data = archive.read(CLASS_PATH)
        except KeyError as error:
            raise ValueError(f"pinned JVM artifact does not contain {CLASS_PATH}") from error

    class_name, methods = read_class_methods(class_data)
    if class_name != "kotlinx/io/bytestring/HexKt":
        raise ValueError(f"unexpected facade class name: {class_name}")
    observed = []
    for (name, _), declaration in declarations.items():
        expected_name = name + "$default"
        matches = [
            method for method in methods
            if method["name"] == expected_name
            and method["descriptor"] == declaration["bridge_descriptor"]
        ]
        if len(matches) != 1:
            raise ValueError(
                f"expected exactly one {expected_name}{declaration['bridge_descriptor']}, found {len(matches)}"
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
            raise ValueError(
                f"unexpected flags on {expected_name}{declaration['bridge_descriptor']}: {actual_flags}"
            )
        defaults = declaration["defaults"]
        mask_count = (len(defaults) + 31) // 32
        mask_values = [0] * mask_count
        for parameter_index, has_default in enumerate(defaults):
            if has_default:
                mask_values[parameter_index // 32] |= 1 << (parameter_index % 32)
        observed.append({
            "name": expected_name,
            "descriptor": declaration["bridge_descriptor"],
            "flags": actual_flags,
            "default_mask_values_when_all_parameters_are_omitted": mask_values,
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
            "Reference classfile shape only. KSwiftK emits native code; native default-dispatch "
            "execution is separate evidence and does not establish candidate JVM classfile ABI."
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    jar_group = parser.add_mutually_exclusive_group(required=True)
    jar_group.add_argument("--jar", type=Path, help="previously downloaded pinned bytestring JVM jar")
    jar_group.add_argument("--download", action="store_true", help="download the pinned bytestring JVM jar")
    args = parser.parse_args()

    try:
        lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
        declarations = verify_pinned_inputs(lock)
        artifact = next(
            entry for entry in lock["mavenArtifacts"]
            if entry["coordinate"] == "org.jetbrains.kotlinx:kotlinx-io-bytestring-jvm:0.9.1"
        )
        if args.jar:
            report = verify_jar(args.jar, artifact, declarations)
        else:
            with tempfile.TemporaryDirectory(prefix="kuu2621-hex-jvm-") as temporary:
                jar_path = Path(temporary) / artifact["url"].rsplit("/", 1)[-1]
                with urllib.request.urlopen(artifact["url"], timeout=60) as response:
                    jar_path.write_bytes(response.read())
                report = verify_jar(jar_path, artifact, declarations)
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError, StopIteration, zipfile.BadZipFile, json.JSONDecodeError) as error:
        print(f"ByteString Hex JVM ABI probe: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
