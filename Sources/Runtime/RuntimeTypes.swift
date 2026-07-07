import Foundation

public struct KTypeInfo {
    public let fqName: UnsafePointer<CChar>
    public let instanceSize: UInt32
    public let fieldCount: UInt32
    public let fieldOffsets: UnsafePointer<UInt32>
    public let vtableSize: UInt32
    public let vtable: UnsafePointer<UnsafeRawPointer>
    public let itable: UnsafeRawPointer?
    public let gcDescriptor: UnsafeRawPointer?

    public init(
        fqName: UnsafePointer<CChar>,
        instanceSize: UInt32,
        fieldCount: UInt32,
        fieldOffsets: UnsafePointer<UInt32>,
        vtableSize: UInt32,
        vtable: UnsafePointer<UnsafeRawPointer>,
        itable: UnsafeRawPointer?,
        gcDescriptor: UnsafeRawPointer?
    ) {
        self.fqName = fqName
        self.instanceSize = instanceSize
        self.fieldCount = fieldCount
        self.fieldOffsets = fieldOffsets
        self.vtableSize = vtableSize
        self.vtable = vtable
        self.itable = itable
        self.gcDescriptor = gcDescriptor
    }
}

struct KKObjHeader {
    var typeInfo: UnsafePointer<KTypeInfo>?
    var flags: UInt32
    var size: UInt32
}

public protocol KKContinuation {
    var context: UnsafeMutableRawPointer? { get }
    func resumeWith(_ result: UnsafeMutableRawPointer?)
}

typealias KKSuspendEntryPoint = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKThunkEntryPoint = @convention(c) (UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureThunkEntryPoint = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint1 = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint2 = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint3 = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint1 = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint2 = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint3 = @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKDelegateObserverEntryPoint = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int

final class RuntimeStringBox {
    let value: String

    init(_ value: String) {
        self.value = value
    }
}

struct RuntimeValue {
    static let rawTag = 0
    static let stringTag = 1
    static let charTag = 2

    var tag: Int
    var payload0: Int
    var payload1: Int
    var payload2: Int
    var payload3: Int

    init(raw: Int) {
        self.tag = Self.rawTag
        self.payload0 = raw
        self.payload1 = 0
        self.payload2 = 0
        self.payload3 = 0
    }

    init(stringData data: Int, length: Int, byteCount: Int, hash: Int) {
        self.tag = Self.stringTag
        self.payload0 = data
        self.payload1 = length
        self.payload2 = byteCount
        self.payload3 = hash
    }

    init(charScalar value: Int) {
        self.tag = Self.charTag
        self.payload0 = value
        self.payload1 = 0
        self.payload2 = 0
        self.payload3 = 0
    }

    var legacyRawValue: Int {
        guard tag == Self.stringTag else {
            return payload0
        }
        guard let data = UnsafePointer<UInt8>(bitPattern: payload0) else {
            return 0
        }
        let string = runtimeStringFromFlatFields(
            data: data,
            length: payload1,
            byteCount: payload2,
            hash: payload3
        )
        return registerRuntimeObject(RuntimeStringBox(string))
    }

    var childReferenceRawValue: Int? {
        guard tag == Self.rawTag, payload0 != 0 else {
            return nil
        }
        return payload0
    }
}

class RuntimeThrowableBox {
    let message: String
    var cause: Int
    /// Suppressed exceptions (STDLIB-EXCEPT-105).
    /// Stores raw Int pointers to other RuntimeThrowableBox instances.
    var suppressed: [Int] = []

    var exceptionFQName: String {
        "kotlin.Throwable"
    }

    var exceptionHierarchyFQNames: [String] {
        [exceptionFQName]
    }

    var renderedMessage: String {
        message
    }

    init(message: String, cause: Int = 0) {
        self.message = message
        self.cause = cause
    }
}

final class RuntimeUninitializedPropertyAccessExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.UninitializedPropertyAccessException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.UninitializedPropertyAccessException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        "UninitializedPropertyAccessException: \(message)"
    }
}

/// Distinct type used to identify CancellationException at runtime.
/// The runtime checks `is RuntimeCancellationBox` to distinguish cancellation from
/// regular throwables (CORO-002 / spec.md J17).
final class RuntimeCancellationBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlin.CancellationException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.CancellationException",
            "kotlinx.coroutines.CancellationException",
            "CancellationException",
            "kotlin.IllegalStateException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        message
    }

    override init(message: String, cause: Int = 0) {
        super.init(message: message, cause: cause)
    }
}

class RuntimeArrayBox {
    private var storage: [RuntimeValue]

    var values: [RuntimeValue] {
        get {
            storage
        }
        set {
            storage = newValue
        }
    }

    var elements: [Int] {
        get {
            storage.map(\.legacyRawValue)
        }
        set {
            storage = newValue.map { RuntimeValue(raw: $0) }
        }
    }

    init(length: Int) {
        storage = Array(repeating: RuntimeValue(raw: 0), count: max(0, length))
    }
}

final class RuntimeObjectBox: RuntimeArrayBox {
    let classID: Int64

    init(length: Int, classID: Int64) {
        self.classID = classID
        super.init(length: length)
    }
}

final class RuntimePairBox {
    let firstValue: RuntimeValue
    let secondValue: RuntimeValue

    var first: Int { firstValue.legacyRawValue }
    var second: Int { secondValue.legacyRawValue }

    init(first: Int, second: Int) {
        self.firstValue = RuntimeValue(raw: first)
        self.secondValue = RuntimeValue(raw: second)
    }

    init(firstValue: RuntimeValue, secondValue: RuntimeValue) {
        self.firstValue = firstValue
        self.secondValue = secondValue
    }
}

final class RuntimeTripleBox {
    let first: Int
    let second: Int
    let third: Int

    init(first: Int, second: Int, third: Int) {
        self.first = first
        self.second = second
        self.third = third
    }
}

final class RuntimeIntBox {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }
}

final class RuntimeBoolBox {
    let value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}

final class RuntimeLongBox {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }
}

final class RuntimeFloatBox {
    let value: Float

    init(_ value: Float) {
        self.value = value
    }
}

final class RuntimeDoubleBox {
    let value: Double

    init(_ value: Double) {
        self.value = value
    }
}

final class RuntimeCharBox {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }
}

enum RuntimeCallableRefKind {
    case function
    case property
}

struct RuntimeCallableRefMetadata {
    let nameRaw: Int
    let arity: Int
    let kind: RuntimeCallableRefKind
    let isSuspend: Bool
}

final class RuntimeFunctionValueBox {
    let fnPtr: Int
    let closureRaw: Int
    let arity: Int

    init(fnPtr: Int, closureRaw: Int, arity: Int) {
        self.fnPtr = fnPtr
        self.closureRaw = closureRaw
        self.arity = arity
    }
}

// MARK: - Collection Types (STDLIB-001)

/// Runtime box for `listOf(...)` / `mutableListOf(...)`.
/// Stores elements directly or as a lightweight view over another list/array.
final class RuntimeListBox {
    private enum Storage {
        case direct([RuntimeValue])
        case reversedViewOf(RuntimeListBox)
        case arrayViewOf(RuntimeArrayBox)
    }

    private var storage: Storage

    init(elements: [Int]) {
        storage = .direct(elements.map { RuntimeValue(raw: $0) })
    }

    init(values: [RuntimeValue]) {
        storage = .direct(values)
    }

    init(reversedViewOf base: RuntimeListBox) {
        storage = .reversedViewOf(base)
    }

    init(arrayViewOf base: RuntimeArrayBox) {
        storage = .arrayViewOf(base)
    }

    var values: [RuntimeValue] {
        get {
            switch storage {
            case .direct(let values):
                return values
            case .reversedViewOf(let base):
                return Array(base.values.reversed())
            case .arrayViewOf(let base):
                return base.values
            }
        }
        set {
            switch storage {
            case .direct:
                storage = .direct(newValue)
            case .reversedViewOf(let base):
                base.values = Array(newValue.reversed())
            case .arrayViewOf(let base):
                base.values = newValue
            }
        }
    }

    var elements: [Int] {
        get {
            values.map(\.legacyRawValue)
        }
        set {
            values = newValue.map { RuntimeValue(raw: $0) }
        }
    }
}

/// Runtime box for `setOf(...)` / `mutableSetOf(...)`.
/// Stores unique elements in insertion order as runtime values.
final class RuntimeSetBox {
    private var storage: [RuntimeValue]

    var values: [RuntimeValue] {
        get {
            storage
        }
        set {
            storage = newValue
        }
    }

    var elements: [Int] {
        get {
            storage.map(\.legacyRawValue)
        }
        set {
            storage = newValue.map { RuntimeValue(raw: $0) }
        }
    }

    init(elements: [Int]) {
        self.storage = elements.map { RuntimeValue(raw: $0) }
    }

