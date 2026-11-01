import Foundation

struct RuntimeJavaMethodMetadata: Hashable {
    let name: String
    let signature: String
    let parameterTypeTokens: [Int]
    let returnTypeToken: Int
    let returnTypeName: String
    let flags: Int

    var isSynthetic: Bool { flags & 1 != 0 }
    var isPublic: Bool { flags & 2 != 0 }

    init?(name: String, signature: String, flags: Int) {
        let parts = signature.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              let returnTypeToken = Int(parts[1])
        else { return nil }

        let parameterTypeTokens: [Int]
        if parts[0].isEmpty {
            parameterTypeTokens = []
        } else {
            var parsedTokens: [Int] = []
            for token in parts[0].split(separator: ",") {
                guard let token = Int(token) else { return nil }
                parsedTokens.append(token)
            }
            parameterTypeTokens = parsedTokens
        }

        self.name = name
        self.signature = signature
        self.parameterTypeTokens = parameterTypeTokens
        self.returnTypeToken = returnTypeToken
        self.returnTypeName = String(parts[2])
        self.flags = flags
    }
}

final class RuntimeJavaMethodRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var methodsByTypeToken: [Int: [RuntimeJavaMethodMetadata]] = [:]

    func register(typeToken: Int, method: RuntimeJavaMethodMetadata) {
        guard typeToken != 0, !method.name.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var methods = methodsByTypeToken[typeToken, default: []]
        guard !methods.contains(method) else { return }
        methods.append(method)
        methodsByTypeToken[typeToken] = methods
    }

    func methods(for typeToken: Int) -> [RuntimeJavaMethodMetadata] {
        lock.lock()
        defer { lock.unlock() }
        return methodsByTypeToken[typeToken] ?? []
    }

    func method(for typeToken: Int, name: String, parameterTypeTokens: [Int]) -> RuntimeJavaMethodMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return methodsByTypeToken[typeToken]?.first {
            $0.name == name && $0.parameterTypeTokens == parameterTypeTokens
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        methodsByTypeToken.removeAll()
    }
}

struct RuntimeJavaFieldMetadata {
    let annotations: [RuntimeAnnotationRecord]
}

final class RuntimeJavaFieldRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var fieldsByTypeToken: [Int: [String: [RuntimeAnnotationRecord]]] = [:]

    func registerField(typeToken: Int, name: String) {
        guard typeToken != 0, !name.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var fields = fieldsByTypeToken[typeToken, default: [:]]
        if fields[name] == nil { fields[name] = [] }
        fieldsByTypeToken[typeToken] = fields
    }

    func registerAnnotation(typeToken: Int, name: String, annotation: RuntimeAnnotationRecord) {
        guard typeToken != 0, !name.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var fields = fieldsByTypeToken[typeToken, default: [:]]
        var annotations = fields[name, default: []]
        runtimeAppendAnnotationRecord(annotation, to: &annotations)
        fields[name] = annotations
        fieldsByTypeToken[typeToken] = fields
    }

    func field(for typeToken: Int, name: String) -> RuntimeJavaFieldMetadata? {
        lock.lock()
        defer { lock.unlock() }
        guard let annotations = fieldsByTypeToken[typeToken]?[name] else { return nil }
        return RuntimeJavaFieldMetadata(annotations: annotations)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        fieldsByTypeToken.removeAll()
    }
}

final class RuntimeJavaFieldBox {
    let metadata: RuntimeJavaFieldMetadata

    init(metadata: RuntimeJavaFieldMetadata) {
        self.metadata = metadata
    }
}

final class RuntimeJavaMethodBox {
    let metadata: RuntimeJavaMethodMetadata

    init(metadata: RuntimeJavaMethodMetadata) {
        self.metadata = metadata
    }
}

let runtimeJavaMethodRegistry = RuntimeJavaMethodRegistry()
let runtimeJavaFieldRegistry = RuntimeJavaFieldRegistry()

@_cdecl("__kk_java_class_register_declared_method")
public func __kk_java_class_register_declared_method(
    _ typeToken: Int,
    _ methodNameRaw: Int,
    _ signatureRaw: Int,
    _ flags: Int
) -> Int {
    let name = extractString(from: UnsafeMutableRawPointer(bitPattern: methodNameRaw)) ?? ""
    let signature = extractString(from: UnsafeMutableRawPointer(bitPattern: signatureRaw)) ?? ""
    guard let metadata = RuntimeJavaMethodMetadata(name: name, signature: signature, flags: flags) else {
        runtimeStructuredPanic("invalid Java Method metadata descriptor")
    }
    runtimeJavaMethodRegistry.register(typeToken: typeToken, method: metadata)
    return 0
}

@_cdecl("__kk_java_class_get_declared_methods")
public func __kk_java_class_get_declared_methods(_ classRaw: Int) -> Int {
    guard let javaClass = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }

    return runtimeJavaMethodArray(runtimeJavaMethodRegistry.methods(for: javaClass.typeToken))
}

@_cdecl("__kk_java_class_get_methods")
public func __kk_java_class_get_methods(_ classRaw: Int) -> Int {
    guard let javaClass = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    return runtimeJavaMethodArray(runtimeJavaPublicMethods(typeToken: javaClass.typeToken))
}

