#!/usr/bin/env python3
"""Build a deterministic per-declaration index for atomicfu 0.33.0 KLIB API."""

from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "docs/atomicfu-0.33.0/reference"
INDEX_PATH = REFERENCE / "atomicfu.common-native.declarations.json"
UPSTREAM_COMMIT = "fc175fc575419ca9eae0d3c14cefe9c5cd7ca351"
KLIB_BLOB_SHA1 = "d170cb60f282c47b96d2c98041a7f5f2bf2e5850"
EXPECTED_LEGACY_SIGNATURES = 130
EXPECTED_TOTAL_DECLARATIONS = 155
EXPECTED_COMMON_NATIVE_DECLARATIONS = 150
EXPECTED_COMMON_NATIVE_SIGNATURES = 126
EXPECTED_INHERITED_JS_WASM_DECLARATIONS = 5

# Git blob hashes for the source declarations and annotations referenced by the
# index. Files are pinned at UPSTREAM_COMMIT and are not compiler inputs.
SOURCE_BLOBS = {
    "atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/AtomicFU.common.kt": "721d86023038690cb7feffda049188ce1d2d9979",
    "atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/OptionalJsName.kt": "d27c84e83bb05240beb3049e5eea97c268ab9a09",
    "atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/Trace.common.kt": "7105ca2e6fa124364460a12ab2ad6fa30c1b2476",
    "atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/TraceFormat.kt": "99969bfa0c250fff7f8aca7105fc27a8cba98a00",
    "atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/locks/SynchronousMutex.kt": "8de86a013b951a93838d206cbcaf63ba27180b2e",
    "atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/locks/Synchronized.common.kt": "ae0ea685437c061c98ccfd2d6fade06b22258199",
    "atomicfu/src/concurrentMain/kotlin/kotlinx/atomicfu/locks/ParkingSupport.kt": "d52c9593e8b6264e143a53e4f26200da9c8ecc13",
    "atomicfu/src/jsAndWasmSharedMain/kotlin/kotlinx/atomicfu/locks/Synchronized.kt": "acb538d055f2283bb0cdbcc821168b309011e267",
    "atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/AtomicFU.kt": "61c33a9fdc20515562661fe063f6bf34ded1e038",
    "atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/Trace.kt": "9d8dcbf2e7a2e4774cadb7024c717b260f4f8511",
    "atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/locks/ParkingSupport.kt": "d1fb1e6c42649f4e05b6ad8a340052f6cbb14640",
    "atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/locks/SynchronousMutex.kt": "cd50f621c1057f7edf6595a37bb185da99b01868",
    "atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/locks/Synchronized.kt": "2cfa72ce247c6a2bd89560a1c70918d029c1e313",
}

NATIVE_TARGETS = {
    "androidNativeArm32",
    "androidNativeArm64",
    "androidNativeX64",
    "androidNativeX86",
    "iosArm64",
    "iosSimulatorArm64",
    "iosX64",
    "linuxArm32Hfp",
    "linuxArm64",
    "linuxX64",
    "macosArm64",
    "macosX64",
    "mingwX64",
    "tvosArm64",
    "tvosSimulatorArm64",
    "tvosX64",
    "watchosArm32",
    "watchosArm64",
    "watchosDeviceArm64",
    "watchosSimulatorArm64",
    "watchosX64",
}
DECLARATION_PREFIXES = (
    "final class ",
    "open class ",
    "abstract class ",
    "enum class ",
    "final object ",
    "open object ",
    "constructor ",
    "final val ",
    "final var ",
    "open val ",
    "open var ",
    "final fun ",
    "final inline fun ",
    "open fun ",
    "final inline operator fun ",
    "final operator fun ",
    "final inline suspend fun ",
    "final suspend fun ",
    "final annotation class ",
    "open annotation class ",
    "abstract interface annotation class ",
)
CLASS_PREFIXES = (
    "final class ",
    "open class ",
    "abstract class ",
    "enum class ",
    "final object ",
    "open object ",
    "final annotation class ",
    "open annotation class ",
    "abstract interface annotation class ",
)
PROPERTY_PREFIXES = ("final val ", "final var ", "open val ", "open var ")


def is_declaration(line: str) -> bool:
    return line.startswith(DECLARATION_PREFIXES)


def is_native(targets: tuple[str, ...]) -> bool:
    return "native" in targets or bool(NATIVE_TARGETS.intersection(targets))


def target_expression(targets: tuple[str, ...], default_targets: tuple[str, ...]) -> str:
    if targets == default_targets:
        return "default (all targets listed by the KLIB dump)"
    return "[" + ", ".join(targets) + "]"


