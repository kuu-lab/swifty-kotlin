import Foundation
import Dispatch

private let runtimeRunnableTypeID = runtimeStableNominalTypeID(fqName: "java.lang.Runnable")
private let runtimeExecutorTypeID = runtimeStableNominalTypeID(fqName: "java.util.concurrent.Executor")
private let runtimeExecutorServiceTypeID = runtimeStableNominalTypeID(fqName: "java.util.concurrent.ExecutorService")
private let runtimeDispatcherBridgeTypeID = runtimeStableNominalTypeID(
    fqName: "kotlinx.coroutines.CoroutineDispatcherRuntimeBridge"
)

private final class RuntimeObjectPin: @unchecked Sendable {
    let handle: Int

    init(raw: Int) {
        handle = runtimeIsHeapObject(raw) ? kk_pin_object(raw) : 0
    }

    func release() {
        if handle != 0 {
            _ = kk_unpin_object(handle)
        }
    }

    deinit { release() }
}

private final class RuntimeRunnableBox: @unchecked Sendable {
    let dispatcher: RuntimeDispatcher?
    let work: @Sendable () -> Void

    init(dispatcher: RuntimeDispatcher?, work: @escaping @Sendable () -> Void) {
        self.dispatcher = dispatcher
        self.work = work
    }
}

private func runtimeRegisterRunnable(
    dispatcher: RuntimeDispatcher?,
    work: @escaping @Sendable () -> Void
) -> Int {
    let box = RuntimeRunnableBox(dispatcher: dispatcher, work: work)
    let raw = registerRuntimeObject(box, typeID: runtimeRunnableTypeID)
    _ = kk_object_register_itable_iface(raw, Int(runtimeRunnableTypeID), 0)
    _ = kk_object_register_itable_method(
        raw,
        0,
        0,
        unsafeBitCast(runtimeRunnableRun, to: Int.self)
    )
    return raw
}

private func runtimeInvokeRunnable(_ raw: Int, outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    let methodRaw = kk_itable_lookup_dynamic(raw, Int(runtimeRunnableTypeID), 0)
    guard methodRaw != 0 else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Runnable.run is not implemented")
        return 0
    }
    let method = unsafeBitCast(
        methodRaw,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    return method(raw, outThrown)
}

private let runtimeRunnableRun: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    guard isRegisteredRuntimeObjectPointer(raw),
          let pointer = UnsafeMutableRawPointer(bitPattern: raw),
          let box = tryCast(pointer, to: RuntimeRunnableBox.self)
    else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Invalid native Runnable")
        return 0
    }
    let savedDispatcher = RuntimeDispatcher.current
    if let dispatcher = box.dispatcher {
        RuntimeDispatcher.current = dispatcher
    }
    defer {
        RuntimeDispatcher.current = savedDispatcher
        _ = runtimeReleaseObject(raw)
    }
    box.work()
    return 0
}

private func runtimeReportAsyncThrowable(_ thrown: Int) {
    if thrown != 0 {
        _ = kk_native_processUnhandledException(thrown, nil)
    }
}

private func runtimeReleaseRunnableBoxIfOwned(_ raw: Int) {
    guard isRegisteredRuntimeObjectPointer(raw),
          let pointer = UnsafeMutableRawPointer(bitPattern: raw),
          tryCast(pointer, to: RuntimeRunnableBox.self) != nil
    else {
        return
    }
    _ = runtimeReleaseObject(raw)
}

/// A runtime view of a source-defined CoroutineDispatcher. Its bridge method
/// enters the Kotlin override, while RuntimeRunnableBox restores the runtime's
/// dispatcher identity when the executor eventually invokes the task.
private final class RuntimeSourceCoroutineDispatcher: RuntimeDispatcher, @unchecked Sendable {
    let sourceHandle: Int
    private let sourcePin: RuntimeObjectPin

    init(sourceHandle: Int) {
        self.sourceHandle = sourceHandle
        sourcePin = RuntimeObjectPin(raw: sourceHandle)
        super.init(
            queue: DispatchQueue.global(qos: .default),
            tag: sourceHandle,
            displayName: "CoroutineDispatcher"
        )
    }

