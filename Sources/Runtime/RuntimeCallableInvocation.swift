import Foundation

final class RuntimePropertyAccessorContext {
    var metadata: RuntimeCallableRefMetadata

    init(metadata: RuntimeCallableRefMetadata) {
        self.metadata = metadata
    }
}

private func callableMetadata(_ raw: Int) -> RuntimeCallableRefMetadata? {
    runtimeStorage.withDelegateLock { $0.callableRefMetadataByValue[raw] }
        ?? runtimeReflectionObject(from: raw, as: RuntimePropertyAccessorContext.self)?.metadata
}

@_cdecl("__kk_kcallable_register")
public func __kk_kcallable_register(
    _ raw: Int, _ invoker: Int, _ environment: Int, _ parameters: Int,
    _ typeParameters: Int, _ flags: Int, _ visibility: Int,
    _ setterInvoker: Int, _ setterParameters: Int
) -> Int {
    let boundArguments = callableArguments(environment) ?? []
    for parameter in (callableArguments(parameters) ?? []) + (callableArguments(setterParameters) ?? []) {
        runtimeReflectionObject(from: parameter, as: RuntimeKParameterBox.self)?.boundArguments = boundArguments
    }
    runtimeStorage.withDelegateLock { state in
        guard var metadata = state.callableRefMetadataByValue[raw] else { return }
        metadata.invoker = invoker
        metadata.environment = environment
        metadata.parameters = parameters
        metadata.typeParameters = typeParameters
        metadata.flags = flags
        metadata.visibility = visibility
        metadata.setterInvoker = setterInvoker
        metadata.setterParameters = setterParameters
        state.callableRefMetadataByValue[raw] = metadata
    }
    return raw
}

@_cdecl("__kk_kcallable_is_runtime")
public func __kk_kcallable_is_runtime(_ raw: Int) -> Int {
    if callableMetadata(raw) != nil
        || runtimeReflectionObject(from: raw, as: RuntimeKFunctionBox.self) != nil
        || runtimeReflectionObject(from: raw, as: RuntimeKConstructorBox.self) != nil
        || runtimeReflectionObject(from: raw, as: RuntimeKPropertyStub.self) != nil {
        return 1
    }
    return 0
}

@_cdecl("__kk_kcallable_get_metadata")
public func __kk_kcallable_get_metadata(_ raw: Int, _ member: Int) -> Int {
    let metadata = callableMetadata(raw)
    switch member {
    case 0: return metadata?.parameters ?? __kk_kfunction_get_parameters(raw)
    case 1: return metadata?.typeParameters ?? registerRuntimeObject(RuntimeListBox(elements: []))
    case 2:
        guard let ordinal = metadata?.visibility, (0..<4).contains(ordinal) else { return runtimeNullSentinelInt }
        let name = ["PUBLIC", "PROTECTED", "INTERNAL", "PRIVATE"][ordinal]
        return kk_enum_box_ordinal(ordinal, runtimeMakeStringRaw(name), Int(runtimeStableNominalTypeID(fqName: "kotlin.reflect.KVisibility")))
    case 3: return (metadata?.flags ?? 1) & 1 != 0 ? 1 : 0
    case 4: return (metadata?.flags ?? 1) & 2 != 0 ? 1 : 0
    case 5: return (metadata?.flags ?? 1) & 4 != 0 ? 1 : 0
    case 6: return metadata?.isSuspend == true ? 1 : __kk_kfunction_is_suspend(raw)
    case 7: return metadata.map { $0.flags & 16 != 0 ? 1 : 0 } ?? kk_kproperty_stub_is_const(raw)
    case 8: return metadata.map { $0.flags & 32 != 0 ? 1 : 0 } ?? kk_kproperty_stub_is_lateinit(raw)
    case 9: return runtimePropertyAccessor(raw, isSetter: false)
    case 10: return runtimePropertyAccessor(raw, isSetter: true)
    case 11: return metadata?.property ?? runtimeNullSentinelInt
    case 12: return runtimeAnnotationList(metadata?.annotations ?? [])
    default: return runtimeNullSentinelInt
    }
}

