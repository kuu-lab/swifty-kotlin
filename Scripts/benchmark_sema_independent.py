#!/usr/bin/env python3
"""Measure the opt-in independent-body runner against the serial Sema path."""

import argparse
import csv
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading


def positive(value):
    value = int(value)
    if value < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return value



def run_measured(command, timeout):
    # wait4 returns this child's peak RSS, unlike the cumulative maximum from
    # getrusage(RUSAGE_CHILDREN). File-backed stderr avoids pipe deadlocks.
    with tempfile.TemporaryFile() as stderr:
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=stderr)
        expired = threading.Event()

        def stop():
            expired.set()
            try:
                process.kill()
            except ProcessLookupError:
                pass

        timer = threading.Timer(timeout, stop)
        timer.daemon = True
        timer.start()
        try:
            _, status, usage = os.wait4(process.pid, 0)
            process.returncode = os.waitstatus_to_exitcode(status)
        finally:
            timer.cancel()
        stderr.seek(0)
        error_text = stderr.read().decode("utf-8", errors="replace")
        if expired.is_set():
            raise subprocess.TimeoutExpired(command, timeout, stderr=error_text)
        rss = usage.ru_maxrss if sys.platform == "darwin" else usage.ru_maxrss * 1024
        return subprocess.CompletedProcess(command, process.returncode, stderr=error_text), rss


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=root / ".build/debug/kswiftc")
    parser.add_argument("--files", type=positive, nargs="+", default=[10, 50, 100])
    parser.add_argument("--jobs", type=positive, nargs="+", default=[1, 2, 4])
    parser.add_argument("--functions", type=positive, default=20)
    parser.add_argument("--terms", type=positive, default=16)
    parser.add_argument("--body", choices=["scalar", "locals"], default="scalar")
    parser.add_argument("--runs", type=positive, default=3)
    parser.add_argument("--stdlib", choices=["none", "source", "artifact"], default="none")
    parser.add_argument("--stdlib-library", type=Path)
    parser.add_argument("--timeout", type=positive, default=600)
    args = parser.parse_args()
    if (args.stdlib == "artifact") != (args.stdlib_library is not None):
        parser.error("--stdlib artifact requires --stdlib-library, and only artifact accepts it")
    compiler = args.compiler.resolve()
    if not compiler.is_file():
        parser.error("build kswiftc first")
    flags = {
        "none": ["--no-stdlib"],
        "source": ["--stdlib-from-source"],
        "artifact": ["--no-stdlib", "--stdlib-library", str(args.stdlib_library)],
    }[args.stdlib]
    writer = csv.writer(sys.stdout, delimiter="\t", lineterminator="\n")
    writer.writerow(["stdlib", "files", "functions_per_file", "terms", "body", "jobs",
                     "parallel_sema", "sample", "metric", "value"])
    with tempfile.TemporaryDirectory(prefix="kuu-2000-benchmark-") as directory:
        work = Path(directory)
        for count in args.files:
            inputs = []
            for file in range(count):
                source = work / f"input{file}.kt"
                expression = " + ".join(["x * x"] * args.terms)
                body = (f"= {expression}" if args.body == "scalar" else
                        f"{{ val y = {expression}; var z = y; z = z + 1; return z }}")
                source.write_text("package independentbench\n" + "\n".join(
                    f"fun f{file}_{function}(x: Int): Int {body}"
                    for function in range(args.functions)
                ) + "\n", encoding="utf-8")
                inputs.append(str(source))
            configs = [(jobs, enabled) for jobs in args.jobs for enabled in [False, True]]
            # Each configuration gets its own warmup. Reverse alternating
            # rounds to reduce ordering bias. Keep individual samples.
            for sample in range(args.runs + 1):
                for jobs, enabled in configs if sample % 2 == 0 else reversed(configs):
                    print(f"[Sema independent] {args.stdlib} files={count} jobs={jobs} "
                          f"enabled={enabled} sample={sample}", file=sys.stderr, flush=True)
                    command = [str(compiler), *flags, "--emit", "kir", "-o", str(work / "out"),
                               "-Xfrontend", "time-phases", "-Xfrontend", f"jobs={jobs}"]
                    if enabled:
                        command += ["-Xfrontend", "sema-parallel"]
                    command += inputs
                    result, rss = run_measured(command, args.timeout)
                    if result.returncode:
                        raise RuntimeError(f"compiler failed ({result.returncode}):\n{result.stderr}")
                    values = {"max_rss_bytes": rss}
                    for line in result.stderr.splitlines():
                        match = re.fullmatch(r"\s*(Sema|TypeCheckSema|type-check)\s+"
                                             r"(\d+\.\d+)\s+\d+\.\d+%\s*", line)
                        if match:
                            values[match[1] + "_ms"] = match[2]
                    expected = {"Sema_ms", "TypeCheckSema_ms", "type-check_ms", "max_rss_bytes"}
                    if set(values) != expected:
                        raise RuntimeError(f"missing timing or RSS metrics:\n{result.stderr}")
                    if sample:
                        for metric in sorted(values):
                            writer.writerow([args.stdlib, count, args.functions, args.terms, args.body, jobs,
                                             int(enabled), sample, metric, values[metric]])
                        sys.stdout.flush()


if __name__ == "__main__":
    main()
