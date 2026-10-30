@_cdecl("__kk_function_set_enclosing_class")
public func __kk_function_set_enclosing_class(_ value: Int, _ enclosingClassNameRaw: Int) {
    guard value != 0,
          let enclosingClassName = extractString(from: UnsafeMutableRawPointer(bitPattern: enclosingClassNameRaw))
    else {
        return
    }
    let functionPointer = runtimeFunctionValueBox(from: value)?.fnPtr ?? value
    runtimeStorage.withDelegateLock { state in
        state.functionEnclosingClassNamesByPointer[functionPointer] = enclosingClassName
    }
}

func runtimeFunctionEnclosingClassName(for value: Int) -> String? {
    let functionPointer = runtimeFunctionValueBox(from: value)?.fnPtr ?? value
    return runtimeStorage.withDelegateLock { state in
        state.functionEnclosingClassNamesByPointer[functionPointer]
    }
}

@_cdecl("kk_function_value_tag_arity")
public func kk_function_value_tag_arity(_ functionRaw: Int, _ functionTypePayload: Int) -> Int {
    guard functionRaw != 0, functionTypePayload >= 0 else {
        return functionRaw
    }
    runtimeStorage.withDelegateLock { state in
        state.functionTypePayloadByValue[functionRaw] = functionTypePayload
    }
    return functionRaw
}

@_cdecl("__kk_function_set_description")
public func __kk_function_set_description(_ value: Int, _ descriptionRaw: Int, _ identity: Int) {
    guard value != 0,
          let description = extractString(from: UnsafeMutableRawPointer(bitPattern: descriptionRaw)) else {
        return
    }
    let text = identity == 0 ? description : "\(description)@\(String(UInt(bitPattern: value), radix: 16))"
    runtimeStorage.withDelegateLock { state in
        state.functionDescriptionsByValue[value] = text
    }
}

func runtimeFunctionDescription(_ value: Int) -> String? {
    if let description = runtimeStorage.withDelegateLock({ state in
        state.functionDescriptionsByValue[value]
    }) {
        return description
    }
    if let function = runtimeFunctionValueBox(from: value) {
        return "kotlin.Function\(function.arity)@\(String(UInt(bitPattern: value), radix: 16))"
    }
    return nil
}

@_cdecl("__kk_function_copy_description")
public func __kk_function_copy_description(_ source: Int, _ target: Int) {
    guard target != 0 else { return }
    let description = runtimeFunctionDescription(source)
    let metadata = runtimeStorage.withDelegateLock { state -> RuntimeCallableRefMetadata? in
        if let description {
            state.functionDescriptionsByValue[target] = description
        }
        let metadata = state.callableRefMetadataByValue[source]
        if let metadata {
            state.callableRefMetadataByValue[target] = metadata
        }
        let adapterIdentity = state.callableAdapterIdentityByValue[source]
        if let adapterIdentity {
            state.callableAdapterIdentityByValue[target] = adapterIdentity
        }
        return metadata
    }
    if let metadata {
        runtimeRegisterKCallableItableIfNeeded(
            rawValue: target,
            typeID: metadata.kind == .function ? kFunctionRuntimeTypeID : kPropertyRuntimeTypeID
        )
    }
}

func runtimeFunctionValueBox(from rawValue: Int) -> RuntimeFunctionValueBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeFunctionValueBox.self)
}

struct RuntimeCallableReferenceIdentity {
    let targetRaw: Int
    let returnTypeRaw: Int
    let arity: Int
    let kind: RuntimeCallableRefKind
    let isSuspend: Bool
    let modifierFlags: Int
    let captures: [Int]
    /// Non-zero when this identity belongs to a `fun interface` SAM-adapter
    /// wrapper: the stable nominal type ID of the implemented interface.
    /// Plain callable references carry 0.
    var samInterfaceTypeID: Int64 = 0
}

