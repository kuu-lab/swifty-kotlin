#!/usr/bin/env python3
"""Generate compile-only Kotlin consumers from the pinned kotlinx-io ledger."""

from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


HERE = Path(__file__).resolve().parent
OUTPUT = HERE / "f01_consumers"
LEDGER = HERE / "api-inventory.tsv"
DECLARATIONS = HERE / "source-declarations.json"
INVALID_GUARDS = HERE / "negative-api-guards.tsv"
IN_SCOPE_REPRESENTATION = "Kotlin source API / KLIB dump"
IMPORTS = (
    "import kotlinx.io.*",
    "import kotlinx.io.files.*",
    "import kotlinx.io.bytestring.*",
    "import kotlinx.io.unsafe.*",
    "import kotlinx.io.bytestring.unsafe.*",
    "import kotlin.io.encoding.*",
    "import kotlin.time.*",
    "import kotlin.text.*",
)
OPT_INS = (
    "kotlinx.io.DelicateIoApi",
    "kotlinx.io.InternalIoApi",
    "kotlinx.io.UnsafeIoApi",
    "kotlinx.io.bytestring.unsafe.UnsafeByteStringApi",
    "kotlin.ExperimentalUnsignedTypes",
    "kotlin.contracts.ExperimentalContracts",
)
API_OPT_IN_MARKERS = (
    "DelicateIoApi",
    "InternalIoApi",
    "UnsafeIoApi",
    "UnsafeByteStringApi",
)
OBJECT_RECEIVERS = {
    "Base64": "kotlin.io.encoding.Base64",
    "HexFormat": "kotlin.text.HexFormat",
}


def read_inputs():
    with LEDGER.open(newline="") as stream:
        rows = list(csv.DictReader(stream, delimiter="\t"))
    declarations = json.loads(DECLARATIONS.read_text())["declarations"]
    by_source = defaultdict(list)
    for declaration in declarations:
        by_source[(declaration["path"], declaration["line"])].append(declaration)
    return rows, by_source


def read_invalid_guards():
    with INVALID_GUARDS.open(newline="") as stream:
        guards = list(csv.DictReader(stream, delimiter="\t"))
    identifiers = [guard["guard_id"] for guard in guards]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("negative API guard IDs must be unique")
    for guard in guards:
        if not all(guard[key].strip() for key in ("owner", "name", "call", "upstream_absence")):
            raise ValueError("negative API guards require a target, call, and upstream absence basis")
        if guard["parameter_types"].strip() == "*":
            guard["parameter_types"] = "*"
        else:
            guard["parameter_types"] = json.loads(guard["parameter_types"])
            if not isinstance(guard["parameter_types"], list):
                raise ValueError(f"{guard['guard_id']} parameter_types must be a JSON array or '*'")
    return guards


def invalid_guard_matches_declaration(guard, declaration):
    if declaration.get("kind") != "function":
        return False
    if declaration.get("owner") != guard["owner"] or declaration.get("name") != guard["name"]:
        return False
    if (declaration.get("receiver") or "") != guard["receiver"]:
        return False
    if guard["parameter_types"] == "*":
        return True
    return [parameter["type"] for parameter in declaration.get("parameters", [])] == guard["parameter_types"]


def validate_invalid_guard_absence(guards, by_source):
    upstream_declarations = (
        declaration
        for declarations in by_source.values()
        for declaration in declarations
        if declaration.get("origin") == "upstream"
    )
    upstream_declarations = list(upstream_declarations)
    for guard in guards:
        if any(invalid_guard_matches_declaration(guard, declaration) for declaration in upstream_declarations):
            raise ValueError(f"{guard['guard_id']} is no longer absent from the pinned upstream source catalog")


def source_key(row):
    refs = row["upstream_source_refs"].split(";")
    for ref in refs:
        path, separator, line = ref.rpartition(":")
        if separator and path.startswith(("core/common/src/", "bytestring/common/src/")):
            return path, int(line)
    for ref in refs:
        path, separator, line = ref.rpartition(":")
        if separator:
            return path, int(line)
    raise ValueError(f"no source location in {row['row_id']}")


