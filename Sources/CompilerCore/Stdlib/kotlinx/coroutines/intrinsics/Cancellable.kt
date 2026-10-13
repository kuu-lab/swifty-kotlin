package kotlinx.coroutines.intrinsics

import kotlin.coroutines.Continuation

/**
 * Compatibility stub for code that imports kotlinx.coroutines' cancellable start helper.
 * The bundled Native target does not provide cancellable dispatch at this layer.
 */
public fun <T> (suspend () -> T).startCoroutineCancellable(completion: Continuation<T>): Unit {}
