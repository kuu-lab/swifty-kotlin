import Foundation

/// JVM-parity direct supertypes for bundled builtin types. kotlin-reflect reports
/// JVM-only supertypes (`kotlin.Number`, `java.io.Serializable`,
/// `kotlin.Cloneable`, …) that Sema does not model, so the display-name lists
/// are curated here keyed by qualified name. Verified against kotlinc +
/// kotlin-reflect. Also consulted by `java.lang.Class.interfaces`/`superclass`
/// (`__kk_class_interfaces`/`__kk_class_superclass`) for builtin class tokens
/// that carry no registered metadata.
let runtimeBuiltinSupertypes: [String: [String]] = {
    var table: [String: [String]] = [
        "kotlin.Any": [],
        "kotlin.Unit": ["kotlin.Any"],
        "kotlin.Nothing": ["kotlin.Any"],
        // Kotlin/JVM 2.4.20 reflection lists Serializable directly on boxed primitives.
        "kotlin.Byte": ["kotlin.Number", "kotlin.Comparable<kotlin.Byte>", "java.io.Serializable"],
        "kotlin.Short": ["kotlin.Number", "kotlin.Comparable<kotlin.Short>", "java.io.Serializable"],
        "kotlin.Int": ["kotlin.Number", "kotlin.Comparable<kotlin.Int>", "java.io.Serializable"],
        "kotlin.Long": ["kotlin.Number", "kotlin.Comparable<kotlin.Long>", "java.io.Serializable"],
        "kotlin.Float": ["kotlin.Number", "kotlin.Comparable<kotlin.Float>", "java.io.Serializable"],
        "kotlin.Double": ["kotlin.Number", "kotlin.Comparable<kotlin.Double>", "java.io.Serializable"],
        "kotlin.UByte": ["kotlin.Comparable<kotlin.UByte>", "kotlin.Any"],
        "kotlin.UShort": ["kotlin.Comparable<kotlin.UShort>", "kotlin.Any"],
        "kotlin.UInt": ["kotlin.Comparable<kotlin.UInt>", "kotlin.Any"],
        "kotlin.ULong": ["kotlin.Comparable<kotlin.ULong>", "kotlin.Any"],
        "kotlin.Char": ["kotlin.Comparable<kotlin.Char>", "java.io.Serializable", "kotlin.Any"],
        "kotlin.Boolean": ["kotlin.Comparable<kotlin.Boolean>", "java.io.Serializable", "kotlin.Any"],
        "kotlin.String": [
            "kotlin.Comparable<kotlin.String>", "kotlin.CharSequence",
            "java.io.Serializable", "kotlin.Any",
        ],
        "kotlin.Throwable": ["kotlin.Any", "java.io.Serializable"],
        "kotlin.Exception": ["kotlin.Throwable"],
        "kotlin.RuntimeException": ["java.lang.Exception"],
        "kotlin.Error": ["kotlin.Throwable"],
        "kotlin.Number": ["kotlin.Any", "java.io.Serializable"],
        "kotlin.Enum": ["kotlin.Comparable<E>", "java.io.Serializable", "kotlin.Any"],
        "kotlin.Annotation": ["kotlin.Any"],
        "kotlin.Comparable": ["kotlin.Any"],
        "kotlin.CharSequence": ["kotlin.Any"],
        "kotlin.Cloneable": ["kotlin.Any"],
        "kotlin.collections.Iterable": ["kotlin.Any"],
        "kotlin.collections.Collection": ["kotlin.collections.Iterable<E>", "kotlin.Any"],
        "kotlin.collections.MutableCollection": ["kotlin.collections.Iterable<E>", "kotlin.Any"],
        "kotlin.collections.List": ["kotlin.collections.Collection<E>", "kotlin.Any"],
        "kotlin.collections.MutableList": ["kotlin.collections.Collection<E>", "kotlin.Any"],
        "kotlin.collections.Set": ["kotlin.collections.Collection<E>", "kotlin.Any"],
        "kotlin.collections.MutableSet": ["kotlin.collections.Collection<E>", "kotlin.Any"],
        "kotlin.collections.Map": ["kotlin.Any"],
        "kotlin.collections.MutableMap": ["kotlin.Any"],
        "kotlin.collections.Map.Entry": ["kotlin.Any"],
        "kotlin.collections.MutableMap.MutableEntry": ["kotlin.Any"],
        "kotlin.collections.Iterator": ["kotlin.Any"],
        "kotlin.collections.MutableIterator": ["kotlin.Any"],
        "kotlin.collections.ListIterator": ["kotlin.collections.Iterator<T>", "kotlin.Any"],
        "kotlin.collections.MutableListIterator": ["kotlin.collections.Iterator<T>", "kotlin.Any"],
        "kotlin.Array": ["kotlin.Any", "kotlin.Cloneable", "java.io.Serializable"],
        "kotlin.ByteArray": ["kotlin.Any", "kotlin.Cloneable", "java.io.Serializable"],
        "kotlin.ShortArray": ["kotlin.Any", "kotlin.Cloneable", "java.io.Serializable"],
        "kotlin.IntArray": ["kotlin.Any", "kotlin.Cloneable", "java.io.Serializable"],
        "kotlin.LongArray": ["kotlin.Any", "kotlin.Cloneable", "java.io.Serializable"],
        "kotlin.FloatArray": ["kotlin.Any", "kotlin.Cloneable", "java.io.Serializable"],
        "kotlin.DoubleArray": ["kotlin.Any", "kotlin.Cloneable", "java.io.Serializable"],
        "kotlin.CharArray": ["kotlin.Any", "kotlin.Cloneable", "java.io.Serializable"],
        "kotlin.BooleanArray": ["kotlin.Any", "kotlin.Cloneable", "java.io.Serializable"],
        "kotlin.UByteArray": ["kotlin.collections.Collection<kotlin.UByte>", "kotlin.Any"],
        "kotlin.UShortArray": ["kotlin.collections.Collection<kotlin.UShort>", "kotlin.Any"],
        "kotlin.UIntArray": ["kotlin.collections.Collection<kotlin.UInt>", "kotlin.Any"],
        "kotlin.ULongArray": ["kotlin.collections.Collection<kotlin.ULong>", "kotlin.Any"],
        "kotlin.Pair": ["java.io.Serializable", "kotlin.Any"],
        "kotlin.Triple": ["java.io.Serializable", "kotlin.Any"],
        "kotlin.Result": ["java.io.Serializable", "kotlin.Any"],
        "kotlin.text.Regex": ["java.io.Serializable", "kotlin.Any"],
        "kotlin.text.MatchResult": ["kotlin.Any"],
        "kotlin.ranges.IntRange": [
            "kotlin.ranges.IntProgression", "kotlin.ranges.ClosedRange<kotlin.Int>",
            "kotlin.ranges.OpenEndRange<kotlin.Int>",
        ],
        "kotlin.ranges.IntProgression": ["kotlin.collections.Iterable<kotlin.Int>", "kotlin.Any"],
        "kotlin.ranges.CharRange": [
            "kotlin.ranges.CharProgression", "kotlin.ranges.ClosedRange<kotlin.Char>",
            "kotlin.ranges.OpenEndRange<kotlin.Char>",
        ],
        "kotlin.ranges.CharProgression": ["kotlin.collections.Iterable<kotlin.Char>", "kotlin.Any"],
        "kotlin.sequences.Sequence": ["kotlin.Any"],
        "kotlin.reflect.KClass": [
            "kotlin.reflect.KDeclarationContainer", "kotlin.reflect.KAnnotatedElement",
            "kotlin.reflect.KClassifier", "kotlin.Any",
        ],
        "kotlin.IllegalArgumentException": ["java.lang.RuntimeException"],
        "kotlin.IllegalStateException": ["java.lang.RuntimeException"],
        "kotlin.NoSuchElementException": ["java.lang.RuntimeException"],
        "kotlin.NullPointerException": ["java.lang.RuntimeException"],
        "kotlin.ClassCastException": ["java.lang.RuntimeException"],
        "kotlin.IndexOutOfBoundsException": ["java.lang.RuntimeException"],
        "kotlin.ArrayIndexOutOfBoundsException": ["java.lang.IndexOutOfBoundsException"],
        "kotlin.AssertionError": ["java.lang.Error"],
        "kotlin.ArithmeticException": ["java.lang.RuntimeException"],
        "kotlin.NumberFormatException": ["java.lang.IllegalArgumentException"],
        "kotlin.ConcurrentModificationException": ["java.lang.RuntimeException"],
        "kotlin.UnsupportedOperationException": ["java.lang.RuntimeException"],
        "kotlin.NotImplementedError": ["java.lang.Error"],
        "kotlin.Function": ["kotlin.Any"],
    ]
    for arity in 0...22 {
        table["kotlin.Function\(arity)"] = ["kotlin.Function<R>", "kotlin.Any"]
    }
    return table
}()