    init(values: [RuntimeValue]) {
        self.storage = values
    }
}

/// Runtime box for `mapOf(...)` / `mutableMapOf(...)`.
/// Stores keys and values as parallel runtime-value arrays.
final class RuntimeMapBox {
    private var keyStorage: [RuntimeValue]
    private var valueStorage: [RuntimeValue]
    let defaultValueFnPtr: Int
    let defaultValueClosureRaw: Int

    var keyValues: [RuntimeValue] {
        get {
            keyStorage
        }
        set {
            keyStorage = newValue
        }
    }

    var entryValues: [RuntimeValue] {
        get {
            valueStorage
        }
        set {
            valueStorage = newValue
        }
    }

    var keys: [Int] {
        get {
            keyStorage.map(\.legacyRawValue)
        }
        set {
            keyStorage = newValue.map { RuntimeValue(raw: $0) }
        }
    }

    var values: [Int] {
        get {
            valueStorage.map(\.legacyRawValue)
        }
        set {
            valueStorage = newValue.map { RuntimeValue(raw: $0) }
        }
    }

    init(keys: [Int], values: [Int], defaultValueFnPtr: Int = 0, defaultValueClosureRaw: Int = 0) {
        self.keyStorage = keys.map { RuntimeValue(raw: $0) }
        self.valueStorage = values.map { RuntimeValue(raw: $0) }
        self.defaultValueFnPtr = defaultValueFnPtr
        self.defaultValueClosureRaw = defaultValueClosureRaw
    }
}

/// Runtime box for `ArrayDeque<T>`.
/// Stores elements in a mutable runtime-value array.
final class RuntimeArrayDequeBox {
    private var storage: [RuntimeValue]

    var values: [RuntimeValue] {
        get {
            storage
        }
        set {
            storage = newValue
        }
    }

    var elements: [Int] {
        get {
            storage.map(\.legacyRawValue)
        }
        set {
            storage = newValue.map { RuntimeValue(raw: $0) }
        }
    }

    init(elements: [Int]) {
        self.storage = elements.map { RuntimeValue(raw: $0) }
    }
}

/// Lazy wrapper for `withIndex()` result. Kotlin returns `IndexingIterable` with
/// default Object.toString() = "kotlin.collections.IndexingIterable@<hex>".
final class RuntimeIndexingIterableBox {
    let listRaw: Int

    init(listRaw: Int) {
        self.listRaw = listRaw
    }
}

/// Iterator for `withIndex()` result. Each call to `next()` yields an
/// `IndexedValue<E>` pair (index, element) represented as `RuntimePairBox`.
final class RuntimeIndexingIteratorBox {
    let values: [RuntimeValue]
    var index: Int

    init(values: [RuntimeValue]) {
        self.values = values
        index = 0
    }
}

/// Iterator box for `List` iteration via `for (x in list)`.
final class RuntimeListIteratorBox {
    let elements: [Int]
    var index: Int

    init(elements: [Int]) {
        self.elements = elements
        index = 0
    }
}

/// Iterator box for `String` iteration via `for (c in str)` (STDLIB-189).
final class RuntimeStringIteratorBox {
    let charRaws: [Int]
    var index: Int

    init(charRaws: [Int]) {
        self.charRaws = charRaws
        index = 0
    }
}

/// Lazy iterable view for `String.asIterable()` (STDLIB-317).
/// Stores the immutable string payload; characters are yielded on demand when
/// the iterable is consumed (e.g. via `iterator()`, `toList()`, or `for-in`).
final class RuntimeStringIterableBox {
    let source: String

    init(source: String) {
        self.source = source
    }
}

/// Iterator box for `Map` iteration via `for (entry in map)`.
final class RuntimeMapIteratorBox {
    let keys: [Int]
    let values: [Int]
    var index: Int

    init(keys: [Int], values: [Int]) {
        self.keys = keys
        self.values = values
        index = 0
    }
}

// MARK: - Sequence Types (STDLIB-003)

/// Represents a lazy operation in a sequence chain.
/// Each step stores its kind (source, map, filter, take) and a function pointer
/// for map/filter transformations. Lazy semantics: no evaluation until terminal.
enum SequenceStepKind {
    case source(elements: [Int])
    case valueSource(values: [RuntimeValue])
    case stringSource(source: String)
    case mapStep(fnPtr: Int, closureRaw: Int)
    case filterStep(fnPtr: Int, closureRaw: Int)
    case filterNotStep(fnPtr: Int, closureRaw: Int)
    case takeStep(count: Int)
    case builder(elements: [Int])
    case generator(seed: Int, fnPtr: Int, closureRaw: Int)
    /// STDLIB-SEQ-002: 1-arg form: `generateSequence { nextFunction() }`.
    /// Calls `nextFunction` (no-arg) repeatedly; each non-null return value is an element.
    case nullableGenerator(fnPtr: Int, closureRaw: Int)
    case dropStep(count: Int)
    case distinctStep
    case distinctByStep(fnPtr: Int, closureRaw: Int)
    case zipStep(otherElements: [Int])
    case takeWhileStep(fnPtr: Int, closureRaw: Int)
    case dropWhileStep(fnPtr: Int, closureRaw: Int)
    case onEachStep(fnPtr: Int, closureRaw: Int)
    case onEachIndexedStep(fnPtr: Int, closureRaw: Int)
    /// STDLIB-HOF-022: Additional lazy transformation steps
    case mapNotNullStep(fnPtr: Int, closureRaw: Int)
    case filterNotNullStep
    case filterIsInstanceStep(typeToken: Int)
    case requireNoNullsStep
    case mapIndexedStep(fnPtr: Int, closureRaw: Int)
    case mapIndexedNotNullStep(fnPtr: Int, closureRaw: Int)
    case filterIndexedStep(fnPtr: Int, closureRaw: Int)
    case withIndexStep
    case flatMapStep(fnPtr: Int, closureRaw: Int)
    case flatMapIndexedStep(fnPtr: Int, closureRaw: Int)
    case chunkedTransformStep(size: Int, fnPtr: Int, closureRaw: Int)
    /// STDLIB-SEQ-019: Random shuffle of the full upstream result. Each full iteration
    /// of the returned sequence re-shuffles (intermediate, stateful; matches Kotlin).
    case shuffledStep(randomRaw: Int?)
    /// STDLIB-563: Lazy continuation-based builder. CPS producers suspend by
    /// returning COROUTINE_SUSPENDED; legacy callbacks keep the thread-backed
    /// producer path.
    case lazyBuilder(coroutine: RuntimeSequenceCoroutine)
}

/// Runtime box for `Sequence<T>`.
/// Stores a chain of lazy steps that are only evaluated on terminal operations.
final class RuntimeSequenceConstrainOnceState {
    var consumed = false
}

final class RuntimeSequenceBox {
    var steps: [SequenceStepKind]
    let constrainOnceState: RuntimeSequenceConstrainOnceState?

    init(steps: [SequenceStepKind], constrainOnceState: RuntimeSequenceConstrainOnceState? = nil) {
        self.steps = steps
        self.constrainOnceState = constrainOnceState
    }
}

/// Runtime box for the `sequence { yield(x) }` builder.
/// Accumulates yielded elements during builder block execution.
/// Used as a fallback when the lazy coroutine path is not available.
final class RuntimeSequenceBuilderBox {
    var elements: [Int] = []
}

// STDLIB-563: Continuation-based lazy sequence coroutine.
//
// Compiler-generated builders use the CPS producer path: each `yield(value)`
// publishes a value, returns COROUTINE_SUSPENDED, and is resumed by the next
// consumer request through the stored continuation. Legacy tests/direct ABI
// callers keep the thread-backed path below for non-CPS raw callbacks.
//
// The coroutine is started lazily on the first call to `materializeAll()`.
//
// Producer protocol (DEBT-CORO-002 / CORO-004):
//   CPS producer (compiler-generated builders):
//     1. First consumer request starts runSuspendEntryLoopWithContinuation().
//     2. On yield(value): queue value, signal consumer, return COROUTINE_SUSPENDED.
//     3. Next consumer request resumes the stored continuation with Unit.
//     4. On completion: set finished flag, signal consumer.
//
//   Legacy producer (direct ABI tests / pre-CPS callbacks):
//     1. Waits on producerGate on a dedicated OS thread.
//     2. Runs builder lambda sequentially.
//     3. On yield(value): queue value, signal consumer, block on producerGate.
//     4. On completion: set finished flag, signal consumer.
//
//   Consumer thread — blocking path (non-coroutine callers):
//     1. Signals producerGate (starts or resumes producer), blocks on consumerGate.
//     2. Reads yielded value or observes finished flag.
//
//   Consumer thread — suspension path (CORO-004 Phase 2, coroutine callers):
//     1. Calls nextElementAsync(callerState:), which signals producerGate and
//        installs a resume continuation in consumerGate instead of blocking.
//     2. Returns COROUTINE_SUSPENDED; the GCD thread is released immediately.
//     3. When the producer yields, the continuation fires and calls
//        callerState.resume(with: element) or callerState.resume(with: doneSentinel).
//
// DEBT-CORO-002 status: compiler-generated producers use CPS and no longer
// allocate a dedicated producer thread. The thread-backed path remains for
// legacy non-CPS callbacks.
//
// CORO-004 Phase 3: CPS-transformed sequence builder lambdas call yield() as a
// real suspend point, so compiler-generated producers no longer need a
// dedicated thread. The legacy thread path remains only for pre-CPS callbacks.
final class RuntimeSequenceCoroutine: @unchecked Sendable {
    /// Legacy builder function pointer or CPS suspend entry point.
    let fnPtr: Int
    let closureRaw: Int
    private let functionID: Int
    private let usesCPSProducer: Bool

