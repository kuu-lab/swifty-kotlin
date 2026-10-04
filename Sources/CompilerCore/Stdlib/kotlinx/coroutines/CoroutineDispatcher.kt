package kotlinx.coroutines

import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext

public abstract class CoroutineDispatcher : CoroutineContext.Element, ContinuationInterceptor {
    public companion object Key : CoroutineContext.Key<CoroutineDispatcher>
    public override val key: CoroutineContext.Key<*> get() = Key
}
