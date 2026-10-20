import Foundation

/// Kotlin compilers resolve mapped JVM types through built-in package fragments.
/// These fragments describe this bootstrap library's supported API; no bytes are
/// read from an installed Kotlin distribution.
enum JVMBuiltins {
    private final class Fragment {
        typealias Proto = JVMMetadata.Proto
        let package: String
        var strings: [String] = []
        struct Name: Equatable { let parent: Int; let short: Int; let kind: Int }
        var names: [Name] = []
        var classes: [Data] = []
        init(_ package: String) { self.package = package; _ = qualified(package, kind: 1) }
        func index(_ name: String) -> Int {
            if let i = strings.firstIndex(of: name) { return i }
            strings.append(name); return strings.count - 1
        }
        func qualified(_ name: String, kind: Int = 0) -> Int {
            let parts = name.split(separator: "/").map(String.init)
            var parent = -1
            for (i, part) in parts.enumerated() {
                let item = Name(parent: parent, short: index(part), kind: i == parts.count - 1 ? kind : 1)
                if let existing = names.firstIndex(of: item) { parent = existing }
                else { names.append(item); parent = names.count - 1 }
            }
            return parent
        }
        func type(_ name: String, _ arguments: [Data] = [], nullable: Bool = false) -> Data {
            var p = Proto(); p.int(6, qualified(name)); if nullable { p.int(3, 1) }
            for argument in arguments { var a = Proto(); a.int(1, 2); a.data(2, argument); p.data(2, a.bytes) }
            return p.bytes
        }
        func parameterType(_ id: Int, nullable: Bool = false) -> Data {
            var p = Proto(); p.int(7, id); if nullable { p.int(3, 1) }; return p.bytes
        }
        func function(_ name: String, _ result: Data, _ parameters: [(String, Data)] = [], flags: Int = 38) -> Data {
            var p = Proto(); p.int(9, flags); p.int(2, index(name)); p.data(3, result)
            for (name, type) in parameters { var a = Proto(); a.int(2, index(name)); a.data(3, type); p.data(6, a.bytes) }
            return p.bytes
        }
        func property(_ name: String, _ type: Data) -> Data {
            var p = Proto(); p.int(11, 550); p.int(2, index(name)); p.data(3, type); p.int(7, 38); return p.bytes
        }
        func declaration(_ name: String, flags: Int = 6, parameters: [(String, Int)] = [], supertypes: [Data] = [], functions: [Data] = [], properties: [Data] = [], constructor: Bool = false) {
            var p = Proto(); p.int(1, flags); p.int(3, qualified(name))
            for (i, pair) in parameters.enumerated() {
                var t = Proto(); t.int(1, i); t.int(2, index(pair.0)); t.int(4, pair.1); t.data(5, type("kotlin/Any", nullable: true)); p.data(5, t.bytes)
            }
            for type in supertypes { p.data(6, type) }
            if constructor { var c = Proto(); c.int(1, 6); p.data(8, c.bytes) }
            for function in functions { p.data(9, function) }
            for property in properties { p.data(10, property) }
            classes.append(p.bytes)
        }
        func emit() -> Data {
            let packageIndex = qualified(package, kind: 1)
            var table = Proto(); for s in strings { table.string(1, s) }
            var qualifiedNames = Proto()
            for name in names {
                var n = Proto(); n.int(2, name.short); n.int(3, name.kind)
                if name.parent >= 0 { n.int(1, name.parent) }; qualifiedNames.data(1, n.bytes)
            }
            var p = Proto(); p.int(151, packageIndex)
            var fragment = Proto(); fragment.data(1, table.bytes); fragment.data(2, qualifiedNames.bytes); fragment.data(3, p.bytes)
            for declaration in classes { fragment.data(4, declaration) }
            var header = JVMBytes(); for v: UInt32 in [3, 1, 0, 7] { header.u4(v) }
            header.data.append(fragment.bytes); return header.data
        }
    }

