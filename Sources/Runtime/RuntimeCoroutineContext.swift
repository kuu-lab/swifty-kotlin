import Dispatch
import Foundation

// `CoroutineContext` element runtime (STDLIB-CORO-077) and the
// coroutine dispatcher scheduler (STDLIB-133).
//
// Split out from `RuntimeCoroutine.swift`.

// MARK: - CoroutineContext Elements (STDLIB-CORO-077)

private let runtimeCoroutineContextInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.coroutines.CoroutineContext"
)

private let runtimeEmptyCoroutineContextTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.coroutines.EmptyCoroutineContext"
)

/// A coroutine context is a keyed collection of context elements.
/// Elements include: dispatcher, Job, CoroutineName, CoroutineExceptionHandler.
/// Contexts compose via the `+` operator (right-hand side wins for same key).
final class RuntimeCoroutineContext: @unchecked Sendable {
    var dispatcher: Int  // 0 means "inherit from parent"
    var dispatcherHandleRaw: Int
    var name: String?
    var nameHandleRaw: Int
    var exceptionHandler: RuntimeExceptionHandlerBox?
    var jobHandleRaw: Int

    /// Context operations expose the original element; scheduling uses its tag.
    var dispatcherElementHandle: Int {
        dispatcherHandleRaw != 0 ? dispatcherHandleRaw : dispatcher
    }

    init(
        dispatcher: Int = 0,
        name: String? = nil,
        exceptionHandler: RuntimeExceptionHandlerBox? = nil,
        jobHandleRaw: Int = 0,
        nameHandleRaw: Int = 0,
        dispatcherHandleRaw: Int = 0
    ) {
        self.dispatcher = dispatcher
        self.dispatcherHandleRaw = dispatcherHandleRaw
        self.name = name
        self.nameHandleRaw = nameHandleRaw != 0 ? nameHandleRaw
            : name.map { runtimeRegisterObject(RuntimeCoroutineNameBox(name: $0)) } ?? 0
        self.exceptionHandler = exceptionHandler
        self.jobHandleRaw = jobHandleRaw
    }

    /// Merge another context into this one. Right-hand side wins for duplicate keys.
    func plus(_ other: RuntimeCoroutineContext) -> RuntimeCoroutineContext {
        // The dispatcher/interceptor slot is occupied whenever the other
        // context carries a dispatcher — a scheduler tag or an element object
        // with no tag (e.g. a runBlocking event loop, KUU-1395) — so
        // `ctx + element` replaces it like kotlinx's `+` does.
        let otherHasDispatcher = other.dispatcherElementHandle != 0
        return RuntimeCoroutineContext(
            dispatcher: otherHasDispatcher ? other.dispatcher : self.dispatcher,
            name: other.name ?? self.name,
            exceptionHandler: other.exceptionHandler ?? self.exceptionHandler,
            jobHandleRaw: other.jobHandleRaw != 0 ? other.jobHandleRaw : self.jobHandleRaw,
            nameHandleRaw: other.name != nil ? other.nameHandleRaw : self.nameHandleRaw,
            dispatcherHandleRaw: otherHasDispatcher ? other.dispatcherHandleRaw : self.dispatcherHandleRaw
        )
    }
}

/// KUU-1387: content identity of a `CoroutineContext` object. Ambient-context
/// readers (`coroutineContext`, `currentCoroutineContext()`,
/// `continuation.context`) must return the same object whenever the same
/// logical context is in force — Kotlin's property contract returns the
/// continuation's one fixed context on every access (JVM), so repeated reads
/// are `===`- and `==`-stable.
private struct RuntimeCoroutineContextIdentity: Hashable {
    let dispatcher: Int
    let dispatcherHandleRaw: Int
    let name: String?
    let nameHandleRaw: Int
    let exceptionHandlerRaw: Int
    let jobHandleRaw: Int

    init(
        dispatcher: Int,
        dispatcherHandleRaw: Int,
        name: String?,
        nameHandleRaw: Int,
        exceptionHandler: RuntimeExceptionHandlerBox?,
        jobHandleRaw: Int
    ) {
        self.dispatcher = dispatcher
        self.dispatcherHandleRaw = dispatcherHandleRaw
        self.name = name
        self.nameHandleRaw = nameHandleRaw
        self.exceptionHandlerRaw = exceptionHandler.map {
            Int(bitPattern: Unmanaged.passUnretained($0).toOpaque())
        } ?? 0
        self.jobHandleRaw = jobHandleRaw
    }

    init(_ context: RuntimeCoroutineContext) {
        self.init(
            dispatcher: context.dispatcher,
            dispatcherHandleRaw: context.dispatcherHandleRaw,
            name: context.name,
            nameHandleRaw: context.nameHandleRaw,
            exceptionHandler: context.exceptionHandler,
            jobHandleRaw: context.jobHandleRaw
        )
    }
}

private struct RuntimeWeakCoroutineContext {
    weak var context: RuntimeCoroutineContext?
}

/// Canonicalizes `RuntimeCoroutineContext` objects by content identity so every
/// read of an equal ambient context resolves to the same registered object.
/// Weak entries let contexts die with their last handle (registered objects are
/// retained by `runtimeRegisterObject`, so an entry outlives its consumers in
/// practice and only a never-registered context can drop out early).
private final class RuntimeCoroutineContextCanonicalizer: @unchecked Sendable {
    static let shared = RuntimeCoroutineContextCanonicalizer()

    private let lock = NSLock()
    private var contexts: [RuntimeCoroutineContextIdentity: RuntimeWeakCoroutineContext] = [:]

    func canonical(_ context: RuntimeCoroutineContext) -> RuntimeCoroutineContext {
        let key = RuntimeCoroutineContextIdentity(context)
        lock.lock()
        defer { lock.unlock() }
        if let cached = contexts[key]?.context {
            return cached
        }
        contexts[key] = RuntimeWeakCoroutineContext(context: context)
        return context
    }

    func canonical(
        dispatcher: Int,
        dispatcherHandleRaw: Int,
        name: String?,
        nameHandleRaw: Int,
        exceptionHandler: RuntimeExceptionHandlerBox?,
        jobHandleRaw: Int
    ) -> RuntimeCoroutineContext {
        let key = RuntimeCoroutineContextIdentity(
            dispatcher: dispatcher,
            dispatcherHandleRaw: dispatcherHandleRaw,
            name: name,
            nameHandleRaw: nameHandleRaw,
            exceptionHandler: exceptionHandler,
            jobHandleRaw: jobHandleRaw
        )
        lock.lock()
        defer { lock.unlock() }
        if let cached = contexts[key]?.context {
            return cached
        }
        let context = RuntimeCoroutineContext(
            dispatcher: dispatcher,
            name: name,
            exceptionHandler: exceptionHandler,
            jobHandleRaw: jobHandleRaw,
            nameHandleRaw: nameHandleRaw,
            dispatcherHandleRaw: dispatcherHandleRaw
        )
        contexts[key] = RuntimeWeakCoroutineContext(context: context)
        return context
    }
}

/// The canonical object for `context`'s content — `context` itself when it is
/// the first object registered under that identity.
func runtimeCanonicalCoroutineContext(_ context: RuntimeCoroutineContext) -> RuntimeCoroutineContext {
    RuntimeCoroutineContextCanonicalizer.shared.canonical(context)
}

/// The canonical object for the given content, creating it only on a miss so
/// repeated `coroutineContext` reads on an unchanged context allocate nothing.
func runtimeCanonicalCoroutineContext(
    dispatcher: Int,
    dispatcherHandleRaw: Int,
    name: String?,
    nameHandleRaw: Int,
    exceptionHandler: RuntimeExceptionHandlerBox?,
    jobHandleRaw: Int
) -> RuntimeCoroutineContext {
    RuntimeCoroutineContextCanonicalizer.shared.canonical(
        dispatcher: dispatcher,
        dispatcherHandleRaw: dispatcherHandleRaw,
        name: name,
        nameHandleRaw: nameHandleRaw,
        exceptionHandler: exceptionHandler,
        jobHandleRaw: jobHandleRaw
    )
}