    override func dispatchAsync(execute work: @escaping @Sendable () -> Void) {
        let runnable = runtimeRegisterRunnable(dispatcher: self, work: work)
        let inherited = RuntimeContinuationState.current?.makeContinuationContext()
        let context = registerRuntimeObject(RuntimeCoroutineContext(
            dispatcher: sourceHandle,
            name: inherited?.name,
            exceptionHandler: inherited?.exceptionHandler,
            jobHandleRaw: inherited?.jobHandleRaw ?? 0,
            nameHandleRaw: inherited?.nameHandleRaw ?? 0,
            dispatcherHandleRaw: sourceHandle,
            extras: inherited?.extras ?? []
        ))
        let methodRaw = kk_itable_lookup_dynamic(
            sourceHandle,
            Int(runtimeDispatcherBridgeTypeID),
            0
        )
        guard methodRaw != 0 else {
            runtimeReleaseRunnableBoxIfOwned(runnable)
            runtimeReportAsyncThrowable(runtimeAllocateIllegalStateException(
                message: "CoroutineDispatcher dispatch bridge is missing"
            ))
            return
        }
        let method = unsafeBitCast(
            methodRaw,
            to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var thrown = 0
        _ = method(sourceHandle, context, runnable, &thrown)
        if thrown != 0 {
            runtimeReleaseRunnableBoxIfOwned(runnable)
        }
        runtimeReportAsyncThrowable(thrown)
    }

    override func dispatchSync<T>(execute work: @escaping @Sendable () -> T) -> T {
        if isCurrent { return work() }
        let semaphore = DispatchSemaphore(value: 0)
        let result = RuntimeDispatcherSyncResultBox<T>()
        dispatchAsync {
            result.value = work()
            semaphore.signal()
        }
        semaphore.wait()
        guard let value = result.value else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: source dispatcher dispatchSync produced no result")
        }
        return value
    }
}

private final class RuntimeDispatcherSyncResultBox<T>: @unchecked Sendable {
    var value: T?
}

func runtimeSourceCoroutineDispatcher(from raw: Int) -> RuntimeDispatcher? {
    guard runtimeIsSourceCoroutineDispatcher(raw) else {
        return nil
    }
    return RuntimeSourceCoroutineDispatcher(sourceHandle: raw)
}

func runtimeIsSourceCoroutineDispatcher(_ raw: Int) -> Bool {
    raw != 0 && runtimeRegisteredInterfaceSlot(
        objectRaw: raw,
        interfaceTypeID: runtimeDispatcherBridgeTypeID
    ) != nil
}

/// KUU-3719: resolves a `ContinuationInterceptor` element to a
/// `RuntimeDispatcher` when the interceptor is dispatcher-backed (a
/// `CoroutineDispatcher` object, a dispatcher tag, or a native dispatcher).
/// Returns nil for user-defined interceptors so their custom interception
/// still runs through `interceptContinuation`.
func runtimeInterceptorDispatcher(_ interceptorRaw: Int) -> RuntimeDispatcher? {
    guard interceptorRaw != 0 else {
        return nil
    }
    if let sourceDispatcher = runtimeSourceCoroutineDispatcher(from: interceptorRaw) {
        return sourceDispatcher
    }
    if isDispatcherTag(interceptorRaw) {
        return runtimeResolveDispatcher(from: interceptorRaw)
    }
    if isRegisteredRuntimeObjectPointer(interceptorRaw),
       let pointer = UnsafeMutableRawPointer(bitPattern: interceptorRaw),
       let dispatcher = tryCast(pointer, to: RuntimeDispatcher.self)
    {
        return dispatcher
    }
    return nil
}

private final class RuntimeDispatcherExecutorBox: @unchecked Sendable {
    let dispatcherHandle: Int
    private let dispatcherPin: RuntimeObjectPin

    init(dispatcherHandle: Int) {
        self.dispatcherHandle = dispatcherHandle
        dispatcherPin = RuntimeObjectPin(raw: dispatcherHandle)
    }
}

private let runtimeDispatcherExecutorExecute: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    executorRaw, runnableRaw, outThrown in
    outThrown?.pointee = 0
    guard isRegisteredRuntimeObjectPointer(executorRaw),
          let pointer = UnsafeMutableRawPointer(bitPattern: executorRaw),
          let executor = tryCast(pointer, to: RuntimeDispatcherExecutorBox.self)
    else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Invalid dispatcher Executor")
        return 0
    }
    let dispatcher = runtimeResolveDispatcher(from: executor.dispatcherHandle)
    let runnablePin = RuntimeObjectPin(raw: runnableRaw)
    dispatcher.dispatchAsync {
        defer {
            runnablePin.release()
            runtimeReleaseRunnableBoxIfOwned(runnableRaw)
        }
        var thrown = 0
        _ = runtimeInvokeRunnable(runnableRaw, outThrown: &thrown)
        runtimeReportAsyncThrowable(thrown)
    }
    return 0
}

@_cdecl("__kk_dispatcher_as_executor")
public func __kk_dispatcher_as_executor(
    _ dispatcherHandle: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let box = RuntimeDispatcherExecutorBox(dispatcherHandle: dispatcherHandle)
    let raw = registerRuntimeObject(box, typeID: runtimeExecutorTypeID)
    _ = kk_object_register_itable_iface(raw, Int(runtimeExecutorTypeID), 0)
    _ = kk_object_register_itable_method(
        raw,
        0,
        0,
        unsafeBitCast(runtimeDispatcherExecutorExecute, to: Int.self)
    )
    _ = kk_object_register_any_to_string(raw, unsafeBitCast(runtimeExecutorToString, to: Int.self))
    return raw
}