private func runtimeJavaPublicMethods(typeToken: Int) -> [RuntimeJavaMethodMetadata] {
    var visitedTypes: Set<Int> = []
    var visitedSignatures: Set<String> = []
    var methods: [RuntimeJavaMethodMetadata] = []

    func visit(_ currentTypeToken: Int) {
        guard visitedTypes.insert(currentTypeToken).inserted else { return }

        for method in runtimeJavaMethodRegistry.methods(for: currentTypeToken) where method.isPublic {
            let key = "\(method.name)(\(method.parameterTypeTokens.map(String.init).joined(separator: ",")))"
            if visitedSignatures.insert(key).inserted {
                methods.append(method)
            }
        }

        guard let metadata = runtimeKClassMetadataRegistry.lookup(typeToken: currentTypeToken) else { return }
        for displayName in metadata.supertypeDisplayNames {
            let name = String(displayName.prefix { $0 != "<" })
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            visit(Int(truncatingIfNeeded: runtimeTypeToken(forQualifiedName: name)))
        }
    }

    visit(typeToken)
    return methods
}

private func runtimeJavaMethodArray(_ methods: [RuntimeJavaMethodMetadata]) -> Int {
    let array = RuntimeArrayBox(length: methods.count)
    let arrayRaw = registerRuntimeObject(array)
    let methodTypeID = runtimeStableNominalTypeID(fqName: "java.lang.reflect.Method")
    let methodTypeToken = Int(
        ((methodTypeID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift)
            | RuntimeTypeTokenEncoding.nominalBase
    )
    array.installComponentTypeIfAbsent(__kk_array_component_type(methodTypeToken, 0))
    runtimeRegisterArrayType(rawValue: arrayRaw, typeID: runtimeStableNominalTypeID(fqName: "kotlin.Array"))

    for (index, metadata) in methods.enumerated() {
        array[index] = registerRuntimeObject(
            RuntimeJavaMethodBox(metadata: metadata),
            typeID: methodTypeID
        )
    }
    return arrayRaw
}

@_cdecl("__kk_java_class_get_declared_method")
public func __kk_java_class_get_declared_method(_ classRaw: Int, _ nameRaw: Int, _ parameterTypesRaw: Int) -> Int {
    guard let javaClass = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    let name = extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw)) ?? ""
    guard let parameterTypes = runtimeArrayBox(from: parameterTypesRaw) else {
        runtimeStructuredPanic("invalid Java Class parameter array")
    }

    var parameterTypeTokens: [Int] = []
    parameterTypeTokens.reserveCapacity(parameterTypes.count)
    for index in 0..<parameterTypes.count {
        guard let parameterType = resolveRuntimeHandle(parameterTypes[index], as: RuntimeJavaClassBox.self) else {
            runtimeStructuredPanic("invalid Java Class parameter handle")
        }
        parameterTypeTokens.append(parameterType.typeToken)
    }

    guard let metadata = runtimeJavaMethodRegistry.method(
        for: javaClass.typeToken,
        name: name,
        parameterTypeTokens: parameterTypeTokens
    ) else {
        runtimeStructuredPanic("java.lang.NoSuchMethodException: \(name)")
    }

    let methodTypeID = runtimeStableNominalTypeID(fqName: "java.lang.reflect.Method")
    return registerRuntimeObject(RuntimeJavaMethodBox(metadata: metadata), typeID: methodTypeID)
}

@_cdecl("__kk_java_class_register_declared_field")
public func __kk_java_class_register_declared_field(_ typeToken: Int, _ fieldNameRaw: Int) -> Int {
    let name = extractString(from: UnsafeMutableRawPointer(bitPattern: fieldNameRaw)) ?? ""
    runtimeJavaFieldRegistry.registerField(typeToken: typeToken, name: name)
    return 0
}

@_cdecl("__kk_java_field_register_single_annotation")
public func __kk_java_field_register_single_annotation(
    _ typeToken: Int,
    _ fieldNameRaw: Int,
    _ fqNameRaw: Int,
    _ argsEncodedRaw: Int,
    _ argCount: Int
) -> Int {
    let fieldName = extractString(from: UnsafeMutableRawPointer(bitPattern: fieldNameRaw)) ?? ""
    let fqName = extractString(from: UnsafeMutableRawPointer(bitPattern: fqNameRaw)) ?? "Unknown"
    let encoded = extractString(from: UnsafeMutableRawPointer(bitPattern: argsEncodedRaw)) ?? ""
    let arguments = argCount > 0 && !encoded.isEmpty ? encoded.components(separatedBy: "|") : []
    runtimeJavaFieldRegistry.registerAnnotation(
        typeToken: typeToken,
        name: fieldName,
        annotation: RuntimeAnnotationRecord(annotationFQName: fqName, arguments: arguments)
    )
    return 0
}