/// A CoroutineName element wrapping a String name.
final class RuntimeCoroutineNameBox: @unchecked Sendable {
    let name: String
    init(name: String) {
        self.name = name
    }
}

private final class RuntimeCoroutineNameKey: @unchecked Sendable {}
private let runtimeCoroutineNameKeyRaw = runtimeRegisterObject(RuntimeCoroutineNameKey())

/// KUU-1386: singleton backing `Job.Key` (`kk_job_key`). Mirroring
/// CoroutineName's key, `Job`/`Job.Key` expressions evaluate to this object so
/// `job.key == Job` is true and `ctx[Job]`/`ctx.minusKey(Job)` resolve the
/// context's stored job handle.
private final class RuntimeJobKey: @unchecked Sendable {}
private let runtimeJobKeyRaw = runtimeRegisterObject(RuntimeJobKey())

@_cdecl("kk_job_key")
public func kk_job_key() -> Int {
    runtimeJobKeyRaw
}

/// KUU-1395: singletons backing `ContinuationInterceptor.Key` /
/// `CoroutineDispatcher.Key` (`kk_continuation_interceptor_key` /
/// `kk_coroutine_dispatcher_key`). Mirroring `Job.Key`, the source companions
/// evaluate to these objects so `ctx[ContinuationInterceptor]` /
/// `ctx[CoroutineDispatcher]` resolve the context's dispatcher element — for
/// a `runBlocking` coroutine, its event loop.
private final class RuntimeContinuationInterceptorKey: @unchecked Sendable {}
private let runtimeContinuationInterceptorKeyRaw = runtimeRegisterObject(RuntimeContinuationInterceptorKey())

private final class RuntimeCoroutineDispatcherKey: @unchecked Sendable {}
private let runtimeCoroutineDispatcherKeyRaw = runtimeRegisterObject(RuntimeCoroutineDispatcherKey())

@_cdecl("kk_continuation_interceptor_key")
public func kk_continuation_interceptor_key() -> Int {
    runtimeContinuationInterceptorKeyRaw
}

@_cdecl("kk_coroutine_dispatcher_key")
public func kk_coroutine_dispatcher_key() -> Int {
    runtimeCoroutineDispatcherKeyRaw
}

@_cdecl("kk_coroutine_name_key")
public func kk_coroutine_name_key() -> Int {
    runtimeCoroutineNameKeyRaw
}

@_cdecl("kk_coroutine_name_key_get")
public func kk_coroutine_name_key_get(_ receiver: Int) -> Int {
    runtimeCoroutineNameKeyRaw
}

func runtimeCoroutineContextElementMethod(_ receiver: Int, _ interfaceTypeID: Int, _ methodSlot: Int) -> Int? {
    // Element declares get/fold/minusKey; its key getter follows those slots.
    guard interfaceTypeID == Int(runtimeStableNominalTypeID(fqName: "kotlin.coroutines.CoroutineContext.Element")) else {
        return nil
    }
    let ptr = isRegisteredRuntimeObjectPointer(receiver) ? UnsafeMutableRawPointer(bitPattern: receiver) : nil
    let isName = ptr.flatMap { tryCast($0, to: RuntimeCoroutineNameBox.self) } != nil
    let isDispatcher = isDispatcherTag(receiver) || ptr.flatMap { tryCast($0, to: RuntimeDispatcher.self) } != nil
    guard isName || isDispatcher else {
        return nil
    }
    switch methodSlot {
    case 0:
        let get: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { receiver, key, outThrown in
            outThrown?.pointee = 0
            let element = kk_context_get(receiver, key)
            return element == 0 ? runtimeNullSentinelInt : element
        }
        return unsafeBitCast(get, to: Int.self)
    case 1:
        let fold: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
            receiver, initial, operation, closure, outThrown in
            outThrown?.pointee = 0
            return kk_context_fold(receiver, initial, operation, closure, outThrown)
        }
        return unsafeBitCast(fold, to: Int.self)
    case 2:
        let minusKey: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { receiver, key, outThrown in
            outThrown?.pointee = 0
            return kk_context_minusKey(receiver, key)
        }
        return unsafeBitCast(minusKey, to: Int.self)
    case 3 where isName:
        let getter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { receiver, outThrown in
            outThrown?.pointee = 0
            return kk_coroutine_name_key_get(receiver)
        }
        return unsafeBitCast(getter, to: Int.self)
    case 3:
        // KUU-1395: a dispatcher/interceptor element's `key` is
        // ContinuationInterceptor.Key — kotlinx's CoroutineDispatcher passes
        // it to AbstractCoroutineContextElement's constructor.
        let getter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
            outThrown?.pointee = 0
            return kk_continuation_interceptor_key()
        }
        return unsafeBitCast(getter, to: Int.self)
    default:
        return nil
    }
}

/// Register a heap-allocated object in the runtime storage so it is not GC'd.
func runtimeRegisterObject<T: AnyObject>(_ object: T) -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(object).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Create a CoroutineName context element.
/// nameRaw is a pointer to a runtime string (RuntimeStringBox or interned).
@_cdecl("kk_coroutine_name_create")
public func kk_coroutine_name_create(_ nameRaw: Int) -> Int {
    let nameStr: String
    if nameRaw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw) {
        if let stringBox = tryCast(ptr, to: RuntimeStringBox.self) {
            nameStr = stringBox.value
        } else {
            nameStr = "coroutine"
        }
    } else {
        nameStr = "coroutine"
    }
    let box = RuntimeCoroutineNameBox(name: nameStr)
    return runtimeRegisterObject(box)
}

/// Get the name string from a CoroutineName handle.
/// Returns a RuntimeStringBox pointer.
@_cdecl("kk_coroutine_name_get")
public func kk_coroutine_name_get(_ handleRaw: Int) -> Int {
    guard handleRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: handleRaw),
          let nameBox = tryCast(ptr, to: RuntimeCoroutineNameBox.self)
    else {
        let emptyBox = RuntimeStringBox("")
        return runtimeRegisterObject(emptyBox)
    }
    let resultBox = RuntimeStringBox(nameBox.name)
    return runtimeRegisterObject(resultBox)
}

/// Create a CoroutineExceptionHandler from a function value.
/// KUU-CORO-101: this is a *synthetic* top-level function
/// (registerSyntheticCoroutineTopLevelFunction in
/// HeaderHelpers+SyntheticCoroutineRegistry.swift), confirmed via `--emit kir`
/// to pass the 2-arg Kotlin lambda `{ context, exception -> ... }` as a
/// single combined value -- resolved the same way `kk_function_invoke_2`
/// resolves any Kotlin function value (bare capture-free pointer, or a
/// `kk_function_create_N`-wrapped box). See
/// [[function-type-param-abi-split-convention]]: a *bundled* `external fun`
/// with a function-type parameter (e.g. `__kk_job_invoke_on_completion` in
/// Job.kt) instead crosses as a split (fnPtr, closureRaw) pair -- do not
/// confuse the two conventions. Previously this bitcast `handlerFnPtr`
/// directly to a 1-arg entry point and called it with only the exception,
/// which is wrong on two counts: it silently dropped the closure environment
/// (so a handler that captured locals would read garbage) and the context
/// argument. If the function pointer is invalid, the handler falls back to
/// printing the exception to stderr.
@_cdecl("kk_exception_handler_create")
public func kk_exception_handler_create(_ handlerFnPtr: Int) -> Int {
    let capturedFnPtr = handlerFnPtr
    let box = RuntimeExceptionHandlerBox { contextRaw, throwableRaw in
        if capturedFnPtr != 0 {
            _ = kk_function_invoke_2(capturedFnPtr, contextRaw, throwableRaw, nil)
        } else {
            var message = "Unknown exception"
            if throwableRaw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: throwableRaw) {
                if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
                    message = throwable.message ?? "Throwable"
                } else if let cancellation = tryCast(ptr, to: RuntimeCancellationBox.self) {
                    message = cancellation.message ?? "CancellationException"
                }
            }
            FileHandle.standardError.write(Data("CoroutineExceptionHandler: \(message)\n".utf8))
        }
    }
    return runtimeRegisterObject(box)
}