private let runtimeBuiltinTypeParameterNames: [String: [String]] = [
    "kotlin.Enum": ["E"],
    "kotlin.Comparable": ["T"],
    "kotlin.collections.Iterable": ["T"],
    "kotlin.collections.Collection": ["E"],
    "kotlin.collections.MutableCollection": ["E"],
    "kotlin.collections.List": ["E"],
    "kotlin.collections.MutableList": ["E"],
    "kotlin.collections.Set": ["E"],
    "kotlin.collections.MutableSet": ["E"],
    "kotlin.collections.Map": ["K", "V"],
    "kotlin.collections.MutableMap": ["K", "V"],
    "kotlin.collections.Map.Entry": ["K", "V"],
    "kotlin.collections.MutableMap.MutableEntry": ["K", "V"],
    "kotlin.collections.Iterator": ["T"],
    "kotlin.collections.MutableIterator": ["T"],
    "kotlin.collections.ListIterator": ["T"],
    "kotlin.collections.MutableListIterator": ["T"],
    "kotlin.Array": ["T"],
    "kotlin.reflect.KClass": ["T"],
]

func runtimeKClassTypeParameterMetadata(
    qualifiedName: String,
    metadata: RuntimeKClassMetadataEntry?
) -> [RuntimeKTypeParameterMetadata] {
    if let parameters = metadata?.typeParameters, !parameters.isEmpty {
        return parameters
    }
    let names = runtimeBuiltinTypeParameterNames[qualifiedName] ?? []
    let count = max(metadata?.typeParameterCount ?? 0, names.count)
    return (0..<count).map { index in
        let name = names.indices.contains(index) ? names[index] : "T\(index)"
        let identity = Int(truncatingIfNeeded: runtimeStableNominalTypeID(
            fqName: "\(qualifiedName).<type-parameter-\(index)>"
        ))
        return RuntimeKTypeParameterMetadata(identity: identity, name: name, varianceOrdinal: 0)
    }
}