    /// Producer suspend gate — signalled by the consumer when it wants the next element.
    private let producerGate = RuntimeCoroutineSyncGate()

    /// Consumer suspend gate — signalled by the producer after yielding or finishing.
    private let consumerGate = RuntimeCoroutineSyncGate()

    /// Guard for mutable state access.
    private let stateLock = NSLock()

    /// Values published by the producer but not consumed yet.
    private var pendingYieldedValues: [Int] = []

    /// Whether the producer has finished (either completed or threw).
    private var finished = false

    /// Whether the coroutine producer has been initialized.
    private var started = false

    /// Whether the CPS suspend-entry loop has been kicked off.
    private var cpsLoopStarted = false

    /// Continuation handle used to resume the CPS builder after yield().
    private var producerContinuationRaw: Int = 0

    /// All elements materialized so far (cache for re-iteration).
    private var materializedElements: [Int] = []

    /// Whether the coroutine has been fully exhausted.
    private var fullyMaterialized = false

    /// Registered handle for the builder proxy — stored here so that future
    /// CPS re-invocations can call invokeBuilderLambda() without recreating it.
    private var builderHandle: Int = 0

    init(fnPtr: Int, closureRaw: Int, functionID: Int = 0, usesCPSProducer: Bool = false) {
        self.fnPtr = fnPtr
        self.closureRaw = closureRaw
        self.functionID = functionID
        self.usesCPSProducer = usesCPSProducer
    }

    /// Called by the producer to yield a value.
    func yieldValue(_ value: Int) -> Int {
        stateLock.lock()
        pendingYieldedValues.append(value)
        stateLock.unlock()

        consumerGate.signal()
        if usesCPSProducer {
            return Int(bitPattern: kk_coroutine_suspended())
        }
        producerGate.wait()
        return 0
    }

    /// Called by the producer when it finishes (normally or via exception).
    func markFinished() {
        stateLock.lock()
        finished = true
        stateLock.unlock()
        consumerGate.signal()
    }

    private func consumePendingValueLocked() -> Int? {
        guard !pendingYieldedValues.isEmpty else {
            return nil
        }
        return pendingYieldedValues.removeFirst()
    }

    /// Consumer side: advance the producer one step and block until it yields or finishes.
    private func awaitProducerYield() {
        requestProducerStep()
        consumerGate.wait()
    }

    /// Non-blocking variant for coroutine callers (CORO-004 Phase 2).
    ///
    /// Signals the producer and installs `callerState` as a resume continuation
    /// in `consumerGate`.  When the producer yields or finishes, the continuation
    /// fires on a GCD thread: it reads the yielded value (or done flag), caches
    /// the element, and resumes `callerState` with either the element value or
    /// `kk_sequence_completed_sentinel()`.  Returns `true` when the caller must
    /// propagate COROUTINE_SUSPENDED; `false` when the result was already
    /// available and the blocking path has completed.
    private func awaitProducerYieldAsync(callerState: RuntimeContinuationState) -> Bool {
        requestProducerStep()
        let coroutine = self
        let didSuspend = consumerGate.wait(resumeContinuation: {
            coroutine.stateLock.lock()
            if let value = coroutine.consumePendingValueLocked() {
                coroutine.materializedElements.append(value)
                coroutine.consumptionIndex += 1
                coroutine.stateLock.unlock()
                callerState.resume(with: value)
            } else if coroutine.finished {
                coroutine.fullyMaterialized = true
                coroutine.stateLock.unlock()
                let doneSentinel = Int(bitPattern:
                    UnsafeMutableRawPointer(
                        Unmanaged.passUnretained(runtimeStorage.sequenceCompletedBox).toOpaque()
                    )
                )
                callerState.resume(with: doneSentinel)
            } else {
                coroutine.stateLock.unlock()
                callerState.resume(with: 0)
            }
        })
        return didSuspend
    }

    /// Invokes the legacy non-CPS builder lambda on its producer thread.
    private func invokeBuilderLambda() {
        var thrown = 0
        let fn = unsafeBitCast(
            fnPtr,
            to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        _ = fn(closureRaw, builderHandle, &thrown)

        if thrown != 0 {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: sequence lambda threw but no outThrown available")
        }

        markFinished()
    }

    /// Result type for `nextElement()`: either a value or end-of-sequence.
    enum NextResult {
        case value(Int)
        case done
    }

    /// Request the next element from the coroutine, one at a time.
    ///
    /// If there are already-materialized elements beyond the current
    /// consumption index, return the cached element. Otherwise, resume the
    /// producer to compute the next value.
    ///
    /// Returns `.done` when the producer has finished and all cached
    /// elements have been consumed.
    private var consumptionIndex: Int = 0

    func nextElement() -> NextResult {
        stateLock.lock()
        if consumptionIndex < materializedElements.count {
            let elem = materializedElements[consumptionIndex]
            consumptionIndex += 1
            stateLock.unlock()
            return .value(elem)
        }
        if let value = consumePendingValueLocked() {
            materializedElements.append(value)
            consumptionIndex += 1
            stateLock.unlock()
            return .value(value)
        }
        if fullyMaterialized {
            stateLock.unlock()
            return .done
        }
        if finished {
            fullyMaterialized = true
            stateLock.unlock()
            return .done
        }
        stateLock.unlock()

        awaitProducerYield()

        stateLock.lock()
        if let value = consumePendingValueLocked() {
            materializedElements.append(value)
            consumptionIndex += 1
            stateLock.unlock()
            return .value(value)
        }
        if finished {
            fullyMaterialized = true
            stateLock.unlock()
            return .done
        }
        stateLock.unlock()
        return .done
    }

    /// Suspension-aware element request for coroutine callers (CORO-004 Phase 2).
    ///
    /// Like `nextElement()` but uses `awaitProducerYieldAsync` so the calling
    /// GCD thread is not held while the producer computes the next element.
    ///
    /// Return convention:
    ///   - `nil`           — the coroutine was suspended; `callerState` will be
    ///                       resumed with the element value or with
    ///                       `kk_sequence_completed_sentinel()` when done.
    ///   - `.value(elem)`  — result was immediately available (cache hit).
    ///   - `.done`         — sequence already fully materialised.
    func nextElementAsync(callerState: RuntimeContinuationState) -> NextResult? {
        stateLock.lock()
        if consumptionIndex < materializedElements.count {
            let elem = materializedElements[consumptionIndex]
            consumptionIndex += 1
            stateLock.unlock()
            return .value(elem)
        }
        if let value = consumePendingValueLocked() {
            materializedElements.append(value)
            consumptionIndex += 1
            stateLock.unlock()
            return .value(value)
        }
        if fullyMaterialized {
            stateLock.unlock()
            return .done
        }
        if finished {
            fullyMaterialized = true
            stateLock.unlock()
            return .done
        }
        stateLock.unlock()

        let didSuspend = awaitProducerYieldAsync(callerState: callerState)
        if didSuspend {
            return nil
        }
        // Signal arrived before the continuation could be installed — fall
        // through to read the result synchronously (same as nextElement()).
        stateLock.lock()
        if let value = consumePendingValueLocked() {
            materializedElements.append(value)
            consumptionIndex += 1
            stateLock.unlock()
            return .value(value)
        }
        if finished {
            fullyMaterialized = true
            stateLock.unlock()
            return .done
        }
        stateLock.unlock()
        return .done
    }

    /// Reset the consumption index so re-iteration over the same coroutine
    /// replays from the beginning (using cached elements first, then resuming
    /// the producer if needed).
    func resetIteration() {
        stateLock.lock()
        consumptionIndex = 0
        stateLock.unlock()
    }

    /// Materialize all elements from the coroutine and return them.
    func materializeAll() -> [Int] {
        stateLock.lock()
        if fullyMaterialized {
            let elems = materializedElements
            stateLock.unlock()
            return elems
        }
        stateLock.unlock()

        while true {
            stateLock.lock()
            if let value = consumePendingValueLocked() {
                materializedElements.append(value)
                stateLock.unlock()
                continue
            }
            if finished {
                fullyMaterialized = true
                let elems = materializedElements
                stateLock.unlock()
                return elems
            }
            stateLock.unlock()

            awaitProducerYield()

            stateLock.lock()
            if let value = consumePendingValueLocked() {
                materializedElements.append(value)
                stateLock.unlock()
                continue
            }
            if finished {
                fullyMaterialized = true
                let elems = materializedElements
                stateLock.unlock()
                return elems
            }
            stateLock.unlock()
        }
    }

    private func requestProducerStep() {
        ensureStarted()
        if !usesCPSProducer {
            producerGate.signal()
            return
        }

        stateLock.lock()
        if finished {
            stateLock.unlock()
            return
        }
        let isFirstStep = !cpsLoopStarted
        cpsLoopStarted = true
        let continuation = producerContinuationRaw
        stateLock.unlock()

        if isFirstStep {
            let coroutine = self
            _ = runSuspendEntryLoopWithContinuation(
                entryPointRaw: fnPtr,
                continuation: continuation,
                onCompletion: { _, thrown in
                    if thrown != 0 {
                        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: sequence lambda threw but no outThrown available")
                    }
                    coroutine.markFinished()
                }
            )
            return
        }

        guard let state = runtimeContinuationState(from: continuation) else {
            markFinished()
            return
        }
        if let doubleResume = state.resume(with: 0) {
            state.deliverDoubleResumeException(doubleResume)
        }
    }

    /// Initialize the producer. Compiler-generated CPS builders do not start a
    /// thread; legacy non-CPS callbacks keep the old dedicated-thread fallback.
    private func ensureStarted() {
        stateLock.lock()
        guard !started else {
            stateLock.unlock()
            return
        }
        started = true
        stateLock.unlock()

        let coroutine = self
        // builderHandle is written before the thread starts, so no lock needed:
        // Thread.detachNewThread provides the happens-before edge the reader relies on.
        coroutine.builderHandle = registerRuntimeObject(
            RuntimeSequenceCoroutineBuilderProxy(coroutine: coroutine)
        )

        if usesCPSProducer {
            let continuation = kk_coroutine_continuation_new(functionID)
            _ = kk_coroutine_launcher_arg_set(continuation, 0, Int64(closureRaw))
            _ = kk_coroutine_launcher_arg_set(continuation, 1, Int64(coroutine.builderHandle))
            stateLock.lock()
            producerContinuationRaw = continuation
            stateLock.unlock()
            return
        }

        Thread.detachNewThread {
            // Wait for the first consumer request before running the lambda.
            coroutine.producerGate.wait()
            coroutine.invokeBuilderLambda()
        }
    }
}

/// Proxy object passed to the builder lambda as the "builder" handle.
/// When `kk_sequence_builder_yield` receives this handle, it delegates to the
/// coroutine's `yieldValue()`, returning COROUTINE_SUSPENDED for CPS producers
/// or blocking only for legacy non-CPS producers.
final class RuntimeSequenceCoroutineBuilderProxy {
    let coroutine: RuntimeSequenceCoroutine