/// Invoke a CoroutineExceptionHandler with a context and exception.
@_cdecl("kk_exception_handler_invoke")
public func kk_exception_handler_invoke(_ handlerRaw: Int, _ contextRaw: Int, _ exceptionRaw: Int) {
    guard handlerRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: handlerRaw),
          let handler = tryCast(ptr, to: RuntimeExceptionHandlerBox.self)
    else {
        return
    }
    handler.handler(contextRaw, exceptionRaw)
}

/// Compose two CoroutineContext elements using the + operator.
/// Each argument can be a RuntimeCoroutineContext, a dispatcher tag,
/// a RuntimeCoroutineNameBox, or a RuntimeExceptionHandlerBox.
@_cdecl("kk_context_plus")
public func kk_context_plus(_ leftRaw: Int, _ rightRaw: Int) -> Int {
    // The source-backed empty singleton is the identity on either side.
    // Preserve the operand itself before converting to the runtime's closed
    // element representation, which cannot retain arbitrary source Elements.
    if runtimeObjectTypeID(rawValue: rightRaw) == runtimeEmptyCoroutineContextTypeID {
        return leftRaw
    }
    if runtimeObjectTypeID(rawValue: leftRaw) == runtimeEmptyCoroutineContextTypeID {
        return rightRaw
    }
    let leftCtx = resolveToCoroutineContext(leftRaw)
    let rightCtx = resolveToCoroutineContext(rightRaw)
    let merged = leftCtx.plus(rightCtx)
    return runtimeRegisterObject(merged)
}

/// Preserve Kotlin overrides while retaining native context composition.
@_cdecl("__kk_context_plus_dispatch")
public func __kk_context_plus_dispatch(
    _ contextRaw: Int,
    _ otherRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    // An Element without a plus override inherits this bodyless bridge.
    // Its itable entry must use native composition rather than re-enter us.
    let bridge: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = __kk_context_plus_dispatch
    let method = kk_itable_lookup_dynamic(contextRaw, Int(runtimeCoroutineContextInterfaceTypeID), 2)
    if method != unsafeBitCast(bridge, to: Int.self), let result = runtimeSourceInterfaceCall1(
        contextRaw, otherRaw,
        interfaceTypeID: runtimeCoroutineContextInterfaceTypeID,
        methodSlot: 2,
        context: "CoroutineContext.plus dispatch",
        outThrown: outThrown
    ) {
        return result
    }
    return kk_context_plus(contextRaw, otherRaw)
}

/// Fetch a context element by key.
/// The current runtime recognizes the closed set of coroutine element handles
/// already modeled in RuntimeCoroutineContext.
@_cdecl("kk_context_get")
public func kk_context_get(_ contextRaw: Int, _ keyRaw: Int) -> Int {
    let ctx = resolveToCoroutineContext(contextRaw)
    if let match = runtimeCoroutineContextElementHandle(for: keyRaw, in: ctx) {
        return match
    }
    return 0
}

@_cdecl("__kk_context_get_dispatch")
public func __kk_context_get_dispatch(
    _ contextRaw: Int,
    _ keyRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    if let result = runtimeSourceInterfaceCall1(
        contextRaw, keyRaw,
        interfaceTypeID: runtimeCoroutineContextInterfaceTypeID,
        methodSlot: 0,
        context: "CoroutineContext.get dispatch",
        outThrown: outThrown
    ) {
        return result
    }
    let result = kk_context_get(contextRaw, keyRaw)
    return result == 0 ? runtimeNullSentinelInt : result
}

/// Fold the known coroutine context elements from left to right.
@_cdecl("kk_context_fold")
public func kk_context_fold(
    _ contextRaw: Int,
    _ initial: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    // Source methods receive a Kotlin function value, whereas the bridge ABI
    // receives the callback entry point and its captured environment separately.
    if kk_itable_lookup_dynamic(contextRaw, Int(runtimeCoroutineContextInterfaceTypeID), 1) != 0 {
        let operation = kk_function_create_2(fnPtr, closureRaw, outThrown)
        if let result = runtimeSourceInterfaceCall2(
            contextRaw, initial, operation,
            interfaceTypeID: runtimeCoroutineContextInterfaceTypeID,
            methodSlot: 1,
            context: "CoroutineContext.fold dispatch",
            outThrown: outThrown
        ) {
            return result
        }
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    let ctx = resolveToCoroutineContext(contextRaw)
    var acc = initial
    for elementRaw in runtimeCoroutineContextElementHandles(in: ctx) {
        var thrown = 0
        let result = lambda(closureRaw, acc, elementRaw, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return acc
        }
        acc = maybeUnbox(result)
    }
    return acc
}

/// Remove a context element by key.
@_cdecl("kk_context_minusKey")
public func kk_context_minusKey(_ contextRaw: Int, _ keyRaw: Int) -> Int {
    let resolved = resolveToCoroutineContext(contextRaw)
    let reduced = runtimeCoroutineContextRemovingElement(for: keyRaw, from: resolved)
    return runtimeRegisterObject(reduced)
}

@_cdecl("__kk_context_minusKey_dispatch")
public func __kk_context_minusKey_dispatch(
    _ contextRaw: Int,
    _ keyRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    if let result = runtimeSourceInterfaceCall1(
        contextRaw, keyRaw,
        interfaceTypeID: runtimeCoroutineContextInterfaceTypeID,
        methodSlot: 3,
        context: "CoroutineContext.minusKey dispatch",
        outThrown: outThrown
    ) {
        return result
    }
    return kk_context_minusKey(contextRaw, keyRaw)
}

/// Extract the dispatcher from a CoroutineContext.
/// Returns a dispatcher tag (or 0 if none).
@_cdecl("kk_context_get_dispatcher")
public func kk_context_get_dispatcher(_ contextRaw: Int) -> Int {
    if isDispatcherTag(contextRaw) {
        return contextRaw
    }
    if contextRaw != 0,
       isRegisteredRuntimeObjectPointer(contextRaw),
       let ptr = UnsafeMutableRawPointer(bitPattern: contextRaw),
       let ctx = tryCast(ptr, to: RuntimeCoroutineContext.self)
    {
        return ctx.dispatcher
    }
    if isRegisteredRuntimeObjectPointer(contextRaw),
       let ptr = UnsafeMutableRawPointer(bitPattern: contextRaw),
       let dispatcher = tryCast(ptr, to: RuntimeDispatcher.self) {
        return dispatcher.tag
    }
    return 0
}

/// Intercept compiler-created states, leaving ordinary source continuations untouched.
@_cdecl("__kk_continuation_intercepted")
public func __kk_continuation_intercepted(
    _ continuationRaw: Int,
    _ interceptorKey: Int = 0,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    outThrown?.pointee = 0
    if let state = runtimeContinuationState(from: continuationRaw) {
        return state.intercepted(continuationRaw: continuationRaw, interceptorKey: interceptorKey, outThrown: outThrown)
    }
    guard continuationRaw != 0,
          isRegisteredRuntimeObjectPointer(continuationRaw),
          let ptr = UnsafeMutableRawPointer(bitPattern: continuationRaw)
    else {
        return continuationRaw
    }
    let object = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    guard let continuation = object as? KKContinuation else {
        return continuationRaw
    }
    let intercepted = runtimeInterceptedContinuation(continuation)
    let interceptedObject = intercepted as AnyObject
    if interceptedObject === object {
        return continuationRaw
    }
    return runtimeRegisterObject(interceptedObject)
}

func runtimeContinuationInterceptor(context: Int, key: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let getRaw = kk_itable_lookup_dynamic(
        context, Int(runtimeStableNominalTypeID(fqName: "kotlin.coroutines.CoroutineContext")), 0
    )
    if getRaw != 0, key != 0 {
        let get = unsafeBitCast(getRaw, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        let result = get(context, key, outThrown)
        return result == runtimeNullSentinelInt ? 0 : result
    }
    return kk_context_get_dispatcher(context)
}

private final class RuntimeGeneratedContinuation: KKContinuation, @unchecked Sendable {
    let state: RuntimeContinuationState
    let raw: Int

    init(state: RuntimeContinuationState, raw: Int) {
        self.state = state
        self.raw = raw
    }

    var context: UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: __kk_coroutine_continuation_context(raw))
    }

    func resumeWith(_ result: UnsafeMutableRawPointer?) {
        __kk_coroutine_continuation_resume_with(raw, Int(bitPattern: result))
    }
}

