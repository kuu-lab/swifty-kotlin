import Foundation

struct RuntimeJavaMethodMetadata: Hashable {
    let name: String
    let signature: String
    let flags: Int

    var isSynthetic: Bool { flags & 1 != 0 }
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
    runtimeJavaMethodRegistry.register(
        typeToken: typeToken,
        method: RuntimeJavaMethodMetadata(name: name, signature: signature, flags: flags)
    )
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

@_cdecl("__kk_java_method_get_name")
public func __kk_java_method_get_name(_ methodRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(methodRaw, as: RuntimeJavaMethodBox.self) else {
        runtimeStructuredPanic("invalid Java Method handle")
    }
    return runtimeMakeStringRaw(box.metadata.name)
}

@_cdecl("__kk_java_method_is_synthetic")
public func __kk_java_method_is_synthetic(_ methodRaw: Int) -> Int {
    guard let box = resolveRuntimeHandle(methodRaw, as: RuntimeJavaMethodBox.self) else {
        runtimeStructuredPanic("invalid Java Method handle")
    }
    return box.metadata.isSynthetic ? 1 : 0
}
