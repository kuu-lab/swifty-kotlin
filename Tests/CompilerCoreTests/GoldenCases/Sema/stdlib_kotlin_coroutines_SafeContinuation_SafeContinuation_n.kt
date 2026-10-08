@file:Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")
import kotlin.coroutines.*
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED

// KUU-1597 Sema owner: pin SafeContinuation constructors, context, and result APIs; state-machine behavior stays in Scripts/diff_cases/stdlib_kotlin_coroutines_SafeContinuation_SafeContinuation_n.kt.
fun main() {
    val completion: Continuation<Int> = Continuation(EmptyCoroutineContext) {}
    val withValue: SafeContinuation<Int> = SafeContinuation(completion, 42)
    val initialValue: Any? = withValue.getOrThrow()
    val withNull: SafeContinuation<Int?> = SafeContinuation(
        Continuation<Int?>(EmptyCoroutineContext) {},
        null,
    )
    val nullableValue: Any? = withNull.getOrThrow()

    val immediate: SafeContinuation<Int> = SafeContinuation(completion)
    val context: CoroutineContext = immediate.context
    immediate.resumeWith(Result.success(42))
    val resumedValue: Any? = immediate.getOrThrow()

    val suspended: SafeContinuation<Int> = SafeContinuation(completion)
    val suspensionMarker: Any = COROUTINE_SUSPENDED
    val suspendedValue: Any? = suspended.getOrThrow()
    suspended.resumeWith(Result.success(9))
    val completedValue: Any? = suspended.getOrThrow()
}
