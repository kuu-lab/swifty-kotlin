#!/usr/bin/env python3
"""Compare worker ownership fixtures across source/artifact, O0/O2 and jobs=1/2/4."""

import argparse
from pathlib import Path
import subprocess


SOURCES = [
    """package ownership
fun first(x: Int): Int { val y: Int = x + 1; return y * 2 }
fun serial(x: Int): Int { val f = { x + 1 }; return f() }
fun second(x: Long): Long { var y: Long = x; y = y + 2; return y }
fun captured(x: Int): Int { val y = x + 1; val f: (Int) -> Int = { z -> y + z }; val o = object { fun read(): Int = y }; return f(o.read()) }
""",
    """package ownership
fun branch(x: Int): Int { var y: Int = x; if (x > 0) { val z: Int = x + 2; y = z }; return y }
fun last(x: Int): Int { val a: Int = x + 1; val b: Int = a * 2; return b }
fun main() {
    println(first(3))
    println(serial(3))
    println(second(40L))
    println(branch(3))
    println(last(3))
    println(captured(3))
}
""",
]
EXPECTED = b"8\n4\n42\n5\n8\n8\n"


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=root / ".build/debug/kswiftc")
    parser.add_argument("--output", type=Path, required=True, help="empty directory for all inputs, logs and artifacts")
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    if not compiler.is_file() or args.timeout < 1:
        parser.error("build kswiftc first and use a positive timeout")
    work = args.output.resolve()
    if work.exists() and (not work.is_dir() or any(work.iterdir())):
        parser.error("--output must be an empty directory (the stdlib artifact must be fresh)")
    work.mkdir(parents=True, exist_ok=True)
    inputs = []
    for index, source in enumerate(SOURCES):
        path = work / f"input{index}.kt"
        path.write_text(source, encoding="utf-8")
        inputs.append(str(path))

    def run(command, label):
        print(label, flush=True)
        result = subprocess.run(command, capture_output=True, timeout=args.timeout)
        (work / f"{label}.stdout").write_bytes(result.stdout)
        (work / f"{label}.stderr").write_bytes(result.stderr)
        if result.returncode:
            raise RuntimeError(f"{label}: exit {result.returncode}; inspect {work / (label + '.stderr')}")
        return result.stdout

    artifact = work / "fresh.kklib"
    run([str(compiler), "--stdlib-only", "--emit", "library", "-o", str(artifact)], "build-artifact")
    comparisons = 0
    for route, flags in [
        ("source", ["--stdlib-from-source"]),
        ("artifact", ["--no-stdlib", "--stdlib-library", str(artifact)]),
    ]:
        for opt in [0, 2]:
            baseline = None
            raw_baseline = None
            for jobs in [1, 2, 4]:
                label = f"{route}-O{opt}-jobs{jobs}"
                common = [str(compiler), *flags, f"-O{opt}", "-Xfrontend", "sema-parallel",
                          "-Xfrontend", f"jobs={jobs}", *inputs]
                executable = work / label
                run([*common, "-o", str(executable)], label + "-compile")
                output = run([str(executable)], label + "-run")
                if output != EXPECTED:
                    raise RuntimeError(f"{label}: stdout mismatch: {output!r}")
                kir = work / (label + "-kir")
                run([*common, "--emit", "kir", "-o", str(kir)], label + "-kir-compile")
                comparable = "\n".join(line.rstrip() for line in
                    Path(str(kir) + ".kir").read_text(encoding="utf-8").replace(str(work), "<work>").splitlines())
                (work / (label + ".comparable.kir")).write_text(comparable, encoding="utf-8")
                if baseline is None:
                    baseline = comparable
                elif comparable != baseline:
                    raise RuntimeError(f"{label}: raw KIR differs from jobs=1")
                else:
                    comparisons += 1
    print(f"PASS: 12 executable compile/runs, 12 KIR compiles, {comparisons} raw KIR comparisons; {work}")


if __name__ == "__main__":
    main()