private func runtimeCallableReferenceIdentity(from rawValue: Int) -> RuntimeCallableReferenceIdentity? {
    let (metadata, functionValueIdentity, adapterIdentity) = runtimeStorage.withDelegateLock { state in
        (
            state.callableRefMetadataByValue[rawValue],
            state.functionValueCallableRefIdentityByValue[rawValue],
            state.callableAdapterIdentityByValue[rawValue]
        )
    }
    if let metadata, metadata.identityTargetRaw != 0 {
        return RuntimeCallableReferenceIdentity(
            targetRaw: metadata.identityTargetRaw,
            returnTypeRaw: metadata.returnTypeRaw,
            arity: metadata.arity,
            kind: metadata.kind,
            isSuspend: metadata.isSuspend,
            modifierFlags: metadata.modifierFlags,
            captures: metadata.identityCaptures
        )
    }
    if let functionValueIdentity {
        return functionValueIdentity
    }
    guard let adapterIdentity else {
        return nil
    }
    return RuntimeCallableReferenceIdentity(
        targetRaw: adapterIdentity.targetRaw,
        returnTypeRaw: adapterIdentity.returnTypeRaw,
        arity: adapterIdentity.arity,
        kind: .function,
        isSuspend: adapterIdentity.isSuspend,
        modifierFlags: adapterIdentity.modifierFlags,
        captures: adapterIdentity.captures,
        samInterfaceTypeID: adapterIdentity.samInterfaceTypeID
    )
}

func runtimeCallableReferenceValuesEqual(_ lhs: Int, _ rhs: Int) -> Bool? {
    let lhsIdentity = runtimeCallableReferenceIdentity(from: lhs)
    let rhsIdentity = runtimeCallableReferenceIdentity(from: rhs)
    guard lhsIdentity != nil || rhsIdentity != nil else { return nil }
    guard let lhsIdentity, let rhsIdentity,
          lhsIdentity.targetRaw == rhsIdentity.targetRaw,
          runtimeCallableReturnTypesEqual(lhsIdentity.returnTypeRaw, rhsIdentity.returnTypeRaw),
          lhsIdentity.arity == rhsIdentity.arity,
          lhsIdentity.kind == rhsIdentity.kind,
          lhsIdentity.isSuspend == rhsIdentity.isSuspend,
          lhsIdentity.modifierFlags == rhsIdentity.modifierFlags,
          lhsIdentity.captures.count == rhsIdentity.captures.count
    else {
        return false
    }
    if lhsIdentity.samInterfaceTypeID != rhsIdentity.samInterfaceTypeID {
        // A SAM-adapter wrapper's synthesized `equals` only succeeds when the
        // other operand `instanceof`s the same `fun interface` (JVM
        // FunctionAdapter contract): a plain callable reference, a non-object
        // value, or a wrapper of an unrelated interface is never equal.
        guard lhsIdentity.samInterfaceTypeID != 0,
              let rhsTypeID = runtimeObjectTypeID(rawValue: rhs),
              runtimeIsAssignable(sourceTypeID: rhsTypeID, targetTypeID: lhsIdentity.samInterfaceTypeID)
        else {
            return false
        }
    }
    return zip(lhsIdentity.captures, rhsIdentity.captures).allSatisfy { lhsCapture, rhsCapture in
        runtimeValuesEqual(lhsCapture, rhsCapture)
    }
}

private func runtimeCallableReturnTypesEqual(_ lhsRaw: Int, _ rhsRaw: Int) -> Bool {
    if lhsRaw == rhsRaw { return true }
    guard lhsRaw != 0, rhsRaw != 0,
          let lhs = runtimeStringFromRaw(lhsRaw),
          let rhs = runtimeStringFromRaw(rhsRaw)
    else {
        return false
    }
    return lhs == rhs
}

func runtimeCallableReferenceHashCode(_ rawValue: Int) -> Int? {
    guard let identity = runtimeCallableReferenceIdentity(from: rawValue) else { return nil }
    var hash = Int32(truncatingIfNeeded: identity.targetRaw)
    hash = 31 &* hash &+ Int32(identity.arity)
    hash = 31 &* hash &+ (identity.isSuspend ? 1 : 0)
    hash = 31 &* hash &+ Int32(truncatingIfNeeded: identity.modifierFlags)
    if identity.kind == .property {
        hash = 31 &* hash &+ 1
    }
    for capture in identity.captures {
        hash = 31 &* hash &+ Int32(truncatingIfNeeded: runtimeValueHash(capture))
    }
    return Int(hash)
}

private let runtimeFunctionInterfaceTypeIDs = (0...22).map {
    runtimeStableNominalTypeID(fqName: "kotlin.Function.Function\($0)")
}