def parse_api_records(contents: bytes) -> tuple[tuple[str, ...], dict[str, dict[str, Any]]]:
    """Parse declarations while inheriting target comments through class/property scopes."""
    lines = contents.decode("utf-8").splitlines()
    target_header = next(
        (line for line in lines if line.startswith("// Targets:")), None
    )
    if target_header is None:
        raise ValueError("KLIB dump has no global Targets header")
    default_targets = tuple(
        item.strip()
        for item in target_header.removeprefix("// Targets:").strip().strip("[]").split(",")
        if item.strip()
    )

    # Each scope is (indent, target set). KLIB API comments on a class or
    # property govern nested members unless a member has its own Targets line.
    target_scopes: list[tuple[int, tuple[str, ...]]] = []
    pending_targets: tuple[str, ...] | None = None
    records: dict[str, dict[str, Any]] = {}

    for raw_line in lines:
        line = raw_line.strip()
        indent = len(raw_line) - len(raw_line.lstrip())
        if line.startswith("// Targets:"):
            pending_targets = tuple(
                item.strip()
                for item in line.removeprefix("// Targets:").strip().strip("[]").split(",")
                if item.strip()
            )
            continue

        if is_declaration(line):
            while target_scopes and indent <= target_scopes[-1][0]:
                target_scopes.pop()
            inherited_targets = target_scopes[-1][1] if target_scopes else default_targets
            effective_targets = pending_targets or inherited_targets
            signature, separator, api_identity = line.partition(" // ")
            if not separator:
                raise ValueError(f"KLIB declaration lacks ABI identity: {line}")
            signature = signature.strip()
            identity = api_identity.strip()
            api_symbol = identity.split("|", maxsplit=1)[0]
            if not api_symbol:
                raise ValueError(f"empty ABI symbol for KLIB declaration: {line}")

            # Preserve the flat parser's 130 candidates for auditability, but
            # classify inherited JS/Wasm entries separately. This prevents
            # child members from being mislabeled common/native.
            flat_native_candidate = pending_targets is None or is_native(pending_targets)
            if is_native(effective_targets) or flat_native_candidate:
                key = (identity, signature)
                record = records.setdefault(
                    key,
                    {
                        "signature": signature,
                        "api_identity": identity,
                        "api_symbol": api_symbol,
                        "target_expressions": set(),
                        "effective_targets": set(),
                        "common_native": False,
                        "flat_candidate": False,
                    },
                )
                record["target_expressions"].add(
                    target_expression(effective_targets, default_targets)
                )
                record["effective_targets"].update(effective_targets)
                record["common_native"] |= is_native(effective_targets)
                record["flat_candidate"] |= flat_native_candidate

            if line.startswith(CLASS_PREFIXES) or line.startswith(PROPERTY_PREFIXES):
                target_scopes.append((indent, effective_targets))
            pending_targets = None
            continue

        if line == "}":
            while target_scopes and indent <= target_scopes[-1][0]:
                target_scopes.pop()
            pending_targets = None

    return default_targets, records


def declaration_kind(signature: str) -> str:
    if "annotation class " in signature:
        return "annotation_class"
    if signature.startswith(CLASS_PREFIXES):
        return "class"
    if signature.startswith(("final object ", "open object ")):
        return "object"
    if signature.startswith("constructor "):
        return "constructor"
    if signature.startswith(PROPERTY_PREFIXES):
        return "property"
    return "function"


def has_name(signature: str, name: str) -> bool:
    return re.search(rf"(?<![A-Za-z0-9_]){re.escape(name)}(?![A-Za-z0-9_])", signature) is not None


