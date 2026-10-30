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

@_cdecl("__kk_kcallable_register_return_type")
public func __kk_kcallable_register_return_type(_ raw: Int, _ returnTypeKTypeRaw: Int) -> Int {
    runtimeStorage.withDelegateLock { state in
        guard var metadata = state.callableRefMetadataByValue[raw] else { return }
        metadata.returnTypeKTypeRaw = returnTypeKTypeRaw
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
    if let stub = runtimeReflectionObject(from: raw, as: RuntimeKPropertyStub.self),
       stub.isLocalDelegated
    {
        return runtimeLocalDelegatedPropertyAccessor(raw: raw, stub: stub, isSetter: isSetter)
    }
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
        property: raw, returnTypeKTypeRaw: metadata.returnTypeKTypeRaw
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

@_cdecl("__kk_callable_ref_set_identity")
public func __kk_callable_ref_set_identity(_ callable: Int, _ targetRaw: Int, _ capturesRaw: Int) {
    guard targetRaw != 0 else { return }
    let captures: [Int]
    if capturesRaw == runtimeNullSentinelInt {
        captures = []
    } else if let values = callableArguments(capturesRaw) {
        captures = values
    } else {
        return
    }
    runtimeStorage.withDelegateLock { state in
        guard var metadata = state.callableRefMetadataByValue[callable] else { return }
        metadata.identityTargetRaw = targetRaw
        metadata.identityCaptures = captures
        state.callableRefMetadataByValue[callable] = metadata
    }
}

/// Record equality identity for an adapted callable-reference function value
/// without registering KFunction reflection metadata on the function object.
@_cdecl("__kk_function_value_set_callable_ref_identity")
public func __kk_function_value_set_callable_ref_identity(
    _ callable: Int,
    _ targetRaw: Int,
    _ capturesRaw: Int,
    _ arity: Int,
    _ kindRaw: Int,
    _ flags: Int
) {
    guard callable != 0, targetRaw != 0, arity >= 0, (0...1).contains(kindRaw) else { return }
    let captures: [Int]
    if capturesRaw == runtimeNullSentinelInt {
        captures = []
    } else if let values = callableArguments(capturesRaw) {
        captures = values
    } else {
        return
    }
    runtimeStorage.withDelegateLock { state in
        state.functionValueCallableRefIdentityByValue[callable] = RuntimeCallableReferenceIdentity(
            targetRaw: targetRaw,
            returnTypeRaw: 0,
            arity: arity,
            kind: kindRaw == 0 ? .function : .property,
            isSuspend: (flags & 1) != 0,
            modifierFlags: flags & ~1,
            captures: captures
        )
    }
}

/// `flags` packs KFunction modifier bits like `kk_callable_ref_tag_kfunction`:
/// bit0=suspend, bit1=inline, bit2=operator, bit3=infix, bit4=external.
private func runtimeSetCallableAdapterIdentity(
    _ callable: Int,
    samInterfaceTypeID: Int,
    _ targetRaw: Int,
    _ capturesRaw: Int,
    _ arity: Int,
    _ flags: Int,
    returnTypeRaw: Int = 0
) {
    guard callable != 0, targetRaw != 0 else { return }
    let captures: [Int]
    if capturesRaw == runtimeNullSentinelInt {
        captures = []
    } else if let values = callableArguments(capturesRaw) {
        captures = values
    } else {
        return
    }
    runtimeStorage.withDelegateLock { state in
        state.callableAdapterIdentityByValue[callable] = RuntimeCallableAdapterIdentity(
            samInterfaceTypeID: Int64(samInterfaceTypeID),
            targetRaw: targetRaw,
            returnTypeRaw: returnTypeRaw,
            arity: arity,
            isSuspend: (flags & 1) != 0,
            modifierFlags: flags & ~1,
            captures: captures
        )
    }
}

@_cdecl("__kk_callable_adapter_set_identity")
public func __kk_callable_adapter_set_identity(
    _ callable: Int,
    _ samInterfaceTypeID: Int,
    _ targetRaw: Int,
    _ capturesRaw: Int,
    _ arity: Int,
    _ flags: Int,
    _ returnTypeRaw: Int
) {
    runtimeSetCallableAdapterIdentity(
        callable, samInterfaceTypeID: samInterfaceTypeID,
        targetRaw, capturesRaw, arity, flags, returnTypeRaw: returnTypeRaw
    )
}

@_cdecl("__kk_sam_adapter_set_identity")
public func __kk_sam_adapter_set_identity(
    _ callable: Int,
    _ interfaceTypeID: Int,
    _ targetRaw: Int,
    _ capturesRaw: Int,
    _ arity: Int,
    _ flags: Int
) {
    guard interfaceTypeID != 0 else { return }
    runtimeSetCallableAdapterIdentity(
        callable, samInterfaceTypeID: interfaceTypeID,
        targetRaw, capturesRaw, arity, flags
    )
}

func runtimeCallableRoots() -> [Int] {
    let (entries, functionValueEntries, adapterEntries) = runtimeStorage.withDelegateLock {
        (
            $0.callableRefMetadataByValue,
            $0.functionValueCallableRefIdentityByValue,
            $0.callableAdapterIdentityByValue
        )
    }
    var roots = entries.flatMap { raw, metadata in
        [raw, metadata.returnTypeRaw, metadata.property] + metadata.identityCaptures
            + (callableArguments(metadata.environment) ?? [])
            + (callableArguments(metadata.typeParameters) ?? [])
    }
    for (raw, identity) in adapterEntries {
        roots.append(raw)
        roots.append(identity.returnTypeRaw)
        roots.append(contentsOf: identity.captures)
    }
    for (raw, identity) in functionValueEntries {
        roots.append(raw)
        roots.append(contentsOf: identity.captures)
    }
    return roots
}

@_cdecl("__kk_kcallable_call")
public func __kk_kcallable_call(_ raw: Int, _ arguments: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let values = callableArguments(arguments) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Expected a callable argument array.")
        return runtimeNullSentinelInt
    }
    guard let metadata = callableMetadata(raw) else {
        // KUU-2947: a local delegated property stub has no real accessor —
        // the JVM raises UnsupportedOperationException from call/callBy
        // rather than an invalid-handle error.
        if let stub = runtimeReflectionObject(from: raw, as: RuntimeKPropertyStub.self),
           stub.isLocalDelegated
        {
            outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
                message: "call/callBy are not supported for this declaration."
            )
            return runtimeNullSentinelInt
        }
        let list = registerRuntimeObject(RuntimeListBox(elements: values))
        return __kk_kfunction_call_vararg(raw, list, outThrown)
    }
    guard values.count == metadata.arity else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Callable expects \(metadata.arity) arguments, got \(values.count).")
        return runtimeNullSentinelInt
    }
    return invokeCallable(metadata, values: values, mask: 0, outThrown: outThrown)
}

