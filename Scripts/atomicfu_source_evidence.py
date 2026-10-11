"""Verify atomicfu ledger facts against exact pinned Kotlin source spans.

This is a fixed-source evidence reader, not a general Kotlin compiler. Explicit
ABI-identity anchors disambiguate overloads and implicit declarations. Unknown
source syntax fails instead of silently manufacturing annotation facts.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "docs/atomicfu-0.33.0/reference"


def blob_sha1(data: bytes) -> str:
    return hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()


def mask_noncode(text: str) -> str:
    # Keep offsets and newlines, removing comments and string contents. Kotlin
    # nested block comments and escaped quoted strings occur in these sources.
    result = list(text)
    i = 0
    while i < len(text):
        end = i
        if text.startswith("//", i):
            end = text.find("\n", i)
            if end < 0:
                end = len(text)
        elif text.startswith("/*", i):
            depth, end = 1, i + 2
            while depth:
                if end >= len(text):
                    raise ValueError("unterminated source comment")
                if text.startswith("/*", end):
                    depth += 1
                    end += 2
                elif text.startswith("*/", end):
                    depth -= 1
                    end += 2
                else:
                    end += 1
        elif text[i] in ('"', "'"):
            quote, end = text[i], i + 1
            while end < len(text):
                if text[end] == "\\":
                    end += 2
                elif text[end] == quote:
                    end += 1
                    break
                else:
                    end += 1
            else:
                raise ValueError("unterminated source literal")
        if end > i:
            for j in range(i, end):
                if result[j] != "\n":
                    result[j] = " "
            i = end
        else:
            i += 1
    return "".join(result)


def balanced_end(code: str, start: int) -> int:
    pairs = {"(": ")", "[": "]", "{": "}"}
    stack = [pairs[code[start]]]
    for i in range(start + 1, len(code)):
        char = code[i]
        if char in pairs:
            stack.append(pairs[char])
        elif char in pairs.values():
            if char != stack.pop():
                raise ValueError("unbalanced source delimiters")
            if not stack:
                return i + 1
    raise ValueError("unterminated source delimiters")


def split_arguments(raw: str) -> list[dict]:
    code = mask_noncode(raw)
    parts, depth, start = [], 0, 0
    for i, char in enumerate(code):
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(raw[start:i].strip())
            start = i + 1
    parts.append(raw[start:].strip())
    result = []
    for part in parts:
        if not part:
            continue
        match = re.match(r"^([A-Za-z_][A-Za-z_0-9]*)\s*=", mask_noncode(part))
        result.append({
            "name": match[1] if match else None,
            "expression": part[match.end():].strip() if match else part,
        })
    return result


class PinnedSource:
    def __init__(self, record: dict):
        self.record = record
        self.path = record["path"]
        data = (ROOT / record["local_path"]).read_bytes()
        if blob_sha1(data) != record["git_blob_sha1"]:
            raise ValueError(f"pinned source SHA mismatch: {self.path}")
        self.text = data.decode("utf-8")
        self.code = mask_noncode(self.text)
        self.annotations = []
        for match in re.finditer(r"@(?:(\w+):)?([\w.]+)", self.code):
            end = match.end()
            while end < len(self.code) and self.code[end].isspace():
                end += 1
            arguments = []
            if end < len(self.code) and self.code[end] == "(":
                close = balanced_end(self.code, end)
                arguments = split_arguments(self.text[end + 1:close - 1])
                end = close
            else:
                end = match.end()
            self.annotations.append({
                "name": match[2], "use_site_target": match[1],
                "arguments": arguments, "source": self.text[match.start():end],
                "start_offset": match.start(), "end_offset": end,
                "line": self.text.count("\n", 0, match.start()) + 1,
            })

    def prefix_annotations(self, start: int) -> list[dict]:
        result = []
        for annotation in reversed(self.annotations):
            if annotation["end_offset"] > start:
                continue
            if self.code[annotation["end_offset"]:start].strip():
                break
            if annotation["use_site_target"] == "file":
                break
            result.append(annotation)
            start = annotation["start_offset"]
        return list(reversed(result))

    def anchor(self, anchor: dict) -> tuple[int, str]:
        start = anchor["offset"]
        header = anchor["header"]
        if self.text[start:start + len(header)] != header:
            raise ValueError(f"source declaration anchor changed: {self.path}:{anchor['line']}")
        if self.text.count("\n", 0, start) + 1 != anchor["line"]:
            raise ValueError("source anchor line/offset mismatch")
        return start, header


def load_sources() -> tuple[dict, dict[str, PinnedSource]]:
    manifest = json.loads((REFERENCE / "atomicfu.source-manifest.json").read_text())
    if manifest["upstream_commit"] != "fc175fc575419ca9eae0d3c14cefe9c5cd7ca351":
        raise ValueError("unexpected source reference version")
    sources = {}
    for record in manifest["sources"]:
        if record["evidence_status"] == "pinned":
            sources[record["path"]] = PinnedSource(record)
        elif record != {
            "path": "atomicfu/src/jsAndWasmSharedMain/kotlin/kotlinx/atomicfu/locks/Synchronized.kt",
            "git_blob_sha1": "acb538d055f2283bb0cdbcc821168b309011e267",
            "local_path": None,
            "evidence_status": "unavailable-js-wasm-exclusion",
        }:
            raise ValueError("unexpected unavailable source")
    return manifest, sources


def annotation_records(records: list[dict], sources: dict) -> list[dict]:
    constants = sources["atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/MangledJsNames.kt"]
    declarations = {
        match[1]: {
            "path": constants.path,
            "git_blob_sha1": constants.record["git_blob_sha1"],
            "line": constants.text.count("\n", 0, match.start()) + 1,
            "expression": match[2],
        }
        for match in re.finditer(r'(?m)^internal const val (\w+) = ("(?:\\.|[^"\\])*")', constants.text)
    }
    output = []
    for record in records:
        record = {**record, "arguments": [dict(a) for a in record["arguments"]]}
        for argument in record["arguments"]:
            if argument["expression"] in declarations:
                argument["constant_reference"] = declarations[argument["expression"]]
        output.append(record)
    return output


def validate_callable_anchor(identity: str, source: PinnedSource, start: int, mode: str) -> None:
    """Reject overload/extension substitution even if the JSON is regenerated."""
    if mode not in {"declaration", "explicit_constructor"}:
        return
    code = source.code[start:]
    pattern = (r"constructor\s*\(" if mode == "explicit_constructor" else
               r"\bfun\s+(?:<[^\n>]+>\s*)?([\w<>?.]+)\s*\(")
    match = re.search(pattern, code.split("\n", 1)[0])
    if not match:
        return  # Nominal/property rows have no callable parameter list.
    opening = start + match.end() - 1
    close = balanced_end(source.code, opening)
    parameters = split_arguments(source.text[opening + 1:close - 1])
    symbol, abi = identity.split("|", 1)
    abi_parameters = abi[abi.index("(") + 1:abi.index(")")]
    expected_count = len(abi_parameters.split(";")) if abi_parameters else 0
    if len(parameters) != expected_count:
        raise ValueError(f"source overload arity does not match ABI identity: {identity}")
    if mode == "declaration":
        declared = match[1]
        receiver = declared.rsplit(".", 1)[0] if "." in declared else None
        expected_receiver = re.search(r"@kotlinx\.atomicfu(?:\.locks)?\.(\w+)", abi)
        if expected_receiver:
            expected = expected_receiver[1]
            # Native ReentrantLock is the upstream SynchronizedObject alias.
            expected = "ReentrantLock" if expected == "SynchronizedObject" and declared.endswith("withLock") else expected
            if receiver is None or re.sub(r"<.*>", "", receiver) != expected:
                raise ValueError(f"source extension receiver does not match ABI identity: {identity}")
        elif receiver is not None:
            raise ValueError(f"unexpected source extension receiver: {identity}")
        if symbol == "kotlinx.atomicfu/atomic":
            expected = abi_parameters.split(";", 1)[0]
            expected = expected.rsplit(".", 1)[-1] if expected.startswith("kotlin.") else "T"
            actual = parameters[0]["expression"].split(":", 1)[1].split("=", 1)[0].strip()
            if actual != expected:
                raise ValueError(f"source atomic factory overload type mismatch: {identity}")


def source_fact(identity: str, path: str, role: str, sources: dict, anchors: dict) -> dict:
    if path not in sources:
        if not identity.startswith("kotlinx.atomicfu.locks/"):
            raise ValueError("missing source outside JS/Wasm lock exclusion")
        return {
            "path": path, "git_blob_sha1": "acb538d055f2283bb0cdbcc821168b309011e267",
            "role": role, "evidence_status": "unavailable-js-wasm-exclusion",
            "visibility": None, "annotations": None, "annotation_records": None,
            "inherited_annotations": None, "enclosing_annotation_records": None,
            "file_annotations": None, "file_annotation_records": None,
            "declaration": None,
            "annotation_evidence": "source bytes unavailable; annotation names and arguments are not inferred",
        }
    source = sources[path]
    anchor = anchors[identity][path]
    start, header = source.anchor(anchor)
    mode = anchor["mode"]
    validate_callable_anchor(identity, source, start, mode)
    symbol = identity.split("|", 1)[0]
    name = symbol.rsplit("/", 1)[-1].split(".")[-1]
    if mode in {"implicit_constructor", "annotation_parameter", "parameter_accessor"}:
        if "class " not in header:
            raise ValueError("implicit declaration anchor is not a class header")
    elif mode in {"constructor_parameter", "constructor_parameter_accessor"}:
        if not re.search(r"\bval\s+a\s*:", header):
            raise ValueError("missing constructor property a")
    elif mode == "property_accessor":
        property_name = symbol.rsplit("/", 1)[-1].split(".")[-2]
        if not re.search(rf"\b(?:val|var)\s+{re.escape(property_name)}\b", header):
            raise ValueError("accessor anchor has wrong property owner")
    elif mode == "explicit_constructor":
        if "constructor" not in header:
            raise ValueError("constructor anchor lacks constructor")
    elif not re.search(rf"\b{re.escape(name)}\b", header):
        raise ValueError(f"source declaration name does not match ABI identity: {identity} in {path}: {header}")
    # An explicit owner header must belong to the requested nominal class.
    enclosing = []
    if anchor.get("owner"):
        owner_start, owner_header = source.anchor(anchor["owner"])
        expected_owner = symbol.rsplit("/", 1)[-1].split(".")[0]
        if not re.search(rf"\b(?:class|object)\s+{re.escape(expected_owner)}\b", owner_header):
            raise ValueError("source owner does not match ABI identity")
        opening = source.code.find("{", owner_start)
        # Constructor/property parameters may precede the opening brace.
        if opening >= 0 and "{" in owner_header and not owner_start <= start < balanced_end(source.code, opening):
            raise ValueError("source declaration is outside its nominal owner")
        enclosing.extend(source.prefix_annotations(owner_start))
    direct = [] if mode in {"implicit_constructor", "annotation_parameter", "parameter_accessor", "property_accessor", "constructor_parameter_accessor"} else source.prefix_annotations(start)
    inherited = source.prefix_annotations(start) if mode in {"property_accessor", "constructor_parameter_accessor"} else []
    enclosing.extend(inherited)
    file_records = [a for a in source.annotations if a["use_site_target"] == "file"]
    visibility = re.match(r"(?:public|internal|protected|private)\b", header)
    visibility = visibility[0] if visibility else "public"
    if mode in {"constructor_parameter", "constructor_parameter_accessor"}:
        visibility = "internal"
    direct = annotation_records(direct, sources)
    inherited = annotation_records(inherited, sources)
    enclosing = annotation_records(enclosing, sources)
    file_records = annotation_records(file_records, sources)
    return {
        "path": path, "git_blob_sha1": source.record["git_blob_sha1"],
        "role": role, "evidence_status": "verified-pinned-source",
        "visibility": visibility,
        "annotations": [a["name"] for a in direct], "annotation_records": direct,
        "inherited_annotations": [a["name"] for a in inherited],
        "enclosing_annotation_records": enclosing,
        "file_annotations": [a["name"] for a in file_records],
        "file_annotation_records": file_records,
        "declaration": anchor,
        "annotation_evidence": "exact pinned declaration span; direct, property-accessor context, enclosing class and file annotations are separate",
    }


def validate_source_semantics(index: dict) -> None:
    manifest, sources = load_sources()
    anchors = json.loads((REFERENCE / "atomicfu.source-anchors.json").read_text())
    native_identities = set()
    for row in index["declarations"]:
        identity = row["api_identity"]
        expected_paths = set(anchors[identity])
        if {ref["path"] for ref in row["source_provenance"]} != expected_paths:
            raise ValueError(f"source declaration paths mismatch: {identity}")
        signature = row["signature"]
        expected_kind = ("annotation_class" if "annotation class " in signature else
            "object" if signature.startswith(("final object ", "open object ")) else
            "class" if re.match(r"(?:final|open|abstract|enum) class ", signature) else
            "constructor" if signature.startswith("constructor ") else
            "property" if re.match(r"(?:final|open) (?:val|var) ", signature) else "function")
        if row["kind"] != expected_kind:
            raise ValueError(f"declaration kind mismatch: {identity}")
        for ref in row["source_provenance"]:
            if row["scope"] == "common-native" and ref["path"] not in sources:
                raise ValueError(f"common/native declaration has no source evidence: {identity}")
            expected = source_fact(identity, ref["path"], ref["role"], sources, anchors)
            if ref != expected:
                raise ValueError(f"source semantics mismatch: {identity} in {ref['path']}")
        visibilities = {ref["visibility"] for ref in row["source_provenance"] if ref["visibility"] is not None}
        expected_visibility = next(iter(visibilities), None) if len(visibilities) <= 1 else "mixed"
        if row["kotlin_visibility"] != expected_visibility:
            raise ValueError(f"Kotlin visibility mismatch: {identity}")
        if row["scope"] == "common-native":
            native_identities.add(identity)
    if len(native_identities) != 150:
        raise ValueError("source evidence does not cover all 150 common/native identities")