func runtimeInterceptGeneratedContinuation(interceptor: Int, continuation: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard interceptor != 0 else {
        return continuation
    }
    let interceptRaw = kk_itable_lookup_dynamic(
        interceptor, Int(runtimeStableNominalTypeID(fqName: "kotlin.coroutines.ContinuationInterceptor")), 0
    )
    guard interceptRaw != 0 else {
        return continuation
    }
    let intercept = unsafeBitCast(interceptRaw, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    return intercept(interceptor, continuation, outThrown)
}

func runtimeReleaseInterceptedContinuation(interceptor: Int, continuation: Int) {
    let releaseRaw = kk_itable_lookup_dynamic(
        interceptor, Int(runtimeStableNominalTypeID(fqName: "kotlin.coroutines.ContinuationInterceptor")), 1
    )
    guard releaseRaw != 0 else {
        return
    }
    let release = unsafeBitCast(releaseRaw, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    _ = release(interceptor, continuation, &thrown)
    if thrown != 0 {
        _ = kk_native_processUnhandledException(thrown, nil)
    }
}

/// Intercept a continuation using an explicit interceptor object.
@_cdecl("kk_continuation_interceptor_intercept_continuation")
public func kk_continuation_interceptor_intercept_continuation(
    _ interceptorRaw: Int,
    _ continuationRaw: Int
) -> Int {
    let dispatcherTag = kk_context_get_dispatcher(interceptorRaw)
    guard dispatcherTag != 0,
          continuationRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: continuationRaw)
    else {
        return continuationRaw
    }
    let continuation: KKContinuation
    if let state = runtimeContinuationState(from: continuationRaw) {
        continuation = RuntimeGeneratedContinuation(state: state, raw: continuationRaw)
    } else {
        guard isRegisteredRuntimeObjectPointer(continuationRaw),
              let native = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? KKContinuation
        else {
            return continuationRaw
        }
        continuation = native
    }
    let intercepted = runtimeInterceptedContinuation(using: dispatcherTag, continuation: continuation)
    let interceptedObject = intercepted as AnyObject
    if interceptedObject === continuation as AnyObject {
        return continuationRaw
    }
    return runtimeRegisterObject(interceptedObject)
}

func runtimeIsNativeDispatcher(_ receiver: Int) -> Bool {
    let isDispatcherObject = isRegisteredRuntimeObjectPointer(receiver)
        && UnsafeMutableRawPointer(bitPattern: receiver).flatMap { tryCast($0, to: RuntimeDispatcher.self) } != nil
    return isDispatcherTag(receiver) || isDispatcherObject
}

@_cdecl("__kk_job_is_runtime")
public func kk_job_is_runtime(_ receiver: Int) -> Int {
    // runtimeJobHandle unwraps bound JobSupport-wrapper boxes (Job(),
    // CompletableDeferred(), ...), so `keyOf(job)` reaches `Job.Key` for them
    // too; unbound source elements fall through to their own `key` getter.
    return runtimeJobHandle(from: receiver) != nil
        || runtimeAsyncTask(from: receiver) != nil ? 1 : 0
}

@_cdecl("__kk_is_native_dispatcher")
public func kk_is_native_dispatcher(_ receiver: Int) -> Int {
    runtimeIsNativeDispatcher(receiver) ? 1 : 0
}

// The compiler supplies the source implementation, not a runtime-owned slot.
@_cdecl("__kk_dispatcher_default_method")
public func kk_dispatcher_default_method(_ receiver: Int, _ virtualMethod: Int, _ defaultMethod: Int) -> Int {
    runtimeIsNativeDispatcher(receiver) ? defaultMethod : virtualMethod
}

func runtimeDispatcherInterceptorMethod(_ receiver: Int, _ interfaceTypeID: Int, _ methodSlot: Int) -> Int? {
    guard interfaceTypeID == Int(runtimeStableNominalTypeID(fqName: "kotlin.coroutines.ContinuationInterceptor")),
          runtimeIsNativeDispatcher(receiver)
    else {
        return nil
    }
    // ContinuationInterceptor declares intercept/release before its context overrides.
    switch methodSlot {
    case 0:
        let intercept: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { receiver, continuation, outThrown in
            outThrown?.pointee = 0
            return kk_continuation_interceptor_intercept_continuation(receiver, continuation)
        }
        return unsafeBitCast(intercept, to: Int.self)
    case 1:
        let release: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
            outThrown?.pointee = 0
            return 0
        }
        return unsafeBitCast(release, to: Int.self)
    default:
        return nil
    }
}

/// Return the raw handle for a known context element matching the supplied key.
private func runtimeCoroutineContextElementHandle(for keyRaw: Int, in ctx: RuntimeCoroutineContext) -> Int? {
    if keyRaw == runtimeCoroutineNameKeyRaw {
        return ctx.name != nil ? ctx.nameHandleRaw : nil
    }
    if keyRaw == runtimeContinuationInterceptorKeyRaw || keyRaw == runtimeCoroutineDispatcherKeyRaw {
        // KUU-1395: `ctx[ContinuationInterceptor]` / `ctx[CoroutineDispatcher]`
        // resolve the context's dispatcher element. A tag-only slot resolves to
        // its dispatcher object so the element answers `is CoroutineDispatcher`.
        let handle = ctx.dispatcherElementHandle
        guard handle != 0 else { return nil }
        return isDispatcherTag(handle) ? runtimeDispatcherObjectHandle(forTag: handle) : handle
    }
    if keyRaw != 0,
       let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
       let dispatcher = tryCast(ptr, to: RuntimeDispatcher.self)
    {
        return ctx.dispatcher == dispatcher.tag ? ctx.dispatcherElementHandle : nil
    }
    if isDispatcherTag(keyRaw) {
        return ctx.dispatcher == keyRaw ? ctx.dispatcherElementHandle : nil
    }
    if keyRaw != 0,
       let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
       let nameBox = tryCast(ptr, to: RuntimeCoroutineNameBox.self)
    {
        return ctx.name == nameBox.name ? ctx.nameHandleRaw : nil
    }
    if keyRaw != 0,
       let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
       tryCast(ptr, to: RuntimeExceptionHandlerBox.self) != nil
    {
        return ctx.exceptionHandler.map { Int(bitPattern: UnsafeMutableRawPointer(Unmanaged.passUnretained($0).toOpaque())) }
    }
    if keyRaw == runtimeJobKeyRaw {
        // KUU-1386: `ctx[Job]` — the Job.Key singleton maps to the stored job.
        return ctx.jobHandleRaw != 0 ? ctx.jobHandleRaw : nil
    }
    if runtimeJobHandle(from: keyRaw) != nil {
        guard ctx.jobHandleRaw == keyRaw else { return nil }
        return keyRaw
    }
    if runtimeAsyncTask(from: keyRaw) != nil {
        guard ctx.jobHandleRaw == keyRaw else { return nil }
        return keyRaw
    }
    return nil
}