def source_paths_for(api_symbol: str, signature: str, common_native: bool) -> list[tuple[str, str]]:
    """Return (pinned path, role) references for this exact source/API entry."""
    symbol = api_symbol
    text = f"{api_symbol} {signature}"

    if "kotlinx.atomicfu/OptionalJsName" in symbol:
        return [("atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/OptionalJsName.kt", "common expect annotation")]

    if "kotlinx.atomicfu.locks/ExperimentalThreadBlockingApi" in symbol:
        return [("atomicfu/src/concurrentMain/kotlin/kotlinx/atomicfu/locks/ParkingSupport.kt", "concurrent declaration")]

    if "ParkingSupport" in text or "ParkingHandle" in text:
        return [
            ("atomicfu/src/concurrentMain/kotlin/kotlinx/atomicfu/locks/ParkingSupport.kt", "concurrent expect/declaration"),
            ("atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/locks/ParkingSupport.kt", "native actual"),
        ]

    if "SynchronousMutex" in text:
        common = "atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/locks/SynchronousMutex.kt"
        native = "atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/locks/SynchronousMutex.kt"
        if api_symbol.endswith("/withLock"):
            return [(common, "common inline implementation")]
        return [(common, "common expect"), (native, "native actual")]

    if "SynchronizedObject" in text or "ReentrantLock" in text or "Lock" in text and "kotlinx.atomicfu.locks/" in symbol:
        common = "atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/locks/Synchronized.common.kt"
        native = "atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/locks/Synchronized.kt"
        js_shared = "atomicfu/src/jsAndWasmSharedMain/kotlin/kotlinx/atomicfu/locks/Synchronized.kt"
        if not common_native:
            if api_symbol.endswith("/Lock.<get-Lock>"):
                return [(js_shared, "JS/Wasm actual property accessor")]
            if "ReentrantLock." in api_symbol:
                return [(common, "common expect API"), (js_shared, "JS/Wasm actual member")]
        if "SynchronizedObject." in api_symbol and any(
            api_symbol.endswith("." + name) for name in ("lock", "tryLock", "unlock")
        ):
            return [(native, "native actual member")]
        if "SynchronizedObject" in api_symbol and api_symbol.endswith("/SynchronizedObject"):
            return [(common, "common expect"), (native, "native actual")]
        if api_symbol.endswith("/reentrantLock") or api_symbol.endswith("/withLock") or api_symbol.endswith("/synchronized"):
            return [(common, "common expect"), (native, "native actual")]
        return [(common, "common expect"), (native, "native actual")]

    if "TraceFormat" in text:
        return [("atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/TraceFormat.kt", "common declaration")]

    if (
        api_symbol.startswith("kotlinx.atomicfu/TraceBase")
        or api_symbol.endswith("/Trace")
        or "/traceFormatDefault" in api_symbol
        or api_symbol.endswith("/named")
    ):
        common = "atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/Trace.common.kt"
        if any(token in api_symbol for token in ("/Trace", "/named", "/traceFormatDefault")):
            return [(common, "common expect/declaration"), ("atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/Trace.kt", "native actual")]
        return [(common, "common declaration")]

    if "kotlinx.atomicfu/Atomic" in text or api_symbol.endswith("/atomic") or api_symbol.endswith("/atomicArrayOfNulls"):
        arrays = ("AtomicArray", "AtomicBooleanArray", "AtomicIntArray", "AtomicLongArray")
        if any(name in text for name in arrays) or api_symbol.endswith("/atomicArrayOfNulls"):
            return [("atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/AtomicFU.common.kt", "common declaration")]
        if re.search(r"Atomic(?:Ref|Boolean|Int|Long)\.a(?:\.|$)", api_symbol):
            return [("atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/AtomicFU.kt", "native internal actual")]
        if api_symbol.endswith("/atomic"):
            return [
                ("atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/AtomicFU.common.kt", "common expect"),
                ("atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/AtomicFU.kt", "native actual"),
            ]
        if api_symbol in {
            "kotlinx.atomicfu/loop",
            "kotlinx.atomicfu/update",
            "kotlinx.atomicfu/getAndUpdate",
            "kotlinx.atomicfu/updateAndGet",
        }:
            return [("atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/AtomicFU.common.kt", "common inline implementation")]
        return [
            ("atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/AtomicFU.common.kt", "common expect"),
            ("atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/AtomicFU.kt", "native actual"),
        ]

    raise ValueError(f"no pinned source mapping for API declaration {api_symbol}: {signature}")