func runtimeKClassTypeParameterHandles(
    qualifiedName: String,
    metadata: RuntimeKClassMetadataEntry?
) -> [Int] {
    runtimeKClassTypeParameterMetadata(qualifiedName: qualifiedName, metadata: metadata)
        .map { parameter in
            let identity = parameter.identity == 0
                ? Int(truncatingIfNeeded: runtimeStableNominalTypeID(
                    fqName: "\(qualifiedName).<type-parameter-\(parameter.name)>"
                ))
                : parameter.identity
            return runtimeKTypeParameterHandle(
                identity: identity,
                name: parameter.name,
                varianceOrdinal: parameter.varianceOrdinal
            )
        }
}

/// Resolves a qualified type name to its runtime type token, mirroring the
/// builtin-base table in `__kk_type_token_qualified_name` and falling back to
/// a nominal token whose payload is the FNV name hash used by
/// `RuntimeTypeCheckToken.stableNominalTypeID`.
func runtimeTypeToken(forQualifiedName name: String) -> Int64 {
    switch name {
    case "kotlin.Any": return RuntimeTypeTokenEncoding.anyBase
    case "kotlin.String": return RuntimeTypeTokenEncoding.stringBase
    case "kotlin.Int": return RuntimeTypeTokenEncoding.intBase
    case "kotlin.Boolean": return RuntimeTypeTokenEncoding.booleanBase
    case "kotlin.UInt": return RuntimeTypeTokenEncoding.uintBase
    case "kotlin.ULong": return RuntimeTypeTokenEncoding.ulongBase
    case "kotlin.UByte": return RuntimeTypeTokenEncoding.ubyteBase
    case "kotlin.UShort": return RuntimeTypeTokenEncoding.ushortBase
    case "kotlin.Byte": return RuntimeTypeTokenEncoding.byteBase
    case "kotlin.Short": return RuntimeTypeTokenEncoding.shortBase
    case "kotlin.Long": return RuntimeTypeTokenEncoding.longBase
    case "kotlin.Double": return RuntimeTypeTokenEncoding.doubleBase
    case "kotlin.Float": return RuntimeTypeTokenEncoding.floatBase
    case "kotlin.Char": return RuntimeTypeTokenEncoding.charBase
    case "kotlin.Nothing": return RuntimeTypeTokenEncoding.nullBase
    case "kotlin.Unit": return RuntimeTypeTokenEncoding.unitBase
    default:
        // KUU-3811: a `kotlin.FunctionN` classifier in a supertype display
        // name is the same runtime classifier as the `FunctionN::class`
        // literal — resolve it to the function-base token so
        // `KType.classifier == FunctionN::class` holds and the KType renders
        // in function-type notation like kotlinc. `kotlin.Function` itself
        // and non-canonical spellings (e.g. `Function03`) stay nominal.
        if name.hasPrefix("kotlin.Function") {
            let arityText = String(name.dropFirst("kotlin.Function".count))
            if let arity = Int(arityText), String(arity) == arityText, (0 ... 255).contains(arity) {
                return RuntimeTypeTokenEncoding.functionBase
                    | (Int64(arity) << RuntimeTypeTokenEncoding.payloadShift)
            }
        }
        if name.hasPrefix("kotlin.coroutines.SuspendFunction") {
            let arityText = String(name.dropFirst("kotlin.coroutines.SuspendFunction".count))
            if let arity = Int(arityText), String(arity) == arityText, (0 ... 255).contains(arity) {
                return RuntimeTypeTokenEncoding.functionBase
                    | ((Int64(arity) | 0x100) << RuntimeTypeTokenEncoding.payloadShift)
            }
        }
        return RuntimeTypeTokenEncoding.nominalBase
            | ((runtimeStableNominalTypeID(fqName: name) & RuntimeTypeTokenEncoding.payloadMask)
                << RuntimeTypeTokenEncoding.payloadShift)
    }
}

