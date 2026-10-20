import Dispatch
import Foundation

private let runtimeCoroutineContextInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.coroutines.CoroutineContext"
)

private let runtimeEmptyCoroutineContextTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.coroutines.EmptyCoroutineContext"
)

final class RuntimeCoroutineContext: @unchecked Sendable {
    var dispatcher: Int  // 0 means "inherit from parent"
    var dispatcherHandleRaw: Int
    var name: String?
    var nameHandleRaw: Int
    var exceptionHandler: RuntimeExceptionHandlerBox?
    var jobHandleRaw: Int
    /// Source-defined elements the fixed fields cannot model, stored as
    /// ordered (key, element) handle pairs. Element order matters for `fold`.
    var extras: [(key: Int, element: Int)]

    /// Context operations expose the original element; scheduling uses its tag.
    var dispatcherElementHandle: Int {
        if dispatcherHandleRaw != 0 { return dispatcherHandleRaw }
        // KUU-2687: a bare scheduler tag resolves to the singleton dispatcher
        // object so `fold`/`get`/`===`/printing all see the Dispatchers.*
        // value the tag stands for — never the raw integer (which is
        // indistinguishable from an Int literal at the print layer).
        if isDispatcherTag(dispatcher) { return runtimeDispatcherObjectHandle(forTag: dispatcher) }
        return dispatcher
    }

    init(
        dispatcher: Int = 0,
        name: String? = nil,
        exceptionHandler: RuntimeExceptionHandlerBox? = nil,
        jobHandleRaw: Int = 0,
        nameHandleRaw: Int = 0,
        dispatcherHandleRaw: Int = 0,
        extras: [(key: Int, element: Int)] = []
    ) {
        self.dispatcher = dispatcher
        self.dispatcherHandleRaw = dispatcherHandleRaw
        self.name = name
        self.nameHandleRaw = nameHandleRaw != 0 ? nameHandleRaw
            : name.map { runtimeRegisterObject(RuntimeCoroutineNameBox(name: $0)) } ?? 0
        self.exceptionHandler = exceptionHandler
        self.jobHandleRaw = jobHandleRaw
        self.extras = extras
    }

    func extraElement(for keyRaw: Int) -> Int? {
        for pair in extras where pair.key == keyRaw {
            return pair.element
        }
        return nil
    }