def pick_declaration(row, by_source):
    key = source_key(row)
    candidates = by_source.get(key, [])
    if not candidates:
        raise ValueError(f"{row['row_id']} has no source declaration at {key}")
    name = row["name"]
    for declaration in candidates:
        if declaration.get("name") == name or (
            declaration.get("kind") == "constructor" and name == "<init>"
        ):
            return declaration
    return candidates[0]


def kotlin_name(fq_name):
    return fq_name.replace("/", ".")


def safe_type(type_name):
    return type_name or "kotlin.Unit"


def function_arguments(parameters, omit_defaults=False, named=False):
    selected = [
        index
        for index, parameter in enumerate(parameters)
        if not (omit_defaults and parameter.get("default") is not None)
    ]
    return ", ".join(
        f"{parameters[index]['name']} = api_arg_{index}" if named else f"api_arg_{index}"
        for index in selected
    )


def typed_function_parameters(parameters):
    return [
        f"api_arg_{index}: {safe_type(parameter['type'])}"
        for index, parameter in enumerate(parameters)
    ]


def type_parameter_clause(parameters):
    if not parameters:
        return ""
    names = []
    for parameter in parameters:
        bound = parameter.get("bound")
        bound_type = bound.get("name") if bound else None
        names.append(f"{parameter['name']} : {safe_type(bound_type)}" if bound_type else parameter["name"])
    return "<" + ", ".join(names) + ">"


def probe_header(identifier, parameters, type_parameters=(), receiver_parameter=None):
    values = ([receiver_parameter] if receiver_parameter else []) + typed_function_parameters(parameters)
    type_clause = type_parameter_clause(type_parameters)
    generic_clause = f"{type_clause} " if type_clause else ""
    return f"fun {generic_clause}f01_{identifier.replace('-', '_')}({', '.join(values)}) {{"


def one_line_comment(text):
    return " ".join(text.replace("\r", " ").replace("\n", " ").split())


def property_probe(identifier, declaration, class_types, prefix=""):
    name = declaration["name"]
    owner = declaration.get("owner")
    receiver = declaration.get("receiver")
    if owner in class_types:
        receiver_parameter = f"target: {kotlin_name(owner)}"
        expression = f"target.{name}"
    elif receiver:
        object_name = OBJECT_RECEIVERS.get(receiver)
        if object_name:
            receiver_parameter = None
            expression = f"{object_name}.{name}"
        else:
            receiver_parameter = f"target: {safe_type(receiver)}"
            expression = f"target.{name}"
    else:
        receiver_parameter = None
        expression = kotlin_name(declaration["fqName"])
    header = probe_header(prefix + identifier, [], receiver_parameter=receiver_parameter)
    return [header, f"    {expression}", "}"]


