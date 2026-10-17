#!/usr/bin/env python3
"""Run KUU-2563's pinned JVM tests and the same bodies on the KSwiftK native bridge."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys

from run_jvm_reference import execute, sha256, verify_file
from run_candidate_subset import PREFIX, parse_events, tree_hash


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
SCOPE_PATH = HERE / "kuu-2563-scope.json"
LOCK_PATH = HERE / "reference-lock.json"
CATALOG_PATH = HERE / "jvm-executions.expected.json"
NATIVE_CATALOG_PATH = HERE / "native-executions.expected.json"
PROBE_PATH = HERE / "kuu-2563" / "ApiContractProbe.kt"
OBSERVATION_TOKEN = "KUU2563_OBS"
FACTORIES = {
    "kotlinx.io.BufferSourceTestJVM": "BUFFER",
    "kotlinx.io.RealBufferedSourceTestJVM": "REAL_BUFFERED_SOURCE",
    "kotlinx.io.OneByteAtATimeBufferedSourceTestJVM": "ONE_BYTE_AT_A_TIME_BUFFERED_SOURCE",
    "kotlinx.io.OneByteAtATimeBufferTestJVM": "ONE_BYTE_AT_A_TIME_BUFFER",
    "kotlinx.io.PeekBufferTestJVM": "PEEK_BUFFER",
    "kotlinx.io.PeekBufferedSourceTestJVM": "PEEK_BUFFERED_SOURCE",
}
GUARDED_METHODS = {
    "inputStreamForClosedSource",
    "inputStreamClosesSource",
    "inputStreamAvailableForClosedSource",
}
ASSERTION_CALL = re.compile(
    r"assertEquals\([^\n]*\)|assertByteArrayEquals\([^\n]*\)|assertTrue\([^\n]*\)|"
    r"assertFailsWith<[^>]+>\s*\{.*?\}", re.DOTALL
)
FRIEND_ACCESS_HELPER_SOURCE = '''package kotlinx.io

// Mirrors the friend-only helper used by the pinned SourceFactory test fixture.
internal fun minOf(a: Long, b: Long): Long = if (a <= b) a else b
'''
FRIEND_ACCESS_HELPER_DECLARATION = "internal fun minOf(a: Long, b: Long): Long = if (a <= b) a else b"


def json_write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def candidate_test_support_sources(port: Path, factory: Path, probe: Path,
                                   friend_helper: Path, use_source_stdlib: bool) -> list[str]:
    sources = [str(port), str(factory), str(probe)]
    if not use_source_stdlib:
        sources.append(str(friend_helper))
    return sources


def verify_friend_helper_declaration(package_root: Path) -> str:
    source_path = package_root / "Sources/CompilerCore/Stdlib/kotlinx/io/-Util.kt"
    source_lines = source_path.read_text(encoding="utf-8").splitlines()
    if FRIEND_ACCESS_HELPER_DECLARATION not in source_lines:
        raise ValueError("KLIB test helper differs from the pinned bundled stdlib helper")
    return sha256(source_path)


def extract_function(source: str, name: str) -> tuple[str, int, int]:
    match = re.search(r"^[ \t]*fun\s+" + re.escape(name) + r"\s*\(\s*\)\s*\{", source, re.MULTILINE)
    if not match:
        raise ValueError(f"missing locked parameterless source function: {name}")
    brace_start = source.find("{", match.start(), match.end())
    depth = 0
    for position in range(brace_start, len(source)):
        char = source[position]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end = position + 1
                while end < len(source) and source[end] in "\r\n":
                    end += 1
                snippet = source[match.start():end]
                start_line = source.count("\n", 0, match.start()) + 1
                end_line = source.count("\n", 0, position) + 1
                return snippet, start_line, end_line
    raise ValueError(f"unterminated function body: {name}")


def assertion_rows(source: str, method: str, function: str, start_line: int) -> list[dict]:
    rows = []
    for index, match in enumerate(ASSERTION_CALL.finditer(function), start=1):
        expression = match.group(0).strip()
        line_start = start_line + function.count("\n", 0, match.start())
        line_end = start_line + function.count("\n", 0, match.end() - 1)
        required = ["value"]
        if expression.startswith("assertFailsWith"):
            required = ["exception_type"]
        if not expression.startswith("assertFailsWith") and ("input.read(" in expression or "input.skip(" in expression):
            required.append("bytes_consumed")
        if method in {"inputStream", "inputStreamOffsetCount"} and re.search(r",\s*read\s*\)\s*$", expression):
            required.append("bytes_consumed")
        if method == "readNioBuffer":
            required = ["value", "byte_buffer_state"]
            if "byteCount" in expression:
                required.append("bytes_consumed")
        rows.append({
            "id": f"{method}:assertion-{index}",
            "source_path": "core/jvm/test/AbstractSourceTestJVM.kt",
            "line_start": line_start,
            "line_end": line_end,
            "expression": expression,
            "required_observations": list(dict.fromkeys(required)),
        })
    if method in GUARDED_METHODS:
        guard = re.search(r"if\s*\(source\s+is\s+kotlinx\.io\.Buffer\)\s*\{\s*return\s*}", function)
        if not guard:
            raise ValueError(f"missing original Buffer early-return guard in {method}")
        line_start = start_line + function.count("\n", 0, guard.start())
        line_end = start_line + function.count("\n", 0, guard.end() - 1)
        rows.insert(0, {
            "id": f"{method}:buffer-early-return",
            "source_path": "core/jvm/test/AbstractSourceTestJVM.kt",
            "line_start": line_start,
            "line_end": line_end,
            "expression": "if (source is kotlinx.io.Buffer) { return }",
            "required_observations": ["value"],
            "kind": "original conditional path, not a skipped execution",
        })
    if not rows:
        raise ValueError(f"no original assertion or guarded path found for {method}")
    return rows


def select_rows(catalog: list[dict], scope: dict) -> list[dict]:
    ids = set(scope["source_function_ids"])
    rows = [row for row in catalog if row.get("upstream_id") in ids]
    if len(rows) != scope["expected_jvm_execution_count"]:
        raise ValueError(f"scope selected {len(rows)} JVM IDs, expected {scope['expected_jvm_execution_count']}")
    if {row["upstream_id"] for row in rows} != ids:
        raise ValueError("fixed JVM catalog does not cover every scoped source function")
    if any(row.get("source_set") != "jvm" for row in rows):
        raise ValueError("KUU-2563 candidate mapping requires JVM catalog IDs")
    if any(row["concrete_class"] not in FACTORIES for row in rows):
        raise ValueError("unknown inherited factory class in selected JVM catalog")
    if len({row["execution_id"] for row in rows}) != len(rows):
        raise ValueError("duplicate execution ID in selected JVM catalog")
    return sorted(rows, key=lambda row: row["execution_id"])


def build_sources(upstream: Path, rows: list[dict], lock: dict, scope: dict, output: Path) -> dict:
    source_path = upstream / scope["source_path"]
    raw = source_path.read_bytes()
    text = raw.decode("utf-8")
    record = next(item for item in lock["upstream_files"] if item["path"] == scope["source_path"])
    verify_file(source_path, record)
    if hashlib.sha256(raw).hexdigest() != scope["source_sha256"]:
        raise ValueError("KUU-2563 source hash differs from its task scope")

    method_chunks = []
    mapped_assertions = {}
    for identifier in scope["source_function_ids"]:
        method = identifier.split("#", 1)[1]
        snippet, start_line, _ = extract_function(text, method)
        method_chunks.append(snippet)
        mapped_assertions[identifier] = assertion_rows(text, method, snippet, start_line)

    class_body = "\n".join(method_chunks)
    port = output / "Kuu2563OriginalSourceTests.kt"
    support = f'''{PREFIX.decode()}package kotlinx.io

import java.io.InputStream
import java.nio.Buffer
import java.nio.ByteBuffer

object Kuu2563Observation {{
    private var activeId: String = ""
    private var assertionCount: Int = 0

    fun begin(identifier: String, method: String) {{
        activeId = identifier
        assertionCount = 0
        println("{OBSERVATION_TOKEN}\\t" + activeId + "\\tBEGIN\\t" + method)
    }}

    fun equal(expected: Any?, actual: Any?) {{
        assertionCount += 1
        println("{OBSERVATION_TOKEN}\\t" + activeId + "\\tVALUE\\t" + wire(expected) + "\\t" + wire(actual))
    }}

    fun exception(actualType: String) {{
        assertionCount += 1
        println("{OBSERVATION_TOKEN}\\t" + activeId + "\\tEXCEPTION\\t" + actualType)
    }}

    fun boundsProbe(firstUnreadByte: Int) {{
        println("{OBSERVATION_TOKEN}\\t" + activeId + "\\tBOUNDS_PROBE\\t" + firstUnreadByte)
    }}

    fun finish(identifier: String, method: String, isBufferFactory: Boolean) {{
        val branch = if (method in setOf("inputStreamForClosedSource", "inputStreamClosesSource", "inputStreamAvailableForClosedSource") && isBufferFactory && assertionCount == 0) "buffer-early-return" else "assertions-executed"
        println("{OBSERVATION_TOKEN}\\t" + identifier + "\\tEND\\t" + assertionCount + "\\t" + branch)
    }}

    private fun wire(value: Any?): String = when (value) {{
        null -> "null"
        is String -> value.replace("\\\\", "\\\\\\\\").replace("\\t", "\\\\t").replace("\\n", "\\\\n")
        else -> value.toString()
    }}
}}

fun <T> assertEquals(expected: T, actual: T) {{
    Kuu2563Observation.equal(expected, actual)
    if (expected != actual) throw AssertionError("Expected $expected but was $actual")
}}

fun assertTrue(actual: Boolean) {{
    Kuu2563Observation.equal(true, actual)
    if (!actual) throw AssertionError("Expected true")
}}

inline fun <reified T : Throwable> assertFailsWith(block: () -> Unit): T {{
    try {{
        block()
    }} catch (failure: Throwable) {{
        if (failure is T) {{
            Kuu2563Observation.exception(T::class.qualifiedName ?: failure.toString())
            return failure
        }}
        throw AssertionError("Expected ${{T::class.qualifiedName}} but caught $failure")
    }}
    throw AssertionError("Expected ${{T::class.qualifiedName}} but no exception was thrown")
}}

fun assertByteArrayEquals(expectedUtf8: String, b: ByteArray) {{
    assertEquals(expectedUtf8, b.toString(Charsets.UTF_8))
}}

fun probeInvalidInputStreamRangeDoesNotConsume(factory: SourceFactory): Int {{
    val pipe = factory.pipe()
    pipe.sink.writeString("a")
    pipe.sink.emit()
    val input = pipe.source.asInputStream()
    var failed = false
    try {{
        input.read(ByteArray(1), 1, 1)
    }} catch (expected: IllegalArgumentException) {{
        failed = true
    }}
    if (!failed) throw AssertionError("invalid InputStream range did not throw IllegalArgumentException")
    val firstUnreadByte = input.read()
    if (firstUnreadByte != 'a'.code) throw AssertionError("invalid InputStream range consumed source data")
    return firstUnreadByte
}}

class Kuu2563OriginalSourceTest(private val factory: SourceFactory) {{
    private var sink: Sink
    private var source: Source

    init {{
        val pipe: SourceFactory.Pipe = factory.pipe()
        sink = pipe.sink
        source = pipe.source
    }}

{class_body}
}}
'''
    port.write_text(support, encoding="utf-8")

    friend_helper = output / "Kuu2563FriendAccess.kt"
    friend_helper.write_text(FRIEND_ACCESS_HELPER_SOURCE, encoding="utf-8")

    driver = output / "Kuu2563Driver.kt"
    event_token = "KIO_" + hashlib.sha256(raw + b"KUU-2563").hexdigest()[:24]
    lines = ["package kotlinx.io", "", "private fun runKuu2563Case(identifier: String, factory: SourceFactory, method: String, suite: String) {",
             f'    println("{event_token} BEGIN " + identifier)',
             "    Kuu2563Observation.begin(identifier, method)", "    try {", "        val test = Kuu2563OriginalSourceTest(factory)",
             "        when (method) {"]
    for method in [identifier.split("#", 1)[1] for identifier in scope["source_function_ids"]]:
        lines.append(f'            "{method}" -> test.{method}()')
    lines += [
        '            else -> throw IllegalArgumentException("unknown selected method: $method")',
        "        }",
        '        if (method == "inputStreamBounds") Kuu2563Observation.boundsProbe(probeInvalidInputStreamRangeDoesNotConsume(factory))',
        f'        println("{event_token} PASS " + identifier)',
        "    } catch (failure: Throwable) {",
        f'        println("{event_token} FAIL " + identifier)',
        f'        println("{event_token} EXCEPTION " + (failure::class.qualifiedName ?: failure.toString()))',
        "    }",
        '    Kuu2563Observation.finish(identifier, method, suite == "kotlinx.io.BufferSourceTestJVM" || suite == "kotlinx.io.OneByteAtATimeBufferTestJVM")',
        "}",
        "",
        "fun main() {",
    ]
    for row in rows:
        lines.append(
            f'    runKuu2563Case({json.dumps(row["execution_id"])}, SourceFactory.{FACTORIES[row["concrete_class"]]}, '
            f'{json.dumps(row["method_name"])}, {json.dumps(row["concrete_class"])})'
        )
    lines += [
        "    try {",
        "        runKuu2563ApiContractProbe()",
        '        println("KUU2563_PROBE PASS KUU2563_API_CONTRACT_PROBE_PASS")',
        "    } catch (failure: Throwable) {",
        '        println("KUU2563_PROBE FAIL " + (failure::class.qualifiedName ?: failure.toString()))',
        "    }",
        "}",
        "",
    ]
    driver.write_text("\n".join(lines), encoding="utf-8")
    return {
        "source_port": str(port),
        "source_port_sha256": sha256(port),
        "source_bytes_preserved": True,
        "selected_method_count": len(method_chunks),
        "selected_functions": mapped_assertions,
        "friend_access_helper": str(friend_helper),
        "friend_access_helper_sha256": sha256(friend_helper),
        "driver": str(driver),
        "driver_sha256": sha256(driver),
        "event_token": event_token,
        "observation_token": OBSERVATION_TOKEN,
    }


def parse_observations(text: str, expected_ids: list[str]) -> dict[str, dict]:
    result: dict[str, dict] = {}
    for line in text.splitlines():
        if not line.startswith(OBSERVATION_TOKEN + "\t"):
            continue
        parts = line.split("\t")
        if len(parts) < 4:
            raise ValueError(f"malformed observation line: {line}")
        _, identifier, kind, *values = parts
        if identifier not in expected_ids:
            raise ValueError(f"observation names unknown execution ID: {identifier}")
        row = result.setdefault(identifier, {"values": [], "exception_types": [], "assertion_count": 0})
        if kind == "BEGIN":
            if "method" in row or len(values) != 1:
                raise ValueError(f"duplicate or malformed observation begin: {identifier}")
            row["method"] = values[0]
        elif kind == "VALUE":
            if len(values) != 2:
                raise ValueError(f"malformed observed value: {line}")
            row["values"].append({"expected": values[0], "actual": values[1]})
        elif kind == "EXCEPTION":
            if len(values) != 1:
                raise ValueError(f"malformed observed exception: {line}")
            row["exception_types"].append(values[0])
        elif kind == "BOUNDS_PROBE":
            if len(values) != 1 or "bounds_probe_read" in row:
                raise ValueError(f"duplicate or malformed bounds probe: {identifier}")
            row["bounds_probe_read"] = int(values[0])
        elif kind == "END":
            if len(values) != 2 or "status" in row:
                raise ValueError(f"duplicate or malformed observation end: {identifier}")
            row["assertion_count"] = int(values[0])
            row["branch"] = values[1]
            row["status"] = "COMPLETE"
        else:
            raise ValueError(f"unknown observation kind: {kind}")
    if set(result) != set(expected_ids):
        missing = sorted(set(expected_ids) - set(result))
        raise ValueError(f"missing observation execution IDs: {missing[:10]}")
    if any(row.get("status") != "COMPLETE" for row in result.values()):
        raise ValueError("one or more observation records did not finish")
    return result


def classify_process_result(exit_code: int, timed_out: bool) -> str:
    if timed_out:
        return "TIMEOUT"
    if exit_code < 0:
        return "CRASH"
    if exit_code != 0:
        return "NONZERO_EXIT"
    return "EXITED_ZERO"


def load_reference_junit(reuse_directory: Path, upstream: Path, kotlin_home: Path, java: Path,
                         dependencies: Path, generated: dict, rows: list[dict],
                         scope: dict, lock: dict) -> dict:
    reused = reuse_directory.resolve()
    summary_path = reused / "summary.json"
    environment_path = reused / "environment.json"
    execution_map_path = reused / "execution-map.json"
    junit_results_path = reused / "junit" / "results.json"
    run_stdout_path = reused / "run.stdout"
    run_result_path = reused / "run.result.json"
    outer_result_path = reused.parent / "reference-junit.result.json"
    java_version_path = reused / "java-version.stderr"
    kotlin_version_path = reused / "kotlin-version.stderr"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    environment = json.loads(environment_path.read_text(encoding="utf-8"))
    execution_map = json.loads(execution_map_path.read_text(encoding="utf-8"))
    junit_results = json.loads(junit_results_path.read_text(encoding="utf-8"))
    run_result = json.loads(run_result_path.read_text(encoding="utf-8"))
    outer_result = json.loads(outer_result_path.read_text(encoding="utf-8"))
    expected_ids = generated["execution_ids"]
    expected_source_ids = set(scope["source_function_ids"])
    source_paths = sorted(item["path"] for item in scope["source_closure"])
    if (summary.get("kind") != "reference-only"
            or summary.get("reference_counts") != {"PASS": len(expected_ids)}
            or summary.get("concrete_execution_count") != len(expected_ids)
            or set(summary.get("selected_source_function_ids", [])) != expected_source_ids):
        raise ValueError("reused JVM reference summary does not match the selected passing scope")
    if (environment.get("source_files") != source_paths or environment.get("java") != str(java.resolve())
            or environment.get("upstream_commit") != lock["commit"]
            or environment.get("kotlin") != lock["kotlin"]
            or environment.get("kotlinx_io") != lock["kotlinx_io"]):
        raise ValueError("reused JVM reference sources or Java runtime differ from the current request")
    if (environment.get("reference_lock_sha256") != sha256(LOCK_PATH)
            or environment.get("coverage_map_sha256") != sha256(HERE / "coverage-map.seed.json")
            or environment.get("runner_sha256") != sha256(HERE / "JvmReferenceRunner.java")):
        raise ValueError("reused JVM reference harness inputs are stale")
    probe = environment.get("contract_probe")
    if not isinstance(probe, dict) or probe.get("sha256") != sha256(PROBE_PATH):
        raise ValueError("reused JVM reference contract probe is stale")
    if outer_result.get("exitcode") != 0 or run_result.get("exitcode") != 0 or run_result.get("timeout"):
        raise ValueError("reused JVM reference execution did not exit successfully")
    raw_output = run_stdout_path.read_text(encoding="utf-8")
    if "KUU2563_API_CONTRACT_PROBE_PASS" not in raw_output:
        raise ValueError("reused JVM reference did not report the API contract probe")
    if not re.search(r'version "21[.\"]', java_version_path.read_text(encoding="utf-8")):
        raise ValueError("reused JVM reference Java runtime is not Java 21")
    if not re.search(r"kotlinc-jvm 2\.3\.10(?:\s|$)", kotlin_version_path.read_text(encoding="utf-8")
                     + (reused / "kotlin-version.stdout").read_text(encoding="utf-8")):
        raise ValueError("reused JVM reference Kotlin compiler is not 2.3.10")
    if len(execution_map) != len(expected_ids) or len(junit_results) != len(expected_ids):
        raise ValueError("reused JVM reference execution count differs from the locked catalog")
    expected_by_id = {row["execution_id"]: row for row in rows}
    for row in execution_map:
        identifier = row.get("execution_id")
        expected = expected_by_id.get(identifier)
        result = row.get("reference_result", {})
        if (expected is None or row.get("upstream_id") != expected["upstream_id"]
                or row.get("git_blob_sha") != expected["git_blob_sha"]
                or result.get("status") != "PASS"):
            raise ValueError(f"reused JVM reference execution is stale or failed: {identifier}")
    if {row.get("execution_id") for row in execution_map} != set(expected_ids):
        raise ValueError("reused JVM reference execution IDs differ from the locked catalog")
    if any(row.get("status") != "PASS" for row in junit_results):
        raise ValueError("reused original JUnit output contains a non-passing execution")
    for item in scope["source_closure"]:
        verify_file(upstream / item["path"], item)
    for item in environment.get("sdk_files", []):
        verify_file(kotlin_home.resolve() / item["path"], item)
    for item in lock["jvm_artifacts"]:
        jar = dependencies / item["url"].rsplit("/", 1)[1]
        verify_file(jar, item)
    return {
        "command_exitcode": 0,
        "summary": summary,
        "summary_sha256": sha256(summary_path),
        "execution_map_sha256": sha256(execution_map_path),
        "junit_results_sha256": sha256(junit_results_path),
        "raw_output_sha256": sha256(run_stdout_path),
        "contract_probe_pass": True,
        "reused_from": str(reused),
    }


def normalize_observation(row: dict, method: str, suite: str) -> dict:
    values = row["values"]
    result = {"value": {"assertions": values}}
    if row["exception_types"]:
        result["exception_type"] = ", ".join(row["exception_types"])
    if row["branch"] == "buffer-early-return":
        result["value"]["original_path"] = "Source is Buffer; original body returned before its close/read assertions"
    elif method in GUARDED_METHODS:
        result["value"]["original_path"] = "Source is not Buffer; original body continued past its guard"
    if method == "inputStream":
        try:
            result["bytes_consumed"] = sum(int(item["actual"]) for item in values
                                           if re.fullmatch(r"-?\d+", item["actual"]) and int(item["actual"]) > 0)
        except ValueError:
            raise ValueError(f"could not derive inputStream read count for {row}")
    elif method == "inputStreamOffsetCount":
        result["bytes_consumed"] = int(values[0]["actual"])
    elif method == "inputStreamSkip":
        result["bytes_consumed"] = int(values[0]["actual"]) + 1 + int(values[2]["actual"])
    elif method == "inputStreamCharByChar":
        result["bytes_consumed"] = sum(1 for item in values if item["actual"] != "-1")
    elif method == "inputStreamBounds":
        if row.get("bounds_probe_read") != ord("a"):
            raise ValueError("invalid InputStream range consumed bytes or failed its per-factory bounds probe")
        result["bytes_consumed"] = 0
        result["value"]["bounds_probe_first_unread_byte"] = row["bounds_probe_read"]
    elif method in {"inputStreamForClosedSource", "inputStreamClosesSource", "inputStreamAvailableForClosedSource"}:
        result["bytes_consumed"] = 0
        if method == "inputStreamClosesSource" and row["exception_types"]:
            result["resource_lifecycle"] = ["original body calls InputStream.close()", "Source.readByte() throws IllegalStateException"]
        elif method == "inputStreamForClosedSource" and row["exception_types"]:
            result["resource_lifecycle"] = ["original body closes Source", "InputStream.read() and both bulk read overloads throw IOException"]
        elif method == "inputStreamAvailableForClosedSource" and row["exception_types"]:
            result["resource_lifecycle"] = ["original body closes Source", "InputStream.available() throws IOException"]
    elif method == "inputStreamAvailable":
        result["bytes_consumed"] = int(values[2]["actual"]) - int(values[4]["actual"])
    elif method == "readNioBuffer":
        if len(values) != 4:
            raise ValueError(f"readNioBuffer expected four original value assertions, got {len(values)}")
        result["bytes_consumed"] = int(values[0]["actual"])
        result["byte_buffer_state"] = {
            "reported_bytes": int(values[0]["actual"]),
            "position": int(values[1]["actual"]),
            "limit": int(values[2]["actual"]),
            "capacity": int(values[2]["expected"]),
            "contents": values[3]["actual"],
        }
    if row["branch"] == "buffer-early-return" and method in GUARDED_METHODS:
        result["value"]["assertions_executed"] = 0
    if (not result["value"].get("assertions") and row["branch"] != "buffer-early-return"
            and method not in GUARDED_METHODS and method != "inputStreamBounds"):
        raise ValueError(f"non-guarded test emitted no assertion observations: {method} / {suite}")
    return result


def build_coverage_entries(scope: dict, lock: dict, catalog_rows: list[dict], generated: dict,
                          reference_observations: dict, candidate_observations: dict,
                          matrix_summary: dict, artifact: str, artifact_sha256: str) -> list[dict]:
    if matrix_summary.get("status") != "PASS":
        raise ValueError("cannot map upstream assertions from an incomplete candidate matrix")
    if len(catalog_rows) != scope["expected_jvm_execution_count"]:
        raise ValueError("candidate coverage map requires every locked JVM execution")
    entries = []
    assertion_groups = generated["selected_functions"]
    source_sha256 = scope["source_sha256"]
    source_blob_sha = scope["source_git_blob_sha"]
    for upstream_id in scope["source_function_ids"]:
        method = upstream_id.split("#", 1)[1]
        assertions = assertion_groups[upstream_id]
        assertion_ids = {item["id"] for item in assertions}
        entry = {
            "upstream_id": upstream_id,
            "upstream_path": scope["source_path"],
            "source_sha256": source_sha256,
            "source_git_blob_sha": source_blob_sha,
            "disposition": "paired",
            "reason": "All six candidate source, fresh stdlib-library, and producer-consumer O0/O2 lanes matched the pinned JVM reference for every locked factory execution.",
            "assertions": [
                {**item, "source_sha256": source_sha256}
                for item in assertions
            ],
            "executions": [],
        }
        for row in (item for item in catalog_rows if item["upstream_id"] == upstream_id):
            identifier = row["execution_id"]
            suite = row["concrete_class"]
            reference = reference_observations.get(identifier)
            candidate = candidate_observations.get(identifier)
            if reference is None or candidate is None:
                raise ValueError(f"missing paired observations for {identifier}")
            if reference != candidate:
                raise ValueError(f"reference and candidate observations differ for {identifier}")
            if suite in {"kotlinx.io.BufferSourceTestJVM", "kotlinx.io.OneByteAtATimeBufferTestJVM"} and method in GUARDED_METHODS:
                mapped_assertion_ids = [f"{method}:buffer-early-return"]
            else:
                mapped_assertion_ids = [item["id"] for item in assertions
                                        if item.get("kind") != "original conditional path, not a skipped execution"]
            if not mapped_assertion_ids or not set(mapped_assertion_ids).issubset(assertion_ids):
                raise ValueError(f"execution maps no original assertion: {identifier}")
            entry["executions"].append({
                "platform": "jvm",
                "execution_id": identifier,
                "invocation": {field: row[field] for field in (
                    "display_name", "concrete_class", "declaring_class", "method_name", "parameter_types",
                )},
                "assertion_ids": mapped_assertion_ids,
                "reference": {
                    "runner": "pinned kotlinx-io JVM JUnit 5 execution plus assertion observation adapter",
                    "result": {"status": "PASS", "artifact": artifact, "sha256": artifact_sha256},
                    "observations": {**reference, "artifact": artifact, "sha256": artifact_sha256},
                },
                "candidate": {
                    "runner": "KSwiftK macOS native bridge executable",
                    "result": {"status": "PASS", "artifact": artifact, "sha256": artifact_sha256},
                    "observations": {**candidate, "artifact": artifact, "sha256": artifact_sha256},
                },
            })
        if not entry["executions"]:
            raise ValueError(f"no locked JVM executions for {upstream_id}")
        entries.append(entry)
    return entries


def build_durable_evidence(scope: dict, lock: dict, generated: dict, summary: dict,
                           junit_directory: Path, reference_observation_directory: Path,
                           output_directory: Path) -> dict:
    junit_execution_map = json.loads((junit_directory / "execution-map.json").read_text(encoding="utf-8"))
    junit_results = json.loads((junit_directory / "junit" / "results.json").read_text(encoding="utf-8"))
    reference_observations = json.loads(
        (reference_observation_directory / "results.json").read_text(encoding="utf-8"))
    candidate_lanes = {}
    for lane_name in ("source-O0", "source-O2", "stdlib-library-O0", "stdlib-library-O2",
                      "producer-consumer-O0", "producer-consumer-O2"):
        lane_directory = output_directory / "candidate" / lane_name
        candidate_lanes[lane_name] = {
            "summary": json.loads((lane_directory / "summary.json").read_text(encoding="utf-8")),
            "results": json.loads((lane_directory / "results.json").read_text(encoding="utf-8")),
            "observations": json.loads((lane_directory / "observations.json").read_text(encoding="utf-8")),
            "artifacts": {
                filename: sha256(lane_directory / filename)
                for filename in ("compile.stdout", "compile.stderr", "run.stdout", "run.stderr")
                if (lane_directory / filename).is_file()
            },
        }
    api_contracts = []
    for row in scope["api_rows"]:
        api_contracts.append({
            **row,
            "validation_status": "behavioral-evidence-recorded; JVM descriptor remains unverified",
            "observed": summary["api_contract_probe"],
            "jvm_descriptor_status": "unverified: candidate output is a macOS native executable/KLIB, not a JVM classfile",
        })
    return {
        "schema_version": 1,
        "issue": "KUU-2563",
        "kind": "kotlinx-io-upstream-assertion-matrix",
        "candidate_sha": scope["candidate_sha"],
        "upstream": {"version": lock["kotlinx_io"], "kotlin_version": lock["kotlin"],
                     "commit": lock["commit"], "source_path": scope["source_path"],
                     "source_sha256": scope["source_sha256"],
                     "source_git_blob_sha": scope["source_git_blob_sha"]},
        "scope": {"source_function_ids": scope["source_function_ids"],
                  "expected_jvm_execution_count": scope["expected_jvm_execution_count"],
                  "expected_native_execution_count": scope["expected_native_execution_count"],
                  "execution_ids": generated["execution_ids"],
                  "assertions": generated["selected_functions"]},
        "candidate_inputs": summary["candidate_inputs"],
        "generated_inputs": {
            "source_port_sha256": generated["source_port_sha256"],
            "driver_sha256": generated["driver_sha256"],
            "friend_access_helper_sha256": generated["friend_access_helper_sha256"],
            "probe_sha256": sha256(PROBE_PATH),
        },
        "reference_junit": {
            "summary": summary["reference_junit"],
            "execution_map": junit_execution_map,
            "results": junit_results,
            "output_sha256": sha256(junit_directory / "run.stdout"),
            "stderr_sha256": sha256(junit_directory / "run.stderr"),
        },
        "reference_observations": reference_observations,
        "fresh_stdlib": summary["fresh_stdlib"],
        "candidate_lanes": candidate_lanes,
        "api_contracts": api_contracts,
        "native_catalog_execution_count": 0,
        "status": summary["status"],
    }


def record_coverage_map(entries: list[dict], artifact_path: Path, artifact_sha256: str) -> None:
    if not artifact_path.is_file() or sha256(artifact_path) != artifact_sha256:
        raise ValueError("durable coverage artifact is missing or its SHA-256 changed")
    coverage_path = HERE / "coverage-map.verified.json"
    value = json.loads(coverage_path.read_text(encoding="utf-8"))
    locked_commit = json.loads(LOCK_PATH.read_text(encoding="utf-8"))["commit"]
    if value.get("schema_version") != 1 or value.get("upstream_commit") != locked_commit:
        raise ValueError("coverage-map.verified.json does not match the locked schema and upstream commit")
    selected = {entry["upstream_id"] for entry in entries}
    existing = [entry for entry in value.get("mappings", [])
                if entry.get("upstream_id") not in selected]
    value["mappings"] = existing + entries
    json_write(coverage_path, value)


def reference_observation_run(upstream: Path, kotlin_home: Path, java: Path, dependencies: Path,
                              generated: dict, catalog_rows: list[dict], source_closure: list[dict], output: Path,
                              timeout: float, reuse_directory: Path | None = None) -> tuple[dict[str, dict], dict]:
    expected_ids = generated["execution_ids"]
    if reuse_directory is not None:
        reused = reuse_directory.resolve()
        compile_result = json.loads((reused / "compile.result.json").read_text(encoding="utf-8"))
        run_result = json.loads((reused / "run.result.json").read_text(encoding="utf-8"))
        if compile_result.get("exitcode") != 0 or compile_result.get("timeout"):
            raise ValueError("reused reference observation compile did not complete successfully")
        if run_result.get("exitcode") != 0 or run_result.get("timeout"):
            raise ValueError("reused reference observation run did not complete successfully")
        raw_output = (reused / "run.stdout").read_text(encoding="utf-8")
        event_results = parse_events(raw_output, expected_ids, generated["event_token"])
        observations = parse_observations(raw_output, expected_ids)
        probe_pass = "KUU2563_PROBE PASS KUU2563_API_CONTRACT_PROBE_PASS" in raw_output
        normalized = {
            identifier: normalize_observation(
                observations[identifier],
                next(item for item in catalog_rows if item["execution_id"] == identifier)["method_name"],
                next(item for item in catalog_rows if item["execution_id"] == identifier)["concrete_class"],
            )
            for identifier in expected_ids
        }
        if not probe_pass or any(row["status"] != "PASS" for row in event_results):
            raise ValueError("reused reference observations do not contain all passing executions and probe")
        original = json.loads((reused / "results.json").read_text(encoding="utf-8"))
        if (original.get("status") != "PASS" or original.get("probe_pass") is not True
                or original.get("execution_ids") != expected_ids
                or original.get("observations") != normalized):
            raise ValueError("reused reference observation summary does not match its raw output")
        expected_inputs = {
            "source_port_sha256": generated["source_port_sha256"],
            "driver_sha256": generated["driver_sha256"],
            "probe_sha256": sha256(PROBE_PATH),
        }
        factory_path = upstream / next(item["path"] for item in source_closure
                                       if item["path"].endswith("SourceFactory.kt"))
        expected_inputs["source_factory_sha256"] = sha256(factory_path)
        if original.get("inputs") != expected_inputs:
            raise ValueError("reused reference observation inputs differ from current pinned sources")
        return observations, {**original, "reused_from": str(reused), "raw_output_sha256": sha256(reused / "run.stdout")}

    output.mkdir(parents=True, exist_ok=False)
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    jars = []
    for artifact in lock["jvm_artifacts"]:
        jar = dependencies / artifact["url"].rsplit("/", 1)[1]
        verify_file(jar, artifact)
        jars.append(jar.resolve())
    sdk = kotlin_home.resolve() / "lib"
    io_jars = [jar for jar in jars if jar.name.startswith("kotlinx-io-")]
    compile_cp = jars + [sdk / "kotlin-test.jar", sdk / "kotlin-test-junit5.jar"]
    port = Path(generated["source_port"])
    driver = Path(generated["driver"])
    sources = [str(upstream / item["path"]) for item in source_closure if item["path"].endswith("SourceFactory.kt")]
    if len(sources) != 1:
        raise ValueError("KUU-2563 requires exactly one pinned SourceFactory.kt")
    sources += [str(port), str(PROBE_PATH.resolve()), str(driver)]
    jar_out = output / "Kuu2563ReferenceObservations.jar"
    command = [str(kotlin_home.resolve() / "bin/kotlinc"), *sources,
        "-classpath", os.pathsep.join(map(str, compile_cp)),
        "-Xfriend-paths=" + ",".join(map(str, io_jars)),
        "-opt-in=kotlinx.io.InternalIoApi", "-opt-in=kotlin.ExperimentalStdlibApi",
        "-XXLanguage:+UnnamedLocalVariables", "-include-runtime", "-d", str(jar_out)]
    compiler_environment = {"JAVACMD": str(java.resolve())}
    code = execute(command, output, "compile", timeout, compiler_environment)
    if code:
        return {}, {"status": "FAIL", "compile_exitcode": code, "command": command}
    runtime_cp = jars + [jar_out]
    command = [str(java.resolve()), "-Xmx1024m", "-cp", os.pathsep.join(map(str, runtime_cp)),
               "kotlinx.io.Kuu2563DriverKt"]
    code = execute(command, output, "run", timeout)
    text = (output / "run.stdout").read_text(encoding="utf-8")
    results = parse_events(text, expected_ids, generated["event_token"])
    observations = parse_observations(text, expected_ids)
    probe_pass = "KUU2563_PROBE PASS KUU2563_API_CONTRACT_PROBE_PASS" in text
    summary = {"status": "PASS" if code == 0 and probe_pass and all(row["status"] == "PASS" for row in results)
               else "FAIL", "compile_exitcode": 0, "run_exitcode": code,
               "probe_pass": probe_pass, "counts": dict(collections.Counter(row["status"] for row in results)),
               "execution_ids": expected_ids, "results": results,
               "observations": {identifier: normalize_observation(observations[identifier],
                   next(item for item in catalog_rows if item["execution_id"] == identifier)["method_name"],
                   next(item for item in catalog_rows if item["execution_id"] == identifier)["concrete_class"])
                   for identifier in expected_ids},
               "inputs": {"source_port_sha256": generated["source_port_sha256"],
                          "driver_sha256": generated["driver_sha256"], "probe_sha256": sha256(PROBE_PATH),
                          "source_factory_sha256": sha256(Path(sources[0]))}}
    json_write(output / "results.json", summary)
    return observations, summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--kotlin-home", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True)
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--compiler-resource-bundle", type=Path,
                        help="explicit Bundle.module directory when it is not beside the compiler")
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--reuse-reference-output-dir", type=Path,
                        help="validated prior output containing reference-junit/ and reference-observations/")
    parser.add_argument("--record-coverage", action="store_true",
                        help="save durable matrix evidence; update coverage-map.verified.json only after all lanes pass")
    parser.add_argument("--compile-timeout", type=float, default=1200)
    parser.add_argument("--stdlib-timeout", type=float, default=1800)
    parser.add_argument("--run-timeout", type=float, default=60)
    args = parser.parse_args(argv)
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    summary = {"schema_version": 1, "kind": "KUU-2563-candidate-and-reference-matrix",
               "host": platform.platform(), "status": "ERROR"}
    try:
        scope = json.loads(SCOPE_PATH.read_text(encoding="utf-8"))
        lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
        catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
        native_catalog = json.loads(NATIVE_CATALOG_PATH.read_text(encoding="utf-8"))
        root = args.package_root.resolve()
        if lock["commit"] != scope["upstream_commit"]:
            raise ValueError("scope upstream commit differs from reference lock")
        if lock["kotlin"] != "2.3.10" or lock["kotlinx_io"] != "0.9.1":
            raise ValueError("KUU-2563 reference versions differ from its pinned versions")
        for item in scope["source_closure"]:
            verify_file(args.upstream / item["path"], item)
        verify_file(CATALOG_PATH, {"sha256": lock["jvm_execution_catalog_sha256"]})
        verify_file(NATIVE_CATALOG_PATH, {"sha256": lock["native_execution_catalog_sha256"]})
        rows = select_rows(catalog, scope)
        native_ids = {row["upstream_id"] for row in native_catalog}
        if any(identifier in native_ids for identifier in scope["source_function_ids"]):
            raise ValueError("KUU-2563 scope must not invent Native reference execution IDs")
        if scope["expected_native_execution_count"] != 0:
            raise ValueError("task scope unexpectedly expects Native reference executions")
        generated_dir = args.output / "generated"
        generated_dir.mkdir()
        generated = build_sources(args.upstream, rows, lock, scope, generated_dir)
        generated["execution_ids"] = [row["execution_id"] for row in rows]
        summary.update({"candidate_sha": scope["candidate_sha"], "upstream_commit": lock["commit"],
            "reference_version": lock["kotlinx_io"], "kotlin_version": lock["kotlin"],
            "source_function_count": len(scope["source_function_ids"]), "jvm_execution_count": len(rows),
            "native_reference_execution_count": 0, "source_function_ids": scope["source_function_ids"],
            "generated": generated})

        revision = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
                                  check=True, capture_output=True, text=True).stdout.strip()
        if revision != scope["candidate_sha"]:
            raise ValueError(f"candidate checkout SHA {revision} differs from pinned {scope['candidate_sha']}")
        dirty = subprocess.run(["git", "-C", str(root), "status", "--porcelain", "--",
            "Package.swift", "Sources/CompilerCore", "Sources/CompilerBackend", "Sources/Runtime", "Sources/RuntimeABI"],
            check=True, capture_output=True, text=True).stdout.strip()
        if dirty:
            raise ValueError("candidate compiler/runtime source tree has uncommitted changes")
        friend_access_source_sha256 = verify_friend_helper_declaration(root)
        compiler = args.compiler.resolve()
        if not compiler.is_file():
            raise ValueError(f"missing candidate compiler binary: {compiler}")
        candidate_sources_hash = tree_hash(root / "Sources" / "CompilerCore")
        candidate_runtime_hash = tree_hash(root / "Sources" / "Runtime")
        candidate_abi_hash = tree_hash(root / "Sources" / "RuntimeABI")
        resources = None
        candidates = ([args.compiler_resource_bundle.resolve()] if args.compiler_resource_bundle else [])
        candidates += [compiler.parent / "KSwiftK_CompilerCore.resources",
                       compiler.parent / "KSwiftK_CompilerCore.bundle"]
        for candidate in candidates:
            if (candidate / "Stdlib").is_dir():
                resources = candidate
                break
            if (candidate / "Contents" / "Resources" / "Stdlib").is_dir():
                resources = candidate / "Contents" / "Resources"
                break
        if resources is None:
            raise ValueError("candidate compiler resource bundle with Stdlib is required for source-injection lane")
        summary["candidate_inputs"] = {"compiler": str(compiler), "compiler_sha256": sha256(compiler),
            "compiler_resource_bundle": str(resources), "compiler_resource_bundle_sha256": tree_hash(resources),
            "package_root": str(root), "candidate_git_sha": revision,
            "compiler_sources_sha256": candidate_sources_hash, "runtime_sources_sha256": candidate_runtime_hash,
            "runtime_abi_sources_sha256": candidate_abi_hash, "package_manifest_sha256": sha256(root / "Package.swift"),
            "scope_sha256": sha256(SCOPE_PATH), "reference_lock_sha256": sha256(LOCK_PATH),
            "jvm_catalog_sha256": sha256(CATALOG_PATH), "native_catalog_sha256": sha256(NATIVE_CATALOG_PATH),
            "probe_sha256": sha256(PROBE_PATH),
            "friend_access_helper_sha256": generated["friend_access_helper_sha256"],
            "friend_access_source_sha256": friend_access_source_sha256,
            "runner_sha256": sha256(Path(__file__))}

        if args.reuse_reference_output_dir:
            reused_output = args.reuse_reference_output_dir.resolve()
            reference_junit_directory = reused_output / "reference-junit"
            reference_observation_directory = reused_output / "reference-observations"
            summary["reference_junit"] = load_reference_junit(
                reference_junit_directory, args.upstream.resolve(), args.kotlin_home.resolve(),
                args.java.resolve(), args.dependencies.resolve(), generated, rows, scope, lock)
            reference_code = summary["reference_junit"]["command_exitcode"]
            reference_summary = summary["reference_junit"]["summary"]
            reference_observations, reference_obs_summary = reference_observation_run(
                args.upstream.resolve(), args.kotlin_home.resolve(), args.java.resolve(), args.dependencies.resolve(),
                generated, rows, scope["source_closure"], args.output / "reference-observations",
                args.compile_timeout + args.run_timeout, reference_observation_directory)
        else:
            reference_junit_directory = args.output / "reference-junit"
            reference_observation_directory = args.output / "reference-observations"
            reference_dir = reference_junit_directory
            cmd = [sys.executable, str(HERE / "run_jvm_reference.py"), "--upstream", str(args.upstream.resolve()),
                   "--kotlin-home", str(args.kotlin_home.resolve()), "--java", str(args.java.resolve()),
                   "--dependencies", str(args.dependencies.resolve()), "--output", str(reference_dir),
                   "--compile-timeout", str(args.compile_timeout), "--run-timeout", str(args.run_timeout)]
            for identifier in scope["source_function_ids"]:
                cmd += ["--source-function-id", identifier]
            for item in scope["source_closure"]:
                cmd += ["--compile-source-path", item["path"]]
            cmd += ["--contract-probe", str(PROBE_PATH.resolve())]
            reference_code = execute(cmd, args.output, "reference-junit", args.compile_timeout + args.run_timeout)
            reference_summary_path = reference_dir / "summary.json"
            if not reference_summary_path.is_file():
                raise ValueError("selected original JVM reference runner did not produce summary.json")
            reference_summary = json.loads(reference_summary_path.read_text(encoding="utf-8"))
            summary["reference_junit"] = {"command_exitcode": reference_code, "summary": reference_summary,
                "summary_sha256": sha256(reference_summary_path),
                "execution_map_sha256": sha256(reference_dir / "execution-map.json"),
                "contract_probe_pass": "KUU2563_API_CONTRACT_PROBE_PASS" in
                    (reference_dir / "run.stdout").read_text(encoding="utf-8")}

            reference_observations, reference_obs_summary = reference_observation_run(
                args.upstream.resolve(), args.kotlin_home.resolve(), args.java.resolve(), args.dependencies.resolve(),
                generated, rows, scope["source_closure"], reference_observation_directory,
                args.compile_timeout + args.run_timeout)
        summary["reference_observations"] = reference_obs_summary
        summary["reference_artifact_paths"] = {
            "junit": str(reference_junit_directory),
            "observations": str(reference_observation_directory),
        }

        stdlib = args.output / "fresh-stdlib.kklib"
        stdlib_cache = args.output / "fresh-stdlib-cache"
        stdlib_cache.mkdir()
        stdlib_code = execute([str(compiler), "--stdlib-only", "--emit", "library", "-O0", "-o", str(stdlib)],
            args.output, "fresh-stdlib-build", args.stdlib_timeout,
            {"KSWIFTK_PACKAGE_ROOT": str(root), "KSWIFTK_STDLIB_CACHE_DIR": str(stdlib_cache)})
        summary["fresh_stdlib"] = {"exitcode": stdlib_code,
            "sha256": tree_hash(stdlib) if stdlib.is_dir() else None,
            "manifest": json.loads((stdlib / "manifest.json").read_text()) if (stdlib / "manifest.json").is_file() else None}

        port = Path(generated["source_port"])
        driver = Path(generated["driver"])
        factory_source = args.upstream.resolve() / next(item["path"] for item in scope["source_closure"]
                                                       if item["path"].endswith("SourceFactory.kt"))
        probe = PROBE_PATH.resolve()
        lane_reports = {}
        for mode, use_source, use_test_library in (
            ("source", True, False), ("stdlib-library", False, False), ("producer-consumer", False, True),
        ):
            for optimization in ("O0", "O2"):
                lane_name = f"{mode}-{optimization}"
                lane_dir = args.output / "candidate" / lane_name
                lane_dir.mkdir(parents=True)
                cache = lane_dir / "stdlib-cache"
                cache.mkdir()
                base = [str(compiler), "-" + optimization]
                base += ["--stdlib-from-source"] if use_source else ["--stdlib-library", str(stdlib)]
                env = {"KSWIFTK_PACKAGE_ROOT": str(root), "KSWIFTK_STDLIB_CACHE_DIR": str(cache)}
                friend_helper = Path(generated["friend_access_helper"])
                sources = candidate_test_support_sources(
                    port, factory_source, probe, friend_helper, use_source
                )
                results = [{"execution_id": identifier, "status": "NOT_RUN"} for identifier in generated["execution_ids"]]
                report = {"mode": mode, "optimization": optimization, "status": "NOT_RUN",
                          "candidate_sha": revision, "source_function_count": len(scope["source_function_ids"]),
                          "expected_execution_count": len(generated["execution_ids"]), "compile_exitcode": None,
                          "run_exitcode": None, "observations_match_reference": False}
                binary = lane_dir / "candidate"
                if use_test_library:
                    test_library = lane_dir / "OriginalTests.kklib"
                    lib_command = base + ["--emit", "library", "-m", "KioKuu2563OriginalTests", *sources, "-o", str(test_library)]
                    lib_code = execute(lib_command, lane_dir, "test-library-compile", args.compile_timeout, env)
                    report["test_library_compile_exitcode"] = lib_code
                    report["test_library_sha256"] = tree_hash(test_library) if test_library.is_dir() else None
                    compile_command = base + ["-I", str(test_library), str(driver), "-o", str(binary)] if lib_code == 0 else []
                    code = execute(compile_command, lane_dir, "compile", args.compile_timeout, env) if lib_code == 0 else lib_code
                else:
                    compile_command = base + sources + [str(driver), "-o", str(binary)]
                    code = execute(compile_command, lane_dir, "compile", args.compile_timeout, env)
                report["compile_exitcode"] = code
                if code == 0 and binary.is_file():
                    report["executable_sha256"] = sha256(binary)
                    run_code = execute([str(binary)], lane_dir, "run", args.run_timeout)
                    report["run_exitcode"] = run_code
                    run_result = json.loads((lane_dir / "run.result.json").read_text(encoding="utf-8"))
                    report["run_result"] = run_result
                    report["process_outcome"] = classify_process_result(run_code, run_result.get("timeout") is True)
                    stdout = (lane_dir / "run.stdout").read_text(encoding="utf-8")
                    try:
                        results = parse_events(stdout, generated["execution_ids"], generated["event_token"])
                    except ValueError as error:
                        report["event_protocol_error"] = str(error)
                        results = [{"execution_id": identifier, "status": "NOT_RUN"}
                                   for identifier in generated["execution_ids"]]
                    probe_pass = "KUU2563_PROBE PASS KUU2563_API_CONTRACT_PROBE_PASS" in stdout
                    report["probe_pass"] = probe_pass
                    report["counts"] = dict(collections.Counter(row["status"] for row in results))
                    report["results"] = results
                    report["raw_stdout_sha256"] = sha256(lane_dir / "run.stdout")
                    report["raw_stderr_sha256"] = sha256(lane_dir / "run.stderr")
                    observations: dict[str, dict] = {}
                    normalized: dict[str, dict] = {}
                    mismatches: list[str] = []
                    if run_code == 0:
                        try:
                            observations = parse_observations(stdout, generated["execution_ids"])
                            normalized = {identifier: normalize_observation(observations[identifier],
                                next(item for item in rows if item["execution_id"] == identifier)["method_name"],
                                next(item for item in rows if item["execution_id"] == identifier)["concrete_class"])
                                for identifier in generated["execution_ids"]}
                            mismatches = [identifier for identifier in generated["execution_ids"]
                                          if normalized[identifier] != reference_obs_summary["observations"][identifier]]
                        except ValueError as error:
                            report["protocol_error"] = str(error)
                    report["observed_execution_count"] = len(normalized)
                    report["unobserved_execution_ids"] = [identifier for identifier in generated["execution_ids"]
                                                           if identifier not in normalized]
                    report["observations_match_reference"] = (
                        len(normalized) == len(generated["execution_ids"]) and not mismatches
                    )
                    report["observation_mismatch_ids"] = mismatches
                    report["observations"] = normalized
                    if report["process_outcome"] != "EXITED_ZERO":
                        report["status"] = report["process_outcome"]
                    elif "protocol_error" in report:
                        report["status"] = "ERROR"
                    elif "event_protocol_error" in report:
                        report["status"] = "ERROR"
                    else:
                        report["status"] = "PASS" if probe_pass and all(
                            row["status"] == "PASS" for row in results) and not mismatches else "FAIL"
                    if sha256(binary) != report["executable_sha256"]:
                        raise ValueError(f"candidate executable changed during {lane_name}")
                else:
                    report["results"] = results
                    report["observations"] = {}
                    report["counts"] = {"NOT_RUN": len(generated["execution_ids"])}
                    report["unobserved_execution_ids"] = generated["execution_ids"]
                    compile_result_path = lane_dir / "compile.result.json"
                    if compile_result_path.is_file():
                        compile_result = json.loads(compile_result_path.read_text(encoding="utf-8"))
                        report["compile_result"] = compile_result
                        report["status"] = "COMPILE_TIMEOUT" if compile_result.get("timeout") else "COMPILE_FAIL"
                    else:
                        report["status"] = "COMPILE_FAIL"
                    report["compile_stdout_sha256"] = sha256(lane_dir / "compile.stdout") if (lane_dir / "compile.stdout").is_file() else None
                    report["compile_stderr_sha256"] = sha256(lane_dir / "compile.stderr") if (lane_dir / "compile.stderr").is_file() else None
                json_write(lane_dir / "summary.json", report)
                lane_reports[lane_name] = {key: value for key, value in report.items() if key != "observations"}
                if "observations" in report:
                    json_write(lane_dir / "observations.json", report["observations"])
                json_write(lane_dir / "results.json", report["results"])
        summary["candidate_lanes"] = lane_reports
        for record in scope["source_closure"]:
            verify_file(args.upstream / record["path"], record)
        unchanged = {
            "compiler_sha256": sha256(compiler),
            "compiler_resource_bundle_sha256": tree_hash(resources),
            "compiler_sources_sha256": tree_hash(root / "Sources" / "CompilerCore"),
            "runtime_sources_sha256": tree_hash(root / "Sources" / "Runtime"),
            "runtime_abi_sources_sha256": tree_hash(root / "Sources" / "RuntimeABI"),
            "package_manifest_sha256": sha256(root / "Package.swift"),
            "source_port_sha256": sha256(port), "driver_sha256": sha256(driver),
            "probe_sha256": sha256(probe),
            "friend_access_helper_sha256": sha256(friend_helper),
            "friend_access_source_sha256": verify_friend_helper_declaration(root),
            "scope_sha256": sha256(SCOPE_PATH),
            "reference_lock_sha256": sha256(LOCK_PATH), "jvm_catalog_sha256": sha256(CATALOG_PATH),
            "native_catalog_sha256": sha256(NATIVE_CATALOG_PATH),
        }
        expected_hashes = {"compiler_sha256": summary["candidate_inputs"]["compiler_sha256"],
            "compiler_resource_bundle_sha256": summary["candidate_inputs"]["compiler_resource_bundle_sha256"],
            "compiler_sources_sha256": candidate_sources_hash, "runtime_sources_sha256": candidate_runtime_hash,
            "runtime_abi_sources_sha256": candidate_abi_hash, "package_manifest_sha256": summary["candidate_inputs"]["package_manifest_sha256"],
            "source_port_sha256": generated["source_port_sha256"], "driver_sha256": generated["driver_sha256"],
            "probe_sha256": summary["candidate_inputs"]["probe_sha256"],
            "friend_access_helper_sha256": generated["friend_access_helper_sha256"],
            "friend_access_source_sha256": summary["candidate_inputs"]["friend_access_source_sha256"],
            "scope_sha256": summary["candidate_inputs"]["scope_sha256"],
            "reference_lock_sha256": summary["candidate_inputs"]["reference_lock_sha256"],
            "jvm_catalog_sha256": summary["candidate_inputs"]["jvm_catalog_sha256"],
            "native_catalog_sha256": summary["candidate_inputs"]["native_catalog_sha256"]}
        if unchanged != expected_hashes:
            raise ValueError("candidate or upstream inputs changed during the validation matrix")
        all_lanes_pass = all(item["status"] == "PASS" for item in lane_reports.values()) and len(lane_reports) == 6
        reference_pass = reference_code == 0 and reference_summary["reference_counts"] == {"PASS": 60}
        observations_pass = reference_obs_summary["status"] == "PASS"
        summary["status"] = "PASS" if stdlib_code == 0 and all_lanes_pass and reference_pass and observations_pass else "FAIL"
        summary["api_contract_probe"] = {
            "probe_sha256": sha256(PROBE_PATH),
            "contracts": [row["contract_scope"] for row in scope["api_rows"]],
            "reference_junit_pass": summary["reference_junit"].get("contract_probe_pass") is True,
            "reference_observations_pass": reference_obs_summary.get("probe_pass") is True,
            "candidate_lanes": {name: report.get("probe_pass") is True for name, report in lane_reports.items()},
            "jvm_descriptor_verified": False,
        }
        summary["candidate_input_hashes_unchanged"] = True
        summary["reference_input_hashes_unchanged"] = True
        if args.record_coverage:
            evidence_path = HERE / "evidence" / "kuu-2563-matrix.json"
            evidence_path.parent.mkdir(parents=True, exist_ok=True)
            evidence = build_durable_evidence(
                scope, lock, generated, summary, reference_junit_directory,
                reference_observation_directory, args.output)
            json_write(evidence_path, evidence)
            evidence_sha256 = sha256(evidence_path)
            durable_record = {
                "path": evidence_path.relative_to(REPO).as_posix(),
                "sha256": evidence_sha256,
                "verified_source_function_count": 0,
                "verified_jvm_execution_count": 0,
                "native_execution_count": 0,
                "coverage_map_updated": False,
            }
            if summary["status"] == "PASS":
                candidate_source_o0 = json.loads(
                    (args.output / "candidate" / "source-O0" / "observations.json").read_text(encoding="utf-8"))
                entries = build_coverage_entries(
                    scope, lock, rows, generated, reference_obs_summary["observations"], candidate_source_o0,
                    summary, evidence_path.relative_to(REPO).as_posix(), evidence_sha256)
                record_coverage_map(entries, evidence_path, evidence_sha256)
                durable_record.update({
                    "verified_source_function_count": len(entries),
                    "verified_jvm_execution_count": sum(len(item["executions"]) for item in entries),
                    "coverage_map_updated": True,
                })
            summary["durable_evidence"] = durable_record
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        summary.update({"status": "ERROR", "error": str(error)})
    finally:
        json_write(args.output / "summary.json", summary)
    return 0 if summary.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