def direct_annotations(path: str, api_symbol: str, signature: str) -> list[str]:
    symbol = api_symbol
    if path.endswith("OptionalJsName.kt") and symbol == "kotlinx.atomicfu/OptionalJsName":
        return ["OptIn", "OptionalExpectation", "Retention", "Target", "Deprecated"]

    if path.endswith("AtomicFU.common.kt"):
        if symbol.endswith("/atomicArrayOfNulls"):
            return ["Deprecated", "Suppress", "OptionalJsName"]
        if re.search(r"/Atomic(?:Boolean|Int|Long)?Array(?:$|[.(])", symbol):
            if symbol.endswith(("AtomicArray", "AtomicBooleanArray", "AtomicIntArray", "AtomicLongArray")) or ".<init>" in symbol:
                return ["Deprecated", "Suppress", "OptionalJsName"]
            if symbol.endswith(".get"):
                return ["OptionalJsName"]
            if symbol.endswith(".size"):
                return ["OptionalJsName"]
        if re.search(r"/Atomic(?:Ref|Boolean|Int|Long)\.(?:getValue|setValue)$", symbol):
            return ["InlineOnly"]

    if path.endswith("AtomicFU.kt"):
        if re.search(r"/Atomic(?:Ref|Boolean|Int|Long)\.a$", symbol):
            return ["PublishedApi"]
        if re.search(r"/Atomic(?:Ref|Boolean|Int|Long)\.(?:getValue|setValue)$", symbol):
            return ["InlineOnly"]

    if path.endswith("Trace.common.kt"):
        if symbol.endswith("/Trace"):
            return ["Suppress"]
        if symbol.endswith("/TraceBase"):
            return ["Suppress", "OptionalJsName"]
        if symbol.startswith("kotlinx.atomicfu/TraceBase.append"):
            return ["OptionalJsName"]
        if symbol.endswith("TraceBase.invoke"):
            return ["InlineOnly"]

    if path.endswith("Trace.kt") and symbol.endswith("/Trace"):
        return ["Suppress"]

    if path.endswith("TraceFormat.kt"):
        if symbol.endswith("/TraceFormat"):
            if "crossinline" in signature:
                return ["InlineOnly"]
            if "class " in signature:
                return ["Suppress", "OptionalJsName"]
        if symbol.endswith("TraceFormat.format"):
            return ["Suppress", "OptionalJsName"]

    if path.endswith("SynchronousMutex.kt") and path.startswith("atomicfu/src/commonMain") and symbol.endswith("/withLock"):
        return ["OptIn"]

    if path.endswith("ParkingSupport.kt"):
        if symbol.endswith(("/ParkingSupport", "/ParkingHandle")):
            return ["ExperimentalThreadBlockingApi"]
        if symbol.endswith("/ExperimentalThreadBlockingApi"):
            return ["Retention", "Target", "RequiresOptIn"]

    if path.endswith("Synchronized.kt") and path.startswith("atomicfu/src/jsAndWasmSharedMain") and symbol.endswith("/Lock.<get-Lock>"):
        return ["OptionalJsName"]

    return []


def inherited_annotations(path: str, api_symbol: str) -> list[str]:
    if path.endswith("OptionalJsName.kt") and api_symbol.startswith("kotlinx.atomicfu/OptionalJsName."):
        return ["Deprecated"]
    if path.endswith("ParkingSupport.kt") and "ParkingSupport." in api_symbol:
        return ["ExperimentalThreadBlockingApi"]
    if path.endswith("AtomicFU.kt") and re.search(r"/Atomic(?:Ref|Boolean|Int|Long)\.a\.<get-a>$", api_symbol):
        return ["PublishedApi"]
    if path.endswith("AtomicFU.common.kt") and re.search(r"/Atomic(?:Array|BooleanArray|IntArray|LongArray)\.size\.<get-size>$", api_symbol):
        return ["OptionalJsName"]
    return []


def visibility_for(path: str, api_symbol: str) -> str:
    if path.endswith("AtomicFU.kt") and re.search(r"/Atomic(?:Ref|Boolean|Int|Long)\.a(?:\.<get-a>)?$", api_symbol):
        return "internal"
    return "public"


def source_reference(path: str, role: str, api_symbol: str, signature: str) -> dict[str, Any]:
    if path not in SOURCE_BLOBS:
        raise ValueError(f"source path missing pinned Git blob: {path}")
    annotations = direct_annotations(path, api_symbol, signature)
    inherited = inherited_annotations(path, api_symbol)
    file_annotations = []
    if path.endswith(("AtomicFU.common.kt", "Trace.common.kt", "TraceFormat.kt")):
        file_annotations = ["Suppress"]
    elif path.endswith("AtomicFU.kt"):
        file_annotations = ["Suppress"]
    elif path.endswith("Synchronized.kt") and path.startswith("atomicfu/src/jsAndWasmSharedMain"):
        file_annotations = ["Suppress"]
    return {
        "path": path,
        "git_blob_sha1": SOURCE_BLOBS[path],
        "role": role,
        "visibility": visibility_for(path, api_symbol),
        "annotations": annotations,
        "inherited_annotations": inherited,
        "file_annotations": file_annotations,
        "annotation_evidence": (
            "pinned declaration has no direct annotation; source blob and API symbol identify the checked declaration"
            if not annotations
            else "direct annotations on the pinned declaration"
        ),
    }