    init(coroutine: RuntimeSequenceCoroutine) {
        self.coroutine = coroutine
    }
}

// Runtime box for the `iterator { yield(x) }` builder (STDLIB-331/564).
//
// Implements lazy iteration using a cooperative producer-consumer pattern.
// Compiler-generated builders use the CPS producer path, where yield() returns
// COROUTINE_SUSPENDED and the consumer resumes the stored continuation. Legacy
// direct ABI callers keep the thread-backed path for non-CPS callbacks.
//
// Protocol:
//   1. `kk_iterator_builder_build_coro(entryPointRaw, functionID, closureRaw)`
//      creates the CPS box for compiler-generated builders.
//   2. First `hasNext` / `next` call starts the suspend-entry loop.
//   3. Producer yield(value) transitions to .hasValue, signals consumer, and
//      returns COROUTINE_SUSPENDED. The next consumer request resumes it.
//   4. On completion: transitions to .done, signals consumer.
//
// DEBT-CORO-002: compiler-generated producers no longer occupy a dedicated
// thread. Legacy `kk_iterator_builder_build(fnPtr)` callbacks keep the old
// dedicated-thread fallback.
//
// CORO-004 Phase 2 (consumer suspension, IN PROGRESS):
//   probeHasNextAsync(callerState:) wires consumerGate to a resume continuation
//   so the calling GCD thread is released immediately.  C entry points
//   kk_iterator_builder_hasNext_coro / kk_iterator_builder_next_coro expose
//   this for future coroutine-aware compiler output.  Existing entry points
//   (kk_iterator_builder_hasNext / _next) remain unchanged.
//
// CORO-004 Phase 3: CPS-transformed iterator builder lambdas call yield() as a
// real suspend point, so compiler-generated producers no longer need a
// dedicated thread. The legacy thread path remains only for pre-CPS callbacks.
final class RuntimeIteratorBuilderBox: @unchecked Sendable {
    private let fnPtr: Int
    private let closureRaw: Int
    private let functionID: Int
    private let usesCPSProducer: Bool
    private var builderHandle: Int = 0

    /// Producer suspend gate — signalled by the consumer (`hasNext` / `next`).
    private let producerGate = RuntimeCoroutineSyncGate()
    /// Consumer suspend gate — signalled by the producer (`yield` or completion).
    private let consumerGate = RuntimeCoroutineSyncGate()
    private let stateLock = NSLock()
    private var started = false
    private var cpsLoopStarted = false
    private var producerContinuationRaw: Int = 0

    /// The most recently yielded value, valid when `state == .hasValue`.
    private(set) var yieldedValue: Int = 0
    /// Current state of the iterator.
    private(set) var state: IteratorState = .initial

    enum IteratorState {
        /// Producer has not yet been advanced.
        case initial
        /// Producer yielded a value; `yieldedValue` is valid.
        case hasValue
        /// Producer finished (lambda returned).
        case done
    }

    init(fnPtr: Int, closureRaw: Int = 0, functionID: Int = 0, usesCPSProducer: Bool = false) {
        self.fnPtr = fnPtr
        self.closureRaw = closureRaw
        self.functionID = functionID
        self.usesCPSProducer = usesCPSProducer
    }

    func bindRegisteredHandle(_ handle: Int) {
        builderHandle = handle
    }

    func yieldValue(_ value: Int) -> Int {
        stateLock.lock()
        yieldedValue = value
        state = .hasValue
        stateLock.unlock()

        consumerGate.signal()
        if usesCPSProducer {
            return Int(bitPattern: kk_coroutine_suspended())
        }
        producerGate.wait()
        return 0
    }

    func probeHasNext() -> Bool {
        stateLock.lock()
        let current = state
        stateLock.unlock()

        switch current {
        case .hasValue:
            return true
        case .done:
            return false
        case .initial:
            awaitProducerYield()
            stateLock.lock()
            defer { stateLock.unlock() }
            return state == .hasValue
        }
    }

    func consumeNext() -> Int {
        stateLock.lock()
        let current = state
        stateLock.unlock()

        if current == .initial {
            awaitProducerYield()
        }

        stateLock.lock()
        guard state == .hasValue else {
            stateLock.unlock()
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: NoSuchElementException: Iterator has no more elements.")
        }
        let value = yieldedValue
        state = .initial
        stateLock.unlock()
        return value
    }

    private func awaitProducerYield() {
        requestProducerStep()
        consumerGate.wait()
    }

    /// Suspension-aware hasNext for coroutine callers (CORO-004 Phase 2).
    ///
    /// When state is already known (`.hasValue` / `.done`), returns 1 / 0
    /// synchronously without touching any gate.  When state is `.initial`,
    /// signals the producer and installs `callerState` as a resume continuation
    /// in `consumerGate`.  On producer yield the continuation fires on a GCD
    /// thread: it reads the new state and calls `callerState.resume(with: 1/0)`.
    ///
    /// Returns 1 (hasNext), 0 (done), or `Int(bitPattern: kk_coroutine_suspended())`
    /// when the caller must propagate COROUTINE_SUSPENDED up the call stack.
    /// The `kk_iterator_builder_hasNext_coro` C entry point wraps this method.
    func probeHasNextAsync(callerState: RuntimeContinuationState) -> Int {
        stateLock.lock()
        let current = state
        stateLock.unlock()

        switch current {
        case .hasValue:
            return 1
        case .done:
            return 0
        case .initial:
            let box = self
            requestProducerStep()
            let didSuspend = consumerGate.wait(resumeContinuation: {
                box.stateLock.lock()
                let hasValue = box.state == .hasValue
                box.stateLock.unlock()
                callerState.resume(with: hasValue ? 1 : 0)
            })
            if didSuspend {
                return Int(bitPattern: kk_coroutine_suspended())
            }
            // Signal was pending before the continuation could be installed —
            // the producer already yielded, read the result directly.
            stateLock.lock()
            defer { stateLock.unlock() }
            return state == .hasValue ? 1 : 0
        }
    }

