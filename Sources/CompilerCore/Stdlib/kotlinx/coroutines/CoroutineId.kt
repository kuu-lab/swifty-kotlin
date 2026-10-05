package kotlinx.coroutines

import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext

// `CoroutineId` context element from kotlinx-coroutines CoroutineId.kt.
// Debuggers and tracing use it to name a coroutine; the runtime context set is
// closed (resolveToCoroutineContext), so for now it is an ordinary
// `AbstractCoroutineContextElement` usable through `ctx[CoroutineId]`.
//
@ExperimentalCoroutinesApi
public class CoroutineId(id: Long) : AbstractCoroutineContextElement(CoroutineId.Key) {
    public companion object Key : CoroutineContext.Key<CoroutineId>

    public val id: Long = id

    override fun toString(): String = "CoroutineId($id)"
}