def emit_probe(row, declaration):
    kind = declaration["kind"]
    identifier = row["row_id"]
    name = declaration.get("name", row["name"])
    owner = declaration.get("owner")
    receiver = declaration.get("receiver")
    parameters = declaration.get("parameters", [])
    fq_name = declaration.get("fqName", "")
    out = [f"// Ledger {identifier}: {one_line_comment(declaration['signature'])}"]

    if kind == "function":
        member = owner and owner in CLASS_TYPES
        receiver_type = safe_type(receiver) if receiver else None
        type_parameters = declaration.get("typeParameters", [])
        if member:
            out.append(probe_header(identifier, parameters, type_parameters, f"target: {kotlin_name(owner)}"))
            call_target = "target"
        elif receiver_type:
            object_name = OBJECT_RECEIVERS.get(receiver_type)
            if object_name:
                out.append(probe_header(identifier, parameters, type_parameters))
                call_target = object_name
            else:
                out.append(probe_header(identifier, parameters, type_parameters, f"target: {receiver_type}"))
                call_target = "target"
        else:
            out.append(probe_header(identifier, parameters, type_parameters))
            call_target = None

        call_name = name
        full_args = function_arguments(parameters)
        call = f"{call_target}.{call_name}({full_args})" if call_target else f"{call_name}({full_args})"
        out.append(f"    {call}")
        if any(parameter.get("default") is not None for parameter in parameters):
            omitted_args = function_arguments(parameters, omit_defaults=True, named=True)
            omitted_call = (
                f"{call_target}.{call_name}({omitted_args})"
                if call_target
                else f"{call_name}({omitted_args})"
            )
            out.append(f"    {omitted_call}")
        out.append("}")
        return out

    if kind == "constructor":
        class_name = kotlin_name(owner) if owner else kotlin_name(fq_name.rsplit(".", 1)[0])
        if owner in ANNOTATION_TYPES:
            out.extend([f"@{class_name}", f"fun f01_{identifier.replace('-', '_')}() {{", "}"])
            return out
        out.append(probe_header(identifier, parameters, declaration.get("typeParameters", [])))
        out.append(f"    {class_name}({function_arguments(parameters)})")
        if any(parameter.get("default") is not None for parameter in parameters):
            out.append(f"    {class_name}({function_arguments(parameters, omit_defaults=True)})")
        out.append("}")
        return out

    if kind == "property":
        member = owner and owner in CLASS_TYPES
        if member:
            out.append(f"fun f01_{identifier.replace('-', '_')}(target: {kotlin_name(owner)}) {{")
            expression = f"target.{name}"
        elif receiver:
            receiver_name = OBJECT_RECEIVERS.get(receiver, safe_type(receiver))
            if receiver in OBJECT_RECEIVERS:
                out.append(f"fun f01_{identifier.replace('-', '_')}() {{")
                expression = f"{receiver_name}.{name}"
            else:
                out.append(
                    f"fun f01_{identifier.replace('-', '_')}(target: {receiver_name}) {{"
                )
                expression = f"target.{name}"
        else:
            out.append(f"fun f01_{identifier.replace('-', '_')}() {{")
            expression = kotlin_name(fq_name)
        out.extend([f"    {expression}", "}"])
        return out

    if kind == "annotation class":
        out.extend([f"@{kotlin_name(fq_name)}", f"fun f01_{identifier.replace('-', '_')}() {{", "}"])
        return out

    if kind in ("class", "interface", "object", "typealias"):
        if kind == "object":
            out.extend([f"fun f01_{identifier.replace('-', '_')}() {{", f"    {kotlin_name(fq_name)}", "}"])
        else:
            out.extend(
                [
                    f"fun f01_{identifier.replace('-', '_')}(value: {kotlin_name(fq_name)}) {{",
                    "    value.hashCode()",
                    "}",
                ]
            )
        return out

    raise ValueError(f"unsupported declaration kind {kind!r} for {identifier}")


def render_consumer(rows, by_source, scope):
    is_jvm_consumer = scope == "jvm-common"
    api_scope = "common" if is_jvm_consumer else scope
    selected = [
        row
        for row in rows
        if row["representation"] == IN_SCOPE_REPRESENTATION
        and row["source_api"] == "yes"
        and row["platform_scope"] == api_scope
        and row["deprecation"] in ("", "none", "not-applicable")
        and (not is_jvm_consumer or row["jvm_abi_refs"])
    ]
    selected.sort(key=lambda row: row["row_id"])
    declarations = [pick_declaration(row, by_source) for row in selected]
    class_types = {
        declaration["fqName"]
        for declaration in by_source_values(by_source)
        if declaration.get("kind") in ("class", "interface", "object", "annotation class")
    }
    annotation_types = {
        declaration["fqName"]
        for declaration in by_source_values(by_source)
        if declaration.get("kind") == "annotation class"
    }
    global CLASS_TYPES
    global ANNOTATION_TYPES
    CLASS_TYPES = class_types
    ANNOTATION_TYPES = annotation_types

    imports = list(IMPORTS)
    markers = list(OPT_INS)
    if scope == "apple-only":
        imports.extend(("import kotlinx.cinterop.*", "import platform.Foundation.*", "import kotlin.experimental.ExperimentalNativeApi"))
        markers.extend(
            (
                "kotlinx.cinterop.UnsafeNumber",
                "kotlinx.cinterop.BetaInteropApi",
                "kotlinx.cinterop.ExperimentalForeignApi",
                "kotlin.experimental.ExperimentalNativeApi",
            )
        )
    lines = [
        "// Generated by Scripts/io_api_inventory/generate_f01_consumers.py.",
        "// Do not edit by hand; regenerate from api-inventory.tsv and source-declarations.json.",
        "@file:OptIn(",
        *[f"    {marker}::class," for marker in markers],
        ")",
        *imports,
        "",
    ]
    if len(selected) != len(declarations):
        raise ValueError("selected API rows and source declarations must have matching counts")
    for row, declaration in zip(selected, declarations):
        lines.extend(emit_probe(row, declaration))
        lines.append("")
    return "\n".join(lines), selected


