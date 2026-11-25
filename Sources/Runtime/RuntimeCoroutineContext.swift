import Dispatch
import Foundation

private let runtimeCoroutineContextInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.coroutines.CoroutineContext"
)

private let runtimeEmptyCoroutineContextTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.coroutines.EmptyCoroutineContext"
)

enum RuntimeContextElementSlot: Hashable {
    case dispatcher
    case name
    case exceptionHandler
    case job
    case extra(key: Int, element: Int)
}

struct RuntimeContextElementPair: Hashable {
    let key: Int
    let element: Int
}

private nonisolated(unsafe) var runtimeEmptyCoroutineContextRaw: Int = 0

private func runtimeNoteEmptyCoroutineContext(_ raw: Int) -> Bool {
    guard raw != 0,
          runtimeObjectTypeID(rawValue: raw) == runtimeEmptyCoroutineContextTypeID
    else {
        return false
    }
    runtimeEmptyCoroutineContextRaw = raw
    return true
}

func runtimeNoteEmptyCoroutineContextClassID(_ classID: Int, raw: Int) {
    if classID == Int(runtimeEmptyCoroutineContextTypeID) {
        runtimeEmptyCoroutineContextRaw = raw
    }
}

final class RuntimeCoroutineContext: @unchecked Sendable {
    var dispatcher: Int  // 0 means "inherit from parent"
    var dispatcherHandleRaw: Int
    var name: String?
    var nameHandleRaw: Int
    var exceptionHandler: RuntimeExceptionHandlerBox?
    var jobHandleRaw: Int
    var extras: [(key: Int, element: Int)]
    var elementOrder: [RuntimeContextElementSlot]

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
        extras: [(key: Int, element: Int)] = [],
        elementOrder: [RuntimeContextElementSlot]? = nil
    ) {
        self.dispatcher = dispatcher
        self.dispatcherHandleRaw = dispatcherHandleRaw
        self.name = name
        self.nameHandleRaw = nameHandleRaw != 0 ? nameHandleRaw
            : name.map { registerRuntimeCoroutineName($0) } ?? 0
        self.exceptionHandler = exceptionHandler
        self.jobHandleRaw = jobHandleRaw
        self.extras = extras
        self.elementOrder = elementOrder ?? RuntimeCoroutineContext.defaultElementOrder(
            hasName: name != nil,
            hasExceptionHandler: exceptionHandler != nil,
            hasJob: jobHandleRaw != 0,
            hasDispatcher: dispatcherHandleRaw != 0 || dispatcher != 0,
            extras: extras
        )
    }

    static func defaultElementOrder(
        hasName: Bool,
        hasExceptionHandler: Bool,
        hasJob: Bool,
        hasDispatcher: Bool,
        extras: [(key: Int, element: Int)]
    ) -> [RuntimeContextElementSlot] {
        var slots: [RuntimeContextElementSlot] = []
        if hasName { slots.append(.name) }
        if hasExceptionHandler { slots.append(.exceptionHandler) }
        if hasJob { slots.append(.job) }
        var interceptorExtras: [RuntimeContextElementSlot] = []
        for extra in extras {
            if extra.key == runtimeContinuationInterceptorKeyRaw {
                interceptorExtras.append(.extra(key: extra.key, element: extra.element))
            } else {
                slots.append(.extra(key: extra.key, element: extra.element))
            }
        }
        if hasDispatcher { slots.append(.dispatcher) }
        slots.append(contentsOf: interceptorExtras)
        return slots
    }

    func elementPair(for slot: RuntimeContextElementSlot) -> RuntimeContextElementPair? {
        switch slot {
        case .dispatcher:
            let handle = dispatcherElementHandle
            return handle != 0
                ? RuntimeContextElementPair(key: runtimeContinuationInterceptorKeyRaw, element: handle)
                : nil
        case .name:
            return name != nil
                ? RuntimeContextElementPair(key: runtimeCoroutineNameKeyRaw, element: nameHandleRaw)
                : nil
        case .exceptionHandler:
            guard let handler = exceptionHandler else { return nil }
            return RuntimeContextElementPair(
                key: runtimeExceptionHandlerKeyRaw,
                element: Int(bitPattern: Unmanaged.passUnretained(handler).toOpaque())
            )
        case .job:
            return jobHandleRaw != 0
                ? RuntimeContextElementPair(key: runtimeJobKeyRaw, element: jobHandleRaw)
                : nil
        case .extra(let key, let element):
            return RuntimeContextElementPair(key: key, element: element)
        }
    }

    var memberElementPairs: Set<RuntimeContextElementPair> {
        var pairs = Set<RuntimeContextElementPair>()
        let dispatcherHandle = dispatcherElementHandle
        if dispatcherHandle != 0 {
            pairs.insert(RuntimeContextElementPair(
                key: runtimeContinuationInterceptorKeyRaw, element: dispatcherHandle))
        }
        if name != nil {
            pairs.insert(RuntimeContextElementPair(
                key: runtimeCoroutineNameKeyRaw, element: nameHandleRaw))
        }
        if let handler = exceptionHandler {
            pairs.insert(RuntimeContextElementPair(
                key: runtimeExceptionHandlerKeyRaw,
                element: Int(bitPattern: Unmanaged.passUnretained(handler).toOpaque())))
        }
        if jobHandleRaw != 0 {
            pairs.insert(RuntimeContextElementPair(key: runtimeJobKeyRaw, element: jobHandleRaw))
        }
        for extra in extras {
            pairs.insert(RuntimeContextElementPair(key: extra.key, element: extra.element))
        }
        return pairs
    }

    var orderedElements: [RuntimeContextElementPair] {
        let members = memberElementPairs
        return elementOrder
            .compactMap { elementPair(for: $0) }
            .filter { members.contains($0) }
    }

    func isInterceptorElementSlot(_ slot: RuntimeContextElementSlot) -> Bool {
        elementPair(for: slot)?.key == runtimeContinuationInterceptorKeyRaw
    }

    func installJobHandle(_ raw: Int) {
        jobHandleRaw = raw
        guard raw != 0, !elementOrder.contains(.job) else { return }
        let insertionIndex = elementOrder.firstIndex(where: isInterceptorElementSlot) ?? elementOrder.endIndex
        elementOrder.insert(.job, at: insertionIndex)
    }

    func installDispatcherElementHandle(_ raw: Int) {
        dispatcherHandleRaw = raw
        guard raw != 0,
              !elementOrder.contains(where: {
                  if case .dispatcher = $0 { return true }
                  return false
              })
        else {
            return
        }
        let insertionIndex = elementOrder.firstIndex(where: isInterceptorElementSlot) ?? elementOrder.endIndex
        elementOrder.insert(.dispatcher, at: insertionIndex)
    }

    func extraElement(for keyRaw: Int) -> Int? {
        for pair in extras where pair.key == keyRaw {
            return pair.element
        }
        return nil
    }

    func plus(_ other: RuntimeCoroutineContext) -> RuntimeCoroutineContext {
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
        let merged = RuntimeCoroutineContext(
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
        let mergedPairs = merged.memberElementPairs
        var claimedKeys = Set(other.orderedElements.map(\.key))
        if otherHasDispatcher {
            claimedKeys.insert(runtimeCoroutineDispatcherKeyRaw)
        }
        var newOrder: [RuntimeContextElementSlot] = []
        for slot in elementOrder where !isInterceptorElementSlot(slot) {
            if let pair = elementPair(for: slot),
               !claimedKeys.contains(pair.key),
               mergedPairs.contains(pair) {
                newOrder.append(slot)
            }
        }
        for slot in other.elementOrder where !other.isInterceptorElementSlot(slot) {
            newOrder.append(slot)
        }
        if let rightInterceptor = other.elementOrder.last(where: {
            other.isInterceptorElementSlot($0)
        }) {
            newOrder.append(rightInterceptor)
        } else if let leftInterceptor = elementOrder.last(where: {
            isInterceptorElementSlot($0)
        }),
            let pair = elementPair(for: leftInterceptor),
            !claimedKeys.contains(pair.key),
            mergedPairs.contains(pair) {
            newOrder.append(leftInterceptor)
        }
        merged.elementOrder = newOrder
        return merged
    }
}