func runtimeCallableObjectPair(
    from rawValue: Int,
    arity expectedArity: Int? = nil
) -> (fnPtr: Int, closureRaw: Int, arity: Int)? {
    let registration = runtimeStorage.withMetadataLock { state -> (Int, Int)? in
        guard let slots = state.objectInterfaceSlots[UInt(bitPattern: rawValue)] else { return nil }
        for (arity, typeID) in runtimeFunctionInterfaceTypeIDs.enumerated() {
            guard expectedArity == nil || expectedArity == arity else { continue }
            if let slot = slots[typeID] { return (arity, slot) }
        }
        return nil
    }
    guard let (arity, slot) = registration else { return nil }
    let fnPtr = kk_itable_lookup(rawValue, slot, 0)
    guard fnPtr != 0 else { return nil }
    return (fnPtr, rawValue, arity)
}

private func runtimeIsFunctionObject(_ rawValue: Int) -> Bool {
    runtimeStorage.withGCLock { state in
        let key = UInt(bitPattern: rawValue)
        return state.objectPointers.contains(key) || state.heapObjects[key] != nil
    }
}

/// KUU-3802: codegen registers a nominal `SuspendFunctionN` implementor's
/// invoke launcher thunk — the `(continuation, outThrown)` entry point a
/// `RuntimeFunctionValueBox` carries — under this reserved itable method slot,
/// alongside the ordinary invoke bridge at slot 0. The value is far outside
/// the method-slot range any declared interface member can occupy.
let runtimeSuspendInvokeEntryMethodSlot = Int(UInt32.max)

/// A nominal class instance implementing a suspend function type
/// (`class C : suspend () -> T`) is not a `RuntimeFunctionValueBox` — its
/// constructor registers a `kotlin.coroutines.SuspendFunction{arity}` itable
/// whose reserved method slot carries the invoke launcher thunk. Resolving it
/// lets suspend-function call sites and the coroutine builders drive the
/// object through the same child-continuation state-machine machinery a
/// boxed suspend callable uses.
func runtimeSuspendInvokeEntryPoint(objectRaw: Int, arity: Int) -> Int {
    guard objectRaw != 0, (0 ... 22).contains(arity) else {
        return 0
    }
    let interfaceTypeID = runtimeStableNominalTypeID(
        fqName: "kotlin.coroutines.SuspendFunction\(arity)"
    )
    return kk_itable_lookup_dynamic(
        objectRaw,
        Int(interfaceTypeID),
        runtimeSuspendInvokeEntryMethodSlot
    )
}

private func runtimeFunctionInvocationPair(
    _ rawValue: Int,
    arity: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> (fnPtr: Int, closureRaw: Int)? {
    if let box = runtimeFunctionValueBox(from: rawValue) {
        guard box.arity == arity else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: arity, actual: box.arity)
            return nil
        }
        return (box.fnPtr, box.closureRaw)
    }
    if let object = runtimeCallableObjectPair(from: rawValue, arity: arity) {
        return (object.fnPtr, object.closureRaw)
    }
    if let object = runtimeCallableObjectPair(from: rawValue) {
        outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: arity, actual: object.arity)
        return nil
    }
    outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid function value")
    return nil
}

private func runtimeFunctionNeedsDispatch(_ rawValue: Int) -> Bool {
    rawValue == 0 || rawValue == runtimeNullSentinelInt || runtimeIsFunctionObject(rawValue)
        || runtimeCallableObjectPair(from: rawValue) != nil
}

func runtimeResolveClosureInvocation(
    fnPtr: Int,
    closureRaw: Int,
    arity: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> (fnPtr: Int, closureRaw: Int, preservesBoxes: Bool)? {
    if runtimeFunctionNeedsDispatch(fnPtr) {
        guard let pair = runtimeFunctionInvocationPair(fnPtr, arity: arity, outThrown: outThrown) else { return nil }
        return (pair.fnPtr, pair.closureRaw, runtimeCallableObjectPair(from: fnPtr) != nil)
    }
    // splitCallableLambdaArgument may already have resolved the object's pair.
    let object = runtimeCallableObjectPair(from: closureRaw)
    if let object, object.fnPtr == fnPtr, object.arity != arity {
        outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: arity, actual: object.arity)
        return nil
    }
    return (fnPtr, closureRaw, object?.fnPtr == fnPtr)
}