def by_source_values(by_source):
    for declarations in by_source.values():
        yield from declarations


def render_negative(rows, by_source):
    selected = [
        row
        for row in rows
        if row["representation"] == IN_SCOPE_REPRESENTATION
        and row["source_api"] == "yes"
        and row["platform_scope"] == "common"
        and row["deprecation"] not in ("", "none", "not-applicable")
    ]
    lines = [
        "// Generated by Scripts/io_api_inventory/generate_f01_consumers.py.",
        "// Deprecated API references must be rejected with the ledger's deprecation contract.",
        *IMPORTS,
        "",
    ]
    for row in sorted(selected, key=lambda item: item["row_id"]):
        declaration = pick_declaration(row, by_source)
        identifier = row["row_id"].replace("-", "_")
        lines.append(
            f"// Ledger {row['row_id']}: {one_line_comment(declaration['signature'])} "
            f"[annotations: {row['annotations']}]"
        )
        if declaration["kind"] == "function":
            receiver = declaration.get("receiver")
            parameters = declaration.get("parameters", [])
            if receiver:
                receiver_expr = OBJECT_RECEIVERS.get(receiver, "target")
                receiver_parameter = None if receiver in OBJECT_RECEIVERS else f"target: {safe_type(receiver)}"
                call = f"{receiver_expr}.{declaration['name']}({function_arguments(parameters)})"
            else:
                receiver_parameter = None
                call = f"{declaration['name']}({function_arguments(declaration.get('parameters', []))})"
            lines.extend(
                [
                    probe_header("negative_" + identifier, parameters, declaration.get("typeParameters", []), receiver_parameter),
                    f"    {call}",
                    "}",
                    "",
                ]
            )
            continue
        elif declaration["kind"] == "property":
            call = kotlin_name(declaration["fqName"])
        else:
            continue
        lines.extend([f"fun f01_negative_{identifier}() {{", f"    {call}", "}", ""])
    return "\n".join(lines), selected


def render_opt_in_negative(rows, by_source, markers=None):
    selected = [
        row
        for row in rows
        if row["representation"] == IN_SCOPE_REPRESENTATION
        and row["source_api"] == "yes"
        and row["platform_scope"] == "common"
        and any(marker in row["annotations"].split(",") for marker in API_OPT_IN_MARKERS)
        and (markers is None or any(marker in row["annotations"].split(",") for marker in markers))
    ]
    lines = [
        "// Generated by Scripts/io_api_inventory/generate_f01_consumers.py.",
        "// These references intentionally omit @OptIn and must retain their upstream opt-in diagnostics.",
        *IMPORTS,
        "",
    ]
    for row in sorted(selected, key=lambda item: item["row_id"]):
        declaration = pick_declaration(row, by_source)
        identifier = row["row_id"].replace("-", "_")
        lines.append(
            f"// Ledger {row['row_id']}: {one_line_comment(declaration['signature'])} "
            f"[annotations: {row['annotations']}]"
        )
        if declaration["kind"] == "function":
            receiver = declaration.get("receiver")
            parameters = declaration.get("parameters", [])
            receiver_parameter = None
            if receiver:
                receiver_expr = OBJECT_RECEIVERS.get(receiver, "target")
                if receiver not in OBJECT_RECEIVERS:
                    receiver_parameter = f"target: {safe_type(receiver)}"
                call = f"{receiver_expr}.{declaration['name']}({function_arguments(parameters)})"
            elif declaration.get("owner") in CLASS_TYPES:
                receiver_expr = "target"
                receiver_parameter = f"target: {kotlin_name(declaration['owner'])}"
                call = (
                    f"{receiver_expr}.{declaration['name']}"
                    f"({function_arguments(parameters)})"
                )
            else:
                call = f"{declaration['name']}({function_arguments(parameters)})"
            lines.extend(
                [
                    probe_header("opt_in_" + identifier, parameters, declaration.get("typeParameters", []), receiver_parameter),
                    f"    {call}",
                    "}",
                    "",
                ]
            )
            continue
        elif declaration["kind"] == "property":
            lines.extend(property_probe(identifier, declaration, CLASS_TYPES, prefix="opt_in_"))
            lines.append("")
        elif declaration["kind"] in ("class", "interface", "object", "annotation class"):
            if declaration["kind"] == "object":
                expression = kotlin_name(declaration["fqName"])
                lines.extend([f"fun f01_opt_in_{identifier}() {{", f"    {expression}", "}", ""])
            else:
                lines.extend(
                    [
                        f"fun f01_opt_in_{identifier}(value: {kotlin_name(declaration['fqName'])}) {{",
                        "    value.hashCode()",
                        "}",
                        "",
                    ]
                )
        else:
            raise ValueError(f"unsupported opt-in declaration kind for {row['row_id']}: {declaration['kind']}")
    return "\n".join(lines), selected