private struct RuntimeCoroutineContextIdentity: Hashable {
    let dispatcher: Int
    let dispatcherHandleRaw: Int
    let name: String?
    let nameHandleRaw: Int
    let exceptionHandlerRaw: Int
    let jobHandleRaw: Int
    let extraKeys: [Int]
    let extraElements: [Int]
    var elementOrder: [RuntimeContextElementSlot]

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
        self.elementOrder = RuntimeCoroutineContext.defaultElementOrder(
            hasName: name != nil,
            hasExceptionHandler: exceptionHandler != nil,
            hasJob: jobHandleRaw != 0,
            hasDispatcher: dispatcherHandleRaw != 0 || dispatcher != 0,
            extras: extras
        )
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
        self.elementOrder = context.elementOrder
    }
}

private struct RuntimeCoroutineContextContentIdentity {
    let elements: Set<RuntimeContextElementPair>

    init(_ context: RuntimeCoroutineContext) {
        elements = context.memberElementPairs
    }

    func hasSameElements(as other: RuntimeCoroutineContextContentIdentity) -> Bool {
        guard elements.count == other.elements.count else { return false }
        var unmatched = Array(other.elements)
        for element in elements {
            guard let index = unmatched.firstIndex(where: {
                $0.key == element.key && runtimeValuesEqual($0.element, element.element)
            }) else {
                return false
            }
            unmatched.remove(at: index)
        }
        return unmatched.isEmpty
    }
}

