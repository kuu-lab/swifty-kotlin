#!/usr/bin/env python3
"""
Scripts/audit_runtime_bridges.py

Audits Runtime @_cdecl bridges against RuntimeABISpec declarations.
Provides:
1. Exact counts and distribution of kk_ and __kk_ bridges.
2. Cross-check between Sources/Runtime and Sources/RuntimeABI.
3. Detection of missing or mismatched bridge specs.
4. Foundation for automated RuntimeABISpec code generation.
"""

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

SPEC_ENTRY_PATTERN = re.compile(
    r'\b(?:abi|abi[A-Z][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*ABI)\.(?P<kind>th|nt)\(\s*'
    # Name is usually a string literal; stdlib*HOFName helpers pass the
    # resolved name dynamically but carry the fallback literal, which is
    # what the spec resolves to unless a surface spec remaps it.
    r'(?:"(?P<symbol>[_a-zA-Z0-9]+)"|[^)]*?fallback:\s*"(?P<fb_symbol>[_a-zA-Z0-9]+)"\s*\))'
    r'(?:,\s*(?P<params>(?:"[^"]*"(?:\s*\+\s*"[^"]*")*)))?'
    r'(?:,\s*ret:\s*\.(?P<ret>[_a-zA-Z0-9]+))?'
    r'(?:,\s*raw:\s*(?P<raw>true|false))?'
)

STRING_LITERAL_PATTERN = re.compile(r'"([^"]*)"')
PARAM_NAME_PATTERN = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)\s*:')


def cdecl_param_names(params: str):
    """Yield the label of each top-level parameter in a Swift cdecl signature.

    Splits on commas that are not nested inside generics/parens/brackets so
    types like ``UnsafeMutablePointer<(Int, Int)>`` stay intact, then takes
    the identifier immediately before the first ``:`` of each part.
    """
    parts, depth, start = [], 0, 0
    for i, ch in enumerate(params):
        if ch in "(<[{":
            depth += 1
        elif ch in ")>]}" and depth > 0:
            depth -= 1
        elif ch == "," and depth == 0:
            parts.append(params[start:i])
            start = i + 1
    parts.append(params[start:])
    for part in parts:
        m = PARAM_NAME_PATTERN.search(part)
        if m:
            yield m.group(1), part[m.end():].strip()

def scan_runtime_cdecls(runtime_dir):
    cdecls = {}
    for root, _, files in os.walk(runtime_dir):
        for f in sorted(files):
            if not f.endswith(".swift"):
                continue
            path = os.path.join(root, f)
            with open(path, "r", encoding="utf-8") as fp:
                content = fp.read()
            for m in CDECL_PATTERN.finditer(content):
                symbol = m.group("symbol")
                func_name = m.group("func_name")
                params = m.group("params").strip()
                ret = (m.group("ret") or "Void").strip()
                # The thrown channel is the outThrown ABI slot: a nullable
                # int-pointer out-parameter. Runtime sources name it
                # outThrown/thrown/nextThrown etc., so match on a "thrown"
                # param name combined with the pointer type — a plain
                # `thrown: Int` value parameter is not the channel.
                has_out_thrown = any(
                    "thrown" in name.lower()
                    and "UnsafeMutablePointer<Int" in ptype
                    for name, ptype in cdecl_param_names(params)
                )
                cdecls[symbol] = {
                    "file": f,
                    "func_name": func_name,
                    "params": params,
                    "return_type": ret,
                    "has_out_thrown": has_out_thrown,
                }
    return cdecls