@_cdecl("__kk_kproperty0_get")
public func __kk_kproperty0_get(
    _ raw: Int,
    _ interfaceTypeID: Int,
    _ methodSlot: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    // KUU-3693: a local delegated property stub carries its own KProperty0
    // itable whose `get` throws the JVM's UnsupportedOperationException for
    // local delegated references, so it dispatches through the standard
    // dynamic lookup like every other receiver. Non-local stubs instead park
    // `call` at the (interfaceSlot, 0) key `get` resolves to — dispatching
    // them would invoke `call` with the wrong arity — so they keep bailing
    // until accessor-backed wrappers replace the stub path.
    if let stub = runtimeReflectionObject(from: raw, as: RuntimeKPropertyStub.self),
       !stub.isLocalDelegated
    {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
            message: "Local delegated property reflection is not supported."
        )
        return runtimeNullSentinelInt
    }
    let methodRaw = kk_itable_lookup_dynamic(raw, interfaceTypeID, methodSlot)
    guard methodRaw != 0 else {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
            message: "Property reference has no getter implementation."
        )
        return runtimeNullSentinelInt
    }
    let method = unsafeBitCast(
        methodRaw,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    return method(raw, outThrown)
}

/// `KPropertyN.getDelegate` (KUU-3694): delegated-property stubs answer the
/// delegate handle the compiler stored beside the current getValue/setValue
/// call (`__kk_kproperty_stub_set_delegate`); `::prop` wrappers and any other
/// receiver dispatch through the registered itable method, whose impl reads
/// the delegate storage directly. Stubs never given a delegate answer `null`
/// — the JVM's answer for non-delegated and local delegated properties.
@_cdecl("__kk_kproperty_get_delegate")
public func __kk_kproperty_get_delegate(
    _ raw: Int,
    _ interfaceTypeID: Int,
    _ methodSlot: Int,
    _ arg0: Int,
    _ arg1: Int,
    _ arity: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    if let stub = runtimeReflectionObject(from: raw, as: RuntimeKPropertyStub.self) {
        return stub.delegateRaw != 0 ? stub.delegateRaw : runtimeNullSentinelInt
    }
    let methodRaw = kk_itable_lookup_dynamic(raw, interfaceTypeID, methodSlot)
    guard methodRaw != 0 else {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
            message: "Property reference has no getDelegate implementation."
        )
        return runtimeNullSentinelInt
    }
    switch arity {
    case 0:
        let method = unsafeBitCast(
            methodRaw,
            to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        return method(raw, outThrown)
    case 1:
        let method = unsafeBitCast(
            methodRaw,
            to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        return method(raw, arg0, outThrown)
    default:
        let method = unsafeBitCast(
            methodRaw,
            to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        return method(raw, arg0, arg1, outThrown)
    }
}

private let callableVarargArrayTypeIDs: Set<Int64> = Set([
    "Array", "BooleanArray", "ByteArray", "CharArray", "DoubleArray",
    "FloatArray", "IntArray", "LongArray", "ShortArray", "UByteArray",
    "UShortArray", "UIntArray", "ULongArray",
].map { runtimeStableNominalTypeID(fqName: "kotlin.\($0)") })

/// callBy supplies an empty array for an omitted non-optional vararg. The
/// public parameter token describes the whole array, not its element type.
private func callableEmptyVarargArray(_ raw: Int) -> Int? {
    guard let parameter = runtimeReflectionObject(from: raw, as: RuntimeKParameterBox.self),
          parameter.isVararg, let token = parameter.typeToken else { return nil }
    let wide = Int64(token)
    guard wide & RuntimeTypeTokenEncoding.baseMask == RuntimeTypeTokenEncoding.nominalBase else { return nil }
    let typeID = (wide >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask
    guard callableVarargArrayTypeIDs.contains(typeID) else { return nil }
    let genericArrayID = runtimeStableNominalTypeID(fqName: "kotlin.Array")
    guard typeID != genericArrayID || parameter.arrayComponentType.map({ $0 != 0 }) == true else { return nil }
    let empty = kk_array_new(0)
    if let component = parameter.arrayComponentType {
        runtimeArrayBox(from: empty)?.installComponentTypeIfAbsent(component)
    }
    runtimeRegisterArrayType(rawValue: empty, typeID: typeID)
    return empty
}

@_cdecl("__kk_kcallable_call_by")
public func __kk_kcallable_call_by(_ raw: Int, _ arguments: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let metadata = callableMetadata(raw) else {
        if let stub = runtimeReflectionObject(from: raw, as: RuntimeKPropertyStub.self),
           stub.isLocalDelegated
        {
            outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
                message: "call/callBy are not supported for this declaration."
            )
        } else {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Invalid callable or parameter map.")
        }
        return runtimeNullSentinelInt
    }
    guard let map = runtimeReflectionObject(from: arguments, as: RuntimeMapBox.self),
          let parameters = callableArguments(metadata.parameters), parameters.count == metadata.arity else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Invalid callable or parameter map.")
        return runtimeNullSentinelInt
    }
    // Kotlin ignores map entries that do not correspond to this callable.
    var values: [Int] = []
    var mask = 0
    let receiverCount = parameters.prefix { runtimeKParameterInternalKind($0) != 2 }.count
    for (index, parameter) in parameters.enumerated() {
        if let entry = map.index(ofRawKey: parameter) ?? map.keys.firstIndex(where: { callableParameterMatches($0, parameter) }) {
            values.append(map.values[entry])
        } else if __kk_kparameter_is_optional(parameter) != 0, index - receiverCount < 30 {
            mask |= 1 << (index - receiverCount)
            values.append(0)
        } else if __kk_kparameter_is_optional(parameter) == 0, __kk_kparameter_is_vararg(parameter) != 0 {
            guard let empty = callableEmptyVarargArray(parameter) else {
                outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Vararg parameter \(index) does not have an array type.")
                return runtimeNullSentinelInt
            }
            values.append(empty)
        } else {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "No argument provided for required parameter \(index).")
            return runtimeNullSentinelInt
        }
    }
    return invokeCallable(metadata, values: values, mask: mask, outThrown: outThrown)
}

