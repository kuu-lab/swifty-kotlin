package kotlinx.coroutines

import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.__isNativeDispatcher
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_job_is_runtime")
internal external fun __kkJobIsRuntime(element: CoroutineContext.Element): Boolean

// Native handles have no Kotlin key getter slot. Source elements must still
// invoke their actual override, including custom dispatcher and Job classes.
internal fun CoroutineContext.Element.__kkCoroutineElementKey(): CoroutineContext.Key<*> {
    if (__kkJobIsRuntime(this)) return Job.Key
    if (__isNativeDispatcher(this)) return ContinuationInterceptor.Key
    return this.key
}
