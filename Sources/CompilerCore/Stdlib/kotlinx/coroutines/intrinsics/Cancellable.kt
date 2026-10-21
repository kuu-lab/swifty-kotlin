package kotlinx.coroutines.intrinsics

import kotlin.coroutines.Continuation
import kotlin.internal.KsSymbolName
import kotlinx.coroutines.InternalCoroutinesApi

/**
 * Starts this coroutine in a cancellable way: it runs in `completion`'s context
 * and reports its normal value or exception to `completion`. When the context's
 * ContinuationInterceptor produces a dispatched continuation the start itself
 * is cancellable -- a Job that is no longer active once the resume reaches the
 * coroutine (inline or on the dispatcher queue) completes `completion` with the
 * job's CancellationException without running the block.
 *
 * The bridge creates the unintercepted coroutine, applies `intercepted()`,
 * and performs kotlinx's MODE_CANCELLABLE first resume, including upstream's
 * `runSafely` failure delivery, in the runtime entry point.
 */
@KsSymbolName("__kk_start_coroutine_cancellable")
@InternalCoroutinesApi
@SinceKotlin("1.3")
public external fun <T> (suspend () -> T).startCoroutineCancellable(completion: Continuation<T>)
