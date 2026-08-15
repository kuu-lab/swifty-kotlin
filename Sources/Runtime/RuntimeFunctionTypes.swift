
// MARK: - ランタイム関数型操作

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

private func runtimeFunctionInvokeInvalidArity(expected: Int, actual: Int) -> Int {
    runtimeAllocateThrowable(message: "Function invoke arity mismatch: expected \(expected), got \(actual)")
}

@_cdecl("kk_function_invoke")
public func kk_function_invoke(
    _ functionRaw: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeFunctionValueBox(from: functionRaw) {
        guard box.arity == 1 else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: 1, actual: box.arity)
            return 0
        }
        let function = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint1.self)
        return function(box.closureRaw, arg, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint1.self)
    return function(arg, outThrown)
}

@_cdecl("kk_function_invoke_0")
public func kk_function_invoke_0(
    _ functionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeFunctionValueBox(from: functionRaw) {
        guard box.arity == 0 else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: 0, actual: box.arity)
            return 0
        }
        let function = unsafeBitCast(box.fnPtr, to: KKClosureThunkEntryPoint.self)
        return function(box.closureRaw, outThrown)
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
    if let box = runtimeFunctionValueBox(from: functionRaw) {
        guard box.arity == 2 else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: 2, actual: box.arity)
            return 0
        }
        let function = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint2.self)
        return function(box.closureRaw, arg1, arg2, outThrown)
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
    if let box = runtimeFunctionValueBox(from: functionRaw) {
        guard box.arity == 3 else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: 3, actual: box.arity)
            return 0
        }
        let function = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint3.self)
        return function(box.closureRaw, arg1, arg2, arg3, outThrown)
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
    if let box = runtimeFunctionValueBox(from: functionRaw) {
        guard box.arity == 4 else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: 4, actual: box.arity)
            return 0
        }
        let function = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint4.self)
        return function(box.closureRaw, arg1, arg2, arg3, arg4, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint4.self)
    return function(arg1, arg2, arg3, arg4, outThrown)
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
    if let existing = runtimeFunctionValueBox(from: bodyRaw), existing.arity == 0 {
        return bodyRaw
    }
    guard bodyRaw != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid function body")
        return 0
    }
    return registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: bodyRaw, closureRaw: closureRaw, arity: 0))
}

@_cdecl("kk_function_create_1")
public func kk_function_create_1(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let existing = runtimeFunctionValueBox(from: bodyRaw), existing.arity == 1 {
        return bodyRaw
    }
    guard bodyRaw != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid function body")
        return 0
    }
    return registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: bodyRaw, closureRaw: closureRaw, arity: 1))
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
    runtimeFunctionValueBox(from: functionRaw)?.fnPtr ?? functionRaw
}

@_cdecl("kk_function_value_closure_raw")
public func kk_function_value_closure_raw(_ functionRaw: Int) -> Int {
    runtimeFunctionValueBox(from: functionRaw)?.closureRaw ?? 0
}

@_cdecl("kk_function_create_2")
public func kk_function_create_2(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let existing = runtimeFunctionValueBox(from: bodyRaw), existing.arity == 2 {
        return bodyRaw
    }
    guard bodyRaw != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid function body")
        return 0
    }
    return registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: bodyRaw, closureRaw: closureRaw, arity: 2))
}

@_cdecl("kk_function_create_3")
public func kk_function_create_3(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let existing = runtimeFunctionValueBox(from: bodyRaw), existing.arity == 3 {
        return bodyRaw
    }
    guard bodyRaw != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid function body")
        return 0
    }
    return registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: bodyRaw, closureRaw: closureRaw, arity: 3))
}

@_cdecl("kk_function_create_4")
public func kk_function_create_4(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let existing = runtimeFunctionValueBox(from: bodyRaw), existing.arity == 4 {
        return bodyRaw
    }
    guard bodyRaw != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid function body")
        return 0
    }
    return registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: bodyRaw, closureRaw: closureRaw, arity: 4))
}