private struct RuntimeWeakCoroutineContext {
    weak var context: RuntimeCoroutineContext?
}

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

func runtimeCanonicalCoroutineContext(_ context: RuntimeCoroutineContext) -> RuntimeCoroutineContext {
    RuntimeCoroutineContextCanonicalizer.shared.canonical(context)
}

func runtimeCoroutineContextsHaveSameContent(
    _ lhs: RuntimeCoroutineContext,
    _ rhs: RuntimeCoroutineContext
) -> Bool {
    RuntimeCoroutineContextContentIdentity(lhs).hasSameElements(
        as: RuntimeCoroutineContextContentIdentity(rhs)
    )
}

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

private let runtimeCoroutineNameTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.CoroutineName")
private let runtimeCoroutineElementTypeID = runtimeStableNominalTypeID(fqName: "kotlin.coroutines.CoroutineContext.Element")
private let runtimeCoroutineContextTypeID = runtimeStableNominalTypeID(fqName: "kotlin.coroutines.CoroutineContext")

private func registerRuntimeCoroutineName(_ name: String) -> Int {
    let raw = runtimeRegisterObject(RuntimeCoroutineNameBox(name: name))
    runtimeRegisterObjectType(rawValue: raw, classID: runtimeCoroutineNameTypeID)
    runtimeRegisterTypeEdge(childTypeID: runtimeCoroutineNameTypeID, parentTypeID: runtimeCoroutineElementTypeID)
    runtimeRegisterTypeEdge(childTypeID: runtimeCoroutineElementTypeID, parentTypeID: runtimeCoroutineContextTypeID)
    return raw
}

private let runtimeExceptionHandlerTypeID = runtimeStableNominalTypeID(
    fqName: "kotlinx.coroutines.CoroutineExceptionHandler"
)

func runtimeRegisterExceptionHandler(_ box: RuntimeExceptionHandlerBox) -> Int {
    let raw = runtimeRegisterObject(box)
    runtimeRegisterObjectType(rawValue: raw, classID: runtimeExceptionHandlerTypeID)
    runtimeRegisterTypeEdge(
        childTypeID: runtimeExceptionHandlerTypeID,
        parentTypeID: runtimeCoroutineElementTypeID
    )
    runtimeRegisterTypeEdge(
        childTypeID: runtimeCoroutineElementTypeID,
        parentTypeID: runtimeCoroutineContextTypeID
    )
    return raw
}

private final class RuntimeCoroutineNameKey: @unchecked Sendable {}
private let runtimeCoroutineNameKeyRaw = runtimeRegisterObject(RuntimeCoroutineNameKey())

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

private final class RuntimeCoroutineDispatcherKey: @unchecked Sendable {}
private let runtimeCoroutineDispatcherKeyRaw = runtimeRegisterObject(RuntimeCoroutineDispatcherKey())

@_cdecl("kk_coroutine_dispatcher_key")
public func kk_coroutine_dispatcher_key() -> Int {
    runtimeTypedCoroutineContextKey(
        runtimeCoroutineDispatcherKeyRaw, fqName: "kotlinx.coroutines.CoroutineDispatcher.Key"
    )
}

