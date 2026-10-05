
// MARK: - ランタイム関数型操作

@_cdecl("__kk_function_set_description")
public func __kk_function_set_description(_ value: Int, _ descriptionRaw: Int, _ identity: Int) {
    guard let description = extractString(from: UnsafeMutableRawPointer(bitPattern: descriptionRaw)) else {
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
    guard let description = runtimeFunctionDescription(source) else {
        return
    }
    runtimeStorage.withDelegateLock { state in
        state.functionDescriptionsByValue[target] = description
    }
}

func runtimeFunctionValueBox(from rawValue: Int) -> RuntimeFunctionValueBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeFunctionValueBox.self)
}

private let runtimeFunctionInterfaceTypeIDs = (0...22).map {
    runtimeStableNominalTypeID(fqName: "kotlin.Function.Function\($0)")
}

func runtimeCallableObjectPair(from rawValue: Int) -> (fnPtr: Int, closureRaw: Int, arity: Int)? {
    let registration = runtimeStorage.withMetadataLock { state -> (Int, Int)? in
        guard let slots = state.objectInterfaceSlots[UInt(bitPattern: rawValue)] else { return nil }
        for (arity, typeID) in runtimeFunctionInterfaceTypeIDs.enumerated() {
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
    if let object = runtimeCallableObjectPair(from: rawValue) {
        guard object.arity == arity else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: arity, actual: object.arity)
            return nil
        }
        return (object.fnPtr, object.closureRaw)
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

@_cdecl("kk_function_invoke")
public func kk_function_invoke(
    _ functionRaw: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if runtimeFunctionNeedsDispatch(functionRaw) {
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
        guard let pair = runtimeFunctionInvocationPair(functionRaw, arity: 5, outThrown: outThrown) else { return 0 }
        let function = unsafeBitCast(pair.fnPtr, to: KKClosureFunctionEntryPoint5.self)
        return function(pair.closureRaw, arg1, arg2, arg3, arg4, arg5, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint5.self)
    return function(arg1, arg2, arg3, arg4, arg5, outThrown)
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
