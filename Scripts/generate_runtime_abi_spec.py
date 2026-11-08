#!/usr/bin/env python3
"""
Scripts/generate_runtime_abi_spec.py

Generates RuntimeABISpec definitions directly from Sources/Runtime @_cdecl declarations.
Establishes Sources/Runtime as the Single Source of Truth (SSOT), eliminating 7.1k lines
of manual, duplicated spec maintenance in Sources/RuntimeABI.

Usage:
    python3 Scripts/generate_runtime_abi_spec.py [--output <path>] [--check] [--stats]
"""

import argparse
import os
import re
import sys
from collections import defaultdict

CDECL_PATTERN = re.compile(
    r'@_cdecl\("(?P<symbol>[_a-zA-Z0-9]+)"\)\s*\n'
    r'(?:@\w+(?:\([^)]*\))?\s*\n)*'
    r'(?:public\s+|private\s+|internal\s+)*func\s+(?P<func_name>[_a-zA-Z0-9]+)\s*'
    r'\((?P<params>[^)]*)\)\s*(?:->\s*(?P<ret>[^{\n]+))?',
    re.MULTILINE
)

SWIFT_TO_ABI_TYPE = {
    "Int": ".intptr",
    "Int64": ".int64",
    "UInt64": ".uint64",
    "Int32": ".int32",
    "UInt32": ".uint32",
    "Float": ".float",
    "Double": ".double",
    "UnsafeMutableRawPointer": ".opaquePointer",
    "UnsafeRawPointer": ".constRawPointer",
    "UnsafeMutableRawPointer?": ".nullableOpaquePointer",
    "UnsafeRawPointer?": ".nullableConstRawPointer",
    "UnsafePointer<UInt8>": ".constUInt8Pointer",
    "UnsafePointer<CChar>": ".constUInt8Pointer",
    "UnsafePointer<UInt8>?": ".nullableConstUInt8Pointer",
    "UnsafePointer<CChar>?": ".nullableConstUInt8Pointer",
    "UnsafeMutablePointer<UInt8>?": ".nullableUInt8Pointer",
    "UnsafeMutablePointer<Int>?": ".nullableIntptrPointer",
    "UnsafeMutablePointer<UnsafeMutableRawPointer?>?": ".nullableRawPointerPointer",
    "Void": ".void",
    "()": ".void",
}

def derive_section(filename):
    base = filename
    if base.startswith("Runtime"):
        base = base[len("Runtime"):]
    if base.endswith(".swift"):
        base = base[:-len(".swift")]
    # Strip subcategory suffixes like +Something or Basics/Bindings/Values
    base = base.split("+")[0]
    for suffix in ["Basics", "Bindings", "Values", "Helpers", "Stdlib", "Conversion", "Flat", "AndDispatch", "Operations"]:
        if base.endswith(suffix) and len(base) > len(suffix):
            base = base[:-len(suffix)]
            break
    return base or "General"

def parse_parameter(param_str):
    param_str = param_str.strip()
    if not param_str:
        return None
    # e.g. "_ name: Type" or "name: Type" or "_ name: Type = default"
    if "=" in param_str:
        param_str = param_str.split("=")[0].strip()
    parts = param_str.split(":")
    if len(parts) != 2:
        return None
    name_part = parts[0].strip()
    type_part = parts[1].strip()
    name_tokens = name_part.split()
    name = name_tokens[-1] if name_tokens else "arg"
    return name, type_part

def scan_runtime(runtime_dir):
    functions = []
    for root, _, files in os.walk(runtime_dir):
        for f in sorted(files):
            if not f.endswith(".swift"):
                continue
            path = os.path.join(root, f)
            with open(path, "r", encoding="utf-8") as fp:
                content = fp.read()
            section = derive_section(f)
            for m in CDECL_PATTERN.finditer(content):
                symbol = m.group("symbol")
                raw_params = m.group("params").strip()
                raw_ret = (m.group("ret") or "Void").strip()

                param_items = []
                is_throwing = False
                if raw_params:
                    # Split top-level commas (ignoring generics <...>)
                    depth = 0
                    current = []
                    for ch in raw_params:
                        if ch in "<(":
                            depth += 1
                        elif ch in ">)":
                            depth -= 1
                        if ch == "," and depth == 0:
                            p = parse_parameter("".join(current))
                            if p:
                                param_items.append(p)
                            current = []
                        else:
                            current.append(ch)
                    if current:
                        p = parse_parameter("".join(current))
                        if p:
                            param_items.append(p)

                # Check throwing status
                clean_params = []
                for name, p_type in param_items:
                    if name == "outThrown" or "outThrown" in name:
                        is_throwing = True
                    else:
                        clean_params.append((name, p_type))

                # Returns raw boolean check
                returns_raw_boolean = raw_ret == "Bool"

                functions.append({
                    "symbol": symbol,
                    "section": section,
                    "file": f,
                    "params": clean_params,
                    "is_throwing": is_throwing,
                    "return_type": raw_ret,
                    "returns_raw_boolean": returns_raw_boolean,
                })
    return functions