def render_internal_negative(rows, by_source):
    selected = [
        row
        for row in rows
        if row["representation"] == "@PublishedApi internal source declaration"
    ]
    lines = [
        "// Generated by Scripts/io_api_inventory/generate_f01_consumers.py.",
        "// @PublishedApi implementation declarations must remain hidden from user source.",
        "@file:OptIn(",
        *[f"    {marker}::class," for marker in OPT_INS],
        ")",
        *IMPORTS,
        "",
    ]
    for row in sorted(selected, key=lambda item: item["row_id"]):
        declaration = pick_declaration(row, by_source)
        identifier = row["row_id"].replace("-", "_")
        lines.append(f"// Ledger {row['row_id']}: {one_line_comment(declaration['signature'])}")
        kind = declaration["kind"]
        if kind == "function":
            receiver = declaration.get("receiver")
            parameters = declaration.get("parameters", [])
            receiver_parameter = None
            if receiver:
                receiver_expr = OBJECT_RECEIVERS.get(receiver, "target")
                if receiver not in OBJECT_RECEIVERS:
                    receiver_parameter = f"target: {safe_type(receiver)}"
                call = f"{receiver_expr}.{declaration['name']}({function_arguments(parameters)})"
            elif declaration.get("owner") in CLASS_TYPES:
                receiver_expr = "target"
                receiver_parameter = f"target: {kotlin_name(declaration['owner'])}"
                call = (
                    f"{receiver_expr}.{declaration['name']}"
                    f"({function_arguments(parameters)})"
                )
            else:
                call = f"{declaration['name']}({function_arguments(parameters)})"
            lines.extend(
                [
                    probe_header("internal_" + identifier, parameters, declaration.get("typeParameters", []), receiver_parameter),
                    f"    {call}",
                    "}",
                    "",
                ]
            )
            continue
        elif kind == "property":
            lines.extend(property_probe(identifier, declaration, CLASS_TYPES, prefix="internal_"))
            lines.append("")
        elif kind in ("class", "interface", "annotation class", "typealias"):
            lines.extend(
                [
                    f"fun f01_internal_{identifier}(value: {kotlin_name(declaration['fqName'])}) {{",
                    "    value.hashCode()",
                    "}",
                    "",
                ]
            )
        elif kind == "constructor":
            class_name = kotlin_name(declaration.get("owner") or declaration["fqName"].rsplit(".", 1)[0])
            lines.extend(
                [
                    f"fun f01_internal_{identifier}() {{",
                    f"    {class_name}({function_arguments(declaration.get('parameters', []))})",
                    "}",
                    "",
                ]
            )
        else:
            raise ValueError(f"unsupported internal declaration kind for {row['row_id']}: {kind}")
    return "\n".join(lines), selected


def render_invalid_negative(guards):
    lines = [
        "// Generated by Scripts/io_api_inventory/generate_f01_consumers.py.",
        "// Each call is listed in negative-api-guards.tsv as absent from pinned kotlinx-io 0.9.1.",
        "import kotlinx.io.*",
        "import kotlinx.io.bytestring.*",
        "",
        "fun f01_invalid(buffer: Buffer, bytes: ByteString) {",
    ]
    for guard in guards:
        lines.extend(
            [
                f"    // Guard {guard['guard_id']}: {one_line_comment(guard['upstream_absence'])}",
                f"    {guard['call']}",
            ]
        )
    lines.extend(["}", ""])
    return "\n".join(lines)