@_cdecl("__kk_java_field_register_annotation_factory")
public func __kk_java_field_register_annotation_factory(
    _ typeToken: Int,
    _ fieldNameRaw: Int,
    _ fqNameRaw: Int,
    _ argsEncodedRaw: Int,
    _ argCount: Int,
    _ factory: Int
) -> Int {
    let fieldName = extractString(from: UnsafeMutableRawPointer(bitPattern: fieldNameRaw)) ?? ""
    let fqName = extractString(from: UnsafeMutableRawPointer(bitPattern: fqNameRaw)) ?? "Unknown"
    let encoded = extractString(from: UnsafeMutableRawPointer(bitPattern: argsEncodedRaw)) ?? ""
    let arguments = argCount > 0 && !encoded.isEmpty ? encoded.components(separatedBy: "|") : []
    runtimeJavaFieldRegistry.registerAnnotation(
        typeToken: typeToken,
        name: fieldName,
        annotation: RuntimeAnnotationRecord(annotationFQName: fqName, arguments: arguments, factory: factory)
    )
    return 0
}

@_cdecl("__kk_java_class_get_declared_field")
public func __kk_java_class_get_declared_field(_ classRaw: Int, _ nameRaw: Int) -> Int {
    guard let javaClass = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    let name = extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw)) ?? ""
    guard let metadata = runtimeJavaFieldRegistry.field(for: javaClass.typeToken, name: name) else {
        runtimeStructuredPanic("java.lang.NoSuchFieldException: \(name)")
    }
    return registerRuntimeObject(
        RuntimeJavaFieldBox(metadata: metadata),
        typeID: runtimeStableNominalTypeID(fqName: "java.lang.reflect.Field")
    )
}

@_cdecl("__kk_java_field_get_annotations_typed")
public func __kk_java_field_get_annotations_typed(
    _ fieldRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let field = resolveRuntimeHandle(fieldRaw, as: RuntimeJavaFieldBox.self) else {
        runtimeStructuredPanic("invalid Java Field handle")
    }
    return runtimeAnnotationArray(field.metadata.annotations, outThrown: outThrown)
}

private func runtimeJavaClassAnnotations(typeToken: Int) -> [RuntimeAnnotationRecord] {
    guard let metadata = runtimeKClassMetadataRegistry.lookup(typeToken: typeToken) else { return [] }

    var annotations = metadata.annotations
    var presentAnnotationNames = Set(annotations.map(\.annotationFQName))
    var visitedClassNames: Set<String> = [metadata.qualifiedName]
    var current = metadata

    while let superclass = runtimeJavaSuperclassMetadata(of: current),
          visitedClassNames.insert(superclass.qualifiedName).inserted
    {
        for annotation in superclass.annotations
        where !presentAnnotationNames.contains(annotation.annotationFQName)
            && runtimeJavaAnnotationIsInherited(annotation.annotationFQName)
        {
            annotations.append(annotation)
            presentAnnotationNames.insert(annotation.annotationFQName)
        }
        current = superclass
    }

    return annotations
}


private func runtimeJavaSuperclassMetadata(of metadata: RuntimeKClassMetadataEntry) -> RuntimeKClassMetadataEntry? {
    for displayName in metadata.supertypeDisplayNames {
        let name = String(displayName.prefix { $0 != "<" }).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let candidate = runtimeKClassMetadataRegistry.lookup(qualifiedName: name),
              !candidate.isInterface
        else {
            continue
        }
        return candidate
    }
    return nil
}

private func runtimeJavaAnnotationIsInherited(_ annotationName: String) -> Bool {
    runtimeKClassMetadataRegistry.isJavaInheritedAnnotation(name: annotationName)
}

@_cdecl("__kk_java_class_register_inherited_annotation")
public func __kk_java_class_register_inherited_annotation(_ annotationNameRaw: Int) -> Int {
    let annotationName = extractString(from: UnsafeMutableRawPointer(bitPattern: annotationNameRaw)) ?? ""
    runtimeKClassMetadataRegistry.registerJavaInheritedAnnotation(name: annotationName)
    return 0
}

@_cdecl("__kk_java_class_get_annotations_typed")
public func __kk_java_class_get_annotations_typed(
    _ classRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let javaClass = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    return runtimeAnnotationArray(runtimeJavaClassAnnotations(typeToken: javaClass.typeToken), outThrown: outThrown)
}

@_cdecl("__kk_java_class_get_name")
public func __kk_java_class_get_name(_ classRaw: Int) -> Int {
    guard let javaClass = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    return runtimeMakeStringRaw(runtimeJavaClassName(javaClass))
}

@_cdecl("__kk_class_simple_name")
public func __kk_class_simple_name(_ classRaw: Int) -> Int {
    guard let javaClass = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }

    if let metadata = runtimeKClassMetadataRegistry.lookup(typeToken: javaClass.typeToken), metadata.isLocal {
        // JVM Class.getSimpleName() returns "" for anonymous classes (KUU-3828).
        return runtimeMakeStringRaw(metadata.isAnonymous ? "" : metadata.simpleName)
    }

    let displayText = javaClass.displayText
    let className: String
    if displayText.hasPrefix("class ") {
        className = String(displayText.dropFirst("class ".count))
    } else if displayText.hasPrefix("interface ") {
        className = String(displayText.dropFirst("interface ".count))
    } else {
        className = javaClass.javaNameOverride ?? runtimeJavaClassName(javaClass)
    }

    if let arraySimpleName = runtimeJavaArraySimpleName(className) {
        return runtimeMakeStringRaw(arraySimpleName)
    }
    return runtimeMakeStringRaw(runtimeJavaSimpleClassName(className))
}

