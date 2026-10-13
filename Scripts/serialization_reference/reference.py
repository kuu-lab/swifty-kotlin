#!/usr/bin/env python3
"""Verify pinned upstream ABI evidence and run the real JVM reference."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent


def read_manifest(root=ROOT):
    return json.loads((root / "manifest.json").read_text())


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def verify_files(root, manifest):
    for record in manifest["files"]:
        path = root / record["path"]
        if root.resolve() not in path.resolve().parents:
            raise ValueError("Invalid pinned path: " + record["path"])
        data = path.read_bytes()
        blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        if sha256(data) != record["sha256"] or blob != record["git_blob"]:
            raise ValueError("Upstream hash mismatch: " + record["path"])


def expand_targets(names, aliases):
    return sorted({target for name in names for target in aliases.get(name, [name])})


def declarations(root, manifest):
    records = []
    for file in manifest["files"]:
        if not file["path"].endswith(".api"):
            continue
        aliases, owners = {}, []
        dump_targets = ["jvm"] if file["platform"] == "jvm" else []
        pending_targets = None
        seen_declaration = False
        for number, raw in enumerate((root / file["path"]).read_text().splitlines(), 1):
            text = raw.strip()
            target_match = re.fullmatch(r"// Targets: \[(.*)\]", text)
            alias_match = re.fullmatch(r"// Alias: (\w+) => \[(.*)\]", text)
            if alias_match:
                aliases[alias_match[1]] = alias_match[2].split(", ")
            if target_match:
                names = target_match[1].split(", ")
                if not seen_declaration:
                    dump_targets = names
                else:
                    pending_targets = names
            if not text or text.startswith("//") or text == "}":
                continue
            indent = len(raw.expandtabs(4)) - len(raw.expandtabs(4).lstrip())
            while owners and owners[-1][0] >= indent:
                owners.pop()
            signature, _, abi_id = text.partition(" // ")
            targets = expand_targets(pending_targets if pending_targets is not None else
                                     owners[-1][2] if owners else dump_targets, aliases)
            pending_targets = None
            seen_declaration = True
            owner = " > ".join(value for _, value, _ in owners)
            identity = json.dumps([file["module"], file["platform"], owner, signature, targets])
            classifications = [file["platform"] + "-abi"]
            if "synthetic" in signature or "$default" in signature:
                classifications.append("synthetic")
            if re.search(r"kotlinx[./]serialization(?:[./]\w+)*[./]internal[./]", owner + signature):
                classifications.append("exported-internal-package")
            if any(name in signature for name in ["java/", "java.", "com/typesafe/config", "com.typesafe.config"]):
                classifications.append("jvm-dependency")
            records.append({
                "id": sha256(identity.encode()), "module": file["module"], "dump": file["path"],
                "platform": file["platform"], "targets": list(targets), "line": number,
                "owner": owner, "signature": signature, "abi_id": abi_id or None,
                "classification": classifications, "implementation": "unmapped",
            })
            owners.append((indent, signature, targets))
    ids = [record["id"] for record in records]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate declaration identity")
    return {"schema_version": 1, "commit": manifest["commit"], "declarations": records}


def index_text(root, manifest):
    index = declarations(root, manifest)
    rows = ",\n".join("    " + json.dumps(row) for row in index.pop("declarations"))
    header = json.dumps(index, indent=2)[:-2]
    return header + ',\n  "declarations": [\n' + rows + "\n  ]\n}\n"


def verify_index(root, manifest):
    if (root / "declarations.json").read_text() != index_text(root, manifest):
        raise ValueError("Declaration index is stale; regenerate with the index command")


def verify_implementations(root, manifest):
    path = root / "implementations.json"
    if not path.exists():
        return
    overlay = json.loads(path.read_text())
    if overlay["schema_version"] != 1 or overlay["commit"] != manifest["commit"]:
        raise ValueError("Implementation mappings use a different upstream snapshot")
    declarations_by_id = {row["id"]: row for row in declarations(root, manifest)["declarations"]}
    repository = root.parent.parent.resolve()
    seen = set()
    for mapping in overlay["mappings"]:
        identity = mapping["declaration_id"]
        if identity in seen or identity not in declarations_by_id:
            raise ValueError("Duplicate or unknown implementation declaration: " + identity)
        seen.add(identity)
        for relative in mapping["source"] + [mapping["fixture"], mapping["expected"], mapping["test"]]:
            target = repository / relative
            if repository not in target.resolve().parents or not target.is_file():
                raise ValueError("Missing or invalid implementation path: " + relative)
    # The factory's rejection set follows Native's registry, including builtin
    # arrays and modern time/uuid types, rather than just the nine primitive kinds.
    native = (root / "upstream/core/nativeMain/src/kotlinx/serialization/internal/Platform.kt").read_text()
    registry = native.split("internal actual fun initBuiltins()", 1)[1]
    names = re.findall(r"^\s*(\w+)::class to", registry, re.MULTILINE)
    qualified = {"kotlin." + ("time." if name in {"Duration", "Instant"} else
                             "uuid." if name == "Uuid" else "") + name: name + "Serializer"
                 for name in names}
    factory = repository / "Sources/CompilerCore/Stdlib/kotlinx/serialization/descriptors/PrimitiveSerialDescriptor.kt"
    projection = dict(re.findall(r'^\s*"([^"]+)" -> "(\w+)"', factory.read_text(), re.MULTILINE))
    if len(names) != 30 or projection != qualified:
        raise ValueError("Primitive descriptor reserved names differ from the pinned Native registry")


def verify_artifacts(cache, manifest):
    paths = []
    for record in manifest["artifacts"]:
        path = cache / record["filename"]
        data = path.read_bytes()
        if len(data) != record["bytes"] or sha256(data) != record["sha256"]:
            raise ValueError("Artifact hash mismatch: " + record["filename"])
        paths.append(path)
    return paths


def fetch_artifacts(cache, manifest):
    cache.mkdir(parents=True, exist_ok=True)
    for record in manifest["artifacts"]:
        destination = cache / record["filename"]
        if destination.exists():
            data = destination.read_bytes()
        else:
            with urllib.request.urlopen(record["url"], timeout=30) as response:
                data = response.read()
            with urllib.request.urlopen(record["url"] + ".sha1", timeout=30) as response:
                published = response.read().decode().strip().split()[0]
            if published != record["published_sha1"] or hashlib.sha1(data).hexdigest() != published:
                raise ValueError("Published checksum mismatch: " + record["filename"])
        if len(data) != record["bytes"] or sha256(data) != record["sha256"]:
            raise ValueError("Artifact hash mismatch: " + record["filename"])
        if not destination.exists():
            with tempfile.NamedTemporaryFile(dir=cache, delete=False) as temporary:
                temporary.write(data)
                temporary_path = Path(temporary.name)
            temporary_path.replace(destination)
    return verify_artifacts(cache, manifest)


def run_reference(root, manifest, cache, kotlin_home, output, case="modules"):
    jars = verify_artifacts(cache, manifest)
    compiler = kotlin_home / "bin/kotlinc"
    runtime = kotlin_home / "bin/kotlin"
    plugin = kotlin_home / "lib/kotlinx-serialization-compiler-plugin.jar"
    version = subprocess.run([str(compiler), "-version"], capture_output=True, text=True, timeout=60)
    if version.returncode or not re.search(r"kotlinc-jvm 2\.3\.10(?:\s|$)", version.stdout + version.stderr):
        raise ValueError("Reference requires Kotlin JVM 2.3.10")
    if sha256(plugin.read_bytes()) != manifest["compiler_plugin_sha256"]:
        raise ValueError("Serialization compiler plugin hash mismatch")
    output.mkdir(parents=True, exist_ok=True)
    fixtures = root.parent / "reference_cases"
    source, expected, main_class = {
        "modules": (root / "serialization_modules.kt", root / "expected.stdout", "Serialization_modulesKt"),
        "primitive-descriptor": (fixtures / "serialization_primitive_descriptor.kt",
                                 fixtures / "serialization_primitive_descriptor.expected", "Serialization_primitive_descriptorKt"),
        "nullable-descriptor": (fixtures / "serialization_nullable_descriptor.kt",
                                fixtures / "serialization_nullable_descriptor.expected", "Serialization_nullable_descriptorKt"),
        "wrapped-descriptor": (fixtures / "serialization_wrapped_descriptor.kt",
                               fixtures / "serialization_wrapped_descriptor.expected", "Serialization_wrapped_descriptorKt"),
        "collection-descriptor": (fixtures / "serialization_collection_descriptor.kt",
                                  fixtures / "serialization_collection_descriptor.expected", "Serialization_collection_descriptorKt"),
        "annotation-api": (fixtures / "serialization_annotation_api.kt",
                           fixtures / "serialization_annotation_api.expected", "Serialization_annotation_apiKt"),
        "class-descriptor": (fixtures / "serialization_class_descriptor.kt",
                             fixtures / "serialization_class_descriptor.expected", "Serialization_class_descriptorKt"),
    }[case]
    jar = output / "reference.jar"
    jar.unlink(missing_ok=True)
    classpath = os.pathsep.join(str(path.resolve()) for path in jars)
    commands = [
        [str(compiler), "-Xplugin=" + str(plugin), "-classpath", classpath,
         str(source), "-d", str(jar)],
        [str(runtime), "-classpath", str(jar.resolve()) + os.pathsep + classpath, main_class],
    ]
    evidence = {"version_output": version.stdout + version.stderr, "java_version": "",
                "case": case, "source_sha256": sha256(source.read_bytes()),
                "plugin_sha256": manifest["compiler_plugin_sha256"], "runs": []}
    java = subprocess.run(["java", "-version"], capture_output=True, text=True, timeout=30)
    evidence["java_version"] = java.stdout + java.stderr
    for label, command in zip(["compile", "run"], commands):
        result = subprocess.run(command, capture_output=True, text=True, timeout=180)
        (output / (label + ".stdout")).write_text(result.stdout)
        (output / (label + ".stderr")).write_text(result.stderr)
        evidence["runs"].append({"command": command, "exit_code": result.returncode})
        (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        if result.returncode:
            raise ValueError(label + " failed; see " + str(output / (label + ".stderr")))
    if (output / "run.stdout").read_text() != expected.read_text():
        raise ValueError("JVM reference output mismatch; see " + str(output / "run.stdout"))
    print((output / "run.stdout").read_text(), end="")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["verify", "index", "fetch", "run"])
    parser.add_argument("--cache", type=Path, default=Path.home() / ".cache/kswiftk/serialization-1.10.0")
    parser.add_argument("--kotlin-home", type=Path, default=os.environ.get("KOTLIN_HOME"))
    parser.add_argument("--output", type=Path, default=Path("serialization-reference-output"))
    parser.add_argument("--case", choices=["modules", "primitive-descriptor", "nullable-descriptor", "wrapped-descriptor", "collection-descriptor", "class-descriptor", "annotation-api"], default="modules")
    args = parser.parse_args()
    manifest = read_manifest()
    verify_files(ROOT, manifest)
    if args.action == "index":
        (ROOT / "declarations.json").write_text(index_text(ROOT, manifest))
    else:
        verify_index(ROOT, manifest)
        verify_implementations(ROOT, manifest)
        if args.action == "fetch":
            fetch_artifacts(args.cache, manifest)
        elif args.action == "run":
            if args.kotlin_home is None:
                parser.error("run requires --kotlin-home or KOTLIN_HOME")
            run_reference(ROOT, manifest, args.cache, args.kotlin_home, args.output, args.case)
    print("serialization reference: " + args.action + " OK")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