def render_manifest(rows, invalid_guards):
    entries = [
        {
            "row_id": row["row_id"],
            "scope": row["platform_scope"],
            "api_kind": row["api_kind"],
            "upstream_source_refs": row["upstream_source_refs"],
        }
        for row in rows
        if row["representation"] == IN_SCOPE_REPRESENTATION and row["source_api"] == "yes"
    ]
    entries.sort(key=lambda item: item["row_id"])
    return json.dumps(
        {
            "generated_from": ["api-inventory.tsv", "negative-api-guards.tsv"],
            "entries": entries,
            "negative_api_guards": invalid_guards,
        },
        indent=2,
    ) + "\n"


def generate():
    rows, by_source = read_inputs()
    invalid_guards = read_invalid_guards()
    validate_invalid_guard_absence(invalid_guards, by_source)
    common, common_rows = render_consumer(rows, by_source, "common")
    jvm, jvm_rows = render_consumer(rows, by_source, "jvm-common")
    apple, apple_rows = render_consumer(rows, by_source, "apple-only")
    platform, platform_rows = render_consumer(
        rows,
        by_source,
        next(
            (row["platform_scope"] for row in rows if row["representation"] == IN_SCOPE_REPRESENTATION
             and row["source_api"] == "yes" and row["platform_scope"].startswith("platform-only:")),
            "platform-only",
        ),
    )
    negative, negative_rows = render_negative(rows, by_source)
    opt_in_negative, opt_in_rows = render_opt_in_negative(rows, by_source)
    opt_in_warning_negative, opt_in_warning_rows = render_opt_in_negative(
        rows, by_source, {"DelicateIoApi", "UnsafeIoApi"}
    )
    opt_in_error_negative, opt_in_error_rows = render_opt_in_negative(
        rows, by_source, {"InternalIoApi", "UnsafeByteStringApi"}
    )
    internal_negative, internal_rows = render_internal_negative(rows, by_source)
    expected = [
        row for row in rows
        if row["representation"] == IN_SCOPE_REPRESENTATION and row["source_api"] == "yes"
        and row["deprecation"] in ("", "none", "not-applicable")
    ]
    represented_ids = {
        row["row_id"] for row in common_rows + apple_rows + platform_rows
    }
    expected_ids = {row["row_id"] for row in expected}
    if represented_ids != expected_ids:
        missing = sorted(expected_ids - represented_ids)
        extra = sorted(represented_ids - expected_ids)
        raise ValueError(f"consumer coverage mismatch: missing={missing}, extra={extra}")
    return {
        "positive-common.kt": common,
        "positive-jvm.kt": jvm,
        "positive-apple.kt": apple,
        "positive-platform.kt": platform,
        "negative-deprecated.kt": negative,
        "negative-opt-in.kt": opt_in_negative,
        "negative-opt-in-warning.kt": opt_in_warning_negative,
        "negative-opt-in-error.kt": opt_in_error_negative,
        "negative-internal.kt": internal_negative,
        "negative-invalid.kt": render_invalid_negative(invalid_guards),
        "consumer-manifest.json": render_manifest(rows, invalid_guards),
    }, {
        "positive_common": len(common_rows),
        "positive_jvm": len(jvm_rows),
        "positive_apple": len(apple_rows),
        "positive_platform": len(platform_rows),
        "negative_deprecated": len(negative_rows),
        "negative_opt_in": len(opt_in_rows),
        "negative_opt_in_warning": len(opt_in_warning_rows),
        "negative_opt_in_error": len(opt_in_error_rows),
        "negative_internal": len(internal_rows),
        "negative_invalid": len(invalid_guards),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    outputs, counts = generate()
    mismatches = []
    for name, expected in outputs.items():
        path = OUTPUT / name
        if args.write:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(expected)
        elif not path.exists() or path.read_text() != expected:
            mismatches.append(name)
    if mismatches:
        raise SystemExit("generated F01 consumers are stale: " + ", ".join(mismatches))
    print("F01 consumer coverage: " + ", ".join(f"{key}={value}" for key, value in counts.items()))


if __name__ == "__main__":
    main()