def generate_spec_swift(functions):
    lines = [
        "//",
        "// GeneratedRuntimeABISpec.swift",
        "// Auto-generated by Scripts/generate_runtime_abi_spec.py from Sources/Runtime @_cdecl declarations.",
        "// DO NOT EDIT MANUALLY - Single Source of Truth is Sources/Runtime.",
        "//",
        "",
        "import Foundation",
        "",
        "public extension RuntimeABISpec {",
        "    static let autoGeneratedFunctions: [RuntimeABIFunctionSpec] = [",
    ]

    for fn in sorted(functions, key=lambda x: x["symbol"]):
        sym = fn["symbol"]
        sec = fn["section"]
        th = "true" if fn["is_throwing"] else "false"
        raw = ", returnsRawBoolean: true" if fn["returns_raw_boolean"] else ""
        
        # Build parameter spec array
        param_entries = []
        for name, p_type in fn["params"]:
            abi_t = SWIFT_TO_ABI_TYPE.get(p_type, ".intptr")
            param_entries.append(f'RuntimeABIParameter(name: "{name}", type: {abi_t})')
        
        if fn["is_throwing"]:
            param_entries.append('RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)')

        params_code = "[" + ", ".join(param_entries) + "]"
        
        ret_abi = SWIFT_TO_ABI_TYPE.get(fn["return_type"], ".intptr" if fn["return_type"] == "Int" else ".void")
        if fn["returns_raw_boolean"]:
            ret_abi = ".int32"

        lines.append(f'        RuntimeABIFunctionSpec(')
        lines.append(f'            name: "{sym}",')
        lines.append(f'            parameters: {params_code},')
        lines.append(f'            returnType: {ret_abi},')
        lines.append(f'            section: "{sec}",')
        lines.append(f'            isThrowing: {th}{raw}')
        lines.append(f'        ),')

    lines.append("    ]")
    lines.append("}")
    return "\n".join(lines) + "\n"

def main():
    parser = argparse.ArgumentParser(description="Generate RuntimeABISpec from Sources/Runtime")
    parser.add_argument("--output", help="Path to output GeneratedRuntimeABISpec.swift")
    parser.add_argument("--stats", action="store_true", help="Print extraction stats")
    parser.add_argument("--check", help="Check if generated file is up to date with given file")
    args = parser.parse_args()

    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    runtime_dir = os.path.join(repo_root, "Sources", "Runtime")

    functions = scan_runtime(runtime_dir)

    if args.stats or (not args.output and not args.check):
        sections = defaultdict(int)
        for fn in functions:
            sections[fn["section"]] += 1
        print(f"Extracted {len(functions)} @_cdecl bridge specifications from {runtime_dir}")
        print(f"Sections ({len(sections)}):")
        for s, c in sorted(sections.items(), key=lambda x: -x[1])[:15]:
            print(f"  - {s:<25} {c:>4} bridges")
        print(f"  ... and {len(sections) - 15} more sections")

    generated = generate_spec_swift(functions)

    if args.output:
        out_path = os.path.abspath(args.output)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as fp:
            fp.write(generated)
        print(f"Successfully generated {out_path} ({len(functions)} functions)")

    if args.check:
        with open(args.check, "r", encoding="utf-8") as fp:
            current = fp.read()
        if current == generated:
            print(f"Generated spec is up-to-date with {args.check}")
            sys.exit(0)
        else:
            print(f"Error: {args.check} is out of date. Run Scripts/generate_runtime_abi_spec.py to regenerate.")
            sys.exit(1)

if __name__ == "__main__":
    main()