/// Resolves `fnPtr`/`closureRaw` regardless of whether the caller arrived as
/// a raw (fnPtr, closureRaw) pair or as a `kk_function_create_N`-wrapped
/// function-value handle in `fnPtr` (with `closureRaw` then unused/0). Native
/// bridges that must defer invocation — e.g. queue a job onto another thread
/// instead of calling it inline — should resolve the pair with this *before*
/// capturing it into the deferred closure, so that closure only ever holds a
/// raw pair with no lingering dependency on the wrapper box's lifetime.
@inline(__always)
func resolveFunctionValuePair(fnPtr: Int, closureRaw: Int) -> (fnPtr: Int, closureRaw: Int) {
    if let box = runtimeFunctionValueBox(from: fnPtr) {
        return (box.fnPtr, box.closureRaw)
    }
    if let object = runtimeCallableObjectPair(from: fnPtr) {
        return (object.fnPtr, object.closureRaw)
    }
    guard !runtimeFunctionNeedsDispatch(fnPtr) else {
        runtimeStructuredPanic("Invalid function value")
    }
    return (fnPtr, closureRaw)
}

private func runtimeFunctionInvokeInvalidArity(expected: Int, actual: Int) -> Int {
    runtimeAllocateThrowable(message: "Function invoke arity mismatch: expected \(expected), got \(actual)")
}

@_cdecl("kk_suspend_function_create")
public func kk_suspend_function_create(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ arity: Int,
    _ entryPointRaw: Int
) -> Int {
    registerRuntimeObject(RuntimeFunctionValueBox(
        fnPtr: bodyRaw, closureRaw: closureRaw, arity: arity,
        suspendEntryPoint: entryPointRaw
    ))
}

func runtimeInvokeSuspendFunction(
    _ functionRaw: Int,
    arguments: [Int],
    continuation: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard functionRaw != 0 else {
        outThrown?.pointee = runtimeAllocateNullPointerException(message: "")
        return 0
    }
    if let box = runtimeFunctionValueBox(from: functionRaw), box.suspendEntryPoint != 0 {
        guard box.arity == arguments.count else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: box.arity, actual: arguments.count)
            return 0
        }
        let child = kk_coroutine_continuation_new(box.suspendEntryPoint)
        for (index, argument) in ([box.closureRaw] + arguments).enumerated() {
            _ = kk_coroutine_launcher_arg_set(child, Int64(index), Int64(argument))
        }
        if runtimeContinuationState(from: continuation) != nil {
            return kk_coroutine_call_direct_suspend(box.suspendEntryPoint, child, continuation)
        }
        return kk_kxmini_run_blocking_with_cont(box.suspendEntryPoint, child, outThrown)
    }

    // KUU-3802: a nominal `SuspendFunctionN` implementor has no callable box —
    // codegen recorded the invoke launcher thunk in the interface's reserved
    // itable slot. Drive it through the same child-continuation machinery the
    // boxed path uses so suspensions, results, and thrown exceptions flow
    // identically to a boxed suspend callable.
    let objectEntryRaw = runtimeSuspendInvokeEntryPoint(
        objectRaw: functionRaw,
        arity: arguments.count
    )
    if objectEntryRaw != 0 {
        let child = kk_coroutine_continuation_new(objectEntryRaw)
        for (index, argument) in ([functionRaw] + arguments).enumerated() {
            _ = kk_coroutine_launcher_arg_set(child, Int64(index), Int64(argument))
        }
        if runtimeContinuationState(from: continuation) != nil {
            return kk_coroutine_call_direct_suspend(objectEntryRaw, child, continuation)
        }
        return kk_kxmini_run_blocking_with_cont(objectEntryRaw, child, outThrown)
    }

    // Legacy raw thunks and synchronous callbacks retain their ordinary ABI.
    let callerState = runtimeContinuationState(from: continuation)
    var thrown = 0
    let result: Int
    switch arguments.count {
    case 0: result = kk_function_invoke_0(functionRaw, &thrown)
    case 1: result = kk_function_invoke(functionRaw, arguments[0], &thrown)
    case 2: result = kk_function_invoke_2(functionRaw, arguments[0], arguments[1], &thrown)
    case 3: result = kk_function_invoke_3(functionRaw, arguments[0], arguments[1], arguments[2], &thrown)
    case 4: result = kk_function_invoke_4(functionRaw, arguments[0], arguments[1], arguments[2], arguments[3], &thrown)
    case 5: result = kk_function_invoke_5(functionRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], &thrown)
    default: result = kk_function_invoke_6(functionRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], &thrown)
    }
    if result != Int(bitPattern: kk_coroutine_suspended()) {
        callerState?.thrownException = thrown
    }
    outThrown?.pointee = thrown
    return result
}

