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
