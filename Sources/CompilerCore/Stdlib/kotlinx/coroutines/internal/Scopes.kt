package kotlinx.coroutines.internal

import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.ScopedCoroutine

public open class ScopeCoroutine<T>(
    context: CoroutineContext,
    uCont: Continuation<T>
) : ScopedCoroutine<T>(context, uCont)
