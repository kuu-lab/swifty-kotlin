#!/usr/bin/env python3
"""Measure full, cold incremental, no-op, and local-edit KIR compilation."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import statistics
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=Path(".build/debug/kswiftc"))
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--files", type=int, default=32)
    parser.add_argument("--stdlib-mode", choices=["none", "source"], default="none")
    parser.add_argument("--compile-timeout", type=float, default=300)
    parser.add_argument("--report-dir", type=Path, required=True,
                        help="New directory for JSON, phase logs, and KIR outputs")
    args = parser.parse_args()
    if args.repetitions < 1 or args.files < 2:
        parser.error("repetitions must be positive and files must be at least 2")
    if args.compile_timeout <= 0:
        parser.error("compile-timeout must be positive")
    compiler = args.compiler.resolve(strict=True)
    args.report_dir.mkdir(parents=True, exist_ok=False)
    rows = []
    with tempfile.TemporaryDirectory(prefix="kswiftk-incremental-") as temporary:
        root = Path(temporary)
        inputs = [root / f"part{i}.kt" for i in range(args.files)]

        def write_inputs(value):
            for i, path in enumerate(inputs):
                contents = "\n".join(
                    f"fun part{i}value{j}(): Int = {value if i == 1 and j == 0 else j}"
                    for j in range(8)
                )
                if i == 0:
                    contents += "\nfun main() { val result = part1value0() + part0value0() }"
                path.write_text(contents + "\n")

        output = root / "out"
        common = [str(compiler), *map(str, inputs), "--emit", "kir", "-o", str(output),
                  "--no-stdlib" if args.stdlib_mode == "none" else "--stdlib-from-source",
                  "-Xfrontend", "time-phases"]

        def run(label, repetition, cache):
            # Use the same output path; delete it to prove no-op artifact restoration.
            output.with_suffix(".kir").unlink(missing_ok=True)
            flags = ["--no-incremental"] if cache is None else ["--incremental-cache", str(cache)]
            prefix = args.report_dir / f"{repetition}-{label}"
            print(json.dumps({"repetition": repetition, "starting": label}), flush=True)
            start = time.perf_counter()
            try:
                result = subprocess.run(common + flags, capture_output=True, timeout=args.compile_timeout)
            except subprocess.TimeoutExpired as error:
                prefix.with_suffix(".stderr").write_bytes(error.stderr or b"")
                prefix.with_suffix(".stdout").write_bytes(error.stdout or b"")
                prefix.with_suffix(".failure.json").write_text(json.dumps({
                    "case": label, "repetition": repetition,
                    "timeout_seconds": args.compile_timeout, "completed": False,
                }, indent=2) + "\n")
                raise RuntimeError(f"{label} timed out; see {prefix}.failure.json") from None
            elapsed = (time.perf_counter() - start) * 1000
            prefix.with_suffix(".stderr").write_bytes(result.stderr)
            prefix.with_suffix(".stdout").write_bytes(result.stdout)
            if result.returncode:
                raise RuntimeError(f"{label} failed: see {prefix}.stderr")
            phase_ms = {
                name: float(duration) for name, duration in re.findall(
                    r"^([A-Za-z]+)\s+([0-9.]+)\s+[0-9.]+%$",
                    result.stderr.decode(), re.MULTILINE
                ) if name != "TOTAL"
            }
            if label == "incremental-noop" and set(phase_ms) != {"LoadSources"}:
                raise RuntimeError("No-op did not skip the pipeline; inspect phase log")
            if label != "incremental-noop" and "Sema" not in phase_ms:
                raise RuntimeError("Expected Sema to run; inspect phase log")
            data = output.with_suffix(".kir").read_bytes()
            prefix.with_suffix(".kir").write_bytes(data)
            returned_values = {
                name: int(value) for name, _, value in re.findall(
                    r"^decl\[\d+\] function #\d+ (part\d+value\d+) [^\n]*\n"
                    r"  const r(\d+)=intLiteral\((-?\d+)\)\n  return r\2(?=\n|$)",
                    data.decode(), re.MULTILINE
                )
            }
            expected_values = {
                f"part{i}value{j}": 42 if label.endswith("edit") and i == 1 and j == 0 else j
                for i in range(args.files) for j in range(8)
            }
            if returned_values != expected_values:
                raise RuntimeError("Generated function return values differ from source; inspect KIR")
            row = {"repetition": repetition, "case": label, "wall_ms": elapsed,
                   "phase_ms": phase_ms,
                   "output_sha256": hashlib.sha256(data).hexdigest(),
                   "cache_bytes": sum(p.stat().st_size for p in cache.rglob("*") if p.is_file())
                   if cache else 0}
            rows.append(row)
            print(json.dumps(row), flush=True)
            return data

        for repetition in range(1, args.repetitions + 1):
            write_inputs(0)
            cache = root / f"cache{repetition}"
            full = run("full", repetition, None)
            cold = run("incremental-cold", repetition, cache)
            noop = run("incremental-noop", repetition, cache)
            if full != cold or cold != noop:
                raise RuntimeError("Full/cold/no-op KIR differs; inspect retained outputs")
            write_inputs(42)
            changed = run("incremental-edit", repetition, cache)
            changed_full = run("full-edit", repetition, None)
            if changed == noop:
                raise RuntimeError("Local edit restored stale KIR")
            # AST IDs can differ after restoration; all generated return values were checked above.
            if not changed_full:
                raise RuntimeError("Full local-edit compilation produced empty KIR")
    report = {"compiler": str(compiler), "files": args.files, "functions_per_file": 8,
              "stdlib_mode": args.stdlib_mode, "rows": rows,
              "median_wall_ms": {
                  label: statistics.median(r["wall_ms"] for r in rows if r["case"] == label)
                  for label in sorted({r["case"] for r in rows})}}
    (args.report_dir / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report["median_wall_ms"], indent=2))


if __name__ == "__main__":
    main()
