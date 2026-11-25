#!/usr/bin/env python3
"""Preflight two kswiftc binaries before an A/B compile benchmark."""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


EMIT_MODES = ("executable", "object", "llvm", "kir", "library", "class", "jar", "dex", "apk")
OUTPUT_SUFFIX = {"kir": ".kir", "llvm": ".ll", "object": ".o", "library": ".kklib"}


class PreflightError(Exception):
    pass


def infer_build_config(path: Path) -> str | None:
    for part in reversed(path.absolute().parts):
        lowered = part.lower()
        if lowered in {"release", "kswiftc-release"}:
            return "release"
        if lowered in {"debug", "kswiftc-debug"}:
            return "debug"
    return None


def resolve_build_config(path: Path, declared: str | None, label: str) -> str:
    inferred = infer_build_config(path)
    if declared and inferred and declared != inferred:
        raise PreflightError(
            f"{label} build config mismatch: declared {declared} but path implies {inferred}: {path}"
        )
    config = declared or inferred
    if config is None:
        raise PreflightError(
            f"{label} build config cannot be verified for {path}; "
            "pass --base-build-config/--candidate-build-config or use a path containing debug/release"
        )
    return config


def require_executable(path: Path, label: str) -> Path:
    if not path.is_file() or not os.access(path, os.X_OK):
        raise PreflightError(f"{label} compiler is not an executable file: {path}")
    return path


def output_is_usable(path: Path) -> bool:
    if path.is_file():
        return path.stat().st_size > 0
    if path.is_dir():
        return any(p.is_file() and p.stat().st_size > 0 for p in path.rglob("*"))
    return False


def acceptable_outputs(emit: str, output: Path) -> list[Path]:
    candidates = [output]
    if emit == "executable":
        candidates.append(Path(str(output) + ".wasm"))
    return candidates


def run_compile(label: str, compiler: Path, emit: str, compiler_args: list[str],
                inputs: list[Path], output: Path, acceptable: list[Path],
                timeout: float, work_dir: Path) -> None:
    stdout_path = work_dir / f"{label}.stdout"
    stderr_path = work_dir / f"{label}.stderr"
    command = [str(compiler), "--emit", emit, *compiler_args, "-o", str(output), *map(str, inputs)]
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise PreflightError(f"{label} compile timed out after {timeout} seconds") from None
    stdout_path.write_bytes(result.stdout)
    stderr_path.write_bytes(result.stderr)
    if result.returncode != 0:
        detail = stderr_path.read_text(encoding="utf-8", errors="replace").strip()
        raise PreflightError(
            f"{label} compile failed with exit {result.returncode}: {detail or stdout_path}"
        )
    if not any(output_is_usable(path) for path in acceptable):
        expected = ", ".join(str(path) for path in acceptable)
        raise PreflightError(f"{label} compile exited 0 but produced no usable output at {expected}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-compiler", type=Path, required=True)
    parser.add_argument("--candidate-compiler", type=Path, required=True)
    parser.add_argument("--base-build-config", choices=["debug", "release"])
    parser.add_argument("--candidate-build-config", choices=["debug", "release"])
    parser.add_argument("--emit", choices=EMIT_MODES, default="kir")
    parser.add_argument("--compiler-arg", action="append", default=[],
                        help="Extra kswiftc argument applied to both compiles; repeat as needed")
    parser.add_argument("--input", type=Path, action="append", default=[],
                        help="Kotlin input file; repeat for multiple files. Default: generated probe")
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--work-dir", type=Path,
                        help="Directory for logs and outputs (default: temporary directory)")
    args = parser.parse_args(argv)
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    forbidden = {"-o", "--output"}
    for arg in args.compiler_arg:
        if arg in forbidden or arg.startswith("--output="):
            parser.error("--compiler-arg must not set the output path; the preflight owns -o")
    return args


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    base = require_executable(args.base_compiler.absolute(), "base")
    candidate = require_executable(args.candidate_compiler.absolute(), "candidate")
    base_config = resolve_build_config(base, args.base_build_config, "base")
    candidate_config = resolve_build_config(candidate, args.candidate_build_config, "candidate")
    if base_config != candidate_config:
        raise PreflightError(
            f"build config mismatch: base={base_config} candidate={candidate_config} "
            f"({base} vs {candidate})"
        )

    inputs = args.input
    if inputs:
        missing = [str(path) for path in inputs if not path.is_file()]
        if missing:
            raise PreflightError(f"input file not found: {missing[0]}")

    if args.work_dir is None:
        with tempfile.TemporaryDirectory(prefix="kswiftk-benchmark-preflight-") as temporary:
            return run_pair(args, base, candidate, base_config, inputs, Path(temporary))
    if args.work_dir.exists():
        raise PreflightError(f"work directory already exists: {args.work_dir}")
    args.work_dir.mkdir(parents=True, exist_ok=False)
    return run_pair(args, base, candidate, base_config, inputs, args.work_dir)


def run_pair(args: argparse.Namespace, base: Path, candidate: Path, config: str,
             inputs: list[Path], work_dir: Path) -> int:
    if not inputs:
        probe = work_dir / "benchmark-preflight.kt"
        probe.write_text("fun main() {}\n", encoding="utf-8")
        inputs = [probe]

    suffix = OUTPUT_SUFFIX.get(args.emit, "")
    base_output = work_dir / f"base-output{suffix}"
    candidate_output = work_dir / f"candidate-output{suffix}"
    run_compile("base", base, args.emit, args.compiler_arg, inputs, base_output,
                acceptable_outputs(args.emit, base_output), args.timeout, work_dir)
    run_compile("candidate", candidate, args.emit, args.compiler_arg, inputs, candidate_output,
                acceptable_outputs(args.emit, candidate_output), args.timeout, work_dir)
    print(f"benchmark preflight passed: config={config} emit={args.emit}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except PreflightError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