private func runtimeJavaSimpleClassName(_ className: String) -> String {
    className.split(whereSeparator: { $0 == "." || $0 == "$" }).last.map(String.init) ?? className
}

private func runtimeJavaArraySimpleName(_ descriptor: String) -> String? {
    var component = descriptor[...]
    var dimensions = 0
    while component.first == "[" {
        dimensions += 1
        component = component.dropFirst()
    }
    guard dimensions > 0, let componentCode = component.first else { return nil }

    let componentName: String
    switch componentCode {
    case "Z": componentName = "boolean"
    case "B": componentName = "byte"
    case "C": componentName = "char"
    case "D": componentName = "double"
    case "F": componentName = "float"
    case "I": componentName = "int"
    case "J": componentName = "long"
    case "S": componentName = "short"
    case "L":
        guard component.last == ";" else { return nil }
        let binaryName = String(component.dropFirst().dropLast())
        componentName = runtimeJavaSimpleClassName(binaryName)
    default:
        return nil
    }
    return componentName + String(repeating: "[]", count: dimensions)
}

private func runtimeJavaClassName(_ javaClass: RuntimeJavaClassBox) -> String {
    if let override = javaClass.javaNameOverride { return override }
    let base = Int64(javaClass.typeToken) & RuntimeTypeTokenEncoding.baseMask
    switch base {
    case RuntimeTypeTokenEncoding.anyBase: return "java.lang.Object"
    case RuntimeTypeTokenEncoding.stringBase: return "java.lang.String"
    case RuntimeTypeTokenEncoding.booleanBase: return "boolean"
    case RuntimeTypeTokenEncoding.charBase: return "char"
    case RuntimeTypeTokenEncoding.intBase: return "int"
    case RuntimeTypeTokenEncoding.longBase: return "long"
    case RuntimeTypeTokenEncoding.floatBase: return "float"
    case RuntimeTypeTokenEncoding.doubleBase: return "double"
    case RuntimeTypeTokenEncoding.byteBase: return "byte"
    case RuntimeTypeTokenEncoding.shortBase: return "short"
    case RuntimeTypeTokenEncoding.nullBase: return "java.lang.Void"
    default:
        let qualifiedNameRaw = __kk_type_token_qualified_name(javaClass.typeToken, javaClass.nameHint)
        let qualifiedName = extractString(from: UnsafeMutableRawPointer(bitPattern: qualifiedNameRaw))
            ?? "java.lang.Object"
        // KUU-4067: `Class.getName()` reports the JVM binary name — kotlin
        // standard classes mapped to java.lang/java.util types (Throwable,
        // Comparable, List, …) print their Java spelling here just like in
        // `displayText`, while the KClass reflection APIs keep kotlin names.
        return runtimeJavaBinaryName(qualifiedName, metadataDisplayName: nil)
    }
}

@_cdecl("__kk_java_method_get_name")
public func __kk_java_method_get_name(_ methodRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(methodRaw, as: RuntimeJavaMethodBox.self) else {
        runtimeStructuredPanic("invalid Java Method handle")
    }
    return runtimeMakeStringRaw(box.metadata.name)
}

@_cdecl("__kk_java_method_get_return_type")
public func __kk_java_method_get_return_type(_ methodRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(methodRaw, as: RuntimeJavaMethodBox.self) else {
        runtimeStructuredPanic("invalid Java Method handle")
    }
    return registerRuntimeObject(
        RuntimeJavaClassBox(
            typeToken: box.metadata.returnTypeToken,
            javaNameOverride: box.metadata.returnTypeName
        ),
        typeID: runtimeStableNominalTypeID(fqName: "java.lang.Class")
    )
}

@_cdecl("__kk_java_method_is_synthetic")
public func __kk_java_method_is_synthetic(_ methodRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(methodRaw, as: RuntimeJavaMethodBox.self) else {
        runtimeStructuredPanic("invalid Java Method handle")
    }
    return box.metadata.isSynthetic ? 1 : 0
}

// MARK: - Class supertype graph (KUU-4067)

/// Bundled builtin interfaces that typically carry no registered KClass
/// metadata — the compiler emits metadata only for nominal class literals it
/// visits, while `java.lang.Class.interfaces`/`superclass` must classify
/// supertypes the JVM way anyway. Mirrors the interface-shaped entries in
/// `runtimeBuiltinSupertypes` plus the JVM-only markers that show up in them.
let runtimeJavaInterfaceNominalNames: Set<String> = [
    "kotlin.Annotation",
    "kotlin.CharSequence",
    "kotlin.Cloneable",
    "kotlin.Comparable",
    "kotlin.Function",
    "kotlin.sequences.Sequence",
    "kotlin.ranges.ClosedRange",
    "kotlin.ranges.OpenEndRange",
    "kotlin.collections.Iterable",
    "kotlin.collections.Collection",
    "kotlin.collections.MutableCollection",
    "kotlin.collections.List",
    "kotlin.collections.MutableList",
    "kotlin.collections.Set",
    "kotlin.collections.MutableSet",
    "kotlin.collections.Map",
    "kotlin.collections.MutableMap",
    "kotlin.collections.Map.Entry",
    "kotlin.collections.MutableMap.MutableEntry",
    "kotlin.collections.Iterator",
    "kotlin.collections.MutableIterator",
    "kotlin.collections.ListIterator",
    "kotlin.collections.MutableListIterator",
    "kotlin.reflect.KAnnotatedElement",
    "kotlin.reflect.KClassifier",
    "kotlin.reflect.KDeclarationContainer",
    "kotlin.reflect.KClass",
    "java.io.Serializable",
    "java.lang.Cloneable",
    "java.lang.Iterable",
    "java.lang.annotation.Annotation",
]

