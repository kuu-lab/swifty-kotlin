package kotlinx.coroutines.internal

import kotlin.coroutines.Continuation
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CoroutineDispatcher

// KUU-3910: upstream kotlinx-coroutines declares these as `internal` in
// `kotlinx.coroutines.internal`; bundled coroutines exposes them publicly
// (like ScopeCoroutine in this package) because library sources such as
// ktor-utils `StackTraceRecover.kt` import them with
// `@Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")`.

/**
 * Upstream recovers a coroutine stack trace on JVM in debug mode and returns a
 * rewritten copy of [exception]. Stack recovery is a no-op here, so the
 * throwable is returned unchanged — the same result upstream produces on
 * non-JVM targets and on a JVM without the debug agent.
 */
public fun <E : Throwable> recoverStackTrace(exception: E, continuation: Continuation<*>): E = exception

/** Single-argument upstream overload used at non-suspending await points. */
public fun <E : Throwable> recoverStackTrace(exception: E): E = exception

/** Upstream rethrows [exception] after stack recovery; identity + rethrow here. */
public suspend inline fun recoverAndThrow(exception: Throwable): Nothing {
    throw exception
}

/**
 * The opposite of [recoverStackTrace]. Upstream guarantees
 * `unwrap(recoverStackTrace(e)) === e`; with recovery being a no-op, unwrap is
 * the identity as well.
 */
public fun <E : Throwable> unwrap(exception: E): E = exception

/**
 * Whether resuming a coroutine suspended in [context] must go through a
 * dispatch. Upstream exposes the dispatcher's decision as the
 * `CoroutineDispatcher.isDispatchNeeded` member; this top-level form answers
 * for a whole context the same way kotlinx's resume paths do: with no
 * interceptor there is nothing to dispatch through, a dispatcher answers for
 * itself, and any other interceptor is treated conservatively as needing
 * interception.
 */
public fun isDispatchNeeded(context: CoroutineContext): Boolean =
    when (val interceptor = context[ContinuationInterceptor]) {
        null -> false
        is CoroutineDispatcher -> interceptor.isDispatchNeeded(context)
        else -> true
    }