private func runtimeCreateFunctionValue(
    bodyRaw: Int,
    closureRaw: Int,
    arity: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if runtimeFunctionNeedsDispatch(bodyRaw) {
        guard runtimeFunctionInvocationPair(bodyRaw, arity: arity, outThrown: outThrown) != nil else { return 0 }
        return bodyRaw
    }
    return registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: bodyRaw, closureRaw: closureRaw, arity: arity))
}

/// A suspend function value reached through the non-suspend `FunctionN.invoke`
/// ABI (e.g. a suspend lambda stored in a plain `transform: (T) -> R` parameter
/// such as `map`'s) cannot relay `COROUTINE_SUSPENDED` to its immediate caller:
/// that frame is an ordinary function, not a state machine. Drive the value
/// synchronously through the suspend-value path with no caller continuation,
/// which drains the body on the event loop and returns the final result.
private func runtimeInvokeSuspendBoxIfNeeded(
    _ functionRaw: Int,
    arguments: [Int],
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    guard let box = runtimeFunctionValueBox(from: functionRaw), box.suspendEntryPoint != 0 else {
        return nil
    }
    return runtimeInvokeSuspendFunction(
        functionRaw, arguments: arguments, continuation: 0, outThrown: outThrown
    )
}

@_cdecl("kk_function_invoke")
public func kk_function_invoke(
    _ functionRaw: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if runtimeFunctionNeedsDispatch(functionRaw) {
        if let driven = runtimeInvokeSuspendBoxIfNeeded(functionRaw, arguments: [arg], outThrown: outThrown) {
            return driven
        }
        guard let pair = runtimeFunctionInvocationPair(functionRaw, arity: 1, outThrown: outThrown) else { return 0 }
        let function = unsafeBitCast(pair.fnPtr, to: KKClosureFunctionEntryPoint1.self)
        return function(pair.closureRaw, arg, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint1.self)
    return function(arg, outThrown)
}

@_cdecl("kk_function_invoke_0")
public func kk_function_invoke_0(
    _ functionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if runtimeFunctionNeedsDispatch(functionRaw) {
        if let driven = runtimeInvokeSuspendBoxIfNeeded(functionRaw, arguments: [], outThrown: outThrown) {
            return driven
        }
        guard let pair = runtimeFunctionInvocationPair(functionRaw, arity: 0, outThrown: outThrown) else { return 0 }
        let function = unsafeBitCast(pair.fnPtr, to: KKClosureThunkEntryPoint.self)
        return function(pair.closureRaw, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKThunkEntryPoint.self)
    return function(outThrown)
}

@_cdecl("kk_function_invoke_2")
public func kk_function_invoke_2(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if runtimeFunctionNeedsDispatch(functionRaw) {
        if let driven = runtimeInvokeSuspendBoxIfNeeded(functionRaw, arguments: [arg1, arg2], outThrown: outThrown) {
            return driven
        }
        guard let pair = runtimeFunctionInvocationPair(functionRaw, arity: 2, outThrown: outThrown) else { return 0 }
        let function = unsafeBitCast(pair.fnPtr, to: KKClosureFunctionEntryPoint2.self)
        return function(pair.closureRaw, arg1, arg2, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint2.self)
    return function(arg1, arg2, outThrown)
}

@_cdecl("kk_function_invoke_3")
public func kk_function_invoke_3(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if runtimeFunctionNeedsDispatch(functionRaw) {
        if let driven = runtimeInvokeSuspendBoxIfNeeded(functionRaw, arguments: [arg1, arg2, arg3], outThrown: outThrown) {
            return driven
        }
        guard let pair = runtimeFunctionInvocationPair(functionRaw, arity: 3, outThrown: outThrown) else { return 0 }
        let function = unsafeBitCast(pair.fnPtr, to: KKClosureFunctionEntryPoint3.self)
        return function(pair.closureRaw, arg1, arg2, arg3, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint3.self)
    return function(arg1, arg2, arg3, outThrown)
}

@_cdecl("kk_function_invoke_4")
public func kk_function_invoke_4(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if runtimeFunctionNeedsDispatch(functionRaw) {
        if let driven = runtimeInvokeSuspendBoxIfNeeded(
            functionRaw, arguments: [arg1, arg2, arg3, arg4], outThrown: outThrown
        ) {
            return driven
        }
        guard let pair = runtimeFunctionInvocationPair(functionRaw, arity: 4, outThrown: outThrown) else { return 0 }
        let function = unsafeBitCast(pair.fnPtr, to: KKClosureFunctionEntryPoint4.self)
        return function(pair.closureRaw, arg1, arg2, arg3, arg4, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint4.self)
    return function(arg1, arg2, arg3, arg4, outThrown)
}

@_cdecl("kk_function_invoke_5")
public func kk_function_invoke_5(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if runtimeFunctionNeedsDispatch(functionRaw) {
        if let driven = runtimeInvokeSuspendBoxIfNeeded(
            functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5], outThrown: outThrown
        ) {
            return driven
        }
        guard let pair = runtimeFunctionInvocationPair(functionRaw, arity: 5, outThrown: outThrown) else { return 0 }
        let function = unsafeBitCast(pair.fnPtr, to: KKClosureFunctionEntryPoint5.self)
        return function(pair.closureRaw, arg1, arg2, arg3, arg4, arg5, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint5.self)
    return function(arg1, arg2, arg3, arg4, arg5, outThrown)
}

@_cdecl("kk_function_invoke_6")
public func kk_function_invoke_6(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if runtimeFunctionNeedsDispatch(functionRaw) {
        if let driven = runtimeInvokeSuspendBoxIfNeeded(
            functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6], outThrown: outThrown
        ) {
            return driven
        }
        guard let pair = runtimeFunctionInvocationPair(functionRaw, arity: 6, outThrown: outThrown) else { return 0 }
        let function = unsafeBitCast(pair.fnPtr, to: KKClosureFunctionEntryPoint6.self)
        return function(pair.closureRaw, arg1, arg2, arg3, arg4, arg5, arg6, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint6.self)
    return function(arg1, arg2, arg3, arg4, arg5, arg6, outThrown)
}

private func runtimeInvokeHighArityFunctionValue(
    _ functionRaw: Int,
    arguments: [Int],
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let driven = runtimeInvokeSuspendBoxIfNeeded(functionRaw, arguments: arguments, outThrown: outThrown) {
        return driven
    }
    if runtimeFunctionNeedsDispatch(functionRaw) {
        guard let pair = runtimeFunctionInvocationPair(functionRaw, arity: arguments.count, outThrown: outThrown) else {
            return 0
        }
        return runtimeInvokeHighArityFunctionPointer(
            pair.fnPtr, closureRaw: pair.closureRaw, arguments: arguments, outThrown: outThrown
        )
    }
    return runtimeInvokeHighArityFunctionPointer(
        functionRaw, closureRaw: nil, arguments: arguments, outThrown: outThrown
    )
}

private func runtimeInvokeHighArityFunctionPointer(
    _ functionRaw: Int,
    closureRaw: Int?,
    arguments: [Int],
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let closureRaw {
        switch arguments.count {

        case 7:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint7.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], outThrown)

        case 8:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint8.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], outThrown)

        case 9:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint9.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], outThrown)

        case 10:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint10.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], outThrown)

        case 11:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint11.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], outThrown)

        case 12:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint12.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], outThrown)

        case 13:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint13.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], outThrown)

        case 14:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint14.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], outThrown)

        case 15:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint15.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], outThrown)

        case 16:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint16.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15], outThrown)

        case 17:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint17.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15], arguments[16], outThrown)

        case 18:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint18.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15], arguments[16], arguments[17], outThrown)

        case 19:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint19.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15], arguments[16], arguments[17], arguments[18], outThrown)

        case 20:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint20.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15], arguments[16], arguments[17], arguments[18], arguments[19], outThrown)

        case 21:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint21.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15], arguments[16], arguments[17], arguments[18], arguments[19], arguments[20], outThrown)

        case 22:
            let function = unsafeBitCast(functionRaw, to: KKClosureFunctionEntryPoint22.self)
            return function(closureRaw, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15], arguments[16], arguments[17], arguments[18], arguments[19], arguments[20], arguments[21], outThrown)

        default:
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "Unsupported function invocation arity: \(arguments.count)"
            )
            return 0
        }
    }
    switch arguments.count {

    case 7:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint7.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], outThrown)

    case 8:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint8.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], outThrown)

    case 9:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint9.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], outThrown)

    case 10:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint10.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], outThrown)

    case 11:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint11.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], outThrown)

    case 12:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint12.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], outThrown)

    case 13:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint13.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], outThrown)

    case 14:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint14.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], outThrown)

    case 15:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint15.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], outThrown)

    case 16:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint16.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15], outThrown)

    case 17:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint17.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15], arguments[16], outThrown)

    case 18:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint18.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15], arguments[16], arguments[17], outThrown)

    case 19:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint19.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15], arguments[16], arguments[17], arguments[18], outThrown)

    case 20:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint20.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15], arguments[16], arguments[17], arguments[18], arguments[19], outThrown)

    case 21:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint21.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15], arguments[16], arguments[17], arguments[18], arguments[19], arguments[20], outThrown)

    case 22:
        let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint22.self)
        return function(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9], arguments[10], arguments[11], arguments[12], arguments[13], arguments[14], arguments[15], arguments[16], arguments[17], arguments[18], arguments[19], arguments[20], arguments[21], outThrown)

    default:
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "Unsupported function invocation arity: \(arguments.count)"
        )
        return 0
    }
}