    /// Invokes the legacy non-CPS builder lambda on its producer thread.
    private func invokeBuilderLambda() {
        var thrown = 0
        _ = runtimeInvokeClosureThunk(
            fnPtr: fnPtr,
            closureRaw: builderHandle,
            outThrown: &thrown
        )
        if thrown != 0 {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: iterator lambda threw an exception")
        }

        stateLock.lock()
        state = .done
        stateLock.unlock()
        consumerGate.signal()
    }

    private func requestProducerStep() {
        ensureStarted()
        if !usesCPSProducer {
            producerGate.signal()
            return
        }

        stateLock.lock()
        if state == .done {
            stateLock.unlock()
            return
        }
        let isFirstStep = !cpsLoopStarted
        cpsLoopStarted = true
        let continuation = producerContinuationRaw
        stateLock.unlock()

        if isFirstStep {
            let box = self
            _ = runSuspendEntryLoopWithContinuation(
                entryPointRaw: fnPtr,
                continuation: continuation,
                onCompletion: { _, thrown in
                    if thrown != 0 {
                        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: iterator lambda threw an exception")
                    }
                    box.stateLock.lock()
                    box.state = .done
                    box.stateLock.unlock()
                    box.consumerGate.signal()
                }
            )
            return
        }

        guard let state = runtimeContinuationState(from: continuation) else {
            stateLock.lock()
            self.state = .done
            stateLock.unlock()
            consumerGate.signal()
            return
        }
        if let doubleResume = state.resume(with: 0) {
            state.deliverDoubleResumeException(doubleResume)
        }
    }

    /// Initialize the producer. Compiler-generated CPS builders do not start a
    /// thread; legacy non-CPS callbacks keep the old dedicated-thread fallback.
    private func ensureStarted() {
        stateLock.lock()
        guard !started else {
            stateLock.unlock()
            return
        }
        started = true
        stateLock.unlock()

        if usesCPSProducer {
            let continuation = kk_coroutine_continuation_new(functionID)
            _ = kk_coroutine_launcher_arg_set(continuation, 0, Int64(builderHandle))
            _ = kk_coroutine_launcher_arg_set(continuation, 1, Int64(closureRaw))
            stateLock.lock()
            producerContinuationRaw = continuation
            stateLock.unlock()
            return
        }

        let box = self
        Thread.detachNewThread {
            // Wait for the first consumer signal before running the lambda.
            box.producerGate.wait()
            box.invokeBuilderLambda()
        }
    }
}

/// Runtime box for `Grouping<T, K>` returned by `groupingBy`.
/// Stores the source elements and key selector function pointer/closure.
final class RuntimeGroupingBox {
    let sourceElements: [Int]
    let keyFnPtr: Int
    let keyClosureRaw: Int

    init(sourceElements: [Int], keyFnPtr: Int, keyClosureRaw: Int) {
        self.sourceElements = sourceElements
        self.keyFnPtr = keyFnPtr
        self.keyClosureRaw = keyClosureRaw
    }
}

// MARK: - Stdlib Delegate Types (P5-80)

/// Thread-safety mode for `lazy` delegate.
enum LazyThreadSafetyMode: Int {
    case synchronized = 1
    case none = 0
    case publication = 2
}

/// Runtime box for `kotlin.lazy {}` delegate.
/// Holds an initializer function pointer and caches the computed value.
final class RuntimeLazyBox {
    private enum CachedState {
        case uninitialized
        case initialized(Int)
    }

    private let initializerFnPtr: Int
    private var cachedState: CachedState = .uninitialized
    private let mode: LazyThreadSafetyMode
    private let lock = NSLock()

    init(initializerFnPtr: Int, mode: LazyThreadSafetyMode) {
        self.initializerFnPtr = initializerFnPtr
        self.mode = mode
    }

    init(initializedValue: Int) {
        initializerFnPtr = 0
        cachedState = .initialized(initializedValue)
        mode = .none
    }

    func getValue() -> Int {
        switch mode {
        case .synchronized:
            lock.lock()
            defer { lock.unlock() }
            return getValueLocked()
        case .publication:
            return getValuePublication()
        case .none:
            return getValueUnsafe()
        }
    }

    private func getValueLocked() -> Int {
        switch cachedState {
        case .initialized(let value):
            return value
        case .uninitialized:
            let value = evaluateInitializer()
            cachedState = .initialized(value)
            return value
        }
    }

    private func getValueUnsafe() -> Int {
        if let cached = cachedValue() {
            return cached
        }
        let value = evaluateInitializer()
        cachedState = .initialized(value)
        return value
    }

    private func getValuePublication() -> Int {
        if let cached = cachedValue() {
            return cached
        }

        let value = evaluateInitializer()
        if compareAndSetCachedValue(expected: .uninitialized, update: .initialized(value)) {
            return value
        }
        return cachedValue() ?? value
    }

    private func cachedValue() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        switch cachedState {
        case .initialized(let value):
            return value
        case .uninitialized:
            return nil
        }
    }

    private func compareAndSetCachedValue(expected: CachedState, update: CachedState) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard cachedStateMatches(expected) else {
            return false
        }
        cachedState = update
        return true
    }

    private func cachedStateMatches(_ expected: CachedState) -> Bool {
        switch (cachedState, expected) {
        case (.uninitialized, .uninitialized):
            return true
        case (.initialized(let current), .initialized(let expected)):
            return current == expected
        default:
            return false
        }
    }

    private func evaluateInitializer() -> Int {
        let fnPtr = unsafeBitCast(initializerFnPtr, to: KKThunkEntryPoint.self)
        var thrown = 0
        let value = fnPtr(&thrown)
        if thrown != 0 {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: lazy initializer threw")
        }
        return value
    }

    var isInitialized: Bool {
        switch mode {
        case .synchronized:
            lock.lock()
            defer { lock.unlock() }
            return cachedStateIsInitialized()
        case .publication:
            return cachedValue() != nil
        case .none:
            return cachedStateIsInitialized()
        }
    }

    private func cachedStateIsInitialized() -> Bool {
        switch cachedState {
        case .initialized:
            return true
        case .uninitialized:
            return false
        }
    }
}

/// Runtime box for `Delegates.observable(initialValue) { ... }` delegate.
/// Stores a mutable value and invokes a callback after each set.
final class RuntimeObservableBox {
    var currentValue: Int
    let callbackFnPtr: Int

    init(initialValue: Int, callbackFnPtr: Int) {
        currentValue = initialValue
        self.callbackFnPtr = callbackFnPtr
    }
}

/// Runtime box for `Delegates.vetoable(initialValue) { ... }` delegate.
/// Stores a mutable value and invokes a callback before each set;
/// the callback returns non-zero to accept the change, zero to veto.
final class RuntimeVetoableBox {
    var currentValue: Int
    let callbackFnPtr: Int

    init(initialValue: Int, callbackFnPtr: Int) {
        currentValue = initialValue
        self.callbackFnPtr = callbackFnPtr
    }
}

/// Runtime box for `Delegates.notNull<T>()` delegate.
/// Throws `IllegalStateException` if accessed before being assigned.
final class RuntimeNotNullBox {
    var currentValue: Int?
}

/// Runtime reflection metadata record stored in the global registry.
/// Populated from the binary metadata blob emitted by `RuntimeReflectionMetadataEmitter`.
/// Each entry corresponds to a type or declaration that can be queried via `KClass` at runtime.
struct RuntimeKClassMetadataEntry {
    let qualifiedName: String
    let simpleName: String
    let supertypeName: String?
    let isDataClass: Bool
    let isSealedClass: Bool
    let isValueClass: Bool
    let isInterface: Bool
    let isObject: Bool
    let isEnumClass: Bool
    let isAnnotationClass: Bool
    let isAbstract: Bool
    let fieldCount: Int
    let memberCount: Int
    let constructorCount: Int
    // STDLIB-REFLECT-060: additional KClass basic reflection fields
    let isFinal: Bool
    let isOpen: Bool
    let visibility: String
    let typeParameterCount: Int
    // STDLIB-REFLECT-067: additional type-kind introspection flags
    var isInner: Bool = false
    var isCompanion: Bool = false
    var isFunInterface: Bool = false
    /// Runtime annotations attached to this type (STDLIB-REFLECT-065).
    var annotations: [RuntimeAnnotationRecord] = []
}

/// Runtime representation of an annotation attached to a declaration (STDLIB-REFLECT-065).
struct RuntimeAnnotationRecord {
    /// Fully-qualified name of the annotation class (e.g. "MyLabel").
    let annotationFQName: String
    /// Argument values serialized as strings (e.g. ["hello"]).
    let arguments: [String]
}

