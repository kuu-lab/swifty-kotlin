#!/usr/bin/env python3
"""Verify pinned JVM default bridges for the three ByteString.indexOf overloads."""

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
REPO = HERE.parents[1]
LOCK_PATH = HERE / "upstream-lock.json"
JVM_DECLARATIONS_PATH = HERE / "jvm-declarations.json"
SOURCE_DECLARATIONS_PATH = HERE / "source-declarations.json"
TEST_INDEX_PATH = HERE / "upstream-tests-index.json"
UPSTREAM = HERE / "upstream/kotlinx-io-0.9.1"
API_PATH = UPSTREAM / "bytestring/api/kotlinx-io-bytestring.api"
UPSTREAM_SOURCE_PATH = UPSTREAM / "bytestring/common/src/ByteString.kt"
LOCAL_SOURCE_PATH = REPO / "Sources/CompilerCore/Stdlib/kotlinx/io/bytestring/ByteString.kt"
CLASS_PATH = "kotlinx/io/bytestring/ByteStringKt.class"
EXPECTED_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"
EXPECTED_CANDIDATE_SHA = "fd01a5e98145e8295e5b299b0a7190cc8d44e3a7"
UPSTREAM_API_RELATIVE_PATH = "bytestring/api/kotlinx-io-bytestring.api"
UPSTREAM_SOURCE_RELATIVE_PATH = "bytestring/common/src/ByteString.kt"
LOCAL_SOURCE_RELATIVE_PATH = "Sources/CompilerCore/Stdlib/kotlinx/io/bytestring/ByteString.kt"

EXPECTED_METHODS = [
    {
        "row_id": "jvm-d49996f4a43448e9",
        "needle_type": "kotlin.Byte",
        "source_parameter": "byte",
        "upstream_source_line": 305,
        "candidate_source_line": 142,
        "api_line": 90,
        "case_name": "indexOfByte",
        "candidate_execution_id": "kotlinx.io.bytestring.ByteStringTest.indexOfByte",
        "upstream_execution_id": (
            "[engine:junit-jupiter]/[class:kotlinx.io.bytestring.ByteStringTest]/"
            "[method:indexOfByte()]"
        ),
        "base_descriptor": "(Lkotlinx/io/bytestring/ByteString;BI)I",
        "bridge_descriptor": "(Lkotlinx/io/bytestring/ByteString;BIILjava/lang/Object;)I",
    },
    {
        "row_id": "jvm-f0c73d7133f5a588",
        "needle_type": "kotlinx.io.bytestring.ByteString",
        "source_parameter": "byteString",
        "upstream_source_line": 327,
        "candidate_source_line": 151,
        "api_line": 91,
        "case_name": "indexOfByteString",
        "candidate_execution_id": "kotlinx.io.bytestring.ByteStringTest.indexOfByteString",
        "upstream_execution_id": (
            "[engine:junit-jupiter]/[class:kotlinx.io.bytestring.ByteStringTest]/"
            "[method:indexOfByteString()]"
        ),
        "base_descriptor": (
            "(Lkotlinx/io/bytestring/ByteString;"
            "Lkotlinx/io/bytestring/ByteString;I)I"
        ),
        "bridge_descriptor": (
            "(Lkotlinx/io/bytestring/ByteString;"
            "Lkotlinx/io/bytestring/ByteString;IILjava/lang/Object;)I"
        ),
    },
    {
        "row_id": "jvm-0a5972de7cfbf1ce",
        "needle_type": "kotlin.ByteArray",
        "source_parameter": "byteArray",
        "upstream_source_line": 351,
        "candidate_source_line": 154,
        "api_line": 92,
        "case_name": "indexOfByteArray",
        "candidate_execution_id": "kotlinx.io.bytestring.ByteStringTest.indexOfByteArray",
        "upstream_execution_id": (
            "[engine:junit-jupiter]/[class:kotlinx.io.bytestring.ByteStringTest]/"
            "[method:indexOfByteArray()]"
        ),
        "base_descriptor": "(Lkotlinx/io/bytestring/ByteString;[BI)I",
        "bridge_descriptor": "(Lkotlinx/io/bytestring/ByteString;[BIILjava/lang/Object;)I",
    },
]

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


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(f"blob {len(data)}\0".encode("ascii") + data).hexdigest()


def read_class_methods(data: bytes) -> tuple[str, list[dict]]:
    reader = ClassReader(data)
    if reader.u4() != 0xCAFEBABE:
        raise ValueError("ByteStringKt.class has an invalid classfile magic number")
    reader.u2()
    reader.u2()
    constant_pool_count = reader.u2()
    constant_pool = [None] * constant_pool_count
    index = 1
    while index < constant_pool_count:
        tag = reader.u1()
        if tag == 1:
            length = reader.u2()
            value = reader.take(length).replace(b"\xc0\x80", b"\x00")
            constant_pool[index] = (tag, value.decode("utf-8", errors="surrogatepass"))
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
        raise ValueError("invalid this_class entry in ByteStringKt.class")
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


