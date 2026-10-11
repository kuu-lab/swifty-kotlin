// MARK: - Collection HOF Helpers (STDLIB-005)

typealias RuntimeCollectionLambda1 = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias RuntimeCollectionLambda2 = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias RuntimeCollectionLambda3 = @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias RuntimeCollectionLambda4 = @convention(c) (Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
/// Writes a thrown payload when the caller provided an out-thrown slot.
func runtimeSetThrown(_ outThrown: UnsafeMutablePointer<Int>?, _ value: Int) {
    outThrown?.pointee = value
}

/// Sets `NoSuchElementException` on the thrown channel. Used by iterator `next()`
/// after the iteration is exhausted so callers do not observe a silent `0`.
func runtimeThrowIteratorExhausted(
    _ outThrown: UnsafeMutablePointer<Int>?,
    message: String = "Iterator contains no more elements."
) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: message))
    return 0
}

/// Normalizes truthiness for predicates from raw/boxed Boolean values.
func runtimeCollectionBool(_ value: Int) -> Bool {
    kk_unbox_bool(value) != 0
}

@inline(__always)
func runtimeInvokeCollectionLambda1(
    fnPtr: Int,
    closureRaw: Int,
    value: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let pair = runtimeResolveClosureInvocation(fnPtr: fnPtr, closureRaw: closureRaw, arity: 1, outThrown: outThrown) else { return 0 }
    let fn = unsafeBitCast(pair.fnPtr, to: RuntimeCollectionLambda1.self)
    return fn(
        maybeUnbox(pair.closureRaw),
        pair.preservesBoxes ? value : maybeUnbox(value),
        outThrown
    )
}

/// Like `runtimeInvokeCollectionLambda1`, but tolerates `fnPtr` arriving as a
/// `kk_function_create_1`-wrapped function-value handle instead of a raw,
/// directly-callable function pointer.
///
/// `Sequence<T>.chunked(size, transform)` / `.windowed(..., transform)` have
/// real Kotlin-source declarations (SequenceWindowChunk.kt) so their
/// `require()`-style validation runs; because they take a function-typed
/// parameter, KIRLoweringDriver's auto-inline heuristic
/// (`hasLambdaParam && !isSuspend`) always inlines their body at the call
/// site. `materializeSourceBackedFunctionValueArguments` wraps the caller's
/// lambda via `kk_function_create_1` before that inlining substitutes it in,
/// since from the *caller's* perspective this looks like an ordinary
/// function-value parameter. The inlined body then forwards that already-
/// wrapped handle straight to this native bridge via
/// `splitCallableLambdaArgument`, whose fallback (no compile-time
/// `callableValueInfo` exists for a plain forwarded parameter) assumes an
/// unrecognized value is already a raw callable and pairs it with a literal
/// `0` closureRaw. Unwrapping here — the same `RuntimeFunctionValueBox`
/// detection `kk_function_invoke` already relies on — makes the lazy/eager
/// invocation robust to either calling convention without having to teach
/// every KIR argument-adaptation path about this one forwarding pattern.
@inline(__always)
func runtimeInvokeCollectionLambda1MaybeWrapped(
    fnPtr: Int,
    closureRaw: Int,
    value: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeFunctionValueBox(from: fnPtr) {
        return runtimeInvokeCollectionLambda1(
            fnPtr: box.fnPtr,
            closureRaw: box.closureRaw,
            value: value,
            outThrown: outThrown
        )
    }
    return runtimeInvokeCollectionLambda1(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        value: value,
        outThrown: outThrown
    )
}

/// Like `runtimeInvokeCollectionLambda1`, but leaves `value` boxed for statically-`Any` lambda parameters (LambdaLowerer unboxes concrete-primitive ones itself).
@inline(__always)
func runtimeInvokeCollectionLambda1PreservingBox(
    fnPtr: Int,
    closureRaw: Int,
    value: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let pair = runtimeResolveClosureInvocation(fnPtr: fnPtr, closureRaw: closureRaw, arity: 1, outThrown: outThrown) else { return 0 }
    let fn = unsafeBitCast(pair.fnPtr, to: RuntimeCollectionLambda1.self)
    return fn(maybeUnbox(pair.closureRaw), value, outThrown)
}

