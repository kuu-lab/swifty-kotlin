package kotlinx.coroutines

import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext

public class DispatchedCoroutine<T>(
    context: CoroutineContext,
    uCont: Continuation<T>
) : ScopedCoroutine<T>(context, uCont)