private func runtimePropertyAccessor(_ raw: Int, isSetter: Bool) -> Int {
    guard var metadata = callableMetadata(raw), metadata.kind == .property,
          !isSetter || metadata.setterInvoker != 0 else { return runtimeNullSentinelInt }
    let arity = metadata.arity + (isSetter ? 1 : 0)
    let functionPointer: Int
    switch arity {
    case 0:
        let function: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = runtimePropertyAccessorInvoke0
        functionPointer = unsafeBitCast(function, to: Int.self)
    case 1:
        let function: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = runtimePropertyAccessorInvoke1
        functionPointer = unsafeBitCast(function, to: Int.self)
    case 2:
        let function: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = runtimePropertyAccessorInvoke2
        functionPointer = unsafeBitCast(function, to: Int.self)
    default:
        let function: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = runtimePropertyAccessorInvoke3
        functionPointer = unsafeBitCast(function, to: Int.self)
    }
    let context = RuntimePropertyAccessorContext(metadata: metadata)
    let contextRaw = registerRuntimeObject(context)
    let box = RuntimeFunctionValueBox(fnPtr: functionPointer, closureRaw: contextRaw, arity: arity)
    let accessor = registerRuntimeObject(box, typeID: kFunctionRuntimeTypeID)
    runtimeRegisterKCallableItableIfNeeded(rawValue: accessor, typeID: kFunctionRuntimeTypeID)
    metadata.property = raw
    if isSetter {
        metadata.invoker = metadata.setterInvoker
        metadata.parameters = metadata.setterParameters
    }
    let name = extractString(from: UnsafeMutableRawPointer(bitPattern: metadata.nameRaw)) ?? ""
    metadata = RuntimeCallableRefMetadata(
        nameRaw: runtimeMakeStringRaw(isSetter ? "<set-\(name)>" : "<get-\(name)>"),
        returnTypeRaw: isSetter ? runtimeMakeStringRaw("Unit") : metadata.returnTypeRaw,
        arity: metadata.arity + (isSetter ? 1 : 0), kind: .function, isSuspend: false,
        invoker: metadata.invoker, environment: metadata.environment, parameters: metadata.parameters,
        typeParameters: metadata.typeParameters, flags: metadata.flags & 7, visibility: metadata.visibility,
        property: raw
    )
    context.metadata = metadata
    runtimeStorage.withDelegateLock { $0.callableRefMetadataByValue[accessor] = metadata }
    return accessor
}

private func runtimePropertyAccessorInvoke0(_ raw: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let metadata = callableMetadata(raw) else { return runtimeNullSentinelInt }
    return invokeCallable(metadata, values: [], mask: 0, outThrown: thrown)
}

private func runtimePropertyAccessorInvoke1(_ raw: Int, _ a: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let metadata = callableMetadata(raw) else { return runtimeNullSentinelInt }
    return invokeCallable(metadata, values: [a], mask: 0, outThrown: thrown)
}

private func runtimePropertyAccessorInvoke2(_ raw: Int, _ a: Int, _ b: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let metadata = callableMetadata(raw) else { return runtimeNullSentinelInt }
    return invokeCallable(metadata, values: [a, b], mask: 0, outThrown: thrown)
}

private func runtimePropertyAccessorInvoke3(_ raw: Int, _ a: Int, _ b: Int, _ c: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let metadata = callableMetadata(raw) else { return runtimeNullSentinelInt }
    return invokeCallable(metadata, values: [a, b, c], mask: 0, outThrown: thrown)
}

private func callableArguments(_ raw: Int) -> [Int]? {
    if let list = runtimeReflectionObject(from: raw, as: RuntimeListBox.self) { return list.elements }
    return runtimeArrayBox(from: raw)?.elements
}