/// Return the raw handles for the known elements stored in the context.
private func runtimeCoroutineContextElementHandles(in ctx: RuntimeCoroutineContext) -> [Int] {
    var handles: [Int] = []
    // KUU-1395: the dispatcher slot is also occupied by handle-only elements
    // (the runBlocking event loop), and a tag-only slot folds as its
    // dispatcher object.
    let dispatcherHandle = ctx.dispatcherElementHandle
    if dispatcherHandle != 0 {
        handles.append(
            isDispatcherTag(dispatcherHandle)
                ? runtimeDispatcherObjectHandle(forTag: dispatcherHandle)
                : dispatcherHandle
        )
    }
    if ctx.name != nil {
        handles.append(ctx.nameHandleRaw)
    }
    if let handler = ctx.exceptionHandler {
        handles.append(Int(bitPattern: UnsafeMutableRawPointer(Unmanaged.passUnretained(handler).toOpaque())))
    }
    if ctx.jobHandleRaw != 0 {
        handles.append(ctx.jobHandleRaw)
    }
    return handles
}

/// Remove any known element that matches the supplied key handle.
private func runtimeCoroutineContextRemovingElement(for keyRaw: Int, from ctx: RuntimeCoroutineContext) -> RuntimeCoroutineContext {
    let next = RuntimeCoroutineContext(
        dispatcher: ctx.dispatcher,
        name: ctx.name,
        exceptionHandler: ctx.exceptionHandler,
        jobHandleRaw: ctx.jobHandleRaw,
        nameHandleRaw: ctx.nameHandleRaw,
        dispatcherHandleRaw: ctx.dispatcherHandleRaw
    )
    if keyRaw == runtimeCoroutineNameKeyRaw {
        next.name = nil
        next.nameHandleRaw = 0
        return next
    }
    if keyRaw == runtimeContinuationInterceptorKeyRaw || keyRaw == runtimeCoroutineDispatcherKeyRaw {
        // KUU-1395: `ctx.minusKey(ContinuationInterceptor)` drops the
        // dispatcher element (the runBlocking event loop included).
        next.dispatcher = 0
        next.dispatcherHandleRaw = 0
        return next
    }
    if keyRaw != 0,
       let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
       let dispatcher = tryCast(ptr, to: RuntimeDispatcher.self)
    {
        if next.dispatcher == dispatcher.tag {
            next.dispatcher = 0
            next.dispatcherHandleRaw = 0
        }
        return next
    }
    if isDispatcherTag(keyRaw) {
        if next.dispatcher == keyRaw {
            next.dispatcher = 0
            next.dispatcherHandleRaw = 0
        }
        return next
    }
    if keyRaw != 0,
       let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
       let nameBox = tryCast(ptr, to: RuntimeCoroutineNameBox.self)
    {
        if next.name == nameBox.name {
            next.name = nil
            next.nameHandleRaw = 0
        }
        return next
    }
    if keyRaw != 0,
       let ptr = UnsafeMutableRawPointer(bitPattern: keyRaw),
       let handler = tryCast(ptr, to: RuntimeExceptionHandlerBox.self)
    {
        if next.exceptionHandler === handler {
            next.exceptionHandler = nil
        }
        return next
    }
    if keyRaw == runtimeJobKeyRaw {
        // KUU-1386: `ctx.minusKey(Job)` — drop the stored job element.
        next.jobHandleRaw = 0
        return next
    }
    if runtimeJobHandle(from: keyRaw) != nil {
        if next.jobHandleRaw == keyRaw {
            next.jobHandleRaw = 0
        }
        return next
    }
    return next
}

/// `kotlinx.coroutines.isActive` extension on CoroutineContext: `this[Job]?.isActive ?: true`.
@_cdecl("kk_context_is_active")
public func kk_context_is_active(_ contextRaw: Int) -> Int {
    let ctx = resolveToCoroutineContext(contextRaw)
    guard let job = runtimeJobHandle(from: ctx.jobHandleRaw)
        ?? runtimeAsyncTask(from: ctx.jobHandleRaw)?.completionJob else {
        return 1 // No Job element: kotlinx.coroutines treats this as active.
    }
    return job.isActiveSnapshot() ? 1 : 0
}

/// KUU-CORO-101: ABI backing for the `CoroutineContext.job` extension
/// (`kotlinx.coroutines.job`). Returns the Job element's raw handle, or 0 if
/// the context has none -- the Kotlin wrapper (`Job.kt`) treats 0 as "no Job
/// element" and throws, matching real kotlinx.coroutines' `error(...)`.
@_cdecl("kk_context_get_job")
public func kk_context_get_job(_ contextRaw: Int) -> Int {
    let ctx = resolveToCoroutineContext(contextRaw)
    return ctx.jobHandleRaw
}

/// Extract the CoroutineName from a CoroutineContext.
/// Returns a RuntimeStringBox pointer (or 0 if no name).
@_cdecl("kk_context_get_name")
public func kk_context_get_name(_ contextRaw: Int) -> Int {
    guard contextRaw != 0,
          isRegisteredRuntimeObjectPointer(contextRaw),
          let ptr = UnsafeMutableRawPointer(bitPattern: contextRaw),
          let ctx = tryCast(ptr, to: RuntimeCoroutineContext.self),
          let name = ctx.name
    else {
        return 0
    }
    let resultBox = RuntimeStringBox(name)
    return runtimeRegisterObject(resultBox)
}


/// Release a CoroutineContext (decrement reference count).
@_cdecl("kk_context_release")
public func kk_context_release(_ contextRaw: Int) {
    _ = runtimeReleaseObject(contextRaw)
}

/// withContext with a full CoroutineContext (not just a dispatcher tag).
/// Extracts the dispatcher from the context and delegates to the dispatcher-
/// aware withContext, while installing the child context (name, handler,
/// dispatcher and a fresh child Job) the block's ambient context exposes.
@_cdecl("kk_with_context_full")
public func kk_with_context_full(_ contextRaw: Int, _ blockFnPtr: Int, _ continuation: Int) -> Int {
    let resolvedCtx = resolveToCoroutineContext(contextRaw)
    let dispatcherTag = resolvedCtx.dispatcher != 0
        ? resolvedCtx.dispatcher
        : RuntimeDispatcherTag.defaultDispatcher

    let restoreJobHandle = runtimeInstallWithContextChildContext(
        overrideContext: resolvedCtx,
        continuation: continuation
    )

    return kk_with_context_impl(dispatcherTag, blockFnPtr, continuation, restoreJobHandle: restoreJobHandle)
}

