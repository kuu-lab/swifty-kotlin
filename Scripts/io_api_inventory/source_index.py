"""Match source declarations by Kotlin owner, receiver and parameter types.

Type syntax comes from Kotlin PSI, never a name-only regular expression. Unknown
types retain an explicit unresolved marker and cannot match a resolved API key.
"""

import hashlib
import json
import re
from collections import defaultdict


BUILTINS = {
    name: "kotlin." + name for name in (
        "Any", "Nothing", "Unit", "Boolean", "Byte", "Short", "Int", "Long",
        "Float", "Double", "Char", "String", "CharSequence", "Array", "ByteArray",
        "ShortArray", "IntArray", "LongArray", "UByte", "UInt", "ULong", "UShort",
        "UByteArray", "UIntArray", "ULongArray", "UShortArray", "Comparable", "Comparator",
        "Throwable", "Exception", "RuntimeException", "IllegalArgumentException",
        "IllegalStateException", "IndexOutOfBoundsException", "Annotation",
    )
}
BUILTINS.update({name: "kotlin.collections." + name for name in (
    "Iterable", "Iterator", "Collection", "List", "MutableList", "Set", "MutableSet",
    "Map", "MutableMap", "ListIterator", "MutableIterator",
)})
BUILTINS.update({"Appendable": "kotlin.text.Appendable", "IntRange": "kotlin.ranges.IntRange"})
BUILTINS["HexFormat"] = "kotlin.text.HexFormat"


def api_key(api_id, kind):
    identity, separator, signature = api_id.partition("|")
    identity = re.sub(r"\.<(?:get|set)-[^>]+>$", "", identity).replace("/", ".")
    accessor = kind == "source accessor"
    if accessor:
        kind = "property"
    if kind in {"class", "interface", "object", "annotation class"}:
        return kind, identity, "", ()
    if kind == "property":
        receiver = signature.partition("(")[0].partition("@")[2] if accessor else signature.partition("{}")[0].lstrip("@")
        return kind, identity, receiver, ()
    parameters = signature.partition("(")[2].partition(")")[0]
    prefix = signature.partition("(")[0]
    receiver = prefix.partition("@")[2]
    return kind, identity, receiver, tuple(parameters.split(";")) if parameters else ()


