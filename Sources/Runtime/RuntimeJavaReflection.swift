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
        return runtimeMakeStringRaw(metadata.simpleName)
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
        return extractString(from: UnsafeMutableRawPointer(bitPattern: qualifiedNameRaw)) ?? "java.lang.Object"
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