/// KUU-1398: kotlinx's `withContext` runs its block under a child context —
/// `parent + overrides` plus a fresh child Job (the `ScopeCoroutine`) — so the
/// ambient `coroutineContext` inside the block is a different object carrying
/// the override's elements and a new Job, whatever the override contains.
///
/// Installs that child context on the block's continuation state and returns
/// the one-shot restore closure `kk_with_context_impl` invokes when the block
/// has genuinely finished (across all of its completion paths). Returns nil
/// when the continuation carries no state to mutate.
private func runtimeInstallWithContextChildContext(
    overrideContext resolvedCtx: RuntimeCoroutineContext,
    continuation: Int
) -> (@Sendable (Int) -> Void)? {
    guard let contState = runtimeContinuationState(from: continuation) else {
        return nil
    }

    // `withContext(EmptyCoroutineContext)` is a no-op on the JVM: the merged
    // context is the same instance, so no child coroutine or Job is created.
    if resolvedCtx.dispatcher == 0, resolvedCtx.name == nil,
       resolvedCtx.exceptionHandler == nil, resolvedCtx.jobHandleRaw == 0
    {
        return nil
    }

    // The block inherits the *caller's* ambient context — the fresh
    // continuation state still has no scope/job of its own — merged with the
    // override's elements (right-hand side wins per `+`).
    let savedBuilderContext = contState.builderContext
    let savedJobHandle = contState.jobHandle
    let parentContext = RuntimeContinuationState.current?.makeContinuationContext()
        ?? RuntimeCoroutineScope.current?.context
        ?? RuntimeCoroutineContext()
    let mergedContext = parentContext.plus(resolvedCtx)
    contState.builderContext = mergedContext
    // The block runs under the merged child context (kotlinx's ScopeCoroutine):
    // mirror its CoroutineName onto the ambient scope for the block's duration
    // so `RuntimeCoroutineScope.current.name` observes the override.
    let blockScope = contState.scope
    let savedScopeName = blockScope?.name
    blockScope?.name = mergedContext.name

    // The block's ambient Job is always a fresh child. It is parented to the
    // override's own Job element when the context carries one — except
    // NonCancellable, which leaves it detached from the enclosing Job's
    // cancellation — and to the ambient Job otherwise.
    let overrideJob = runtimeJobHandle(from: resolvedCtx.jobHandleRaw)
    let isNonCancellable = resolvedCtx.jobHandleRaw == kk_non_cancellable_instance()
    let blockJobRaw = kk_job_new()
    let blockJob = runtimeJobHandle(from: blockJobRaw)
    // The block reports its failure through the continuation's throw channel;
    // failing the parent job here would surface a CancellationException that
    // swallows the block's real error.
    blockJob?.propagatesFailureToParent = false
    blockJob?.continuationState = contState
    if !isNonCancellable, let blockJob {
        let parentJob = overrideJob
            ?? runtimeJobHandle(from: parentContext.jobHandleRaw)
            ?? runtimeAsyncTask(from: parentContext.jobHandleRaw)?.completionJob
            ?? RuntimeJobHandle.current
        parentJob?.registerChild(blockJobRaw)
    }
    contState.jobHandle = blockJob

    let shieldedCaller = isNonCancellable ? RuntimeContinuationState.current : nil
    shieldedCaller?.beginCancellationShield()
    return { [weak contState] thrown in
        if thrown != 0 {
            _ = blockJob?.completeExceptionally(with: thrown)
        } else {
            _ = blockJob?.complete(with: 0)
        }
        contState?.jobHandle = savedJobHandle
        contState?.builderContext = savedBuilderContext
        contState?.scope?.name = savedScopeName
        shieldedCaller?.endCancellationShield()
    }
}

/// Check if a raw Int value is a known dispatcher tag.
private func isDispatcherTag(_ raw: Int) -> Bool {
    raw == RuntimeDispatcherTag.defaultDispatcher ||
    raw == RuntimeDispatcherTag.ioDispatcher ||
    raw == RuntimeDispatcherTag.mainDispatcher
}

func isRegisteredRuntimeObjectPointer(_ raw: Int) -> Bool {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return false
    }
    return runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
}

/// Convert any context-like raw value to a RuntimeCoroutineContext.
/// Handles: RuntimeCoroutineContext, dispatcher tags, RuntimeCoroutineNameBox,
/// RuntimeExceptionHandlerBox.
func resolveToCoroutineContext(_ raw: Int) -> RuntimeCoroutineContext {
    if raw == 0 {
        return RuntimeCoroutineContext()
    }
    if isDispatcherTag(raw) {
        return RuntimeCoroutineContext(dispatcher: raw)
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return RuntimeCoroutineContext()
    }
    // KUU-1386: job/task handles live in the runtime's weak live-handle
    // registry, not `objectPointers` — resolve them before the GC-object
    // check or a lone `Job` receiver would collapse into a dispatcher
    // context and `job.get`/`job.minusKey`/`job.fold` would misbehave.
    if runtimeJobHandle(from: raw) != nil {
        return RuntimeCoroutineContext(jobHandleRaw: raw)
    }
    if runtimeAsyncTask(from: raw) != nil {
        return RuntimeCoroutineContext(jobHandleRaw: raw)
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return RuntimeCoroutineContext(dispatcher: RuntimeDispatcherTag.defaultDispatcher)
    }
    if let ctx = tryCast(ptr, to: RuntimeCoroutineContext.self) {
        return ctx
    }
    if let dispatcher = tryCast(ptr, to: RuntimeDispatcher.self) {
        return RuntimeCoroutineContext(dispatcher: dispatcher.tag, dispatcherHandleRaw: raw)
    }
    if let nameBox = tryCast(ptr, to: RuntimeCoroutineNameBox.self) {
        return RuntimeCoroutineContext(name: nameBox.name, nameHandleRaw: raw)
    }
    if let handler = tryCast(ptr, to: RuntimeExceptionHandlerBox.self) {
        return RuntimeCoroutineContext(exceptionHandler: handler)
    }
    if runtimeJobHandle(from: raw) != nil {
        return RuntimeCoroutineContext(jobHandleRaw: raw)
    }
    if runtimeAsyncTask(from: raw) != nil {
        return RuntimeCoroutineContext(jobHandleRaw: raw)
    }
    return RuntimeCoroutineContext(dispatcher: raw)
}

// MARK: - Coroutine Dispatcher Scheduler (STDLIB-133)

/// A coroutine dispatcher that schedules work on a specific GCD queue.
/// Each dispatcher wraps a DispatchQueue and provides `dispatch(_:)` to execute
/// a closure on that queue. The three well-known dispatchers (Default, IO, Main)
/// are singletons returned by `kk_dispatcher_default/io/main`.
final class RuntimeDispatcher: @unchecked Sendable {
    let queue: DispatchQueue
    let tag: Int
    let displayName: String?

    /// CORO-003: pthread key for the currently active dispatcher (replaces threadDictionary).
    private static let currentDispatcherPthreadKey: pthread_key_t = makePthreadKey()

    /// The dispatcher active on the current thread, if any.
    static var current: RuntimeDispatcher? {
        get { pthreadGetValue(currentDispatcherPthreadKey) }
        set { pthreadSetValue(currentDispatcherPthreadKey, newValue) }
    }

    init(
        queue: DispatchQueue,
        tag: Int,
        displayName: String? = nil,
        nominalTypeFqName: String = "kotlinx.coroutines.CoroutineDispatcher"
    ) {
        self.queue = queue
        self.tag = tag
        self.displayName = displayName
        // KUU-1395: a dispatcher object carries CoroutineDispatcher's nominal
        // identity so `is`/`as?` checks on `Dispatchers.*` values and on the
        // runBlocking event-loop element answer like kotlinx's.
        registerCoroutineDispatcherTypeEdgesOnce()
        runtimeRegisterObjectType(
            rawValue: Int(bitPattern: Unmanaged.passUnretained(self).toOpaque()),
            classID: runtimeStableNominalTypeID(fqName: nominalTypeFqName)
        )
    }

    /// Dispatch a closure onto this dispatcher's queue synchronously, setting
    /// `RuntimeDispatcher.current` for the duration.
    func dispatchSync<T>(execute work: @Sendable () -> T) -> T {
        if isCurrent {
            // Already on the correct dispatcher; execute inline to avoid deadlock.
            // Still set RuntimeDispatcher.current so callee code can observe
            // which dispatcher is active (it may be nil if we arrived here via
            // the Thread.isMainThread fallback).
            let saved = RuntimeDispatcher.current
            RuntimeDispatcher.current = self
            defer { RuntimeDispatcher.current = saved }
            return work()
        }
        return queue.sync {
            let saved = RuntimeDispatcher.current
            RuntimeDispatcher.current = self
            defer { RuntimeDispatcher.current = saved }
            return work()
        }
    }

