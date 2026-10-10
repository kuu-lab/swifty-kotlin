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
EXPECTED_TAG_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"

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
    "Scripts/diff_cases/kotlinx_io_",
    "Tests/CompilerBackendTests/Integration/BundledStdlibExecutionTests+ByteString",
    "Tests/CompilerBackendTests/Integration/BundledStdlibExecutionTests+KtorIOCoverage.swift",
    "Tests/CompilerCoreTests/GoldenCases/Sema/kotlinx_io_",
    "Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlinx_io_",
    "Tests/CompilerCoreTests/Sema/KotlinxIO",
    "Tests/RuntimeTests/RuntimeIoFileSystemTests.swift",
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
    name = row["_candidate_name"].lower()
    owner = row["owner_fqn"].rsplit("/", 1)[-1].lower()
    refs = []
    for path, content in local_tests:
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
        f"- Public JVM exception typealiases tracked separately: **{sum(row['representation'] == 'Kotlin platform typealias' for row in rows)}**.",
        f"- Source exception contracts documented with `@throws`/`@Throws`: **{len(exception_rows)}** rows.",
        "- Source deprecation levels found: "
        + (", ".join(f"{level}={count}" for level, count in sorted(deprecation_counts.items())) or "none"),
        "- No row is marked `verified` by this inventory generator; the test harness and behavior work own semantic verification.",
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

    local_tests = []
    local_paths = list(REPO.joinpath("Tests").rglob("*.swift"))
    local_paths.extend(REPO.joinpath("Tests/CompilerCoreTests/GoldenCases/Sema").glob("*.kt"))
    local_paths.extend(REPO.joinpath("Scripts/diff_cases").glob("*.kt"))
    for path in sorted(local_paths):
        rel = path.relative_to(REPO).as_posix()
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
            row["notes"] += "; generated JVM ABI presence cannot be established from Kotlin source-name matching alone"
        row["owner_issue"] = owner_for(row)
        row["upstream_test_refs"] = ";".join(upstream_test_refs(row, test_index)) or "no upstream test file mapped"
        row["local_test_refs"] = ";".join(local_test_refs(row, local_tests)) or "none"
        if row["representation"] == "JVM public ABI dump":
            row["scope_decision"] = "in-scope JVM ABI and Java interoperability"
        for test_ref in row["upstream_test_refs"].split(";"):
            test_path = test_ref.split("#", 1)[0]
            if test_path not in tests:
                fail(f"unlocked upstream test reference: {test_path}")

    pair_rows(api_rows)
    api_rows.sort(key=lambda row: (row["module"], row["representation"], row["row_id"]))
    check_negative_guards(api_rows)
    scope_rows = parse_platform_public_declarations(sources, api_rows, index)
    return lock, api_rows, scope_rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help="regenerate the TSV and summary files")
    mode.add_argument("--check", action="store_true", help="verify inputs and generated outputs")
    parser.add_argument("--verify-jars", type=Path, help="verify previously downloaded jars in this directory")
    parser.add_argument("--download-jars", action="store_true", help="download and verify the two pinned Maven Central jars")
    args = parser.parse_args()

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
