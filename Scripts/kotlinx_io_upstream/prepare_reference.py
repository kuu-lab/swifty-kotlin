#!/usr/bin/env python3
"""Install hash-locked reference compilers, artifacts, and upstream sources."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import posixpath
import tarfile
import urllib.request
import zipfile

from run_jvm_reference import execute

HERE = Path(__file__).resolve().parent


def download(record: dict, directory: Path) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / record["url"].rsplit("/", 1)[1]
    digest = hashlib.sha256()
    with urllib.request.urlopen(record["url"], timeout=60) as response, path.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)
            digest.update(chunk)
    if digest.hexdigest() != record["sha256"]:
        path.unlink()
        raise ValueError(f"download SHA-256 mismatch: {record['url']}")
    return path


def safe_member(name: str, prefix: str) -> None:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != prefix:
        raise ValueError(f"unsafe archive path: {name}")


def validate_tar_member(member: tarfile.TarInfo, prefix: str) -> None:
    safe_member(member.name, prefix)
    if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
        raise ValueError(f"unsupported SDK archive entry: {member.name}")
    if member.issym() or member.islnk():
        if PurePosixPath(member.linkname).is_absolute():
            raise ValueError(f"absolute SDK link: {member.linkname}")
        target = (posixpath.join(posixpath.dirname(member.name), member.linkname)
            if member.issym() else member.linkname)
        safe_member(posixpath.normpath(target), prefix)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=("jvm", "macos_arm64", "macos_x64", "linux_x64"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    lock = json.loads((HERE / "reference-lock.json").read_text())
    (args.output / "install-plan.json").write_text(json.dumps({
        "target": args.target, "repository": lock["repository"], "commit": lock["commit"],
        "reference_lock_sha256": hashlib.sha256((HERE / "reference-lock.json").read_bytes()).hexdigest(),
    }, indent=2) + "\n")
    upstream = args.output / "upstream"
    for stage, command in (
        ("prepare-git-init", ["git", "init", str(upstream)]),
        ("prepare-git-fetch", ["git", "-C", str(upstream), "fetch", "--depth=1", lock["repository"], lock["commit"]]),
        ("prepare-git-checkout", ["git", "-C", str(upstream), "checkout", "--detach", "FETCH_HEAD"]),
    ):
        if execute(command, args.output, stage, 120):
            raise RuntimeError(f"{stage} failed; raw logs and command retained in {args.output}")
    downloads = args.output / "downloads"
    if args.target == "jvm":
        compiler = download(lock["compiler_archive"], downloads)
        with zipfile.ZipFile(compiler) as archive:
            for member in archive.infolist():
                safe_member(member.filename, "kotlinc")
            archive.extractall(args.output / "installation")
        installation = args.output / "installation/kotlinc"
        (installation / "bin/kotlinc").chmod(0o755)
        artifacts = lock["jvm_artifacts"]
    else:
        compiler = download(lock["native_compiler_archives"][args.target], downloads)
        prefix = compiler.name.removesuffix(".tar.gz")
        with tarfile.open(compiler, "r:gz") as archive:
            for member in archive.getmembers():
                validate_tar_member(member, prefix)
            archive.extractall(args.output / "installation")
        installation = next(path.parent.parent for path in (args.output / "installation").glob("*/bin/kotlinc-native"))
        artifacts = [row for row in lock["native_artifacts"] if args.target.replace("_", "") in row["coordinate"]]
    dependencies = args.output / "dependencies"
    for artifact in artifacts:
        download(artifact, dependencies)
    (args.output / "paths.json").write_text(json.dumps({
        "target": args.target, "upstream": str(upstream.resolve()), "installation": str(installation.resolve()),
        "dependencies": str(dependencies.resolve()), "compiler_archive_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
        "compiler_archive": str(compiler.resolve()),
        "reference_lock_sha256": hashlib.sha256((HERE / "reference-lock.json").read_bytes()).hexdigest(),
    }, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