class SourceIndex:
    def __init__(self, path, repository, upstream):
        data = path.read_bytes()
        catalog = json.loads(data.decode("utf-8"))
        lock = json.loads(path.with_name("upstream-lock.json").read_text(encoding="utf-8"))
        if hashlib.sha256(data).hexdigest() != lock["sourceDeclarationsSha256"]:
            raise ValueError("Source declaration catalog lock mismatch")
        if catalog["schemaVersion"] != 1 or catalog["toolchain"]["kotlinVersion"] != "2.3.10":
            raise ValueError("Unsupported source declaration catalog")
        adapter = path.with_name("ExtractSourceDeclarations.kt")
        if hashlib.sha256(adapter.read_bytes()).hexdigest() != catalog["toolchain"]["extractorSha256"]:
            raise ValueError("PSI adapter changed; refresh the source declaration catalog")
        self.files = {(entry["origin"], entry["path"]): entry for entry in catalog["files"]}
        for (origin, relative), entry in self.files.items():
            root = upstream if origin == "upstream" else repository
            source = (root / relative).resolve()
            if root.resolve() not in source.parents or hashlib.sha256(source.read_bytes()).hexdigest() != entry["sha256"]:
                raise ValueError("Source catalog hash mismatch: " + relative)
        actual = {
            ("upstream", source.relative_to(upstream).as_posix()) for source in upstream.rglob("*.kt")
        } | {
            ("local", source.relative_to(repository).as_posix())
            for source in (repository / "Sources/CompilerCore/Stdlib/kotlinx/io").rglob("*.kt")
        }
        if actual != set(self.files):
            raise ValueError("Source catalog file set changed; refresh it")
        expected_runtime = {entry["path"]: entry["sha256"] for entry in catalog["runtimeFiles"]}
        actual_runtime = {source.relative_to(repository).as_posix(): hashlib.sha256(source.read_bytes()).hexdigest()
                          for source in (repository / "Sources/Runtime").rglob("*.swift")}
        if expected_runtime != actual_runtime:
            raise ValueError("Runtime implementation catalog inputs changed; refresh it")
        self.declarations = catalog["declarations"]
        self.types = {d["fqName"] for d in self.declarations if d["kind"] in {"class", "interface", "object", "annotation class", "typealias"}}
        self.by_key = defaultdict(list)
        for declaration in self.declarations:
            declaration["_key"] = self.declaration_key(declaration)
            self.by_key[(declaration["origin"], declaration["_key"])].append(declaration)

    def resolve_name(self, name, declaration):
        file = self.files[(declaration["origin"], declaration["path"])]
        generic = {parameter["name"]: "0:%d" % index for index, parameter in enumerate(declaration.get("typeParameters") or [])}
        if name in generic:
            return generic[name]
        first, dot, rest = name.partition(".")
        imported = [entry["name"] for entry in file["imports"] if not entry["wildcard"] and (entry["alias"] or entry["name"].rsplit(".", 1)[-1]) == first]
        if len(set(imported)) == 1:
            return imported[0] + ("." + rest if dot else "")
        if name.startswith(("kotlin.", "kotlinx.", "java.", "platform.", "kotlinx.")):
            return name
        owners = declaration["owner"].split(".")
        for size in range(len(owners), len(file["package"].split(".")) - 1, -1):
            candidate = ".".join(owners[:size] + [name])
            if candidate in self.types:
                return candidate
        if name in BUILTINS:
            return BUILTINS[name]
        stars = [entry["name"] + "." + name for entry in file["imports"] if entry["wildcard"]]
        known = [candidate for candidate in stars if candidate in self.types or candidate in BUILTINS.values()]
        if len(set(known)) == 1:
            return known[0]
        return "unresolved:" + name

    def type_name(self, shape, declaration):
        if shape is None:
            return ""
        if shape["kind"] == "nullable":
            return self.type_name(shape["inner"], declaration) + "?"
        if shape["kind"] == "function":
            parameters = ([shape["receiver"]] if shape["receiver"] else []) + shape["parameters"]
            arguments = [self.type_name(parameter, declaration) for parameter in parameters + [shape["result"]]]
            return "kotlin.Function%d<%s>" % (len(parameters), ",".join(arguments))
        if shape["kind"] != "user":
            return "unresolved:" + shape.get("source", str(shape))
        name = self.resolve_name(shape["name"], declaration)
        if shape["arguments"]:
            arguments = []
            for projection in shape["arguments"]:
                if projection["type"] is None:
                    arguments.append("*")
                else:
                    variance = {"IN": "in|", "OUT": "out|"}.get(projection["variance"], "")
                    arguments.append(variance + self.type_name(projection["type"], declaration))
            name += "<" + ",".join(arguments) + ">"
        return name

    def declaration_key(self, declaration):
        kind = declaration["kind"]
        receiver = self.type_name(declaration["receiverShape"], declaration)
        def parameter_type(parameter):
            name = self.type_name(parameter["typeShape"], declaration)
            if not parameter["vararg"]:
                return name
            primitives = {"kotlin." + primitive for primitive in (
                "Byte", "Short", "Int", "Long", "Float", "Double", "Char", "Boolean", "UByte", "UShort", "UInt", "ULong"
            )}
            return (name + "Array" if name in primitives else "kotlin.Array<out|" + name + ">") + "..."
        parameters = tuple(parameter_type(parameter) for parameter in declaration["parameters"]) if kind in {"function", "constructor"} else ()
        return kind, declaration["fqName"], receiver, parameters

    def match(self, origin, key):
        return self.by_key.get((origin, key), [])