@inline(__always)
func runtimeInvokeCollectionLambda2(
    fnPtr: Int,
    closureRaw: Int,
    lhs: Int,
    rhs: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let pair = runtimeResolveClosureInvocation(fnPtr: fnPtr, closureRaw: closureRaw, arity: 2, outThrown: outThrown) else { return 0 }
    let fn = unsafeBitCast(pair.fnPtr, to: RuntimeCollectionLambda2.self)
    return fn(
        maybeUnbox(pair.closureRaw),
        pair.preservesBoxes ? lhs : maybeUnbox(lhs),
        pair.preservesBoxes ? rhs : maybeUnbox(rhs),
        outThrown
    )
}

@inline(__always)
func runtimeInvokeCollectionLambda3(
    fnPtr: Int,
    closureRaw: Int,
    arg1: Int,
    arg2: Int,
    arg3: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let pair = runtimeResolveClosureInvocation(fnPtr: fnPtr, closureRaw: closureRaw, arity: 3, outThrown: outThrown) else { return 0 }
    let fn = unsafeBitCast(pair.fnPtr, to: RuntimeCollectionLambda3.self)
    return fn(
        maybeUnbox(pair.closureRaw),
        pair.preservesBoxes ? arg1 : maybeUnbox(arg1),
        pair.preservesBoxes ? arg2 : maybeUnbox(arg2),
        pair.preservesBoxes ? arg3 : maybeUnbox(arg3),
        outThrown
    )
}

@inline(__always)
func runtimeInvokeCollectionLambda4(
    fnPtr: Int,
    closureRaw: Int,
    arg1: Int,
    arg2: Int,
    arg3: Int,
    arg4: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let pair = runtimeResolveClosureInvocation(fnPtr: fnPtr, closureRaw: closureRaw, arity: 4, outThrown: outThrown) else { return 0 }
    let fn = unsafeBitCast(pair.fnPtr, to: RuntimeCollectionLambda4.self)
    return fn(
        maybeUnbox(pair.closureRaw),
        pair.preservesBoxes ? arg1 : maybeUnbox(arg1),
        pair.preservesBoxes ? arg2 : maybeUnbox(arg2),
        pair.preservesBoxes ? arg3 : maybeUnbox(arg3),
        pair.preservesBoxes ? arg4 : maybeUnbox(arg4),
        outThrown
    )
}

@inline(__always)
func runtimeInvokeClosureThunk(
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let pair = runtimeResolveClosureInvocation(fnPtr: fnPtr, closureRaw: closureRaw, arity: 0, outThrown: outThrown) else { return 0 }
    let fn = unsafeBitCast(pair.fnPtr, to: KKClosureThunkEntryPoint.self)
    return fn(pair.closureRaw, outThrown)
}

/// Like `runtimeInvokeClosureThunk`, but tolerates `fnPtr` arriving as a
/// `kk_function_create_0`-wrapped function-value handle instead of a raw,
/// directly-callable function pointer — see `resolveFunctionValuePair`. Kept
/// as a defensive pairing for zero-arg native bridges alongside
/// `kk_worker_execute`'s job half (see the comment at its call site), which
/// is the confirmed instance of this ABI boundary receiving a wrapped
/// handle.
@inline(__always)
func runtimeInvokeClosureThunkMaybeWrapped(
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let resolved = resolveFunctionValuePair(fnPtr: fnPtr, closureRaw: closureRaw)
    return runtimeInvokeClosureThunk(fnPtr: resolved.fnPtr, closureRaw: resolved.closureRaw, outThrown: outThrown)
}