def require_locked_file(path: Path, lock: dict, relative: str) -> bytes:
    data = path.read_bytes()
    entry = next((item for item in lock["upstreamFiles"] if item["path"] == relative), None)
    if entry is None or len(data) != entry["size"]:
        raise ValueError(f"pinned upstream input has the wrong size: {relative}")
    if git_blob_sha(data) != entry["gitBlobSha"] or sha256(data) != entry["sha256"]:
        raise ValueError(f"pinned upstream input hash mismatch: {relative}")
    return data


def declaration(catalog: dict, origin: str, path: str, line: int) -> dict:
    matches = [
        item
        for item in catalog["declarations"]
        if item["origin"] == origin and item["path"] == path and item["line"] == line
    ]
    if len(matches) != 1:
        raise ValueError(f"expected one {origin} declaration at {path}:{line}")
    return matches[0]


def source_contract(item: dict, spec: dict) -> dict:
    expected_parameters = [
        (spec["source_parameter"], spec["needle_type"].rsplit(".", 1)[-1], None),
        ("startIndex", "Int", "0"),
    ]
    actual_parameters = [
        (parameter["name"], parameter["type"], parameter["default"])
        for parameter in item["parameters"]
    ]
    if (
        item["kind"] != "function"
        or item["fqName"] != "kotlinx.io.bytestring.indexOf"
        or item["receiver"] != "ByteString"
        or item["returnType"] != "Int"
        or item["visibility"] != "public"
        or not item["hasBody"]
        or item["annotations"]
        or actual_parameters != expected_parameters
    ):
        raise ValueError(f"unexpected indexOf source contract at {item['path']}:{item['line']}")
    return {
        "visibility": item["visibility"],
        "receiver": "kotlinx.io.bytestring.ByteString",
        "parameters": [
            {"name": name, "type": type_name, "default": default}
            for name, type_name, default in actual_parameters
        ],
        "return_type": "kotlin.Int",
        "annotations": [],
        "deprecation": "none",
        "exception_contract": "not-declared-in-source",
    }


