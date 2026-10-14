#!/usr/bin/env python3
"""Generate executable ledger probes; compile-only F01 probes are not execution.

The JVM-paired subset runs with fresh inputs per row. Unsafe segments and
contexts are used only inside the upstream callback scope. Other ledger views
are retained as unpaired obligations, never silently counted as verified.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import generate_f01_consumers as f01

HERE = Path(__file__).resolve().parent
OUTPUT = HERE / "f02_consumers"
SUPPORT = '''
private var callbacks = 0
private fun seed(): Buffer = Buffer().apply { write(byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)) }
private fun observe(value: Any?): String = when (value) {
    null -> "null"
    is Buffer -> "Buffer:" + value.size + ":" + value.snapshot().toHexString()
    is ByteString -> "ByteString:" + value.toHexString()
    is ByteArray -> "ByteArray:" + value.joinToString(",")
    is Path -> "Path:" + value.toString()
    is FileMetadata -> "FileMetadata:" + value.isRegularFile + ":" + value.isDirectory + ":" + value.size
    is Throwable -> "Throwable:" + exceptionType(value) + ":" + value.message
    is String -> "String:" + value
    is StringBuilder -> "StringBuilder:" + value.toString()
    is List<*> -> "List:" + value.joinToString(",") { observe(it) }
    is Char -> "Char:" + value.code
    is Boolean -> "Boolean:" + value
    is Byte -> "Byte:" + value
    is Short -> "Short:" + value
    is Int -> "Int:" + value
    is Long -> "Long:" + value
    is Float -> "FloatBits:" + value.toRawBits()
    is Double -> "DoubleBits:" + value.toRawBits()
    is UByte -> "UByte:" + value
    is UShort -> "UShort:" + value
    is UInt -> "UInt:" + value
    is ULong -> "ULong:" + value
    is Unit -> "Unit"
    is Source -> "Source"
    is Sink -> "Sink"
    is RawSource -> "RawSource"
    is RawSink -> "RawSink"
    is FileSystem -> "FileSystem"
    is Segment -> "Segment"
    is SegmentReadContext -> "SegmentReadContext"
    is SegmentWriteContext -> "SegmentWriteContext"
    is BufferIterationContext -> "BufferIterationContext"
    is ByteStringBuilder -> "ByteStringBuilder:" + value.toByteString().toHexString()
    else -> "other:" + value::class.simpleName
}
private fun exceptionType(failure: Throwable): String = when (failure) {
    is EOFException -> "EOFException"
    is IOException -> "IOException"
    is IndexOutOfBoundsException -> "IndexOutOfBoundsException"
    is NumberFormatException -> "NumberFormatException"
    is IllegalArgumentException -> "IllegalArgumentException"
    is IllegalStateException -> "IllegalStateException"
    is UnsupportedOperationException -> "UnsupportedOperationException"
    else -> "other:" + failure::class.simpleName
}
'''


def expression(type_name: str, name: str = "") -> str:
    type_name = type_name.removeprefix("kotlinx.io.bytestring.unsafe.").removeprefix("kotlinx.io.unsafe.")
    type_name = type_name.removeprefix("kotlinx.io.files.").removeprefix("kotlinx.io.bytestring.").removeprefix("kotlinx.io.")
    values = {
        "Buffer": "seed()", "Source": "seed()", "Sink": "Buffer()",
        "RawSource": "seed()", "RawSink": "Buffer()", "FileSystem": "SystemFileSystem",
        "ByteString": "ByteString(1, 2, 3)", "ByteString.Companion": "ByteString.Companion",
        "ByteStringBuilder": "ByteStringBuilder()", "ByteArray": "byteArrayOf(1, 2, 3, 4)",
        "Path": 'Path("f02-path")', "FileMetadata": "FileMetadata(false, false, 0L)",
        "UnsafeBufferOperations": "UnsafeBufferOperations", "UnsafeByteStringOperations": "UnsafeByteStringOperations",
        "Segment": "segment!!", "SegmentReadContext": "context", "SegmentWriteContext": "context",
        "BufferIterationContext": "context", "Boolean": "false", "String": '"0102"',
        "CharSequence": '"0102"', "String?": '"message"', "Throwable?": "null", "Any?": "null",
        "Byte": "1.toByte()", "Short": "1.toShort()", "Float": "1.25f", "Double": "1.25",
        "UByte": "1.toUByte()", "UShort": "1.toUShort()", "UInt": "1U", "ULong": "1UL",
        "HexFormat": "HexFormat.Default", "A": "StringBuilder()",
    }
    if type_name in values:
        if type_name == "Byte" and name in {"b0", "b1", "b2", "b3"}:
            return str(int(name[1]) + 1) + ".toByte()"
        return values[type_name]
    if type_name in ("Int", "Long"):
        value = 2 if name in {"endIndex", "byteCount", "count", "length"} else 0
        if name == "minimumCapacity": value = 1
        return str(value) + ("L" if type_name == "Long" else "")
    if "->" in type_name:
        arguments, result = type_name.rsplit("->", 1)
        result = result.strip()
        if ".()" in arguments:
            return '{ callbacks++; append(7.toByte()) }'
        # The declarations use no nested function types in their parameters.
        count = len(arguments[arguments.index("(") + 1:arguments.rindex(")")].split(","))
        prefix = ", ".join(f"arg{index}" for index in range(count)) + " -> "
        return "{ " + prefix + "callbacks++; " + ("0" if result == "Int" else "Unit") + " }"
    raise ValueError(f"no executable input recipe for {type_name} ({name})")


def generate() -> dict[str, str]:
    rows, by_source = f01.read_inputs()
    header, selected = f01.render_consumer(rows, by_source, "jvm-common")
    header = header.split("// Ledger ", 1)[0]
    header = header.replace("generate_f01_consumers.py", "generate_f02_consumers.py")
    header += "package f02ledger\n"  # Move the package before imports below.
    header = header.replace("package f02ledger\n", "").replace("import kotlinx.io.*", "package f02ledger\nimport kotlinx.io.*", 1)
    producer = [header, SUPPORT]
    consumer_functions = []
    calls = []
    covered = []
    call_ids = []
    for row in selected:
        declaration = f01.pick_declaration(row, by_source)
        lines = f01.emit_probe(row, declaration)
        # Each expression is observed, including both full/default calls. Type
        # rows observe erased identity instead of a nondeterministic hashCode.
        observed_lines = []
        expression_index = 0
        for line in lines:
            if line.startswith("    "):
                value = line.strip()
                if value == "value.hashCode()": value = "value"
                identifier = row["row_id"] + ":" + str(expression_index)
                expression_index += 1
                call_ids.append(identifier)
                observed_lines += [f'    println("CALL:{identifier}")', "    try {",
                    '        println("value:" + observe(' + value + "))", "    } catch (failure: Throwable) {",
                    '        println("call-exception:" + exceptionType(failure))', "    }",
                    f'    println("CALL-END:{identifier}")']
            else:
                observed_lines.append(line)
        lines = observed_lines
        producer += lines + [""]
        function_header = next(line for line in lines if line.startswith("fun "))
        args = function_header[function_header.index("(") + 1:function_header.rindex(")")]
        # Types containing commas are read from the catalog, not split from Kotlin.
        parameter_values = []
        watches = []
        if args.startswith("target:"):
            target_type = declaration.get("receiver") or declaration["owner"]
            parameter_values.append(("target", target_type, expression(target_type)))
        elif args.startswith("value:"):
            target_type = declaration["fqName"]
            parameter_values.append(("target", target_type, expression(target_type)))
        for index, parameter in enumerate(declaration.get("parameters", [])):
            parameter_values.append((f"input{index}", parameter["type"], expression(parameter["type"], parameter["name"])))
        # Annotation constructors have no constructor parameter probe.
        if declaration["kind"] == "annotation class": parameter_values = []
        contexts = [type_name for _, type_name, _ in parameter_values
                    if type_name.split(".")[-1] in {"Segment", "SegmentReadContext", "SegmentWriteContext", "BufferIterationContext"}]
        call = []
        for name, type_name, value in parameter_values:
            concrete_type = "StringBuilder" if type_name == "A" else type_name
            call.append(f"    val {name}: {concrete_type} = {value}")
            if "->" not in type_name: watches.append(name)
        name = f"f01_{row['row_id'].replace('-', '_')}"
        call += ["    try {", f"        {name}({', '.join(name for name, _, _ in parameter_values)})", "    } finally {"]
        call += [f'        println("state:{name}:" + observe({name}))' for name in watches]
        call += ["    }"]
        if contexts:
            short_types = {name.split(".")[-1] for name in contexts}
            if "SegmentWriteContext" in short_types:
                begin = "UnsafeBufferOperations.writeToTail(contextBuffer, 4) { context, segment ->"
                end = "4\n    }\n    println(\"committed:\" + observe(contextBuffer))"
                initialization = ["        context.setUnchecked(segment, 0, 42.toByte(), 42.toByte(), 42.toByte(), 42.toByte())"]
            elif "BufferIterationContext" in short_types:
                begin = "UnsafeBufferOperations.iterate(contextBuffer) { context, segment ->"
                end = "Unit\n    }"
                initialization = []
            else:
                begin = "UnsafeBufferOperations.readFromHead(contextBuffer) { context, segment ->"
                end = "0\n    }"
                initialization = []
            call = ["    val contextBuffer = seed()", "    " + begin] + initialization + ["    " + line for line in call] + ["    " + end]
        probe = "run_" + row["row_id"].replace("-", "_")
        consumer_functions += [f"private fun {probe}() {{", "    callbacks = 0",
                     f'    println("BEGIN:{row["row_id"]}")', "    try {", *["    " + line for line in call],
                     '        println("exception:none")', "    } catch (failure: Throwable) {",
                     '        println("exception:" + exceptionType(failure))', "    }",
                     '    println("callbacks:" + callbacks)', f'    println("END:{row["row_id"]}")', "}", ""]
        calls.append(f"    {probe}()")
        covered.append(row["row_id"])
    consumer_header = header.replace("package f02ledger", "package f02consumer\nimport f02ledger.*")
    consumer = consumer_header + SUPPORT + "\n" + "\n".join(consumer_functions)
    consumer += "\nfun main() {\n" + "\n".join(calls) + "\n}\n"
    return {"Producer.kt": "\n".join(producer), "Consumer.kt": consumer,
            "manifest.json": json.dumps({"schema_version": 1, "kind": "executable-ledger-scenarios",
                "paired_source_rows": covered, "required_call_ids": call_ids,
                "unpaired_ledger_rows": [row["row_id"] for row in rows if row["row_id"] not in covered],
                "scope": "JVM-paired common source APIs; other platform/ABI rows remain obligations",
                "observations": ["value", "exception_type", "argument_state", "callbacks"],
                "not_proven": ["all input boundaries", "resource lifecycle", "JVM bytecode descriptors", "GC roots"],
            }, indent=2) + "\n"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    for name, contents in generate().items():
        path = OUTPUT / name
        if args.write:
            OUTPUT.mkdir(exist_ok=True)
            path.write_text(contents)
        elif not path.exists() or path.read_text() != contents:
            raise ValueError(f"stale generated consumer: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