/// Internal `RuntimeKParameterBox.kind` ordinal (2 = VALUE). Unlike
/// `__kk_kparameter_get_kind`, this does not translate to the Kotlin
/// `KParameter.Kind` declaration ordinals.
private func runtimeKParameterInternalKind(_ raw: Int) -> Int {
    runtimeReflectionObject(from: raw, as: RuntimeKParameterBox.self)?.kind ?? 2
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
        let receiverCount = parameters.prefix { runtimeKParameterInternalKind($0) != 2 }.count
        for (index, raw) in parameters.enumerated() where index < values.count {
            let valueIndex = index - receiverCount
            if valueIndex >= 0, valueIndex < Int.bitWidth - 1, mask & (1 << valueIndex) != 0 { continue }
            guard let parameter = runtimeReflectionObject(from: raw, as: RuntimeKParameterBox.self),
                  let token = parameter.typeToken, token & 0xff != 0 else { continue }
            let componentMatches: Bool
            if let expectedComponent = parameter.arrayComponentType {
                componentMatches = runtimeArrayBox(from: values[index])?.componentType.map {
                    runtimeArrayComponentIsAssignable($0, to: expectedComponent)
                } ?? false
            } else {
                componentMatches = true
            }
            if kk_op_is(values[index], token) == 0 || !componentMatches {
                outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Argument \(index) has an incompatible type.")
                return runtimeNullSentinelInt
            }
        }
    }
    let arguments = registerRuntimeObject(RuntimeListBox(elements: values))
    let invoke = unsafeBitCast(metadata.invoker, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    return invoke(metadata.environment, arguments, mask, outThrown)
}
