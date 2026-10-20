#!/usr/bin/env python3
"""Check Kotlin runtime class/member references without an official Kotlin JAR.

This is a static linkage check. Execution tests remain necessary to verify
behavior and virtual dispatch, especially implementations of JDK interfaces.
"""
import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import struct
import subprocess
from functools import lru_cache
import sys
import zipfile


@dataclass
class ClassInfo:
    name: str
    parents: list[str]
    methods: set[tuple[str, str]]
    fields: set[tuple[str, str]]
    classes: set[str]
    members: list[tuple[int, str, str, str]]


class Reader:
    def __init__(self, data):
        self.data = data
        self.offset = 0

    def take(self, size):
        if size < 0 or size > len(self.data) - self.offset:
            raise ValueError("Truncated class file")
        result = self.data[self.offset:self.offset + size]
        self.offset += size
        return result

    def u1(self):
        return self.take(1)[0]

    def u2(self):
        return struct.unpack(">H", self.take(2))[0]

    def u4(self):
        return struct.unpack(">I", self.take(4))[0]


def read_class(data):
    r = Reader(data)
    if r.u4() != 0xCAFEBABE:
        raise ValueError("Invalid class magic")
    r.take(4)
    pool = [None] * r.u2()
    index = 1
    while index < len(pool):
        tag = r.u1()
        if tag == 1:
            # Names/descriptors are ASCII; metadata may use modified UTF-8.
            pool[index] = (tag, r.take(r.u2()).decode("utf-8", errors="replace"))
        elif tag in (3, 4):
            r.take(4)
        elif tag in (5, 6):
            r.take(8)
            index += 1
        elif tag in (7, 8, 16, 19, 20):
            pool[index] = (tag, r.u2())
        elif tag in (9, 10, 11, 12, 17, 18):
            pool[index] = (tag, r.u2(), r.u2())
        elif tag == 15:
            r.take(3)
        else:
            raise ValueError(f"Unsupported constant pool tag {tag}")
        index += 1

    def utf8(index):
        return pool[index][1]

    def classname(index):
        return utf8(pool[index][1])

    descriptors = set()

    def annotation():
        descriptors.add(utf8(r.u2()))
        for _ in range(r.u2()):
            r.u2()
            element_value()

    def element_value():
        tag = chr(r.u1())
        if tag == "e":
            descriptors.add(utf8(r.u2()))
            r.u2()
        elif tag == "c":
            descriptors.add(utf8(r.u2()))
        elif tag == "@":
            annotation()
        elif tag == "[":
            for _ in range(r.u2()):
                element_value()
        elif tag in "BCDFIJSZs":
            r.u2()
        else:
            raise ValueError(f"Invalid annotation element tag {tag}")

    def attributes():
        for _ in range(r.u2()):
            attribute = utf8(r.u2())
            end = r.u4() + r.offset
            if attribute == "Signature":
                descriptors.add(utf8(r.u2()))
            elif attribute in ("RuntimeVisibleAnnotations", "RuntimeInvisibleAnnotations"):
                for _ in range(r.u2()):
                    annotation()
            elif attribute in ("RuntimeVisibleParameterAnnotations", "RuntimeInvisibleParameterAnnotations"):
                for _ in range(r.u1()):
                    for _ in range(r.u2()):
                        annotation()
            elif attribute == "AnnotationDefault":
                element_value()
            if r.offset > end:
                raise ValueError("Invalid attribute size")
            r.take(end - r.offset)

    r.u2()
    name = classname(r.u2())
    superclass = r.u2()
    parents = ([classname(superclass)] if superclass else [])
    parents += [classname(r.u2()) for _ in range(r.u2())]

    def declarations():
        result = set()
        for _ in range(r.u2()):
            r.u2()
            member_name, descriptor = utf8(r.u2()), utf8(r.u2())
            result.add((member_name, descriptor))
            descriptors.add(descriptor)
            attributes()
        return result

    fields = declarations()
    methods = declarations()
    attributes()
    references = set()
    members = []
    for entry in pool:
        if entry is None:
            continue
        if entry[0] == 7:
            value = utf8(entry[1])
            if value.startswith("["):
                descriptors.add(value)
            else:
                references.add(value)
        if entry[0] == 12:
            descriptors.add(utf8(entry[2]))
        elif entry[0] == 16:
            descriptors.add(utf8(entry[1]))
        if entry[0] in (9, 10, 11):
            pair = pool[entry[2]]
            members.append((entry[0], classname(entry[1]), utf8(pair[1]), utf8(pair[2])))
    for descriptor in descriptors:
        references.update(re.findall(r"L(kotlin/[^;<>()\[\s]+)(?=[;<])", descriptor))
    return ClassInfo(name, parents, methods, fields, references, members)