private let runtimeExecutorToString: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw, outThrown in
    outThrown?.pointee = 0
    if isRegisteredRuntimeObjectPointer(raw),
       let pointer = UnsafeMutableRawPointer(bitPattern: raw),
       let executor = tryCast(pointer, to: RuntimeDispatcherExecutorBox.self) {
        let dispatcher = runtimeResolveDispatcher(from: executor.dispatcherHandle)
        let name = dispatcher.displayName ?? "CoroutineDispatcher"
        return runtimeMakeStringRaw("Executor(\(name))")
    }
    return runtimeMakeStringRaw("Executor")
}

private final class RuntimeThreadPoolExecutorBox: @unchecked Sendable {
    let operationQueue: OperationQueue
    let name: String
    let scheduled: Bool
    private let stateLock = NSLock()
    private var didShutdown = false
    private var inFlightOperations = 0

    init(threadCount: Int, name: String, scheduled: Bool) {
        self.name = name
        self.scheduled = scheduled
        operationQueue = OperationQueue()
        operationQueue.name = name
        operationQueue.maxConcurrentOperationCount = threadCount
        operationQueue.qualityOfService = .userInitiated
    }

    func execute(_ runnableRaw: Int, outThrown: UnsafeMutablePointer<Int>?) {
        stateLock.lock()
        guard !didShutdown else {
            stateLock.unlock()
            outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Executor is shut down")
            return
        }
        inFlightOperations += 1
        let runnablePin = RuntimeObjectPin(raw: runnableRaw)
        let poolName = name
        let operation = BlockOperation {
            let previousThreadName = Thread.current.name
            if !poolName.isEmpty {
                Thread.current.name = poolName
            }
            defer { Thread.current.name = previousThreadName }
            var thrown = 0
            _ = runtimeInvokeRunnable(runnableRaw, outThrown: &thrown)
            runtimeReportAsyncThrowable(thrown)
        }
        operation.completionBlock = { [self] in
            runnablePin.release()
            runtimeReleaseRunnableBoxIfOwned(runnableRaw)
            stateLock.lock()
            inFlightOperations -= 1
            stateLock.unlock()
        }
        operationQueue.addOperation(operation)
        stateLock.unlock()
    }

    func shutdown(cancelPending: Bool = false) {
        stateLock.lock()
        didShutdown = true
        if cancelPending {
            operationQueue.cancelAllOperations()
        }
        stateLock.unlock()
    }

    var isShutdown: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return didShutdown
    }

    var isTerminated: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return didShutdown && inFlightOperations == 0
    }

    var description: String {
        let mode = scheduled ? "ScheduledThreadPool" : "ThreadPool"
        return "\(mode)(\(name), maxConcurrentOperationCount=\(operationQueue.maxConcurrentOperationCount))"
    }
}

private let runtimeThreadPoolExecute: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    executorRaw, runnableRaw, outThrown in
    outThrown?.pointee = 0
    guard isRegisteredRuntimeObjectPointer(executorRaw),
          let pointer = UnsafeMutableRawPointer(bitPattern: executorRaw),
          let executor = tryCast(pointer, to: RuntimeThreadPoolExecutorBox.self)
    else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Invalid thread pool Executor")
        return 0
    }
    executor.execute(runnableRaw, outThrown: outThrown)
    return 0
}

private let runtimeThreadPoolShutdown: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    executorRaw, outThrown in
    outThrown?.pointee = 0
    guard let executor = runtimeThreadPool(from: executorRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Invalid thread pool Executor")
        return 0
    }
    executor.shutdown()
    return 0
}

private let runtimeThreadPoolShutdownNow: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    executorRaw, outThrown in
    outThrown?.pointee = 0
    guard let executor = runtimeThreadPool(from: executorRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Invalid thread pool Executor")
        return 0
    }
    executor.shutdown(cancelPending: true)
    return registerRuntimeObject(
        RuntimeListBox(elements: []),
        typeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.List")
    )
}

private let runtimeThreadPoolIsShutdown: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    executorRaw, outThrown in
    outThrown?.pointee = 0
    guard let executor = runtimeThreadPool(from: executorRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Invalid thread pool Executor")
        return 0
    }
    return executor.isShutdown ? 1 : 0
}

private let runtimeThreadPoolIsTerminated: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    executorRaw, outThrown in
    outThrown?.pointee = 0
    guard let executor = runtimeThreadPool(from: executorRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Invalid thread pool Executor")
        return 0
    }
    return executor.isTerminated ? 1 : 0
}