    static func resources() -> [(String, Data)] {
        let root = Fragment("kotlin")
        let any = root.type("kotlin/Any"), int = root.type("kotlin/Int"), boolean = root.type("kotlin/Boolean")
        root.declaration("kotlin/Any", flags: 22, functions: [root.function("equals", boolean, [("other", root.type("kotlin/Any", nullable: true))], flags: 278), root.function("hashCode", int, flags: 22), root.function("toString", root.type("kotlin/String"), flags: 22)], constructor: true)
        root.declaration("kotlin/Nothing", supertypes: [any])
        root.declaration("kotlin/Annotation", flags: 102, supertypes: [any])
        root.declaration("kotlin/Throwable", flags: 22, supertypes: [any], properties: [root.property("message", root.type("kotlin/String", nullable: true)), root.property("cause", root.type("kotlin/Throwable", nullable: true))])
        root.declaration("kotlin/Unit", flags: 326, supertypes: [any])
        root.declaration("kotlin/Comparable", flags: 102, parameters: [("T", 0)], supertypes: [any], functions: [root.function("compareTo", int, [("other", root.parameterType(0))], flags: 294)])
        let conversions = ["Byte", "Short", "Int", "Long", "Float", "Double"]
        root.declaration("kotlin/Number", flags: 38, supertypes: [any], functions: conversions.map { root.function("to" + $0, root.type("kotlin/" + $0)) })
        for name in ["Byte", "Short", "Int", "Long", "Float", "Double", "Char", "Boolean"] {
            let own = root.type("kotlin/" + name)
            var functions: [Data] = []
            if name == "Boolean" { functions.append(root.function("not", boolean, flags: 262)) }
            else {
                let numeric = ["Byte", "Short", "Int", "Long", "Float", "Double"]
                if numeric.contains(name) {
                    for other in numeric {
                        let result = [name, other].contains("Double") ? "Double" : [name, other].contains("Float") ? "Float" : [name, other].contains("Long") ? "Long" : "Int"
                        for operation in ["plus", "minus", "times", "div", "rem"] { functions.append(root.function(operation, root.type("kotlin/" + result), [("other", root.type("kotlin/" + other))], flags: 262)) }
                        functions.append(root.function("compareTo", int, [("other", root.type("kotlin/" + other))], flags: 262))
                    }
                    for operation in ["unaryPlus", "unaryMinus"] { functions.append(root.function(operation, ["Byte", "Short"].contains(name) ? int : own, flags: 262)) }
                }
                for operation in ["inc", "dec"] { functions.append(root.function(operation, own, flags: 262)) }
            }
            if ["Int", "Long", "Boolean"].contains(name) {
                for operation in ["and", "or", "xor"] {
                    functions.append(root.function(operation, own, [("other", own)], flags: 518))
                }
            }
            if ["Int", "Long"].contains(name) {
                for operation in ["shl", "shr", "ushr"] {
                    functions.append(root.function(operation, own, [("bitCount", int)], flags: 518))
                }
                functions.append(root.function("inv", own, flags: 6))
            }
            if conversions.contains(name) { functions += conversions.map { root.function("to" + $0, root.type("kotlin/" + $0), flags: 6) } }
            let parents = conversions.contains(name) ? [root.type("kotlin/Number"), root.type("kotlin/Comparable", [own])] : [any, root.type("kotlin/Comparable", [own])]
            root.declaration("kotlin/" + name, supertypes: parents, functions: functions)
        }
        root.declaration("kotlin/CharSequence", flags: 102, supertypes: [any], functions: [root.function("get", root.type("kotlin/Char"), [("index", int)], flags: 294)], properties: [root.property("length", int)])
        root.declaration("kotlin/String", supertypes: [root.type("kotlin/CharSequence"), root.type("kotlin/Comparable", [root.type("kotlin/String")])], functions: [root.function("plus", root.type("kotlin/String"), [("other", root.type("kotlin/Any", nullable: true))], flags: 262)])
        root.declaration("kotlin/Array", parameters: [("T", 2)], supertypes: [any], functions: [root.function("get", root.parameterType(0), [("index", int)], flags: 294), root.function("set", root.type("kotlin/Unit"), [("index", int), ("value", root.parameterType(0))], flags: 294)], properties: [root.property("size", int)])

        let c = Fragment("kotlin/collections")
        let e = c.parameterType(0), k = c.parameterType(0), v = c.parameterType(1)
        let b = c.type("kotlin/Boolean"), i = c.type("kotlin/Int"), unit = c.type("kotlin/Unit")
        let t = { (name: String, arguments: [Data]) in c.type("kotlin/collections/" + name, arguments) }
        c.declaration("kotlin/collections/Iterator", flags: 102, parameters: [("T", 1)], supertypes: [c.type("kotlin/Any")], functions: [c.function("hasNext", b, flags: 294), c.function("next", e, flags: 294)])
        c.declaration("kotlin/collections/Iterable", flags: 102, parameters: [("T", 1)], supertypes: [c.type("kotlin/Any")], functions: [c.function("iterator", t("Iterator", [e]), flags: 294)])
        c.declaration("kotlin/collections/Collection", flags: 102, parameters: [("E", 1)], supertypes: [t("Iterable", [e])], functions: [c.function("isEmpty", b), c.function("contains", b, [("element", e)], flags: 294)], properties: [c.property("size", i)])
        c.declaration("kotlin/collections/List", flags: 102, parameters: [("E", 1)], supertypes: [t("Collection", [e])], functions: [c.function("get", e, [("index", i)], flags: 294), c.function("indexOf", i, [("element", e)])])
        c.declaration("kotlin/collections/Set", flags: 102, parameters: [("E", 1)], supertypes: [t("Collection", [e])])
        c.declaration("kotlin/collections/Map", flags: 102, parameters: [("K", 2), ("V", 1)], supertypes: [c.type("kotlin/Any")], functions: [c.function("get", c.parameterType(1, nullable: true), [("key", k)], flags: 294), c.function("containsKey", b, [("key", k)]), c.function("containsValue", b, [("value", v)]), c.function("isEmpty", b)], properties: [c.property("size", i), c.property("keys", t("Set", [k])), c.property("values", t("Collection", [v]))])
        c.declaration("kotlin/collections/MutableIterable", flags: 102, parameters: [("T", 1)], supertypes: [t("Iterable", [e])])
        c.declaration("kotlin/collections/MutableCollection", flags: 102, parameters: [("E", 2)], supertypes: [t("Collection", [e]), t("MutableIterable", [e])], functions: [c.function("add", b, [("element", e)]), c.function("remove", b, [("element", e)]), c.function("clear", unit)])
        c.declaration("kotlin/collections/MutableList", flags: 102, parameters: [("E", 2)], supertypes: [t("List", [e]), t("MutableCollection", [e])], functions: [c.function("set", e, [("index", i), ("element", e)], flags: 294), c.function("removeAt", e, [("index", i)])])
        c.declaration("kotlin/collections/MutableSet", flags: 102, parameters: [("E", 2)], supertypes: [t("Set", [e]), t("MutableCollection", [e])])
        c.declaration("kotlin/collections/MutableMap", flags: 102, parameters: [("K", 2), ("V", 2)], supertypes: [t("Map", [k, v])], functions: [c.function("put", c.parameterType(1, nullable: true), [("key", k), ("value", v)]), c.function("remove", c.parameterType(1, nullable: true), [("key", k)]), c.function("clear", unit)])
        return [("kotlin/kotlin.kotlin_builtins", root.emit()), ("kotlin/collections/collections.kotlin_builtins", c.emit())]
    }
}