@_cdecl("kk_function_invoke_7")
public func kk_function_invoke_7(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7], outThrown: outThrown)
}

@_cdecl("kk_function_invoke_8")
public func kk_function_invoke_8(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ arg8: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8], outThrown: outThrown)
}

@_cdecl("kk_function_invoke_9")
public func kk_function_invoke_9(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ arg8: Int,
    _ arg9: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9], outThrown: outThrown)
}

@_cdecl("kk_function_invoke_10")
public func kk_function_invoke_10(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ arg8: Int,
    _ arg9: Int,
    _ arg10: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10], outThrown: outThrown)
}

@_cdecl("kk_function_invoke_11")
public func kk_function_invoke_11(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ arg8: Int,
    _ arg9: Int,
    _ arg10: Int,
    _ arg11: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11], outThrown: outThrown)
}

@_cdecl("kk_function_invoke_12")
public func kk_function_invoke_12(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ arg8: Int,
    _ arg9: Int,
    _ arg10: Int,
    _ arg11: Int,
    _ arg12: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12], outThrown: outThrown)
}

@_cdecl("kk_function_invoke_13")
public func kk_function_invoke_13(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ arg8: Int,
    _ arg9: Int,
    _ arg10: Int,
    _ arg11: Int,
    _ arg12: Int,
    _ arg13: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13], outThrown: outThrown)
}