/// Global registry mapping type tokens to runtime metadata entries.
/// Populated during module initialization via `kk_kclass_register_metadata`.
final class RuntimeKClassMetadataRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Int: RuntimeKClassMetadataEntry] = [:]

    func register(typeToken: Int, entry: RuntimeKClassMetadataEntry) {
        lock.lock()
        defer { lock.unlock() }
        entries[typeToken] = entry
    }

    func lookup(typeToken: Int) -> RuntimeKClassMetadataEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[typeToken]
    }

    func appendAnnotations(typeToken: Int, annotations: [RuntimeAnnotationRecord]) {
        lock.lock()
        defer { lock.unlock() }
        if var entry = entries[typeToken] {
            entry.annotations.append(contentsOf: annotations)
            entries[typeToken] = entry
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}

let runtimeKClassMetadataRegistry = RuntimeKClassMetadataRegistry()

/// Global registry mapping a `KClass` raw handle to constructor reflection handles.
final class RuntimeKConstructorRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var constructorsByClassRaw: [Int: [Int]] = [:]

    func register(classRaw: Int, constructorRaw: Int) {
        guard classRaw != 0, classRaw != runtimeNullSentinelInt,
              constructorRaw != 0, constructorRaw != runtimeNullSentinelInt
        else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        constructorsByClassRaw[classRaw, default: []].append(constructorRaw)
    }

    func constructors(for classRaw: Int) -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return constructorsByClassRaw[classRaw] ?? []
    }

    func primaryConstructor(for classRaw: Int) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        let constructors = constructorsByClassRaw[classRaw] ?? []
        for constructorRaw in constructors {
            guard let ptr = UnsafeMutableRawPointer(bitPattern: constructorRaw),
                  let box = tryCast(ptr, to: RuntimeKConstructorBox.self),
                  box.isPrimary
            else {
                continue
            }
            return constructorRaw
        }
        return constructors.first
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        constructorsByClassRaw.removeAll()
    }
}

let runtimeKConstructorRegistry = RuntimeKConstructorRegistry()

/// Global registry mapping a `KClass` raw handle to its member callable handles.
/// Members are registered during module initialization via `kk_kclass_register_member`.
/// Each entry is a KFunction or KPropertyStub raw handle (STDLIB-REFLECT-ABI-002).
final class RuntimeKMemberRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var membersByClassRaw: [Int: [Int]] = [:]

    func register(classRaw: Int, memberRaw: Int) {
        guard classRaw != 0, classRaw != runtimeNullSentinelInt,
              isCallableMemberHandle(memberRaw)
        else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        membersByClassRaw[classRaw, default: []].append(memberRaw)
    }

    func members(for classRaw: Int) -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return membersByClassRaw[classRaw] ?? []
    }

    func functions(for classRaw: Int) -> [Int] {
        members(for: classRaw, matching: RuntimeKFunctionBox.self)
    }

    func properties(for classRaw: Int) -> [Int] {
        members(for: classRaw, matching: RuntimeKPropertyStub.self)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        membersByClassRaw.removeAll()
    }

    private func members<T: AnyObject>(for classRaw: Int, matching type: T.Type) -> [Int] {
        members(for: classRaw).filter { isRuntimeObject($0, of: type) }
    }

    private func isCallableMemberHandle(_ raw: Int) -> Bool {
        isRuntimeObject(raw, of: RuntimeKFunctionBox.self)
            || isRuntimeObject(raw, of: RuntimeKPropertyStub.self)
    }

    private func isRuntimeObject<T: AnyObject>(_ raw: Int, of type: T.Type) -> Bool {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
            return false
        }
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        guard isObjectPointer else {
            return false
        }
        return tryCast(ptr, to: type) != nil
    }
}

let runtimeKMemberRegistry = RuntimeKMemberRegistry()

/// Runtime box for `KClass<T>` metadata references produced by `T::class`.
/// Stores the type token and an optional name-hint pointer so that
/// `.simpleName` / `.qualifiedName` can be resolved at runtime.
/// When metadata has been registered via `kk_kclass_register_metadata`,
/// additional properties (isData, isSealed, qualifiedName, etc.) are
/// available through the global metadata registry.
final class RuntimeKClassBox {
    let typeToken: Int
    let nameHint: Int

    init(typeToken: Int, nameHint: Int) {
        self.typeToken = typeToken
        self.nameHint = nameHint
    }

    /// Looks up the associated metadata entry from the global registry.
    var metadata: RuntimeKClassMetadataEntry? {
        runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)
    }
}

// MARK: - kotlin.reflect.KType (REFL-005)

/// Runtime box for `kotlin.reflect.KType`.
/// Represents a Kotlin type at runtime, as returned by `typeOf<T>()`.
final class RuntimeKTypeBox {
    /// The classifier — typically a `KClass` raw handle.
    let classifierRaw: Int
    /// Type arguments as `RuntimeKTypeProjectionBox` raw handles.
    let argumentRaws: [Int]
    /// Whether the type is marked nullable (`T?`).
    let isMarkedNullable: Bool

    init(classifierRaw: Int, argumentRaws: [Int], isMarkedNullable: Bool) {
        self.classifierRaw = classifierRaw
        self.argumentRaws = argumentRaws
        self.isMarkedNullable = isMarkedNullable
    }
}

/// Runtime representation of `kotlin.reflect.KVariance`.
/// Matches the Kotlin enum ordinals: IN=0, OUT=1, INVARIANT=2.
enum RuntimeKVariance: Int {
    case `in` = 0
    case out = 1
    case invariant = 2
}

/// Runtime box for `kotlin.reflect.KTypeProjection`.
/// Represents a type argument with optional variance.
final class RuntimeKTypeProjectionBox {
    /// The projected type as a `RuntimeKTypeBox` raw handle, or 0 for star projection.
    let typeRaw: Int
    /// The variance (nil for star projection).
    let variance: RuntimeKVariance?

    init(typeRaw: Int, variance: RuntimeKVariance?) {
        self.typeRaw = typeRaw
        self.variance = variance
    }
}

/// Runtime box for `kotlin.reflect.KParameter`.
/// Represents a single parameter of a KFunction or KConstructor.
final class RuntimeKParameterBox {
    /// Parameter index (0-based).
    let index: Int
    /// Parameter name as a KKString raw handle (0 if unnamed).
    let nameRaw: Int
    /// Parameter type as a KKString raw handle describing the type name.
    let typeRaw: Int
    /// Whether this parameter is optional (has a default value).
    let isOptional: Bool
    /// Parameter kind: 0 = INSTANCE, 1 = EXTENSION_RECEIVER, 2 = VALUE.
    let kind: Int

    init(index: Int, nameRaw: Int, typeRaw: Int, isOptional: Bool = false, kind: Int = 2) {
        self.index = index
        self.nameRaw = nameRaw
        self.typeRaw = typeRaw
        self.isOptional = isOptional
        self.kind = kind
    }
}

/// Runtime box for `kotlin.reflect.KFunction<T>`.
/// Represents a constructor or function member with full reflection metadata (STDLIB-REFLECT-063).
final class RuntimeKFunctionBox {
    /// Interned KKString raw pointer for the function name.
    let nameRaw: Int
    /// Number of value parameters (not counting the dispatch receiver).
    let arity: Int
    /// Interned KKString raw pointer for the return type descriptor, or 0 if unknown.
    let returnTypeRaw: Int
    /// Whether this function is declared `suspend`.
    let isSuspend: Bool
    /// Raw function pointer used by `call()` dispatch.  Zero when not callable.
    let fnPtr: Int
    /// Closure environment for the callable reference (zero for top-level functions).
    let closureRaw: Int
    /// KParameter raw handles for all parameters (including receiver if any).
    let parameterRaws: [Int]
    /// Function type string as a KKString raw handle (e.g. "(Int, Int) -> Int").
    let typeStringRaw: Int

    init(
        nameRaw: Int,
        arity: Int,
        returnTypeRaw: Int = 0,
        isSuspend: Bool = false,
        fnPtr: Int = 0,
        closureRaw: Int = 0,
        parameterRaws: [Int] = [],
        typeStringRaw: Int = 0
    ) {
        self.nameRaw = nameRaw
        self.arity = arity
        self.returnTypeRaw = returnTypeRaw
        self.isSuspend = isSuspend
        self.fnPtr = fnPtr
        self.closureRaw = closureRaw
        self.parameterRaws = parameterRaws
        self.typeStringRaw = typeStringRaw
    }
}

// MARK: - kotlin.reflect.KConstructor (STDLIB-REFLECT-064)

