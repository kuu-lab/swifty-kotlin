#!/usr/bin/env python3
"""Measure Sema intervals, separately from parallel Lex/Parse/BuildAST work."""

import argparse
import csv
from pathlib import Path
import re
import subprocess
import sys
import tempfile


METRICS = (
    "Sema", "sema-setup", "header-collection", "declaration-validation", "body-checks", "type-check",
)


def positive_int(value):
    result = int(value)
    if result < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return result


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=root / ".build/debug/kswiftc")
    parser.add_argument("--files", type=positive_int, nargs="+", default=[10, 50, 100])
    parser.add_argument("--jobs", type=positive_int, nargs="+", default=[1, 4])
    parser.add_argument("--runs", type=positive_int, default=3)
    parser.add_argument("--stdlib", choices=["none", "source", "artifact"], default="none")
    parser.add_argument("--stdlib-library", type=Path)
    parser.add_argument("--timeout", type=positive_int, default=600)
    args = parser.parse_args()
    if args.stdlib == "artifact" and args.stdlib_library is None:
        parser.error("--stdlib artifact requires --stdlib-library")
    if args.stdlib != "artifact" and args.stdlib_library is not None:
        parser.error("--stdlib-library requires --stdlib artifact")
    compiler = args.compiler.resolve()
    if not compiler.is_file():
        parser.error(f"build kswiftc first; compiler missing: {compiler}")
    stdlib_flags = {
        "none": ["--no-stdlib"],
        "source": ["--stdlib-from-source"],
        "artifact": ["--stdlib-library", str(args.stdlib_library)],
    }[args.stdlib]
    writer = csv.writer(sys.stdout, delimiter="\t", lineterminator="\n")
    writer.writerow(["stdlib", "user_files", "jobs", "sample", "metric", "ms"])
    with tempfile.TemporaryDirectory(prefix="kswiftk-sema-bench-") as directory:
        work = Path(directory)
        for count in args.files:
            inputs = []
            for index in range(count):
                source = work / f"input{index}.kt"
                source.write_text(f"""package semabench
interface Renderable{index} {{ fun render(): String }}
class Widget{index}(val id: Int, val label: String) : Renderable{index} {{
    override fun render(): String = label
    fun compute(x: Int): Int = x + id
}}
val value{index} = {index}
fun helper{index}(x: Int): Int = x + value{(index + 1) % count}
fun transform{index}(s: String): String = s
""", encoding="utf-8")
                inputs.append(str(source))
            # Interleave jobs configurations per round to reduce ordering bias.
            # Round zero warms each configuration and is deliberately omitted.
            for sample in range(args.runs + 1):
                for jobs in args.jobs:
                    label = "warmup" if sample == 0 else f"sample {sample}"
                    print(f"[Sema benchmark] stdlib={args.stdlib} files={count} jobs={jobs} {label}",
                          file=sys.stderr, flush=True)
                    command = [str(compiler), *stdlib_flags, "--emit", "kir",
                               "-Xfrontend", "time-phases", "-Xfrontend", f"jobs={jobs}",
                               "-o", str(work / "output.kir"), *inputs]
                    completed = subprocess.run(command, stdout=subprocess.DEVNULL,
                                               stderr=subprocess.PIPE, text=True,
                                               timeout=args.timeout)
                    if completed.returncode != 0:
                        raise RuntimeError(f"compiler failed ({completed.returncode}):\n{completed.stderr}")
                    values = {}
                    for line in completed.stderr.splitlines():
                        match = re.fullmatch(r"\s*([\w-]+)\s+(\d+\.\d+)\s+\d+\.\d+%\s*", line)
                        if match and match[1] in METRICS:
                            values[match[1]] = match[2]
                    if set(values) != set(METRICS):
                        raise RuntimeError(f"missing Sema timings; rebuild kswiftc:\n{completed.stderr}")
                    if sample:
                        for metric in METRICS:
                            writer.writerow([args.stdlib, count, jobs, sample, metric, values[metric]])
                        sys.stdout.flush()


if __name__ == "__main__":
    main()