def verify_inputs(lock: dict, candidate_sha: str) -> tuple[dict, dict, dict]:
    if lock.get("commit") != EXPECTED_COMMIT or lock.get("tag") != "0.9.1":
        raise ValueError("upstream lock does not point to kotlinx-io 0.9.1")
    if lock.get("kotlinCompilerVersion") != "2.3.10":
        raise ValueError("upstream lock does not use Kotlin 2.3.10")
    if candidate_sha != EXPECTED_CANDIDATE_SHA:
        raise ValueError("candidate SHA must match the fixed KUU-2618 baseline")

    api_data = require_locked_file(API_PATH, lock, UPSTREAM_API_RELATIVE_PATH)
    source_data = require_locked_file(UPSTREAM_SOURCE_PATH, lock, UPSTREAM_SOURCE_RELATIVE_PATH)
    source_catalog_data = SOURCE_DECLARATIONS_PATH.read_bytes()
    jvm_catalog_data = JVM_DECLARATIONS_PATH.read_bytes()
    test_index_data = TEST_INDEX_PATH.read_bytes()
    if sha256(source_catalog_data) != lock.get("sourceDeclarationsSha256"):
        raise ValueError("source declaration catalog does not match its lock")
    if sha256(jvm_catalog_data) != lock.get("jvmDeclarationsSha256"):
        raise ValueError("JVM metadata catalog does not match its lock")
    if sha256(test_index_data) != lock.get("upstreamTestsIndexSha256"):
        raise ValueError("upstream test index does not match its lock")
    source_catalog = json.loads(source_catalog_data.decode("utf-8"))
    jvm_catalog = json.loads(jvm_catalog_data.decode("utf-8"))
    test_index = json.loads(test_index_data.decode("utf-8"))
    if test_index.get("commit") != EXPECTED_COMMIT:
        raise ValueError("upstream test index uses a different commit")
    for origin, relative, path in (
        ("upstream", UPSTREAM_SOURCE_RELATIVE_PATH, UPSTREAM_SOURCE_PATH),
        ("local", LOCAL_SOURCE_RELATIVE_PATH, LOCAL_SOURCE_PATH),
    ):
        file_entry = next(
            (
                item
                for item in source_catalog["files"]
                if item["origin"] == origin and item["path"] == relative
            ),
            None,
        )
        if file_entry is None or sha256(path.read_bytes()) != file_entry["sha256"]:
            raise ValueError(f"source catalog file hash mismatch: {relative}")
    test_file = next(
        (item for item in test_index["files"] if item["path"] == "bytestring/common/test/ByteStringTest.kt"),
        None,
    )
    if test_file is None:
        raise ValueError("pinned ByteStringTest.kt is absent from the test index")
    source_lines = source_data.decode("utf-8").splitlines()
    api_lines = api_data.decode("utf-8").splitlines()
    metadata = {
        (item["jvmName"], item["descriptor"]): item
        for item in jvm_catalog["declarations"]
        if item["jvmOwner"] == "kotlinx/io/bytestring/ByteStringKt"
    }
    for spec in EXPECTED_METHODS:
        if spec["case_name"] not in test_file.get("testNames", []):
            raise ValueError(f"pinned upstream test is missing: {spec['case_name']}")
        if not source_lines[spec["upstream_source_line"] - 1].lstrip().startswith("public fun ByteString.indexOf("):
            raise ValueError(f"source line does not identify the expected indexOf overload: {spec['row_id']}")
        api_text = f"public static synthetic fun indexOf$default {spec['bridge_descriptor']}"
        if api_lines[spec["api_line"] - 1].strip() != api_text:
            raise ValueError(f"API dump line does not match the expected bridge: {spec['row_id']}")
        declaration(source_catalog, "upstream", UPSTREAM_SOURCE_RELATIVE_PATH, spec["upstream_source_line"])
        local_declaration = declaration(
            source_catalog, "local", LOCAL_SOURCE_RELATIVE_PATH, spec["candidate_source_line"]
        )
        source_contract(
            declaration(source_catalog, "upstream", UPSTREAM_SOURCE_RELATIVE_PATH, spec["upstream_source_line"]),
            spec,
        )
        source_contract(local_declaration, spec)
        underlying = metadata.get(("indexOf", spec["base_descriptor"]))
        if underlying is None:
            raise ValueError(f"missing Kotlin metadata method for {spec['row_id']}")
        expected_types = [spec["needle_type"], "kotlin.Int"]
        if (
            underlying.get("fqName") != "kotlinx.io.bytestring.indexOf"
            or underlying.get("receiver") != "kotlinx.io.bytestring.ByteString"
            or underlying.get("parameters") != expected_types
            or underlying.get("defaults") != [False, True]
            or underlying.get("visibility") != "public"
        ):
            raise ValueError(f"Kotlin metadata does not map the underlying overload: {spec['row_id']}")

    return source_catalog, jvm_catalog, {
        "api": api_data,
        "upstream_source": source_data,
        "source_catalog": source_catalog_data,
        "jvm_catalog": jvm_catalog_data,
        "test_index": test_index_data,
    }