@_cdecl("kk_function_invoke_14")
public func kk_function_invoke_14(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ arg8: Int,
    _ arg9: Int,
    _ arg10: Int,
    _ arg11: Int,
    _ arg12: Int,
    _ arg13: Int,
    _ arg14: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14], outThrown: outThrown)
}

@_cdecl("kk_function_invoke_15")
public func kk_function_invoke_15(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ arg8: Int,
    _ arg9: Int,
    _ arg10: Int,
    _ arg11: Int,
    _ arg12: Int,
    _ arg13: Int,
    _ arg14: Int,
    _ arg15: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15], outThrown: outThrown)
}

@_cdecl("kk_function_invoke_16")
public func kk_function_invoke_16(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ arg8: Int,
    _ arg9: Int,
    _ arg10: Int,
    _ arg11: Int,
    _ arg12: Int,
    _ arg13: Int,
    _ arg14: Int,
    _ arg15: Int,
    _ arg16: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16], outThrown: outThrown)
}

@_cdecl("kk_function_invoke_17")
public func kk_function_invoke_17(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ arg8: Int,
    _ arg9: Int,
    _ arg10: Int,
    _ arg11: Int,
    _ arg12: Int,
    _ arg13: Int,
    _ arg14: Int,
    _ arg15: Int,
    _ arg16: Int,
    _ arg17: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17], outThrown: outThrown)
}

@_cdecl("kk_function_invoke_18")
public func kk_function_invoke_18(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ arg8: Int,
    _ arg9: Int,
    _ arg10: Int,
    _ arg11: Int,
    _ arg12: Int,
    _ arg13: Int,
    _ arg14: Int,
    _ arg15: Int,
    _ arg16: Int,
    _ arg17: Int,
    _ arg18: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17, arg18], outThrown: outThrown)
}

@_cdecl("kk_function_invoke_19")
public func kk_function_invoke_19(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ arg8: Int,
    _ arg9: Int,
    _ arg10: Int,
    _ arg11: Int,
    _ arg12: Int,
    _ arg13: Int,
    _ arg14: Int,
    _ arg15: Int,
    _ arg16: Int,
    _ arg17: Int,
    _ arg18: Int,
    _ arg19: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17, arg18, arg19], outThrown: outThrown)
}

