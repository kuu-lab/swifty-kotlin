import Foundation

struct RuntimeJavaMethodMetadata: Hashable {
    let name: String
    let signature: String
    let parameterTypeTokens: [Int]
    let returnTypeToken: Int
    let returnTypeName: String
    let flags: Int

    var isSynthetic: Bool { flags & 1 != 0 }

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

final class RuntimeJavaMethodBox {
    let metadata: RuntimeJavaMethodMetadata

    init(metadata: RuntimeJavaMethodMetadata) {
        self.metadata = metadata
    }
}

let runtimeJavaMethodRegistry = RuntimeJavaMethodRegistry()

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

    let methods = runtimeJavaMethodRegistry.methods(for: javaClass.typeToken)
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

@_cdecl("__kk_java_class_get_name")
public func __kk_java_class_get_name(_ classRaw: Int) -> Int {
    guard let javaClass = resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self) else {
        runtimeStructuredPanic("invalid Java Class handle")
    }
    return runtimeMakeStringRaw(runtimeJavaClassName(javaClass))
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