def verify_jar(jar_path: Path, lock: dict, candidate_sha: str, source_catalog: dict) -> dict:
    artifact = next(
        item
        for item in lock["mavenArtifacts"]
        if item["coordinate"] == "org.jetbrains.kotlinx:kotlinx-io-bytestring-jvm:0.9.1"
    )
    jar_data = jar_path.read_bytes()
    jar_sha = sha256(jar_data)
    if jar_sha != artifact["sha256"]:
        raise ValueError(f"pinned bytestring JVM artifact SHA-256 mismatch: {jar_sha}")
    with zipfile.ZipFile(jar_path) as archive:
        try:
            class_data = archive.read(CLASS_PATH)
        except KeyError as error:
            raise ValueError(f"pinned JVM artifact does not contain {CLASS_PATH}") from error

    class_name, methods = read_class_methods(class_data)
    if class_name != "kotlinx/io/bytestring/ByteStringKt":
        raise ValueError(f"unexpected facade class name: {class_name}")
    report_methods = []
    expected_bridge_flags = {"public": True, "static": True, "synthetic": True, "bridge": False}
    for spec in EXPECTED_METHODS:
        base = [
            method
            for method in methods
            if method["name"] == "indexOf" and method["descriptor"] == spec["base_descriptor"]
        ]
        bridge = [
            method
            for method in methods
            if method["name"] == "indexOf$default"
            and method["descriptor"] == spec["bridge_descriptor"]
        ]
        if len(base) != 1 or len(bridge) != 1:
            raise ValueError(f"expected one source method and one default bridge for {spec['row_id']}")
        base_flags = base[0]["access_flags"]
        if not (base_flags & ACC_PUBLIC and base_flags & ACC_STATIC):
            raise ValueError(f"underlying JVM method is not public static: {spec['row_id']}")
        if base_flags & (ACC_SYNTHETIC | ACC_BRIDGE):
            raise ValueError(f"underlying JVM method has unexpected generated flags: {spec['row_id']}")
        flags = bridge[0]["access_flags"]
        observed_flags = {
            "public": bool(flags & ACC_PUBLIC),
            "static": bool(flags & ACC_STATIC),
            "synthetic": bool(flags & ACC_SYNTHETIC),
            "bridge": bool(flags & ACC_BRIDGE),
        }
        if observed_flags != expected_bridge_flags:
            raise ValueError(f"unexpected flags on indexOf$default for {spec['row_id']}: {observed_flags}")
        upstream = declaration(
            source_catalog, "upstream", UPSTREAM_SOURCE_RELATIVE_PATH, spec["upstream_source_line"]
        )
        local = declaration(
            source_catalog, "local", LOCAL_SOURCE_RELATIVE_PATH, spec["candidate_source_line"]
        )
        report_methods.append({
            "row_id": spec["row_id"],
            "case_id": f"bytestring/common/test/ByteStringTest.kt#{spec['case_name']}",
            "candidate_execution_id": spec["candidate_execution_id"],
            "upstream_execution_id": spec["upstream_execution_id"],
            "result": "PASS",
            "underlying_descriptor": spec["base_descriptor"],
            "bridge_descriptor": spec["bridge_descriptor"],
            "api_reference": f"{UPSTREAM_API_RELATIVE_PATH}:{spec['api_line']}",
            "underlying_flags": {"public": True, "static": True, "synthetic": False, "bridge": False},
            "flags": observed_flags,
            "mask_values_when_defaults_are_omitted": [2],
            "marker_parameter": "java.lang.Object",
            "upstream_source": f"{UPSTREAM_SOURCE_RELATIVE_PATH}:{spec['upstream_source_line']}",
            "candidate_source": f"{LOCAL_SOURCE_RELATIVE_PATH}:{spec['candidate_source_line']}",
            "source_contract": source_contract(upstream, spec),
        })

    probe_data = Path(__file__).read_bytes()
    return {
        "schema_version": 1,
        "result": "PASS",
        "candidate_sha": candidate_sha,
        "reference_version": lock["tag"],
        "reference_commit": lock["commit"],
        "artifact_coordinate": artifact["coordinate"],
        "artifact_sha256": jar_sha,
        "probe_sha256": sha256(probe_data),
        "probe_inputs_sha256": sha256(json.dumps({
            "probe": sha256(probe_data),
            "api": sha256(API_PATH.read_bytes()),
            "upstream_source": sha256(UPSTREAM_SOURCE_PATH.read_bytes()),
            "candidate_source": sha256(LOCAL_SOURCE_PATH.read_bytes()),
            "source_declarations": sha256(SOURCE_DECLARATIONS_PATH.read_bytes()),
            "jvm_declarations": sha256(JVM_DECLARATIONS_PATH.read_bytes()),
            "upstream_lock": sha256(LOCK_PATH.read_bytes()),
            "upstream_tests_index": sha256(TEST_INDEX_PATH.read_bytes()),
            "reference_artifact": jar_sha,
        }, sort_keys=True, separators=(",", ":")).encode("utf-8")),
        "class": CLASS_PATH,
        "class_sha256": sha256(class_data),
        "execution_count": len(report_methods),
        "passed_count": sum(method["result"] == "PASS" for method in report_methods),
        "methods": report_methods,
        "candidate_boundary": (
            "Reference classfile shape only. KSwiftK emits native code; candidate native "
            "default-dispatch execution is separate evidence and does not establish candidate "
            "JVM classfile ABI."
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    jar_group = parser.add_mutually_exclusive_group(required=True)
    jar_group.add_argument("--jar", type=Path, help="previously downloaded pinned bytestring JVM jar")
    jar_group.add_argument("--download", action="store_true", help="download the pinned bytestring JVM jar")
    parser.add_argument("--candidate-sha", required=True)
    parser.add_argument("--output", type=Path, help="write the deterministic report to this path")
    args = parser.parse_args()

    try:
        lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
        source_catalog, _, _ = verify_inputs(lock, args.candidate_sha)
        if args.jar:
            report = verify_jar(args.jar, lock, args.candidate_sha, source_catalog)
        else:
            artifact = next(
                item for item in lock["mavenArtifacts"]
                if item["coordinate"] == "org.jetbrains.kotlinx:kotlinx-io-bytestring-jvm:0.9.1"
            )
            with tempfile.TemporaryDirectory(prefix="kuu2618-indexof-jvm-") as temporary:
                jar_path = Path(temporary) / artifact["url"].rsplit("/", 1)[-1]
                with urllib.request.urlopen(artifact["url"], timeout=60) as response:
                    jar_path.write_bytes(response.read())
                report = verify_jar(jar_path, lock, args.candidate_sha, source_catalog)
        rendered = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(rendered, encoding="utf-8")
        print(rendered, end="")
        return 0
    except (OSError, ValueError, KeyError, StopIteration, zipfile.BadZipFile, json.JSONDecodeError) as error:
        print(f"ByteString.indexOf JVM ABI probe: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