@_cdecl("kk_function_invoke_20")
public func kk_function_invoke_20(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ arg8: Int,
    _ arg9: Int,
    _ arg10: Int,
    _ arg11: Int,
    _ arg12: Int,
    _ arg13: Int,
    _ arg14: Int,
    _ arg15: Int,
    _ arg16: Int,
    _ arg17: Int,
    _ arg18: Int,
    _ arg19: Int,
    _ arg20: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17, arg18, arg19, arg20], outThrown: outThrown)
}

@_cdecl("kk_function_invoke_21")
public func kk_function_invoke_21(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ arg8: Int,
    _ arg9: Int,
    _ arg10: Int,
    _ arg11: Int,
    _ arg12: Int,
    _ arg13: Int,
    _ arg14: Int,
    _ arg15: Int,
    _ arg16: Int,
    _ arg17: Int,
    _ arg18: Int,
    _ arg19: Int,
    _ arg20: Int,
    _ arg21: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17, arg18, arg19, arg20, arg21], outThrown: outThrown)
}

@_cdecl("kk_function_invoke_22")
public func kk_function_invoke_22(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ arg4: Int,
    _ arg5: Int,
    _ arg6: Int,
    _ arg7: Int,
    _ arg8: Int,
    _ arg9: Int,
    _ arg10: Int,
    _ arg11: Int,
    _ arg12: Int,
    _ arg13: Int,
    _ arg14: Int,
    _ arg15: Int,
    _ arg16: Int,
    _ arg17: Int,
    _ arg18: Int,
    _ arg19: Int,
    _ arg20: Int,
    _ arg21: Int,
    _ arg22: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeInvokeHighArityFunctionValue(functionRaw, arguments: [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17, arg18, arg19, arg20, arg21, arg22], outThrown: outThrown)
}

@_cdecl("kk_function_create_0")
public func kk_function_create_0(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    // A function-valued parameter may already be boxed when it is captured by
    // another lambda. Keep boxing idempotent so the outer closure does not
    // turn the inner function object into a function pointer.
    runtimeCreateFunctionValue(bodyRaw: bodyRaw, closureRaw: closureRaw, arity: 0, outThrown: outThrown)
}

@_cdecl("kk_function_create_1")
public func kk_function_create_1(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeCreateFunctionValue(bodyRaw: bodyRaw, closureRaw: closureRaw, arity: 1, outThrown: outThrown)
}

// A callable value forwarded as an ordinary argument (e.g. a bundled
// Kotlin-source HOF like `Sequence.chunked(size, transform)` receiving its
// trailing lambda) arrives boxed via kk_function_create_1/2/... rather than
// as a raw (fnPtr, closureRaw) pair, because the lowering that produced it
// didn't know the callee would eventually need the raw C-ABI closure
// convention (see CallLowerer+MemberCallEmission.splitCallableLambdaArgument,
// whose compile-time-only fallback can't inspect closure shape). These two
// accessors let call sites recover the pair at runtime regardless of which
// shape the value turns out to have — mirrors kk_function_invoke's existing
// box-or-raw branch, minus the actual invocation.
@_cdecl("kk_function_value_fn_ptr")
public func kk_function_value_fn_ptr(_ functionRaw: Int) -> Int {
    resolveFunctionValuePair(fnPtr: functionRaw, closureRaw: 0).fnPtr
}

@_cdecl("kk_function_value_closure_raw")
public func kk_function_value_closure_raw(_ functionRaw: Int) -> Int {
    resolveFunctionValuePair(fnPtr: functionRaw, closureRaw: 0).closureRaw
}

@_cdecl("kk_function_create_2")
public func kk_function_create_2(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeCreateFunctionValue(bodyRaw: bodyRaw, closureRaw: closureRaw, arity: 2, outThrown: outThrown)
}

@_cdecl("kk_function_create_3")
public func kk_function_create_3(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeCreateFunctionValue(bodyRaw: bodyRaw, closureRaw: closureRaw, arity: 3, outThrown: outThrown)
}

@_cdecl("kk_function_create_4")
public func kk_function_create_4(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeCreateFunctionValue(bodyRaw: bodyRaw, closureRaw: closureRaw, arity: 4, outThrown: outThrown)
}

@_cdecl("kk_function_create_5")
public func kk_function_create_5(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeCreateFunctionValue(bodyRaw: bodyRaw, closureRaw: closureRaw, arity: 5, outThrown: outThrown)
}

@_cdecl("kk_function_create_6")
public func kk_function_create_6(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeCreateFunctionValue(bodyRaw: bodyRaw, closureRaw: closureRaw, arity: 6, outThrown: outThrown)
}