func runtimeCallableReflectionRoots() -> [Int] {
    let entries = runtimeStorage.withDelegateLock { $0.callableRefMetadataByValue }
    return entries.flatMap { raw, metadata in
        [raw, metadata.property] + (callableArguments(metadata.environment) ?? [])
            + (callableArguments(metadata.typeParameters) ?? [])
    }
}

@_cdecl("__kk_kcallable_call")
public func __kk_kcallable_call(_ raw: Int, _ arguments: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let values = callableArguments(arguments) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Expected a callable argument array.")
        return runtimeNullSentinelInt
    }
    guard let metadata = callableMetadata(raw) else {
        let list = registerRuntimeObject(RuntimeListBox(elements: values))
        return __kk_kfunction_call_vararg(raw, list, outThrown)
    }
    guard values.count == metadata.arity else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Callable expects \(metadata.arity) arguments, got \(values.count).")
        return runtimeNullSentinelInt
    }
    return invokeCallable(metadata, values: values, mask: 0, outThrown: outThrown)
}

@_cdecl("__kk_kcallable_call_by")
public func __kk_kcallable_call_by(_ raw: Int, _ arguments: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let metadata = callableMetadata(raw),
          let map = runtimeReflectionObject(from: arguments, as: RuntimeMapBox.self),
          let parameters = callableArguments(metadata.parameters), parameters.count == metadata.arity else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Invalid callable or parameter map.")
        return runtimeNullSentinelInt
    }
    // Kotlin ignores map entries that do not correspond to this callable.
    var values: [Int] = []
    var mask = 0
    let receiverCount = parameters.prefix { __kk_kparameter_get_kind($0) != 2 }.count
    for (index, parameter) in parameters.enumerated() {
        if let entry = map.index(ofRawKey: parameter) ?? map.keys.firstIndex(where: { callableParameterMatches($0, parameter) }) {
            values.append(map.values[entry])
        } else if __kk_kparameter_is_optional(parameter) != 0, index - receiverCount < 30 {
            mask |= 1 << (index - receiverCount)
            values.append(0)
        } else {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "No argument provided for required parameter \(index).")
            return runtimeNullSentinelInt
        }
    }
    return invokeCallable(metadata, values: values, mask: mask, outThrown: outThrown)
}

private func callableParameterMatches(_ lhs: Int, _ rhs: Int) -> Bool {
    guard let lhs = runtimeReflectionObject(from: lhs, as: RuntimeKParameterBox.self),
          let rhs = runtimeReflectionObject(from: rhs, as: RuntimeKParameterBox.self),
          lhs.callableOwner != 0, lhs.callableOwner == rhs.callableOwner, lhs.index == rhs.index,
          lhs.boundArguments.count == rhs.boundArguments.count else { return false }
    return zip(lhs.boundArguments, rhs.boundArguments).allSatisfy { runtimeValuesEqual(RuntimeValue(raw: $0), RuntimeValue(raw: $1)) }
}

private func invokeCallable(_ metadata: RuntimeCallableRefMetadata, values: [Int], mask: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard metadata.invoker != 0 else {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(message: "Callable has no invocation bridge.")
        return runtimeNullSentinelInt
    }
    if let parameters = callableArguments(metadata.parameters) {
        let receiverCount = parameters.prefix { __kk_kparameter_get_kind($0) != 2 }.count
        for (index, raw) in parameters.enumerated() where index < values.count {
            let valueIndex = index - receiverCount
            if valueIndex >= 0, valueIndex < Int.bitWidth - 1, mask & (1 << valueIndex) != 0 { continue }
            guard let parameter = runtimeReflectionObject(from: raw, as: RuntimeKParameterBox.self),
                  let token = parameter.typeToken, token & 0xff != 0 else { continue }
            if kk_op_is(values[index], token) == 0 {
                outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Argument \(index) has an incompatible type.")
                return runtimeNullSentinelInt
            }
        }
    }
    let arguments = registerRuntimeObject(RuntimeListBox(elements: values))
    let invoke = unsafeBitCast(metadata.invoker, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    return invoke(metadata.environment, arguments, mask, outThrown)
}
