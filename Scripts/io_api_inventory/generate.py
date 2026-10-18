#!/usr/bin/env python3
"""Build a deterministic kotlinx-io 0.9.1 API and test cross-reference ledger."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
import tempfile
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))
from source_index import SourceIndex, api_key

UPSTREAM = HERE / "upstream" / "kotlinx-io-0.9.1"
LOCK_PATH = HERE / "upstream-lock.json"
TEST_INDEX_PATH = HERE / "upstream-tests-index.json"
LEDGER_PATH = HERE / "api-inventory.tsv"
SCOPE_PATH = HERE / "platform-scope.tsv"
SUMMARY_PATH = HERE / "inventory-summary.md"
VALIDATION_EVIDENCE_PATH = HERE / "api-validation-evidence.json"
UPSTREAM_RUNNER = REPO / "Scripts/kotlinx_io_upstream"
UPSTREAM_RUNNER_LOCK_PATH = UPSTREAM_RUNNER / "reference-lock.json"
REFERENCE_EXECUTIONS_PATH = UPSTREAM_RUNNER / "jvm-executions.expected.json"
CANDIDATE_EXECUTIONS_PATH = UPSTREAM_RUNNER / "native-executions.expected.json"
EXPECTED_TAG_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"
NO_DIRECT_UPSTREAM_ASSERTION_SOURCE_REFS = {
    "core/common/src/files/Paths.kt:115",
    "core/common/src/files/Paths.kt:133",
}
NO_DIRECT_UPSTREAM_ASSERTION = "none (no direct upstream assertion mapped)"
VALIDATION_EVIDENCE_SCHEMA_VERSION = 2
VALIDATION_LANES_BY_OBLIGATION = {
    "jvm-descriptor": ("jvm-descriptor",),
    "native-source": (
        "source-O0",
        "source-O2",
        "stdlib-library-O0",
        "stdlib-library-O2",
    ),
    "native-bridge": ("producer-consumer-O0", "producer-consumer-O2"),
}
LOCAL_NATIVE_PROBE_LANES = (
    "source-O0",
    "source-O2",
    "stdlib-library-O0",
    "stdlib-library-O2",
    "producer-consumer-O0",
    "producer-consumer-O2",
)
LOCAL_PROBE_EVIDENCE_CASES = {
    "local:Scripts/io_api_inventory/probes/segment_data_as_byte_array.kt#internal-view": {
        "path": "Scripts/io_api_inventory/probes/segment_data_as_byte_array.kt",
        "row_ids": {"internal-7f39deeafb60d29d", "klib-952eb71e7667983b"},
        "lanes": LOCAL_NATIVE_PROBE_LANES,
        "methods": {"reference": "jvm-probe", "candidate": "native-matrix"},
    },
    "local:Scripts/io_api_inventory/probes/segment_data_as_byte_array_negative.kt#internal-visibility": {
        "path": "Scripts/io_api_inventory/probes/segment_data_as_byte_array_negative.kt",
        "row_ids": {"internal-7f39deeafb60d29d", "klib-952eb71e7667983b"},
        "lanes": LOCAL_NATIVE_PROBE_LANES,
        "methods": {"reference": "jvm-visibility-probe", "candidate": "native-visibility-probe"},
    },
    "local:Scripts/io_api_inventory/probes/segment_data_as_byte_array_jvm_abi.kt#jvm-descriptor": {
        "path": "Scripts/io_api_inventory/probes/segment_data_as_byte_array_jvm_abi.kt",
        "row_ids": {"jvm-f7053c9293f03a10"},
        "lanes": ("jvm-descriptor",),
        "methods": {"reference": "jvm-abi-reflection", "candidate": "source-metadata"},
    },
}

LEDGER_COLUMNS = [
    "row_id",
    "module",
    "representation",
    "platform_scope",
    "api_kind",
    "source_api",
    "owner_fqn",
    "name",
    "signature",
    "default_parameter_count",
    "annotations",
    "platform_metadata",
    "deprecation",
    "exception_contract",
    "upstream_source_refs",
    "jvm_abi_refs",
    "upstream_test_refs",
    "local_candidate_refs",
    "local_implementation_refs",
    "local_contract_differences",
    "local_test_refs",
    "status",
    "owner_issue",
    "scope_decision",
    "notes",
]

SCOPE_COLUMNS = [
    "platform_group",
    "source_roots",
    "source_file_count",
    "public_declaration_count",
    "api_dump_target_marker_count",
    "decision",
    "reason",
]

PLATFORM_ROOTS = {
    "Android Native": ["core/androidNative/src"],
    "Apple source actuals": ["core/apple/src", "bytestring/apple/src"],
    "JavaScript and Node": ["core/js/src", "core/nodeFilesystemShared/src"],
    "Linux and Unix": ["core/linux/src", "core/unix/src"],
    "Windows Native": ["core/mingw/src", "core/nativeNonApple/src"],
    "Wasm": ["core/wasm/src", "core/wasmJs/src", "core/wasmWasi/src"],
    "Native shared implementation": [
        "core/native/src",
        "core/nativeNonAndroid/src",
    ],
}

TEST_HINTS = {
    "ByteString.kt": ["bytestring/common/test/ByteStringTest.kt"],
    "ByteStringBuilder.kt": ["bytestring/common/test/ByteStringBuilderTest.kt"],
    "Base64.kt": ["bytestring/common/test/ByteStringBase64Test.kt"],
    "Hex.kt": ["bytestring/common/test/ByteStringHexTest.kt"],
    "UnsafeByteStringOperations.kt": [
        "bytestring/common/test/unsafe/UnsafeByteStringOperationsTest.kt"
    ],
    "ByteStringApple.kt": ["bytestring/apple/test/ByteStringAppleTest.kt"],
    "ByteStringJvmExt.kt": [
        "bytestring/jvm/test/ByteStringByteBufferExtensionsTest.kt",
        "bytestring/jvm/test/ByteStringJvmTest.kt",
    ],
    "Buffer.kt": [
        "core/common/test/CommonBufferTest.kt",
        "core/jvm/test/BufferTest.kt",
    ],
    "Buffers.kt": [
        "core/common/test/CommonBufferTest.kt",
        "core/jvm/test/BufferTest.kt",
    ],
    "ByteStrings.kt": [
        "core/common/test/AbstractSourceTest.kt",
        "core/common/test/AbstractSinkTest.kt",
        "core/common/test/CommonBufferTest.kt",
    ],
    "RawSource.kt": [
        "core/common/test/AbstractSourceTest.kt",
        "core/common/test/CommonRealSourceTest.kt",
    ],
    "RealSource.kt": [
        "core/common/test/AbstractSourceTest.kt",
        "core/common/test/CommonRealSourceTest.kt",
    ],
    "PeekSource.kt": [
        "core/common/test/AbstractSourceTest.kt",
        "core/common/test/CommonRealSourceTest.kt",
    ],
    "Source.kt": [
        "core/common/test/AbstractSourceTest.kt",
        "core/common/test/CommonRealSourceTest.kt",
    ],
    "Sources.kt": [
        "core/common/test/AbstractSourceTest.kt",
        "core/common/test/CommonRealSourceTest.kt",
    ],
    "RawSink.kt": [
        "core/common/test/AbstractSinkTest.kt",
        "core/common/test/CommonRealSinkTest.kt",
    ],
    "RealSink.kt": [
        "core/common/test/AbstractSinkTest.kt",
        "core/common/test/CommonRealSinkTest.kt",
    ],
    "Sink.kt": [
        "core/common/test/AbstractSinkTest.kt",
        "core/common/test/CommonRealSinkTest.kt",
    ],
    "Sinks.kt": [
        "core/common/test/AbstractSinkTest.kt",
        "core/common/test/CommonRealSinkTest.kt",
    ],
    "Utf8.kt": ["core/common/test/Utf8Test.kt"],
    "FileSystem.kt": ["core/common/test/files/SmokeFileTest.kt"],
    "Paths.kt": [
        "core/common/test/files/SmokeFileTest.kt",
        "core/common/test/files/UtilsTest.kt",
    ],
    "UnsafeBufferOperations.kt": [
        "core/common/test/unsafe/UnsafeBufferOperationsForEachTest.kt",
        "core/common/test/unsafe/UnsafeBufferOperationsIterationTest.kt",
        "core/common/test/unsafe/UnsafeBufferOperationsMoveTest.kt",
        "core/common/test/unsafe/UnsafeBufferOperationsReadTest.kt",
        "core/common/test/unsafe/UnsafeBufferOperationsWriteTest.kt",
    ],
    "UnsafeBufferOperationsJvm.kt": [
        "core/jvm/test/unsafe/UnsafeBufferOperationsJvmReadBulkTest.kt",
        "core/jvm/test/unsafe/UnsafeBufferOperationsJvmReadFromHeadTest.kt",
        "core/jvm/test/unsafe/UnsafeBufferOperationsJvmWriteToTailTest.kt",
    ],
    "BuffersJvm.kt": ["core/jvm/test/NioTest.kt", "core/jvm/test/BufferTest.kt"],
    "SinksJvm.kt": [
        "core/jvm/test/NioTest.kt",
        "core/jvm/test/AbstractSinkTestJVM.kt",
    ],
    "SourcesJvm.kt": [
        "core/jvm/test/NioTest.kt",
        "core/jvm/test/AbstractSourceTestJVM.kt",
    ],
    "JvmCore.kt": ["core/jvm/test/JvmPlatformTest.kt"],
    "PathsJvm.kt": ["core/common/test/files/SmokeFileTest.kt"],
    "FileSystemJvm.kt": ["core/common/test/files/SmokeFileTest.kt"],
    "AppleCore.kt": [
        "core/apple/test/NSInputStreamSourceTest.kt",
        "core/apple/test/NSOutputStreamSinkTest.kt",
    ],
    "SourcesApple.kt": [
        "core/apple/test/NSInputStreamSourceTest.kt",
        "core/apple/test/SourceNSInputStreamTest.kt",
    ],
    "SinksApple.kt": [
        "core/apple/test/NSOutputStreamSinkTest.kt",
        "core/apple/test/SinkNSOutputStreamTest.kt",
    ],
    "FileSystemApple.kt": ["core/common/test/files/SmokeFileTest.kt"],
}

LOCAL_IO_TEST_PREFIXES = (
    "Scripts/io_api_inventory/f02_consumers/SegmentReadContextAbiProbe.java",
    "Scripts/io_api_inventory/probes/",
    "Scripts/diff_cases/kotlinx_io_",
    "Tests/CompilerBackendTests/Integration/BundledStdlibExecutionTests+ByteString",
    "Tests/CompilerBackendTests/Integration/BundledStdlibExecutionTests+KtorIOCoverage.swift",
    "Tests/CompilerBackendTests/Fixtures/IOSegmentReadContextImpl2590/",
    "Tests/CompilerCoreTests/GoldenCases/Sema/kotlinx_io_",
    "Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlinx_io_",
    "Tests/CompilerCoreTests/Sema/KotlinxIO",
    "Tests/RuntimeTests/RuntimeIoFileSystemTests.swift",
)
LOCAL_IO_PROBE_API_NAMES = {"dataasbytearray"}

SEGMENT_READ_CONTEXT_IMPL_ROW_IDS = frozenset({
    "internal-230a62161c7ea51a",
    "jvm-f8c529b67df6423d",
    "klib-80388c3ba30d5f55",
    "klib-bc524370ccf4a2da",
})
SEGMENT_READ_CONTEXT_IMPL_LOCAL_TESTS = (
    "Scripts/io_api_inventory/f02_consumers/SegmentReadContextAbiProbe.java",
    "Tests/CompilerBackendTests/Fixtures/IOSegmentReadContextImpl2590/",
)
SEGMENT_LIMIT_PROBE_REFS = (
    "Tests/CompilerBackendTests/Fixtures/IOGate2587/SegmentLimit.kt",
    "Scripts/io_api_inventory/run_f02_matrix.py",
    "Scripts/io_api_inventory/test_f02_matrix.py",
)
VALIDATION_PROBE_TEST_REFS = {
    row_id: SEGMENT_LIMIT_PROBE_REFS
    for row_id in (
        "internal-11e61a31ae5fe3d2",
        "jvm-92721bc63200d18d",
        "jvm-98dc8444d3a4ea0f",
        "klib-2d963e0c76f5e362",
        "klib-b170c0f57a48a601",
        "klib-c08a0991fed339e4",
    )
}

INDEX_OF_DEFAULT_BRIDGES = {
    (
        "bytestring",
        "kotlinx/io/bytestring/ByteStringKt",
        "indexOf$default",
        "(Lkotlinx/io/bytestring/ByteString;[BIILjava/lang/Object;)I",
    ): {
        "row_id": "jvm-0a5972de7cfbf1ce",
        "needle_type": "kotlin.ByteArray",
        "source_parameter": "byteArray",
        "upstream_source_line": 351,
        "local_source_line": 154,
        "api_line": 92,
        "case_name": "indexOfByteArray",
        "candidate_execution_id": "kotlinx.io.bytestring.ByteStringTest.indexOfByteArray",
        "base_descriptor": "(Lkotlinx/io/bytestring/ByteString;[BI)I",
    },
    (
        "bytestring",
        "kotlinx/io/bytestring/ByteStringKt",
        "indexOf$default",
        "(Lkotlinx/io/bytestring/ByteString;BIILjava/lang/Object;)I",
    ): {
        "row_id": "jvm-d49996f4a43448e9",
        "needle_type": "kotlin.Byte",
        "source_parameter": "byte",
        "upstream_source_line": 305,
        "local_source_line": 142,
        "api_line": 90,
        "case_name": "indexOfByte",
        "candidate_execution_id": "kotlinx.io.bytestring.ByteStringTest.indexOfByte",
        "base_descriptor": "(Lkotlinx/io/bytestring/ByteString;BI)I",
    },
    (
        "bytestring",
        "kotlinx/io/bytestring/ByteStringKt",
        "indexOf$default",
        "(Lkotlinx/io/bytestring/ByteString;Lkotlinx/io/bytestring/ByteString;IILjava/lang/Object;)I",
    ): {
        "row_id": "jvm-f0c73d7133f5a588",
        "needle_type": "kotlinx.io.bytestring.ByteString",
        "source_parameter": "byteString",
        "upstream_source_line": 327,
        "local_source_line": 151,
        "api_line": 91,
        "case_name": "indexOfByteString",
        "candidate_execution_id": "kotlinx.io.bytestring.ByteStringTest.indexOfByteString",
        "base_descriptor": (
            "(Lkotlinx/io/bytestring/ByteString;"
            "Lkotlinx/io/bytestring/ByteString;I)I"
        ),
    },
}
INDEX_OF_DEFAULT_BRIDGE_DIFF_CASE = (
    "Scripts/diff_cases/kotlinx_io_bytestring_indexof_default_bridges.kt"
)
INDEX_OF_DEFAULT_BRIDGE_LOCAL_TEST = (
    "Tests/CompilerBackendTests/Integration/"
    "BundledStdlibExecutionTests+ByteStringIndexOfDefaults.swift"
)
INDEX_OF_DEFAULT_BRIDGE_PROBE = (
    "Scripts/io_api_inventory/probe_bytestring_indexof_jvm_abi.py"
)
INDEX_OF_DEFAULT_BRIDGE_PROBE_REPORT = (
    "Scripts/io_api_inventory/probe-results/kuu-2618-indexof-jvm-abi.json"
)
INDEX_OF_DEFAULT_BRIDGE_PROBE_INPUTS = (
    "Scripts/io_api_inventory/source-declarations.json",
    "Scripts/io_api_inventory/jvm-declarations.json",
    "Scripts/io_api_inventory/upstream-lock.json",
    "Scripts/io_api_inventory/upstream-tests-index.json",
    "Scripts/io_api_inventory/upstream/kotlinx-io-0.9.1/bytestring/api/kotlinx-io-bytestring.api",
    "Scripts/io_api_inventory/upstream/kotlinx-io-0.9.1/bytestring/common/src/ByteString.kt",
    INDEX_OF_DEFAULT_BRIDGE_PROBE,
)
INDEX_OF_DEFAULT_BRIDGE_TEST_INPUTS = (
    INDEX_OF_DEFAULT_BRIDGE_DIFF_CASE,
    INDEX_OF_DEFAULT_BRIDGE_LOCAL_TEST,
    INDEX_OF_DEFAULT_BRIDGE_PROBE_REPORT,
    *INDEX_OF_DEFAULT_BRIDGE_PROBE_INPUTS,
    "Scripts/kotlinx_io_upstream/reference-lock.json",
    "Scripts/kotlinx_io_upstream/JvmReferenceRunner.java",
    "Scripts/kotlinx_io_upstream/run_jvm_reference.py",
    "Scripts/kotlinx_io_upstream/run_candidate_suites.py",
    "Scripts/kotlinx_io_upstream/run_candidate_subset.py",
    "Scripts/kotlinx_io_upstream/jvm-executions.expected.json",
    "Scripts/kotlinx_io_upstream/native-executions.expected.json",
)

MODIFIERS = (
    "public|internal|private|protected|actual|expect|inline|suspend|operator|"
    "infix|tailrec|open|override|abstract|external|final|data|sealed|const|"
    "lateinit|annotation|enum|value|crossinline|noinline"
)


def fail(message: str) -> None:
    raise SystemExit(f"inventory error: {message}")


def stable_id(*parts: str) -> str:
    return hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()[:16]


def clean(value: object) -> str:
    if value is None:
        return ""
    return re.sub(r"\s+", " ", str(value)).strip()


def git_blob_sha(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def _unique_json_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            fail(f"duplicate JSON field in validation evidence: {key}")
        result[key] = value
    return result


def _validation_input_files(
    references: str,
    root: Path,
    namespace: str,
    locked_files: dict[str, dict] | None = None,
) -> dict[str, str]:
    files = {}
    root = root.resolve()
    for reference in references.split(";"):
        reference = reference.strip()
        if not reference or reference == "none" or reference.startswith("none ("):
            continue
        relative = reference.split("#", 1)[0]
        line_suffix = re.match(r"^(.*?):\d+(?::\d+)?$", relative)
        if line_suffix:
            relative = line_suffix.group(1)
        path = Path(relative)
        if path.is_absolute():
            fail(f"absolute path in validation input reference: {reference}")
        resolved = (root / path).resolve()
        if root not in resolved.parents:
            fail(f"unsafe path in validation input reference: {reference}")
        key = f"{namespace}/{relative}"
        if resolved.is_file():
            data = resolved.read_bytes()
            if locked_files is not None:
                locked = locked_files.get(relative)
                if locked is None or len(data) != locked["size"] or git_blob_sha(data) != locked["gitBlobSha"]:
                    fail(f"upstream test input does not match its lock: {reference}")
            files[key] = hashlib.sha256(data).hexdigest()
        elif locked_files is not None and relative in locked_files:
            # The upstream test sources are pinned by Git blob SHA and size in the checked-in index.
            descriptor = json.dumps(
                locked_files[relative], sort_keys=True, separators=(",", ":")
            )
            files[key] = hashlib.sha256(descriptor.encode("utf-8")).hexdigest()
        else:
            fail(f"missing validation input file: {reference}")
    return files


def validation_input_hashes(
    row: dict,
    repository: Path = REPO,
    upstream: Path = UPSTREAM,
) -> dict[str, str]:
    """Hash the implementation and test files currently mapped to one ledger row."""
    locked_upstream_tests = None
    if upstream.resolve() == UPSTREAM.resolve():
        try:
            lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
            index_bytes = TEST_INDEX_PATH.read_bytes()
            if hashlib.sha256(index_bytes).hexdigest() != lock.get("upstreamTestsIndexSha256"):
                fail("upstream test index changed while hashing validation inputs")
            test_index = json.loads(index_bytes.decode("utf-8"))
            lock_entries = {entry["path"]: entry for entry in lock.get("upstreamTests", [])}
            if set(lock_entries) != {entry["path"] for entry in test_index.get("files", [])}:
                fail("upstream test index and lock file list differ while hashing validation inputs")
            locked_upstream_tests = {}
            for entry in test_index["files"]:
                locked = lock_entries[entry["path"]]
                if (entry.get("gitBlobSha"), entry.get("size")) != (
                    locked.get("gitBlobSha"), locked.get("size")
                ):
                    fail(f"upstream test input lock mismatch: {entry['path']}")
                locked_upstream_tests[entry["path"]] = {
                    "gitBlobSha": entry["gitBlobSha"],
                    "size": entry["size"],
                }
        except (OSError, json.JSONDecodeError) as error:
            fail(f"cannot load upstream test input hashes: {error}")

    implementation_files = _validation_input_files(
        ";".join((row.get("local_candidate_refs", ""), row.get("local_implementation_refs", ""))),
        repository,
        "repo",
    )
    test_files = _validation_input_files(row.get("local_test_refs", ""), repository, "repo")
    test_files.update(
        _validation_input_files(
            row.get("upstream_test_refs", ""), upstream, "upstream", locked_upstream_tests
        )
    )

    def digest(files: dict[str, str]) -> str:
        encoded = json.dumps(files, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(encoded.encode("utf-8")).hexdigest()

    return {
        "implementation_input_sha256": digest(implementation_files),
        "test_input_sha256": digest(test_files),
    }


def validation_obligations(row: dict) -> list[str]:
    """Return the compatibility obligations that apply to this ledger representation."""
    if row.get("_jvm_key") in INDEX_OF_DEFAULT_BRIDGES:
        # These rows describe generated JVM bridges, but the compiler under test
        # emits native code. Require both the pinned JVM reference and the
        # candidate's native implementation lanes, with the classfile probe
        # recorded separately so native output cannot stand in for JVM ABI.
        return ["jvm-descriptor", "native-source"]
    if row.get("representation") == "JVM public ABI dump":
        return ["jvm-descriptor"]
    return ["native-source", "native-bridge"]


def restore_hidden_jvm_key(row: dict) -> dict:
    """Restore the non-rendered JVM signature key from a stable ledger row ID."""
    for jvm_key, spec in INDEX_OF_DEFAULT_BRIDGES.items():
        if spec["row_id"] == row.get("row_id"):
            row["_jvm_key"] = jvm_key
            break
    return row


def validate_index_of_bridge_probe(
    row: dict,
    record: dict,
    repository: Path = REPO,
) -> None:
    """Require a passing reference classfile probe for each mapped default bridge."""
    spec = INDEX_OF_DEFAULT_BRIDGES.get(row.get("_jvm_key"))
    if spec is None:
        return
    if row.get("row_id") != spec["row_id"]:
        fail(f"ByteString.indexOf bridge row identity changed: {row.get('row_id')}")
    report_path = repository / INDEX_OF_DEFAULT_BRIDGE_PROBE_REPORT
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError) as error:
        fail(f"cannot read ByteString.indexOf JVM ABI probe report: {error}")
    if report.get("schema_version") != 1 or report.get("result") != "PASS":
        fail(f"ByteString.indexOf JVM ABI probe did not pass for {row['row_id']}")
    if report.get("candidate_sha") != record.get("candidate_sha"):
        fail(f"ByteString.indexOf JVM ABI probe candidate SHA mismatch for {row['row_id']}")
    if (report.get("reference_version"), report.get("reference_commit")) != (
        "0.9.1",
        EXPECTED_TAG_COMMIT,
    ):
        fail(f"ByteString.indexOf JVM ABI probe reference pin mismatch for {row['row_id']}")
    probe_path = repository / INDEX_OF_DEFAULT_BRIDGE_PROBE
    if report.get("probe_sha256") != hashlib.sha256(probe_path.read_bytes()).hexdigest():
        fail(f"stale ByteString.indexOf JVM ABI probe hash for {row['row_id']}")
    if report.get("execution_count") != 3 or report.get("passed_count") != 3:
        fail("ByteString.indexOf JVM ABI probe must pass all three mapped methods")
    expected_artifact = next(
        (
            item
            for item in json.loads(LOCK_PATH.read_text(encoding="utf-8"))["mavenArtifacts"]
            if item["coordinate"]
            == "org.jetbrains.kotlinx:kotlinx-io-bytestring-jvm:0.9.1"
        ),
        None,
    )
    if expected_artifact is None or report.get("artifact_sha256") != expected_artifact["sha256"]:
        fail(f"ByteString.indexOf JVM ABI probe artifact hash mismatch for {row['row_id']}")
    if report.get("artifact_coordinate") != expected_artifact["coordinate"]:
        fail(f"ByteString.indexOf JVM ABI probe artifact coordinate mismatch for {row['row_id']}")
    probe_inputs = {
        "probe": hashlib.sha256((repository / INDEX_OF_DEFAULT_BRIDGE_PROBE).read_bytes()).hexdigest(),
        "api": hashlib.sha256((repository / INDEX_OF_DEFAULT_BRIDGE_PROBE_INPUTS[4]).read_bytes()).hexdigest(),
        "upstream_source": hashlib.sha256((repository / INDEX_OF_DEFAULT_BRIDGE_PROBE_INPUTS[5]).read_bytes()).hexdigest(),
        "candidate_source": hashlib.sha256(
            (repository / "Sources/CompilerCore/Stdlib/kotlinx/io/bytestring/ByteString.kt").read_bytes()
        ).hexdigest(),
        "source_declarations": hashlib.sha256(
            (repository / INDEX_OF_DEFAULT_BRIDGE_PROBE_INPUTS[0]).read_bytes()
        ).hexdigest(),
        "jvm_declarations": hashlib.sha256(
            (repository / INDEX_OF_DEFAULT_BRIDGE_PROBE_INPUTS[1]).read_bytes()
        ).hexdigest(),
        "upstream_lock": hashlib.sha256(
            (repository / INDEX_OF_DEFAULT_BRIDGE_PROBE_INPUTS[2]).read_bytes()
        ).hexdigest(),
        "upstream_tests_index": hashlib.sha256(
            (repository / INDEX_OF_DEFAULT_BRIDGE_PROBE_INPUTS[3]).read_bytes()
        ).hexdigest(),
        "reference_artifact": expected_artifact["sha256"],
    }
    expected_probe_inputs_sha = hashlib.sha256(
        json.dumps(probe_inputs, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    if report.get("probe_inputs_sha256") != expected_probe_inputs_sha:
        fail(f"stale ByteString.indexOf JVM ABI probe inputs for {row['row_id']}")
    if report.get("candidate_boundary") != (
        "Reference classfile shape only. KSwiftK emits native code; candidate native "
        "default-dispatch execution is separate evidence and does not establish candidate "
        "JVM classfile ABI."
    ):
        fail("ByteString.indexOf JVM ABI probe boundary statement changed")
    methods = report.get("methods")
    if not isinstance(methods, list) or len(methods) != 3:
        fail("ByteString.indexOf JVM ABI probe report must contain exactly three methods")
    matches = [method for method in methods if method.get("row_id") == row["row_id"]]
    if len(matches) != 1:
        fail(f"ByteString.indexOf JVM ABI probe omitted {row['row_id']}")
    method = matches[0]
    expected_bridge = row["_jvm_key"][3]
    expected_flags = {"public": True, "static": True, "synthetic": True, "bridge": False}
    if (
        method.get("result") != "PASS"
        or method.get("bridge_descriptor") != expected_bridge
        or method.get("flags") != expected_flags
        or method.get("mask_values_when_defaults_are_omitted") != [2]
        or method.get("marker_parameter") != "java.lang.Object"
        or method.get("underlying_descriptor") != spec["base_descriptor"]
        or method.get("underlying_flags")
        != {"public": True, "static": True, "synthetic": False, "bridge": False}
    ):
        fail(f"ByteString.indexOf JVM ABI probe details mismatch for {row['row_id']}")
    if method.get("case_id") != f"bytestring/common/test/ByteStringTest.kt#{spec['case_name']}":
        fail(f"ByteString.indexOf JVM ABI probe case mismatch for {row['row_id']}")
    if method.get("api_reference") != (
        "bytestring/api/kotlinx-io-bytestring.api:" + str(spec["api_line"])
    ):
        fail(f"ByteString.indexOf JVM ABI probe API reference mismatch for {row['row_id']}")
    if method.get("upstream_source") != f"bytestring/common/src/ByteString.kt:{spec['upstream_source_line']}":
        fail(f"ByteString.indexOf JVM ABI probe upstream source mismatch for {row['row_id']}")
    if method.get("candidate_source") != (
        "Sources/CompilerCore/Stdlib/kotlinx/io/bytestring/ByteString.kt:"
        f"{spec['local_source_line']}"
    ):
        fail(f"ByteString.indexOf JVM ABI probe candidate source mismatch for {row['row_id']}")
    if method.get("candidate_execution_id") != spec["candidate_execution_id"]:
        fail(f"ByteString.indexOf JVM ABI probe candidate case mismatch for {row['row_id']}")
    expected_reference_execution_id = (
        "[engine:junit-jupiter]/[class:kotlinx.io.bytestring.ByteStringTest]/"
        f"[method:{spec['case_name']}()]"
    )
    if method.get("upstream_execution_id") != expected_reference_execution_id:
        fail(f"ByteString.indexOf JVM ABI probe reference case mismatch for {row['row_id']}")
    expected_source_type = spec["needle_type"].rsplit(".", 1)[-1]
    if method.get("source_contract") != {
        "visibility": "public",
        "receiver": "kotlinx.io.bytestring.ByteString",
        "parameters": [
            {"name": spec["source_parameter"], "type": expected_source_type, "default": None},
            {"name": "startIndex", "type": "Int", "default": "0"},
        ],
        "return_type": "kotlin.Int",
        "annotations": [],
        "deprecation": "none",
        "exception_contract": "not-declared-in-source",
    }:
        fail(f"ByteString.indexOf JVM ABI probe source contract mismatch for {row['row_id']}")


def required_execution_lanes(obligations: list[str]) -> list[str]:
    return [lane for obligation in obligations for lane in VALIDATION_LANES_BY_OBLIGATION[obligation]]


def local_probe_execution_id(
    candidate_sha: str,
    reference_commit: str,
    case_id: str,
    lane: str,
    subject: str,
) -> str:
    """Return a stable identity for one registered local probe and validation lane."""
    if subject not in ("reference", "candidate"):
        fail(f"unknown local probe evidence subject: {subject}")
    digest = hashlib.sha256(
        "|".join(("io-api-local-probe-v1", candidate_sha, reference_commit, case_id, lane, subject))
        .encode("utf-8")
    ).hexdigest()[:32]
    return f"local-probe-v1:{subject}:{digest}"


def _local_probe_case_spec(row: dict, case_id: str) -> dict | None:
    spec = LOCAL_PROBE_EVIDENCE_CASES.get(case_id)
    if spec is None or row.get("row_id") not in spec["row_ids"]:
        return None
    if spec["path"] not in row.get("local_test_refs", "").split(";"):
        return None
    return spec


def _load_validation_execution_catalogs() -> dict[str, dict[str, str]]:
    try:
        lock = json.loads(UPSTREAM_RUNNER_LOCK_PATH.read_text(encoding="utf-8"))
        if lock.get("commit") != EXPECTED_TAG_COMMIT:
            fail("validation execution catalogs use a different upstream commit")
        catalogs = {}
        for subject, path, lock_key in (
            ("reference", REFERENCE_EXECUTIONS_PATH, "jvm_execution_catalog_sha256"),
            ("candidate", CANDIDATE_EXECUTIONS_PATH, "native_execution_catalog_sha256"),
        ):
            contents = path.read_bytes()
            if hashlib.sha256(contents).hexdigest() != lock.get(lock_key):
                fail(f"{subject} execution catalog does not match its lock")
            entries = json.loads(contents.decode("utf-8"))
            if not isinstance(entries, list):
                fail(f"{subject} execution catalog must be an array")
            catalog = {}
            for entry in entries:
                if not isinstance(entry, dict):
                    fail(f"{subject} execution catalog contains a malformed entry")
                execution_id = entry.get("execution_id")
                case_id = entry.get("upstream_id")
                if not isinstance(execution_id, str) or not execution_id:
                    fail(f"{subject} execution catalog has an empty execution_id")
                if not isinstance(case_id, str) or not case_id:
                    fail(f"{subject} execution catalog has an empty upstream_id")
                if execution_id in catalog:
                    fail(f"duplicate {subject} execution ID in locked catalog: {execution_id}")
                catalog[execution_id] = case_id
            catalogs[subject] = catalog
        return catalogs
    except (OSError, json.JSONDecodeError, UnicodeDecodeError) as error:
        fail(f"cannot load validation execution catalogs: {error}")


def _case_id_matches_row(row: dict, case_id: str) -> bool:
    case_path, separator, case_name = case_id.partition("#")
    if not separator or not case_path or not case_name:
        return False
    for reference in row.get("upstream_test_refs", "").split(";"):
        reference_path, marker, reference_name = reference.partition("#")
        # A suite mapping is a discovery hint, not row-level execution evidence.
        if not marker or reference_name == "suite-reference" or case_path != reference_path:
            continue
        if case_name == reference_name:
            return True
    return False


def apply_validation_evidence(
    rows: list[dict],
    lock: dict,
    evidence_path: Path = VALIDATION_EVIDENCE_PATH,
    repository: Path = REPO,
    upstream: Path = UPSTREAM,
    execution_catalogs: dict[str, dict[str, str]] | None = None,
) -> None:
    """Promote rows only when their pinned, current evidence satisfies every obligation."""
    by_id = {}
    for row in rows:
        row_id = row.get("row_id")
        if not isinstance(row_id, str) or not row_id:
            fail("API inventory row has an empty row_id")
        if row_id in by_id:
            fail(f"duplicate API inventory row_id: {row_id}")
        by_id[row_id] = row
        row["status"] = row.get("_inventory_status", row.get("status", "missing"))

    try:
        evidence = json.loads(
            evidence_path.read_text(encoding="utf-8"), object_pairs_hook=_unique_json_object
        )
    except OSError as error:
        fail(f"cannot read validation evidence {evidence_path}: {error}")
    except json.JSONDecodeError as error:
        fail(f"invalid validation evidence JSON: {error}")
    except UnicodeDecodeError as error:
        fail(f"validation evidence is not UTF-8: {error}")

    if not isinstance(evidence, dict) or set(evidence) != {"schema_version", "records"}:
        fail("validation evidence must contain only schema_version and records")
    schema_version = evidence["schema_version"]
    if type(schema_version) is not int or schema_version not in (1, VALIDATION_EVIDENCE_SCHEMA_VERSION):
        fail("unsupported validation evidence schema_version")
    records = evidence["records"]
    if not isinstance(records, list):
        fail("validation evidence records must be an array")
    if records and (schema_version == 1 or any(
        isinstance(record, dict) and record.get("evidence_source") == "upstream-catalog"
        for record in records
    )):
        if execution_catalogs is None:
            execution_catalogs = _load_validation_execution_catalogs()
        if set(execution_catalogs) != {"reference", "candidate"}:
            fail("validation execution catalogs must include reference and candidate entries")

    base_record_fields = {
        "row_id",
        "candidate_sha",
        "reference_version",
        "reference_commit",
        "implementation_input_sha256",
        "test_input_sha256",
        "compatibility_obligations",
        "executions",
    }
    execution_fields = {"case_id", "lane", "reference", "candidate"}
    catalog_result_fields = {"execution_id", "result", "exit_code"}
    local_result_fields = catalog_result_fields | {"method"}
    seen_ids = set()
    sha256_pattern = re.compile(r"^[0-9a-f]{64}$")
    candidate_sha_pattern = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")

    for record in records:
        if not isinstance(record, dict):
            fail("each validation record must be an object")
        evidence_source = "upstream-catalog" if schema_version == 1 else record.get("evidence_source")
        record_fields = base_record_fields | ({"evidence_source"} if schema_version == 2 else set())
        if set(record) != record_fields:
            fail(f"each validation record must contain exactly the schema v{schema_version} fields")
        if evidence_source not in ("upstream-catalog", "local-probe"):
            fail(f"unknown evidence_source for schema v{schema_version}")
        if evidence_source == "upstream-catalog" and execution_catalogs is None:
            execution_catalogs = _load_validation_execution_catalogs()
        row_id = record["row_id"]
        if not isinstance(row_id, str) or not row_id:
            fail("validation record has an empty row_id")
        if row_id in seen_ids:
            fail(f"duplicate validation evidence row_id: {row_id}")
        seen_ids.add(row_id)
        row = by_id.get(row_id)
        if row is None:
            fail(f"validation evidence references unknown row_id: {row_id}")
        if row["status"] != "unverified":
            fail(f"validation evidence cannot promote {row_id} from status {row['status']}")

        candidate_sha = record["candidate_sha"]
        if not isinstance(candidate_sha, str) or not candidate_sha_pattern.fullmatch(candidate_sha):
            fail(f"malformed candidate SHA for row {row_id}")
        if (record["reference_version"], record["reference_commit"]) != (
            lock.get("tag"),
            lock.get("commit"),
        ):
            fail(f"reference version mismatch for row {row_id}")

        hashes = validation_input_hashes(row, repository, upstream)
        for field in ("implementation_input_sha256", "test_input_sha256"):
            value = record[field]
            if not isinstance(value, str) or not sha256_pattern.fullmatch(value):
                fail(f"malformed {field} for row {row_id}")
            if value != hashes[field]:
                fail(f"stale {field} for row {row_id}")

        obligations = validation_obligations(row)
        recorded_obligations = record["compatibility_obligations"]
        if (not isinstance(recorded_obligations, list)
                or recorded_obligations != obligations):
            fail(f"compatibility obligations mismatch for row {row_id}")
        executions = record["executions"]
        if not isinstance(executions, list) or not executions:
            fail(f"validation evidence has no executed cases for row {row_id}")
        required_lanes = required_execution_lanes(obligations)
        covered_lanes = set()
        covered_local_case_lanes = set()
        seen_cases = set()
        seen_execution_ids = {"reference": set(), "candidate": set()}
        for execution in executions:
            if not isinstance(execution, dict) or set(execution) != execution_fields:
                fail(f"malformed execution record for row {row_id}")
            case_id = execution["case_id"]
            lane = execution["lane"]
            if not isinstance(case_id, str) or not case_id.strip() or case_id != case_id.strip():
                fail(f"empty execution case_id for row {row_id}")
            local_case_spec = None
            if evidence_source == "upstream-catalog":
                if not _case_id_matches_row(row, case_id):
                    fail(f"execution case {case_id!r} is not mapped to row {row_id}'s upstream tests")
            else:
                local_case_spec = _local_probe_case_spec(row, case_id)
                if local_case_spec is None:
                    fail(f"local probe case {case_id!r} is not registered for row {row_id}")
            if not isinstance(lane, str) or lane not in required_lanes:
                fail(f"unexpected validation lane {lane!r} for row {row_id}")
            if local_case_spec is not None and lane not in local_case_spec["lanes"]:
                fail(f"unexpected local probe lane {lane!r} for row {row_id} case {case_id}")
            identity = (lane, case_id)
            if identity in seen_cases:
                fail(f"duplicate execution case {case_id!r} in lane {lane!r} for row {row_id}")
            seen_cases.add(identity)
            covered_lanes.add(lane)
            if local_case_spec is not None:
                covered_local_case_lanes.add((case_id, lane))
            for subject in ("reference", "candidate"):
                result = execution[subject]
                result_fields = local_result_fields if local_case_spec is not None else catalog_result_fields
                if not isinstance(result, dict) or set(result) != result_fields:
                    fail(f"malformed {subject} result for row {row_id} case {case_id}")
                execution_id = result["execution_id"]
                if (not isinstance(execution_id, str) or not execution_id.strip()
                        or execution_id != execution_id.strip()):
                    fail(f"empty {subject} execution_id for row {row_id} case {case_id}")
                if local_case_spec is None:
                    catalog_case_id = execution_catalogs[subject].get(execution_id)
                    if catalog_case_id is None:
                        fail(f"unknown {subject} execution_id for row {row_id}: {execution_id}")
                    if catalog_case_id != case_id:
                        fail(f"{subject} execution_id does not map to case {case_id} for row {row_id}")
                else:
                    expected_execution_id = local_probe_execution_id(
                        candidate_sha, record["reference_commit"], case_id, lane, subject
                    )
                    if execution_id != expected_execution_id:
                        fail(f"{subject} local execution_id does not map to case/lane for row {row_id}")
                    if result["method"] != local_case_spec["methods"][subject]:
                        fail(f"unexpected {subject} evidence method for row {row_id} case {case_id}")
                execution_identity = (lane, execution_id)
                if execution_identity in seen_execution_ids[subject]:
                    fail(f"duplicate {subject} execution_id for row {row_id}: {execution_id}")
                seen_execution_ids[subject].add(execution_identity)
                if result["result"] != "PASS":
                    fail(f"non-passing {subject} result for row {row_id} case {case_id}")
                if type(result["exit_code"]) is not int or result["exit_code"] != 0:
                    fail(f"non-zero {subject} exit code for row {row_id} case {case_id}")

        missing_lanes = set(required_lanes) - covered_lanes
        if missing_lanes:
            fail(f"missing validation lanes for row {row_id}: {', '.join(sorted(missing_lanes))}")
        if evidence_source == "local-probe":
            required_cases = {
                case_id: spec
                for case_id, spec in LOCAL_PROBE_EVIDENCE_CASES.items()
                if row_id in spec["row_ids"] and spec["path"] in row.get("local_test_refs", "").split(";")
            }
            for case_id, spec in required_cases.items():
                observed_lanes = {
                    lane for observed_case, lane in covered_local_case_lanes if observed_case == case_id
                }
                missing_case_lanes = set(spec["lanes"]) - observed_lanes
                if missing_case_lanes:
                    fail(
                        f"missing local probe lanes for row {row_id} case {case_id}: "
                        f"{', '.join(sorted(missing_case_lanes))}"
                    )
            if not required_cases:
                fail(f"row {row_id} has no registered local probe evidence cases")
        validate_index_of_bridge_probe(row, record, repository)
        row["status"] = "verified"


def load_inputs() -> tuple[dict, dict, list[dict], list[dict]]:
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    test_index_bytes = TEST_INDEX_PATH.read_bytes()
    test_index = json.loads(test_index_bytes.decode("utf-8"))
    if lock.get("tag") != "0.9.1" or lock.get("commit") != EXPECTED_TAG_COMMIT:
        fail("the upstream tag must remain pinned to 0.9.1 at the recorded commit")
    if hashlib.sha256(test_index_bytes).hexdigest() != lock.get("upstreamTestsIndexSha256"):
        fail("the upstream test catalog index does not match its pinned SHA-256")
    if test_index.get("commit") != lock["commit"]:
        fail("the upstream test catalog uses a different commit")

    source_files = lock.get("upstreamFiles", [])
    expected_paths = {entry["path"] for entry in source_files}
    if len(expected_paths) != len(source_files):
        fail("duplicate path in upstreamFiles")
    for entry in source_files:
        path = (UPSTREAM / entry["path"]).resolve()
        if UPSTREAM.resolve() not in path.parents:
            fail(f"unsafe upstream input path: {entry['path']}")
        if not path.is_file():
            fail(f"missing pinned upstream input: {entry['path']}")
        data = path.read_bytes()
        if len(data) != entry["size"]:
            fail(f"size mismatch for {entry['path']}")
        if git_blob_sha(data) != entry["gitBlobSha"]:
            fail(f"Git blob SHA mismatch for {entry['path']}")
        if hashlib.sha256(data).hexdigest() != entry["sha256"]:
            fail(f"SHA-256 mismatch for {entry['path']}")

    tests = test_index.get("files", [])
    lock_tests = {entry["path"]: entry for entry in lock.get("upstreamTests", [])}
    if set(lock_tests) != {entry["path"] for entry in tests}:
        fail("upstream test catalog and lock file list differ")
    for entry in tests:
        pinned = lock_tests[entry["path"]]
        if (entry["gitBlobSha"], entry["size"]) != (
            pinned["gitBlobSha"],
            pinned["size"],
        ):
            fail(f"test catalog hash mismatch: {entry['path']}")

    test_paths = {entry["path"] for entry in tests}
    required_api = set(lock["apiDumps"])
    if not required_api.issubset(expected_paths):
        fail("one or more of the four API dumps are absent from upstreamFiles")
    return lock, test_index, source_files, tests


def source_paths(source_files: list[dict]) -> list[Path]:
    return [
        UPSTREAM / entry["path"]
        for entry in source_files
        if entry["path"].endswith(".kt")
        and "/src/" in entry["path"]
    ]


def source_platform(path: str) -> str:
    parts = path.split("/")
    if len(parts) > 1 and parts[1] in {"common", "apple", "jvm", "native"}:
        return parts[1]
    return parts[1] if len(parts) > 1 else "unknown"


def declaration_lines(path: Path, kind: str, name: str) -> list[tuple[int, str]]:
    """Find source declaration lines by exact Kotlin declaration name."""
    if name in {"", "<init>"}:
        return []
    quoted = re.escape(name)
    if kind == "object" and name == "Companion":
        pattern = re.compile(
            rf"^\s*(?:(?:{MODIFIERS})\s+)*(?:companion\s+object(?:\s+`?{quoted}`?)?|object\s+`?{quoted}`?)(?:\W|$)"
        )
    elif kind in {"class", "interface", "object", "annotation class"}:
        pattern = re.compile(
            rf"^\s*(?:(?:{MODIFIERS})\s+)*(?:annotation\s+class|"
            rf"enum\s+class|class|interface|object)\s+`?{quoted}`?(?:\W|$)"
        )
    elif kind == "property":
        pattern = re.compile(
            rf"^\s*(?:(?:{MODIFIERS})\s+)*(?:val|var)\s+"
            rf"(?:[\w.`<>?, ]+\.)?`?{quoted}`?(?:\W|$)"
        )
    else:
        pattern = re.compile(
            rf"^\s*(?:(?:{MODIFIERS})\s+)*fun\b.*?"
            rf"(?:\.|\s|/|<|>)`?{quoted}`?\s*(?:<[^\n>]*>)?\s*\("
        )
    result = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if pattern.search(line):
            result.append((number, line.strip()))
    return result


def metadata_for(path: Path, line_number: int) -> tuple[str, str, str, str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    index = max(0, line_number - 1)
    target_indent = len(lines[index]) - len(lines[index].lstrip())
    declaration_start = re.compile(
        rf"^\s*(?:(?:{MODIFIERS}|companion)\s+)*(?:fun|val|var|class|interface|object|constructor)\b"
    )
    previous = [
        line_index
        for line_index, line in enumerate(lines[:index])
        if len(line) - len(line.lstrip()) == target_indent and declaration_start.match(line)
    ]
    window_start = (previous[-1] + 1) if previous else max(0, index - 100)
    window = "\n".join(lines[window_start:index])
    annotation_names = sorted(
        {
            name
            for name in re.findall(r"@([A-Za-z_][A-Za-z_0-9.]*)", window)
            if name[0].isupper() or name in {"JvmName", "Throws", "PublishedApi"}
        }
    )
    deprecated = "none"
    deprecated_body = balanced_annotation_body(window, "Deprecated")
    if deprecated_body is not None:
        body = deprecated_body
        level = re.search(r"level\s*=\s*DeprecationLevel\.(WARNING|ERROR|HIDDEN)", body)
        message = re.search(r"message\s*=\s*\"([^\"]*)\"", body) or re.search(r"\"([^\"]*)\"", body)
        deprecated = (level.group(1) if level else "WARNING")
        if message:
            deprecated += ": " + message.group(1)
    exceptions = []
    throws = re.search(r"@Throws\s*\(([^)]*)\)", window)
    if throws:
        exceptions.append("@Throws(" + clean(throws.group(1)) + ")")
    for thrown in re.findall(r"@throws\s+([\w.]+)([^\n]*)", window):
        exceptions.append("@throws " + clean(" ".join(thrown)))
    exception_contract = "; ".join(dict.fromkeys(exceptions)) or "not-declared-in-source"
    return ",".join(annotation_names) or "none", deprecated, exception_contract, lines[index].strip()


def balanced_annotation_body(text: str, annotation: str) -> str | None:
    match = re.search(rf"@{re.escape(annotation)}\s*\(", text)
    if not match:
        return None
    start = match.end()
    depth = 1
    in_string = False
    escaped = False
    for index in range(start, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return text[start:index]
    return text[start:]


def source_declares_type(path: Path, name: str) -> bool:
    return any(declaration_lines(path, kind, name) for kind in ("class", "interface", "object", "annotation class"))


def source_matches_jvm_owner(path: Path, class_name: str) -> bool:
    simple_name = class_name.rsplit("/", 1)[-1]
    if simple_name.endswith("Kt"):
        return path.stem == simple_name[:-2]
    simple_name = simple_name.split("$", 1)[0]
    return source_declares_type(path, simple_name)


def source_constructor_lines(path: Path, class_name: str) -> list[tuple[int, str]]:
    type_lines = declaration_lines(path, "class", class_name)
    if not type_lines:
        return []
    class_indent = min(len(line) - len(line.lstrip()) for _, line in type_lines)
    result = list(type_lines)
    constructor = re.compile(rf"^\s*(?:(?:{MODIFIERS})\s+)*constructor\b")
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        indent = len(line) - len(line.lstrip())
        if indent > class_indent and constructor.match(line):
            result.append((number, line.strip()))
    # Explicit secondary constructors carry clearer visibility and docs than
    # the class header, which may describe a different private primary ctor.
    explicit_constructor = re.compile(rf"^\s*(?:(?:{MODIFIERS})\s+)*constructor\b")
    return sorted(result, key=lambda item: (not bool(explicit_constructor.match(item[1])), item[0]))


def source_declaration_visibility(line: str, kind: str) -> str:
    declaration = re.match(
        rf"^\s*((?:(?:{MODIFIERS}|companion)\s+)*)(?:annotation\s+class|enum\s+class|class|interface|object|fun|val|var|constructor)\b",
        line,
    )
    prefix = declaration.group(1) if declaration else ""
    visibility = re.search(r"\b(internal|private|protected)\b", prefix)
    if visibility:
        return visibility.group(1)
    if kind == "constructor":
        constructor_visibility = re.search(r"\b(internal|private|protected)\s+constructor\b", line)
        if constructor_visibility:
            return constructor_visibility.group(1)
    return ""


def jvm_name_mapping(sources: list[Path], module: str, jvm_name: str) -> str:
    quoted = re.escape(jvm_name)
    annotation = re.compile(rf"@JvmName\s*\(\s*(?:name\s*=\s*)?\"{quoted}\"\s*\)")
    function = re.compile(r"\bfun\s+(?:<[^>]+>\s*)?(?:[^\s(]+\.)?([A-Za-z_][A-Za-z_0-9]*)\s*\(")
    for source in sources:
        if source.relative_to(UPSTREAM).parts[0] != module:
            continue
        lines = source.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            if not annotation.search(line):
                continue
            for following in lines[index + 1 : index + 10]:
                match = function.search(following)
                if match:
                    return match.group(1)
    return ""


def api_id_parts(api_id: str) -> tuple[str, str, str]:
    identity = api_id.split("|", 1)[0]
    identity = re.sub(r"\.<(?:get|set)-[^>]+>$", "", identity)
    if "/" in identity:
        package, leaf = identity.rsplit("/", 1)
    else:
        package, leaf = "", identity
    if "." in leaf:
        owner, member = leaf.rsplit(".", 1)
        owner_fqn = f"{package}/{owner}" if package else owner
    else:
        owner_fqn, member = "", leaf
    return package, owner_fqn, member


def declaration_kind(signature: str, api_id: str = "") -> tuple[str, str]:
    text = signature.strip()
    identity = api_id.split("|", 1)[0] if api_id else ""
    api_leaf = identity.rsplit("/", 1)[-1].rsplit(".", 1)[-1]
    if re.search(r"\bannotation\s+class\b", text):
        name = re.search(r"\bannotation\s+class\s+([^\s:{(]+)", text)
        return "annotation class", name.group(1).split("/")[-1] if name else ""
    if re.search(r"\binterface\b", text) and " fun " not in text:
        name = re.search(r"\binterface\s+([^\s:{(]+)", text)
        return "interface", name.group(1).split("/")[-1] if name else ""
    if re.search(r"\b(?:class|object)\b", text) and " fun " not in text:
        match = re.search(r"\b(class|object)\s+([^\s:{(]+)", text)
        return (match.group(1), match.group(2).split("/")[-1]) if match else ("class", "")
    if re.search(r"\bval\b|\bvar\b", text) and "<get-" not in text:
        if api_leaf:
            return "property", api_leaf
        return "property", text.split("|", 1)[0].split()[-1].split("/")[-1]
    accessor = re.search(r"<(?:get|set)-([^>]+)>", text)
    if accessor:
        return "source accessor", accessor.group(1)
    if re.search(r"\bconstructor\b|\bfun\s+<init>", text):
        return "constructor", "<init>"
    function = re.search(r"\bfun\s+(?:<[^>]+>\s*)?(?:[^\s(]+\.)?([^\s(]+)\s*\(", text)
    if function:
        return "function", function.group(1).split("/")[-1]
    # KLIB renders extension receivers as `fun (Receiver).package/name(...)`.
    # In that form the callable name is unambiguous in the ABI identity after
    # `//`; use that pinned identity rather than guessing from the return type.
    if re.search(r"\bfun\b", text) and api_id:
        if re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", api_leaf):
            return "function", api_leaf
    return "declaration", ""


def parse_klib(path: Path, module: str, sources: list[Path]) -> list[dict]:
    rows = []
    pending_target = "common"
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = raw.strip()
        if stripped.startswith("// Targets: ["):
            target_text = stripped[len("// Targets: [") :].split("]", 1)[0]
            pending_target = "apple-only" if target_text == "apple" else "platform-only:" + target_text
            continue
        if not stripped or stripped.startswith("//"):
            continue
        if " // " not in stripped:
            continue
        signature, metadata = stripped.split(" // ", 1)
        api_id = re.sub(r"\[\d+\]\s*$", "", metadata).strip()
        kind, name = declaration_kind(signature, api_id)
        if not name:
            continue
        package, owner, member = api_id_parts(api_id)
        if kind in {"class", "interface", "object", "annotation class"}:
            owner_fqn = api_id.split("|", 1)[0]
        elif owner:
            owner_fqn = owner
        else:
            owner_fqn = package or module
        source_kind = (
            "property"
            if kind == "source accessor"
            else "class"
            if kind == "constructor"
            else kind
        )
        source_name = (
            owner_fqn.rsplit("/", 1)[-1].rsplit(".", 1)[-1]
            if kind == "constructor"
            else name
        )
        matching = []
        for source in sources:
            rel = source.relative_to(UPSTREAM).as_posix()
            if rel.split("/", 1)[0] != module:
                continue
            found = declaration_lines(source, source_kind, source_name)
            if found:
                matching.extend((source, number, text) for number, text in found)
        if owner:
            owner_name = owner.rsplit("/", 1)[-1]
            owner_matches = [item for item in matching if source_declares_type(item[0], owner_name)]
            if owner_matches:
                matching = owner_matches
        if kind == "constructor":
            constructor_matches = []
            for source in dict.fromkeys(item[0] for item in matching):
                constructor_matches.extend(
                    (source, number, declaration)
                    for number, declaration in source_constructor_lines(source, source_name)
                )
            if constructor_matches:
                matching = constructor_matches
        preferred = source_platform(
            matching[0][0].relative_to(UPSTREAM).as_posix()
        ) if matching else ""
        if pending_target == "apple-only":
            matching.sort(
                key=lambda item: 0
                if "/apple/src/" in item[0].as_posix()
                else 1
            )
        elif preferred:
            matching.sort(
                key=lambda item: 0
                if source_platform(item[0].relative_to(UPSTREAM).as_posix())
                in {"common", "apple", "jvm", "native"}
                else 1
            )
        refs = []
        annotations, deprecated, exception_contract = "none", "none", "not-declared-in-source"
        source_line = ""
        if matching:
            unique = []
            for source, number, text in matching:
                ref = f"{source.relative_to(UPSTREAM).as_posix()}:{number}"
                if ref not in refs:
                    refs.append(ref)
                    unique.append((source, number, text))
            if unique:
                annotations, deprecated, exception_contract, source_line = metadata_for(
                    unique[0][0], unique[0][1]
                )
        if kind == "source accessor":
            source_api = "no"
            api_kind = "source-property-accessor"
        else:
            source_api = "yes"
            api_kind = kind
        source_visibility = source_declaration_visibility(source_line, kind)
        is_internal_abi = bool(source_visibility)
        if is_internal_abi:
            source_api = "no"
            api_kind = (
                f"{source_visibility} source-property-accessor"
                if kind == "source accessor"
                else f"{source_visibility} {kind}"
            )
        defaults = len(re.findall(r"\s=\s\.\.\.", signature))
        row = {
            "row_id": "klib-" + stable_id(module, pending_target, api_id),
            "module": module,
            "representation": (
                "Internal implementation ABI / KLIB dump"
                if is_internal_abi
                else "Kotlin source API / KLIB dump"
            ),
            "platform_scope": pending_target,
            "api_kind": api_kind,
            "source_api": source_api,
            "owner_fqn": owner_fqn,
            "name": name,
            "signature": signature,
            "default_parameter_count": str(defaults),
            "annotations": annotations,
            "deprecation": deprecated,
            "exception_contract": exception_contract,
            "upstream_source_refs": ";".join(refs) or "source declaration not found by name",
            "jvm_abi_refs": "",
            "upstream_test_refs": "",
            "local_candidate_refs": "",
            "local_test_refs": "",
            "status": "unverified",
            "owner_issue": "KUU-1725",
            "scope_decision": (
                "in-scope internal implementation ABI; not a public Kotlin source API"
                if is_internal_abi
                else "in-scope Apple API"
                if pending_target == "apple-only"
                else "in-scope common/native API"
            ),
            "notes": f"KLIB declaration key: {api_id}; source declaration line: {source_line}",
            "_source_paths": [item[0] for item in matching],
            "_candidate_name": source_name,
            "_candidate_kind": source_kind,
            "_api_id": api_id,
        }
        if kind == "source accessor":
            row["notes"] += "; accessor is linked to a source property and is not a separate callable API"
        if is_internal_abi:
            row["notes"] += "; source visibility is non-public; retained because the pinned KLIB/JVM dump exposes implementation ABI"
        if defaults:
            row["notes"] += "; default expressions are preserved in the pinned source snapshot"
        rows.append(row)
        pending_target = "common"
    return rows


def parse_jvm_api(path: Path, module: str, sources: list[Path]) -> list[dict]:
    rows = []
    current_class = ""
    class_method_names: dict[str, set[str]] = defaultdict(set)
    parsed: list[dict] = []
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        text = raw.strip()
        if not text:
            current_class = ""
            continue
        if text == "}":
            current_class = ""
            continue
        if not text.startswith("public "):
            continue
        if " class " in text or " interface " in text:
            if "annotation class " in text:
                match = re.search(r"\bannotation\s+class\s+([^\s:{]+)", text)
                kind = "annotation class"
            elif " interface class " in text:
                match = re.search(r"\binterface\s+class\s+([^\s:{]+)", text)
                kind = "interface"
            elif "interface " in text:
                match = re.search(r"\binterface\s+([^\s:{]+)", text)
                kind = "interface"
            else:
                match = re.search(r"\bclass\s+([^\s:{]+)", text)
                kind = "class"
            if match:
                current_class = match.group(1).strip()
                generated_class = ""
                if kind == "class" and current_class.endswith("Kt"):
                    generated_class = "JVM file facade"
                elif kind == "class" and "$Companion" in current_class:
                    generated_class = "JVM companion ABI class"
                parsed.append(
                    {
                        "line": line_number,
                        "signature": text,
                        "class": current_class,
                        "name": current_class.rsplit("/", 1)[-1],
                        "kind": generated_class or kind,
                    }
                )
            continue
        if " fun " in text:
            method = re.search(r"\bfun\s+([^\s(]+)", text)
            if not method:
                continue
            name = method.group(1)
            class_method_names[current_class].add(name)
            parsed.append(
                {
                    "line": line_number,
                    "signature": text,
                    "class": current_class,
                    "name": name,
                    "kind": "constructor" if name == "<init>" else "function",
                }
            )
        elif " field " in text:
            field = re.search(r"\bfield\s+([^\s]+)", text)
            if field:
                parsed.append(
                    {
                        "line": line_number,
                        "signature": text,
                        "class": current_class,
                        "name": field.group(1),
                        "kind": "field",
                    }
                )

    # Recognize Java property accessors from Kotlin source properties rather than
    # treating every JavaBean-looking function as a generated getter.
    property_names = set()
    for source in sources:
        rel = source.relative_to(UPSTREAM).as_posix()
        if rel.split("/", 1)[0] != module:
            continue
        for number, line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
            match = re.match(
                rf"^\s*(?:(?:{MODIFIERS})\s+)*(?:val|var)\s+"
                r"(?:[\w.`<>?, ]+\.)?`?([A-Za-z_][\w]*)`?\b",
                line,
            )
            if match:
                property_names.add(match.group(1))

    for entry in parsed:
        name = entry["name"]
        kind = entry["kind"]
        generated = "source"
        candidate_name = name
        source_api = "yes"
        jvm_name_source = jvm_name_mapping(sources, module, name) if kind == "function" else ""
        if kind in {"JVM file facade", "JVM companion ABI class"}:
            generated = kind
            source_api = "no"
            candidate_name = ""
        elif kind == "field":
            generated = "JVM field ABI"
            source_api = "no"
            candidate_name = name
        elif kind == "function":
            if jvm_name_source:
                generated = "Kotlin source function with @JvmName"
                candidate_name = jvm_name_source
            elif name in {"getHead", "getTail", "getPos", "getLimit", "getSizeMut", "getPrev", "getNext", "setHead", "setTail", "setPos", "setLimit", "setSizeMut", "setPrev", "setNext"}:
                generated = "published internal accessor"
                source_api = "no"
                candidate_name = re.sub(r"^(?:get|set)", "", name)
                candidate_name = candidate_name[:1].lower() + candidate_name[1:]
            elif name.startswith(("get", "is", "set")):
                property_candidate = (
                    name[3:4].lower() + name[4:]
                    if name.startswith("get") or name.startswith("set")
                    else name
                )
                capitalized_property = (
                    name[3:]
                    if name.startswith(("get", "set"))
                    else name
                )
                if property_candidate in property_names:
                    generated = "Kotlin property getter/setter"
                    source_api = "no"
                    candidate_name = property_candidate
                elif capitalized_property in property_names:
                    generated = "Kotlin property getter/setter"
                    source_api = "no"
                    candidate_name = capitalized_property
                elif "$default" in name or " synthetic " in entry["signature"]:
                    generated = "default/synthetic bridge"
                    source_api = "no"
                    candidate_name = name.split("$default", 1)[0]
                elif name.endswith("-" + name.split("-", 1)[-1]) and "-" in name:
                    generated = "JVM-mangled source function"
                    candidate_name = name.split("-", 1)[0]
            elif "$default" in name or " synthetic " in entry["signature"]:
                generated = "default/synthetic bridge"
                source_api = "no"
                candidate_name = name.split("$default", 1)[0]
            elif name.endswith("-" + name.split("-", 1)[-1]) and "-" in name:
                generated = "JVM-mangled source function"
                candidate_name = name.split("-", 1)[0]
            if name.startswith("get") and name[3:] == "Indices":
                generated = "Kotlin property getter"
                source_api = "no"
                candidate_name = "indices"
            if "Ljava/lang/Object;" in entry["signature"] and any(
                other["class"] == entry["class"]
                and other["name"] == name
                and "Ljava/lang/Object;" not in other["signature"]
                for other in parsed
            ):
                generated = "JVM bridge method"
                source_api = "no"
        elif kind == "constructor" and "synthetic" in entry["signature"]:
            generated = "default/synthetic constructor"
            source_api = "no"
            candidate_name = entry["class"].rsplit("/", 1)[-1]

        if kind in {"class", "interface", "annotation class"}:
            candidate_kind = kind
            source_name = entry["name"]
        elif kind in {"JVM file facade", "JVM companion ABI class"}:
            candidate_kind = ""
            source_name = ""
        elif kind == "field":
            if candidate_name == "Companion":
                candidate_kind = "object"
                source_name = "Companion"
            elif candidate_name == "INSTANCE":
                candidate_kind = "object"
                source_name = entry["class"].rsplit("/", 1)[-1]
            else:
                candidate_kind = "property"
                source_name = candidate_name
        elif kind == "constructor":
            candidate_kind = "class"
            source_name = candidate_name if candidate_name != "<init>" else entry["class"].rsplit("/", 1)[-1]
        elif generated in {"Kotlin property getter/setter", "Kotlin property getter", "published internal accessor"}:
            candidate_kind = "property"
            source_name = candidate_name
        else:
            candidate_kind = "function"
            source_name = candidate_name
        matching = []
        for source in sources:
            rel = source.relative_to(UPSTREAM).as_posix()
            if rel.split("/", 1)[0] != module:
                continue
            for number, declaration in declaration_lines(source, candidate_kind, source_name):
                matching.append((source, number, declaration))
        owner_matches = [
            item for item in matching if source_matches_jvm_owner(item[0], entry["class"])
        ]
        if owner_matches:
            matching = owner_matches
        if kind == "constructor":
            constructor_matches = []
            class_name = entry["class"].rsplit("/", 1)[-1]
            for source in dict.fromkeys(item[0] for item in matching):
                constructor_matches.extend(
                    (source, number, declaration)
                    for number, declaration in source_constructor_lines(source, class_name)
                )
            if constructor_matches:
                matching = constructor_matches
        matching.sort(
            key=lambda item: 0
            if ("/jvm/src/" in item[0].as_posix() or "/common/src/" in item[0].as_posix())
            else 1
        )
        annotations, deprecated, exception_contract, source_line = (
            metadata_for(matching[0][0], matching[0][1])
            if matching
            else ("none", "none", "not-declared-in-source", "")
        )
        api_kind = kind if generated == "source" else generated
        row = {
            "row_id": "jvm-" + stable_id(module, entry["class"], entry["signature"]),
            "module": module,
            "representation": "JVM public ABI dump",
            "platform_scope": "JVM",
            "api_kind": api_kind,
            "source_api": source_api,
            "owner_fqn": entry["class"] or module,
            "name": name,
            "signature": entry["signature"],
            "default_parameter_count": "n/a",
            "annotations": annotations,
            "deprecation": deprecated,
            "exception_contract": exception_contract,
            "upstream_source_refs": ";".join(
                f"{source.relative_to(UPSTREAM).as_posix()}:{number}"
                for source, number, _ in matching
            )
            or "source declaration not found by name",
            "jvm_abi_refs": "",
            "upstream_test_refs": "",
            "local_candidate_refs": "",
            "local_test_refs": "",
            "status": "unverified",
            "owner_issue": "KUU-1725",
            "scope_decision": "in-scope JVM ABI and Java interoperability",
            "notes": f"JVM entry class line {entry['line']}; source line: {source_line}; generated kind: {generated}",
            "_source_paths": [source for source, _, _ in matching],
            "_candidate_name": source_name,
            "_candidate_kind": candidate_kind,
            "_api_id": f"{entry['class']}.{name}",
            "_jvm_key": (module, entry["class"],
                (re.search(r"\b(?:fun|field)\s+(\S+)", entry["signature"]).group(1) if kind in {"function", "constructor", "field"} else "<class>"),
                (re.search(r"\b(?:fun|field)\s+\S+\s+(\S+)", entry["signature"]).group(1) if kind in {"function", "constructor", "field"} else "")),
        }
        rows.append(row)
    return rows


def owner_for(row: dict) -> str:
    if row.get("_jvm_key") in INDEX_OF_DEFAULT_BRIDGES:
        return "KUU-2618"
    text = " ".join(
        [row["module"], row["owner_fqn"], row["name"], row["signature"], row["upstream_source_refs"]]
    ).lower()
    if row["platform_scope"] == "apple-only" or "platform.foundation" in text:
        return "KUU-1763"
    key = repr(row.get("_source_key", "")).lower()
    if row["representation"] == "Kotlin platform typealias" or "java." in key or (row["representation"] == "JVM public ABI dump" and "_source_key" not in row):
        return "KUU-1762"
    if "kotlinx.io.files" in text.replace("/", "."):
        return "KUU-1761"
    if row["module"] == "bytestring":
        return "KUU-1760"
    if any(x in text for x in ("utf8", "readline", "readcodepoint", "writecodepoint")):
        return "KUU-1733"
    if any(x in text for x in ("buffer", "segment", "snapshot", "indexof")):
        return "KUU-1729"
    if any(x in text for x in ("rawsource", "rawsink", "peek", "buffered", "close", "flush", "emit")):
        return "KUU-1730"
    if any(
        x in text
        for x in (
            "readbyte",
            "readshort",
            "readint",
            "readlong",
            "readfloat",
            "readdouble",
            "readdecimal",
            "readhexadecimal",
            "readubyte",
            "readuint",
            "readulong",
            "readushort",
            "readbytearray",
            "readatmostto",
            "readto(",
            "writebyte",
            "writeshort",
            "writeint",
            "writelong",
            "writefloat",
            "writedouble",
            "writedecimal",
            "writehexadecimal",
            "writeubyte",
            "writeuint",
            "writeulong",
            "writeushort",
        )
    ):
        return "KUU-1731"
    return "KUU-1730"


def apply_index_of_default_bridge_mappings(rows: list[dict], index: SourceIndex) -> None:
    """Map generated indexOf bridges to the exact defaulted Kotlin overloads."""
    source_path = "bytestring/common/src/ByteString.kt"
    local_path = "Sources/CompilerCore/Stdlib/kotlinx/io/bytestring/ByteString.kt"
    for row in rows:
        spec = INDEX_OF_DEFAULT_BRIDGES.get(row.get("_jvm_key"))
        if spec is None:
            continue
        if row.get("row_id") != spec["row_id"]:
            fail(f"ByteString.indexOf bridge row identity changed: {row.get('row_id')}")
        source_key = (
            "function",
            "kotlinx.io.bytestring.indexOf",
            "kotlinx.io.bytestring.ByteString",
            (spec["needle_type"], "kotlin.Int"),
        )
        upstream = index.match("upstream", source_key)
        local = index.match("local", source_key)
        if len(upstream) != 1 or len(local) != 1:
            fail(
                f"expected one upstream and local indexOf declaration for {row['row_id']}"
            )
        upstream_declaration = upstream[0]
        local_declaration = local[0]
        expected_parameters = [
            (spec["source_parameter"], spec["needle_type"].rsplit(".", 1)[-1], None),
            ("startIndex", "Int", "0"),
        ]
        for origin, declaration, expected_path, expected_line in (
            ("upstream", upstream_declaration, source_path, spec["upstream_source_line"]),
            ("local", local_declaration, local_path, spec["local_source_line"]),
        ):
            actual_parameters = [
                (parameter["name"], parameter["type"], parameter["default"])
                for parameter in declaration["parameters"]
            ]
            if (
                declaration["path"] != expected_path
                or declaration["line"] != expected_line
                or declaration["visibility"] != "public"
                or declaration["receiver"] != "ByteString"
                or declaration["returnType"] != "Int"
                or not declaration["hasBody"]
                or declaration["annotations"]
                or actual_parameters != expected_parameters
            ):
                fail(f"unexpected {origin} indexOf source contract for {row['row_id']}")
        row["_source_key"] = source_key
        row["_source_declarations"] = [upstream_declaration]
        row["_source_paths"] = [UPSTREAM / source_path]
        row["_typed_local_refs"] = [f"{local_path}:{spec['local_source_line']}"]
        row["_candidate_kind"] = "function"
        row["_candidate_name"] = "indexOf"
        row["upstream_source_refs"] = f"{source_path}:{spec['upstream_source_line']}"
        row["jvm_abi_refs"] = (
            "bytestring/api/kotlinx-io-bytestring.api:" + str(spec["api_line"])
        )
        row["annotations"], row["deprecation"], row["exception_contract"] = (
            declaration_metadata(upstream_declaration)
        )
        row["notes"] = (
            f"Generated JVM default bridge maps to {source_path}:{spec['upstream_source_line']} "
            f"and {local_path}:{spec['local_source_line']}; source contract is public, "
            f"JVM API dump entry is bytestring/api/kotlinx-io-bytestring.api:{spec['api_line']}; "
            "startIndex defaults to 0, and no opt-in, deprecation, or throws annotation is "
            "declared. The fixed JVM artifact probe verifies the reference classfile shape; "
            "Candidate native default-dispatch execution is tracked separately and does "
            "not establish candidate JVM classfile ABI."
        )


def local_candidates(row: dict) -> list[str]:
    if "_typed_local_refs" in row:
        return row["_typed_local_refs"]
    name = row["_candidate_name"]
    kind = row["_candidate_kind"]
    if not name or name.startswith("<"):
        return []
    local_root = REPO / "Sources/CompilerCore/Stdlib/kotlinx/io"
    matches = []
    for path in sorted(local_root.rglob("*.kt")):
        found = declaration_lines(path, kind, name)
        for line_number, _ in found:
            matches.append(f"{path.relative_to(REPO).as_posix()}:{line_number}")
    return matches


def declaration_metadata(declaration: dict) -> tuple[str, str, str]:
    entries = declaration["annotations"]
    annotations = ",".join(sorted({entry["name"] for entry in entries if entry["name"]})) or "none"
    deprecated = "none"
    exceptions = []
    for entry in entries:
        name = (entry["name"] or "").rsplit(".", 1)[-1]
        if name == "Deprecated":
            arguments = entry["arguments"]
            level = next((argument["expression"].rsplit(".", 1)[-1] for argument in arguments if argument["name"] == "level"), "WARNING")
            message = next((argument["expression"] for argument in arguments if argument["name"] == "message"), arguments[0]["expression"] if arguments else "")
            deprecated = level + (": " + message if message else "")
        if name == "Throws":
            exceptions.append(entry["source"])
    doc = declaration["doc"] or ""
    exceptions.extend("@throws " + clean(" ".join(thrown)) for thrown in re.findall(r"@throws\s+([\w.]+)([^\n]*)", doc))
    return annotations, deprecated, "; ".join(dict.fromkeys(exceptions)) or "not-declared-in-source"


def attach_platform_metadata(row: dict, declarations: list[dict]) -> None:
    details = []
    names = set()
    for declaration in declarations:
        annotations, deprecation, exceptions = declaration_metadata(declaration)
        names.update(annotations.split(",") if annotations != "none" else [])
        details.append({
            "reference": "%s:%d" % (declaration["path"], declaration["line"]),
            "visibility": declaration["visibility"], "annotations": declaration["annotations"],
            "deprecation": deprecation, "exceptionContract": exceptions,
            "defaults": {parameter["name"]: parameter["default"] for parameter in declaration["parameters"] if parameter["default"] is not None},
        })
    row["platform_metadata"] = json.dumps(details, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    row["annotations"] = ",".join(sorted(names)) or ("none" if declarations else "unmapped")


def apply_typed_correspondence(rows: list[dict], index: SourceIndex) -> None:
    for row in rows:
        if "/ KLIB dump" not in row["representation"]:
            continue
        kind, _ = declaration_kind(row["signature"], row["_api_id"])
        key = api_key(row["_api_id"], kind)
        matching = index.match("upstream", key)
        matching = sorted(matching, key=lambda declaration: (
            0 if ("/apple/src/" in declaration["path"] if row["platform_scope"] == "apple-only" else "/common/src/" in declaration["path"]) else 1,
            declaration["path"], declaration["line"]
        ))
        row["_source_key"] = key
        row["_source_declarations"] = matching
        row["_accessor_role"] = "getter" if ".<get-" in row["_api_id"] else "setter" if ".<set-" in row["_api_id"] else None
        row["_typed_local_refs"] = sorted({
            "%s:%d" % (declaration["path"], declaration["line"])
            for declaration in index.match("local", key)
        })
        row["_source_paths"] = [UPSTREAM / declaration["path"] for declaration in matching]
        row["upstream_source_refs"] = ";".join("%s:%d" % (declaration["path"], declaration["line"]) for declaration in matching) or "unmapped: no exact source declaration"
        row["annotations"], row["deprecation"], row["exception_contract"] = declaration_metadata(matching[0]) if matching else ("unmapped", "unmapped", "unmapped")
        attach_platform_metadata(row, matching)
        visibility = matching[0]["visibility"] if matching else "unmapped"
        internal = visibility in {"internal", "private", "protected"}
        row["source_api"] = "no" if internal or kind == "source accessor" else "yes"
        row["api_kind"] = (visibility + " " if internal else "") + ("source-property-accessor" if kind == "source accessor" else kind)
        row["representation"] = "Internal implementation ABI / KLIB dump" if internal else "Kotlin source API / KLIB dump"
        row["notes"] = "KLIB declaration key: %s; exact owner/receiver/parameter source match; visibility: %s" % (row["_api_id"], visibility)
        if matching:
            row["notes"] += "; source declaration: " + matching[0]["signature"]
        if internal:
            row["scope_decision"] = "in-scope internal implementation ABI; not a public Kotlin source API"


def apply_jvm_correspondence(rows: list[dict], index: SourceIndex, lock: dict) -> None:
    path = HERE / "jvm-declarations.json"
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != lock["jvmDeclarationsSha256"]:
        fail("JVM declaration catalog lock mismatch")
    catalog = json.loads(data.decode("utf-8"))
    adapter = HERE / "ExtractJvmDeclarations.kt"
    if catalog["schemaVersion"] != 1 or hashlib.sha256(adapter.read_bytes()).hexdigest() != catalog["toolchain"]["jvmExtractorSha256"]:
        fail("JVM metadata adapter changed; refresh the declaration catalogs")
    expected = {artifact["url"].rsplit("/", 1)[-1]: artifact["sha256"] for artifact in lock["mavenArtifacts"]}
    if {jar["file"]: jar["sha256"] for jar in catalog["jars"]} != expected:
        fail("JVM metadata catalog does not match the pinned artifact hashes")
    declarations = {}
    for declaration in catalog["declarations"]:
        key = (declaration["module"], declaration["jvmOwner"], declaration["jvmName"], declaration["descriptor"])
        if key in declarations:
            fail("duplicate JVM metadata signature: " + repr(key))
        declarations[key] = declaration
    for row in rows:
        if row["representation"] != "JVM public ABI dump":
            continue
        declaration = declarations.get(row["_jvm_key"])
        if declaration is None:
            row["_typed_local_refs"] = []
            row["_source_paths"] = []
            row["upstream_source_refs"] = "no direct Kotlin metadata declaration (generated ABI)"
            row["annotations"], row["deprecation"], row["exception_contract"] = "n/a", "n/a", "n/a"
            row["notes"] = "JVM ABI signature: " + repr(row["_jvm_key"]) + "; no direct Kotlin metadata declaration"
            if row["source_api"] == "yes":
                row["source_api"] = "no"
                row["api_kind"] = "JVM ABI without direct Kotlin metadata declaration"
            continue
        key = (declaration["kind"], declaration["fqName"], declaration["receiver"], tuple(declaration["parameters"]))
        row["_source_key"] = key
        matching = sorted(index.match("upstream", key), key=lambda entry: (
            0 if "/common/src/" in entry["path"] else 1 if "/jvm/src/" in entry["path"] else 2,
            entry["path"], entry["line"]
        ))
        row["_source_declarations"] = matching
        row["_accessor_role"] = ("field" if row["api_kind"] == "JVM field ABI" else "setter" if declaration["descriptor"].endswith("V") else "getter") if declaration["kind"] == "property" else None
        row["_source_paths"] = [UPSTREAM / entry["path"] for entry in matching]
        row["upstream_source_refs"] = ";".join("%s:%d" % (entry["path"], entry["line"]) for entry in matching) or "unmapped: no exact Kotlin source declaration"
        row["_typed_local_refs"] = sorted({"%s:%d" % (entry["path"], entry["line"]) for entry in index.match("local", key)})
        row["_candidate_kind"], row["_candidate_name"] = declaration["kind"], declaration["fqName"].rsplit(".", 1)[-1]
        row["annotations"], row["deprecation"], row["exception_contract"] = declaration_metadata(matching[0]) if matching else ("unmapped", "unmapped", "unmapped")
        attach_platform_metadata(row, matching)
        internal = declaration["visibility"] not in {"public", "protected"}
        if declaration["kind"] == "property":
            row["api_kind"] = "JVM field ABI" if row["api_kind"] == "JVM field ABI" else "published internal accessor" if internal else "Kotlin property getter/setter"
            row["source_api"] = "no"
        elif internal:
            row["api_kind"] = declaration["visibility"] + " " + declaration["kind"]
            row["source_api"] = "no"
        elif row["api_kind"] not in {"JVM companion ABI class", "JVM file facade", "JVM field ABI"}:
            row["api_kind"] = declaration["kind"]
            row["source_api"] = "yes"
        row["default_parameter_count"] = str(sum(declaration["defaults"]))
        row["notes"] = "Exact Kotlin metadata JVM signature: " + repr(row["_jvm_key"]) + "; Kotlin source key: " + repr(key) + "; visibility: " + declaration["visibility"]


def typed_published_internals(index: SourceIndex) -> list[dict]:
    rows = []
    for declaration in index.declarations:
        if declaration["origin"] != "upstream" or declaration["visibility"] != "internal":
            continue
        if not any((annotation["name"] or "").rsplit(".", 1)[-1] == "PublishedApi" for annotation in declaration["annotations"]):
            continue
        annotations, deprecated, exceptions = declaration_metadata(declaration)
        key = declaration["_key"]
        reference = "%s:%d" % (declaration["path"], declaration["line"])
        rows.append({
            "row_id": "internal-" + stable_id(reference, repr(key)),
            "module": declaration["path"].split("/", 1)[0],
            "representation": "@PublishedApi internal source declaration",
            "platform_scope": source_platform(declaration["path"]),
            "api_kind": "internal-" + declaration["kind"], "source_api": "no",
            "owner_fqn": declaration["owner"], "name": declaration["name"],
            "signature": declaration["signature"],
            "default_parameter_count": str(sum(parameter["default"] is not None for parameter in declaration["parameters"])),
            "annotations": annotations, "deprecation": deprecated, "exception_contract": exceptions,
            "upstream_source_refs": reference, "jvm_abi_refs": "", "upstream_test_refs": "",
            "local_candidate_refs": "", "local_test_refs": "", "status": "unverified",
            "owner_issue": "KUU-1725", "scope_decision": "in-scope internal implementation ABI",
            "notes": "PSI declaration identity: " + repr(key),
            "_source_key": key, "_api_id": "internal:" + reference,
            "_source_declarations": [declaration],
            "_source_paths": [UPSTREAM / declaration["path"]],
            "_candidate_name": declaration["name"], "_candidate_kind": declaration["kind"],
            "_typed_local_refs": sorted({"%s:%d" % (local["path"], local["line"]) for local in index.match("local", key)}),
        })
    return rows


def platform_typealiases(index: SourceIndex) -> list[dict]:
    rows = []
    for declaration in index.declarations:
        if declaration["origin"] != "upstream" or declaration["kind"] != "typealias" or declaration["visibility"] != "public":
            continue
        key = declaration["_key"]
        reference = "%s:%d" % (declaration["path"], declaration["line"])
        row = {
            "row_id": "alias-" + stable_id(reference, declaration["fqName"]),
            "module": declaration["path"].split("/", 1)[0],
            "representation": "Kotlin platform typealias", "platform_scope": source_platform(declaration["path"]),
            "api_kind": "typealias", "source_api": "yes", "owner_fqn": declaration["owner"],
            "name": declaration["name"], "signature": "typealias " + declaration["fqName"] + " = " + declaration["aliasTarget"],
            "default_parameter_count": "0", "annotations": "none", "deprecation": "none", "exception_contract": "not-declared-in-source",
            "upstream_source_refs": reference, "jvm_abi_refs": "", "upstream_test_refs": "", "local_test_refs": "",
            "status": "unverified", "owner_issue": "KUU-1762", "scope_decision": "in-scope JVM exception typealias; no separate generated JVM class",
            "notes": "Actual typealias representation retained separately from the common/native class API",
            "_source_key": key, "_source_declarations": [declaration], "_api_id": "alias:" + reference,
            "_source_paths": [UPSTREAM / declaration["path"]], "_candidate_name": declaration["name"], "_candidate_kind": "typealias",
            "_typed_local_refs": sorted({"%s:%d" % (local["path"], local["line"]) for local in index.match("local", key)}),
        }
        attach_platform_metadata(row, [declaration])
        rows.append(row)
    return rows


def local_contract_differences(row: dict, index: SourceIndex) -> str:
    declarations = row.get("_source_declarations", [])
    key = row.get("_source_key")
    if not declarations or key is None:
        return "not-applicable"
    local = index.match("local", key)
    if not local:
        return "missing exact local declaration"
    expected = declarations[0]
    differences = []
    for candidate in local:
        mismatches = []
        for upstream, parameter in zip(expected["parameters"], candidate["parameters"]):
            if upstream["name"] != parameter["name"]:
                mismatches.append("parameter name: %s vs %s" % (upstream["name"], parameter["name"]))
            if (upstream["default"] is None) != (parameter["default"] is None):
                mismatches.append("default presence: %s upstream=%s local=%s" % (upstream["name"], upstream["default"] is not None, parameter["default"] is not None))
        if expected["visibility"] != candidate["visibility"]:
            mismatches.append("visibility: %s vs %s" % (expected["visibility"], candidate["visibility"]))
        if mismatches:
            differences.append({"reference": "%s:%d" % (candidate["path"], candidate["line"]), "differences": mismatches})
    return json.dumps(differences, sort_keys=True, separators=(",", ":")) if differences else "none detected (semantics unverified)"


def local_test_refs(row: dict, local_tests: list[tuple[str, str]]) -> list[str]:
    if row.get("_jvm_key") in INDEX_OF_DEFAULT_BRIDGES:
        return list(INDEX_OF_DEFAULT_BRIDGE_TEST_INPUTS)
    name = row["_candidate_name"].lower()
    owner = row["owner_fqn"].rsplit("/", 1)[-1].lower()
    refs = []
    for path, content in local_tests:
        if path.startswith("Scripts/io_api_inventory/probes/") and name not in LOCAL_IO_PROBE_API_NAMES:
            continue
        if (path == SEGMENT_READ_CONTEXT_IMPL_LOCAL_TESTS[0]
                or path.startswith(SEGMENT_READ_CONTEXT_IMPL_LOCAL_TESTS[1])):
            if row["row_id"] not in SEGMENT_READ_CONTEXT_IMPL_ROW_IDS:
                continue
        haystack = content.lower()
        if name and re.search(rf"(?<!\w){re.escape(name)}(?!\w)", haystack):
            refs.append(path)
        elif owner and owner in haystack and row["module"] == "bytestring":
            refs.append(path)
    return list(dict.fromkeys(refs))


def local_implementation_refs(row: dict, index: SourceIndex, runtime_symbols: dict) -> list[str]:
    key = row.get("_source_key")
    if key is None:
        return []
    references = []
    for declaration in index.match("local", key):
        if declaration["hasBody"]:
            references.append("%s:%d" % (declaration["path"], declaration["line"]))
        for annotation in declaration["annotations"]:
            if (annotation["name"] or "").rsplit(".", 1)[-1] != "KsSymbolName":
                continue
            for argument in annotation["arguments"]:
                name = argument["expression"].strip('"')
                references.extend(runtime_symbols.get(name, []))
    return sorted(set(references))


def upstream_test_refs(row: dict, test_index: dict) -> list[str]:
    indexof_bridge = INDEX_OF_DEFAULT_BRIDGES.get(row.get("_jvm_key"))
    if indexof_bridge is not None:
        path = "bytestring/common/test/ByteStringTest.kt"
        entry = next((item for item in test_index["files"] if item["path"] == path), None)
        case_name = indexof_bridge["case_name"]
        if entry is None or case_name not in entry.get("testNames", []):
            fail(f"locked upstream test is missing for ByteString.indexOf bridge: {case_name}")
        return [f"{path}#{case_name}"]
    if row.get("upstream_source_refs") in NO_DIRECT_UPSTREAM_ASSERTION_SOURCE_REFS:
        # The upstream smoke cases use SystemFileSystem raw methods; they do not
        # exercise these deprecated Path extensions or assert their annotations.
        return []
    source_paths = row.get("_source_paths", [])
    hints = []
    for source in source_paths:
        hints.extend(TEST_HINTS.get(source.name, []))
    if not hints:
        if row["module"] == "bytestring":
            hints = ["bytestring/common/test/ByteStringTest.kt"]
        elif "files/" in row["owner_fqn"]:
            hints = ["core/common/test/files/SmokeFileTest.kt"]
        else:
            hints = ["core/common/test/AbstractSourceTest.kt", "core/common/test/AbstractSinkTest.kt"]
    index_by_path = {entry["path"]: entry for entry in test_index["files"]}
    name = row["_candidate_name"].lower()
    refs = []
    for hint in dict.fromkeys(hints):
        entry = index_by_path.get(hint)
        if not entry:
            continue
        matched = [test for test in entry.get("testNames", []) if name and name in test.lower()]
        if matched:
            refs.extend(f"{hint}#{test}" for test in matched)
        else:
            refs.append(f"{hint}#suite-reference")
    return refs


def pair_rows(rows: list[dict]) -> None:
    source_rows = [row for row in rows if "/ KLIB dump" in row["representation"]]
    binary_rows = [row for row in rows if row["representation"] == "JVM public ABI dump"]
    for group, opposite in ((source_rows, binary_rows), (binary_rows, source_rows)):
        by_key = defaultdict(list)
        for row in opposite:
            if "_source_key" in row:
                by_key[row["_source_key"]].append(row["row_id"])
        for row in group:
            key = row.get("_source_key")
            role = row.get("_accessor_role")
            row["jvm_abi_refs"] = ";".join(sorted(
                other["row_id"] for other in opposite if key is not None and other.get("_source_key") == key
                and (role is None or other.get("_accessor_role") is None or role == other["_accessor_role"])
            ))


def parse_published_internals(sources: list[Path]) -> list[dict]:
    rows = []
    annotation = re.compile(r"^\s*@PublishedApi\s*$")
    for path in sources:
        lines = path.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            if not annotation.match(line):
                continue
            following = "\n".join(lines[index + 1 : index + 5])
            declaration = re.search(
                rf"^\s*internal\s+(?:inline\s+|operator\s+|suspend\s+|open\s+|override\s+)*"
                r"(fun|val|var|class|object)\s+([A-Za-z_][\w]*)",
                following,
                re.MULTILINE,
            )
            if not declaration:
                continue
            kind, name = declaration.group(1), declaration.group(2)
            row = {
                "row_id": "internal-" + stable_id(path.relative_to(UPSTREAM).as_posix(), str(index + 2), name),
                "module": path.relative_to(UPSTREAM).parts[0],
                "representation": "@PublishedApi internal source declaration",
                "platform_scope": source_platform(path.relative_to(UPSTREAM).as_posix()),
                "api_kind": f"internal-{kind}",
                "source_api": "no",
                "owner_fqn": path.relative_to(UPSTREAM).as_posix(),
                "name": name,
                "signature": clean(declaration.group(0)),
                "default_parameter_count": "see source",
                "annotations": "PublishedApi",
                "deprecation": "none",
                "exception_contract": "not-declared-in-source",
                "upstream_source_refs": f"{path.relative_to(UPSTREAM).as_posix()}:{index + 2}",
                "jvm_abi_refs": "",
                "upstream_test_refs": "",
                "local_candidate_refs": "",
                "local_test_refs": "",
                "status": "unverified",
                "owner_issue": "KUU-1725",
                "scope_decision": "in-scope implementation ABI; internal source visibility",
                "notes": "Tracked separately from public source API; @PublishedApi permits inline callers to depend on this ABI.",
                "_source_paths": [path],
                "_candidate_name": name,
                "_candidate_kind": "function" if kind == "fun" else "property",
                "_api_id": f"internal:{path.relative_to(UPSTREAM).as_posix()}:{index + 2}:{name}",
            }
            rows.append(row)
    return rows


def parse_platform_public_declarations(sources: list[Path], api_rows: list[dict], source_index: SourceIndex) -> list[dict]:
    results = []
    source_by_root = {root: [] for roots in PLATFORM_ROOTS.values() for root in roots}
    for source in sources:
        rel = source.relative_to(UPSTREAM).as_posix()
        for roots in PLATFORM_ROOTS.values():
            for root in roots:
                if rel.startswith(root + "/"):
                    source_by_root[root].append(source)
    for group, roots in PLATFORM_ROOTS.items():
        files = [path for root in roots for path in source_by_root[root]]
        public_count = 0
        for path in files:
            depth = 0
            in_block_comment = False
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                # Count only source declarations at file scope. Override members,
                # locals, and expressions must not inflate the platform-only API
                # inventory. API dumps remain authoritative for shared contracts.
                if depth == 0 and re.match(
                    r"^\s*(?:(?:public|actual|expect|internal|private|protected|inline|suspend|operator|tailrec|external|data|sealed|open|abstract|final|value|annotation|enum)\s+)*(?:fun|val|var|class|interface|object)\b",
                    line,
                ):
                    if not re.search(r"\b(?:actual|expect|internal|private|protected)\b", line):
                        public_count += 1

                # Strip comments and quoted strings before adjusting nesting so
                # braces in examples, URLs, and diagnostics do not affect scope.
                code = []
                index = 0
                while index < len(line):
                    if in_block_comment:
                        end = line.find("*/", index)
                        if end < 0:
                            index = len(line)
                        else:
                            in_block_comment = False
                            index = end + 2
                    elif line.startswith("//", index):
                        break
                    elif line.startswith("/*", index):
                        in_block_comment = True
                        index += 2
                    elif line[index] in {'"', "'"}:
                        quote = line[index]
                        index += 1
                        while index < len(line):
                            if line[index] == "\\":
                                index += 2
                            elif line[index] == quote:
                                index += 1
                                break
                            else:
                                index += 1
                        code.append(" ")
                    else:
                        code.append(line[index])
                        index += 1
                code_text = "".join(code)
                depth += code_text.count("{") - code_text.count("}")
                if depth < 0:
                    depth = 0
        file_paths = {path.relative_to(UPSTREAM).as_posix() for path in files}
        public_count = sum(
            declaration["origin"] == "upstream" and declaration["path"] in file_paths
            and declaration["visibility"] == "public" and not declaration["actual"] and not declaration["expect"]
            and declaration["owner"] == source_index.files[("upstream", declaration["path"])]["package"]
            for declaration in source_index.declarations
        )
        if group == "Native shared implementation":
            decision = "in-scope when implementing a common/native API"
            reason = "These actuals implement the shared Native contract; they do not create a new public API or justify target-out."
        elif group == "Apple source actuals":
            decision = "in-scope Apple implementation"
            reason = "Apple-specific API declarations are captured by the explicit Apple target markers in the KLIB API dumps; actual source files implement the in-scope Apple/common surface."
        else:
            decision = "target-out for declarations unique to this platform"
            reason = (
                "The macOS product surface is common/native/Apple plus JVM interop. "
                "Only declarations unique to this source set are excluded; shared common API rows remain in scope."
            )
        results.append(
            {
                "platform_group": group,
                "source_roots": ";".join(roots),
                "source_file_count": str(len(files)),
                "public_declaration_count": str(public_count),
                "api_dump_target_marker_count": "0" if group == "Native shared implementation" else "0",
                "decision": decision,
                "reason": reason,
            }
        )
    apple_api_rows = [row for row in api_rows if row["platform_scope"] == "apple-only"]
    results.append(
        {
            "platform_group": "Apple KLIB declarations",
            "source_roots": "core/api/kotlinx-io-core.klib.api;bytestring/api/kotlinx-io-bytestring.klib.api",
            "source_file_count": "2",
            "public_declaration_count": str(len(apple_api_rows)),
            "api_dump_target_marker_count": str(len(apple_api_rows)),
            "decision": "in-scope Apple API",
            "reason": "Each row is explicitly preceded by `// Targets: [apple]` in the immutable 0.9.1 KLIB API dump.",
        }
    )
    return results


def render_tsv(path: Path, columns: list[str], rows: list[dict]) -> str:
    from io import StringIO

    stream = StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=columns, delimiter="\t", lineterminator="\n")
    writer.writeheader()
    for row in rows:
        writer.writerow({column: clean(row.get(column, "")) for column in columns})
    return stream.getvalue()


def make_summary(lock: dict, rows: list[dict], scope_rows: list[dict]) -> str:
    counts = Counter((row["representation"], row["status"]) for row in rows)
    kinds = Counter(row["api_kind"] for row in rows)
    missing = [row for row in rows if row["status"] == "missing"]
    unverified = [row for row in rows if row["status"] == "unverified"]
    verified = [row for row in rows if row["status"] == "verified"]
    source_rows = [row for row in rows if row["representation"] == "Kotlin source API / KLIB dump"]
    klib_internal_rows = [row for row in rows if row["representation"] == "Internal implementation ABI / KLIB dump"]
    abi_rows = [row for row in rows if row["representation"] == "JVM public ABI dump"]
    generated = [row for row in abi_rows if row["source_api"] == "no"]
    internal_rows = [row for row in rows if row["representation"] == "@PublishedApi internal source declaration"]
    deprecation_counts = Counter(
        row["deprecation"].split(":", 1)[0]
        for row in rows
        if row["deprecation"] not in {"none", "n/a"}
    )
    exception_rows = [row for row in rows if row["exception_contract"] not in {"not-declared-in-source", "n/a"}]
    lines = [
        "# kotlinx-io 0.9.1 API inventory",
        "",
        f"Upstream: [`Kotlin/kotlinx-io@{lock['commit']}`](https://github.com/Kotlin/kotlinx-io/tree/{lock['commit']}) (tag `0.9.1`).",
        f"Kotlin compiler baseline: `{lock['kotlinCompilerVersion']}`.",
        "",
        "## Generated counts",
        "",
        f"- Kotlin/KLIB source declaration rows: **{len(source_rows)}**.",
        f"- JVM ABI dump rows: **{len(abi_rows)}**, including **{len(generated)}** generated/accessor rows kept separate from Kotlin source callables.",
        f"- KLIB rows backed by non-public implementation declarations: **{len(klib_internal_rows)}**; these are separate from public source APIs.",
        f"- `@PublishedApi internal` implementation ABI rows: **{len(internal_rows)}**.",
        f"- Rows marked missing because no exact owner/receiver/parameter local declaration was found: **{len(missing)}**.",
        f"- Rows with exact local declarations or generated ABI entries, without semantic verification: **{len(unverified)}**.",
        f"- Rows promoted by current passing reference/candidate evidence: **{len(verified)}**.",
        f"- Public JVM exception typealiases tracked separately: **{sum(row['representation'] == 'Kotlin platform typealias' for row in rows)}**.",
        f"- Source exception contracts documented with `@throws`/`@Throws`: **{len(exception_rows)}** rows.",
        "- Source deprecation levels found: "
        + (", ".join(f"{level}={count}" for level, count in sorted(deprecation_counts.items())) or "none"),
        "- `verified` is derived only from current, passing evidence records; declaration matching and status strings alone cannot promote a row.",
        "",
        "`api-inventory.tsv` includes the authoritative KLIB source declaration and the JVM ABI entries as separate representations. "
        "KLIB records whose source declaration is internal/private are retained in their own implementation-ABI representation. "
        "The API dump cannot prove implementation semantics; Kotlin PSI and JVM metadata establish declaration identity, with `unverified` for exact local declarations and `missing` when none exists. `local_contract_differences` preserves parameter/default/visibility differences and `local_implementation_refs` points to source bodies or declared runtime bridges.",
        "",
        "## Surface and exclusions",
        "",
        "- Common Kotlin APIs remain in scope even though the KLIB dump advertises JS, Wasm, Android Native, Linux, and MinGW targets. A common declaration is not target-out merely because those targets also compile it.",
        "- Entries carrying the upstream `// Targets: [apple]` marker are in-scope Apple APIs.",
        "- Every entry from the JVM ABI dump is kept in scope for Java/JVM interop, including `java.io`, `java.nio`, `Charset`, and ByteString bridges.",
        "- `platform-scope.tsv` records platform-specific source roots and the target-only decision. Native shared actuals remain in scope when they implement a common/native contract.",
        "- Platform source counts include only top-level non-actual declarations in the listed roots; KLIB/JVM API dumps remain authoritative for the exported surface.",
        "- The source API rows come from upstream API dumps; they do not synthesize Okio-only `ByteString.hex()`, `Buffer.snapshot(byteCount)`, or `select` APIs. The generator has explicit guards for these false positives.",
        "",
        "## Reproducibility",
        "",
        "The checked-in upstream snapshot is verified against both Git blob SHA-1 and SHA-256 from `upstream-lock.json`. The test catalog is pinned by Git blob SHA and file size at the same commit.",
        "The JVM artifacts are fixed by Maven coordinate and SHA-256 in the lock; use `python3 Scripts/io_api_inventory/generate.py --check --verify-jars /path/to/jars` with files named by artifact or `--download-jars` to check them.",
        "",
        "```sh",
        "python3 Scripts/io_api_inventory/generate.py --write",
        "python3 Scripts/io_api_inventory/generate.py --check",
        "python3 Scripts/io_api_inventory/generate.py --check --verify-jars /tmp",
        "```",
        "",
        "## Owner routing",
        "",
        "Rows route to KUU-1729 (Buffer/Segment), KUU-1730 (source/sink lifecycle and common helpers), KUU-1731 (primitive/ByteArray I/O), KUU-1733 (UTF-8), KUU-1760 (ByteString), KUU-1761 (Filesystem), KUU-1762 (JVM interop/ABI/typealiases), or KUU-1763 (Apple). All are children of KUU-1725; missing declarations stay in scope.",
        "",
        "## JVM ABI classification",
        "",
        f"Generated JVM-only entries are classified separately: `{sum(1 for r in abi_rows if r['api_kind'] in {'default/synthetic bridge', 'default/synthetic constructor'})}` default/synthetic entries, `{sum(1 for r in abi_rows if r['api_kind'] in {'Kotlin property getter/setter', 'Kotlin property getter', 'published internal accessor'})}` property/internal accessors, `{sum(1 for r in abi_rows if r['api_kind'] == 'JVM bridge method')}` bridge entries, `{sum(1 for r in abi_rows if r['api_kind'] == 'JVM file facade')}` file facades, `{sum(1 for r in abi_rows if r['api_kind'] == 'JVM companion ABI class')}` companion classes, and `{sum(1 for r in abi_rows if r['api_kind'] == 'JVM field ABI')}` fields.",
        "Getter/setter rows are marked as ABI accessors only when an upstream Kotlin property with the matching name exists; methods such as `getByteString` remain source callables.",
        "",
    ]
    return "\n".join(lines)


def check_negative_guards(rows: list[dict]) -> None:
    source_rows = [row for row in rows if row["representation"] == "Kotlin source API / KLIB dump"]
    names = {row["name"] for row in source_rows}
    signatures = [row["signature"] for row in source_rows]
    if "hex" in names:
        fail("Okio-only ByteString.hex() was added to the Kotlin source API rows")
    if any(row["name"] == "snapshot" and row["default_parameter_count"] != "0" for row in source_rows):
        fail("Okio-only Buffer.snapshot(byteCount) was added to the source API rows")
    if "select" in names or any(re.search(r"\bselect\s*\(", signature) for signature in signatures):
        fail("Okio-only select() was added to the Kotlin source API rows")
    if "snapshot" not in names:
        fail("the real kotlinx-io Buffer.snapshot() declaration is missing")
    if not any(row["name"] in {"hexToByteString", "toHexString"} for row in source_rows):
        fail("expected kotlinx-io hex conversion APIs were not found")


def verify_jars(lock: dict, directory: Path | None, download: bool) -> None:
    if directory is None and not download:
        return
    temp_dir = None
    if download:
        temp_dir = tempfile.TemporaryDirectory(prefix="kotlinx-io-091-")
        directory = Path(temp_dir.name)
    assert directory is not None
    for artifact in lock["mavenArtifacts"]:
        filename = artifact["url"].rsplit("/", 1)[-1]
        candidate_names = [filename, artifact["coordinate"].split(":")[1] + ".jar"]
        path = next((directory / name for name in candidate_names if (directory / name).is_file()), None)
        if path is None and download:
            path = directory / filename
            with urllib.request.urlopen(artifact["url"], timeout=30) as response:
                path.write_bytes(response.read())
        if path is None:
            fail(f"missing jar for {artifact['coordinate']} in {directory}")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != artifact["sha256"]:
            fail(f"jar SHA-256 mismatch for {artifact['coordinate']}: {digest}")
        print(f"OK {artifact['coordinate']} sha256={digest}")
    if temp_dir is not None:
        temp_dir.cleanup()


def build_outputs() -> tuple[dict, list[dict], list[dict]]:
    lock, test_index, files, _ = load_inputs()
    index = SourceIndex(HERE / "source-declarations.json", REPO, UPSTREAM)
    sources = source_paths(files)
    api_rows = []
    for module, path in (
        ("core", UPSTREAM / "core/api/kotlinx-io-core.klib.api"),
        ("bytestring", UPSTREAM / "bytestring/api/kotlinx-io-bytestring.klib.api"),
    ):
        api_rows.extend(parse_klib(path, module, sources))
    apply_typed_correspondence(api_rows, index)
    for module, path in (
        ("core", UPSTREAM / "core/api/kotlinx-io-core.api"),
        ("bytestring", UPSTREAM / "bytestring/api/kotlinx-io-bytestring.api"),
    ):
        api_rows.extend(parse_jvm_api(path, module, sources))
    api_rows.extend(typed_published_internals(index))
    api_rows.extend(platform_typealiases(index))
    apply_jvm_correspondence(api_rows, index, lock)
    apply_index_of_default_bridge_mappings(api_rows, index)

    local_tests = []
    local_paths = list(REPO.joinpath("Tests").rglob("*.swift"))
    local_paths.extend(REPO.joinpath("Tests/CompilerCoreTests/GoldenCases/Sema").glob("*.kt"))
    local_paths.extend(REPO.joinpath("Scripts/diff_cases").glob("*.kt"))
    local_paths.extend(REPO.joinpath("Scripts/io_api_inventory/probes").glob("*.kt"))
    local_paths.extend(REPO.joinpath("Tests/CompilerBackendTests/Fixtures/IOSegmentReadContextImpl2590").glob("*.kt"))
    local_paths.append(REPO / "Scripts/io_api_inventory/f02_consumers/SegmentReadContextAbiProbe.java")
    for path in sorted(local_paths):
        rel = path.relative_to(REPO).as_posix()
        if rel in {INDEX_OF_DEFAULT_BRIDGE_DIFF_CASE, INDEX_OF_DEFAULT_BRIDGE_LOCAL_TEST}:
            continue
        if rel.startswith(LOCAL_IO_TEST_PREFIXES):
            content = path.read_text(encoding="utf-8")
            if "kotlinx.io" in content or "KotlinxIO" in path.name or "KtorIO" in path.name:
                local_tests.append((rel, content))

    tests = {entry["path"]: entry for entry in test_index["files"]}
    runtime_symbols = defaultdict(list)
    for path in sorted((REPO / "Sources/Runtime").rglob("*.swift")):
        content = path.read_text(encoding="utf-8")
        for match in re.finditer(r'@_cdecl\("([^"]+)"\)', content):
            runtime_symbols[match.group(1)].append("%s:%d" % (path.relative_to(REPO).as_posix(), content[:match.start()].count("\n") + 1))
    for row in api_rows:
        candidates = local_candidates(row)
        row["local_candidate_refs"] = ";".join(candidates) or "none"
        row["local_implementation_refs"] = ";".join(local_implementation_refs(row, index, runtime_symbols)) or "none (interface/abstract/generated or no implementation mapped)"
        row["local_contract_differences"] = local_contract_differences(row, index)
        row["status"] = "unverified" if candidates else "missing"
        if row["representation"] == "JVM public ABI dump" and row["source_api"] == "no":
            row["status"] = "unverified"
            if row.get("_jvm_key") not in INDEX_OF_DEFAULT_BRIDGES:
                row["notes"] += "; generated JVM ABI presence cannot be established from Kotlin source-name matching alone"
        row["owner_issue"] = owner_for(row)
        direct_upstream_tests = upstream_test_refs(row, test_index)
        row["upstream_test_refs"] = ";".join(direct_upstream_tests) or NO_DIRECT_UPSTREAM_ASSERTION
        test_refs = local_test_refs(row, local_tests) + list(VALIDATION_PROBE_TEST_REFS.get(row["row_id"], ()))
        row["local_test_refs"] = ";".join(dict.fromkeys(test_refs)) or "none"
        if row["representation"] == "JVM public ABI dump":
            row["scope_decision"] = "in-scope JVM ABI and Java interoperability"
        for test_ref in row["upstream_test_refs"].split(";"):
            if test_ref == "none" or test_ref.startswith("none ("):
                continue
            test_path = test_ref.split("#", 1)[0]
            if test_path not in tests:
                fail(f"unlocked upstream test reference: {test_path}")

    for row in api_rows:
        row["_inventory_status"] = row["status"]

    pair_rows(api_rows)
    api_rows.sort(key=lambda row: (row["module"], row["representation"], row["row_id"]))
    apply_validation_evidence(api_rows, lock)
    check_negative_guards(api_rows)
    scope_rows = parse_platform_public_declarations(sources, api_rows, index)
    return lock, api_rows, scope_rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=False)
    mode.add_argument("--write", action="store_true", help="regenerate the TSV and summary files")
    mode.add_argument("--check", action="store_true", help="verify inputs and generated outputs")
    mode.add_argument("--show-input-hashes", metavar="ROW_ID", help="print current validation inputs for one ledger row")
    parser.add_argument("--verify-jars", type=Path, help="verify previously downloaded jars in this directory")
    parser.add_argument("--download-jars", action="store_true", help="download and verify the two pinned Maven Central jars")
    args = parser.parse_args()

    if args.show_input_hashes:
        if args.verify_jars or args.download_jars:
            parser.error("--show-input-hashes cannot be combined with jar verification")
        with LEDGER_PATH.open(encoding="utf-8", newline="") as stream:
            matches = [row for row in csv.DictReader(stream, delimiter="\t")
                       if row.get("row_id") == args.show_input_hashes]
        if len(matches) != 1:
            fail(f"expected exactly one ledger row with row_id {args.show_input_hashes!r}; found {len(matches)}")
        # Hidden JVM keys are reconstructed from the row identity because they
        # are intentionally not part of the TSV schema.
        restore_hidden_jvm_key(matches[0])
        hashes = validation_input_hashes(matches[0])
        lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
        print(json.dumps({
            "row_id": args.show_input_hashes,
            "reference_version": lock["tag"],
            "reference_commit": lock["commit"],
            "compatibility_obligations": validation_obligations(matches[0]),
            "required_execution_lanes": required_execution_lanes(validation_obligations(matches[0])),
            **hashes,
        }, indent=2))
        return 0

    if not args.write and not args.check:
        parser.error("choose exactly one of --write, --check, or --show-input-hashes")

    lock, rows, scope_rows = build_outputs()
    ledger_text = render_tsv(LEDGER_PATH, LEDGER_COLUMNS, rows)
    scope_text = render_tsv(SCOPE_PATH, SCOPE_COLUMNS, scope_rows)
    summary_text = make_summary(lock, rows, scope_rows)
    if args.write:
        # Write bytes to preserve the deterministic LF output on Python 3.9,
        # which is still the system interpreter on the supported macOS host.
        LEDGER_PATH.write_bytes(ledger_text.encode("utf-8"))
        SCOPE_PATH.write_bytes(scope_text.encode("utf-8"))
        SUMMARY_PATH.write_bytes(summary_text.encode("utf-8"))
        print(
            f"Wrote {len(rows)} API/ABI/internal rows, {len(scope_rows)} platform scope rows, "
            f"and {SUMMARY_PATH.relative_to(REPO)}."
        )
    else:
        for path, expected in (
            (LEDGER_PATH, ledger_text),
            (SCOPE_PATH, scope_text),
            (SUMMARY_PATH, summary_text),
        ):
            if not path.is_file() or path.read_text(encoding="utf-8") != expected:
                fail(f"generated output is stale: {path.relative_to(REPO)}; run with --write")
        print(f"OK deterministic inventory: {len(rows)} rows; {len(scope_rows)} scope rows.")
    verify_jars(lock, args.verify_jars, args.download_jars)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