private final class RuntimeExceptionHandlerKey: @unchecked Sendable {}
private let runtimeExceptionHandlerKeyRaw = runtimeRegisterObject(RuntimeExceptionHandlerKey())

@_cdecl("kk_exception_handler_key")
public func kk_exception_handler_key() -> Int {
    runtimeExceptionHandlerKeyRaw
}

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

// Hoisted: `kk_itable_lookup_dynamic` consults this interceptor on every
/// dynamic dispatch, so the FNV hash must not be recomputed per call.
private let runtimeCoroutineContextElementInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.coroutines.CoroutineContext.Element"
)

func runtimeCoroutineContextElementMethod(_ receiver: Int, _ interfaceTypeID: Int, _ methodSlot: Int) -> Int? {
    guard interfaceTypeID == Int(runtimeCoroutineContextElementInterfaceTypeID) else {
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
            runtimeThrowingBridge(outThrown) {
                let element = kk_context_get(receiver, key)
                return element == 0 ? runtimeNullSentinelInt : element
            }
        }
        return unsafeBitCast(get, to: Int.self)
    case 1:
        let fold: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
            receiver, initial, operation, closure, outThrown in
            runtimeThrowingBridge(outThrown) {
                return kk_context_fold(receiver, initial, operation, closure, outThrown)
            }
        }
        return unsafeBitCast(fold, to: Int.self)
    case 2:
        let minusKey: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { receiver, key, outThrown in
            runtimeThrowingBridge(outThrown) {
                return kk_context_minusKey(receiver, key)
            }
        }
        return unsafeBitCast(minusKey, to: Int.self)
    case 3:
        let getter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { receiver, outThrown in
            runtimeThrowingBridge(outThrown) {
                return runtimeCoroutineElementKeyHandle(for: receiver)
            }
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

func runtimeRegisterObject<T: AnyObject>(_ object: T) -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(object).toOpaque())
    runtimeStorage.withGCLock { state in
        let key = UInt(bitPattern: ptr)
        state.objectPointers.insert(key)
        recordRetainedBoxManagedHeapFieldsLocked(object, owner: key, state: &state)
    }
    return Int(bitPattern: ptr)
}

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
    return registerRuntimeCoroutineName(nameStr)
}

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
    return runtimeRegisterExceptionHandler(box)
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

@_cdecl("kk_context_plus")
public func kk_context_plus(_ leftRaw: Int, _ rightRaw: Int) -> Int {
    if runtimeNoteEmptyCoroutineContext(rightRaw) {
        return leftRaw
    }
    if runtimeNoteEmptyCoroutineContext(leftRaw) {
        return rightRaw
    }
    let leftCtx = resolveToCoroutineContext(leftRaw)
    let rightCtx = resolveToCoroutineContext(rightRaw)
    let merged = leftCtx.plus(rightCtx)
    let elements = merged.orderedElements
    if elements.isEmpty {
        return runtimeEmptyCoroutineContextRaw != 0
            ? runtimeEmptyCoroutineContextRaw
            : runtimeRegisterObject(merged)
    }
    if elements.count == 1 {
        return elements[0].element
    }
    return runtimeRegisterObject(merged)
}

@_cdecl("__kk_context_plus_dispatch")
public func __kk_context_plus_dispatch(
    _ contextRaw: Int,
    _ otherRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
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
}

/// Kotlin-facing callers (`CoroutineContext.get`, `Element.get`, the
/// `CoroutineName`/`Job` member bridges, and itable thunks inheriting them)
/// declare an `E?` result, so an absent key must report the null sentinel —
/// never raw 0, which crosses the erased boundary as `kotlin.Unit`
/// (KUU-3752). The two-element `kk_context_get` ABI is therefore
/// sentinel-based; internal callers that modeled "absent" as 0 already pass
/// `runtimeNullSentinelInt` through their `== 0 ? sentinel : result`
/// normalization unchanged.
@_cdecl("kk_context_get")
public func kk_context_get(_ contextRaw: Int, _ keyRaw: Int) -> Int {
    let ctx = resolveToCoroutineContext(contextRaw)
    if let match = runtimeCoroutineContextElementHandle(for: keyRaw, in: ctx) {
        return match
    }
    return runtimeNullSentinelInt
}

