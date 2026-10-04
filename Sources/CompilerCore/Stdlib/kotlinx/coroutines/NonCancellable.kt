package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext

// Upstream shape: `object NonCancellable : AbstractCoroutineContextElement(Key), Job`.
// The `Job` conformance is grafted in the compiler's synthetic registry
// (HeaderHelpers+SyntheticCoroutineRegistry) so `val job: Job = NonCancellable`
// and `withContext(NonCancellable)` type-check, while bare `NonCancellable`
// references evaluate to the runtime's never-cancelled job handle via the
// `kk_non_cancellable_instance` external link name.
//
// The handle is a raw runtime job pointer, not a heap object, so members of
// this object cannot be member `val`s (a member-`val` access lowers to a
// field-array read — "Array reference is null") or member `fun`s (the
// receiver materialization hits the same field-read path for the object's
// first declared member). The `Job` surface is therefore inherited instead:
// `isActive`/`isCompleted`/`isCancelled` resolve to `kk_job_*` on the
// never-cancelled job (always active / never completed / never cancelled),
// `cancel(...)` resolves to `kk_job_cancel` — which guards the shared
// `runtimeNonCancellableJob` singleton so cancelling it is a no-op — and
// `join()` resolves to `kk_job_join`, which suspends forever on the
// never-completing job, matching upstream `join() = awaitCancellation()`.
// `invokeOnCompletion`/`cancelAndJoin`/`cancelAndJoin(cause)` ride the `Job`
// extensions in Job.kt the same way. Known limitation: the inherited
// `Element.key` member virtual-dispatches on the raw handle, so reading
// `NonCancellable.key` traps; use the `Key` extension property below
// (context-key lookups still resolve statically).
internal object NonCancellableKey : CoroutineContext.Key<NonCancellable>

public object NonCancellable : AbstractCoroutineContextElement(NonCancellableKey) {
    override fun toString(): String = "NonCancellable"
}

/** The context key for `NonCancellable`, mirroring upstream `Key`. */
public val NonCancellable.Key: CoroutineContext.Key<NonCancellable>
    get() = NonCancellableKey

/** Upstream `NonCancellable.parent` is always `null`. */
public val NonCancellable.parent: Job?
    get() = null

/** Upstream `NonCancellable.children` is always empty. */
public val NonCancellable.children: Sequence<Job>
    get() = emptySequence()