/// Element primitive token bases for `Class.componentType`/`isArray` on the
/// eight signed primitive array classes keyed by nominal type ID. The four
/// unsigned array classes are value-class wrappers over the signed storage on
/// the JVM — `UIntArray::class.java.isArray` is false — so they are absent.
private let runtimeJavaPrimitiveArrayElementBase: [Int64: Int64] = {
    func nominalID(_ name: String) -> Int64 {
        runtimeStableNominalTypeID(fqName: "kotlin.\(name)")
    }
    return [
        nominalID("BooleanArray"): RuntimeTypeTokenEncoding.booleanBase,
        nominalID("ByteArray"): RuntimeTypeTokenEncoding.byteBase,
        nominalID("CharArray"): RuntimeTypeTokenEncoding.charBase,
        nominalID("DoubleArray"): RuntimeTypeTokenEncoding.doubleBase,
        nominalID("FloatArray"): RuntimeTypeTokenEncoding.floatBase,
        nominalID("IntArray"): RuntimeTypeTokenEncoding.intBase,
        nominalID("LongArray"): RuntimeTypeTokenEncoding.longBase,
        nominalID("ShortArray"): RuntimeTypeTokenEncoding.shortBase,
    ]
}()

/// java.lang wrapper binary names mapped back to their primitive token base
/// when a `Class` component descriptor ("[Ljava.lang.Integer;") resolves to a
/// `javaObjectType` handle.
private let runtimeJavaWrapperPrimitiveBase: [String: Int64] = [
    "java.lang.Boolean": RuntimeTypeTokenEncoding.booleanBase,
    "java.lang.Byte": RuntimeTypeTokenEncoding.byteBase,
    "java.lang.Short": RuntimeTypeTokenEncoding.shortBase,
    "java.lang.Integer": RuntimeTypeTokenEncoding.intBase,
    "java.lang.Long": RuntimeTypeTokenEncoding.longBase,
    "java.lang.Character": RuntimeTypeTokenEncoding.charBase,
    "java.lang.Float": RuntimeTypeTokenEncoding.floatBase,
    "java.lang.Double": RuntimeTypeTokenEncoding.doubleBase,
    "java.lang.Void": RuntimeTypeTokenEncoding.nullBase,
]