/// Runtime box for `kotlin.reflect.KFunction<T>` representing a constructor.
/// Extends the basic KFunction box with constructor-specific metadata:
/// isPrimary, visibility, and the declaring class reference.
final class RuntimeKConstructorBox {
    let nameRaw: Int
    let arity: Int
    let returnTypeRaw: Int
    /// C function pointer for the underlying constructor implementation (0 if unavailable).
    let fnPtr: Int
    /// Whether this is the primary constructor of the class.
    let isPrimary: Bool
    /// Visibility as a KKString raw handle (e.g. "PUBLIC", "PRIVATE", "PROTECTED", "INTERNAL").
    let visibilityRaw: Int
    /// The declaring KClass raw handle (0 if unknown).
    let declaringClassRaw: Int
    /// Parameter names as KKString raw handles.
    let parameterNameRaws: [Int]

    init(
        nameRaw: Int,
        arity: Int,
        returnTypeRaw: Int = 0,
        fnPtr: Int = 0,
        isPrimary: Bool = false,
        visibilityRaw: Int = 0,
        declaringClassRaw: Int = 0,
        parameterNameRaws: [Int] = []
    ) {
        self.nameRaw = nameRaw
        self.arity = arity
        self.returnTypeRaw = returnTypeRaw
        self.fnPtr = fnPtr
        self.isPrimary = isPrimary
        self.visibilityRaw = visibilityRaw
        self.declaringClassRaw = declaringClassRaw
        self.parameterNameRaws = parameterNameRaws
    }
}

// MARK: - Annotation Reflection (STDLIB-REFLECT-065)

/// Runtime box for a Kotlin annotation instance.
/// Represents a single annotation applied to a declaration, with its class
/// name and argument values accessible at runtime.
final class RuntimeAnnotationBox {
    /// Fully-qualified name of the annotation class.
    let annotationFQName: String
    /// Argument values serialized as strings.
    let arguments: [String]
    /// Raw KClass handle for the annotation class (0 if not available).
    let annotationClassRaw: Int

    init(annotationFQName: String, arguments: [String], annotationClassRaw: Int = 0) {
        self.annotationFQName = annotationFQName
        self.arguments = arguments
        self.annotationClassRaw = annotationClassRaw
    }
}

// MARK: - BufferedReader (STDLIB-567)

/// Runtime box for `java.io.BufferedReader` returned by `File.bufferedReader()`.
/// Wraps a streaming file reader, supporting `readLine()` and `readLines()`.
final class RuntimeBufferedReaderBox {
    private var fileHandle: FileHandle?
    private var pendingData: Data
    private var closed: Bool
    private var reachedEOF: Bool
    private let chunkSize: Int

    init(fileHandle: FileHandle, chunkSize: Int = 4096) {
        self.fileHandle = fileHandle
        self.pendingData = Data()
        self.closed = false
        self.reachedEOF = false
        self.chunkSize = max(1, chunkSize)
    }

    /// Creates a `BufferedReader` backed by an already-loaded `Data` buffer.
    /// Used by `InputStream.bufferedReader()` (STDLIB-IO-FN-007) where the
    /// underlying `InputStream` is in-memory (`ByteArrayInputStream`) — no
    /// `FileHandle` is involved, so the buffer is treated as already at EOF.
    init(data: Data, chunkSize: Int = 4096) {
        self.fileHandle = nil
        self.pendingData = data
        self.closed = false
        self.reachedEOF = true
        self.chunkSize = max(1, chunkSize)
    }

    /// Returns the next line, or `nil` when all lines have been consumed.
    func readLine() -> String? {
        guard !closed else { return nil }

        while true {
            if let (lineLength, terminatorLength) = locateLineTerminator() {
                let lineData = pendingData.prefix(lineLength)
                pendingData.removeFirst(lineLength + terminatorLength)
                return String(decoding: lineData, as: UTF8.self)
            }

            if reachedEOF {
                guard !pendingData.isEmpty else { return nil }
                let line = String(decoding: pendingData, as: UTF8.self)
                pendingData.removeAll(keepingCapacity: false)
                return line
            }

            if !readNextChunk() {
                reachedEOF = true
            }
        }
    }

    /// Returns all remaining lines as an array.
    func readLines() -> [String] {
        guard !closed else { return [] }
        var remaining: [String] = []
        while let line = readLine() {
            remaining.append(line)
        }
        return remaining
    }