def build_declaration_index(klib_contents: bytes) -> dict[str, Any]:
    default_targets, records = parse_api_records(klib_contents)
    selected = [record for record in records.values() if record["common_native"]]
    inherited_js = [
        record
        for record in records.values()
        if record["flat_candidate"] and not record["common_native"]
    ]
    unique_selected_signatures = {row["signature"] for row in selected}
    unique_legacy_signatures = {row["signature"] for row in records.values()}
    if (
        len(selected),
        len(unique_selected_signatures),
        len(inherited_js),
        len(records),
        len(unique_legacy_signatures),
    ) != (
        EXPECTED_COMMON_NATIVE_DECLARATIONS,
        EXPECTED_COMMON_NATIVE_SIGNATURES,
        EXPECTED_INHERITED_JS_WASM_DECLARATIONS,
        EXPECTED_TOTAL_DECLARATIONS,
        EXPECTED_LEGACY_SIGNATURES,
    ):
        raise ValueError(
            "pinned API identity inventory count changed: "
            f"common/native declarations={len(selected)}, "
            f"common/native signatures={len(unique_selected_signatures)}, "
            f"inherited JS/Wasm declarations={len(inherited_js)}, "
            f"total declarations={len(records)}, "
            f"legacy distinct signatures={len(unique_legacy_signatures)}"
        )

    ordered = sorted(
        records.values(),
        key=lambda row: (not row["common_native"], row["api_symbol"], row["signature"]),
    )
    overload_groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in ordered:
        group = record["api_symbol"]
        overload_groups[group].append(record)

    declarations = []
    for record in ordered:
        signature = record["signature"]
        api_symbol = record["api_symbol"]
        common_native = record["common_native"]
        source_refs = source_paths_for(api_symbol, signature, common_native)
        sources = [source_reference(path, role, api_symbol, signature) for path, role in source_refs]
        group_rows = overload_groups[api_symbol]
        overload_index = next(i for i, item in enumerate(group_rows, start=1) if item is record)
        declarations.append(
            {
                "scope": "common-native" if common_native else "js-wasm-only (inherited target scope; excluded)",
                "signature": signature,
                "api_identity": record["api_identity"],
                "api_symbol": api_symbol,
                "kind": declaration_kind(signature),
                "overload_group": api_symbol,
                "overload_index": overload_index,
                "overload_count": len(group_rows),
                "klib_target_expressions": sorted(record["target_expressions"]),
                "kotlin_visibility": (
                    next(iter({source["visibility"] for source in sources}))
                    if len({source["visibility"] for source in sources}) == 1
                    else "mixed"
                ),
                "source_provenance": sources,
            }
        )

    source_paths_used = sorted(
        {
            source["path"]
            for declaration in declarations
            for source in declaration["source_provenance"]
        }
    )
    return {
        "schema_version": 1,
        "upstream": {
            "repository": "Kotlin/kotlinx-atomicfu",
            "version": "0.33.0",
            "commit": UPSTREAM_COMMIT,
            "api_snapshot": "atomicfu.klib.api",
            "api_git_blob_sha1": KLIB_BLOB_SHA1,
            "default_targets": list(default_targets),
        },
        "summary": {
            "common_native_declarations": len(selected),
            "common_native_unique_signatures": len(unique_selected_signatures),
            "inherited_js_wasm_exclusions": len(inherited_js),
            "total_api_identity_rows": len(declarations),
            "legacy_flat_unique_signatures": len(unique_legacy_signatures),
        },
        "target_scope_note": (
            "Targets comments inherit through KLIB class and property scopes. The legacy flat pass has 130 unique "
            "rendered signatures, but 24 of those signatures identify more than one declaration owner. The "
            "identity-preserving index has 150 common/native declarations (126 unique rendered signatures) and "
            "five inherited JS/Wasm-only declaration identities; those exclusions remain listed with their effective "
            "targets."
        ),
        "pinned_source_files": [
            {"path": path, "git_blob_sha1": SOURCE_BLOBS[path]}
            for path in source_paths_used
        ],
        "declarations": declarations,
    }


def render_index(klib_contents: bytes) -> bytes:
    document = build_declaration_index(klib_contents)
    return (json.dumps(document, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="regenerate the checked-in declaration JSON")
    args = parser.parse_args()
    klib = (REFERENCE / "atomicfu.klib.api").read_bytes()
    generated = render_index(klib)
    if args.write:
        INDEX_PATH.write_bytes(generated)
        print(f"WROTE {INDEX_PATH.relative_to(ROOT)}")
    elif INDEX_PATH.read_bytes() != generated:
        raise SystemExit(f"{INDEX_PATH.relative_to(ROOT)} is stale; run {Path(__file__).name} --write")
    else:
        print(f"PASS deterministic declaration index: {INDEX_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
