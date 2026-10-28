import Foundation

struct JVMTextParameter {
    let name: String
    let source: String
    let type: JVMValueType
    var fallback: String? = nil
    var variadic = false
}

/// The same intrinsic signatures drive Sema declarations and JVM invocation.
struct JVMTextOperation {
    let name: String
    var receiver = "String"
    var receiverType: JVMValueType = .string
    var parameters: [JVMTextParameter] = []
    var sourceResult = "String"
    var result: JVMValueType = .string
    var owner = "kotlin/text/StringsKt"
    var method: String? = nil
    var instance = false

    static let sequence = JVMValueType.reference("java/lang/CharSequence", nullable: false)
    static let list = JVMValueType.reference("java/util/List", nullable: false)
    static let operations: [JVMTextOperation] = {
        func p(_ name: String, _ source: String, _ type: JVMValueType, _ fallback: String? = nil, variadic: Bool = false) -> JVMTextParameter { JVMTextParameter(name: name, source: source, type: type, fallback: fallback, variadic: variadic) }
        var ops: [JVMTextOperation] = []
        func add(_ name: String, _ params: [JVMTextParameter] = [], sourceResult: String = "String", result: JVMValueType = .string, receiver: String = "String", jvmReceiver: JVMValueType = .string, owner: String = "kotlin/text/StringsKt", method: String? = nil, instance: Bool = false) {
            ops.append(JVMTextOperation(name: name, receiver: receiver, receiverType: jvmReceiver, parameters: params, sourceResult: sourceResult, result: result, owner: owner, method: method, instance: instance))
        }
        for receiver in ["String", "CharSequence"] {
            let rt: JVMValueType = receiver == "String" ? .string : sequence
            add("get", [p("index", "Int", .int)], sourceResult: "Char", result: .char, receiver: receiver, jvmReceiver: rt, owner: rt.referenceName!, method: "charAt", instance: true)
            add("isEmpty", sourceResult: "Boolean", result: .boolean, receiver: receiver, jvmReceiver: rt)
            add("isNotEmpty", sourceResult: "Boolean", result: .boolean, receiver: receiver, jvmReceiver: rt)
            add("isBlank", sourceResult: "Boolean", result: .boolean, receiver: receiver, jvmReceiver: sequence)
            add("isNotBlank", sourceResult: "Boolean", result: .boolean, receiver: receiver, jvmReceiver: sequence)
            add("subSequence", [p("startIndex", "Int", .int), p("endIndex", "Int", .int)], sourceResult: "CharSequence", result: sequence, receiver: receiver, jvmReceiver: rt, owner: rt.referenceName!, instance: true)
            for name in ["first", "last"] {
                add(name, sourceResult: "Char", result: .char, receiver: receiver, jvmReceiver: sequence)
                add(name + "OrNull", sourceResult: "Char?", result: .reference("java/lang/Character", nullable: true), receiver: receiver, jvmReceiver: sequence)
            }
        }
        add("substring", [p("startIndex", "Int", .int), p("endIndex", "Int", .int, "length")], owner: "java/lang/String", instance: true)
        add("codePointAt", [p("index", "Int", .int)], sourceResult: "Int", result: .int, owner: "java/lang/String", instance: true)
        let intStream = JVMValueType.reference("java/util/stream/IntStream", nullable: false)
        for name in ["chars", "codePoints"] {
            add(name, sourceResult: "IntStream", result: intStream, receiver: "CharSequence", jvmReceiver: sequence, owner: "java/lang/CharSequence", instance: true)
        }
        add("slice", [p("indices", "IntRange", .reference("kotlin/ranges/IntRange", nullable: false))])
        add("slice", [p("indices", "Iterable<Int>", .reference("java/lang/Iterable", nullable: false))], sourceResult: "CharSequence", result: sequence, receiver: "CharSequence", jvmReceiver: sequence)
        for name in ["take", "takeLast", "drop", "dropLast"] { add(name, [p("n", "Int", .int)]) }
        for name in ["trim", "trimStart", "trimEnd"] {
            add(name, result: sequence, jvmReceiver: sequence)
            add(name, [p("chars", "Char", .char, variadic: true)])
        }
        add("trimIndent")
        add("trimMargin", [p("marginPrefix", "String", .string, "margin")])
        for name in ["uppercase", "lowercase", "reversed"] { add(name) }
        add("repeat", [p("n", "Int", .int)], jvmReceiver: sequence)
        for name in ["padStart", "padEnd"] { add(name, [p("length", "Int", .int), p("padChar", "Char", .char, "space")]) }
        for name in ["removePrefix", "removeSuffix"] { add(name, [p(name == "removePrefix" ? "prefix" : "suffix", "CharSequence", sequence)]) }
        add("removeSurrounding", [p("delimiter", "CharSequence", sequence)])
        add("removeSurrounding", [p("prefix", "CharSequence", sequence), p("suffix", "CharSequence", sequence)])
        for name in ["startsWith", "endsWith", "contains"] {
            for char in [false, true] {
                let element: JVMValueType = char ? .char : (name == "contains" ? sequence : .string)
                let parameter = name == "startsWith" ? "prefix" : (name == "endsWith" ? "suffix" : (char ? "char" : "other"))
                add(name, [p(parameter, char ? "Char" : (name == "contains" ? "CharSequence" : "String"), element), p("ignoreCase", "Boolean", .boolean, "false")], sourceResult: "Boolean", result: .boolean, jvmReceiver: char || name == "contains" ? sequence : .string)
                if name == "contains" {
                    add(name, [p(parameter, char ? "Char" : "CharSequence", element), p("ignoreCase", "Boolean", .boolean, "false")], sourceResult: "Boolean", result: .boolean, receiver: "CharSequence", jvmReceiver: sequence)
                }
            }
        }
        add("startsWith", [p("prefix", "String", .string), p("startIndex", "Int", .int), p("ignoreCase", "Boolean", .boolean, "false")], sourceResult: "Boolean", result: .boolean)
        for name in ["indexOf", "lastIndexOf"] {
            for char in [false, true] {
                add(name, [p(char ? "char" : "string", char ? "Char" : "String", char ? .char : .string), p("startIndex", "Int", .int, name == "indexOf" ? "0" : "lastIndex"), p("ignoreCase", "Boolean", .boolean, "false")], sourceResult: "Int", result: .int, jvmReceiver: sequence)
            }
        }
        for name in ["substringBefore", "substringAfter", "substringBeforeLast", "substringAfterLast"] {
            for char in [false, true] { add(name, [p("delimiter", char ? "Char" : "String", char ? .char : .string), p("missingDelimiterValue", "String", .string, "this")]) }
        }
        for name in ["replace", "replaceFirst"] {
            for char in [false, true] { add(name, [p(char ? "oldChar" : "oldValue", char ? "Char" : "String", char ? .char : .string), p(char ? "newChar" : "newValue", char ? "Char" : "String", char ? .char : .string), p("ignoreCase", "Boolean", .boolean, "false")]) }
        }
        for char in [false, true] { add("split", [p("delimiters", char ? "Char" : "String", char ? .char : .string, variadic: true), p("ignoreCase", "Boolean", .boolean, "false"), p("limit", "Int", .int, "0")], sourceResult: "List<String>", result: list, jvmReceiver: sequence) }
        add("equals", [p("other", "Any?", .reference("java/lang/Object", nullable: true))], sourceResult: "Boolean", result: .boolean, owner: "java/lang/String", instance: true)
        add("equals", [p("other", "String?", .reference("java/lang/String", nullable: true)), p("ignoreCase", "Boolean", .boolean, "false")], sourceResult: "Boolean", result: .boolean, receiver: "String?", jvmReceiver: .reference("java/lang/String", nullable: true))
        add("compareTo", [p("other", "String", .string), p("ignoreCase", "Boolean", .boolean, "false")], sourceResult: "Int", result: .int)
        add("toCharArray", [p("startIndex", "Int", .int, "0"), p("endIndex", "Int", .int, "length")], sourceResult: "CharArray", result: .reference("[C", nullable: false))
        add("concatToString", [p("startIndex", "Int", .int, "0"), p("endIndex", "Int", .int, "length")], receiver: "CharArray", jvmReceiver: .reference("[C", nullable: false))
        for (name, type, wrapper) in [("Byte", JVMValueType.byte, "Byte"), ("Short", .short, "Short"), ("Int", .int, "Integer"), ("Long", .long, "Long")] {
            add("to" + name, [p("radix", "Int", .int, "10")], sourceResult: name, result: type, owner: "java/lang/" + wrapper, method: "parse" + name)
            add("to" + name + "OrNull", [p("radix", "Int", .int, "10")], sourceResult: name + "?", result: .reference("java/lang/" + wrapper, nullable: true))
        }
        for (name, type) in [("Float", JVMValueType.float), ("Double", .double)] {
            add("to" + name, sourceResult: name, result: type, owner: "java/lang/" + name, method: "parse" + name)
            add("to" + name + "OrNull", sourceResult: name + "?", result: .reference("java/lang/" + name, nullable: true))
        }
        add("toBoolean", sourceResult: "Boolean", result: .boolean, receiver: "String?", jvmReceiver: .reference("java/lang/String", nullable: true), owner: "java/lang/Boolean", method: "parseBoolean")
        add("toBooleanStrict", sourceResult: "Boolean", result: .boolean)
        add("toBooleanStrictOrNull", sourceResult: "Boolean?", result: .reference("java/lang/Boolean", nullable: true))
        return ops
    }()
}
