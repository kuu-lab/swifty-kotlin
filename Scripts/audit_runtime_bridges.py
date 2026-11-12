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
    r'\b(?:abi|abi[A-Z][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*ABI)\.(?P<kind>th|nt)\(\s*"(?P<symbol>[_a-zA-Z0-9]+)"'
    r'(?:,\s*"(?P<params>[^"]*)")?'
    r'(?:,\s*ret:\s*\.(?P<ret>[_a-zA-Z0-9]+))?'
    r'(?:,\s*raw:\s*(?P<raw>true|false))?'
)

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
                has_out_thrown = "outThrown" in params
                cdecls[symbol] = {
                    "file": f,
                    "func_name": func_name,
                    "params": params,
                    "return_type": ret,
                    "is_throwing": has_out_thrown,
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
                symbol = m.group("symbol")
                kind = m.group("kind")
                params = (m.group("params") or "").strip()
                ret = m.group("ret") or "intptr"
                raw = m.group("raw") == "true"
                specs[symbol] = {
                    "file": f,
                    "kind": kind,
                    "is_throwing": kind == "th",
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
    # Check throwing mismatches
    common = set(cdecls.keys()) & set(specs.keys())
    throwing_mismatches = []
    for s in common:
        c_th = cdecls[s]["is_throwing"]
        s_th = specs[s]["is_throwing"]
        if c_th != s_th:
            throwing_mismatches.append((s, c_th, s_th))

    print(f"Throwing flag mismatches: {len(throwing_mismatches)}")
    for s, c_th, s_th in throwing_mismatches[:10]:
        print(f"  ! {s}: Runtime has outThrown={c_th}, spec has isThrowing={s_th}")

if __name__ == "__main__":
    main()