private let runtimeThreadPoolClose: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    executorRaw, outThrown in
    outThrown?.pointee = 0
    guard let executor = runtimeThreadPool(from: executorRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Invalid thread pool Executor")
        return 0
    }
    executor.shutdown()
    return 0
}

private let runtimeThreadPoolToString: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    executorRaw, outThrown in
    outThrown?.pointee = 0
    return runtimeThreadPool(from: executorRaw).map { runtimeMakeStringRaw($0.description) }
        ?? runtimeMakeStringRaw("ThreadPoolExecutor")
}

private func runtimeThreadPool(from raw: Int) -> RuntimeThreadPoolExecutorBox? {
    guard isRegisteredRuntimeObjectPointer(raw),
          let pointer = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }
    return tryCast(pointer, to: RuntimeThreadPoolExecutorBox.self)
}

private func runtimeRegisterThreadPoolExecutor(_ executor: RuntimeThreadPoolExecutorBox) -> Int {
    let raw = registerRuntimeObject(executor, typeID: runtimeExecutorServiceTypeID)
    let executorID = runtimeExecutorTypeID
    let serviceID = runtimeExecutorServiceTypeID
    let javaCloseableID = runtimeStableNominalTypeID(fqName: "java.io.Closeable")
    let kotlinCloseableID = runtimeStableNominalTypeID(fqName: "kotlin.io.Closeable")
    let autoCloseableID = runtimeStableNominalTypeID(fqName: "kotlin.AutoCloseable")

    runtimeRegisterTypeEdge(childTypeID: serviceID, parentTypeID: executorID)
    runtimeRegisterTypeEdge(childTypeID: javaCloseableID, parentTypeID: autoCloseableID)
    runtimeRegisterTypeEdge(childTypeID: kotlinCloseableID, parentTypeID: autoCloseableID)
    runtimeRegisterTypeEdge(childTypeID: serviceID, parentTypeID: javaCloseableID)
    runtimeRegisterTypeEdge(childTypeID: serviceID, parentTypeID: kotlinCloseableID)

    _ = kk_object_register_itable_iface(raw, Int(serviceID), 0)
    _ = kk_object_register_itable_method(raw, 0, 0, unsafeBitCast(runtimeThreadPoolShutdown, to: Int.self))
    _ = kk_object_register_itable_method(raw, 0, 1, unsafeBitCast(runtimeThreadPoolShutdownNow, to: Int.self))
    _ = kk_object_register_itable_method(raw, 0, 2, unsafeBitCast(runtimeThreadPoolIsShutdown, to: Int.self))
    _ = kk_object_register_itable_method(raw, 0, 3, unsafeBitCast(runtimeThreadPoolIsTerminated, to: Int.self))

    _ = kk_object_register_itable_iface(raw, Int(executorID), 1)
    _ = kk_object_register_itable_method(raw, 1, 0, unsafeBitCast(runtimeThreadPoolExecute, to: Int.self))

    for (interfaceID, slot) in [(javaCloseableID, 2), (kotlinCloseableID, 3), (autoCloseableID, 4)] {
        _ = kk_object_register_itable_iface(raw, Int(interfaceID), slot)
        _ = kk_object_register_itable_method(raw, slot, 0, unsafeBitCast(runtimeThreadPoolClose, to: Int.self))
    }
    _ = kk_object_register_any_to_string(raw, unsafeBitCast(runtimeThreadPoolToString, to: Int.self))
    return raw
}

@_cdecl("__kk_dispatcher_default_execute")
public func __kk_dispatcher_default_execute(
    _ runnableRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let runnablePin = RuntimeObjectPin(raw: runnableRaw)
    runtimeResolveDispatcher(from: RuntimeDispatcherTag.defaultDispatcher).dispatchAsync {
        defer {
            runnablePin.release()
            runtimeReleaseRunnableBoxIfOwned(runnableRaw)
        }
        var thrown = 0
        _ = runtimeInvokeRunnable(runnableRaw, outThrown: &thrown)
        runtimeReportAsyncThrowable(thrown)
    }
    return 0
}

@_cdecl("__kk_coroutine_new_thread_pool_executor")
public func __kk_coroutine_new_thread_pool_executor(
    _ nThreads: Int,
    _ nameRaw: Int,
    _ scheduled: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard nThreads > 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Expected at least one thread, but got \(nThreads)"
        )
        return 0
    }
    guard let name = extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw)) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Thread pool name is null")
        return 0
    }
    return runtimeRegisterThreadPoolExecutor(
        RuntimeThreadPoolExecutorBox(threadCount: nThreads, name: name, scheduled: scheduled != 0)
    )
}
