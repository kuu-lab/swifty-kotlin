import Foundation

class RuntimeThrowableBox {
    let message: String?
    var cause: Int
    let stackTraceAddresses: [Int]
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
        message ?? "Throwable"
    }

    init(message: String?, cause: Int = 0) {
        self.message = message
        self.cause = cause
        self.stackTraceAddresses = runtimeCurrentStackTraceAddresses()
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

    override init(message: String?, cause: Int = 0) {
        super.init(message: message, cause: cause)
    }
}

/// `kotlinx.coroutines.TimeoutCancellationException` -- thrown when a
/// `withTimeout` deadline expires (CORO-002 / spec.md J17).
///
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
