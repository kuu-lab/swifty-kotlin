import Foundation

private struct RuntimeThrowableHierarchyCache {
    let typeIDs: [Int64]
    let isBaseThrowable: Bool
}

class RuntimeThrowableBox {
    let message: String?
    /// Handle of the Kotlin `String` argument handed to the constructor, when
    /// one was supplied. `__kk_throwable_message` returns it verbatim so
    /// `throwable.message === arg` holds like on the JVM; for synthesized
    /// messages the getter lazily materializes one stable box here.
    var messageRaw: Int
    var cause: Int
    /// JVM parity for `Throwable.initCause`: the cause slot starts out
    /// "uninitialized" (the JVM `this` sentinel) and only the first cause write
    /// — a cause-taking constructor or `initCause` — marks it initialized, so
    /// a later `initCause` must fail with `IllegalStateException`. A
    /// constructor-provided `null` cause still counts as initialized.
    var causeInitialized: Bool
    var stackTraceAddresses: [Int]
    var stackTraceFrames: [RuntimeLogicalStackTraceFrame]
    var stackTraceElementsRaw: Int = 0
    var suppressionEnabled = true
    var writableStackTrace = true
    /// Stores raw Int pointers to other RuntimeThrowableBox instances.
    var suppressed: [Int] = []
    private var cachedExceptionHierarchy: RuntimeThrowableHierarchyCache?
    private let exceptionHierarchyCacheLock = NSLock()

    var exceptionFQName: String {
        "kotlin.Throwable"
    }

    var exceptionHierarchyFQNames: [String] {
        [exceptionFQName]
    }

    private func exceptionHierarchyCache() -> RuntimeThrowableHierarchyCache {
        exceptionHierarchyCacheLock.lock()
        defer { exceptionHierarchyCacheLock.unlock() }
        if let cachedExceptionHierarchy {
            return cachedExceptionHierarchy
        }
        let fqNames = exceptionHierarchyFQNames
        let cache = RuntimeThrowableHierarchyCache(
            typeIDs: fqNames.map { runtimeStableNominalTypeID(fqName: $0) },
            isBaseThrowable: fqNames == ["kotlin.Throwable"]
        )
        cachedExceptionHierarchy = cache
        return cache
    }

    /// Stable nominal IDs for `exceptionHierarchyFQNames`, computed once per box.
    var exceptionHierarchyTypeIDs: [Int64] {
        exceptionHierarchyCache().typeIDs
    }

    /// Whether the hierarchy is exactly `[kotlin.Throwable]` (the untyped fallback).
    var exceptionHierarchyIsBaseThrowable: Bool {
        exceptionHierarchyCache().isBaseThrowable
    }

    var renderedMessage: String {
        message ?? "Throwable"
    }

    init(message: String?, cause: Int = 0, messageRaw: Int = 0) {
        self.message = message
        self.cause = cause
        // A non-zero cause can only come from a cause-taking constructor, so it
        // is already initialized; cause-taking `@_cdecl` factories mark the
        // explicit-null case via `runtimeMarkThrowableCauseInitialized`.
        self.causeInitialized = cause != 0
        self.messageRaw = messageRaw == runtimeNullSentinelInt ? 0 : messageRaw
        self.stackTraceAddresses = runtimeCurrentStackTraceAddresses()
        self.stackTraceFrames = runtimeCurrentLogicalStackTrace()
    }
}

func runtimeRenderedExceptionMessage(_ name: String, _ message: String?) -> String {
    guard let message else { return name }
    return "\(name): \(message)"
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
        runtimeRenderedExceptionMessage("UninitializedPropertyAccessException", message)
    }
}

/// Distinct type used to identify CancellationException at runtime.
/// The runtime checks `is RuntimeCancellationBox` to distinguish cancellation from
/// regular throwables (CORO-002 / spec.md J17).
///
/// Non-final so `RuntimeTimeoutCancellationBox` can subclass it: every existing
/// `is RuntimeCancellationBox` / `tryCast(_:to: RuntimeCancellationBox.self)` site
/// (notably `kk_is_cancellation_exception`, which backs the
/// `catch (e: CancellationException)` fast path) then accepts the timeout flavour
/// without further wiring, matching kotlinx.coroutines' subclass relationship.
class RuntimeCancellationBox: RuntimeThrowableBox {
    // Job-generated wrappers identify cancellation without confusing a user-
    // thrown CancellationException (even one with the same underlying cause).
    weak var cancellationJob: RuntimeJobHandle?

    override var exceptionFQName: String {
        "kotlin.CancellationException"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlin.CancellationException",
            "kotlin.coroutines.cancellation.CancellationException",
            "kotlinx.coroutines.CancellationException",
            "CancellationException",
            "kotlin.IllegalStateException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        message ?? "CancellationException"
    }

    override init(message: String?, cause: Int = 0, messageRaw: Int = 0) {
        super.init(message: message, cause: cause, messageRaw: messageRaw)
    }
}

/// A *subclass* of `RuntimeCancellationBox`, mirroring kotlinx.coroutines, so
/// `catch (e: CancellationException)` catches a timeout while
/// `catch (e: TimeoutCancellationException)` stays narrow: the latter is matched
/// nominally by `kk_op_is` against `exceptionHierarchyFQNames`, which a plain
/// `job.cancel()` cancellation does not carry.
final class RuntimeTimeoutCancellationBox: RuntimeCancellationBox {
    override var exceptionFQName: String {
        "kotlinx.coroutines.TimeoutCancellationException"
    }

    override var exceptionHierarchyFQNames: [String] {
        // The unqualified spelling is required because a `catch` clause resolves
        // its type by short name, so the Sema symbol's fqName may be either the
        // packaged or the bare form (see `resolveCatchClauseParameterType`).
        [
            "kotlinx.coroutines.TimeoutCancellationException",
            "TimeoutCancellationException",
        ] + super.exceptionHierarchyFQNames
    }

    override var renderedMessage: String {
        message ?? "TimeoutCancellationException"
    }
}