@_cdecl("__kk_context_get_dispatch")
public func __kk_context_get_dispatch(
    _ contextRaw: Int,
    _ keyRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
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
    return runtimeThrowingBridge(outThrown) {
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
        for pair in ctx.orderedElements {
            var thrown = 0
            let result = lambda(closureRaw, acc, pair.element, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return acc
            }
            acc = maybeUnbox(result)
        }
        return acc
    }
}

@_cdecl("kk_context_minusKey")
public func kk_context_minusKey(_ contextRaw: Int, _ keyRaw: Int) -> Int {
    let resolved = resolveToCoroutineContext(contextRaw)
    let reduced = runtimeCoroutineContextRemovingElement(for: keyRaw, from: resolved)
    let elements = reduced.orderedElements
    if elements.isEmpty {
        return runtimeEmptyCoroutineContextRaw != 0
            ? runtimeEmptyCoroutineContextRaw
            : runtimeRegisterObject(reduced)
    }
    if elements.count == 1 {
        return elements[0].element
    }
    return runtimeRegisterObject(reduced)
}

@_cdecl("__kk_context_minusKey_dispatch")
public func __kk_context_minusKey_dispatch(
    _ contextRaw: Int,
    _ keyRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
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
}

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

@_cdecl("__kk_continuation_intercepted")
public func __kk_continuation_intercepted(
    _ continuationRaw: Int,
    _ interceptorKey: Int = 0,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) -> Int {
    return runtimeThrowingBridge(outThrown) {
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

final class RuntimeGeneratedContinuation: KKContinuation, @unchecked Sendable {
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

@_cdecl("__kk_start_coroutine_cancellable")
public func __kk_start_coroutine_cancellable(
    _ functionRaw: Int,
    _ completionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>? = nil
) {
    runtimeThrowingBridge(outThrown) {
        var thrown = 0
        let coroutine = kk_create_coroutine_unintercepted_no_receiver(
            functionRaw, 0, completionRaw
        )
        let intercepted = __kk_continuation_intercepted(
            coroutine, kk_continuation_interceptor_key(), &thrown
        )
        if thrown == 0 {
            if isRegisteredRuntimeObjectPointer(intercepted),
               let ptr = UnsafeMutableRawPointer(bitPattern: intercepted),
               let wrapper = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? KKInterceptedContinuation,
               let generated = wrapper.continuation as? RuntimeGeneratedContinuation
            {
                generated.state.markCancellableCoroutineStart()
            }
            __kk_coroutine_continuation_resume_with(
                intercepted,
                runtimeResultSuccess(kk_box_unit(0)),
                &thrown
            )
        }
        if thrown != 0 {
            __kk_coroutine_continuation_resume_with(
                completionRaw, runtimeResultFailure(thrown), nil
            )
            outThrown?.pointee = thrown
        }
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
        || runtimeIsSourceCoroutineDispatcher(receiver)
}

@_cdecl("__kk_job_is_runtime")
public func kk_job_is_runtime(_ receiver: Int) -> Int {
    return runtimeJobHandle(from: receiver) != nil
        || runtimeAsyncTask(from: receiver) != nil ? 1 : 0
}

@_cdecl("__kk_is_native_dispatcher")
public func kk_is_native_dispatcher(_ receiver: Int) -> Int {
    runtimeIsNativeDispatcher(receiver) ? 1 : 0
}

@_cdecl("__kk_dispatcher_default_method")
public func kk_dispatcher_default_method(_ receiver: Int, _ virtualMethod: Int, _ defaultMethod: Int) -> Int {
    runtimeIsNativeDispatcher(receiver) ? defaultMethod : virtualMethod
}

private let runtimeContinuationInterceptorInterfaceTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.coroutines.ContinuationInterceptor"
)

func runtimeDispatcherInterceptorMethod(_ receiver: Int, _ interfaceTypeID: Int, _ methodSlot: Int) -> Int? {
    guard interfaceTypeID == Int(runtimeContinuationInterceptorInterfaceTypeID),
          runtimeIsNativeDispatcher(receiver)
    else {
        return nil
    }
    switch methodSlot {
    case 0:
        let intercept: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { receiver, continuation, outThrown in
            runtimeThrowingBridge(outThrown) {
                return kk_continuation_interceptor_intercept_continuation(receiver, continuation)
            }
        }
        return unsafeBitCast(intercept, to: Int.self)
    case 1:
        let release: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
            runtimeThrowingBridge(outThrown) {
                return 0
            }
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
        let handle = ctx.dispatcherElementHandle
        let dispatcherElement: Int? = handle != 0
            ? (isDispatcherTag(handle) ? runtimeDispatcherObjectHandle(forTag: handle) : handle)
            : nil
        if keyRaw == runtimeContinuationInterceptorKeyRaw {
            return dispatcherElement ?? ctx.extraElement(for: runtimeContinuationInterceptorKeyRaw)
        }
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

private func runtimeCoroutineContextRemovingElement(for keyRaw: Int, from ctx: RuntimeCoroutineContext) -> RuntimeCoroutineContext {
    let next = runtimeCoroutineContextRemovingElementFields(for: keyRaw, from: ctx)
    let members = next.memberElementPairs
    next.elementOrder = next.elementOrder.filter { slot in
        next.elementPair(for: slot).map { members.contains($0) } ?? false
    }
    return next
}

private func runtimeCoroutineContextRemovingElementFields(for keyRaw: Int, from ctx: RuntimeCoroutineContext) -> RuntimeCoroutineContext {
    let next = RuntimeCoroutineContext(
        dispatcher: ctx.dispatcher,
        name: ctx.name,
        exceptionHandler: ctx.exceptionHandler,
        jobHandleRaw: ctx.jobHandleRaw,
        nameHandleRaw: ctx.nameHandleRaw,
        dispatcherHandleRaw: ctx.dispatcherHandleRaw,
        extras: ctx.extras.filter { pair in
            pair.key != keyRaw
                && !(keyRaw == runtimeCoroutineDispatcherKeyRaw
                     && pair.key == runtimeContinuationInterceptorKeyRaw)
        },
        elementOrder: ctx.elementOrder
    )
    if keyRaw == runtimeCoroutineNameKeyRaw {
        next.name = nil
        next.nameHandleRaw = 0
        return next
    }
    if keyRaw == runtimeContinuationInterceptorKeyRaw || keyRaw == runtimeCoroutineDispatcherKeyRaw {
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
        return 1
    }
    return job.isActiveSnapshot() ? 1 : 0
}

@_cdecl("kk_context_get_job")
public func kk_context_get_job(_ contextRaw: Int) -> Int {
    let ctx = resolveToCoroutineContext(contextRaw)
    return ctx.jobHandleRaw != 0 ? ctx.jobHandleRaw
        : (ctx.extraElement(for: runtimeJobKeyRaw)
            .flatMap { runtimeExtraElementGet($0, key: runtimeJobKeyRaw) } ?? 0)
}

public func kk_context_get_name(_ contextRaw: Int) -> Int {
    guard contextRaw != 0 else {
        return 0
    }
    guard let name = resolveToCoroutineContext(contextRaw).name else {
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
    return runtimeThrowingBridge(outThrown) {
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
}

private func runtimeInstallWithContextChildContext(
    overrideContext resolvedCtx: RuntimeCoroutineContext,
    continuation: Int
) -> (@Sendable (Int) -> Int)? {
    guard let contState = runtimeContinuationState(from: continuation) else {
        return nil
    }

    let savedBuilderContext = contState.builderContext
    let savedJobHandle = contState.jobHandle
    let savedScope = contState.scope
    let parentContext = RuntimeContinuationState.current?.makeContinuationContext()
        ?? RuntimeCoroutineScope.current?.context
        ?? RuntimeCoroutineContext()
    let mergedContext = parentContext.plus(resolvedCtx)

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
        var joined: Set<Int> = []
        while let blockJob {
            let children = blockJob.registeredChildrenSnapshot().filter { !joined.contains($0) }
            if children.isEmpty { break }
            for child in children {
                joined.insert(child)
                guard let childJob = runtimeJobHandle(from: child)
                    ?? runtimeAsyncTask(from: child)?.completionJob else { continue }
                _ = childJob.join()
                let failure = childJob.completionSnapshot(handoff: .exception).exception
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
        let settledCause = blockJob?.completionSnapshot(handoff: .exception).exception ?? failure
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

private func runtimeSourceContextElementKey(_ raw: Int) -> Int? {
    guard UnsafeMutableRawPointer(bitPattern: raw) != nil else {
        return nil
    }
    let elementTypeID = runtimeStableNominalTypeID(fqName: "kotlin.coroutines.CoroutineContext.Element")
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
    if raw == 0 || runtimeNoteEmptyCoroutineContext(raw) {
        return RuntimeCoroutineContext()
    }
    if isDispatcherTag(raw) {
        return RuntimeCoroutineContext(dispatcher: raw)
    }
    if runtimeIsSourceCoroutineDispatcher(raw) {
        runtimePinHeapObjectIfNeeded(raw)
        return RuntimeCoroutineContext(dispatcher: raw, dispatcherHandleRaw: raw)
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
    var tag: Int
    let displayName: String?
    let isUnconfined: Bool
    let supportsImmediateDispatch: Bool
    weak var blockingEventLoop: RuntimeEventLoop?
    private var immediatePeerStorage: RuntimeDispatcher?

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
        registerCoroutineDispatcherTypeEdgesOnce()
        runtimeRegisterObjectType(
            rawValue: Int(bitPattern: Unmanaged.passUnretained(self).toOpaque()),
            classID: runtimeStableNominalTypeID(fqName: nominalTypeFqName)
        )
    }

    var immediatePeer: RuntimeDispatcher { immediatePeerStorage ?? self }
    func setImmediatePeer(_ peer: RuntimeDispatcher) { immediatePeerStorage = peer }

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

final class RuntimeLimitedDispatcher: RuntimeDispatcher, @unchecked Sendable {
    let base: RuntimeDispatcher
    let parallelismLimit: Int
    private let gateLock = NSLock()
    private var inFlight = 0
    private var pending: [@Sendable () -> Void] = []

    init(base: RuntimeDispatcher, parallelism: Int, name: String?) {
        self.base = base
        self.parallelismLimit = parallelism
        let displayNamePrefix = base.displayName ?? "dispatcher"
        super.init(
            queue: base.queue,
            tag: 0,
            displayName: name ?? "\(displayNamePrefix).limitedParallelism(\(parallelism))"
        )
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
private let runtimeImmediateMainDispatcher = RuntimeDispatcher(
    queue: DispatchQueue.main,
    tag: RuntimeDispatcherTag.mainImmediateDispatcher,
    displayName: "Dispatchers.Main.immediate",
    supportsImmediateDispatch: true,
    nominalTypeFqName: "kotlinx.coroutines.MainCoroutineDispatcher"
)

private func runtimeEnsureMainImmediatePeer() {
    runtimeMainDispatcher.setImmediatePeer(runtimeImmediateMainDispatcher)
}

func runtimeResolveDispatcher(from raw: Int) -> RuntimeDispatcher {
    if let sourceDispatcher = runtimeSourceCoroutineDispatcher(from: raw) {
        return sourceDispatcher
    }
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
    runtimeRegisterBorrowedHandle(runtimeMainDispatcher)
}

@_cdecl("__kk_dispatcher_immediate")
public func kk_dispatcher_immediate(
    _ dispatcher: Int, _ getterSlot: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
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
}

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

@_cdecl("__kk_dispatcher_limited_parallelism")
public func kk_dispatcher_limited_parallelism(
    _ dispatcher: Int, _ parallelism: Int, _ nameRaw: Int
) -> Int {
    runtimeEnsureMainImmediatePeer()
    guard let resolved = runtimeDispatcherIfSupported(dispatcher) else {
        return dispatcher
    }
    let name = nameRaw != 0
        ? extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw))
        : nil
    let view: RuntimeDispatcher
    var created = false
    if resolved.isMainDispatcher {
        if let name {
            view = RuntimeNamedDispatcher(wrapped: resolved, name: name)
            created = true
        } else {
            view = resolved
        }
    } else if let limited = resolved as? RuntimeLimitedDispatcher,
              parallelism >= limited.parallelismLimit {
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
            name: name
        )
        created = true
    }
    return view === resolved && !created
        ? dispatcher
        : runtimeRegisterBorrowedHandle(view, retain: created)
}

@_cdecl("__kk_dispatcher_is_unconfined")
public func kk_dispatcher_is_unconfined(_ dispatcher: Int) -> Int {
    (runtimeDispatcherIfSupported(dispatcher)?.isUnconfined ?? false) ? 1 : 0
}

@_cdecl("__kk_dispatcher_is_dispatch_needed")
public func kk_dispatcher_is_dispatch_needed(_ dispatcher: Int) -> Int {
    guard let resolved = runtimeDispatcherIfSupported(dispatcher) else { return 1 }
    if resolved.isUnconfined { return 0 }
    if resolved.supportsImmediateDispatch, resolved.isCurrent { return 0 }
    return 1
}

@_cdecl("kk_vtable_lookup_or_default")
public func kk_vtable_lookup_or_default(_ receiver: Int, _ slot: Int, _ defaultMethod: Int) -> Int {
    if runtimeDispatcherIfSupported(receiver) != nil {
        return defaultMethod
    }
    return kk_vtable_lookup(receiver, slot)
}

private final class WithContextResultBox: @unchecked Sendable {
    var value: Int = 0
    var failure: Int = 0
}

@_cdecl("kk_with_context")
public func kk_with_context(_ dispatcherRaw: Int, _ blockFnPtr: Int, _ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    kk_with_context_full(dispatcherRaw, blockFnPtr, continuation, outThrown)
}

func kk_with_context_impl(
    _ dispatcherRaw: Int,
    _ blockFnPtr: Int,
    _ continuation: Int,
    outThrown: UnsafeMutablePointer<Int>? = nil,
    restoreJobHandle: (@Sendable (Int) -> Int)?
) -> Int {
    let dispatcher = runtimeResolveDispatcher(from: dispatcherRaw)

    guard suspendEntryPoint(from: blockFnPtr) != nil else {
        _ = kk_coroutine_state_exit(continuation, 0)
        outThrown?.pointee = restoreJobHandle?(0) ?? 0
        return 0
    }

    let parentScope = runtimeContinuationState(from: continuation)?.scope ?? RuntimeCoroutineScope.current

    // Propagate caller's scope to continuation context so that
    // runSuspendEntryLoopWithContinuation installs it under the fresh task key.
    // Without this, contState.scope would be nil for a freshly created
    // continuation and child coroutines launched inside the withContext block
    // would lose the parent scope — breaking structured concurrency.
    if let contState = runtimeContinuationState(from: continuation) {
        if contState.scope == nil { contState.scope = parentScope }
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

    if let callerState = RuntimeContinuationState.current {
        let capturedContinuation = continuation
        dispatcher.dispatchAsync {
            let savedScope = RuntimeCoroutineScope.current
            RuntimeCoroutineScope.current = parentScope
            defer { RuntimeCoroutineScope.current = savedScope }
            _ = runSuspendEntryLoopWithContinuation(
                entryPointRaw: blockFnPtr,
                continuation: capturedContinuation,
                onCompletion: { result, thrown, resumeThrown in
                    let failure = restoreJobHandle?(thrown) ?? thrown
                    if failure != 0 {
                        callerState.resume(withException: failure, outThrown: resumeThrown)
                    } else {
                        callerState.resume(with: result, outThrown: resumeThrown)
                    }
                }
            )
        }
        return Int(bitPattern: kk_coroutine_suspended())
    }

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

func runtimeCoroutineContextToString(_ context: RuntimeCoroutineContext) -> String {
    let elements = context.orderedElements
    if elements.isEmpty {
        return "EmptyCoroutineContext"
    }
    let rendered = elements.map { runtimeCoroutineContextElementToString($0.element) }
    return rendered.count == 1 ? rendered[0] : "[\(rendered.joined(separator: ", "))]"
}

private func runtimeCoroutineContextElementToString(_ element: Int) -> String {
    if isDispatcherTag(element) {
        return runtimeResolveDispatcher(from: element).displayName
            ?? runtimeRenderAnyForPrint(element)
    }
    if let override = runtimeAnyToStringOverride(element),
       let text = extractString(from: override) {
        return text
    }
    if let ptr = UnsafeMutableRawPointer(bitPattern: element),
       let nameBox = tryCast(ptr, to: RuntimeCoroutineNameBox.self) {
        return "CoroutineName(\(nameBox.name))"
    }
    return runtimeRenderAnyForPrint(element)
}