    /// Right-hand side wins for duplicate keys — including a `key` collision
    /// between a built-in field and an extras element, which
    /// `kotlin.coroutines` resolves as `minusKey(otherKeys) + other`.
    func plus(_ other: RuntimeCoroutineContext) -> RuntimeCoroutineContext {
        // The dispatcher/interceptor slot is occupied whenever the other
        // context carries a dispatcher — a scheduler tag or an element object
        // with no tag (e.g. a runBlocking event loop, KUU-1395) — so
        // `ctx + element` replaces it like kotlinx's `+` does.
        let otherHasDispatcher = other.dispatcherElementHandle != 0
        let otherClaimsJob = other.extras.contains { $0.key == runtimeJobKeyRaw }
        let otherClaimsName = other.extras.contains { $0.key == runtimeCoroutineNameKeyRaw }
        let otherClaimsHandler = other.extras.contains { $0.key == runtimeExceptionHandlerKeyRaw }
        let otherClaimsDispatcher = other.extras.contains {
            $0.key == runtimeContinuationInterceptorKeyRaw || $0.key == runtimeCoroutineDispatcherKeyRaw
        }
        var mergedExtras = extras.filter { pair in
            !other.extras.contains { $0.key == pair.key }
                && !(other.jobHandleRaw != 0 && pair.key == runtimeJobKeyRaw)
                && !(other.name != nil && pair.key == runtimeCoroutineNameKeyRaw)
                && !(other.exceptionHandler != nil && pair.key == runtimeExceptionHandlerKeyRaw)
                && !(otherHasDispatcher
                     && (pair.key == runtimeContinuationInterceptorKeyRaw
                         || pair.key == runtimeCoroutineDispatcherKeyRaw))
        }
        mergedExtras.append(contentsOf: other.extras)
        return RuntimeCoroutineContext(
            dispatcher: otherHasDispatcher ? other.dispatcher
                : (otherClaimsDispatcher ? 0 : self.dispatcher),
            name: other.name ?? (otherClaimsName ? nil : self.name),
            exceptionHandler: other.exceptionHandler ?? (otherClaimsHandler ? nil : self.exceptionHandler),
            jobHandleRaw: other.jobHandleRaw != 0 ? other.jobHandleRaw
                : (otherClaimsJob ? 0 : self.jobHandleRaw),
            nameHandleRaw: other.name != nil ? other.nameHandleRaw
                : (otherClaimsName ? 0 : self.nameHandleRaw),
            dispatcherHandleRaw: otherHasDispatcher ? other.dispatcherHandleRaw
                : (otherClaimsDispatcher ? 0 : self.dispatcherHandleRaw),
            extras: mergedExtras
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
    let extraKeys: [Int]
    let extraElements: [Int]

    init(
        dispatcher: Int,
        dispatcherHandleRaw: Int,
        name: String?,
        nameHandleRaw: Int,
        exceptionHandler: RuntimeExceptionHandlerBox?,
        jobHandleRaw: Int,
        extras: [(key: Int, element: Int)]
    ) {
        self.dispatcher = dispatcher
        self.dispatcherHandleRaw = dispatcherHandleRaw
        self.name = name
        self.nameHandleRaw = nameHandleRaw
        self.exceptionHandlerRaw = exceptionHandler.map {
            Int(bitPattern: Unmanaged.passUnretained($0).toOpaque())
        } ?? 0
        self.jobHandleRaw = jobHandleRaw
        self.extraKeys = extras.map(\.key)
        self.extraElements = extras.map(\.element)
    }

    init(_ context: RuntimeCoroutineContext) {
        self.init(
            dispatcher: context.dispatcher,
            dispatcherHandleRaw: context.dispatcherHandleRaw,
            name: context.name,
            nameHandleRaw: context.nameHandleRaw,
            exceptionHandler: context.exceptionHandler,
            jobHandleRaw: context.jobHandleRaw,
            extras: context.extras
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
        jobHandleRaw: Int,
        extras: [(key: Int, element: Int)]
    ) -> RuntimeCoroutineContext {
        let key = RuntimeCoroutineContextIdentity(
            dispatcher: dispatcher,
            dispatcherHandleRaw: dispatcherHandleRaw,
            name: name,
            nameHandleRaw: nameHandleRaw,
            exceptionHandler: exceptionHandler,
            jobHandleRaw: jobHandleRaw,
            extras: extras
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
            dispatcherHandleRaw: dispatcherHandleRaw,
            extras: extras
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

/// Whether two runtime context models contain the same elements in the same order.
func runtimeCoroutineContextsHaveSameContent(
    _ lhs: RuntimeCoroutineContext,
    _ rhs: RuntimeCoroutineContext
) -> Bool {
    RuntimeCoroutineContextIdentity(lhs) == RuntimeCoroutineContextIdentity(rhs)
}

/// The canonical object for the given content, creating it only on a miss so
/// repeated `coroutineContext` reads on an unchanged context allocate nothing.
func runtimeCanonicalCoroutineContext(
    dispatcher: Int,
    dispatcherHandleRaw: Int,
    name: String?,
    nameHandleRaw: Int,
    exceptionHandler: RuntimeExceptionHandlerBox?,
    jobHandleRaw: Int,
    extras: [(key: Int, element: Int)] = []
) -> RuntimeCoroutineContext {
    RuntimeCoroutineContextCanonicalizer.shared.canonical(
        dispatcher: dispatcher,
        dispatcherHandleRaw: dispatcherHandleRaw,
        name: name,
        nameHandleRaw: nameHandleRaw,
        exceptionHandler: exceptionHandler,
        jobHandleRaw: jobHandleRaw,
        extras: extras
    )
}

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

@_cdecl("kk_coroutine_name_key")
public func kk_coroutine_name_key() -> Int {
    runtimeCoroutineNameKeyRaw
}

@_cdecl("kk_coroutine_name_key_get")
public func kk_coroutine_name_key_get(_ receiver: Int) -> Int {
    runtimeCoroutineNameKeyRaw
}

/// KUU-1405: singleton backing `ContinuationInterceptor.Key` /
/// `CoroutineDispatcher.Key`. The bundled stdlib marks those companions
/// `@KsSymbolName`s onto these getters so `ctx[ContinuationInterceptor]` and
/// `ctx[CoroutineDispatcher]` resolve the stored dispatcher element, matching
/// kotlinx where both companions model the same interceptor key.
private final class RuntimeContinuationInterceptorKey: @unchecked Sendable {}
private let runtimeContinuationInterceptorKeyRaw = runtimeRegisterObject(RuntimeContinuationInterceptorKey())

/// Runtime-backed companions bypass Kotlin object allocation and its type registration.
/// Register both the companion identity and Key supertype whenever a key is exposed.
private func runtimeTypedCoroutineContextKey(_ rawValue: Int, fqName: String) -> Int {
    let typeID = runtimeStableNominalTypeID(fqName: fqName)
    runtimeRegisterObjectType(rawValue: rawValue, classID: typeID)
    runtimeRegisterTypeEdge(
        childTypeID: typeID,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.coroutines.CoroutineContext.Key")
    )
    return rawValue
}

@_cdecl("kk_continuation_interceptor_key")
public func kk_continuation_interceptor_key() -> Int {
    runtimeTypedCoroutineContextKey(
        runtimeContinuationInterceptorKeyRaw, fqName: "kotlin.coroutines.ContinuationInterceptor.Key"
    )
}

/// `CoroutineDispatcher.Key` is a distinct object in kotlinx — an
/// `AbstractCoroutineContextKey` whose base key is `ContinuationInterceptor`
/// — so `ctx[CoroutineDispatcher]` accepts dispatcher elements while
/// `ctx[ContinuationInterceptor]` on a `CoroutineDispatcher`-keyed element
/// does not.
private final class RuntimeCoroutineDispatcherKey: @unchecked Sendable {}
private let runtimeCoroutineDispatcherKeyRaw = runtimeRegisterObject(RuntimeCoroutineDispatcherKey())

@_cdecl("kk_coroutine_dispatcher_key")
public func kk_coroutine_dispatcher_key() -> Int {
    runtimeTypedCoroutineContextKey(
        runtimeCoroutineDispatcherKeyRaw, fqName: "kotlinx.coroutines.CoroutineDispatcher.Key"
    )
}

/// KUU-1405: singleton backing `CoroutineExceptionHandler.Key` so
/// `ctx[CoroutineExceptionHandler]`/`minusKey` resolve the stored handler.
private final class RuntimeExceptionHandlerKey: @unchecked Sendable {}
private let runtimeExceptionHandlerKeyRaw = runtimeRegisterObject(RuntimeExceptionHandlerKey())

@_cdecl("kk_exception_handler_key")
public func kk_exception_handler_key() -> Int {
    runtimeExceptionHandlerKeyRaw
}

/// KUU-1405: merge the source-element `extras` of two contexts the way
/// `base.plus(override)` merges the fixed fields — override extras win per
/// key, and extras claiming a built-in key lose to the merged built-in
/// field (the coroutine's own Job, resolved name/dispatcher/handler).
func runtimeMergedContextExtras(
    inherited: [(key: Int, element: Int)],
    override: [(key: Int, element: Int)],
    jobPresent: Bool,
    namePresent: Bool,
    dispatcherPresent: Bool,
    handlerPresent: Bool
) -> [(key: Int, element: Int)] {
    var merged = inherited
    for pair in override {
        merged.removeAll { $0.key == pair.key }
        merged.append(pair)
    }
    if jobPresent {
        merged.removeAll { $0.key == runtimeJobKeyRaw }
    }
    if namePresent {
        merged.removeAll { $0.key == runtimeCoroutineNameKeyRaw }
    }
    if dispatcherPresent {
        merged.removeAll {
            $0.key == runtimeContinuationInterceptorKeyRaw || $0.key == runtimeCoroutineDispatcherKeyRaw
        }
    }
    if handlerPresent {
        merged.removeAll { $0.key == runtimeExceptionHandlerKeyRaw }
    }
    return merged
}

func runtimeCoroutineContextElementMethod(_ receiver: Int, _ interfaceTypeID: Int, _ methodSlot: Int) -> Int? {
    // Element declares get/fold/minusKey; its key getter follows those slots.
    guard interfaceTypeID == Int(runtimeStableNominalTypeID(fqName: "kotlin.coroutines.CoroutineContext.Element")) else {
        return nil
    }
    let ptr = isRegisteredRuntimeObjectPointer(receiver) ? UnsafeMutableRawPointer(bitPattern: receiver) : nil
    let isName = ptr.flatMap { tryCast($0, to: RuntimeCoroutineNameBox.self) } != nil
    let isDispatcher = isDispatcherTag(receiver) || ptr.flatMap { tryCast($0, to: RuntimeDispatcher.self) } != nil
    let isHandler = ptr.flatMap { tryCast($0, to: RuntimeExceptionHandlerBox.self) } != nil
    let isJob = runtimeJobHandle(from: receiver) != nil || runtimeAsyncTask(from: receiver) != nil
    guard isName || isDispatcher || isHandler || isJob else {
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
    case 3:
        let getter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { receiver, outThrown in
            outThrown?.pointee = 0
            return runtimeCoroutineElementKeyHandle(for: receiver)
        }
        return unsafeBitCast(getter, to: Int.self)
    default:
        return nil
    }
}

private func runtimeCoroutineElementKeyHandle(for receiver: Int) -> Int {
    if let ptr = isRegisteredRuntimeObjectPointer(receiver)
        ? UnsafeMutableRawPointer(bitPattern: receiver) : nil
    {
        if tryCast(ptr, to: RuntimeCoroutineNameBox.self) != nil {
            return runtimeCoroutineNameKeyRaw
        }
        if tryCast(ptr, to: RuntimeDispatcher.self) != nil
            || tryCast(ptr, to: RuntimeExceptionHandlerBox.self) != nil
        {
            return tryCast(ptr, to: RuntimeDispatcher.self) != nil
                ? kk_continuation_interceptor_key()
                : runtimeExceptionHandlerKeyRaw
        }
    }
    if isDispatcherTag(receiver) {
        return kk_continuation_interceptor_key()
    }
    if runtimeJobHandle(from: receiver) != nil || runtimeAsyncTask(from: receiver) != nil {
        return runtimeJobKeyRaw
    }
    return 0
}

/// Register a heap-allocated object in the runtime storage so it is not GC'd.
func runtimeRegisterObject<T: AnyObject>(_ object: T) -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(object).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

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

@_cdecl("kk_exception_handler_invoke")
public func kk_exception_handler_invoke(_ handlerRaw: Int, _ contextRaw: Int, _ exceptionRaw: Int) -> Int {
    guard handlerRaw != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: handlerRaw),
          let handler = tryCast(ptr, to: RuntimeExceptionHandlerBox.self)
    else {
        return 0
    }
    handler.handler(contextRaw, exceptionRaw)
    return 0
}

/// Each argument can be a RuntimeCoroutineContext, a dispatcher tag,
/// a RuntimeCoroutineNameBox, or a RuntimeExceptionHandlerBox.
@_cdecl("kk_context_plus")
public func kk_context_plus(_ leftRaw: Int, _ rightRaw: Int) -> Int {
    // The source-backed empty singleton is the identity on either side.
    // Preserve the operand itself so `ctx + EmptyCoroutineContext` keeps the
    // exact context object (kotlinx returns the same instance).
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

let runtimeCoroutineContextFoldBridgePointer: Int = {
    let bridge: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = kk_context_fold
    return unsafeBitCast(bridge, to: Int.self)
}()

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
    // Runtime-backed Job implementations can register this bridge itself in
    // their context itable. It takes a split callback pair, whereas Kotlin
    // overrides take one function value; never invoke the bridge through the
    // source-method ABI or recursively dispatch back into it.
    let method = kk_itable_lookup_dynamic(contextRaw, Int(runtimeCoroutineContextInterfaceTypeID), 1)
    if method != 0, method != runtimeCoroutineContextFoldBridgePointer {
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

/// The raw handle `extras` reports for `keyRaw`: kotlinx's `CombinedContext.get`
/// calls `element.get(key)`, so a source element answers through its own
/// dispatch — `by`-delegated elements forward to their delegate, and custom
/// `get` overrides win over stored-key matching.
private func runtimeExtraElementGet(_ element: Int, key keyRaw: Int) -> Int? {
    guard let result = runtimeSourceInterfaceCall1(
        element,
        keyRaw,
        interfaceTypeID: runtimeStableNominalTypeID(fqName: "kotlin.coroutines.CoroutineContext.Element"),
        methodSlot: 0,
        context: "CoroutineContext.Element.get"
    ) else {
        return element
    }
    return result == 0 || result == runtimeNullSentinelInt ? nil : result
}

private func runtimeCoroutineContextElementHandle(for keyRaw: Int, in ctx: RuntimeCoroutineContext) -> Int? {
    if let extra = ctx.extraElement(for: keyRaw) {
        return runtimeExtraElementGet(extra, key: keyRaw)
    }
    if keyRaw == runtimeCoroutineNameKeyRaw {
        return ctx.name != nil ? ctx.nameHandleRaw : nil
    }
    if keyRaw == runtimeContinuationInterceptorKeyRaw || keyRaw == runtimeCoroutineDispatcherKeyRaw {
        // KUU-1395: `ctx[ContinuationInterceptor]` / `ctx[CoroutineDispatcher]`
        // resolve the context's dispatcher element. A handle-only element
        // (the runBlocking event loop) occupies the slot the same way a tag
        // does, and a tag-only slot resolves to its dispatcher object so the
        // element answers `is CoroutineDispatcher`.
        let handle = ctx.dispatcherElementHandle
        let dispatcherElement: Int? = handle != 0
            ? (isDispatcherTag(handle) ? runtimeDispatcherObjectHandle(forTag: handle) : handle)
            : nil
        if keyRaw == runtimeContinuationInterceptorKeyRaw {
            return dispatcherElement ?? ctx.extraElement(for: runtimeContinuationInterceptorKeyRaw)
        }
        // CoroutineDispatcher.Key is a polymorphic sub-key of
        // ContinuationInterceptor: it also accepts elements keyed by the
        // interceptor key.
        return dispatcherElement
            ?? (ctx.extraElement(for: runtimeCoroutineDispatcherKeyRaw)
                ?? ctx.extraElement(for: runtimeContinuationInterceptorKeyRaw))
    }
    if keyRaw == runtimeExceptionHandlerKeyRaw {
        return ctx.exceptionHandler.map {
            Int(bitPattern: UnsafeMutableRawPointer(Unmanaged.passUnretained($0).toOpaque()))
        }
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
    handles.append(contentsOf: ctx.extras.map(\.element))
    return handles
}

private func runtimeCoroutineContextRemovingElement(for keyRaw: Int, from ctx: RuntimeCoroutineContext) -> RuntimeCoroutineContext {
    let next = RuntimeCoroutineContext(
        dispatcher: ctx.dispatcher,
        name: ctx.name,
        exceptionHandler: ctx.exceptionHandler,
        jobHandleRaw: ctx.jobHandleRaw,
        nameHandleRaw: ctx.nameHandleRaw,
        dispatcherHandleRaw: ctx.dispatcherHandleRaw,
        extras: ctx.extras.filter { pair in
            pair.key != keyRaw
                // CoroutineDispatcher.Key's polymorphic minusKey also drops
                // elements stored under the ContinuationInterceptor key.
                && !(keyRaw == runtimeCoroutineDispatcherKeyRaw
                     && pair.key == runtimeContinuationInterceptorKeyRaw)
        }
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
    if keyRaw == runtimeExceptionHandlerKeyRaw {
        next.exceptionHandler = nil
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
    return ctx.jobHandleRaw != 0 ? ctx.jobHandleRaw
        : (ctx.extraElement(for: runtimeJobKeyRaw)
            .flatMap { runtimeExtraElementGet($0, key: runtimeJobKeyRaw) } ?? 0)
}

/// Returns a RuntimeStringBox pointer (or 0 if no name).
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


public func kk_context_release(_ contextRaw: Int) {
    _ = runtimeReleaseObject(contextRaw)
}

@_cdecl("kk_with_context_full")
public func kk_with_context_full(_ contextRaw: Int, _ blockFnPtr: Int, _ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    outThrown?.pointee = 0
    let resolvedCtx = resolveToCoroutineContext(contextRaw)
    let dispatcherTag = resolvedCtx.dispatcher != 0
        ? resolvedCtx.dispatcher
        : RuntimeDispatcherTag.defaultDispatcher

    let restoreJobHandle = runtimeInstallWithContextChildContext(
        overrideContext: resolvedCtx,
        continuation: continuation
    )

    return kk_with_context_impl(dispatcherTag, blockFnPtr, continuation, outThrown: outThrown, restoreJobHandle: restoreJobHandle)
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
) -> (@Sendable (Int) -> Int)? {
    guard let contState = runtimeContinuationState(from: continuation) else {
        return nil
    }

    // The block inherits the *caller's* ambient context — the fresh
    // continuation state still has no scope/job of its own — merged with the
    // override's elements (right-hand side wins per `+`).
    let savedBuilderContext = contState.builderContext
    let savedJobHandle = contState.jobHandle
    let savedScope = contState.scope
    let parentContext = RuntimeContinuationState.current?.makeContinuationContext()
        ?? RuntimeCoroutineScope.current?.context
        ?? RuntimeCoroutineContext()
    let mergedContext = parentContext.plus(resolvedCtx)

    // The block's ambient Job is always a fresh child. It is parented to the
    // override's own Job element when the context carries one — except
    // NonCancellable, which leaves it detached from the enclosing Job's
    // cancellation — and to the ambient Job otherwise.
    let overrideJobHandle = resolvedCtx.jobHandleRaw != 0
        ? resolvedCtx.jobHandleRaw
        : (resolvedCtx.extraElement(for: runtimeJobKeyRaw)
            .flatMap { runtimeExtraElementGet($0, key: runtimeJobKeyRaw) } ?? 0)
    let overrideJob = runtimeJobHandle(from: overrideJobHandle)
        ?? runtimeAsyncTask(from: overrideJobHandle)?.completionJob
    let isNonCancellable = overrideJobHandle == kk_non_cancellable_instance()
    let blockJobRaw = kk_job_new()
    let blockJob = runtimeJobHandle(from: blockJobRaw)
    // The block reports its failure through the continuation's throw channel;
    // failing the parent job here would surface a CancellationException that
    // swallows the block's real error.
    blockJob?.propagatesFailureToParent = false
    blockJob?.debugName = mergedContext.dispatcherElementHandle == parentContext.dispatcherElementHandle
        ? "UndispatchedCoroutine" : "DispatchedCoroutine"
    blockJob?.continuationState = contState
    let blockParent: RuntimeJobHandle? = isNonCancellable ? nil : (overrideJob
        ?? runtimeJobHandle(from: parentContext.jobHandleRaw)
        ?? runtimeAsyncTask(from: parentContext.jobHandleRaw)?.completionJob
        ?? RuntimeJobHandle.current)
    if blockJob != nil { blockParent?.registerChild(blockJobRaw) }
    contState.jobHandle = blockJob
    // Even an empty override receives a fresh ScopeCoroutine. Its receiver
    // keeps this context after the block returns or another coroutine runs.
    let childContext = mergedContext.plus(RuntimeCoroutineContext(jobHandleRaw: blockJobRaw))
    let blockScope = RuntimeCoroutineScope(context: childContext)
    if let blockJob { blockScope.adoptJob(blockJob) }
    _ = runtimeRegisterObject(blockScope)
    contState.scope = blockScope
    contState.builderContext = childContext

    let shieldedCaller = isNonCancellable ? RuntimeContinuationState.current : nil
    shieldedCaller?.beginCancellationShield()
    return { [weak contState] thrown in
        if thrown != 0 {
            blockScope.recordBodyFailure(thrown)
            blockScope.cancel(message: "withContext failed", cause: thrown)
        }
        _ = blockScope.waitForChildren()
        // A ContextScope constructed around this Job owns another child list.
        // Join those children through the shared Job hierarchy as well.
        var joined: Set<Int> = []
        while let blockJob {
            let children = blockJob.registeredChildrenSnapshot().filter { !joined.contains($0) }
            if children.isEmpty { break }
            for child in children {
                joined.insert(child)
                guard let childJob = runtimeJobHandle(from: child)
                    ?? runtimeAsyncTask(from: child)?.completionJob else { continue }
                _ = childJob.join()
                let failure = childJob.completionSnapshot().exception
                if failure != 0, kk_is_cancellation_exception(failure) == 0 {
                    blockScope.recordBodyFailure(failure)
                    blockScope.cancel(message: "withContext child failed", cause: failure)
                }
            }
        }
        let childFailure = blockScope.childFailureSnapshot()
        var failure = childFailure != 0 ? childFailure : thrown
        if failure == 0, blockJob?.cancellationSnapshot() == true,
           let blockJob {
            failure = runtimeJobCancellationException(blockJob)
        }
        if failure != 0 { _ = blockJob?.completeExceptionally(with: failure) }
        else { _ = blockJob?.complete(with: 0) }
        let settledCause = blockJob?.completionSnapshot().exception ?? failure
        // A scoped failure is delivered through its caller. Once caught it
        // must not remain in the parent's hierarchy as an unhandled child.
        blockParent?.detachChild(blockJobRaw)
        contState?.jobHandle = savedJobHandle
        contState?.builderContext = savedBuilderContext
        contState?.scope = savedScope
        shieldedCaller?.endCancellationShield()
        return settledCause
    }
}

func isDispatcherTag(_ raw: Int) -> Bool {
    raw == RuntimeDispatcherTag.defaultDispatcher ||
    raw == RuntimeDispatcherTag.ioDispatcher ||
    raw == RuntimeDispatcherTag.mainDispatcher ||
    raw == RuntimeDispatcherTag.mainImmediateDispatcher
}

func isRegisteredRuntimeObjectPointer(_ raw: Int) -> Bool {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return false
    }
    return runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
}

/// GC-root a heap-object handle so storing it inside a runtime-owned context
/// keeps it alive across mark-and-sweep (contexts outlive the Kotlin frames
/// that created their elements).
private func runtimePinHeapObjectIfNeeded(_ raw: Int) {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return
    }
    runtimeStorage.withGCLock { state in
        let key = UInt(bitPattern: ptr)
        if state.heapObjects[key] != nil {
            state.pinnedObjectCounts[key, default: 0] += 1
        }
    }
}

/// KUU-1405: if `raw` is a source-defined `CoroutineContext.Element` (an
/// object carrying the Element itable), return its own `key` handle so the
/// element can be modelled in `RuntimeCoroutineContext.extras`.
/// Returns nil for runtime boxes, non-elements, and non-pointer values.
private func runtimeSourceContextElementKey(_ raw: Int) -> Int? {
    guard UnsafeMutableRawPointer(bitPattern: raw) != nil else {
        return nil
    }
    let elementTypeID = runtimeStableNominalTypeID(fqName: "kotlin.coroutines.CoroutineContext.Element")
    // `key` is the Element interface slot after get/fold/minusKey; its
    // presence identifies a source element.
    guard let keyRaw = runtimeSourceInterfaceCall0(
        raw,
        interfaceTypeID: elementTypeID,
        methodSlot: 3,
        context: "CoroutineContext.Element.key"
    ), keyRaw != 0, keyRaw != runtimeNullSentinelInt else {
        return nil
    }
    runtimePinHeapObjectIfNeeded(raw)
    runtimePinHeapObjectIfNeeded(keyRaw)
    return keyRaw
}

func resolveToCoroutineContext(_ raw: Int) -> RuntimeCoroutineContext {
    // Source-backed EmptyCoroutineContext is a heap singleton, not a dispatcher.
    if raw == 0 || runtimeObjectTypeID(rawValue: raw) == runtimeEmptyCoroutineContextTypeID {
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
    if !isObjectPointer {
        // KUU-1405: a source-defined `CoroutineContext.Element` (a GC heap
        // object) contributes itself under its own key, like kotlinx's
        // `elem.plus(other)` treating a lone element as a single-entry
        // context. Previously it fell into the default-dispatcher fallback.
        if let elementKey = runtimeSourceContextElementKey(raw) {
            return RuntimeCoroutineContext(extras: [(key: elementKey, element: raw)])
        }
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
    if let elementKey = runtimeSourceContextElementKey(raw) {
        return RuntimeCoroutineContext(extras: [(key: elementKey, element: raw)])
    }
    return RuntimeCoroutineContext(dispatcher: raw)
}

class RuntimeDispatcher: @unchecked Sendable {
    let queue: DispatchQueue
    /// The scheduler identity stored on a `RuntimeCoroutineContext`. Views
    /// assign their own pointer post-init so the context keeps the view as the
    /// dispatcher element instead of collapsing to the base tag.
    var tag: Int
    let displayName: String?
    let isUnconfined: Bool
    /// KUU-2687: `Dispatchers.Main.immediate` semantics — when a dispatch lands
    /// while already running on this dispatcher, the work runs in place rather
    /// than being re-queued (upstream `isDispatchNeeded() == false`).
    let supportsImmediateDispatch: Bool
    weak var blockingEventLoop: RuntimeEventLoop?
    private var immediatePeerStorage: RuntimeDispatcher?

    /// CORO-003: pthread key for the currently active dispatcher (replaces threadDictionary).
    private static let currentDispatcherPthreadKey: pthread_key_t = makePthreadKey()

    static var current: RuntimeDispatcher? {
        get { pthreadGetValue(currentDispatcherPthreadKey) }
        set { pthreadSetValue(currentDispatcherPthreadKey, newValue) }
    }

    init(
        queue: DispatchQueue,
        tag: Int,
        displayName: String? = nil,
        isUnconfined: Bool = false,
        supportsImmediateDispatch: Bool = false,
        nominalTypeFqName: String = "kotlinx.coroutines.CoroutineDispatcher"
    ) {
        self.queue = queue
        self.tag = tag
        self.displayName = displayName
        self.isUnconfined = isUnconfined
        self.supportsImmediateDispatch = supportsImmediateDispatch
        // KUU-1395: a dispatcher object carries CoroutineDispatcher's nominal
        // identity so `is`/`as?` checks on `Dispatchers.*` values and on the
        // runBlocking event-loop element answer like kotlinx's.
        registerCoroutineDispatcherTypeEdgesOnce()
        runtimeRegisterObjectType(
            rawValue: Int(bitPattern: Unmanaged.passUnretained(self).toOpaque()),
            classID: runtimeStableNominalTypeID(fqName: nominalTypeFqName)
        )
    }

    /// The dispatcher `.immediate` resolves to. For every dispatcher except
    /// `Dispatchers.Main` (and views over it) this is `self`, matching upstream
    /// where only `MainCoroutineDispatcher.immediate` is a distinct object.
    var immediatePeer: RuntimeDispatcher { immediatePeerStorage ?? self }
    func setImmediatePeer(_ peer: RuntimeDispatcher) { immediatePeerStorage = peer }

    /// Whether this dispatcher (or the dispatcher a view delegates to) is the
    /// main-bound one — upstream `limitedParallelism` answers namedOrThis for it.
    var isMainDispatcher: Bool {
        tag == RuntimeDispatcherTag.mainDispatcher
            || tag == RuntimeDispatcherTag.mainImmediateDispatcher
    }

    func dispatchSync<T>(execute work: @escaping @Sendable () -> T) -> T {
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

    func dispatchAsync(execute work: @escaping @Sendable () -> Void) {
        // immediate dispatchers resume in place when already on their thread —
        // upstream `DispatchedContinuation` skips dispatch when
        // `isDispatchNeeded` returns false.
        if supportsImmediateDispatch, isCurrent {
            let saved = RuntimeDispatcher.current
            RuntimeDispatcher.current = self
            work()
            RuntimeDispatcher.current = saved
            return
        }
        queue.async { [self] in
            let saved = RuntimeDispatcher.current
            RuntimeDispatcher.current = self
            work()
            RuntimeDispatcher.current = saved
        }
    }

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
        if tag == RuntimeDispatcherTag.mainDispatcher
            || tag == RuntimeDispatcherTag.mainImmediateDispatcher,
           Thread.isMainThread { return true }
        return false
    }
}

/// KUU-2687: runtime backing for `CoroutineDispatcher.limitedParallelism` —
/// the upstream `LimitedDispatcher` view. Dispatched work enters a FIFO queue
/// and at most `parallelismLimit` of it runs on the underlying dispatcher at
/// once; a suspension frees its slot, which the next queued task takes.
/// Nested views enqueue their worker tasks through the parent view's own gate,
/// so chained views compound the limit the way upstream's do.
final class RuntimeLimitedDispatcher: RuntimeDispatcher, @unchecked Sendable {
    let base: RuntimeDispatcher
    let parallelismLimit: Int
    private let gateLock = NSLock()
    private var inFlight = 0
    private var pending: [@Sendable () -> Void] = []

    init(base: RuntimeDispatcher, parallelism: Int, displayName: String) {
        self.base = base
        self.parallelismLimit = parallelism
        super.init(queue: base.queue, tag: 0, displayName: displayName)
        self.tag = Int(bitPattern: Unmanaged.passUnretained(self).toOpaque())
    }

    override func dispatchAsync(execute work: @escaping @Sendable () -> Void) {
        gateLock.lock()
        pending.append(work)
        gateLock.unlock()
        pump()
    }

    override func dispatchSync<T>(execute work: @escaping @Sendable () -> T) -> T {
        if isCurrent {
            let saved = RuntimeDispatcher.current
            RuntimeDispatcher.current = self
            defer { RuntimeDispatcher.current = saved }
            return work()
        }
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = RuntimeSyncResultBox<T>()
        dispatchAsync {
            resultBox.value = work()
            semaphore.signal()
        }
        semaphore.wait()
        guard let value = resultBox.value else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: limited dispatcher dispatchSync produced no result")
        }
        return value
    }

    /// Start worker tasks until every permit is held. Each worker occupies its
    /// slot only while a task runs; a suspending coroutine releases it.
    private func pump() {
        while true {
            gateLock.lock()
            guard inFlight < parallelismLimit, !pending.isEmpty else {
                gateLock.unlock()
                return
            }
            inFlight += 1
            let work = pending.removeFirst()
            gateLock.unlock()
            base.dispatchAsync { [self] in
                let saved = RuntimeDispatcher.current
                RuntimeDispatcher.current = self
                work()
                RuntimeDispatcher.current = saved
                gateLock.lock()
                inFlight -= 1
                gateLock.unlock()
                pump()
            }
        }
    }
}

private final class RuntimeSyncResultBox<T>: @unchecked Sendable {
    var value: T?
}

/// KUU-2687: runtime backing for upstream `NamedDispatcher` — the view
/// `limitedParallelism(parallelism, name)` returns for dispatchers that already
/// satisfy the limit (Main) and for nested views whose requested parallelism
/// is not tighter than the parent's.
final class RuntimeNamedDispatcher: RuntimeDispatcher, @unchecked Sendable {
    let wrapped: RuntimeDispatcher
    private let peerLock = NSLock()
    private var cachedImmediatePeer: RuntimeDispatcher?

    init(wrapped: RuntimeDispatcher, name: String) {
        self.wrapped = wrapped
        // Upstream `NamedDispatcher` is a plain `CoroutineDispatcher` — never
        // a `MainCoroutineDispatcher` — whatever it wraps, and nested
        // `limitedParallelism` on it builds a real `LimitedDispatcher`
        // (only `MainDispatcher`/`LimitedDispatcher`/`Unconfined` override).
        super.init(
            queue: wrapped.queue,
            tag: 0,
            displayName: name,
            isUnconfined: wrapped.isUnconfined,
            supportsImmediateDispatch: wrapped.supportsImmediateDispatch,
            nominalTypeFqName: "kotlinx.coroutines.CoroutineDispatcher"
        )
        self.tag = Int(bitPattern: Unmanaged.passUnretained(self).toOpaque())
    }

    /// Upstream `NamedDispatcher.immediate` is a named view over the wrapped
    /// dispatcher's immediate peer.
    override var immediatePeer: RuntimeDispatcher {
        peerLock.lock()
        defer { peerLock.unlock() }
        if let cachedImmediatePeer { return cachedImmediatePeer }
        let peer = RuntimeNamedDispatcher(
            wrapped: wrapped.immediatePeer, name: displayName ?? "dispatcher"
        )
        cachedImmediatePeer = peer
        return peer
    }

    override var isCurrent: Bool {
        RuntimeDispatcher.current === self || wrapped.isCurrent
    }

    override func dispatchAsync(execute work: @escaping @Sendable () -> Void) {
        wrapped.dispatchAsync { [self] in
            let saved = RuntimeDispatcher.current
            RuntimeDispatcher.current = self
            work()
            RuntimeDispatcher.current = saved
        }
    }

    override func dispatchSync<T>(execute work: @escaping @Sendable () -> T) -> T {
        wrapped.dispatchSync { [self] in
            let saved = RuntimeDispatcher.current
            RuntimeDispatcher.current = self
            defer { RuntimeDispatcher.current = saved }
            return work()
        }
    }
}

enum RuntimeDispatcherTag {
    static let defaultDispatcher: Int = 0x4B4B_4401 // "KKD\x01"
    static let ioDispatcher: Int = 0x4B4B_4402 // "KKD\x02"
    static let mainDispatcher: Int = 0x4B4B_4403 // "KKD\x03"
    /// KUU-2687: `Dispatchers.Main.immediate` is a distinct object upstream
    /// (`MainCoroutineDispatcher.immediate`); keep a dedicated tag so contexts
    /// preserve it as the interceptor element and `is Dispatchers.Main` stays
    /// false like kotlinx's.
    static let mainImmediateDispatcher: Int = 0x4B4B_4404 // "KKD\x04"
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

private let runtimeDefaultDispatcher = RuntimeDispatcher(
    queue: DispatchQueue.global(qos: .default),
    tag: RuntimeDispatcherTag.defaultDispatcher,
    displayName: "Dispatchers.Default"
)
private let runtimeIODispatcher = RuntimeDispatcher(
    queue: DispatchQueue(label: "kk.dispatcher.io", qos: .utility, attributes: .concurrent),
    tag: RuntimeDispatcherTag.ioDispatcher,
    displayName: "Dispatchers.IO"
)
private let runtimeMainDispatcher = RuntimeDispatcher(
    queue: DispatchQueue.main,
    tag: RuntimeDispatcherTag.mainDispatcher,
    displayName: "Dispatchers.Main",
    nominalTypeFqName: "kotlinx.coroutines.MainCoroutineDispatcher"
)
/// KUU-2687: upstream `Dispatchers.Main.immediate` — same main queue, but a
/// dispatch requested while already on the main thread runs in place instead
/// of being re-queued.
private let runtimeImmediateMainDispatcher = RuntimeDispatcher(
    queue: DispatchQueue.main,
    tag: RuntimeDispatcherTag.mainImmediateDispatcher,
    displayName: "Dispatchers.Main.immediate",
    supportsImmediateDispatch: true,
    nominalTypeFqName: "kotlinx.coroutines.MainCoroutineDispatcher"
)

/// Wire the Main ↔ Main.immediate peer relation on first use; idempotent.
private func runtimeEnsureMainImmediatePeer() {
    runtimeMainDispatcher.setImmediatePeer(runtimeImmediateMainDispatcher)
}

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
    case RuntimeDispatcherTag.mainImmediateDispatcher:
        runtimeImmediateMainDispatcher
    default:
        runtimeDefaultDispatcher
    }
}

/// Register a strong-runtime-owned object pointer as a borrowed handle so it
/// can cross the ABI as a Kotlin object reference. Singletons are passed
/// unretained; freshly created views must pass `retain: true` or the pointer
/// would dangle once the local goes out of scope.
private func runtimeRegisterBorrowedHandle(
    _ object: RuntimeDispatcher, retain: Bool = false
) -> Int {
    let pointer = retain
        ? Unmanaged.passRetained(object).toOpaque()
        : Unmanaged.passUnretained(object).toOpaque()
    runtimeStorage.withGCLock { state in
        let key = UInt(bitPattern: pointer)
        state.objectPointers.insert(key)
        state.borrowedObjectPointers.insert(key)
    }
    return Int(bitPattern: pointer)
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
    case RuntimeDispatcherTag.mainImmediateDispatcher:
        runtimeImmediateMainDispatcher
    default:
        runtimeNamedDispatchers[0] // "Dispatchers.Default"
    }
    return runtimeRegisterBorrowedHandle(object)
}

// These globals own the objects; accessors register their pointers idempotently.
// Named IO uses its actual pool; Unconfined is distinguished without changing
// the legacy tag fallback used by unrelated invocation paths.
private let runtimeNamedDispatchers: [RuntimeDispatcher] = [
    RuntimeDispatcher(queue: runtimeDefaultDispatcher.queue, tag: RuntimeDispatcherTag.defaultDispatcher,
                      displayName: "Dispatchers.Default"),
    RuntimeDispatcher(queue: runtimeIODispatcher.queue, tag: RuntimeDispatcherTag.ioDispatcher,
                      displayName: "Dispatchers.IO"),
    RuntimeDispatcher(queue: runtimeDefaultDispatcher.queue, tag: RuntimeDispatcherTag.defaultDispatcher,
                      displayName: "Dispatchers.Unconfined", isUnconfined: true),
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

public func kk_dispatcher_default() -> Int {
    RuntimeDispatcherTag.defaultDispatcher
}

public func kk_dispatcher_io() -> Int {
    RuntimeDispatcherTag.ioDispatcher
}

@_cdecl("kk_dispatcher_main")
public func kk_dispatcher_main() -> Int {
    // `Dispatchers.Main` resolves to the dispatcher *object* (not the bare
    // scheduler tag) so it is `===`-equal to the element
    // `ctx[ContinuationInterceptor]` hands back — kotlinx's singleton
    // contract. Every scheduling path resolves tags and objects through the
    // same `runtimeResolveDispatcher`, so either form dispatches identically.
    runtimeRegisterBorrowedHandle(runtimeMainDispatcher)
}

// Memory-representation bridge: scheduler tags have no Kotlin vtable, while
// source-defined MainCoroutineDispatcher implementations retain their getter.
@_cdecl("__kk_dispatcher_immediate")
public func kk_dispatcher_immediate(
    _ dispatcher: Int, _ getterSlot: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    // Bare tags and runtime dispatcher objects resolve through the shared
    // path: Main answers its dedicated immediate object, everything else self.
    // A source-defined MainCoroutineDispatcher keeps its Kotlin getter below.
    if runtimeDispatcherIfSupported(dispatcher) != nil {
        return kk_dispatcher_immediate_or_self(dispatcher)
    }
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

/// KUU-2687: upstream `MainCoroutineDispatcher.immediate` resolution for
/// runtime dispatchers — `Dispatchers.Main` answers the immediate object,
/// `Dispatchers.Main.immediate` answers itself, all other dispatchers answer
/// themselves (kotlinx's default getter).
/// Resolves only real runtime dispatchers (tags + registered objects); a
/// source-defined `CoroutineDispatcher` heap object resolves to nil so bridge
/// entry points can leave it untouched instead of collapsing to Default.
private func runtimeDispatcherIfSupported(_ raw: Int) -> RuntimeDispatcher? {
    if isDispatcherTag(raw) { return runtimeResolveDispatcher(from: raw) }
    guard isRegisteredRuntimeObjectPointer(raw),
          let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let dispatcher = tryCast(ptr, to: RuntimeDispatcher.self)
    else { return nil }
    return dispatcher
}

@_cdecl("__kk_dispatcher_immediate_or_self")
public func kk_dispatcher_immediate_or_self(_ dispatcher: Int) -> Int {
    runtimeEnsureMainImmediatePeer()
    guard let resolved = runtimeDispatcherIfSupported(dispatcher) else {
        return dispatcher
    }
    return runtimeRegisterBorrowedHandle(resolved.immediatePeer)
}

/// KUU-2687: upstream `CoroutineDispatcher.limitedParallelism`. Returns a
/// dispatcher *view* whose concurrent task count never exceeds `parallelism`.
/// Nested view rules: a view on `Dispatchers.Main` is a named wrapper of Main
/// (upstream `namedOrThis`); a limited view whose stored parallelism is not
/// tighter than the requested one returns itself (a named wrapper of it when
/// `name` is given); otherwise the returned view queues through the parent
/// view so limits compound. Validation of `parallelism` and the Unconfined
/// rejection happen on the Kotlin side.
@_cdecl("__kk_dispatcher_limited_parallelism")
public func kk_dispatcher_limited_parallelism(
    _ dispatcher: Int, _ parallelism: Int, _ nameRaw: Int
) -> Int {
    runtimeEnsureMainImmediatePeer()
    // A source-defined dispatcher keeps its identity — the runtime cannot
    // delegate dispatch into a Kotlin `dispatch()` override from a view yet.
    guard let resolved = runtimeDispatcherIfSupported(dispatcher) else {
        return dispatcher
    }
    let name = nameRaw != 0
        ? extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw))
        : nil
    let view: RuntimeDispatcher
    var created = false
    if resolved.isMainDispatcher {
        // Upstream `MainDispatcher.limitedParallelism` → `namedOrThis`.
        if let name {
            view = RuntimeNamedDispatcher(wrapped: resolved, name: name)
            created = true
        } else {
            view = resolved
        }
    } else if let limited = resolved as? RuntimeLimitedDispatcher,
              parallelism >= limited.parallelismLimit {
        // Upstream `LimitedDispatcher.limitedParallelism`: the requested limit
        // is no tighter than the existing one → `namedOrThis`.
        if let name {
            view = RuntimeNamedDispatcher(wrapped: limited, name: name)
            created = true
        } else {
            view = limited
        }
    } else {
        view = RuntimeLimitedDispatcher(
            base: resolved,
            parallelism: parallelism,
            // Upstream: `name ?: "$dispatcher.limitedParallelism($parallelism)"`.
            displayName: name ?? "\(resolved.displayName ?? "dispatcher").limitedParallelism(\(parallelism))"
        )
        created = true
    }
    // `view === resolved` means upstream returned `this` — keep the caller's
    // raw handle so `Main.limitedParallelism(n) === Dispatchers.Main` holds.
    return view === resolved && !created
        ? dispatcher
        : runtimeRegisterBorrowedHandle(view, retain: created)
}

/// KUU-2687: Kotlin-side `Unconfined` check for `limitedParallelism` —
/// upstream throws `UnsupportedOperationException` on it.
@_cdecl("__kk_dispatcher_is_unconfined")
public func kk_dispatcher_is_unconfined(_ dispatcher: Int) -> Int {
    (runtimeDispatcherIfSupported(dispatcher)?.isUnconfined ?? false) ? 1 : 0
}

/// A simple heap-allocated, `@unchecked Sendable` box used to pass an integer
/// result from a `DispatchQueue.async` closure back to the waiting thread in
/// the non-coroutine (semaphore) fallback path of `kk_with_context`.
/// Synchronization is provided externally by a `DispatchSemaphore`.
private final class WithContextResultBox: @unchecked Sendable {
    var value: Int = 0
    var failure: Int = 0
}

@_cdecl("kk_with_context")
public func kk_with_context(_ dispatcherRaw: Int, _ blockFnPtr: Int, _ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    // A bare dispatcher tag still gets the child-context treatment: on JVM
    // every `withContext` installs a fresh child Job and exposes the
    // dispatcher element in the ambient context, not just reschedules.
    kk_with_context_full(dispatcherRaw, blockFnPtr, continuation, outThrown)
}

/// `restoreJobHandle`, when non-nil, is invoked exactly once at the point the
/// block's execution has genuinely finished -- across all three completion
/// paths below (inline, CORO-004 async, non-coroutine semaphore) -- so that
/// `kk_with_context_full`'s job-element override (e.g. NonCancellable) does
/// not leak past the end of this withContext block.
func kk_with_context_impl(
    _ dispatcherRaw: Int,
    _ blockFnPtr: Int,
    _ continuation: Int,
    outThrown: UnsafeMutablePointer<Int>? = nil,
    restoreJobHandle: (@Sendable (Int) -> Int)?
) -> Int {
    // `kk_with_context_full` resolves the context argument first; the raw may
    // be a scheduler tag or a dispatcher-object handle (limited/named views).
    // `runtimeResolveDispatcher` covers both, falling back to Default.
    let dispatcher = runtimeResolveDispatcher(from: dispatcherRaw)

    guard suspendEntryPoint(from: blockFnPtr) != nil else {
        // Clean up the continuation to avoid leaking coroutine state.
        _ = kk_coroutine_state_exit(continuation, 0)
        outThrown?.pointee = restoreJobHandle?(0) ?? 0
        return 0
    }

    // Capture the current coroutine scope so child launches inside the block
    // are registered with the correct scope on the target queue's thread.
    let parentScope = runtimeContinuationState(from: continuation)?.scope ?? RuntimeCoroutineScope.current

    // Propagate caller's scope to continuation context so that
    // runSuspendEntryLoopWithContinuation installs it under the fresh task key.
    // Without this, contState.scope would be nil for a freshly created
    // continuation and child coroutines launched inside the withContext block
    // would lose the parent scope — breaking structured concurrency.
    if let contState = runtimeContinuationState(from: continuation) {
        if contState.scope == nil { contState.scope = parentScope }
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
    if (dispatcher.tag == RuntimeDispatcherTag.mainDispatcher && Thread.isMainThread)
        || (dispatcher.supportsImmediateDispatch && dispatcher.isCurrent) {
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
        outThrown?.pointee = restoreJobHandle?(thrown) ?? thrown
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
                    let failure = restoreJobHandle?(thrown) ?? thrown
                    if failure != 0 {
                        callerState.resume(withException: failure)
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
        resultBox.failure = restoreJobHandle?(thrown) ?? thrown
        semaphore.signal()
    }

    // The dispatched block runs on a real dispatcher queue, so it is not itself
    // queued on any runBlocking event loop -- but this thread may be draining
    // one, and the block can join work that is. Drain rather than park.
    runtimeWaitDrainingEventLoop(semaphore)
    outThrown?.pointee = resultBox.failure
    return resultBox.value
}