    /// Reads the remaining content of the reader into a single `String`
    /// (STDLIB-IO-FN-033). Mirrors `kotlin.io.readText()`: drains any buffered
    /// bytes and then reads the underlying stream to EOF, decoding the
    /// accumulated bytes as UTF-8. Returns an empty string if the reader is
    /// already closed or has nothing left to read. Does NOT close the reader,
    /// matching Kotlin's `Reader.readText()` contract (callers wrap in `use`
    /// to release the underlying file handle).
    func readText() -> String {
        guard !closed else { return "" }
        var data = pendingData
        pendingData.removeAll(keepingCapacity: false)
        while !reachedEOF {
            if !readNextChunk() {
                reachedEOF = true
            } else {
                data.append(pendingData)
                pendingData.removeAll(keepingCapacity: false)
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Reads a single character, returning its Unicode scalar value, or -1 on EOF.
    func read() -> Int {
        guard !closed else { return -1 }

        while true {
            if !pendingData.isEmpty {
                let byte = pendingData.removeFirst()
                // Fast path: ASCII byte
                if byte & 0x80 == 0 {
                    return Int(byte)
                }
                // Multi-byte UTF-8: put back and decode
                var codePoint: UInt32 = 0
                let totalBytes: Int
                if byte & 0xE0 == 0xC0 {
                    totalBytes = 2
                    codePoint = UInt32(byte & 0x1F)
                } else if byte & 0xF0 == 0xE0 {
                    totalBytes = 3
                    codePoint = UInt32(byte & 0x0F)
                } else if byte & 0xF8 == 0xF0 {
                    totalBytes = 4
                    codePoint = UInt32(byte & 0x07)
                } else {
                    // Continuation byte or invalid — return as-is
                    return Int(byte)
                }
                // Ensure we have enough continuation bytes
                while pendingData.count < totalBytes - 1 {
                    if reachedEOF { return Int(byte) }
                    if !readNextChunk() { reachedEOF = true }
                }
                if pendingData.count < totalBytes - 1 { return Int(byte) }
                for _ in 1 ..< totalBytes {
                    let cont = pendingData.removeFirst()
                    codePoint = (codePoint << 6) | UInt32(cont & 0x3F)
                }
                return Int(codePoint)
            }

            if reachedEOF { return -1 }
            if !readNextChunk() { reachedEOF = true }
        }
    }

    /// Returns true if data is available to be read without blocking (buffered bytes exist or not EOF).
    func ready() -> Bool {
        guard !closed else { return false }
        return !pendingData.isEmpty || !reachedEOF
    }

    func close() {
        guard !closed else { return }
        try? fileHandle?.close()
        fileHandle = nil
        pendingData.removeAll(keepingCapacity: false)
        closed = true
    }

    deinit {
        close()
    }

    private func readNextChunk() -> Bool {
        guard let fileHandle else { return false }
        guard let chunk = try? fileHandle.read(upToCount: chunkSize), !chunk.isEmpty else {
            return false
        }
        pendingData.append(chunk)
        return true
    }

    private func locateLineTerminator() -> (lineLength: Int, terminatorLength: Int)? {
        var index = pendingData.startIndex
        while index < pendingData.endIndex {
            let byte = pendingData[index]
            if byte == 0x0A {
                return (pendingData.distance(from: pendingData.startIndex, to: index), 1)
            }
            if byte == 0x0D {
                let nextIndex = pendingData.index(after: index)
                if nextIndex < pendingData.endIndex {
                    let lineLength = pendingData.distance(from: pendingData.startIndex, to: index)
                    return (lineLength, pendingData[nextIndex] == 0x0A ? 2 : 1)
                }
                if reachedEOF {
                    return (pendingData.distance(from: pendingData.startIndex, to: index), 1)
                }
                return nil
            }
            index = pendingData.index(after: index)
        }
        return nil
    }
}

// MARK: - InputStream / OutputStream (STDLIB-IO-092)

final class RuntimeInputStreamBox {
    private let data: Data
    private var offset: Int
    private var closed: Bool
    private var markOffset: Int
    private var markLimit: Int

    init(data: Data) {
        self.data = data
        self.offset = 0
        self.closed = false
        self.markOffset = 0
        self.markLimit = 0
    }

    func readByte() -> Int {
        guard !closed else { return -1 }
        guard offset < data.count else { return -1 }
        defer { offset += 1 }
        return Int(data[offset])
    }

    func available() -> Int {
        guard !closed else { return 0 }
        return max(0, data.count - offset)
    }

    func skip(_ count: Int) -> Int {
        guard !closed else { return 0 }
        let bounded = max(0, min(count, available()))
        offset += bounded
        return bounded
    }

    func read(into list: RuntimeListBox) -> Int {
        guard !closed else { return -1 }
        let writableCount = min(list.elements.count, available())
        guard writableCount > 0 else { return -1 }
        var newElements = list.elements
        for index in 0 ..< writableCount {
            newElements[index] = Int(Int8(bitPattern: data[offset + index]))
        }
        list.elements = newElements
        offset += writableCount
        return writableCount
    }

    /// Reads all remaining bytes from the stream as a list of signed Int values
    /// in the range [-128, 127] (matching `kotlin.ByteArray` element semantics).
    /// Advances the read cursor to the end of the underlying buffer.  When the
    /// stream is closed or already at EOF, returns an empty list.
    /// Used by `InputStream.readBytes()` (STDLIB-IO-FN-029).
    func readAllBytes() -> [Int] {
        guard !closed else { return [] }
        let remaining = max(0, data.count - offset)
        guard remaining > 0 else { return [] }
        var elements: [Int] = []
        elements.reserveCapacity(remaining)
        for index in 0 ..< remaining {
            elements.append(Int(Int8(bitPattern: data[offset + index])))
        }
        offset += remaining
        return elements
    }

    func mark(readLimit: Int) {
        // FileInputStream does not support mark/reset; this is a no-op.
    }

    func markSupported() -> Bool { false }

    /// Attempts a reset.  Returns `false` when mark/reset is not supported
    /// (matching JVM FileInputStream behaviour — callers must raise IOException).
    func reset() -> Bool { false }

    func close() {
        closed = true
    }

    /// Drain remaining bytes (after the current `offset`) so they can be
    /// handed to a `BufferedReader` constructed by
    /// `InputStream.bufferedReader()` (STDLIB-IO-FN-007). Mirrors what the
    /// JVM does: wrapping an `InputStream` in an `InputStreamReader` reads
    /// from the *current* position onwards. Advances the offset to the end
    /// because callers should treat the stream as fully consumed.
    func drainRemaining() -> Data {
        guard !closed else { return Data() }
        let remaining = data.suffix(from: data.startIndex.advanced(by: offset))
        offset = data.count
        return Data(remaining)
    }
}

/// Runtime box for `java.io.SequenceInputStream` — chains two InputStreams.
final class RuntimeSequenceInputStreamBox {
    private var first: RuntimeInputStreamBox?
    private var second: RuntimeInputStreamBox?
    private var closed: Bool

    init(first: RuntimeInputStreamBox, second: RuntimeInputStreamBox) {
        self.first = first
        self.second = second
        self.closed = false
    }

    func readByte() -> Int {
        guard !closed else { return -1 }
        if let s1 = first {
            let b = s1.readByte()
            if b != -1 { return b }
            // first stream exhausted — move to second
            s1.close()
            first = nil
        }
        return second?.readByte() ?? -1
    }

    func available() -> Int {
        guard !closed else { return 0 }
        return first?.available() ?? 0
    }

    /// Reads all remaining bytes across both chained streams.  Drains `first`
    /// fully, then drains `second`.  Used by `InputStream.readBytes()`
    /// (STDLIB-IO-FN-029) when the receiver is a SequenceInputStream.
    func readAllBytes() -> [Int] {
        guard !closed else { return [] }
        var elements: [Int] = []
        if let s1 = first {
            elements.append(contentsOf: s1.readAllBytes())
            s1.close()
            first = nil
        }
        if let s2 = second {
            elements.append(contentsOf: s2.readAllBytes())
        }
        return elements
    }

    func close() {
        guard !closed else { return }
        first?.close()
        second?.close()
        first = nil
        second = nil
        closed = true
    }
}

// MARK: - RuntimeOutputStreamSink (STDLIB-IO-ENC-FN-002)

/// Pluggable back-end for `RuntimeOutputStreamBox`.  Concrete implementations
/// may wrap a real `FileHandle` (normal file-backed streams) or provide a
/// transforming layer such as the Base64-encoding stream.
protocol RuntimeOutputStreamSink: AnyObject {
    func write(_ data: Data) throws
    func flush() throws
    func close()
}

/// Concrete `RuntimeOutputStreamSink` backed by a `FileHandle`.
final class RuntimeFileHandleOutputStreamSink: RuntimeOutputStreamSink {
    private let fileHandle: FileHandle
    private var closed: Bool

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
        self.closed = false
    }

    func write(_ data: Data) throws {
        guard !closed else { return }
        try fileHandle.write(contentsOf: data)
    }

    func flush() throws {
        guard !closed else { return }
        try fileHandle.synchronize()
    }

    func close() {
        guard !closed else { return }
        try? fileHandle.close()
        closed = true
    }

    var underlyingFileHandle: FileHandle { fileHandle }
}

final class RuntimeOutputStreamBox {
    private let sink: RuntimeOutputStreamSink

    init(fileHandle: FileHandle) {
        self.sink = RuntimeFileHandleOutputStreamSink(fileHandle: fileHandle)
    }

    init(sink: RuntimeOutputStreamSink) {
        self.sink = sink
    }

    func writeByte(_ value: Int) throws {
        let byte = UInt8(truncatingIfNeeded: value)
        try sink.write(Data([byte]))
    }

    func writeBytes(_ values: [Int]) throws {
        let bytes = values.map { UInt8(truncatingIfNeeded: $0) }
        try sink.write(Data(bytes))
    }

    func write(_ data: Data) throws {
        try sink.write(data)
    }

    func flush() throws {
        try sink.flush()
    }

    func close() {
        sink.close()
    }

    /// Returns true if the underlying stream has been closed.
    /// Note: after close() the sink handles the closed state internally;
    /// writes on a closed sink are no-ops.
    var isClosed: Bool { false }

    var underlyingFileHandle: FileHandle? {
        (sink as? RuntimeFileHandleOutputStreamSink)?.underlyingFileHandle
    }

    /// Creates a `RuntimeBufferedWriterBox` wrapping the underlying file handle.
    /// Returns `nil` when the sink is not file-handle backed (e.g. an encoding
    /// stream).  STDLIB-IO-FN-009.
    func makeBufferedWriter(encoding: String.Encoding) -> RuntimeBufferedWriterBox? {
        guard let fileHandle = underlyingFileHandle else {
            return nil
        }
        let writer = RuntimeBufferedWriterBox(fileHandle: fileHandle, encoding: encoding)
        return writer
    }
}

// MARK: - BufferedWriter (STDLIB-IO-091/093)

/// Runtime box for `java.io.BufferedWriter` returned by `File.bufferedWriter()`.
/// Wraps a streaming file writer, supporting `write()`, `newLine()`, `flush()`, and `close()`.
final class RuntimeBufferedWriterBox {
    private let fileHandle: FileHandle
    private var buffer: Data
    private let bufferSize: Int
    private let encoding: String.Encoding
    private var closed: Bool

    init(fileHandle: FileHandle, bufferSize: Int = 8192, encoding: String.Encoding = .utf8) {
        self.fileHandle = fileHandle
        self.buffer = Data()
        self.bufferSize = max(1, bufferSize)
        self.encoding = encoding
        self.closed = false
    }

    /// Writes a string to the buffer, flushing when full.
    func write(_ text: String) throws {
        guard !closed else { return }
        guard let data = text.data(using: encoding) ?? text.data(using: .utf8) else { return }
        buffer.append(data)
        if buffer.count >= bufferSize {
            try flushBuffer()
        }
    }

    /// Writes a system line separator.
    func newLine() throws {
        try write("\n")
    }

    /// Flushes buffered data to the file.
    func flush() throws {
        guard !closed else { return }
        try flushBuffer()
        try fileHandle.synchronize()
    }

    func close() {
        guard !closed else { return }
        try? flushBuffer()
        try? fileHandle.close()
        closed = true
    }

    deinit {
        close()
    }

    private func flushBuffer() throws {
        guard !buffer.isEmpty else { return }
        try fileHandle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}

// MARK: - RuntimeChildReferenceProviding conformances (ABI-004)
//
// These conformances enable the recursive BFS freeze in kk_freeze_object to
// traverse all reachable object references when freezing an object graph.
// Only types that store `Int` child handles need to conform.

extension RuntimeArrayBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] { values.compactMap(\.childReferenceRawValue) }
}

extension RuntimePairBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] {
        [firstValue, secondValue].compactMap(\.childReferenceRawValue)
    }
}

extension RuntimeTripleBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] { [first, second, third] }
}

extension RuntimeListBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] { values.compactMap(\.childReferenceRawValue) }
}

extension RuntimeSetBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] { values.compactMap(\.childReferenceRawValue) }
}

extension RuntimeMapBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] {
        keyValues.compactMap(\.childReferenceRawValue)
            + entryValues.compactMap(\.childReferenceRawValue)
    }
}

extension RuntimeArrayDequeBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] { values.compactMap(\.childReferenceRawValue) }
}