private func runtimeJavaNominalTypeID(_ typeToken: Int) -> Int64? {
    let token = Int64(truncatingIfNeeded: typeToken) & ~RuntimeTypeTokenEncoding.nullableBit
    guard token & RuntimeTypeTokenEncoding.baseMask == RuntimeTypeTokenEncoding.nominalBase else {
        return nil
    }
    return (token >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask
}

/// The JVM array descriptor ("[I", "[Ljava.lang.String;") carried by
/// instance-backed array class handles, or nil for plain class tokens.
private func runtimeJavaClassArrayDescriptor(_ box: RuntimeJavaClassBox) -> String? {
    if box.displayText.hasPrefix("class [") {
        return String(box.displayText.dropFirst("class ".count))
    }
    if let override = box.javaNameOverride, override.hasPrefix("[") { return override }
    if let className = box.className, className.hasPrefix("[") { return className }
    return nil
}

private func runtimeJavaClassIsArray(_ box: RuntimeJavaClassBox) -> Bool {
    if runtimeJavaClassArrayDescriptor(box) != nil { return true }
    guard let nominalID = runtimeJavaNominalTypeID(box.typeToken) else { return false }
    if nominalID == runtimeStableNominalTypeID(fqName: "kotlin.Array") { return true }
    return runtimeJavaPrimitiveArrayElementBase[nominalID] != nil
}

/// JVM `isPrimitive()`: the `javaPrimitiveType` handles render the primitive
/// keyword ("int") directly; `T::class.java` handles share the same primitive
/// token (JVM `Int::class.java` *is* `int.class`) unless they are explicit
/// `javaObjectType` wrapper boxes, which carry a java.lang name override.
private func runtimeJavaClassModelsPrimitive(_ box: RuntimeJavaClassBox) -> Bool {
    if box.displayText == runtimeJavaPrimitiveClassDisplayText(typeToken: box.typeToken) {
        return true
    }
    guard box.javaNameOverride == nil, box.className == nil else { return false }
    // The `nullBase` token is *not* primitive here: `Nothing::class.java` is
    // `java.lang.Void` — a real final class — while only `javaPrimitiveType`
    // produces the primitive `void` token (matched by displayText above).
    switch Int64(truncatingIfNeeded: box.typeToken) & RuntimeTypeTokenEncoding.baseMask {
    case RuntimeTypeTokenEncoding.booleanBase, RuntimeTypeTokenEncoding.byteBase,
         RuntimeTypeTokenEncoding.shortBase, RuntimeTypeTokenEncoding.intBase,
         RuntimeTypeTokenEncoding.longBase, RuntimeTypeTokenEncoding.charBase,
         RuntimeTypeTokenEncoding.floatBase, RuntimeTypeTokenEncoding.doubleBase:
        return true
    default:
        return false
    }
}

private func runtimeJavaClassIsInterfaceKind(_ box: RuntimeJavaClassBox) -> Bool {
    if let metadata = runtimeKClassMetadataRegistry.lookup(typeToken: box.typeToken) {
        return metadata.isInterface
    }
    if box.displayText.hasPrefix("interface ") { return true }
    let qualifiedName = runtimeJavaQualifiedName(typeToken: box.typeToken, nameHint: box.nameHint)
    return runtimeJavaInterfaceNominalNames.contains(qualifiedName)
}

/// Strips generic arguments and the trailing `?` from a supertype display
/// name ("kotlin.Comparable<kotlin.Int>" → "kotlin.Comparable").
private func runtimeJavaSupertypeBaseName(_ display: String) -> String {
    var base = display.trimmingCharacters(in: .whitespaces)
    if base.hasSuffix("?") { base = String(base.dropLast()) }
    if let genericStart = base.firstIndex(of: "<") {
        base = String(base[..<genericStart]).trimmingCharacters(in: .whitespaces)
    }
    return base
}

/// Classifies a supertype display-name base as an interface. Registered
/// metadata wins; otherwise the curated builtin-interface table decides.
/// Unresolvable names default to *class* — nominal supertype metadata is
/// registered transitively at class-literal evaluation, so a lookup miss is
/// a JVM/builtin name (e.g. a synthesized alias) rather than a user class.
private func runtimeJavaSupertypeIsInterface(_ baseName: String) -> Bool {
    if let metadata = runtimeKClassMetadataRegistry.lookup(qualifiedName: baseName) {
        return metadata.isInterface
    }
    return runtimeJavaInterfaceNominalNames.contains(baseName)
}

private func runtimeJavaClassHandle(forSupertypeName baseName: String) -> Int {
    let token = runtimeTypeToken(forQualifiedName: baseName)
    return runtimeJavaClassHandle(
        typeToken: Int(truncatingIfNeeded: token),
        nameHint: runtimeMakeStringRaw(baseName)
    )
}

/// The direct-supertype display names for a class token: the curated builtin
/// table first (it already models the JVM shape), then registered metadata.
private func runtimeJavaDirectSupertypeNames(of box: RuntimeJavaClassBox) -> [String] {
    let qualifiedName = runtimeJavaQualifiedName(typeToken: box.typeToken, nameHint: box.nameHint)
    return runtimeBuiltinSupertypes[qualifiedName]
        ?? runtimeKClassMetadataRegistry.lookup(typeToken: box.typeToken)?.supertypeDisplayNames
        ?? []
}

private func runtimeJavaObjectClassHandle() -> Int {
    runtimeJavaClassHandle(typeToken: Int(RuntimeTypeTokenEncoding.anyBase), nameHint: 0)
}

@_cdecl("__kk_class_superclass")
public func __kk_class_superclass(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    // JVM: arrays extend Object; interfaces, primitives, void, and Object
    // itself have no superclass.
    if runtimeJavaClassIsArray(box) { return runtimeJavaObjectClassHandle() }
    if runtimeJavaClassModelsPrimitive(box) { return runtimeNullSentinelInt }
    if Int64(truncatingIfNeeded: box.typeToken) & RuntimeTypeTokenEncoding.baseMask
        == RuntimeTypeTokenEncoding.anyBase
    {
        return runtimeNullSentinelInt
    }
    if runtimeJavaClassIsInterfaceKind(box) { return runtimeNullSentinelInt }
    for display in runtimeJavaDirectSupertypeNames(of: box) {
        let baseName = runtimeJavaSupertypeBaseName(display)
        guard !baseName.isEmpty, !runtimeJavaSupertypeIsInterface(baseName) else { continue }
        return runtimeJavaClassHandle(forSupertypeName: baseName)
    }
    // JVM: every non-interface class without a resolvable superclass record
    // still extends java.lang.Object.
    return runtimeJavaObjectClassHandle()
}

@_cdecl("__kk_class_interfaces")
public func __kk_class_interfaces(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    var interfaceNames: [String] = []
    if runtimeJavaClassModelsPrimitive(box) {
        // JVM: primitive class tokens implement no interfaces.
    } else if runtimeJavaClassIsArray(box) {
        // JVM: every array class implements Cloneable and Serializable.
        interfaceNames = ["kotlin.Cloneable", "java.io.Serializable"]
    } else {
        for display in runtimeJavaDirectSupertypeNames(of: box) {
            let baseName = runtimeJavaSupertypeBaseName(display)
            guard !baseName.isEmpty,
                  runtimeJavaSupertypeIsInterface(baseName),
                  !interfaceNames.contains(baseName)
            else { continue }
            interfaceNames.append(baseName)
        }
    }
    let array = RuntimeArrayBox(length: interfaceNames.count)
    let arrayRaw = registerRuntimeObject(array)
    let classTypeID = runtimeStableNominalTypeID(fqName: "java.lang.Class")
    let classTypeToken = Int(
        ((classTypeID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift)
            | RuntimeTypeTokenEncoding.nominalBase
    )
    array.installComponentTypeIfAbsent(__kk_array_component_type(classTypeToken, 0))
    runtimeRegisterArrayType(rawValue: arrayRaw, typeID: runtimeStableNominalTypeID(fqName: "kotlin.Array"))
    for (index, name) in interfaceNames.enumerated() {
        array[index] = runtimeJavaClassHandle(forSupertypeName: name)
    }
    return arrayRaw
}

@_cdecl("__kk_class_is_array")
public func __kk_class_is_array(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    return runtimeJavaClassIsArray(box) ? 1 : 0
}

@_cdecl("__kk_class_is_primitive")
public func __kk_class_is_primitive(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    return runtimeJavaClassModelsPrimitive(box) ? 1 : 0
}

@_cdecl("__kk_class_is_enum")
public func __kk_class_is_enum(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    return runtimeKClassMetadataRegistry.lookup(typeToken: box.typeToken)?.isEnumClass == true ? 1 : 0
}

/// The array-class nominal token for a JVM descriptor's component shape:
/// "[I" → kotlin.IntArray, "[Ljava.lang.String;" → kotlin.Array.
private func runtimeJavaArrayClassToken(forDescriptor descriptor: String) -> Int {
    let component = descriptor.dropFirst()
    let arrayNominalName: String
    if component.hasPrefix("[") || component.hasPrefix("L") {
        arrayNominalName = "kotlin.Array"
    } else {
        switch component.first {
        case "Z": arrayNominalName = "kotlin.BooleanArray"
        case "B": arrayNominalName = "kotlin.ByteArray"
        case "C": arrayNominalName = "kotlin.CharArray"
        case "D": arrayNominalName = "kotlin.DoubleArray"
        case "F": arrayNominalName = "kotlin.FloatArray"
        case "I": arrayNominalName = "kotlin.IntArray"
        case "J": arrayNominalName = "kotlin.LongArray"
        case "S": arrayNominalName = "kotlin.ShortArray"
        default: arrayNominalName = "kotlin.Array"
        }
    }
    return runtimeNominalTypeToken(runtimeStableNominalTypeID(fqName: arrayNominalName))
}

/// A Class handle describing one level down from a JVM array descriptor:
/// "[I" → `int`, "[Ljava.lang.Integer;" → `java.lang.Integer`,
/// "[[I" → the `int[]` array class.
private func runtimeJavaComponentClassHandle(forDescriptor descriptor: String) -> Int {
    let component = String(descriptor.dropFirst())
    if component.hasPrefix("[") {
        let token = runtimeJavaArrayClassToken(forDescriptor: component)
        return runtimeJavaClassHandle(
            cacheKey: JavaClassCacheKey(typeToken: token, runtimeClassName: component),
            typeToken: token,
            nameHint: { 0 },
            javaNameOverride: component,
            displayText: { "class \(component)" }
        )
    }
    if component.hasPrefix("L"), component.hasSuffix(";") {
        let binaryName = String(component.dropFirst().dropLast())
        if let primitiveBase = runtimeJavaWrapperPrimitiveBase[binaryName] {
            return __kk_kclass_java_object_type(__kk_kclass_create(Int(primitiveBase), 0))
        }
        let kotlinName = runtimeKotlinClassName(forJavaClassName: binaryName)
        return runtimeJavaClassHandle(
            typeToken: Int(truncatingIfNeeded: runtimeTypeToken(forQualifiedName: kotlinName)),
            nameHint: runtimeMakeStringRaw(kotlinName)
        )
    }
    let primitiveBase: Int64
    switch component.first {
    case "Z": primitiveBase = RuntimeTypeTokenEncoding.booleanBase
    case "B": primitiveBase = RuntimeTypeTokenEncoding.byteBase
    case "C": primitiveBase = RuntimeTypeTokenEncoding.charBase
    case "D": primitiveBase = RuntimeTypeTokenEncoding.doubleBase
    case "F": primitiveBase = RuntimeTypeTokenEncoding.floatBase
    case "I": primitiveBase = RuntimeTypeTokenEncoding.intBase
    case "J": primitiveBase = RuntimeTypeTokenEncoding.longBase
    case "S": primitiveBase = RuntimeTypeTokenEncoding.shortBase
    default: return runtimeJavaObjectClassHandle()
    }
    return __kk_kclass_java_primitive_type(__kk_kclass_create(Int(primitiveBase), 0))
}

@_cdecl("__kk_class_component_type")
public func __kk_class_component_type(_ classRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    if let descriptor = runtimeJavaClassArrayDescriptor(box) {
        return runtimeJavaComponentClassHandle(forDescriptor: descriptor)
    }
    guard let nominalID = runtimeJavaNominalTypeID(box.typeToken) else {
        return runtimeNullSentinelInt
    }
    if let primitiveBase = runtimeJavaPrimitiveArrayElementBase[nominalID] {
        return __kk_kclass_java_primitive_type(__kk_kclass_create(Int(primitiveBase), 0))
    }
    if nominalID == runtimeStableNominalTypeID(fqName: "kotlin.Array") {
        // `Array<T>::class.java` erases the element type; the only recoverable
        // component classifier is the erased Object bound.
        return runtimeJavaObjectClassHandle()
    }
    return runtimeNullSentinelInt
}

final class RuntimeJavaConstructorBox: RuntimeChildReferenceProviding {
    let callableRaw: Int
    let usesDefaultArguments: Bool

    init(callableRaw: Int, usesDefaultArguments: Bool) {
        self.callableRaw = callableRaw
        self.usesDefaultArguments = usesDefaultArguments
    }

    var childRefs: [Int] { [callableRaw] }
}

private func runtimeJavaReflectionValues(from raw: Int) -> [Int]? {
    if let list = runtimeReflectionObject(from: raw, as: RuntimeListBox.self) {
        return list.elements
    }
    return runtimeArrayBox(from: raw)?.elements
}

private func runtimeJavaConstructorParameterRaws(_ constructorRaw: Int) -> [Int]? {
    runtimeJavaReflectionValues(from: __kk_kcallable_get_metadata(constructorRaw, 0))
}

private func runtimeJavaConstructorMatches(
    _ constructorRaw: Int,
    parameterTypes: [RuntimeJavaClassBox]
) -> Bool {
    guard let constructor = runtimeReflectionObject(from: constructorRaw, as: RuntimeKConstructorBox.self),
          constructor.arity == parameterTypes.count,
          constructor.jvmVisibilityOrdinal == 0,
          let parameterRaws = runtimeJavaConstructorParameterRaws(constructorRaw),
          parameterRaws.count == parameterTypes.count
    else {
        return false
    }
    return zip(parameterRaws, parameterTypes).allSatisfy { parameterRaw, parameterType in
        guard let parameter = runtimeReflectionObject(from: parameterRaw, as: RuntimeKParameterBox.self),
              let typeToken = parameter.typeToken
        else {
            return false
        }
        return typeToken == parameterType.typeToken
    }
}

private func runtimeJavaConstructorSupportsImplicitNoArgs(_ constructorRaw: Int) -> Bool {
    guard let constructor = runtimeReflectionObject(from: constructorRaw, as: RuntimeKConstructorBox.self),
          constructor.arity > 0,
          constructor.jvmVisibilityOrdinal == 0,
          let parameterRaws = runtimeJavaConstructorParameterRaws(constructorRaw),
          parameterRaws.count == constructor.arity
    else {
        return false
    }
    return parameterRaws.allSatisfy {
        runtimeReflectionObject(from: $0, as: RuntimeKParameterBox.self)?.isOptional == true
    }
}

@_cdecl("__kk_java_class_get_constructor")
public func __kk_java_class_get_constructor(
    _ classRaw: Int,
    _ parameterTypesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let javaClass = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self),
          let parameterTypeRaws = runtimeArrayBox(from: parameterTypesRaw)?.elements
    else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Invalid Java Class or parameter types.")
        return runtimeNullSentinelInt
    }

    var parameterTypes: [RuntimeJavaClassBox] = []
    parameterTypes.reserveCapacity(parameterTypeRaws.count)
    for raw in parameterTypeRaws {
        guard let parameterType = resolveRuntimeHandle(raw, as: RuntimeJavaClassBox.self) else {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Invalid Java constructor parameter type.")
            return runtimeNullSentinelInt
        }
        parameterTypes.append(parameterType)
    }

    let kclassRaw = __kk_kclass_create(javaClass.typeToken, javaClass.nameHint)
    let constructors = runtimeKConstructorRegistry.constructors(for: kclassRaw)
    let matchingConstructor = constructors.first {
        runtimeJavaConstructorMatches($0, parameterTypes: parameterTypes)
    }
    let defaultArgumentConstructor: Int?
    if parameterTypes.isEmpty {
        defaultArgumentConstructor = constructors.first(where: runtimeJavaConstructorSupportsImplicitNoArgs)
    } else {
        defaultArgumentConstructor = nil
    }
    guard let callableRaw = matchingConstructor ?? defaultArgumentConstructor else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "No matching public constructor.")
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(
        RuntimeJavaConstructorBox(
            callableRaw: callableRaw,
            usesDefaultArguments: matchingConstructor == nil
        ),
        typeID: runtimeStableNominalTypeID(fqName: "java.lang.reflect.Constructor")
    )
}

@_cdecl("__kk_java_constructor_new_instance")
public func __kk_java_constructor_new_instance(
    _ constructorRaw: Int,
    _ argumentsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let constructor = resolveRuntimeHandle(constructorRaw, as: RuntimeJavaConstructorBox.self),
          let arguments = runtimeArrayBox(from: argumentsRaw)?.elements
    else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Invalid Java Constructor or arguments.")
        return runtimeNullSentinelInt
    }

    if constructor.usesDefaultArguments {
        guard arguments.isEmpty else {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Implicit no-argument constructor received arguments.")
            return runtimeNullSentinelInt
        }
        let emptyArguments = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        return __kk_kcallable_call_by(constructor.callableRaw, emptyArguments, outThrown)
    }

    return __kk_kcallable_call(constructor.callableRaw, argumentsRaw, outThrown)
}