    /// Dispatch a closure onto this dispatcher's queue asynchronously, setting
    /// `RuntimeDispatcher.current` for the duration.
    func dispatchAsync(execute work: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            let saved = RuntimeDispatcher.current
            RuntimeDispatcher.current = self
            work()
            RuntimeDispatcher.current = saved
        }
    }

    /// Returns true if we are already executing on this dispatcher.
    ///
    /// NOTE: Re-entrancy detection relies on the `RuntimeDispatcher.current`
    /// thread-local, which is only set inside `dispatchSync`/`dispatchAsync`
    /// blocks. For the main dispatcher we additionally check
    /// `Thread.isMainThread` to avoid a guaranteed deadlock when
    /// `DispatchQueue.main.sync` is called from the main thread before any
    /// dispatcher context has been established.
    var isCurrent: Bool {
        if RuntimeDispatcher.current?.tag == tag { return true }
        // DispatchQueue.main.sync from the main thread deadlocks; detect it
        // even when RuntimeDispatcher.current has not been set yet.
        if tag == RuntimeDispatcherTag.mainDispatcher, Thread.isMainThread { return true }
        return false
    }
}

/// Dispatcher tag constants used as opaque handles.
private enum RuntimeDispatcherTag {
    static let defaultDispatcher: Int = 0x4B4B_4401 // "KKD\x01"
    static let ioDispatcher: Int = 0x4B4B_4402 // "KKD\x02"
    static let mainDispatcher: Int = 0x4B4B_4403 // "KKD\x03"
}

/// KUU-1395: `CoroutineDispatcher` is abstract and never constructed at the
/// Kotlin level, so no construction site emits its supertype edges; register
/// the chain to `ContinuationInterceptor`/`Element`/`CoroutineContext` once
/// here so `is`/`as?` checks on runtime dispatcher objects resolve like
/// kotlinx's (mirrors `registerJobFamilyTypeEdgesOnce`, KUU-1386).
func registerCoroutineDispatcherTypeEdgesOnce() {
    runtimeStorage.withMetadataLock { state in
        if state.coroutineDispatcherTypeEdgesRegistered { return }
        func nominalID(_ fqName: String) -> Int64 { runtimeStableNominalTypeID(fqName: fqName) }
        let dispatcher = nominalID("kotlinx.coroutines.CoroutineDispatcher")
        let mainDispatcher = nominalID("kotlinx.coroutines.MainCoroutineDispatcher")
        let interceptor = nominalID("kotlin.coroutines.ContinuationInterceptor")
        let element = nominalID("kotlin.coroutines.CoroutineContext.Element")
        let context = nominalID("kotlin.coroutines.CoroutineContext")
        for (child, parent) in [
            (dispatcher, element), (dispatcher, interceptor),
            (mainDispatcher, dispatcher),
            (interceptor, element), (element, context),
        ] {
            state.typeParents[child, default: []].insert(parent)
        }
        state.coroutineDispatcherTypeEdgesRegistered = true
    }
}

/// Singleton dispatchers. Initialized lazily on first access.
private let runtimeDefaultDispatcher = RuntimeDispatcher(
    queue: DispatchQueue.global(qos: .default),
    tag: RuntimeDispatcherTag.defaultDispatcher
)
private let runtimeIODispatcher = RuntimeDispatcher(
    queue: DispatchQueue(label: "kk.dispatcher.io", qos: .utility, attributes: .concurrent),
    tag: RuntimeDispatcherTag.ioDispatcher
)
private let runtimeMainDispatcher = RuntimeDispatcher(
    queue: DispatchQueue.main,
    tag: RuntimeDispatcherTag.mainDispatcher,
    nominalTypeFqName: "kotlinx.coroutines.MainCoroutineDispatcher"
)

/// Resolve a raw dispatcher Int to a RuntimeDispatcher instance.
/// Returns the Default dispatcher for unrecognized values.
func runtimeResolveDispatcher(from raw: Int) -> RuntimeDispatcher {
    if isRegisteredRuntimeObjectPointer(raw),
       let ptr = UnsafeMutableRawPointer(bitPattern: raw),
       let dispatcher = tryCast(ptr, to: RuntimeDispatcher.self) {
        return dispatcher
    }
    return switch raw {
    case RuntimeDispatcherTag.ioDispatcher:
        runtimeIODispatcher
    case RuntimeDispatcherTag.mainDispatcher:
        runtimeMainDispatcher
    default:
        runtimeDefaultDispatcher
    }
}

/// KUU-1395: registered handle for the dispatcher *object* behind a bare
/// scheduler tag — what `ctx[ContinuationInterceptor]`/`ctx.fold` expose when
/// the context only recorded the tag. Named singletons are used so the element
/// is `===`-equal to the `Dispatchers.*` value the tag came from.
private func runtimeDispatcherObjectHandle(forTag tag: Int) -> Int {
    let object: RuntimeDispatcher = switch tag {
    case RuntimeDispatcherTag.ioDispatcher:
        runtimeNamedDispatchers[1] // "Dispatchers.IO"
    case RuntimeDispatcherTag.mainDispatcher:
        runtimeMainDispatcher
    default:
        runtimeNamedDispatchers[0] // "Dispatchers.Default"
    }
    let pointer = Unmanaged.passUnretained(object).toOpaque()
    runtimeStorage.withGCLock { state in
        let key = UInt(bitPattern: pointer)
        state.objectPointers.insert(key)
        state.borrowedObjectPointers.insert(key)
    }
    return Int(bitPattern: pointer)
}

// These globals own the objects; accessors register their pointers idempotently.
// IO and Unconfined preserve the existing Default scheduler compatibility behavior.
private let runtimeNamedDispatchers: [RuntimeDispatcher] = [
    RuntimeDispatcher(queue: runtimeDefaultDispatcher.queue, tag: RuntimeDispatcherTag.defaultDispatcher,
                      displayName: "Dispatchers.Default"),
    RuntimeDispatcher(queue: runtimeDefaultDispatcher.queue, tag: RuntimeDispatcherTag.defaultDispatcher,
                      displayName: "Dispatchers.IO"),
    RuntimeDispatcher(queue: runtimeDefaultDispatcher.queue, tag: RuntimeDispatcherTag.defaultDispatcher,
                      displayName: "Dispatchers.Unconfined"),
]

@_cdecl("__kk_dispatcher_named")
public func kk_dispatcher_named(_ kind: Int) -> Int {
    guard runtimeNamedDispatchers.indices.contains(kind) else {
        runtimeStructuredPanic("__kk_dispatcher_named: invalid dispatcher kind")
    }
    let object = runtimeNamedDispatchers[kind]
    let pointer = Unmanaged.passUnretained(object).toOpaque()
    runtimeStorage.withGCLock { state in
        let key = UInt(bitPattern: pointer)
        state.objectPointers.insert(key)
        state.borrowedObjectPointers.insert(key)
    }
    return Int(bitPattern: pointer)
}

@_cdecl("kk_dispatcher_default")
public func kk_dispatcher_default() -> Int {
    RuntimeDispatcherTag.defaultDispatcher
}

@_cdecl("kk_dispatcher_io")
public func kk_dispatcher_io() -> Int {
    RuntimeDispatcherTag.ioDispatcher
}

@_cdecl("kk_dispatcher_main")
public func kk_dispatcher_main() -> Int {
    RuntimeDispatcherTag.mainDispatcher
}