def scan_runtime_abi_specs(abi_dir):
    specs = {}
    for root, _, files in os.walk(abi_dir):
        for f in sorted(files):
            if not f.endswith(".swift"):
                continue
            path = os.path.join(root, f)
            with open(path, "r", encoding="utf-8") as fp:
                content = fp.read()
            for m in SPEC_ENTRY_PATTERN.finditer(content):
                line_start = content.rfind("\n", 0, m.start()) + 1
                line_end = content.find("\n", m.start())
                if line_end == -1:
                    line_end = len(content)
                if content[line_start:line_end].lstrip().startswith("//"):
                    continue
                symbol = m.group("symbol") or m.group("fb_symbol")
                kind = m.group("kind")
                params_expr = m.group("params") or ""
                # The params argument may be several string literals joined by
                # `+` when a long list is wrapped; concatenate their contents.
                params = "".join(STRING_LITERAL_PATTERN.findall(params_expr)).strip()
                ret = m.group("ret") or "intptr"
                raw = m.group("raw") == "true"
                has_out_thrown = any(
                    token.split(":", 1)[0] == "outThrown"
                    for token in params.split()
                )
                specs[symbol] = {
                    "file": f,
                    "kind": kind,
                    "is_throwing": kind == "th",
                    "has_out_thrown": has_out_thrown,
                    "params": params,
                    "ret": ret,
                    "raw_boolean": raw,
                }
    return specs

def main():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    runtime_dir = os.path.join(repo_root, "Sources", "Runtime")
    abi_dir = os.path.join(repo_root, "Sources", "RuntimeABI")

    cdecls = scan_runtime_cdecls(runtime_dir)
    specs = scan_runtime_abi_specs(abi_dir)

    kk_cdecls = [k for k in cdecls if not k.startswith("__kk_")]
    und_cdecls = [k for k in cdecls if k.startswith("__kk_")]

    print(f"=== Runtime Bridges Audit Summary ===")
    print(f"Total Sources/Runtime @_cdecl found: {len(cdecls)}")
    print(f"  - kk_  bridges: {len(kk_cdecls)}")
    print(f"  - __kk_ bridges: {len(und_cdecls)}")
    print(f"Total Sources/RuntimeABI specs found: {len(specs)}")
    print()

    in_runtime_not_in_spec = sorted(set(cdecls.keys()) - set(specs.keys()))
    in_spec_not_in_runtime = sorted(set(specs.keys()) - set(cdecls.keys()))

    print(f"Bridges in Runtime but not in RuntimeABISpec: {len(in_runtime_not_in_spec)}")
    if in_runtime_not_in_spec and len(in_runtime_not_in_spec) <= 20:
        for s in in_runtime_not_in_spec:
            print(f"  + {s} ({cdecls[s]['file']})")
    elif in_runtime_not_in_spec:
        for s in in_runtime_not_in_spec[:15]:
            print(f"  + {s} ({cdecls[s]['file']})")
        print(f"  ... and {len(in_runtime_not_in_spec) - 15} more")

    print()
    print(f"Specs in RuntimeABISpec but not in Runtime: {len(in_spec_not_in_runtime)}")
    if in_spec_not_in_runtime and len(in_spec_not_in_runtime) <= 20:
        for s in in_spec_not_in_runtime:
            print(f"  - {s} ({specs[s]['file']})")
    elif in_spec_not_in_runtime:
        for s in in_spec_not_in_runtime[:15]:
            print(f"  - {s} ({specs[s]['file']})")
        print(f"  ... and {len(in_spec_not_in_runtime) - 15} more")

    print()
    # The spec's isThrowing flag (th/nt) and the presence of an outThrown
    # parameter are independent fields, and the Runtime cdecl only exposes
    # the latter. Compare like with like: outThrown presence on both sides.
    common = set(cdecls.keys()) & set(specs.keys())
    out_thrown_mismatches = []
    for s in common:
        c_has = cdecls[s]["has_out_thrown"]
        s_has = specs[s]["has_out_thrown"]
        if c_has != s_has:
            out_thrown_mismatches.append((s, c_has, s_has))

    print(f"outThrown signature mismatches: {len(out_thrown_mismatches)}")
    for s, c_has, s_has in out_thrown_mismatches[:10]:
        print(f"  ! {s}: Runtime outThrown={c_has}, spec outThrown={s_has}")

if __name__ == "__main__":
    main()