private func runtimeReflectionStringRaw(_ string: String) -> Int {
    let utf8 = Array(string.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
}

private func runtimeSplitTypeDisplayName(_ display: String) -> (base: String, args: [String])? {
    var trimmed = display.trimmingCharacters(in: .whitespaces)
    if trimmed.hasSuffix("?") {
        trimmed = String(trimmed.dropLast())
    }
    guard let openIndex = trimmed.firstIndex(of: "<") else {
        return trimmed.isEmpty ? nil : (trimmed, [])
    }
    let base = String(trimmed[..<openIndex]).trimmingCharacters(in: .whitespaces)
    guard !base.isEmpty else { return nil }
    let argsStart = trimmed.index(after: openIndex)
    var depth = 0
    var endIndex: String.Index?
    var cursor = openIndex
    while cursor < trimmed.endIndex {
        let ch = trimmed[cursor]
        if ch == "<" { depth += 1 }
        if ch == ">" {
            depth -= 1
            if depth == 0 {
                endIndex = cursor
                break
            }
        }
        cursor = trimmed.index(after: cursor)
    }
    guard let endIndex else { return nil }
    let inner = trimmed[argsStart..<endIndex]
    var args: [String] = []
    var argDepth = 0
    var argStart = inner.startIndex
    var index = inner.startIndex
    while index < inner.endIndex {
        let ch = inner[index]
        if ch == "<" { argDepth += 1 }
        if ch == ">" { argDepth -= 1 }
        if ch == ",", argDepth == 0 {
            args.append(String(inner[argStart..<index]).trimmingCharacters(in: .whitespaces))
            argStart = inner.index(after: index)
        }
        index = inner.index(after: index)
    }
    let last = String(inner[argStart..<inner.endIndex]).trimmingCharacters(in: .whitespaces)
    if !last.isEmpty {
        args.append(last)
    }
    return (base, args)
}

/// Type-parameter display names like `E` produce a
/// nominal classifier placeholder — there is no KTypeParameter box yet.
private func runtimeKTypeForSupertypeDisplayName(
    _ display: String,
    typeParameterClassifiers: [String: Int]
) -> Int {
    guard let (base, argDisplays) = runtimeSplitTypeDisplayName(display) else {
        return 0
    }
    if argDisplays.isEmpty, let typeParameterRaw = typeParameterClassifiers[base] {
        return registerRuntimeObject(RuntimeKTypeBox(
            classifierRaw: typeParameterRaw,
            argumentRaws: [],
            isMarkedNullable: display.trimmingCharacters(in: .whitespaces).hasSuffix("?")
        ))
    }
    let baseRaw = runtimeReflectionStringRaw(base)
    let token = runtimeTypeToken(forQualifiedName: base)
    let classifierRaw = __kk_kclass_create(Int(token), baseRaw)
    var argumentRaws: [Int] = []
    for argDisplay in argDisplays {
        let argRaw = runtimeKTypeForSupertypeDisplayName(
            argDisplay,
            typeParameterClassifiers: typeParameterClassifiers
        )
        let projection = RuntimeKTypeProjectionBox(typeRaw: argRaw, variance: .invariant)
        argumentRaws.append(registerRuntimeObject(projection))
    }
    // KUU-3811: a function classifier keeps no stored display name so the
    // KType renders in function-type notation `(P…) -> R` and compares equal
    // to `typeOf<(P…) -> R>` like kotlinc instead of printing the flat
    // `kotlin.FunctionN<…>` nominal spelling.
    let typeNameRaw = (token & RuntimeTypeTokenEncoding.baseMask)
        == RuntimeTypeTokenEncoding.functionBase ? 0 : baseRaw
    let box = RuntimeKTypeBox(
        classifierRaw: classifierRaw,
        argumentRaws: argumentRaws,
        isMarkedNullable: false,
        typeNameRaw: typeNameRaw
    )
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(box)
}

@_cdecl("__kk_kclass_supertypes")
public func __kk_kclass_supertypes(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let qualifiedName = box.metadata?.qualifiedName ?? {
        let raw = __kk_type_token_qualified_name(box.typeToken, box.nameHint)
        return extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }()
    let displays = runtimeBuiltinSupertypes[qualifiedName]
        ?? box.metadata?.supertypeDisplayNames
        ?? []
    let parameters = runtimeKClassTypeParameterMetadata(
        qualifiedName: qualifiedName,
        metadata: box.metadata
    )
    let parameterHandles = runtimeKClassTypeParameterHandles(
        qualifiedName: qualifiedName,
        metadata: box.metadata
    )
    let parameterClassifiers = Dictionary(
        zip(parameters.map(\.name), parameterHandles),
        uniquingKeysWith: { first, _ in first }
    )
    let elements = displays.compactMap { display -> Int? in
        let raw = runtimeKTypeForSupertypeDisplayName(
            display,
            typeParameterClassifiers: parameterClassifiers
        )
        return raw == 0 ? nil : raw
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}