def classes_in(path):
    if path.is_dir():
        return [read_class(p.read_bytes()) for p in sorted(path.rglob("*.class"))]
    with zipfile.ZipFile(path) as archive:
        return [read_class(archive.read(name)) for name in sorted(archive.namelist())
                if name.endswith(".class") and not name.startswith("META-INF/")]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifacts", nargs="+", type=Path, help="Own stdlib JAR and optional generated/consumer JARs or class directories")
    args = parser.parse_args()
    classes = {}
    for path in args.artifacts:
        for info in classes_in(path):
            # Match Java classpath precedence.
            classes.setdefault(info.name, info)
    @lru_cache(maxsize=None)
    def foreign_class(owner):
        # Resolve inherited JDK members rather than assuming that every member
        # exists on an external superclass. No Kotlin library enters this path.
        if not owner.startswith(("java/", "javax/")):
            return None
        result = subprocess.run(["javap", "-s", "-p", owner.replace("/", ".")], capture_output=True, text=True)
        if result.returncode:
            return None
        methods, fields, parents = set(), set(), []
        previous = ""
        for line in result.stdout.splitlines():
            line = line.strip()
            if line.endswith("{"):
                header = line
                while re.search(r"<[^<>]*>", header):
                    header = re.sub(r"<[^<>]*>", "", header)
                for clause in re.findall(r"(?:extends|implements) (.*?)(?= implements |\{|$)", header):
                    parents.extend(value.strip().replace(".", "/") for value in clause.split(","))
            if line.startswith("descriptor:"):
                descriptor = line.split(":", 1)[1].strip()
                if "(" in previous:
                    name = previous.split("(", 1)[0].split()[-1]
                    if name == owner.replace("/", "."):
                        name = "<init>"
                    methods.add((name, descriptor))
                else:
                    fields.add((previous.rstrip(";").split()[-1], descriptor))
            if line and not line.startswith("descriptor:"):
                previous = line
        if not parents and owner != "java/lang/Object":
            parents.append("java/lang/Object")
        return ClassInfo(owner, parents, methods, fields, set(), [])

    def contains(owner, name, descriptor, field=False, seen=None):
        seen = set() if seen is None else seen
        if owner in seen:
            return False
        seen.add(owner)
        info = classes.get(owner) or foreign_class(owner)
        if info is None:
            return False
        if (name, descriptor) in (info.fields if field else info.methods):
            return True
        if name == "<init>":
            return False
        return any(contains(parent, name, descriptor, field, seen) for parent in info.parents)

    failures = set()
    references = 0
    for info in classes.values():
        for name in info.classes:
            if name.startswith("kotlin/") and name not in classes:
                failures.add(f"{info.name}: missing class {name}")
        for tag, owner, name, descriptor in info.members:
            if not owner.startswith("kotlin/") and owner not in classes:
                continue
            references += 1
            if owner not in classes:
                failures.add(f"{info.name}: missing class {owner}")
            elif not contains(owner, name, descriptor, tag == 9):
                failures.add(f"{info.name}: missing {'field' if tag == 9 else 'method'} {owner}.{name}{descriptor}")
    for failure in sorted(failures):
        print(failure, file=sys.stderr)
    print(f"Checked {len(classes)} classes and {references} member references; {len(failures)} unresolved references.")
    return bool(failures)


if __name__ == "__main__":
    sys.exit(main())