// Memory-representation bridge: scheduler tags have no Kotlin vtable, while
// source-defined MainCoroutineDispatcher implementations retain their getter.
@_cdecl("__kk_dispatcher_immediate")
public func kk_dispatcher_immediate(
    _ dispatcher: Int, _ getterSlot: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    if isDispatcherTag(dispatcher) { return dispatcher }
    let fnPtr = kk_vtable_lookup(dispatcher, getterSlot)
    let getter = unsafeBitCast(
        fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let result = getter(dispatcher, &thrown)
    if thrown != 0 {
        runtimePropagateThrownOrTrap(
            thrown, outThrown: outThrown, context: "MainCoroutineDispatcher.immediate"
        )
    }
    return result
}

/// A simple heap-allocated, `@unchecked Sendable` box used to pass an integer
/// result from a `DispatchQueue.async` closure back to the waiting thread in
/// the non-coroutine (semaphore) fallback path of `kk_with_context`.
/// Synchronization is provided externally by a `DispatchSemaphore`.
private final class WithContextResultBox: @unchecked Sendable {
    var value: Int = 0
}

/// Kotlin `withContext(dispatcher) { block }` — switches coroutine execution
/// to the dispatch queue that corresponds to `dispatcherRaw`, runs the
/// suspend-aware block through the full entry loop (supporting intermediate
/// suspension points such as `delay`), and blocks the caller until the block
/// completes, returning its result.
///
/// STDLIB-CORO-077: Also handles RuntimeCoroutineContext objects. If dispatcherRaw
/// is a pointer to a RuntimeCoroutineContext, the dispatcher is extracted from it
/// and context elements (name, exception handler) are propagated.
@_cdecl("kk_with_context")
public func kk_with_context(_ dispatcherRaw: Int, _ blockFnPtr: Int, _ continuation: Int) -> Int {
    // A bare dispatcher tag still gets the child-context treatment: on JVM
    // every `withContext` installs a fresh child Job and exposes the
    // dispatcher element in the ambient context, not just reschedules.
    kk_with_context_full(dispatcherRaw, blockFnPtr, continuation)
}

/// Shared implementation behind the `kk_with_context` ABI entry point.
/// `restoreJobHandle`, when non-nil, is invoked exactly once at the point the
/// block's execution has genuinely finished -- across all three completion
/// paths below (inline, CORO-004 async, non-coroutine semaphore) -- so that
/// `kk_with_context_full`'s job-element override (e.g. NonCancellable) does
/// not leak past the end of this withContext block.
func kk_with_context_impl(
    _ dispatcherRaw: Int,
    _ blockFnPtr: Int,
    _ continuation: Int,
    restoreJobHandle: (@Sendable (Int) -> Void)?
) -> Int {
    // `kk_with_context_full` resolves the context argument first, so this
    // always receives a dispatcher tag (0/unknown values fall to Default).
    let resolvedDispatcher = switch dispatcherRaw {
    case RuntimeDispatcherTag.defaultDispatcher,
         RuntimeDispatcherTag.ioDispatcher,
         RuntimeDispatcherTag.mainDispatcher:
        dispatcherRaw
    default:
        RuntimeDispatcherTag.defaultDispatcher
    }
    let dispatcher = runtimeResolveDispatcher(from: resolvedDispatcher)

    guard suspendEntryPoint(from: blockFnPtr) != nil else {
        // Clean up the continuation to avoid leaking coroutine state.
        _ = kk_coroutine_state_exit(continuation, 0)
        restoreJobHandle?(0)
        return 0
    }

    // Capture the current coroutine scope so child launches inside the block
    // are registered with the correct scope on the target queue's thread.
    let parentScope = RuntimeCoroutineScope.current

    // Propagate caller's scope to continuation context so that
    // runSuspendEntryLoopWithContinuation installs it under the fresh task key.
    // Without this, contState.scope would be nil for a freshly created
    // continuation and child coroutines launched inside the withContext block
    // would lose the parent scope — breaking structured concurrency.
    if let contState = runtimeContinuationState(from: continuation) {
        contState.scope = parentScope
        // KUU-964: propagate the caller's Job the same way — withContext(context)
        // without a Job element keeps the ambient Job, so `coroutineContext.job`
        // resolves inside the block (kotlinx's contract). A Job element the
        // context itself carries (e.g. NonCancellable) was already installed by
        // `kk_with_context_full` and must not be clobbered.
        if contState.jobHandle == nil {
            contState.jobHandle = contState.scope?.job
                ?? RuntimeContinuationState.current?.jobHandle
                ?? RuntimeJobHandle.current
        }
    }

    // NOTE: When the target queue is DispatchQueue.main and we are already on
    // the main thread, dispatching async + semaphore.wait() would deadlock
    // because the main thread cannot process the enqueued block while blocked.
    // CLI programs produced by this compiler do not run a main run loop, so
    // even calls from a background thread targeting the main queue would hang.
    // We therefore execute inline whenever we are already on the target queue
    // (main-thread case) to avoid the deadlock.
    if dispatcher.tag == RuntimeDispatcherTag.mainDispatcher && Thread.isMainThread {
        let savedScope = RuntimeCoroutineScope.current
        let savedDispatcher = RuntimeDispatcher.current
        defer { RuntimeCoroutineScope.current = savedScope }
        defer { RuntimeDispatcher.current = savedDispatcher }
        RuntimeCoroutineScope.current = parentScope
        RuntimeDispatcher.current = dispatcher
        var thrown = 0
        let result = runSuspendEntryLoopWithContinuation(
            entryPointRaw: blockFnPtr,
            continuation: continuation,
            outThrown: &thrown
        )
        restoreJobHandle?(thrown)
        return result
    }

    // CORO-004: Continuation-based withContext (caller suspend path).
    //
    // When called from inside a coroutine, the caller's GCD thread must not be
    // blocked while the dispatched block runs.  Instead we install a completion
    // resumer on the *caller* state so the outer suspend-entry loop can re-enter
    // without holding any thread.  The dispatched block starts its own inner
    // suspend-entry loop on the target queue and returns immediately (async path);
    // the dispatcher thread is released rather than blocked for the duration of
    // the block (DEBT-CORO-003: previously the dispatcher thread was blocked by
    // the inner completionGate semaphore inside runSuspendEntryLoopWithContinuation).
    if let callerState = RuntimeContinuationState.current {
        let capturedContinuation = continuation
        dispatcher.dispatchAsync {
            let savedScope = RuntimeCoroutineScope.current
            RuntimeCoroutineScope.current = parentScope
            defer { RuntimeCoroutineScope.current = savedScope }
            _ = runSuspendEntryLoopWithContinuation(
                entryPointRaw: blockFnPtr,
                continuation: capturedContinuation,
                onCompletion: { result, thrown in
                    restoreJobHandle?(thrown)
                    if thrown != 0 {
                        callerState.resume(withException: thrown)
                    } else {
                        callerState.resume(with: result)
                    }
                }
            )
        }
        return Int(bitPattern: kk_coroutine_suspended())
    }

    // Non-coroutine context (e.g. runBlocking top-level, tests): block the
    // calling thread until the dispatched block completes.
    let semaphore = DispatchSemaphore(value: 0)
    let resultBox = WithContextResultBox()

    dispatcher.dispatchAsync {
        let savedScope = RuntimeCoroutineScope.current
        RuntimeCoroutineScope.current = parentScope
        defer { RuntimeCoroutineScope.current = savedScope }

        var thrown = 0
        resultBox.value = runSuspendEntryLoopWithContinuation(
            entryPointRaw: blockFnPtr,
            continuation: continuation,
            outThrown: &thrown
        )
        restoreJobHandle?(thrown)
        semaphore.signal()
    }

    // The dispatched block runs on a real dispatcher queue, so it is not itself
    // queued on any runBlocking event loop -- but this thread may be draining
    // one, and the block can join work that is. Drain rather than park.
    runtimeWaitDrainingEventLoop(semaphore)
    return resultBox.value
}
